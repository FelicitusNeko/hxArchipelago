package ap;

import ap.Definitions;
import ap.PacketTypes;
import haxe.Int64;
import haxe.Json;
import haxe.Log;
import haxe.Timer;
import haxe.exceptions.NotImplementedException;
import helder.Set;
import hx.ws.Types.MessageType;
import hx.ws.WebSocket;
import sys.thread.Mutex;

using StringTools;

class Client {
	private var _uri:String;
	private var _game:String;
	private var _uuid:String;
	private var _ws:WebSocket;
	private var _state:State = State.DISCONNECTED;

	private var _hOnSocketConnected:Void->Void = null;
	private var _hOnSocketDisconnected:Void->Void = null;
	private var _hOnSlotConnected:Dynamic->Void = null;
	private var _hOnSlotDisconnected:Void->Void = null;
	private var _hOnSlotRefused:List<String>->Void = null;
	private var _hOnRoomInfo:Void->Void = null;
	private var _hOnItemsReceived:List<NetworkItem>->Void = null;
	private var _hOnLocationInfo:List<NetworkItem>->Void = null;
	private var _hOnDataPackageChanged:Dynamic->Void = null;
	private var _hOnPrint:String->Void = null;
	private var _hOnPrintJson:(Array<JSONMessagePart>) -> Void = null;
	private var _hOnBounced:Dynamic->Void = null;
	private var _hOnLocationChecked:List<Int64>->Void = null;

	private var _lastSocketConnect:Float;
	private var _socketReconnectInterval:Float = 1.5;
	private var _checkQueue:Set<Int64>;
	private var _scoutQueue:Set<Int64>;
	private var _clientStatus:ClientStatus = ClientStatus.UNKNOWN;
	private var _seed:String;
	private var _slot:String;
	private var _team:Int = -1;
	private var _slotnr:Int = -1;
	private var _players:List<NetworkPlayer>;
	private var _locations:Map<Int64, String>;
	private var _items:Map<Int64, String>;
	private var _dataPackageValid:Bool = false;
	private var _dataPackage:DataPackageObject;
	private var _serverConnectTime:Float;
	private var _localConnectTime:Float;

	private var _msgQueue:List<String>;
	private var _msgMutex:Mutex;

	public var state(get, never):State;
	public var seed(get, never):String;
	public var slot(get, never):String;
	public var player_number(get, never):Int;
	public var is_data_package_valid(get, never):Bool;
	public var server_time(get, never):Float;

	// [private] std::chrono::steady_clock::time_point _localConnectTime;

	public function new(uuid:String, game:String, uri:String = "ws://localhost:38281") {
		_players = new List<NetworkPlayer>();
		_locations = new Map<Int64, String>();
		_items = new Map<Int64, String>();
		_checkQueue = new Set<Int64>();
		_scoutQueue = new Set<Int64>();
		_msgQueue = new List<String>();
		_msgMutex = new Mutex();

		if (uri.length > 0) {
			var p = uri.indexOf("://");
			if (p < 0) {
				_uri = "ws://" + uri;
				p = 2;
			} else
				_uri = uri;

			var pColon = _uri.indexOf(":", p + 3);
			var pSlash = _uri.indexOf("/", p + 3);
			if (pColon < 0 || (pSlash >= 0 && pColon > pSlash)) {
				var tmp = _uri.substr(0, pSlash) + ":38281";
				if (pSlash >= 0)
					tmp += _uri.substr(pSlash);
				_uri = tmp;
			}
		}

		_uuid = uuid;
		_game = game;
		_dataPackage = {version: 1, games: new Map<String, GameData>()};
		connect_socket();
	}

	public function set_socket_connected_handler(f:Void->Void) {
		_hOnSocketConnected = f;
	}

	public function set_socket_disconnected_handler(f:Void->Void) {
		_hOnSocketDisconnected = f;
	}

	public function set_slot_connected_handler(f:Dynamic->Void) {
		_hOnSlotConnected = f;
	}

	public function set_slot_refused_handler(f:List<String>->Void) {
		_hOnSlotRefused = f;
	}

	public function set_slot_disconnected_handler(f:Void->Void) {
		_hOnSlotDisconnected = f;
	}

	public function set_room_info_handler(f:Void->Void) {
		_hOnRoomInfo = f;
	}

	public function set_items_received_handler(f:List<NetworkItem>->Void) {
		_hOnItemsReceived = f;
	}

	public function set_location_info_handler(f:List<NetworkItem>->Void) {
		_hOnLocationInfo = f;
	}

	public function set_data_package_changed_handler(f:Dynamic->Void) {
		_hOnDataPackageChanged = f;
	}

	public function set_print_handler(f:String->Void) {
		_hOnPrint = f;
	}

	public function set_print_json_handler(f:(Array<JSONMessagePart>) -> Void) {
		_hOnPrintJson = f;
	}

	public function set_bounced_handler(f:Dynamic->Void) {
		_hOnBounced = f;
	}

	public function set_location_checked_handler(f:List<Int64>->Void) {
		_hOnLocationChecked = f;
	}

	public function set_data_package(data:Dynamic) {
		if (!_dataPackageValid && data.games) {
			_dataPackage = data;
			for (game => gamedata in _dataPackage.games) {
				_dataPackage.games[game] = gamedata;
				for (itemName => itemId in gamedata.item_name_to_id)
					_items[itemId] = itemName;
				for (locationName => locationId in gamedata.location_name_to_id)
					_locations[locationId] = locationName;
			}
		}
	}

	public function get_player_alias(slot:Int):String {
		if (slot == 0)
			return "Server";
		for (player in _players)
			if (player.team == _team && player.slot == slot)
				return player.alias;
		return "Unknown";
	}

	public function get_location_name(code:Int64):String {
		if (_locations.exists(code))
			return _locations.get(code);
		return "Unknown";
	}

	public function get_item_name(code:Int64):String {
		if (_items.exists(code))
			return _items.get(code);
		return "Unknown";
	}

	public function render_json(msg:Array<JSONMessagePart>, fmt:RenderFormat = RenderFormat.TEXT) {
		if (fmt == RenderFormat.HTML)
			throw new NotImplementedException("ap.Client.render_json(..., HTML) not yet implemented [upstream]");
		else {
			// TODO: this is a stub
			return "NYI";
		}
	}

	private inline function InternalSend(packet:Dynamic):Bool {
		debug("> " + packet.cmd + ": " + Json.stringify(packet));
		_ws.send(Json.stringify(packet));
		return true;
	}

	public function LocationChecks(locations:List<Int64>):Bool {
		if (_state == State.SLOT_CONNECTED) {
			InternalSend({
				cmd: "LocationChecks",
				locations: locations
			});
		} else
			for (i in locations)
				_checkQueue.add(i);
		// TODO: [upstream] this needs to be sent at some point
		return true;
	}

	public function LocationScouts(locations:List<Int64>):Bool {
		if (_state == State.SLOT_CONNECTED) {
			InternalSend({
				cmd: "LocationScouts",
				locations: locations
			});
		} else
			for (i in locations)
				_checkQueue.add(i);
		// TODO: [upstream] this needs to be sent at some point
		return true;
	}

	public function StatusUpdate(status:ClientStatus):Bool {
		if (_state == State.SLOT_CONNECTED) {
			return InternalSend({
				cmd: "StatusUpdate",
				status: status
			});
		}
		_clientStatus = status;
		return false;
	}

	public function ConnectSlot(name:String, password:String, items_handling:Int, ?tags:List<String>, ?ver:Version):Bool {
		if (tags == null)
			tags = new List<String>();
		if (ver == null)
			ver = {
				major: 0,
				minor: 3,
				build: 1
			};

		if (_state < State.SOCKET_CONNECTED)
			return false;
		_slot = name;
		debug("Connecting slot...");
		return InternalSend({
			cmd: "Connect",
			game: _game,
			uuid: _uuid,
			name: name,
			password: password,
			version: ver,
			items_handling: items_handling,
			tags: tags
		});
	}

	public function ConnectUpdate(?items_handling:Int, ?tags:List<String>):Bool {
		if (items_handling == null && tags == null)
			return false;
		var packet:Dynamic = {
			cmd: "ConnectUpdate"
		};
		if (items_handling != null)
			packet.items_handling = items_handling;
		if (tags != null)
			packet.tags = tags;

		return InternalSend(packet);
	}

	public function Sync():Bool {
		if (_state < State.SLOT_CONNECTED)
			return false;
		return InternalSend({
			cmd: "Sync"
		});
	}

	public function GetDataPackage(exclude:List<String>):Bool {
		if (_state < State.SLOT_CONNECTED)
			return false;
		return InternalSend({
			cmd: "GetDataPackage",
			exclusions: exclude
		});
	}

	public function Bounce(data:Dynamic, games:List<String>, slots:List<Int>, tags:List<String>):Bool {
		if (_state < State.ROOM_INFO)
			return false;
		var packet:Dynamic = {
			cmd: "Bounce",
			data: data
		};

		if (games != null)
			packet.games = games;
		if (slots != null)
			packet.slots = slots;
		if (tags != null)
			packet.tags = tags;

		return InternalSend(packet);
	}

	public function Say(text:String):Bool {
		if (_state < State.ROOM_INFO)
			return false;
		return InternalSend({
			cmd: "Say",
			text: text
		});
	}

	public function get_state():State {
		return _state;
	}

	public function get_seed():String {
		return _seed;
	}

	public function get_slot():String {
		return _slot;
	}

	public function get_player_number():Int {
		return _slotnr;
	}

	public function get_is_data_package_valid():Bool {
		return _dataPackageValid;
	}

	public function get_server_time():Float {
		return _serverConnectTime + (Timer.stamp() - _localConnectTime);
	}

	public function poll() {
		if (_ws != null && _state == State.DISCONNECTED) {
			_ws.close();
			_ws = null;
		}
		if (_ws != null)
			process_queue();
		if (_state < State.SOCKET_CONNECTED) {
			var t = Sys.time();
			if (t - _lastSocketConnect > _socketReconnectInterval) {
				if (_state != State.DISCONNECTED)
					log("Connect timed out. Retrying.");
				else
					log("Reconnecting to server");
				connect_socket();
			}
		}
	}

	public function process_queue() {
		_msgMutex.acquire();
		if (_msgQueue.length > 0)
			try {
				for (msg in _msgQueue) {
					var packet:List<Packet> = Json.parse(msg);
					for (command in packet) {
						switch (command.cmd) {
							case "RoomInfo":
								{
									cast(command, RoomInfoPacket);
									_localConnectTime = Timer.stamp();
									_serverConnectTime = command.time;
									_seed = command.seed_name;
									if (_state < State.ROOM_INFO)
										_state = State.ROOM_INFO;
									if (_hOnRoomInfo != null)
										_hOnRoomInfo();

									_dataPackageValid = true;
									var exclude:List<String> = new List<String>();
									for (game => ver in command.datapackage_versions) {
										try {
											if (ver < 1) {
												_dataPackageValid = false;
												continue;
											}
											if (_dataPackage.games[game] == null) {
												_dataPackageValid = false;
												continue;
											}
											if (_dataPackage.games[game].version != ver) {
												_dataPackageValid = false;
												continue;
											}
											exclude.add(game);
										} catch (e) {
											trace(e.message);
											_dataPackageValid = false;
										}
									}
									if (!_dataPackageValid)
										GetDataPackage(exclude);
									else
										debug("DataPackage up to date");
								}

							case "ConnectionRefused":{
								var refusedPacket:ConnectionRefusedPacket = command;
								if (_hOnSlotRefused != null)
									_hOnSlotRefused(refusedPacket.errors);
							}

							case "Connected":
								_state = State.SLOT_CONNECTED;
								_team = command.team;
								_slotnr = command.slot;
								_players.clear();
								for (player in command.players)
									_players.add({
										team: player.team,
										slot: player.slot,
										alias: player.alias,
										name: player.name
									});
								if (_hOnSlotConnected != null)
									_hOnSlotConnected(command.slot_data);
								// TODO: [upstream] store checked/missing locations
								if (_hOnLocationChecked != null)
									_hOnLocationChecked(command.checked_locations);

							case "ReceivedItems":
								{
									var items:List<NetworkItem> = new List<NetworkItem>();
									var index:Int = command.index;
									for (item in command.items)
										items.add({
											item: item.item,
											location: item.location,
											player: item.player,
											flags: item.flags,
											index: index++
										});
									if (_hOnItemsReceived != null)
										_hOnItemsReceived(items);
								}

							case "LocationInfo":
								{
									var items:List<NetworkItem> = new List<NetworkItem>();
									var index:Int = command.index;
									for (item in command.locations)
										items.add({
											item: item.item,
											location: item.location,
											player: item.player,
											index: index++
										});
									if (_hOnLocationInfo != null)
										_hOnLocationInfo(items);
								}

							case "RoomUpdate":
								// TODO: [upstream] store checked/missing locations
								if (_hOnLocationChecked != null)
									_hOnLocationChecked(command.checked_locations);

							case "DataPackage":
								var data:Dynamic = _dataPackage;
								if (!data.games)
									data.games = {};
								for (game => gameData in command.data.games)
									data.games[game] = gameData;
								data.version = command.data.version;
								_dataPackageValid = false;
								set_data_package(data);
								_dataPackageValid = true;
								if (_hOnDataPackageChanged != null)
									_hOnDataPackageChanged(_dataPackage);

							case "Print":
								if (_hOnPrint != null)
									_hOnPrint(command.text);

							case "PrintJSON":
								if (_hOnPrintJson != null) {
									var jsonCommand: PrintJsonPacket = command;
									_hOnPrintJson(jsonCommand.data);
								}

							case "Bounced":
								if (_hOnBounced != null)
									_hOnBounced(command);

							case _:
								debug("unhandled cmd");
						}
					}
				}
				_msgQueue.clear();
			} catch (e) {
				trace(e.message);
			}
		_msgMutex.release();
	}

	public function reset() {
		if (_ws != null)
			_ws.close();
		_ws = null;
		_checkQueue.clear();
		_scoutQueue.clear();
		_seed = "";
		_slot = "";
		_team = -1;
		_slotnr = -1;
		_players.clear();
		_clientStatus = ClientStatus.UNKNOWN;
	}

	private inline function log(msg:String) {
		Log.trace(msg);
	}

	private inline function debug(msg:String) {
		#if debug
		Log.trace(msg);
		#end
	}

	private function onopen() {
		debug("onopen()");
		log("Server connected");
		_state = State.SOCKET_CONNECTED;
		if (_hOnSocketConnected != null)
			_hOnSocketConnected();
		_socketReconnectInterval = 1500;
	}

	private function onclose() {
		debug("onclose()");
		if (_state > State.SOCKET_CONNECTING) {
			log("Server disconnected");
			_state = State.DISCONNECTED;
			if (_hOnSocketDisconnected != null)
				_hOnSocketDisconnected();
		}
		_state = State.DISCONNECTED;
		_seed = "";
	}

	private function onmessage(msg:MessageType) {
		switch (msg) {
			case StrMessage(content):
				_msgMutex.acquire();
				_msgQueue.add(content);
				_msgMutex.release();
			case _:
		}
	}

	private function onerror(e:Dynamic) {
		debug("onerror()");
	}

	private function connect_socket() {
		if (_ws != null)
			_ws.close();
		if (_uri.length == 0) {
			_ws = null;
			_state = State.DISCONNECTED;
			return;
		}
		_state = State.SOCKET_CONNECTING;
		_ws = new WebSocket(_uri);
		_ws.onopen = onopen;
		_ws.onclose = onclose;
		_ws.onmessage = onmessage;
		_ws.onerror = onerror;

		_lastSocketConnect = Timer.stamp();
		_socketReconnectInterval *= 2;
		if (_socketReconnectInterval > 15000)
			_socketReconnectInterval = 15000;
	}

	private function color2ansi(color:String):String {
		// convert color to ansi color command
		if (color == "red")
			return "\x1b[31m";
		if (color == "green")
			return "\x1b[32m";
		if (color == "yellow")
			return "\x1b[33m";
		if (color == "blue")
			return "\x1b[34m";
		if (color == "magenta")
			return "\x1b[35m";
		if (color == "cyan")
			return "\x1b[36m";
		if (color == "plum")
			return "\x1b[38:5:219m";
		if (color == "slateblue")
			return "\x1b[38:5:62m";
		if (color == "salmon")
			return "\x1b[38:5:210m";
		return "\x1b[0m";
	}

	private function deansify(text:String):String {
		return StringTools.replace(text, '\x1b', " ");
	}
}

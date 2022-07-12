package ap;

import haxe.DynamicAccess;
import ap.Definitions;
import ap.PacketTypes;
import haxe.exceptions.NotImplementedException;
import haxe.Timer;
import haxe.Json as HJson;
import helder.Set;
import hx.ws.Types.MessageType;
import hx.ws.WebSocket;
#if sys
import sys.FileSystem;
import sys.io.File;
#end
import sys.thread.Mutex;
import tink.Json as TJson;

using StringTools;
using ap.Bitsets;

class Client {
	public var uri(default, null):String;
	public var _game(default, null):String;
	public var uuid(default, null):String;

	private var _ws:WebSocket;
	private var _lastSocketConnect:Float = 0;
	private var _socketReconnectInterval:Float = 1.5;
	private var _checkQueue = new Set<Int>();
	private var _scoutQueue = new Set<Int>();
	private var _clientStatus:ClientStatus = ClientStatus.UNKNOWN;

	private var _players:Array<NetworkPlayer> = [];
	private var _locations:Map<Int, String> = [];
	private var _items:Map<Int, String> = [];
	private var _dataPackage:DataPackageObject;

	public var state(default, null):State = State.DISCONNECTED;
	public var seed(default, null):String = "";
	public var slot(default, null):String = "";
	public var team(default, null):Int = -1;
	public var slotnr(default, null):Int = -1;
	public var dataPackageValid(default, null):Bool = false;
	public var serverConnectTime(default, null):Float = 0;
	public var localConnectTime(default, null):Float = 0;

	public var player_number(get, never):Int;
	public var is_data_package_valid(get, never):Bool;
	public var server_time(get, never):Float;

	private var _packetQueue:Array<IncomingPacket> = [];
	private var _msgMutex = new Mutex();

	public var _hOnSocketConnected(null, default):Void->Void = null;
	public var _hOnSocketDisconnected(null, default):Void->Void = null;
	public var _hOnSlotConnected(null, default):Dynamic->Void = null;
	public var _hOnSlotDisconnected(null, default):Void->Void = null;
	public var _hOnSlotRefused(null, default):Array<String>->Void = null;
	public var _hOnRoomInfo(null, default):Void->Void = null;
	public var _hOnItemsReceived(null, default):Array<NetworkItem>->Void = null;
	public var _hOnLocationInfo(null, default):Array<NetworkItem>->Void = null;
	public var _hOnDataPackageChanged(null, default):DataPackageObject->Void = null;
	public var _hOnPrint(null, default):String->Void = null;
	public var _hOnPrintJson(null, default):(Array<JSONMessagePart>, NetworkItem, Int) -> Void = null;
	public var _hOnBounced(null, default):Dynamic->Void = null;
	public var _hOnLocationChecked(null, default):Array<Int>->Void = null;

	// [private] std::chrono::steady_clock::time_point localConnectTime;

	public function new(uuid:String, game:String, uri:String = "ws://localhost:38281") {
		#if debug
		trace("Creating new AP client to " + uri);
		#end

		if (uri.length > 0) {
			var p = uri.indexOf("://");
			if (p < 0) {
				uri = "ws://" + uri;
				p = 2;
			} else
				this.uri = uri;

			var pColon = uri.indexOf(":", p + 3);
			var pSlash = uri.indexOf("/", p + 3);
			if (pColon < 0 || (pSlash >= 0 && pColon > pSlash)) {
				var tmp = uri.substr(0, pSlash) + ":38281";
				if (pSlash >= 0)
					tmp += uri.substr(pSlash);
				uri = tmp;
			}
		}

		this.uuid = uuid;
		_game = game;
		_dataPackage = {version: 1, games: new Map<String, GameData>()};
		connect_socket();
	}

	public function get_player_number():Int {
		return slotnr;
	}

	public function get_is_data_package_valid():Bool {
		return dataPackageValid;
	}

	public function get_server_time():Float {
		return serverConnectTime + (Timer.stamp() - localConnectTime);
	}

	public function set_data_package(data:Dynamic) {
		if (!dataPackageValid && data.games) {
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

	#if sys
	public function set_data_package_from_file(path:String) {
		if (!FileSystem.exists(path))
			return false;
		set_data_package(HJson.parse(File.getContent(path)));
		return true;
	}

	public function save_data_package(path:String) {
		try {
			var f = File.write(path, true);
			f.writeString(TJson.stringify(_dataPackage));
			f.close();
		} catch (_) {
			return false;
		}
		return true;
	}
	#end

	public function get_player_alias(slot:Int):String {
		if (slot == 0)
			return "Server";
		for (player in _players)
			if (player.team == team && player.slot == slot)
				return player.alias;
		return "Unknown";
	}

	public function get_location_name(code:Int):String {
		if (_locations.exists(code))
			return _locations.get(code);
		return "Unknown";
	}

	/**
		Usage is not recommended

		Return the id associated with the location name

		Return `null` when undefined
	**/
	public function get_location_id(name:String):Null<Int> {
		if (_dataPackage.games.exists(_game) && _dataPackage.games[_game].location_name_to_id.exists(name))
			return _dataPackage.games[_game].location_name_to_id[name];
		return null;
	}

	public function get_item_name(code:Int):String {
		if (_items.exists(code))
			return _items.get(code);
		return "Unknown";
	}

	public function render_json(msg:Array<JSONMessagePart>, fmt:RenderFormat = RenderFormat.TEXT) {
		if (fmt == RenderFormat.HTML)
			throw new NotImplementedException("ap.Client.render_json(..., HTML) not yet implemented [upstream]");

		var out:String = "";
		var colorIsSet:Bool = false;
		for (node in msg) {
			var color:String = null;
			var text:String = "";
			if (fmt != RenderFormat.TEXT)
				color = node.color;
			var id:Null<Int> = Std.parseInt(node.text);
			if (id == null)
				id = 0;
			switch (node.type) {
				case JTYPE_PLAYER_ID:
					if (color == null)
						color = id == slotnr ? "magenta" : "yellow";
					text = get_player_alias(id);
				case JTYPE_ITEM_ID:
					if (color == null) {
						if (node.found)
							color = "green";
						else if (node.flags.contains(FLAG_ADVANCEMENT))
							color = "plum";
						else if (node.flags.contains(FLAG_NEVER_EXCLUDE))
							color = "slateblue";
						else if (node.flags.contains(FLAG_TRAP))
							color = "salmon";
						else
							color = "cyan";
					}
					text = get_item_name(id);
				case JTYPE_LOCATION_ID:
					if (color == null)
						color = "blue";
					text = get_location_name(id);
				default:
					text = node.text;
			}
			if (fmt == RenderFormat.ANSI) {
				if (color == null && colorIsSet) {
					out += color2ansi("");
					colorIsSet = false;
				} else if (color != null) {
					out += color2ansi(color);
					colorIsSet = true;
				}
				out += deansify(text);
			} else
				out += text;
		}
		if (fmt == RenderFormat.ANSI && colorIsSet)
			out += color2ansi("");
		return out;
	}

	private inline function InternalSend(packet:OutgoingPacket):Bool {
		#if debug
		trace("> " + packet);
		#end
		_ws.send(TJson.stringify([packet]));
		return true;
	}

	public function LocationChecks(locations:Array<Int>):Bool {
		if (state == State.SLOT_CONNECTED) {
			InternalSend(OutgoingPacket.LocationChecks(locations));
		} else
			for (i in locations)
				_checkQueue.add(i);
		// TODO: [upstream] this needs to be sent at some point
		return true;
	}

	public function LocationScouts(locations:Array<Int>):Bool {
		if (state == State.SLOT_CONNECTED) {
			InternalSend(OutgoingPacket.LocationScouts(locations));
		} else
			for (i in locations)
				_checkQueue.add(i);
		// TODO: [upstream] this needs to be sent at some point
		return true;
	}

	public function StatusUpdate(status:ClientStatus):Bool {
		if (state == State.SLOT_CONNECTED) {
			return InternalSend(OutgoingPacket.StatusUpdate(status));
		}
		_clientStatus = status;
		return false;
	}

	public function ConnectSlot(name:String, password:Null<String>, items_handling:Int, ?tags:Array<String>, ?ver:NetworkVersion):Bool {
		if (tags == null)
			tags = [];
		if (ver == null)
			ver = {
				major: 0,
				minor: 3,
				build: 1,
			};

		var sendVer = new DynamicAccess<Dynamic>();
		sendVer.set("major", ver.major);
		sendVer.set("minor", ver.minor);
		sendVer.set("build", ver.build);
		sendVer.set("class", "Version");

		if (state < State.SOCKET_CONNECTED)
			return false;
		slot = name;
		#if debug
		trace("Connecting slot...");
		#end
		var p:OutgoingPacket = Connect(
			password,
			_game,
			name,
			uuid,
			sendVer,
			items_handling,
			tags
		);
		return InternalSend(p);
	}

	public function ConnectUpdate(?items_handling:Int, ?tags:Array<String>):Bool {
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
		if (state < State.SLOT_CONNECTED)
			return false;
		return InternalSend(OutgoingPacket.Sync);
	}

	public function GetDataPackage(include:Array<String>):Bool {
		if (state < State.SLOT_CONNECTED)
			return false;
		return InternalSend(OutgoingPacket.GetDataPackage(include));
	}

	public function Bounce(data:Dynamic, games:Array<String>, slots:Array<Int>, tags:Array<String>):Bool {
		if (state < State.ROOM_INFO)
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
		if (state < State.ROOM_INFO)
			return false;
		return InternalSend(OutgoingPacket.Say(text));
	}

	public function poll() {
		if (_ws != null && state == State.DISCONNECTED) {
			_ws.close();
			_ws = null;
		}
		if (_ws != null)
			process_queue();
		if (state < State.SOCKET_CONNECTED) {
			var t = Timer.stamp();
			if (t - _lastSocketConnect > _socketReconnectInterval) {
				if (state != State.DISCONNECTED)
					trace("Connect timed out. Retrying.");
				else
					trace("Reconnecting to server");
				connect_socket();
			}
		}
	}

	public function process_queue() {
		_msgMutex.acquire();
		if (_packetQueue.length > 0)
			trace(_packetQueue.length + " packet(s) in queue; processing");
		for (packet in _packetQueue) {
			switch (packet) {
				case RoomInfo(version, tags, password, permissions, hint_cost, location_check_points, games, datapackage_version, datapackage_versions, seed_name, time):
					localConnectTime = Timer.stamp();
					serverConnectTime = time;
					seed = seed_name;
					if (state < State.ROOM_INFO)
						state = State.ROOM_INFO;
					if (_hOnRoomInfo != null)
						_hOnRoomInfo();

					dataPackageValid = true;
					var include:Array<String> = [];
					for (game => ver in datapackage_versions) {
						try {
							if (ver < 1) { // don't cache for version 0
								include.push(game);
								continue;
							}
							if (_dataPackage.games[game] == null) { // new game
								include.push(game);
								continue;
							}
							if (_dataPackage.games[game].version != ver) { // existing update
								include.push(game);
								continue;
							}
						} catch (e) {
							trace(e.message);
							include.push(game);
						}
					}
					if (!(dataPackageValid = include.length > 0))
						GetDataPackage(include);
					#if debug
					else
						trace("DataPackage up to date");
					#end

				case ConnectionRefused(errors):
					if (_hOnSlotRefused != null)
						_hOnSlotRefused(errors);

				case Connected(team, slot, players, missing_locations, checked_locations, slot_data, slot_info):
					state = State.SLOT_CONNECTED;
					this.team = team;
					slotnr = slot;
					_players = [];
					for (player in players)
						_players.push({
							team: player.team,
							slot: player.slot,
							alias: player.alias,
							name: player.name
						});
					if (_hOnSlotConnected != null)
						_hOnSlotConnected(slot_data);
					// TODO: [upstream] store checked/missing locations
					if (_hOnLocationChecked != null)
						_hOnLocationChecked(checked_locations);

				case ReceivedItems(index, items):
					var index:Int = index;
					for (item in items)
						item.index = index++;
					if (_hOnItemsReceived != null)
						_hOnItemsReceived(items);

				case LocationInfo(locations):
					if (_hOnLocationInfo != null)
						_hOnLocationInfo(locations);

				case RoomUpdate(hint_points, players, checked_locations, missing_locations):
					// TODO: [upstream] store checked/missing locations
					if (_hOnLocationChecked != null)
						_hOnLocationChecked(checked_locations);

				case DataPackage(pdata):
					var data = _dataPackage;
					if (data.games == null)
						data.games = [];
					for (game => gameData in pdata.games)
						data.games[game] = gameData;
					data.version = pdata.version;
					dataPackageValid = false;
					set_data_package(data);
					dataPackageValid = true;
					if (_hOnDataPackageChanged != null)
						_hOnDataPackageChanged(_dataPackage);

				case Print(text):
					if (_hOnPrint != null)
						_hOnPrint(text);

				case PrintJSON(data, receiving, item, found):
					if (_hOnPrintJson != null)
						_hOnPrintJson(data, item, receiving);

				case Bounced(games, slots, tags, data):
					if (_hOnBounced != null)
						_hOnBounced(data);

				default:
					#if debug
					trace("unhandled cmd");
					#end
			}
		}
		_packetQueue = [];
		_msgMutex.release();
	}

	public function reset() {
		if (_ws != null)
			_ws.close();
		_ws = null;
		_checkQueue.clear();
		_scoutQueue.clear();
		seed = "";
		slot = "";
		team = -1;
		slotnr = -1;
		_players = [];
		_clientStatus = ClientStatus.UNKNOWN;
	}

	private inline function log(msg:String) {
		trace(msg);
	}

	private inline function debug(msg:String) {
		#if debug
		trace(msg);
		#end
	}

	private function onopen() {
		#if debug
		trace("onopen()");
		#end
		trace("Server connected");
		state = State.SOCKET_CONNECTED;
		if (_hOnSocketConnected != null)
			_hOnSocketConnected();
		_socketReconnectInterval = 1500;
	}

	private function onclose() {
		#if debug
		trace("onclose()");
		#end
		if (state > State.SOCKET_CONNECTING) {
			trace("Server disconnected");
			state = State.DISCONNECTED;
			if (_hOnSocketDisconnected != null)
				_hOnSocketDisconnected();
		}
		state = State.DISCONNECTED;
		seed = "";
	}

	private function onmessage(msg:MessageType) {
		#if debug
		trace("onmessage()");
		#end
		switch (msg) {
			case StrMessage(content):
				_msgMutex.acquire();
				try {
					var newPackets:Array<IncomingPacket> = TJson.parse(content);
					trace(newPackets);
					for (newPacket in newPackets)
						_packetQueue.push(newPacket);
				} catch (e) {
					trace("EXCEPTION: " + e);
				}
				// _packetQueue = _packetQueue.concat(ne);
				_msgMutex.release();

			default:
		}
	}

	private function onerror(e:Dynamic) {
		#if debug
		trace("onerror()");
		#end
	}

	private function connect_socket() {
		if (_ws != null)
			_ws.close();
		if (uri.length == 0) {
			_ws = null;
			state = State.DISCONNECTED;
			return;
		}
		state = State.SOCKET_CONNECTING;
		#if debug
		trace("Connecting to " + uri);
		#end
		_ws = new WebSocket(uri);
		_ws.onopen = onopen;
		_ws.onclose = onclose;
		_ws.onmessage = onmessage;
		_ws.onerror = onerror;

		_lastSocketConnect = Timer.stamp();
		_socketReconnectInterval *= 2;
		if (_socketReconnectInterval > 15)
			_socketReconnectInterval = 15;
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

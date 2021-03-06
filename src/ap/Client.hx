package ap;

import ap.Definitions;
import ap.PacketTypes;
import haxe.DynamicAccess;
import haxe.exceptions.NotImplementedException;
import haxe.Timer;
import helder.Set;
import hx.ws.Types.MessageType;
import hx.ws.WebSocket;
import tink.Json as TJson;
#if sys
import sys.FileSystem;
import sys.io.File;
import sys.thread.Mutex;
#else
import ap.PseudoMutex;
#end

using StringTools;
using ap.Bitsets;

/** The Archipelago client for Haxe. **/
class Client {
	/** Read-only. The URI the client is configured to connect to. **/
	public var uri(default, null):String;

	/** Read-only. The game the client is configured to connect for. **/
	public var game(default, null):String;

	/** Read-only. The UUID to identify the client. Deprecated, and likely to be removed in a future version. **/
	public var uuid(default, null):String;

	/** The websocket client. **/
	private var _ws:WebSocket;

	/** The local timestamp indicating when the last connection attempt was initiated. **/
	private var _lastSocketConnect:Float = 0;

	/** The amount of time, in seconds, to wait before attempting to reconnect. **/
	private var _socketReconnectInterval:Float = 1.5;

	/** The location checks to be sent, accumulated while the client is not connected. **/
	private var _checkQueue = new Set<Int>();

	/** The location scouts to be sent, accumulated while the client is not connected. **/
	private var _scoutQueue = new Set<Int>();

	/** The list of players in this multiworld. **/
	private var _players:Array<NetworkPlayer> = [];

	/** The dictionary to associate location IDs to names. **/
	private var _locations:Map<Int, String> = [];

	/** The dictionary to associate item IDs to names. **/
	private var _items:Map<Int, String> = [];

	/** A copy of the Data Package used by the client. **/
	private var _dataPackage:DataPackageObject;

	/** The current server state for this client. **/
	public var clientStatus(default, set):ClientStatus = ClientStatus.UNKNOWN;

	/** Read-only. The current connection state of the client. **/
	public var state(default, null):State = State.DISCONNECTED;

	/** Read-only. A unique string identifier for this multiworld's seed. **/
	public var seed(default, null):String = "";

	/** Read-only. The slot name the client is connected to. **/
	public var slot(default, null):String = "";

	/** Read-only. The team number the player belongs to. Currently unused. **/
	public var team(default, null):Int = -1;

	/** Read-only. The slot number the player is in. **/
	public var slotnr(default, null):Int = -1;

	/** Read-only. Whether the data package is currently accurate to server data. **/
	public var dataPackageValid(default, null):Bool = false;

	/** Read-only. The UNIX time, in seconds, when the connection was established. **/
	public var serverConnectTime(default, null):Float = 0;

	/** Read-only. A local timestamp representing when the connection was established. **/
	public var localConnectTime(default, null):Float = 0;

	/** Read-only. The current UNIX time for the server, in seconds, extrapolated based on `localConnectTime`. **/
	public var server_time(get, never):Float;

	/** The list of packets received since the last `poll()`. **/
	private var _packetQueue:Array<IncomingPacket> = [];

	/** Locks access to `_packetQueue` to either the websocket client or the game. **/
	#if sys
	private var _msgMutex = new Mutex();
	#else
	private var _msgMutex = new PseudoMutex();
	#end

	/** Write-only. Called when the websocket connects to the server. **/
	public var _hOnSocketConnected(null, default):Void->Void = null;

	/** Write-only. Called when the websocket disconnects from the server. **/
	public var _hOnSocketDisconnected(null, default):Void->Void = null;

	/**
		Write-only. Called when the client connects to the server.
		@param slot_data The custom data sent from the server pertaining to the game, if any.
	**/
	public var _hOnSlotConnected(null, default):Dynamic->Void = null;

	/** Write-only. Called when the client disconnects from the server. **/
	public var _hOnSlotDisconnected(null, default):Void->Void = null;

	/** Write-only. Called if slot authentication fails. **/
	public var _hOnSlotRefused(null, default):Array<String>->Void = null;

	/** Write-only. Called when a RoomInfo packet is received. **/
	public var _hOnRoomInfo(null, default):Void->Void = null;

	/** Write-only. Called when an ItemsReceived packet is received. **/
	public var _hOnItemsReceived(null, default):Array<NetworkItem>->Void = null;

	/** Write-only. Called when a LocationInfo packet is received. **/
	public var _hOnLocationInfo(null, default):Array<NetworkItem>->Void = null;

	/**
		Write-only. Called if the Data Package has changed.
		@param data The new content of the Data Package.
	**/
	public var _hOnDataPackageChanged(null, default):DataPackageObject->Void = null;

	/**
		Write-only. Called when a Print packet is received.
		@param text The text received.
	**/
	public var _hOnPrint(null, default):String->Void = null;

	/**
		Write-only. Called when a PrintJSON packet is received.
		@param data The content of the message, in `JSONMessagePart`s.
		@param item The item in question, if any.
		@param receiving The ID of the receiving player, if any.
	**/
	public var _hOnPrintJson(null, default):(Array<JSONMessagePart>, Null<NetworkItem>, Null<Int>) -> Void = null;

	/**
		Write-only. Called when a Bounced packet is received.
		@param data The data contained in the packet.
	**/
	public var _hOnBounced(null, default):Dynamic->Void = null;

	/**
		Write-only. Called when locations have been checked.
		@param ids The ID numbers for the locations checked.
	**/
	public var _hOnLocationChecked(null, default):Array<Int>->Void = null;

	/**
		Creates a new instance of the Archipelago client.
		@param uuid The unique ID for this client. Deprecated, and likely to be removed in a later version.
		@param game The game to connect to.
		@param uri The server to connect to, including host name and port.
	**/
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
		this.game = game;
		_dataPackage = {games: new DynamicAccess<GameData>()};
		connect_socket();
	}

	public function set_clientStatus(status:ClientStatus):ClientStatus {
		if (state == State.SLOT_CONNECTED)
			InternalSend(OutgoingPacket.StatusUpdate(status));
		return clientStatus = status;
	}

	public function get_server_time():Float {
		return serverConnectTime + (Timer.stamp() - localConnectTime);
	}

	/**
		Sets the Data Package's data.
		@param data The data to add to the Data Package.
	**/
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
	/**
		Loads the Data Package from a file. Only available on `sys` platforms.
		@param path The file to load.
		@return Whether the operation was successful.
	**/
	public function set_data_package_from_file(path:String) {
		if (!FileSystem.exists(path))
			return false;
		set_data_package(TJson.parse(File.getContent(path)));
		return true;
	}

	/**
		Saves the Data Package to a file. Only available on `sys` platforms.
		@param path The file to save to.
		@return Whether the operation was successful.
	**/
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

	/**
		Resolves a slot number into that player's current alias.
		@param slot The slot to look up.
		@return The name attached to the given slot number, or "Unknown" if no such slot exists. For a slot number of 0, "Server" is returned.
	**/
	public function get_player_alias(slot:Int):String {
		if (slot == 0)
			return "Server";
		for (player in _players)
			if (player.team == team && player.slot == slot)
				return player.alias;
		return "Unknown";
	}

	/**
		Resolves a location ID into the name of that location.
		@param code The location ID to look up.
		@return The name of the location attached to the given ID, or "Unknown" if it was not found.
	**/
	public function get_location_name(code:Int):String {
		if (_locations.exists(code))
			return _locations.get(code);
		return "Unknown";
	}

	/**
		Resolves a location name into the ID of that location. Usage is not recommended.
		@param name The name of the location to look up.
		@return The ID associated with the location name, or `null` if it was not found.
	**/
	public function get_location_id(name:String):Null<Int> {
		if (_dataPackage.games.exists(game) && _dataPackage.games[game].location_name_to_id.exists(name))
			return _dataPackage.games[game].location_name_to_id[name];
		return null;
	}

	/**
		Resolves an item ID into the name of that item.
		@param code The item ID to look up.
		@return The name of the item attached to the given ID, or "Unknown" if it was not found.
	**/
	public function get_item_name(code:Int):String {
		if (_items.exists(code))
			return _items.get(code);
		return "Unknown";
	}

	/**
		Renders `JSONMessagePart`s into a more usable format.
		@param msg The `JSONMessagePart`s to render.
		@param fmt The format to render into.
		@return The rendered result.
		@throws NotImplementedException Thrown if HTML rendering was requested.
	**/
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

	/**
		Sends a packet to the server.
		@param packet The packet to send.
		@return Whether the operation was successful.
	**/
	private inline function InternalSend(packet:OutgoingPacket):Bool {
		#if debug
		trace("> " + packet);
		#end
		_ws.send(TJson.stringify([packet]));
		return true;
	}

	/**
		Sends a LocationChecks packet to the server.
		@param location The locations to check.
		@return Whether the operation was successful.
	**/
	public function LocationChecks(locations:Array<Int>):Bool {
		if (state == State.SLOT_CONNECTED)
			return InternalSend(OutgoingPacket.LocationChecks(locations));
		else
			for (i in locations)
				_checkQueue.add(i);
		// TODO: [upstream] this needs to be sent at some point
		return true;
	}

	/**
		Sends a LocationScouts packet to the server.
		@param location The locations to scout.
		@return Whether the operation was successful.
	**/
	public function LocationScouts(locations:Array<Int>, create_as_hint = 0):Bool {
		if (state == State.SLOT_CONNECTED)
			return InternalSend(OutgoingPacket.LocationScouts(locations, create_as_hint));
		else
			for (i in locations)
				_checkQueue.add(i);
		// TODO: [upstream] this needs to be sent at some point
		return true;
	}

	/**
		Connects to a slot in the multiworld.
		@param name The slot name.
		@param password The password for this multiworld, if any.
		@param items_handling The flags regarding how item processing will be handled.
		@param tags The capability tags for this session. Defaults to `[]`.
		@param ver The minimum version number for this client. Currently defaults to 0.3.2; later versions may change this.
	**/
	public function ConnectSlot(name:String, password:Null<String>, items_handling:Int, ?tags:Array<String>, ?ver:NetworkVersion):Bool {
		if (state < State.SOCKET_CONNECTED)
			return false;

		if (tags == null)
			tags = [];
		if (ver == null)
			ver = {
				major: 0,
				minor: 3,
				build: 2,
			};

		var sendVer = new DynamicAccess<Dynamic>();
		sendVer.set("major", ver.major);
		sendVer.set("minor", ver.minor);
		sendVer.set("build", ver.build);
		sendVer.set("class", "Version");

		slot = name;
		#if debug
		trace("Connecting to slot...");
		#end
		return InternalSend(OutgoingPacket.Connect(password, game, name, uuid, sendVer, items_handling, tags));
	}

	/**
		Updates the connection with new item handling or tags.
		@param items_handling The flags regarding how item processing will be handled, if changed.
		@param tags The capability tags for this session, if changed.
	**/
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

	/**
		Synchronizes check progress with the multiworld server.
		@return Whether the operation was successful.
	**/
	public function Sync():Bool {
		if (state < State.SLOT_CONNECTED)
			return false;
		return InternalSend(OutgoingPacket.Sync);
	}

	/**
		Requests data package information from the multiworld server.
		@param include Optional. The games to include in the Data Package request. If not specified, will retrieve the complete Data Package.
		@return Whether the operation was successful.
	**/
	public function GetDataPackage(?include:Array<String>):Bool {
		if (state < State.SLOT_CONNECTED)
			return false;
		return InternalSend(OutgoingPacket.GetDataPackage(include));
	}

	/**
		Sends a Bounce packet to the multiworld server.
		@param data Arbitrary data to include in the Bounce packet.
		@param games Optional. The games to target for this packet.
		@param slots Optional. The slot numbers to target for this packet.
		@param tags Optional. The tags to target for this packet.
		@return Whether the operation was successful.
	**/
	public function Bounce(data:Dynamic, ?games:Array<String>, ?slots:Array<Int>, ?tags:Array<String>):Bool {
		if (state < State.ROOM_INFO)
			return false;
		return InternalSend(OutgoingPacket.Bounce(games, slots, tags, data));
	}

	/**
		Sends a text message to the multiworld server.
		@param text The text to send.
		@return Whether the operation was successful.
	**/
	public function Say(text:String):Bool {
		if (state < State.ROOM_INFO)
			return false;
		return InternalSend(OutgoingPacket.Say(text));
	}

	/** Polls the client for new packets. **/
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

	/** Processes the packets currently in the queue. **/
	private function process_queue() {
		#if sys
		_msgMutex.acquire();
		#else
		_msgMutex.acquire("process_queue");
		#end
		if (_packetQueue.length > 0)
			trace(_packetQueue.length + " packet(s) in queue; processing");
		for (packet in _packetQueue) {
			switch (packet) {
				case RoomInfo(version, tags, password, permissions, hint_cost, location_check_points, games, datapackage_version, datapackage_versions,
					seed_name, time):
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

				case RoomUpdate(_, _, _, _, _, _, _, _, _, _, _, _, _, checked_locations, missing_locations):
					// TODO: [upstream] store checked/missing locations
					if (_hOnLocationChecked != null)
						_hOnLocationChecked(checked_locations);

				case DataPackage(pdata):
					var data:DataPackageObject = {
						games: _dataPackage.games.copy(),
					};
					for (game => gameData in pdata.games)
						data.games[game] = gameData;
					dataPackageValid = false;
					set_data_package(data);
					dataPackageValid = true;
					if (_hOnDataPackageChanged != null)
						_hOnDataPackageChanged(_dataPackage);

				case Print(text):
					if (_hOnPrint != null)
						_hOnPrint(text);

				case PrintJSON(data, type, receiving, item, found):
					if (_hOnPrintJson != null)
						_hOnPrintJson(data, item, receiving);

				case Bounced(games, slots, tags, data):
					if (games != null && !games.contains(game)) break;
					if (slots != null && !slots.contains(slotnr)) break;
					// TODO: check to make sure tag matches
					if (_hOnBounced != null)
						_hOnBounced(data);

				default:
					#if debug
					trace("unhandled cmd");
					#end
			}
		}
		_packetQueue = [];
		#if sys
		_msgMutex.release();
		#else
		_msgMutex.release("process_queue");
		#end
	}

	/** Resets the client to its original state. **/
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
		clientStatus = ClientStatus.UNKNOWN;
	}

	/** Outputs a message to the terminal. **/
	private inline function log(msg:String) {
		trace(msg);
	}

	/** Outputs a message to the terminal, only if built in debug mode. **/
	private inline function debug(msg:String) {
		#if debug
		trace(msg);
		#end
	}

	/** Called when the websocket is opened. **/
	private function onopen() {
		#if debug
		trace("onopen()");
		#end
		trace("Server connected");
		state = State.SOCKET_CONNECTED;
		if (_hOnSocketConnected != null)
			_hOnSocketConnected();
		_socketReconnectInterval = 1.5;
	}

	/** Called when the websocket is closed. **/
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

	/**
		Called when the websocket receives a message.
		@param msg The message received.
	**/
	private function onmessage(msg:MessageType) {
		#if debug
		trace("onmessage()");
		#end
		switch (msg) {
			case StrMessage(content):
				#if sys
				_msgMutex.acquire();
				#else
				_msgMutex.acquire("onmessage");
				#end
				try {
					var newPackets:Array<IncomingPacket> = TJson.parse(content);
					trace(newPackets);
					for (newPacket in newPackets)
						_packetQueue.push(newPacket);
				} catch (e) {
					trace("EXCEPTION: " + e);
				}
				// _packetQueue = _packetQueue.concat(ne);
				#if sys
				_msgMutex.release();
				#else
				_msgMutex.release("onmessage");
				#end

			default:
		}
	}

	/**
		Called when the websocket encounters an error.
		@param e The error data.
	**/
	private function onerror(e:Dynamic) {
		#if debug
		trace("onerror()");
		#end
	}

	/** Creates a new websocket client and connects to the server. **/
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

	/**
		Converts a color string to an ANSI representation of that string.
		@param color The color to convert.
		@return The ANSI representation of the color.
	**/
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

	/**
		Strips ANSI escape codes from a string.
		@param text The string to de-ANSIfy.
		@return The de-ANSIfied string.
	**/
	private inline function deansify(text:String):String {
		return ~/\x1b\[[\d:]+m/g.replace(text, "");
	}
}

package ap;

import hx.concurrent.lock.RLock;
import ap.Definitions;
import ap.PacketTypes;
import haxe.DynamicAccess;
import haxe.Exception;
import haxe.exceptions.NotImplementedException;
import haxe.Timer;
import helder.Set;
import hx.ws.Types.MessageType;
import hx.ws.WebSocket;
import tink.Json as TJson;
#if sys
import sys.FileSystem;
import sys.io.File;
#end
#if (lime && !AP_NO_LIME)
import lime.app.Event;
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

	/** Read-only. The number of hint points the player has. **/
	public var hintPoints(default, null):Int = -1;

	/** Read-only. The number of hint points it costs to request a hint. **/
	public var hintCostPoints(get, null):Int;

	/** Read-only. The percentage of total hint points it costs to request a hint. **/
	public var hintCostPercent(default, null):Int = -1;

	/** Read-only. The total number of location checks in this world. **/
	public var locationCount(default, null):Int = -1;

	/** Read-only. Whether the data package is currently accurate to server data. **/
	public var dataPackageValid(default, null):Bool = false;

	/** Read-only. The UNIX time, in seconds, when the connection was established. **/
	public var serverConnectTime(default, null):Float = 0;

	/** Read-only. A local timestamp representing when the connection was established. **/
	public var localConnectTime(default, null):Float = 0;

	/** Read-only. The number of times connection has been attempted. Will be reset to 0 when connected. **/
	public var connectAttempts(default, null) = 0;

	/** Read-only. The current UNIX time for the server, in seconds, extrapolated based on `localConnectTime`. **/
	public var server_time(get, never):Float;

	/** The current client tags. **/
	public var tags(get, set):Array<String>;

	private var _tags:Array<String> = [];

	/** The list of packets received since the last `poll()`. **/
	private var _packetQueue:Array<IncomingPacket> = [];

	/** Locks access to `_packetQueue` to either the websocket client or the game. **/
	private var _msgLock = new RLock();

	/** The list of packets queued to be sent since the last `poll()`. **/
	private var _sendQueue:Array<OutgoingPacket> = [];

	/** Locks access to `_sendQueue` to either the websocket client or the game. **/
	private var _sendLock = new RLock();

	private var _hasTriedWSS = false;
	private var _hasBeenConnected = false;

	#if (lime && !AP_NO_LIME)
	/** Called when the websocket connects to the server. **/
	public var onSocketConnected(default, null) = new Event<Void->Void>();

	/** Called when the websocket disconnects from the server. **/
	public var onSocketDisconnected(default, null) = new Event<Void->Void>();

	/**
		Called when the client connects to the slot.
		@param slot_data The custom data sent from the server pertaining to the game, if any.
	**/
	public var onSlotConnected(default, null) = new Event<Dynamic->Void>();

	/** Called when the websocket disconnects from the slot. **/
	public var onSlotDisconnected(default, null) = new Event<Void->Void>();

	/**
		Called when an ItemsReceived packet is received.
		@param errors The error code(s) received from the server.
	**/
	public var onSlotRefused(default, null) = new Event<Array<String>->Void>();

	/** Called when a RoomInfo packet is received. **/
	public var onRoomInfo(default, null) = new Event<Void->Void>();

	/**
		Called when an ItemsReceived packet is received.
		@param items The list of items received.
	**/
	public var onItemsReceived(default, null) = new Event<Array<NetworkItem>->Void>();

	/**
		Called when a LocationInfo packet is received.
		@param items The list of items scouted.
	**/
	public var onLocationInfo(default, null) = new Event<Array<NetworkItem>->Void>();

	/**
		Called when the Data Package has changed.
		@param data The new content of the Data Package.
	**/
	public var onDataPackageChanged(default, null) = new Event<Array<DataPackageObject>->Void>();

	/**
		Called when a Print packet is received.
		@param text The text received.
	**/
	public var onPrint(default, null) = new Event<String->Void>();

	/**
		Called when a PrintJSON packet is received.
		@param data The content of the message, in `JSONMessagePart`s.
		@param item The item in question, if any.
		@param receiving The ID of the receiving player, if any.
	**/
	public var onPrintJSON(default, null) = new Event<(Array<JSONMessagePart>, Null<NetworkItem>, Null<Int>) -> Void>();

	/**
		Called when a Bounced packet is received.
		@param data The data contained in the packet.
	**/
	public var onBounced(default, null) = new Event<Dynamic->Void>();

	/**
		Called when locations have been checked.
		@param ids The ID numbers for the locations checked.
	**/
	public var onLocationChecked(default, null) = new Event<Array<Int>->Void>();

	/**
		Called when data has been retrieved from a Get call.
		@param keys A key-value collection containing all the values for the keys requested in the Get package.
	**/
	public var onRetrieved(default, null) = new Event<DynamicAccess<Dynamic>->Void>();

	/**
		Called when a Set operation has been processed, and a reply was requested.
		@param key The key that was updated.
		@param value The new value for the key.
		@param original_value The value the key had before it was updated.
	**/
	public var onSetReply(default, null) = new Event<(String, Dynamic, Dynamic) -> Void>();

	/**
		Called when an error occurs.
		@param funcName The function where the error was caught.
		@param data The error data.
	**/
	public var onThrow(default, null) = new Event<(String, Dynamic) -> Void>();

	inline function _hOnSocketConnected()
		return onSocketConnected.dispatch();

	inline function _hOnSocketDisconnected()
		return onSocketDisconnected.dispatch();

	inline function _hOnSlotConnected(slotData)
		return onSlotConnected.dispatch(slotData);

	inline function _hOnSlotDisconnected()
		return onSlotDisconnected.dispatch();

	inline function _hOnSlotRefused(errors)
		return onSlotRefused.dispatch(errors);

	inline function _hOnItemsReceived(items)
		return onItemsReceived.dispatch(items);

	inline function _hOnLocationInfo(items)
		return onLocationInfo.dispatch(items);

	inline function _hOnDataPackageChanged(data)
		return onDataPackageChanged.dispatch(data);

	inline function _hOnPrint(text)
		return onPrint.dispatch(text);

	inline function _hOnPrintJson(data, item, receiving)
		return onPrintJson.dispatch(data, item, receiving);

	inline function _hOnBounced(data)
		return onBounced.dispatch(data);

	inline function _hOnLocationChecked(data)
		return onLocationChecked.dispatch(data);

	inline function _hOnRetrieved(keys)
		return onRetrieved.dispatch(keys);

	inline function _hOnSetReply(key, value, original_value)
		return onSetReply.dispatch(key, value, original_value);

	inline function _hOnThrow(funcName, data)
		return onThrow.dispatch(funcName, data);
	#else

	/** Write-only. Called when the websocket connects to the server. **/
	public var _hOnSocketConnected(null, default):Void->Void = () -> {};

	/** Write-only. Called when the websocket disconnects from the server. **/
	public var _hOnSocketDisconnected(null, default):Void->Void = () -> {};

	/**
		Write-only. Called when the client connects to the slot.
		@param slot_data The custom data sent from the server pertaining to the game, if any.
	**/
	public var _hOnSlotConnected(null, default):Dynamic->Void = (_) -> {};

	/** Write-only. Called when the client disconnects from the slot. **/
	public var _hOnSlotDisconnected(null, default):Void->Void = () -> {};

	/** Write-only. Called if slot authentication fails. **/
	public var _hOnSlotRefused(null, default):Array<String>->Void = (_) -> {};

	/** Write-only. Called when a RoomInfo packet is received. **/
	public var _hOnRoomInfo(null, default):Void->Void = () -> {};

	/** Write-only. Called when an ItemsReceived packet is received. **/
	public var _hOnItemsReceived(null, default):Array<NetworkItem>->Void = (_) -> {};

	/** Write-only. Called when a LocationInfo packet is received. **/
	public var _hOnLocationInfo(null, default):Array<NetworkItem>->Void = (_) -> {};

	/**
		Write-only. Called when the Data Package has changed.
		@param data The new content of the Data Package.
	**/
	public var _hOnDataPackageChanged(null, default):DataPackageObject->Void = (_) -> {};

	/**
		Write-only. Called when a Print packet is received.
		@param text The text received.
	**/
	public var _hOnPrint(null, default):String->Void = (_) -> {};

	/**
		Write-only. Called when a PrintJSON packet is received.
		@param data The content of the message, in `JSONMessagePart`s.
		@param item The item in question, if any.
		@param receiving The ID of the receiving player, if any.
	**/
	public var _hOnPrintJson(null, default):(Array<JSONMessagePart>, Null<NetworkItem>, Null<Int>) -> Void = (_, _, _) -> {};

	/**
		Write-only. Called when a Bounced packet is received.
		@param data The data contained in the packet.
	**/
	public var _hOnBounced(null, default):Dynamic->Void = (_) -> {};

	/**
		Write-only. Called when locations have been checked.
		@param ids The ID numbers for the locations checked.
	**/
	public var _hOnLocationChecked(null, default):Array<Int>->Void = (_) -> {};

	/**
		Write-only. Called when data has been retrieved from a Get call.
		@param keys A key-value collection containing all the values for the keys requested in the Get package.
	**/
	public var _hOnRetrieved(null, default):DynamicAccess<Dynamic>->Void = (_) -> {};

	/**
		Write-only. Called when a Set operation has been processed, and a reply was requested.
		@param key The key that was updated.
		@param value The new value for the key.
		@param original_value The value the key had before it was updated.
	**/
	public var _hOnSetReply(null, default):(String, Dynamic, Dynamic) -> Void = (_, _, _) -> {};

	/**
		Write-only. Called when an error occurs.
		@param funcName The function where the error was caught.
		@param data The error data.
	**/
	public var _hOnThrow(null, default):(String, Dynamic) -> Void = (_, _) -> {};
	#end

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
				this.uri = "ws://" + uri;
				p = 2;
			} else
				this.uri = uri;

			var pColon = this.uri.indexOf(":", p + 3);
			var pSlash = this.uri.indexOf("/", p + 3);
			if (pColon < 0 || (pSlash >= 0 && pColon > pSlash)) {
				var tmp = this.uri.substr(0, pSlash) + ":38281";
				if (pSlash >= 0)
					tmp += this.uri.substr(pSlash);
				this.uri = tmp;
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

	public inline function get_server_time()
		return serverConnectTime + (Timer.stamp() - localConnectTime);

	inline function get_tags()
		return _tags.slice(0);

	function set_tags(tags) {
		ConnectUpdate(null, tags);
		return tags;
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

	public function get_hintCostPoints() {
		if (hintCostPercent <= 0)
			return hintCostPercent;
		if (locationCount <= 0)
			return locationCount;
		return Math.floor(Math.max(1, hintCostPercent * locationCount / 100));
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
						else if (node.flags.isAdvancement)
							color = "plum";
						else if (node.flags.isNeverExclude)
							color = "slateblue";
						else if (node.flags.isTrap)
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
		if (packet == null) {
			_hOnThrow("InternalSend", new Exception("Something tried to queue a null packet"));
			return false;
		}

		#if debug
		trace("> " + packet);
		#end

		_sendLock.execute(() -> _sendQueue.push(packet));

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
		@param ver The minimum version number for this client. Currently defaults to 0.4.1; later versions may change this.
	**/
	public function ConnectSlot(name:String, password:Null<String>, items_handling:Int, ?tags:Array<String>, ?ver:NetworkVersion):Bool {
		if (state < State.SOCKET_CONNECTED)
			return false;

		if (tags == null)
			_tags = [];
		if (ver == null)
			ver = {
				major: 0,
				minor: 4,
				build: 1,
			};

		// HACK: because "class" is getting dropped every time I try to process this with tink
		var sendVer = new DynamicAccess<Dynamic>();
		sendVer.set("major", ver.major);
		sendVer.set("minor", ver.minor);
		sendVer.set("build", ver.build);
		sendVer.set("class", "Version");

		slot = name;
		#if debug
		trace("Connecting to slot...");
		#end
		return InternalSend(OutgoingPacket.Connect(password, game, name, uuid, sendVer, items_handling, tags, true));
	}

	/**
		Updates the connection with new item handling or tags.
		@param items_handling The flags regarding how item processing will be handled, if changed.
		@param tags The capability tags for this session, if changed.
	**/
	public function ConnectUpdate(?items_handling:Int, ?tags:Array<String>):Bool {
		if (items_handling == null && tags == null)
			return false;

		return InternalSend(OutgoingPacket.ConnectUpdate(items_handling, tags));
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

	public function Get(keys:Array<String>) {
		if (state < State.SLOT_CONNECTED)
			return false;
		return InternalSend(OutgoingPacket.Get(keys));
	}

	public function Set(key:String, dflt:Dynamic, want_reply:Bool, operations:Array<DataStorageOperation>) {
		if (state < State.SLOT_CONNECTED)
			return false;
		return InternalSend(OutgoingPacket.Set(key, dflt, want_reply, operations));
	}

	public function SetNotify(keys:Array<String>) {
		if (state < State.SLOT_CONNECTED)
			return false;
		return InternalSend(OutgoingPacket.SetNotify(keys));
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
				if (state != State.DISCONNECTED) {
					_hOnThrow("poll", new Exception("Connect timed out"));
					trace("Connect timed out. Retrying.");
				} else
					trace("Reconnecting to server");
				connect_socket();
			}
		}
	}

	/** Processes the packets currently in the queue. **/
	private function process_queue() {
		if (_sendQueue.length > 0) {
			_sendLock.execute(() -> {
				#if debug
				trace('Sending ${_sendQueue.length} queued packet(s)');
				#end
				_ws.send(TJson.stringify(_sendQueue));
				_sendQueue = [];
			});
		}

		_msgLock.acquire();
		var grabQueue = _packetQueue.slice(0);
		_packetQueue = [];
		_msgLock.release();

		#if debug
		if (grabQueue.length > 0)
			trace('Processing ${grabQueue.length} received packet(s)');
		#end

		for (packet in grabQueue) {
			switch (packet) {
				case RoomInfo(version, _, tags, password, permissions, hint_cost, location_check_points, games, _, datapackage_versions,
					datapackage_checksums, seed_name, time):
					localConnectTime = Timer.stamp();
					_hasBeenConnected = true;
					serverConnectTime = time;
					seed = seed_name;
					hintCostPercent = hint_cost;
					hintPoints *= location_check_points;
					_tags = tags;
					if (state < State.ROOM_INFO)
						state = State.ROOM_INFO;
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
					_hOnSlotRefused(errors);

				case Connected(team, slot, players, missing_locations, checked_locations, slot_data, slot_info, hint_points):
					connectAttempts = 0;
					state = State.SLOT_CONNECTED;
					this.clientStatus = ClientStatus.CONNECTED;
					this.team = team;
					slotnr = slot;
					_players = [];
					locationCount = missing_locations.length + checked_locations.length;
					hintPoints = hint_points;
					for (player in players)
						_players.push({
							team: player.team,
							slot: player.slot,
							alias: player.alias,
							name: player.name
						});
					_hOnSlotConnected(slot_data);
					// TODO: [upstream] store checked/missing locations
					_hOnLocationChecked(checked_locations);

				case ReceivedItems(index, items):
					var index:Int = index;
					for (item in items)
						item.index = index++;
					_hOnItemsReceived(items);

				case LocationInfo(locations):
					_hOnLocationInfo(locations);

				case RoomUpdate(_, tags, _, _, _, _, _, _, _, _, _, _, hint_points, _, checked_locations, missing_locations):
					// TODO: [upstream] store checked/missing locations
					hintPoints = hint_points;
					_tags = tags;
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
					_hOnDataPackageChanged(_dataPackage);

				case Print(text):
					_hOnPrint(text);

				case PrintJSON(data, type, receiving, item, found, team, slot, message, tags, countdown):
					_hOnPrintJson(data, item, receiving);

				case Bounced(games, slots, tags, data):
					if (games != null && !games.contains(game))
						break;
					if (slots != null && !slots.contains(slotnr))
						break;
					if (tags != null) {
						var tagMatch = false;
						for (bTag in tags)
							tagMatch = tagMatch || this.tags.contains(bTag);
						if (!tagMatch)
							break;
					}
					_hOnBounced(data);

				// BUG: "Cannot access non-static abstract field statically" on extracting "keys"
				// case Retrieved(keys):
				//	_hOnRetrieved(keys);

				case SetReply(key, value, original_value):
					_hOnSetReply(key, value, original_value);

				case x:
					#if debug
					trace('unhandled cmd ${x.getName()}');
					#end
					_hOnThrow("process_queue", x);
			}
		}
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
		connectAttempts = 0;
		this.clientStatus = ClientStatus.UNKNOWN;
	}

	/** Called when the websocket is opened. **/
	private function onopen() {
		#if debug
		trace("onopen()");
		#end
		trace("Server connected");
		state = State.SOCKET_CONNECTED;
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
			_hOnSocketDisconnected();
		}
		if (!_hasBeenConnected && !_hasTriedWSS) {
			#if debug
			trace("Disconnected immediately; may be a WSS socket (upgrading)");
			#end
			uri = toggleWSS(uri);
		}
		state = State.DISCONNECTED;
		seed = "";
		_ws.close();
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
				_msgLock.acquire();
				try {
					#if debug
					trace(content);
					#end
					var newPackets:Array<IncomingPacket> = TJson.parse(content);
					trace(newPackets);
					for (newPacket in newPackets)
						_packetQueue.push(newPacket);
				} catch (e) {
					trace("EXCEPTION: " + e);
					_hOnThrow("onmessage", e);
				}
				_msgLock.release();

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
		_hOnThrow("onerror", e);
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

		try {
			_lastSocketConnect = Timer.stamp();
			_socketReconnectInterval *= 2;
			if (_socketReconnectInterval > 15)
				_socketReconnectInterval = 15;
			connectAttempts++;

			_ws = new WebSocket(uri);
			_ws.onopen = onopen;
			_ws.onclose = onclose;
			_ws.onmessage = onmessage;
			_ws.onerror = onerror;
		} catch (e:Exception) {
			trace("Error connecting to AP socket", e);
			_hOnThrow("connect_socket", e);
			if (e.message == "ssl network error" && uri.startsWith("wss:")) { // TODO: check what happens if you try to connect WS client to WSS server
				#if debug
				trace("WSS connection not found; auto-switching to WS");
				#end
				_hasTriedWSS = true;
				uri = toggleWSS(uri);
			}
		}
	}

	public function disconnect_socket() {
		if (_ws != null) {
			_ws.close();
			state = State.DISCONNECTED;
		}
	}

	/**
		Converts a color string to an ANSI representation of that string.
		@param color The color to convert.
		@return The ANSI representation of the color.
	**/
	private static function color2ansi(color:String):String
		return switch (color) {
			case "red": "\x1b[31m";
			case "green": "\x1b[32m";
			case "yellow": "\x1b[33m";
			case "blue": "\x1b[34m";
			case "magenta": "\x1b[35m";
			case "cyan": "\x1b[36m";
			case "plum": "\x1b[38:5:219m";
			case "slateblue": "\x1b[38:5:62m";
			case "salmon": "\x1b[38:5:210m";
			default: "\x1b[0m";
		}

	/**
		Strips ANSI escape codes from a string.
		@param text The string to de-ANSIfy.
		@return The de-ANSIfied string.
	**/
	private static inline function deansify(text:String):String
		return ~/\x1b\[[\d:]+m/g.replace(text, "");

	/**
		Changes a wss:// URI into ws://, and vice versa.
		@param uri The URI to convert.
		@return The URI with the opposite protocol. If the original URI does not have a protocol specified, a wss:// URI is returned.
	**/
	private static function toggleWSS(uri:String):String {
		var isWSS = uri.startsWith("wss://");
		var baseURI = (~/^wss?:\/\//).replace(uri, "");
		return (isWSS ? "ws://" : "wss://") + baseURI;
	}
}

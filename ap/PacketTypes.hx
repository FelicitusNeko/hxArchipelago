package ap;

import haxe.Int64;

@:enum
abstract Permission(Int) from Int to Int {
	var PERM_DISABLED = 0;
	var PERM_ENABLED = 1 << 0;
	var PERM_GOAL = 1 << 1;
	var PERM_AUTO = 1 << 2;
	var PERM_AUTO_GOAL = PERM_GOAL | PERM_AUTO;
	var PERM_AUTO_ENABLED = PERM_AUTO_GOAL | PERM_ENABLED;
}

@:enum
abstract SlotType(Int) from Int to Int {
	var STYPE_SPECTATOR = 0;
	var STYPE_PLAYER = 1 << 0;
	var STYPE_GROUP = 1 << 1;
}

@:enum
abstract ItemFlags(Int) from Int to Int {
	var FLAG_NONE = 0;
	var FLAG_ADVANCEMENT = 1 << 0;
	var FLAG_NEVER_EXCLUDE = 1 << 1;
	var FLAG_TRAP = 1 << 2;
}

@:enum
abstract JSONType(String) {
  var JTYPE_TEXT = "text";
  var JTYPE_PLAYER_ID = "player_id";
  var JTYPE_PLAYER_NAME = "player_name";
  var JTYPE_ITEM_ID = "item_id";
  var JTYPE_ITEM_NAME = "item_name";
  var JTYPE_LOCATION_ID = "location_id";
  var JTYPE_LOCATION_NAME = "location_name";
  var JTYPE_ENTRANCE_NAME = "entrance_name";
  var JTYPE_COLOR = "color";
}

typedef NetworkItem = {
	var item:Int64;
	var location:Int64;
	var player:Int;
	var flags:ItemFlags;
	var ?index:Int;
}

typedef NetworkPlayer = {
	var team:Int;
	var slot:Int;
	var alias:String;
	var name:String;
}

typedef JSONMessagePart = {
	var ?type:JSONType;
	var ?color:String;
	var ?text:String;
	var ?found:Bool;
	var ?flags:ItemFlags;
}

typedef Version = {
	var major:Int;
	var minor:Int;
	var build:Int;
}

typedef GameData = {
	var item_name_to_id:Map<String, Int64>;
	var location_name_to_id:Map<String, Int64>;
	var version:Int;
}

typedef DataPackageObject = {
	var games:Map<String, GameData>;
  var version:Int;
}

typedef NetworkSlot = {
  var name:String;
  var game:String;
  var type:SlotType;
  var ?group_members:Array<Int>;
}

typedef Packet = {
	var cmd:String;
}

// Incoming packets

typedef RoomInfoPacket = {
	var cmd:String;
	var tags:Array<String>;
	var password:Bool;
	var permissions:Map<String, Permission>;
	var hint_cost:Int;
	var location_check_points:Int;
	var players:Array<NetworkPlayer>;
	var games:Array<String>;
	var datapackage_version:Int;
	var datapackage_versions:Map<String, Int>;
	var seed_name:String;
	var time:Float;
}

typedef ConnectionRefusedPacket = {
  var cmd:String;
  var errors:Array<String>;
}

typedef ConnectedPacket = {
  var cmd:String;
  var team:Int;
  var slot:Int;
  var players:Array<NetworkPlayer>;
  var missing_locations:Array<Int64>;
  var checked_locations:Array<Int64>;
  var slot_data:Dynamic;
  var slot_info:Map<Int, NetworkSlot>;
}

typedef ReceivedItemsPacket = {
  var cmd:String;
  var index:Int;
  var items:Array<NetworkItem>;
}

typedef LocationInfoPacket = {
  var cmd:String;
  var locations:Array<NetworkItem>;
}

typedef RoomUpdatePacket = {
  var cmd:String;
  var hint_points:Int;
  var players:Array<NetworkPlayer>;
  var checked_locations:Array<Int64>;
  var missing_locations:Array<Int64>;
}

typedef PrintPacket = {
	var cmd:String;
	var text:String;
}

typedef PrintJsonPacket = {
	var cmd:String;
  var data:Array<JSONMessagePart>;
  var receiving:Int;
  var item:NetworkItem;
  var found:Bool;
}

typedef DataPackagePacket = {
	var cmd:String;
  var data:DataPackageObject;
}

typedef BouncedPacket = {
	var cmd:String;
  var games:Array<String>;
  var slots:Array<Int>;
  var tags:Array<String>;
  var data:Dynamic;
}

typedef RetrievedPacket = {
	var cmd:String;
  var keys:Map<String, Dynamic>;
}

typedef SetReplyPacket = {
	var cmd:String;
  var key:String;
  var value:Dynamic;
  var original_value:Dynamic;
}

enum PacketType {
  RoomInfo(p:RoomInfoPacket);
  ConnectionRefused(p:ConnectionRefusedPacket);
  Connected(p:ConnectedPacket);
  ReceivedItems(p:ReceivedItemsPacket);
  LocationInfo(p:LocationInfoPacket);
  RoomUpdate(p:RoomUpdatePacket);
  Print(p:PrintPacket);
  PrintJSON(p:PrintJsonPacket);
  DataPackage(p:DataPackagePacket);
  Bounced(p:BouncedPacket);
  Retrieved(p:RetrievedPacket);
  SetReply(p:SetReplyPacket);
}

// Outgoing packets

typedef ConnectPacket = {
  var cmd:String;
  var password:String;
  var game:String;
  var name:String;
  var uuid:String;
  var version:Version;
  var items_handling:Int;
  var tags:Array<String>;
}

typedef ConnectUpdatePacket = {
  var cmd:String;
  var ?items_handling:Int;
  var ?tags:Array<String>;
}

// Bounce packets

  typedef DeathLinkBouncePacket = {
    var time:Float;
    var cause:String;
    var source:String;
  }
  

package ap;

import ap.Definitions.ClientStatus;
import haxe.DynamicAccess;

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
	var item:Int;
	var location:Int;
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

// TODO: figure out how to not have to include "class" through Tink library
//@:json({"class": "Version"})
// @:jsonStringify((ver:NetworkVersion) -> {
// 	return {
// 		major: ver.major,
// 		minor: ver.minor,
// 		build: ver.build,
// 		"class": "Version"
// 	};
// })
typedef NetworkVersion = {
	var major:Int;
	var minor:Int;
	var build:Int;
}

typedef GameData = {
	var item_name_to_id:DynamicAccess<Int>;
	var location_name_to_id:DynamicAccess<Int>;
	var version:Int;
}

typedef DataPackageObject = {
	var games:DynamicAccess<GameData>;
	var version:Int;
}

typedef NetworkSlot = {
	var name:String;
	var game:String;
	var type:SlotType;
	var ?group_members:Array<Int>;
}

// Incoming packets

enum IncomingPacket {
	@:json({cmd: "RoomInfo"})
	RoomInfo(
		// HACK: due to how NetworkVersion is sent
		//version:NetworkVersion,
		version:DynamicAccess<Dynamic>,
		tags:Array<String>,
		password:Bool,
		permissions:DynamicAccess<Permission>,
		hint_cost:Int,
		location_check_points:Int,
		games:Array<String>,
		datapackage_version:Int,
		datapackage_versions:DynamicAccess<Int>,
		seed_name:String,
		time:Float
	);

	@:json({cmd: "ConnectionRefused"})
	ConnectionRefused(
		errors:Array<String>
	);

	@:json({cmd: "Connected"})
	Connected(
		team:Int,
		slot:Int,
		players:Array<NetworkPlayer>,
		missing_locations:Array<Int>,
		checked_locations:Array<Int>,
		slot_data:Null<Dynamic>,
		slot_info:DynamicAccess<NetworkSlot>
	);

	@:json({cmd: "ReceivedItems"})
	ReceivedItems(
		index:Int,
		items:Array<NetworkItem>
	);

	@:json({cmd: "LocationInfo"})
	LocationInfo(
		locations:Array<NetworkItem>
	);

	@:json({cmd: "RoomUpdate"})
	RoomUpdate(
		hint_points:Int,
		players:Array<NetworkPlayer>,
		checked_locations:Array<Int>,
		missing_locations:Array<Int>
	);

	@:json({cmd: "Print"})
	Print(
		text:String
	);

	@:json({cmd: "PrintJSON"})
	PrintJSON(
		data:Array<JSONMessagePart>,
		receiving:Int,
		item:NetworkItem,
		found:Bool
		);

	@:json({cmd: "DataPackage"})
	DataPackage(
		data:DataPackageObject
	);

	@:json({cmd: "Bounced"})
	Bounced(
		games:Array<String>,
		slots:Array<Int>,
		tags:Array<String>,
		data:Dynamic
	);

	@:json({cmd: "Retrieved"})
	Retrieved(
		keys:DynamicAccess<Dynamic>
	);

	@:json({cmd: "SetReply"})
	SetReply(
		key:String,
		value:Dynamic,
		original_value:Dynamic
	);

	@:json({cmd: "InvalidPacket"})
	InvalidPacket(
		type:String,
		original_cmd:Null<String>,
		text:String
	);

	Unknown(
		cmd:String
	);
}

// Outgoing packets

enum OutgoingPacket {
	@:json({cmd: "Connect"})
	Connect(
		password:Null<String>,
		game:String,
		name:String,
		uuid:String,
		// HACK: due to how NetworkVersion is sent
		//version:NetworkVersion,
		version:DynamicAccess<Dynamic>,
		items_handling:Int,
		tags:Array<String>
	);

	@:json({cmd: "ConnectUpdate"})
	ConnectUpdate(
		items_handling:Null<Int>,
		tags:Null<Array<String>>
	);

	@:json({cmd: "LocationChecks"})
	LocationChecks(
		locations:Array<Int>
	);

	@:json({cmd: "LocationScouts"})
	LocationScouts(
		locations:Array<Int>
	);

	@:json({cmd: "StatusUpdate"})
	StatusUpdate(
		status:ClientStatus
	);

	@:json({cmd: "Sync"})
	Sync;

	@:json({cmd: "GetDataPackage"})
	GetDataPackage(
		include:Array<String>
	);

	@:json({cmd: "Say"})
	Say(
		text:String
	);
}

// Bounce packets

typedef DeathLinkBouncePacket = {
	var time:Float;
	var cause:String;
	var source:String;
}

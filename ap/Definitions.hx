package ap;

import haxe.Json;
import haxe.Int64;

enum State {
  DISCONNECTED;
  SOCKET_CONNECTING;
  SOCKET_CONNECTED;
  ROOM_INFO;
  SLOT_CONNECTED;
}

enum abstract ClientStatus(Int) {
  var UNKNOWN = 0;
  var READY = 10;
  var PLAYING = 20;
  var GOAL = 30;
}

enum RenderFormat {
  TEXT;
  HTML;
  ANSI;
}

enum abstract ItemFlags(Int) from Int to Int {
  var FLAG_NONE = 0;
  var FLAG_ADVANCEMENT = 1 << 0;
  var FLAG_NEVER_EXCLUDE = 1 << 1;
  var FLAG_TRAP = 1 << 2;
}

typedef NetworkItem = {
  var item:Int64;
  var location:Int64;
  var player:Int;
  var flags:ItemFlags;
  var index:Int;
}

typedef NetworkPlayer = {
  var team:Int;
  var slot:Int;
  var alias:String;
  var name:String;
}

typedef TextNode = {
  var type:String;
  var color:String;
  var text:String;
  var found:Bool;
  var flags:ItemFlags;
}

typedef Version = {
  var major:Int;
  var minor:Int;
  var build:Int;
}

package ap;

@:enum
abstract State(Int) {
	var DISCONNECTED = 0;
	var SOCKET_CONNECTING = 1;
	var SOCKET_CONNECTED = 2;
	var ROOM_INFO = 3;
	var SLOT_CONNECTED = 4;

  @:op(A < B) static function lt(a:State, b:State):Bool;
  @:op(A <= B) static function lte(a:State, b:State):Bool;
  @:op(A > B) static function gt(a:State, b:State):Bool;
  @:op(A >= B) static function gte(a:State, b:State):Bool;
  @:op(A == B) static function eq(a:State, b:State):Bool;
  @:op(A != B) static function ne(a:State, b:State):Bool;
}

@:enum
abstract ClientStatus(Int) {
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


# hxArchipelago

Haxe Archipelago multiworld randomizer client library. See [archipelago.gg](https://archipelago.gg).

This is a port of [apclientpp](https://github.com/black-sliver/apclientpp) by Black-Sliver.

## Prerequisites

- Haxe 4.3.x recommended, 4.2.x should work as well
- If Lime is being used, additional functionality can be accessed (unless `AP_NO_LIME` is defined)

## How to use

- Add dependencies to your project (should be handled automatically by `haxelib`)
  - [hxWebSockets](https://lib.haxe.org/p/hxWebSockets/)
  - [helder.set](https://lib.haxe.org/p/helder.set/)
  - [tink_json](https://lib.haxe.org/p/tink_json/)
  - [haxe-concurrent](https://lib.haxe.org/p/haxe-concurrent/)
- `import ap.Client`
- instantiate hxArchipelago and use its API
  - assign event listeners
  - call `poll` repeatedly (e.g. once per frame) for it to connect and callbacks to fire)
  - use `ConnectSlot` to connect to a slot after RoomInfo
  - use `StatusUpdate`, `LocationChecks` and `LocationScouts` to send status, checks and scouts
  - use `Say` to send a (chat) message
  - use `Bounce` to send a bounce (deathlink, ...)
  - use `Get`, `Set` and `SetNotify` to access data storage api,
    see [Archipelago network protocol](https://github.com/ArchipelagoMW/Archipelago/blob/main/docs/network%20protocol.md#get)
- see [FlixelBumpStik](https://github.com/FelicitusNeko/FlixelBumpStik) for an implementation example
- see [Gotchas](#gotchas)

## Additional Configuration

- if using Lime and you do not want to use Lime events, declare `AP_NO_LIME` in your `build.hxml` or `project.xml` file

## Callbacks

Use `_hOn*` or `on*.add()` to set callbacks.
- if using Lime, call `on*.add()` to add event listeners
- otherwise, assign listeners to `_hOn*` (example: `_hOnSlotConnected = [function...]`)

Because of automatic reconnect, there is no callback for a hard connection error.
If the game has to be connected at all times, it should wait for `SlotConnected` and show an error to the user if that
did not happen within 10 seconds.
Once `SlotConnected` was received, a `SocketError` or `SocketDisconnected` can be used to detect a disconnect.

- SocketConnected `(Void)`: called when the socket gets connected
- SocketError `(String)`: called when connect or a ping failed - no action required, reconnect is automatic.
- SocketDisconnected `(Void)`: called when the socket gets disconnected - no action required, reconnect is automatic.
- RoomInfo `(Void)`: called when the server sent room info. send `ConnectSlot` from this callback.
- SlotConnected `(Dynamic)`: called as reply to `ConnectSlot` when successful. argument is slot data.
- SlotRefused `(Array<String>)`: called as reply to `ConnectSlot` failed. argument is reason.
- SlotDisconnected `(Void)`: currently unused
- ItemsReceived `(Array<NetworkItem>)`: called when receiving items - previously received after connect and new over time
- LocationInfo `(Array<NetworkItem>)`: called as reply to `LocationScouts`
- LocationChecked `(Array<Int>)`: called when a local location was remoetly checked or was already checked when connecting
- DataPackageChanged `(DataPackageObject)`: called when data package (texts) were updated from the server
- Print `(String)`: legacy chat message, no longer present in 0.5.0
- PrintJSON `(Array<JSONMessagePart>)`: colorful chat and server messages. pass arg.data to render_json for text output
- Bounced `(Dynamic)`: broadcasted when a client sends a Bounce
- Retrieved `(DynamicAccess<Dynamic>)`: called as reply to `Get`
  - **NOTE**: This functionality is not currently working due to a code incompatibility.
- SetReply `(String, Dynamic, Dynamic)`: called as reply to `Set` and when value for `SetNotify` changed

## Gotchas

- `poll()` handles both sending outgoing packets, as well as processing incoming packets, so it has to be called repeatedly while hxArchipelago exists.

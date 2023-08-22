package ap;

import haxe.Timer;

class PseudoMutex {
	var curMutex:Null<String> = null;
	var captureCount = 0;

	public function new() {}

	public function acquire(id:String) {
		if (curMutex == null)
			curMutex = id;
		else if (curMutex == id)
			captureCount++;
		else {
			var unlock = false;
			while (!unlock)
				Timer.delay(() -> {
					unlock = tryAcquire(id);
				}, 10);
		}
	}

	public function release(id:String) {
		if (curMutex == id) {
			captureCount--;
			if (captureCount == 0)
				curMutex = null;
		}
	}

	public function tryAcquire(id:String) {
		if (curMutex == null) {
			curMutex = id;
			captureCount = 1;
			return true;
		} else
			return false;
	}
}

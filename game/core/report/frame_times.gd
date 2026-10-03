class_name FrameTimes
extends RefCounted
## Ring buffer of recent frame times for issue reports: average and p99 over the last N seconds.
## The debug overlay feeds it every frame whether or not the overlay is shown.

const CAPACITY := 8192  # 30 s at up to 270 fps

var _ms := PackedFloat32Array()
var _next: int = 0
var _count: int = 0


func _init() -> void:
	_ms.resize(CAPACITY)


## Records one frame.
func push(delta_s: float) -> void:
	_ms[_next] = delta_s * 1000.0
	_next = (_next + 1) % CAPACITY
	_count = mini(_count + 1, CAPACITY)


## {"avg_ms", "p99_ms", "seconds"} over the most recent frames adding up to at most `window_s`.
func stats(window_s: float = 30.0) -> Dictionary:
	var picked := PackedFloat32Array()
	var total := 0.0
	for k in range(_count):
		var ms: float = _ms[(_next - 1 - k + CAPACITY) % CAPACITY]
		if total + ms > window_s * 1000.0 and not picked.is_empty():
			break
		picked.append(ms)
		total += ms
	if picked.is_empty():
		return {"avg_ms": 0.0, "p99_ms": 0.0, "seconds": 0.0}
	picked.sort()
	var p99: float = picked[mini(picked.size() - 1, int(ceil(picked.size() * 0.99)) - 1)]
	return {"avg_ms": snappedf(total / picked.size(), 0.01), "p99_ms": snappedf(p99, 0.01), "seconds": snappedf(total / 1000.0, 0.1)}

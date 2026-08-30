extends RefCounted
class_name RateLimiter
## Token-bucket rate limiter used by the host to bound how often any single peer
## may issue a given class of request.
##
## Two thresholds:
##   * the normal limit - excess requests are silently dropped;
##   * an abuse threshold - a peer that floods far past the limit for a sustained
##     window is reported so the host can disconnect it.
##
## The limiter is intentionally per-(peer, channel) so that a player spamming
## interact cannot starve their own blaster, and one hostile client cannot
## starve anybody else.

var _rate: float
var _burst: float
var _abuse_rate: float
var _abuse_window: float

# peer_id -> { tokens: float, last: float, over: float }
var _buckets: Dictionary = {}


func _init(rate_per_second: float, burst: float = 0.0, abuse_multiplier: float = 0.0, abuse_window: float = 0.0) -> void:
	_rate = maxf(rate_per_second, 0.001)
	_burst = burst if burst > 0.0 else maxf(rate_per_second, 1.0)
	_abuse_rate = _rate * abuse_multiplier
	_abuse_window = abuse_window


## Returns true when the request is allowed. `now` is injectable so tests can
## drive the limiter deterministically instead of sleeping.
func allow(peer_id: int, now: float = -1.0) -> bool:
	if now < 0.0:
		now = Time.get_ticks_msec() / 1000.0
	var b: Dictionary = _buckets.get(peer_id, {"tokens": _burst, "last": now, "over": 0.0})
	var elapsed: float = maxf(now - float(b["last"]), 0.0)
	b["last"] = now
	b["tokens"] = minf(float(b["tokens"]) + elapsed * _rate, _burst)
	# Decay the abuse counter at the abuse rate so honest bursts do not accumulate.
	if _abuse_window > 0.0:
		b["over"] = maxf(float(b["over"]) - elapsed * maxf(_abuse_rate, 1.0), 0.0)

	var allowed := false
	if float(b["tokens"]) >= 1.0:
		b["tokens"] = float(b["tokens"]) - 1.0
		allowed = true
	else:
		b["over"] = float(b["over"]) + 1.0

	_buckets[peer_id] = b
	return allowed


## True when this peer has flooded far enough past the limit that it should be
## treated as hostile or broken rather than merely throttled.
func is_abusive(peer_id: int) -> bool:
	if _abuse_window <= 0.0 or _abuse_rate <= 0.0:
		return false
	var b: Variant = _buckets.get(peer_id)
	if b == null:
		return false
	return float((b as Dictionary)["over"]) >= _abuse_rate * _abuse_window


func forget(peer_id: int) -> void:
	_buckets.erase(peer_id)


func clear() -> void:
	_buckets.clear()


func tracked_peers() -> Array:
	return _buckets.keys()

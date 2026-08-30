extends TestCase
## The token bucket the host uses to bound per-peer request rates.
##
## Time is injected rather than slept, so these run instantly and
## deterministically.


func test_burst_is_allowed_then_throttled() -> void:
	var limiter := RateLimiter.new(4.0, 4.0)
	var allowed := 0
	for i in 10:
		if limiter.allow(2, 0.0):
			allowed += 1
	check_eq(allowed, 4, "the initial burst is exactly the bucket size")


func test_tokens_refill_over_time() -> void:
	var limiter := RateLimiter.new(4.0, 4.0)
	for i in 4:
		limiter.allow(2, 0.0)
	check_false(limiter.allow(2, 0.0), "the bucket is empty")
	check(limiter.allow(2, 0.30), "a token has refilled after 0.3s at 4/s")


func test_peers_are_independent() -> void:
	var limiter := RateLimiter.new(2.0, 2.0)
	limiter.allow(2, 0.0)
	limiter.allow(2, 0.0)
	check_false(limiter.allow(2, 0.0), "peer 2 is exhausted")
	check(limiter.allow(3, 0.0), "peer 3 is unaffected by peer 2")


func test_abuse_detection_needs_sustained_flooding() -> void:
	var limiter := RateLimiter.new(4.0, 4.0, 6.0, 3.0)
	for i in 10:
		limiter.allow(2, 0.0)
	check_false(limiter.is_abusive(2), "a short burst is throttled, not treated as hostile")
	for i in 200:
		limiter.allow(2, 0.0)
	check(limiter.is_abusive(2), "sustained flooding is detected")


func test_abuse_counter_decays() -> void:
	var limiter := RateLimiter.new(4.0, 4.0, 6.0, 3.0)
	for i in 200:
		limiter.allow(2, 0.0)
	check(limiter.is_abusive(2), "flooding registered")
	# A long quiet period must clear the strike so an honest player is not
	# punished for one bad moment.
	limiter.allow(2, 60.0)
	check_false(limiter.is_abusive(2), "the abuse counter decays while quiet")


func test_forget_clears_a_peer() -> void:
	var limiter := RateLimiter.new(2.0, 2.0)
	limiter.allow(9, 0.0)
	limiter.allow(9, 0.0)
	check_false(limiter.allow(9, 0.0), "peer 9 exhausted")
	limiter.forget(9)
	check(limiter.allow(9, 0.0), "a forgotten peer starts fresh")
	check_eq(limiter.tracked_peers().size(), 1, "only the re-added peer is tracked")


func test_no_abuse_thresholds_means_never_abusive() -> void:
	var limiter := RateLimiter.new(1.0, 1.0)
	for i in 500:
		limiter.allow(2, 0.0)
	check_false(limiter.is_abusive(2), "a limiter with no abuse window never reports abuse")

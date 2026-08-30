extends TestCase
## Join codes. These are read aloud over voice chat and typed by hand, so the
## interesting cases are all about human error rather than happy-path encoding.


func test_round_trip_on_the_default_port() -> void:
	for address in ["192.168.1.20", "10.0.0.1", "127.0.0.1", "8.8.8.8", "255.255.255.255", "0.0.0.0"]:
		var code := JoinCode.encode(address, GameConfig.DEFAULT_PORT)
		check_ne(code, "", "%s produces a code" % address)
		var back := JoinCode.decode(code)
		check_allowed(back, "%s decodes" % address)
		check_eq(String(back["address"]), address, "%s survives the round trip" % address)
		check_eq(int(back["port"]), GameConfig.DEFAULT_PORT, "%s keeps the default port" % address)


func test_round_trip_on_a_custom_port() -> void:
	for port in [1, 1024, 7001, 27015, 65535]:
		var code := JoinCode.encode("192.168.4.7", port)
		var back := JoinCode.decode(code)
		check_allowed(back, "port %d decodes" % port)
		check_eq(int(back["port"]), port, "port %d survives the round trip" % port)
		check_eq(String(back["address"]), "192.168.4.7", "the address survives with port %d" % port)


func test_default_port_codes_are_shorter() -> void:
	var short_code := JoinCode.encode("192.168.1.20", GameConfig.DEFAULT_PORT)
	var long_code := JoinCode.encode("192.168.1.20", 27015)
	check_eq(short_code.replace("-", "").length(), 8, "a default-port code is 8 characters")
	check_eq(long_code.replace("-", "").length(), 11, "a custom-port code is 11 characters")


func test_codes_are_grouped_for_reading() -> void:
	var code := JoinCode.encode("192.168.1.20", GameConfig.DEFAULT_PORT)
	check(code.contains("-"), "codes are grouped with a dash")
	check_eq(code.length(), 9, "an 8-character code renders as 4-4")


func test_lowercase_and_spacing_are_forgiven() -> void:
	var code := JoinCode.encode("192.168.1.20", GameConfig.DEFAULT_PORT)
	var variants := [
		code.to_lower(),
		code.replace("-", ""),
		code.replace("-", " "),
		"  " + code + "  ",
		code.replace("-", "_"),
	]
	for variant in variants:
		var back := JoinCode.decode(variant)
		check_allowed(back, "'%s' still decodes" % variant)
		check_eq(String(back["address"]), "192.168.1.20", "'%s' decodes to the right address" % variant)


func test_confusable_characters_are_folded() -> void:
	# The alphabet never contains I, L, O or U, so anyone typing one of those
	# meant the character it resembles. Folding them is the difference between
	# "it works" and "the code is broken" for a code read over voice.
	var code := JoinCode.encode("10.0.0.5", GameConfig.DEFAULT_PORT)
	var mangled := code.replace("0", "O").replace("1", "I")
	var back := JoinCode.decode(mangled)
	check_allowed(back, "O-for-0 and I-for-1 are forgiven")
	check_eq(String(back["address"]), "10.0.0.5", "the folded code still points at the right host")


func test_a_single_character_typo_is_caught() -> void:
	var code := JoinCode.encode("192.168.1.20", GameConfig.DEFAULT_PORT).replace("-", "")
	var caught := 0
	var attempts := 0
	for i in code.length():
		for entry in ["2", "7", "K", "Z"]:
			var replacement := String(entry)
			if code[i] == replacement:
				continue
			attempts += 1
			var typo: String = code.substr(0, i) + replacement + code.substr(i + 1)
			var back := JoinCode.decode(typo)
			# Either the checksum rejects it, or it decodes to a DIFFERENT
			# address - what must never happen is silently reading as the
			# original host.
			if not bool(back["ok"]) or String(back["address"]) != "192.168.1.20":
				caught += 1
	check_eq(caught, attempts, "no single-character typo silently resolves to the original address")


func test_a_transposition_is_caught() -> void:
	# A plain checksum would accept a swapped pair; the weighting exists for
	# exactly this case, because swapping two characters is what people do when
	# reading a code back.
	var code := JoinCode.encode("192.168.1.20", GameConfig.DEFAULT_PORT).replace("-", "")
	var missed := 0
	var swaps := 0
	for i in code.length() - 1:
		if code[i] == code[i + 1]:
			continue
		swaps += 1
		var swapped: String = code.substr(0, i) + code[i + 1] + code[i] + code.substr(i + 2)
		var back := JoinCode.decode(swapped)
		if bool(back["ok"]) and String(back["address"]) == "192.168.1.20":
			missed += 1
	check(swaps > 0, "there were transpositions to test")
	check_eq(missed, 0, "no transposition silently resolves to the original address")


func test_garbage_is_rejected_with_a_readable_reason() -> void:
	for bad in ["", "hello", "ABCD-EF", "ABCD-EFGH-IJKLMNOP", "!!!!-!!!!"]:
		var back := JoinCode.decode(bad)
		check_false(bool(back["ok"]), "'%s' is rejected" % bad)
		check(String(back["reason"]).length() > 10,
			"'%s' is rejected with an explanation, not a blank" % bad)


func test_encode_rejects_what_it_cannot_represent() -> void:
	for bad in ["not-an-ip", "1.2.3", "1.2.3.4.5", "256.1.1.1", "1.-2.3.4", "::1", "1.2.3.a", ""]:
		check_eq(JoinCode.encode(bad, GameConfig.DEFAULT_PORT), "",
			"'%s' cannot be encoded" % bad)
	check_eq(JoinCode.encode("1.2.3.4", 0), "", "port 0 cannot be encoded")
	check_eq(JoinCode.encode("1.2.3.4", 70000), "", "an out-of-range port cannot be encoded")


func test_looks_like_code_distinguishes_from_an_address() -> void:
	var code := JoinCode.encode("192.168.1.20", GameConfig.DEFAULT_PORT)
	check(JoinCode.looks_like_code(code), "a code looks like a code")
	check(JoinCode.looks_like_code(code.to_lower()), "a lowercase code looks like a code")
	check_false(JoinCode.looks_like_code("192.168.1.20"), "an IPv4 address does not")
	check_false(JoinCode.looks_like_code("myhost.local"), "a hostname does not")
	check_false(JoinCode.looks_like_code("::1"), "an IPv6 address does not")
	check_false(JoinCode.looks_like_code(""), "an empty string does not")


func test_private_address_detection() -> void:
	for private in ["192.168.0.1", "10.1.2.3", "172.16.0.1", "172.31.255.255", "127.0.0.1", "169.254.1.1"]:
		check(JoinCode.is_private_address(private), "%s is recognised as local-only" % private)
	for public in ["8.8.8.8", "1.1.1.1", "172.32.0.1", "172.15.0.1", "203.0.113.9"]:
		check_false(JoinCode.is_private_address(public), "%s is not local-only" % public)


func test_ipv4_parsing_edges() -> void:
	check_eq(JoinCode.ipv4_to_int("0.0.0.0"), 0, "0.0.0.0 parses to zero")
	check_eq(JoinCode.ipv4_to_int("255.255.255.255"), 4294967295, "the broadcast address parses")
	check_eq(JoinCode.ipv4_to_int("1.2.3.4"), 16909060, "a known address parses to the known integer")
	check_eq(JoinCode.ipv4_to_int("01.02.03.04"), 16909060, "leading zeroes are tolerated")
	check_eq(JoinCode.ipv4_to_int("1.2.3.4444"), -1, "an over-long octet is rejected")
	check_eq(JoinCode.int_to_ipv4(16909060), "1.2.3.4", "the integer converts back")


func test_session_name_sanitisation() -> void:
	check_eq(LanDiscovery.sanitize_session_name("Star Battle"), "Star Battle", "a plain name survives")
	check_eq(LanDiscovery.sanitize_session_name("  Star   Battle  "), "Star Battle",
		"whitespace is trimmed and collapsed")
	check_eq(LanDiscovery.sanitize_session_name("Star|Battle"), "Star Battle",
		"the field separator cannot appear in a name")
	check_eq(LanDiscovery.sanitize_session_name("Star\nBattle"), "StarBattle",
		"control characters are removed")
	check_eq(LanDiscovery.sanitize_session_name(""), GameConfig.SESSION_NAME_FALLBACK,
		"an empty name falls back")
	check_eq(LanDiscovery.sanitize_session_name("ab"), GameConfig.SESSION_NAME_FALLBACK,
		"a too-short name falls back")
	check(LanDiscovery.sanitize_session_name("X".repeat(80)).length() <= GameConfig.SESSION_NAME_MAX_LENGTH,
		"a long name is clamped")

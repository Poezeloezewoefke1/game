extends TestCase
## Display-name hygiene. Names arrive from the network and land in UI labels and
## log lines, so they are untrusted input.


func test_ordinary_names_survive() -> void:
	check_eq(NameSanitizer.sanitize("Nova", 5), "Nova", "a plain name is unchanged")
	check_eq(NameSanitizer.sanitize("Ada Lovelace", 5), "Ada Lovelace", "an internal space is kept")


func test_whitespace_is_trimmed_and_collapsed() -> void:
	check_eq(NameSanitizer.sanitize("   Nova   ", 5), "Nova", "surrounding whitespace is removed")
	check_eq(NameSanitizer.sanitize("Nova    Prime", 5), "Nova Prime", "runs of spaces collapse")
	check_eq(NameSanitizer.sanitize("\tNova\t", 5), "Nova", "tabs are treated as whitespace")


func test_empty_and_short_names_fall_back_deterministically() -> void:
	check_eq(NameSanitizer.sanitize("", 7), NameSanitizer.fallback_name(7), "an empty name falls back")
	check_eq(NameSanitizer.sanitize("   ", 7), NameSanitizer.fallback_name(7), "whitespace only falls back")
	check_eq(NameSanitizer.sanitize("x", 7), NameSanitizer.fallback_name(7), "a too-short name falls back")
	check_eq(NameSanitizer.sanitize("", 7), NameSanitizer.sanitize("", 7), "the fallback is stable")
	check_ne(NameSanitizer.fallback_name(7), NameSanitizer.fallback_name(8),
		"different peers get different fallbacks")


func test_no_fallback_when_peer_is_zero() -> void:
	check_eq(NameSanitizer.sanitize("", 0), "", "peer 0 means 'tell me it is unusable'")


func test_length_is_capped() -> void:
	var long_name := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var out := NameSanitizer.sanitize(long_name, 5)
	check(out.length() <= GameConfig.NAME_MAX_LENGTH,
		"a long name is capped to %d (got %d)" % [GameConfig.NAME_MAX_LENGTH, out.length()])


func test_control_characters_are_stripped() -> void:
	var dirty := "No" + String.chr(0x07) + "va" + String.chr(0x00 + 1)
	check_eq(NameSanitizer.sanitize(dirty, 5), "Nova", "control characters are removed")
	check_eq(NameSanitizer.sanitize("A\nB\rC", 5), "ABC", "newlines cannot break log lines")
	check_eq(NameSanitizer.sanitize("Nova" + String.chr(0x7F), 5), "Nova", "DEL is removed")


func test_direction_overrides_are_stripped() -> void:
	# U+202E can visually reverse text and spoof another player's name.
	var spoof := "Nova" + String.chr(0x202E) + "xyz"
	var out := NameSanitizer.sanitize(spoof, 5)
	check_false(out.contains(String.chr(0x202E)), "the RTL override is removed")
	check_eq(out, "Novaxyz", "the remaining characters are kept")


func test_zero_width_characters_are_stripped() -> void:
	var sneaky := "No" + String.chr(0x200B) + "va" + String.chr(0xFEFF)
	check_eq(NameSanitizer.sanitize(sneaky, 5), "Nova", "zero-width characters are removed")


func test_markup_escape() -> void:
	check_eq(NameSanitizer.escape_markup("[b]bold[/b]"), "[lb]b]bold[lb]/b]",
		"bracket sequences cannot open BBCode tags")


func test_is_acceptable_matches_sanitize() -> void:
	check(NameSanitizer.is_acceptable("Nova"), "a clean name is acceptable")
	check_false(NameSanitizer.is_acceptable(""), "an empty name is not acceptable")
	check_false(NameSanitizer.is_acceptable("a"), "a one-character name is not acceptable")
	check_false(NameSanitizer.is_acceptable("Nova" + String.chr(0x202E)), "a spoofing name is not acceptable")

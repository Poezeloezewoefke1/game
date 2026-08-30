extends RefCounted
class_name NameSanitizer
## Display-name hygiene.
##
## SECURITY NOTE: a display name is presentation only. It is NEVER an identity.
## Identity is always the multiplayer peer id. Two players may legitimately end
## up with the same display name and nothing in the authority model may depend
## on names being unique.
##
## The sanitizer removes control characters (which can corrupt terminal logs and
## break RichTextLabel parsing), collapses whitespace, enforces length, and
## produces a deterministic fallback so an invalid name can never yield an empty
## or dangerous label.

## Characters that must never survive into a label or a log line.
const _CONTROL_MAX := 0x1F
const _DEL := 0x7F
## Unicode direction-override and zero-width characters: these can be used to
## visually spoof another player's name in the lobby list.
const _FORBIDDEN_CODEPOINTS: PackedInt32Array = [
	0x200B, 0x200C, 0x200D, 0x200E, 0x200F,
	0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
	0x2066, 0x2067, 0x2068, 0x2069,
	0xFEFF,
]


## True when `raw` is acceptable exactly as typed (used by the UI to show a
## validation hint before the player presses Host/Join).
static func is_acceptable(raw: String) -> bool:
	return sanitize(raw, 0) == raw.strip_edges() and sanitize(raw, 0) != ""


## Returns a safe, non-empty display name.
## `peer_id` seeds the deterministic fallback; pass 0 when no fallback is wanted
## (the function then returns "" for unusable input).
static func sanitize(raw: String, peer_id: int) -> String:
	var out := ""
	var previous_was_space := false
	for i in raw.length():
		var c := raw.unicode_at(i)
		if c <= _CONTROL_MAX or c == _DEL:
			continue
		if _FORBIDDEN_CODEPOINTS.has(c):
			continue
		if c == 0x20 or c == 0x09:
			# Collapse runs of whitespace; never allow a leading space.
			if out.is_empty() or previous_was_space:
				continue
			previous_was_space = true
			out += " "
			continue
		previous_was_space = false
		out += String.chr(c)
		if out.length() >= GameConfig.NAME_MAX_LENGTH:
			break

	out = out.strip_edges()
	if out.length() < GameConfig.NAME_MIN_LENGTH:
		if peer_id == 0:
			return ""
		return fallback_name(peer_id)
	return out


## Deterministic fallback so the same peer always renders the same label, on
## every machine, without any negotiation.
static func fallback_name(peer_id: int) -> String:
	return "%s-%d" % [GameConfig.NAME_FALLBACK_PREFIX, abs(peer_id) % 10000]


## Escapes BBCode so a crafted name cannot inject markup into RichTextLabel.
## Plain Label nodes do not need this, but the lobby/HUD may use rich text.
static func escape_markup(text: String) -> String:
	return text.replace("[", "[lb]")

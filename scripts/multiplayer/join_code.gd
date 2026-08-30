extends RefCounted
class_name JoinCode
## Short, typo-tolerant codes that encode an address instead of naming one.
##
## WHAT THIS IS: `NOVA-7K3M` is not a name looked up on a server - it IS the
## address, packed into eight characters. That is what lets it work with no
## infrastructure at all: there is nothing to host, nothing to keep alive, and
## no account to create.
##
## WHAT THIS IS NOT: it does not make an unreachable host reachable. A code for
## a public IP still needs that host to forward the game's UDP port, exactly as
## typing the IP would. Codes remove typing errors, not NAT.
##
## FORMAT
##   32-bit IPv4                          -> 7 payload characters (default port)
##   32-bit IPv4 + 16-bit port            -> 10 payload characters (custom port)
##   plus 1 checksum character            -> 8 or 11 characters total
##   displayed in groups of four          -> NOVA-7K3M / NOVA-7K3M-2XZ
##
## The length itself distinguishes the two forms, so no flag bit is needed.
##
## ALPHABET: Crockford base32 - no I, L, O or U. Those are the characters people
## misread as 1, 1, 0 and V, and a code that is read aloud over voice chat has
## to survive that. Decoding also folds the confusable characters back in, so
## someone who types "O" where the code has "0" still gets through.

const ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

const PAYLOAD_CHARS_DEFAULT_PORT := 7
const PAYLOAD_CHARS_CUSTOM_PORT := 10


## Builds a code for `address`:`port`. Returns "" when the address is not IPv4.
static func encode(address: String, port: int) -> String:
	var ip := ipv4_to_int(address)
	if ip < 0:
		return ""
	var payload := ""
	if port == GameConfig.DEFAULT_PORT:
		payload = _to_base32(ip, PAYLOAD_CHARS_DEFAULT_PORT)
	else:
		if port < 1 or port > 65535:
			return ""
		payload = _to_base32((ip << 16) | port, PAYLOAD_CHARS_CUSTOM_PORT)
	return _group(payload + _checksum_char(payload))


## Parses a code. Returns {"ok": bool, "address": String, "port": int,
## "reason": String}. `reason` is written for a player, not a log file.
static func decode(code: String) -> Dictionary:
	var clean := _normalise(code)
	if clean.is_empty():
		return _fail("Enter a join code or an IP address.")

	var expected_payload := 0
	if clean.length() == PAYLOAD_CHARS_DEFAULT_PORT + 1:
		expected_payload = PAYLOAD_CHARS_DEFAULT_PORT
	elif clean.length() == PAYLOAD_CHARS_CUSTOM_PORT + 1:
		expected_payload = PAYLOAD_CHARS_CUSTOM_PORT
	else:
		return _fail("A join code is 8 or 11 characters; that one is %d." % clean.length())

	var payload := clean.substr(0, expected_payload)
	var given_check := clean.substr(expected_payload, 1)
	if given_check != _checksum_char(payload):
		return _fail("That code has a typo in it - check the characters and try again.")

	var value := _from_base32(payload)
	if value < 0:
		return _fail("That code contains characters a join code never uses.")

	var ip := 0
	var port := GameConfig.DEFAULT_PORT
	if expected_payload == PAYLOAD_CHARS_DEFAULT_PORT:
		ip = value
	else:
		ip = (value >> 16) & 0xFFFFFFFF
		port = value & 0xFFFF
		if port < 1:
			return _fail("That code carries an invalid port.")

	return {"ok": true, "address": int_to_ipv4(ip), "port": port, "reason": ""}


## True when the text looks like a code rather than an address, so the UI can
## accept either in one field without asking the player which they typed.
static func looks_like_code(text: String) -> bool:
	var t := text.strip_edges()
	if t.is_empty():
		return false
	if t.contains(".") or t.contains(":"):
		return false
	var clean := _normalise(t)
	return clean.length() == PAYLOAD_CHARS_DEFAULT_PORT + 1 \
		or clean.length() == PAYLOAD_CHARS_CUSTOM_PORT + 1


## An address in one of the ranges that only works on the local network. The UI
## uses this to say so, rather than letting somebody share a code that cannot
## possibly work for a friend across the internet.
static func is_private_address(address: String) -> bool:
	var ip := ipv4_to_int(address)
	if ip < 0:
		return false
	var a := (ip >> 24) & 0xFF
	var b := (ip >> 16) & 0xFF
	if a == 10 or a == 127:
		return true
	if a == 192 and b == 168:
		return true
	if a == 172 and b >= 16 and b <= 31:
		return true
	if a == 169 and b == 254:
		return true
	return false


# --------------------------------------------------------------------------

## Returns -1 when `address` is not a dotted IPv4 quad.
static func ipv4_to_int(address: String) -> int:
	var parts := address.strip_edges().split(".")
	if parts.size() != 4:
		return -1
	var value := 0
	for part in parts:
		if part.is_empty() or part.length() > 3:
			return -1
		for i in part.length():
			if part.unicode_at(i) < 0x30 or part.unicode_at(i) > 0x39:
				return -1
		var octet := part.to_int()
		if octet < 0 or octet > 255:
			return -1
		value = (value << 8) | octet
	return value


static func int_to_ipv4(value: int) -> String:
	return "%d.%d.%d.%d" % [
		(value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF]


static func _to_base32(value: int, chars: int) -> String:
	var out := ""
	for i in range(chars - 1, -1, -1):
		out += ALPHABET[(value >> (i * 5)) & 31]
	return out


## Returns -1 if any character is outside the alphabet.
static func _from_base32(text: String) -> int:
	var value := 0
	for i in text.length():
		var index := ALPHABET.find(text[i])
		if index < 0:
			return -1
		value = (value << 5) | index
	return value


## Position-weighted so a transposition changes the result. A plain sum would
## accept "7K3M" typed as "K73M", which is exactly the mistake people make when
## reading a code back over voice.
static func _checksum_char(payload: String) -> String:
	var total := 0
	for i in payload.length():
		var index := ALPHABET.find(payload[i])
		if index < 0:
			return "0"
		total += (i + 1) * (index + 1)
	return ALPHABET[total % 32]


## Uppercases, strips separators, and folds the characters people confuse.
static func _normalise(code: String) -> String:
	var out := ""
	var upper := code.strip_edges().to_upper()
	for i in upper.length():
		var c := upper[i]
		match c:
			"-", " ", "_", ".", ",": continue
			"I", "L": out += "1"
			"O": out += "0"
			"U": out += "V"
			_: out += c
	return out


static func _group(text: String) -> String:
	var out := ""
	for i in text.length():
		if i > 0 and i % 4 == 0:
			out += "-"
		out += text[i]
	return out


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "address": "", "port": 0, "reason": reason}

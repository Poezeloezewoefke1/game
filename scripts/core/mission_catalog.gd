extends RefCounted
class_name MissionCatalog
## The destinations the Starfarer can fly to, as DATA.
##
## Adding a planet should mean adding an entry here and authoring a scene - not
## touching the state machine, the terminal, the HUD or GameManager. Everything
## in this file is static and side-effect free, so the unlock rules and the
## catalog's own integrity are directly unit-testable.
##
## WHY THE CRYSTAL IDS LOOK LIKE NERAVA
## `crystal_ruins`, `crystal_cave` and `crystal_grove` are SLOT ids, not place
## names. They were named after Nerava's layout when it was the only world, and
## they are baked into every level scene and half the test suite, so renaming
## them would be churn with no gain. Each mission supplies its own display names
## for the three slots below; nothing outside this file should ever show a raw
## crystal id to a player.

const NERAVA := "nerava"
const CINDER := "cinder"
const HALLOW := "hallow"

## Hazard applied to the whole surface. "none" costs nothing; the others tick
## damage unless the crew shuts the source down. See scripts/world/hazard_field.
const HAZARD_NONE := "none"
const HAZARD_HEAT := "heat"
const HAZARD_COLD := "cold"

## Scene keys are literals rather than GameConfig references because this is a
## `const` and a const initialiser cannot touch an autoload. A unit test asserts
## every key here resolves in GameConfig.SCENE_PATHS, which is the check that
## makes the duplication safe.
const MISSIONS: Dictionary = {
	NERAVA: {
		"order": 0,
		"name": "Nerava",
		"tagline": "Jungle world. The source of the signal.",
		"scene": "nerava",
		"threat": 1,
		"hazard": HAZARD_NONE,
		"brief": "The signal originates here. Recover the Star Map from the temple.",
		"crystal_names": {
			"crystal_ruins": "Ruins Crystal",
			"crystal_cave": "Cave Crystal",
			"crystal_grove": "Grove Crystal",
		},
	},
	CINDER: {
		"order": 1,
		"name": "Cinder",
		"tagline": "Volcanic. The ash never settles.",
		"scene": "cinder",
		"threat": 2,
		"hazard": HAZARD_HEAT,
		"brief": "A second altar under the ash flats. The ground itself will burn you.",
		"crystal_names": {
			"crystal_ruins": "Slag Crystal",
			"crystal_cave": "Magma Crystal",
			"crystal_grove": "Ashfall Crystal",
		},
	},
	HALLOW: {
		"order": 2,
		"name": "Hallow",
		"tagline": "Frozen. Something walked here before you.",
		"scene": "hallow",
		"threat": 3,
		"hazard": HAZARD_COLD,
		"brief": "The last altar. The cold is the least of what is waiting.",
		"crystal_names": {
			"crystal_ruins": "Rime Crystal",
			"crystal_cave": "Deepshaft Crystal",
			"crystal_grove": "Hollow Crystal",
		},
	},
}


## Mission ids in flight order. Sorted by "order" rather than by Dictionary
## insertion, so a hand edit that reorders the literal cannot silently reorder
## the campaign.
static func ids() -> Array:
	var out: Array = MISSIONS.keys()
	out.sort_custom(func(a, b): return int(MISSIONS[a]["order"]) < int(MISSIONS[b]["order"]))
	return out


static func has_mission(id: String) -> bool:
	return MISSIONS.has(id)


static func first_id() -> String:
	var all := ids()
	return String(all[0]) if not all.is_empty() else ""


static func field(id: String, key: String, fallback: Variant = "") -> Variant:
	var m: Variant = MISSIONS.get(id)
	if m == null:
		return fallback
	return (m as Dictionary).get(key, fallback)


static func display_name(id: String) -> String:
	return String(field(id, "name", id))


static func tagline(id: String) -> String:
	return String(field(id, "tagline", ""))


static func brief(id: String) -> String:
	return String(field(id, "brief", ""))


static func scene_key(id: String) -> String:
	return String(field(id, "scene", ""))


static func hazard(id: String) -> String:
	return String(field(id, "hazard", HAZARD_NONE))


static func threat(id: String) -> int:
	return int(field(id, "threat", 1))


## What this mission calls one of the three crystal slots. Falls back to the id
## itself, which is ugly on screen but is never silently wrong.
static func crystal_label(mission_id: String, crystal_id: String) -> String:
	var names: Variant = field(mission_id, "crystal_names", {})
	return String((names as Dictionary).get(crystal_id, crystal_id))


## A mission is flyable when every mission before it in the order is done. The
## first one is always flyable, including on a fresh save with nothing recorded.
static func is_unlocked(id: String, completed: Array) -> bool:
	if not has_mission(id):
		return false
	var order := int(field(id, "order", 0))
	for other in MISSIONS:
		if int(MISSIONS[other]["order"]) < order and not completed.has(other):
			return false
	return true


## The next mission the crew has not finished, or "" when the campaign is over.
static func next_unfinished(completed: Array) -> String:
	for id in ids():
		if not completed.has(id):
			return String(id)
	return ""


static func unlocked_ids(completed: Array) -> Array:
	var out: Array = []
	for id in ids():
		if is_unlocked(String(id), completed):
			out.append(id)
	return out

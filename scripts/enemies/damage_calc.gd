class_name DamageCalc
extends RefCounted
## Central damage resolution. Kept pure and static so it is directly unit-testable.

const MIN_DAMAGE_FRACTION := 0.10   # armor can never reduce a hit below this fraction of its raw value

## damage_type multipliers vs. special defences (mirrors data/characters/weapons_catalog.json)
const TYPE_TABLE := {
	"melee": {"vs_shield": 1.0, "vs_structure": 0.7, "ignores_armor": false},
	"ranged": {"vs_shield": 0.65, "vs_structure": 0.4, "ignores_armor": false},
	"explosive": {"vs_shield": 1.3, "vs_structure": 1.5, "ignores_armor": false},
	"magic": {"vs_shield": 1.0, "vs_structure": 0.5, "ignores_armor": false},
	"true": {"vs_shield": 1.0, "vs_structure": 1.0, "ignores_armor": true},
}

## Core formula.
##   armor_pct   0..1 fraction of damage the gear removes
##   armor_pen   0..1 fraction of the target's armor that is ignored
##   Damage never falls below MIN_DAMAGE_FRACTION of the raw value, so a maxed-armor enemy is
##   always killable and chip damage never rounds to nothing.
static func apply_armor(raw: float, armor_pct: float, armor_pen: float) -> float:
	var effective_armor: float = clampf(armor_pct, 0.0, 0.95) * (1.0 - clampf(armor_pen, 0.0, 1.0))
	var out := raw * (1.0 - effective_armor)
	return maxf(out, raw * MIN_DAMAGE_FRACTION)

## Full resolution including damage type, crits and target defences.
## target: {"armor_pct": float, "is_structure": bool, "blocks_projectiles": bool}
static func resolve(raw: float, damage_type: String, armor_pen: float, target: Dictionary,
		crit_chance: float = 0.0, crit_mult: float = 2.0, rng_roll: float = 1.0) -> Dictionary:
	var table: Dictionary = TYPE_TABLE.get(damage_type, TYPE_TABLE["melee"])
	var dmg := raw
	var crit := false
	if crit_chance > 0.0 and rng_roll < crit_chance:
		dmg *= crit_mult
		crit = true
	if target.get("blocks_projectiles", false):
		dmg *= float(table["vs_shield"])
	if target.get("is_structure", false):
		dmg *= float(table["vs_structure"])
	if not bool(table["ignores_armor"]):
		dmg = apply_armor(dmg, float(target.get("armor_pct", 0.0)), armor_pen)
	return {"damage": dmg, "crit": crit}

## Splash falloff: full damage at the centre, `min_fraction` at the rim.
static func splash_falloff(distance: float, radius: float, min_fraction: float = 0.4) -> float:
	if radius <= 0.0:
		return 1.0 if distance <= 0.0 else 0.0
	var t: float = clampf(distance / radius, 0.0, 1.0)
	return lerpf(1.0, min_fraction, t)

## Mace bonus: damage scales with the height the attacker struck from (Density-style).
static func mace_height_bonus(height_delta: float, per_unit: float = 0.35, cap: float = 2.5) -> float:
	return clampf(1.0 + maxf(0.0, height_delta) * per_unit, 1.0, cap)

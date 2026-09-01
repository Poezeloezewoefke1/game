@tool
extends Node3D
class_name PropScatter
## Deterministic set dressing.
##
## NOT procedural generation: the layout, the routes and every gameplay object
## are hand-placed, and this changes none of them. It fills authored regions
## with rocks and foliage from a FIXED seed, so the level is byte-identical on
## every launch and on every machine - which also means it cannot desynchronise
## between host and client, and cannot move a rock into a doorway on one
## player's screen and not another's.
##
## It exists because the canyon and the three side paths were correct, walkable
## and completely empty, which is most of why they read as grey corridors rather
## than places.

enum Kind { ROCK, BOULDER, FOLIAGE, RUBBLE, CRYSTAL_SHARD }

@export var kind: Kind = Kind.ROCK:
	set(value):
		kind = value
		_rebuild()

## How many props to place. Kept low on purpose - this is dressing, not a forest.
@export var count: int = 12:
	set(value):
		count = maxi(value, 0)
		_rebuild()

## The box, centred on this node, that props are placed inside.
@export var region: Vector3 = Vector3(20.0, 0.0, 20.0):
	set(value):
		region = value
		_rebuild()

## Change this to reshuffle the arrangement. Same seed, same level, always.
@export var seed_value: int = 1:
	set(value):
		seed_value = value
		_rebuild()

@export var min_scale: float = 0.6:
	set(value):
		min_scale = value
		_rebuild()

@export var max_scale: float = 1.6:
	set(value):
		max_scale = value
		_rebuild()

## Props nearer than this to the region's centre line are skipped, so scatter
## can line a corridor without blocking the middle of it.
@export var clear_radius: float = 0.0:
	set(value):
		clear_radius = value
		_rebuild()


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	ModelKit.clear(self)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + int(kind)

	for i in count:
		var local := Vector3(
			rng.randf_range(-region.x, region.x) * 0.5,
			0.0,
			rng.randf_range(-region.z, region.z) * 0.5)
		if clear_radius > 0.0 and Vector2(local.x, local.z).length() < clear_radius:
			continue

		var scale_value := rng.randf_range(min_scale, max_scale)
		var yaw := rng.randf_range(0.0, 360.0)
		var instance := _make(rng, scale_value)
		if instance == null:
			continue
		instance.position = local + Vector3(0.0, _sink(scale_value), 0.0)
		instance.rotation_degrees = Vector3(
			rng.randf_range(-8.0, 8.0), yaw, rng.randf_range(-8.0, 8.0))


## Props are pushed slightly into the ground so they read as embedded rather
## than resting on a flat plane like game pieces on a board.
func _sink(scale_value: float) -> float:
	match kind:
		Kind.FOLIAGE: return scale_value * 0.5
		Kind.RUBBLE: return -scale_value * 0.12
		_: return -scale_value * 0.18


func _make(rng: RandomNumberGenerator, scale_value: float) -> MeshInstance3D:
	var variant := rng.randi_range(0, 9999)
	match kind:
		Kind.ROCK:
			return ModelKit.part(self,
				MeshFactory.rock(Vector3.ONE * scale_value, variant),
				Vector3.ZERO, Color(0.40, 0.36, 0.32), 0.05, 0.94)
		Kind.BOULDER:
			return ModelKit.part(self,
				MeshFactory.rock(Vector3(1.4, 1.1, 1.3) * scale_value, variant, 6, 8),
				Vector3.ZERO, Color(0.31, 0.29, 0.27), 0.05, 0.96)
		Kind.FOLIAGE:
			return ModelKit.part(self,
				MeshFactory.rock(Vector3(1.2, 1.5, 1.2) * scale_value, variant, 4, 6),
				Vector3.ZERO, Color(0.14, 0.33, 0.19), 0.0, 0.9)
		Kind.RUBBLE:
			return ModelKit.part(self,
				MeshFactory.beveled_box(
					Vector3(scale_value * 1.2, scale_value * 0.35, scale_value * 0.9), 0.05),
				Vector3.ZERO, Color(0.44, 0.41, 0.36), 0.05, 0.92)
		Kind.CRYSTAL_SHARD:
			var shard := ModelKit.emissive(self,
				MeshFactory.crystal(scale_value * 0.9, scale_value * 0.16, 5),
				Vector3.ZERO, Color(0.35, 0.72, 1.0), 0.7)
			return shard
	return null

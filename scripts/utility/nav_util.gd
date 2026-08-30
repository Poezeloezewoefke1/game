extends RefCounted
class_name NavUtil
## Deciding when a NavigationMap is actually usable.
##
## THE TRAP: the widely-copied recipe is `await get_tree().physics_frame` and,
## a little better, "wait until map_get_iteration_id() > 0". Both are wrong once
## a level can be entered more than once. The iteration id belongs to the MAP,
## not to the region, and it is already non-zero from the previous visit - so
## the check passes instantly while the freshly baked mesh has not been
## committed yet, and the first path query silently returns nothing.
##
## The only reliable answer is to ask the map a real question and see whether it
## can answer it.


## True when the map holds at least one region AND can actually produce a path
## near `near`. `near` should be somewhere the caller cares about, because a map
## can be live while the specific area is still unbaked.
static func is_map_usable(map: RID, near: Vector3) -> bool:
	if not map.is_valid():
		return false
	if NavigationServer3D.map_get_regions(map).is_empty():
		return false
	var probe := NavigationServer3D.map_get_path(map, near, near + Vector3(2.0, 0.0, 0.0), true)
	return probe.size() > 0


## Waits until the map is usable. Returns false if it never became usable within
## `max_physics_frames`, so the caller can fall back rather than hang.
static func await_map_usable(tree: SceneTree, map: RID, near: Vector3,
		max_physics_frames: int = 240) -> bool:
	for i in max_physics_frames:
		if is_map_usable(map, near):
			return true
		await tree.physics_frame
	return is_map_usable(map, near)

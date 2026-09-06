class_name MapPath
extends RefCounted
## A polyline the enemies walk along, with cumulative arc lengths for O(log n) sampling.
## Distances are in world units from the entrance (0) to the base (total_length).

var points: PackedVector3Array = PackedVector3Array()
var cumulative: PackedFloat32Array = PackedFloat32Array()
var tangents: PackedVector3Array = PackedVector3Array()
var normals: PackedVector3Array = PackedVector3Array()   # left-hand lateral direction per segment
var total_length: float = 0.0
var id: String = "main"

func build(pts: PackedVector3Array) -> void:
	points = pts
	cumulative = PackedFloat32Array()
	tangents = PackedVector3Array()
	normals = PackedVector3Array()
	cumulative.resize(points.size())
	var acc := 0.0
	cumulative[0] = 0.0
	for i in range(points.size() - 1):
		var seg: Vector3 = points[i + 1] - points[i]
		var t: Vector3 = seg.normalized()
		tangents.push_back(t)
		normals.push_back(Vector3(-t.z, 0.0, t.x).normalized())
		acc += seg.length()
		cumulative[i + 1] = acc
	if tangents.size() > 0:
		tangents.push_back(tangents[tangents.size() - 1])
		normals.push_back(normals[normals.size() - 1])
	total_length = acc

## Index of the segment containing `distance`.
func segment_at(distance: float) -> int:
	var lo := 0
	var hi := cumulative.size() - 1
	if distance <= 0.0:
		return 0
	if distance >= total_length:
		return max(0, cumulative.size() - 2)
	while lo < hi - 1:
		var mid := (lo + hi) >> 1
		if cumulative[mid] <= distance:
			lo = mid
		else:
			hi = mid
	return lo

func position_at(distance: float) -> Vector3:
	if points.size() < 2:
		return points[0] if points.size() == 1 else Vector3.ZERO
	var d: float = clampf(distance, 0.0, total_length)
	var i := segment_at(d)
	var seg_len: float = cumulative[i + 1] - cumulative[i]
	var t: float = 0.0 if seg_len <= 0.0001 else (d - cumulative[i]) / seg_len
	return points[i].lerp(points[i + 1], t)

func tangent_at(distance: float) -> Vector3:
	if tangents.is_empty():
		return Vector3.FORWARD
	return tangents[segment_at(clampf(distance, 0.0, total_length))]

func normal_at(distance: float) -> Vector3:
	if normals.is_empty():
		return Vector3.RIGHT
	return normals[segment_at(clampf(distance, 0.0, total_length))]

## Position including a lateral offset (used to spread a column across the road width).
func position_offset(distance: float, lateral: float) -> Vector3:
	return position_at(distance) + normal_at(distance) * lateral

## Distance ranges where the path passes within `radius` of `center` (XZ only).
## Towers use this to convert a circular range into distance intervals for fast enemy queries.
func ranges_within(center: Vector3, radius: float, step: float = 0.5) -> Array:
	var out: Array = []
	var r2 := radius * radius
	var inside := false
	var start := 0.0
	var d := 0.0
	while d <= total_length:
		var p := position_at(d)
		var dx := p.x - center.x
		var dz := p.z - center.z
		var inside_now := (dx * dx + dz * dz) <= r2
		if inside_now and not inside:
			start = d
			inside = true
		elif not inside_now and inside:
			out.append(Vector2(start, d))
			inside = false
		d += step
	if inside:
		out.append(Vector2(start, total_length))
	return out

func nearest_distance_to(point: Vector3, step: float = 0.5) -> float:
	var best := 0.0
	var best_d2 := INF
	var d := 0.0
	while d <= total_length:
		var p := position_at(d)
		var d2 := p.distance_squared_to(point)
		if d2 < best_d2:
			best_d2 = d2
			best = d
		d += step
	return best

func min_distance_to(point: Vector3, step: float = 0.5) -> float:
	return position_at(nearest_distance_to(point, step)).distance_to(point)

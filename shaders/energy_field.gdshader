shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// The altar's beam and any shield or containment field.
//
// Hexagonal cells that brighten along their borders, drifting across the
// surface, with the whole thing strongest edge-on. The hex grid is what makes
// it read as an engineered field rather than as fog: a soft glow could be
// anything, a cell structure could only have been built.

uniform vec3 colour : source_color = vec3(0.40, 0.85, 1.0);
uniform float energy : hint_range(0.0, 8.0) = 1.6;
uniform float cell_scale : hint_range(1.0, 60.0) = 14.0;
uniform float drift_speed : hint_range(0.0, 3.0) = 0.35;
uniform float edge_width : hint_range(0.01, 0.5) = 0.12;
uniform float fresnel_power : hint_range(0.2, 8.0) = 2.2;
uniform float base_alpha : hint_range(0.0, 1.0) = 0.14;

varying vec3 world_position;

// Distance to the nearest hexagon border, in a unit-hex tiling.
float hex_edge(vec2 p) {
	const vec2 s = vec2(1.0, 1.7320508);
	vec2 a = mod(p, s) - s * 0.5;
	vec2 b = mod(p - s * 0.5, s) - s * 0.5;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	// Distance to the hex boundary from the cell centre.
	float d = max(abs(g.y) * 0.8660254 + abs(g.x) * 0.5, abs(g.x));
	return d;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - facing, fresnel_power);

	vec2 p = world_position.xz * cell_scale + vec2(0.0, TIME * drift_speed);
	// A second, offset layer at a different rate, so the pattern never repeats
	// visibly and the field looks like it is being maintained.
	float d1 = hex_edge(p);
	float d2 = hex_edge(p * 0.61 + vec2(TIME * drift_speed * 0.4, 0.0));
	float cells = smoothstep(0.5 - edge_width, 0.5, d1)
		+ 0.5 * smoothstep(0.5 - edge_width * 1.6, 0.5, d2);

	// A pulse travelling up the field.
	float sweep = smoothstep(0.0, 0.15,
		abs(fract(world_position.y * 0.22 - TIME * 0.35) - 0.5) * 2.0 - 0.7);

	float intensity = base_alpha + cells * 0.55 + rim * 0.9 + sweep * 0.5;
	ALBEDO = vec3(0.0);
	EMISSION = colour * energy * intensity;
	ALPHA = clamp(intensity * 0.85, 0.0, 1.0);
}

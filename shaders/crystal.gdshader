shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

// The Power Crystals and the altar's caged shards.
//
// A crystal is a hard case for a standard material: the thing that makes one
// read as crystal rather than as coloured plastic is that it is BRIGHTER AT THE
// EDGES than in the middle, because you are looking through more of it. That is
// a Fresnel term, and no amount of emission tuning on a plain material gets
// there. On top of that:
//
//  - light moves inside it, on a slow vertical scroll, so it is alive when the
//    player is standing still;
//  - it pulses, slightly, and out of phase with its own inner banding, so the
//    pulse does not look like a global brightness slider;
//  - the facets keep hard shading, because the whole model is flat shaded and
//    smoothing it here would fight the silhouette.

uniform vec3 core_colour : source_color = vec3(0.35, 0.72, 1.0);
uniform vec3 edge_colour : source_color = vec3(0.85, 0.97, 1.0);
uniform float emission_energy : hint_range(0.0, 6.0) = 1.1;
uniform float fresnel_power : hint_range(0.5, 8.0) = 2.6;
uniform float flow_speed : hint_range(0.0, 4.0) = 0.55;
uniform float pulse_speed : hint_range(0.0, 6.0) = 1.3;
uniform float pulse_depth : hint_range(0.0, 1.0) = 0.22;
uniform float band_scale : hint_range(0.5, 40.0) = 9.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.12;

varying vec3 local_position;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	return fract((p + p) * p);
}

float noise11(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash11(i), hash11(i + 1.0), f);
}

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	// Fresnel against the view direction. NORMAL and VIEW are both in view
	// space here, which is why this is a dot of the two rather than of a world
	// normal and a camera vector.
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - facing, fresnel_power);

	// Internal banding, scrolling upward through the crystal's own space so it
	// keeps flowing when the crystal spins.
	float bands = sin(local_position.y * band_scale - TIME * flow_speed * 3.0) * 0.5 + 0.5;
	bands = mix(bands, noise11(local_position.y * band_scale * 0.5 + TIME * flow_speed), 0.4);

	// The pulse is deliberately not a clean sine: a slow sine plus a slower
	// noise reads as something charged rather than as a blinking light.
	float pulse = 1.0 + pulse_depth * (sin(TIME * pulse_speed) * 0.6
		+ (noise11(TIME * pulse_speed * 0.37) - 0.5) * 0.8);

	vec3 inner = mix(core_colour, edge_colour, bands * 0.45);
	vec3 lit = mix(inner, edge_colour, rim);

	ALBEDO = core_colour * 0.35;
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
	SPECULAR = 0.85;
	// Edges glow hardest; the body glows enough to light its own facets.
	EMISSION = lit * emission_energy * pulse * (0.35 + rim * 1.5 + bands * 0.35);
	RIM = 0.6;
	RIM_TINT = 0.4;
}

shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// The Star Map, and anything else that should read as projected light rather
// than as an object.
//
// Additive and depth-write-off, so it never occludes what is behind it - a
// hologram that hides the wall it is in front of instantly reads as solid. The
// scanlines run in WORLD space, not UV space, so they stay put as the armillary
// turns instead of swimming with the geometry, which is the tell that separates
// a projection from a striped texture.

uniform vec3 colour : source_color = vec3(0.45, 0.85, 1.0);
uniform float energy : hint_range(0.0, 6.0) = 1.4;
uniform float scan_frequency : hint_range(1.0, 400.0) = 90.0;
uniform float scan_speed : hint_range(0.0, 8.0) = 1.6;
uniform float scan_depth : hint_range(0.0, 1.0) = 0.45;
uniform float fresnel_power : hint_range(0.2, 8.0) = 1.6;
uniform float flicker_amount : hint_range(0.0, 1.0) = 0.12;
uniform float glitch_rate : hint_range(0.0, 20.0) = 6.0;
uniform float glitch_amount : hint_range(0.0, 0.4) = 0.05;

varying vec3 world_position;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	return fract((p + p) * p);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Occasional horizontal tear, held for a few frames at a time rather than
	// jittering every frame - a continuous wobble reads as a broken shader.
	float slot = floor(TIME * glitch_rate);
	if (hash11(slot) > 0.86) {
		float band = step(0.5, fract(world_position.y * 6.0 + hash11(slot + 1.0) * 10.0));
		VERTEX.x += (hash11(slot + 2.0) - 0.5) * glitch_amount * band;
	}
}

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - facing, fresnel_power);

	float scan = sin(world_position.y * scan_frequency - TIME * scan_speed * 10.0) * 0.5 + 0.5;
	scan = mix(1.0, scan, scan_depth);

	// Two flickers at different rates, so the brightness never settles into a
	// visible loop.
	float flicker = 1.0 - flicker_amount
		* (hash11(floor(TIME * 24.0)) * 0.6 + hash11(floor(TIME * 7.3)) * 0.4);

	ALBEDO = vec3(0.0);
	EMISSION = colour * energy * scan * flicker * (0.30 + rim * 1.25);
	ALPHA = clamp((0.25 + rim * 0.85) * scan * flicker, 0.0, 1.0);
}

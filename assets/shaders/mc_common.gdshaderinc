// Shared helpers for Minecraft-style character shaders. Pure functions only (no built-ins).
// Vertex attributes (see MCMeshBuilder):
//   CUSTOM0 = (part_id, use_vertex_color, enchant_glint, 0)
//   CUSTOM1 = (pivot.xyz, 0)
// Per-instance (MultiMesh custom data): (walk_phase, flash, ghost, swing_amplitude)

uniform sampler2D skin_tex : source_color, filter_nearest, repeat_disable;
uniform sampler2D armor_tex : source_color, filter_nearest, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float ghost : hint_range(0.0, 1.0) = 0.0;
uniform float anim_enabled = 0.0;
uniform float walk_phase = 0.0;
uniform float swing_amplitude = 0.0;
uniform float glint_strength = 1.0;
uniform float emission_boost = 0.0;
uniform vec4 emission_color : source_color = vec4(1.0, 0.5, 0.1, 1.0);

varying float v_use_color;
varying float v_glint;
varying float v_flash;
varying float v_ghost;

mat3 mc_rot_x(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, c, s), vec3(0.0, -s, c));
}

// Returns the limb swing angle for a part id given a walk phase and amplitude.
float mc_limb_angle(float part, float phase, float amp) {
	float swing = sin(phase * 6.2831853) * amp;
	if (part == 2.0 || part == 6.0) { return swing; }
	if (part == 3.0) { return -swing; }
	if (part == 4.0) { return -swing; }
	if (part == 5.0) { return swing; }
	return 0.0;
}

// Animates a vertex/normal pair around its pivot.
void mc_animate(inout vec3 vert, inout vec3 nrm, float part, vec3 pivot, float phase, float amp) {
	float ang = mc_limb_angle(part, phase, amp);
	if (abs(ang) > 0.0001) {
		mat3 r = mc_rot_x(ang);
		vert = r * (vert - pivot) + pivot;
		nrm = r * nrm;
	}
	vert.y += abs(sin(phase * 6.2831853 * 2.0)) * 0.02 * amp;
}

// Computes albedo / emission / alpha from the sampled textures and vertex data.
void mc_shade(vec2 uv, vec4 vcol, float use_color, float glint, float flash_v, float time,
		out vec3 albedo, out vec3 emission, out float alpha) {
	vec4 tex = texture(skin_tex, uv);
	vec4 pat = texture(armor_tex, uv);
	vec3 base = mix(tex.rgb, vcol.rgb * pat.rgb, use_color);
	alpha = mix(tex.a, 1.0, use_color);
	vec3 col = base * tint.rgb;
	col = mix(col, vec3(1.0, 0.35, 0.3), flash_v);
	albedo = col;
	vec3 em = emission_color.rgb * emission_boost;
	if (glint > 0.5) {
		float stripe = sin((uv.x + uv.y) * 40.0 + time * 3.0) * 0.5 + 0.5;
		stripe = smoothstep(0.55, 1.0, stripe);
		em += vec3(0.65, 0.3, 0.95) * stripe * 0.7 * glint_strength;
	}
	emission = em;
}

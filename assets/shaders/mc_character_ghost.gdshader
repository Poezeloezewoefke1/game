// Transparent variant for invisible / ghosted characters (Invisible Mafia style enemies, placement previews).
shader_type spatial;
render_mode cull_back, blend_mix, depth_prepass_alpha, diffuse_lambert, specular_disabled;

#include "res://assets/shaders/mc_common.gdshaderinc"

void vertex() {
	v_use_color = CUSTOM0.y;
	v_glint = CUSTOM0.z;
	float phase = walk_phase;
	float amp = swing_amplitude;
	float f = flash;
	float g = ghost;
	if (anim_enabled > 0.5) {
		phase = INSTANCE_CUSTOM.x;
		f = max(f, INSTANCE_CUSTOM.y);
		g = max(g, INSTANCE_CUSTOM.z);
		amp = INSTANCE_CUSTOM.w;
	}
	if (amp > 0.0001) {
		vec3 v = VERTEX;
		vec3 n = NORMAL;
		mc_animate(v, n, CUSTOM0.x, CUSTOM1.xyz, phase, amp);
		VERTEX = v;
		NORMAL = n;
	}
	v_flash = f;
	v_ghost = g;
}

void fragment() {
	vec3 albedo;
	vec3 emission;
	float alpha;
	mc_shade(UV, COLOR, v_use_color, v_glint, v_flash, TIME, albedo, emission, alpha);
	if (alpha < 0.5) {
		discard;
	}
	ALBEDO = albedo;
	EMISSION = emission + vec3(0.2, 0.3, 0.4) * v_ghost;
	ROUGHNESS = 0.85;
	METALLIC = 0.0;
	ALPHA = alpha * (1.0 - v_ghost * 0.75);
}

// Opaque (alpha-scissor) Minecraft-style character shader. Used for heroes, towers, enemies, bosses.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_lambert, specular_disabled;

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
	ALBEDO = albedo;
	EMISSION = emission;
	ROUGHNESS = 0.85;
	METALLIC = 0.0;
	ALPHA = alpha;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}

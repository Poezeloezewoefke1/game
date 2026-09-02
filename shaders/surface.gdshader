shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// The surface shader every piece of level geometry uses.
//
// FOUR THINGS IT DOES THAT A PLAIN MATERIAL CANNOT:
//
// 1. WORLD-SPACE TRIPLANAR. The level is built from generated boxes with no
//    authored UVs, so any ordinary mapping either stretches across a 34 m floor
//    or restarts at every block edge. Projecting from world space instead means
//    the texture is continuous ACROSS blocks: a wall meeting a floor shares the
//    grain, and no seam appears where two boxes touch.
//
// 2. SLOPE BLENDING. A second material is laid over the first on near-flat
//    upward faces - dust settling on ledges, litter on the ground - with the
//    blend driven by the world normal. One texture used everywhere is the
//    single biggest giveaway that a scene is untextured.
//
// 3. A DETAIL NORMAL at a much higher tiling rate, faded in close to the
//    camera. A 512 px base map is smooth mush from a metre away; this is what
//    keeps a surface reading as a material when a player walks into it.
//
// 4. MACRO VARIATION. A very low frequency tint drift, so the eye stops seeing
//    the base map repeat across a large slab.
//
// The palette colour still drives everything through `tint`, so the existing
// level files keep working and the art direction is unchanged.

group_uniforms Base;
uniform vec3 tint : source_color = vec3(0.5, 0.5, 0.5);
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_map : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D metallic_map : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float texture_scale : hint_range(0.02, 2.0) = 0.28;
uniform float normal_strength : hint_range(0.0, 3.0) = 1.0;
uniform float roughness_scale : hint_range(0.0, 2.0) = 1.0;
uniform float metallic_scale : hint_range(0.0, 2.0) = 1.0;
uniform float albedo_texture_mix : hint_range(0.0, 1.0) = 0.85;

group_uniforms Overlay;
uniform bool overlay_enabled = false;
uniform sampler2D overlay_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D overlay_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 overlay_tint : source_color = vec3(0.6, 0.55, 0.42);
uniform float overlay_scale : hint_range(0.02, 2.0) = 0.22;
// How steep a face can be and still collect the overlay. 1.0 = only dead flat.
uniform float overlay_slope : hint_range(0.0, 1.0) = 0.68;
uniform float overlay_sharpness : hint_range(0.5, 24.0) = 6.0;
uniform float overlay_amount : hint_range(0.0, 1.0) = 0.75;

group_uniforms Detail;
uniform sampler2D detail_normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float detail_scale : hint_range(0.1, 12.0) = 2.4;
uniform float detail_strength : hint_range(0.0, 2.0) = 0.6;
uniform float detail_distance : hint_range(1.0, 60.0) = 16.0;

group_uniforms Variation;
uniform float macro_strength : hint_range(0.0, 1.0) = 0.22;
uniform float macro_scale : hint_range(0.002, 0.2) = 0.021;

group_uniforms Emission;
uniform vec3 emission_colour : source_color = vec3(0.0);
uniform float emission_energy : hint_range(0.0, 8.0) = 0.0;

varying vec3 world_position;
varying vec3 world_normal;


// Triplanar weights, biased so one axis dominates rather than the three
// blending into a smear on every diagonal face.
vec3 blend_weights(vec3 n, float sharpness) {
	vec3 w = pow(abs(n), vec3(sharpness));
	return w / max(w.x + w.y + w.z, 0.0001);
}

vec4 triplanar_sample(sampler2D tex, vec3 p, vec3 w) {
	return texture(tex, p.yz) * w.x
		 + texture(tex, p.xz) * w.y
		 + texture(tex, p.xy) * w.z;
}

// Triplanar normals need each projection's tangent-space normal rotated into
// world space before blending, or the lighting leans the wrong way on two of
// the three axes. This is the "whiteout" blend, which is cheap and stable.
vec3 triplanar_normal(sampler2D tex, vec3 p, vec3 w, vec3 n, float strength) {
	vec3 nx = texture(tex, p.yz).rgb * 2.0 - 1.0;
	vec3 ny = texture(tex, p.xz).rgb * 2.0 - 1.0;
	vec3 nz = texture(tex, p.xy).rgb * 2.0 - 1.0;
	nx = vec3(nx.z * sign(n.x), nx.y, nx.x);
	ny = vec3(ny.x, ny.z * sign(n.y), ny.y);
	nz = vec3(nz.x, nz.y * sign(n.z), nz.z);
	vec3 blended = normalize(nx * w.x + ny * w.y + nz * w.z);
	return normalize(mix(n, blended, clamp(strength, 0.0, 1.0)));
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Cheap smooth 3D value noise, only used for the macro tint drift.
float macro_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i.xy + i.z * 37.0);
	float b = hash12(i.xy + vec2(1.0, 0.0) + i.z * 37.0);
	float c = hash12(i.xy + vec2(0.0, 1.0) + i.z * 37.0);
	float d = hash12(i.xy + vec2(1.0, 1.0) + i.z * 37.0);
	float e = hash12(i.xy + (i.z + 1.0) * 37.0);
	float g = hash12(i.xy + vec2(1.0, 0.0) + (i.z + 1.0) * 37.0);
	float h = hash12(i.xy + vec2(0.0, 1.0) + (i.z + 1.0) * 37.0);
	float k = hash12(i.xy + vec2(1.0, 1.0) + (i.z + 1.0) * 37.0);
	return mix(mix(mix(a, b, f.x), mix(c, d, f.x), f.y),
			   mix(mix(e, g, f.x), mix(h, k, f.x), f.y), f.z);
}


void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}


void fragment() {
	vec3 n = normalize(world_normal);
	vec3 w = blend_weights(n, 4.0);
	vec3 p = world_position * texture_scale;

	vec3 base = triplanar_sample(albedo_map, p, w).rgb;
	vec3 surface_normal = triplanar_normal(normal_map, p, w, n, normal_strength);
	float rough = triplanar_sample(roughness_map, p, w).r * roughness_scale;
	float metal = triplanar_sample(metallic_map, p, w).r * metallic_scale;

	// The overlay only lands on faces pointing up, and only as far as its own
	// noise lets it, so the boundary is ragged rather than a contour line.
	if (overlay_enabled) {
		float up = clamp(n.y, 0.0, 1.0);
		float slope_mask = smoothstep(overlay_slope, min(overlay_slope + 0.22, 1.0), up);
		float ragged = macro_noise(world_position * 0.35);
		slope_mask *= smoothstep(0.34, 0.66, ragged * 0.6 + 0.4);
		slope_mask = pow(slope_mask, max(24.0 / overlay_sharpness, 0.05)) * overlay_amount;
		if (slope_mask > 0.001) {
			vec3 op = world_position * overlay_scale;
			vec3 oa = triplanar_sample(overlay_albedo, op, w).rgb * overlay_tint;
			base = mix(base * tint, oa, slope_mask);
			vec3 on = triplanar_normal(overlay_normal, op, w, n, normal_strength);
			surface_normal = normalize(mix(surface_normal, on, slope_mask));
			rough = mix(rough, 0.92, slope_mask);
			metal = mix(metal, 0.0, slope_mask);
		} else {
			base *= tint;
		}
	} else {
		base *= tint;
	}

	// Keep some of the flat palette colour: the textures carry the detail, the
	// palette carries the art direction, and letting the texture win outright
	// would throw away the level's colour language.
	base = mix(tint, base, albedo_texture_mix);

	// Macro variation. Two octaves at very different scales, so both a whole
	// wall and a single block vary.
	float macro = macro_noise(world_position * macro_scale) * 0.65
		+ macro_noise(world_position * macro_scale * 3.7) * 0.35;
	base *= 1.0 + (macro - 0.5) * macro_strength * 2.0;

	// Detail normal, faded out with distance so it costs nothing far away and
	// never aliases into noise on the horizon.
	float view_distance = length(VERTEX);
	float detail_fade = 1.0 - smoothstep(detail_distance * 0.35, detail_distance, view_distance);
	if (detail_fade > 0.001) {
		vec3 dn = triplanar_normal(detail_normal_map, world_position * detail_scale, w,
			surface_normal, detail_strength * detail_fade);
		surface_normal = dn;
	}

	ALBEDO = base;
	// Nothing in this game is a mirror. Letting the map's scratch lows through
	// unclamped turned every wall and floor into wet glass under the station's
	// ceiling lights.
	ROUGHNESS = clamp(rough, 0.22, 1.0);
	METALLIC = clamp(metal, 0.0, 1.0);
	// The normal is computed in world space, so it is handed over as one.
	NORMAL = normalize((VIEW_MATRIX * vec4(surface_normal, 0.0)).xyz);
	if (emission_energy > 0.0) {
		EMISSION = emission_colour * emission_energy;
	}
}

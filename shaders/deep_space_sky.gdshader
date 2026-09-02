shader_type sky;
render_mode use_debanding;

// A deep-space sky: stars, the galactic band, nebulae, and planets that are
// actually SPHERES rather than pictures pasted onto the dome.
//
// WHY ANALYTIC PLANETS. A billboard planet is a flat disc: it is lit uniformly,
// it has no terminator, and the moment the player looks at it from a different
// angle nothing changes. Intersecting a ray with a real sphere per pixel costs
// a handful of instructions and gives the day/night terminator, limb darkening,
// an atmosphere that only glows where it is edge-on, and rings that pass BEHIND
// the planet and cast a shadow across it. That is the difference between "there
// is a planet in the sky" and "there is a picture of a planet in the sky".
//
// DROP-IN PHOTOGRAPHY. Each planet has an optional albedo texture slot. Leave it
// empty and the surface is generated below; assign a real equirectangular
// photograph and it is sampled instead, with the same lighting, terminator and
// atmosphere applied on top. Nothing else has to change.

group_uniforms Stars;
uniform float star_density : hint_range(0.0, 1.0) = 0.85;
uniform float star_brightness : hint_range(0.0, 6.0) = 2.6;
uniform float star_size : hint_range(0.2, 3.0) = 1.0;

group_uniforms Galaxy;
uniform vec3 galaxy_axis = vec3(0.36, 0.86, 0.36);
uniform float galaxy_strength : hint_range(0.0, 3.0) = 0.85;
uniform vec3 galaxy_core_colour : source_color = vec3(1.0, 0.90, 0.74);
uniform vec3 galaxy_dust_colour : source_color = vec3(0.30, 0.19, 0.16);

group_uniforms Nebula;
uniform float nebula_strength : hint_range(0.0, 3.0) = 0.7;
uniform vec3 nebula_a : source_color = vec3(0.20, 0.42, 0.95);
uniform vec3 nebula_b : source_color = vec3(0.85, 0.22, 0.55);

group_uniforms Lighting;
uniform vec3 sun_direction = vec3(0.42, 0.30, -0.85);
uniform vec3 sun_colour : source_color = vec3(1.0, 0.96, 0.90);
uniform float sun_size : hint_range(0.0, 0.2) = 0.013;
uniform float exposure : hint_range(0.0, 4.0) = 1.0;

group_uniforms PlanetOne;
uniform bool planet1_enabled = true;
uniform vec3 planet1_direction = vec3(-0.55, 0.22, -0.80);
uniform float planet1_size : hint_range(0.005, 0.6) = 0.16;
uniform vec3 planet1_colour_a : source_color = vec3(0.78, 0.66, 0.48);
uniform vec3 planet1_colour_b : source_color = vec3(0.47, 0.31, 0.20);
uniform vec3 planet1_atmosphere : source_color = vec3(0.95, 0.78, 0.55);
uniform float planet1_bands : hint_range(0.0, 40.0) = 13.0;
uniform float planet1_ring_inner : hint_range(0.0, 4.0) = 1.5;
uniform float planet1_ring_outer : hint_range(0.0, 4.0) = 2.45;
uniform float planet1_ring_tilt : hint_range(-1.5, 1.5) = 0.55;
uniform sampler2D planet1_photo : source_color, hint_default_black;
uniform bool planet1_use_photo = false;

group_uniforms PlanetTwo;
uniform bool planet2_enabled = true;
uniform vec3 planet2_direction = vec3(0.80, 0.44, 0.40);
uniform float planet2_size : hint_range(0.005, 0.6) = 0.055;
uniform vec3 planet2_colour_a : source_color = vec3(0.42, 0.55, 0.72);
uniform vec3 planet2_colour_b : source_color = vec3(0.16, 0.26, 0.42);
uniform vec3 planet2_atmosphere : source_color = vec3(0.45, 0.68, 1.0);
uniform sampler2D planet2_photo : source_color, hint_default_black;
uniform bool planet2_use_photo = false;

group_uniforms Moon;
uniform bool moon_enabled = true;
uniform vec3 moon_direction = vec3(-0.20, 0.52, 0.83);
uniform float moon_size : hint_range(0.002, 0.3) = 0.030;
uniform vec3 moon_colour : source_color = vec3(0.62, 0.60, 0.58);


// --------------------------------------------------------------------------
// Noise
// --------------------------------------------------------------------------

vec3 hash33(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)),
			 dot(p, vec3(269.5, 183.3, 246.1)),
			 dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453123);
}

float hash13(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
			   mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

float fbm(vec3 p, int octaves) {
	float total = 0.0;
	float amplitude = 0.5;
	float weight = 0.0;
	for (int i = 0; i < octaves; i++) {
		total += value_noise(p) * amplitude;
		weight += amplitude;
		p *= 2.03;
		amplitude *= 0.5;
	}
	return total / max(weight, 0.0001);
}

// Ridged noise, which is what gives dust lanes and cloud bands an edge rather
// than the soft cotton-wool look plain fbm has.
float ridged(vec3 p, int octaves) {
	float total = 0.0;
	float amplitude = 0.5;
	float weight = 0.0;
	for (int i = 0; i < octaves; i++) {
		total += (1.0 - abs(value_noise(p) * 2.0 - 1.0)) * amplitude;
		weight += amplitude;
		p *= 2.11;
		amplitude *= 0.5;
	}
	return total / max(weight, 0.0001);
}


// --------------------------------------------------------------------------
// Stars
// --------------------------------------------------------------------------

// Colour from an approximate stellar class. Real skies are not white speckle:
// the brightest stars split into blue-white O/B and orange-red K/M, and putting
// that spread in is most of what makes a starfield look observed rather than
// generated.
vec3 star_colour(float t) {
	if (t < 0.30) { return mix(vec3(0.62, 0.72, 1.00), vec3(0.85, 0.90, 1.00), t / 0.30); }
	if (t < 0.62) { return mix(vec3(0.85, 0.90, 1.00), vec3(1.00, 0.98, 0.94), (t - 0.30) / 0.32); }
	if (t < 0.85) { return mix(vec3(1.00, 0.98, 0.94), vec3(1.00, 0.87, 0.68), (t - 0.62) / 0.23); }
	return mix(vec3(1.00, 0.87, 0.68), vec3(1.00, 0.66, 0.45), (t - 0.85) / 0.15);
}

// One layer of stars on a cubic lattice. Each cell holds at most one star, at a
// jittered position, so they never form a visible grid.
vec3 star_layer(vec3 dir, float scale, float threshold, float brightness, float radius) {
	vec3 p = dir * scale;
	vec3 cell = floor(p);
	vec3 total = vec3(0.0);
	// The 3x3x3 neighbourhood, so a star near a cell edge is not clipped.
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 offset = vec3(float(x), float(y), float(z));
				vec3 id = cell + offset;
				vec3 rnd = hash33(id);
				if (rnd.z > threshold) { continue; }
				vec3 centre = id + 0.15 + 0.7 * rnd;
				float d = length(p - centre);
				// Magnitude is heavily skewed: a few bright stars, very many
				// faint ones, which is how the real distribution runs.
				float magnitude = pow(fract(rnd.x * 91.7), 3.5);
				float size = radius * (0.35 + 0.85 * magnitude);
				float core = smoothstep(size, 0.0, d);
				// A wide, weak halo around the bright ones only.
				float halo = smoothstep(size * 6.0, 0.0, d) * magnitude * 0.28;
				total += star_colour(fract(rnd.y * 53.3))
					* (core * core + halo) * brightness * (0.25 + magnitude);
			}
		}
	}
	return total;
}


// --------------------------------------------------------------------------
// Planets
// --------------------------------------------------------------------------

// Distance from `dir` to the planet centre, in units of the planet's angular
// radius. Below 1.0 the ray hits the disc.
float disc_coord(vec3 dir, vec3 centre, float angular_radius) {
	return length(dir - centre * dot(dir, centre)) / max(angular_radius, 0.0001);
}

// Surface point on the unit sphere for a ray that hits the disc at `r` (0 at
// the centre, 1 at the limb). This is what makes the texture wrap round the
// body and compress towards the edge, exactly as a photograph of a planet does.
vec3 sphere_point(vec3 dir, vec3 centre, float angular_radius, out float ndotv) {
	vec3 right = normalize(cross(centre, vec3(0.0, 1.0, 0.0)) + vec3(0.0001, 0.0, 0.0));
	vec3 up = normalize(cross(right, centre));
	vec3 offset = dir - centre * dot(dir, centre);
	vec2 uv = vec2(dot(offset, right), dot(offset, up)) / max(angular_radius, 0.0001);
	float r2 = clamp(dot(uv, uv), 0.0, 1.0);
	ndotv = sqrt(max(1.0 - r2, 0.0));
	return normalize(right * uv.x + up * uv.y + centre * ndotv);
}

// Equirectangular lookup, so an assigned photograph maps the same way every
// planetary map on the internet is stored.
vec2 equirect_uv(vec3 n) {
	return vec2(atan(n.z, n.x) / (2.0 * PI) + 0.5, acos(clamp(n.y, -1.0, 1.0)) / PI);
}


// --------------------------------------------------------------------------

void sky() {
	vec3 dir = EYEDIR;
	vec3 sun = normalize(sun_direction);
	vec3 colour = vec3(0.0);

	// --- Deep background: a cold gradient, darkest away from the galaxy ------
	float up = clamp(dir.y * 0.5 + 0.5, 0.0, 1.0);
	colour += mix(vec3(0.006, 0.008, 0.020), vec3(0.012, 0.016, 0.038), up);

	// --- The galactic band --------------------------------------------------
	// Distance from the galactic plane drives everything: the band is brightest
	// on the plane, and the dust lane sits right on it, splitting the band in
	// two the way the Milky Way actually looks.
	vec3 axis = normalize(galaxy_axis);
	float plane = abs(dot(dir, axis));
	float band = pow(1.0 - clamp(plane, 0.0, 1.0), 7.0);
	float towards_core = pow(clamp(dot(dir, normalize(vec3(0.55, -0.1, -0.83))) * 0.5 + 0.5, 0.0, 1.0), 3.0);
	float cloud = fbm(dir * 5.5, 5);
	float lane = ridged(dir * 9.0 + vec3(11.3), 4);
	vec3 galaxy = mix(vec3(0.58, 0.63, 0.80), galaxy_core_colour, towards_core * 0.85);
	galaxy *= band * (0.35 + 0.9 * cloud) * (0.55 + 0.75 * towards_core);
	// Dust: subtractive, and tinted, so it reads as material in front of the
	// stars rather than as the band simply being dimmer there.
	float dust = band * smoothstep(0.35, 0.85, lane) * (0.5 + 0.5 * towards_core);
	galaxy = max(galaxy - galaxy_dust_colour * dust * 2.1, vec3(0.0));
	colour += galaxy * galaxy_strength;

	// --- Nebulae ------------------------------------------------------------
	float n1 = fbm(dir * 2.6 + vec3(31.7, 5.1, 12.9), 5);
	float n2 = fbm(dir * 3.9 + vec3(-8.2, 19.4, -3.3), 5);
	float mask1 = smoothstep(0.52, 0.86, n1) * pow(band, 0.35);
	float mask2 = smoothstep(0.58, 0.90, n2);
	colour += nebula_a * mask1 * nebula_strength * 0.55;
	colour += nebula_b * mask2 * nebula_strength * 0.32;

	// --- Stars --------------------------------------------------------------
	// Three layers at different densities: the sky has structure at more than
	// one scale, and a single layer always reads as a texture.
	float density = clamp(star_density, 0.0, 1.0);
	// More stars towards the galactic plane, which is the single strongest cue
	// that the band is made of stars rather than painted on.
	float crowding = 1.0 + band * 2.2;
	vec3 stars = vec3(0.0);
	stars += star_layer(dir, 38.0, 0.30 * density * crowding, 1.0, 0.075 * star_size);
	stars += star_layer(dir, 82.0, 0.42 * density * crowding, 0.62, 0.055 * star_size);
	stars += star_layer(dir, 175.0, 0.55 * density * crowding, 0.34, 0.045 * star_size);
	stars += star_layer(dir, 340.0, 0.60 * density * crowding, 0.18, 0.040 * star_size);
	colour += stars * star_brightness;

	// --- The system's sun ---------------------------------------------------
	float sun_d = distance(dir, sun);
	colour += sun_colour * smoothstep(sun_size, sun_size * 0.55, sun_d) * 6.0;
	colour += sun_colour * pow(max(dot(dir, sun), 0.0), 900.0) * 2.0;
	colour += sun_colour * pow(max(dot(dir, sun), 0.0), 40.0) * 0.12;

	// --- Planet one: a banded gas giant with rings --------------------------
	if (planet1_enabled) {
		vec3 centre = normalize(planet1_direction);
		vec3 right = normalize(cross(centre, vec3(0.0, 1.0, 0.0)) + vec3(0.0001, 0.0, 0.0));
		vec3 up_axis = normalize(cross(right, centre));
		// The ring normal has to lean TOWARDS the viewer, not merely spin
		// within the plane perpendicular to the line of sight. Built purely
		// from `right` and `up_axis` - both perpendicular to `centre` - the
		// ring plane contained the view ray exactly, so the rings were always
		// seen perfectly edge-on and rendered as nothing at all. Mixing
		// `centre` in is what opens them.
		vec3 ring_normal = normalize(up_axis * cos(planet1_ring_tilt)
			+ centre * sin(planet1_ring_tilt)
			+ right * 0.12);

		float r = disc_coord(dir, centre, planet1_size);
		float ndotv;
		vec3 surface = sphere_point(dir, centre, planet1_size, ndotv);
		float lit = clamp(dot(surface, sun), 0.0, 1.0);

		// RINGS. The first version put the eye at -centre and solved from
		// there, which is wrong for a sky shader: the eye is at the origin and
		// the planet is a direction, not a position. Placing the planet centre
		// one unit away along `centre` makes the geometry ordinary again -
		// intersect the view ray with the ring plane through that centre, and
		// measure the hit radius in planet radii.
		vec3 planet_centre = centre;                 // one unit out
		float denom = dot(dir, ring_normal);
		float ring_t = dot(planet_centre, ring_normal) / (abs(denom) < 1e-5 ? 1e-5 : denom);
		vec3 ring_hit = dir * ring_t;
		float ring_r = length(ring_hit - planet_centre) / max(planet1_size, 1e-4);

		float ring_band = smoothstep(planet1_ring_inner, planet1_ring_inner + 0.05, ring_r)
			* (1.0 - smoothstep(planet1_ring_outer - 0.10, planet1_ring_outer, ring_r));
		// Gaps. A solid annulus reads as a plastic hoop; real rings are ranges
		// of particle density with a wide division through them.
		// Two clear divisions and a slow density drift, rather than a high
		// frequency sine: the first version produced a dozen hard concentric
		// lines and read as wireframe instead of as billions of ice particles.
		float grain = fbm(vec3(ring_r * 9.0, 0.0, 0.0), 4);
		float gaps = 0.62 + 0.38 * grain;
		gaps *= 1.0 - 0.85 * exp(-pow((ring_r - 1.93) * 22.0, 2.0));
		gaps *= 1.0 - 0.40 * exp(-pow((ring_r - 2.24) * 34.0, 2.0));
		// Denser towards the middle of the sheet, thinning at both edges.
		gaps *= 0.55 + 0.45 * sin(clamp((ring_r - planet1_ring_inner)
			/ max(planet1_ring_outer - planet1_ring_inner, 1e-4), 0.0, 1.0) * PI);
		// Edge-on the rings almost vanish, which is the cue that they are a
		// flat sheet and not a torus.
		float openness = smoothstep(0.008, 0.16, abs(denom));
		float ring_alpha = ring_band * gaps * openness * 1.0;
		// Only the half of the plane in FRONT of the eye exists.
		ring_alpha *= step(0.0, ring_t);
		vec3 ring_colour = mix(vec3(0.55, 0.48, 0.39), vec3(0.95, 0.91, 0.83), gaps);

		// A ring sample is hidden when it lands on the planet's disc AND lies
		// beyond the planet's centre plane - that is the far half of the ring.
		float ring_disc = disc_coord(normalize(ring_hit), centre, planet1_size);
		bool ring_behind = ring_disc < 1.0 && ring_t > dot(centre, dir);
		if (ring_alpha > 0.001 && ring_behind) {
			colour = mix(colour, ring_colour * 0.55, ring_alpha);
		}

		if (r < 1.0) {
			vec3 body;
			if (planet1_use_photo) {
				body = texture(planet1_photo, equirect_uv(surface)).rgb;
			} else {
				// Latitude bands, warped by noise so they are not stripes, plus
				// a storm oval - the detail the eye actually looks for.
				float lat = surface.y;
				float warp = fbm(surface * 3.2, 4) * 0.16;
				float bands = sin((lat + warp) * planet1_bands) * 0.5 + 0.5;
				bands = smoothstep(0.18, 0.82, bands);
				bands = mix(bands, ridged(surface * 7.0, 4), 0.34);
				body = mix(planet1_colour_b, planet1_colour_a, bands);
				float storm = smoothstep(0.24, 0.0,
					length((surface - normalize(vec3(0.55, -0.28, 0.6))) * vec3(1.0, 2.1, 1.0)));
				body = mix(body, vec3(0.86, 0.44, 0.30), storm * 0.85);
			}
			// Limb darkening: the edge of a lit sphere is dimmer, and leaving it
			// out is what makes a rendered planet look like a sticker.
			float limb = pow(ndotv, 0.42);
			// A soft terminator rather than a hard line.
			float shade = smoothstep(-0.08, 0.32, dot(surface, sun));
			vec3 planet = body * (shade * limb * 1.35 + 0.012);
			// The rings drop a shadow across the disc.
			// Ring shadow: trace from the surface point towards the star and
			// see where that line crosses the ring plane. This is why the
			// shadow is a curved band that moves with the light, rather than a
			// stripe painted at a fixed latitude.
			float sdenom = dot(sun, ring_normal);
			if (abs(sdenom) > 1e-4) {
				float st = -dot(surface, ring_normal) / sdenom;
				if (st > 0.0) {
					float sr = length(surface + sun * st) / 1.0;
					float in_ring = smoothstep(planet1_ring_inner, planet1_ring_inner + 0.05, sr)
						* (1.0 - smoothstep(planet1_ring_outer - 0.08, planet1_ring_outer, sr));
					planet *= 1.0 - in_ring * 0.55;
				}
			}
			float edge = smoothstep(1.0, 0.985, r);
			colour = mix(colour, planet, edge);
			// Atmospheric limb, brightest where the star grazes the edge.
			float rim = pow(1.0 - ndotv, 2.6) * pow(max(lit, 0.0), 0.6);
			colour += planet1_atmosphere * rim * 0.5 * edge;
		} else {
			// Outside the disc: a thin halo of scattered light.
			colour += planet1_atmosphere * smoothstep(1.16, 1.0, r) * 0.10
				* pow(max(dot(centre, sun), 0.0) * 0.5 + 0.5, 2.0);
		}

		if (ring_alpha > 0.001 && !ring_behind) {
			// Ring particles in shadow behind the planet are dark.
			float ring_lit = step(0.0, dot(normalize(ring_hit - centre * 0.0), sun)) * 0.55 + 0.45;
			colour = mix(colour, ring_colour * ring_lit, ring_alpha);
		}
	}

	// --- Planet two: a small ocean world ------------------------------------
	if (planet2_enabled) {
		vec3 centre = normalize(planet2_direction);
		float r = disc_coord(dir, centre, planet2_size);
		float ndotv;
		vec3 surface = sphere_point(dir, centre, planet2_size, ndotv);
		if (r < 1.0) {
			vec3 body;
			if (planet2_use_photo) {
				body = texture(planet2_photo, equirect_uv(surface)).rgb;
			} else {
				float land = fbm(surface * 2.4 + vec3(4.1), 5);
				float coast = smoothstep(0.48, 0.56, land);
				body = mix(planet2_colour_b, planet2_colour_a, coast);
				// Ice caps.
				body = mix(body, vec3(0.92, 0.95, 1.0),
					smoothstep(0.72, 0.92, abs(surface.y)));
				// Cloud deck, on its own noise so it crosses the coastlines.
				float cloud2 = smoothstep(0.55, 0.78, fbm(surface * 3.6 + vec3(19.7), 5));
				body = mix(body, vec3(1.0), cloud2 * 0.62);
			}
			float shade = smoothstep(-0.06, 0.30, dot(surface, sun));
			float limb = pow(ndotv, 0.4);
			colour = mix(colour, body * (shade * limb * 1.4 + 0.015), smoothstep(1.0, 0.98, r));
			float rim = pow(1.0 - ndotv, 2.2) * shade;
			colour += planet2_atmosphere * rim * 0.85;
		} else {
			colour += planet2_atmosphere * smoothstep(1.35, 1.0, r) * 0.12;
		}
	}

	// --- A cratered moon ----------------------------------------------------
	if (moon_enabled) {
		vec3 centre = normalize(moon_direction);
		float r = disc_coord(dir, centre, moon_size);
		if (r < 1.0) {
			float ndotv;
			vec3 surface = sphere_point(dir, centre, moon_size, ndotv);
			// Craters: ridged noise inverted, so the rims catch the light.
			float craters = 1.0 - ridged(surface * 14.0, 4);
			float maria = smoothstep(0.42, 0.62, fbm(surface * 3.0 + vec3(7.7), 4));
			vec3 body = moon_colour * (0.68 + 0.42 * craters) * mix(1.0, 0.68, maria);
			float shade = smoothstep(-0.05, 0.22, dot(surface, sun));
			colour = mix(colour, body * (shade * pow(ndotv, 0.3) * 1.25 + 0.01),
				smoothstep(1.0, 0.975, r));
		}
	}

	COLOR = colour * exposure;
}

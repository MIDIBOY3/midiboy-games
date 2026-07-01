shader_type spatial;
render_mode cull_back;

// Discovered star/planet backdrop sphere.
// Procedural planet SURFACE: FBM continents vs ocean, polar ice caps and a thin
// drifting cloud layer, all tinted per biome. Detail is fragment-only (cheap) and
// normal lighting still draws the day/night terminator over it.

uniform vec4 land_color : source_color = vec4(0.30, 0.50, 0.20, 1.0);
uniform vec4 ocean_color : source_color = vec4(0.04, 0.16, 0.34, 1.0);
uniform vec4 pole_color : source_color = vec4(0.92, 0.96, 1.0, 1.0);
uniform vec4 cloud_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float emission_energy = 0.18;
uniform float body_glow = 1.4;   // brightest surface (clouds/ice/bright land) blooms past 1.0
uniform float seed = 0.0;
uniform float sea_level = 0.48;     // FBM threshold: higher = more ocean
uniform float pole_amount = 0.6;    // size of the ice caps (0 = none)
uniform float cloud_amount = 0.35;  // cloud opacity
uniform float rotate_speed = 0.02;  // slow self-rotation of the surface
// Surface STYLE: 0 terran, 1 ocean (shimmer), 2 gas (wood-grain bands), 3 night city
// (twinkling lights), 4 barren/dark, 5 lava (glowing cracks). Lets each star look distinct.
uniform int world_type = 0;
// Ending homeworld extras (gated; default 0 → discovered stars are unaffected).
// A sun-glint sparkle skating over the oceans, and golden city lights that twinkle on
// the planet's NIGHT side (sun_dir = world-space direction TOWARD the sun).
uniform float ocean_glint = 0.0;
uniform float night_lights = 0.0;
uniform vec3 sun_dir = vec3(0.5, 0.7, 0.5);

varying vec3 v_obj;   // object-space position (direction on the unit sphere)

void vertex() {
	v_obj = normalize(VERTEX);
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1) * 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash3(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash3(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash3(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash3(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash3(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash3(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash3(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash3(i + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);
	float nxy0 = mix(nx00, nx10, f.y);
	float nxy1 = mix(nx01, nx11, f.y);
	return mix(nxy0, nxy1, f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p *= 2.02;
		a *= 0.5;
	}
	return v;
}

// Cheap 2-octave value-noise FBM, normalized to ~the same 0..1 range as fbm(). Used ONLY
// for the sea-glitter: its 3rd-5th octaves are sub-pixel/aliasing at the glitter's high
// frequencies (pow() picks out the low-octave peaks anyway), so dropping them is visually
// ~identical but ~2.5x cheaper — the planet BODY (continents/clouds) keeps full fbm().
float fbm_lite(vec3 p) {
	return (vnoise(p) * 0.5 + vnoise(p * 2.02) * 0.25) / 0.75;
}

void fragment() {
	vec3 dir = normalize(v_obj);
	// Spin the surface slowly around the planet's axis.
	float ang = TIME * rotate_speed;
	float cs = cos(ang);
	float sn = sin(ang);
	mat3 rot = mat3(vec3(cs, 0.0, sn), vec3(0.0, 1.0, 0.0), vec3(-sn, 0.0, cs));
	vec3 p = rot * dir;
	vec3 sp = p * 2.4 + vec3(seed);

	vec3 surf;
	vec3 emit_col = vec3(0.0);
	float emit_extra = 0.0;
	vec3 sea_glint = vec3(0.0);   // homeworld sun-glitter, fed into EMISSION so it blooms
	float metal = 0.0;
	float rough = 0.92;

	if (world_type == 2) {
		// GAS GIANT: latitude bands warped by noise → a wood-grain / Jupiter look.
		float bands = sin(dir.y * 9.0 + fbm(sp * 1.4) * 3.2);
		float t = smoothstep(-0.4, 0.4, bands);
		surf = mix(ocean_color.rgb, land_color.rgb, t);
		surf *= mix(0.82, 1.16, fbm(sp * 4.0 + 2.0));
		float swirl = smoothstep(0.5, 0.82, fbm(p * 3.0 + vec3(TIME * 0.12, 0.0, 0.0)));
		surf = mix(surf, cloud_color.rgb, swirl * cloud_amount);
		rough = 0.85;
	} else {
		float cont = fbm(sp);
		float land_t = smoothstep(sea_level - 0.06, sea_level + 0.06, cont);
		surf = mix(ocean_color.rgb, land_color.rgb, land_t);
		surf *= mix(0.82, 1.18, fbm(sp * 3.3 + 5.0));
		float lat = abs(dir.y);
		float cap = smoothstep(0.92 - pole_amount * 0.30, 0.96, lat) * step(0.001, pole_amount);
		surf = mix(surf, pole_color.rgb, cap);

		if (world_type == 1) {
			// OCEAN: a moving sun-glint shimmer over the water.
			float water = 1.0 - land_t;
			float gl = pow(fbm_lite(p * 7.0 + vec3(TIME * 0.16, 0.0, TIME * 0.1)), 6.0);
			surf += vec3(0.5, 0.72, 0.95) * gl * water * 0.6;
			rough = 0.5;
		} else if (world_type == 3) {
			// NIGHT CITY: dark world; clustered city lights on land twinkle (day & night).
			surf *= 0.32;
			float grid = step(0.9, vnoise(sp * 46.0)) * land_t;
			float cell = hash3(floor(sp * 46.0));
			float tw = 0.55 + 0.45 * sin(TIME * 4.0 + cell * 40.0);
			emit_col = mix(vec3(1.0, 0.85, 0.45), vec3(0.6, 0.9, 1.0), step(0.5, cell));
			emit_extra = grid * tw * 3.2;
		} else if (world_type == 4) {
			// BARREN / DARK: low-albedo rock with cratery mottle, no sea/clouds.
			surf = land_color.rgb * mix(0.4, 0.9, fbm(sp * 5.0));
			surf *= mix(1.0, 0.68, smoothstep(0.6, 0.62, fbm(sp * 8.0)));
		} else if (world_type == 5) {
			// LAVA: dark crust with glowing molten cracks in the low ground.
			float low = 1.0 - smoothstep(sea_level - 0.02, sea_level + 0.10, cont);
			surf = mix(land_color.rgb * 0.35, land_color.rgb * 0.7, land_t);
			emit_col = vec3(1.0, 0.42, 0.10);
			emit_extra = low * (0.6 + 0.4 * sin(TIME * 2.0 + cont * 22.0)) * 2.4;
			surf = mix(surf, vec3(1.0, 0.4, 0.12), low * 0.5);
		}

		// Clouds for the water/terran styles only (skip barren/lava).
		if (world_type != 4 && world_type != 5) {
			float clouds = smoothstep(0.55, 0.78,
				fbm(p * 2.0 + vec3(11.0 + seed, TIME * rotate_speed * 1.6, 3.0)));
			surf = mix(surf, cloud_color.rgb, clouds * cloud_amount);
		}

		// Sparkling sun-glint on the seas (kirakira) for water worlds (terran/ocean),
		// plus golden night-side city lights. Both gated by their uniforms, so a world
		// only lights up when the spawner asks for it (homeworld + ocean/terran stars).
		if (world_type == 0 || world_type == 1) {
			float water = 1.0 - land_t;
			if (ocean_glint > 0.0) {
				// Broad rolling sun-glitter band sweeping across the seas.
				float gl = pow(fbm_lite(p * 7.0 + vec3(TIME * 0.13, 0.0, TIME * 0.08)), 5.0);
				// Sharp twinkling diamond points: high-freq sparkles that flash on/off,
				// each with its own blink phase so the water reads as a field of jewels.
				float sn = fbm_lite(p * 34.0 + vec3(0.0, TIME * 0.5, 0.0));
				float spark = pow(sn, 13.0);
				float flick = 0.5 + 0.5 * sin(TIME * 7.0 + sn * 120.0);
				spark *= flick;
				// A second, larger sparkle layer for big lens-like flares here and there.
				float sn2 = fbm_lite(p * 16.0 + vec3(TIME * 0.22, 5.0, 0.0));
				float flare = pow(sn2, 9.0) * (0.6 + 0.4 * sin(TIME * 3.0 + sn2 * 60.0));
				float glitter = (gl * 0.9 + spark * 6.0 + flare * 3.0) * water * ocean_glint;
				// Hot sparkle cores trend to pure white (cool blue in the broad band).
				vec3 gcol = mix(vec3(0.55, 0.78, 1.0), vec3(1.0, 1.0, 1.0),
					clamp(spark * 4.0 + flare * 2.0, 0.0, 1.0));
				surf += gcol * glitter;
				sea_glint += gcol * glitter * 1.6;   // bloom the brightest glints into stars
			}
			if (night_lights > 0.0) {
				vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
				float night = smoothstep(0.18, -0.28, dot(wn, normalize(sun_dir)));
				float grid = step(0.86, vnoise(sp * 40.0)) * land_t;
				float cell = hash3(floor(sp * 40.0));
				float tw = 0.6 + 0.4 * sin(TIME * 3.0 + cell * 50.0);
				emit_col = mix(vec3(1.0, 0.85, 0.5), vec3(0.7, 0.92, 1.0), step(0.6, cell));
				emit_extra = grid * tw * night * night_lights * 3.2;
			}
		}
	}

	ALBEDO = surf;
	METALLIC = metal;
	ROUGHNESS = rough;
	// Bloom only WARM bright bits (lava/desert/city lights) — white clouds/ice must NOT
	// blow out, so the generic bloom is gated by warmth; styled emission adds on top.
	float lum = max(surf.r, max(surf.g, surf.b));
	float warm = clamp(surf.r - surf.b, 0.0, 1.0);
	float core = smoothstep(0.7, 1.0, lum) * warm;
	EMISSION = surf * emission_energy + surf * core * body_glow + emit_col * emit_extra + sea_glint;
}

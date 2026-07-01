shader_type spatial;
render_mode unshaded;

uniform float scroll_y = 0.0;
uniform float scroll_x = 0.0;
uniform float time_val = 0.0;
uniform float zoom = 1.0;
uniform float ground_mix = 0.0;        // 0 = starfield (space), 1 = planet atmosphere
uniform vec3 sky_color = vec3(0.3, 0.5, 0.7);  // biome sky tint
uniform float nebula_strength = 0.0;   // per-sector nebula intensity (0 = none)
uniform float dark_mix = 0.0;          // 0 = normal, 1 = eerie black-hole void (stars die, field darkens)
uniform float space_brightness = 1.0;  // global light scale for the whole space backdrop (1.0 = unchanged)
uniform vec3 nebula_a = vec3(0.18, 0.10, 0.40);  // nebula core color
uniform vec3 nebula_b = vec3(0.45, 0.18, 0.55);  // nebula highlight color

// Per-system dramatic backdrop feature (faded in by its strength; crossfaded
// between systems by Background.gd). Only one is usually non-zero at a time.
uniform float galaxy_strength = 0.0;
uniform float blackhole_strength = 0.0;
uniform float sun_strength = 0.0;
uniform float lunar_strength = 0.0;
uniform float twin_strength = 0.0;
uniform float supernova_strength = 0.0;
uniform float aurora_strength = 0.0;
uniform float cluster_strength = 0.0;
uniform vec2  feature_pos = vec2(0.5, 0.5);       // feature center in UV space
uniform vec3  feature_color = vec3(1.0, 0.9, 0.7);
uniform float feature_seed = 0.0;                  // per-system shape variation

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 43.21);
	return fract(p.x * p.y);
}

vec3 star_layer(vec2 uv, float sy, float sx, float density, float star_size) {
	vec2 luv = uv + vec2(sx, -sy);
	vec2 id  = floor(luv * density);
	vec2 lc  = fract(luv * density) - 0.5;

	float h = hash21(id);
	if (h > 0.25) return vec3(0.0);

	vec2 offset = (vec2(hash21(id + vec2(1.7, 0.3)), hash21(id + vec2(0.3, 2.3))) - 0.5) * 0.65;
	float dist = length(lc - offset);

	float twinkle = 0.55 + 0.45 * sin(time_val * (2.0 + hash21(id + vec2(3.1, 0.0)) * 5.0) + h * 6.28318);
	float brightness = 0.4 + 0.6 * hash21(id + vec2(5.5, 1.1));
	float star = smoothstep(star_size, 0.0, dist) * brightness * twinkle;

	float warm = hash21(id + vec2(7.7, 2.2));
	vec3 color = mix(vec3(0.75, 0.88, 1.0), vec3(1.0, 0.92, 0.75), warm);
	return color * star;
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

// Drifting interstellar cloud, per-sector colored. Layered fbm so the sky reads
// as a distinct nebula in each star system (faded in by nebula_strength).
vec3 nebula(vec2 uv, float sy, float sx) {
	vec2 q = uv * 2.4 + vec2(sx * 0.4, -sy * 1.1);
	float n = fbm(q);
	float n2 = fbm(q * 1.7 + vec2(3.1, n * 1.6));
	float cloud = smoothstep(0.32, 0.95, n * 0.6 + n2 * 0.6);
	vec3 col = mix(nebula_a, nebula_b, clamp(n2, 0.0, 1.0));
	return col * cloud;
}

// Spiral galaxy: rotating log-spiral arms with a bright bulge.
vec3 galaxy_feature(vec2 uv) {
	vec2 d = uv - feature_pos;
	d.y *= 1.35;                                   // slight inclination
	float r = length(d);
	float a = atan(d.y, d.x);
	float spin = time_val * 0.04 + feature_seed;
	float swirl = sin(2.0 * a + r * 17.0 - spin * 2.0);
	float arm = smoothstep(0.15, 1.0, 0.5 + 0.5 * swirl);
	float disk = smoothstep(0.42, 0.0, r);
	float core = smoothstep(0.085, 0.0, r);
	float dust = arm * disk;
	vec3 col = mix(nebula_a, feature_color, clamp(dust + core, 0.0, 1.0));
	return col * (dust * 0.9 + core * 2.0);
}

// Black hole: black core, bright swirling accretion ring, soft glow halo.
vec3 blackhole_feature(vec2 uv) {
	vec2 d = uv - feature_pos;
	float r = length(d);
	float a = atan(d.y, d.x);
	float hole = smoothstep(0.072, 0.060, r);      // 1 inside the event horizon
	float ring = smoothstep(0.155, 0.085, r) * smoothstep(0.058, 0.085, r);
	float swirl = 0.5 + 0.5 * sin(a * 3.0 + r * 34.0 - time_val * 1.3 + feature_seed);
	vec3 col = mix(feature_color, nebula_b, swirl) * ring * 2.2;
	col += feature_color * smoothstep(0.34, 0.07, r) * 0.22;   // halo
	return col * (1.0 - hole);
}

// Sun: blazing core with radial bloom and faint lens rays.
vec3 sun_at(vec2 uv, vec2 ctr, vec3 tint, float seed) {
	vec2 d = uv - ctr;
	float r = length(d);
	float a = atan(d.y, d.x);
	float core = smoothstep(0.085, 0.0, r);
	float glow = pow(smoothstep(0.62, 0.0, r), 2.0);
	float rays = 0.6 + 0.4 * sin(a * 11.0 + seed);
	return tint * (core * 2.6 + glow * (0.8 + 0.4 * rays));
}

vec3 sun_feature(vec2 uv) {
	return sun_at(uv, feature_pos, feature_color, feature_seed);
}

// Binary stars: two suns sharing the system, the second mirrored and tinted cool.
vec3 twin_feature(vec2 uv) {
	vec3 c = sun_at(uv, feature_pos, feature_color, feature_seed);
	vec2 p2 = vec2(1.0 - feature_pos.x, clamp(feature_pos.y + 0.16 * sin(feature_seed), 0.15, 0.85));
	c += sun_at(uv, p2, feature_color.bgr, feature_seed + 3.0) * 0.85;
	return c;
}

// Supernova: blazing core with an expanding shock ring that loops.
vec3 supernova_feature(vec2 uv) {
	vec2 d = uv - feature_pos;
	float r = length(d);
	float ph = fract(time_val * 0.06 + feature_seed);   // 0..1 expansion loop
	float radius = ph * 0.5;
	float ring = smoothstep(0.035, 0.0, abs(r - radius)) * (1.0 - ph);
	float core = smoothstep(0.13, 0.0, r) * (0.65 + 0.35 * sin(time_val * 3.0));
	vec3 col = feature_color * (core * 2.2);
	col += mix(feature_color, nebula_b, 0.5) * ring * 2.6;
	return col;
}

// Aurora: drifting, waving curtains of colour banded across the sky.
vec3 aurora_feature(vec2 uv) {
	float n = fbm(vec2(uv.x * 4.0 + time_val * 0.12, uv.y * 1.5 + feature_seed));
	float wave = sin(uv.x * 7.0 + n * 3.5 + time_val * 0.6 + feature_seed);
	float curtain = smoothstep(0.35, 1.0, 0.5 + 0.5 * wave);
	curtain *= smoothstep(0.0, 0.45, uv.y) * smoothstep(1.05, 0.55, uv.y);
	vec3 col = mix(feature_color, nebula_b, clamp(uv.y + n * 0.3, 0.0, 1.0));
	return col * curtain * 0.95;
}

// Dense star cluster: a concentrated swarm of bright stars with a glowing haze.
vec3 cluster_feature(vec2 uv) {
	vec2 d = uv - feature_pos;
	float fall = smoothstep(0.42, 0.0, length(d));
	vec3 c = star_layer(uv, scroll_y * 1.5, scroll_x * 0.3, 58.0, 0.020);
	c += star_layer(uv, scroll_y * 1.2, scroll_x * 0.2, 92.0, 0.014);
	c += feature_color * smoothstep(0.18, 0.0, length(d)) * 0.35;
	return c * fall;
}

// Lunar: a distant world hanging in a black sky, lit on one side by the harsh key
// light — a crescent/terminator that echoes the half-shadow look on the ship.
vec3 lunar_feature(vec2 uv) {
	vec2 d = uv - feature_pos;
	float R = 0.17;
	float r = length(d);
	float inside = smoothstep(R, R - 0.005, r);
	vec2 ldir = normalize(vec2(0.62, 0.78));
	float lambert = clamp(dot(normalize(d + 0.0001), ldir) * 0.5 + 0.5, 0.0, 1.0);
	vec3 surf = feature_color * (0.06 + pow(lambert, 1.6));   // dark side + lit crescent
	return surf * inside;
}

// 惑星ステージの背景：地形はポリゴン(PlanetTerrain)が描くので、
// 背景クアッドはバイオーム色の大気ヘイズになる（ガス惑星等の隙間から見える）。
vec3 atmosphere(vec2 uv, float sy, float sx) {
	float wisps = vnoise(uv * 4.0 + vec2(sx * 0.3, -sy * 2.5));
	return sky_color * (0.25 + 0.45 * (1.0 - uv.y)) + sky_color * wisps * 0.2;
}

// Gravitational-lens swirl: rotate every point about the hole by an amount that grows
// toward the centre, so the WHOLE cosmos appears to spiral into the black hole.
vec2 blackhole_warp(vec2 uv) {
	vec2 d = uv - feature_pos;
	float r = length(d);
	float a = atan(d.y, d.x);
	a += 0.42 / (r + 0.18) + time_val * 0.025;     // shear stronger near the centre + slow spin
	return feature_pos + vec2(cos(a), sin(a)) * r;
}

void fragment() {
	// 中心を基点にズーム：低高度(zoom小)で拡大、高高度(zoom大)で縮小
	vec2 uv = (UV - 0.5) * zoom + 0.5;
	// In the void, gravitationally lens the whole field so stars + clouds spiral inward.
	vec2 fuv = (dark_mix > 0.001) ? mix(uv, blackhole_warp(uv), dark_mix) : uv;
	// 遠景：ゆっくり・極小・視差少
	vec3 col  = star_layer(fuv, scroll_y * 1.0, scroll_x * 0.2, 28.0, 0.015);
	// 中景
	col      += star_layer(fuv, scroll_y * 2.5, scroll_x * 0.5, 18.0, 0.022);
	// 近景：速い・小さめ・視差大
	col      += star_layer(fuv, scroll_y * 4.5, scroll_x * 1.0, 10.0, 0.035);

	if (nebula_strength > 0.001) {
		col += nebula(fuv, scroll_y * 0.6, scroll_x * 0.4) * nebula_strength;
	}

	if (sun_strength > 0.001) {
		col += sun_feature(uv) * sun_strength;
	}
	if (galaxy_strength > 0.001) {
		col += galaxy_feature(uv) * galaxy_strength;
	}
	if (blackhole_strength > 0.001) {
		col += blackhole_feature(uv) * blackhole_strength;
	}
	if (twin_strength > 0.001) {
		col += twin_feature(uv) * twin_strength;
	}
	if (supernova_strength > 0.001) {
		col += supernova_feature(uv) * supernova_strength;
	}
	if (aurora_strength > 0.001) {
		col += aurora_feature(uv) * aurora_strength;
	}
	if (cluster_strength > 0.001) {
		col += cluster_feature(uv) * cluster_strength;
	}
	if (lunar_strength > 0.001) {
		col += lunar_feature(uv) * lunar_strength;
	}

	if (ground_mix > 0.001) {
		col = mix(col, atmosphere(uv, scroll_y, scroll_x), ground_mix);
	}

	// ===== BLACK-HOLE VOID =====
	// The DARKEST place in the game: a near-black field sculpted by the shader's light into
	// a stark moonscape of highlights and shadows. The lensed nebula is treated as a
	// heightfield and LIT — only its ridges catch the light; everything else falls to black.
	if (dark_mix > 0.001) {
		vec2 d = uv - feature_pos;
		float r = length(d);
		// Lensed cloud heightfield + its surface normal (finite differences).
		vec2 nq = fuv * 3.2 + vec2(scroll_x * 0.3, -scroll_y * 0.5);
		float e  = 0.012;
		float h  = fbm(nq);
		float hx = fbm(nq + vec2(e, 0.0));
		float hy = fbm(nq + vec2(0.0, e));
		vec3 nrm = normalize(vec3(-(hx - h) * 7.0, -(hy - h) * 7.0, 1.0));
		vec3 ldir = normalize(vec3(0.62, 0.46, 0.64));
		float lam  = max(dot(nrm, ldir), 0.0);            // ONE hard key light, sharply one-sided
		float key  = pow(lam, 2.4);                       // lit flank
		float crest = pow(lam, 6.0);                      // blazing crest highlight
		float cloudmask = smoothstep(0.34, 0.88, h);      // only cloudy ridges face the light
		vec3 shadow = vec3(0.004, 0.002, 0.008);          // near-pure-black void floor (darkest in game)
		vec3 warm   = vec3(1.00, 0.74, 0.86);             // magenta-tinted lit flank
		vec3 hicol  = vec3(1.00, 0.97, 1.00);             // blinding cold-white crest
		// Single bright light: dim flank + a crest that BLOWS OUT (clamped to white later).
		vec3 lit = (warm * key * 0.55 + hicol * crest * 2.6) * cloudmask;
		// Near-pure-black base + the one blazing light + only the brightest lensed stars.
		vec3 voidcol = shadow + lit + col * 0.10;
		// Soft gravitational darkening toward the centre — a gradient, never a hard disc.
		voidcol *= mix(1.0, 0.14, smoothstep(0.42, 0.0, r));
		// Faint cool lensing shimmer — a soft halo, never a bright yellow ring.
		float shimmer = smoothstep(0.32, 0.20, r) * smoothstep(0.08, 0.20, r);
		voidcol += vec3(0.14, 0.22, 0.42) * shimmer * 0.12;
		col = mix(col, voidcol, dark_mix);
	}

	// The background is kept fully LDR (<= 1.0) so the environment Glow never blooms it —
	// nebulae and stars keep their exact shape. (Game FX glow because their emission goes
	// above the env's HDR threshold; the background never does.)
	ALBEDO = clamp(col * space_brightness, 0.0, 1.0);
}

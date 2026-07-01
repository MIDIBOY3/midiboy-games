shader_type spatial;
render_mode cull_back;

// Star-surface voxel blocks in ONE MultiMesh. Per-instance COLOR carries the block's
// TINT in rgb and its MATERIAL ID in alpha (id = floor(COLOR.a*8)):
//   0 stone, 1 dirt, 2 grass, 3 ore, 4 gold, 5 silver.
uniform float emission_energy = 0.0;
uniform float block_glow = 2.4;
// Star-wide style values are supplied once per MultiMesh. This remains branch-free for
// Mobile/Metal: every block keeps its material-ID treatment while sharing a planet mood.
uniform vec4 style_tint : source_color = vec4(1.0);
uniform vec4 style_vein_color : source_color = vec4(0.0);
uniform float style_colorize = 0.0;
uniform float style_metal_boost = 0.0;
uniform float style_rough_shift = 0.0;
uniform float style_vein_strength = 0.0;
uniform float style_vein_emission = 0.0;

varying flat float v_seed;
varying flat float v_id;

float h11(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	v_seed = h11(float(INSTANCE_ID) + 1.0);
	v_id = COLOR.a;
}

void fragment() {
	int id = int(floor(v_id * 8.0));
	vec3 base = COLOR.rgb;
	float v = v_seed;
	vec3 alb = base * mix(0.86, 1.14, v);
	float metal = 0.0;
	float rough = 0.92;
	float emiss = 0.0;

	if (id == 1) {
		rough = 0.98;
		alb = base * mix(0.8, 1.1, v);
	} else if (id == 2) {
		rough = 0.95;
		alb = base * mix(0.82, 1.14, v) + vec3(0.0, 0.05, 0.0) * step(0.55, v);
	} else if (id == 3) {
		rough = 0.7;
		metal = 0.25;
		alb = base * mix(0.8, 1.05, v);
		if (v > 0.62) {
			alb += vec3(0.28, 0.55, 1.0) * 0.55;
			emiss += 1.6;
		}
	} else if (id == 4) {
		metal = 0.5;
		rough = 0.34;
		alb = base * mix(0.92, 1.14, v);
		emiss += step(0.7, v) * 0.5;
	} else if (id == 5) {
		metal = 0.5;
		rough = 0.3;
		alb = base * mix(0.92, 1.12, v);
		emiss += step(0.75, v) * 0.6;
	} else {
		rough = 0.9;
		alb = base * mix(0.84, 1.14, v);
	}

	alb = mix(alb, style_tint.rgb * mix(0.72, 1.12, v), style_colorize);
	metal = clamp(metal + style_metal_boost, 0.0, 1.0);
	rough = clamp(rough + style_rough_shift, 0.08, 1.0);
	float vein = step(0.78, v) * style_vein_strength;
	alb += style_vein_color.rgb * vein;
	emiss += vein * style_vein_emission;

	ALBEDO = alb;
	METALLIC = metal;
	ROUGHNESS = rough;
	float lum = max(alb.r, max(alb.g, alb.b));
	float warm = clamp(alb.r - alb.b, 0.0, 1.0);
	float core = smoothstep(0.72, 1.0, lum) * warm;
	EMISSION = alb * emission_energy + alb * core * block_glow + alb * emiss;
}

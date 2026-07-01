shader_type spatial;
render_mode cull_disabled;

// Diamond-arena accent blocks. These used to be self-emissive; now they are glossy,
// light-reactive blocks so key lights and floor shadows remain visible.
uniform float energy = 1.0;

varying flat float v_seed;

float h(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	// One seed per voxel cell (block size ≈ 0.2 → *5 quantises to the cell).
	v_seed = h(floor(VERTEX * 5.0));
}

void fragment() {
	vec3 base = COLOR.rgb;
	vec3 col = base * mix(0.72, 1.12, v_seed);
	float vein = smoothstep(0.80, 0.96, v_seed);
	col += base * vein * 0.28;
	ALBEDO = col;
	METALLIC = 0.22;
	ROUGHNESS = mix(0.18, 0.38, v_seed);
	SPECULAR = 0.72;
}

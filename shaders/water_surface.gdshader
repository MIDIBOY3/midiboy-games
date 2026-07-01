shader_type spatial;
render_mode cull_disabled;

// 水・溶岩・ネオン運河のブロック面（トップ + 岸の側面壁）。
// 流れるテクスチャアニメは使わない方針：質感は「ガラスのような3Dブロック」。
// 静的な深浅のムラ + ごく緩やかな頂点のうねり + 強めのスペキュラ + 透過で
// 下の砂底や岸壁が透けて見える。溶岩・ネオンは glow で発光（ゆっくり脈動）。

uniform vec3 base_color = vec3(0.06, 0.26, 0.50);
uniform float glow = 0.4;        // エミッション強度（溶岩・ネオンは強）
uniform float alpha = 0.85;
uniform float wave_speed = 1.0;  // 頂点のうねり速度（溶岩はゆっくり）

varying vec2 wpos;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 43.21);
	return fract(p.x * p.y);
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

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xy;
	// 幾何的な静かなうねり（テクスチャは流さない）
	VERTEX.z += sin(wpos.x * 6.0 + TIME * wave_speed * 1.2) * 0.008
		+ cos(wpos.y * 5.0 + TIME * wave_speed * 0.9) * 0.008;
}

void fragment() {
	// 深場/浅瀬の静的なムラ（ワールド固定 — 地形と一体で動く）
	float depth_n = vnoise(wpos * 2.2);
	vec3 deep = base_color * 0.5;
	vec3 shallow = base_color * 1.3 + vec3(0.02, 0.04, 0.04);
	vec3 col = mix(deep, shallow, depth_n);
	// ごく薄い光のシーン（ゆっくり明滅、移動はしない）
	float sheen = 0.5 + 0.5 * sin(TIME * wave_speed * 0.5 + depth_n * 6.28318);
	col *= 0.96 + 0.08 * sheen;

	ALBEDO = col;
	EMISSION = base_color * glow * (0.45 + 0.25 * sheen);
	ALPHA = alpha;
	ROUGHNESS = 0.05;
	SPECULAR = 0.7;
	METALLIC = 0.1;
}

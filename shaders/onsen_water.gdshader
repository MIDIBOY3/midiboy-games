shader_type spatial;
render_mode cull_disabled, depth_draw_always;

// 温泉のお湯。トップダウンで「揺らめく湯面」を突き詰める版：
// 多重リップル→擬似法線を揺らし、固定ライト方向との反射で“動くきらめき”を出す。
// 乳白の温泉色（深浅ミックス）＋縁のフレネル明部＋ゆっくり脈動する内部発光（glowでにじむ）。
// シーンのランタン光ともSPECULARで照り合う。

uniform vec3 deep_color : source_color = vec3(0.04, 0.26, 0.30);
uniform vec3 shallow_color : source_color = vec3(0.42, 0.74, 0.72);
uniform vec3 sheen_color : source_color = vec3(0.90, 1.00, 0.98);
uniform float water_alpha = 0.86;
uniform float glow = 0.5;
uniform float ripple_speed = 1.0;
uniform float ripple_scale = 9.0;

varying vec3 wpos;

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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.0 + vec2(7.3, 3.1);
		a *= 0.5;
	}
	return v;
}

// 湯面の高さ場（多重リップル＋ゆらぎ）
float height(vec2 p, float t) {
	float h = 0.0;
	h += sin(p.x * ripple_scale + t * 1.3) * 0.25;
	h += sin(p.y * ripple_scale * 1.18 - t * 1.05) * 0.25;
	h += sin((p.x + p.y) * ripple_scale * 0.6 + t * 0.8) * 0.2;
	h += fbm(p * 2.2 + vec2(t * 0.12, -t * 0.10)) * 0.6;
	return h;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * ripple_speed;
	VERTEX.z += (height(wpos.xy, t) - 0.5) * 0.012;   // 緩やかな実うねり（細分割メッシュで効く）
}

void fragment() {
	vec2 uv = wpos.xy;
	float t = TIME * ripple_speed;
	float e = 0.045;
	float h = height(uv, t);
	float hx = height(uv + vec2(e, 0.0), t);
	float hy = height(uv + vec2(0.0, e), t);
	vec3 nrm = normalize(vec3((h - hx) / e, (h - hy) / e, 4.0));

	// 乳白の温泉色：高さ場で深浅をミックス
	float shade = clamp(h * 0.6 + 0.4, 0.0, 1.0);
	vec3 col = mix(deep_color, shallow_color, shade);

	// 動くスペキュラのきらめき（固定ライト方向 × 揺れる法線）
	vec3 L1 = normalize(vec3(0.35, 0.45, 0.82));
	vec3 L2 = normalize(vec3(-0.40, -0.25, 0.88));
	vec3 V = vec3(0.0, 0.0, 1.0);
	float s1 = pow(max(dot(reflect(-L1, nrm), V), 0.0), 48.0);
	float s2 = pow(max(dot(reflect(-L2, nrm), V), 0.0), 64.0);
	float glints = s1 + s2 * 0.7;

	// 縁のフレネル明部
	float fres = pow(1.0 - clamp(nrm.z, 0.0, 1.0), 2.5);

	// ゆっくりした内部発光の脈動
	float pulse = 0.6 + 0.4 * sin(t * 0.5 + h * 6.2831);

	ALBEDO = col;
	EMISSION = col * glow * (0.5 + 0.3 * pulse) + sheen_color * (glints * 1.2 + fres * 0.25);
	ALPHA = clamp(water_alpha + glints * 0.1, 0.0, 1.0);
	ROUGHNESS = 0.06;
	SPECULAR = 0.9;
	METALLIC = 0.0;
}

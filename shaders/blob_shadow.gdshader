// Soft round drop-shadow for the top-down GOLDEN walk arena. A camera-facing quad with a
// radial alpha falloff — no texture needed — laid on the floor under the mech so it reads as
// grounded (影を感じる). Unshaded + mix-blend + never writing depth so it never self-occludes.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float strength : hint_range(0.0, 1.0) = 0.55;
uniform vec3 shadow_color : source_color = vec3(0.0, 0.0, 0.02);

void fragment() {
	float d = distance(UV, vec2(0.5));      // 0 at centre .. ~0.707 at corners
	float a = smoothstep(0.5, 0.06, d);     // soft disc, faded edge
	ALBEDO = shadow_color;
	ALPHA = a * strength;
}

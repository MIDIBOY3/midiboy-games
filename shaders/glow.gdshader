shader_type spatial;
// A pure, edgeless light bloom: a camera-facing billboard whose alpha falls off radially
// to zero at the rim, blended additively — reads as a light source, not an object.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 glow_color : source_color = vec4(0.85, 0.95, 1.0, 1.0);
uniform float intensity = 4.0;
uniform float softness = 2.4;   // higher = tighter core, softer halo

void vertex() {
	// Billboard: always face the camera (ignore the node's own rotation/orbit tilt), but
	// KEEP the node's scale so growing the node (e.g. an explosion flash) still works.
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0] * sx,
		INV_VIEW_MATRIX[1] * sy,
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]);
}

void fragment() {
	float d = distance(UV, vec2(0.5)) * 2.0;        // 0 at centre → 1 at the rim
	float a = pow(clamp(1.0 - d, 0.0, 1.0), softness);
	EMISSION = glow_color.rgb * intensity * a;
	ALPHA = a;                                       // fades to 0 at the edge → no edge
}

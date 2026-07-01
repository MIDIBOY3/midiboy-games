shader_type spatial;
render_mode blend_add, cull_back, unshaded, depth_draw_never;

// Glowing atmosphere halo for the ending homeworld. A Fresnel rim on a sphere a touch
// larger than the planet: transparent where we look straight through (so the globe
// shows), brightening to a luminous limb at the silhouette. Additive + emissive so the
// scene's WorldEnvironment glow blooms it into a soft, majestic halo. Stack two of these
// (a tight bright rim + a wide soft glow) for depth.

uniform vec3 glow_color : source_color = vec3(0.40, 0.70, 1.0);
uniform float rim_power = 2.4;     // higher = thinner, sharper rim
uniform float intensity = 1.6;
uniform float twinkle = 0.0;       // gentle breathing of the halo (0 = steady)

void fragment() {
	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fres = pow(1.0 - ndv, rim_power);
	float pulse = 1.0 + twinkle * sin(TIME * 0.8);
	float a = clamp(fres * intensity * pulse, 0.0, 1.0);
	ALBEDO = glow_color;
	EMISSION = glow_color * fres * intensity * pulse;
	ALPHA = a;
}

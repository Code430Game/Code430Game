shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// The patch of road a traffic car's headlights light at night: one MultiMesh instance per car,
// a flat quad ahead of it (the plane's -Z end is the far end). Brightest near the car, fading
// to the sides and toward the far end; `night` (DayNight) fades the whole lot in after dusk.
uniform float night = 0.0;
uniform vec3 tint : source_color = vec3(1.0, 0.92, 0.75);
uniform float strength = 0.5;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;  // -1..1 across, -1 far .. 1 near
	float across = 1.0 - smoothstep(0.35, 1.0, abs(p.x) * (0.75 + 0.25 * (p.y * 0.5 + 0.5)));
	float along = smoothstep(-1.0, -0.2, p.y) * (1.0 - smoothstep(0.75, 1.0, p.y));
	float near = mix(0.45, 1.0, p.y * 0.5 + 0.5);
	ALBEDO = tint * across * along * near * strength * night;
}

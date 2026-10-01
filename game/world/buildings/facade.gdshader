shader_type spatial;
render_mode cull_back;

// Procedural facades. UV is in metres (u along the wall, v up from the ground),
// UV2.x is the treatment (0 plain, 1 punched brick, 2 glass grid, 3 stone tall,
// -1 roof), UV2.y is a per-building seed. COLOR is the sRGB base colour.

uniform float storey_height_m = 3.2;
uniform float night = 0.0;  // 0 by day, 1 at night: lit windows glow

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec3 srgb_to_linear(vec3 c) {
	return pow(c, vec3(2.2));
}

void fragment() {
	vec3 base = srgb_to_linear(COLOR.rgb);
	float treatment = UV2.x;
	float seed = UV2.y;
	float u = UV.x;
	float v = UV.y;
	vec3 albedo = base;
	float rough = 0.9;
	float metal = 0.0;
	vec3 glow = vec3(0.0);
	if (treatment >= 0.5 && v > 0.0) {
		float storey = floor(v / storey_height_m);
		float sv = fract(v / storey_height_m);           // 0..1 within the storey
		float cell_w = 3.0;
		float win_w = 0.45;
		float win_lo = 0.30;
		float win_hi = 0.72;
		vec3 glass = vec3(0.10, 0.13, 0.18);
		if (treatment >= 1.5 && treatment < 2.5) {       // glass grid
			cell_w = 1.6;
			win_w = 0.86;
			win_lo = 0.12;
			win_hi = 0.92;
			glass = vec3(0.16, 0.22, 0.30);
		} else if (treatment >= 2.5) {                   // stone, tall windows
			cell_w = 3.6;
			win_w = 0.34;
			win_lo = 0.18;
			win_hi = 0.84;
			glass = vec3(0.09, 0.10, 0.12);
		}
		float col = floor(u / cell_w);
		float su = fract(u / cell_w);
		float in_col = step(abs(su - 0.5), win_w * 0.5);
		float in_row = step(win_lo, sv) * step(sv, win_hi);
		float lit = step(0.72, hash21(vec2(col + seed * 97.0, storey + seed * 31.0)));
		vec3 window = mix(glass, glass + vec3(0.55, 0.45, 0.25), lit * 0.6);
		float is_window = in_col * in_row;
		if (storey < 0.5 && treatment >= 1.5 && treatment < 2.5) {
			is_window = step(0.10, sv) * step(sv, 0.95);   // glass storefront at street level
		}
		albedo = mix(base, window, is_window);
		glow = vec3(1.0, 0.82, 0.55) * lit * is_window * 1.0;
		rough = mix(0.9, 0.25, is_window);
		metal = mix(0.0, 0.1, is_window);
		// faint storey line
		albedo *= 1.0 - 0.10 * step(sv, 0.04) * (1.0 - is_window);
		// per-building tone variation
		albedo *= 0.94 + 0.12 * hash21(vec2(seed, 7.0));
	} else if (treatment < -0.5) {
		albedo = base * 0.85;                            // roof
	}
	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = glow * night;
}

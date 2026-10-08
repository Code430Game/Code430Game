shader_type spatial;
render_mode cull_back;

// Procedural facades. UV is in metres (u along the wall, v up from the ground),
// UV2.x is the treatment, UV2.y a per-building seed, COLOR the sRGB base colour.
// Treatments: 0 plain, 1 punched brick, 2 glass grid, 3 stone tall, 4 stucco (small
// windows), 5 precast (wide bands), 6 curtain wall; +10 marks a shopfront ground floor;
// -1 is a roof, -2 trim (parapets, balconies, roof boxes: shaded, no windows).

uniform float storey_height_m = 3.2;
uniform float night = 0.0;  // 0 by day, 1 at night: lit windows glow
uniform float snow = 0.0;  // add-weather: roofs and trim whiten
uniform float wetness = 0.0;  // walls darken a little in the rain

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec3 srgb_to_linear(vec3 c) {
	return pow(c, vec3(2.2));
}

vec3 hue_color(float h) {
	return 0.55 + 0.45 * cos(6.28318 * (vec3(h) + vec3(0.0, 0.33, 0.67)));
}

void fragment() {
	vec3 base = srgb_to_linear(COLOR.rgb);
	float treatment = UV2.x;
	float seed = UV2.y;
	bool shopfront = treatment >= 9.5;
	if (shopfront) {
		treatment -= 10.0;
	}
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
		float frame = 0.0;                               // mullion darkening for curtain walls
		if (treatment >= 1.5 && treatment < 2.5) {       // glass grid
			cell_w = 1.6;
			win_w = 0.86;
			win_lo = 0.12;
			win_hi = 0.92;
			glass = vec3(0.16, 0.22, 0.30);
		} else if (treatment >= 2.5 && treatment < 3.5) { // stone, tall windows
			cell_w = 3.6;
			win_w = 0.34;
			win_lo = 0.18;
			win_hi = 0.84;
			glass = vec3(0.09, 0.10, 0.12);
		} else if (treatment >= 3.5 && treatment < 4.5) { // stucco, small windows
			cell_w = 2.6;
			win_w = 0.36;
			win_lo = 0.34;
			win_hi = 0.68;
			glass = vec3(0.12, 0.14, 0.16);
		} else if (treatment >= 4.5 && treatment < 5.5) { // precast, wide bands
			cell_w = 4.0;
			win_w = 0.80;
			win_lo = 0.38;
			win_hi = 0.80;
			glass = vec3(0.12, 0.16, 0.20);
		} else if (treatment >= 5.5) {                   // curtain wall: all glass, mullions
			cell_w = 1.5;
			win_w = 1.0;
			win_lo = 0.0;
			win_hi = 1.0;
			glass = mix(vec3(0.14, 0.20, 0.28), vec3(0.20, 0.24, 0.26), seed);
			frame = 1.0;
		}
		float col = floor(u / cell_w);
		float su = fract(u / cell_w);
		float in_col = step(abs(su - 0.5), win_w * 0.5);
		float in_row = step(win_lo, sv) * step(sv, win_hi);
		float lit = step(0.72, hash21(vec2(col + seed * 97.0, storey + seed * 31.0)));
		vec3 window = mix(glass, glass + vec3(0.55, 0.45, 0.25), lit * 0.6);
		float is_window = in_col * in_row;
		if (frame > 0.5) {
			float mull = step(su, 0.04) + step(0.96, su) + step(sv, 0.03);
			window = mix(window, vec3(0.05), clamp(mull, 0.0, 1.0) * 0.8);
		}
		if (storey < 0.5 && (shopfront || (treatment >= 1.5 && treatment < 2.5))) {
			is_window = step(0.10, sv) * step(sv, 0.88);
			if (shopfront) {
				// awnings over the shop bays only, in a muted seeded colour
				float bay = step(abs(fract(u / 4.0) - 0.5), 0.42);
				float awning = step(0.86, sv) * step(sv, 0.98) * bay;
				vec3 awning_col = mix(hue_color(seed + floor(u / 4.0) * 0.17), vec3(0.45), 0.45) * 0.7;
				base = mix(base, srgb_to_linear(awning_col), awning);
				is_window *= bay;
				window = mix(vec3(0.08, 0.10, 0.12), vec3(0.25, 0.22, 0.16), lit * 0.5);
			}
		}
		albedo = mix(base, window, is_window);
		glow = vec3(1.0, 0.82, 0.55) * lit * is_window * 1.0;
		rough = mix(0.9, 0.25, is_window);
		metal = mix(0.0, 0.1, is_window);
		albedo *= 1.0 - 0.10 * step(sv, 0.04) * (1.0 - is_window);
		albedo *= 0.94 + 0.12 * hash21(vec2(seed, 7.0));
		if (treatment >= 0.5 && treatment < 1.5) {
			albedo *= 1.0 - 0.06 * step(fract(v / 0.3), 0.12) * (1.0 - is_window);
		}
	} else if (treatment < -1.5) {
		albedo = mix(base * 0.75, vec3(0.86, 0.88, 0.92), snow * 0.6);  // trim
		rough = 0.8;
	} else if (treatment < -0.5) {
		albedo = mix(base * 0.85, vec3(0.88, 0.90, 0.94), snow);       // roof
		rough = mix(rough, 0.8, snow);
	}
	albedo *= 1.0 - 0.18 * wetness;
	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metal;
	EMISSION = glow * night;
}

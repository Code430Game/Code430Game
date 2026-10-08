shader_type sky;
// The sky: a day-night gradient (DayNight feeds the colours by the hour), the sun disc and a
// halo from the first directional light, and scrolling clouds from a seamless noise texture.
// Coverage thresholds the noise; the edge softens banks; undersides darken as the noise thickens.
// cloud_layers 1 on the deck preset, 2 on high (the second at half scale, a quarter the speed).

uniform vec3 top_color : source_color = vec3(0.25, 0.42, 0.72);
uniform vec3 horizon_color : source_color = vec3(0.68, 0.72, 0.78);
uniform vec3 ground_color : source_color = vec3(0.15, 0.15, 0.17);
uniform float night = 0.0;
uniform float cloud_coverage = 0.15;
uniform vec2 cloud_offset = vec2(0.0);
uniform vec3 cloud_tint : source_color = vec3(1.0);
uniform int cloud_layers = 1;
uniform float cloud_scale = 0.30;
uniform float sun_disc = 1.0;  // 0 hides the sun (fog)
uniform sampler2D cloud_noise : hint_default_white, filter_linear_mipmap, repeat_enable;

void sky() {
	vec3 dir = EYEDIR;
	float h = clamp(dir.y, -1.0, 1.0);
	vec3 col;
	if (h >= 0.0) {
		col = mix(horizon_color, top_color, pow(h, 0.55));
	} else {
		col = mix(horizon_color, ground_color, pow(-h, 0.5));
	}
	float sunlit = 0.3;
	if (LIGHT0_ENABLED) {
		float cosang = dot(dir, LIGHT0_DIRECTION);
		float disc = smoothstep(0.99905, 0.99965, cosang);
		float halo = pow(max(cosang, 0.0), 48.0) * 0.22;
		float through = 1.0 - cloud_coverage * 0.85;
		col += LIGHT0_COLOR * LIGHT0_ENERGY * (disc * 1.6 + halo) * sun_disc * through;
		sunlit = clamp(LIGHT0_DIRECTION.y * 1.6 + 0.35, 0.12, 1.0);
	}
	if (h > 0.015) {
		vec2 uv = dir.xz / (h + 0.18) * cloud_scale;
		float n = texture(cloud_noise, uv * 0.5 + cloud_offset).r;
		if (cloud_layers > 1) {
			n = n * 0.62 + texture(cloud_noise, uv * 0.23 + cloud_offset * 0.25 + vec2(0.31, 0.67)).r * 0.38;
		}
		// The noise sits around 0.5; this threshold covers about `cloud_coverage` of the sky.
		float thr = 0.5 + (0.5 - cloud_coverage) * 0.45;
		float edge = mix(0.10, 0.05, cloud_coverage);
		float c = smoothstep(thr - edge, thr + edge, n);
		float fade = smoothstep(0.015, 0.22, h);
		vec3 lit = cloud_tint * mix(0.62, 1.05, sunlit);
		float thick = smoothstep(thr, min(thr + 0.3, 1.0), n);
		vec3 cloud_col = lit * mix(1.0, 0.66, thick) * (1.0 - night * 0.86);
		col = mix(col, cloud_col, c * fade);
	}
	COLOR = col;
}

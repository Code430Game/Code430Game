shader_type spatial;
// Ground surfaces (roads, junctions, lots, sidewalks, markings): the vertex colour, authored in
// sRGB, times a world-space detail texture (SurfaceDetail). The texture is centred on mid-grey,
// so 0.5 leaves the colour alone; it also nudges roughness. With `macro`, a second sample at a
// much larger scale breaks up the tiling (the high preset).

render_mode cull_back;

uniform sampler2D detail : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_m = 4.0;
uniform float strength = 1.0;
uniform float roughness = 0.9;
uniform bool macro = false;
uniform vec3 emission_color = vec3(0.0);
// Slab joints (sidewalks): UV = metres along/across the ribbon, UV2 = (width, slab length).
uniform bool joints = false;
uniform float joint_w_m = 0.025;
uniform float emission_energy = 0.0;
// Weather (add-weather): `wetness` darkens and polishes the surface so lights reflect in it,
// `snow` whitens it by `snow_cover` (1 on sidewalks and lots, 0 on ploughed roads and paint).
uniform float wetness = 0.0;
uniform float snow = 0.0;
uniform float snow_cover = 0.0;
uniform vec3 snow_color : source_color = vec3(0.86, 0.88, 0.92);

varying vec3 world_pos;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float d = texture(detail, world_pos.xz / tile_m).r - 0.5;
	if (macro) {
		d += (texture(detail, world_pos.xz / (tile_m * 9.7) + vec2(0.37, 0.71)).r - 0.5) * 0.6;
	}
	vec3 base = srgb_to_linear(COLOR.rgb);
	ALBEDO = base * (1.0 + d * 2.0 * strength);
	ROUGHNESS = clamp(roughness - d * 0.3, 0.0, 1.0);
	if (joints && UV2.y > 0.0) {
		float slab = UV2.y;
		float into = fract(UV.x / slab) * slab;
		float gap = min(into, slab - into);
		float w = max(joint_w_m, fwidth(UV.x));  // widen with distance so lines do not shimmer
		float line = 1.0 - smoothstep(w, w * 2.0, gap);
		if (UV2.x > 3.0) {  // wide ribbons get a joint down the middle too
			float wc = max(joint_w_m, fwidth(UV.y));
			line = max(line, 1.0 - smoothstep(wc, wc * 2.0, abs(UV.y)));
		}
		ALBEDO *= mix(1.0, 0.7, line);
	}
	ALBEDO = mix(ALBEDO, ALBEDO * 0.6, wetness);
	ROUGHNESS = mix(ROUGHNESS, 0.2, wetness);
	SPECULAR = mix(0.5, 0.7, wetness);
	float s = snow * snow_cover;
	ALBEDO = mix(ALBEDO, snow_color * (1.0 + d * 0.6), s);
	ROUGHNESS = mix(ROUGHNESS, 0.78, s);
	EMISSION = emission_color * emission_energy * (1.0 - s);
}

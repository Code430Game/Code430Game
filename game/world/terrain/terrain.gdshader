shader_type spatial;
// Terrain: one colour, darkened while wet and whitened under snow (add-weather). The weather
// controller writes `wetness` and `snow` on the shared material once per frame.
render_mode cull_back;

uniform vec3 base_color : source_color = vec3(0.30, 0.36, 0.26);
uniform vec3 snow_color : source_color = vec3(0.88, 0.90, 0.94);
uniform float wetness = 0.0;
uniform float snow = 0.0;

void fragment() {
	vec3 a = base_color * (1.0 - 0.28 * wetness);
	ALBEDO = mix(a, snow_color, snow);
	ROUGHNESS = mix(1.0, 0.8, snow);
	SPECULAR = mix(0.3, 0.45, wetness);
}

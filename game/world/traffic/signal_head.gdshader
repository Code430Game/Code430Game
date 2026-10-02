shader_type spatial;
// Signal lamp: the per-instance colour is both the albedo and the glow, so a red lamp glows
// red after dusk instead of the flat white emission a StandardMaterial3D gives every instance.
uniform float day_energy = 0.8;
uniform float night_energy = 3.0;
uniform float night : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.4;
	EMISSION = COLOR.rgb * mix(day_energy, night_energy, night);
}

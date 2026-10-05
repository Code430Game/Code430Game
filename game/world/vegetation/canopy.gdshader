shader_type spatial;
render_mode cull_disabled;
// Trees and bushes (add-vegetation): vertex colour times the MultiMesh instance colour, and on
// the high preset a gentle sway of the canopy (vertices above the trunk) phased per instance.

uniform bool sway = false;
uniform float sway_amount = 0.03;
uniform float sway_speed = 1.3;

void vertex() {
	if (sway) {
		float lift = clamp((VERTEX.y - 0.35) / 0.65, 0.0, 1.0);
		float phase = float(INSTANCE_ID) * 1.7;
		VERTEX.x += sin(TIME * sway_speed + phase) * sway_amount * lift;
		VERTEX.z += cos(TIME * sway_speed * 0.8 + phase) * sway_amount * 0.7 * lift;
	}
}

void fragment() {
	ALBEDO = pow(COLOR.rgb, vec3(2.2));  // vertex colours are sRGB, as on the other world materials
	ROUGHNESS = 0.95;
}

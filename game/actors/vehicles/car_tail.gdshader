shader_type spatial;
render_mode cull_back;

// Traffic tail lights: red vertex colour, a night glow, and a brake flash per instance
// through INSTANCE_CUSTOM.r (the MultiMesh custom data), so each car brakes on its own.
uniform float night = 0.0;

varying float brake;

void vertex() {
	brake = INSTANCE_CUSTOM.r;
}

void fragment() {
	vec3 base = pow(COLOR.rgb, vec3(2.2));
	ALBEDO = base;
	ROUGHNESS = 0.3;
	EMISSION = vec3(1.0, 0.12, 0.08) * (night * 2.4 + brake * 5.0);
}

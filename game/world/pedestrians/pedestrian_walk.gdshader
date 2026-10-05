shader_type spatial;
// Walk cycle for the pedestrian crowd: the pool mesh is in the rest pose with each vertex's bone
// index in CUSTOM0.r; each vertex is carried up its bone chain with the rotations of
// CharacterMesh.walk_pose, so every instance walks with its own phase in one draw.
// INSTANCE_CUSTOM.x = phase (radians), .y = amount 0..1; .zw are free (reserved for paint marks).
// Bone order and parents follow CharacterMesh.BONES; keep the WALK_ constants equal to
// CharacterMesh's (test_pedestrian_walk.gd checks them).

render_mode cull_back;

const float WALK_SWING = 0.55;
const float WALK_KNEE = 0.9;
const float WALK_ARM = 0.8;
const float WALK_ELBOW = 0.35;
const float WALK_BOB = 0.025;

// hips, spine, head, upper_arm_l, forearm_l, upper_arm_r, forearm_r, thigh_l, shin_l, thigh_r, shin_r
const int PARENT[11] = int[](-1, 0, 1, 1, 3, 1, 5, 0, 7, 0, 9);

// Bone pivots in model space for this pool's profile (CharacterMesh.bone_pivot).
uniform vec3 pivots[11];

float bone_angle(int b, float phase, float amount) {
	float swing = WALK_SWING * amount;
	if (b == 7) return -swing * sin(phase);
	if (b == 9) return swing * sin(phase);
	if (b == 8) return -WALK_KNEE * amount * max(0.0, sin(phase - PI * 0.5));
	if (b == 10) return -WALK_KNEE * amount * max(0.0, sin(phase + PI * 0.5));
	if (b == 3) return WALK_ARM * swing * sin(phase);
	if (b == 5) return -WALK_ARM * swing * sin(phase);
	if (b == 4 || b == 6) return WALK_ELBOW * amount;
	return 0.0;
}

vec3 rot_x(vec3 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(p.x, c * p.y - s * p.z, s * p.y + c * p.z);
}

// Paint from weapons (add-weapons-and-combat): INSTANCE_CUSTOM.z is the palette index + 1 (0 =
// clean), .w how much; splotches by position so it reads as paint, not a dye.
const vec3 PAINT[4] = vec3[](vec3(0.95, 0.25, 0.55), vec3(0.2, 0.75, 0.95), vec3(0.98, 0.82, 0.15), vec3(0.45, 0.9, 0.3));
varying vec2 paint;
varying vec3 local_pos;

void vertex() {
	paint = INSTANCE_CUSTOM.zw;
	local_pos = VERTEX;
	float phase = INSTANCE_CUSTOM.x;
	float amount = INSTANCE_CUSTOM.y;
	int b = int(CUSTOM0.r + 0.5);
	vec3 p = VERTEX - pivots[b];
	vec3 n = NORMAL;
	for (int depth = 0; depth < 4 && b >= 0; depth++) {
		int parent = PARENT[b];
		float a = bone_angle(b, phase, amount);
		p = rot_x(p, a);
		n = rot_x(n, a);
		p += pivots[b] - (parent >= 0 ? pivots[parent] : vec3(0.0));
		if (parent < 0) {
			p.y += WALK_BOB * amount * abs(sin(phase));
		}
		b = parent;
	}
	VERTEX = p;
	NORMAL = n;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	if (paint.x > 0.5) {
		vec3 q = local_pos * 7.0;
		float splotch = step(0.15, sin(q.x * 1.3 + q.y * 0.7) * sin(q.y * 1.1 - q.z * 0.9) + 0.35);
		ALBEDO = mix(ALBEDO, PAINT[clamp(int(paint.x + 0.5) - 1, 0, 3)], splotch * paint.y);
	}
	ROUGHNESS = 0.8;
}

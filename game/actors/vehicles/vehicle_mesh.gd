class_name VehicleMesh
extends RefCounted
## Parametric low-poly vehicle bodies for every catalogue class, at two levels of detail. An
## entry with a kit `model` draws that at LOD0 instead (KitVehicle); LOD1 stays parametric.
##
## Approach: a side profile (z along the vehicle, y up; -Z is the front) is computed from the
## entry's dims for its body class, then extruded across the width into a hull; the cabin sits
## a little inboard. LOD0 adds wheel wells cut into the side skirts (with dark liners), bumpers,
## window panes with pillars between them, mirrors, a grille, lens-mapped lights, plates and
## class parts (pickup bed, box truck cargo box, taxi sign and check band). LOD1 is the hull
## with glass sides, lights and six-sided wheels. Every face carries its own outward normal
## (flat shading) and is wound to match it. UVs map details to TrimSheet cells; everything
## else samples the white blank cell.
##
## Surfaces: 0 body (white vertices: the material tint or MultiMesh instance colour paints
## them), 1 dark parts (glass, trim, wheels, plates, white cargo boxes), 2 headlights,
## 3 tail lights (own surface so the player's car can swap in a brake material). Origin on the
## ground under the vehicle's centre; the wheels touch y = 0.

enum Lod { LOD0, LOD1 }

const GLASS_COLOR := Color(0.14, 0.17, 0.21)
const DARK_COLOR := Color(0.09, 0.09, 0.10)
const TRIM_COLOR := Color(0.16, 0.16, 0.17)
const HEADLIGHT_COLOR := Color(1.0, 0.97, 0.85)
const TAILLIGHT_COLOR := Color(0.9, 0.12, 0.1)
const TUMBLEHOME_M := 0.08  # cabin sides inboard of the body sides
const PROUD_M := 0.006  # decals (panes, bands, lights, plates) stand off the face they sit on
const LIGHT_NIGHT_ENERGY := 4.0
## Triangle budgets per class (tests hold the generator to them).
const LOD0_BUDGET := {"sedan": 900, "hatchback": 900, "coupe": 900, "taxi": 900, "suv": 1100, "pickup": 1100, "van": 1100, "box_truck": 1300, "bus": 1300}
const LOD1_BUDGET := 260


## Builds the mesh for a catalogue entry. With wheels, wheel geometry is included (traffic);
## the player's car has wheel nodes and leaves them out. `livery` is the entry's livery
## variant for the current mode (stripe, roof sign), {} for none.
static func build(entry: Dictionary, lod: int = Lod.LOD0, with_wheels: bool = true, livery: Dictionary = {}) -> ArrayMesh:
	if lod == Lod.LOD0 and KitVehicle.has_model(entry):
		return KitVehicle.build(entry, with_wheels)
	if str(entry.get("body_class", "sedan")) == "bus":
		return BusMesh.build(with_wheels)
	var b := _Builder.new(entry, lod, livery)
	b.hull()
	b.sides()
	b.lights()
	if lod == Lod.LOD0:
		b.details()
	b.class_parts()
	if with_wheels:
		b.wheels()
	return b.commit()


## A copy of `mesh` pushed in around each of `dents` ([{"at": Vector3, "depth": float}] in the
## mesh's frame, add-vehicle-and-building-damage): vertices within `radius` of a dent move
## toward the body's middle line by up to its depth, easing to none at the edge. Each surface
## keeps its material. Moved triangles get new flat normals, so the crumple catches the light,
## and the paint (surface 0's vertex colour) is scraped darker around each dent. `mesh` itself
## is untouched, so cars that share it are not dented.
static func dented(mesh: ArrayMesh, dents: Array, radius: float) -> ArrayMesh:
	var out := ArrayMesh.new()
	for si in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var moved := PackedByteArray()
		moved.resize(verts.size())
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		for vi in range(verts.size()):
			var v := verts[vi]
			verts[vi] = dent_point(v, dents, radius)
			if verts[vi] != v:
				moved[vi] = 1
				if si == 0 and vi < colors.size():
					colors[vi] = colors[vi] * scrape_shade(v, dents, radius)
		arrays[Mesh.ARRAY_VERTEX] = verts
		if si == 0 and not colors.is_empty():
			arrays[Mesh.ARRAY_COLOR] = colors
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		if normals.size() == verts.size() and mesh.surface_get_primitive_type(si) == Mesh.PRIMITIVE_TRIANGLES:
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var tris := idx.size() if not idx.is_empty() else verts.size()
			for t in range(0, tris - 2, 3):
				var i0 := idx[t] if not idx.is_empty() else t
				var i1 := idx[t + 1] if not idx.is_empty() else t + 1
				var i2 := idx[t + 2] if not idx.is_empty() else t + 2
				if moved[i0] == 0 and moved[i1] == 0 and moved[i2] == 0:
					continue
				# Godot winds front faces clockwise: the normal is (c - a) x (b - a).
				var n := (verts[i2] - verts[i0]).cross(verts[i1] - verts[i0])
				if n.length() < 1e-8:
					continue
				n = n.normalized()
				if n.dot(normals[i0] + normals[i1] + normals[i2]) < 0.0:
					n = -n  # keep it on the side the old normals faced
				normals[i0] = n
				normals[i1] = n
				normals[i2] = n
			arrays[Mesh.ARRAY_NORMAL] = normals
		out.add_surface_from_arrays(mesh.surface_get_primitive_type(si), arrays)
		out.surface_set_material(si, mesh.surface_get_material(si))
	return out


## How much a scrape darkens the paint at `v`: 1 untouched, down to 0.3 at a dent's middle.
static func scrape_shade(v: Vector3, dents: Array, radius: float) -> float:
	var shade := 1.0
	for d: Dictionary in dents:
		var k := 1.0 - v.distance_to(d["at"]) / radius
		if k > 0.0:
			shade = minf(shade, lerpf(1.0, 0.3, k))
	return shade


## `v` moved by `dents` (see dented): toward the middle line at the dent's height, never past it.
static func dent_point(v: Vector3, dents: Array, radius: float) -> Vector3:
	for d: Dictionary in dents:
		var at: Vector3 = d["at"]
		var dist := v.distance_to(at)
		if dist >= radius:
			continue
		var inward: Vector3
		if absf(at.x) * 2.0 > absf(at.z):
			inward = Vector3(-at.x, 0.0, 0.0)  # a side hit pushes the side in
		else:
			inward = Vector3(0.0, 0.0, -at.z)  # a front or rear hit pushes it back
		if inward.length() < 0.001:
			inward = Vector3.DOWN  # straight down onto the roof
		var k := 1.0 - dist / radius
		v += inward.normalized() * float(d["depth"]) * k * k
	return v


## Wheel centre positions (x, y, z) for an entry, front left first: for wheel nodes and tests.
static func wheel_positions(entry: Dictionary) -> Array[Vector3]:
	var d: Dictionary = entry.get("dims", {})
	var length := float(d.get("length_m", 4.6))
	var wr := float(d.get("wheel_radius_m", 0.33))
	var front := -length * 0.5 + float(d.get("front_overhang_m", 0.9))
	var rear := front + float(d.get("wheelbase_m", 2.7))
	var hx := float(d.get("track_m", 1.56)) * 0.5
	return [Vector3(-hx, wr, front), Vector3(hx, wr, front), Vector3(-hx, wr, rear), Vector3(hx, wr, rear)]


## Collision box size (width, height, length) for an entry.
static func box_size(entry: Dictionary) -> Vector3:
	var d: Dictionary = entry.get("dims", {})
	return Vector3(float(d.get("width_m", 1.8)), float(d.get("height_m", 1.45)) * 0.9, float(d.get("length_m", 4.6)))


# --- shared materials (one instance each, so DayNight can drive them all) ---

static var _lights: StandardMaterial3D = null
static var _tails: StandardMaterial3D = null
static var _brake: StandardMaterial3D = null
static var _dark: StandardMaterial3D = null


## Tintable body material: vertex colour (white) times the tint (or the MultiMesh instance
## colour) times the trim sheet.
static func body_material(tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_color = tint
	m.albedo_texture = TrimSheet.texture()
	m.roughness = 0.35
	m.metallic = 0.25
	return m


static func dark_material() -> StandardMaterial3D:
	if _dark == null:
		_dark = StandardMaterial3D.new()
		_dark.vertex_color_use_as_albedo = true
		_dark.albedo_texture = TrimSheet.texture()
		_dark.roughness = 0.3
		_dark.metallic = 0.1
	return _dark


static var _broken: StandardMaterial3D


## A smashed light (add-vehicle-and-building-damage): dark, dull and never glowing, whatever the
## lens's vertex colour.
static func broken_light_material() -> StandardMaterial3D:
	if _broken == null:
		_broken = StandardMaterial3D.new()
		_broken.albedo_color = Color(0.06, 0.06, 0.065)
		_broken.roughness = 0.9
	return _broken


## Headlights: lens texture, glow after dusk (DayNight raises the energy).
static func light_material() -> StandardMaterial3D:
	if _lights == null:
		_lights = StandardMaterial3D.new()
		_lights.vertex_color_use_as_albedo = true
		_lights.albedo_texture = TrimSheet.texture()
		_lights.emission_enabled = true
		_lights.emission = Color(1.0, 0.9, 0.7)
		_lights.emission_energy_multiplier = 0.0
	return _lights


## Tail lights: red glow after dusk (DayNight raises the energy).
static func tail_material() -> StandardMaterial3D:
	if _tails == null:
		_tails = StandardMaterial3D.new()
		_tails.vertex_color_use_as_albedo = true
		_tails.emission_enabled = true
		_tails.emission = Color(1.0, 0.12, 0.08)
		_tails.emission_energy_multiplier = 0.0
	return _tails


## Bright red for the player's tail lights while braking, day or night.
static func brake_material() -> StandardMaterial3D:
	if _brake == null:
		_brake = StandardMaterial3D.new()
		_brake.vertex_color_use_as_albedo = true
		_brake.emission_enabled = true
		_brake.emission = Color(1.0, 0.1, 0.05)
		_brake.emission_energy_multiplier = 5.0
	return _brake


const POLICE_BLUE := Color(0.08, 0.18, 0.6)
const AMBULANCE_RED := Color(0.75, 0.08, 0.1)


class _Builder:
	var e: Dictionary
	var lod: int
	var livery: Dictionary
	var cls: String
	var st: Array[SurfaceTool] = []
	# dims
	var length: float
	var width: float
	var height: float
	var wr: float
	var hw: float
	var zf: float
	var zr: float
	var cl: float  # body underside
	var hb: float  # belt line / bonnet height
	var axles: Array[float] = []
	var profile: Array = []  # [z, y, glass] rows, front bottom over the top to rear bottom
	var cab_end: float  # rear of the cabin (pickup, box truck), else the rear
	var windscreen: Array = []  # [Vector2 foot, Vector2 top] in (z, y)
	var rear_glass: Array = []  # [Vector2 top, Vector2 foot], or [] for a vertical back

	func _init(entry: Dictionary, lod_in: int, livery_in: Dictionary) -> void:
		e = entry
		lod = lod_in
		livery = livery_in
		cls = str(e.get("body_class", "sedan"))
		var d: Dictionary = e.get("dims", {})
		length = float(d.get("length_m", 4.6))
		width = float(d.get("width_m", 1.8))
		height = float(d.get("height_m", 1.45))
		wr = float(d.get("wheel_radius_m", 0.33))
		hw = width * 0.5
		zf = -length * 0.5
		zr = length * 0.5
		cl = wr * 0.6
		for p in VehicleMesh.wheel_positions(e):
			if not axles.has(p.z):
				axles.append(p.z)
		for i in range(4):
			var t := SurfaceTool.new()
			t.begin(Mesh.PRIMITIVE_TRIANGLES)
			st.append(t)
		_make_profile(d)

	# --- profile per class ---

	func _make_profile(d: Dictionary) -> void:
		var cs := float(d.get("cabin_start_m", length * 0.38))
		var rl := float(d.get("roof_length_m", length * 0.28))
		cab_end = zr
		match cls:
			"van":
				hb = height * 0.46
				var foot := Vector2(zf + cs, hb + 0.08)
				var top := Vector2(zf + cs + 0.55, height)
				windscreen = [foot, top]
				profile = [[zf, cl, false], [zf, hb * 0.85, false], [zf + 0.18, hb, false], [foot.x, foot.y, false],
					[foot.x, foot.y, true], [top.x, top.y, true], [top.x, top.y, false],
					[zr - 0.05, height, false], [zr, height - 0.05, false], [zr, cl, false]]
			"box_truck":
				hb = 1.15
				var cab_h := minf(height * 0.8, 2.7)
				cab_end = zf + 2.0
				var foot := Vector2(zf + 0.22, hb + 0.15)
				var top := Vector2(zf + 0.5, cab_h)
				windscreen = [foot, top]
				profile = [[zf, cl, false], [zf, hb, false], [foot.x, foot.y, false],
					[foot.x, foot.y, true], [top.x, top.y, true], [top.x, top.y, false],
					[cab_end, cab_h, false], [cab_end, cl, false]]
			"pickup":
				hb = height * 0.56
				var ws := (height - hb) * 0.95
				var foot := Vector2(zf + cs, hb + 0.03)
				var top := Vector2(foot.x + ws, height)
				cab_end = minf(top.x + rl, zr - float(d.get("bed_length_m", 1.9)))
				var bed_floor := hb - 0.35
				windscreen = [foot, top]
				profile = [[zf, cl, false], [zf, hb - 0.14, false], [zf + 0.14, hb - 0.02, false], [foot.x, foot.y, false],
					[foot.x, foot.y, true], [top.x, top.y, true], [top.x, top.y, false],
					[cab_end, height, false], [cab_end, height - 0.03, true], [cab_end + 0.04, hb + 0.06, true],
					[cab_end + 0.04, hb + 0.04, false], [cab_end + 0.04, bed_floor, false], [zr, bed_floor, false], [zr, cl, false]]
			_:
				var ratios := {"sedan": [0.6, 1.05, 1.15], "taxi": [0.6, 1.05, 1.15], "coupe": [0.62, 1.5, 1.9],
					"hatchback": [0.6, 1.15, 0.0], "suv": [0.58, 0.9, 0.0]}
				var r: Array = ratios.get(cls, ratios["sedan"])
				hb = height * float(r[0])
				var foot := Vector2(zf + cs, hb + 0.03)
				var top := Vector2(foot.x + (height - hb) * float(r[1]), height)
				var roof_end := minf(top.x + rl, zr - 0.25)
				windscreen = [foot, top]
				profile = [[zf, cl, false], [zf, hb - 0.14, false], [zf + 0.14, hb - 0.02, false], [foot.x, foot.y, false],
					[foot.x, foot.y, true], [top.x, top.y, true], [top.x, top.y, false], [roof_end, height, false]]
				if float(r[2]) > 0.0:  # sloping rear glass onto a boot
					var gfoot := Vector2(minf(roof_end + (height - hb) * float(r[2]), zr - 0.35), hb + 0.04)
					rear_glass = [Vector2(roof_end, height), gfoot]
					profile += [[roof_end, height, true], [gfoot.x, gfoot.y, true], [gfoot.x, gfoot.y, false],
						[zr - 0.1, hb - 0.02, false], [zr, hb - 0.12, false], [zr, cl, false]]
				else:  # hatch: near-vertical rear glass
					var gfoot := Vector2(zr - 0.1, hb + 0.08)
					rear_glass = [Vector2(roof_end, height), gfoot]
					profile += [[roof_end, height, true], [gfoot.x, gfoot.y, true], [gfoot.x, gfoot.y, false],
						[zr, hb - 0.06, false], [zr, cl, false]]

	# --- primitives: every face wound to match its outward normal ---

	func tri(s: int, p: Array, n: Vector3, color: Color, uv: Array) -> void:
		var geo: Vector3 = (p[1] - p[0]).cross(p[2] - p[0])
		var order := [0, 1, 2]
		# Godot front faces are clockwise seen from outside: the cross product points inward.
		if geo.dot(n) > 0.0:
			order = [0, 2, 1]
		for k: int in order:
			st[s].set_color(color)
			st[s].set_normal(n)
			st[s].set_uv(uv[k])
			st[s].add_vertex(p[k])

	## Quad a b c d (bottom left, bottom right, top right, top left seen from outside), with the
	## cell's UV rectangle stretched over it.
	func quad(s: int, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, color: Color, cell: String = "blank") -> void:
		var r := TrimSheet.uv_rect(cell)
		var ua := Vector2(r.position.x, r.end.y)
		var ub := r.end
		var uc := Vector2(r.end.x, r.position.y)
		var ud := r.position
		tri(s, [a, b, c], n, color, [ua, ub, uc])
		tri(s, [a, c, d], n, color, [ua, uc, ud])

	func box(s: int, centre: Vector3, size: Vector3, color: Color, cells: Dictionary = {}) -> void:
		var h := size * 0.5
		var faces := {
			"front": [Vector3(0, 0, -1), Vector3.RIGHT, Vector3.UP],
			"back": [Vector3(0, 0, 1), Vector3.LEFT, Vector3.UP],
			"left": [Vector3(-1, 0, 0), Vector3.BACK, Vector3.UP],
			"right": [Vector3(1, 0, 0), Vector3.FORWARD, Vector3.UP],
			"top": [Vector3.UP, Vector3.RIGHT, Vector3.BACK],
			"bottom": [Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD],
		}
		for name: String in faces:
			var f: Array = faces[name]
			var n: Vector3 = f[0]
			var u: Vector3 = f[1]
			var v: Vector3 = f[2]
			var c := centre + n * (absf(n.x) * h.x + absf(n.y) * h.y + absf(n.z) * h.z)
			var hu := absf(u.x) * h.x + absf(u.y) * h.y + absf(u.z) * h.z
			var hv := absf(v.x) * h.x + absf(v.y) * h.y + absf(v.z) * h.z
			quad(s, c - u * hu - v * hv, c + u * hu - v * hv, c + u * hu + v * hv, c - u * hu + v * hv, n, color, str(cells.get(name, "blank")))

	## A flat polygon of (z, y) points at x, facing out on `side` (-1 left, +1 right).
	func side_polygon(s: int, poly: PackedVector2Array, x: float, side: float, color: Color) -> void:
		var clean := PackedVector2Array()
		for p in poly:
			if clean.is_empty() or clean[clean.size() - 1].distance_to(p) > 0.001:
				clean.append(p)
		if clean.size() > 2 and clean[0].distance_to(clean[clean.size() - 1]) < 0.001:
			clean.remove_at(clean.size() - 1)
		var idx := Geometry2D.triangulate_polygon(clean)
		var uv := TrimSheet.uv_centre("blank")
		for t in range(0, idx.size(), 3):
			var pts: Array = []
			for k in range(3):
				var q := clean[idx[t + k]]
				pts.append(Vector3(x, q.y, q.x))
			tri(s, pts, Vector3(side, 0, 0), color, [uv, uv, uv])

	# --- parts ---

	func _inset(y: float) -> float:
		return TUMBLEHOME_M if y > hb + 0.02 else 0.0

	## Profile extruded across the width.
	func hull() -> void:
		for i in range(profile.size() - 1):
			var a: Array = profile[i]
			var b: Array = profile[i + 1]
			var pa := Vector2(a[0], a[1])
			var pb := Vector2(b[0], b[1])
			if pa.distance_to(pb) < 0.001:
				continue
			var glass: bool = a[2] and b[2]
			var d := pb - pa
			var n := Vector3(0.0, d.x, -d.y).normalized()  # outward for a front-to-rear walk over the top
			var xa := hw - _inset(pa.y)
			var xb := hw - _inset(pb.y)
			quad(1 if glass else 0, Vector3(-xa, pa.y, pa.x), Vector3(xa, pa.y, pa.x), Vector3(xb, pb.y, pb.x), Vector3(-xb, pb.y, pb.x),
				n, GLASS_COLOR if glass else Color.WHITE)
		var under_end := cab_end if cls == "box_truck" else zr
		quad(0, Vector3(-hw, cl, under_end), Vector3(hw, cl, under_end), Vector3(hw, cl, zf), Vector3(-hw, cl, zf), Vector3.DOWN, Color.WHITE)

	## Lower side panels (with wheel wells at LOD0) and the cabin sides.
	func sides() -> void:
		for side: float in [-1.0, 1.0]:
			var lower := PackedVector2Array()
			for row: Array in profile:
				lower.append(Vector2(row[0], minf(row[1], hb)))
			# Back along the bottom, rear to front, notched round each axle at LOD0.
			var arch_r := wr + 0.06
			var bottom := PackedVector2Array()
			if lod == Lod.LOD0:
				var sorted := _panel_axles()
				sorted.sort()
				sorted.reverse()
				for az: float in sorted:
					var dy := wr - cl
					var half := sqrt(maxf(arch_r * arch_r - dy * dy, 0.0))
					var a0 := atan2(-dy, half)  # where the circle meets the bottom line, rear side
					var segs := 6
					for k in range(segs + 1):
						var ang := lerpf(a0, PI - a0, float(k) / segs)
						bottom.append(Vector2(az + cos(ang) * arch_r, wr + sin(ang) * arch_r))
			for p in bottom:
				lower.append(p)
			side_polygon(0, lower, side * hw, side, Color.WHITE)
			if lod == Lod.LOD0:
				_arch_liners(side, arch_r)
			# Cabin side: the profile above the belt.
			var cab := PackedVector2Array()
			var upper: Array = []
			for row: Array in profile:
				if float(row[1]) > hb + 0.02 and float(row[0]) <= cab_end + 0.05:
					upper.append(Vector2(row[0], row[1]))
			if upper.size() < 2:
				continue
			cab.append(Vector2(upper[0].x, hb + 0.02))
			for p: Vector2 in upper:
				cab.append(p)
			cab.append(Vector2(upper[upper.size() - 1].x, hb + 0.02))
			var x := side * (hw - TUMBLEHOME_M)
			# Shoulder: the strip of roof-facing body between the side panel and the inboard cabin.
			var s0: float = upper[0].x
			var s1: float = upper[upper.size() - 1].x
			var xo := side * hw
			quad(0, Vector3(xo, hb, s0), Vector3(x, hb + 0.02, s0), Vector3(x, hb + 0.02, s1), Vector3(xo, hb, s1), Vector3.UP, Color.WHITE)
			if lod == Lod.LOD1:
				side_polygon(1, cab, x, side, GLASS_COLOR)
			else:
				side_polygon(0, cab, x, side, Color.WHITE)
				_panes(side, x)

	## Axles under the side panels (a box truck's rear axle is under the cargo box, not the cab).
	func _panel_axles() -> Array:
		var out := []
		for az: float in axles:
			if az < cab_end - wr:
				out.append(az)
		return out

	## Dark arch liners: the inside of each wheel well.
	func _arch_liners(side: float, arch_r: float) -> void:
		var dy := wr - cl
		var half := sqrt(maxf(arch_r * arch_r - dy * dy, 0.0))
		var a0 := atan2(-dy, half)
		var segs := 6
		for az: float in _panel_axles():
			for k in range(segs):
				var t0 := lerpf(a0, PI - a0, float(k) / segs)
				var t1 := lerpf(a0, PI - a0, float(k + 1) / segs)
				var p0 := Vector2(az + cos(t0) * arch_r, wr + sin(t0) * arch_r)
				var p1 := Vector2(az + cos(t1) * arch_r, wr + sin(t1) * arch_r)
				var mid := (p0 + p1) * 0.5
				var inward := (Vector2(az, wr) - mid).normalized()  # faces the wheel
				var xo := side * hw
				var xi := side * (hw - 0.3)
				quad(1, Vector3(xo, p0.y, p0.x), Vector3(xi, p0.y, p0.x), Vector3(xi, p1.y, p1.x), Vector3(xo, p1.y, p1.x),
					Vector3(0.0, inward.y, inward.x), DARK_COLOR)

	## Window panes on the cabin side, pillars left between them in the body colour.
	func _panes(side: float, x: float) -> void:
		var y0 := hb + 0.07
		var y1 := height - 0.07 if cls != "box_truck" else float(profile[5][1]) - 0.07
		var front0 := _along(windscreen[0], windscreen[1], y0) + 0.07
		var front1 := _along(windscreen[0], windscreen[1], y1) + 0.07
		var rear0: float
		var rear1: float
		match cls:
			"van":
				rear0 = windscreen[1].x + 0.6
				rear1 = rear0
			"box_truck", "pickup":
				rear0 = cab_end - 0.1
				rear1 = rear0
			_:
				rear0 = _along(rear_glass[1], rear_glass[0], y0) - 0.07
				rear1 = _along(rear_glass[1], rear_glass[0], y1) - 0.07
		var xp := x + side * PROUD_M
		var n := Vector3(side, 0, 0)
		var split := cls in ["sedan", "taxi", "hatchback", "suv", "coupe"]
		if split:
			var mid := (front1 + rear1) * 0.5 + 0.1
			var gap := 0.06
			_pane(xp, n, front0, mid - gap, mid - gap, front1, y0, y1)
			_pane(xp, n, mid + gap, rear0, rear1, mid + gap, y0, y1)
		else:
			_pane(xp, n, front0, rear0, rear1, front1, y0, y1)

	func _pane(x: float, n: Vector3, z_bl: float, z_br: float, z_tr: float, z_tl: float, y0: float, y1: float) -> void:
		if z_br - z_bl < 0.1 or z_tr - z_tl < 0.05:
			return
		quad(1, Vector3(x, y0, z_bl), Vector3(x, y0, z_br), Vector3(x, y1, z_tr), Vector3(x, y1, z_tl), n, Color.WHITE, "tint")

	## z where the line from p to q crosses height y.
	func _along(p: Vector2, q: Vector2, y: float) -> float:
		if absf(q.y - p.y) < 0.001:
			return p.x
		return lerpf(p.x, q.x, clampf((y - p.y) / (q.y - p.y), 0.0, 1.0))

	func lights() -> void:
		var front_z := zf - PROUD_M
		var y_head := hb - 0.12 if cls not in ["van", "box_truck"] else minf(hb * 0.8, 0.95)
		var rear_z := zr + PROUD_M
		if cls == "box_truck":
			rear_z = zr + PROUD_M + 0.0
		for side: float in [-1.0, 1.0]:
			var x0 := side * hw * 0.5
			var x1 := side * hw * 0.88
			quad(2, Vector3(x0, y_head - 0.14, front_z), Vector3(x1, y_head - 0.14, front_z), Vector3(x1, y_head, front_z), Vector3(x0, y_head, front_z),
				Vector3.FORWARD, HEADLIGHT_COLOR, "lens" if lod == Lod.LOD0 else "blank")
			var yt := (hb - 0.3) if cls not in ["van", "box_truck", "pickup"] else cl + 0.45
			quad(3, Vector3(x0, yt, rear_z), Vector3(x1, yt, rear_z), Vector3(x1, yt + 0.16, rear_z), Vector3(x0, yt + 0.16, rear_z),
				Vector3.BACK, TAILLIGHT_COLOR)

	## LOD0: bumpers, grille, plates, mirrors, livery band.
	func details() -> void:
		var bump_h := 0.28
		for front: bool in [true, false]:
			var z := zf + 0.04 if front else zr - 0.04
			var dir := -1.0 if front else 1.0
			box(0, Vector3(0, cl + bump_h * 0.5, z + dir * 0.04), Vector3(width, bump_h, 0.16), Color.WHITE)
			box(1, Vector3(0, cl - 0.01, z + dir * 0.05), Vector3(width * 0.94, 0.06, 0.12), TRIM_COLOR)
			var pz := z + dir * (0.12 + PROUD_M)
			var n := Vector3(0, 0, dir)
			quad(1, Vector3(-0.26, cl + 0.07, pz), Vector3(0.26, cl + 0.07, pz), Vector3(0.26, cl + 0.19, pz), Vector3(-0.26, cl + 0.19, pz), n, Color.WHITE, "plate")
		# Grille between the headlights.
		var gz := zf - PROUD_M
		var gy := hb - 0.12 if cls not in ["van", "box_truck"] else minf(hb * 0.8, 0.95)
		quad(1, Vector3(-hw * 0.46, gy - 0.16, gz), Vector3(hw * 0.46, gy - 0.16, gz), Vector3(hw * 0.46, gy - 0.02, gz), Vector3(-hw * 0.46, gy - 0.02, gz),
			Vector3.FORWARD, Color.WHITE, "grille")
		# Mirrors at the foot of the windscreen.
		for side: float in [-1.0, 1.0]:
			box(0, Vector3(side * (hw + 0.07), windscreen[0].y + 0.1, windscreen[0].x + 0.12), Vector3(0.12, 0.11, 0.07), Color.WHITE)
		if str(livery.get("stripe", "none")) == "police":
			for side: float in [-1.0, 1.0]:
				var x := side * (hw + PROUD_M)
				box(1, Vector3(x, hb - 0.2, (zf + zr) * 0.5), Vector3(0.012, 0.16, (zr - zf) * 0.86), POLICE_BLUE)
		if str(livery.get("stripe", "none")) == "ambulance":
			# A red band along each side with a cross on the box behind the cab.
			var mid := zf + (zr - zf) * 0.62
			for side: float in [-1.0, 1.0]:
				var x := side * (hw + PROUD_M)
				box(1, Vector3(x, hb * 0.42, (zf + zr) * 0.5), Vector3(0.012, 0.2, (zr - zf) * 0.9), AMBULANCE_RED)
				box(1, Vector3(x, hb * 0.72, mid), Vector3(0.014, 0.62, 0.2), AMBULANCE_RED)
				box(1, Vector3(x, hb * 0.72, mid), Vector3(0.014, 0.2, 0.62), AMBULANCE_RED)
		if str(livery.get("stripe", "none")) == "check":
			for side: float in [-1.0, 1.0]:
				var x := side * (hw + PROUD_M)
				quad(0, Vector3(x, hb - 0.16, zf + 0.35), Vector3(x, hb - 0.16, cab_end - 0.35), Vector3(x, hb - 0.06, cab_end - 0.35), Vector3(x, hb - 0.06, zf + 0.35),
					Vector3(side, 0, 0), Color.WHITE, "check")

	## Parts only some classes have.
	func class_parts() -> void:
		match cls:
			"pickup":
				var floor_y := hb - 0.35
				var wall_h := hb - floor_y + 0.06
				var bed0 := cab_end + 0.04
				var bed_len := zr - bed0
				for side: float in [-1.0, 1.0]:
					box(0, Vector3(side * (hw - 0.04), floor_y + wall_h * 0.5, bed0 + bed_len * 0.5), Vector3(0.08, wall_h, bed_len), Color.WHITE)
				box(0, Vector3(0, floor_y + wall_h * 0.5, zr - 0.04), Vector3(width - 0.16, wall_h, 0.08), Color.WHITE)  # tailgate
			"box_truck":
				var box_y0 := wr * 2.0 + 0.1  # clear of the rear wheels
				var box0 := cab_end + 0.1
				box(1, Vector3(0, (box_y0 + height) * 0.5, (box0 + zr) * 0.5), Vector3(width, height - box_y0, zr - box0), Color(0.93, 0.93, 0.92),
					{"back": "roller" if lod == Lod.LOD0 else "blank"})
				box(1, Vector3(0, (cl + box_y0) * 0.5, (box0 + zr) * 0.5), Vector3(1.0, box_y0 - cl, zr - box0), DARK_COLOR)  # chassis rails
		if lod == Lod.LOD0 and str(livery.get("roof_sign", "")) != "":
			var roof_mid: float = (windscreen[1].x + (rear_glass[0].x if not rear_glass.is_empty() else cab_end)) * 0.5
			box(1, Vector3(0, height + 0.1, roof_mid), Vector3(0.5, 0.18, 0.22), Color.WHITE,  # 1 cm clear of the roof: no z-fighting
				{"front": "roof_sign", "back": "roof_sign", "left": "roof_sign", "right": "roof_sign"})

	func wheels() -> void:
		var sides := 12 if lod == Lod.LOD0 else 6
		var ww := clampf(wr * 0.68, 0.2, 0.32)
		for c in VehicleMesh.wheel_positions(e):
			for i in range(sides):
				var a0 := TAU * i / sides
				var a1 := TAU * (i + 1) / sides
				var r0 := Vector3(0, cos(a0), sin(a0)) * wr
				var r1 := Vector3(0, cos(a1), sin(a1)) * wr
				var hx := Vector3(ww * 0.5, 0, 0)
				var n := ((r0 + r1) * 0.5).normalized()
				quad(1, c + r0 - hx, c + r1 - hx, c + r1 + hx, c + r0 + hx, n, DARK_COLOR, "dark")
				var uv := TrimSheet.uv_centre("dark")
				for sx: float in [-1.0, 1.0]:
					var o := Vector3(sx * ww * 0.5, 0, 0)
					tri(1, [c + o, c + o + r0, c + o + r1], Vector3(sx, 0, 0), DARK_COLOR, [uv, uv, uv])

	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for t in st:
			t.commit(mesh)
		mesh.surface_set_material(0, VehicleMesh.body_material(Color.WHITE))
		mesh.surface_set_material(1, VehicleMesh.dark_material())
		mesh.surface_set_material(2, VehicleMesh.light_material())
		mesh.surface_set_material(3, VehicleMesh.tail_material())
		return mesh

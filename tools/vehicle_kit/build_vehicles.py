"""Builds the game's vehicles from the Quaternius kit cars. Runs inside Blender:

    blender -b --factory-startup -P tools/vehicle_kit/build_vehicles.py -- <repo> [id ...]

(`scripts/build-vehicles.sh` finds Blender and runs this, then the lineup render.)

Each recipe in recipes.json names a source model in art/quaternius/cars and either keeps it as
it is or derives a new body from it: `box` keeps the cab and adds a bevelled box behind it
(ambulance, van, box truck); `pickup` keeps a crew cab and adds a bed. Every output gets the
same treatment so the game can read them alike:

- the kit wheels are replaced by light 16-sided wheels (the originals are 1,680 triangles a
  car), one object per wheel named Wheel_FL, Wheel_FR, Wheel_RL, Wheel_RR with its origin at
  the hub;
- the body paint material is renamed `Paint` (the game tints it per car) and two-tone accents
  `PaintAccent`; every other material keeps its kit name;
- scaled to the recipe's length, centred, wheels on the ground, front towards -Z in glTF.

Measured dims (length, width, wheelbase, track, wheel radius, overhang) go to
build/vehicle_kit/dims.json for tools/vehicle_kit/apply_dims.py to copy into the catalogue.
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ARGS = sys.argv[sys.argv.index("--") + 1 :]
REPO = os.path.abspath(ARGS[0])
ONLY = set(ARGS[1:])
SRC = os.path.join(REPO, "art", "quaternius", "cars")
OUT = os.path.join(REPO, "game", "assets", "vehicles")
DIMS_OUT = os.path.join(REPO, "build", "vehicle_kit", "dims.json")
RECIPES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "recipes.json")

WHEEL_SIDES = 16
ARCH_CLEAR_M = 0.09  # gap between tyre and arch


# --- scene helpers ---


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, rgb):
    m = bpy.data.materials.get(name)
    if m is not None:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*rgb, 1.0)
    p.inputs["Roughness"].default_value = 0.6
    return m


def load(path):
    """Imports a kit car; returns (body object, [(centre, radius, width)] wheels)."""
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    for o in [o for o in bpy.data.objects if o.type != "MESH"]:
        bpy.data.objects.remove(o)
    for o in meshes:
        o.data.transform(o.matrix_world)
        o.matrix_world = Matrix.Identity(4)
    wheels = []
    for o in [o for o in meshes if "Wheel" in o.name]:
        for side in (-1, 1):  # BackWheels holds both rear wheels: split by side
            vs = [v.co for v in o.data.vertices if (v.co.x > 0) == (side > 0)]
            if not vs:
                continue
            lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
            hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
            wheels.append([(lo + hi) / 2, (hi.z - lo.z) / 2, hi.x - lo.x])
        bpy.data.objects.remove(o)
    bodies = [o for o in bpy.data.objects if o.type == "MESH"]
    for o in bodies:
        o.select_set(True)
    bpy.context.view_layer.objects.active = bodies[0]
    if len(bodies) > 1:
        bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = "Body"
    return body, wheels


def box(name, lo, hi, mat, bevel=0.0, segments=1):
    """An axis-aligned box object from corner `lo` to `hi`, optionally bevelled."""
    me = bpy.data.meshes.new(name)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    c = (Vector(lo) + Vector(hi)) / 2
    s = Vector(hi) - Vector(lo)
    for v in bm.verts:
        v.co = Vector((c.x + v.co.x * s.x, c.y + v.co.y * s.y, c.z + v.co.z * s.z))
    if bevel > 0.0:
        bmesh.ops.bevel(
            bm, geom=bm.edges[:], offset=bevel, segments=segments, profile=0.5, affect="EDGES"
        )
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    return o


def slice_z(o, heights):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    for z in heights:
        bmesh.ops.bisect_plane(
            bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, z), plane_no=(0, 0, 1)
        )
    bm.to_mesh(o.data)
    bm.free()


def paint_bands(o, mats, skirt_top, stripe=None):
    """Material slots 0 paint, 1 black, 2 stripe; faces below `skirt_top` go black and side
    faces inside the stripe band go to the stripe."""
    for m in mats:
        o.data.materials.append(m)
    for p in o.data.polygons:
        c = p.center
        p.material_index = 0
        if c.z < skirt_top:
            p.material_index = 1
        elif stripe and stripe[0] < c.z < stripe[1] and abs(p.normal.z) < 0.5:
            p.material_index = 2


def cut_arch(o, y, radius, z, width):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=16, radius=radius, depth=width, location=(0, y, z), rotation=(0, math.pi / 2, 0)
    )
    cyl = bpy.context.object
    cyl.data.materials.append(bpy.data.materials["Black"])
    mod = o.modifiers.new("arch", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cyl
    mod.solver = "EXACT"
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cyl)


def join_into(target, parts):
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    target.select_set(True)
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.join()


# --- the cab ---


def cut_cab(body, cab, wheels):
    """Keeps the body in front of `cut_y`, caps the cut, drops the roof rails, then scales the
    cab from its front bottom (`scale_y` squashes it forward, `scale_z` makes it taller)."""
    cut_y = cab["cut_y"]
    bm = bmesh.new()
    bm.from_mesh(body.data)
    res = bmesh.ops.bisect_plane(
        bm,
        geom=bm.verts[:] + bm.edges[:] + bm.faces[:],
        plane_co=(0, cut_y, 0),
        plane_no=(0, 1, 0),
        clear_outer=True,
    )
    edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
    if edges:
        filled = bmesh.ops.triangle_fill(
            bm, use_beauty=True, use_dissolve=False, edges=edges, normal=(0, 1, 0)
        )
        paint = body.data.materials.find("Paint")
        for f in filled["geom"]:
            if isinstance(f, bmesh.types.BMFace):
                f.material_index = paint
    if cab.get("drop_roof_rails", False):
        black = body.data.materials.find("Black")
        rails = [
            f
            for f in bm.faces
            if f.material_index == black
            and f.calc_center_median().z > 1.36
            and f.calc_center_median().y > -0.6
        ]
        bmesh.ops.delete(bm, geom=rails, context="FACES")
    sy, sz = cab.get("scale_y", 1.0), cab.get("scale_z", 1.0)
    if sy != 1.0 or sz != 1.0:
        y0 = min(v.co.y for v in bm.verts)
        z0 = min(v.co.z for v in bm.verts)
        for v in bm.verts:
            v.co.y = y0 + (v.co.y - y0) * sy
            v.co.z = z0 + (v.co.z - z0) * sz
        for w in wheels:
            if w[0].y < 0:
                w[0].y = y0 + (w[0].y - y0) * sy
    bm.to_mesh(body.data)
    bm.free()


def body_half_width(body, near_y, z_max):
    vs = [v.co for v in body.data.vertices if abs(v.co.y - near_y) < 0.25 and v.co.z < z_max]
    return max(abs(v.x) for v in vs) if vs else 0.95


# --- derived bodies ---


def derive_box(body, wheels, r, M):
    cut_cab(body, r["cab"], wheels)
    b = r["box"]
    hw = b["width"] / 2
    y0, y1, z0, z1 = b["y0"], b["y1"], b["z0"], b["z1"]
    paint = M[b.get("box_paint", "Paint")]
    shell = box("Box", (-hw, y0, z0), (hw, y1, z1), paint, bevel=b.get("bevel", 0.07), segments=2)
    shell.data.materials.clear()
    skirt = z0 + b.get("skirt_h", 0.16)
    stripe = b.get("stripe")
    slice_z(shell, [skirt] + (stripe or []))
    paint_bands(shell, [paint, M["Black"], M["Stripe"]], skirt, stripe)
    rear_y = r["rear_axle_y"]
    wr = max(w[1] for w in wheels)
    if z0 < 2 * wr + ARCH_CLEAR_M:
        cut_arch(shell, rear_y, wr + ARCH_CLEAR_M, wr, b["width"] + 0.4)
    parts = [shell]
    win = r.get("windows", {})
    if "side" in win:
        wy0, wy1, wz0, wz1 = win["side"]
        for s in (-1, 1):
            parts.append(
                box(
                    "SideWin",
                    (s * hw - 0.015, wy0, wz0),
                    (s * hw + 0.015, wy1, wz1),
                    M["Windows"],
                    0.02,
                )
            )
    if win.get("rear", False):
        wz0, wz1 = z0 + (z1 - z0) * 0.53, z0 + (z1 - z0) * 0.78
        parts.append(
            box(
                "RearWinL",
                (-hw + 0.28, y1 - 0.01, wz0),
                (-0.10, y1 + 0.015, wz1),
                M["Windows"],
                0.02,
            )
        )
        parts.append(
            box(
                "RearWinR", (0.10, y1 - 0.01, wz0), (hw - 0.28, y1 + 0.015, wz1), M["Windows"], 0.02
            )
        )
    if r.get("roller_door", False):
        z = skirt + 0.12
        while z < z1 - 0.15:
            parts.append(
                box(
                    "Slat",
                    (-hw + 0.12, y1 - 0.005, z),
                    (hw - 0.12, y1 + 0.012, z + 0.025),
                    M["Grey"],
                )
            )
            z += 0.24
        parts.append(
            box(
                "Latch", (-0.12, y1, skirt + 0.10), (0.12, y1 + 0.04, skirt + 0.18), M["Grey"], 0.01
            )
        )
    else:
        parts.append(
            box(
                "Seam",
                (-0.012, y1 - 0.01, skirt + 0.04),
                (0.012, y1 + 0.012, z1 - 0.12),
                M["Black"],
            )
        )
    tail_z = (skirt + 0.30, skirt + 0.68) if z0 < 0.5 else (z0 - 0.02, z0 + 0.30)
    for s in (-1, 1):
        x = s * (hw - 0.16)
        parts.append(
            box(
                "Tail",
                (x - 0.06, y1 - 0.01, tail_z[0]),
                (x + 0.06, y1 + 0.03, tail_z[1]),
                M["TailLights"],
                0.015,
            )
        )
    step_z = min(z0, 0.42)
    parts.append(
        box(
            "Step",
            (-hw + 0.08, y1 - 0.05, step_z - 0.12),
            (hw - 0.08, y1 + 0.16, step_z),
            M["Grey"],
            0.03,
        )
    )
    if "curb_door" in r:  # right-hand side when facing forward is -X
        dy0, dy1 = r["curb_door"]
        x = -hw - 0.012
        top = z1 - 0.20
        for lo, hi in (
            ((x, dy0, skirt + 0.02), (x + 0.024, dy0 + 0.03, top)),
            ((x, dy1 - 0.03, skirt + 0.02), (x + 0.024, dy1, top)),
            ((x, dy0, top - 0.03), (x + 0.024, dy1, top)),
        ):
            parts.append(box("DoorSeam", lo, hi, M["Black"]))
        parts.append(
            box(
                "Handle",
                (x - 0.02, dy0 + 0.13, 1.28),
                (x + 0.01, dy0 + 0.27, 1.34),
                M["Grey"],
                0.01,
            )
        )
    if r.get("chassis", False):
        cy0 = r["cab"]["cut_y"] - 0.2
        for s in (-1, 1):
            parts.append(
                box(
                    "Rail",
                    (s * 0.42 - 0.07, cy0, 0.36),
                    (s * 0.42 + 0.07, y1 - 0.05, z0),
                    M["Black"],
                )
            )
        parts.append(
            box(
                "CabBack",
                (-0.6, r["cab"]["cut_y"] - 0.02, 0.4),
                (0.6, y0 - 0.02, z0 + 0.1),
                M["Black"],
            )
        )
    if r.get("beacons") == "ambulance":
        for ya, yb in ((y0 + 0.02, y0 + 0.20), (y1 - 0.20, y1 - 0.02)):
            for s in (-1, 1):
                xa, xb = sorted((s * (hw - 0.04), s * (hw - 0.32)))
                parts.append(
                    box("Beacon", (xa, ya, z1 - 0.02), (xb, yb, z1 + 0.10), M["RedLights"], 0.02)
                )
            parts.append(
                box("Flood", (-0.22, ya, z1 - 0.02), (0.22, yb, z1 + 0.08), M["WhiteLights"], 0.02)
            )
        parts.append(
            box(
                "FrontBar",
                (-0.70, y0 - 0.03, z1 - 0.17),
                (0.70, y0 + 0.01, z1 - 0.02),
                M["RedLights"],
                0.015,
            )
        )
    join_into(body, parts)
    for w in wheels:
        if w[0].y > 0:
            w[0].y = rear_y


def derive_pickup(body, wheels, r, M):
    cut_cab(body, r["cab"], wheels)
    b = r["bed"]
    y0 = r["cab"]["cut_y"] - 0.02
    y1, fz, tz, t, sz = b["y1"], b["floor_z"], b["top_z"], b["wall"], b["skirt_z"]
    hw = body_half_width(body, y0, 1.0)
    rear_y = r["rear_axle_y"]
    wr = max(w[1] for w in wheels)
    panels = []
    for s in (-1, 1):
        xa, xb = sorted((s * hw, s * (hw - t)))
        panels.append(box("BedSide", (xa, y0, sz), (xb, y1, tz), M["Paint"], 0.02))
    panels.append(box("Tailgate", (-hw, y1 - t, sz), (hw, y1, tz), M["Paint"], 0.02))
    join_into(panels[0], panels[1:])
    bed = panels[0]
    bed.data.materials.clear()
    skirt = sz + 0.13
    slice_z(bed, [skirt])
    paint_bands(bed, [M["Paint"], M["Black"], M["Stripe"]], skirt)
    cut_arch(bed, rear_y, wr + ARCH_CLEAR_M, wr, 2 * hw + 0.4)
    parts = [bed]
    parts.append(box("BedFloor", (-hw + t, y0, fz - 0.06), (hw - t, y1 - t, fz), M["Black"]))
    parts.append(box("BedFront", (-hw + t, y0, fz), (hw - t, y0 + t, tz - 0.02), M["Paint"]))
    parts.append(box("Under", (-hw + t, y0, sz + 0.05), (hw - t, y1 - t, fz - 0.06), M["Black"]))
    for s in (-1, 1):
        x = s * (hw - 0.07)
        parts.append(
            box(
                "Tail",
                (x - 0.05, y1 - 0.01, tz - 0.36),
                (x + 0.05, y1 + 0.03, tz - 0.06),
                M["TailLights"],
                0.015,
            )
        )
    parts.append(
        box(
            "Bumper",
            (-hw + 0.04, y1 - 0.04, sz - 0.04),
            (hw - 0.04, y1 + 0.12, sz + 0.12),
            M["Grey"],
            0.03,
        )
    )
    parts.append(
        box("Handle", (-0.15, y1, tz - 0.16), (0.15, y1 + 0.02, tz - 0.10), M["Black"], 0.005)
    )
    join_into(body, parts)
    for w in wheels:
        if w[0].y > 0:
            w[0].y = rear_y


# --- wheels, scale, export ---


def make_wheel(name, centre, radius, width, M):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=WHEEL_SIDES,
        radius=radius,
        depth=width,
        location=(0, 0, 0),
        rotation=(0, math.pi / 2, 0),
    )
    tyre = bpy.context.object
    tyre.data.materials.append(M["Black"])
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=WHEEL_SIDES,
        radius=radius * 0.6,
        depth=width + 0.02,
        location=(0, 0, 0),
        rotation=(0, math.pi / 2, 0),
    )
    rim = bpy.context.object
    rim.data.materials.append(M["Grey"])
    join_into(tyre, [rim])
    tyre.data.transform(tyre.matrix_world)
    tyre.matrix_world = Matrix.Translation(centre)
    tyre.name = name
    return tyre


def build(r):
    reset()
    body, wheels = load(os.path.join(SRC, r["source"]))
    mats = body.data.materials
    for n in r.get("paint", []):
        bpy.data.materials[n].name = "Paint"
    for n in r.get("accent", []):
        bpy.data.materials[n].name = "PaintAccent"
    M = {m.name: m for m in mats}
    M["Paint"] = bpy.data.materials["Paint"]
    M["Stripe"] = material("Stripe", (0.62, 0.05, 0.04))
    M["RedLights"] = material("RedLights", (0.64, 0.04, 0.03))
    M["WhiteLights"] = material("WhiteLights", (0.64, 0.64, 0.64))
    M["Cargo"] = material("Cargo", (0.60, 0.60, 0.58))
    for n, rgb in (
        ("Black", (0.01, 0.01, 0.01)),
        ("Grey", (0.16, 0.16, 0.16)),
        ("Windows", (0.03, 0.03, 0.03)),
        ("TailLights", (0.64, 0.07, 0.06)),
    ):
        M[n] = bpy.data.materials.get(n) or material(n, rgb)
    derive = r.get("derive")
    if derive == "box":
        derive_box(body, wheels, r, M)
    elif derive == "pickup":
        derive_pickup(body, wheels, r, M)

    # scale to length, centre, wheels on the ground
    vs = [v.co for v in body.data.vertices]
    s = r["length_m"] / (max(v.y for v in vs) - min(v.y for v in vs))
    body.data.transform(Matrix.Scale(s, 4))
    for w in wheels:
        w[0] = w[0] * s
        w[1] *= s
        w[2] *= s
    vs = [v.co for v in body.data.vertices]
    cx = (max(v.x for v in vs) + min(v.x for v in vs)) / 2
    cy = (max(v.y for v in vs) + min(v.y for v in vs)) / 2
    gz = min(w[0].z - w[1] for w in wheels)
    shift = Vector((-cx, -cy, -gz))
    body.data.transform(Matrix.Translation(shift))
    for w in wheels:
        w[0] = w[0] + shift

    # measure (front is -y, left is +x here)
    vs = [v.co for v in body.data.vertices]
    wr = sum(w[1] for w in wheels) / len(wheels)
    front_y = sum(w[0].y for w in wheels if w[0].y < 0) / 2
    rear_y = sum(w[0].y for w in wheels if w[0].y > 0) / 2
    low = [v for v in vs if v.z < 2 * wr]
    win = [
        body.matrix_world @ p.center
        for p in body.data.polygons
        if mats[p.material_index].name == "Windows"
    ]
    ymin = min(v.y for v in vs)
    dims = {
        "length_m": round(max(v.y for v in vs) - ymin, 3),
        "width_m": round(2 * max(abs(v.x) for v in low), 3),
        "height_m": round(max(v.z for v in vs), 3),
        "wheelbase_m": round(rear_y - front_y, 3),
        "track_m": round(sum(abs(w[0].x) for w in wheels) / len(wheels) * 2, 3),
        "wheel_radius_m": round(wr, 3),
        "front_overhang_m": round(front_y - ymin, 3),
        "cabin_start_m": round(min(c.y for c in win) - ymin, 3) if win else None,
    }

    names = {
        (True, True): "Wheel_FL",
        (True, False): "Wheel_FR",
        (False, True): "Wheel_RL",
        (False, False): "Wheel_RR",
    }
    objs = [body]
    for w in wheels:
        objs.append(make_wheel(names[(w[0].y < 0, w[0].x > 0)], w[0], w[1], w[2], M))
    # glTF: the exporter maps Blender -Y to +Z; turn half a circle so the front ends up at -Z
    turn = Matrix.Rotation(math.pi, 4, "Z")
    for o in objs:
        o.data.transform(turn.to_3x3().to_4x4())
        o.matrix_world = Matrix.Translation(turn @ o.matrix_world.translation)
    body.name = "Body"
    for o in bpy.data.objects:
        o.select_set(o in objs)
    out = os.path.join(OUT, r["id"] + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=out, export_format="GLB", use_selection=True, export_apply=True, export_yup=True
    )
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs)
    print(f"vehicle_kit: {r['id']}: {tris} triangles -> {os.path.relpath(out, REPO)}")
    return dims


def main():
    with open(RECIPES) as f:
        recipes = json.load(f)["vehicles"]
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(os.path.dirname(DIMS_OUT), exist_ok=True)
    dims = {}
    if os.path.exists(DIMS_OUT):
        with open(DIMS_OUT) as f:
            dims = json.load(f)
    for r in recipes:
        if ONLY and r["id"] not in ONLY:
            continue
        dims[r["id"]] = build(r)
    with open(DIMS_OUT, "w") as f:
        json.dump(dims, f, indent=1, sort_keys=True)
        f.write("\n")


main()

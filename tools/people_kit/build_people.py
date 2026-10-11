"""Builds the game's people from the Quaternius modular men and women. Runs inside Blender:

    blender -b --factory-startup -P tools/people_kit/build_people.py -- <repo> [pack ...]

(`scripts/build-people.sh` finds Blender and runs this, then the lineup render.)

The game walks people on its own small rig (CharacterMesh.BONES: hips, spine, head, two bones
per arm and leg) with a procedural walk that also runs in the crowd's shader, so the kit's
62-bone skeleton and animations are not used. Instead every part is moved onto that rig:

- the kit's T-pose arms are lowered (recipes.json `arm_hang_deg`) and the pose baked in;
- each vertex goes to one of our bones: the kit bone with the most weight on it, mapped by
  KIT_TO_OURS (fingers to the forearm, the foot to the shin, and so on); the bone index is
  written to the vertex colour's red channel as (bone + 0.5) / 16;
- each kit material becomes a colour role: Skin, Hair, Eye, Stubble, Top, Accent, Bottom,
  Shoes (the game paints these from the profile) or Kit_<name> (kept in the kit colour);
- parts over their triangle budget are decimated, then scaled so a man's head is
  `height_m` tall (women keep the kit's own size against men), turned to face -Z in glTF.

Output per pack: game/assets/people/<pack>.glb with one object per part (Face, Hair1..,
Beard1.., Hat1, Hat1Under.., Outfit0_Top, Outfit0_Legs, Outfit0_Feet, ..) and an entry in
game/assets/people/people.json: the bone pivots in game coordinates, the eyes (for glasses)
and the names of the choices.
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
SRC = os.path.join(REPO, "art", "quaternius")
OUT = os.path.join(REPO, "game", "assets", "people")
RECIPES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "recipes.json")

# Our bones, in CharacterMesh.BONES order.
OURS = [
    "hips",
    "spine",
    "head",
    "upper_arm_l",
    "forearm_l",
    "upper_arm_r",
    "forearm_r",
    "thigh_l",
    "shin_l",
    "thigh_r",
    "shin_r",
]
# Kit .L sits at +x and ends at -x once turned to face -Z; our _l bones sit at +x. So kit .R is
# our _l.
SIDE = {"R": "l", "L": "r"}


def kit_to_ours(name):
    base, _, side = name.partition(".")
    s = SIDE.get(side, "")
    if base in ("Root", "Body", "Hips"):
        return "hips"
    if base in ("Abdomen", "Torso", "Chest", "Shoulder"):
        return "spine"
    if base in ("Neck", "Head"):
        return "head"
    if base == "UpperArm":
        return "upper_arm_" + s
    if base in ("LowerArm", "Wrist") or base[:-1] in ("Index", "Middle", "Ring", "Pinky", "Thumb"):
        return "forearm_" + s
    if base == "UpperLeg":
        return "thigh_" + s
    if base in ("LowerLeg", "Foot", "Toes"):
        return "shin_" + s
    return None


def log(*a):
    print("people_kit:", *a)


def role_material(role, kit_colour=None):
    name = role if kit_colour is None else "Kit_" + role
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        p = m.node_tree.nodes["Principled BSDF"]
        p.inputs["Base Color"].default_value = (
            kit_colour if kit_colour is not None else (1, 1, 1, 1)
        )
        p.inputs["Roughness"].default_value = 0.8
    return m


def kit_colour(mat):
    if mat and mat.use_nodes:
        for n in mat.node_tree.nodes:
            if n.type == "BSDF_PRINCIPLED":
                return tuple(n.inputs["Base Color"].default_value)
    return (0.5, 0.5, 0.5, 1.0)


def rest_and_hang(arm, hang_deg):
    """Clears any action, lowers the arms by `hang_deg` from the T-pose, returns pivots (kit
    space) of our bones."""
    if arm.animation_data:
        arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    for side, sign in (("L", 1.0), ("R", -1.0)):
        pb = arm.pose.bones["UpperArm." + side]
        head = pb.head.copy()
        rot = Matrix.Rotation(math.radians(hang_deg * sign), 4, "Y")
        pb.matrix = Matrix.Translation(head) @ rot @ Matrix.Translation(-head) @ pb.matrix
        bpy.context.view_layer.update()
    mw = arm.matrix_world
    head = lambda n: mw @ arm.pose.bones[n].head
    thigh_l, thigh_r = head("UpperLeg.R"), head("UpperLeg.L")
    hips = (thigh_l + thigh_r) / 2
    return {
        "hips": hips,
        "spine": head("Abdomen"),
        "head": head("Neck"),
        "upper_arm_l": head("UpperArm.R"),
        "forearm_l": head("LowerArm.R"),
        "upper_arm_r": head("UpperArm.L"),
        "forearm_r": head("LowerArm.L"),
        "thigh_l": thigh_l,
        "shin_l": head("LowerLeg.R"),
        "thigh_r": thigh_r,
        "shin_r": head("LowerLeg.L"),
    }


def region_test(region, rule):
    if region is None:
        return lambda c: True
    beard = lambda c: c.z < rule["below_z"] and c.y < rule["front_y"]
    return beard if region == "beard" else (lambda c: not beard(c))


def extract(src, name, roles, budget, region=None, rule=None, avoid=None):
    """A new object from the posed `src`: faces whose kit material is in `roles` (kit name ->
    role, or -> ("Kit", colour)) and inside `region`, materials replaced by role materials,
    weights folded onto our bones and decimated to `budget` triangles. `avoid` is a set of
    rounded face centres to drop (coincident copies of the face's eyebrows)."""
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(
        src.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg
    )
    me.transform(src.matrix_world)
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    for g in src.vertex_groups:
        obj.vertex_groups.new(name=g.name)
    kit_names = [m.name if m else "" for m in me.materials]
    keep_region = region_test(region, rule)
    bm = bmesh.new()
    bm.from_mesh(me)
    dead = []
    for f in bm.faces:
        kn = kit_names[f.material_index] if f.material_index < len(kit_names) else ""
        c = f.calc_center_median()
        if (
            kn not in roles
            or not keep_region(c)
            or avoid
            and tuple(round(x, 3) for x in c) in avoid
        ):
            dead.append(f)
    bmesh.ops.delete(bm, geom=dead, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(me)
    bm.free()
    if not me.polygons:
        bpy.data.objects.remove(obj)
        raise SystemExit(f"people_kit: {name}: nothing left from {src.name} {sorted(roles)}")
    # Materials -> roles.
    slots = []
    for kn in kit_names:
        r = roles.get(kn)
        if r is None:
            slots.append(None)
        elif r == "Kit":
            slots.append(role_material(kn, kit_colour(bpy.data.materials.get(kn))))
        else:
            slots.append(role_material(r))
    for i, m in enumerate(slots):
        me.materials[i] = m if m is not None else role_material("Kit_unused", (1, 0, 1, 1))
    # Fold weights onto our bones.
    ours = {b: obj.vertex_groups.new(name="our_" + b) for b in OURS}
    mapping = {
        g.index: kit_to_ours(g.name) for g in obj.vertex_groups if not g.name.startswith("our_")
    }
    for v in me.vertices:
        sums = {}
        for ge in v.groups:
            b = mapping.get(ge.group)
            if b:
                sums[b] = sums.get(b, 0.0) + ge.weight
        for b, w in sums.items():
            ours[b].add([v.index], w, "REPLACE")
    for g in [g for g in obj.vertex_groups if not g.name.startswith("our_")]:
        obj.vertex_groups.remove(g)
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    if tris > budget:
        mod = obj.modifiers.new("dec", "DECIMATE")
        mod.ratio = budget / tris
        mod.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
    # Dominant bone -> vertex colour red; head by default for unweighted (hair, hats).
    me = obj.data
    me.calc_loop_triangles()
    group_bone = {g.index: OURS.index(g.name[4:]) for g in obj.vertex_groups}
    head_i = OURS.index("head")
    bone_of = []
    for v in me.vertices:
        best, best_w = head_i, 0.0
        for ge in v.groups:
            if ge.weight > best_w:
                best, best_w = group_bone[ge.group], ge.weight
        bone_of.append(best)
    attr = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    me.color_attributes.active_color = attr
    me.color_attributes.render_color_index = me.color_attributes.active_color_index
    for loop in me.loops:
        b = bone_of[loop.vertex_index]
        attr.data[loop.index].color = ((b + 0.5) / 16.0, 0.0, 0.0, 1.0)
    for g in list(obj.vertex_groups):
        obj.vertex_groups.remove(g)
    for p in me.polygons:
        p.use_smooth = False
    return obj


def face_centres(obj, kit_role="Hair"):
    out = set()
    for p in obj.data.polygons:
        m = obj.data.materials[p.material_index]
        if m and m.name == kit_role:
            out.add(tuple(round(x, 3) for x in p.center))
    return out


def build_pack(pack, rec):
    bpy.ops.wm.open_mainfile(filepath=os.path.join(SRC, pack["source"]))
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    for o in bpy.data.objects:
        o.hide_set(False)
        o.hide_viewport = False
    pivots = rest_and_hang(arm, rec["arm_hang_deg"])
    meshes = {o.name: o for o in bpy.data.objects if o.type == "MESH"}
    budget = rec["budget"]
    rule = rec["beard_region"]
    made = []

    face_rec = pack["face"]
    face = extract(meshes[face_rec["from"]], "Face", face_rec["roles"], budget["face"])
    made.append(face)
    brows = face_centres(face)
    # The face's eyebrows also sit in some hair meshes: drop those copies.
    for k, h in enumerate(pack["hair"]):
        if "from" in h:
            roles = {m: "Hair" for m in h["materials"]}
            made.append(
                extract(
                    meshes[h["from"]],
                    f"Hair{k}",
                    roles,
                    budget["hair"],
                    h.get("region"),
                    rule,
                    brows,
                )
            )
    for k, b in enumerate(pack["beard"]):
        if "from" in b:
            roles = {m: b.get("role", "Hair") for m in b["materials"]}
            made.append(
                extract(
                    meshes[b["from"]], f"Beard{k}", roles, budget["beard"], b.get("region"), rule
                )
            )
    for k, h in enumerate(pack["hat"]):
        if "from" in h:
            made.append(
                extract(
                    meshes[h["from"]], f"Hat{k}", {m: "Kit" for m in h["materials"]}, budget["hat"]
                )
            )
            if h.get("under"):
                roles = {m: "Hair" for m in h["under"]}
                made.append(
                    extract(
                        meshes[h["from"]], f"Hat{k}Under", roles, budget["under"], None, None, brows
                    )
                )
    for k, o in enumerate(pack["outfits"]):
        for slot, part in (("top", "Top"), ("legs", "Legs"), ("feet", "Feet")):
            src = meshes[o[slot]]
            roles = {m.name: "Kit" for m in src.data.materials if m}
            roles["Skin"] = "Skin"
            roles.update(o["tint"].get(slot, {}))
            made.append(extract(src, f"Outfit{k}_{part}", roles, budget[slot]))

    # Eyes, for glasses: the face's Eye role triangles.
    eye = [
        p.center for p in face.data.polygons if face.data.materials[p.material_index].name == "Eye"
    ]
    eye_lo = Vector((min(c.x for c in eye), min(c.y for c in eye), min(c.z for c in eye)))
    eye_hi = Vector((max(c.x for c in eye), max(c.y for c in eye), max(c.z for c in eye)))

    # Everything but our objects goes; scale and turn to face -Z in glTF.
    for o in [o for o in bpy.data.objects if o not in made]:
        bpy.data.objects.remove(o)
    floor = min((o.matrix_world @ v.co).z for o in made for v in o.data.vertices)
    scale = rec["_scale"]
    xf = (
        Matrix.Rotation(math.pi, 4, "Z")
        @ Matrix.Scale(scale, 4)
        @ Matrix.Translation((0, 0, -floor))
    )
    for o in made:
        o.data.transform(xf)
        o.matrix_world = Matrix.Identity(4)

    def game(v):  # kit space -> glTF/Godot (x, y up, z): Blender (x, y, z) -> (x, z, -y)
        w = xf @ Vector(v)
        return [round(w.x, 4), round(w.z, 4), round(-w.y, 4)]

    os.makedirs(OUT, exist_ok=True)
    out = os.path.join(OUT, pack["id"] + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=out,
        export_format="GLB",
        use_selection=False,
        export_apply=True,
        export_vertex_color="ACTIVE",
        export_all_vertex_colors=False,
        export_normals=True,
        export_texcoords=False,
        export_materials="EXPORT",
        export_animations=False,
        export_skins=False,
    ) if "export_vertex_color" in bpy.ops.export_scene.gltf.get_rna_type().properties else bpy.ops.export_scene.gltf(
        filepath=out,
        export_format="GLB",
        use_selection=False,
        export_apply=True,
        export_colors=True,
        export_normals=True,
        export_texcoords=False,
        export_materials="EXPORT",
        export_animations=False,
        export_skins=False,
    )
    tris = {o.name: sum(len(p.vertices) - 2 for p in o.data.polygons) for o in made}
    # Each bone's extent on the plain body (face and the first outfit), for ragdoll shapes.
    lo = {b: [9.0] * 3 for b in OURS}
    hi = {b: [-9.0] * 3 for b in OURS}
    for o in made:
        if o.name not in ("Face", "Outfit0_Top", "Outfit0_Legs", "Outfit0_Feet"):
            continue
        col = o.data.color_attributes["Col"].data
        for loop in o.data.loops:
            b = OURS[int(col[loop.index].color[0] * 16.0)]
            v = o.data.vertices[loop.vertex_index].co
            g = (v.x, v.z, -v.y)
            lo[b] = [min(a, c) for a, c in zip(lo[b], g)]
            hi[b] = [max(a, c) for a, c in zip(hi[b], g)]
    names = lambda key: [e["name"] for e in pack[key]]
    entry = {
        "model": "res://assets/people/{}.glb".format(pack["id"]),
        "body": pack["body"],
        "pivots": {b: game(pivots[b]) for b in OURS},
        "bones": {
            b: {"min": [round(c, 4) for c in lo[b]], "max": [round(c, 4) for c in hi[b]]}
            for b in OURS
        },
        "eyes": {
            "centre": game((eye_lo + eye_hi) / 2),
            "half_spacing": round((eye_hi.x - eye_lo.x) / 2 * scale, 4),
        },
        "hair": names("hair"),
        "hair_parts": [f"Hair{k}" if "from" in h else "" for k, h in enumerate(pack["hair"])],
        "beard": names("beard"),
        "beard_parts": [f"Beard{k}" if "from" in b else "" for k, b in enumerate(pack["beard"])],
        "hat": names("hat"),
        "hat_parts": [(f"Hat{k}" if "from" in h else "") for k, h in enumerate(pack["hat"])],
        "hat_under": [
            (f"Hat{k}Under" if h.get("under") else "") for k, h in enumerate(pack["hat"])
        ],
        "outfit": names("outfits"),
        "top": round(
            max(
                v.co.z for o in made if o.name.startswith(("Face", "Hair")) for v in o.data.vertices
            ),
            4,
        ),
        "triangles": tris,
    }
    log(
        pack["id"],
        "->",
        out,
        "parts",
        len(made),
        "max person",
        tris["Face"]
        + max(tris.get(p, 0) for p in entry["hair_parts"] if p)
        + max(
            tris[f"Outfit{k}_Top"] + tris[f"Outfit{k}_Legs"] + tris[f"Outfit{k}_Feet"]
            for k in range(len(pack["outfits"]))
        ),
    )
    return entry


def face_top(pack):
    """The kit height of a pack's face (its skin), before scaling."""
    bpy.ops.wm.open_mainfile(filepath=os.path.join(SRC, pack["source"]))
    o = bpy.data.objects[pack["face"]["from"]]
    feet = min(
        (o2.matrix_world @ v.co).z
        for o2 in bpy.data.objects
        if o2.type == "MESH" and o2.name.endswith("_Feet")
        for v in o2.data.vertices
    )
    skin = [i for i, m in enumerate(o.data.materials) if m and m.name == "Skin"]
    top = max(
        (o.matrix_world @ o.data.vertices[i].co).z
        for p in o.data.polygons
        if p.material_index in skin
        for i in p.vertices
    )
    return top - feet


def main():
    with open(RECIPES) as f:
        rec = json.load(f)
    men = next(p for p in rec["packs"] if p["body"] == 0)
    rec["_scale"] = rec["height_m"] / face_top(men)
    path = os.path.join(OUT, "people.json")
    data = {"packs": {}}
    if os.path.exists(path):
        with open(path) as f:
            data = json.load(f)
    for pack in rec["packs"]:
        if ONLY and pack["id"] not in ONLY:
            continue
        data["packs"][pack["id"]] = build_pack(pack, rec)
    data["about"] = "Written by tools/people_kit/build_people.py; do not edit by hand."
    with open(path, "w") as f:
        json.dump(data, f, indent=1, sort_keys=True)
        f.write("\n")
    log("wrote", path)


main()

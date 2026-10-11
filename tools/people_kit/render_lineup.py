"""Renders the built people (runs inside Blender):

    blender -b --factory-startup -P tools/people_kit/render_lineup.py -- <out.png> <pack.glb> [--side]

Row 1: every outfit, each with the next hair style. Row 2: every hair style, beard and hat. Role
materials get stand-in colours so tinted parts read apart from kit-coloured ones."""

import math
import sys

import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1 :]
out, glb = args[0], args[1]
side = "--side" in args
ROLE = {
    "Skin": (0.80, 0.55, 0.40),
    "Hair": (0.20, 0.12, 0.07),
    "Eye": (0.02, 0.02, 0.02),
    "Stubble": (0.45, 0.30, 0.22),
    "Top": (0.15, 0.35, 0.75),
    "Accent": (0.85, 0.65, 0.10),
    "Bottom": (0.25, 0.25, 0.28),
    "Shoes": (0.45, 0.20, 0.10),
}
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
parts = {o.name: o for o in bpy.data.objects if o.type == "MESH"}
for m in bpy.data.materials:  # the vertex colour holds bone indices: unhook it from the colour
    bsdf = (
        next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if m.use_nodes
        else None
    )
    if bsdf is None:
        continue
    base = bsdf.inputs["Base Color"]
    src = base.links[0].from_node if base.links else None
    colour = ROLE.get(m.name)
    if colour is None and src is not None and src.type == "MIX":
        colour = tuple(src.inputs[7].default_value)[:3]
    for link in list(base.links):
        m.node_tree.links.remove(link)
    if colour is not None:
        base.default_value = (*colour, 1)
for o in parts.values():
    o.hide_render = True
sc = bpy.context.scene


def person(names, x, y):
    for n in names:
        if n and n in parts:
            c = parts[n].copy()
            sc.collection.objects.link(c)
            c.hide_render = False
            c.location = (x, y, 0)
            if side:
                c.rotation_euler.z = math.radians(90)


outfits = sorted(
    {n.split("_")[0] for n in parts if n.startswith("Outfit")}, key=lambda s: int(s[6:])
)
hairs = [f"Hair{k}" for k in range(6)]
for i, o in enumerate(outfits):
    person(["Face", hairs[(i + 1) % 6], o + "_Top", o + "_Legs", o + "_Feet"], i * 0.9, 0)
row2 = [[h] for h in hairs] + [["Beard1"], ["Beard2"], ["Hat1", "Hat1Under"], ["Hat2", "Hat2Under"]]
for i, extra in enumerate(row2):
    person(
        ["Face", "Outfit0_Top", "Outfit0_Legs", "Outfit0_Feet"] + extra,
        i * 0.9 * len(outfits) / len(row2),
        3.0,
    )
engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in engines else "BLENDER_EEVEE"
sc.render.resolution_x, sc.render.resolution_y = 2000, 1100
world = bpy.data.worlds.new("w")
sc.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.75, 0.8, 0.88, 1)
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sun.data.energy = 3.5
sun.rotation_euler = (math.radians(55), 0, math.radians(25))
sc.collection.objects.link(sun)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.type = "ORTHO"
w = (len(outfits) - 1) * 0.9
cam.data.ortho_scale = w + 1.4
aim = Vector((w / 2, 1.5, 1.2))
cam.location = aim + Vector((0, 40, 22)).normalized() * 50
cam.rotation_euler = (aim - cam.location).to_track_quat("-Z", "Y").to_euler()
cam.data.clip_end = 200
sc.render.filepath = out
bpy.ops.render.render(write_still=True)

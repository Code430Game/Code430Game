"""Renders the built vehicles side by side (runs inside Blender):

    blender -b --factory-startup -P tools/vehicle_kit/render_lineup.py -- <out.png> [--rear] <a.glb> ...

The built models face +Y once imported back into Blender; the camera looks at their front
three-quarter (or the rear with --rear)."""

import math
import sys

import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1 :]
out = args.pop(0)
view = 1.0
if args and args[0] == "--rear":
    view = -1.0
    args.pop(0)
bpy.ops.wm.read_factory_settings(use_empty=True)
x = 0.0
top = 0.0
for f in args:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=f)
    new = [o for o in bpy.data.objects if o not in before]
    w = (
        max(
            max((o.matrix_world @ Vector(c)).x for c in o.bound_box)
            for o in new
            if o.type == "MESH"
        )
        * 2
    )
    top = max(
        top,
        max(
            max((o.matrix_world @ Vector(c)).z for c in o.bound_box)
            for o in new
            if o.type == "MESH"
        ),
    )
    for o in new:
        if o.parent is None:
            o.location.x += x + w / 2
    x += w + 0.9
sc = bpy.context.scene
engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in engines else "BLENDER_EEVEE"
sc.render.resolution_x, sc.render.resolution_y = 1800, 640
world = bpy.data.worlds.new("w")
sc.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.75, 0.8, 0.88, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 0.8
bpy.ops.mesh.primitive_plane_add(size=400)
ground = bpy.data.materials.new("ground")
ground.use_nodes = True
ground.node_tree.nodes["Principled BSDF"].inputs[0].default_value = (0.35, 0.36, 0.38, 1)
bpy.context.object.data.materials.append(ground)
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sun.data.energy = 3.5
sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(145 if view > 0 else -35))
sc.collection.objects.link(sun)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.type = "ORTHO"
cam.data.ortho_scale = max(x * 0.92, top * 4.0)
aim = Vector((x / 2 - 0.45, 0, top * 0.45))
cam.location = aim + Vector((0.9 * view, 1.6 * view, 0.9)).normalized() * 60
cam.rotation_euler = (aim - cam.location).to_track_quat("-Z", "Y").to_euler()
cam.data.clip_end = 200
sc.render.filepath = out
bpy.ops.render.render(write_still=True)

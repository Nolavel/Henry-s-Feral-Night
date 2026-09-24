"""Builds Henry's outfit around the UAL mannequin as skinned, continuous meshes.

Each garment is cut from a copy of the body by bone region, pushed out along the
normals and thickened, so it inherits the body's skin weights and bends at the
elbows and knees exactly like the body. Body faces under clothes are removed.
Run: python3 tools/blender/build_henry_outfit.py [--render out_dir]
Writes assets/characters/henry/henry_outfit.glb (body + garments + armature + clips).
"""
import math
import os
import sys

import bpy  # must load before bmesh
import bmesh
from mathutils import Vector

SOURCE = "assets/animation/ual/Unreal-Godot/UAL1_Standard.glb"
OUT = "assets/characters/henry/henry_outfit.glb"

## name: (colour, push-out metres, shell thickness, decimate ratio)
GARMENTS = {
	"Jacket": ((0.30, 0.34, 0.20), 0.028, 0.010, 0.5),
	"Pants": ((0.27, 0.30, 0.36), 0.014, 0.008, 0.5),
	"Boots": ((0.30, 0.22, 0.15), 0.020, 0.012, 1.0),
	"Beanie": ((0.52, 0.20, 0.16), 0.016, 0.010, 0.45),
}
BODY_COLOUR = (0.55, 0.55, 0.56)

TORSO = {"pelvis", "spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r"}
ARMS = {"upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r"}
LEGS = {"thigh_l", "thigh_r", "calf_l", "calf_r"}
FEET = {"foot_l", "foot_r", "ball_l", "ball_r", "ball_leaf_l", "ball_leaf_r"}


def dominant(mesh, obj):
	names = {g.index: g.name for g in obj.vertex_groups}
	out = []
	for v in mesh.vertices:
		best = max(v.groups, key=lambda g: g.weight, default=None)
		out.append(names.get(best.group, "") if best else "")
	return out


def bone_t(arm, bone, p):
	"""Position of p along a bone, 0 at head and 1 at tail, in world space."""
	b = arm.data.bones[bone]
	h = arm.matrix_world @ b.head_local
	t = arm.matrix_world @ b.tail_local
	d = t - h
	return (p - h).dot(d) / d.length_squared


def regions(body, arm):
	"""Per-vertex garment name, or '' for skin, measured on the rest pose."""
	mesh = body.data
	dom = dominant(mesh, body)
	world = [body.matrix_world @ v.co for v in mesh.vertices]
	zs = [p.z for p in world]
	height = max(zs) - min(zs)
	floor = min(zs)
	hem = floor + 0.475 * height  # jacket hem just below the hips
	boot_top = floor + 0.17 * height
	pants_low = boot_top - 0.05  # tucked into the boots
	pants_high = hem + 0.08  # tucked under the jacket
	neck_z = arm.matrix_world @ arm.data.bones["neck_01"].head_local
	head = arm.matrix_world @ arm.data.bones["Head"].head_local
	beanie_z = head.z + 0.56 * (max(zs) - head.z)
	out = []
	extra = []
	for i, p in enumerate(world):
		b = dom[i]
		layers = set()
		if (b in LEGS or b in FEET) and pants_low < p.z < boot_top + 0.04:
			layers.add("Pants")
		if (b in LEGS or b == "pelvis") and hem - 0.02 < p.z < pants_high:
			layers.add("Pants")
		extra.append(layers)
		b = dom[i]
		side = b[-1:] if b.endswith(("_l", "_r")) else ""
		if b in ("Head",) and p.z > beanie_z:
			out.append("Beanie")
		elif b == "neck_01" and p.z < neck_z.z + 0.09:  # high collar
			out.append("Jacket")
		elif b in TORSO or (b in ARMS and not (b.startswith("lowerarm") and bone_t(arm, "lowerarm_" + side, p) > 0.93)):
			out.append("Jacket")
		elif b in LEGS and p.z > hem and b.startswith("thigh"):
			out.append("Jacket")
		elif (b in FEET or b in LEGS) and p.z < boot_top:
			out.append("Boots")
		elif b in LEGS or b in FEET:
			out.append("Pants")
		else:
			out.append("")
	## Overlap: a vertex may belong to its own garment plus the tucked-in layer.
	return [({r} if r else set()) | extra[i] for i, r in enumerate(out)]


def material(name, colour):
	m = bpy.data.materials.new(name)
	m.diffuse_color = (*colour, 1.0)
	m.use_nodes = True
	bsdf = m.node_tree.nodes["Principled BSDF"]
	bsdf.inputs["Base Color"].default_value = (*colour, 1.0)
	bsdf.inputs["Roughness"].default_value = 0.85
	return m


def build_garment(body, arm, name, region, spec):
	colour, push, thick, ratio = spec
	obj = body.copy()
	obj.data = body.data.copy()
	obj.name = obj.data.name = name
	bpy.context.collection.objects.link(obj)
	bm = bmesh.new()
	bm.from_mesh(obj.data)
	bm.verts.ensure_lookup_table()
	keep = {i for i, r in enumerate(region) if name in r}
	## A face touching the region stays: the body is low-poly, so large shin
	## triangles would otherwise leave holes on both sides of a seam.
	bmesh.ops.delete(bm, geom=[f for f in bm.faces if not any(v.index in keep for v in f.verts)], context="FACES")
	bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
	## glTF splits vertices on UV seams; weld them or the push opens cracks.
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
	bm.normal_update()
	for v in bm.verts:
		v.co += v.normal * push
	bm.to_mesh(obj.data)
	bm.free()
	obj.data.materials.clear()
	obj.data.materials.append(material(name, colour))
	bpy.context.view_layer.objects.active = obj
	dec = obj.modifiers.new("Decimate", "DECIMATE")
	dec.ratio = ratio
	sol = obj.modifiers.new("Solidify", "SOLIDIFY")
	sol.thickness = thick
	sol.offset = -1.0
	sol.use_rim = True
	for mod in ("Decimate", "Solidify"):
		bpy.ops.object.modifier_move_to_index(modifier=mod, index=0)
		bpy.ops.object.modifier_apply(modifier=mod)
	for p in obj.data.polygons:
		p.use_smooth = False
	return obj


def mask_body(body, region):
	"""Deletes skin faces fully inside a garment, one ring away from its border."""
	bm = bmesh.new()
	bm.from_mesh(body.data)
	bm.verts.ensure_lookup_table()
	covered = {v.index for v in bm.verts if region[v.index] - {"Beanie"}}
	border = {v.index for v in bm.verts if v.index in covered and any(
		e.other_vert(v).index not in covered for e in v.link_edges)}
	inner = covered - border
	bmesh.ops.delete(bm, geom=[f for f in bm.faces if all(v.index in inner for v in f.verts)], context="FACES")
	bm.to_mesh(body.data)
	bm.free()
	body.data.materials.clear()
	body.data.materials.append(material("Skin", BODY_COLOUR))


def build():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.ops.import_scene.gltf(filepath=SOURCE)
	for o in list(bpy.data.objects):
		if o.type == "MESH" and o.name != "Mannequin":
			bpy.data.objects.remove(o)
	arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
	body = bpy.data.objects["Mannequin"]
	region = regions(body, arm)
	for name, spec in GARMENTS.items():
		build_garment(body, arm, name, region, spec)
	mask_body(body, region)
	return arm


def export(arm):
	os.makedirs(os.path.dirname(OUT), exist_ok=True)
	bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_animations=True,
		export_animation_mode="ACTIONS", export_apply=False, export_yup=True)


def render(arm, out_dir):
	"""Idle/walk/sprint turnaround stills with Cycles on the CPU."""
	scene = bpy.context.scene
	scene.render.engine = "CYCLES"
	scene.cycles.device = "CPU"
	scene.cycles.samples = 24
	scene.render.resolution_x, scene.render.resolution_y = 640, 800
	world = bpy.data.worlds.new("W")
	world.color = (0.8, 0.8, 0.82)
	world.use_nodes = True
	world.node_tree.nodes["Background"].inputs[0].default_value = (0.75, 0.76, 0.78, 1.0)
	world.node_tree.nodes["Background"].inputs[1].default_value = 0.45
	scene.world = world
	sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
	sun.data.energy = 3.0
	sun.rotation_euler = (math.radians(50), 0, math.radians(35))
	scene.collection.objects.link(sun)
	cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
	cam.data.lens = 50
	scene.collection.objects.link(cam)
	scene.camera = cam
	arm.animation_data_create()
	shots = [("Idle_Loop", 0.3), ("Walk_Loop", 0.25), ("Sprint_Loop", 0.25)]
	views = {"front": 0.0, "side": 90.0, "back34": 150.0}
	for clip, phase in shots:
		act = bpy.data.actions[clip]
		arm.animation_data.action = act
		f0, f1 = act.frame_range
		scene.frame_set(int(f0 + phase * (f1 - f0)))
		for view, deg in views.items():
			a = math.radians(deg)
			cam.location = Vector((math.sin(a) * 4.2, -math.cos(a) * 4.2, 1.0))
			cam.rotation_euler = (math.radians(88), 0, a)
			scene.render.filepath = os.path.join(out_dir, f"{clip}_{view}.png")
			bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
	armature = build()
	export(armature)
	if "--render" in sys.argv:
		render(armature, sys.argv[sys.argv.index("--render") + 1])

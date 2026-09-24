"""Builds Henry's outfit around the UAL mannequin as skinned, continuous meshes.

Each garment is cut from a copy of the body by bone region, pushed out along the
normals and thickened, so it inherits the body's skin weights and bends at the
elbows and knees exactly like the body. Skin under each garment is split into
Skin_<item> meshes the game hides while that item is worn.
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

## name: (colour, push-out metres, shell thickness, smoothing passes)
## Smoothing irons out the mannequin's muscles so cloth reads as panels.
GARMENTS = {
	"Jacket": ((0.30, 0.34, 0.20), 0.030, 0.010, 12),
	"Pants": ((0.27, 0.30, 0.36), 0.014, 0.008, 8),
	"Boots": ((0.30, 0.22, 0.15), 0.020, 0.012, 6),
	"Sole": ((0.17, 0.12, 0.09), 0.022, 0.014, 2),
	"Beanie": ((0.52, 0.20, 0.16), 0.016, 0.010, 6),
	"BeanieCuff": ((0.46, 0.17, 0.14), 0.034, 0.014, 4),
}
BODY_COLOUR = (0.55, 0.55, 0.56)
DECIMATE_RATIO = 0.35
CUTS = {}
## Garments whose edge follows whole faces; the rest also keep faces straddling it.
CLEAN_EDGE = set()
HOOD_COLOUR = (0.28, 0.32, 0.19)

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
		if b == "Head" and beanie_z - 0.005 < p.z < beanie_z + 0.045:
			layers.add("BeanieCuff")
		if b in FEET and p.z < floor + 0.035:
			layers.add("Sole")
		extra.append(layers)
		b = dom[i]
		side = b[-1:] if b.endswith(("_l", "_r")) else ""
		if b in ("Head",) and p.z > beanie_z:
			out.append("Beanie")
		elif b == "neck_01":  # high collar up to the jaw
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
	## Rest-pose heights where a garment edge is cut straight.
	CUTS.update({"Pants": (pants_low, None), "Boots": (None, boot_top),
		"Beanie": (beanie_z, None)})
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
	colour, push, thick, passes = spec
	obj = body.copy()
	obj.data = body.data.copy()
	obj.name = obj.data.name = "Outfit_" + name
	bpy.context.collection.objects.link(obj)
	bm = bmesh.new()
	bm.from_mesh(obj.data)
	bm.verts.ensure_lookup_table()
	keep = {i for i, r in enumerate(region) if name in r}
	## A face touching the region stays: the body is low-poly, so large shin
	## triangles would otherwise leave holes on both sides of a seam.
	test = all if name in CLEAN_EDGE else any
	bmesh.ops.delete(bm, geom=[f for f in bm.faces if not test(v.index in keep for v in f.verts)], context="FACES")
	bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
	## glTF splits vertices on UV seams; weld them or the push opens cracks.
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
	bm.normal_update()
	rest = {v: (v.co.copy(), v.normal.copy()) for v in bm.verts}
	for _ in range(passes):
		bmesh.ops.smooth_vert(bm, verts=bm.verts, factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
	bm.normal_update()
	## Push from the smoothed surface by a uniform depth covering most muscle peaks;
	## skin under the garment is masked, so the rare peak left cannot poke through.
	sunk = sorted(max(0.0, (rest[v][0] - v.co).dot(v.normal)) for v in bm.verts)
	depth = push + sunk[int(len(sunk) * 0.7)]
	low, high = CUTS.get(name, (None, None))
	for v in bm.verts:
		v.co += v.normal * depth
		if low is not None and rest[v][0].z < low:
			v.co.z = max(v.co.z, low)
		if high is not None and rest[v][0].z > high:
			v.co.z = min(v.co.z, high)
	bm.to_mesh(obj.data)
	bm.free()
	obj.data.materials.clear()
	obj.data.materials.append(material(name, colour))
	bpy.context.view_layer.objects.active = obj
	dec = obj.modifiers.new("Decimate", "DECIMATE")
	dec.ratio = DECIMATE_RATIO
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


## Garment piece to the equipment mesh name (GarmentData.mesh_node_name) it belongs to.
ITEM_OF = {"Jacket": "Coat", "Hood": "Coat", "Pants": "Trousers", "Boots": "Boots", "Sole": "Boots",
	"Beanie": "Hat", "BeanieCuff": "Hat"}
## Which garment owns skin under overlapping layers, outermost first.
SKIN_PRIORITY = ("Jacket", "Boots", "Pants")


def split_body(body, region):
	"""Moves skin fully inside a garment (one ring from its border) into Skin_<item>
	meshes, which the game hides while that item is worn."""
	owner = [next((g for g in SKIN_PRIORITY if g in r), "") for r in region]
	bm = bmesh.new()
	bm.from_mesh(body.data)
	bm.verts.ensure_lookup_table()
	border = {v.index for v in bm.verts if owner[v.index] and any(
		owner[e.other_vert(v).index] != owner[v.index] for e in v.link_edges)}
	face_owner = {}
	for f in bm.faces:
		labels = {owner[v.index] for v in f.verts}
		if len(labels) == 1 and "" not in labels and not any(v.index in border for v in f.verts):
			face_owner[f.index] = ITEM_OF[labels.pop()]
	bm.free()
	skin = material("Skin", BODY_COLOUR)
	for item in sorted(set(face_owner.values())) + [""]:
		part = body if item == "" else body.copy()
		if item:
			part.data = body.data.copy()
			part.name = part.data.name = "Skin_" + item
			bpy.context.collection.objects.link(part)
		pm = bmesh.new()
		pm.from_mesh(part.data)
		pm.faces.ensure_lookup_table()
		drop = [f for f in pm.faces if face_owner.get(f.index, "") != item]
		bmesh.ops.delete(pm, geom=drop, context="FACES")
		bmesh.ops.delete(pm, geom=[v for v in pm.verts if not v.link_faces], context="VERTS")
		pm.to_mesh(part.data)
		pm.free()
		part.data.materials.clear()
		part.data.materials.append(skin)


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
	split_body(body, region)
	build_hood(arm, body)
	return arm


def build_hood(arm, body):
	"""A hood folded down behind the neck: a flattened ring skinned to neck and chest."""
	neck = arm.matrix_world @ arm.data.bones["neck_01"].head_local
	bpy.ops.mesh.primitive_torus_add(major_radius=0.12, minor_radius=0.05, major_segments=12,
		minor_segments=6, location=(neck.x, neck.y + 0.03, neck.z + 0.075))
	hood = bpy.context.active_object
	hood.name = hood.data.name = "Outfit_Hood"
	hood.scale = (1.05, 0.95, 0.75)
	hood.rotation_euler = (math.radians(-18), 0.0, 0.0)  # tips up at the back
	bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
	bm = bmesh.new()
	bm.from_mesh(hood.data)
	for v in bm.verts:
		if v.co.y < -0.02:  # the front of the ring hides under the collar
			v.co.z -= 0.03
	bm.to_mesh(hood.data)
	bm.free()
	for bone, w in (("neck_01", 0.6), ("spine_03", 0.4)):
		g = hood.vertex_groups.new(name=bone)
		g.add(range(len(hood.data.vertices)), w, "REPLACE")
	hood.parent = arm
	hood.matrix_parent_inverse = arm.matrix_world.inverted()
	hood.modifiers.new("Armature", "ARMATURE").object = arm
	hood.data.materials.append(material("Hood", HOOD_COLOUR))
	for p in hood.data.polygons:
		p.use_smooth = False


def export(arm):
	os.makedirs(os.path.dirname(OUT), exist_ok=True)
	bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_animations=True,
		export_animation_mode="ACTIONS", export_apply=False, export_yup=True)


def render(arm, out_dir):
	"""Idle/walk/sprint turnaround stills with Cycles on the CPU."""
	scene = bpy.context.scene
	for o in bpy.data.objects:
		o.hide_render = o.name.startswith("Skin_")  # all items worn, as in game
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

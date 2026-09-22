import bpy
import json
import math
import os
import sys
from mathutils import Vector, Matrix

ROOT = os.getcwd()
HENRY_PATH = os.path.join(ROOT, "assets/models/characters/henry_test_model/Henry_Test_player.glb")
UAL_PATH = os.path.join(ROOT, "assets/animation/ual/Unreal-Godot/UAL1_Standard.glb")
OUT_DIR = os.path.join(ROOT, "assets/models/characters/henry_ual")
PREVIEW_DIR = os.path.join(ROOT, "docs/rig_previews/henry_ual")
OUT_GLB = os.path.join(OUT_DIR, "Henry_UAL_Rigged.glb")
REPORT_PATH = os.path.join(PREVIEW_DIR, "rig_report.json")

os.makedirs(OUT_DIR, exist_ok=True)
os.makedirs(PREVIEW_DIR, exist_ok=True)


def log(msg):
    print(f"[HFN-RIG] {msg}", flush=True)


def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for datablocks in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.armatures,
        bpy.data.cameras,
        bpy.data.lights,
    ):
        for block in list(datablocks):
            if block.users == 0:
                datablocks.remove(block)


def import_glb(path):
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    after = set(bpy.context.scene.objects)
    return list(after - before)


def bbox_world(objects):
    pts = []
    for obj in objects:
        if obj.type != 'MESH':
            continue
        for corner in obj.bound_box:
            pts.append(obj.matrix_world @ Vector(corner))
    if not pts:
        raise RuntimeError("No mesh bounds available")
    min_v = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    max_v = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return min_v, max_v


def bottom_center(bounds):
    mn, mx = bounds
    return Vector(((mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5, mn.z))


def set_active(obj):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def choose_armature(objects):
    arms = [o for o in objects if o.type == 'ARMATURE']
    if not arms:
        raise RuntimeError("UAL import has no armature")
    arms.sort(key=lambda o: len(o.data.bones), reverse=True)
    return arms[0]


def choose_donor_mesh(objects, armature):
    meshes = [o for o in objects if o.type == 'MESH']
    if not meshes:
        raise RuntimeError("UAL import has no mesh")

    def score(obj):
        has_arm = any(m.type == 'ARMATURE' and m.object == armature for m in obj.modifiers)
        parented = obj.parent == armature
        return (1 if (has_arm or parented) else 0, len(obj.data.vertices))

    meshes.sort(key=score, reverse=True)
    return meshes[0]


def align_henry_to_donor(henry_meshes, donor_mesh):
    src_bounds = bbox_world(henry_meshes)
    dst_bounds = bbox_world([donor_mesh])
    src_h = max(src_bounds[1].z - src_bounds[0].z, 1e-6)
    dst_h = max(dst_bounds[1].z - dst_bounds[0].z, 1e-6)
    scale = dst_h / src_h

    src_anchor = bottom_center(src_bounds)
    dst_anchor = bottom_center(dst_bounds)
    xform = (
        Matrix.Translation(dst_anchor)
        @ Matrix.Scale(scale, 4)
        @ Matrix.Translation(-src_anchor)
    )
    for obj in henry_meshes:
        obj.matrix_world = xform @ obj.matrix_world

    return scale, src_bounds, dst_bounds


def transfer_weights(target, donor, armature):
    # The imported Tripo mesh is not skinned. Rebuild groups to match UAL bones exactly.
    target.vertex_groups.clear()
    for vg in donor.vertex_groups:
        target.vertex_groups.new(name=vg.name)

    set_active(target)
    mod = target.modifiers.new(name="UAL_WeightTransfer", type='DATA_TRANSFER')
    mod.object = donor
    mod.use_vert_data = True
    mod.data_types_verts = {'VGROUP_WEIGHTS'}
    mod.vert_mapping = 'POLYINTERP_NEAREST'
    mod.mix_mode = 'REPLACE'
    mod.mix_factor = 1.0

    if hasattr(mod, "layers_vgroup_select_src"):
        mod.layers_vgroup_select_src = 'ALL'
    if hasattr(mod, "layers_vgroup_select_dst"):
        mod.layers_vgroup_select_dst = 'NAME'

    bpy.ops.object.modifier_apply(modifier=mod.name)

    arm_mod = target.modifiers.new(name="UAL_Armature", type='ARMATURE')
    arm_mod.object = armature
    arm_mod.use_deform_preserve_volume = True

    world = target.matrix_world.copy()
    target.parent = armature
    target.matrix_world = world


def normalize_weights(target):
    set_active(target)
    try:
        bpy.ops.object.vertex_group_normalize_all(lock_active=False)
    except Exception as exc:
        log(f"normalize_all skipped for {target.name}: {exc}")


def weight_stats(target):
    total = len(target.data.vertices)
    unweighted = 0
    weak = 0
    for v in target.data.vertices:
        weight_sum = sum(g.weight for g in v.groups)
        if not v.groups:
            unweighted += 1
        elif weight_sum < 0.50:
            weak += 1
    return {
        "vertices": total,
        "unweighted_vertices": unweighted,
        "weak_weight_vertices": weak,
        "unweighted_ratio": (unweighted / total) if total else 0.0,
    }


def remove_objects(objects):
    for obj in list(objects):
        if obj and obj.name in bpy.data.objects:
            bpy.data.objects.remove(obj, do_unlink=True)


def action_by_alias(aliases):
    lowered = [(a, a.name.lower()) for a in bpy.data.actions]
    for alias in aliases:
        needle = alias.lower()
        for action, name in lowered:
            if name == needle or name.endswith("|" + needle) or needle in name:
                return action
    return None


def set_action(armature, aliases, phase=0.5):
    action = action_by_alias(aliases)
    if action is None:
        armature.animation_data_clear()
        return None, 0
    if armature.animation_data is None:
        armature.animation_data_create()
    armature.animation_data.action = action
    start, end = action.frame_range
    frame = int(round(start + (end - start) * phase))
    bpy.context.scene.frame_set(frame)
    bpy.context.view_layer.update()
    return action.name, frame


def set_render_engine(scene):
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE", "BLENDER_WORKBENCH"):
        try:
            scene.render.engine = engine
            return engine
        except Exception:
            pass
    return scene.render.engine


def look_at(camera, point):
    direction = point - camera.location
    camera.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()


def make_material(name, color, roughness=0.6):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Roughness"].default_value = roughness
    return mat


def setup_preview_scene(target_meshes):
    scene = bpy.context.scene
    engine = set_render_engine(scene)
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.film_transparent = False

    if hasattr(scene, "eevee"):
        scene.eevee.taa_render_samples = 32

    world = bpy.data.worlds.new("HFN_RigPreview_World") if not scene.world else scene.world
    scene.world = world
    world.color = (0.025, 0.03, 0.04)

    mn, mx = bbox_world(target_meshes)
    height = max(mx.z - mn.z, 0.1)
    center = Vector(((mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5, mn.z + height * 0.52))

    bpy.ops.mesh.primitive_plane_add(size=max(6.0, height * 4.0), location=(center.x, center.y, mn.z - 0.01))
    ground = bpy.context.object
    ground.name = "PreviewGround"
    ground.data.materials.append(make_material("PreviewGroundMat", (0.055, 0.065, 0.08), 0.82))

    bpy.ops.object.light_add(type='AREA', location=(center.x + height * 1.1, center.y - height * 1.3, mn.z + height * 1.65))
    key = bpy.context.object
    key.name = "KeyLight"
    key.data.energy = 950
    key.data.shape = 'DISK'
    key.data.size = height * 1.2
    key.rotation_euler = (math.radians(25), 0, math.radians(35))

    bpy.ops.object.light_add(type='AREA', location=(center.x - height * 1.0, center.y + height * 0.7, mn.z + height * 1.15))
    fill = bpy.context.object
    fill.name = "FillLight"
    fill.data.energy = 500
    fill.data.size = height * 1.0

    bpy.ops.object.light_add(type='AREA', location=(center.x, center.y + height * 0.2, mn.z + height * 2.0))
    rim = bpy.context.object
    rim.name = "RimLight"
    rim.data.energy = 700
    rim.data.size = height * 0.8

    cam_data = bpy.data.cameras.new("RigPreviewCamera")
    cam = bpy.data.objects.new("RigPreviewCamera", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.data.lens = 62

    return scene, cam, center, height, ground, engine


def render_pose(scene, camera, target, height, filename, view="front"):
    if view == "front":
        camera.location = target + Vector((0.0, -height * 2.2, height * 0.12))
    elif view == "three_quarter":
        camera.location = target + Vector((height * 1.25, -height * 2.0, height * 0.15))
    elif view == "side":
        camera.location = target + Vector((height * 2.15, 0.0, height * 0.10))
    else:
        camera.location = target + Vector((0.0, -height * 2.2, height * 0.12))

    look_at(camera, target)
    scene.render.filepath = os.path.join(PREVIEW_DIR, filename)
    bpy.ops.render.render(write_still=True)


def select_export_objects(armature, target_meshes):
    bpy.ops.object.select_all(action='DESELECT')
    armature.select_set(True)
    for obj in target_meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = armature


def export_glb(armature, target_meshes):
    select_export_objects(armature, target_meshes)
    kwargs = dict(
        filepath=OUT_GLB,
        export_format='GLB',
        use_selection=True,
        export_animations=True,
        export_skins=True,
        export_all_influences=False,
        export_apply=False,
    )
    try:
        bpy.ops.export_scene.gltf(**kwargs)
    except TypeError:
        kwargs.pop("export_all_influences", None)
        kwargs.pop("export_apply", None)
        bpy.ops.export_scene.gltf(**kwargs)


def main():
    clear_scene()

    log(f"Import UAL: {UAL_PATH}")
    ual_objects = import_glb(UAL_PATH)
    armature = choose_armature(ual_objects)
    donor = choose_donor_mesh(ual_objects, armature)
    donor_name = donor.name
    donor_vertex_group_count = len(donor.vertex_groups)
    armature.name = "Henry_UAL_Armature"
    armature.data.pose_position = 'REST'

    ual_meshes = [o for o in ual_objects if o.type == 'MESH']
    log(f"UAL armature bones={len(armature.data.bones)} donor={donor.name} verts={len(donor.data.vertices)}")
    log(f"UAL actions={[a.name for a in bpy.data.actions]}")

    log(f"Import Henry: {HENRY_PATH}")
    henry_objects = import_glb(HENRY_PATH)
    henry_meshes = [o for o in henry_objects if o.type == 'MESH']
    if not henry_meshes:
        raise RuntimeError("Henry GLB imported without mesh")

    scale, src_bounds, dst_bounds = align_henry_to_donor(henry_meshes, donor)
    log(f"Henry meshes={[(o.name, len(o.data.vertices)) for o in henry_meshes]}")
    log(f"Alignment scale={scale:.6f}")

    for idx, target in enumerate(henry_meshes):
        target.name = "Henry_Body" if idx == 0 else f"Henry_Body_{idx:02d}"
        transfer_weights(target, donor, armature)
        normalize_weights(target)

    stats = {obj.name: weight_stats(obj) for obj in henry_meshes}
    log(f"Weight stats={stats}")

    # Remove UAL mannequin geometry only; keep armature and imported actions.
    remove_objects(ual_meshes)
    armature.data.pose_position = 'POSE'

    # Remove empty roots from Henry import if they are no longer needed.
    for obj in list(henry_objects):
        if obj.type == 'EMPTY' and obj.name in bpy.data.objects and not obj.children:
            bpy.data.objects.remove(obj, do_unlink=True)

    export_glb(armature, henry_meshes)
    log(f"Exported {OUT_GLB}")

    scene, camera, center, height, ground, engine = setup_preview_scene(henry_meshes)
    poses = {}

    pose_specs = [
        ("idle_front.png", ["Idle", "Idle_Loop"], 0.50, "front"),
        ("walk_3q.png", ["Walk", "Walk_Loop"], 0.55, "three_quarter"),
        ("sprint_side.png", ["Sprint", "Sprint_Loop", "Jog_Fwd", "Jog_Fwd_Loop"], 0.62, "side"),
        ("stress_pose.png", ["Jog_Fwd", "Jog_Fwd_Loop", "Sprint", "Sprint_Loop"], 0.83, "front"),
    ]
    for filename, aliases, phase, view in pose_specs:
        action_name, frame = set_action(armature, aliases, phase)
        poses[filename] = {"action": action_name, "frame": frame, "view": view}
        render_pose(scene, camera, center, height, filename, view)

    report = {
        "blender_version": bpy.app.version_string,
        "render_engine": engine,
        "source_henry": os.path.relpath(HENRY_PATH, ROOT),
        "source_ual": os.path.relpath(UAL_PATH, ROOT),
        "output_glb": os.path.relpath(OUT_GLB, ROOT),
        "armature": armature.name,
        "bone_count": len(armature.data.bones),
        "donor_mesh": donor_name,
        "donor_vertex_groups": donor_vertex_group_count,
        "henry_meshes": [o.name for o in henry_meshes],
        "alignment_scale": scale,
        "source_bounds": {
            "min": list(src_bounds[0]),
            "max": list(src_bounds[1]),
        },
        "donor_bounds": {
            "min": list(dst_bounds[0]),
            "max": list(dst_bounds[1]),
        },
        "weight_stats": stats,
        "actions": [a.name for a in bpy.data.actions],
        "previews": poses,
    }
    with open(REPORT_PATH, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)

    log(f"Report: {REPORT_PATH}")


if __name__ == "__main__":
    main()

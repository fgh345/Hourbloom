"""Merge validated hoe poses with the existing gameplay clips on one rig.

Run Blender with --background --factory-startup --python this_file.
Source .blend files remain unchanged. Ordinary hands and grip hands export as
separate meshes so gameplay can switch them together with the visible tool.
"""
from pathlib import Path
import json
import math
import bpy
from mathutils import Matrix, Vector

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SOURCE = ROOT / 'Art/Characters/ForestGirl/runtime.blend'
OUTPUT = ROOT / 'Assets/Tools/Hoe/forest_girl_tools.glb'
FPS = 240


def reset(rig):
    for bone in rig.pose.bones:
        bone.rotation_mode = 'QUATERNION'
        bone.matrix_basis.identity()


def export(objects, path):
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = next(ob for ob in objects if ob.type == 'ARMATURE')
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True,
        use_active_scene=True, export_animations=True, export_animation_mode='NLA_TRACKS',
        export_yup=True, export_skins=True, export_morph=False)


# Bake the original local pose channels in seconds before changing the rest
# proportions. Bone axes are unchanged; local zero translations still join the
# newly lengthened upper arm, forearm and hand without animated scaling.
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
source_scene = bpy.context.scene
source_rig = next(ob for ob in source_scene.objects if ob.type == 'ARMATURE')
source_fps = source_scene.render.fps / source_scene.render.fps_base
for track in source_rig.animation_data.nla_tracks:
    track.mute = True
source_tracks = [(track.name, track.strips[0].action) for track in source_rig.animation_data.nla_tracks]
source_manifest = json.loads((SOURCE.parent/'runtime_manifest.json').read_text())
loops = {clip['name']: clip['loop'] for clip in source_manifest['clips']}
source_rest = {bone.name: bone.matrix_local.copy() for bone in source_rig.data.bones}
open_hands = {}
for ob in source_scene.objects:
    if ob.type == 'MESH' and ob.name.startswith('Hand •'):
        weighted = [group.name for group in ob.vertex_groups]
        bone_name = next(name for name in weighted if name.startswith('hand.'))
        open_hands[ob.name] = (bone_name, source_rig.matrix_world.inverted() @ ob.matrix_world)
records = []
for name, action in source_tracks:
    start, end = action.frame_range
    seconds = (end-start)/source_fps
    last = round(seconds*FPS)
    frames = []
    source_rig.animation_data.action = action
    for frame in range(last+1):
        reset(source_rig)
        sample = start + frame/FPS*source_fps
        source_scene.frame_set(math.floor(sample), subframe=sample%1)
        bpy.context.view_layer.update()
        frames.append({bone.name: (tuple(bone.location), tuple(bone.rotation_quaternion), tuple(bone.scale))
            for bone in source_rig.pose.bones})
    records.append((name, seconds, frames))

bpy.ops.wm.open_mainfile(filepath=str(HERE/'hoe_preview.blend'))
scene = bpy.context.scene
scene.name = 'ForestGirl_Tools_Runtime'
scene.render.fps = FPS
rig = next(ob for ob in scene.objects if ob.type == 'ARMATURE')
hoe_actions = [(track.name, track.strips[0].action) for track in rig.animation_data.nla_tracks
    if track.name == 'Hoe']
unused_hoe_actions = [track.strips[0].action for track in rig.animation_data.nla_tracks
    if track.name == 'HoeIdle']
assert len(hoe_actions) == 1
rig.animation_data_clear()
for action in unused_hoe_actions:
    bpy.data.actions.remove(action)
rig.animation_data_create()
reset(rig)
bpy.context.view_layer.update()

# Append only the source open hand objects and rebind their vertices to the new
# wrist rest matrices. Their materials, vertex colors and finger detail survive.
with bpy.data.libraries.load(str(SOURCE), link=False) as (available, requested):
    requested.objects = list(open_hands)
for ob in requested.objects:
    original = next(name for name in open_hands if ob.name == name or ob.name.startswith(name+'.'))
    bone_name, original_local = open_hands[original]
    rest_change = rig.data.bones[bone_name].matrix_local @ source_rest[bone_name].inverted() @ original_local
    for vertex in ob.data.vertices:
        vertex.co = rest_change @ vertex.co
    ob.data.update()
    side = bone_name[-1]
    ob.name = 'OpenHand_'+side+'_'+original.split('•',1)[1].strip().replace(' ', '_')
    scene.collection.objects.link(ob)
    ob.parent = rig
    ob.matrix_parent_inverse = Matrix.Identity(4)
    ob.matrix_basis = Matrix.Identity(4)
    for modifier in ob.modifiers:
        if modifier.type == 'ARMATURE':
            modifier.object = rig


def attach(action, name):
    action.name = 'Runtime_'+name
    action.use_fake_user = True
    track = rig.animation_data.nla_tracks.new()
    track.name = name
    strip = track.strips.new(name, 0, action)
    strip.name = name
    track.mute = True


# The use clip is already baked at 240 fps; preserve its exact transforms.
for name, action in hoe_actions:
    attach(action, name)
clips = [{'name': name, 'duration': (action.frame_range[1]-action.frame_range[0])/FPS,
          'loop': False} for name, action in hoe_actions]
for name, seconds, frames in records:
    rig.animation_data.action = None
    previous = {}
    for frame, values in enumerate(frames):
        reset(rig)
        for bone_name, (location, rotation, scale) in values.items():
            bone = rig.pose.bones[bone_name]
            bone.location = location
            bone.rotation_quaternion = rotation
            if bone_name in previous and bone.rotation_quaternion.dot(previous[bone_name]) < 0:
                bone.rotation_quaternion.negate()
            previous[bone_name] = bone.rotation_quaternion.copy()
            bone.scale = scale
            for path in ('location', 'rotation_quaternion', 'scale'):
                bone.keyframe_insert(data_path=path, frame=frame, group=bone_name)
        # The unused tool bone receives its neutral rest pose to prevent stale
        # Hoe transforms during transitions back to locomotion.
        bone = rig.pose.bones['hoe_tool']
        for path in ('location', 'rotation_quaternion', 'scale'):
            bone.keyframe_insert(data_path=path, frame=frame, group='hoe_tool')
    action = rig.animation_data.action
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for fc in bag.fcurves:
                    for key in fc.keyframe_points:
                        key.interpolation = 'LINEAR'
    rig.animation_data.action = None
    attach(action, name)
    clips.append({'name': name, 'duration': seconds, 'loop': loops[name]})
reset(rig)
rig.animation_data.action = None
scene.frame_start = 0
scene.frame_end = round(max(clip['duration'] for clip in clips)*FPS)
bpy.context.view_layer.update()
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'runtime.blend'))
export(list(scene.objects), OUTPUT)

# Validate the actual exported skeleton, clip duration and invariant segment
# lengths. This also catches accidentally interpreting 24 fps clips as 240 fps.
verification = bpy.data.scenes.new('Tools_Export_Verification')
verification.render.fps = FPS
bpy.context.window.scene = verification
bpy.ops.import_scene.gltf(filepath=str(OUTPUT))
verified = next(ob for ob in verification.objects if ob.type == 'ARMATURE')
for track in verified.animation_data.nla_tracks:
    track.mute = True
expected = {clip['name']: clip for clip in clips}
assert len(verified.data.bones) == 17
assert set(track.name for track in verified.animation_data.nla_tracks) == set(expected)
maximum_length_error = 0.0
maximum_grip_error = 0.0
maximum_wrist_roll = 0.0
for track in verified.animation_data.nla_tracks:
    action = track.strips[0].action
    start, end = action.frame_range
    actual_seconds = (end-start)/FPS
    assert abs(actual_seconds-expected[track.name]['duration']) < 1e-5, (track.name, actual_seconds)
    verified.animation_data.action = action
    for step in range(21):
        sample = start+(end-start)*step/20
        verification.frame_set(math.floor(sample), subframe=sample%1)
        bpy.context.view_layer.update()
        for bone in verified.pose.bones:
            assert all(math.isfinite(value) for row in bone.matrix for value in row)
            assert max(abs(value-1) for value in bone.scale) < 1e-4, (track.name, bone.name, tuple(bone.scale))
        for side in ('L','R'):
            upper, forearm, hand = (verified.pose.bones[prefix+'.'+side] for prefix in ('upper_arm','forearm','hand'))
            for bone, endpoint in ((upper, forearm.head), (forearm, hand.head)):
                actual = (verified.matrix_world.to_3x3()@(endpoint-bone.head)).length
                rest = (verified.matrix_world.to_3x3()@(bone.bone.tail_local-bone.bone.head_local)).length
                error = abs(actual-rest)
                maximum_length_error = max(maximum_length_error, error)
                assert error < 1e-5, (track.name, side, error)
            if track.name == 'Hoe':
                tool = verified.matrix_world @ verified.pose.bones['hoe_tool'].matrix
                scale = tool.to_scale().x
                sign = -1 if side == 'L' else 1
                grip_z = .62 if side == 'L' else .745
                expected_wrist = tool @ Vector((sign*.041/scale, 0, (grip_z+.006)/scale))
                grip_error = (verified.matrix_world @ hand.head - expected_wrist).length
                maximum_grip_error = max(maximum_grip_error, grip_error)
                assert grip_error < .003, (track.name, side, grip_error)
                axis = (verified.matrix_world.to_3x3() @ (hand.head-forearm.head)).normalized()
                rest_axis = (forearm.bone.tail_local-forearm.bone.head_local).normalized()
                rest_radial = rest_axis.cross(Vector((0,1,0))).normalized()
                radial = verified.matrix_world.to_3x3() @ (forearm.matrix.to_3x3()
                    @ forearm.bone.matrix_local.to_3x3().inverted() @ rest_radial)
                radial = (radial-axis*radial.dot(axis)).normalized()
                reference = (tool.to_3x3() @ Vector((0,1,0))).normalized().cross(axis)
                assert reference.length > .25
                reference.normalize()
                roll = abs(math.degrees(math.atan2(axis.dot(radial.cross(reference)), radial.dot(reference))))
                maximum_wrist_roll = max(maximum_wrist_roll, roll)
                assert roll < .1, (track.name, side, roll)
report = {'source_character': str(SOURCE.relative_to(ROOT)), 'source_hoe': 'Art/Tools/Hoe/hoe_preview.blend',
    'fps': FPS, 'clips': clips, 'bones': [bone.name for bone in verified.data.bones],
    'skeleton_path': 'ForestGirlScale/Forest_Girl_Rig/Skeleton3D',
    'tool_mesh_prefix': 'Hoe_', 'grip_hand_mesh_prefix': 'GripHand_', 'open_hand_mesh_prefix': 'OpenHand_',
    'continuous_arm_mesh_prefix': 'HoeArm_', 'open_hand_mesh_count': len(open_hands),
    'max_exported_arm_length_error_m': maximum_length_error,
    'max_exported_grip_error_m': maximum_grip_error, 'max_axial_wrist_roll_degrees': maximum_wrist_roll,
    'impact_time': json.loads((HERE/'manifest.json').read_text())['impact_time'], 'impact_position_godot': json.loads((HERE/'manifest.json').read_text())['impact_position_godot']}
(HERE/'runtime_manifest.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
print('HOE_RUNTIME_REPORT', json.dumps(report, ensure_ascii=False))

# Restore the ordinary farming/interaction clips after a fresh tool export.
import runpy
runpy.run_path(str(HERE / 'add_basic_actions.py'))

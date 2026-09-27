"""Import the supplied GLB, refine its profile and add gameplay movement clips.

Run in Blender with --background --factory-startup --python this_file.
Source attachments are never executed. Scaling lives on a shared parent so
mesh/bind matrices and the supplied Idle/Walk animation remain compatible.
"""
from pathlib import Path
import json
import math
import sys
import bpy
from mathutils import Matrix, Vector

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from shape_profile import reshape
ROOT = HERE.parents[2]
SOURCE = HERE / 'Source' / 'forest_girl.glb'
OUTPUT = ROOT / 'Assets' / 'Characters' / 'ForestGirl' / 'forest_girl.glb'

def main():
    studio = bpy.data.scenes.new('ForestGirl_Runtime_Studio')
    bpy.context.window.scene = studio
    prior_objects = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    for obj in list(studio.objects):
        if obj in prior_objects:
            for collection in list(obj.users_collection):
                if collection == studio.collection or collection in studio.collection.children_recursive:
                    collection.objects.unlink(obj)
    rig = next(o for o in studio.objects if o.type == 'ARMATURE')
    custom_shapes = {pb.custom_shape for pb in rig.pose.bones if pb.custom_shape}
    for obj in custom_shapes:
        for collection in list(obj.users_collection):
            collection.objects.unlink(obj)
    meshes = [o for o in studio.objects if o.type == 'MESH']
    studio.render.fps = 24
    rig.animation_data.action = None
    for track in rig.animation_data.nla_tracks:
        track.mute = True
    for pb in rig.pose.bones:
        pb.matrix_basis.identity()
    bpy.context.view_layer.update()
    profile_report = reshape(meshes)
    bpy.context.view_layer.update()
    corners = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    low, high = min(p.z for p in corners), max(p.z for p in corners)
    scale = 1.20 / (high-low)
    wrapper = bpy.data.objects.new('ForestGirlScale', None)
    studio.collection.objects.link(wrapper)
    for obj in list(studio.objects):
        if obj != wrapper and obj.parent is None:
            transform = obj.matrix_world.copy()
            obj.parent = wrapper
            obj.matrix_world = transform
    wrapper.scale = (scale,)*3
    wrapper.location.z = -low*scale
    source_actions = {a.name:a for a in bpy.data.actions if a.name in ('Idle','Walk')}
    clips = []
    def attach(action, name, loop):
        action.name = name
        action.use_fake_user = True
        action['loop'] = loop
        track = rig.animation_data.nla_tracks.new()
        track.name = name
        strip = track.strips.new(name,1,action)
        strip.name = name
        track.mute = True
        clips.append({'name':name, 'duration':float(action.frame_range[1]-action.frame_range[0])/24, 'loop':loop})
    for name in ('Idle','Walk'):
        a = source_actions[name]
        clips.append({'name':name,'duration':float(a.frame_range[1]-a.frame_range[0])/24,'loop':True,'source':'user'})
        attach(a.copy(), 'freehand_'+name.lower(), True)
    def reset():
        for pb in rig.pose.bones:
            # Imported Idle/Walk actions use quaternion channels. All clips
            # sharing this rig must use that same rotation representation.
            pb.rotation_mode = 'QUATERNION'
            pb.rotation_quaternion = (1,0,0,0)
            pb.location = (0,0,0)
            pb.scale = (1,1,1)
    def rotate(name, x=0, y=0, z=0):
        basis = rig.data.bones[name].matrix_local.to_3x3()
        rotation = Matrix.Rotation(z,3,'Z') @ Matrix.Rotation(y,3,'Y') @ Matrix.Rotation(x,3,'X')
        rig.pose.bones[name].rotation_quaternion = (basis.inverted() @ rotation @ basis).to_quaternion()
    def offset(name, position):
        rig.pose.bones[name].location = rig.data.bones[name].matrix_local.to_3x3().inverted() @ Vector(position)
    def make(name, seconds, pose, loop=False):
        rig.animation_data.action = None
        last = round(seconds*24)+1
        previous_rotations = {}
        for frame in range(1,last+1):
            reset()
            pose((frame-1)/(last-1))
            for pb in rig.pose.bones:
                # q and -q describe the same pose; keep successive keys in
                # the same hemisphere so every pose transition interpolates smoothly.
                rotation = pb.rotation_quaternion.copy()
                if pb.name in previous_rotations and rotation.dot(previous_rotations[pb.name]) < 0:
                    rotation.negate()
                pb.rotation_quaternion = rotation
                previous_rotations[pb.name] = rotation.copy()
                pb.keyframe_insert('rotation_quaternion',frame=frame,group=pb.name)
                pb.keyframe_insert('location',frame=frame,group=pb.name)
                pb.keyframe_insert('scale',frame=frame,group=pb.name)
        action = rig.animation_data.action
        rig.animation_data.action = None
        attach(action,name,loop)
    def run(t):
        s,c = math.sin(math.tau*t),math.cos(math.tau*t)
        for sign, side in ((1,'L'),(-1,'R')):
            phase = s*sign
            rotate('thigh.'+side,-.55*phase)
            rotate('shin.'+side,.70*max(0,-phase))
            rotate('foot.'+side,-.15*phase)
            rotate('upper_arm.'+side,.45*phase)
            rotate('forearm.'+side,-.30)
        rotate('chest',.10,0,.02*c)
        rotate('head',-.05)
        offset('root',(0,0,.025*(1-math.cos(math.tau*t*2))))
    def smooth(value):
        value = max(0.0, min(1.0, value))
        return value*value*(3.0-2.0*value)
    def curve(t, keys):
        for (a, left), (b, right) in zip(keys, keys[1:]):
            if t <= b:
                return left+(right-left)*smooth((t-a)/(b-a))
        return keys[-1][1]
    def ground_feet():
        bpy.context.view_layer.update()
        depsgraph = bpy.context.evaluated_depsgraph_get()
        bottom = min((evaluated.matrix_world @ vertex.co).z
            for obj in meshes if obj.name.startswith('Boot')
            for evaluated in [obj.evaluated_get(depsgraph)]
            for vertex in evaluated.data.vertices)
        offset('root', (0, 0, -bottom/scale))
    def air_pose(t, moving=False, descending=False):
        # Start in extension at the impulse, reach a relaxed asymmetric apex,
        # then unfold for contact. Moving jumps use a clear running split.
        gather = smooth(t) if not descending else 1-smooth(t)
        if moving:
            thighs = (-.75*gather-.06, .26*gather+.04)
            knees = (.85*gather+.10, .90*gather+.10)
            arms = (.28*gather+.08, -.48*gather-.10)
            lean = .12+.07*gather
        else:
            thighs = (-.62*gather-.015, -.42*gather-.015)
            knees = (1.12*gather+.03, .85*gather+.03)
            arms = (-.55*gather+.10*(1-gather), -.40*gather+.08*(1-gather))
            lean = -.04*(1-gather)+.07*gather
        for index, side in enumerate(('L','R')):
            rotate('thigh.'+side, thighs[index])
            rotate('shin.'+side, knees[index])
            # Soften ankles in flight, approach a flat foot before contact.
            rotate('foot.'+side, -(thighs[index]+knees[index])*(.75+.25*(1-gather)))
            rotate('upper_arm.'+side, arms[index], 0, (.045 if index == 0 else -.035)*gather)
            rotate('forearm.'+side, -.10-(.16 if index == 0 else .12)*gather)
        rotate('chest', lean)
        rotate('head', -lean*.55)
    def land(t):
        # Brief planted recovery is used only when stationary. Locomotion
        # instead keeps its legs running and receives upper-body recoil.
        compression = curve(t, [(0,.025), (.24,.24), (.65,.075), (1,0)])
        for side in ('L','R'):
            rotate('thigh.'+side, -compression)
            rotate('shin.'+side, compression*2)
            rotate('foot.'+side, -compression)
            rotate('upper_arm.'+side, -compression*.50)
            rotate('forearm.'+side, -compression*.45)
        rotate('chest', compression*.45)
        rotate('head', -compression*.22)
        ground_feet()
    def recoil(t):
        # Additive, upper-body-only impulse: no pelvis/root/leg keys may
        # displace the active stride when a running jump touches down.
        amount = curve(t, [(0,0), (.24,1), (.65,.25), (1,0)])
        rotate('chest', .16*amount)
        rotate('head', -.09*amount)
        for side in ('L','R'):
            rotate('upper_arm.'+side, -.10*amount)
            rotate('forearm.'+side, -.08*amount)
    make('freehand_run',.75,run,True)
    make('jump_start',.30,lambda t:air_pose(t))
    make('jump_move',.30,lambda t:air_pose(t,moving=True))
    make('freehand_fall',.25,lambda t:air_pose(t,descending=True))
    make('fall_move',.25,lambda t:air_pose(t,moving=True,descending=True))
    make('landing_soft',.20,land)
    make('landing_recoil',.20,recoil)
    make('pose_lean_left',.125,lambda t:rotate('chest',0,0,-.12))
    make('pose_lean_right',.125,lambda t:rotate('chest',0,0,.12))
    reset()
    rig.animation_data.action = None
    studio.frame_set(1)
    bpy.context.view_layer.update()
    OUTPUT.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    for o in studio.objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'runtime.blend'))
    bpy.ops.export_scene.gltf(filepath=str(OUTPUT),export_format='GLB',use_selection=True,use_active_scene=True,
        export_animations=True,export_animation_mode='NLA_TRACKS',export_yup=True,export_skins=True,export_morph=False)
    triangles = sum(len(p.vertices)-2 for o in meshes for p in o.data.polygons)
    # Reimport the exported package in an isolated scene, validating the actual
    # bind transforms rather than trusting the authoring scene's dimensions.
    verification = bpy.data.scenes.new('ForestGirl_Export_Verification')
    bpy.context.window.scene = verification
    bpy.ops.import_scene.gltf(filepath=str(OUTPUT))
    exported_rig = next(o for o in verification.objects if o.type == 'ARMATURE')
    for track in exported_rig.animation_data.nla_tracks:
        track.mute = True
    exported_rig.animation_data.action = None
    for pb in exported_rig.pose.bones:
        pb.matrix_basis.identity()
    bpy.context.view_layer.update()
    shapes = {pb.custom_shape for pb in exported_rig.pose.bones if pb.custom_shape}
    exported_meshes = [o for o in verification.objects if o.type == 'MESH' and o not in shapes]
    bounds = [o.matrix_world @ Vector(c) for o in exported_meshes for c in o.bound_box]
    minimum, maximum = min(p.z for p in bounds), max(p.z for p in bounds)
    assert abs(minimum) < .00001 and abs(maximum-minimum-1.20) < .00001
    assert len(exported_meshes) == len(meshes)
    assert [pb.name for pb in exported_rig.pose.bones] == [pb.name for pb in rig.pose.bones]
    validated = []
    for track in exported_rig.animation_data.nla_tracks:
        action = track.strips[0].action
        exported_rig.animation_data.action = action
        for fraction in (0, .25, .5, .75, 1):
            start, end = action.frame_range
            verification.frame_set(round(start+fraction*(end-start)))
            bpy.context.view_layer.update()
            assert all(math.isfinite(value) for pb in exported_rig.pose.bones for row in pb.matrix for value in row)
        validated.append(track.name)
    assert sorted(validated) == sorted(clip['name'] for clip in clips)
    landing_track = next(track for track in exported_rig.animation_data.nla_tracks if track.name == 'landing_soft')
    exported_rig.animation_data.action = landing_track.strips[0].action
    landing_floors = []
    # Also check between baked keys to catch interpolation dipping below ground.
    for step in range(33):
        start, end = landing_track.strips[0].action.frame_range
        frame = start+(end-start)*step/32
        verification.frame_set(int(frame), subframe=frame-int(frame))
        bpy.context.view_layer.update()
        depsgraph = bpy.context.evaluated_depsgraph_get()
        landing_floors.append(min((evaluated.matrix_world @ vertex.co).z
            for obj in exported_meshes if obj.name.startswith('Boot')
            for evaluated in [obj.evaluated_get(depsgraph)]
            for vertex in evaluated.data.vertices))
    assert min(landing_floors) > -.005 and max(landing_floors) < .005
    bpy.context.window.scene = studio
    report = {'source':'Source/forest_girl.glb','profile_refinement':profile_report,'meshes':len(meshes),'triangles':triangles,
        'materials':len({m.name for o in meshes for m in o.data.materials if m}),
        'bones':[b.name for b in rig.data.bones], 'source_height':high-low,'source_floor':low,
        'uniform_scale':scale,'height':1.20,'floor':0.0,'front':'Blender -Y / Godot +Z',
        'clips':clips,'export_reimport_validation':{'height':maximum-minimum,'floor':minimum,'sampled_clips':validated,'landing_floor_min':min(landing_floors),'landing_floor_max':max(landing_floors)},'jump_note':'Separate standing/running arcs; stationary soft contact or additive upper-body recoil over live locomotion; no rolling.'}
    (HERE/'runtime_manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print('FOREST_RUNTIME_OK',json.dumps(report))

if __name__ == '__main__':
    main()

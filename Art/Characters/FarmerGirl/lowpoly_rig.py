"""Compact authoring rig and deterministic 30 FPS farm actions.

Coordinates are Blender metres (front -Y). Geometry may supply a JSON
``scene['rig_points']`` dictionary overriding joint positions below.
"""
import json
import math
import bpy
from mathutils import Matrix, Vector

DEFAULT_POINTS = {
    'pelvis': (0, 0, .43), 'spine_01': (0, 0, .51),
    'spine_02': (0, 0, .65), 'neck': (0, 0, .745),
    'head': (0, 0, .94), 'head_top': (0, 0, 1.12),
}
for side, sign in [('L', 1), ('R', -1)]:
    DEFAULT_POINTS.update({
        'shoulder_'+side: (sign*.14, 0, .67),
        'elbow_'+side: (sign*.25, 0, .57),
        'wrist_'+side: (sign*.33, 0, .48),
        'hand_'+side: (sign*.35, 0, .46),
        'hip_'+side: (sign*.075, 0, .42),
        'knee_'+side: (sign*.075, 0, .27),
        'ankle_'+side: (sign*.075, 0, .105),
        'foot_'+side: (sign*.075, -.075, .065),
        'toe_'+side: (sign*.075, -.105, .055),
    })


def build_rig(scene, collection, objects):
    points = dict(DEFAULT_POINTS)
    raw = scene.get('rig_points')
    if raw:
        points.update(json.loads(raw) if isinstance(raw, str) else dict(raw))
    arm = bpy.data.armatures.new('RIG_Character')
    rig = bpy.data.objects.new('RIG_Character', arm)
    collection.objects.link(rig)
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='EDIT')
    def bone(name, head, tail, parent=None, deform=True):
        item = arm.edit_bones.new(name)
        item.head, item.tail, item.use_deform = head, tail, deform
        if parent:
            item.parent = arm.edit_bones[parent]
        return item
    bone('root', (0,0,0), (0,0,.10))
    chain = ['pelvis', 'spine_01', 'spine_02', 'neck', 'head']
    for i, name in enumerate(chain):
        tail = points[chain[i+1]] if i+1 < len(chain) else points['head_top']
        bone(name, points[name], tail, chain[i-1] if i else 'root')
    for side in ('L', 'R'):
        bone('upperarm_'+side, points['shoulder_'+side], points['elbow_'+side], 'spine_02')
        bone('forearm_'+side, points['elbow_'+side], points['wrist_'+side], 'upperarm_'+side)
        bone('hand_'+side, points['wrist_'+side], points['hand_'+side], 'forearm_'+side)
        bone('thigh_'+side, points['hip_'+side], points['knee_'+side], 'pelvis')
        bone('shin_'+side, points['knee_'+side], points['ankle_'+side], 'thigh_'+side)
        bone('foot_'+side, points['ankle_'+side], points['foot_'+side], 'shin_'+side)
        bone('toe_'+side, points['foot_'+side], points['toe_'+side], 'foot_'+side)
        for part, joint in [('Hand','wrist'), ('Foot','ankle')]:
            point = Vector(points[joint+'_'+side])
            bone('IK_'+part+'_'+side, point, point+Vector((0,0,.055)), 'root', False)
    hand = Vector(points['hand_R'])
    bone('socket_hand_R', hand, hand+Vector((0,-.06,0)), 'hand_R')
    bone('socket_back', (0,.075,.61), (0,.135,.61), 'spine_02')
    bone('socket_head', (0,0,1.10), (0,0,1.16), 'head')
    bpy.ops.object.mode_set(mode='OBJECT')
    rig.show_in_front = True
    arm.display_type = 'STICK'
    rig['IK_instructions'] = 'Set named IK constraint influence to 1 for authoring; exported clips use FK.'
    for side in ('L', 'R'):
        for part, name in [('Hand','forearm_'), ('Foot','shin_')]:
            constraint = rig.pose.bones[name+side].constraints.new('IK')
            constraint.name = 'Authoring_IK_'+part+'_'+side
            constraint.target, constraint.subtarget = rig, 'IK_'+part+'_'+side
            constraint.chain_count = 2
            constraint.use_stretch = False
            constraint.influence = 0
    for obj in objects:
        if obj.type != 'MESH':
            continue
        # Geometry can provide precise weights. Otherwise bind rigid accessories,
        # blend long limb pieces across the elbow/knee, and blend torso rings.
        has_weights = any(v.groups for v in obj.data.vertices)
        if not has_weights:
            bind = str(obj.get('bind_bone', 'pelvis'))
            if bind not in arm.bones:
                raise ValueError('Unknown bind bone for '+obj.name+': '+bind)
            groups = {}
            def put(index, weights):
                for name, value in weights.items():
                    if value > .00001:
                        group = groups.get(name) or obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name)
                        groups[name] = group
                        group.add([index], value, 'REPLACE')
            for vertex in obj.data.vertices:
                position = obj.matrix_world @ vertex.co
                weights = {bind: 1.0}
                side = bind[-1:]
                if side in ('L','R') and bind.startswith(('upperarm_', 'forearm_', 'thigh_', 'shin_')):
                    arm_limb = bind.startswith(('upperarm_', 'forearm_'))
                    upper, lower = ('upperarm_', 'forearm_') if arm_limb else ('thigh_', 'shin_')
                    joint = Vector(points[('elbow_' if arm_limb else 'knee_')+side])
                    # 5 cm transition prevents a rigid hinge seam at the joint.
                    t = max(0., min(1., .5+(joint.z-position.z)/.05))
                    weights = {upper+side: 1-t, lower+side: t}
                elif obj.name.startswith('CHR_Clothes_Dress'):
                    # The bodice follows the chest; the bell hem follows each
                    # thigh enough to clear bent knees without rigid skirt clipping.
                    if position.z >= .49:
                        t = max(0., min(1., (position.z-.49)/.17))
                        weights = {'pelvis': 1-t, 'spine_02': t}
                    else:
                        t = .85*max(0., min(1., (.49-position.z)/.145))
                        left = max(0., min(1., .5+position.x/.10))
                        weights = {'pelvis': 1-t, 'thigh_L': t*left, 'thigh_R': t*(1-left)}
                elif bind in ('pelvis', 'spine_01', 'spine_02') and obj.get('blend_torso', False):
                    t = max(0., min(1., (position.z-.50)/.14))
                    weights = {'pelvis': 1-t, 'spine_02': t}
                put(vertex.index, weights)
        obj.parent = rig
        modifier = obj.modifiers.new('CharacterSkin', 'ARMATURE')
        modifier.object = rig
        modifier.use_deform_preserve_volume = True
        for vertex in obj.data.vertices:
            if len(vertex.groups) > 4:
                raise ValueError('More than four skin influences: '+obj.name)
    rig.select_set(False)
    scene.render.fps = 30
    rig['joint_positions'] = json.dumps(points)
    return rig


def add_animations(rig):
    """Create farm clips and compatible state-machine names, all in place."""
    scene = bpy.context.scene
    scene.render.fps = 30
    manifest = []
    built_actions = {}
    def reset():
        for pb in rig.pose.bones:
            for constraint in pb.constraints:
                if constraint.type == 'IK':
                    constraint.influence = 0
        for pb in rig.pose.bones:
            pb.rotation_mode = 'XYZ'
            pb.rotation_euler = (0,0,0)
            pb.location = (0,0,0)
            pb.scale = (1,1,1)
    def rotate(name, x=0, y=0, z=0):
        basis = rig.data.bones[name].matrix_local.to_3x3()
        world = (Matrix.Rotation(z,3,'Z') @ Matrix.Rotation(y,3,'Y') @ Matrix.Rotation(x,3,'X'))
        rig.pose.bones[name].rotation_euler = (basis.inverted() @ world @ basis).to_euler('XYZ')
    def offset(name, position):
        basis = rig.data.bones[name].matrix_local.to_3x3()
        rig.pose.bones[name].location = basis.inverted() @ Vector(position)
    def hand_target(side, target):
        control = rig.pose.bones['IK_Hand_'+side]
        bpy.context.view_layer.update()
        matrix = control.matrix.copy()
        matrix.translation = Vector(target)
        control.matrix = matrix
        rig.pose.bones['forearm_'+side].constraints['Authoring_IK_Hand_'+side].influence = 1
    def bake_ik():
        bpy.context.view_layer.update()
        solved = {}
        for side in ('L', 'R'):
            constraint = rig.pose.bones['forearm_'+side].constraints['Authoring_IK_Hand_'+side]
            if constraint.influence > 0:
                for name in ('upperarm_'+side, 'forearm_'+side):
                    pb = rig.pose.bones[name]
                    solved[name] = pb.bone.convert_local_to_pose(
                        pb.matrix.copy(), pb.bone.matrix_local,
                        parent_matrix=pb.parent.matrix.copy(),
                        parent_matrix_local=pb.parent.bone.matrix_local, invert=True)
                constraint.influence = 0
        for name, matrix in solved.items():
            rig.pose.bones[name].matrix_basis = matrix
        bpy.context.view_layer.update()
    def make(name, duration, pose, loop=False):
        rig.animation_data_create()
        rig.animation_data.action = None
        last = duration+1
        frames = sorted(set(list(range(1,last+1,3))+[last]))
        for frame in frames:
            reset()
            pose((frame-1)/duration)
            bake_ik()
            for pb in rig.pose.bones:
                if pb.name.startswith('IK_'):
                    continue
                pb.keyframe_insert('rotation_euler', frame=frame, group=pb.name)
                pb.keyframe_insert('location', frame=frame, group=pb.name)
        action = rig.animation_data.action
        action.name, action.use_fake_user = name, True
        action['loop'] = loop
        built_actions[name] = action
        track = rig.animation_data.nla_tracks.new()
        track.name = name
        strip = track.strips.new(name, 1, action)
        strip.name = name
        track.mute = True
        rig.animation_data.action = None
        manifest.append({'name':name, 'frames':last, 'fps':30, 'loop':loop})
    def idle(t):
        s = math.sin(math.tau*t)
        rotate('spine_02', .014*s)
        rotate('head', -.01*s, 0, .012*s)
        offset('pelvis', (0,0,.002*s))
    def gait(t, run=False):
        s, c = math.sin(math.tau*t), math.cos(math.tau*t)
        for sign, side in [(1,'L'),(-1,'R')]:
            phase = s*sign
            rotate('thigh_'+side, -(.65 if run else .37)*phase)
            rotate('shin_'+side, (.80 if run else .42)*max(0,-phase))
            rotate('foot_'+side, -.14*phase)
            rotate('upperarm_'+side, (.55 if run else .28)*phase)
            rotate('forearm_'+side, .45 if run else .16)
        rotate('spine_02', .12 if run else .025, 0, .025*c)
        rotate('head', -.06 if run else -.02)
        offset('root', (0,0,(.012 if run else .005)*(1-math.cos(math.tau*t*2))))
    def squat(amount=1):
        rotate('spine_01', 1.1*amount)
        rotate('spine_02', -.2*amount)
        for side in ('L','R'):
            rotate('thigh_'+side, -1.2*amount)
            rotate('shin_'+side, 2.35*amount)
            rotate('foot_'+side, -1.15*amount)
        # Ground the sole after flexing both leg chains; avoid a floating squat.
        bpy.context.view_layer.update()
        bottoms = []
        for side, sign in [('L',1),('R',-1)]:
            pb = rig.pose.bones['foot_'+side]
            deform = pb.matrix @ pb.bone.matrix_local.inverted()
            for y in (-.12,.07):
                bottoms.append((deform @ Vector((sign*.075,y,0))).z)
        offset('root', (0,0,-min(bottoms)))
        bpy.context.view_layer.update()
    def pickup(t):
        s = math.sin(math.pi*t)**2
        squat(s)
        hand_target('R', (-.11, -.22*s, .46-.32*s))
        rotate('head', -.22*s)
    def carry(t):
        hand_target('R', (-.10,-.18,.54))
        hand_target('L', (.10,-.18,.54))
        rotate('spine_02', -.025+.008*math.sin(math.tau*t))
    def watering(t):
        s = math.sin(math.pi*t)**2
        hand_target('R', (-.13,-.21,.56))
        rotate('hand_R', -.25-.50*s)
        rotate('head', .13)
        rotate('spine_02', .07)
    def hoe(t):
        s = .5-.5*math.cos(math.tau*t)
        rotate('spine_02', .08+.18*s)
        hand_target('R', (-.10,-.10-.08*s,.78-.23*s))
        hand_target('L', (.05,-.14-.06*s,.68-.17*s))
        rotate('head', .12)
    def plant(t):
        squat(1)
        hand_target('R', (-.10,-.24,.13+.018*math.sin(math.tau*t)))
        hand_target('L', (.10,-.16,.33))
        rotate('head', -.2)
    def wave(t):
        f = math.sin(math.pi*t)**.35
        rotate('upperarm_R', 0, 1.8*f, 0)
        rotate('forearm_R', .3*math.sin(math.tau*t*3)*f, 0, 0)
        rotate('head', 0, 0, -.045*f)
    required = [('Idle',90,idle,True), ('Walk',30,gait,True),
                ('Run',21,lambda t:gait(t,True),True), ('Pickup',60,pickup,False),
                ('Carry',60,carry,False), ('Watering',60,watering,True),
                ('Hoe',60,hoe,True), ('Plant',60,plant,False), ('Wave',60,wave,False)]
    for spec in required:
        make(*spec)
    aliases = {'Idle':'freehand_idle', 'Walk':'freehand_walk', 'Run':'freehand_run',
               'Carry':'carry_harvest', 'Watering':'watering', 'Wave':'wave'}
    for source, name in aliases.items():
        action = built_actions[source].copy()
        action.name, action.use_fake_user = name, True
        track = rig.animation_data.nla_tracks.new()
        track.name = name
        strip = track.strips.new(name,1,action)
        strip.name, track.mute = name, True
        entry = dict(next(row for row in manifest if row['name']==source))
        entry['name'] = name
        if source == 'Carry':
            entry['loop'] = True
            action['loop'] = True
        manifest.append(entry)
    def fall(t):
        for sign, side in [(1,'L'),(-1,'R')]:
            rotate('upperarm_'+side, .15, 0, sign*.35)
            rotate('forearm_'+side, .2)
        rotate('thigh_L', .12)
        rotate('thigh_R', -.10)
    make('freehand_fall',30,fall,True)
    make('jump_start',15,lambda t:squat(.55*math.sin(math.pi*t)))
    make('landing_soft',12,lambda t:squat(.65*(1-t)**2))
    def roll(t):
        f = math.sin(math.pi*t)
        squat(.7*f)
        rotate('spine_02', .50*f)
        angle = -math.tau*t
        rotate('root', angle)
        pivot = Vector((0,0,.56))
        correction = pivot-Matrix.Rotation(angle,3,'X') @ pivot
        correction.z += .02*f
        offset('root', correction)
    make('landing_roll',45,roll)
    make('pose_lean_left',3,lambda t:rotate('spine_02',0,0,-.12))
    make('pose_lean_right',3,lambda t:rotate('spine_02',0,0,.12))
    def thinking(t):
        rotate('upperarm_R', -.7, 0, -.15)
        rotate('forearm_R', -1.32)
        rotate('head', .07,0,-.06)
    make('thinking',60,thinking,True)
    def arms_up(t):
        for sign, side in [(1,'L'),(-1,'R')]:
            rotate('upperarm_'+side,0,-sign*2.0,0)
    # Acceptance poses are separately named so they are inspectable in Blender
    # and in the game review without repurposing gameplay clips.
    make('QA_Squat',3,lambda t:squat(.8))
    make('QA_ArmsUp',3,arms_up)
    make('QA_HoldItem',3,carry)
    def tpose(t):
        for sign, side in [(1,'L'),(-1,'R')]:
            rotate('upperarm_'+side,0,-sign*.74,0)
    make('QA_TPose',3,tpose)
    reset()
    scene.frame_set(1)
    return manifest

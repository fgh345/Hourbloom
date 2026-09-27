"""Build a reusable low-poly hoe and an isolated ForestGirl hoeing preview.

Run: blender --background --factory-startup --python Art/Tools/Hoe/build_hoe_preview.py
Character runtime is loaded as data; supplied attachment scripts are not executed.
Coordinates are Blender metres, Z-up, character facing -Y. No gameplay assets are changed.
"""
from pathlib import Path
import json
import math
import sys
import bpy
import bmesh
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = ROOT / 'Assets/Tools/Hoe'
FPS = 240
AUTHOR_DURATION = 1.15
AUTHOR_IMPACT = .85
DURATION = .6
TIME_SCALE = DURATION / AUTHOR_DURATION
IMPACT = AUTHOR_IMPACT * TIME_SCALE
GRIPS = {'R': .745, 'L': .62}
CUTTING_EDGE = Vector((0, .142, -.078))
SOCKET_CENTER = Vector((0, 0, .025))


def material(name, color, roughness=.8, metallic=0):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Metallic'].default_value = metallic
    return m


def mesh(name, vertices, faces, mat):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    ob = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(ob)
    ob.data.materials.append(mat)
    return ob


def cylinder(name, radius, depth, z, mat, sides=10):
    bpy.ops.mesh.primitive_cylinder_add(vertices=sides, radius=radius, depth=depth, location=(0,0,z))
    ob = bpy.context.object
    ob.name = name
    ob.data.materials.append(mat)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return ob


def bevel_box(name, center, size, mat, bevel=.004):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    ob = bpy.context.object
    ob.name = name
    ob.scale = size
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    ob.data.materials.append(mat)
    mod = ob.modifiers.new('Soft handmade edges', 'BEVEL')
    mod.width = bevel
    mod.segments = 1
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return ob


def tube(name, points, radius, mat, sides=6):
    verts, faces = [], []
    for index, p in enumerate(points):
        p = Vector(p)
        tangent = Vector(points[min(index+1,len(points)-1)]) - Vector(points[max(index-1,0)])
        tangent.normalize()
        normal = tangent.cross(Vector((0,0,1))).normalized()
        if normal.length < .01:
            normal = tangent.cross(Vector((0,1,0))).normalized()
        other = tangent.cross(normal).normalized()
        for i in range(sides):
            angle = math.tau*i/sides
            verts.append(tuple(p+radius*(math.cos(angle)*normal+math.sin(angle)*other)))
    for j in range(len(points)-1):
        for i in range(sides):
            a=j*sides+i; b=j*sides+(i+1)%sides
            faces.append((a,b,b+sides,a+sides))
    faces += [tuple(reversed(range(sides))), tuple((len(points)-1)*sides+i for i in range(sides))]
    return mesh(name,verts,faces,mat)


def tool_geometry():
    wood = material('Hoe • warm chestnut wood',(.39,.205,.095))
    wood_light = material('Hoe • wood facet highlight',(.53,.30,.145))
    wood_dark = material('Hoe • wood facet shadow',(.27,.125,.055))
    steel = material('Hoe • brushed blue-gray iron',(.29,.365,.395),.62,.55)
    edge = material('Hoe • worn cutting edge',(.50,.57,.585),.47,.65)
    collar = material('Hoe • dark iron socket',(.17,.205,.22),.66,.5)
    cloth = material('Hoe • flax grip wrap',(.78,.685,.50))
    cloth_light = material('Hoe • wrap raised seams',(.91,.81,.63))
    objects = []
    shaft = cylinder('Hoe_WoodHandle',.015,.755,.3825,wood)
    shaft.data.materials.append(wood_light); shaft.data.materials.append(wood_dark)
    for p in shaft.data.polygons:
        p.material_index = (1 if p.index%5==0 else 2 if p.index%5==3 else 0)
    objects.append(shaft)
    objects.append(cylinder('Hoe_HandleButt',.018,.026,.754,wood_light))
    objects.append(cylinder('Hoe_IronSocket',.023,.081,.025,collar))
    # Slightly tapered, curved-down blade with a broad readable edge.
    # x = blade width; +y points toward the worker; z is handle axis.
    # The blade bends toward the worker and down, so its sharpened lip cuts soil.
    verts = [(-.058,.008,.024),(.058,.008,.024),
             (-.096,.142,-.070),(.096,.142,-.070),
             (-.058,.008,.010),(.058,.008,.010),
             (-.096,.142,-.078),(.096,.142,-.078)]
    blade = mesh('Hoe_ForgedBlade',verts,[(0,1,3,2),(4,6,7,5),(0,4,5,1),(0,2,6,4),(1,5,7,3),(2,3,7,6)],steel)
    objects.append(blade)
    objects.append(mesh('Hoe_SharpenedEdge',
        [(-.096,.142,-.070),(.096,.142,-.070),(-.093,.126,-.059),(.093,.126,-.059),
         (-.096,.142,-.078),(.096,.142,-.078)],[(0,1,3,2),(0,4,5,1)],edge))
    # Complete the 180-degree rotation about the shaft on the symmetric head.
    # Mirroring Y alone would reverse the iron's surface winding.
    for ob in (blade, objects[-1]):
        for vertex in ob.data.vertices:
            vertex.co.x *= -1
    # The inherited closed blade face list was inside-out on the top face.
    # Orient the closed volume outwards; the open sharpened strip already
    # has an upward top face and outward front face after the shaft rotation.
    bm=bmesh.new(); bm.from_mesh(blade.data)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(blade.data); bm.free(); blade.data.update()
    # Two short wraps leave the shaft visible between the grip positions.
    for side,z in GRIPS.items():
        objects.append(cylinder('Hoe_ClothGrip_'+side,.0172,.053,z,cloth,12))
        for j in range(5):
            objects.append(cylinder('Hoe_WrapSeam_'+side+'_'+str(j),.0178,.003,z-.021+j*.0105,cloth_light,12))
    objects.append(cylinder('Hoe_SocketPin',.009,.004,.052,edge,8))
    return objects


def pose_rotation(rig, name, x=0, y=0, z=0):
    basis = rig.data.bones[name].matrix_local.to_3x3()
    rotation = Matrix.Rotation(z,3,'Z') @ Matrix.Rotation(y,3,'Y') @ Matrix.Rotation(x,3,'X')
    rig.pose.bones[name].rotation_quaternion = (basis.inverted() @ rotation @ basis).to_quaternion()


def smooth(t):
    t=max(0,min(1,t))
    return t*t*(3-2*t)


def curve(t, keys):
    for (a,x),(b,y) in zip(keys,keys[1:]):
        if t<=b:
            return x+(y-x)*smooth((t-a)/(b-a))
    return keys[-1][1]


def tool_matrix(t, idle=False):
    if idle:
        angle=1.0
        yaw=0
        grip=Vector((.015,-.075,.63+.002*math.sin(math.tau*t)))
    else:
        # Evaluate unchanged author poses on the compressed playback timeline.
        t /= TIME_SCALE
        # Keep the reference anticipation and strike, then briefly settle at contact.
        # Recover with a small extraction directly into the low ready hold.
        angle=curve(t,[(0,1.4),(.12,1.4),(.32,2.3),(.50,2.65),(.57,2.65),(.85,1.1),(.90,1.1),(1.02,1.25),(1.15,1.4)])
        yaw=curve(t,[(0,0),(.12,0),(.50,.35),(.57,.35),(.85,0),(.90,0),(1.15,0)])
        grip=Vector((curve(t,[(0,.015),(.12,.015),(.50,.035),(.57,.035),(.85,.015),(.90,.015),(1.15,.015)]),
            curve(t,[(0,-.15),(.12,-.15),(.32,-.12),(.50,-.04),(.57,-.04),(.73,-.17),(.85,-.20),(.90,-.20),(1.02,-.175),(1.15,-.15)]),
            curve(t,[(0,.51),(.12,.51),(.32,.63),(.50,.735),(.57,.735),(.73,.60),(.85,.50),(.90,.50),(1.02,.51),(1.15,.51)])))
    direction=Vector((math.sin(angle)*math.sin(yaw),math.sin(angle)*math.cos(yaw),math.cos(angle)))
    xaxis=(Vector((1,0,0))-direction*direction.x).normalized()
    yaxis=direction.cross(xaxis)
    rotation=Matrix((xaxis,yaxis,direction)).transposed()
    head=grip-direction*GRIPS['R']
    # Contact is derived from actual sharp-edge vertices, not a hand-tuned marker.
    local_low=min((rotation@p).z for p in TOOL_VERTS)
    head.z=max(head.z,-local_low)
    if not idle and abs(t-AUTHOR_IMPACT)<1e-7:
        head.z=-local_low
    return Matrix.LocRotScale(head,rotation.to_quaternion(),Vector((1,1,1)))


def skin_mesh(ob, rig, bone, coords_in_world=False):
    transform=rig.matrix_world.inverted() if coords_in_world else Matrix.Identity(4)
    for v in ob.data.vertices:
        v.co=transform @ v.co
    ob.parent=rig
    ob.matrix_parent_inverse=Matrix.Identity(4)
    ob.matrix_basis=Matrix.Identity(4)
    group=ob.vertex_groups.new(name=bone)
    group.add(list(range(len(ob.data.vertices))),1,'REPLACE')
    mod=ob.modifiers.new('Rigid prop attachment','ARMATURE'); mod.object=rig


def grip_hands(rig, skin):
    result=[]
    scale=rig.matrix_world.to_scale().x
    for side in ('L','R'):
        sign=-1 if side=='L' else 1
        wrist=Vector((sign*.041,0,GRIPS[side]+.006))
        parts=[]
        parts.append(bevel_box('GripHand_'+side+'_Palm',(sign*.031,.002,GRIPS[side]),(.027,.035,.050),skin,.005))
        # Four bent finger arcs, each wrapped around the shaft with visible knuckle facets.
        for j in range(4):
            z=GRIPS[side]-.016+j*.0107
            points=[]
            for angle in (0,-.50,-1.05,-1.65,-2.15,-2.55):
                points.append((sign*.024*math.cos(angle),.024*math.sin(angle),z))
            parts.append(tube('GripHand_'+side+'_Finger_'+str(j),points,.0062,skin,6))
        parts.append(tube('GripHand_'+side+'_Thumb',
            [(sign*.031,.019,GRIPS[side]+.018),(sign*.018,.022,GRIPS[side]+.026),
             (sign*.001,.018,GRIPS[side]+.026),(-sign*.010,.007,GRIPS[side]+.020)],.008,skin,6))
        bone=rig.data.bones['hand.'+side]
        for ob in parts:
            # Created in the tool coordinate frame. Rebind around this hand's
            # wrist in its original rest basis; the pose maps it back onto shaft.
            for v in ob.data.vertices:
                v.co=bone.matrix_local @ ((v.co-wrist)/scale)
            skin_mesh(ob,rig,'hand.'+side)
        result+=parts
    return result


def solve_arm(rig, side, transform):
    sign=-1 if side=='L' else 1
    wrist_local=Vector((sign*.041,0,GRIPS[side]+.006))
    wrist=transform@wrist_local
    upper=rig.pose.bones['upper_arm.'+side]
    lower=rig.pose.bones['forearm.'+side]
    hand=rig.pose.bones['hand.'+side]
    bpy.context.view_layer.update()
    shoulder=rig.matrix_world@upper.head
    l1=rig.data.bones[upper.name].length*rig.matrix_world.to_scale().x
    l2=rig.data.bones[lower.name].length*rig.matrix_world.to_scale().x
    ray=wrist-shoulder
    distance=ray.length
    REACH_ERRORS.append(max(0,distance-(l1+l2)))
    if distance<=abs(l1-l2)+.00001:
        raise AssertionError(f'Over-folded {side} grip: {distance:.5f} < {abs(l1-l2):.5f}, wrist {tuple(wrist)}, shoulder {tuple(shoulder)}')
    if distance>=l1+l2-.00001:
        raise AssertionError(f'Unreachable {side} grip: {distance:.5f} > {l1+l2:.5f}, wrist {tuple(wrist)}, shoulder {tuple(shoulder)}')
    direction=ray.normalized()
    outward=Vector((sign, .18, -.10))
    normal=(outward-direction*outward.dot(direction)).normalized()
    along=(l1*l1-l2*l2+distance*distance)/(2*distance)
    height=math.sqrt(max(0,l1*l1-along*along))
    elbow=shoulder+direction*along+normal*height
    inv=rig.matrix_world.inverted()
    for pb,start,end in ((upper,shoulder,elbow),(lower,elbow,wrist)):
        rest=rig.data.bones[pb.name]
        desired=(inv@end-inv@start).normalized()
        restdir=(rest.tail_local-rest.head_local).normalized()
        rotation=restdir.rotation_difference(desired).to_matrix()@rest.matrix_local.to_3x3()
        if pb == lower:
            # Preserve palm-facing roll through the return. The grip's X
            # axis becomes almost parallel to the forearm at the strike, so
            # it cannot define stable pronation. Its Y axis stays transverse
            # throughout both clips. Align the forearm ring's binormal to that
            # palm reference, leaving the wrist only its required bend.
            grip_rotation=inv.to_3x3() @ transform.to_3x3()
            palm=(grip_rotation @ Vector((0,1,0))).normalized()
            radial=palm.cross(desired)
            if radial.length<.25:
                raise AssertionError(f'Degenerate {side} palm roll reference')
            radial.normalize()
            rest_radial=restdir.cross(Vector((0,1,0))).normalized()
            rest_frame=Matrix((rest_radial,restdir.cross(rest_radial),restdir)).transposed()
            frame=Matrix((radial,desired.cross(radial),desired)).transposed()
            rotation=frame @ rest_frame.transposed() @ rest.matrix_local.to_3x3()
        pb.matrix=Matrix.LocRotScale(inv@start,rotation.to_quaternion(),Vector((1,1,1)))
        bpy.context.view_layer.update()
    rotation=rig.matrix_world.to_quaternion().inverted()@transform.to_quaternion()
    hand.matrix=Matrix.LocRotScale(inv@wrist,rotation,Vector((1,1,1)))
    bpy.context.view_layer.update()
    GRIP_ERRORS.append((rig.matrix_world@hand.head-wrist).length)
    JOINT_ERRORS.append((rig.matrix_world@lower.tail-wrist).length)


def solve_leg(rig, side, target):
    upper=rig.pose.bones['thigh.'+side];lower=rig.pose.bones['shin.'+side]
    foot=rig.pose.bones['foot.'+side]
    bpy.context.view_layer.update()
    hip=rig.matrix_world@upper.head
    scale=rig.matrix_world.to_scale().x
    l1=upper.bone.length*scale;l2=lower.bone.length*scale
    ray=target-hip;distance=ray.length
    if distance>=l1+l2-.00001:
        raise AssertionError(f'Unreachable planted foot {side}: {distance:.5f} > {l1+l2:.5f}')
    direction=ray.normalized();pole=Vector((0,-1,0))
    normal=(pole-direction*pole.dot(direction)).normalized()
    along=(l1*l1-l2*l2+distance*distance)/(2*distance)
    knee=hip+direction*along+normal*math.sqrt(max(0,l1*l1-along*along))
    inv=rig.matrix_world.inverted()
    for bone,start,end in ((upper,hip,knee),(lower,knee,target)):
        rest=bone.bone;desired=(inv@end-inv@start).normalized()
        restdir=(rest.tail_local-rest.head_local).normalized()
        rotation=restdir.rotation_difference(desired).to_matrix()@rest.matrix_local.to_3x3()
        bone.matrix=Matrix.LocRotScale(inv@start,rotation.to_quaternion(),Vector((1,1,1)))
        bpy.context.view_layer.update()
    foot.matrix=Matrix.LocRotScale(inv@target,foot.bone.matrix_local.to_quaternion(),Vector((1,1,1)))
    bpy.context.view_layer.update()


def body_pose(rig, t, idle=False):
    if not idle:
        t /= TIME_SCALE
    for p in rig.pose.bones:
        p.rotation_mode='QUATERNION';p.matrix_basis.identity()
    lean=.065 if idle else curve(t,[(0,.09),(.12,.09),(.50,-.13),(.57,-.13),(.73,.25),(.85,.50),(.90,.50),(1.02,.28),(1.15,.09)])
    side_lean=0 if idle else curve(t,[(0,0),(.12,0),(.50,.10),(.57,.10),(.85,0),(.90,0),(1.15,0)])
    pose_rotation(rig,'chest',lean,side_lean)
    # A small planted stagger opens during anticipation and remains through
    # contact, rather than rotating knees while the boots float off the ground.
    stagger=0 if idle else curve(t,[(0,0),(.12,0),(.38,.072),(.90,.072),(1.15,0)])
    sink=.008 if idle else curve(t,[(0,.01),(.12,.01),(.50,.028),(.57,.028),(.85,.075),(.90,.075),(1.02,.040),(1.15,.01)])
    shift=0 if idle else curve(t,[(0,0),(.12,0),(.50,.022),(.57,.022),(.85,-.015),(.90,-.015),(1.15,0)])
    scale=rig.matrix_world.to_scale().x
    offset=Vector((0,shift,-sink))/scale
    rig.pose.bones['root'].location=rig.data.bones['root'].matrix_local.to_3x3().inverted()@offset
    bpy.context.view_layer.update()
    for side in ('L','R'):
        rest=rig.matrix_world@rig.data.bones['foot.'+side].head_local
        rest.y+=-stagger if side=='L' else stagger
        solve_leg(rig,side,rest)
    # Keep the head facing naturally ahead/slightly down; torso supplies effort.
    head=rig.pose.bones['head']
    gaze=.035 if idle else curve(t,[(0,.035),(.57,.035),(.85,.20),(.90,.20),(1.15,.035)])
    orientation=Matrix.Rotation(gaze,3,'X') @ rig.data.bones['head'].matrix_local.to_3x3()
    head.matrix=Matrix.LocRotScale(head.head,orientation.to_quaternion(),Vector((1,1,1)))
    bpy.context.view_layer.update()
    deps=bpy.context.evaluated_depsgraph_get()
    bottoms=[(o.evaluated_get(deps).matrix_world@v.co).z for o in BOOTS for v in o.evaluated_get(deps).data.vertices]
    correction=Vector((0,0,-min(bottoms)/scale))
    rig.pose.bones['root'].location+=rig.data.bones['root'].matrix_local.to_3x3().inverted()@correction
    bpy.context.view_layer.update()


def animate(rig, name, seconds, idle=False):
    rig.animation_data_create(); rig.animation_data.action=None
    last=round(seconds*FPS)
    previous={}
    contact=[]
    for frame in range(0,last+1):
        t=frame/FPS
        # Bracket exact impact with its held pose. The exporter samples integer
        # frames; this guarantees subframe gameplay impact has the blade on soil
        # rather than interpolating a floating edge (at most one bake frame early).
        pose_t=IMPACT if not idle and math.floor(IMPACT*FPS)<=frame<=math.ceil(IMPACT*FPS) else t
        body_pose(rig,pose_t,idle)
        transform=tool_matrix(pose_t,idle)
        inv=rig.matrix_world.inverted()
        rotation=rig.matrix_world.to_quaternion().inverted()@transform.to_quaternion()
        rig.pose.bones['hoe_tool'].matrix=Matrix.LocRotScale(inv@transform.translation,rotation,Vector((1,1,1)))
        try:
            solve_arm(rig,'R',transform);solve_arm(rig,'L',transform)
        except AssertionError as error:
            raise AssertionError(f'{name} at {t:.4f}s: {error}') from error
        for p in rig.pose.bones:
            q=p.rotation_quaternion.copy()
            if p.name in previous and q.dot(previous[p.name])<0:q.negate()
            p.rotation_quaternion=q; previous[p.name]=q.copy()
            for channel in ('rotation_quaternion','location','scale'):
                p.keyframe_insert(channel,frame=frame,group=p.name)
        low=min((transform@v).z for v in TOOL_VERTS)
        contact.append({'time':round(t,6),'blade_min_z':round(low,6)})
    action=rig.animation_data.action; action.name=name; action.use_fake_user=True
    # Keyed quaternion and positions were baked together; linear interpolation
    # keeps subframe contacts and grip positions within the sampled motion path.
    for slot in action.slots:
        for layer in action.layers:
            for strip in layer.strips:
                bag=strip.channelbag(slot)
                if bag:
                    for fc in bag.fcurves:
                        for key in fc.keyframe_points:key.interpolation='LINEAR'
    rig.animation_data.action=None
    track=rig.animation_data.nla_tracks.new(); track.name=name
    strip=track.strips.new(name,0,action); strip.name=name; track.mute=True
    return action,contact


def verify_reference_raise(rig, scene):
    """Measure actual preview meshes, not only the prop origin/contact marker."""
    rig.animation_data.action=next(t.strips[0].action for t in rig.animation_data.nla_tracks if t.name=='Hoe')
    head_objects=[o for o in scene.objects if o.type=='MESH' and o.name.startswith(('Hat •','Head','Face','Hair'))]
    moving_objects=[o for o in scene.objects if o.type=='MESH' and o.name.startswith(('Hoe_','GripHand_'))]
    minimum=math.inf; intersections=0
    for frame in range(round(DURATION*FPS)+1):
        scene.frame_set(frame);bpy.context.view_layer.update()
        deps=bpy.context.evaluated_depsgraph_get();vertices=[];faces=[]
        for o in head_objects:
            ev=o.evaluated_get(deps);off=len(vertices)
            vertices.extend(ev.matrix_world@v.co for v in ev.data.vertices)
            faces.extend(tuple(off+i for i in face.vertices) for face in ev.data.polygons)
        tree=BVHTree.FromPolygons(vertices,faces)
        for o in moving_objects:
            ev=o.evaluated_get(deps)
            points=[ev.matrix_world@v.co for v in ev.data.vertices]
            minimum=min(minimum,min(tree.find_nearest(p)[3] for p in points))
            for edge in ev.data.edges:
                start,end=(points[i] for i in edge.vertices);delta=end-start
                if delta.length>.00001:
                    hit=tree.ray_cast(start,delta.normalized(),delta.length)
                    if hit[0] and .000001<hit[3]<delta.length-.000001:
                        intersections+=1
                        if intersections<8:print('CLEARANCE_HIT',frame/FPS,o.name,tuple(hit[0]))
    apex_time=.535*TIME_SCALE
    apex_frame=apex_time*FPS
    scene.frame_set(math.floor(apex_frame),subframe=apex_frame%1);bpy.context.view_layer.update()
    deps=bpy.context.evaluated_depsgraph_get()
    hat_top=max((o.evaluated_get(deps).matrix_world@v.co).z for o in head_objects if o.name.startswith('Hat •') for v in o.evaluated_get(deps).data.vertices)
    tool=rig.matrix_world@rig.pose.bones['hoe_tool'].matrix;scale=tool.to_scale().x
    socket=tool@(SOCKET_CENTER/scale)
    raised_tool_objects=[o for o in moving_objects if o.name.startswith('Hoe_')]
    raised_tool_top=max((o.evaluated_get(deps).matrix_world@v.co).z for o in raised_tool_objects for v in o.evaluated_get(deps).data.vertices)
    extensions={};heights={};lengths={}
    for side in ('R','L'):
        shoulder=rig.matrix_world@rig.pose.bones['upper_arm.'+side].head
        wrist=rig.matrix_world@rig.pose.bones['hand.'+side].head
        length=sum(rig.data.bones[b+'.'+side].length for b in ('upper_arm','forearm'))*rig.matrix_world.to_scale().x
        lengths[side]=length;extensions[side]=(wrist-shoulder).length/length;heights[side]=wrist.z-shoulder.z
    assert raised_tool_top>hat_top, (raised_tool_top,hat_top)
    assert min(heights.values())>.015, heights
    # User-approved natural swing takes priority over brim clearance.
    # Keep intersections visible in the report without distorting the motion.
    return {'raised_time':apex_time,'raised_socket_height_m':socket.z,'raised_tool_top_m':raised_tool_top,'raised_hat_top_m':hat_top,
        'raised_arm_extension_ratio':extensions,'raised_wrist_height_above_shoulder_m':heights,
        'arm_segment_total_length_m':lengths,'head_tool_mesh_edge_intersections':intersections,
        'head_tool_mesh_vertex_min_distance_m':minimum}


def wrist_roll(rig, side):
    """Measure axial skin-ring roll independent of elbow/wrist bending."""
    lower=rig.pose.bones['forearm.'+side]
    hand=rig.pose.bones['hand.'+side]
    axis=(rig.matrix_world@hand.head-rig.matrix_world@lower.head).normalized()
    rest=rig.data.bones[lower.name]
    rest_axis=(rest.tail_local-rest.head_local).normalized()
    rest_radial=rest_axis.cross(Vector((0,1,0))).normalized()
    radial=rig.matrix_world.to_3x3() @ (lower.matrix.to_3x3() @ rest.matrix_local.to_3x3().inverted() @ rest_radial)
    radial=(radial-axis*radial.dot(axis)).normalized()
    prop=rig.matrix_world@rig.pose.bones['hoe_tool'].matrix
    palm=(prop.to_3x3()@Vector((0,1,0))).normalized()
    reference=palm.cross(axis)
    transverse=reference.length
    reference.normalize()
    return math.degrees(math.atan2(axis.dot(radial.cross(reference)),radial.dot(reference))),transverse


def select_export(objects,path,animations=False):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,
        use_active_scene=True,export_animations=animations,export_animation_mode='NLA_TRACKS',
        export_yup=True,export_skins=True,export_morph=False)


def setup_render(objects, path):
    scene=bpy.context.scene
    for o in scene.objects:o.hide_render=o not in objects
    groundmat=material('Preview • parchment backdrop',(.76,.70,.59))
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.081))
    ground=bpy.context.object; ground.name='StudioBackdrop'; ground.data.materials.append(groundmat)
    bpy.ops.object.camera_add(location=(1.05,-1.7,.95))
    camera=bpy.context.object; camera.name='HoeCloseupCamera'
    camera.rotation_euler=(Vector((0,-.035,.34))-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.type='ORTHO';camera.data.ortho_scale=1.03;scene.camera=camera
    for name,loc,energy,size in [('Key',(-2,-3,4),70,3),('Fill',(3,-1,2),35,3)]:
        bpy.ops.object.light_add(type='AREA',location=loc)
        light=bpy.context.object;light.name=name;light.data.energy=energy;light.data.shape='DISK';light.data.size=size
        light.rotation_euler=(Vector((0,0,.3))-light.location).to_track_quat('-Z','Y').to_euler()
    if scene.world is None: scene.world=bpy.data.worlds.new('HoeStudioWorld')
    scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.72,.76,.8,1)
    scene.world.node_tree.nodes['Background'].inputs[1].default_value=.25
    scene.view_settings.view_transform='Standard'
    scene.render.engine='CYCLES';scene.cycles.samples=32
    scene.render.resolution_x=1024;scene.render.resolution_y=1024;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG';scene.render.filepath=str(path)
    bpy.ops.render.render(write_still=True)
    for o in list(scene.objects):
        if o.name in ['StudioBackdrop','HoeCloseupCamera','Key','Fill']:bpy.data.objects.remove(o,do_unlink=True)
    for o in scene.objects:o.hide_render=False


bpy.ops.wm.open_mainfile(filepath=str(ROOT/'Art/Characters/ForestGirl/runtime.blend'))
scene=bpy.context.scene;scene.name='ForestGirl_Hoe_ArtPreview';scene.render.fps=FPS;scene.frame_start=0
rig=next(o for o in scene.objects if o.type=='ARMATURE')
rig.animation_data_clear()
for p in rig.pose.bones:p.matrix_basis.identity()
bpy.context.view_layer.update()
hand_objects=[o for o in scene.objects if o.type=='MESH' and o.name.startswith('Hand •')]
# Closed preview fingers use a plain peach skin material; face vertex colors
# remain on the supplied character and are enabled by the Godot import script.
skin=bpy.data.materials['Skin • peach']
for o in hand_objects:bpy.data.objects.remove(o,do_unlink=True)
sys.path.insert(0,str(HERE))
from arm_geometry import repair_arms
ARM_REPORT=repair_arms(rig,arm_length_scale=1.40)
BOOTS=[o for o in scene.objects if o.type=='MESH' and o.name.startswith('Boot')]
OUT.mkdir(parents=True,exist_ok=True)
(HERE/'Review').mkdir(parents=True,exist_ok=True)
TOOL=tool_geometry()
TOOL_VERTS=[v.co.copy() for o in TOOL for v in o.data.vertices]
select_export(TOOL,OUT/'hoe.glb')
if '--skip-closeup' not in sys.argv:
    setup_render(TOOL,HERE/'Review/hoe_closeup.png')
# Additional prop bone is independent of chest/root, so the tool's contact arc
# is authored explicitly while both wrists solve to its same moving frame.
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.context.view_layer.objects.active=rig
bpy.ops.object.mode_set(mode='EDIT')
bone=rig.data.edit_bones.new('hoe_tool');bone.head=(0,0,0);bone.tail=(0,0,.75/rig.matrix_world.to_scale().x)
bpy.ops.object.mode_set(mode='OBJECT')
for ob in TOOL:
    for v in ob.data.vertices:
        v.co=rig.data.bones['hoe_tool'].matrix_local @ (v.co/rig.matrix_world.to_scale().x)
    skin_mesh(ob,rig,'hoe_tool')
GRIP_HANDS=grip_hands(rig,skin)
REACH_ERRORS=[];GRIP_ERRORS=[];JOINT_ERRORS=[]
hoe,contact=animate(rig,'Hoe',DURATION)
idle,idle_contact=animate(rig,'HoeIdle',1.0,True)
assert max(JOINT_ERRORS)<.00001, max(JOINT_ERRORS)
# Restore the opening hold pose before saving, with source/preview tracks muted.
body_pose(rig,0)
transform=tool_matrix(0)
inv=rig.matrix_world.inverted()
rig.pose.bones['hoe_tool'].matrix=Matrix.LocRotScale(inv@transform.translation,
    rig.matrix_world.to_quaternion().inverted()@transform.to_quaternion(),Vector((1,1,1)))
solve_arm(rig,'R',transform);solve_arm(rig,'L',transform)
rig.animation_data.action=None
bpy.context.view_layer.update()
# Skeleton marker empties give future attachments a readable grip contract.
for side,z in GRIPS.items():
    marker=bpy.data.objects.new('Grip_'+side,None);scene.collection.objects.link(marker)
    marker.parent=rig;marker.parent_type='BONE';marker.parent_bone='hoe_tool'
    marker.matrix_world=transform@Matrix.Translation((0,0,z))
    marker.empty_display_size=.01
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'hoe_preview.blend'))
select_export(list(scene.objects),OUT/'character_with_hoe.glb',True)
impact_transform=tool_matrix(IMPACT)
edge_points=[impact_transform@v for v in TOOL_VERTS]
lowest=min(edge_points,key=lambda p:p.z)
edge_center=impact_transform@CUTTING_EDGE
socket_center=impact_transform@SOCKET_CENTER
cut_direction=(edge_center-socket_center).normalized()
def godot_point(point):
    return [point.x,point.z,-point.y]
recovery_edge=tool_matrix(1.02*TIME_SCALE)@CUTTING_EDGE
assert edge_center.z < socket_center.z-.10
assert abs(edge_center.y-socket_center.y)<.06
assert -cut_direction.z > .70
assert (recovery_edge.xy-edge_center.xy).length < .06
assert .06 < recovery_edge.z < .15
recovery_samples=[tool_matrix(IMPACT+i*(DURATION-IMPACT)/120) for i in range(121)]
assert max((transform@Vector((0,0,GRIPS['R']))).z for transform in recovery_samples)<.525
assert max((transform@CUTTING_EDGE).z for transform in recovery_samples)<.24
report={
    'source_character':'Art/Characters/ForestGirl/runtime.blend',
    'swing_plane':'reference_with_short_recovery','hat_clearance_required':False,
    'raise_angle_radians':2.65,'impact_angle_radians':1.1,'strike_arc_degrees':math.degrees(2.65-1.1),
    'time_scale':TIME_SCALE,'author_duration_seconds':AUTHOR_DURATION,
    'raised_hold_seconds':[.50*TIME_SCALE,.57*TIME_SCALE],'downstroke_duration_seconds':IMPACT-.57*TIME_SCALE,
    'reference_phase_times':{phase:time*TIME_SCALE for phase,time in {'ready':.10,'anticipation':.535,'swing':.73,'impact':AUTHOR_IMPACT,'follow_through':1.02,'recovered':AUTHOR_DURATION}.items()},
    'arm_geometry':ARM_REPORT,'head_down_pitch_radians':{'ready':.035,'impact':.20},
    'character_height_m':1.2,'tool_total_length_m':max(v.z for v in TOOL_VERTS)-min(v.z for v in TOOL_VERTS),'tool_blade_width_m':.192,
    'fps':FPS,'clips':[{'name':'Hoe','duration':DURATION,'loop':False},{'name':'HoeIdle','duration':1.0,'loop':True}],
    'impact_time':IMPACT,'contact_sampling_advance_seconds':IMPACT-math.floor(IMPACT*FPS)/FPS,
    'impact_position_blender':list(edge_center),
    'impact_position_godot':godot_point(edge_center),
    'impact_socket_position_godot':godot_point(socket_center),
    'impact_socket_to_cutting_edge_godot':godot_point(edge_center-socket_center),
    'impact_cut_direction_godot':godot_point(cut_direction),
    'impact_cut_angle_below_horizontal_degrees':math.degrees(math.asin(-cut_direction.z)),
    'recovery_edge_sample_time':1.02*TIME_SCALE,
    'recovery_edge_position_godot':godot_point(recovery_edge),
    'contact_hold_seconds':[IMPACT,.90*TIME_SCALE],'recovery_duration_seconds':DURATION-IMPACT,
    'impact_edge_end_godot':[lowest.x,lowest.z,-lowest.y],
    'tool_bone':'hoe_tool','hand_bones':['hand.L','hand.R'],'grip_markers':['Grip_L','Grip_R'],
    'skeleton_path':'ForestGirlScale/Forest_Girl_Rig/Skeleton3D',
    'grip_spacing_m':GRIPS['R']-GRIPS['L'],
    'max_grip_error_m':max(GRIP_ERRORS),'max_arm_joint_error_m':max(JOINT_ERRORS),
    'max_reach_error_m':max(REACH_ERRORS),'blade_contact_samples':contact,
    'preview_only_closed_hand_meshes':len(GRIP_HANDS),
    'tool_meshes':len(TOOL),'tool_triangles':sum(len(p.vertices)-2 for ob in TOOL for p in ob.data.polygons),
}
# Validate the exported asset, including the interpolated frames used by Godot.
verification=bpy.data.scenes.new('Hoe_Export_Verification');verification.render.fps=FPS;bpy.context.window.scene=verification
bpy.ops.import_scene.gltf(filepath=str(OUT/'character_with_hoe.glb'))
vrig=next(o for o in verification.objects if o.type=='ARMATURE')
for track in vrig.animation_data.nla_tracks: track.mute=True
exported_errors=[]
exported_wrist_roll={}
vertical_plane={'max_socket_lateral_drift_m':0.0,'max_cutting_edge_lateral_offset_m':0.0,'max_chest_lateral_tilt':0.0}
for track in vrig.animation_data.nla_tracks:
    vrig.animation_data.action=track.strips[0].action
    start,end=vrig.animation_data.action.frame_range
    roll_samples={side:[] for side in ('R','L')}
    for step in range(round((end-start)*2)+1):
        sample=start+step*.5
        verification.frame_set(math.floor(sample),subframe=sample%1)
        bpy.context.view_layer.update()
        tool=vrig.matrix_world@vrig.pose.bones['hoe_tool'].matrix
        scale=tool.to_scale().x
        if track.name=='Hoe':
            socket=tool@(SOCKET_CENTER/scale)
            edge=tool@(CUTTING_EDGE/scale)
            chest=vrig.pose.bones['chest']
            chest_rotation=chest.matrix.to_quaternion().to_matrix() @ chest.bone.matrix_local.to_quaternion().to_matrix().transposed()
            up=vrig.matrix_world.to_quaternion() @ (chest_rotation @ Vector((0,0,1)))
            vertical_plane['max_socket_lateral_drift_m']=max(vertical_plane['max_socket_lateral_drift_m'],abs(socket.x-.015))
            vertical_plane['max_cutting_edge_lateral_offset_m']=max(vertical_plane['max_cutting_edge_lateral_offset_m'],abs(socket.x-edge.x))
            vertical_plane['max_chest_lateral_tilt']=max(vertical_plane['max_chest_lateral_tilt'],abs(up.x))
        for side,z in GRIPS.items():
            sign=-1 if side=='L' else 1
            expected=tool@Vector((sign*.041/scale,0,(z+.006)/scale))
            actual=vrig.matrix_world@vrig.pose.bones['hand.'+side].head
            exported_errors.append((actual-expected).length)
            roll,reference_length=wrist_roll(vrig,side)
            roll_samples[side].append((sample/FPS,roll,reference_length))
    exported_wrist_roll[track.name]={side:{
        'max_axial_roll_degrees':max(abs(v[1]) for v in values),
        'min_palm_reference_transverse_length':min(v[2] for v in values),
        'recovery_axial_roll_range_degrees':max(v[1] for v in values if v[0]>=IMPACT)-min(v[1] for v in values if v[0]>=IMPACT)
    } for side,values in roll_samples.items()}
report['max_exported_subframe_grip_error_m']=max(exported_errors)
report['wrist_roll_validation']=exported_wrist_roll
report['vertical_plane_validation']=vertical_plane
# Reference permits modest lateral anticipation; contact remains straight ahead.
assert abs(edge_center.x-.015)<.0001
for clip in exported_wrist_roll.values():
    for side in clip.values():
        assert side['min_palm_reference_transverse_length']>.25
        assert side['max_axial_roll_degrees']<.1, side
vrig.animation_data.action=next(t.strips[0].action for t in vrig.animation_data.nla_tracks if t.name=='Hoe')
impact_frame=IMPACT*FPS
verification.frame_set(math.floor(impact_frame),subframe=impact_frame%1);bpy.context.view_layer.update()
deps=bpy.context.evaluated_depsgraph_get()
exported_tool=[o for o in verification.objects if o.type=='MESH' and o.name.startswith('Hoe_')]
exported_points=[ev.matrix_world@v.co for o in exported_tool for ev in [o.evaluated_get(deps)] for v in ev.data.vertices]
report['exported_impact_blade_min_z']=min(p.z for p in exported_points)
sharp=next(o for o in exported_tool if o.name.startswith('Hoe_SharpenedEdge'))
ev=sharp.evaluated_get(deps)
sharp_points=[ev.matrix_world@v.co for v in ev.data.vertices]
report['exported_impact_cutting_edge_min_z']=min(p.z for p in sharp_points)
assert abs(report['exported_impact_cutting_edge_min_z'])<.0001
assert abs(report['exported_impact_cutting_edge_min_z']-report['exported_impact_blade_min_z'])<.0001
assert abs(report['exported_impact_blade_min_z'])<.0001, report['exported_impact_blade_min_z']
assert max(exported_errors)<.003, max(exported_errors)
report.update(verify_reference_raise(vrig,verification))
(HERE/'manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print('HOE_PREVIEW_REPORT',json.dumps(report,ensure_ascii=False))

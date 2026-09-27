"""Render the imported game asset, without rebuilding the supplied geometry."""
from pathlib import Path
import bpy, math
from mathutils import Vector
ART=Path(__file__).resolve().parent
OUT=ART/'Review';OUT.mkdir(exist_ok=True)
scene=bpy.context.scene
rig=next(o for o in scene.objects if o.type=='ARMATURE')
if rig.animation_data:
 for t in rig.animation_data.nla_tracks:t.mute=True
 rig.animation_data.action=None
for bone in rig.pose.bones:bone.matrix_basis.identity()
scene.frame_set(1)
world=bpy.data.worlds.new('ForestReviewWorld');world.use_nodes=True
bg=next(n for n in world.node_tree.nodes if n.type=='BACKGROUND');bg.inputs[0].default_value=(.6,.6,.6,1);bg.inputs[1].default_value=.4
scene.world=world
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.002));floor=bpy.context.object;floor.name='ReviewFloor'
fm=bpy.data.materials.new('ReviewFloor');fm.use_nodes=True
sh=next(n for n in fm.node_tree.nodes if n.type=='BSDF_PRINCIPLED');sh.inputs['Base Color'].default_value=(.65,.61,.54,1);sh.inputs['Roughness'].default_value=.95
floor.data.materials.append(fm)
def aim(o,target):o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
for name,pos,power,size in [('Key',(-2,-3,4),170,3),('Fill',(3,-1,2),80,3),('Rim',(1,3,3),160,2)]:
 data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size
 o=bpy.data.objects.new(name,data);scene.collection.objects.link(o);o.location=pos;aim(o,(0,0,.6))
cam=bpy.data.objects.new('RuntimeReviewCamera',bpy.data.cameras.new('RuntimeReviewCamera'));scene.collection.objects.link(cam);scene.camera=cam
cam.data.type='ORTHO';cam.data.ortho_scale=1.55
scene.render.resolution_x=720;scene.render.resolution_y=900;scene.render.resolution_percentage=100
try:scene.render.engine='CYCLES'
except TypeError:pass
scene.cycles.samples=24;scene.cycles.use_denoising=True
scene.render.image_settings.file_format='PNG';scene.view_settings.view_transform='Standard'
for angle,name in [(0,'front'),(90,'side'),(180,'back'),(35,'perspective')]:
 a=math.radians(angle);cam.location=(3*math.sin(a),-3*math.cos(a),.86);aim(cam,(0,0,.6))
 scene.render.filepath=str(OUT/(name+'.png'));bpy.ops.render.render(write_still=True)
cam.location=(1.6,-3,.93);aim(cam,(0,0,.6))
for clip,fraction in [('Walk',.25),('freehand_run',.25),('jump_start',.5),('jump_move',.7),('landing_soft',.25),('freehand_fall',.5),('fall_move',.5)]:
 actions=[s.action for t in rig.animation_data.nla_tracks for s in t.strips if t.name==clip]
 if not actions:continue
 rig.animation_data.action=actions[0]
 start,end=actions[0].frame_range;scene.frame_set(int(start+(end-start)*fraction))
 scene.render.filepath=str(OUT/(clip+'.png'));bpy.ops.render.render(write_still=True)
print('FOREST_RUNTIME_RENDER_OK',flush=True)

"""Render actual skinned acceptance poses from the editable low-poly file."""
from pathlib import Path
import bpy, math
from mathutils import Vector
ART=Path(__file__).resolve().parent
OUT=ART/'renders';OUT.mkdir(exist_ok=True)
scene=bpy.data.scenes['FarmerGirl_LowPoly'];bpy.context.window.scene=scene
rig=bpy.data.objects['RIG_Character'];cam=scene.camera
scene.cycles.samples=24
for track in rig.animation_data.nla_tracks:track.mute=True
cam.location=(1.5,-3,.93);cam.rotation_euler=(Vector((0,0,.6))-cam.location).to_track_quat('-Z','Y').to_euler()
for name,frame in [('Walk',9),('Run',7),('Pickup',31),('Carry',31),('Watering',31),('Hoe',31),('Plant',31),('Wave',31),('QA_Squat',2),('QA_ArmsUp',2),('QA_HoldItem',2),('QA_TPose',2)]:
    rig.animation_data.action=bpy.data.actions[name];scene.frame_set(frame)
    scene.render.filepath=str(OUT/(name+'.png'));bpy.ops.render.render(write_still=True)
print('REVIEW_RENDER_OK')

import bpy, os, math, json
from mathutils import Vector
OUT=os.path.dirname(os.path.abspath(__file__))
bpy.ops.wm.open_mainfile(filepath=os.path.join(OUT,'forest_girl.blend'))
scene=bpy.context.scene
# Render the delivered GLB after a fresh import, rather than the authoring meshes.
bpy.ops.object.select_all(action='DESELECT')
for o in list(bpy.data.objects):
    if not o.name.startswith('STUDIO'):bpy.data.objects.remove(o,do_unlink=True)
for a in list(bpy.data.actions):bpy.data.actions.remove(a)
bpy.ops.import_scene.gltf(filepath=os.path.join(OUT,'forest_girl.glb'))
rig=next(o for o in bpy.data.objects if o.type=='ARMATURE')
for tr in rig.animation_data.nla_tracks:tr.mute=True
print('IMPORTED_ACTIONS',list(bpy.data.actions.keys()))
rig.animation_data.action=next(a for a in bpy.data.actions if a.name.startswith('Walk'))
contact_path=os.path.join(OUT,'walk_contact_check.json')
contact=json.load(open(contact_path))
start=int(rig.animation_data.action.frame_range[0])
sole_objects={l:next(o for o in bpy.data.objects if o.type=='MESH' and o.name.startswith('Boot • '+l+' sole')) for l in ['L','R']}
stance_errors=[];all_heights=[]
for source_frame in range(1,26):
    scene.frame_set(start+source_frame-1);bpy.context.view_layer.update()
    dg=bpy.context.evaluated_depsgraph_get()
    for l in ['L','R']:
        evaluated=sole_objects[l].evaluated_get(dg);m=evaluated.to_mesh()
        low=min((evaluated.matrix_world@v.co).z for v in m.vertices)
        evaluated.to_mesh_clear();all_heights.append(low)
        sample=next(x for x in contact['samples'] if x['frame']==source_frame and x['leg']==l)
        if sample['stance']:stance_errors.append(abs(low-.0005))
contact['reimported_glb']={'maximum_stance_sole_error':max(stance_errors),'minimum_sole_height':min(all_heights),'frames_checked':25}
assert max(stance_errors)<.002, 'Exported stance feet lost their ground contact.'
assert min(all_heights)>-.002, 'Exported soles penetrate the floor.'
with open(contact_path,'w') as f:json.dump(contact,f,indent=2)
print('GLB_FOOT_CONTACT',contact['reimported_glb'])
scene.render.resolution_x=480;scene.render.resolution_y=560
scene.cycles.samples=48;scene.render.threads_mode='FIXED';scene.render.threads=8
cam=scene.camera;cam.location=(5,-8,3.2);cam.rotation_euler=(Vector((0,0,1.87))-cam.location).to_track_quat('-Z','Y').to_euler()
os.makedirs(os.path.join(OUT,'motion_frames'),exist_ok=True)
for f in range(1,25,2):
    scene.frame_set(f);scene.render.filepath=os.path.join(OUT,'motion_frames',f'{f:03d}.png');bpy.ops.render.render(write_still=True)
print('MOTION_RENDER_COMPLETE')

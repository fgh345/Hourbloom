"""Build the v1 low-poly turnaround in an isolated Blender scene.
Run: blender --factory-startup --background --python <this file>.
Geometry is built and validated before UV, painting, rigging and export.
"""
from pathlib import Path
import sys, json, math, shutil, struct
import bpy, bmesh, numpy as np
from mathutils import Vector
ART=Path(__file__).resolve().parent
ROOT=ART.parents[2]
OUT=ROOT/'Assets/Characters/FarmerGirl'
OUT.mkdir(parents=True,exist_ok=True)
(OUT/'textures').mkdir(exist_ok=True)
(ART/'renders').mkdir(exist_ok=True)
sys.path.insert(0,str(ART))
from lowpoly_geometry import build_geometry
from lowpoly_rig import build_rig, add_animations
scene=bpy.data.scenes.new('FarmerGirl_LowPoly')
bpy.context.window.scene=scene
scene.unit_settings.system='METRIC'; scene.unit_settings.scale_length=1
scene.render.fps=30
scene['asset_notes']='Low-poly farm girl v1; new skirt turnaround; -Y forward; height 1.20m including hat.'
character=bpy.data.collections.new('Character'); scene.collection.children.link(character)
collections={}
for name in ('Mesh','Rig','Props','Reference'):
    collections[name]=bpy.data.collections.new(name); character.children.link(collections[name])
def share_atlas(path):
    """Use one external atlas across all three GLBs instead of packing copies."""
    payload=path.read_bytes()
    json_length=struct.unpack_from('<I',payload,12)[0]
    document=json.loads(payload[20:20+json_length])
    binary_start=20+json_length+8
    binary=payload[binary_start:]
    assert len(document['images'])==1, 'Expected one shared atlas'
    image_entry=document['images'][0]
    index=image_entry.pop('bufferView')
    image_entry.pop('mimeType',None)
    image_entry['uri']='textures/T_CHR_BaseColor.png'
    view=document['bufferViews'].pop(index)
    offset=view.get('byteOffset',0)
    size=(view['byteLength']+3)//4*4
    binary=binary[:offset]+binary[offset+size:]
    for entry in document['bufferViews']:
        if entry.get('byteOffset',0)>offset:
            entry['byteOffset']-=size
    def update_indices(value):
        if isinstance(value,dict):
            for key,item in value.items():
                if key=='bufferView':
                    assert item != index, 'Atlas must not be referenced by geometry'
                    if item>index: value[key]=item-1
                else: update_indices(item)
        elif isinstance(value,list):
            for item in value: update_indices(item)
    update_indices(document)
    document['buffers'][0]['byteLength']-=size
    json_bytes=json.dumps(document,separators=(',',':')).encode('utf-8')
    json_bytes+=b' '*((-len(json_bytes))%4)
    binary+=b'\0'*((-len(binary))%4)
    total=12+8+len(json_bytes)+8+len(binary)
    path.write_bytes(struct.pack('<III',0x46546C67,2,total)+struct.pack('<II',len(json_bytes),0x4E4F534A)+json_bytes+struct.pack('<II',len(binary),0x004E4942)+binary)

objects=build_geometry(scene,collections['Mesh'])
for obj in objects:
    bm=bmesh.new(); bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=0.000001)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    assert all(e.is_manifold for e in bm.edges), 'Open geometry: '+obj.name
    assert all(f.calc_area()>1e-10 for f in bm.faces), 'Degenerate: '+obj.name
    bm.to_mesh(obj.data); bm.free()
tris=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in objects)
assert tris<=5000, tris
print('SILHOUETTE_GEOMETRY_OK',tris,flush=True)
# Unique packed UV for opaque surfaces. Facial decals get separate, padded cells.
ordinary=[o for o in objects if not o.get('eye') and not o.get('mouth')]
bpy.ops.object.select_all(action='DESELECT')
for o in ordinary:o.select_set(True)
bpy.context.view_layer.objects.active=ordinary[0]
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.014)
bpy.ops.object.mode_set(mode='OBJECT')
for o in ordinary:
    for loop in o.data.uv_layers.active.data:loop.uv.x=loop.uv.x*.72+.008;loop.uv.y=loop.uv.y*.984+.008
# Record original colour per polygon before replacing materials.
SIZE=1024
coverage=np.zeros((SIZE,SIZE),dtype=np.uint16)
canvas=np.ones((SIZE,SIZE,4),dtype=np.float32);canvas[:,:,:3]=(.93,.89,.8)
def color(mat):
    if mat.use_nodes:
        n=next((n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
        if n:
            raw=np.array(n.inputs['Base Color'].default_value[:3]); return np.where(raw<=.04045,raw/12.92,((raw+.055)/1.055)**2.4)
    return np.array(mat.diffuse_color[:3])
def srgb(rgb):return np.where(rgb<=.0031308,rgb*12.92,1.055*np.power(rgb,1/2.4)-.055)
# Material RGB is linear in Blender. Texture pixels are linear too (image API).
for o in ordinary:
    uv=o.data.uv_layers.active.data
    for p in o.data.polygons:
        points=np.array([uv[i].uv[:] for i in p.loop_indices])*SIZE
        verts=np.array([o.data.vertices[i].co[:] for i in p.vertices])
        base=color(o.data.materials[p.material_index])
        for j in range(1,len(points)-1):
            a,b,c=points[[0,j,j+1]]
            x0,y0=np.floor(np.min([a,b,c],axis=0)-8).astype(int);x1,y1=np.ceil(np.max([a,b,c],axis=0)+8).astype(int)
            x0=max(0,x0);y0=max(0,y0);x1=min(SIZE-1,x1);y1=min(SIZE-1,y1)
            yy,xx=np.mgrid[y0:y1+1,x0:x1+1]; xx=xx+.5;yy=yy+.5
            den=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
            if abs(den)<1e-8:continue
            w0=((b[1]-c[1])*(xx-c[0])+(c[0]-b[0])*(yy-c[1]))/den
            w1=((c[1]-a[1])*(xx-c[0])+(a[0]-c[0])*(yy-c[1]))/den;w2=1-w0-w1
            coverage[y0:y1+1,x0:x1+1]+=((w0>1e-6)&(w1>1e-6)&(w2>1e-6)).astype(np.uint16)
            # Fill padding first; interior overrides and pack spacing prevents bleed.
            lengths=np.array([np.linalg.norm(b-c),np.linalg.norm(a-c),np.linalg.norm(a-b)])
            heights=abs(den)/np.maximum(lengths,1e-6)
            mask=(w0>=-8/heights[0])&(w1>=-8/heights[1])&(w2>=-8/heights[2])
            shade=.97+.035*np.clip(w0*.2+w1*.5+w2*.8,0,1)
            rgb=base[None,None,:]*shade[:,:,None]
            world=w0[:,:,None]*verts[0]+w1[:,:,None]*verts[j]+w2[:,:,None]*verts[j+1]
            # Small green clover embroidery near the cream dress hem.
            if 'Dress' in o.name and base[0]>.6:
                wx=world[:,:,0];wz=world[:,:,2]
                flower=np.zeros_like(mask)
                for cx in (-.105,-.035,.035,.105):
                    for dx,dz in ((-.009,0),(.009,0),(0,.012),(0,-.012)):
                        flower|=((wx-cx-dx)/.009)**2+((wz-.385-dz)/.011)**2<1
                rgb=np.where(flower[:,:,None],np.array([.18,.24,.105]),rgb)
            if o.name.startswith('CHR_Boots_') and 'Sole' not in o.name:
                wx=world[:,:,0];wy=world[:,:,1];wz=world[:,:,2]
                center=.075 if '_L' in o.name else -.075
                lace=np.zeros_like(mask)
                for k in range(3):
                    z=.085+k*.027
                    for direction in (-1,1):
                        line=z+direction*(wx-center)*.38
                        lace|=(abs(wz-line)<.003)&(abs(wx-center)<.024)&(wy<-.066)
                rgb=np.where(lace[:,:,None],np.array([.56,.34,.12]),rgb)
            canvas[y0:y1+1,x0:x1+1,:3][mask]=rgb[mask]
uv_overlap=int(np.count_nonzero(coverage>1))
assert uv_overlap==0, f'Unintended body UV overlap texels: {uv_overlap}'
# Facial texture rows: Neutral, Happy, Surprised, Angry, Sad, Blink, Sleepy, Thinking.
skin=np.array([.8796224,.5647115,.3915725])*.988; dark=np.array([.085,.045,.027]);cream=np.array([.94,.9,.79])
def paint_face(rect,row,mouth=False):
    x0,x1=rect;y0=row*128;y1=y0+128
    yy,xx=np.mgrid[0:128,0:x1-x0];u=xx/(x1-x0);v=yy/128
    rgb=np.broadcast_to(skin,(128,x1-x0,3)).copy()
    def put(mask,col):rgb[mask]=col
    if not mouth:
        ellipse=((u-.5)/.30)**2+((v-.45)/.35)**2
        if row in (1,5,6):
            line=.45+(.12 if row==1 else -.015)*np.cos((u-.5)*7)
            put((abs(v-line)<.025)&(abs(u-.5)<.34),dark)
        else:
            put(ellipse<1,dark)
            put(((u-.5)/.265)**2+((v-.44)/.315)**2<1,cream)
            iris=((u-.51)/.19)**2+((v-.44)/.29)**2
            put(iris<1,np.array([.20,.105,.055]))
            put(((u-.51)/.105)**2+((v-.50)/.20)**2<1,dark)
            put(((u-.44)/.063)**2+((v-.61)/.063)**2<1,cream)
            put(((u-.59)/.034)**2+((v-.32)/.034)**2<1,np.array([.82,.62,.32]))
            brow=.87+(.14*(u-.5) if row==3 else -.12*(u-.5) if row==4 else .10*np.sin(u*4) if row==7 else .0)
            put((abs(v-brow)<.017)&(abs(u-.5)<.26),dark)
    else:
        if row in (1,2):
            m=((u-.5)/(.26 if row==1 else .18))**2+((v-.48)/(.20 if row==1 else .25))**2<1
            put(m,np.array([.4,.07,.045]));put(m&(v<.44),np.array([.85,.24,.15]))
        else:
            line=.5+(.08 if row==4 else -.06)*np.cos((u-.5)*8)+(u-.5)*.15*(row==7)
            put((abs(v-line)<.017)&(abs(u-.5)<.23),np.array([.4,.12,.07]))
    canvas[y0:y1,x0:x1,:3]=rgb
for row in range(8):
    paint_face((768,864),row);paint_face((864,960),row);paint_face((960,1024),row,True)
eyes=[o for o in objects if o.get('eye')]
for index,o in enumerate(eyes+[o for o in objects if o.get('mouth')]):
    mouth=bool(o.get('mouth')); x0=960 if mouth else (768 if index%2==0 else 864);width=64 if mouth else 96
    for loop in o.data.uv_layers.active.data:
        loop.uv=((x0+8+loop.uv.x*(width-16))/1024,(8+loop.uv.y*112)/1024)
image=bpy.data.images.new('T_CHR_BaseColor',width=SIZE,height=SIZE,alpha=True)
image.pixels.foreach_set(canvas.ravel());image.filepath_raw=str(OUT/'textures/T_CHR_BaseColor.png');image.file_format='PNG';image.save()
mat=bpy.data.materials.new('M_CHR_Main');mat.use_nodes=True
shader=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
shader.inputs['Roughness'].default_value=.85;shader.inputs['Metallic'].default_value=0
tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=image;mat.node_tree.links.new(tex.outputs['Color'],shader.inputs['Base Color'])
for o in objects:
    o.data.materials.clear();o.data.materials.append(mat)
    for p in o.data.polygons:p.material_index=0
rig=build_rig(scene,collections['Rig'],objects)
animations=add_animations(rig)
# Join related authored pieces after weights, preserving the specified modular meshes.
groups={}
for o in objects:
    category=o.name.split('.')[0].split('__')[0]
    # Module names start with CHR_Category followed by part suffix.
    category='_'.join(o.name.split('_')[:2])
    groups.setdefault(category,[]).append(o)
meshes=[]
for name,parts in groups.items():
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts:o.select_set(True)
    bpy.context.view_layer.objects.active=parts[0]
    if len(parts)>1:bpy.ops.object.join()
    obj=bpy.context.object;obj.name=name;meshes.append(obj)
# True AO bake into the same unique atlas; authored file retains it as optional texture.
try:scene.render.engine='CYCLES'
except TypeError:pass
scene.cycles.samples=16
world=bpy.data.worlds.new('FarmStudio');world.use_nodes=True;scene.world=world
world.node_tree.nodes.get('Background').inputs[0].default_value=(.65,.65,.65,1)
ao=bpy.data.images.new('T_CHR_AO',width=SIZE,height=SIZE,alpha=False)
aotex=mat.node_tree.nodes.new('ShaderNodeTexImage');aotex.image=ao;mat.node_tree.nodes.active=aotex
bpy.ops.object.select_all(action='DESELECT')
for o in meshes:o.select_set(True)
bpy.context.view_layer.objects.active=meshes[0]
scene.render.bake.margin=8
bpy.ops.object.bake(type='AO')
ao.filepath_raw=str(OUT/'textures/T_CHR_AO.png');ao.file_format='PNG';ao.save()
mat.node_tree.nodes.remove(aotex)
# Export only meshes and deform rig, animation tracks are in-place.
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True)
for o in meshes:o.select_set(True)
bpy.context.view_layer.objects.active=rig
for filename in ('farmer_girl.glb','farm_girl.glb'):
    bpy.ops.export_scene.gltf(filepath=str(OUT/filename),export_format='GLB',use_selection=True,use_active_scene=True,export_animations=True,export_animation_mode='NLA_TRACKS',export_yup=True,export_skins=True,export_morph=False)
    share_atlas(OUT/filename)
# Reset rig for the neutral turnaround.
for track in rig.animation_data.nla_tracks:track.mute=True
rig.animation_data.action=None
for bone in rig.pose.bones:bone.rotation_euler=(0,0,0);bone.location=(0,0,0);bone.scale=(1,1,1)
scene.frame_set(1)
# Studio lighting is separate and excluded from the export.
def aim(o,target):o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
for name,pos,power,size in [('Key',(-2,-3,4),180,3),('Fill',(3,-1,2),80,3),('Rim',(1,3,3),160,2)]:
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size
    o=bpy.data.objects.new(name,data);scene.collection.objects.link(o);o.location=pos;aim(o,(0,0,.65))
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.003));floor=bpy.context.object;floor.name='StudioFloor'
fm=bpy.data.materials.new('StudioFloor');fm.diffuse_color=(.7,.65,.56,1);floor.data.materials.append(fm)
cam=bpy.data.objects.new('ReviewCamera',bpy.data.cameras.new('ReviewCamera'));scene.collection.objects.link(cam);scene.camera=cam
cam.data.type='ORTHO';cam.data.ortho_scale=1.55
scene.render.resolution_x=720;scene.render.resolution_y=900;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.view_settings.view_transform='Standard';scene.cycles.samples=32
scene.cycles.use_denoising=True
bpy.ops.wm.save_as_mainfile(filepath=str(ART/'farm_girl_v01.blend'),compress=True)
shutil.copy2(ART/'farm_girl_v01.blend',ART/'farmer_girl.blend')
for angle,name in [(0,'front'),(90,'side'),(180,'back'),(35,'perspective')]:
    a=math.radians(angle);cam.location=(3*math.sin(a),-3*math.cos(a),.86);aim(cam,(0,0,.60))
    scene.render.filepath=str(ART/'renders'/f'{name}.png');bpy.ops.render.render(write_still=True)
cam.location=(1.72,-2.46,.86);aim(cam,(0,0,.60))
bpy.ops.wm.save_as_mainfile(filepath=str(ART/'farm_girl_v01.blend'),compress=True)
shutil.copy2(ART/'farm_girl_v01.blend',ART/'farmer_girl.blend')
stats={'triangles':tris,'vertices':sum(len(o.data.vertices) for o in meshes),'runtime_meshes':len(meshes),'material_count':1,'material_surfaces':len(meshes),'texture_resolution':[1024,1024],'head_height_m':.42,'heads_tall':round(1.20/.42,3),'height_m':round(max(v.co.z for o in meshes for v in o.data.vertices),4),'bones':len(rig.data.bones),'animations':animations,'expressions':['Neutral','Happy','Surprised','Angry','Sad','Blink','Sleepy','Thinking'],'topology':'closed manifold; no duplicate vertices or degenerate faces','uv':'unique packed body islands; separate padded facial cells','uv_overlap_texels':uv_overlap,'feet_min_z':round(min(v.co.z for o in meshes for v in o.data.vertices),5),'max_bone_influences':max(len(v.groups) for o in meshes for v in o.data.vertices),'source':'build_farmer_girl.py','axis':'Blender -Y forward / Godot +Z forward'}
(ART/'asset_manifest.json').write_text(json.dumps(stats,ensure_ascii=False,indent=2),encoding='utf-8')
(ART/'model_report.txt').write_text(json.dumps(stats,ensure_ascii=False,indent=2)+'\nExport File: Assets/Characters/FarmerGirl/farm_girl.glb\n',encoding='utf-8')
print('FARMER_GIRL_BUILD_OK',json.dumps(stats),flush=True)

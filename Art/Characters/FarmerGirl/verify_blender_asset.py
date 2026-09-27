"""Validate authored topology/UV and independently reimport the exported GLB."""
import bpy,bmesh,json
from pathlib import Path
ART=Path(__file__).resolve().parent;ROOT=ART.parents[2]
scene=bpy.data.scenes['FarmerGirl_LowPoly'];bpy.context.window.scene=scene
meshes=[o for o in scene.objects if o.type=='MESH' and o.name.startswith('CHR_')]
triangles=0
for o in meshes:
    bm=bmesh.new();bm.from_mesh(o.data)
    assert all(e.is_manifold for e in bm.edges),o.name
    assert all(f.calc_area()>1e-10 for f in bm.faces),o.name
    assert tuple(o.scale)==(1,1,1),o.name
    assert max((len(v.groups) for v in o.data.vertices),default=0)<=4
    for vertex in o.data.vertices:assert abs(sum(g.weight for g in vertex.groups)-1)<1e-5
    triangles+=sum(len(p.vertices)-2 for p in o.data.polygons)
    bm.free()
assert triangles<=5000
bounds=[v.co.z for o in meshes for v in o.data.vertices]
assert abs(min(bounds))<1e-5 and abs(max(bounds)-1.20)<1e-5
for o in meshes:
    assert o.data.uv_layers.active
    assert all(0<=p.uv.x<=1 and 0<=p.uv.y<=1 for p in o.data.uv_layers.active.data)
assert len(set(o.data.materials[0].name for o in meshes))==1
manifest=json.loads((ART/'asset_manifest.json').read_text());assert manifest['uv_overlap_texels']==0
import_scene=bpy.data.scenes.new('Independent_GLTF_Reimport');bpy.context.window.scene=import_scene
bpy.ops.import_scene.gltf(filepath=str(ROOT/'Assets/Characters/FarmerGirl/farm_girl.glb'))
rigs=[o for o in import_scene.objects if o.type=='ARMATURE'];assert len(rigs)==1
# Blender's importer may create a custom bone-display mesh; it is not GLB geometry.
import_meshes=[o for o in import_scene.objects if o.type=='MESH' and o.name.startswith('CHR_')]
assert len(import_meshes)==len(meshes)
rig=rigs[0];assert rig.data.bones.get('socket_hand_R') and rig.data.bones.get('head')
for o in import_meshes:
    assert o.data.materials and any(n.type=='TEX_IMAGE' and n.image and n.image.size[:]==(1024,1024) for n in o.data.materials[0].node_tree.nodes)
required={'Idle','Walk','Run','Pickup','Carry','Watering','Hoe','Plant','Wave'}
assert required.issubset({s.action.name.split('.')[0] for t in rig.animation_data.nla_tracks for s in t.strips})
print('BLENDER_ASSET_VERIFICATION_PASS',triangles,len(import_meshes),flush=True)

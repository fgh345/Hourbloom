"""Check the moving right hand against the satchel's enclosing box."""
import bpy,os,json
P=os.path.dirname(os.path.abspath(__file__))
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.join(P,'forest_girl.glb'))
r=next(o for o in bpy.data.objects if o.type=='ARMATURE')
for t in r.animation_data.nla_tracks:t.mute=True
r.animation_data.action=next(a for a in bpy.data.actions if a.name.startswith('Walk'))
start=int(r.animation_data.action.frame_range[0])
hand=[o for o in bpy.data.objects if o.type=='MESH' and o.name.startswith('Hand • R')]
bag=[o for o in bpy.data.objects if o.type=='MESH' and o.name.startswith('Bag •') and o.name not in ['Bag • strap front','Bag • strap back','Bag • shoulder adjuster']]
def bounds(objects,dg):
    vs=[]
    for o in objects:
        e=o.evaluated_get(dg);m=e.to_mesh();vs.extend([e.matrix_world@v.co for v in m.vertices]);e.to_mesh_clear()
    return [(min(v[i] for v in vs),max(v[i] for v in vs)) for i in range(3)]
samples=[]
for frame in range(1,26):
    bpy.context.scene.frame_set(start+frame-1);bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get()
    h=bounds(hand,dg);b=bounds(bag,dg)
    # A positive separating axis is sufficient to show no triangle can intersect.
    separation=max(max(h[i][0]-b[i][1],b[i][0]-h[i][1]) for i in range(3))
    samples.append({'frame':frame,'minimum_separating_gap':separation})
minimum=min(s['minimum_separating_gap'] for s in samples)
print('RIGHT_HAND_BAG_MIN_CLEARANCE',minimum)
assert minimum>.002,'Right hand must clear the satchel in every sampled frame.'
with open(os.path.join(P,'hand_clearance_check.json'),'w') as f:json.dump({'source':'reimported GLB','minimum_separating_gap':minimum,'frames_checked':25,'samples':samples},f,indent=2)

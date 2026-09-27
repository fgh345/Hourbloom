import json, struct, os, math
P=os.path.dirname(os.path.abspath(__file__))
data=open(os.path.join(P,'forest_girl.glb'),'rb').read()
magic,version,total=struct.unpack_from('<III',data)
assert magic==0x46546c67 and version==2 and total==len(data)
n,kind=struct.unpack_from('<II',data,12);doc=json.loads(data[20:20+n]);binary_start=20+n+8
assert doc.get('skins') and len(doc.get('animations',[]))>=2
for a in doc['accessors']:
    if 'bufferView' not in a:continue
    view=doc['bufferViews'][a['bufferView']]
    assert view.get('byteOffset',0)+view['byteLength']<=doc['buffers'][0]['byteLength']
    if a['componentType']==5126:
        comps={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
        start=binary_start+view.get('byteOffset',0)+a.get('byteOffset',0)
        stride=view.get('byteStride',4*comps)
        for i in range(a['count']):assert all(math.isfinite(x) for x in struct.unpack_from('<'+'f'*comps,data,start+i*stride))
report={'file_bytes':len(data),'meshes':len(doc['meshes']),'materials':len(doc.get('materials',[])),'skins':len(doc['skins']),'animations':[{'name':a.get('name'),'channels':len(a['channels'])} for a in doc['animations']],'external_files':[x.get('uri') for x in doc.get('buffers',[])+doc.get('images',[]) if x.get('uri')],'finite_float_data':True}
assert not report['external_files']
open(os.path.join(P,'validation.json'),'w').write(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))

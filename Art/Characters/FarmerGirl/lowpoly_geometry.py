"""Closed, deliberately small silhouette meshes for the second farmer design.
Coordinates are authored in metres, facing -Y. No scene/global deletion occurs.
"""
import math
import bpy
import bmesh
from mathutils import Vector

PALETTE = {'Skin':'F1C6A8','Hair':'5B4031','HairLight':'71503D','Green':'758558','DarkGreen':'536849','Cream':'F1E5C7','Scarf':'C96550','Leather':'795239','Boot':'68452F','Straw':'D9AA62','StrawLight':'EAC182','Gold':'D3AC62'}
RIG_POINTS = {'pelvis':(0,0,.43),'spine_01':(0,0,.51),'spine_02':(0,0,.65),'neck':(0,0,.745),'head':(0,0,.94)}
for _s, _sign in [('L',1),('R',-1)]:
    RIG_POINTS.update({f'shoulder_{_s}':(_sign*.14,0,.67),f'elbow_{_s}':(_sign*.25,0,.57),f'wrist_{_s}':(_sign*.33,0,.48),f'hip_{_s}':(_sign*.075,0,.42),f'knee_{_s}':(_sign*.075,0,.27),f'ankle_{_s}':(_sign*.075,0,.105)})

def build_geometry(scene, collection):
    objects=[]
    mats={}
    for key,h in PALETTE.items():
        mat=bpy.data.materials.new('Blockout_'+key)
        rgb=tuple(int(h[i:i+2],16)/255 for i in (0,2,4))
        mat.diffuse_color=(*rgb,1)
        mat.use_nodes=True
        shader=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
        shader.inputs['Base Color'].default_value=(*rgb,1)
        shader.inputs['Roughness'].default_value=.82
        mats[key]=mat
    def mesh(name,verts,faces,color,bone,smooth=False):
        data=bpy.data.meshes.new(name+'_Mesh');data.from_pydata(verts,[],faces);data.update()
        bm=bmesh.new();bm.from_mesh(data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(data);bm.free()
        ob=bpy.data.objects.new(name,data);collection.objects.link(ob);data.materials.append(mats[color])
        ob['bind_bone']=bone;ob['palette']=color
        for p in data.polygons:p.use_smooth=smooth
        objects.append(ob);return ob
    def sphere(name,c,r,color,bone,n=12,rings=7,smooth=False):
        # Single polar vertices, unlike UV spheres with coincident ring poles.
        vs=[(c[0],c[1],c[2]+r[2])]
        for j in range(1,rings):
            a=math.pi*j/rings
            for i in range(n):
                t=2*math.pi*i/n
                vs.append((c[0]+r[0]*math.sin(a)*math.cos(t),c[1]+r[1]*math.sin(a)*math.sin(t),c[2]+r[2]*math.cos(a)))
        vs.append((c[0],c[1],c[2]-r[2]));bottom=len(vs)-1
        fs=[(0,1+i,1+(i+1)%n) for i in range(n)]
        for j in range(rings-2):
            for i in range(n):
                a=1+j*n+i;b=1+j*n+(i+1)%n
                fs.append((a,a+n,b+n,b))
        fs.extend((bottom,1+(rings-2)*n+(i+1)%n,1+(rings-2)*n+i) for i in range(n))
        return mesh(name,vs,fs,color,bone,smooth)
    def loft(name,levels,color,bone,n=12,smooth=False):
        # levels: centre XYZ, elliptical radii; each end is a closed polygon.
        vs=[]
        for c,rx,ry in levels:
            for i in range(n):
                t=2*math.pi*i/n;vs.append((c[0]+rx*math.cos(t),c[1]+ry*math.sin(t),c[2]))
        fs=[tuple(reversed(range(n)))]
        for j in range(len(levels)-1):
            for i in range(n):fs.append((j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i))
        fs.append(tuple((len(levels)-1)*n+i for i in range(n)))
        return mesh(name,vs,fs,color,bone,smooth)
    def tube(name,a,b,ra,rb,color,bone,n=8):
        axis=(Vector(b)-Vector(a)).normalized();side=axis.cross(Vector((0,1,0))).normalized();other=axis.cross(side)
        vs=[]
        for c,r in [(Vector(a),ra),(Vector(b),rb)]:
            for i in range(n):
                t=i*2*math.pi/n;vs.append(tuple(c+r*(math.cos(t)*side+math.sin(t)*other)))
        fs=[tuple(reversed(range(n))),tuple(range(n,n*2))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
        return mesh(name,vs,fs,color,bone)
    def box(name,c,size,color,bone,bevel=0):
        x,y,z=c;hx,hy,hz=[v/2 for v in size]
        vs=[(x+sx*hx,y+sy*hy,z+sz*hz) for sz in (-1,1) for sy in (-1,1) for sx in (-1,1)]
        ob=mesh(name,vs,[(0,2,3,1),(4,5,7,6),(0,1,5,4),(2,6,7,3),(0,4,6,2),(1,3,7,5)],color,bone)
        if bevel:
            mod=ob.modifiers.new('Soft chunky edges','BEVEL');mod.width=bevel;mod.segments=1
            bpy.context.view_layer.objects.active=ob;ob.select_set(True);bpy.ops.object.modifier_apply(modifier=mod.name);ob.select_set(False)
        return ob
    def ribbon(name,points,width,depth,color,bone):
        # Closed thin solid strip; endpoints never zero width.
        vs=[]
        for x,y,z in points:vs.extend([(x-width/2,y-depth/2,z),(x+width/2,y-depth/2,z),(x+width/2,y+depth/2,z),(x-width/2,y+depth/2,z)])
        fs=[(3,2,1,0)]
        for j in range(len(points)-1):
            for i in range(4):fs.append((j*4+i,j*4+(i+1)%4,(j+1)*4+(i+1)%4,(j+1)*4+i))
        fs.append(tuple((len(points)-1)*4+i for i in range(4)))
        return mesh(name,vs,fs,color,bone)
    # Round cheeks and weak chin, with the flat front used for painted face cards.
    head_mesh=sphere('CHR_Head',(0,0,.925),(.202,.157,.21),'Skin','head',16,15,True)
    for sign,s in [(1,'L'),(-1,'R')]:
        sphere('CHR_Head_Ear_'+s,(sign*.196,-.016,.876),(.027,.019,.044),'Skin','head',8,5,True)
    loft('CHR_Body',[((0,0,.405),.10,.068),((0,0,.52),.096,.066),((0,0,.64),.126,.072),((0,0,.69),.065,.048)],'Cream','spine_01',12,True)
    tube('CHR_Body_Neck',(0,0,.675),(0,0,.765),.035,.038,'Skin','neck',10)
    for sign,s in [(1,'L'),(-1,'R')]:
        shoulder=(sign*.14,0,.67);elbow=(sign*.25,0,.57);wrist=(sign*.33,0,.48)
        tube('CHR_Body_UpperArm_'+s,shoulder,elbow,.036,.031,'Skin','upperarm_'+s,8)
        tube('CHR_Body_Forearm_'+s,elbow,wrist,.031,.023,'Skin','forearm_'+s,8)
        sphere('CHR_Body_Hand_'+s,(sign*.35,-.003,.456),(.027,.022,.044),'Skin','hand_'+s,8,5,True)
        sphere('CHR_Body_Thumb_'+s,(sign*.329,-.018,.455),(.013,.013,.024),'Skin','hand_'+s,6,4)
        tube('CHR_Body_Thigh_'+s,(sign*.075,0,.43),(sign*.075,0,.27),.043,.035,'Skin','thigh_'+s,8)
        tube('CHR_Body_Shin_'+s,(sign*.075,0,.27),(sign*.075,0,.105),.035,.028,'Skin','shin_'+s,8)
        loft('CHR_Boots_'+s,[((sign*.075,-.023,0),.053,.094),((sign*.075,-.023,.025),.055,.096),((sign*.075,-.037,.074),.052,.083),((sign*.075,-.005,.104),.041,.046),((sign*.075,-.002,.18),.042,.046)],'Boot','foot_'+s,8)
        loft('CHR_Boots_Sole_'+s,[((sign*.075,-.023,0),.057,.098),((sign*.075,-.023,.023),.057,.098)],'Leather','foot_'+s,8)
        loft('CHR_Clothes_Sock_'+s,[((sign*.075,0,.169),.045,.048),((sign*.075,0,.215),.041,.044)],'Cream','shin_'+s,8)
    # Cream bell dress; narrow short green jacket is layered above it.
    loft('CHR_Clothes_Dress',[((0,0,.319),.166,.096),((0,0,.345),.161,.092),((0,0,.49),.123,.078),((0,0,.59),.103,.072),((0,0,.682),.112,.073)],'Cream','pelvis',16)
    # Open jacket panels have thickness, closed edge walls rather than open planes.
    for sign,s in [(1,'L'),(-1,'R')]:
        pts=[(sign*.084,-.080,.67),(sign*.075,-.086,.58),(sign*.089,-.091,.46)]
        ribbon('CHR_Clothes_JacketFront_'+s,pts,.077,.014,'Green','spine_02')
        tube('CHR_Clothes_Sleeve_'+s,(sign*.116,0,.673),(sign*.219,0,.596),.052,.047,'Green','upperarm_'+s,8)
        tube('CHR_Clothes_Cuff_'+s,(sign*.218,0,.597),(sign*.263,0,.558),.046,.041,'Cream','forearm_'+s,8)
    ribbon('CHR_Clothes_JacketBack',[(0,.071,.665),(0,.080,.57),(0,.077,.46)],.222,.017,'Green','spine_02')
    # Hair cap plus twelve broad tapered locks, no strands.
    sphere('CHR_Hair_Cap',(0,.026,.972),(.193,.155,.166),'Hair','head',16,8)
    def lock(name,centres,widths,depths,color='Hair'):
        return loft(name,[(c,w,d) for c,w,d in zip(centres,widths,depths)],color,'head',6)
    for i,(x,tip) in enumerate([(-.145,.967),(-.083,.980),(-.025,.974),(.034,.992),(.091,.98)]):
        lock('CHR_Hair_Bang_%02d'%i,[(x,-.099,1.066),(x+.008,-.159,.997),(x-.027,-.165,tip)], [.047,.039,.005],[.038,.020,.009], 'HairLight' if i%2 else 'Hair')
    for sign,s in [(1,'L'),(-1,'R')]:
        lock('CHR_Hair_SideFront_'+s,[(sign*.153,-.076,1.009),(sign*.190,-.099,.930),(sign*.175,-.104,.820)],[.044,.035,.006],[.051,.025,.011])
        lock('CHR_Hair_SideBack_'+s,[(sign*.165,.039,1.019),(sign*.201,.062,.900),(sign*.218,.050,.810)],[.043,.039,.005],[.051,.032,.010])
    for i,x in enumerate([-.135,-.065,0,.067,.137]):
        lock('CHR_Hair_Back_%02d'%i,[(x,.122,1.018),(x,.154,.898),(x+(.018 if i%2 else -.018),.13,.799)],[.043,.044,.007],[.033,.030,.013], 'HairLight' if i%2 else 'Hair')
    # Faceted closed brim ring: inner and outer shell, with slightly upturned edge.
    n=16;vs=[]
    for rx,ry,z in [(.198,.171,1.057),(.283,.237,1.030),(.283,.237,1.048),(.198,.171,1.075)]:
        for i in range(n):
            t=2*math.pi*i/n;vs.append((rx*math.cos(t),ry*math.sin(t),z+.013*math.sin(t)))
    fs=[]
    for j in range(4):
        for i in range(n):fs.append((j*n+i,j*n+(i+1)%n,((j+1)%4)*n+(i+1)%n,((j+1)%4)*n+i))
    mesh('CHR_Hat_Brim',vs,fs,'StrawLight','head')
    loft('CHR_Hat_Crown',[((0,.01,1.061),.195,.166),((0,.01,1.12),.183,.151),((0,.01,1.172),.155,.134),((0,.01,1.20),.11,.101)],'Straw','head',14)
    loft('CHR_Hat_Ribbon',[((0,.01,1.073),.197,.168),((0,.01,1.107),.191,.159)],'Scarf','head',14)
    # Rear red bow and solid ribbon tails.
    for sign,s in [(1,'L'),(-1,'R')]:
        sphere('CHR_Hat_Bow_'+s,(sign*.049,.171,1.077),(.054,.018,.031),'Scarf','head',6,4)
        ribbon('CHR_Hat_BowTail_'+s,[(sign*.024,.17,1.071),(sign*.055,.19,.989),(sign*.077,.188,.92)],.032,.007,'Scarf','head')
    box('CHR_Hat_BowKnot',(0,.188,1.076),(.032,.026,.031),'Scarf','head',.003)
    # Small flower on the character's left hat side, five broad cream petals.
    fc=Vector((.211,-.094,1.074))
    for i in range(5):
        t=2*math.pi*i/5
        c=fc+Vector((.026*math.cos(t),-.004,.026*math.sin(t)))
        sphere('CHR_Accessories_Petal_%d'%i,c,(.018,.010,.023),'Cream','head',6,4)
    sphere('CHR_Accessories_FlowerCentre',fc+Vector((0,-.016,0)),(.014,.009,.014),'Gold','head',8,4)
    for i,(x,z) in enumerate([(.179,1.104),(.238,1.100),(.228,1.043)]):
        sphere('CHR_Accessories_Leaf_%d'%i,(x,-.084,z),(.023,.011,.031),'Green','head',5,3)
    # Collar scarf and two long simple ends.
    loft('CHR_Scarf_Collar',[((0,-.005,.690),.057,.049),((0,-.005,.712),.086,.066),((0,-.005,.745),.074,.057)],'Scarf','neck',10)
    ribbon('CHR_Scarf_FrontTail',[(.047,-.066,.716),(.067,-.10,.638),(.076,-.103,.55)],.041,.010,'Scarf','spine_02')
    ribbon('CHR_Scarf_BackTail',[(.058,.060,.719),(.091,.104,.552),(.122,.105,.375)],.047,.010,'Scarf','spine_02')
    # Crossbody satchel, not a backpack; single flap and simple buckle.
    box('CHR_Backpack_Main',(.143,-.094,.420),(.132,.082,.135),'Leather','pelvis',.008)
    box('CHR_Backpack_Flap',(.143,-.138,.464),(.140,.012,.061),'Leather','pelvis',.004)
    ribbon('CHR_Backpack_Strapping',[(-.098,-.092,.678),(-.020,-.101,.605),(.070,-.106,.528),(.140,-.11,.464)],.023,.007,'Leather','spine_02')
    ribbon('CHR_Backpack_BackStrap',[(-.098,.083,.679),(-.020,.094,.61),(.075,.108,.537),(.145,.012,.475)],.023,.007,'Leather','spine_02')
    box('CHR_Backpack_Buckle',(.143,-.149,.443),(.024,.007,.025),'Gold','pelvis')
    # Clip the actual head triangles rather than approximating them with a grid.
    # This preserves every cheek facet and the head's interpolated smooth normals.
    def face_card(name,xc,zc,width,height,kind):
        head_mesh.data.calc_loop_triangles()
        records=[];index_map={};front=[]
        limits=[(0,xc-width/2,1),(0,xc+width/2,-1),
                (2,zc-height/2,1),(2,zc+height/2,-1)]
        def clipped(poly,axis,bound,sign):
            result=[]
            for a,b in zip(poly,poly[1:]+poly[:1]):
                da=(a[0][axis]-bound)*sign;db=(b[0][axis]-bound)*sign
                if da>=-1e-10:result.append(a)
                if (da>1e-10 and db<-1e-10) or (da<-1e-10 and db>1e-10):
                    t=da/(da-db)
                    result.append((a[0].lerp(b[0],t),a[1].lerp(b[1],t)))
            return result
        def vertex(record):
            # Clipping adjacent Blender float32 triangles can produce sub-micron
            # differences at a shared edge. Weld before deriving shell boundaries.
            for existing,(position,normal) in enumerate(records):
                if (position-record[0]).length<1e-6:
                    return existing
            key=tuple(round(v,9) for v in record[0])
            if key not in index_map:
                index_map[key]=len(records);records.append(record)
            return index_map[key]
        for tri in head_mesh.data.loop_triangles:
            if tri.normal.y>=-.05:continue
            poly=[(head_mesh.data.vertices[i].co.copy(),head_mesh.data.vertices[i].normal.copy()) for i in tri.vertices]
            for axis,bound,sign in limits:
                poly=clipped(poly,axis,bound,sign)
                if len(poly)<3:break
            if len(poly)<3:continue
            ids=[vertex(r) for r in poly]
            for i in range(1,len(ids)-1):
                a,b,c=(records[j][0] for j in (ids[0],ids[i],ids[i+1]))
                if (b-a).cross(c-a).length>1e-10:
                    front.append((ids[0],ids[i],ids[i+1]))
        count=len(records);vs=[]
        for depth in (.0006,.0004):
            vs.extend(tuple(p+n.normalized()*depth) for p,n in records)
        fs=front+[(c+count,b+count,a+count) for a,b,c in front]
        edges={}
        for face in front:
            for a,b in zip(face,face[1:]+face[:1]):
                key=tuple(sorted((a,b)));edges.setdefault(key,[]).append((a,b))
        for edge,uses in edges.items():
            if len(uses)==1:
                a,b=uses[0];fs.append((b,a,a+count,b+count))
        ob=mesh(name,vs,fs,'Skin','head',True);ob[kind]=True
        ob.visible_shadow=False
        # Front normals are exactly the same barycentric interpolation as the head.
        ob.data.normals_split_custom_set([records[loop.vertex_index%count][1].normalized() for loop in ob.data.loops])
        uv=ob.data.uv_layers.new(name='UVMap')
        for loop in ob.data.loops:
            v=records[loop.vertex_index%count][0]
            uv.data[loop.index].uv=((v.x-xc)/width+.5,(v.z-zc)/height+.5)
        return ob
    for sign,s in [(1,'L'),(-1,'R')]:
        eye=face_card('CHR_Eyes_'+s,sign*.083,.900,.095,.120,'eye');eye['eye_side']=s
    face_card('CHR_Mouth',0,.818,.056,.030,'mouth')
    return objects

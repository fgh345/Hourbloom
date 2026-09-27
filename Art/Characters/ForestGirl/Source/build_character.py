import bpy, math, random, os, json
from mathutils import Vector, Matrix
from math import sin, cos, pi, sqrt

OUT=os.path.dirname(os.path.abspath(__file__))
random.seed(12)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for d in bpy.data.materials: bpy.data.materials.remove(d)
CHAR=[]; BIND={}
def material(name,hexcol,roughness=0.85):
    rgb=tuple(int(hexcol[i:i+2],16)/255 for i in (0,2,4))
    # Color inputs are sRGB; Blender expects linear reflectance.
    rgb=tuple(v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in rgb)
    m=bpy.data.materials.new(name);m.diffuse_color=(*rgb,1);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*rgb,1);p.inputs['Roughness'].default_value=roughness;p.inputs['Specular IOR Level'].default_value=.12
    return m
skin=material('Skin • peach','F6BC96'); inner=material('Ears • warm peach','E89576')
cream=material('Linen • warm ivory','F6E2BB'); creamshade=material('Linen • pleats','E5CAA0')
green=material('Jacket • moss','7B884A'); greenlight=material('Jacket • light facets','94A15F'); greendark=material('Jacket • shaded seams','65743E')
red=material('Ribbon • poppy','E44F39'); redlight=material('Ribbon • light','FA7052'); reddark=material('Ribbon • folded','B83A32')
hair=material('Hair • chestnut','634738'); hairlight=material('Hair • amber facets','71513F'); hairdark=material('Hair • depth','533B31')
straw=material('Hat • honey straw','EAB36B'); strawlight=material('Hat • sunlit straw','FFD38C'); strawdark=material('Hat • underside','CE9B5B')
leather=material('Bag and boots • leather','805035'); leatherlight=material('Leather • edges','A57046'); leatherdark=material('Leather • recessed','573B2E')
gold=material('Buckles • brass','D8A64D',.55); sole=material('Soles • caramel','B8894F')
white=material('Eyes • cream white','FFF5DF'); iris=material('Eyes • cocoa','674431'); irislight=material('Eyes • amber','8B5D3E'); black=material('Lashes • espresso','38271F'); shine=material('Eyes • catchlight','FFFFFF'); blush=material('Cheeks • rose','EF9A7C'); mouth=material('Mouth • smile','A44236'); tongue=material('Mouth • coral','F17A61')

def register(o,mat,bone='chest'):
    if mat:o.data.materials.append(mat)
    CHAR.append(o);BIND[o]=bone
    return o
def mesh(name,verts,faces,mat,bone='chest',alts=None):
    d=bpy.data.meshes.new(name);d.from_pydata(verts,[],faces);d.update()
    o=bpy.data.objects.new(name,d);bpy.context.collection.objects.link(o);register(o,mat,bone)
    if alts:
        for m in alts:d.materials.append(m)
        for p in d.polygons:
            if random.random()<.27:p.material_index=random.randrange(len(d.materials))
    return o
def uv(name,loc,scale,mat,bone='chest',seg=20,rings=12,smooth=False):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg,ring_count=rings,location=loc)
    o=bpy.context.object;o.name=name;o.scale=scale
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if smooth:
        for p in o.data.polygons:p.use_smooth=True
    return register(o,mat,bone)
def box(name,loc,scale,mat,bone='chest',bevel=.02):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.name=name;o.dimensions=scale
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    register(o,mat,bone)
    if bevel:
        mod=o.modifiers.new('Soft handmade edges','BEVEL');mod.width=bevel;mod.segments=1
        bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=mod.name)
        o.data.use_auto_smooth=True;mod=o.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL');mod.keep_sharp=True
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return o
def tube(name,points,r,mat,bone='chest',sides=8):
    vs=[]
    for i,p in enumerate(points):
        p=Vector(p);d=Vector(points[min(i+1,len(points)-1)])-Vector(points[max(0,i-1)])
        d.normalize();a=d.cross(Vector((0,1,0)))
        if a.length<.01:a=d.cross(Vector((1,0,0)))
        a.normalize();b=d.cross(a).normalized()
        for j in range(sides):vs.append(p+r*(a*cos(j*2*pi/sides)+b*sin(j*2*pi/sides)))
    fs=[]
    for i in range(len(points)-1):
        for j in range(sides):fs.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
    fs += [tuple(range(sides-1,-1,-1)),tuple((len(points)-1)*sides+j for j in range(sides))]
    return mesh(name,vs,fs,mat,bone)
def limb(name,a,b,r1,r2,mat,bone,sides=10):
    d=Vector(b)-Vector(a);b1=d.normalized().cross(Vector((0,1,0))).normalized();b2=d.normalized().cross(b1)
    vs=[]
    for p,r in [(Vector(a),r1),(Vector(b),r2)]:
        for j in range(sides):vs.append(p+r*(b1*cos(2*pi*j/sides)+b2*sin(2*pi*j/sides)))
    fs=[tuple(range(sides-1,-1,-1)),tuple(sides+j for j in range(sides))]+[(j,(j+1)%sides,(j+1)%sides+sides,j+sides) for j in range(sides)]
    return mesh(name,vs,fs,mat,bone)
def rings(name,rows,n,mat,bone='chest',alts=None):
    vs=[]
    for z,rx,ry in rows:
        for i in range(n):
            a=2*pi*i/n;vs.append((rx*sin(a),-ry*cos(a),z))
    fs=[]
    for k in range(len(rows)-1):
        for i in range(n):fs.append((k*n+i,k*n+(i+1)%n,(k+1)*n+(i+1)%n,(k+1)*n+i))
    fs.extend([tuple(range(n-1,-1,-1)),tuple((len(rows)-1)*n+i for i in range(n))])
    return mesh(name,vs,fs,mat,bone,alts)
def ribbon(name,points,width,mat,bone='chest'):
    vs=[]
    for i,p in enumerate(points):
        vs.extend([(p[0]-width/2,p[1],p[2]),(p[0],p[1]-.025,p[2]+.008),(p[0]+width/2,p[1],p[2])])
    fs=[]
    for i in range(len(points)-1):
        for j in range(2):fs.append((i*3+j,i*3+j+1,(i+1)*3+j+1,(i+1)*3+j))
    o=mesh(name,vs,fs,mat,bone,[redlight,reddark] if mat==red else None)
    mod=o.modifiers.new('Fabric thickness','SOLIDIFY');mod.thickness=.018;bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=mod.name)
    return o

# The body is deliberately short, with a generous bell-shaped linen dress.
body=rings('Dress • fitted bodice',[(1.23,.30,.20),(1.60,.30,.21),(1.92,.35,.22),(2.02,.22,.17)],12,cream)

def skirt_point(a,z):
    t=max(0,min(1,(z-.88)/.63))
    rx=.515-.215*t;ry=.345-.135*t
    fold=(.020*cos(12*a)+.006*cos(5*a+.4))*(1-t)**.65
    return ((rx+fold)*sin(a),-(ry+.65*fold)*cos(a),z+.010*sin(6*a)*max(0,1-t*3))
def skirt_y(x,z,side=-1):
    t=max(0,min(1,(z-.88)/.63));rx=.515-.215*t
    a=math.asin(max(-.98,min(.98,x/rx)))
    for _ in range(4):
        fold=(.020*cos(12*a)+.006*cos(5*a+.4))*(1-t)**.65
        a=math.asin(max(-.995,min(.995,x/(rx+fold))))
    return side*(abs(skirt_point(a,z)[1])+.007)
rows=[.88,.905,.965,1.11,1.30,1.51];n=48
vs=[skirt_point(2*pi*i/n,z) for z in rows for i in range(n)]
fs=[(k*n+i,k*n+(i+1)%n,(k+1)*n+(i+1)%n,(k+1)*n+i) for k in range(len(rows)-1) for i in range(n)]
skirt=mesh('Dress • shaped gathered pleats',vs,fs,cream,'pelvis')
skirt.data.materials.append(creamshade)
for k,f in enumerate(skirt.data.polygons):
    f.material_index=1 if k%n%4==3 else 0
mod=skirt.modifiers.new('Linen thickness','SOLIDIFY');mod.thickness=.009;bpy.context.view_layer.objects.active=skirt;bpy.ops.object.modifier_apply(modifier=mod.name)
for z in [.905,.935]:
    pts=[]
    for i in range(97):
        a=i*2*pi/96;x,y,zz=skirt_point(a,z);pts.append((x*1.009,y*1.009,zz))
    tube('Dress • double stitched hem',pts,.0035,creamshade,'pelvis',5)
for z in [1.52,1.70,1.84]:uv('Dress • covered button',(0,-.222,z),(.016,.009,.016),creamshade,'chest',10,6)
limb('Neck',(0,0,1.95),(0,0,2.22),.13,.14,skin,'chest')

# Open jacket panels follow the dress, leaving the central cream placket visible.
for s,label in [(-1,'L'),(1,'R')]:
    vs=[(s*.105,-.225,1.95),(s*.33,-.14,1.96),(s*.39,-.17,1.56),(s*.425,-.26,1.15),(s*.245,-.308,1.17),(s*.18,-.26,1.58),
        (s*.28,.20,1.96),(s*.38,.24,1.54),(s*.44,.26,1.18)]
    mesh('Jacket • '+label+' front',vs,[(0,1,2,5),(5,2,3,4),(1,6,7,2),(2,7,8,3)],green,'chest',[greenlight,greendark])
    tube('Jacket • '+label+' opening seam',[(s*.11,-.237,1.93),(s*.18,-.273,1.57),(s*.247,-.321,1.17)],.008,greendark)
    # Folded lapels and a turned edge give the jacket visible fabric thickness.
    mesh('Jacket • '+label+' folded lapel',[(s*.12,-.241,1.94),(s*.235,-.204,1.93),(s*.235,-.29,1.78),(s*.185,-.296,1.71)],[(0,1,2),(0,2,3)],greenlight,'chest')
    tube('Jacket • '+label+' turned lower hem',[(s*.248,-.319,1.178),(s*.33,-.306,1.166),(s*.423,-.269,1.154)],.009,greenlight)
    for k in range(5):
        x=s*(.272+k*.025);z=1.192-k*.003
        tube('Jacket • '+label+' hem stitch',[(x,-.32+k*.008,z),(x+s*.009,-.32+k*.008,z)],.0028,creamshade,'chest',4)
mesh('Jacket • back',[(-.28,.205,1.96),(.28,.205,1.96),(-.38,.245,1.54),(.38,.245,1.54),(-.44,.265,1.18),(.44,.265,1.18),(0,.285,1.18),(0,.253,1.6)],[(0,1,3,7,2),(2,7,6,4),(7,3,5,6)],green,'chest',[greenlight])

tube('Jacket • back center seam',[(0,.217,1.93),(0,.268,1.60),(0,.292,1.20)],.005,greendark)

# Arms held in a gentle A pose; hand silhouettes include individual fingers.
for s,label in [(-1,'L'),(1,'R')]:
    shoulder=(s*.30,0,1.89);elbow=(s*.58,-.01,1.60);wrist=(s*.73,-.04,1.40)
    limb('Jacket • '+label+' shoulder',shoulder,(s*.42,-.004,1.77),.128,.185,green,'upper_arm.'+label)
    limb('Jacket • '+label+' sleeve',(s*.42,-.004,1.77),elbow,.185,.158,green,'upper_arm.'+label)
    limb('Jacket • '+label+' sleeve piping',(s*.535,-.008,1.655),(s*.58,-.01,1.60),.165,.165,greenlight,'upper_arm.'+label)
    limb('Linen • '+label+' cuff',(s*.57,-.01,1.61),(s*.675,-.026,1.46),.150,.153,cream,'forearm.'+label)
    limb('Linen • '+label+' rolled cuff edge',(s*.654,-.023,1.493),(s*.683,-.029,1.45),.157,.155,creamshade,'forearm.'+label)
    limb('Arm • '+label,(s*.64,-.03,1.50),wrist,.093,.076,skin,'forearm.'+label)
    uv('Hand • '+label,(s*.77,-.048,1.36),(.102,.064,.12),skin,'hand.'+label,12,8)
    for j in range(4):
        a=(s*(.724+j*.035),-.053,1.32);b=(s*(.752+j*.041),-.059,1.235+(abs(j-1.5)*.017))
        limb('Hand • '+label+' finger '+str(j),a,b,.025,.017,skin,'hand.'+label,6)
    limb('Hand • '+label+' thumb',(s*.708,-.065,1.37),(s*.68,-.09,1.285),.034,.025,skin,'hand.'+label,7)
    x=s*.245
    leg=rings('Leg • '+label,[(.44,.082,.078),(.57,.086,.081),(.65,.092,.084),(.70,.095,.089),(.75,.098,.091),(.87,.104,.095),(1.13,.111,.102)],12,skin,'shin.'+label)
    leg.location.x=x
    limb('Socks • '+label,(x,-.005,.57),(x,-.014,.39),.121,.118,cream,'shin.'+label)
    limb('Boot • '+label+' shaft',(x,0,.42),(x,-.012,.18),.145,.14,leather,'foot.'+label)
    box('Boot • '+label+' rounded toe',(x,-.105,.14),(.35,.45,.23),leather,'foot.'+label,.065)
    box('Boot • '+label+' sole',(x,-.105,.043),(.365,.468,.085),sole,'foot.'+label,.022)
    box('Boot • '+label+' tongue',(x,-.137,.31),(.16,.04,.25),leatherdark,'foot.'+label,.015)
    for side in [-1,1]:
        mesh('Boot • '+label+' leather lace facing',[(x+side*.060,-.176,.20),(x+side*.135,-.12,.205),(x+side*.13,-.12,.423),(x+side*.060,-.176,.42)],[(0,1,2,3)],leatherlight,'foot.'+label)
    for z in [.27,.34]:
        for d in [-1,1]:
            tube('Boot • '+label+' cross lace',[(x-d*.099,-.155,z+.035),(x,-.192,z),(x+d*.099,-.155,z-.035)],.009,gold,'foot.'+label,6)
    for side in [-1,1]:
        tube('Boot • '+label+' bow lace',[(x+side*.099,-.155,.375),(x,-.196,.392),(x+side*.049,-.20,.419),(x+side*.061,-.20,.388),(x,-.196,.392),(x+side*.025,-.199,.342)],.007,gold,'foot.'+label,6)

    # Leather eyelets, tongue loops, and stacked sole edges.
    for z in [.235,.305,.375]:
        for side in [-1,1]:
            cx=x+side*.099
            tube('Boot • '+label+' brass eyelet',[(cx+.014*cos(j*pi/4),-.181+(abs(cx+.014*cos(j*pi/4)-x)-.060)/.075*.056,z+.014*sin(j*pi/4)) for j in range(9)],.0037,gold,'foot.'+label,5)
    tube('Boot • '+label+' cuff rim',[(x+.147*sin(j*2*pi/16),-.001-.147*cos(j*2*pi/16),.418) for j in range(17)],.009,leatherdark,'foot.'+label,6)
    tube('Boot • '+label+' pull loop',[(x-.027,.132,.37),(x-.027,.14,.48),(x+.027,.14,.48),(x+.027,.132,.37)],.012,leatherlight,'foot.'+label,6)
    for side in [-1,1]:
        tube('Boot • '+label+' toe stitch',[(x+side*.148,-.27,.15),(x+side*.116,-.303,.17),(x+side*.047,-.324,.174)],.0045,leatherlight,'foot.'+label,5)

# The clover motifs conform to the pleated skirt instead of floating above it.
def embroidered_leaf(name,x,z,rx,rz,angle,side):
    coords=[]
    for j in range(16):
        a=j*2*pi/16;dx=rx*cos(a);dz=rz*sin(a)
        xx=x+dx*cos(angle)-dz*sin(angle);zz=z+dx*sin(angle)+dz*cos(angle)
        coords.append((xx,skirt_y(xx,zz,side),zz))
    center=(x,skirt_y(x,z,side),z)
    faces=[(0,j+1,(j+1)%16+1) if side<0 else (0,(j+1)%16+1,j+1) for j in range(16)]
    return mesh(name,[center]+coords,faces,green,'pelvis')
for side in [-1,1]:
    for x,z,size in [(-.345,1.055,.046),(-.126,1.081,.054),(.105,1.037,.047),(.323,1.076,.051)]:
        for dx,dz,angle in [(-.62,.05,-.55),(.62,.05,.55),(0,.80,0)]:
            embroidered_leaf('Dress • embroidered clover',x+dx*size,z+dz*size,size*.57,size*.84,angle,side)
        tube('Dress • clover stalk',[(x,skirt_y(x,z,side),z),(x+.007,skirt_y(x+.007,z-.07,side),z-.07)],.004,green,'pelvis',5)
    for j in range(13):
        x=-.405+j*.064;z=.954+.005*sin(j)
        embroidered_leaf('Dress • tiny border leaves',x,z,.017,.006,(-1)**j*.2,side)

# V2: shaped cheeks and a flatter face, with a short chin and generous forehead.
HEAD_ROWS=[(2.055,.065,.14),(2.095,.245,.23),(2.165,.375,.305),
           (2.26,.474,.352),(2.40,.535,.378),(2.56,.553,.392),
           (2.75,.54,.404),(2.93,.474,.369),(3.065,.32,.26),(3.135,.055,.045)]
def face_section(z):
    for i in range(len(HEAD_ROWS)-1):
        a,b=HEAD_ROWS[i:i+2]
        if z<=b[0]:
            t=max(0,min(1,(z-a[0])/(b[0]-a[0])))
            return a[1]+t*(b[1]-a[1]),a[2]+t*(b[2]-a[2])
    return HEAD_ROWS[-1][1:]
dense_rows=[]
for i in range(len(HEAD_ROWS)-1):
    a,b=HEAD_ROWS[i:i+2]
    for k in range(4):
        z=a[0]+(b[0]-a[0])*k/4;rx,ry=face_section(z);dense_rows.append((z,rx,ry))
dense_rows.append(HEAD_ROWS[-1])
vs=[];n=96
for z,rx,ry in dense_rows:
    for i in range(n):
        a=2*pi*i/n;c=cos(a)
        vs.append((rx*sin(a),-.008-ry*(1 if c>=0 else -1)*abs(c)**.68,z))
fs=[(k*n+i,k*n+(i+1)%n,(k+1)*n+(i+1)%n,(k+1)*n+i) for k in range(len(dense_rows)-1) for i in range(n)]
fs += [tuple(range(n-1,-1,-1)),tuple((len(dense_rows)-1)*n+i for i in range(n))]
painted_skin=material('Skin • painted cheeks','FFFFFF')
vc=painted_skin.node_tree.nodes.new('ShaderNodeVertexColor');vc.layer_name='SkinTint'
painted_skin.node_tree.links.new(vc.outputs['Color'],painted_skin.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
head_obj=mesh('Head • shaped cheeks and short chin',vs,fs,painted_skin,'head')
attr=head_obj.data.color_attributes.new(name='SkinTint',type='FLOAT_COLOR',domain='POINT')
for v in head_obj.data.vertices:
    r2=((abs(v.co.x)-.353)/.080)**2+((v.co.z-2.306)/.049)**2
    amount=.55*math.exp(-2.2*r2) if v.co.y<-.16 else 0
    srgb=[a+(b-a)*amount for a,b in zip((246/255,188/255,150/255),(239/255,130/255,105/255))]
    rgb=[c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in srgb]
    attr.data[v.index].color=(*rgb,1)
for f in head_obj.data.polygons:f.use_smooth=True
for side in [-1,1]:
    uv('Ear',(side*.530,-.008,2.335),(.084,.068,.12),skin,'head',16,10,True)
    uv('Ear • inner',(side*.549,-.068,2.343),(.042,.013,.068),inner,'head',12,8,True)
def face_y(x,z,off=.009):
    rx,ry=face_section(z)
    return -.008-ry*max(.018,1-(x/rx)**2)**.34-(.0018+off*.12)
def patch(name,coords,mat,off=.012):
    c=(sum(x for x,z in coords)/len(coords),sum(z for x,z in coords)/len(coords))
    vs=[(c[0],face_y(*c,off),c[1])];n=len(coords)
    for r in [.20,.40,.60,.80,1.0]:
        for x,z in coords:
            xx=c[0]+r*(x-c[0]);zz=c[1]+r*(z-c[1]);vs.append((xx,face_y(xx,zz,off),zz))
    fs=[(0,1+i,1+(i+1)%n) for i in range(n)]
    for k in range(4):
        for i in range(n):fs.append((1+k*n+i,1+(k+1)*n+i,1+(k+1)*n+(i+1)%n,1+k*n+(i+1)%n))
    o=mesh(name,vs,fs,mat,'head')
    for f in o.data.polygons:f.use_smooth=True
    return o
def ellipse(name,x,z,rx,rz,mat,off=.012,n=32):
    return patch(name,[(x+rx*cos(2*pi*i/n),z+rz*sin(2*pi*i/n)) for i in range(n)],mat,off)
for side in [-1,1]:
    x=side*.231
    # No dark enclosing ring: only the upper lid is outlined.
    ellipse('Eye • ivory',x,2.461,.109,.145,white,.016)
    ellipse('Eye • cocoa iris',x+side*.004,2.452,.075,.119,iris,.027)
    ellipse('Eye • amber lower iris',x+side*.004,2.407,.058,.064,irislight,.035)
    ellipse('Eye • dark pupil',x+side*.004,2.466,.033,.086,black,.044)
    ellipse('Eye • main reflection',x-.022,2.525,.020,.025,shine,.056,20)
    ellipse('Eye • lower reflection',x+.028,2.399,.008,.011,shine,.056,14)
    coords=[(x+t*.111,2.465+.145*sqrt(max(0,1-t*t))) for t in [-1,-.85,-.6,-.3,0,.3,.6,.85,1]]
    tube('Eye • fine upper lashes',[(a,face_y(a,b,.055),b) for a,b in coords],.009,black,'head',6)
    coords=[(x+t*.086,2.682+.020*(1-t*t)) for t in [-1,-.5,0,.5,1]]
    tube('Eyebrow',[(a,face_y(a,b,.025),b) for a,b in coords],.009,hair,'head',6)
ellipse('Nose • subtle warmth',0,2.341,.012,.011,inner,.018,16)
patch('Mouth • open smiling contour',[(-.093,2.284),(-.05,2.293),(0,2.292),(.05,2.293),(.093,2.284),(.083,2.221),(.050,2.176),(0,2.163),(-.050,2.176),(-.083,2.221)],mouth,.018)
patch('Mouth • coral interior',[(-.070,2.221),(-.04,2.238),(0,2.242),(.04,2.238),(.070,2.221),(.044,2.184),(0,2.176),(-.044,2.184)],tongue,.031)

# Crown volume with a jagged bob line behind the ears.
n=28;vs=[]
for t in [i/16 for i in range(17)]:
    for i in range(n):
        a=2*pi*i/n;end=1.12+1.15*min(1,(abs(sin(a/2))/.70)**3);theta=.03+(end-.03)*t
        z=2.59+.60*cos(theta);rx,ry=face_section(min(z,3.134));c=cos(a)
        if z>3.13: rx=ry=max(.005,.115*(3.19-z)/.06)
        vs.append(((rx+.035)*sin(a),-.008-(ry+.044)*(1 if c>=0 else -1)*abs(c)**.68,z))
fs=[(k*n+i,(k+1)*n+i,(k+1)*n+(i+1)%n,k*n+(i+1)%n) for k in range(16) for i in range(n)]
mesh('Hair • continuous crown',vs,fs,hair,'head',[hairlight])
def lock(name,points,widths,mat=hair,normal=(0,-1,0),depth=.033):
    # Closed tapered volumes follow the scalp; the ridge is restrained.
    normal=Vector(normal).normalized();vs=[]
    for i,(p,w) in enumerate(zip(points,widths)):
        p=Vector(p);t=Vector(points[min(i+1,len(points)-1)])-Vector(points[max(i-1,0)])
        across=normal.cross(t).normalized();w=max(w,.001)
        vs.extend([p-across*w/2,p+normal*depth,p+across*w/2,p-normal*.025])
    fs=[(3,2,1,0)]
    for k in range(len(points)-1):
        for j in range(4):fs.append((k*4+j,k*4+(j+1)%4,(k+1)*4+(j+1)%4,(k+1)*4+j))
    fs.append(tuple((len(points)-1)*4+j for j in range(4)))
    o=mesh(name,vs,fs,mat,'head')
    o.data.materials.append(hairlight);o.data.materials.append(hairdark)
    for i,f in enumerate(o.data.polygons):
        if i and i<len(o.data.polygons)-1:f.material_index=1 if (i-1)%4==0 else (2 if (i-1)%4>=2 else 0)
    return o
lock('Hair • center sweeping bang',[(.02,-.30,3.13),(.015,-.424,2.98),(-.02,-.438,2.81),(-.10,-.432,2.65),(-.17,-.422,2.56)],[.20,.25,.235,.135,0])
lock('Hair • left outer bang',[(-.20,-.26,3.11),(-.295,-.36,2.96),(-.355,-.389,2.76),(-.405,-.347,2.62),(-.495,-.292,2.54)],[.16,.24,.235,.14,0])
lock('Hair • right sweeping bang',[(.23,-.265,3.10),(.28,-.383,2.96),(.315,-.421,2.81),(.363,-.397,2.67),(.44,-.344,2.55)],[.17,.235,.22,.145,0])
lock('Hair • slim center part',[(.155,-.32,3.075),(.17,-.425,2.91),(.176,-.441,2.76),(.208,-.422,2.665)],[.09,.12,.08,0],hair,depth=.02)
for side in [-1,1]:
    lock('Hair • cheek framing lock',[(side*.465,-.215,2.95),(side*.50,-.282,2.73),(side*.472,-.312,2.49),(side*.457,-.286,2.30),(side*.442,-.244,2.15)],[.14,.17,.145,.10,0],normal=(side*.35,-1,0),depth=.027)
    lock('Hair • outward upper tuft',[(side*.49,.015,2.71),(side*.559,-.021,2.52),(side*.63,-.060,2.39),(side*.695,-.07,2.34)],[.16,.17,.10,0],normal=(side, -.3,0))
    lock('Hair • outward lower tuft',[(side*.49,.10,2.48),(side*.56,.08,2.29),(side*.615,.01,2.15)],[.17,.17,0],normal=(side,-.1,0))
for i in range(11):
    a=pi/2+(i+.25)*pi/11;nor=(sin(a),-cos(a),0)
    shift=.06*sin(i*2.3)
    lock('Hair • layered back bob '+str(i),[(.49*sin(a),.03-.385*cos(a),2.87),(.57*sin(a),.03-.456*cos(a),2.55),(.565*sin(a+shift),.03-.44*cos(a+shift),2.30),(.585*sin(a+shift),.03-.44*cos(a+shift),2.105+.055*sin(i*2.1))],[.13,.19,.16,0],normal=nor,depth=.03)

# Hat geometry is generated in its own tilted local coordinates.
hat_start=len(CHAR)
rings('Hat • broad irregular brim',[(0,1.00,.80),(.032,1.01,.81),(.105,.82,.655),(.145,.575,.48)],24,straw,'head',[strawlight])
rings('Hat • shaded brim underside',[(-.026,1.0,.80),(0,1.0,.80),(.108,.57,.47)],24,strawdark,'head')
rings('Hat • domed crown',[(.12,.576,.481),(.26,.55,.46),(.43,.445,.371),(.545,.28,.235),(.578,.07,.059)],20,straw,'head',[strawlight])
rings('Hat • scarlet grosgrain band',[(.145,.584,.49),(.267,.557,.467)],20,red,'head',[redlight])
rings('Hat • bound brim edge',[(-.007,1.014,.814),(.035,1.024,.824),(.065,.967,.777)],24,strawlight,'head')
# Rear hanging loop and bow.
tube('Hat • hanging loop',[(-.15,.11,.55),(-.14,.11,.75),(0,.11,.82),(.15,.11,.75),(.16,.11,.55)],.037,leather,'head',6)
mesh('Hat • bow left',[(-.05,.505,.20),(-.31,.59,.32),(-.38,.60,.10),(-.08,.53,.14),(-.21,.64,.20)],[(0,1,4),(1,2,4),(2,3,4),(3,0,4)],red,'head',[redlight,reddark])
mesh('Hat • bow right',[(.05,.505,.20),(.31,.59,.32),(.38,.60,.10),(.08,.53,.14),(.21,.64,.20)],[(0,4,1),(1,4,2),(2,4,3),(3,4,0)],red,'head',[redlight,reddark])
box('Hat • bow knot',(0,.565,.20),(.16,.13,.15),red,'head',.025)
ribbon('Hat • ribbon tail left',[(-.10,.57,.15),(-.13,.71,-.08),(-.20,.75,-.43)],.16,red,'head')
ribbon('Hat • ribbon tail right',[(.1,.57,.15),(.22,.73,-.08),(.32,.74,-.39)],.16,red,'head')
hat_matrix=Matrix.Translation((0,.035,3.00)) @ Matrix.Rotation(math.radians(-39),4,'X')
for o in CHAR[hat_start:]:o.matrix_world=hat_matrix @ o.matrix_world

# Five-petal flower and olive leaves on the viewer's right of the hat.
flower=(.82,-.45,3.23)
for dx,dz in [(-.10,.19),(.15,.14),(.16,-.13)]:
    x,y,z=flower;mesh('Hat • folded olive leaf',[(x,y+.025,z),(x+dx-.055,y+.035,z+dz*.65),(x+dx,y+.06,z+dz),(x+dx+.055,y+.035,z+dz*.65),(x+dx*.60,y-.025,z+dz*.65)],[(0,1,4),(1,2,4),(2,3,4),(3,0,4)],green,'head',[greenlight])
for j in range(5):
    a=2*pi*j/5; x=flower[0]+sin(a)*.084;z=flower[2]+cos(a)*.084
    o=uv('Hat • ivory flower petal',(x,flower[1]-.043,z),(.053,.022,.085),cream,'head',12,8);o.rotation_euler[1]=a
uv('Hat • flower golden heart',(flower[0],flower[1]-.073,flower[2]),(.048,.025,.048),gold,'head',12,8)

# Layered neck scarf with a diagonal front fold and two hanging ends.
rings('Scarf • wrapped collar',[(1.925,.22,.185),(1.99,.275,.208),(2.08,.235,.175),(2.105,.17,.14)],12,red,'chest',[redlight,reddark])
mesh('Scarf • diagonal folded front',[(-.26,-.145,2.01),(-.12,-.244,1.935),(.08,-.255,1.91),(.275,-.12,2.025),(.19,-.204,2.077),(-.015,-.251,1.988),(-.22,-.19,2.071)],[(0,1,5,6),(1,2,3,4,5)],redlight,'chest',[red])
ribbon('Scarf • short front end',[(.15,-.235,1.975),(.165,-.281,1.79),(.19,-.282,1.64)],.145,red)
ribbon('Scarf • long left back end',[(-.13,.205,1.98),(-.34,.27,1.50),(-.49,.25,1.05),(-.57,.21,.89)],.16,red)
ribbon('Scarf • long right back end',[(.12,.205,1.98),(.25,.295,1.58),(.42,.30,1.07)],.145,red)
for j in range(5):
    a=j*2*pi/5;uv('Scarf • embroidered daisy',(.19+.026*sin(a),-.333,1.698+.026*cos(a)),(.016,.005,.021),cream,'chest',8,6)

uv('Scarf • embroidered golden center',(.19,-.34,1.698),(.012,.006,.012),gold,'chest',10,6)

# Cross-body strap and satchel: solid construction, flap, stitches and brass hardware.
tube('Bag • strap front',[(-.23,-.208,1.93),(-.15,-.28,1.80),(.07,-.302,1.58),(.31,-.32,1.34),(.44,-.31,1.23)],.044,leather)
tube('Bag • strap back',[(-.23,.235,1.92),(-.06,.292,1.75),(.17,.32,1.52),(.43,.29,1.27),(.55,.05,1.23),(.53,-.21,1.24)],.04,leather)
bag=box('Bag • satchel body',(.47,-.225,1.14),(.39,.235,.40),leather,'pelvis',.035)
box('Bag • side gusset',(.655,-.213,1.125),(.035,.19,.325),leatherdark,'pelvis',.012)
box('Bag • front inset',(.47,-.355,1.13),(.31,.025,.30),leatherlight,'pelvis',.012)
box('Bag • overlapping flap',(.47,-.363,1.29),(.40,.050,.16),leather,'pelvis',.017)
box('Bag • fastening strap',(.47,-.397,1.205),(.071,.026,.22),leatherdark,'pelvis',.009)
def buckle(name,x,y,z,w,h,bone='chest',angle=0):
    pts=[]
    for dx,dz in [(-w/2,-h/2),(-w/2,h/2),(w/2,h/2),(w/2,-h/2),(-w/2,-h/2)]:pts.append((x+dx*cos(angle)+dz*sin(angle),y,z-dx*sin(angle)+dz*cos(angle)))
    tube(name,pts,.012,gold,bone,6)
buckle('Bag • brass clasp',.47,-.423,1.245,.10,.10,'pelvis')
buckle('Bag • shoulder adjuster',-.16,-.327,1.815,.094,.115,'chest',-.70)
for x in [.31,.63]:
    for z in [1.02,1.07,1.12,1.17]:tube('Bag • hand stitch',[(x,-.373,z),(x,-.374,z+.021)],.0035,creamshade,'pelvis',4)

tube('Bag • front leather piping',[(.31,-.377,1.01),(.31,-.377,1.265),(.34,-.377,1.285),(.60,-.377,1.285),(.63,-.377,1.26),(.63,-.377,1.01),(.60,-.377,.985),(.34,-.377,.985),(.31,-.377,1.01)],.0075,leatherlight,'pelvis',6)
box('Bag • side pocket',(.666,-.213,1.10),(.035,.15,.20),leather,'pelvis',.016)
bag_tilt=Matrix.Translation((.47,-.225,1.14)) @ Matrix.Rotation(math.radians(-8),4,'Y') @ Matrix.Translation((-.47,.225,-1.14))
for o in CHAR:
    if o.name.startswith('Bag •') and BIND[o]=='pelvis':o.matrix_world=bag_tilt @ o.matrix_world

# A deforming armature, with separate limb joints and a subtle in-place walk cycle.
bpy.ops.object.armature_add(enter_editmode=True,location=(0,0,0));rig=bpy.context.object;rig.name='Forest_Girl_Rig';arm=rig.data;arm.name='Forest_Girl_Skeleton';arm.edit_bones.remove(arm.edit_bones[0])
def bone(n,h,t,parent=None):
    b=arm.edit_bones.new(n);b.head=h;b.tail=t
    if parent:b.parent=arm.edit_bones[parent]
bone('root',(0,0,0),(0,0,.25));bone('pelvis',(0,0,1.12),(0,0,1.42),'root');bone('chest',(0,0,1.42),(0,0,2.03),'pelvis');bone('head',(0,0,2.03),(0,0,2.84),'chest')
for s,l in [(-1,'L'),(1,'R')]:
    bone('thigh.'+l,(s*.245,0,1.15),(s*.245,0,.70),'pelvis');bone('shin.'+l,(s*.245,0,.70),(s*.245,0,.22),'thigh.'+l);bone('foot.'+l,(s*.245,0,.22),(s*.245,-.23,.12),'shin.'+l)
    bone('upper_arm.'+l,(s*.30,0,1.89),(s*.58,-.01,1.60),'chest');bone('forearm.'+l,(s*.58,-.01,1.60),(s*.73,-.04,1.40),'upper_arm.'+l);bone('hand.'+l,(s*.73,-.04,1.40),(s*.79,-.05,1.27),'forearm.'+l)
bpy.ops.object.mode_set(mode='OBJECT');rig.show_in_front=True
for o in CHAR:
    n=BIND[o]
    if o.type!='MESH':continue
    # World-space mesh coordinates simplify robust vertex weighting and export.
    o.data.transform(o.matrix_world);o.matrix_world=Matrix.Identity(4)
    if o.name.startswith('Leg •'):
        l=n.split('.')[-1];gt=o.vertex_groups.new(name='thigh.'+l);gs=o.vertex_groups.new(name='shin.'+l)
        for v in o.data.vertices:
            w=max(0,min(1,(v.co.z-.655)/.09));gt.add([v.index],w,'REPLACE');gs.add([v.index],1-w,'REPLACE')
    else:o.vertex_groups.new(name=n).add(list(range(len(o.data.vertices))),1,'REPLACE')
    mod=o.modifiers.new('Forest girl skin','ARMATURE');mod.object=rig;o.parent=rig
for p in rig.pose.bones:p.rotation_mode='XYZ'
scene=bpy.context.scene;scene.render.fps=24
def reset_pose():
    for p in rig.pose.bones:p.rotation_euler=(0,0,0);p.location=(0,0,0)
def keyall(f):
    for p in rig.pose.bones:
        p.keyframe_insert('rotation_euler',frame=f,group=p.name);p.keyframe_insert('location',frame=f,group=p.name)
rig.animation_data_create();rig.animation_data.action=bpy.data.actions.new('Idle')
for f in [1,13,25,37,49]:
    reset_pose();t=(f-1)/48*2*pi;rig.pose.bones['chest'].rotation_euler[0]=.014*sin(t);rig.pose.bones['head'].rotation_euler[2]=.018*sin(t);keyall(f)
idle=rig.animation_data.action
rig.animation_data.action=bpy.data.actions.new('Walk')
walk_targets={}
for f in range(1,26):
    reset_pose();cycle=(f-1)/24;t=cycle*2*pi
    hip_offset=-.055+.010*cos(2*t)
    rig.pose.bones['pelvis'].location[1]=hip_offset
    rig.pose.bones['chest'].rotation_euler[1]=.023*sin(t)
    rig.pose.bones['chest'].rotation_euler[2]=.010*cos(t)
    rig.pose.bones['head'].rotation_euler[1]=-.014*sin(t)
    walk_targets[f]={}
    for side,l in [(-1,'L'),(1,'R')]:
        phase=(cycle+(0 if l=='L' else .5))%1
        if phase<.58:
            u=phase/.58;fy=-.22+.44*u;lift=0;pitch=0;stance=True
        else:
            u=(phase-.58)/.42;fy=.22*cos(pi*u);lift=.10*sin(pi*u);pitch=-.12*sin(pi*u)*(2*u-1);stance=False
        fz=.22+lift;dz=fz-(1.15+hip_offset);dist=sqrt(fy*fy+dz*dz)
        l1,l2=.45,.48
        theta=math.atan2(fy,-dz)
        alpha=theta-math.acos(max(-1,min(1,(l1*l1+dist*dist-l2*l2)/(2*l1*dist))))
        beta=math.acos(max(-1,min(1,(dist*dist-l1*l1-l2*l2)/(2*l1*l2))))
        rig.pose.bones['thigh.'+l].rotation_euler[0]=alpha
        rig.pose.bones['shin.'+l].rotation_euler[0]=beta
        rig.pose.bones['foot.'+l].rotation_euler[0]=pitch-alpha-beta
        # Rotate around character-space axes, not each diagonal arm bone's local X.
        arm_rest=arm.bones['upper_arm.'+l].matrix_local.to_3x3()
        outward=-.18 if l=='R' else -.25
        swing=(.18 if l=='R' else .24)*cos(2*pi*phase)
        world_rotation=Matrix.Rotation(outward,3,'Y') @ Matrix.Rotation(swing,3,'X')
        rig.pose.bones['upper_arm.'+l].rotation_euler=(arm_rest.inverted() @ world_rotation @ arm_rest).to_euler('XYZ')
        fore_rest=arm.bones['forearm.'+l].matrix_local.to_3x3()
        rig.pose.bones['forearm.'+l].rotation_euler=(fore_rest.inverted() @ Matrix.Rotation(-.07,3,'X') @ fore_rest).to_euler('XYZ')
        walk_targets[f][l]={'position':[side*.245,fy,fz],'stance':stance}
    keyall(f)
walk=rig.animation_data.action
for a in [idle,walk]:
    a.use_fake_user=True
    for fc in a.fcurves:
        for k in fc.keyframe_points:k.interpolation='BEZIER'
# Check the analytic leg solution against Blender's actual bone transforms.
rig.animation_data.action=walk
contact_report=[]
for f in range(1,26):
    scene.frame_set(f);bpy.context.view_layer.update()
    for l in ['L','R']:
        actual=rig.pose.bones['foot.'+l].head
        target=Vector(walk_targets[f][l]['position'])
        err=(actual-target).length
        contact_report.append({'frame':f,'leg':l,'stance':walk_targets[f][l]['stance'],'ankle_error':err,'ankle_z':actual.z})
max_err=max(x['ankle_error'] for x in contact_report)
print('WALK_ANKLE_MAX_ERROR',max_err)
assert max_err<.002, 'Foot IK must match the target before export.'
with open(os.path.join(OUT,'walk_contact_check.json'),'w') as f:json.dump({'max_ankle_error':max_err,'nominal_forward_speed':.44/.58,'samples':contact_report},f,indent=2)
for fc in walk.fcurves:
    for k in fc.keyframe_points:k.interpolation='LINEAR'
rig.animation_data.action=None
for a in [idle,walk]:
    tr=rig.animation_data.nla_tracks.new();tr.name=a.name;st=tr.strips.new(a.name,1,a);tr.mute=True
reset_pose();scene.frame_set(1)

# Studio lighting exists only in the .blend and previews; GLB exports character only.
scene.render.engine='CYCLES';scene.cycles.samples=96;scene.cycles.use_denoising=False
scene.render.threads_mode='FIXED';scene.render.threads=8
scene.world.color=(.6,.6,.6);scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.72,.77,.83,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.65
floor_mat=material('Studio • warm paper','EEE9DD');bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.005));floor=bpy.context.object;floor.name='STUDIO • ground';floor.data.materials.append(floor_mat)
def area(name,loc,power,size):
    bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.name=name;o.data.energy=power;o.data.shape='DISK';o.data.size=size;o.rotation_euler=(Vector((0,0,1.8))-o.location).to_track_quat('-Z','Y').to_euler()
area('STUDIO • large softbox',(-3,-4,7),171,4);area('STUDIO • fill',(4,-1,4),95,3);area('STUDIO • rim',(1,4,6),190,3)
bpy.ops.object.camera_add();cam=bpy.context.object;cam.name='STUDIO • portrait camera';cam.data.type='ORTHO';cam.data.ortho_scale=4.40;scene.camera=cam
def camera(loc,target=(0,0,1.87)):
    cam.location=loc;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler()
scene.render.resolution_x=900;scene.render.resolution_y=1050;scene.render.resolution_percentage=75 if os.environ.get('CHARACTER_DRAFT') else 100
scene.view_settings.view_transform='Standard';scene.view_settings.look='None';scene.view_settings.exposure=.15;scene.view_settings.gamma=1
scene.render.image_settings.file_format='PNG';scene.render.film_transparent=True
floor.is_shadow_catcher=True
scene.use_nodes=True;nt=scene.node_tree;nt.nodes.clear()
rl=nt.nodes.new('CompositorNodeRLayers');bg=nt.nodes.new('CompositorNodeRGB');bg.outputs[0].default_value=(1.0,.985,.96,1)
over=nt.nodes.new('CompositorNodeAlphaOver');nt.links.new(bg.outputs[0],over.inputs[1]);nt.links.new(rl.outputs['Image'],over.inputs[2]);out=nt.nodes.new('CompositorNodeComposite');nt.links.new(over.outputs[0],out.inputs[0])
camera((4,-8,4.0));scene.render.filepath=os.path.join(OUT,'preview_three_quarter.png')
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'forest_girl.blend'))
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True)
for o in CHAR:o.select_set(True)
bpy.context.view_layer.objects.active=rig
for tr in rig.animation_data.nla_tracks:tr.mute=False
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,'forest_girl.glb'),export_format='GLB',use_selection=True,export_animations=True,export_nla_strips=True,export_force_sampling=True,export_cameras=False,export_lights=False,export_yup=True)
for tr in rig.animation_data.nla_tracks:tr.mute=True
reset_pose()
if not os.environ.get('CHARACTER_NO_RENDER'):
    bpy.ops.render.render(write_still=True)
    if os.environ.get('CHARACTER_DRAFT'): raise SystemExit(0)
    for name,loc in [('front',(0,-9,2.5)),('side',(9,0,2.5)),('back',(0,9,2.5))]:
        camera(loc);scene.render.filepath=os.path.join(OUT,'preview_'+name+'.png');bpy.ops.render.render(write_still=True)
camera((4,-8,4));scene.render.filepath=os.path.join(OUT,'preview_three_quarter.png')
with open(os.path.join(OUT,'model_stats.json'),'w') as f:json.dump({'mesh_objects':len(CHAR),'vertices':sum(len(o.data.vertices) for o in CHAR),'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in CHAR),'bones':len(arm.bones),'animations':['Idle','Walk'],'walk_note':'Analytic two-bone leg targets, planted stance feet, in-place cycle; no root motion or cloth simulation.'},f,indent=2)
print('CHARACTER_BUILD_COMPLETE')

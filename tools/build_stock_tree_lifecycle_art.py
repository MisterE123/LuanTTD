#!/usr/bin/env python3
"""Original native Temperate foliage and snag forms; preserve mature meshes.

python3 tools/build_stock_tree_lifecycle_art.py --check
blender -b -t 2 --python-exit-code 1 --python tools/build_stock_tree_lifecycle_art.py -- --blend --preview /tmp/luanttd-stock-tree-lifecycle.png
"""
from argparse import ArgumentParser
from collections import defaultdict
from math import cos, sqrt, sin, tau
from pathlib import Path
from random import Random
import sys

ROOT=Path(__file__).resolve().parents[1]
MODELS=ROOT/"mods/luanttd_core/models"
STAGES=(0,1,2,4,5,6)
HEIGHTS=(1.029600,.995628,.988827,.906048)
# Measured representative OpenGFX silhouettes (drawn independently):
# broadleaf width/height 20/24,25/31,30/37,35/43,...,28/43;
# birch 15/23,20/33,22/39,28/44,..,24/41; conifer 18/24,..,27/41.
AGE_HEIGHT={
    0:(.565,.615,.625,.535),
    1:(.728,.775,.779,.744),
    2:(.860,.896,.902,.882),
    4:(1.000,1.035,1.015,.992),
    5:(1.001,1.043,1.027,.964),
    6:(.992,1.045,1.040,.948),
}
MATURE_WIDTH=(.63977,.58766,.51350,.63924)
WIDTH_FRACTION={
    0:(.55,.59,.60,.54),1:(.70,.71,.74,.68),2:(.85,.87,.88,.82),
    4:(.94,1.02,1.01,.90),5:(.88,1.04,1.03,.85),6:(.83,1.04,1.04,.73),
}
STAGE_NAMES=("Fresh sapling","Growing sapling","Young tree","Mature reference",
             "Early decline","Late decline","Standing dead")
# Exact indices in the established scenery_palette atlas; no palette copy.
COLOR={
    "cedar":16,"sapwood":18,"metal dark":19,"coal":25,"rust":26,"metal":27,
    "ash":28,"gold":29,"wheat":30,"straw":31,"soil":32,"soil shade":33,
    "sage":34,"hedge":35,"mint":36,"green shade":37,"green":38,"green light":39,
    "pine shade":40,"pine":41,"pine light":42,"yellow leaf":43,
}
EDIT_RGB={
    "cedar":"79553c","sapwood":"a17e53","metal dark":"354d4a","coal":"494854","rust":"89513c",
    "metal":"7b8587","ash":"a5aeab","gold":"c4a257","wheat":"be9b47","straw":"d9b960",
    "soil":"836144","soil shade":"694d3b","sage":"788153","hedge":"425c38","mint":"628249",
    "green shade":"355641","green":"4d7346","green light":"729953",
    "pine shade":"375d52","pine":"487366","pine light":"628771","yellow leaf":"baa353",
}
OAK_GREEN=("green shade","green","green","green light","mint")
BIRCH_GREEN=("hedge","green","mint","green light")
PINE_GREEN=("pine shade","pine shade","pine","pine light","green shade")
OAK_DYING=("cedar","sage","hedge","mint","green","green shade")
OAK_DRY=("cedar","sapwood","sage","soil shade","rust","wheat")
BIRCH_GOLD=("gold","wheat","straw","yellow leaf","sapwood","sage")
PINE_BROWN=("soil shade","cedar","cedar","soil","sapwood","rust","sage")


def normal(a,b,c):
    u=tuple(v-w for v,w in zip(b,a))
    v=tuple(v-w for v,w in zip(c,a))
    return cross(u,v)


def cross(a,b):
    return tuple(a[i]*b[j]-a[j]*b[i] for i,j in ((1,2),(2,0),(0,1)))


def scale(v,s):
    return tuple(x*s for x in v)


def unit(v):
    l=sqrt(sum(i*i for i in v))
    assert l>1e-10
    return scale(v,1/l)


class Tree:
    def __init__(self):
        self.parts=defaultdict(list)

    def face(self,part,mat,verts):
        self.parts[part].append((mat,tuple(verts)))

    def stem(self,part,a,b,r1,r2,n,bark,twist=.0):
        direction=unit(tuple(y-x for x,y in zip(a,b)))
        axis=(0,0,1) if abs(direction[2])<.85 else (0,1,0)
        u=unit(cross(axis,direction))
        v=cross(direction,u)
        pts=[]
        for center,r in ((a,r1),(b,r2)):
            for i in range(n):
                phase=tau*i/n+twist
                pts.append(tuple(xx+r*(t*cos(phase)+w*sin(phase)) for xx,t,w in zip(center,u,v)))
        self.face(part,bark[0],pts[n-1::-1])
        self.face(part,bark[-1],pts[n:])
        for i in range(n):
            k=(i+1)%n
            self.face(part,bark[i%len(bark)],(pts[i],pts[k],pts[n+k],pts[n+i]))
        return b

    def crown(self,part,c,rx,rz,ry,mat,rng,n=6):
        """Closed asymmetrical deciduous leaf mass with subtly fractured planes."""
        x,y,z=c
        phase=rng.random()*tau
        vertices=[(x-.05*rx,y-ry,z+.05*rz)]
        for layer,(dy,w) in enumerate(((-.36,.87),(.25,1.0))):
            for i in range(n):
                a=phase+i*tau/n+layer*.19
                r=w*rng.uniform(.84,1.09)
                vertices.append((x+r*rx*cos(a),y+ry*(dy+rng.uniform(-.105,.105)),z+r*rz*sin(a)))
        vertices.append((x+.14*rx,y+ry,z-.09*rz))
        for i in range(n):
            j=(i+1)%n
            for inds in ((0,1+i,1+j),(1+i,1+n+i,1+j),
                         (1+j,1+n+i,1+n+j),(1+n+i,len(vertices)-1,1+n+j)):
                self.face(part,rng.choice(mat),[vertices[k] for k in inds])

    def whorl(self,part,c,rx,rz,ry,mat,rng,n=8,ripple=.11):
        """Needle skirts come off the central dark leader; floor is not a card."""
        x,y,z=c
        phase=rng.random()*tau
        tip=(x+.06*rx,y+ry,z-.04*rz)
        lower=(x,y+.045*ry,z)
        lip,surface=[],[]
        for i in range(n):
            a=i*tau/n+phase
            r=(.84 if i%2 else 1)*rng.uniform(.94,1.09)
            lip.append((x+rx*r*cos(a),y+ry*rng.uniform(-ripple,ripple),z+rz*r*sin(a)))
            surface.append((x+.67*rx*r*cos(a),y+ry*rng.uniform(.35,.49),z+.67*rz*r*sin(a)))
        for i in range(n):
            j=(i+1)%n
            coat=rng.choice(mat)
            self.face(part,coat,(tip,surface[j],surface[i]))
            # The blade skirt is not an angular cone: each floppy needle
            # bough curves inward toward its approximate branch root.
            self.face(part,coat,(surface[i],surface[j],lip[j]))
            self.face(part,rng.choice((coat,coat,mat[0])),(surface[i],lip[j],lip[i]))
            self.face(part,mat[0],(lower,lip[i],lip[j]))


def tree(style,stage):
    assert stage in STAGES
    rng=Random(981+341*style+56*stage)
    t=Tree()
    h=HEIGHTS[style]*AGE_HEIGHT[stage][style]
    if style%3==0:
        broadleaf(t,style,stage,h,rng)
    else:
        conifer(t,style,stage,h,rng)
    all_pts=[p for fs in t.parts.values() for _,f in fs for p in f]
    width=max(max(p[i] for p in all_pts)-min(p[i] for p in all_pts) for i in (0,2))
    r=MATURE_WIDTH[style]*WIDTH_FRACTION[stage][style]/width
    for part,faces in t.parts.items():
        t.parts[part]=[(col,tuple((x*r,y,z*r) for x,y,z in f)) for col,f in faces]
    return t


def roots(t,style,stage,h,bark):
    n=2 if stage==0 else 3 if stage<=2 else 4
    for i in range(n):
        a=tau*(i+.13)/n
        end=(h*.104*cos(a),-.011,h*.105*sin(a))
        t.stem("Flared root toes",(.001,.048*h,0),end,.024*h,.006*h,4,bark)


def broadleaf(t,style,s,h,rng):
    birch=style==3
    if s>=6:
        bark=("ash","metal","sapwood","coal") if birch else ("cedar","sapwood","ash","soil shade")
    else:
        bark=("sapwood","ash","metal","sapwood") if birch else ("cedar","soil shade","sapwood","cedar")
    width=(.47 if not birch else .41)*h
    spread=(1 if s<=2 else (.92 if s==4 else .85 if s==5 else .86))
    trunk_end=.84*h if s>=4 else .956*h
    trunk_r=(.026 if birch else .037)*h + (.003 if s==0 else .005)
    turn=.054*h if not birch else -.032*h
    trunk_start=(0,-.026,0)
    trunk_low=(turn*.25,.43*h,.008*h)
    trunk_high=(-.024*h,.664*h,-.029*h)
    end=(.068*h,trunk_end,.034*h)
    t.stem("Rooted tapered trunk",trunk_start,trunk_low,trunk_r*1.2,trunk_r*.82,6,bark)
    t.stem("Central trunk bend",trunk_low,trunk_high,trunk_r*.83,trunk_r*.57,6,bark,.18)
    t.stem("Upper trunk leader",trunk_high,end,trunk_r*.54,trunk_r*.16,5,bark,.10)
    roots(t,style,s,h,bark)
    positions=[]
    # Asymmetric principal boughs leave visible crown holes when the leaves
    # go. The gallery captures outline/structure, not merely autumn hues.
    if s<3:
        branches=(2,3,4)[s]
    else:
        branches=5 if not birch else 6
    for i in range(branches):
        a=i*tau/branches+(.28 if birch else .12)+rng.uniform(-.15,.15)
        arm=width*spread*rng.uniform(.55,.92)*(1 if i%3!=1 else .82)
        apex=h*rng.uniform(.755,.900) if s>=4 else h*rng.uniform(.669,.747)
        out=(arm*cos(a),apex,arm*sin(a))
        base=(turn*.42,(.37+.12*(i%3))*h,.004*h)
        bend=(out[0]*.535,out[1]-.14*h,out[2]*.59)
        t.stem("Open supporting boughs",base,bend,trunk_r*.67,trunk_r*.45,5,bark,.14)
        t.stem("Open supporting boughs",bend,out,trunk_r*.445,trunk_r*.20,5,bark)
        positions.append((out,a))
        if s>=4:
            m=tuple(.43*a+.57*b for a,b in zip(bend,out))
            leaf_forward=(out[0]*.77+.085*h*cos(a+.88),out[1]+.077*h,out[2]*.77+.070*h*sin(a+.88))
            t.stem("Visible twig ends after leaf drop",m,leaf_forward,trunk_r*.37,trunk_r*.09,4,bark)
    if s<=2:
        mat=BIRCH_GREEN if birch else OAK_GREEN
        # Young plants have fewer, compact clumps with a bright exposed
        # branch leader. Increase mass and height without mirroring the
        # full mature oak/birch polygon mesh.
        for i,(out,a) in enumerate(positions):
            th=(.185,.192,.199)[s]*h
            q=(out[0]*.76,out[1]+.015*h,out[2]*.78)
            t.crown("Fresh sapling foliage",q,th,th*.91,(.151+.017*(i%2))*h,mat,rng)
        t.crown("Young crown leader foliage",(.014*h,(.837+.008*s)*h,.015*h),
                .207*h,.175*h,.159*h,mat,rng,7)
    elif s<6:
        mat=(BIRCH_GREEN if s==4 else BIRCH_GOLD) if birch else (OAK_DYING if s==4 else OAK_DRY)
        selected=positions if s==4 else [p for i,p in enumerate(positions) if i%2==0]
        for i,(pos,a) in enumerate(selected):
            th=(.103 if s==4 else .066)*h*(1+.15*(i%2))
            q=(pos[0]*1.02, min(pos[1]+.06*h,.914*h),pos[2]*1.01)
            t.crown("Residual declining foliage",q,th,th*.76,(.087 if s==4 else .069)*h,mat,rng,5)
        if s==4:
            t.crown("Thinning exposed crown",(.046*h,.921*h,.037*h),.122*h,.109*h,.079*h,mat,rng,6)
    if s>=5:
        # Pale exposed apex rises to original stock mature-tree scale.
        t.stem("Broken exposed leader",end,(.081*h,.997*h,.046*h),trunk_r*.21,trunk_r*.10,4,bark)


def conifer(t,style,s,h,rng):
    bark=("cedar","sapwood","soil shade","cedar") if s<=4 else ("cedar","soil shade","metal","sapwood")
    r=(.036 if style==1 else .033)*h
    leader=((.024 if style==1 else -.036)*h,.998*h,.015*h)
    lower=(0,.52*h,.006*h)
    t.stem("Conifer flare and straight leader",(0,-.025,0),lower,r*1.20,r*.62,6,bark,.16)
    t.stem("Conifer flare and straight leader",lower,leader,r*.633,r*.09,6,bark)
    roots(t,style,s,h,bark)
    whorls=2 if s==0 else 3 if s<=2 else 4
    width=(.307 if style==1 else .250)*h
    for i in range(whorls):
        q=i/(whorls-1)
        x=(i-1)*.015*h+rng.uniform(-.009,.009)
        z=(i%2-.5)*.018*h
        floor=((.265+.390*q) if s==0 else (.26+.515*q))*h
        radius=width*(1-.71*q)
        top=((.424-.078*q) if s==0 else (.305-.074*q))*h
        if s<=2:
            mat=PINE_GREEN
            yname="Young tapering needle whorls"
            top=min(top,h-floor)
        else:
            yname="Dry attached needle skirts" if s>=5 else "Sparse evergreen and ochre needle skirts"
            mat=(PINE_GREEN+PINE_BROWN*2 if s==4 else PINE_BROWN+(("pine shade","sage") if s==5 else ("soil shade","cedar")))
            radius*=.97 if s==4 else 1.02 if s==5 else 1.01
            top=min(top,h-floor)
        t.whorl(yname,(x,floor,z),radius,radius*(.90 if style==1 else .97),top,mat,rng,n=10 if s>=4 else 8)
        if s>=4 and i<whorls-1:
            for j in range(3):
                a=j*tau/3+i*.74
                e=(x+radius*cos(a)*1.026,floor-.07*h,z+radius*sin(a)*1.026)
                t.stem("Visible exposed conifer twig",lower if i==1 else (x,floor-.012*h,z),e,
                       r*.29,r*.075,4,bark)


def fmt(v,d):
    s=format(round(v,d) or 0,f".{d}f").rstrip("0").rstrip(".") or "0"
    # OBJ decimals allow a leading dot, cutting several bytes per vertex.
    return s[1:] if s.startswith("0.") else ("-"+s[2:] if s.startswith("-0.") else s)


def obj(t,lift):
    verts,uv,norms={}, {}, {}
    out=["# Original LuanTTD stock tree age art; tools/build_stock_tree_lifecycle_art.py",
         "o TemperateAgeTree"]
    root=-1.5+lift*.5
    faces=[]
    for part,geometry in t.parts.items():
        faces.append("# "+part)
        for col,pts in geometry:
            ps=list(reversed([(-x,y,z) for x,y,z in pts]))
            normal_i=norms.setdefault(tuple(round(v,4) or 0 for v in unit(normal(*ps[:3]))),len(norms)+1)
            tis=uv.setdefault(COLOR[col],len(uv)+1)
            vs=[verts.setdefault(tuple(round(v,5) or 0 for v in p),len(verts)+1) for p in ps]
            faces.append("f "+" ".join(f"{vi}/{tis}/{normal_i}" for vi in vs))
    out.extend("v "+fmt(x,5)+" "+fmt(y+root,5)+" "+fmt(z,5) for x,y,z in verts)
    out.extend(f"vt {fmt((i+.5)/64,8)} .5" for i in uv)
    out.extend("vn "+" ".join(fmt(v,4) for v in n) for n in norms)
    return ("\n".join(out+faces)+"\n").encode()


def assets():
    for s in range(4):
        for g in STAGES:
            t=tree(s,g)
            for l in range(5):
                yield MODELS/f"bl_stock_forest_{s}_{l}_g{g}.obj",obj(t,l)


def mature(style):
    path=MODELS/f"bl_stock_forest_{style}_0.obj"
    inv=dict((v,k) for k,v in COLOR.items())
    verts,uv=[],[]
    out=Tree()
    for row in path.read_text().splitlines():
        tag,*vals=row.split()
        if tag=="v":
            x,y,z=map(float,vals)
            verts.append((-x,y+1.5,z))
        elif tag=="vt":uv.append(int(float(vals[0])*64))
        elif tag=="f":
            refs=[tuple(map(int,s.split("/"))) for s in vals]
            color=inv[uv[refs[0][1]-1]]
            out.face("Reference only: unchanged mature native tree",color,[verts[i-1] for i,j,k in refs[::-1]])
    return out


def editable(preview):
    import bpy
    from mathutils import Vector
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene=bpy.context.scene
    scene.name="Original Temperate trees: RC1 life stages"
    scene["native"]="Last stem only. Runtime ages 0/1/2/4/5/6 new; age 3 aliases existing mature art; root y=-1.5+lift/2."
    mats={}
    for name,s in EDIT_RGB.items():
        m=bpy.data.materials.new(name)
        def lin(t):return t/12.92 if t<=.04045 else ((t+.055)/1.055)**2.4
        m.diffuse_color=(*[lin(v/255) for v in bytes.fromhex(s)],1)
        mats[name]=m
    turf=bpy.data.materials.new("Review turf — not exported")
    turf.diffuse_color=(.176,.234,.126,1)

    for s in range(4):
        for g in range(7):
            label=f"{s} {('Oak','Pine','Spruce','Birch')[s]}, {g} {STAGE_NAMES[g]}"
            a=mature(s) if g==3 else tree(s,g)
            xx=g*1.25
            zz=s*1.16
            c=bpy.data.collections.new(label)
            scene.collection.children.link(c)
            for part,faces in a.parts.items():
                points,polys=[],[]
                for mat,verts in faces:
                    polys.append(tuple(range(len(points),len(points)+len(verts))))
                    points.extend((xx+x,-(zz+z),y) for x,y,z in verts)
                me=bpy.data.meshes.new(part)
                me.from_pydata(points,[],polys)
                me.update()
                colors=list(dict.fromkeys(m for m,_ in faces))
                for key in colors:me.materials.append(mats[key])
                for poly,(idx,_) in zip(me.polygons,faces):poly.material_index=colors.index(idx)
                c.objects.link(bpy.data.objects.new(part,me))
            lo=.45
            v=[(xx+dx,-(zz+dz),-.008) for dx,dz in ((-lo,-lo),(-lo,lo),(lo,lo),(lo,-lo))]
            me=bpy.data.meshes.new("Square terrain datum, not exported")
            me.from_pydata(v,[],[(0,1,2,3)]);me.materials.append(turf)
            c.objects.link(bpy.data.objects.new("Datum review reference",me))
    center=Vector((3.75,-1.74,.25))
    bpy.ops.object.camera_add(location=center+Vector((1.9,-11,7.6)))
    cam=bpy.context.object
    cam.rotation_euler=(center-cam.location).to_track_quat("-Z","Y").to_euler()
    cam.data.type="ORTHO"
    cam.data.ortho_scale=10.6
    scene.camera=cam
    scene.render.engine="BLENDER_WORKBENCH"
    scene.render.resolution_x=1370
    scene.render.resolution_y=870
    scene.view_settings.view_transform="Standard"
    scene.view_settings.exposure=.23
    sh=scene.display.shading
    sh.color_type="MATERIAL"
    sh.show_cavity=True
    sh.cavity_type="BOTH"
    sh.light="STUDIO"
    sh.show_shadows=True
    sh.background_type="WORLD"
    scene.world=bpy.data.worlds.new("Light gray studio")
    scene.world.color=(.069,.088,.085)
    for screen in bpy.data.screens:
        for a in screen.areas:
            if a.type=="VIEW_3D":
                view=a.spaces.active
                view.shading.color_type="MATERIAL"
                view.region_3d.view_location=center
                view.region_3d.view_distance=11
                view.region_3d.view_rotation=cam.rotation_euler.to_quaternion()
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art/stock_tree_lifecycle.blend"),compress=True)
    if preview:
        scene.render.filepath=preview
        bpy.ops.render.render(write_still=True)


def main():
    p=ArgumentParser()
    p.add_argument("--check",action="store_true")
    p.add_argument("--blend",action="store_true")
    p.add_argument("--preview")
    flags=p.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else (sys.argv[1:] if "bpy" not in sys.modules else []))
    for path,data in assets():
        if flags.check:assert path.read_bytes()==data,path
        elif not path.exists() or path.read_bytes()!=data:path.write_bytes(data)
    if flags.blend:editable(flags.preview)


if __name__=="__main__":main()

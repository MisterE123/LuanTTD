#!/usr/bin/env python3
"""Build an original OpenTTD 14.1 temperate farm layout-0, per logical cell."""
from math import atan2, cos, hypot, pi, sin
from pathlib import Path
from random import Random
import os
import struct
import sys
import zlib

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_small_airport_art as A

R = A.RAIL
B, T, F, Q = A.B, A.T, A.face, A.rect
PAL = dict(A.PAL, **{
    "soil":"917b55", "drysoil":"b19667", "tread":"887552", "haygold":"cdb05d",
    "oat":"b29c50", "pasture":"798f4c", "verge":"627d47", "hedge":"4d683f",
    "leaf":"567745", "sunleaf":"79944e", "grass_stem":"617938",
    "farmred":"9b5441", "farm_lit":"b9684d", "barn_shadow":"754336",
    "warmclay":"a88460","creamslats":"b99770","creamsun":"d0af86",
    "zinc":"a1ada6", "zinc_light":"c4c4a8", "zinc_edge":"738782",
    "silo_blue":"768c8a", "silo_rust":"857667", "ruralglass":"86a699",
    "cement":"aba692","woodold":"807154","black_hide":"3b4239",
    "cream_hide":"e1d4b8","brown_hide":"8a583d","goat_horn":"beb098",
    "mud":"7d654b","pig":"bf927b","pig_light":"d0a490","dark_soil":"76644f",
})
A.PAL = PAL
A.P = A.H.P = {k:i for i,k in enumerate(PAL)}
R.COLORS[:] = PAL.values()
A.DIGITS.update({"C":("01111","11000","11000","11000","11000","11000","01111"),
                "M":("10001","11011","11111","10101","10001","10001","10001"),
                "S":("01111","11000","11000","01110","00011","00011","11110"),
                "T":("11111","00100","00100","00100","00100","00100","00100"),
                "V":("10001","10001","10001","10001","11011","01010","00100")})
LAYOUT = {(1,0):33,(1,1):34,(1,2):36,(0,0):37,(0,1):37,
          (0,2):36,(2,0):35,(2,1):38,(2,2):38}
ROOT = R.ROOT
NAME = "industry_farm"
D = .5


def fence(m,pts,gate=(),colour="creamslats",label="Split rail paddock"):
    for seg,(a,b) in enumerate(zip(pts,pts[1:])):
        length=hypot(b[0]-a[0],b[1]-a[1]); n=max(1,round(length/.43))
        for i in range(n+1):
            t=i/n; x,z=(a[j]+t*(b[j]-a[j]) for j in (0,1))
            B(m,label+" capped upright", "woodold",x,z,.063,.063,.019,.227,.008)
            if i<n and seg not in gate:
                t2=(i+1)/n; xx,zz=(a[j]+t2*(b[j]-a[j]) for j in (0,1))
                for h in (.093,.178):
                    T(m,label+" hewn rail",colour,(x,z,h),(xx,zz,h+.003),.023,.021,4)
        if seg in gate:
            for h in (.069,.118,.167):
                T(m,label+" galvanized gate bar","zinc_edge",(*a,h),(*b,h),.009,.009,7)
            T(m,label+" gate diagonal brace","zinc_edge",(*a,.062),(*b,.189),.010,.010,6)


def place_grp(m,parts):
    for f in parts:f(m)


def land(m):
    # Grass world runs continuously under the farm; compacted yards only
    # tint active areas. Keep the full northern receiving path and east gap.
    A.strip(m,"Swept gravel route from south lane","drysoil",
      [(2.06,5.5),(2.08,4.96),(2.29,4.34),(1.93,3.66),(1.66,2.94),(1.56,1.75),(1.65,.7),(1.77,-.5)],.395,.006)
    A.strip(m,"Continuous darker cart bed","tread",
      [(2.06,5.5),(2.08,4.96),(2.29,4.34),(1.93,3.66),(1.66,2.94),(1.56,1.75),(1.65,.7),(1.77,-.5)],.266,.007)
    track=[(1.65,1.11),(2.37,.99),(3.25,.92),(4.04,1.04),(4.66,.82)]
    A.strip(m,"Swept eastern grain pickup apron","drysoil",track,.277,.009)
    A.strip(m,"Wagon tread below grain ramp","tread",track,.145,.010)
    for xa,xb,za,zb in ((-.48,1.38,-.48,3.41),(3.63,5.37,1.67,3.32),(3.62,5.36,3.68,5.36)):
        Q(m,"Muted grazed paddock or mill yard","pasture",xa,xb,za,zb,.002)
    for xa,xb,za,zb in ((-.45,1.18,-.42,1.31),(-.41,1.24,1.63,3.17),(2.16,3.4,-.48,.63)):
        Q(m,"Weathered compacted delivery ground under equipment","soil",xa,xb,za,zb,.005)
    rng=Random(1283)
    for j in range(98):
        x,z=(rng.uniform(-.448,5.43),rng.uniform(-.448,5.43))
        if 1.33<x<2.72 or (3.6<x and z>1.7):continue
        w,d=rng.uniform(.02,.094),rng.uniform(.014,.043)
        Q(m,"Scattered stony gravel and dry straw",rng.choice(("soil","drysoil","tread","woodold","verge")),
          x-w*.5,x+w*.5,z-d*.5,z+d*.5,.011)
    fence(m,[(3.64,1.71),(4.03,1.71),(4.50,1.71),(5.33,1.71),(5.33,3.35),(3.64,3.35),(3.64,1.71)],(1,),label="North cattle paddock")
    fence(m,[(3.64,3.68),(4.03,3.68),(4.50,3.68),(5.33,3.68),(5.33,5.34),(3.64,5.34),(3.64,3.68)],(1,),label="South stock paddock")
    for ends in (((-.29,-.35),(1.14,-.35)),((-.35,3.38),(1.22,3.38)),((-.33,3.76),(-.33,5.32),(1.30,5.32))):
        fence(m,list(ends),colour="woodold",label="Service yard boundary")


def roof(m,n,x,z,w,l,e,r,c):
    # Gable panels leave the chosen south front open below the eave.
    A.gable(m,n,x,z,w,l,e,r,c,"z")
    for side in (-1,1):
        for j in range(1,6):
            frac=j/6
            a=(x+side*w/2*frac,z-l/2-.008,r-frac*(r-e)+.012)
            b=(a[0],z+l/2+.005,a[2])
            T(m,n+" shallow flashing standing seams","slate_rib",a,b,.009,.009,5)
        for zz in (z-l/2-.003,z+l/2+.003):
            T(m,n+" cream rake board","board",(x,zz,r),(x+side*w/2,zz,e),.018,.018,5)
    T(m,n+" rain cap","slate_rib",(x,z-l/2-.016,r+.008),(x,z+l/2+.016,r+.008),.022,.019,7)


def gable_panel(m,n,x,z,w,e,r,c,front=True):
    vv=[(x-w/2,z,e),(x+w/2,z,e),(x,z,r)]
    F(m,n,c,vv[::-1] if front else vv)


def plankwall(m,n,x,z,w,l,bottom,eave,wall):
    # Back and both side elevations. Tinted cladding lines are real strips,
    # but no repeated bevel faces hidden inside parts.
    B(m,n+" north boarded frame",wall,x,z-l/2,w,.042,bottom,eave)
    for sign in (-1,1):
        B(m,n+" longitudinal boarded frame",wall,x+sign*w/2,z,.055,l,bottom,eave)
        for j in range(8):
            zz=z+(j+.5)*l/8-l/2
            B(m,n+" vertical wood batten","warmclay" if wall=="creamslats" else "barn_shadow",
              x+sign*(w/2+.029),zz,.011,.014,bottom+.012,eave-.016)
        for zz in (z-l*.477,z+l*.477):
            B(m,n+" whitewashed corner pilaster","board",x+sign*w/2,zz,.073,.054,bottom,eave+.014,.004)


def shed(m,n,x,z,w,l,h,r,wall="creamslats",open_front=True):
    b=.10
    B(m,n+" raised chamfered stone kneewall","foundation",x,z,w+.092,l+.101,.003,b,.009)
    plankwall(m,n,x,z,w,l,b,h,wall)
    for dz,facing in ((-l/2,False),(l/2,True)):
        gable_panel(m,n+" enclosed boarded loft",x,z+dz,w,h,r-.036,wall,facing)
        B(m,n+" eaves lintel","board",x,z+dz,w+.028,.042,h-.065,h+.018,.005)
    if open_front:
        # No solid front wall: loading apron runs through a framed door.
        for s in (-1,1):
            B(m,n+" narrow front pier",wall,x+s*w*.393,z+l/2,w*.216,.062,b,h)
            B(m,n+" loading gate guide","board",x+s*w*.278,z+l/2+.036,.036,.064,b,h-.076,.005)
        Q(m,n+" open pass-through concrete floor","cement",x-w*.31,x+w*.31,z-l*.42,z+l*.59,.101)
        B(m,n+" loft ventilation door","barn_shadow",x,z+l/2+.018,.209,.046,h+.054,h+.226,.007)
        for j in range(4):
            B(m,n+" loft grille slat","creamsun",x,z+l/2+.044,.194,.008,h+.081+j*.031,h+.093+j*.031)
    else:
        B(m,n+" front clapboard elevation",wall,x,z+l/2,w,.053,b,h)
        A.facade_window(m,n+" multipane office sash",x+w*.28,z+l/2+.030,.219,.289,.501)
        A.facade_window(m,n+" multipane office sash",x-w*.28,z+l/2+.030,.219,.289,.501)
        A.doorway(m,n+" farmhouse front stoop",x,z+l/2+.037,.221,.107,.482,"teal")
    roof(m,n+" steep vented roof",x,z,w+.145,l+.137,h+.013,r,"dark_slate" if open_front else "slate")
    for dx in (-w*.46,w*.46):
        B(m,n+" iron tie rods","woodold",x+dx,z+l/2+.040,.044,.043,b+.034,b+.057,.005)


def architecture(m):
    shed(m,"Single-storey farmhouse",2.71,2.026,.923,.839,.674,1.016,"creamslats",False)
    B(m,"Farmhouse chimney reddish anchored brick","brick",2.98,2.02,.159,.142,.746,1.058,.013)
    B(m,"Farmhouse capped open chimney iron","dark_slate",2.98,2.02,.192,.167,1.027,1.066,.010)
    # Two connected barns form the stock double-roof silhouette.
    shed(m,"Threshing barn",4.16,.127,.964,.770,.745,1.129,"creamslats")
    shed(m,"Side-by-side cart shed",4.98,.131,.666,.768,.615,.918,"farmred")
    for x,z,w,l in ((.592,4.14,.954,.690),(2.91,4.807,.843,.661)):
        shed(m,"Light slate grain annex",x,z,w,l,.584,.863,"creamslats")
    fence(m,[(2.27,-.34),(2.73,-.34),(3.31,-.34),(3.34,.36),(3.13,.62),(2.83,.62),(2.38,.62)],(4,),
          label="Stocking and sorting corral")
    B(m,"Working cattle loading chute low non-slip ramp","concrete_d",2.98,.736,.291,.342,.006,.058,.008)
    B(m,"Country farm enamel nameboard","dark_green",2.91,5.236,.66,.050,.710,.792,.009)
    A.lettering(m,"Highfield farm lettering","HIGHFIELD",(2.91,5.265,.752),.0107,"south","bone")
    for xx in (2.60,3.10):
        B(m,"Farmhouse low yard planter","woodold",xx,2.58,.218,.102,.025,.064,.009)
        for i in range(4): B(m,"House herb leaves","leaf",xx-.075+i*.045,2.58,.038,.052,.055,.105,.010)


def storage(m):
    for gx,gz in ((.20,.18),(.80,.18),(.20,2.02),(.80,2.02)):
        h=1.46 if gx<.4 else 1.29
        n="Corrugated vertical grain silo"
        B(m,n+" octagonal concrete footing","cement",gx,gz,.478,.479,.009,.089,.043)
        T(m,n+" weathered turned shell","silo_blue",(gx,gz,.084),(gx,gz,h),.202,.205,16)
        for i in range(4):
            a=.280+i*(h-.30)/4
            T(m,n+" circumferential zinc seam","zinc",(gx,gz,a),(gx,gz,a+.015),.206,.206,16)
        for i in range(16):
            t=2*pi*i/16
            x,z=gx+.207*cos(t),gz+.207*sin(t)
            T(m,n+" standing rib","zinc_edge",(x,z,.120),(x,z,h-.015),.008,.008,5)
        T(m,n+" silvery roof cone","zinc",(gx,gz,h),(gx,gz,h+.137),.224,.028,16)
        T(m,n+" inspection breather cap","zinc_edge",(gx,gz,h+.123),(gx,gz,h+.170),.045,.039,9)
        if gx<.4:
            for xx in (gx-.053,gx+.053):
                T(m,n+" handrail ladder stringer","dark_slate",(xx,gz+.213,.106),(xx,gz+.213,h),.009,.009,6)
            for dz in range(11):
                y=.16+dz*.115
                T(m,n+" ladder tread","steel",(gx-.053,gz+.225,y),(gx+.053,gz+.225,y),.007,.007,6)
        # Formed auger delivery spout bends over the raised cast grate,
        # with no hardware across the main public cart road.
        if gx>.4:
            T(m,n+" angled grain drawing spout","steel",(gx,gz+.058,h*.78),(gx+.370,gz+.16,.52),.055,.053,10)
            T(m,n+" down-pipe sack feed","zinc_edge",(gx+.370,gz+.16,.52),(gx+.370,gz+.16,.39),.054,.050,10)
    Q(m,"Flush receiving weigh plate","dark_metal",.963,1.328,.826,1.171,.014)
    for i in range(10):
        z=.839+i*.034
        Q(m,"Visible inset slot bars","steel",.967,1.321,z-.008,z+.006,.017)
    for gx,gz in ((.84,.76),(.75,2.37),(4.01,.50),(4.37,.50),(5.02,.71),(.75,4.26)):
        T(m,"Pallet oval straw hay roll","haygold",(gx-.105,gz,.103),(gx+.106,gz,.103),.098,.098,10)
        for a in (-.052,.049):
            T(m,"Two distinct hay bindings","oat",(gx+a,gz,.103),(gx+a+.008,gz,.103),.100,.100,10)


def ellipse(m,n,c,x,z,h,rx,rz,ry,j=10,turn=0):
    # Two triangulated rings and the poles: a solid profile at street height.
    def p(a,b):
        q,r=rx*cos(a)*cos(b),rz*sin(a)*cos(b)
        return x+q*cos(turn)-r*sin(turn),z+q*sin(turn)+r*cos(turn),h+ry*sin(b)
    rows=[[p(i*2*pi/j,b) for i in range(j)] for b in (-pi/4,0,pi/4)]
    for j0 in range(j):
        k=(j0+1)%j
        F(m,n,c,[(x,z,h-ry),rows[0][k],rows[0][j0]])
        for a,b in zip(rows,rows[1:]):
            F(m,n,c,[a[j0],a[k],b[k],b[j0]])
        F(m,n,c,[rows[-1][j0],rows[-1][k],(x,z,h+ry)])


def flora(m):
    rng=Random(2143)
    for cx,cz,ht in ((2.27,-.072,.86),(2.47,2.989,.69),(-.11,2.92,.91),(5.34,3.52,.74),(.13,5.01,.64)):
        tx,tz=cx+.024,cz-.029
        T(m,"Orchard forked ash trunk","wood",(cx,cz,0),(tx,tz,ht*.68),.039,.017,8)
        for i in range(7):
            t=i*2*pi/7
            xx=tx+ht*.194*cos(t)
            zz=tz+ht*.194*sin(t)
            y=ht*rng.uniform(.64,.79)
            T(m,"Orchard secondary branch","wood",(tx,tz,ht*.38),(xx,zz,y),.014,.005,6)
            ellipse(m,"Massed leaf clusters",rng.choice(("leaf","verge","sunleaf")),xx,zz,y,ht*.155,ht*.144,ht*.167,7)
        ellipse(m,"Orchard sunlit top leaves","sunleaf",tx,tz,ht*.88,ht*.19,ht*.17,ht*.164,9)
    for j in range(38):
        x,z=rng.uniform(-.43,5.44),rng.uniform(-.41,5.43)
        if 1.1<x<3.3 or z<1.7:continue
        for i in range(3):
            xx=x+i*.018
            F(m,"Three-dimensional grass tufts","grass_stem",[(xx-.01,z,.007),(xx+.013,z,.007),(xx+.012,z+.016,rng.uniform(.043,.087))])
            F(m,"Three-dimensional grass tufts","verge",[(xx+.013,z,.007),(xx-.01,z,.007),(xx+.012,z+.016,rng.uniform(.043,.087))])


def bovine(m,x,z,turn,hue):
    def p(a,b,h):
        return x+a*cos(turn)-b*sin(turn),z+a*sin(turn)+b*cos(turn),h
    def shape(n,c,a,b,h,rx,rz,ry,j=8):
        u,v,y=p(a,b,h)
        ellipse(m,n,c,u,v,y,rx,rz,ry,j,turn)
    shape("Livestock modeled cow barrel and ribs",hue,0,0,.215,.181,.071,.082)
    shape("Livestock shoulder black and cream marking","cream_hide" if hue=="black_hide" else "black_hide",.061,.005,.238,.068,.076,.058)
    shape("Livestock lowered cow head",hue,.184,0,.236,.067,.050,.061)
    shape("Livestock pale square muzzle","cream_hide",.226,-.005,.209,.037,.041,.031)
    for s in (-1,1):
        shape("Livestock turned ears","brown_hide",.167,s*.055,.271,.031,.019,.012,6)
        T(m,"Livestock short shaped poll horn","goat_horn",p(.171,s*.031,.275),p(.165,s*.062,.298),.009,.004,5)
        for xx in (-.122,.107):
            T(m,"Livestock shaped leg and hock",hue,p(xx,s*.040,.195),p(xx-.005,s*.050,.043),.021,.012,6)
            T(m,"Livestock dark hooves","black_hide",p(xx-.004,s*.050,.045),p(xx+.006,s*.053,.007),.015,.014,6)
    T(m,"Livestock curved hanging tail","black_hide",p(-.164,0,.254),p(-.211,.025,.117),.011,.006,6)


def husbandry(m):
    for x,z,a,c in ((4.2,2.35,.8,"black_hide"),(4.88,2.76,2.72,"brown_hide"),
                     (4.53,3.01,1.42,"black_hide"),(2.87,.332,2.44,"brown_hide"),(4.76,4.70,2.02,"black_hide")):
        bovine(m,x,z,a,c)
    for x,z in ((4.28,4.18),(4.28,4.85)):
        ellipse(m,"Pig shaped barrel","pig",x,z,.121,.113,.056,.062,8)
        ellipse(m,"Pig defined snout","pig_light",x+.104,z,.107,.048,.036,.036,8)
        for a in (-.061,.051):
            for s in (-1,1):
                T(m,"Pig grounded feet","pig", (x+a,z+s*.029,.107),(x+a+.005,z+s*.035,.014),.015,.011,5)
    for x,z in ((5.075,2.06),(5.07,4.02)):
        B(m,"Galvanized livestock water trough hull","zinc_edge",x,z,.316,.151,.03,.105,.024)
        B(m,"Livestock trough deliberately inset water","ruralglass",x,z,.260,.113,.099,.108,.013)
        for a in (-.106,.107):
            B(m,"Trough carriage legs","dark_slate",x+a,z,.046,.123,.009,.048,.007)


def clip(m,x,z,layout):
    out=A.mesh()
    x0,z0=2*x-D,2*z-D
    for n,items in m.parts.items():
        for ids,c in items:
            p=[m.vertices[n][i] for i in ids]
            for axis,b,s,adj in ((0,x0,+1,False),
                 (0,x0+2,-1,(x+1,z) in layout),(1,z0,+1,False),(1,z0+2,-1,(x,z+1) in layout)):
                if s<0 and adj and all(abs(v[axis]-b)<A.EPS for v in p):p=[]
                if not p:break
                p=A.clip(p,axis,b,s)
            out.face(n,c,[(a-x0-1,b-z0-1,y) for a,b,y in p])
    return out


def atlas(name,pal):
    def chunk(tag,n):
        return struct.pack(">I",len(n))+tag+n+struct.pack(">I",zlib.crc32(tag+n))
    row=b"".join(bytes.fromhex(c)*8 for c in pal.values())
    (R.TEXTURES/f"bl_{name}_atlas.png").write_bytes(
       b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",len(pal)*8,8,8,2,0,0,0))+
       chunk(b"IDAT",zlib.compress((b"\0"+row)*8,9))+chunk(b"IEND",b""))


def build(name,layout,groups,title,blend,look,cam,scale,pal,render):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    sc=bpy.context.scene;sc.name=title
    sc["Upstream cells"]="OpenTTD 14.1 default layout 0: "+", ".join(f"({x},{z}) GFX {n}" for (x,z),n in layout.items())
    sc["Datum"]="Blender Z up, ground Z=0; runtime grade+1 anchor with cell centered at NW site +(2*x,2*z)"
    mats=R.materials()
    for i,n in enumerate(pal):mats[i].name=n.replace("_"," ").title()
    for n,f in groups:
        m=A.mesh();f(m)
        c=bpy.data.collections.new(n);sc.collection.children.link(c);R.to_blender(m,c,mats)
    full=A.mesh();place_grp(full,[f for _,f in groups])
    for (x,z),gfx in layout.items():
        p=R.MODELS/f"bl_{name}_{x}_{z}.obj"
        R.export_obj(p,clip(full,x,z,layout))
        raw=p.read_text()
        p.write_text(raw.replace(raw.splitlines()[0],f"# {title}; layout 0 ({x},{z}) GFX {gfx}; original Blender art",1))
    atlas(name,pal)
    rot=(Vector(look)-Vector(cam)).to_track_quat("-Z","Y")
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":
                s=area.spaces.active;s.shading.color_type="MATERIAL"
                s.region_3d.view_location=look;s.region_3d.view_distance=scale*1.24;s.region_3d.view_rotation=rot
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art"/blend),compress=True)
    if not render:return
    bpy.ops.mesh.primitive_plane_add(size=24,location=(look[0],look[1],-.0013))
    grass=bpy.data.materials.new("Tempered meadow");grass.diffuse_color=(.211,.316,.107,1)
    bpy.context.object.data.materials.append(grass)
    ob=bpy.data.objects.new("Survey review",bpy.data.cameras.new("Survey review"));sc.collection.objects.link(ob)
    ob.location=cam;ob.rotation_euler=rot.to_euler();ob.data.type="ORTHO";ob.data.ortho_scale=scale;sc.camera=ob
    sc.render.engine="BLENDER_WORKBENCH";sc.render.resolution_x=1470;sc.render.resolution_y=1130
    s=sc.display.shading;s.light="STUDIO";s.color_type="MATERIAL";s.show_shadows=True
    s.show_cavity=True;s.cavity_type="BOTH";s.cavity_ridge_factor=1.15
    sc.view_settings.view_transform="Standard";sc.render.filepath=render
    bpy.ops.render.render(write_still=True)


if __name__=="__main__":
    build(NAME,LAYOUT,(("Swept route, farm roads and fenced fields",land),("Farmhouse, barn, annexes",architecture),
      ("Twin corrugated silo banks, grain transfer and hay",storage),("Ash and orchard trees, planted grass",flora),
      ("Paddock livestock and water",husbandry)),"Highfield Farm","stock_temperate_farm.blend",
      (2.38,2.47,.57),(9.6,11.4,8.6),8.20,PAL,os.getenv("STOCK_FARM_RENDER"))

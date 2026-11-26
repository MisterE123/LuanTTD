#!/usr/bin/env python3
"""Original field rotation and farm boundaries for the native OpenTTD terrain."""
from math import cos, pi, sin
from pathlib import Path
from random import Random
import struct
import sys
import zlib

import bpy
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_stock_farm_art as S

ROOT=S.ROOT
R,A=S.R,S.A
B,T,F=S.B,S.T,S.F
PAL=dict(S.PAL, **{
    "field_leaf":"748a46", "ripe_barley":"b8a061", "ripe_head":"d3b26a",
    "dark_stubble":"8e7f49", "terrace_life":"6c7741",
    "wall_dark":"8e825c", "wall_bright":"ad9e72", "wall_lichen":"929167",
    "wall_cap":"bbab7e", "paling":"9b825a", "paling_old":"b0986d",
})
A.P=A.H.P={k:i for i,k in enumerate(PAL)}
R.COLORS[:]=PAL.values()
# Stock field type order 0..8. On stock type 8 the ground is still
# harvested stubble but visually distinct and receives optional 3D straw.
DATA=(
  ((111,85,59),(146,114,73),(161,132,86), .09,.02,.12),
  ((119,93,60),(151,124,75),(154,132,75), .17,.07,.14),
  ((108,91,59),(112,125,68),(141,148,81), .25,.23,.26),
  ((101,87,57),(103,128,64),(142,156,78), .34,.39,.38),
  ((114,92,58),(119,139,70),(153,161,83), .44,.48,.49),
  ((125,101,64),(143,143,75),(176,160,89), .55,.57,.63),
  ((123,101,59),(159,142,73),(183,159,82), .61,.65,.71),
  ((125,101,65),(142,119,73),(158,135,77), .17,.29,.25),
  ((129,108,65),(149,128,78),(171,145,81), .20,.36,.27),
)
SIZE=64
ROWS=5
tau=2*pi


def png(p,w,h,data):
    def c(n,b):return struct.pack(">I",len(b))+n+b+struct.pack(">I",zlib.crc32(n+b))
    raw=b"".join(b"\0"+data[j*w*3:(j+1)*w*3] for j in range(h))
    p.write_bytes(b"\x89PNG\r\n\x1a\n"+c(b"IHDR",struct.pack(">IIBBBBB",w,h,8,2,0,0,0))+
                  c(b"IDAT",zlib.compress(raw,9))+c(b"IEND",b""))


def avg(a,b,weight):return tuple(u+(v-u)*weight for u,v in zip(a,b))
def sharp(a,b,t):
    t=min(1,max(0,(t-a)/(b-a)))
    return t*t*(3-2*t)


def pixel(x,z,stage):
    """Periodic in both horizontal axes, with common furrow peaks at integer phase."""
    soil,leaf,tip,w,density,heads=DATA[stage]
    warp=.056*sin(tau*(x+z))+.023*sin(tau*(3*x+2*z))
    f=(x-z)*ROWS+warp
    crest=.5+.5*cos(tau*f)
    primary=sharp(.12,.94,crest)
    # Sides of rows remain light/dark when changing soil color; glare does
    # not switch direction on ridges, tile seams or a change of slope.
    p=(x+z)%1
    bump=(.6+.4*cos(tau*(17*p+.12*sin(tau*3*f))))
    bunch=.58+.23*cos(tau*12*p)+.19*cos(tau*(5*p+2*f))
    canopy=sharp(1-w*1.5,1-w*.16,crest)*(.74+.26*bunch)
    base=avg(soil,avg(soil,leaf,.65),primary*.64)
    base=avg(base,leaf,canopy*min(1,.58+density))
    glitter=sharp(.42,1,bump*bunch)*canopy*heads
    base=avg(base,tip,glitter)
    # Pixel textures read well at low render view distances. A periodic
    # sparse grain detail adds terrace variation without noisy photographs.
    ix,iz=int((x%1)*64),int((z%1)*64)
    hash_=(ix*31337+iz*69421+(ix^iz)*71309)&65535
    grit=((hash_%7)-3)*.59
    variance=2.6*cos(tau*(5*x+4*z))+2.2*sin(tau*(x-z))+1.4*cos(tau*(16*x+11*z))
    light=(6.1*sin(tau*(f+.18))+variance+grit)*(.58+.42*(1-canopy))
    return tuple(max(0,min(255,round(v+light))) for v in base)


def fields():
    for s in range(len(DATA)):
        pixels=bytes(c for j in range(SIZE) for i in range(SIZE) for c in pixel((i+.5)/SIZE,(j+.5)/SIZE,s))
        png(R.TEXTURES/f"bl_farm_field_{s}.png",SIZE,SIZE,pixels)


def prism(m,n,col,a,b,h,depth,half,rise):
    """One flat-cut rail face, bevel/free ends and sectional grade joints."""
    z0,z1=-depth,depth
    def y(x):return h+(x+1)*rise*.5
    p=[(a,z0,y(a)-half),(b,z0,y(b)-half),(b,z1,y(b)-half),(a,z1,y(a)-half)]
    q=[(x,z,yy+2*half) for x,z,yy in p]
    F(m,n,col,p[::-1]);F(m,n,col,q)
    for j in range(4):
        k=(j+1)%4
        if j in (1,3) and (abs(a+1)<1e-7 or abs(b-1)<1e-7):continue
        F(m,n,col,(p[j],p[k],q[k],q[j]))


def hedge(m,style,rise):
    rng=Random(551+style)
    widths={1:(.114,.132,.165),4:(.183,.171,.233),5:(.082,.116,.146)}
    spread,fork,h=widths[style]
    n="Rounded field hedge"
    F(m,n+" dark ventilated branch core","hedge",(
       (-1,-spread*.6,.040),(1,-spread*.6,rise+.040),(1,0,rise+h),(-1,0,h)))
    for i in range(9):
        x=-.875+i*.21875
        y=(x+1)*rise/2
        r=rng.uniform(.093,.129)
        for sign in (-1,1):
            k=x+rng.uniform(-.02,.02)
            z=sign*rng.uniform(spread*.23,spread*.39)
            F(m,n+" visible branch and thorn stem","wood",
               ((x-.011,0,y-.006),(x+.011,0,y-.006),(k,z,y+fork)))
            S.ellipse(m,n+" dense individually shaped leaves",
                ("hedge","leaf","sunleaf")[(i+(1 if sign<0 else 0))%3],k,z,y+h*.58,
                min(r,1-abs(k)),spread*.72,h*.63,6)
        S.ellipse(m,n+" irregular light crest",("leaf","leaf","field_leaf")[i%3],
            x,0,y+h,r*.72,spread*.62,h*.45,6)


def posts(m,rise,style):
    n="Stock oak timber rail" if style==2 else "Stock simple exposed field palings"
    for i,x in enumerate((-.918,-.50,0,.50,.918) if style==3 else (-.93,-.32,.32,.93)):
        y=(x+1)*rise/2
        ht=(.183,.235,.193,.217,.206)[i] if style==3 else .229
        B(m,n+" solid eight-sided upright","paling_old" if i%3 else "warmclay",
            x,0,.046,.058,y-.027,y+ht,.008)
        B(m,n+" pointed cut timber cap","woodold",x,0,.037,.043,y+ht-.011,y+ht+.012,.006)
    if style==2:
        for h in (.080,.158):
            prism(m,n+" continuous rough split rail","paling",-1,1,h,.018,.018,rise)
    else:
        # Fine unobtrusive iron wire: rail-only appearance would not
        # distinguish stock sparsely spaced source posts from style 2.
        for h in (.094,.167):
            prism(m,n+" weathered taut strand","dark_metal",-1,1,h,.004,.004,rise)


def stone(m,rise):
    colors=("wall_dark","wall_bright","wall_lichen","wall_cap")
    n="Stock field drystone wall"
    rng=Random(146)
    for layer,(lo,hi,w) in enumerate(((.000,.069,.105),(.061,.139,.088),(.131,.19,.071))):
        count=11 if layer==2 else 9
        for i in range(count):
            a,b=-1+i*2/count,-1+(i+1)*2/count
            p=rng.uniform(.007,.016)
            a,b=a+(p if i else 0),b-(p if i<count-1 else 0)
            z=rng.uniform(-.022,.020)
            f=(a+b)/2
            y=(f+1)*rise/2
            # The side of each split limestone block is bevelled. Stepped
            # geology rises with the slope rather than pitching a whole wall.
            hw=w*rng.uniform(.90,1.09)
            radius=abs(b-a)*.5
            xy=((a,z-hw*.65),(a+radius*.32,z-hw),(b-radius*.32,z-hw),(b,z-hw*.55),
                (b,z+hw*.54),(b-radius*.37,z+hw),(a+radius*.28,z+hw),(a,z+hw*.65))
            levels=[[(x,zz,y+hh) for x,zz in xy] for hh in (lo-.023,hi+rng.uniform(-.008,.011))]
            a0,b0=levels
            F(m,n+" individual pale stone upper face",colors[3 if layer==2 else (i+layer)%4],b0)
            for j in range(8):
                k=(j+1)%8
                F(m,n+" chipped interlocking limestone block",colors[(i*3+j+layer)%3],(a0[j],a0[k],b0[k],b0[j]))


def fence(style,rise):
    m=A.mesh()
    if style==6:stone(m,rise)
    elif style in (2,3):posts(m,rise,style)
    else:hedge(m,style,rise)
    return m


def detail(stage):
    m=A.mesh()
    rng=Random(550+stage)
    if stage==8:
        for x,z in ((-.39,-.57),(.47,.24)):
            T(m,"Round stubble-field straw bale","ripe_head",(x-.106,z,.079),(x+.106,z,.079),.077,.077,10)
            for a in (-.056,.049):
                T(m,"Wheat bale wrap ribbons","dark_stubble",(x+a,z,.079),(x+a+.007,z,.079),.079,.079,10)
            T(m,"Cut exposed end ring small straw fibers","haygold",(x+.107,z,.079),(x+.109,z,.079),.051,.050,10)
    else:
        h=.118 if stage==6 else .094
        for line in (-1.2,-.8,-.4,0,.4,.8,1.2):
            for _ in range(6):
                x=rng.uniform(-.94,.94)
                z=x+line
                if abs(z)>.94:continue
                y=rng.uniform(h*.53,h*1.16); lean=rng.uniform(-.028,.027)
                u=x+lean
                F(m,"Thin visible barley stems","field_leaf",
                    ((x-.007,z,.001),(x+.007,z,.001),(u+.004,z+.014,y),(u-.005,z+.014,y)))
                F(m,"Visible barley standing stem opposite face","field_leaf",
                    ((u-.005,z+.013,y),(u+.004,z+.013,y),(x+.007,z-.001,.001),(x-.007,z-.001,.001)))
                S.ellipse(m,"Actual mature barley seed heads","ripe_head" if stage==6 else "ripe_barley",
                    u,z+.015,y,.010,.011,y*.23,5)
    return m


def export(m,name):
    # Convert centered native author coordinates to the normal Luanti
    # entity convention of ten OBJ units/node (not a static mesh node).
    out=A.mesh()
    for n,fs in m.parts.items():
        for ids,c in fs:
            out.face(n,c,[(10*x-.5,10*z-.5,10*h) for x,z,h in (m.vertices[n][i] for i in ids)])
    R.export_obj(R.MODELS/(name+".obj"),out,vertical_origin=0)


def install(m,name,mats,scene,location):
    export(m,name)
    c=bpy.data.collections.new(name);scene.collection.children.link(c)
    R.to_blender(m,c,mats)
    for o in c.objects:o.location=location


def overlays():
    # Use the existing stock terrain's exact plane topology/UVs, with only
    # a small raised origin so it can sit over the ordinary grass substrate.
    for mask in tuple(range(15))+(23,27,29,30):
        src=R.MODELS/f"bl_land_{mask}.obj"
        lines=src.read_text().splitlines()
        lines[0]="# Original crop surface overlay; stock terrain planes lifted .004 native nodes"
        for i,row in enumerate(lines):
            if row.startswith("v "):
                tag,x,y,z=row.split()
                lines[i]=f"{tag} {x} {float(y)+.004:.6f} {z}"
        (R.MODELS/f"bl_farm_land_{mask}.obj").write_text("\n".join(lines)+"\n")
        # The render node moves one host unit east when the ordinary
        # anchor is occupied by a bridge. OBJ uses the inverse X axis.
        shifted=list(lines)
        shifted[0]="# Same field plane, mesh anchor moved a node east so the bridge can coexist"
        for i,row in enumerate(shifted):
            if row.startswith("v "):
                tag,x,y,z=row.split()
                shifted[i]=f"{tag} {float(x)+1:.6f} {y} {z}"
        (R.MODELS/f"bl_farm_land_{mask}_shifted.obj").write_text("\n".join(shifted)+"\n")


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    s=bpy.context.scene;s.name="Highfield original terrain and field boundaries"
    s["Entity convention"]="10 OBJ units/native node, positive X axis along edge, pivot at center and lowest corner."
    s["Stock appearance"]="OpenGFX stages 0–8 and fence types 1–6 used as historical reference; modeled new meshes and drawn original ground."
    mats=R.materials()
    for j,name in enumerate(PAL):mats[j].name=name
    for style in range(1,7):
        for grade in (0,1):
            install(fence(style,grade),f"bl_farm_fence_{style}_{grade}",mats,s,(0,style*.67,grade*1.06))
    for stage in (5,6,8):
        install(detail(stage),f"bl_farm_field_detail_{stage}",mats,s,(-2.3,1.12+(stage-5)*1.6,0))
    S.atlas("farm_fence",PAL)
    fields()
    overlays()
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":
                v=area.spaces.active;v.shading.color_type="MATERIAL"
                v.region_3d.view_location=(-.35,2.39,.27);v.region_3d.view_distance=8
                v.region_3d.view_rotation=(Vector((-.35,2.39,.27))-Vector((3,-4,4))).to_track_quat("-Z","Y")
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art/stock_temperate_field_boundaries.blend"),compress=True)


if __name__=="__main__":main()

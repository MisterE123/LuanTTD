#!/usr/bin/env python3
"""Original RC1 Temperate Bank site; two exact partitions for GFX 58 and 59.

STOCK_BANK_RENDER=/tmp/stock-bank.png blender -b -t 2 --python-exit-code 1 \
  --python tools/build_stock_temperate_bank_art.py
Coordinates are site X/Z and height above a flat native-grade foundation.
"""
from math import cos, pi, sin
from pathlib import Path
from random import Random
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_stock_farm_art as S

R,A=S.R,S.A
B,T,F,Q=S.B,S.T,S.F,S.Q
ROOT=Path(__file__).resolve().parents[1]
PAL=dict(S.PAL, **{
    "granite_foundation":"858a84","bankstone":"c5b79c","bankstone_light":"d4c6a8",
    "bankstone_shadow":"ad9d85","mortar_bedding":"a69c88","salt_mortar":"c4bca5",
    "bronzed_doors":"665846","oxidized_bronze":"6a8678","bronze_highlight":"b0a881",
    "patina":"70867a","ribbed_copper":"596c62","rib_dark":"485d56",
    "blackened_rail":"39423e","fine_metal":"747d75","lamp_amber":"d1bd83",
    "storefront":"597580","window_glints":"9dac9d","green_enamel":"3d6358",
    "service_yard":"777b75","bankway":"949387","street_stone":"9f9989",
    "cabinet_steel":"656e68","vault_glint":"989c8c","bunting_green":"657450",
    "planted_shadow":"59624c","leaf_sheen":"86916b","bank_maroon":"76594d","vault_mark":"bea470",
})
A.PAL=PAL
A.P=A.H.P={name:i for i,name in enumerate(PAL)}
R.COLORS[:]=PAL.values()
A.DIGITS["K"]=("10001","10010","10100","11000","10100","10010","10001")
STEM="industry_temperate_bank"
LAYOUT={(0,0):58,(1,0):59}
PIN="07b339c0aaeb0a87be9490b2f1c3f17c6b00b837"


def beam(m,n,c,a,b,w=.021,nside=4):
    T(m,n,c,a,b,w,w,nside)


def stones(m,n,x,z,support_y,rows,columns,w,d,h=.13):
    rng=Random(684+rows)
    for j in range(rows):
        row=columns if j%2==0 else columns+1
        for k in range(row):
            a,b=x-w/2+k*w/row,x-w/2+(k+1)*w/row
            base=support_y+j*h+.004
            B(m,n+" dressed ashlar relief",rng.choice(("bankstone","bankstone_light","bankstone","bankstone_shadow")),
              (a+b)/2,z,(b-a)-.006,d,base,base+h-.008,.004)


def window(m,n,x,z,low,w,h,c="bankstone_light",seg=14):
    # Real curved masonry voussoirs sit around a separate glass cameo.
    mid=low+h-w/2
    B(m,n+" shallow bronze window frame","bronzed_doors",x,z,w+.04,.046,low-.014,mid+.013,.009)
    B(m,n+" long paned sash","storefront",x,z+.028,w-.025,.024,low+.035,mid+.001,.006)
    segs=[]
    for i in range(seg+1):
        t=i*pi/seg
        segs.append((x+w*.5*cos(t),z+.043,mid+w*.5*sin(t)))
    F(m,n+" curved translucent fanlight","storefront",segs[::-1])
    for j in range(seg):
        u,v=j*pi/seg,(j+1)*pi/seg
        def p(t,r,y):return x+r*cos(t),z+.055,mid+r*sin(t)
        r=w*.5
        F(m,n+" tapered stone arch voussoir",c if j%2 else "bankstone_shadow",
            (p(u+.013,r,.05),p(u+.013,r+.061,.052),p(v-.013,r+.061,.052),p(v-.013,r,.05)))
    for x0 in (-w*.50,w*.50):
        B(m,n+" pilaster window jamb",c,x+x0,z+.034,.040,.055,low-.004,mid+.013,.006)
    B(m,n+" long square stone sill",c,x,z+.057,w+.117,.077,low-.027,low+.015,.007)
    B(m,n+" double glazing transom","oxidized_bronze",x,z+.050,w-.026,.014,mid-.031,mid+.006,.003)
    B(m,n+" bronze sash muntin","blackened_rail",x,z+.047,.010,.014,low+.038,mid+.028,.002)
    for j in (-1,1):
        B(m,n+" reflected panel band","window_glints",x+j*w*.23,z+.046,w*.28,.012,mid-.082,mid-.047,.003)
    beam(m,n+" radial fanlight glazing member","oxidized_bronze",(x,z+.049,mid),(x+w*.3,z+.049,mid+w*.355),.008,5)
    beam(m,n+" radial fanlight glazing member","oxidized_bronze",(x,z+.049,mid),(x-w*.3,z+.049,mid+w*.355),.008,5)


def column(m,n,x,z,base,r,h):
    T(m,n+" stone podium ring","granite_foundation",(x,z,base-.05),(x,z,base+.055),r*1.29,r*1.15,16)
    T(m,n+" capital shaft footing","bankstone",(x,z,base+.053),(x,z,base+.099),r*1.16,r,18)
    T(m,n+" limestone shaft with classical entasis","bankstone_light",(x,z,base+.097),(x,z,h-.08),r,r*.83,18)
    for i in range(10):
        a=i*pi/5
        beam(m,n+" individually raised fluting shadow","bankstone_shadow",
             (x+r*.97*cos(a),z+r*.97*sin(a),base+.136),(x+r*.818*cos(a),z+r*.818*sin(a),h-.085),.008,6)
    T(m,n+" cast rounded astragal collar","bankstone_light",(x,z,h-.08),(x,z,h-.039),r*.83,r*1.22,16)
    B(m,n+" square stone capital","bankstone_light",x,z,r*2.59,r*2.61,h-.04,h+.014,.009)


def shield(m,n,x,z,h,r):
    T(m,n+" circular raised bronze medallion","bronzed_doors",(x,z,h),(x,z+.031,h),r,r,18)
    T(m,n+" inset old-gold circular seal","bronze_highlight",(x,z+.032,h),(x,z+.041,h),r*.781,r*.781,18)
    vv=[(x-r*.47,z+.046,h+r*.31),(x+r*.47,z+.046,h+r*.31),(x+r*.37,z+.047,h-r*.13),
        (x,z+.059,h-r*.46),(x-r*.37,z+.047,h-r*.13)]
    F(m,n+" shaped bronze shield","green_enamel",vv)
    for q in (-1,1):
        beam(m,n+" double bar crest","bronze_highlight",(x+q*r*.16,z+.05,h-r*.12),(x+q*r*.16,z+.05,h+r*.17),.010)


def civic_base(m):
    # Under the tile split the entire building and street plinth occupy one
    # continuous native grade. No ground plane or dark lip outside the footprint.
    Q(m,"Complete contiguous bank stone forecourt","street_stone",-.5,3.5,-.5,1.5,.004)
    Q(m,"Joint pedestrian sidewalk across the tile seam","bankway",-.48,3.48,1.137,1.476,.012)
    for x in (-.295,.054,.393,.735,1.081,1.435,1.785,2.130):
        for z in (1.171,1.334):
            B(m,"Individual smooth courtyard stone setts","bankstone_shadow" if int(x*100)%3 else "bankstone_light",
              x,z,.328,.129,.009,.021,.009)
    B(m,"One continuous dark granite plinth crossing native seam","granite_foundation",.843,.212,
      2.45,1.305,.008,.172,.043)
    B(m,"One continuous upper sandstone footing crossing seam","bankstone_shadow",.843,.226,
      2.41,1.228,.167,.241,.026)
    B(m,"Low flush slab beneath annex sheltered vehicle bay","granite_foundation",2.676,.227,
      1.27,1.284,.013,.054,.027)
    B(m,"Right apron edge sandstone separately supporting pier","bankstone_shadow",3.371,.214,
      .166,1.21,.017,.191,.021)
    for x in (-.316,2.013):
        B(m,"Raised gold limestone yard planter","bankstone",x,1.191,.169,.229,.025,.119,.023)
        for i in range(5):
            a=i*2*pi/5
            S.ellipse(m,"Individual trimmed foliage facets at bank entrance",
                      "leaf_sheen" if i%2 else "bunting_green",x+.031*cos(a),1.191+.054*sin(a),.123+i*.008,
                      .059,.062,.061,7)
    for x in (-.292,2.127,3.357):
        z=1.288 if x<2.3 else 1.331
        B(m,"Stone pedestal under cast entrance lamp","bankstone",x,z,.067,.065,.017,.084,.014)
        T(m,"Thin cut bank street lamp pillar","blackened_rail",(x,z,.068),(x,z,.546),.016,.014,8)
        T(m,"Glazed warm lantern panels","lamp_amber",(x,z,.525),(x,z,.598),.037,.026,6)
        T(m,"Painted lamp finial and top","blackened_rail",(x,z,.596),(x,z,.631),.043,.009,7)


def main_hall(m):
    name="GFX58 public banking hall"
    x,z=.558,.241
    B(m,name+" lower solid ashlar volume","bankstone",x,z,1.80,1.13,.237,1.482,.023)
    stones(m,name,x,.812,.25,8,9,1.746,.032,h=.153)
    for X in (-.353,1.467):
        B(m,name+" compact architect's corner quoins","bankstone_light",X,.782,.127,.131,.243,1.508,.009)
        for i in range(7):
            B(m,name+" alternate bonded quoin","bankstone_shadow",X+.019,.853,.158,.039,.270+i*.18,.325+i*.18,.007)
        for d in (-.214,.151,.472):
            B(m,name+" deep tall side window","storefront",X+(-.006 if X<0 else .007),d,.027,.152,.658,1.024,.008)
            B(m,name+" side window pale lintel","bankstone_light",X,d,.057,.192,1.014,1.068,.009)
    for X in (-.095,1.193):
        window(m,name,X,.824,.563,.290,.708)
    dx=.55
    # Separate door leaves, two pulls and genuine relief masonry portal.
    B(m,name+" giant deep portal arch backing","bankstone_shadow",dx,.837,.506,.118,.312,1.281,.018)
    window(m,name+" entrance glazed arch",dx,.910,.336,.373,.803,"bankstone_light",18)
    for q in (-1,1):
        X=dx+q*.091
        B(m,name+" separate bronze double door leaf","bronzed_doors",X,.991,.178,.030,.344,.810,.006)
        B(m,name+" open-toned panel above door bottom","oxidized_bronze",X,.998,.136,.010,.480,.745,.004)
        B(m,name+" door bottom deep shadow kick plate","bank_maroon",X,1.007,.146,.013,.356,.463,.004)
        T(m,name+" vertical rounded bronze door pull","bronze_highlight",(X-q*.043,1.017,.492),(X-q*.043,1.017,.617),.015,.013,7)
    B(m,name+" landing flush with the top stair","granite_foundation",dx,.901,.693,.282,.125,.335,.024)
    for j in range(4):
        z1,z2=1.034+j*.071,1.105+j*.071
        B(m,name+" individually molded usable portico stair tread","bankstone_light",dx,
          (z1+z2)/2,.591+j*.027,z2-z1+.008,.021,.327-j*.074,.009)
    for u in (-.408,.408):
        B(m,name+" projecting stone footing below column","granite_foundation",dx+u,1.071,.201,.203,.111,.339,.016)
        column(m,name,dx+u,1.079,.341,.071,1.409)
    B(m,name+" broad triglyph entablature beam","bankstone_light",dx,1.005,1.153,.223,1.417,1.530,.012)
    for i in range(7):
        X=dx-.47+i*.156
        B(m,name+" cut frieze rectangular triglyph","bankstone_shadow",X,1.125,.036,.024,1.453,1.491,.004)
    B(m,name+" raised green ceramic uppercase bank plaque","green_enamel",dx,1.133,.027+.398,.023,1.479,1.558,.006)
    A.lettering(m,name+" separately raised BANK characters","BANK",(dx,1.148,1.520),.011,"south","bone")
    # Sculpture is real geometry across the pediment, not copied pixels.
    for f in (-1,1):
        Z=1.006+f*.144
        p=((dx-.632,Z,1.538),(dx+.632,Z,1.538),(dx,Z,1.972))
        F(m,name+" shallow triangle carved stone pediment","bankstone",p if f<0 else p[::-1])
    for q in (-1,1):
        a=(dx+q*.648,.845,1.527);b=(dx, .845,1.984)
        c=(dx,1.159,1.984);d=(dx+q*.648,1.159,1.527)
        F(m,name+" joined shallow lead surface over pediment","rib_dark",(a,b,c,d) if q>0 else (d,c,b,a))
    for q in (-1,1):
        for Z in (.844,1.162):
            beam(m,name+" raked pediment cornice","bankstone_light",
                 (dx+q*.654,Z,1.532),(dx,Z,1.989),.035)
    B(m,name+" roof apron lower coping continuous across seam","bankstone_light",1.418,.188,3.605,1.287,1.434,1.502,.015)
    B(m,name+" concealed flat lead main roof","rib_dark",x,.169,1.692,.967,1.499,1.557,.009)
    for i in range(8):
        X=-.171+i*.200
        B(m,name+" standing seam at lead roof edges","ribbed_copper",X,.171,.014,.994,1.551,1.569,.003)
    shield(m,name,dx,1.153,1.710,.102)


def vaulted_roof(m):
    name="GFX59 administrative vault and joined copper annex"
    x,z=2.511,.258
    B(m,name+" west projecting sandstone pier","bankstone",1.605,.289,.252,1.03,.240,1.403,.021)
    B(m,name+" east projecting sandstone pier","bankstone",3.389,.289,.160,1.03,.193,1.403,.017)
    B(m,name+" masonry back elevation","bankstone_shadow",x,-.249,1.71,.110,.208,1.444,.023)
    B(m,name+" heavy lintel above secure work bays","bankstone",x,.788,1.77,.157,.769,1.451,.013)
    stones(m,name,x,.872,.792,4,11,1.730,.037,.163)
    for X in (1.695,2.036,2.355,2.711,3.063,3.335):
        B(m,name+" inset narrow band of sash glazing","storefront",X,.907,.195,.031,1.033,1.322,.006)
        B(m,name+" upper muted individual glass reflection","window_glints",X,.929,.157,.011,1.225,1.281,.004)
        B(m,name+" glazing broad lower sill","bankstone_light",X,.934,.212,.045,1.016,1.054,.005)
        B(m,name+" central wrought vertical glazing muntin","blackened_rail",X,.932,.011,.013,1.055,1.317,.003)
    for i in (1.576,3.407):
        B(m,name+" exterior buttress under tied roof","granite_foundation",i,.815,.119,.113,.205,1.445,.008)
    # Copper barrel-vault monitor has a window wall and nonflat cross section.
    a0,a1=1.55,3.47
    rz=.469
    count=18
    def p(t,X):
        return X,z+rz*cos(t),1.534+.355*sin(t)
    for i in range(count):
        a,b=i*pi/count,(i+1)*pi/count
        F(m,name+" individually shaded aged copper panels",
          ("patina","ribbed_copper","patina","rib_dark")[i%4],
          (p(a,a0),p(b,a0),p(b,a1),p(a,a1)))
        beam(m,name+" physically raised standing copper seams","rib_dark",p(a,a0-.006),p(a,a1+.006),.009)
    for X in (a0,a1):
        for i in range(count):
            a,b=i*pi/count,(i+1)*pi/count
            F(m,name+" vaulted tinted clerestory end glazing","storefront",
               (p(a,X),p(b,X),(X,z,1.535)) if X==a0 else (p(b,X),p(a,X),(X,z,1.535)))
            beam(m,name+" exposed structural arch glazing bar","fine_metal",p(a,X),p(b,X),.018)
            if i%4==0:
                beam(m,name+" real radial clerestory support mullion","blackened_rail",(X,z,1.535),p(a,X),.011)
    for i in range(5):
        X=1.755+i*.390
        for j in range(count):
            a,b=j*pi/count,(j+1)*pi/count
            beam(m,name+" raised curved copper reinforcing rib","rib_dark",p(a,X),p(b,X),.009)
    Q(m,name+" annex actual car apron within the second parcel","service_yard",2.116,3.25,.69,1.477,.056)
    for X in (2.134,3.221):
        B(m,name+" inset separate vehicle apron curb","granite_foundation",X,1.107,.059,.727,.055,.104,.010)
    for j in range(5):
        Y=.808+j*.132
        for X in (2.187,3.171):
            Q(m,name+" painted vehicle clearance edge marking","vault_mark",X-.013,X+.013,Y,Y+.057,.058)
    # The driveway is open south under a structural lintel. At the end is
    # a distinct recessed steel rolling shutter across the actual loading bay.
    for X in (2.088,3.236):
        B(m,name+" structural outer pier on either side of open drive","bankstone_light",X,.685,.128,.201,.14,.836,.016)
    B(m,name+" recessed vault receiving roller shutter recess","blackened_rail",2.686,.485,1.01,.102,.083,.781,.021)
    for j in range(15):
        h=.125+j*.041
        B(m,name+" separate metal roller shutter slat","cabinet_steel",2.687,.541,.951,.021,h,h+.026,.006)
    for X in (2.198,3.190):
        B(m,name+" chamfered cast metal vault shutter guide","fine_metal",X,.563,.058,.060,.097,.783,.009)
        T(m,name+" anchored receiving bollard","vault_mark",(X,.746,.068),(X,.746,.222),.029,.029,8)
        T(m,name+" bollard safety cap","bronze_highlight",(X,.746,.217),(X,.746,.244),.031,.023,8)
    B(m,name+" separate pedestrian staff entrance","bronzed_doors",1.849,.918,.197,.042,.246,.715,.011)
    B(m,name+" reflective staff entrance transom","storefront",1.849,.947,.155,.023,.650,.735,.006)
    B(m,name+" bronze employee door plate","bronze_highlight",1.847,.946,.129,.012,.405,.449,.005)


GROUPS=(("Cross-tile paved foundation and original street furniture",civic_base),
        ("GFX58 banking hall, sculpted arch, portico and double doors",main_hall),
        ("GFX59 secure receiving bays, metal shutters and copper monitor",vaulted_roof))


def triangulated(m):
    out=A.mesh()
    for n,faces in m.parts.items():
        for ids,c in faces:
            p=[m.vertices[n][i] for i in ids]
            for j in range(1,len(p)-1):
                out.face(n,c,(p[0],p[j],p[j+1]))
    return out


def source_mesh():
    m=A.mesh()
    for _,f in GROUPS:f(m)
    return triangulated(m)


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    sc=bpy.context.scene
    sc.name="Temperate Bank - OpenTTD RC1 stock industry 12"
    sc["Upstream source"]=f"OpenTTD 16.0-RC1 {PIN} src/table/build_industry.h _tile_table_bank_0"
    sc["Exact occupancy"]="(0,0) GFX58, (1,0) GFX59 (national Temperate industry ID 12)"
    sc["Datum"]="Z up, floor Z=0, visual NW overlay at native grade + 1 per 2×2 logical cell."
    mats=R.materials()
    for i,k in enumerate(PAL): mats[i].name=k.replace("_"," ").title()
    for title,f in GROUPS:
        m=A.mesh()
        f(m)
        c=bpy.data.collections.new(title)
        sc.collection.children.link(c)
        R.to_blender(triangulated(m),c,mats)
    m=source_mesh()
    for (x,z),gfx in LAYOUT.items():
        p=R.MODELS/f"bl_{STEM}_{x}_{z}.obj"
        R.export_obj(p,triangulated(S.clip(m,x,z,LAYOUT)))
        p.write_text(f"# OpenTTD 16.0-RC1 Temperate Bank ID 12, layout 0 ({x},{z}) GFX {gfx}; original Blender art\n"
                     +p.read_text().split("\n",1)[1])
    S.atlas(STEM,PAL)
    look=Vector((1.45,.27,.79))
    cam=Vector((5.1,7.65,4.18))
    rot=(look-cam).to_track_quat("-Z","Y")
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":
                view=area.spaces.active
                view.shading.color_type="MATERIAL"
                view.region_3d.view_location=look
                view.region_3d.view_distance=6.1
                view.region_3d.view_rotation=rot
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art"/"stock_temperate_bank.blend"),compress=True)
    if not os.getenv("STOCK_BANK_RENDER"):return
    bpy.ops.mesh.primitive_plane_add(size=24,location=(1.4,.2,-.002))
    lower=bpy.data.materials.new("Surrounding pavement")
    lower.diffuse_color=(.252,.279,.248,1)
    bpy.context.object.data.materials.append(lower)
    cameradata=bpy.data.cameras.new("Street and roof review")
    ob=bpy.data.objects.new("Street and roof review",cameradata)
    sc.collection.objects.link(ob)
    ob.location=cam
    ob.rotation_euler=rot.to_euler()
    ob.data.type="ORTHO"
    ob.data.ortho_scale=4.72
    sc.camera=ob
    sc.render.engine="BLENDER_WORKBENCH"
    sc.render.resolution_x=1370
    sc.render.resolution_y=970
    s=sc.display.shading
    s.color_type="MATERIAL"
    s.show_shadows=True
    s.show_cavity=True
    s.cavity_type="BOTH"
    s.cavity_ridge_factor=1.14
    sc.view_settings.view_transform="Standard"
    sc.render.filepath=os.environ["STOCK_BANK_RENDER"]
    bpy.ops.render.render(write_still=True)


if __name__=="__main__":
    build()

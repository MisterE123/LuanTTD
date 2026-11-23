#!/usr/bin/env python3
"""Original conventional RC1 Livestock Van #31 and Grain Hopper #33."""
from copy import deepcopy
from pathlib import Path
from math import cos, sin, tau, pi
from random import Random
import os,sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
import build_stock_rail_metals_art as M
from build_stock_rail_metals_art import B,T,bar,J,r,w,bpy,V
EXTRA={
 "Grain filled sunlit gold":"c39541","Grain straw bright":"dfb75d","Grain deep rolled shadow":"ad792f",
 "Grain creamy high grain":"e8c975","Grain ground husks":"bf8b38",
}
def pal(stock):
    p=M.setup(35)
    for old,(name,color) in zip(("Iron oxidized upper","Iron heat glint","Iron density dark","Iron ochre facet","Iron wet seam"),EXTRA.items()):
        i=list(p).index(old)
        entries=list(p.items());entries[i]=(name,color);p=dict(entries)
    if stock==31:
        p|={"Mineral enamel navy":"2b5982","Mineral top milled rim blue":"6283a3","Mineral weathered highlight":"48769c",
            "Well inner soot":"25272a","Mineral steep metal pan":"33455a","Warm bauxite buffer beam":"373b42",
            "Guide iron":"62615a","Body graphite":"353a40"}
    else:
        p|={"Mineral enamel navy":"576474","Mineral top milled rim blue":"899097","Mineral weathered highlight":"667386",
            "Mineral steep metal pan":"565e6b","Well inner soot":"303a47","Warm bauxite buffer beam":"465361"}
    M.P=w.P={n:i for i,n in enumerate(p)}
    r.COLORS[:]=p.values()
    return p
def f(o,g,c,pts):M.f(o,g,c,pts)
def livestock(o):
    B(o,"Separate sealed timber-clad deck under the slatted coach","Flatcar hardwood brown",0,0,.402,.797,.191,.230,.010)
    # True open air between each steel slat, even on the doors.
    for s in (-1,1):
        x=s*.207
        B(o,"Cold rolled blue horizontal side base beam","Mineral enamel navy",x,0,.022,.812,.219,.264,.004)
        B(o,"Cold rolled continuous blue fascia under ventilated roof","Mineral enamel navy",x,0,.026,.812,.441,.481,.003)
        B(o,"Independent darker edge of ventilation sill","Mineral steep metal pan",x,0,.028,.816,.259,.270,.003)
        for z in (-.383,-.276,-.179,-.086,.086,.179,.276,.383):
            B(o,"Original eight vertical braced wall posts on each flank","Mineral weathered highlight",x,z,.026,.024,.265,.449,.004)
            for h in (.286,.420):
                T(o,"Stock van structural rivets on separately modelled wall posts","Mineral top milled rim blue",
                  (s*.223,z,h),.0055,"x",-.002,.002,7)
        for z in (-.254,.254):
            for h in (.300,.349,.398):
                B(o,"Three genuine long open ventilation stiles on either side of the sliding door","Mineral enamel navy",
                  s*.210,z,.017,.313,h-.012,h+.012,.003)
                B(o,"Raised reflective strip along each ventilated steel stile","Mineral weathered highlight",
                  s*.221,z,.004,.306,h+.004,h+.010,.002)
        B(o,"Long external top sliding door track","Guide iron",s*.231,-.071,.014,.374,.434,.445,.003)
        for z in (-.071,.071):
            B(o,"Independent outer sliding door framing channels","Mineral top milled rim blue",
                s*.227,z,.016,.021,.267,.436,.003)
            T(o,"Machined door rollers under the longitudinal rail","Cold rolled coil edge",(s*.239,z,.434),.009,"x",-.004,.003,10)
        for h in (.288,.329,.370,.412):
            B(o,"Genuinely ventilated livestock door horizontal slats","Mineral weathered highlight",
              s*.230,0,.012,.128,h-.012,h+.012,.003)
        bar(o,"Diagonal reinforcement on the separate sliding livestock door","Mineral enamel navy",
            (s*.235,-.064,.275),(s*.235,.064,.418),.012,.010)
        B(o,"Independent animal carriage loading latch","Cold rolled coil edge",s*.241,.070,.009,.025,.338,.360,.003)
        for h in (.207,.218):
            B(o,"Non-slip livestock loading step","Guide iron",s*.207,0,.066,.190,h-.005,h+.006,.006)
        # Weather-dark eaves with original head-end plates.
        bar(o,"Long metal eave gutter above animal cargo","Body graphite",
            (s*.213,-.415,.476),(s*.213,.415,.476),.017,.014)
        B(o,"Solid painted end pan","Mineral enamel navy",0,s*.403,.409,.021,.226,.483,.010)
        for x in (-.152,0,.152):
            B(o,"Individual wagon end stiffeners","Mineral weathered highlight",x,s*.419,.020,.014,.249,.474,.004)
        for x in (-.094,.094):
            bar(o,"External animal van yard grabrail","Guide iron",(x,s*.428,.279),(x,s*.428,.335),.007,.014)
    # Curved rolled weather roof as a sealed volume, distinct from the
    # blue armour van's broad side armour and low central solid vault.
    x=(-.220,-.208,-.170,-.120,-.057,.057,.120,.170,.208,.220)
    h=(.473,.486,.508,.526,.539,.539,.526,.508,.486,.473)
    rings=[[(i,z,j-d) for i,j in zip(x,h)] for z,d in ((-.425,0),(.425,0),(.425,.011),(-.425,.011))]
    roof="Independent weather-black rolled livestock roof"
    for i,a in enumerate(rings):
        b=rings[(i+1)%4]
        for j in range(len(a)-1):
            f(o,roof,"Body graphite" if (i+j)%3 else "Deep chassis iron",(a[j],b[j],b[j+1],a[j+1]))
    for k in (0,-1):f(o,roof,"Deep chassis iron",[row[k] for row in rings][::1 if k==-1 else -1])
    for z in (-.302,-.105,.106,.303):
        for i in range(1,len(x)-2):
            bar(o,"Low zinc seams following the roof curvature","Body sunward",
                (x[i],z,h[i]),(x[i+1],z,h[i+1]),.006,.007)

def grain(o):
    # Wide, shallow, straight-sided flange and two real slope changes;
    # iron ore's tall external ribs and steep hopper lip are distinct.
    levels=(M.ring(.172,.362,.207,.025),M.ring(.192,.374,.255,.025),
      M.ring(.215,.401,.393,.029),M.ring(.221,.411,.426,.030),
      M.ring(.199,.386,.423,.027),M.ring(.145,.349,.260,.022))
    n="Continuous closed flanged bowl with an empty recessed grain well"
    f(o,n,"Well inner soot",levels[0][::-1])
    for k,(a,b) in enumerate(zip(levels,levels[1:])):
        for i in range(8):
            j=(i+1)%8
            tone=("Mineral weathered highlight","Mineral enamel navy","Mineral top milled rim blue",
                  "Mineral top milled rim blue","Well inner soot")[k]
            f(o,n,tone,(a[i],a[j],b[j],b[i]))
    f(o,n,"Mineral steep metal pan",levels[-1])
    for s in (-1,1):
        bar(o,"Raised continuous metallic box toe trim swage","Mineral weathered highlight",
           (s*.194,-.372,.286),(s*.194,.372,.286),.015,.020)
        for z in (-.316,-.159,0,.159,.316):
            bar(o,"Five structurally separate short simple grey reinforcing knees","Mineral weathered highlight",
               (s*.179,z,.254),(s*.217,z,.386),.016,.015)
            B(o,"Grain hopper knee foot pads","Mineral steep metal pan",s*.183,z,.021,.043,.245,.262,.004)
        for z in (-.234,.231):
            B(o,"Independent double discharge trap door flange","Mineral steep metal pan",s*.077,z,.154,.166,.194,.227,.006)
            T(o,"Gate control on the footwell","Guide iron",(s*.168,z,.230),.014,"x",-.023,.021,10)
            bar(o,"Release trap lever","Oxidised irons",(s*.164,z,.228),(s*.215,z+.031,.160),.013,.013)
        B(o,"Standalone end wide reinforced hopper rim","Mineral top milled rim blue",0,s*.403,.353,.021,.402,.426,.006)
        for x in (-.139,.139):
            B(o,"Damped end lower stiffener blocks","Mineral steep metal pan",x,s*.389,.037,.017,.265,.349,.004)
        B(o,"Original circular grain carrier marker backdrop","Original wagon stencil background",s*.222,.081,.011,.106,.331,.377,.005)
        for z in (.064,.081,.098):
            bar(o,"Original slim stylized wheat badge stripe","Original wagon stencil straw",
               (s*.230,z,.339),(s*.230,z+.008,.367),.004,.003)

def kernels(o):
    rng=Random(330016)
    name="Sealed golden grain mass, sunlit sloping shallow surface"
    shade=list(EXTRA)
    n,m=18,30
    rows=[]
    for j in range(m+1):
        z=-.371+.742*j/m
        xlim=.189-.015*(abs(z)/.371)**5
        row=[]
        for i in range(n+1):
            x=xlim*(-1+2*i/n)
            h=.387+.023*(1-(x/xlim)**2)*max(0,cos(z*3.65))+.002*cos(z*45)+rng.uniform(-.003,.003)
            row.append((x,z,h))
        rows.append(row)
    for a,b in zip(rows,rows[1:]):
        for i in range(n):f(o,name,rng.choice(shade),(a[i],a[i+1],b[i+1],b[i]))
    rim=rows[0][:-1]+[p[-1] for p in rows[:-1]]+rows[-1][:0:-1]+[p[0] for p in rows[:0:-1]]
    base=[(x*.74,z*.90,.262) for x,z,h in rim]
    for i,a in enumerate(rim):
        j=(i+1)%len(rim)
        f(o,name,"Grain deep rolled shadow",(a,base[i],base[j],rim[j]))
        f(o,name,"Grain ground husks",(base[j],base[i],(0,0,.262)))
    for iz in range(12):
        for ix in range(7):
            x=(ix-3)*.041+rng.uniform(-.013,.013)
            z=(iz-5.5)*.059+rng.uniform(-.013,.013)
            h=.388+.023*(1-(x/.189)**2)*max(0,cos(z*3.65))+.002*cos(z*45)
            ang=rng.random()*tau
            a=[(x+cos(ang+j*tau/5)*.008,z+sin(ang+j*tau/5)*.005,h-.005) for j in range(5)]
            b=[(x+(u-x)*.72,z+(v-z)*.73,min(.421,h+rng.uniform(.004,.009))) for u,v,_ in a]
            g=f"Independent light grain husk {iz*7+ix+1:02d}"
            f(o,g,"Grain ground husks",a[::-1]);f(o,g,rng.choice(shade),b)
            for j in range(5):
                k=(j+1)%5;f(o,g,rng.choice(shade),(a[j],a[k],b[k],b[j]))

def build(stock,stem,title,fn,load=None,palette_factory=pal,
          source='build_stock_rail_farm_art.py',load_name='grain load'):
    p=palette_factory(stock)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    sc=bpy.context.scene
    sc.name=f"LuanTTD • {title} #{stock}"
    sc["stock"]="OpenTTD 16.0-RC1 conventional rail. Standard gauge, knuckles and tread datum."
    mats=r.materials()
    for name,mat in zip(p,mats):mat.name=name
    gear=M.m();M.underframe(gear,stock==33)
    body=M.m();fn(body)
    J.geometry(sc,"01 • Standard rolling stock frame and couplers",gear,mats)
    J.geometry(sc,"02 • Body, cargo door/rim, detail and end plates",body,mats)
    complete=deepcopy(gear);fn(complete)
    modes=[("_empty" if load else "",complete)]
    extra=None
    if load:
        cargo=M.m();load(cargo)
        extra=J.geometry(sc,f"03 • Separate editable removable {load_name}",cargo,mats)
        full=deepcopy(complete)
        for name,parts in cargo.parts.items():
            for points,c in parts:full.tri(name,c,[cargo.vertices[name][i] for i in points])
        modes.append(("_loaded",full))
    for suffix,mesh in modes:
        path=ROOT/"mods/luanttd_core/models"/f"bl_{stem}{suffix}.obj"
        r.export_obj(path,w.local_obj(mesh))
        path.write_text(f"# Original {title}, RC1 #{stock}; tools/{source}\n"+path.read_text().split("\n",1)[1])
    M.palette(ROOT/"mods/luanttd_core/textures"/f"bl_{stem}_atlas.png",p)
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":
                v=area.spaces.active;v.shading.color_type="MATERIAL"
                v.region_3d.view_location=V((0,0,.26));v.region_3d.view_distance=1.75
                v.region_3d.view_rotation=V((.76,-.82,.61)).to_track_quat("Z","Y")
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art"/f"{stem}.blend"),compress=True)
    if "METALS_REVIEW" in os.environ:
        if extra is None:
            extra=bpy.data.collections.new("Empty preview toggle placeholder")
            sc.collection.children.link(extra)
        M.render(sc,stem,extra)

if __name__=="__main__":
    build(31,"rail_livestock_van","Livestock Van",livestock)
    build(33,"rail_grain_hopper","Grain Hopper",grain,kernels)

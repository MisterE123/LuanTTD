#!/usr/bin/env python3
"""Original one-tile lighthouse/transmitter. Optional STOCK_LANDMARKS_REVIEW=PNG."""
from math import cos, pi, sin, tau
import os
from pathlib import Path
import struct
import sys
import zlib

import bpy
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_rail_wagon_art as W
R=W.rail
PAL={
 "Stone pale grey":"c3c5b7","Stone glancing off white":"d7d7c9","Stone side pale":"b1b9ac",
 "Stone low cool shadow":"969e95","Stone footing rubbed":"898e83","Lime mortar joint":"a6a99e",
 "Blue slate shadow":"424b50","Slate roof main":"535f63","Slate highlight":"6f7c7b",
 "Sill grey casting":"787f73","Iron blue-black":"343e43","Iron grey":"616c6d","Regal lamp gold":"f9cd57",
 "Lamp warm ivory":"ffe595","Lamp dark window":"687253","Weathered brass":"9e8752",
 "Brass optic reflection":"d4af52","Cabinet muted pine grey":"747d73","Door blue green":"506759",
 "Deep glass blue":"344e54","Sky reflecting pane":"719594","Ground granite":"737974",
 "Mast white zinc":"b3b9ae","Mast pale tube edge":"91a39e","Mast shadow grey":"647674",
 "Catenary cable charcoal":"525e57","Dish inner graphite":"4b5455","Dish lip brushed steel":"85928d",
 "Dish highlight":"727e7d","Dish back nickel":"626f72","Antenna warning ruby":"b65148",
 "Small industry tags":"cebea0","Review meadow":"718063",
}
P={k:i for i,k in enumerate(PAL)}
R.COLORS[:]=PAL.values()
W.P=P
B,C=W.slab,W.circular


def mesh():
    return R.Mesh(R.terrain_height(0))


def face(m,n,c,p):
    m.face(n,P[c],p)


def member(m,n,mat,start,end,width,depth=None):
    a,b=Vector(start),Vector(end)
    line=(b-a).normalized()
    x=line.cross(Vector((0,0,1) if abs(line.z)<.95 else (0,1,0))).normalized()*width/2
    y=line.cross(x).normalized()*(depth or width)/2
    angles=(x+y,-x+y,-x-y,x-y)
    s,t=([tuple(v+w) for w in angles] for v in (a,b))
    face(m,n,mat,s[::-1]);face(m,n,mat,t)
    for i in range(4):
        j=(i+1)%4
        face(m,n,mat,(s[i],s[j],t[j],t[i]))


def turn(m,n,profile,colors,cx,cz,N=20):
    # Rotated horizontal rings and an optional smaller open inner ring.
    rings=[[(cx+r*cos(tau*i/N),cz+r*sin(tau*i/N),h)
            for i in range(N)] for h,r in profile]
    for k,(a,b) in enumerate(zip(rings,rings[1:])):
        for i in range(N):
            j=(i+1)%N
            choice=colors[k%len(colors)]
            if not isinstance(choice,str):choice=choice[i%len(choice)]
            face(m,n,choice,(a[i],a[j],b[j],b[i]))


def light(m):
    x,z=.255,.025
    stone=("Stone pale grey","Stone glancing off white","Stone pale grey","Stone side pale",
           "Stone pale grey","Stone low cool shadow","Stone side pale")
    turn(m,"Tapered grey-white lighthouse masonry shafts",[
        (0,.312),(.108,.312),(.142,.277),(.380,.260),(.641,.241),
        (.918,.218),(1.116,.200),(1.170,.190),(1.185,.215)],
        ["Stone footing rubbed","Stone side pale",stone,stone,stone,stone,stone,stone],x,z)
    for h,r in ((.140,.278),(.385,.262),(.642,.243),(.923,.220),(1.104,.204)):
        turn(m,"Separate dark stone bed joints across tower",
          [(h-.005,r-.001),(h,r+.004),(h+.005,r-.001)],["Lime mortar joint"],x,z)
    # Keeper’s service wing adjoins the shaft without hiding it.
    x0,x1=-.770,.146
    z0,z1=-.267,.306
    B(m,"Keeper's ashlar quarters with separate limestone foundation","Stone pale grey",
      (x0+x1)/2,(z0+z1)/2,x1-x0,z1-z0,0,.412,.017,"Stone side pale")
    for zz in (z0-.003,z1+.003):
        for h in (.076,.165,.262,.355):
            B(m,"Individually laid keeper cottage limestone course joints","Lime mortar joint",
              (x0+x1)/2,zz,x1-x0-.035,.006,h,h+.003)
    zz=(z0+z1)/2
    xa,xb=x0-.035,x1+.018
    for j,(u,v,h,k) in enumerate(((z0-.047,zz+.008,.409,.579),(zz+.008,z1+.047,.579,.409))):
        q=((xa,u,h),(xb,u,h),(xb,v,k),(xa,v,k))
        face(m,"Bowed slate main roof slopes and ridge flashing","Slate roof main" if not j else "Blue slate shadow",q)
        for n in range(1,6):
            t=n/6
            member(m,"Sawn slate courses under the shallow roof pitches","Slate highlight" if n%4==0 else "Blue slate shadow",
              (xa,u+(v-u)*t,h+(k-h)*t+.002),(xb,u+(v-u)*t,h+(k-h)*t+.002),.008,.004)
    for xx in (xa,xb):
        q=((xx,z0-.035,.413),(xx,z1+.035,.413),(xx,zz+.008,.578))
        face(m,"Separate shaped slate gable and mortar fascia","Stone side pale",q if xx>0 else q[::-1])
    member(m,"Core extruded slate ridge cap","Slate highlight",(xa,zz+.008,.583),(xb,zz+.008,.583),.026,.010)
    B(m,"Cast service door mortar lintel and reveal","Sill grey casting",-.575,z1+.008,.162,.018,.025,.350,.006)
    B(m,"Paneled keeper access blue-green door","Door blue green",-.575,z1+.019,.126,.009,.029,.331,.005)
    B(m,"Small keeper door rubbed brass latch","Weathered brass",-.535,z1+.026,.015,.007,.171,.190,.002)
    for xx in (-.277,-.026):
        B(m,"Sash windows with separate dressed stone sills","Stone glancing off white",xx,z1+.008,.132,.022,.183,.355,.006)
        B(m,"Recessed double-louvered cottage panes","Deep glass blue",xx,z1+.021,.108,.007,.205,.338,.005)
        B(m,"Pale bright lintel line across glazing","Sky reflecting pane",xx,z1+.025,.103,.006,.299,.320,.002)
        B(m,"Separate sash center mullion","Stone glancing off white",xx,z1+.027,.010,.006,.206,.334,.001)
    for h,t,rr in ((.297,.12,.263),(.708,.103,.237),(1.005,.09,.212)):
        B(m,"Inset small narrow lighthouse service windows","Iron blue-black",x,z+rr,.053,.010,h,h+t,.006)
        B(m,"Narrow window cool glass insert","Sky reflecting pane",x,z+rr+.006,.029,.007,h+.014,h+t-.012,.002)
    # True 360° stone cornice, metal parapet and warm divided lantern.
    turn(m,"Stepped walk-round round stone lantern gallery",
      [(1.173,.192),(1.193,.239),(1.220,.257),(1.239,.261),(1.248,.220)],
      ["Stone footing rubbed","Stone pale grey","Iron grey","Iron blue-black"],x,z)
    turn(m,"Turned glass lantern panes divided by dark metal stanchions",
      [(1.246,.176),(1.285,.174),(1.443,.164),(1.468,.172)],
      ["Iron blue-black",("Lamp dark window","Brass optic reflection","Regal lamp gold","Lamp warm ivory",
        "Regal lamp gold","Brass optic reflection","Lamp dark window","Lamp dark window"),"Iron blue-black"],x,z,16)
    for i in range(12):
        a=tau*i/12
        px,pz=x+.176*cos(a),z+.176*sin(a)
        member(m,"Black narrow lens window mullion","Iron blue-black",(px,pz,1.258),(px,pz,1.453),.010)
        q=(x+.257*cos(a),z+.257*sin(a))
        member(m,"Open top lantern inspection gallery rail stanchion","Iron grey",(*q,1.226),(*q,1.319),.009)
        b=a+tau/12
        member(m,"Separate circular upper lantern gallery railing","Iron blue-black",(*q,1.316),
          (x+.257*cos(b),z+.257*sin(b),1.316),.010)
    turn(m,"Separate rain-cut slate lantern cupola and finial",
      [(1.453,.183),(1.477,.200),(1.495,.185),(1.560,.093),(1.594,.018),(1.612,.006)],
      ["Iron blue-black","Slate roof main","Slate highlight","Slate roof main","Weathered brass"],x,z,16)
    C(m,"Tiny polished capstone for lightning spike","Weathered brass",(x,z,0),.015,"h",1.590,1.617,10)
    member(m,"Top clearly silhouetted small lighthouse finial","Iron grey",(x,z,1.614),(x,z,1.686),.010)


def dish(m,angle,h,sz,offset):
    a=Vector((cos(angle),sin(angle),.055))
    a.normalize()
    u=Vector((-sin(angle),cos(angle),0))
    v=a.cross(u)
    center=Vector((0,0,h))+offset*a
    n=12
    def ring(r,sag):
        return [tuple(center+r*(u*cos(i*tau/n)*.82+v*sin(i*tau/n))+a*sag) for i in range(n)]
    back=(ring(.035,0),ring(sz*.54,.020),ring(sz,.064))
    front=(ring(.035,.012),ring(sz*.54,.031),ring(sz,.075))
    face(m,"Dish centre clamp bolted to brace","Dish lip brushed steel",back[0][::-1])
    face(m,"Concave microwave reflector central dish","Dish inner graphite",front[0])
    for k,(s,t) in enumerate(zip(back,back[1:])):
        for i in range(n):
            j=(i+1)%n
            face(m,"Convex back of pressed antenna dish","Dish back nickel",(s[i],t[i],t[j],s[j]))
    for k,(s,t) in enumerate(zip(front,front[1:])):
        for i in range(n):
            j=(i+1)%n
            col=("Dish highlight","Dish lip brushed steel","Dish inner graphite","Dish inner graphite")[(i+k)%4]
            face(m,"Distinct concave microwave reflector dish bowl",col,(s[i],s[j],t[j],t[i]))
    q,p=back[-1],front[-1]
    for i in range(n):
        j=(i+1)%n
        face(m,"Rolled dish periphery with real rim thickness","Dish lip brushed steel",(q[i],q[j],p[j],p[i]))
    f=center+.137*a
    for i in (0,4,8):
        member(m,"Triangular fine feedhorn support spars","Mast shadow grey",front[-1][i],f,.009)
    member(m,"Actual little central microwave feedhorn","Mast white zinc",f-.015*a,f+.019*a,.027)
    member(m,"Pinned steel dish aiming bracket","Mast shadow grey",Vector((0,0,h)),center,.041,.027)


def transmitter(m):
    levels=(0,.223,.465,.698,.935,1.175,1.414,1.659,1.901,2.118)
    def at(s,t,h):
        d=.142-h*.028
        return (s*d,t*d,h)
    for s,t in ((1,1),(-1,1),(-1,-1),(1,-1)):
        x,z,h=at(s,t,0)
        B(m,"Four isolated tower foundation bolts in concrete pads","Ground granite",x,z,.141,.141,0,.073,.012)
        member(m,"Four continuous galvanized mast legs on open frame","Mast white zinc",at(s,t,.040),at(s,t,2.119),.025)
        member(m,"Structural diagonal below separate foot stanchion","Mast shadow grey",(x*.6,z*.6,.104),
          (x*1.29,z*1.29,.055),.015)
    perimeter=((1,1),(-1,1),(-1,-1),(1,-1))
    for i,(lo,hi) in enumerate(zip(levels,levels[1:])):
        for j,a in enumerate(perimeter):
            b=perimeter[(j+1)%4]
            member(m,"Open alternating web lattice and real diagonal steel ties","Mast pale tube edge",
              at(*(a if (j+i)%2 else b),lo),at(*(b if (j+i)%2 else a),hi),.014)
            member(m,"Small horizontal zinc section band bracing","Mast white zinc",at(*a,hi),at(*b,hi),.013)
        x=.15-hi*.028
        member(m,"Vertical open maintenance ladder lefthand stile","Mast pale tube edge",
          (-.042,x,lo),(-.042,x-.006,hi),.008)
        member(m,"Vertical open maintenance ladder righthand stile","Mast pale tube edge",
          (.042,x,lo),(.042,x-.006,hi),.008)
        for frac in (.29,.69):
            pos=lo+(hi-lo)*frac
            member(m,"Fixed passage ladder separate rung","Mast shadow grey",
              (-.042,x,pos),(.042,x,pos),.007)
    for a in (-.80*pi,-.12*pi,.53*pi):
        x,z=.804*cos(a),.804*sin(a)
        B(m,"Independent metal guy ground deadman pad","Ground granite",x,z,.100,.100,0,.038,.008)
        member(m,"Three diagonal mast tension guy cables","Catenary cable charcoal",
          (.076*cos(a),.076*sin(a),1.86),(x,z,.038),.006)
    B(m,"Low compact base isolator disconnect cabinet","Cabinet muted pine grey",-.318,.160,.196,.17,0,.268,.009)
    B(m,"Service cabinet tilted rainproof panel","Mast shadow grey",-.318,.16,.208,.180,.260,.282,.007)
    for h in (.056,.131,.201):
        B(m,"Pressed flat field cab service-door seam","Mast shadow grey",-.321,.25,.157,.010,h,h+.004,.001)
    B(m,"Roof-level transmission launch platform","Mast pale tube edge",0,0,.261,.261,1.939,1.969,.011)
    for params in ((-.22*pi,2.133,.204,.186),(.43*pi,2.227,.169,.194),(1.09*pi,2.109,.192,.189)):
        dish(m,*params)
    member(m,"Independent upper antenna waveguide pole","Mast white zinc",(0,0,1.995),(0,0,2.425),.026)
    member(m,"Thin upper navigation whip","Mast shadow grey",(0,0,2.405),(0,0,2.557),.009)
    C(m,"Small top ruby aircraft caution beacon","Antenna warning ruby",(0,0,0),.018,"h",2.412,2.445,10)


def atlas():
    row=b"".join(bytes.fromhex(v)*8 for v in PAL.values())
    def c(tag,b):
        return struct.pack(">I",len(b))+tag+b+struct.pack(">I",zlib.crc32(tag+b))
    (R.TEXTURES/"bl_stock_landmarks_atlas.png").write_bytes(
      b"\x89PNG\r\n\x1a\n"+c(b"IHDR",struct.pack(">IIBBBBB",len(P)*8,8,8,2,0,0,0))+
      c(b"IDAT",zlib.compress((b"\0"+row)*8))+c(b"IEND",b""))


def mats():
    out=R.materials()
    for c,m in zip(P,out):
        m.name=c
        p=m.node_tree.nodes["Principled BSDF"]
        p.inputs["Metallic"].default_value=.31 if any(s in c.lower() for s in ("mast","steel","iron","brass")) else .02
        p.inputs["Roughness"].default_value=.63
    return out


def source(scene,name,model,materials):
    col=bpy.data.collections.new(name)
    scene.collection.children.link(col)
    R.to_blender(model,col,materials)


def preview(models,path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc=bpy.context.scene
    pal=mats()
    for name,m,x in ((models[0][0],models[0][1],-.99),(models[1][0],models[1][1],.99)):
        R.instance(sc,R.stash(m,pal,name),x,0)
    bpy.ops.mesh.primitive_plane_add(size=100,location=(0,0,-.005))
    bpy.context.object.data.materials.append(pal[P["Review meadow"]])
    bpy.ops.object.camera_add(location=(2.8,-4.66,3.23))
    c=bpy.context.object
    c.rotation_euler=(Vector((.08,0,1.16))-c.location).to_track_quat("-Z","Y").to_euler()
    c.data.type="ORTHO";c.data.ortho_scale=4.3;sc.camera=c
    sc.render.engine="BLENDER_WORKBENCH"
    sc.render.resolution_x=1300;sc.render.resolution_y=960;sc.render.resolution_percentage=100
    sh=sc.display.shading
    sh.light="STUDIO";sh.color_type="MATERIAL";sh.show_shadows=True;sh.show_cavity=True
    sh.cavity_type="BOTH";sh.background_type="WORLD"
    sc.world=bpy.data.worlds.new("Clear warm temperate sky")
    sc.world.color=(.213,.246,.262)
    sc.view_settings.view_transform="Standard"
    sc.render.filepath=path
    bpy.ops.render.render(write_still=True)


def main():
    models=[]
    for name,fn in (("lighthouse",light),("transmitter",transmitter)):
        model=mesh();fn(model);models.append((name,model))
        p=R.MODELS/f"bl_stock_{name}.obj"
        R.export_obj(p,model)
        data=p.read_text()
        p.write_text("# Original stock landmark · tools/build_stock_landmarks_art.py\n"+data.split("\n",1)[1])
    atlas()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    sc=bpy.context.scene
    sc.name="Original temperate lighthouse and transmitter · LuanTTD"
    sc.view_settings.view_transform="Standard"
    sc["Mount"]="Even native node at (2*x,base+1,2*z); tile center +.5 x,z; mesh floor -.5."
    sc["Provenance"]="Original Blender meshes inspired by OpenGFX 7.1 objects 2601 and 2602. No imported image."
    materials=mats()
    for name,m,x in ((models[0][0],models[0][1],-1.05),(models[1][0],models[1][1],1.05)):
        source(sc,"Purpose-built "+name,m,materials)
        for o in bpy.data.collections["Purpose-built "+name].objects:o.location.x=x
    for screen in bpy.data.screens:
        for a in screen.areas:
            if a.type=="VIEW_3D":
                q=a.spaces.active
                q.shading.color_type="MATERIAL"
                q.region_3d.view_location=(0,0,1.14)
                q.region_3d.view_rotation=Vector((2.6,-4.6,2.05)).to_track_quat("Z","Y")
                q.region_3d.view_distance=4.65
    bpy.ops.wm.save_as_mainfile(filepath=str(R.ROOT/"art/stock_landmarks.blend"),compress=True)
    if target:=os.getenv("STOCK_LANDMARKS_REVIEW"):
        preview(models,target)


if __name__=="__main__":
    main()

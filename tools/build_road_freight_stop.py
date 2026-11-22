#!/usr/bin/env python3
"""Original coal freight stop overlays, all six existing post-stop orientations.

blender -b -t 4 --python-exit-code 1 --python tools/build_road_freight_stop.py
FREIGHT_STOP_RENDER=/tmp/freight.png blender -b -t 4 --python tools/build_road_freight_stop.py

Curb and turn orientation, two-node static anchors and atlas UVs follow
the Post Stop convention. Source motion remains the pinned OpenTTD 14.1
road movement tables; all art, names and surface colors are original.
"""
from math import cos, pi, sin
from pathlib import Path
from random import Random
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_road_post_stop as P

COLORS={
    "Warm concrete":"a79c85","Worn slab":"96917f","Paving joint":"716b5d",
    "Gravel shoulder":"8c846e","Dressed cap":"bdad91","Coarse masonry":"8f7e64",
    "Brown oak":"76533e","Weathered oak":"917359","Timber edge":"a08a67",
    "Red steel roof":"944f3f","Roof seams":"ad6451","Roof shadow":"683c36",
    "Dark steel":"394647","Enameled deep green":"375753","Oiled steel":"536a64",
    "Forged lock":"84918a","Glazing":"709b9c","Glazing glint":"a0bdba",
    "Graphite coal":"303637","Cinder gray":"484947","Coal highlight":"5a5b4f",
    "Ocher hazard paint":"dcb266","Enamel dark":"483b31","Ivory enamel":"eddcb1",
    "Black pulley":"2e3938","Casing iron":"737a70","Grille shadow":"262f35",
    "Gauge copper":"94765c","Signal ruby":"a74638","Slab bolts":"a8aea0",
    "Grass runway shade":"566d48","Tar pavement":"545451",
}
ROOT=P.ROOT
P.COLORS=COLORS
KEYS=("straight_0","straight_1","bay_0","bay_1","bay_2","bay_3")
TURN=(0,1,0,-1,-2,-3)
FONT={
    "A":("01110","11011","11011","11111","11011","11011","11011"),
    "C":("01111","11000","11000","11000","11000","11000","01111"),
    "G":("01111","11000","11000","11011","11011","11011","01111"),
    "E":("11111","11000","11000","11110","11000","11000","11111"),
    "H":("11011","11011","11011","11111","11011","11011","11011"),
    "I":("11111","00100","00100","00100","00100","00100","11111"),
    "L":("11000","11000","11000","11000","11000","11000","11111"),
    "O":("01110","11011","11011","11011","11011","11011","01110"),
    "W":("10001","10001","10101","10101","10101","11111","01010"),
}

def lettering(m,n,text,x,z,h,size):
    # Viewer looking toward canonical +Z from the lane reads increasing +X.
    for j,letter in enumerate(text):
        for r,row in enumerate(FONT[letter]):
            start=(j*6-(len(text)*6-1)/2)*size
            yy=h+(3.5-r)*size
            for i,q in enumerate(row):
                xx=x+start+i*size
                if q=="1":
                    m.face(n,"Ivory enamel",
                      [(xx,z,yy-size),(xx+size,z,yy-size),(xx+size,z,yy),(xx,z,yy)])

def tube(m,n,c,a,b,r0,r1=None,N=10):
    va,vb=Vector(a),Vector(b)
    axis=(vb-va).normalized()
    frame=Vector((0,0,1)) if abs(axis.z)<.85 else Vector((1,0,0))
    u=axis.cross(frame).normalized()
    v=axis.cross(u).normalized()
    r1=r0 if r1 is None else r1
    def ring(o,r):
        return [tuple(o+r*(u*cos(2*pi*k/N)+v*sin(2*pi*k/N))) for k in range(N)]
    m.ring(n,c,ring(va,r0),ring(vb,r1))

def safe_box(m):
    def add(n,c,x0,x1,z0,z1,h0,h1,ch=0,cap=None):
        m.box(n,c,x0,x1,z0,z1,h0,h1,min(ch,(x1-x0)/3,(z1-z0)/3),cap)
    return add

def paving(m,bay):
    floor=safe_box(m)
    if not bay:
        # Clear through lanes unchanged; the weighing bed sits along the curb.
        floor("Flush gravel pavement collar","Gravel shoulder",-.970,.968,.371,.965,-.508,-.495,.008)
        floor("Concrete off-road working slab","Warm concrete",-.961,.958,.399,.973,-.505,-.456,.025)
    else:
        # A bay has a wide, level reversing loop sharing its west throat with
        # the asphalt. Do not narrow the stock turnaround to fit the building.
        # This footprint is an open concrete slab, not highway lane geometry.
        slab=[(-.998,-.403),(-.742,-.815),(-.360,-.891),
              (.182,-.864),(.572,-.691),(.669,-.332),(.662,.345),
              (.512,.665),(.240,.737),(-.326,.689),(-.715,.541),(-.998,.403)]
        base=[(x,z,-.515) for x,z in slab]
        top=[(x,z,-.497) for x,z in slab]
        m.ring("Flush concrete stock turnaround slab","Warm concrete",base,top)
        for x in (-.71,-.405,-.099,.208,.499):
            zmin=-.65 if x<.49 else -.51
            m.box("Turn bay exposed aggregate joint","Worn slab",x-.003,x+.003,zmin,.371,-.497,-.494)
        # A real shallow foot ramp joins the lower slab to the work ledge.
        def ramp(z):return -.496+.046*(z-.595)/(.731-.595)
        floor("Ramped pedestrian join above bay perimeter","Worn slab",-.525,.390,.595,.731,
              lambda z:ramp(z)-.020,ramp,.014)
        floor("Raised concrete side work station","Warm concrete",-.800,.878,.664,.974,-.506,-.452,.017)
        for z in (-.515,.491):
            for i in range(4):
                x=-.51+i*.203
                floor("Flat bay demarcation painted segments","Ivory enamel",
                      x,x+.113,z-.008,z+.008,-.496,-.492)
    start,end,edge=( -.762,.845,.666) if bay else (-.927,.923,.403)
    # Hand-set drain channels and yellow dock stripe remain off the roadway.
    for i in range(11):
        x=start+(end-start)*i/11
        w=(end-start)/11
        floor("Real worn exposed concrete flag joints",("Warm concrete","Warm concrete","Worn slab","Dressed cap")[i%4],
              x,x+w-.006,edge+.011,.954,-.458,-.449 if bay else -.451,.004)
    for i in range(6):
        x=start+(end-start)*i/6
        w=(end-start)/6
        floor("Cut road-edge paving curb sections","Dressed cap",
              x,x+w-.008,edge,edge+.044,-.498,-.438 if bay else -.437,.003)
    for x in ((-.67,.74) if bay else (-.85,.85)):
        z=.702 if bay else .46
        floor("Protective iron bollard root","Dressed cap",x-.031,x+.031,z-.030,z+.03,-.454,-.421,.005)
        m.post("Curbsafe iron protection bollard","Dark steel",x,z,-.434,-.280,.020,.016,8)
        m.post("Bollard warm hazard collars","Ocher hazard paint",x,z,-.341,-.315,.021,.019)
        m.post("Cast turning bollard caps","Enameled deep green",x,z,-.284,-.266,.018,.014)

def office(m,bay):
    x=-.333 if bay else -.535
    lo,hi=x-.237,x+.237
    z0,z1=(.746,.956) if bay else (.603,.942)
    floor=safe_box(m)
    floor("Weathered operator brick footing","Coarse masonry",lo-.036,hi+.036,z0-.015,z1+.018,-.448,-.379,.013)
    floor("Small weighmaster booth timber shell","Brown oak",lo,hi,z0,z1,-.388,-.041,.008)
    for z in (z0-.004,z1+.005):
        for i in range(5):
            y=-.376+i*.065
            floor("Horizontal tongue-and-groove booth boards","Weathered oak",lo+.004,hi-.004,z-.006,z+.005,y,y+.057)
    for x2,w in ((x-.084,.172),(x+.142,.083)):
        y0,y1=(-.237,-.126) if x2<x else (-.313,-.142)
        floor("Jamb color sash frame","Enamel dark",x2-w/2-.017,x2+w/2+.017,z0-.024,z0-.004,y0-.014,y1+.015,.004)
        floor("Glazed weighmaster booth inset windows","Glazing",x2-w/2,x2+w/2,z0-.027,z0-.019,y0,y1,.003)
        floor("Dusty glass diagonal window highlight","Glazing glint",x2-.059,x2-.027,z0-.029,z0-.025,y0+.008,y1-.015,.002)
        floor("Visible timber mullion","Timber edge",x2-.004,x2+.004,z0-.034,z0-.020,y0,y1)
        floor("Sandstone counter sill","Dressed cap",x2-w/2-.023,x2+w/2+.024,z0-.043,z0-.010,y0-.022,y0-.005,.005)
    floor("Weigh-office handle and latch","Forged lock",x+.166,x+.189,z0-.036,z0-.022,-.282,-.267,.005)
    # One real low gabled steel roof with ribs, flashing and gutter.
    rz=(z0+z1)/2
    rz0,rz1=z0-.043,min(.988,z1+.042)
    def yr(z):return .088-.60*abs(z-rz)
    floor("Folded red tin pitched office roof","Red steel roof",lo-.039,hi+.034,rz0,rz,lambda z:yr(z)-.026,yr)
    floor("Folded red tin pitched office roof","Red steel roof",lo-.039,hi+.034,rz,rz1,lambda z:yr(z)-.026,yr)
    for j in range(11):
        a=lo-.023+j*.049
        floor("Folded weathered standing-seam roof strips","Roof seams",a-.004,a+.004,rz0,rz1,
              lambda z:yr(z)+.001,lambda z:yr(z)+.008)
    floor("Roof central copper flashing","Roof seams",lo-.043,hi+.039,rz-.011,rz+.011,.081,.100,.003)
    tube(m,"Period black drainpipe","Dark steel",(hi+.013,rz0,-.006),(hi+.013,z0-.024,-.401),.011,.012,8)
    tube(m,"Real working cast ridge chimney","Dark steel",(x-.119,rz+.037,.047),(x-.119,rz+.037,.176),.018,.016,9)
    tube(m,"Small forged weather hood on vent","Forged lock",(x-.119,rz+.037,.162),(x-.119,rz+.037,.190),.027,.022,9)
    floor("Cast raised WEIGH fascia","Enamel dark",x-.202,x+.214,rz0-.021,rz0+.004,-.041,.029,.008)
    lettering(m,"Engraved WEIGH key","WEIGH",x+.003,rz0-.022,-.005,.0105)
    tube(m,"Weigh house period porcelain light bracket","Dark steel",(x+.121,rz0,-.073),(x+.121,rz0-.044,-.078),.012,.012)
    tube(m,"Signal enamel depot work lamp","Ivory enamel",(x+.121,rz0-.046,-.106),(x+.121,rz0-.046,-.082),.023,.025)
    tube(m,"Depot lamp shaped lid","Enameled deep green",(x+.121,rz0-.046,-.082),(x+.121,rz0-.046,-.069),.026,.018)

def weighing(m,bay):
    x=.010 if bay else -.015
    z=.814 if bay else .703
    floor=safe_box(m)
    floor("Recessed mechanical scale foundation","Grille shadow",x-.206,x+.206,z-.103,z+.125,-.449,-.427,.006)
    floor("Cast iron balance deck weighbridge","Oiled steel",x-.188,x+.187,z-.086,z+.098,-.424,-.413,.007)
    for i in range(8):
        a=x-.170+i*.0475
        floor("Weighbridge non-slip iron deck ribs","Casing iron",a-.003,a+.003,z-.083,z+.094,-.414,-.409,.001)
    for a in (x-.154,x+.157):
        for zs in (z-.071,z+.083):
            m.post("Weighbridge exposed screw anchors","Slab bolts",a,zs,-.414,-.403,.012,.010,6)
    x=x+.098
    z=z+.052
    m.post("Analog axle scale post foot","Dark steel",x,z,-.416,-.384,.040,.035)
    tube(m,"British-style mechanical dial mast","Dark steel",(x,z,-.385),(x,z,-.184),.023,.018)
    tube(m,"Cast circular weigh gauge casing","Enameled deep green",(x,z+.012,-.185),(x,z-.041,-.185),.065,.060,24)
    tube(m,"Enamel recessed dial face","Ivory enamel",(x,z-.041,-.185),(x,z-.043,-.185),.050,.049,24)
    for r in range(9):
        p=(r/8-.5)*1.7*pi
        a=x+.039*sin(p);b=-.185+.039*cos(p)
        tube(m,"Individual gauge graduation indexes","Enamel dark",(a,z-.048,b),(a,z-.050,b),.002,.002,6)
    tube(m,"Weigh gauge copper pointer","Signal ruby",(x,z-.052,-.192),(x+.020,z-.052,-.157),.005,.002,7)
    tube(m,"Meter reset black handle","Black pulley",(x+.051,z,-.214),(x+.075,z,-.231),.007,.006,8)

def coal_hopper(m,bay):
    # Built beside pavement: tapered chute comprising wall, true inner
    # surface, frame, signs and load-compatible axle wheel stops.
    x=.496 if bay else .545
    z=.822 if bay else .732
    w=.440 if bay else .534
    depth=.204 if bay else .306
    floor=safe_box(m)
    floor("Cast pit curb coal transfer plinth","Paving joint",x-w*.59,x+w*.59,z-depth*.61,z+depth*.61,
          -.450,-.416,.015)
    floor("Hopper coal-chute lowest iron frame","Dark steel",x-w*.34,x+w*.34,z-depth*.34,z+depth*.34,
          -.433,-.388,.014)
    sides=((-1,-1),(1,-1),(1,1),(-1,1))
    lo=[(x+a*w*.24,z+b*depth*.24,-.378) for a,b in sides]
    hi=[(x+a*w*.50,z+b*depth*.50,-.246) for a,b in sides]
    il=[(x+a*w*.23,z+b*depth*.22,-.381) for a,b in sides]
    ih=[(x+a*w*.47,z+b*depth*.44,-.249) for a,b in sides]
    for i in range(4):
        j=(i+1)%4
        m.face("Hopper tapered riveted casing","Enameled deep green",
          (lo[i],lo[j],hi[j],hi[i]))
        m.face("Hopper open inner sloping wear plate","Grille shadow",
          (il[j],il[i],ih[i],ih[j]))
        m.face("Visible open steel hopper rim","Forged lock",
          (hi[i],hi[j],ih[j],ih[i]))
        tube(m,"Boxed hopper top edge rim","Oiled steel",hi[i],hi[j],.008,.008,7)
        xx,zz,_=hi[i]
        floor("Hopper four reinforced open legs","Dark steel",xx-.012,xx+.012,zz-.010,zz+.010,-.430,-.261,.003)
        T=(lo[i][0],lo[i][1],lo[i][2]+.01)
        tube(m,"Diagonal receiving hopper steel bracing","Dark steel",(xx,zz,-.427),T,.010,.010,7)
    rng=Random(40 if bay else 75)
    for i in range(20):
        u=x+w*rng.uniform(-.29,.29);v=z+depth*rng.uniform(-.25,.25)
        r=rng.uniform(.012,.036)
        y=-.346+rng.uniform(-.013,.028)
        col=rng.choice(("Graphite coal","Cinder gray","Coal highlight"))
        m.post("Individual loose coal visible below hopper lip",col,u,v,y-.017,y+.009,r,r*.60,6)
    for j in (-1,0,1):
        xx=x+j*w*.25
        tube(m,"Open safety grid coal drop bars","Dark steel",(xx,z-depth*.446,-.241),
               (xx,z+depth*.446,-.241),.005,.005,7)
    face=z-depth*.51
    floor("Coal unloading enamel faceplate","Enamel dark",x-.153,x+.153,face-.021,face+.008,-.339,-.270,.006)
    lettering(m,"Enamel raised COAL clearance notice","COAL",x,face-.022,-.303,.0088)
    # Short visible gravity discharge section beneath the sloping hopper,
    # with gate spindle, not a closed substitute for the model.
    tube(m,"Coal gravity discharge angular hollow-phase conduit","Oiled steel",(x,z,-.383),(x+.096,z+.083,-.418),.033,.030,9)
    tube(m,"Handwheel on delivery shutoff","Gauge copper",(x+.161,z-.021,-.385),(x+.161,z-.052,-.385),.030,.027,12)

def art(bay):
    m=P.Mesh()
    paving(m,bay)
    office(m,bay)
    weighing(m,bay)
    coal_hopper(m,bay)
    return m

def stage(scene,which,mats):
    # Only in the authoring review; terrain cubes and road surfaces stay
    # under runtime control. Fit the actual one-entrance road geometry.
    m=P.Mesh()
    m.box("Native flat grass stand-in","Grass runway shade",-5,5,-4,4,-.590,-.501)
    xend=.02 if which=="Bay" else 4
    m.box("Native radius asphalt clearance reference","Tar pavement",-4,xend,-.3125,.3125,-.512,-.499)
    for a in range(-10,(0 if which=="Bay" else 11)):
        x=a*.38
        m.box("Asphalt paint ideal footprint","Ivory enamel",x-.060,x+.061,-.012,.012,-.4986,-.4982)
    P.author(m,"Backdrop reference (not exported)",mats,scene)

def camera(scene,which):
    loc=(1.65,-2.64,1.22) if which=="Drive Through" else (1.65,-2.79,1.72)
    data=bpy.data.cameras.new(which)
    ob=bpy.data.objects.new(which,data)
    scene.collection.objects.link(ob)
    scene.camera=ob
    ob.location=loc
    ob.rotation_euler=(Vector((.02,.43,-.275))-ob.location).to_track_quat("-Z","Y").to_euler()
    data.type="ORTHO"
    data.ortho_scale=2.54 if which=="Drive Through" else 2.78
    scene.render.engine="BLENDER_WORKBENCH"
    scene.render.resolution_x,scene.render.resolution_y=1272,880
    scene.render.resolution_percentage=100
    scene.display.shading.light="STUDIO"
    scene.display.shading.color_type="MATERIAL"
    scene.display.shading.show_shadows=True
    scene.display.shading.show_cavity=True
    scene.display.shading.cavity_type="BOTH"
    scene.display.shading.background_type="WORLD"
    scene.world=bpy.data.worlds.new("Country sky")
    scene.world.color=(.135,.195,.235)
    scene.view_settings.view_transform="Standard"

def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    straight,bay=art(False),art(True)
    for suffix,turn in zip(KEYS,TURN):
        mesh=(bay if suffix.startswith("bay") else straight).transformed(turn%4)
        raw=P.payload(mesh,suffix)
        p=ROOT/"mods/bayline/models"/f"bl_road_freight_stop_{suffix}.obj"
        p.write_text(raw.replace(raw.splitlines()[0],
            f"# Original coal freight stop, {suffix}, post stop anchor. tools/build_road_freight_stop.py",1))
    (ROOT/"mods/bayline/textures/bl_road_freight_stop.png").write_bytes(P.atlas())
    mats=P.make_materials()
    first=bpy.context.scene
    first.name="Drive Through"
    scenes=(first,bpy.data.scenes.new("Bay"))
    for scene,model in zip(scenes,(straight,bay)):
        scene["native datum"]="X/Z center of 2x2 piece. Ground top at Y=-.5 mesh above even anchor."
        scene["use"]="Cargo receiving equipment is off the travel pavement, not an obstacle or shipping simulation."
        bpy.context.window.scene=scene
        P.author(model,scene.name+" (editable original parts)",mats,scene)
        stage(scene,scene.name,mats)
        camera(scene,scene.name)
    bpy.context.window.scene=first
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art/road_freight_stop.blend"),compress=True)
    if target:=os.environ.get("FREIGHT_STOP_RENDER"):
        for i,scene in enumerate(scenes):
            bpy.context.window.scene=scene
            p=Path(target)
            if i:p=p.with_name(p.stem+"-bay.png")
            scene.render.filepath=str(p)
            bpy.ops.render.render(write_still=True)

if __name__=="__main__":main()

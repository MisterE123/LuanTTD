#!/usr/bin/env python3
"""Original land oil pumpjack set, stock five-cell L plan and optional phase art."""
from math import acos, atan2, cos, hypot, pi, sin, tau
from pathlib import Path
import os
import sys

import bpy
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_stock_farm_art as S

A,R=S.A,S.R
B,T,F,Q=S.B,S.T,S.F,S.Q
PAL=dict(S.PAL, **{
    "pump_copper":"9d644a", "pump_lit":"b47d58", "pump_shadow":"805841",
    "strapped_iron":"625852", "pumpsteel":"68787a", "flashing":"9ca59a",
    "bearingdark":"4e5651", "drill_red":"9d604c", "warning_gold":"c6a063",
    "oil_dark":"313d39", "pad_oil":"595850", "drill_grit":"8a7559",
    "drill_sand":"a48966", "tank_teal":"5d766c", "safety_bone":"d8c7a8",
    "blue_name":"476475", "axle_glint":"a5a89a",
})
A.PAL=PAL;A.P=A.H.P={k:i for i,k in enumerate(PAL)}
R.COLORS[:]=PAL.values()
LAYOUT={(0,0):29,(1,0):29,(2,0):29,(0,1):29,(0,2):29}
NAME="industry_oil_well"
# The horsehead faces +X; this walking beam and its rear pin use a genuine
# four-bar link in the vertical X/Y plane.
PIVOT=(.61,.63,.855)
WHEEL=(.264,.63,.310)
WHEEL_RADIUS=.061
REAR_RADIUS=.490
LINK=.565
FRAME_COUNT=12


def pad(m,x,z,k):
    Q(m,"Oil-stained well pad gasket beneath machinery","drill_grit",x-.44,x+1.45,z-.44,z+1.42,.004)
    Q(m,"Compacted and cobbled beam service apron","pad_oil",x-.34,x+1.371,z+.095,z+1.104,.008)
    for zz in (z-.385,z+1.387):
        for i in range(9):
            a=x-.34+i*.191
            B(m,"Low discreet perimeter split logs","wood",a,zz,.102,.064,.004,.047,.012)
    for q in (-.16,.16):
        Q(m,"Oil well maintenance tire tracks","tread",x-.39,x+1.4,z+.64+q-.033,z+.64+q+.032,.01)
    B(m,"Chamfered concrete machinery plinth","cement",x+.637,z+.641,1.452,.708,.012,.105,.036)
    B(m,"Separate equipment skid running channel","bearingdark",x+.611,z+.629,1.408,.575,.104,.133,.025)
    # Graceful low steel tank with drain pipes and freestanding lights.
    a,b=x+.27,z-.143
    T(m,"Rounded wet receiving tank with steel lid","tank_teal",(a,b,.029),(a,b,.386),.187,.183,14)
    T(m,"Shallow pressed tank cover","flashing",(a,b,.377),(a,b,.418),.186,.143,14)
    T(m,"Capped inspection valve","bearingdark",(a,b,.41),(a,b,.451),.050,.042,8)
    pipe(m,"Flexible oil return pipe","pumpsteel",[(a+.11,b,.191),(a+.32,b,.188),
        (a+.47,b+.13,.188),(a+.39,b+.34,.188),(a+.39,b+.50,.188)],.024)
    for zz in (z-.265,z+.405):
        B(m,"Disposable low weathered jersey block","foundation",x+1.306,zz,.169,.106,.017,.103,.012)
        B(m,"Faint guard stripe","warning_gold",x+1.306,zz,.157,.097,.099,.111,.007)
    if k==2:
        B(m,"Distinct pad overhaul nameboard paint","blue_name",x+.634,z+1.20,.57,.047,.159,.278,.009)
        for xx in (x+.41,x+.852):
            B(m,"Pad name rail stand","wood",xx,z+1.202,.035,.039,.013,.238,.005)
        A.lettering(m,"Raised TIDELAND field opening label","TIDELAND",(x+.634,z+1.228,.22),.0105,"south","bone")


def pipe(m,n,col,pts,r):
    for j,(a,b) in enumerate(zip(pts,pts[1:])):
        T(m,n,col,a,b,r,r,8)
        if j+1<len(pts)-1:
            a,b,c=b
            S.ellipse(m,n+" flexed bend",col,a,b,c,r,r,r,8)


def fixed(m,x,z,k):
    def p(a,b,c):return a+x,b+z,c
    n="Anchored pumpjack A-frame"
    Px,Pz,Py=PIVOT
    wx,wz,wh=WHEEL
    for a in (.32,.86):
        for d in (-.206,.206):
            point=(a,.63+d,.155)
            T(m,n+" formed channel steel stanchion","pump_shadow",p(*point),p(Px,.63+d*.34,Py),
              .042,.037,4)
            B(m,n+" bolted cast footing","foundation",a+x,.63+d+z,.174,.142,.123,.165,.016)
            for s in (-.043,.043):
                T(m,n+" hex footing bolt","pumpsteel",p(a+s,.63+d+.033,.159),
                  p(a+s,.63+d+.033,.172),.010,.010,6)
    for s in (-.012,.013):
        T(m,n+" cross-braced formed steel tie","pump_lit",p(.379,.43,.202+s),
          p(.803,.823,.572+s),.018,.018,4)
    T(m,n+" cross bearing horizontal polished axle","flashing",p(Px,Pz-.154,Py),p(Px,Pz+.154,Py),.063,.063,12)
    for d in (-.133,.133):
        T(m,n+" blackened lateral thrust collar","bearingdark",p(Px,Pz+d-.014,Py),p(Px,Pz+d+.014,Py),
          .069,.069,9)
    B(m,"Cast iron well pedestal and crank gearbox","bearingdark",x+wx,z+wz,.322,.370,.134,.394,.044)
    B(m,"Separate right-side crankcase venting cap","pumpsteel",x+wx,z+wz,.237,.283,.381,.439,.012)
    for a in (.186,.236,.290,.342):
        B(m,"Gearbox cast cooling ribs","flashing",x+a,z+wz,.015,.268,.423,.442,.002)
    T(m,"Rotating drive running shaft drum core","pumpsteel",p(wx,wz-.178,wh),p(wx,wz+.178,wh),.064,.064,12)
    for d in (-.192,.192):
        T(m,"Gear pillar heavy side pivot bearing","pump_shadow",p(wx,wz+d-.017,wh),p(wx,wz+d+.017,wh),.118,.118,16)
    tx,tz=1.237,.63
    T(m,"Long wellhead mounting shoe","bearingdark",p(tx,tz,.131),p(tx,tz,.225),.109,.078,12)
    T(m,"Polished production casing string","pumpsteel",p(tx,tz,.176),p(tx,tz,.424),.059,.046,12)
    T(m,"Oilwell capped yoke inlet arm","drill_red",
      p(tx,tz,.309),p(tx,tz+.154,.309),.054,.039,12)
    T(m,"Production wing-valve offset manifold collar","drill_red",p(tx,tz+.160,.282),p(tx,tz+.160,.359),.041,.041,11)
    pipe(m,"Fixed outlet product pipe with rise and bends","flashing",
      [p(tx+.035,tz,.287),p(tx+.13,tz,.287),p(tx+.13,tz+.068,.287),p(tx+.13,tz+.159,.193),
       p(tx+.13,tz+.266,.178),p(tx-.249,tz+.280,.178)],.031)
    # Fixed frame protectors outside the stroke.
    for d in (-.304,.307):
        B(m,"Pump safe access painted marker","warning_gold",x+.872,z+.63+d,.265,.026,.131,.146,.003)


def pose(t):
    wx,wz,wy=WHEEL
    px,pz,py=PIVOT
    qx,qy=wx+WHEEL_RADIUS*cos(t),wy+WHEEL_RADIUS*sin(t)
    dx,dy=qx-px,qy-py
    d=hypot(dx,dy)
    theta=atan2(dy,dx)-acos((d*d+REAR_RADIUS*REAR_RADIUS-LINK*LINK)/(2*d*REAR_RADIUS))
    return theta-pi, (qx,qy)


def polygon(m,n,c,sil,z,d):
    f=[(x,z-d,y) for x,y in sil];b=[(x,z+d,y) for x,y in sil]
    F(m,n,c,f)
    F(m,n,c,b[::-1])
    for j in range(len(f)):
        k=(j+1)%len(f)
        F(m,n,"pump_lit" if j<3 else c,(f[j],b[j],b[k],f[k]))


def motion(m,x,z,k,t):
    pm,(qx,qy)=pose(t)
    ax,az,ay=PIVOT
    def spin(u,v):
        return ax+x+u*cos(pm)-v*sin(pm),ay+u*sin(pm)+v*cos(pm)
    def wp(u,v,d=0):
        xx,yy=spin(u,v)
        return xx,z+az+d,yy
    n=f"Well {k+1:02} move"
    beam=[spin(*v) for v in ((-.516,-.043),(.536,-.050),(.585,-.018),
                            (.591,.050),(.505,.067),(-.475,.050),(-.527,.007))]
    polygon(m,n+" separate walking I beam","pump_shadow",beam,z+az,.073)
    for h in (-.041,.046):
        T(m,n+" formed walking-beam crown flange","pump_lit",wp(-.517,h),wp(.567,h),.018,.018,4)
    head=[spin(*v) for v in ((.514,-.073),(.601,-.267),(.702,-.224),(.749,-.135),
                            (.764,-.039),(.733,.059),(.691,.115),(.617,.115),(.566,.058))]
    polygon(m,n+" recognizable curved solid horsehead","pump_copper",head,z+az,.109)
    T(m,n+" polished nose guide flange","flashing",wp(.753,-.053,-.112),wp(.753,-.053,.112),.016,.016,8)
    dx,dy=spin(.687,-.215)
    for zz in (-.059,.059):
        T(m,n+" actual bridle polished wire ropes","flashing",(dx,z+az+zz,dy),
           (x+1.237,z+az+zz*.496,max(.441,dy-.188)),.006,.006,6)
    T(m,n+" rod load polished upper plunger","axle_glint",(x+1.237,z+az,.418),
      (x+1.237,z+az,max(.459,dy-.180)),.017,.017,11)
    for d in (-.159,.159):
        dz=z+az+d
        rx,ry=spin(-REAR_RADIUS,0)
        T(m,n+" split linked pitman beam rods","strapped_iron",(rx,dz,ry),(x+qx,dz,qy),.022,.022,6)
        T(m,n+" pitman wrist pinned bearings","pumpsteel",(rx,dz-.014,ry),(rx,dz+.014,ry),.039,.039,9)
        wx,wz,wh=WHEEL
        T(m,n+" eccentric crank bar","pump_lit",(x+wx,dz,wh),(x+qx,dz,qy),.031,.029,5)
        cx=x+wx-.072*cos(t);cy=wh-.072*sin(t)
        T(m,n+" cylindrical moving counterweight","pump_shadow",(cx,dz-.032,cy),(cx,dz+.030,cy),.062,.062,12)


def pads(m):
    for k,(u,v) in enumerate(LAYOUT):pad(m,2*u,2*v,k)


def frames(m):
    for k,(u,v) in enumerate(LAYOUT):fixed(m,2*u,2*v,k)


def operating(m):
    # Stock animated pumping can be wired by a future presentation change;
    # the ordinary per-cell standalones use a useful first frame.
    for k,(u,v) in enumerate(LAYOUT):motion(m,2*u,2*v,k,t=.78+k*.48)


def rig_existing():
    sc=bpy.context.scene
    sc.frame_start=1;sc.frame_end=1+FRAME_COUNT*4
    # Named cross-shape keys align independently on each 3D rod, gear,
    # nose/sheave and counterweight. End frame equals start exactly.
    poses=[]
    for n in range(1,FRAME_COUNT):
        m=A.mesh()
        for k,(u,v) in enumerate(LAYOUT):motion(m,2*u,2*v,k,.78+k*.48+tau*n/FRAME_COUNT)
        poses.append(m)
    objs=[o for o in sc.objects if o.name.startswith("Well ") and " move " in o.name and o.type=="MESH"]
    assert len(objs)==50,len(objs)
    for obj in objs:
        obj.shape_key_add(name="Rest phase")
        for frame,m in enumerate(poses,1):
            ps=m.vertices[obj.name]
            key=obj.shape_key_add(name=f"Pump cycle phase {frame:02d}")
            assert len(ps)==len(key.data)
            for v,p in zip(key.data,ps):v.co=p
            for f,value in ((frame*4-3,0),(frame*4+1,1),(frame*4+5,0)):
                key.value=value
                key.keyframe_insert(data_path="value",frame=f)
        for f in obj.data.shape_keys.animation_data.action.fcurves:
            for p in f.keyframe_points:p.interpolation="LINEAR"
    sc.frame_set(1)
    sc["Motion"]="Five phase-offset, 12-step editable pumps. Rigid-link mechanical loop. Native tiles bake frame 1."
    bpy.ops.wm.save_as_mainfile(filepath=str(S.ROOT/"art"/"stock_oil_well.blend"),compress=True)


if __name__=="__main__":
    S.build(NAME,LAYOUT,(("Five individual pads and gathering pipe work",pads),
      ("Cast drive housings, beam frames, and functioning wellheads",frames),
      ("Moving horseheads, reciprocating rods and eccentric links",operating)),
      "Tideland Oil Wells","stock_oil_well.blend",(2.1,2.23,.39),(8.7,9.1,6.7),7.65,
      PAL,os.getenv("STOCK_OIL_WELL_RENDER"))
    bpy.ops.wm.open_mainfile(filepath=str(S.ROOT/"art"/"stock_oil_well.blend"))
    rig_existing()

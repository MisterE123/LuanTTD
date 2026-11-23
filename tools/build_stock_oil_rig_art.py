#!/usr/bin/env python3
"""Original modular six-tile offshore platform for OpenTTD 16.0-RC1 Oil Rig #5."""
# SPDX-License-Identifier: GPL-2.0-only
import os
import sys
from math import cos, pi, sin
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_stock_farm_art as S

A,R = S.A,S.R
B,T,F,Q = S.B,S.T,S.F,S.Q
PAL = dict(S.PAL, **{
    "leg_blue":"4a6670", "gunmetal":"374850", "washed_blue":"6c8688",
    "grey_aluminium":"acb9b5", "deck_blue":"485f61", "deck_edge":"657b72",
    "orange_steel":"bd6742", "ochre":"d4aa5b", "offshore_red":"ad5e54",
    "night_glass":"3c5762", "window_blue":"719da8", "paint_cream":"d9c79f",
    "petrol_green":"3d6562", "white_pad":"ddd8bd", "pad_green":"54705d",
    "yellow_light":"ffc279", "green_light":"85cda1", "black_rubber":"343b3b",
})
A.PAL=PAL
A.P=A.H.P={k:i for i,k in enumerate(PAL)}
R.COLORS[:]=PAL.values()
LAYOUT={(0,0):24,(0,1):24,(0,2):25,(1,0):26,(1,1):27,(1,2):28}
NAME="industry_oil_rig"
PAD=54/8 # aircraft_cmd.cpp HeliLower adds the Oilrig FTA delta_z
DECK=4.16

def bar(m,name,c,p,q,r=.024,ns=5):
    T(m,name,c,p,q,r,r,ns)

def ledge(m,name,x0,x1,z0,z1,level,omit=()):
    pts=[(x0,z0),(x1,z0),(x1,z1),(x0,z1),(x0,z0)]
    for j,((x,z),(u,v)) in enumerate(zip(pts,pts[1:])):
        if j in omit:
            continue
        for y in (level+.12,level+.235):
            bar(m,name+" stainless guardrails","grey_aluminium",(x,z,y),(u,v,y),.016,6)
        span=((u-x)**2+(v-z)**2)**.5
        for k in range(max(1,round(span/.27))+1):
            t=k/max(1,round(span/.27))
            a,b=x+(u-x)*t,z+(v-z)*t
            bar(m,name+" guarded stanchions","deck_edge",(a,b,level+.016),(a,b,level+.23),.013,6)

def substructure(m):
    frame=[(-.20,-.19),(3.21,-.19),(3.21,5.21),(-.20,5.21)]
    for x,z in frame:
        # Paint stops at the splash band; the actual structure reaches the seabed.
        T(m,"Submerged battered steel piles","leg_blue",(x,z,-4.15),(x,z+.025,1.25),.186,.148,12)
        T(m,"Splash-zone renewable jacket","offshore_red",(x,z,-.51),(x,z,.46),.195,.180,12)
        T(m,"Tubular deck support","leg_blue",(x,z,1.24),(x,z,4.08),.147,.119,12)
        for y,rad in ((-.54,.212),(.49,.192),(1.28,.164),(3.90,.166)):
            T(m,"Welded collars","gunmetal",(x,z,y-.037),(x,z,y+.038),rad,rad,12)
    for (x,z),(u,v) in zip(frame,frame[1:]+frame[:1]):
        for y in (-1.06,.58,2.60,3.86):
            bar(m,"Exposed transverse jacket chords","gunmetal",(x,z,y),(u,v,y),.087,8)
        for lo,hi in ((-1.06,.58),(.58,2.60),(2.60,3.86)):
            bar(m,"Chevron primary bracing","leg_blue",(x,z,lo),((x+u)/2,(z+v)/2,hi),.071,8)
            bar(m,"Chevron primary bracing","leg_blue",(u,v,lo),((x+u)/2,(z+v)/2,hi),.071,8)
    for z in (.2,1.8,3.2,4.8):
        B(m,"Structural deck transverse box girders","leg_blue",1.5,z,3.72,.122,3.87,4.05,.018)
    for i in range(5):
        B(m,"Deck grating stiffeners","gunmetal",-.04+i*.77,2.5,.083,5.75,3.91,4.05,.005)
    B(m,"Continuous working deck, closed spill tray","deck_blue",1.5,2.5,3.83,5.83,4.02,DECK,.038)
    ledge(m,"Main working deck",-.387,3.387,-.377,5.377,DECK,(3,))
    # Outboard spring berth: fenders are in the occupied tile; all
    # navigable pickup positions in the adjacent sea remain clear.
    B(m,"Boat transfer landing","gunmetal",-.254,.53,.409,1.73,.37,.50,.015)
    B(m,"Landing yellow outer nosing","ochre",-.456,.53,.027,1.706,.493,.522,.007)
    ledge(m,"Crew transfer platform",-.438,-.06,-.26,1.32,.50,(3,))
    for dz in (-.07,.19,.99,1.18):
        T(m,"Recessed vertical boat rubber buffers","black_rubber",(-.401,dz,-.58),(-.401,dz,.438),.070,.070,8)
    for z in (.314,.506):
        bar(m,"Crew access ladder hull side","ochre",(-.30,z,.56),(-.30,z,4.24),.021,7)
    for j in range(24):
        y=.61+j*.149
        bar(m,"Crew access ladder convex rungs","grey_aluminium",(-.312,.314,y),(-.312,.506,y),.011,6)
    pts=[(.18,1.15,.61),(.18,1.15,2.51),(.18,1.15,4.43),(.52,1.15,4.43),(.52,2.56,4.43),(1.00,2.56,4.43)]
    for j,(p,q) in enumerate(zip(pts,pts[1:])):
        bar(m,"Hard loading line and riser","orange_steel",p,q,.048,12)
        if j<4:
            T(m,"Oil hose locking flange","ochre",p,tuple(a+(b-a)*.05 for a,b in zip(p,q)),.062,.062,10)
    B(m,"Berth metering desk","petrol_green",-.038,.91,.177,.237,.53,.861,.017)
    bar(m,"Parked flexible transfer hose","black_rubber",(.18,1.15,.67),(-.19,1.10,.771),.049,10)

def helideck(m):
    # Aircraft touchdown and terminal lie on the same uninterrupted pad.
    # The exact source path ends near its outboard edge, allowing tail/rotor
    # overhang over the empty surrounding water rather than adjacent plant.
    x0,x1,z0,z1=1.662,3.718,-.295,1.455
    for x,z in ((1.85,-.14),(3.31,-.14),(1.85,1.27),(3.31,1.27)):
        B(m,"Raised helideck H-section piers","washed_blue",x,z,.103,.118,DECK,6.62,.012)
    for q in (-.14,1.27):
        bar(m,"Helideck diagonal braces","ochre",(1.85,q,DECK+.58),(3.28,q,PAD-.15),.050,7)
        bar(m,"Helideck diagonal braces","ochre",(3.31,q,DECK+.58),(1.88,q,PAD-.15),.050,7)
    B(m,"Cantilevered helideck deep fascia","deck_edge",(x0+x1)/2,(z0+z1)/2,x1-x0,z1-z0,PAD-.165,PAD-.027,.025)
    B(m,"Clear green load-bearing helideck","pad_green",(x0+x1)/2,(z0+z1)/2,x1-x0-.025,z1-z0-.024,PAD-.038,PAD,.008)
    cx,cz=2.61,.625
    for j in range(48):
        a,b=j*pi/24,(j+1)*pi/24
        F(m,"Painted touchdown ring","white_pad",
          [(cx+r*cos(t),cz+r*sin(t),PAD+.003)
            for t,r in ((a,.607),(a,.639),(b,.639),(b,.607))])
    for xx in (cx-.11,cx+.11):
        Q(m,"Helipad white H","white_pad",xx-.027,xx+.027,cz-.158,cz+.158,PAD+.004)
    Q(m,"Helipad white H","white_pad",cx-.11,cx+.11,cz-.027,cz+.027,PAD+.004)
    for x in (x0+.045,x1-.045):
        for z in (-.19,.36,.91,1.36):
            B(m,"Flush green deck edge lights","green_light",x,z,.033,.033,PAD-.006,PAD+.017,.010)
    for j in range(6):
        x=x0+.12+j*.296
        B(m,"Under-edge rescue net toe plate","ochre",x,1.433,.18,.09,PAD-.08,PAD-.047,.006)
    for j in range(19):
        y=DECK+.057+(PAD-DECK-.122)*j/18
        z=1.835-j*.027
        B(m,"Inclined crew ladder treads","grey_aluminium",1.665,z,.230,.068,y-.018,y,.007)
    for x in (1.54,1.785):
        bar(m,"Outboard access handrails","ochre",(x,1.852,DECK+.19),(x,1.346,PAD+.14),.020,6)

def clip_rig(full,x,z,layout):
    # The eastern air deck cantilevers a short way over navigable sea;
    # the station and all sea-level steel stay within their six tiles.
    if (x,z)!=(1,0):
        return original_clip(full,x,z,layout)
    out=A.mesh()
    for n,items in full.parts.items():
        overhang=n.startswith(("Cantilevered helideck","Clear green load-bearing","Flush green deck edge","Under-edge rescue net"))
        for ids,col in items:
            p=[full.vertices[n][i] for i in ids]
            for axis,edge,sign,adjacent in ((0,1.5,1,False),(0,3.725 if overhang else 3.5,-1,False),
                                           (1,-.5,1,False),(1,1.5,-1,True)):
                if adjacent and all(abs(v[axis]-edge)<A.EPS for v in p):p=[]
                if not p:break
                p=A.clip(p,axis,edge,sign)
            out.face(n,col,[(a-2.5,b-.5,h) for a,b,h in p])
    return out

original_clip=S.clip

def topside(m):
    # Three-level derrick, open through both diagonals.
    pos=[(.18,2.13),(1.27,2.13),(1.27,3.29),(.18,3.29)]
    levels=(DECK,5.18,6.15,7.18,8.51)
    stages=[]
    for i,y in enumerate(levels):
        fac=1-i*.153
        stages.append([(.725+(x-.725)*fac,2.71+(z-2.71)*fac,y) for x,z in pos])
    for i,(p,q) in enumerate(zip(stages,stages[1:])):
        for j,a in enumerate(p):
            k=(j+1)%4
            bar(m,"Derrick tapered principal chords","orange_steel",a,q[j],.043,6)
            bar(m,"Derrick crossed wind webs","gunmetal",a,q[k],.019,5)
            bar(m,"Derrick crossed wind webs","orange_steel",p[k],q[j],.020,5)
            bar(m,"Derrick rectangular girts","ochre",a,p[k],.029,5)
    for j in range(4):
        bar(m,"Derrick crown frame","ochre",stages[-1][j],stages[-1][(j+1)%4],.040,6)
    T(m,"Hanging drill-string","grey_aluminium",(.725,2.71,4.35),(.725,2.71,8.49),.036,.021,10)
    T(m,"Travelling block four-sheave body","offshore_red",(.725,2.71,6.04),(.725,2.71,6.26),.13,.11,12)
    T(m,"Rotary drill floor turntable","gunmetal",(.725,2.71,4.16),(.725,2.71,4.26),.345,.335,16)
    ledge(m,"Drilling platform",-.06,1.465,1.835,3.48,DECK)
    # Galley, control room and passage windows, not single printed cubes.
    for i,(x,z,high) in enumerate(((.584,4.46,5.91),(2.665,4.45,5.22))):
        B(m,"Blast-wall living module base","offshore_red",x,z,1.48,1.55,DECK+.018,high-.120,.044)
        B(m,"Overhanging raised storm roof","paint_cream",x,z,1.536,1.590,high-.18,high,.041)
        B(m,"Fire isolation wall waist","washed_blue",x,z,1.50,1.57,DECK+.07,DECK+.235,.012)
        for shift in (-.42,-.14,.14,.42):
            B(m,"Inset black control window gasket","night_glass",x+shift,z+.781,.226,.042,high-.67,high-.382,.015)
            B(m,"Inset broad wheelhouse glazing","window_blue",x+shift,z+.803,.190,.018,high-.632,high-.412,.012)
            B(m,"Window drip sill","paint_cream",x+shift,z+.810,.206,.039,high-.657,high-.636,.006)
        for shift in (-.57,.38):
            B(m,"Roof small emergency intake","deck_edge",x+shift,z-.36,.143,.186,high-.011,high+.117,.015)
        B(m,"Crew side entry recessed threshold","gunmetal",x+.746,z-.09,.040,.318,DECK+.037,DECK+.541,.024)
        B(m,"Separate storm door","paint_cream",x+.767,z-.09,.026,.255,DECK+.049,DECK+.509,.020)
    # Staged separation plant, an articulated crane and a separate flare stack.
    for x,z,color in ((2.13,2.05,"washed_blue"),(2.78,2.37,"petrol_green")):
        T(m,"Process separation round drum","gunmetal",(x-.32,z,4.69),(x+.32,z,4.69),.225,.225,18)
        T(m,"Process separation removable shell",color,(x-.309,z,4.69),(x+.309,z,4.69),.235,.235,18)
        for xx in (x-.235,x+.235):
            T(m,"Drum retention flange","grey_aluminium",(xx-.021,z,4.69),(xx+.021,z,4.69),.251,.251,14)
            B(m,"Engineered drum stand","gunmetal",xx,z,.098,.23,DECK,4.522,.016)
    for x,z in ((2.155,1.745),(2.815,2.071)):
        bar(m,"Routed separation control pipe","orange_steel",(x,z-.125,4.30),(x,z-.125,4.82),.037,9)
        bar(m,"Routed separation control pipe","orange_steel",(x,z-.125,4.82),(x,z+.195,4.82),.037,9)
    x,z=2.87,3.14
    T(m,"Crane pedestalled slew bearing","gunmetal",(x,z,DECK),(x,z,4.46),.205,.205,14)
    B(m,"Crane sleeved hydraulic house","ochre",x,z,.367,.279,4.45,4.96,.05)
    bar(m,"Raised crane boom","ochre",(x,z,4.90),(1.526,3.51,6.10),.056,6)
    bar(m,"Crane diagonal telescoping hydraulic ram","gunmetal",(x,z,4.73),(2.154,3.34,5.553),.027,10)
    bar(m,"Crane suspended steel winch cable","gunmetal",(1.543,3.5,6.10),(1.543,3.5,5.36),.012,7)
    for a in range(10):
        t,u=pi*a/9,pi*(a+1)/9
        bar(m,"Crane forged curve hook","ochre",(1.543-.048*sin(t),3.50,5.35-.048*cos(t)),
            (1.543-.048*sin(u),3.50,5.35-.048*cos(u)),.013,6)
    x,z=3.266,5.061
    T(m,"Independent flare boom mast lower collar","gunmetal",(x,z,DECK),(x,z,5.54),.062,.049,8)
    T(m,"Independent flare boom mast hot sleeve","offshore_red",(x,z,5.54),(x,z,7.12),.053,.035,8)
    T(m,"Slotted blue gas flare tip","grey_aluminium",(x,z,7.10),(x,z,7.32),.056,.044,12)
    bar(m,"Antenna rising above wheelhouse","gunmetal",(.30,4.72,5.93),(.30,4.72,6.64),.014,8)
    bar(m,"Short horizontal radar aerial","paint_cream",(.14,4.72,6.64),(.46,4.72,6.64),.016,6)

if __name__=="__main__":
    title="North Reach | Offshore production and aviation"
    look,cam=(1.45,2.44,3.76),(-9,-12,12.3)
    S.clip=clip_rig
    S.build(NAME,LAYOUT,(("Welded offshore jacket and crew berth",substructure),
        ("Helicopter terminal and clear approach",helideck),("Derrick, extraction, living quarters and crane",topside)),
        title,"stock_oil_rig.blend",look,cam,13.75,PAL,None)
    scene=bpy.context.scene
    scene["Upstream cells"]="OpenTTD 16.0-RC1 Oil Rig #5: GFX 24,24,25,26,27,28"
    scene["Deck datum"]="Ground-independent: Z=0 still water, strip near edge (+31,+9) airport pixels"
    bpy.ops.wm.save_as_mainfile(filepath=str(R.ROOT/"art/stock_oil_rig.blend"),compress=True)
    if render:=os.getenv("STOCK_OIL_RIG_RENDER"):
        bpy.ops.mesh.primitive_plane_add(size=48,location=(2,2,0))
        water=bpy.data.materials.new("North Reach cold seawater")
        water.diffuse_color=(.095,.228,.265,1)
        bpy.context.object.data.materials.append(water)
        ob=bpy.data.objects.new("Survey review",bpy.data.cameras.new("Survey review"))
        scene.collection.objects.link(ob)
        ob.location=cam; ob.rotation_euler=(Vector(look)-Vector(cam)).to_track_quat("-Z","Y").to_euler()
        ob.data.type="ORTHO"; ob.data.ortho_scale=12.3; scene.camera=ob
        scene.render.engine="BLENDER_WORKBENCH"; scene.render.resolution_x=1200; scene.render.resolution_y=1000
        s=scene.display.shading; s.light="STUDIO"; s.color_type="MATERIAL"; s.show_shadows=True
        s.show_cavity=True; s.cavity_type="BOTH"; s.cavity_ridge_factor=1.15
        scene.view_settings.view_transform="Standard"; scene.render.filepath=render
        bpy.ops.render.render(write_still=True)

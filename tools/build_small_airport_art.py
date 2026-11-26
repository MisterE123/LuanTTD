#!/usr/bin/env python3
"""Original Country Airfield kit, one mesh per stock logical tile.

blender -b -t 4 --python-exit-code 1 --python tools/build_small_airport_art.py
SMALL_AIRPORT_RENDER=/tmp/country.png blender -b -t 4 --python tools/build_small_airport_art.py

OpenTTD 14.1: src/table/airport_defaults.h (_tile_table_country_0),
airport_movement.h (_airport_moving_data_country). No copied source art.
Coordinates are native X/Z; stock pixels project as p/8-.5 from the airport
north-west node. Floor datum 0 is its original flat grass top.
"""
from math import cos, sin, pi, hypot
from pathlib import Path
from random import Random
import os
import sys
import struct
import zlib

import bpy
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_ship_facility_art as H

RAIL=H.rail
PAL=dict(
    foundation="777b75", slate="344b54", dark_slate="293b43", slate_rib="53646a",
    glazed="6d9ca3", glass_light="afc3be", glass_dark="3c626a", ochre="a47448",
    board="d7c4a2", bone="f1e0bb", wood="71513c", timber="8d684d",
    brick="ac6851", dark_brick="9c5946", pale_brick="bc7a59", mortar="b8a394",
    jamb="495b57", dark_green="36544d", teal="487369", bright_teal="6e8b78",
    steel="738b8b", dark_metal="4a4d49", bench="916b4b",
    concrete="a9a297", concrete_l="b4aa9b", concrete_d="a19989", concrete_seal="898278",
    gravel="8b8570", gravel_l="9c927b", gravel_d="827d6e",
    runway="565a55", runway_l="5b5e58", runway_d="50544e", asphalt_joint="464944",
    paint="e3d9bf", paint_shadow="c5bda5", yellow="c9a55f",
    red="ba6651", rose="d38467", orange="e39254", flag_bone="e9d9ba",
    chalk="a5b8a8", equipment="505855", gauge="989992",
)
H.PALETTE=PAL
H.P={n:i for i,n in enumerate(PAL)}
RAIL.COLORS[:]=PAL.values()
P=H.P
B,T=H.box,H.tube
ROOT=RAIL.ROOT
EPS=1e-9
RUN_LOW,RUN_HIGH=3.85,5.16
PAINT=.010
PORTAL=(4.995,7.337)
FOOTPRINT=(-.5,7.5,-.5,5.5)
HANGAR_X=53/8-.5
SOURCE=((0,0,"01 Roadside Waiting Room"),(1,0,"02 Dispatch and tower"),(2,0,"03 Service office and hangar annex"),
        (3,0,"04 Open-sided hangar"),(0,1,"05 North lawn and stand B"),(1,1,"06 Stand A and circuit west"),
        (2,1,"07 Apron circuit east"),(3,1,"08 Hangar taxi lead"),
        (0,2,"09 West runway threshold"),(1,2,"10 West runway center"),
        (2,2,"11 East runway center"),(3,2,"12 East runway threshold"))
DIGITS={
    "0":("01110","11011","11011","11011","11011","11011","01110"),
    "1":("01100","11100","01100","01100","01100","01100","11111"),
    "2":("01110","10011","00011","00110","01100","11000","11111"),
    "7":("11111","00011","00110","00110","01100","01100","01100"),
    "9":("01110","11011","11011","01111","00011","10011","01110"),
    "A":("01110","11011","11011","11111","11011","11011","11011"),
    "B":("11110","11011","11011","11110","11011","11011","11110"),
    "D":("11110","11011","11011","11011","11011","11011","11110"),
    "E":("11111","11000","11000","11110","11000","11000","11111"),
    "F":("11111","11000","11000","11110","11000","11000","11000"),
    "G":("01111","11000","11000","11011","11011","11011","01111"),
    "H":("11011","11011","11011","11111","11011","11011","11011"),
    "I":("11111","00100","00100","00100","00100","00100","11111"),
    "L":("11000","11000","11000","11000","11000","11000","11111"),
    "N":("11001","11001","11101","11111","11011","11001","11001"),
    "O":("01110","11011","11011","11011","11011","11011","01110"),
    "R":("11110","11011","11011","11110","11100","11010","11011"),
    "W":("10001","10001","10101","10101","11111","11011","10001"),
    "Y":("11011","11011","11011","01110","00100","00100","00100"),
    " ":("00000",)*7,
}

def mesh():
    return RAIL.Mesh(RAIL.terrain_height(0))

def face(m,n,c,pts):
    m.face(n,P[c],pts)

def rect(m,n,c,x0,x1,z0,z1,h):
    face(m,n,c,[(x0,z0,h),(x1,z0,h),(x1,z1,h),(x0,z1,h)])

def line(m,n,c,coords,w,h):
    for (x,z),(a,b) in zip(coords,coords[1:]):
        d=hypot(a-x,b-z)
        if d<EPS:continue
        dx,dz=(b-z)*w/(2*d),(x-a)*w/(2*d)
        x0,z0=x-dx,z-dz
        x1,z1=a-dx,b-dz
        face(m,n,c,[(x0,z0,h),(x1,z1,h),(a+dx,b+dz,h),(x+dx,z+dz,h)])

def lettering(m,name,s,centre,scale,side="south",color="bone"):
    x,z,h=centre
    for i,c in enumerate(s):
        for r,row in enumerate(DIGITS[c]):
            j=0
            while j<5:
                if row[j]=="0":
                    j+=1
                    continue
                end=j+1
                while end<5 and row[end]=="1":end+=1
                a=(i*6+j-(len(s)*6-1)/2)*scale
                b=(i*6+end-(len(s)*6-1)/2)*scale
                k=(3.5-r)*scale
                if side=="south":
                    face(m,name,color,[(x-b,z,h+k),(x-a,z,h+k),(x-a,z,h+k-scale),(x-b,z,h+k-scale)])
                elif side=="east":
                    face(m,name,color,[(x+k-scale,z-b,h),(x+k,z-b,h),(x+k,z-a,h),(x+k-scale,z-a,h)])
                elif side=="west":
                    face(m,name,color,[(x-k,z+a,h),(x-k+scale,z+a,h),(x-k+scale,z+b,h),(x-k,z+b,h)])
                elif side=="north":
                    face(m,name,color,[(x-b,z-k,h),(x-a,z-k,h),(x-a,z-k+scale,h),(x-b,z-k+scale,h)])
                else:raise ValueError(side)
                j=end

def strip(m,n,c,coords,half,h,z_max=None):
    left,right=[],[]
    for i,(x,z) in enumerate(coords):
        dirs=[]
        for p,q in ((max(0,i-1),i),(i,min(len(coords)-1,i+1))):
            if p==q:continue
            tx,tz=coords[q][0]-coords[p][0],coords[q][1]-coords[p][1]
            d=hypot(tx,tz);dirs.append((-tz/d,tx/d))
        nx,nz=[sum(c)/len(dirs) for c in zip(*dirs)]
        divisor=max(.78,nx*nx+nz*nz)
        left.append((x+half*nx/divisor,z+half*nz/divisor,h))
        right.append((x-half*nx/divisor,z-half*nz/divisor,h))
    for i in range(len(coords)-1):
        polygon=[right[i],right[i+1],left[i+1],left[i]]
        if z_max is not None:polygon=clip(polygon,1,z_max,-1)
        face(m,n,c,polygon)

def tarmac(m):
    # Grass is always the game world cube below. Daylight can still be seen
    # through the grass space between the level hardstands; no full rectangle.
    rect(m,"Runway aggregate shoulders","gravel",-.5,7.5,3.77,5.24,.002)
    rect(m,"Seamless rolled runway wearing course","runway",-.5,7.5,RUN_LOW,RUN_HIGH,.005)
    for i in range(16):
        x=-.5+i*.5
        if i and i%2:
            rect(m,"Fine repair joins","asphalt_joint",x-.003,x+.003,RUN_LOW+.004,RUN_HIGH-.004,.006)
    for z in (RUN_LOW+.085,RUN_HIGH-.085):
        rect(m,"Continuous white runway edge","paint_shadow",-.43,7.43,z-.011,z+.011,PAINT)
    for x in (1.1,1.76,2.42,3.08,3.74,4.4,5.06,5.72):
        rect(m,"Broken white runway centerline","paint",x,x+.27,4.483,4.517,PAINT)
    for side,x,xb in (("east",.30,-.115),("west",6.69,7.10)):
        for z in (4.16,4.28,4.40,4.60,4.72,4.84):
            rect(m,"White piano-key threshold bars","paint",xb-.14,xb+.14,z-.018,z+.018,PAINT)
        lettering(m,"Flat painted runway identifiers",("09" if side=="east" else "27"),(x,4.5,PAINT),.068,side,"paint")
        # Edge approach markers are conspicuous but flush; there are no
        # collision obstructions beside either runway turn.
    for i in range(15):
        x=-.32+i*.54
        for z in (3.813,5.20):
            rect(m,"Flush capped runway reflectors","dark_metal",x-.024,x+.024,z-.023,z+.023,.006)
            rect(m,"Inset amber lenses","bone",x-.011,x+.011,z-.01,z+.01,.008)

    # Asphalt strip in last row, concrete-only lobes on grass mid-row.
    # Runway-to-hangar apron, width 1.43, with separate narrow taxi lanes.
    taxi=[(HANGAR_X,-.5),(HANGAR_X,1.53),(HANGAR_X,2.88),(HANGAR_X,3.52),(HANGAR_X,RUN_LOW)]
    strip(m,"Taxiway gravel margins","gravel",taxi,.747,.002)
    strip(m,"Concrete taxiway from runway to hangar","concrete",taxi,.684,.005)
    for z in (1.51,1.95,2.39,2.83,3.27):
        rect(m,"Taxiway transverse sealed joints","concrete_seal",HANGAR_X-.678,HANGAR_X+.678,z-.005,z+.005,.006)
    main_spur=[(HANGAR_X,2.875),(5.68,2.875),(4.88,2.875),(3.9,2.51),(3.5,2.375)]
    west_spur=[(HANGAR_X,3.78),(4.875,4.125),(2.5,4.125),(1.41,3.13),(.75,2.375)]
    strip(m,"Primary stand concrete fillet","concrete",main_spur,.474,.0057)
    strip(m,"Secondary stand concrete fillet","concrete_d",west_spur,.395,.0054,RUN_LOW)
    for xc,name in ((.75,"B"),(3.5,"A")):
        B(m,"Scored parking hardstand "+name,"concrete_l",xc,2.22,1.75,1.16,.000,.007,.17)
        for x in (-.56,0,.56):
            rect(m,"Parking pad slab joints","concrete_seal",xc+x-.004,xc+x+.004,1.656,2.784,.008)
        # The parking centre marker is exactly on the stock hold point.
        rect(m,"Parking stand stop-line","yellow",xc-.256,xc+.256,2.375-.015,2.375+.015,.013)
        for d in (-.66,.66):
            z=2.27
            rect(m,"Parking stand white boxes","paint_shadow",xc+d-.012,xc+d+.012,z-.43,z+.43,.013)
        lettering(m,"Painted parking stand identifiers",name,(xc,1.91,.013),.039,"north","yellow")
        line(m,"Passenger painted boarding lead","paint",[(xc,1.735),(xc,1.31),(xc-.36,1.13)],.022,.013)
        for z in (1.38,1.49,1.60):
            rect(m,"Pedestrian white crosswalk bars","paint",xc-.14,xc+.14,z-.013,z+.013,.013)
    # Dashed guides avoid coloring over free-running plane wheels.
    for z in (1.42,1.68,1.94,2.20,2.46,2.72,2.98,3.24,3.50):
        rect(m,"Flat ochre taxi centre dashes","yellow",HANGAR_X-.018,HANGAR_X+.018,z,z+.135,.012)
    for elbow in (main_spur,west_spur[:-2]):
        for (a,b),(c,d) in zip(elbow,elbow[1:]):
            q=hypot(c-a,d-b)
            for j in range(int(q/.215)):
                t=(j+.12)*.215/q
                u=min(1.,t+.1/q)
                z0=b+(d-b)*t
                if z0<3.81:
                    line(m,"Deck paint stand circuit centreline","yellow",[(a+(c-a)*t,z0),(a+(c-a)*u,b+(d-b)*u)],.029,.012)
    # A few soft chips in asphalt; visual density scales with native range.
    rng=Random(1928)
    for i in range(452):
        x,z=rng.uniform(-.48,7.48),rng.uniform(3.86,5.15)
        w,l=rng.uniform(.007,.024),rng.uniform(.005,.013)
        rect(m,"Asphalt aggregate weathering",rng.choice(("runway","runway_l","runway_d")),x-w/2,x+w/2,z-l/2,z+l/2,.007)

def gable(m,n,x,z,w,l,low,peak,mat="slate",ridge="x"):
    if ridge=="z":
        p=[(-w/2,-l/2,low),(0,-l/2,peak),(w/2,-l/2,low),
           (-w/2,l/2,low),(0,l/2,peak),(w/2,l/2,low)]
    else:
        p=[(-w/2,l/2,low),(-w/2,0,peak),(-w/2,-l/2,low),
           (w/2,l/2,low),(w/2,0,peak),(w/2,-l/2,low)]
    p=[(x+a,z+b,c) for a,b,c in p]
    q=[(a,b,c-.038) for a,b,c in p]
    for ids in ((0,3,4,1),(1,4,5,2)):
        face(m,n,mat,[p[i] for i in ids][::-1])
        face(m,n,"dark_slate",[q[i] for i in ids])
    for i,j in ((0,1),(1,2),(0,3),(2,5),(3,4),(4,5)):
        # Roof edge fascia cannot be a two-sided paper sheet.
        face(m,n+" fascia","slate_rib",[p[i],p[j],q[j],q[i]])
    T(m,n+" capped ridge","dark_slate",p[1],p[4],.019,.019,8)
    if ridge=="x":
        for j in range(1,max(1,round(w/.115))):
            a=x-w/2+j*w/round(w/.115)
            T(m,n+" standing seams","slate_rib",(a,z-l/2,low+.001),(a,z,peak+.003),.0048,.0048,5)
            T(m,n+" standing seams","slate_rib",(a,z,peak+.003),(a,z+l/2,low+.001),.0048,.0048,5)
    else:
        for j in range(1,max(1,round(l/.092))):
            b=z-l/2+j*l/round(l/.092)
            T(m,n+" standing seams","slate_rib",(x-w/2,b,low+.001),(x,b,peak+.003),.006,.006,5)
            T(m,n+" standing seams","slate_rib",(x,b,peak+.003),(x+w/2,b,low+.001),.006,.006,5)

def gable_end(m,n,x,z,w,eave,peak,c,direction):
    pts=[(x-w/2,z,eave-.005),(x+w/2,z,eave-.005),(x,z,peak-.016)]
    face(m,n,c,pts[::-1] if direction==1 else pts)
    face(m,n,c,pts if direction==1 else pts[::-1])

def facade_window(m,title,x,z,w,h0,h1,orientation="south"):
    front=orientation=="south"
    def box(n,c,a,width,h0,h1,depth=.016):
        if front:B(m,title+n,c,x+a,z,width,depth,h0,h1,.004)
        else:B(m,title+n,c,x,z+a,depth,width,h0,h1,.004)
    box(" dark recessed frame","jamb",0,w+.027,h0-.015,h1+.019,.021)
    box(" glazing","glazed",0,w,h0,h1,.028)
    box(" stone sill","bone",0,w+.054,h0-.028,h0-.007,.06)
    box(" top mullion","bone",0,w+.014,h1-.012,h1+.003,.037)
    for a in (-w/2,0,w/2):box(" timber mullion","bone",a,.010,h0,h1,.037)
    box(" mid horizontal rail","bone",0,w,(h0+h1)/2-.005,(h0+h1)/2+.005,.037)
    box(" oblique light catch","glass_light",.052*w,.15*w,h1-.042,h1-.019,.038)

def doorway(m,name,x,z,w,bottom,h,kind="teal"):
    B(m,name+" dressed jamb","bone",x,z,w+.052,.043,bottom,h+.035,.009)
    B(m,name+" painted frame and door leaf",kind,x,z+.026,w,.026,bottom,h,.006)
    B(m,name+" ticket glass","glass_dark",x,z+.043,w*.7,.012,h-.18,h-.032,.004)
    B(m,name+" brass letter plate","ochre",x+.02,z+.054,.042,.015,h-.23,h-.211,.002)
    B(m,name+" dark granite tread","foundation",x,z+.055,w+.110,.155,.004,.060,.012)

def brickwork(m,n,x,z,w,l,h,seed):
    B(m,n+" ground course","foundation",x,z,w+.031,l+.035,.0,.14,.017)
    B(m,n+" foot wall mass","mortar",x,z,w,l,.125,h)
    B(m,n+" pale upper frieze","board",x,z,w+.021,l+.017,h-.097,h+.008,.008)
    rng=Random(seed)
    for row in range(int((h-.22)/.06)):
        za=.14+row*.06
        start=x-w/2
        a=0
        while a<w-.005:
            b=min(w,a+(.065 if a==0 and row%2 else .125))
            if b-a>.008:
                B(m,n+" weathered staggered brickwork",rng.choice(("brick","brick","dark_brick","pale_brick")),
                  start+(a+b)/2,z+l/2,(b-a)-.007,.012,za,za+.054)
            a=b

def lantern(m,x,z,y,name="Canopy cargo lamp",pole=False):
    if pole:
        B(m,name+" cast iron boot","foundation",x,z,.060,.060,0,.060,.008)
        T(m,name+" forged pole","dark_green",(x,z,.04),(x,z,y),.019,.013,8)
    B(m,name+" amber glazing","bone",x,z,.068,.068,y-.044,y+.023,.014)
    B(m,name+" spun hood","dark_green",x,z,.105,.098,y+.014,y+.041,.019)
    B(m,name+" powder-coated body ring","teal",x,z,.083,.076,y-.044,y-.035,.011)

def terminal(m):
    # Stock APT_SMALL_BUILDING_1, _2, _3 north of the standby centers.
    rect(m,"Terminal concourse terrace","concrete_d",-.39,4.74,-.40,1.36,.005)
    for x in (.01,.44,.87,1.30,1.73,2.16,2.59,3.02,3.45,3.88,4.31):
        rect(m,"Dressed concourse slab seams","concrete_seal",x-.004,x+.004,.72,1.34,.008)
    brickwork(m,"Waiting hall",.61,.255,1.66,1.005,.552,11)
    gable(m,"Waiting hall slate roof",.61,.255,1.78,1.145,.559,.856)
    for x in (.08,1.03):
        facade_window(m,"Waiting hall sash",x,.767,.32,.245,.467)
    doorway(m,"Waiting hall entry",.555,.772,.235,.06,.449)
    B(m,"Low covered verandah","dark_green",.63,.984,1.746,.435,.524,.579,.023)
    B(m,"Verandah painted drip edge","bright_teal",.63,1.205,1.725,.026,.516,.564,.006)
    for x in (-.214,.355,.805,1.436):
        B(m,"Period square covered-verandah post","teal",x,1.19,.040,.048,.016,.541,.006)
        B(m,"Covered verandah post bracket","bright_teal",x,1.152,.083,.091,.45,.53,.012)
    for x in (.08,1.095):
        B(m,"Verandah wood seat","bench",x,.968,.33,.125,.095,.127,.01)
        B(m,"Verandah slatted timber back","wood",x,.932,.33,.037,.125,.232,.008)
        for dx in (-.12,.12):B(m,"Verandah bench iron trestle","dark_green",x+dx,.969,.03,.073,.019,.106,.005)
    lantern(m,.563,1.115,.484)
    B(m,"Waiting room dark destination board","slate",.62,.906,1.085,.038,.548,.677,.007)
    lettering(m,"Raised AIRFIELD terminal nameplate","AIRFIELD",(.62,.927,.608),.019)

    brickwork(m,"Airfield dispatch office",2.23,.205,1.47,1.053,.628,33)
    doorway(m,"Dispatch ramp door",1.759,.753,.231,.06,.441)
    for x in (2.15,2.605):
        facade_window(m,"Dispatch office sash",x,.737,.241,.248,.528)
    B(m,"Dispatch office flat masonry coping","slate",2.23,.205,1.53,1.13,.62,.68,.018)
    # Genuine upper observation cab: glass frames, stone corbels, and roof.
    B(m,"Corbelled observation deck","foundation",2.24,.233,1.23,.96,.665,.76,.029)
    B(m,"Watch cab timber plinth","teal",2.24,.233,1.10,.82,.762,.839,.014)
    B(m,"Watch cab real side glazing","glass_dark",2.24,.233,1.058,.783,.824,1.221,.015)
    for x in (1.824,2.235,2.649):
        facade_window(m,"Observation south sashes",x,.632,.234,.865,1.18)
    for z in (-.026,.252,.503):
        facade_window(m,"Observation east sashes",2.78,z,.201,.863,1.180,"east")
        facade_window(m,"Observation west sashes",1.699,z,.201,.863,1.180,"west")
    B(m,"Watch cab fascia","teal",2.24,.233,1.19,.92,1.180,1.238,.015)
    gable(m,"Watch cab hipped silhouette",2.24,.233,1.29,1.011,1.23,1.406,"dark_slate")
    T(m,"Airfield radio mast","dark_metal",(2.24,.233,1.389),(2.24,.233,1.685),.015,.009,9)
    T(m,"Airfield radio dipole","steel",(2.06,.233,1.635),(2.42,.233,1.635),.008,.008,7)
    T(m,"Mast red glass warning lamp","red",(2.24,.233,1.684),(2.24,.233,1.728),.022,.015,10)
    T(m,"Terminal analog clock painted case","teal",(2.608,.748,.585),(2.608,.798,.585),.102,.092,22)
    T(m,"Terminal analog clock ivory enamel dial","bone",(2.608,.800,.585),(2.608,.808,.585),.080,.080,24)
    for a in range(12):
        q=pi*a/6; x,z=2.608+sin(q)*.065,.585+cos(q)*.065
        T(m,"Analog clock hour indexes","slate",(x,.812,z),(x,.817,z),.0044,.0044,5)
    T(m,"Analog clock hour hand","slate",(2.608,.816,.585),(2.581,.816,.61),.006,.004,6)
    T(m,"Analog clock minute hand","slate",(2.608,.816,.585),(2.645,.816,.626),.0044,.003,5)

    # Third frontage has its own fabric, not architecture duplicated.
    brickwork(m,"Dispatch agents annex",3.831,.179,1.47,.926,.436,54)
    gable(m,"Departure annex shallow slate roof",3.831,.179,1.54,1.016,.446,.684)
    for x in (3.381,4.212):
        facade_window(m,"Agent small punched window",x,.648,.253,.184,.368)
    doorway(m,"Agent luggage claim doorway",3.836,.658,.231,.042,.369)
    B(m,"Boarding checker cottage name","teal",3.826,.656,.956,.028,.457,.577,.008)
    lettering(m,"Raised departure annex AIR name","AIR",(3.826,.672,.515),.023)
    lantern(m,3.853,.802,.439)

    # A wool baggage trolley with two wheels and authentic cargo forms.
    for x in (3.18,4.49):
        z=1.071
        B(m,"Oak baggage hand trolley platform","bench",x,z,.208,.302,.079,.103,.012)
        for dx in (-.104,.104):
            T(m,"Baggage trolley cast spoked wheels","dark_metal",(x+dx-.010,z+.051,.065),
              (x+dx+.010,z+.051,.065),.065,.065,12)
            T(m,"Baggage trolley hub","steel",(x+dx-.015,z+.051,.065),
              (x+dx+.015,z+.051,.065),.024,.024,9)
        for dz in (-.06,.062):
            B(m,"Period luggage cases","wood" if dz>0 else "ochre",x,z+dz,.151,.109,.103,.205,.018)
            for dx in (-.047,.047):
                B(m,"Case leather straps","timber",x+dx,z+dz,.008,.103,.197,.208,.004)
        T(m,"Baggage trolley bent push handle","teal",(x,z-.139,.092),(x,z-.193,.294),.012,.012,8)
        T(m,"Baggage trolley horizontal handgrip","teal",(x-.069,z-.193,.294),(x+.069,z-.193,.294),.012,.012,8)

def hangar(m):
    a,b=PORTAL
    x=(a+b)/2
    z=.383
    length=1.666
    for sign,edge in ((-1,a),(1,b)):
        xc=edge+sign*.043
        B(m,"Hangar concrete flank foundation","foundation",xc,z,.103,1.641,.0,.085,.008)
        B(m,"Hangar longitudinal opaque steel walls","teal",xc,z,.079,1.601,.085,.926,.007)
        for j in range(30):
            zz=z-.776+j*.052
            for direction in (-1,1):
                B(m,"Hangar vertical corrugated wall seams","bright_teal",xc+direction*.041,zz,
                  .006,.010,.082,.932,.001)
        for zz in (-.36,.02,.404,.785,1.138):
            B(m,"Hangar steel wall ribs","dark_green",xc,zz,.112,.040,.035,.961,.008)
        for zz in (-.24,1.019):
            B(m,"Hangar corner impact dye","yellow",xc,zz,.116,.050,.081,.177,.004)
        # Home to the real open parked sliding slab. Nothing bridges the
        # front/rear below the lintel; both ends admit the aircraft silhouette.
        for end in (-1,1):
            zz=z+end*.800
            B(m,"Open bi-parting door leaves against flanks","slate",xc,zz,.111,.038,.021,.863,.007)
            B(m,"Side stowed door pull","steel",xc,zz+end*.025,.045,.018,.448,.534,.003)
        for zz in (-.308,.121,.546,.970):
            B(m,"Hangar raised clerestory light strip","slate",xc,zz,.090,.258,.672,.846,.008)
            B(m,"Hangar clerestory glass","glazed",xc,zz,.099,.221,.704,.817,.005)
            for dz in (-.08,0,.08):
                B(m,"Hangar clerestory ribs","bone",xc,zz+dz,.106,.008,.697,.829)
        # The port maintenance equipment is outside the swept width.
        if sign==-1:
            B(m,"Belted mobile tool chest","dark_metal",edge-.170,.374,.136,.201,.019,.146,.012)
            B(m,"Tool chest enameled drawers","red",edge-.170,.477,.116,.032,.049,.126,.008)
            for h in (.068,.095,.121):
                B(m,"Tool chest chrome handles","steel",edge-.170,.494,.079,.013,h-.003,h+.004,.003)
    for end in (-1,1):
        zz=z+end*.817
        B(m,"Above-clearance portal steel lintel","slate",x,zz,b-a+.14,.088,.908,.992,.013)
        B(m,"Portal exposed sliding hangar door track","dark_metal",x,zz+end*.006,b-a+.17,.032,.889,.925,.005)
        gable_end(m,"Corrugated hangar gable face",x,zz,2.544,.980,1.348,"dark_green",end)
        for j in range(41):
            xx=x-1.221+j*.061
            roof=1.348-.360*abs(xx-x)/1.29
            B(m,"Gable vertical metal sheets","teal",xx,zz,.038,.013,.985,max(roof,.996),.002)
        B(m,"Hangar ivory porcelain identification board","board",x,zz+end*.012,.765,.04,1.024,1.176,.012)
        if end==1:lettering(m,"Raised HANGAR portal nameplate","HANGAR",(x,zz+.034,1.103),.020,"south","slate")
        for xx in (x-.542,x+.542):
            lantern(m,xx,zz-end*.06,.839,"Hangar bulkhead lamp")
    gable(m,"Historic corrugated steel hangar roof",x,z,2.595,1.79,.996,1.39,"slate","z")
    for zz in (-.29,.042,.391,.740,1.079):
        for dx in (-1,1):
            T(m,"Internal exposed roof trusses","dark_metal",(x,zz,1.345),
              (x+dx*1.176,zz,.949),.016,.014,8)
        B(m,"Open hall truss tie beam","dark_metal",x,zz,2.361,.032,.904,.935,.004)

def wind(m, static_only=False):
    # Stock border grass may house fence/flag; only three low fence bays at
    # the sides north of the runway's entire 360-degree turn envelope.
    for x in (-.413,7.411):
        for z in (1.72,2.09,2.46,2.83,3.12):
            B(m,"Oak boundary fence masonry shoe","foundation",x,z,.077,.065,.001,.061,.006)
            B(m,"Boundary fence ported post","board",x,z,.043,.039,.057,.205,.006)
        for h in (.110,.174):
            B(m,"Boundary oak plank fence rail","board",x,2.42,.021,1.41,h-.013,h+.013,.005)
    # A genuinely tapered open sock with a bright lip seen from either side.
    x,z=-.282,1.815
    B(m,"Windsock poured footing","foundation",x,z,.125,.132,.003,.091,.012)
    T(m,"Windsock galvanized mast","dark_metal",(x,z,.07),(x,z,.91),.023,.017,10)
    T(m,"Windsock brass swivel collar","ochre",(x,z,.884),(x,z,.928),.026,.026,10)
    if not static_only:
        T(m,"Windsock swiveling brass support","ochre",(x,z,.898),(x+.042,z-.04,.898),.014,.014,8)
        def ring(t,r):
            xx=x+.04+t*.375
            zz=z-.04-t*.32
            h=.91-.105*t*t
            return [(xx+sin(2*pi*j/12)*r*.58,zz+sin(2*pi*j/12)*r*.66,h+cos(2*pi*j/12)*r)
                    for j in range(12)]
        for j in range(6):
            a,b=j/6,(j+1)/6
            l,r=ring(a,.101-.061*a),ring(b,.101-.061*b)
            for i in range(12):
                ids=(i,(i+1)%12)
                q=(l[ids[0]],r[ids[0]],r[ids[1]],l[ids[1]])
                face(m,"Open striped wind sleeve cloth","orange" if j%2==0 else "flag_bone",q)
                # The folded inside face is real, dark inner textile rather than
                # requiring an alpha texture or rendering back faces.
                qi=tuple((a+.001,b+.001,c) for a,b,c in q[::-1])
                face(m,"Dark unoccluded open sleeve underside","red" if j%2==0 else "board",qi)
        ring_a=ring(0,.101)
        for i in range(12):
            T(m,"Windsock mouth brazed ring","red",ring_a[i],ring_a[(i+1)%12],.007,.007,7)
    for x in (.36,3.22,4.62):
        lantern(m,x,1.272,.386,"Concourse pole lantern",True)

def clip(poly,axis,at,sign):
    """Slice an oriented face without changing normals or assigning border duplicates."""
    coords=[]
    for a,b in zip(poly,poly[1:]+poly[:1]):
        fa,fb=(a[axis]-at)*sign,(b[axis]-at)*sign
        if fa>=-EPS:coords.append(a)
        if (fa< -EPS and fb>EPS) or (fa>EPS and fb< -EPS):
            t=fa/(fa-fb)
            coords.append(tuple(at if k==axis else (1-t)*a[k]+t*b[k] for k in range(3)))
    return coords

def tile(m,tx,tz):
    out=mesh()
    lo_x=2*tx-.5
    lo_z=2*tz-.5
    for name,faces in m.parts.items():
        vs=m.vertices[name]
        for ids,color in faces:
            poly=[vs[i] for i in ids]
            for ax,at,sign in ((0,lo_x,1),(0,lo_x+2,-1),(1,lo_z,1),(1,lo_z+2,-1)):
                # Geometry exactly on a seam is owned by the (+) tile.
                if sign<0 and (tx if ax==0 else tz)<(3 if ax==0 else 2) and all(abs(p[ax]-at)<EPS for p in poly):
                    poly=[]
                if not poly:break
                poly=clip(poly,ax,at,sign)
            out.face(name,color,[(x-(lo_x+1),z-(lo_z+1),y) for x,z,y in poly])
    return out

def atlas(dest):
    def chunk(tag,data):
        return struct.pack(">I",len(data))+tag+data+struct.pack(">I",zlib.crc32(tag+data))
    cols=b"".join(bytes.fromhex(c)*8 for c in PAL.values())
    path=dest/"bl_small_airport_atlas.png"
    path.write_bytes(b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",len(PAL)*8,8,8,2,0,0,0))
        +chunk(b"IDAT",zlib.compress((b"\0"+cols)*8,9))+chunk(b"IEND",b""))

def export():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    m=mesh()
    tarmac(m);terminal(m);hangar(m);wind(m,static_only=True)
    mats=RAIL.materials()
    for i,n in enumerate(PAL):
        mats[i].name=n.replace("_"," ").title()
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene
    scene["datum"]="0 = grass top; OpenTTD 14.1 small Country Airfield; projection source pixel / 8 - .5"
    scene["format"]="Exported independently per 2-node tile at origin + (2*x,ground+1,2*z); preview geo continuous."
    for x,z,name in SOURCE:
        section=tile(m,x,z)
        filename=RAIL.MODELS/f"bl_small_airport_{x}_{z}.obj"
        RAIL.export_obj(filename,section)
        obj=filename.read_text()
        filename.write_text(obj.replace(obj.splitlines()[0],
            f"# LuanTTD original Country Airfield art, tile ({x},{z}); regenerate with tools/build_small_airport_art.py",1))
    # Continuous design (not duplicates clipped on tile boundaries) is the
    # original editable source; semantic collections and material colors.
    for part in ("Groundwork","Terminal buildings","Hangar","Field accessories"):
        c=bpy.data.collections.new(part);scene.collection.children.link(c)
        a=mesh()
        {"Groundwork":tarmac,"Terminal buildings":terminal,"Hangar":hangar,"Field accessories":wind}[part](a)
        RAIL.to_blender(a,c,mats)
    atlas(RAIL.TEXTURES)
    for screen in bpy.data.screens:
        for a in screen.areas:
            if a.type=="VIEW_3D":
                a.spaces.active.shading.color_type="MATERIAL"
                a.spaces.active.region_3d.view_location=(3.5,2.55,.3)
                a.spaces.active.region_3d.view_distance=10.5
                a.spaces.active.region_3d.view_rotation=(Vector((3.5,2.6,.12))-Vector((7.65,10.,6.1))).to_track_quat("-Z","Y")
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art/small_country_airport.blend"),compress=True)
    if os.environ.get("SMALL_AIRPORT_RENDER"):review(scene,Path(os.environ["SMALL_AIRPORT_RENDER"]))

def review(scene,path):
    V=Vector
    def std(n,co):
        ma=bpy.data.materials.new(n);ma.diffuse_color=(*co,1);return ma
    grass=(.154,.250,.095)
    bpy.ops.mesh.primitive_plane_add(size=32,location=(3.5,2.4,-.0012))
    bpy.context.object.data.materials.append(std("Surrounding late-summer pasture",grass))
    world=bpy.data.worlds.new("Open country daylight");scene.world=world;world.use_nodes=True
    bg=world.node_tree.nodes.get("Background")
    bg.inputs[0].default_value=(.61,.75,.89,1);bg.inputs[1].default_value=.55
    light=bpy.data.lights.new("Bright afternoon","SUN");light.energy=2.6;light.angle=.125
    ob=bpy.data.objects.new("Bright afternoon",light);scene.collection.objects.link(ob)
    ob.rotation_euler=(.43,-.31,-.59)
    camera=bpy.data.cameras.new("Country strip survey");camera.type="ORTHO";camera.ortho_scale=10.3
    ob=bpy.data.objects.new("Country strip survey",camera);scene.collection.objects.link(ob);scene.camera=ob
    ob.location=(8.52,11.4,8.35);ob.rotation_euler=(V((3.55,2.23,.05))-ob.location).to_track_quat("-Z","Y").to_euler()
    scene.render.engine="CYCLES";scene.cycles.samples=25;scene.cycles.use_denoising=False
    scene.view_settings.view_transform="AgX"
    scene.render.resolution_x=1152;scene.render.resolution_y=800
    scene.render.resolution_percentage=100
    scene.render.filepath=str(path)
    bpy.ops.render.render(write_still=True)
    camera.ortho_scale=5.7
    ob.location=(6.93,5.63,2.69)
    ob.rotation_euler=(V((4.68,.68,.50))-ob.location).to_track_quat("-Z","Y").to_euler()
    scene.render.filepath=str(path.with_name(path.stem+"-apron.png"))
    bpy.ops.render.render(write_still=True)

if __name__=="__main__":export()

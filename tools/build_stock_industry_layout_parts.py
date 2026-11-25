#!/usr/bin/env python3
"""Native, self-contained industrial modules for alternate pinned RC1 layouts.

The stock tile graphics IDs determine each part's location and function.
No sprites, palette entries, or geometry are copied from OpenTTD.
"""
import sys
from pathlib import Path
from math import pi, cos, sin
from random import Random

import bpy
from mathutils import Quaternion, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_stock_metal_industry_art as M

R, A, S = M.R, M.A, M.S
Q, B, T, F = M.Q, M.B, M.T, M.F
ROOT = Path(__file__).resolve().parents[1]
ART = "stock_industry_layout_parts"

def beam(m, name, color, a, b, width=.023):
    T(m, name, color, a, b, width, width, 4)

def cylinder(m, name, color, x, z, y0, y1, bottom, top=None, sides=16):
    T(m, name, color, (x,z,y0), (x,z,y1), bottom, top or bottom, sides)

def pavement(m, idx, color):
    Q(m, "Occupied two-node stock cell only", color, -.5,1.5,-.5,1.5,.010)
    rng=Random(357+idx)
    for _ in range(45):
        x,z=rng.uniform(-.47,1.44),rng.uniform(-.46,1.44)
        Q(m,"Weathered paving chips",rng.choice(("aggregate","shale","ashphalt",color)),
          x,x+rng.uniform(.009,.027),z,z+.018,.029)

def receiving_lane(m, a=.05, b=.91):
    Q(m,"HGV entrance concrete", "ashphalt",a,b,.32,1.5,.040)
    for x in (a,b-.029):
        Q(m,"Visible shoulder paint","yellow_safety",x,x+.029,.36,1.49,.050)
    for k in range(4):
        z=.63+k*.196
        Q(m,"Lane center stripe","workstone",(a+b)/2-.015,(a+b)/2+.015,z,z+.061,.052)

def hoist(m):
    B(m,"Stone footing and shaft curb","foundation",.50,.25,.96,.91,.010,.13,.020)
    B(m,"Deep shaft opening","coke",.50,.25,.56,.57,.13,.151,.010)
    for side in (-1,1):
        x=.50+side*.435
        xt=.50+side*.233
        for end in (-1,1):
            z=.25+end*.383
            zt=.25+end*.210
            beam(m,"Rolled angle headframe column","metal_blue",(x,z,.13),(xt,zt,1.57),.047)
            beam(m,"Doubled long raker","oxidized_steel",(x,z,.23),(xt,.25-end*.22,1.40),.027)
        for j in range(3):
            y=.29+j*.42
            w=.35-j*.051
            beam(m,"Hoist cross brace","darkiron",(x-side*.06,.25-w,y), (xt,.25+w,y+.38),.019)
            beam(m,"Counter-brace","metal_blue",(x-side*.06,.25+w,y), (xt,.25-w,y+.38),.019)
    for z in (.043,.457):
        beam(m,"I-beam over hoist deck","metal_blue",(.215,z,1.56),(.785,z,1.56),.036)
    B(m,"Headframe top maintenance beam","steel_plate",.50,.25,.61,.46,1.54,1.59,.02)
    for x in (.34,.66):
        T(m,"Rope sheave running rim","oxidized_steel",(x-.028,.25,1.77),(x+.028,.25,1.77),.204,.204,18)
        T(m,"Sheave hub","nickel",(x-.039,.25,1.77),(x+.039,.25,1.77),.071,.071,12)
        for k in range(7):
            angle=2*pi*k/7
            beam(m,"Sheave spokes","darkiron",(x+.032,.25,1.77),
                 (x+.032,.25+.186*cos(angle),1.77+.186*sin(angle)),.013)
        T(m,"Steel lowering cable","darkiron",(x,.41,.14),(x,.41,1.88),.006,.006,6)
    M.ladder(m,"Headframe access",.58,.695,.111,1.53)

def hopper(m):
    for x in (.02,.97):
        for z in (.13,.90):
            B(m,"Loading gantry footing","foundation",x,z,.19,.20,.01,.13,.018)
            beam(m,"Loading hopper column","metal_blue",(x,z,.12),(x,z,1.14),.038)
            beam(m,"Braced hopper frame","oxidized_steel",(x,z,.12),(x,.51,1.10),.026)
    for x in (.06,.94):
        F(m,"Sloping abrasion plate","steel_plate",
          ((x,.10,1.22),(x,.94,1.22),(.50,.70,.75),(.50,.33,.75)))
    for z in (.1,.94):
        beam(m,"Rim channel","metal_blue",(.05,z,1.216),(.95,z,1.216),.035)
    B(m,"Coal dosing gate","oxidized_steel",.5,.51,.42,.41,.65,.80,.04)
    receiving_lane(m,.17,.82)

def staff(m):
    M.shed(m,"Windowed shift office",.40,.35,1.08,.83,.66,.92,"roof_zinc")
    B(m,"Lamp base","foundation",1.19,.98,.11,.11,.01,.071,.009)
    beam(m,"Entrance lamp","darkiron",(1.19,.98,.06),(1.19,.98,.88),.019)
    B(m,"Lamp visor","nickel",1.19,.91,.12,.21,.85,.92,.014)

def spoil(m):
    M.strata(m,"Crushed black coal spoil",.54,.58,.79,.70,.43,("coke","coke_sun","shale"),274,5)
    for x in (0,.33,.68,1.00):
        B(m,"Stockpile retaining timber","oxidized_steel",x,.02,.08,.092,.011,.24,.009)
    B(m,"Loading bulkhead","darkiron",.51,.018,1.12,.06,.049,.155,.006)

def weigh(m):
    M.shed(m,"Weighmaster's cabin",-.07,.32,.52,.72,.53,.73,"metal_blue")
    receiving_lane(m,.26,1.26)
    B(m,"Cast truck weigh plate","darkiron",.76,.73,.76,.77,.019,.057,.018)
    for i in range(9):
        z=.42+i*.073
        Q(m,"Anti-slip weigh rib","steel_plate",.43,1.1,z,z+.012,.063)
    beam(m,"Barrier arm at entry","yellow_safety",(1.20,1.09,.35),(.32,1.09,.35),.019)
    cylinder(m,"Barrier pivot column","oxidized_steel",1.20,1.09,.012,.51,.039)

def belts(m):
    M.conveyor(m,"Open washery feed belt",(.04,1.23,.23),(.97,.06,.84),.44)
    B(m,"Belt drive housing","metal_blue",.99,.06,.43,.30,.45,.83,.037)
    cylinder(m,"Belt drive fan guard","steel_plate",.99,.06,.83,.89,.105)
    M.strata(m,"Screened aggregate toe",.87,1.06,.44,.34,.24,("coke","coke_sun","shale"),405,4)

def generation(m):
    M.shed(m,"Brick generator hall",.53,.49,1.68,1.49,1.0,1.32,"roof_zinc")
    for x in (.21,.83):
        B(m,"Vent roof well","millbrick_dark",x,.55,.21,.45,1.09,1.30,.017)
    B(m,"Service landing","foundation",.53,1.31,1.15,.23,.019,.10,.025)

def powerhouse_chimney(m):
    M.shed(m,"Boiler intake house",.63,.66,1.28,1.24,.81,1.06,"roof_zinc")
    x,z=.06,.10
    cylinder(m,"Concrete chimney footing","foundation",x,z,.014,.12,.30,.26)
    cylinder(m,"Conical boiler stack","millbrick",x,z,.12,2.58,.206,.118)
    for y in (.28,.77,1.18,1.59,1.99,2.41):
        r=.206-(y-.12)*(.088/2.46)
        cylinder(m,"Stack collar", "millbrick_dark",x,z,y,y+.038,r+.016,r+.012)
    cylinder(m,"Open exhaust shroud","darkiron",x,z,2.579,2.629,.144,.142)
    cylinder(m,"Dark flue throat","coke",x,z,2.629,2.640,.094)
    receiving_lane(m,.89,1.47)

def transformers(m):
    for x in (.08,.85):
        for z in (.15,.86):
            B(m,"HV pad foundation","foundation",x,z,.47,.47,.01,.081,.01)
            B(m,"Transformer tank","metal_blue",x,z,.35,.33,.08,.37,.015)
            for i in range(6):
                k=z-.13+i*.052
                B(m,"Thin bank radiator","darkiron",x+.187,k,.072,.024,.119,.343,.002)
            for s in (-1,1):
                cylinder(m,"Ceramic standoff","nickel",x+s*.104,z,.37,.53,.041,.029,10)
                for y in (.42,.46,.50):
                    cylinder(m,"Porcelain annulus","steel_plate",x+s*.104,z,y,y+.015,.052)
    for x in (-.40,1.41):
        for z in (-.32,.38,1.13):
            beam(m,"High-voltage garden fence","steel_plate",(x,z,.014),(x,z,.64),.014)
        for y in (.37,.53):
            beam(m,"Safety barrier rails","darkiron",(x,-.32,y),(x,1.14,y),.011)

def coal_pockets(m):
    hopper(m)
    for x in (-.22,1.21):
        B(m,"Concrete receiving bunker curb","foundation",x,.59,.19,1.34,.01,.24,.026)

def saw_finish(m):
    M.shed(m,"Dry timber finishing mill",.51,.44,1.61,1.41,.73,1.02,"metal_blue")
    B(m,"Covered outgoing sorting porch","steel_plate",.56,1.23,1.45,.38,.52,.57,.018)
    for x in (.036,1.12):
        B(m,"Sorting porch columns","metal_blue",x,1.34,.10,.099,.013,.544,.010)
    for z in (1.15,1.24,1.33):
        B(m,"Wrapped length of milled boards","dryyard",.43,z,.72,.066,.06,.13,.006)
    cylinder(m,"Dust extraction motor duct","nickel",1.015,.18,.75,1.19,.074)
    cylinder(m,"Weatherproof round extraction cowl","darkiron",1.015,.18,1.19,1.23,.13)

def saw_shop(m):
    M.shed(m,"Timber joining and cutting shed",.51,.53,1.56,1.51,.87,1.17,"oxidized_steel",open_south=True)
    B(m,"Saw bench under shelter","metal_blue",.53,.63,.68,.69,.031,.235,.017)
    for x in (.32,.70):
        for z in (.38,.55,.72,.89):
            T(m,"Steel outfeed bed roller","nickel",(x-.09,z,.25),(x+.09,z,.25),.027,.027,8)

def saw_office(m):
    staff(m)
    receiving_lane(m,.66,1.21)

def log_yard(m):
    for lane in range(3):
        for tier in range(3):
            count=3-tier
            for i in range(count):
                x=-.26+lane*.56+i*.114+tier*.057
                color=("rustyard","oxidized_steel","dryyard")[(lane+i+tier)%3]
                z=.04+lane*.18+i*.035
                h=.105+tier*.096
                T(m,"Cut logs with colored bark",(color),(x,z,h),(x,z+.73,h),.052,.048,11)
                T(m,"Visible golden growth rings","workstone",(x,z+.727,h),(x,z+.735,h),.039,.040,11)

def lumber_yard(m):
    for row in range(3):
        x=-.05+row*.57
        for layer in range(6):
            y=.05+layer*.048
            for i in range(3):
                z=.18+i*.29
                B(m,"Separate kiln-dried lumber packs","dryyard" if (row+layer)%2 else "workstone",
                  x,z,.46,.267,y,y+.031,.004)
        for z in (.14,.49,.82):
            B(m,"Vertical lumber straps","darkiron",x,z,.474,.024,.11,.347,.003)

PARTS={
    0:("Mine hoist with shaft, sheaves and walkway","ashphalt",hoist),
    2:("Mine gantry and coal hopper","ashphalt",hopper),
    3:("Mine windowed staff office","dryyard",staff),
    4:("Mine coal stockpile with retaining boards","ashphalt",spoil),
    5:("Coal mine weigh station and gated truck frontage","aggregate",weigh),
    6:("Coal mine open washery feed","ashphalt",belts),
    7:("Power station brick generator hall","aggregate",generation),
    8:("Power station boiler intake and chimney","ashphalt",powerhouse_chimney),
    9:("Power station fenced transformers","aggregate",transformers),
    10:("Power station coal pocket","ashphalt",coal_pockets),
    11:("Sawmill workshop and outfeed rollers","dryyard",saw_shop),
    12:("Sawmill receiving office","aggregate",saw_office),
    13:("Sawmill finishing mill and covered sorting porch","dryyard",saw_finish),
    14:("Sawmill freshly cut log stacks","dryyard",log_yard),
    15:("Sawmill strapped lumber stacks","aggregate",lumber_yard),
}

def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene
    scene.name="LuanTTD / working parts for stock industrial alternate layouts"
    scene["Reference"]="OpenTTD 16.0-RC1 build_industry.h, industry_land.h; original 3D geometry"
    mats=R.materials()
    for idx,(label,ground,fn) in sorted(PARTS.items()):
        c=bpy.data.collections.new(f"GFX {idx:02d} · {label}")
        scene.collection.children.link(c)
        mesh=A.mesh()
        pavement(mesh,idx,ground)
        fn(mesh)
        geo=M.triangulated(mesh)
        R.to_blender(geo,c,mats)
        part_order=list(sorted(PARTS)).index(idx)
        for o in c.objects:
            o.location.x+=(part_order%5)*2.4
            o.location.y+=(part_order//5)*2.4
        path=R.MODELS/f"bl_industry_layout_gfx_{idx}.obj"
        if idx==0:
            rigid,rotor=A.mesh(),A.mesh()
            spinning={"Rope sheave running rim","Sheave hub","Sheave spokes"}
            for name,faces in geo.parts.items():
                for ids,color in faces:
                    vertices=[geo.vertices[name][i] for i in ids]
                    if name in spinning:
                        rotor.face(name,color,[(10*(x-.50)-.5,10*(z-.25)-.5,10*(y-1.77)) for x,z,y in vertices])
                    else:
                        rigid.face(name,color,vertices)
            R.export_obj(R.MODELS/"bl_industry_layout_hoist_wheels.obj",rotor,0,generator=Path(__file__).name)
            geo=rigid
        R.export_obj(path,M.triangulated(S.clip(geo,0,0,{(0,0):idx})),generator=Path(__file__).name)
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":
                view=area.spaces.active
                view.shading.color_type="MATERIAL"
                view.region_3d.view_location=Vector((4.9,2.7,.25))
                view.region_3d.view_distance=17.8
                view.region_3d.view_rotation=Quaternion((.913,.321,.094,.234)).normalized()
    S.atlas(ART,M.PAL)
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art"/f"{ART}.blend"),compress=True)

if __name__=="__main__":
    build()

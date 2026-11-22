#!/usr/bin/env python3
"""Build the original two-loading-bay, one-entrance town bus terminus.

blender -b -t 4 --python-exit-code 1 --python tools/build_road_bus_bay_pair.py
PASSENGER_BAY_RENDER=/tmp/terminal.png blender -b -t 4 --python-exit-code 1 --python tools/build_road_bus_bay_pair.py

Uses the exact road stop movement presentation of OpenTTD 14.1 stock
non-drive-through stops (two bays, shared entry). No graphic is imported.
Runtime: native 2x2 tile NW even anchor at effective flat road base+1.
Variant 0 enters from -X (road bit 8); variants 1/2/3 enter from +Z/+X/-Z.
"""
from pathlib import Path
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_road_post_stop as P
import build_road_freight_stop as F

ROOT=P.ROOT
PAL={
    "Pale mastic":"a79f87","Old concrete flags":"9b9783","Drive slab":"8a8881",
    "Dark underlay":"726b61","Worn concrete cap":"c6b596","Paved edge stone":"a99b7d",
    "Blue arc route enamel":"327677","Bus bay teal":"396765","Aged green":"53746a",
    "Teal edge tone":"759081","Station roof":"3d5357","Raised roof seam":"627879",
    "Rust dark":"65544d","Dark solder":"35414a","Wall red brick":"a2614c",
    "Light brick":"ad7860","Brick shadow":"834f43","Mortar pale":"b79174",
    "Ocher porcelain":"d9b16f","Lined cream":"f0e2b5","Paint cream":"e8d7a5",
    "Dark amber":"9e7e4e","Street lamp glass":"f3d799","Bench top":"a0754d",
    "Bench ends":"765845","Glass dark":"426a69","Glass brilliant":"839e98",
    "White glazed tile":"e5d4b3","Mast steel":"68796f","Grass backdrop":"57814c",
    "Road inset tar":"4f5255","Road inset gravel":"9a937e",
}
P.COLORS=PAL
BAY1,BAY2=.3125,-.1875 # exact projected centers in variant 0
BAY_Z=.155
PAINT_CLEAR=.006
T=F.tube
FONT=dict(F.FONT,**{
    "1":("00100","01100","00100","00100","00100","00100","01110"),
    "2":("01110","10001","00001","00010","00100","01000","11111"),
    "B":("11110","10001","10001","11110","10001","10001","11110"),
    "D":("11110","10001","10001","10001","10001","10001","11110"),
    "I":("11111","00100","00100","00100","00100","00100","11111"),
    "M":("10001","11011","10101","10101","10001","10001","10001"),
    "N":("10001","11001","10101","10011","10001","10001","10001"),
    "P":("11110","10001","10001","11110","10000","10000","10000"),
    "R":("11110","10001","10001","11110","10010","10001","10001"),
    "S":("01111","10000","10000","01110","00001","00001","11110"),
    "T":("11111","00100","00100","00100","00100","00100","00100"),
    "U":("10001","10001","10001","10001","10001","10001","01110"),
    "Y":("10001","10001","01010","00100","00100","00100","00100"),
    " ":("00000",)*7,
})
FLOOR=-.5

def lettering(m,n,text,x,z,y,scale,c="Lined cream",ground=False):
    for i,k in enumerate(text):
        shift=(i*6-(len(text)*6-1)/2)*scale
        for j,row in enumerate(FONT[k]):
            top=y+(3.5-j)*scale
            u=0
            while u<5:
                if row[u]=="0":
                    u+=1;continue
                v=u+1
                while v<5 and row[v]=="1":v+=1
                a,b=x+shift+scale*u,x+shift+scale*v
                if ground:m.face(n,c,[(a,z+top-scale,FLOOR+PAINT_CLEAR),(b,z+top-scale,FLOOR+PAINT_CLEAR),
                                      (b,z+top,FLOOR+PAINT_CLEAR),(a,z+top,FLOOR+PAINT_CLEAR)])
                else:m.face(n,c,[(a,z,top-scale),(b,z,top-scale),(b,z,top),(a,z,top)])
                u=v

def ground(m,park_z=BAY_Z):
    box=F.safe_box(m)
    # Rounded, hard-standing single entry. The envelope matches the actual
    # two bay trajectories, not an invented separate bypass or extra footprint.
    rim=[(-.999,-.402),(-.768,-.750),(-.449,-.871),(.108,-.883),
         (.556,-.753),(.726,-.438),(.748,.314),(.606,.579),
         (.431,.698),(-.491,.681),(-.760,.555),(-.999,.402)]
    m.ring("Continuous flush two-bay concrete hardstand","Drive slab",
           [(x,z,-.513) for x,z in rim],[(x,z,-.497) for x,z in rim])
    # True filled panel paving at entrance, under boarding lines and feet.
    for x,z0,z1 in ((-.75,-.643,.472),(-.47,-.792,.565),(-.19,-.818,.624),
                    (.11,-.826,.625),(.39,-.784,.623),(.59,-.585,.506)):
        box("Indented old pavement expansion joints","Old concrete flags",x-.002,x+.002,z0,z1,
            -.497,-.4949)
    for i in range(12):
        x=-.742+i*.119
        z=.610+(i%2)*.015
        if x<-.60:z=.523
        if x>.51:z=.562
        box("Flush dock-edge traction hatches","Paint cream",x-.026,x+.027,z-.007,z+.010,-.495,-.493,.003)
    front=park_z+.376
    for i,x in enumerate((BAY1,BAY2),start=1):
        for sign in (-1,1):
            xx=x+sign*.215
            box("Two clear painted bay perimeter edges","Paint cream",xx-.009,xx+.009,-.271,front,
                -.497,-.491,.002)
            box("Boarding bay double short painted head bars","Paint cream",min(xx,x),max(xx,x),front-.008,front+.007,
                -.497,-.4908,.003)
        lettering(m,f"Marked stopping bay {i} at exact projected parking throat",str(i),
                  x,park_z-.515,0,.016,"Paint cream",ground=True)
    # Small recessed drainage slot and ramp from hardstand to shelter.
    for x in (-.579,.701):
        box("Setback grouted drain trough","Dark solder",x-.065,x+.065,.635,.669,-.494,-.487,.005)
        for p in range(5):
            xx=x-.050+p*.025
            box("Drain visible cast iron grate","Mast steel",xx-.004,xx+.004,.638,.666,-.487,-.4835,.001)

def building(m):
    box=F.safe_box(m)
    box("Dressed continuous passenger boarding island foundation","Paved edge stone",
        -.891,.856,.659,.982,-.510,-.453,.022)
    def ramp(z):return -.495+max(0,(z-.604))/(.691-.604)*.045
    box("Tapered access apron up to boarding island","Pale mastic",-.523,.553,.604,.692,
        lambda z:ramp(z)-.010,ramp,.006)
    for i in range(13):
        x=-.861+.13*i
        box("Cut individual granite curb slabs","Worn concrete cap",x,x+.121,.659,.707,-.482,-.439,.006)
        for z in (.711,.830):
            box("Square weathered walking flags","Pale mastic" if i%4 else "Old concrete flags",
                x,x+.125,z,z+.112,-.455,-.445,.008)
    # Brick dwarf wind wall with original teal glazed frames above.
    box("Shelter raised brick wind sill base","Mortar pale",-.762,.752,.874,.964,-.451,-.280,.012)
    for row in range(3):
        y=-.448+.054*row
        for col in range(13):
            x=max(-.754,-.807+.059*(row%2)+col*.120)
            a=min(.742,-.807+.059*(row%2)+col*.120+.111)
            if a-x>.008:
                colr=("Wall red brick","Light brick","Wall red brick","Brick shadow")[(col+row*3)%4]
                box("Warm patterned masonry bus shelter bricks",colr,x,a,.864,.875,y,y+.046,.002)
    box("Dressed masonry windbreak capping","Worn concrete cap",-.779,.763,.857,.978,-.286,-.263,.008)
    # Real translucent-looking panes, mounted behind independent frames
    # and stiles on each of two waiting zones; no attached backdrop billboard.
    for x in (-.494,.478):
        box("Green powder-coated shelter glazing frames","Dark solder",x-.221,x+.221,.902,.947,-.254,.081,.004)
        box("Tinted glazing in waiting shelter partition","Glass dark",x-.191,x+.191,.892,.907,-.228,.052,.004)
        for a in (-.140,.000,.140):
            box("Settled vertical partition glass strip","Glass brilliant",x+a-.019,x+a+.021,.888,.896,
                -.211,.035,.003)
        for a in (-.120,0,.120):
            box("Slim glazing wall steel mullions","Teal edge tone",x+a-.006,x+a+.006,.884,.905,
                -.227,.052,.002)
        box("Lower and upper seam glazing partition rails","Mast steel",x-.197,x+.197,.882,.907,
            -.152,-.136,.004)
    for x in (-.736,.064,.727):
        box("Sandstone post plinth","Paved edge stone",x-.050,x+.050,.685,.774,-.445,-.380,.010)
        box("Painted canopy structure uprights","Bus bay teal",x-.027,x+.027,.712,.760,-.383,.123,.007)
        box("Foundry metal front post knee brackets","Aged green",x-.044,x+.044,.734,.848,.025,.123,.011)
        box("Soldered painted post drip fastening","Teal edge tone",x-.038,x+.038,.698,.769,.100,.137,.006)
    # Elevated shallow sawtooth canopy, front stays clear of the longest bus.
    def roof(z):return .202-.57*abs(z-.814)
    for lo,hi in ((.643,.813),(.815,.995)):
        box("Pitched two-part standing seam shelter roof","Station roof",-.807,.799,lo,hi,
              lambda z:roof(z)-.035,roof)
        for j in range(14):
            x=-.779+.119*j
            box("Visible standing seam tin roof strip","Raised roof seam",x-.004,x+.004,lo+.002,hi-.002,
                 lambda z:roof(z)-.001,lambda z:roof(z)+.007)
    box("Folded metal roof ridge caps","Raised roof seam",-.823,.811,.801,.828,.191,.213,.005)
    box("Front cream bus station canopy fascia","Worn concrete cap",-.783,.775,.639,.679,.088,.130,.006)
    T(m,"Water gutter downspout","Mast steel",(.750,.663,.105),(.750,.701,-.422),.010,.008,8)
    box("Mid-century green porcelain bus terminal sign","Blue arc route enamel",-.321,.338,.617,.657,.114,.209,.013)
    box("Raised station cream keyline this face","Worn concrete cap",-.313,.330,.615,.621,.123,.200,.011)
    box("Thin shadow lip to enamel plate","Bus bay teal",-.303,.319,.6125,.618,.127,.194,.009)
    lettering(m,"Terminal raised BUS STATION route identity","BUS STATION",.008,.611,.160,.0082)
    for n,x in ((1,BAY1),(2,BAY2)):
        # Each plate lines up with its own exact paint centerline, not with
        # generic paired signs mirrored for the wrong bay.
        box(f"Individual bus bay {n} cast square indicator","Blue arc route enamel",
            x-.094,x+.094,.646,.679,.021,.086,.012)
        box(f"Bay {n} plate ivory border","Worn concrete cap",
            x-.085,x+.085,.644,.648,.025,.082,.010)
        box(f"Bay {n} plate dark teal field","Bus bay teal",x-.077,x+.077,.642,.645,.028,.079,.008)
        lettering(m,f"Raised numbered BAY {n} sign",f"BAY {n}",x,.6405,.054,.0042)
        for zz in (.742,.851):
            if zz>.8:
                box("Hardwood bench seats","Bench top",x-.137,x+.137,zz-.013,zz+.036,-.299,-.276,.006)
                box("Bench back raised cedar planks","Bench ends",x-.136,x+.136,zz+.035,zz+.052,-.260,-.209,.005)
            for dx in (-.102,.102):
                box("Cast wrought bench feet","Rust dark",x+dx-.013,x+dx+.013,zz-.009,zz+.015,-.432,-.300,.003)
        T(m,"Turquoise turned lamp casing bracket","Bus bay teal",(x,.708,.084),(x,.708,.049),.021,.019,8)
        T(m,"Separate warm glass canopy lights","Street lamp glass",(x,.708,.049),(x,.708,.034),.014,.016,9)
    # Small notice board with texture-independent ruled timetable and cards.
    box("Timetable warm porcelain wall casing","Worn concrete cap",.634,.727,.790,.836,-.217,-.029,.008)
    box("Inset route timetable card","Lined cream",.640,.722,.786,.795,-.208,-.038,.005)
    for i in range(8):
        y=-.197+i*.018
        box("Timetable printed block rules","Dark amber",.649,.715,.784,.789,y,y+.003)
    box("Timetable card upper section bar","Blue arc route enamel",.646,.717,.783,.790,-.076,-.053,.003)
    box("Bus station public waste bin outer shell","Bus bay teal",-.857,-.780,.875,.948,-.448,-.291,.008)
    box("Public bin open hood","Mast steel",-.859,-.778,.872,.953,-.303,-.280,.009)
    box("Dark waste hatch","Dark solder",-.847,-.789,.867,.877,-.332,-.306,.005)

def publish():
    m=P.Mesh();ground(m);building(m)
    mirrored=P.Mesh();ground(mirrored,.0775);building(mirrored)
    for k in range(4):
        obj=P.payload((m if k<2 else mirrored).transformed((-k)%4),str(k))
        p=ROOT/"mods/bayline/models"/f"bl_road_bus_bay_pair_{k}.obj"
        p.write_text(obj.replace(obj.splitlines()[0],
          "# Original simultaneous passenger bay art, stock one-entrance tile. tools/build_road_bus_bay_pair.py",1))
    (ROOT/"mods/bayline/textures/bl_road_bus_bay_pair.png").write_bytes(P.atlas())
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    sc=bpy.context.scene
    sc.name="Stock two-bay passenger terminus"
    sc["Existing road"]="One stock road-stop tile; bit8 canonical entrance from west."
    sc["Native bay centers"]="Centered 2-node tile: (+.3125,+.155) and (-.1875,+.155) in right-hand/left-hand source park; both face +Z. Exported orientation 2/3 uses its actual ported cross-axis park depth +.0775."
    sc["Overlay datum"]="At even native NW x,z and road grade+1; ground Y=-.50 in native mesh, stock road below."
    mats=P.make_materials()
    P.author(m,"Real original two-bay passenger station pieces",mats,sc)
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":
                s=area.spaces.active
                s.shading.color_type="MATERIAL"
                s.region_3d.view_location=(0,.13,-.21)
                s.region_3d.view_distance=3.40
                s.region_3d.view_rotation=(Vector((0,.1,-.19))-Vector((.9,-2.3,1.65))).to_track_quat("-Z","Y")
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art/road_bus_bay_pair.blend"),compress=True)
    if p:=os.environ.get("PASSENGER_BAY_RENDER"):render(sc,mats,p)

def render(sc,mats,path):
    m=P.Mesh()
    m.box("Unused as export: grass reference","Grass backdrop",-4,4,-4,4,-.62,-.5004)
    m.box("Unused as export: grass shoulder","Road inset gravel",-4,-.82,-.375,.375,-.52,-.500)
    m.box("Unused as export: asphalt road","Road inset tar",-4,-.82,-.3125,.3125,-.520,-.4988)
    P.author(m,"Street view context: native texture stand-in",mats,sc)
    cm=bpy.data.cameras.new("Approaching perspective")
    ob=bpy.data.objects.new("Approaching perspective",cm)
    sc.collection.objects.link(ob);sc.camera=ob
    ob.location=(1.47,-2.71,1.54)
    ob.rotation_euler=(Vector((.02,.28,-.18))-ob.location).to_track_quat("-Z","Y").to_euler()
    cm.type="ORTHO";cm.ortho_scale=2.92
    sc.render.engine="BLENDER_WORKBENCH"
    sc.render.resolution_x=1230;sc.render.resolution_y=820
    sc.render.resolution_percentage=100
    sc.display.shading.light="STUDIO"
    sc.display.shading.color_type="MATERIAL"
    sc.display.shading.show_shadows=True
    sc.display.shading.show_cavity=True
    sc.display.shading.cavity_type="BOTH"
    sc.display.shading.background_type="WORLD"
    sc.world=bpy.data.worlds.new("Afternoon sky")
    sc.world.color=(.135,.195,.235)
    sc.view_settings.view_transform="Standard"
    sc.render.filepath=path
    bpy.ops.render.render(write_still=True)

if __name__=="__main__":publish()

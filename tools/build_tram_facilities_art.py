#!/usr/bin/env python3
"""Build the original tram depot and paired street-side tram stops.

Run from the game root: blender -b -t 4 --python-exit-code 1 --python tools/build_tram_facilities_art.py
Set TRAM_FACILITIES_RENDER=/tmp/tram-facilities.png for a Blender art sheet.
"""
from math import cos, sin, pi
from pathlib import Path
import os
import struct
import sys
import zlib

import bpy
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_rail_art as rail

PALETTE = {
    "Groove asphalt":"343739", "Embedded rail":"babbb1", "Contact copper":"705740",
    "Granite shoulder":"7f8178", "Dressed concrete":"a2a496","Paver":"afae9e",
    "Stipple footpath":"93988c","Tactile stone":"c7b892", "Edge paint":"e5d7a8",
    "Mortar":"765c52", "Clay brick":"a1664e", "Light brick":"b9785a",
    "Deep brick":"925840", "Lintel stone":"bbad93", "Slate shade":"495653",
    "Slate gray":"576761", "Slate edge":"6e7c73", "Steel enamel":"355345",
    "Green enamel":"497461", "Green trim":"728d6d", "Cream enamel":"e5d9ac",
    "Timber seat":"966b4b", "Timber dark":"6d543e", "Blue glazing":"6e8e95",
    "Glass reflection":"abc0b6", "Glazing dark":"53696b", "Steel bright":"a6a99a",
    "Steel dark":"3e4b44", "Lamp diffuser":"eed594", "Sign blue":"435a59",
    "Sign raised":"f8e7b8", "Ceramic":"ddd8b9", "Grease black":"393f3c",
    "Depot paving":"89918a", "Threshold edge":"b0ad97", "Warning amber":"cf9c54",
}
P={k:i for i,k in enumerate(PALETTE)}
rail.COLORS[:]=PALETTE.values()
LANE=.155
GAUGE=.106
RAIL_TOP=.012
WIRE=.500
ISLAND_INNER=.350
ISLAND_EDGE=.074
PORTAL_HALF=.421
PORTAL_CLEAR=.625


def square(x,z,w,l,ch=0):
    a,b=x-w/2,x+w/2
    c,d=z-l/2,z+l/2
    q=min(w/3,l/3,ch)
    return [(a,c),(b,c),(b,d),(a,d)] if q==0 else [
        (a+q,c),(b-q,c),(b,c+q),(b,d-q),(b-q,d),(a+q,d),(a,d-q),(a,c+q)]


def level(y):
    return y if callable(y) else lambda x,z:y


def extrusion(m,name,color,profile,low,high,top=None,open_z=False,no_end_caps=()):
    if rail.signed_area(profile)<0:
        profile=profile[::-1]
    low,high=level(low),level(high)
    a,b=([(x,z,f(x,z)) for x,z in profile] for f in (low,high))
    m.face(name,P[color],a[::-1]);m.face(name,P[top or color],b)
    for i in range(len(a)):
        j=(i+1)%len(a)
        if a[i][1]==a[j][1] and ((open_z and abs(a[i][1])==1) or a[i][1] in no_end_caps):
            continue
        m.face(name,P[color],(a[i],a[j],b[j],b[i]))


def slab(m,n,c,x,z,w,l,low,high,qs=0,top=None,open_z=False):
    extrusion(m,n,c,square(x,z,w,l,qs),low,high,top,open_z)


def cylinder(m,n,c,x,z,low,high,rad,top=None,count=14):
    # Taper on the vertical axis. Physical isolator ribs retain volume.
    top=rad if top is None else top
    a,b=([(x+r*cos(2*pi*i/count),z+r*sin(2*pi*i/count),h) for i in range(count)]
         for r,h in ((rad,low),(top,high)))
    m.face(n,P[c],a[::-1]);m.face(n,P[c],b)
    for i in range(count):
        j=(i+1)%count
        m.face(n,P[c],(a[i],a[j],b[j],b[i]))


def zrail(m,start,end,*,wires=True):
    mid=(start+end)/2
    for lane in (-LANE,LANE):
        if wires:
            slab(m,"Live overhead contact wire","Contact copper",lane,mid,.012,end-start,WIRE,WIRE+.013,open_z=True)
        for dx in (-GAUGE/2,GAUGE/2):
            x=lane+dx
            slab(m,"Paved rail grooves","Groove asphalt",x,mid,.032,end-start,.001,.006,open_z=True)
            slab(m,"Road flush tram rail","Embedded rail",x,mid,.013,end-start,.006,RAIL_TOP,open_z=True)


def numbered_face(m,name,z,center,h):
    slab(m,name,"Steel dark",center,z,.336,.040,h,h+.123,.012)
    front=z+.023
    slab(m,name,"Cream enamel",center,front,.305,.013,h+.016,h+.106,.010)
    for i in range(6):
        x=center-.099+i*.042
        # A permanent locally invented street rail cartouche.
        slab(m,name,"Steel enamel",x,front+.006,.012,.006,h+.033,h+.090)
        slab(m,name,"Steel enamel",x+.009,front+.006,.020,.006,h+.034+(i%3)*.020,h+.041+(i%3)*.020)
    for x in (center-.138,center+.138):
        slab(m,name,"Warning amber",x,front+.006,.012,.007,h+.041,h+.081,.002)


def island(m,side):
    # Raised platform .074 node above pavement, aligned to the original
    # streetcar's .0688-node first step, with ramped ends.
    def y(x,z):
        return ISLAND_EDGE - .038*max(0,min(1,(abs(z)-.814)/(.924-.814)))

    def island_strip(name,color,x,w,length,low,high,ch,top=None):
        # Three facets, not a non-planar end-to-end quadrilateral: the
        # center stays flat while each threshold drops .038 node. Internal
        # join faces are omitted to avoid coplanar geometry.
        left,right=x-w/2,x+w/2
        edge=length/2
        extrusion(m,name,color,[(left,-.814),(right,-.814),(right,.814),(left,.814)],
                  low,high,top,no_end_caps=(-.814,.814))
        ch=min(edge-.814,ch,w*.28)
        for sign in (-1,1):
            shell=[(left,sign*.814),(right,sign*.814),(right,sign*(edge-ch)),
                   (right-ch,sign*edge),(left+ch,sign*edge),(left,sign*(edge-ch))]
            if ch==0: shell=[(left,sign*.814),(right,sign*.814),(right,sign*edge),(left,sign*edge)]
            extrusion(m,name,color,shell,low,high,top,no_end_caps=(sign*.814,))

    x=side*(ISLAND_INNER+.261)
    island_strip("Taper-ended boarding islands","Granite shoulder",x,.522,1.848,0,y,.052,"Dressed concrete")
    island_strip("Side-platform walking surface","Stipple footpath",side*.617,.437,1.830,
                 lambda x,z:y(x,z)-.004,lambda x,z:y(x,z)+.001,.034,"Paver")
    island_strip("Chamfered platform coping","Tactile stone",side*.383,.067,1.74,
                 lambda x,z:y(x,z)-.011,lambda x,z:y(x,z)+.004,.019)
    island_strip("Raised stopping edge paint","Edge paint",side*.406,.015,1.694,
                 lambda x,z:y(x,z)+.002,lambda x,z:y(x,z)+.006,.003)
    for z in (-.76,-.57,-.38,-.19,0,.19,.38,.57,.76):
        slab(m,"Platform slab joints","Stipple footpath",side*.644,z,.356,.009,
             lambda x,z:y(x,z)+.0007,lambda x,z:y(x,z)+.003)
    # Physical shelter and bench are all farther back than .48 node.
    zcenter=-.102 if side==1 else .138
    for z in (zcenter-.247,zcenter+.247):
        for x in (.537,.791):
            slab(m,"Fluted shelter legs","Steel enamel",side*x,z,.039,.037,.074,.509,.007)
            slab(m,"Cast shelter shoe","Steel dark",side*x,z,.069,.065,.074,.112,.008)
    for q in (-.177,.174):
        z=zcenter+q
        slab(m,"Backrest and seat mounts","Steel dark",side*.757,z,.114,.043,.078,.213,.008)
    for x in (.689,.734,.779):
        slab(m,"Sealed timber bench slats","Timber seat",side*x,zcenter,.038,.413,.198,.230,.005)
    slab(m,"Timber backrest","Timber dark",side*.793,zcenter,.025,.403,.267,.328,.009)
    for j in range(4):
        z=zcenter+(j-1.5)*.142
        slab(m,"Framed daylight glazing","Steel enamel",side*.810,z,.030,.137,.312,.487)
        slab(m,"Inset shelter glazing","Blue glazing",side*.790,z,.015,.113,.333,.461,.006)
        slab(m,"Inset shelter glazing","Blue glazing",side*.826,z,.012,.111,.333,.461,.008)
        slab(m,"Angled daylight reflection","Glass reflection",side*.832,z-.034,.005,.018,.351,.447,.004)
    # High-contrast suspended route sign at the rail-facing edge. Roof
    # spans along the waiting platform but does not intrude over the lane.
    roof=lambda x,z:.543+.047*(1-abs(abs(x)-.670)/.198)
    for lo,hi in ((.479,.670),(.670,.861)):
        slab(m,"Pitched canopy roof","Slate gray",side*(lo+hi)/2,zcenter,hi-lo,.603,
             lambda x,z:roof(x,z)-.028,roof,.0)
        for z in (zcenter-.214,zcenter-.108,zcenter,zcenter+.108,zcenter+.214):
            slab(m,"Canopy standing ribs","Slate edge",side*(lo+hi)/2,z,hi-lo,.012,
                 lambda x,z:roof(x,z)-.001,lambda x,z:roof(x,z)+.012,.003)
    slab(m,"Coastal cream canopy fascia","Cream enamel",side*.483,zcenter,.032,.614,.490,.545,.007)
    slab(m,"Street-facing route notice enamel","Sign blue",side*.465,zcenter,.020,.260,.451,.501,.006)
    for i in range(5):
        slab(m,"Street-facing letter marks","Sign raised",side*.453,zcenter+(i-2)*.039,
             .007,.017,.463,.487,.003)
    for z in (zcenter-.191,zcenter+.190):
        slab(m,"Shelter underside lamps","Lamp diffuser",side*.611,z,.068,.084,.476,.496,.008)
    post_z=.745 if side<0 else -.753
    cylinder(m,"Tram-stop flag pole","Steel enamel",side*.726,post_z,.069,.575,.017,.014,10)
    slab(m,"Porcelain tram flag","Cream enamel",side*.726,post_z,.047,.134,.478,.571,.013)
    slab(m,"Porcelain tram flag raised mark","Sign blue",side*.700,post_z,.010,.082,.499,.556,.007)
    slab(m,"Porcelain tram flag raised mark","Sign raised",side*.694,post_z,.005,.052,.519,.543,.006)


def stop():
    m=rail.Mesh(rail.terrain_height(0))
    zrail(m,-1,1)
    for side in (-1,1):
        island(m,side)
    # Pole is beyond the shelter and never in the loading area. The hot
    # wires under both drops stay at the same height and lane centers as
    # the ordinary track kit. Cabinet remains outboard of waiting space.
    x,z=.866,.640
    slab(m,"Outboard catenary footing","Granite shoulder",x,z,.149,.175,0,.083,.018)
    cylinder(m,"Cast insulated pole shoe","Steel dark",x,z,.065,.158,.055,.036)
    cylinder(m,"Tapered street catenary pole","Steel enamel",x,z,.142,.684,.024,.015,12)
    slab(m,"Catenary maintenance enclosure","Steel dark",x-.009,z+.072,.089,.077,.088,.274,.012)
    slab(m,"Tapered canopy chromed top","Steel bright",x,z,.053,.054,.648,.682,.008)
    beam=lambda x,z:.596+.033*x
    slab(m,"Two-track catenary span","Steel enamel",.309,z,1.103,.026,
         lambda x,z:beam(x,z)-.012,lambda x,z:beam(x,z)+.015,.003)
    slab(m,"Upper catenary tension support","Steel dark",.309,z,1.103,.011,
         lambda x,z:beam(x,z)+.005,lambda x,z:beam(x,z)+.049,.002)
    for lane in (-LANE,LANE):
        cylinder(m,"Ceramic catenary isolators","Ceramic",lane,z,.544,.574,.021,.018,12)
        for h in (.547,.557,.568):
            cylinder(m,"Ceramic catenary isolators","Cream enamel",lane,z,h,h+.006,.024,.023,12)
        cylinder(m,"Contact wire drop and clamp","Contact copper",lane,z,WIRE+.007,.547,.006,None,8)
    return m


def depot():
    m=rail.Mesh(rail.terrain_height(0))
    zrail(m,-.866,1)
    slab(m,"Depot flush inspection floor","Depot paving",0,.065,1.302,1.87,0,.0007,0,open_z=True)
    slate_h=lambda x,z:.706+.061*(.80-abs(x))
    for side in (-1,1):
        slab(m,"Dressed depot sill","Lintel stone",side*.600,-.174,.199,1.515,0,.093,.012)
        slab(m,"Load-bearing workshop side wall","Clay brick",side*.651,-.169,.139,1.547,.087,.729,.020)
        slab(m,"Stepped masonry piers","Deep brick",side*.576,.570,.301,.151,.075,.718,.017)
        slab(m,"Portal pier cast stone quoin","Lintel stone",side*(PORTAL_HALF+.017),.632,.032,.099,.081,.642,.007)
        for j in range(10):
            h=.112+j*.057
            slab(m,"Mortar bed joint detail","Mortar",side*.720,-.172,.009,1.474,h,h+.008)
            slab(m,"Front brick mortar beds","Mortar",side*.581,.651,.280,.009,h,h+.008)
            for k in range(6):
                if (j*17+k*13)%9>3: continue
                z=-.791+k*.224+.061*(j%2)
                slab(m,"Shifted brick highlights","Light brick",side*.725,z,.006,.103,h+.013,h+.047)
        for z in (-.642,-.244,.183):
            slab(m,"Workshop window stone sill","Lintel stone",side*.724,z,.057,.212,.292,.325,.005)
            slab(m,"Workshop window frame","Steel enamel",side*.727,z,.053,.191,.316,.536,.008)
            for dz in (-.041,.041):
                slab(m,"Industrial side glazing","Blue glazing",side*.756,z+dz,.013,.073,.341,.512,.007)
                slab(m,"Industrial side glazing reflection","Glass reflection",side*.764,z+dz-.018,
                     .006,.011,.359,.487,.002)
            slab(m,"Workshop window cross rail","Steel enamel",side*.765,z,.020,.162,.413,.431)
            slab(m,"Workshop window masonry lintel","Lintel stone",side*.731,z,.046,.219,.526,.553,.005)
        slab(m,"Transverse roof eaves trim","Slate shade",side*.729,-.144,.082,1.704,.699,.740,.012)
        for x in ((-.585,-.490) if side==-1 else (.490,.585)):
            slab(m,"Short portal safety bollards","Warning amber",x,.779,.048,.053,.002,.190,.007)
            slab(m,"Short portal safety bollards","Steel dark",x,.779,.049,.054,.116,.139,.005)
        for z in (-.630,-.340,-.050,.227):
            slab(m,"Side sill workshop workbench","Timber dark",side*.551,z,.125,.170,.085,.200,.009)
    # True single portal front is open across both lanes. The raised door
    # and beaded lintel stay above the current pantograph.
    slab(m,"Rear masonry wall","Clay brick",0,-.910,1.454,.132,0,lambda x,z:slate_h(x,z)-.003,.015)
    slab(m,"Rear brick header","Deep brick",0,-.903,1.464,.144,.686,lambda x,z:slate_h(x,z)-.001,.012)
    slab(m,"Front spanning cast lintel","Lintel stone",0,.593,1.442,.158,PORTAL_CLEAR,.705,.005)
    slab(m,"Retracted slatted electric door","Green enamel",0,.547,.859,.050,.643,.718,.008)
    for h in (.656,.678,.698):
        slab(m,"Retracted slatted electric door","Green trim",0,.576,.850,.012,h,h+.008)
    for side in (-1,1):
        slab(m,"Door tracks vertical edge","Steel enamel",side*.435,.560,.019,.034,.084,.665,.006)
    numbered_face(m,"Porcelain depot franchise plate",.730,0,.696)
    for x in (-.568,.568):
        slab(m,"Entrance lanterns","Steel dark",x,.690,.079,.079,.434,.568,.012)
        slab(m,"Entrance lanterns","Lamp diffuser",x,.717,.060,.046,.458,.538,.010)
        slab(m,"Entrance lanterns","Steel enamel",x,.731,.081,.085,.530,.566,.009)
    # Dual old-style trolley track buffer and roof bond above active wire.
    for lane in (-LANE,LANE):
        slab(m,"Depot backstop feet","Steel dark",lane,-.879,.097,.050,.013,.084,.008)
    for z in (-.590,-.205,.185,.548):
        slab(m,"Interior contact-wire roof beam","Steel enamel",0,z,1.144,.049,.555,.607,.004)
        for lane in (-LANE,LANE):
            cylinder(m,"Depot high-voltage ceramics","Ceramic",lane,z,.521,.580,.024,.023)
            cylinder(m,"Depot contact wire drop","Contact copper",lane,z,WIRE+.008,.523,.007,.007,8)
    # Ventilated industrial monitor roof with asymmetric glass clerestory.
    for a,b in ((-.786,0),(0,.786)):
        slab(m,"Sloped standing seam roof","Slate gray",(a+b)/2,-.133,b-a,1.716,
             slate_h,lambda x,z:slate_h(x,z)+.044)
        for z in (-.917,-.698,-.479,-.260,-.041,.178,.397,.616):
            slab(m,"Raised standing seams","Slate edge",(a+b)/2,z,b-a,.016,
                 lambda x,z:slate_h(x,z)+.042,lambda x,z:slate_h(x,z)+.052)
    slab(m,"Ventilated roof monitor foundation","Steel enamel",0,-.234,.534,1.029,.780,.806,.012)
    slab(m,"Northlight monitor carcass","Green enamel",0,-.234,.421,1.014,.793,.971,.020)
    for z in (-.607,-.422,-.236,-.05,.135):
        for x in (-.210,.210):
            slab(m,"Raised monitor glazing","Glazing dark",x,z,.020,.166,.829,.942,.008)
            slab(m,"Raised monitor glazing","Glass reflection",1.05*x,z-.041,.006,.024,.849,.923,.003)
    crown=lambda x,z:.975+.10*(.28-abs(x))
    for a,b in ((-.285,0),(0,.285)):
        slab(m,"Monitor cap and flashing","Slate shade",(a+b)/2,-.234,b-a,1.103,
             lambda x,z:crown(x,z)-.022,crown)
    slab(m,"Monitor ridge flashing","Slate edge",0,-.235,.055,1.115,.982,1.007,.008)
    return m


def rotate(m,idx):
    out=rail.Mesh(rail.terrain_height(0))
    for group,faces in m.parts.items():
        for f,c in faces:
            out.face(group,c,[((x,z,h),(-z,x,h),(-x,-z,h),(z,-x,h))[idx]
                      for x,z,h in (m.vertices[group][i] for i in f)])
    return out


def atlas():
    def chunk(tag,data):
        return struct.pack(">I",len(data))+tag+data+struct.pack(">I",zlib.crc32(tag+data))
    colors=b"".join(bytes.fromhex(c)*8 for c in PALETTE.values())
    out=b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",8*len(PALETTE),8,8,2,0,0,0))
    out+=chunk(b"IDAT",zlib.compress((b"\0"+colors)*8))+chunk(b"IEND",b"")
    (rail.TEXTURES/"bl_tram_facilities_atlas.png").write_bytes(out)


def render(scene,filename):
    bpy.ops.mesh.primitive_plane_add(size=100,location=(0,0,-.007))
    current=bpy.context.object
    stone=bpy.data.materials.new("Bayside hardstanding")
    stone.diffuse_color=(.14,.19,.17,1)
    current.data.materials.append(stone)
    sky=bpy.data.worlds.new("Overcast skies")
    sky.color=(.34,.45,.52)
    scene.world=sky
    bpy.ops.object.light_add(type="AREA",location=(-2,3.9,6))
    light=bpy.context.object
    light.data.energy=1000
    light.data.size=5.5
    light.rotation_euler=(Vector((.5,1.3,.1))-light.location).to_track_quat("-Z","Y").to_euler()
    bpy.ops.object.camera_add(location=(5.9,6.5,5.1))
    camera=bpy.context.object
    camera.rotation_euler=(Vector((.2,.9,.31))-camera.location).to_track_quat("-Z","Y").to_euler()
    camera.data.type="ORTHO"
    camera.data.ortho_scale=6.9
    scene.camera=camera
    scene.render.engine="BLENDER_EEVEE_NEXT"
    scene.eevee.taa_render_samples=24
    scene.render.resolution_x=1440;scene.render.resolution_y=1020
    scene.render.resolution_percentage=100;scene.render.filepath=filename
    bpy.ops.render.render(write_still=True)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene
    scene.name="LuanTTD / historic street tram facilities"
    scene.view_settings.view_transform="Standard"
    mats=rail.materials()
    for key,i in P.items():
        mat=mats[i];mat.name=key
        node=mat.node_tree.nodes.get("Principled BSDF")
        node.inputs["Roughness"].default_value=.28 if "glazing" in key.lower() else .76
        node.inputs["Metallic"].default_value=.47 if key in ("Contact copper","Embedded rail","Steel bright") else .02
    s,d=stop(),depot()
    for index,turn in enumerate((3,0)):
        m=rotate(s,turn)
        name=f"tram_stop_{index}"
        coll=rail.stash(m,mats,name)
        if index==1: rail.instance(scene,coll,-1.87,-.70)
        rail.export_obj(rail.MODELS/f"bl_{name}.obj",m)
    for direction,turn in enumerate((1,0,3,2)):
        m=rotate(d,turn)
        name=f"tram_depot_{direction}"
        coll=rail.stash(m,mats,name)
        if direction==1: rail.instance(scene,coll,.67,.85)
        rail.export_obj(rail.MODELS/f"bl_{name}.obj",m)
    atlas()
    bpy.ops.wm.save_as_mainfile(filepath=str(rail.ROOT/"art/tram_facilities.blend"),compress=True)
    if os.getenv("TRAM_FACILITIES_RENDER"): render(scene,os.environ["TRAM_FACILITIES_RENDER"])


if __name__=="__main__":
    main()

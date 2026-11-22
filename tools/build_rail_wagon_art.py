#!/usr/bin/env python3
"""Author the original stock-length rail coach and open freight wagon.

    blender -b -t 4 --python-exit-code 1 --python tools/build_rail_wagon_art.py

Objects are built in physical Luanti node units: +X lateral, world -Z
forward, elevation above rail contact. OBJ exported for visual_size=1.
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
    "Dark frame":"273c45", "Frame panel":"3b4b50", "Flange steel":"555f62",
    "Tread steel":"777c7a", "Wheel web":"485156", "Wheel hub":"a3ab9f",
    "Coupler iron":"434545", "Coupler stroke":"767772", "Buffer beam":"763e35",
    "Dark teal":"1d5255", "Coach teal":"326e6b", "Teal bevel":"4b7e76",
    "Cream surround":"e1cda4", "Cream lining":"f1dfb3", "Cream shade":"bba984",
    "Coach roof":"555f64", "Roof edges":"747b7b", "Roof ridge":"646e70",
    "Dark glazing":"2e4246", "Glazing tint":"425d62", "Glazing glint":"608082",
    "Rubber bellows":"3c4547", "Door timber":"786153", "Handle brass":"c6aa6c",
    "Wood shadow":"56463b", "Oak dark":"715b48", "Oak":"80644c",
    "Oak light":"98765a", "Exposed end grain":"9b7c64", "Interior floor":"665547",
    "Freight chassis":"403a35", "Freight shadow":"533b35", "Bauxite":"874a39",
    "Bauxite highlight":"a6634c", "Paint brass":"e0bc78",
}
P={name:i for i,name in enumerate(PALETTE)}
rail.COLORS[:]=PALETTE.values()

GAUGE=.424
COUPLER_HALF=.500
COUPLER_BODY=.499
COUPLER_ELEVATION=.157


def level(value):
    return value if callable(value) else lambda x,z:value


def rect(x,z,w,l,b=0):
    a,c=x-w/2,x+w/2
    d,e=z-l/2,z+l/2
    b=min(w/3,l/3,b)
    return [(a,d),(c,d),(c,e),(a,e)] if not b else [
        (a+b,d),(c-b,d),(c,d+b),(c,e-b),(c-b,e),(a+b,e),(a,e-b),(a,d+b)]


def slab(mesh,n,c,x,z,w,l,lo,hi,chamfer=0,top=None):
    profile=rect(x,z,w,l,chamfer)
    low,high=level(lo),level(hi)
    a,b=([(gx,gz,h(gx,gz)) for gx,gz in profile] for h in (low,high))
    mesh.face(n,P[c],a[::-1]);mesh.face(n,P[top or c],b)
    for i in range(len(a)):
        j=(i+1)%len(a)
        mesh.face(n,P[c],(a[i],a[j],b[j],b[i]))


def faces_xz(mesh,n,c,vertices,lo,hi,top=None):
    if rail.signed_area(vertices)<0: vertices=vertices[::-1]
    a,b=([(x,z,y) for x,z in vertices] for y in (lo,hi))
    mesh.face(n,P[c],a[::-1]);mesh.face(n,P[top or c],b)
    for k in range(len(a)):
        q=(k+1)%len(a)
        mesh.face(n,P[c],(a[k],a[q],b[q],b[k]))


def circular(mesh,name,col,center,radius,axis,start,end,segments=20,cap=True):
    """Detail cylinder in local wheel/longitudinal/vertical unit axes."""
    # Basis pairs have positive normal along the cylinder axis.
    mapping={"x":lambda s,u,v:(s,u,v),"z":lambda s,u,v:(v,s,u),"h":lambda s,u,v:(u,v,s)}
    mp=mapping[axis]
    cx,cz,ch=center
    rings=[]
    for off in (start,end):
        ring=[]
        for i in range(segments):
            a=2*pi*i/segments
            x,z,h=mp(off,radius*cos(a),radius*sin(a))
            ring.append((x+cx,z+cz,h+ch))
        rings.append(ring)
    a,b=rings
    if cap:
        mesh.face(name,P[col],a[::-1]);mesh.face(name,P[col],b)
    for k in range(segments):
        j=(k+1)%segments
        mesh.face(name,P[col],(a[k],a[j],b[j],b[k]))


def couplers(mesh):
    for side in (-1,1):
        # Canvas diagrams can use the exact +/-0.500 knuckle plane. Contact
        # faces stop .001 short to avoid two opposing coincident metal faces.
        slab(mesh,"Coupler draft pockets","Dark frame",0,side*.427,.130,.052,.115,.192,.012)
        slab(mesh,"Coupler drawbars","Coupler iron",0,side*.456,.071,.038,.132,.182,.009)
        slab(mesh,"Coupler knuckles","Coupler stroke",0,side*.481,.091,
             2*(COUPLER_BODY-.481),COUPLER_ELEVATION-.0265,COUPLER_ELEVATION+.0265,.010)
        for x in (-.154,.154):
            center=(x,side*.442,.174)
            circular(mesh,"End buffers and pads","Coupler iron",center,.025,"z",-.018,.018,16)
            circular(mesh,"End buffers and pads","Wheel web",
                     (x,side*.462,.174),.035,"z",-.008,.008,14)
        slab(mesh,"Brake hose","Wheel web",.070,side*.459,.019,.019,.082,.153,.004)
        slab(mesh,"Brake hose","Coupler iron",.079,side*.467,.038,.013,.079,.099,.004)
        slab(mesh,"Buffer beam brass notices","Handle brass",-.093,side*.443,.038,.008,.178,.201,.004)


def chassis(mesh,passenger):
    # Chamfer each end so adjacent bodies leave clearance on tight model track.
    p=rect(0,0,.425,.858,.037)
    faces_xz(mesh,"Covered steel underframe","Dark frame" if passenger else "Freight chassis",p,.127,.204,"Frame panel")
    for side in (-1,1):
        slab(mesh,"End headstocks","Buffer beam" if passenger else "Bauxite",
             0,side*.4255,.399,.030,.133,.225,.008)
        slab(mesh,"Coupler straps","Flange steel",side*.116,0,.014,.594,.121,.147,.004)
    couplers(mesh)


def wheels(mesh,axes,passenger):
    # The two rolling tread centers are exactly +/-0.212. The flanges sit
    # inward beside the rail head; only treads touch h=0.
    r=.100
    for z in axes:
        circular(mesh,"Wheelsets and axles","Wheel web",(0,z,r),.023,"x",-.203,.203,12)
        for side in (-1,1):
            x=side*GAUGE/2
            suffix="L" if side<0 else "R"
            circular(mesh,f"Rolling tread {suffix}","Tread steel",(x,z,r),r,"x",-.026,.026,20)
            lo,hi=sorted((side*-.044,side*-.036))
            circular(mesh,"Inner flange lip","Flange steel",(x,z,r),.110,"x",lo,hi,20)
            circular(mesh,"Wheel face web","Wheel web",(x+side*.025,z,r),.080,"x",-.006,.006,18)
            circular(mesh,"Wheel face hubs","Wheel hub",(x+side*.033,z,r),.031,"x",-.006,.006,16)
            for j in range(5):
                a=2*pi*j/5
                circular(mesh,"Wheel hub rivets","Flange steel",
                         (x+side*.039,z+.017*cos(a),r+.017*sin(a)),
                         .0046,"x",-.004,.004,8)
            slab(mesh,"Oil axle boxes","Dark frame" if passenger else "Freight shadow",
                 side*.196,z,.049,.095,.132,.203,.010,"Wheel web")
            for j in range(3):
                slab(mesh,"Leaf spring shims","Flange steel",
                     side*.192,z,.037,.112+.010*j,.170+.007*j,.175+.007*j,.006)


def side_box(mesh,n,c,side,z,h,w,hi,x=.234,d=.009,b=.004):
    slab(mesh,n,c,side*x,z,d,w,h,hi,b)


def passenger():
    m=rail.Mesh(rail.terrain_height(0))
    chassis(m,True)
    wheels(m,(-.355,-.239,.239,.355),True)
    for z in (-.297,.297):
        slab(m,"Passenger bolster beams","Dark frame",0,z,.391,.179,.142,.195,.012)
        for side in (-1,1):
            side_box(m,"Bogie raised plate","Frame panel",side,z,.139,.185,.188,.203,.014)
    slab(m,"Battery and dynamo boxes","Dark frame",-.095,.028,.139,.252,.081,.162,.013,"Frame panel")
    slab(m,"Battery and dynamo boxes","Frame panel",.106,-.052,.120,.199,.105,.171,.010)
    for z in (-.101,-.067,-.033,.001,.035,.069,.103):
        side_box(m,"Battery box louvers","Flange steel",-1,z,.112,.012,.141,.165,.005)
    # Genuine body frame beneath individual passenger windows.
    p=rect(0,0,.474,.849,.044)
    faces_xz(m,"Tapered passenger body","Coach teal",p,.199,.369,"Teal bevel")
    for side in (-1,1):
        side_box(m,"Body waist cover","Dark teal",side,0,.244,.766,.285,.233,.015)
        side_box(m,"Longitudinal coach lining","Cream lining",side,0,.344,.792,.360,.238,.009)
        side_box(m,"Window sill and below-window plating","Cream surround",side,0,.361,.785,.411,.233,.015)
        side_box(m,"Window head and fascia","Cream surround",side,0,.524,.804,.597,.234,.016)
        side_box(m,"Continuous rain gutter","Roof edges",side,0,.564,.846,.580,.245,.010)
        for z in (-.240,-.120,0,.120,.240):
            side_box(m,"Raised window casement","Cream shade",side,z,.397,.104,.544,.238,.013)
            side_box(m,"Inset glazing","Dark glazing",side,z,.410,.084,.533,.244,.009)
            side_box(m,"Upper ventilation hopper","Glazing tint",side,z,.507,.077,.529,.249,.004,.002)
            side_box(m,"Glazing reflection ribbon","Glazing glint",side,z-.020,.419,.009,.496,
                     .251,.003,.001)
            side_box(m,"Window sash","Cream shade",side,z,.499,.080,.505,.250,.004,.002)
            side_box(m,"Quarter sash divider","Cream shade",side,z+.037,.412,.004,.530,.252,.003,.001)
        for z in (-.294,-.185,-.060,.060,.185,.294):
            side_box(m,"Window and vestibule pillars","Cream surround",side,z,.408,.022,.545,.234,.021)
        for z in (-.358,.358):
            side_box(m,"Vestibule doors","Dark teal",side,z,.226,.102,.574,.229,.020,.010)
            side_box(m,"Vestibule glazing","Dark glazing",side,z,.436,.071,.547,.244,.008,.007)
            side_box(m,"Vestibule bronze catches","Handle brass",side,z-.020,.383,.033,.397,.248,.007)
            side_box(m,"Vestibule risers","Coupler iron",side,z,.190,.124,.215,.234,.054)
            side_box(m,"Vestibule risers","Flange steel",side,z,.162,.092,.182,.220,.056)
        for z in (-.17,.17):
            side_box(m,"Car identification plate","Cream shade",side,z,.268,.090,.296,.240,.009)
        for z in (-.192,-.170,-.148,.148,.170,.192):
            side_box(m,"Painted identification marks","Dark teal",side,z,.274,.007,.289,.246,.005,.001)

    for s in (-1,1):
        # Visible articulated diaphragm at either end, not a drawn-on door.
        slab(m,"Passenger car end walls","Teal bevel",0,s*.403,.410,.049,.344,.542,.016)
        slab(m,"Passenger car end walls","Cream surround",0,s*.404,.410,.045,.528,.610,.020)
        slab(m,"Flexible inter-car gangway","Rubber bellows",0,s*.430,.204,.039,.275,.585,.016)
        slab(m,"Gangway external edge","Frame panel",0,s*.455,.164,.023,.288,.565,.015)
        slab(m,"Recessed saloon end door","Door timber",0,s*.469,.128,.007,.312,.548,.008)
        slab(m,"Saloon door viewing window","Glazing tint",0,s*.474,.074,.004,.423,.527,.006)
        slab(m,"Saloon door handle","Handle brass",.036,s*.475,.018,.006,.371,.397,.003)
        for x in (-.166,.166):
            slab(m,"End safety grab handles","Handle brass",x,s*.430,.013,.020,.319,.481,.004)
    # Low elliptical barrel roof. The strip colors are authored material
    # zones, not a solid cuboid or flat billboard.
    r_width=.257
    n=12
    rings=[]
    for z,fac in ((-.433,.95),(-.383,1.),(.383,1.),(.433,.95)):
        ring=[]
        for i in range(n+1):
            a=pi*i/n
            ring.append((r_width*cos(a)*fac,z,.572+.120*sin(a)*(.97 if fac<1 else 1)))
        rings.append(ring)
    for a,b in zip(rings,rings[1:]):
        for k in range(n):
            col="Roof edges" if k in (0,n-1) else "Roof ridge" if k in (4,5,6,7) else "Coach roof"
            m.face("Elliptical saloon roof",P[col],(a[k+1],a[k],b[k],b[k+1]))
    m.face("Rounded saloon end fascia",P["Coach roof"],rings[0])
    m.face("Rounded saloon end fascia",P["Coach roof"],rings[-1][::-1])
    for z in (-.285,-.107,.093,.270):
        for side in (-1,1):
            slab(m,"Roof vents","Roof edges",side*.061,z,.046,.063,.682,.704,.010,"Coach roof")
            slab(m,"Vent dark exhaust slots","Dark frame",side*.061,z,.025,.037,.703,.706,.007)
    return m


def freight():
    m=rail.Mesh(rail.terrain_height(0))
    chassis(m,False)
    wheels(m,(-.288,.288),False)
    slab(m,"Boxed freight floor","Freight chassis",0,0,.466,.843,.188,.238,.024)
    for i in range(12):
        z=-.381+.069*i
        slab(m,"Individual open-bed floor planks",("Oak dark","Interior floor","Wood shadow")[i%3],
             0,z,.396,.066,.234,.245,.005)
        for x in (-.167,.167):
            slab(m,"Open-bed floor bolt heads","Flange steel",x,z,.010,.011,.244,.249,.003)
    # Four timber courses and pressed corner framing. The floor is recessed
    # below the loaded-bed lip; there is genuinely nothing covering it.
    for side in (-1,1):
        for j in range(4):
            lo=.237+j*.054
            side_box(m,"Raised wagon side planks",("Oak","Oak light","Oak dark","Oak")[j],
                side,0,lo,.813,lo+.050,.216,.031,.005)
            side_box(m,"Pressed steel deck toe guard","Bauxite" if j==0 else "Wood shadow",
                side,0,lo+.007,.793,lo+.012,.228,.009,.003)
        for z in (-.388,-.239,-.078,.078,.239,.388):
            side_box(m,"Pressed external side stakes","Freight shadow",side,z,.212,.037,.475,.235,.022)
            side_box(m,"Raised steel stake web","Bauxite",side,z,.248,.021,.465,.248,.008)
        side_box(m,"Top lip and rope strip","Bauxite highlight",side,0,.448,.854,.479,.223,.044)
        side_box(m,"Lower steel sill","Freight shadow",side,0,.190,.856,.237,.225,.041)
        side_box(m,"Sill angle highlights","Bauxite",side,0,.220,.833,.231,.246,.007)
        for z in (-.325,-.168,.168,.325):
            x=side*.249
            slab(m,"Tie-down lugs","Coupler iron",x,z,.018,.032,.438,.473,.005)
            circular(m,"Stake pin heads","Flange steel",(x,z,.454),.011,"x",-.007,.007,10)
        for z in (-.078,.078):
            side_box(m,"Hopper side gate hinge","Coupler iron",side,z,.215,.052,.248,.250,.022)
            side_box(m,"Door locking flange","Coupler stroke",side,z,.243,.037,.273,.251,.015)
        side_box(m,"Wagon owner and load plate","Freight shadow",side,0,.332,.086,.362,.234,.012)
        for z in (-.025,0,.025):
            side_box(m,"Industrial load stencil","Paint brass",side,z,.341,.010,.352,.243,.008,.002)
        for j,h in enumerate((.275,.319,.367,.421)):
            for z in (-.350,-.215,.192,.343):
                side_box(m,"Timber weathering checks","Exposed end grain",side,
                         z+(j-1.5)*.010,h,.046,h+.004,.233,.004,.001)
    for end in (-1,1):
        for j in range(4):
            lo=.238+.054*j
            slab(m,"Open wagon end planks",("Oak dark","Oak","Oak light","Oak dark")[j],
                 0,end*.407,.405,.028,lo,lo+.051,.005)
        slab(m,"End top lip","Bauxite highlight",0,end*.420,.446,.037,.447,.477,.007)
        for x in (-.179,.179):
            slab(m,"Freight corner stays","Bauxite",x,end*.423,.047,.027,.224,.471,.006)
            for h in (.265,.334,.403,.447):
                circular(m,"Eight end rail bolt heads","Coupler stroke",(x,end*.443,h),
                         .007,"z",-.004,.004,8)
        slab(m,"End door latch","Freight shadow",0,end*.426,.067,.025,.315,.389,.009)
        slab(m,"Recessed end grab handle","Flange steel",0,end*.445,.120,.019,.291,.305,.006)
    return m


def atlas():
    def chunk(tag,payload):
        return struct.pack(">I",len(payload))+tag+payload+struct.pack(">I",zlib.crc32(tag+payload))
    colors=b"".join(bytes.fromhex(v)*8 for v in PALETTE.values())
    content=b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",len(PALETTE)*8,8,8,2,0,0,0))
    content+=chunk(b"IDAT",zlib.compress((b"\0"+colors)*8))+chunk(b"IEND",b"")
    (rail.TEXTURES/"bl_rail_wagon_atlas.png").write_bytes(content)


def local_obj(mesh):
    # Shared writer expects a two-node terrain overlay. Convert editable
    # node-scale artwork into 10 internal OBJ units per Luanti entity node.
    out=rail.Mesh(rail.terrain_height(0))
    for group,faces in mesh.parts.items():
        for f,c in faces:
            out.face(group,c,[(10*x-.5,10*z-.5,10*h+.5) for x,z,h in (mesh.vertices[group][i] for i in f)])
    return out


def render(scene,path):
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.004))
    base=bpy.data.materials.new("Studio ballast slate")
    base.diffuse_color=(.13,.18,.17,1)
    bpy.context.object.data.materials.append(base)
    world=bpy.data.worlds.new("Overcast sky")
    world.color=(.44,.45,.53);scene.world=world
    bpy.ops.object.light_add(type="AREA",location=(-2.2,-3.5,5.5))
    light=bpy.context.object
    light.data.energy=720
    light.data.size=5
    light.rotation_euler=(Vector((0,0,.4))-light.location).to_track_quat("-Z","Y").to_euler()
    bpy.ops.object.camera_add(location=(4.2,-5.2,3.95))
    camera=bpy.context.object
    camera.rotation_euler=(Vector((0,-.06,.30))-camera.location).to_track_quat("-Z","Y").to_euler()
    camera.data.type="ORTHO";camera.data.ortho_scale=3.05;scene.camera=camera
    scene.render.engine="BLENDER_EEVEE_NEXT"
    scene.eevee.taa_render_samples=24
    scene.render.resolution_x=1440;scene.render.resolution_y=1020
    scene.render.resolution_percentage=100;scene.render.filepath=path
    bpy.ops.render.render(write_still=True)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene
    scene.name="LuanTTD / standard 8-unit passenger and freight wagons"
    scene.view_settings.view_transform="Standard"
    mats=rail.materials()
    for i,n in enumerate(PALETTE):
        mat=mats[i];mat.name=n
        node=mat.node_tree.nodes.get("Principled BSDF")
        metal=.55 if "steel" in n.lower() or "coupler" in n.lower() or "brass" in n.lower() else .04
        node.inputs["Metallic"].default_value=metal
        node.inputs["Roughness"].default_value=.31 if "Glazing" in n else .76
    for i,(key,build) in enumerate((("rail_passenger_wagon",passenger),("rail_open_wagon",freight))):
        mesh=build()
        coll=rail.stash(mesh,mats,key)
        rail.instance(scene,coll,(-.62,.62)[i],0)
        rail.export_obj(rail.MODELS/f"bl_{key}.obj",local_obj(mesh))
    atlas()
    bpy.ops.wm.save_as_mainfile(filepath=str(rail.ROOT/"art/rail_wagons.blend"),compress=True)
    if os.getenv("RAIL_WAGON_RENDER"): render(scene,os.environ["RAIL_WAGON_RENDER"])


if __name__=="__main__":
    main()

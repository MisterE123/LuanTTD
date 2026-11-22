"""Build LuanTTD's original Bellhaven Harbor Ferry, era 1926–40.

Blender 4.3+: blender -b -t 2 --python-exit-code 1 --python tools/build_harbor_ferry_art.py
Set BAYLINE_FERRY_REVIEW=/tmp/ferry.png for wet and dry views on one sheet.

Runtime entity: unit visual scale, 10 OBJ units per native node, nose local -Z.
Place its origin at the actual water plane, not on a pavement/stop offset.
"""
from math import cos, pi, sin
import os
from pathlib import Path
import struct
import sys
import zlib

import bpy
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_extra_road_vehicle_art as V

PALETTE={
    "chassis":"364443", "rubber":"313b3b", "tread":"3b4144", "silver":"dbd2b1",
    "steel":"6c8384", "nozzle":"40494b", "bright lamp":"ffdda0", "tail":"b74c36",
    "dark glass":"2a4a56", "light glass":"648e9c", "offwhite":"efe4cb", "enamel":"f4e6b9",
    "wine shade":"543a36", "indicator":"dc8751", "door rubber":"3a4640",
    "deep green":"244b48", "sea green":"366c61", "green light":"527e71", "red oxide":"9b483e",
    "red keel":"783e35", "boot white":"e7d6a7", "deck planks":"af8b60", "deck shade":"8c715a",
    "deck light":"c09b6e", "rust":"b77050", "copper":"b78c58", "carved green":"2d5148",
    "mast gold":"cdab72", "canvas":"ddd5bd", "bench wood":"b46e48", "night sea":"326b7c",
    "sea ripple":"467f8b",
}
ROOT=V.ROOT
V.PALETTE=PALETTE
V.KEYS=list(PALETTE)
B=V.bevel_box
C=V.round_between
M=V.add_mesh
KEEL=-.187
# (longitudinal y, beam half-width, fore/aft sheer). Widths are genuinely
# curved by station, with narrow deep forefoot and broad commuter midbody.
HULL=(
    (-.897,.028,.128),(-.854,.151,.133),(-.790,.240,.137),(-.676,.317,.147),
    (-.512,.348,.151),(-.325,.364,.151),(-.094,.369,.151),(.164,.365,.151),
    (.356,.338,.157),(.524,.285,.169),(.668,.210,.179),(.776,.133,.182),
    (.856,.069,.186),(.898,.013,.184),
)


def rod(name,a,b,r,mat,facets=8):
    return C(name,a,b,r,r,mat,facets)


def hull_contour(w, y, upper):
    # Y=0 in the game is sea level, which corresponds to Blender Z=0.
    # A full red anti-fouling shell lies submerged below a narrow cream boot.
    depth=KEEL+min(.137,abs(y+.04)*.078)
    return [(-w,upper),(-w*.997,.058),(-w*.926,.008),(-w*.915,-.008),
            (-w*.81,-.068),(-w*.58,depth*.80),(-w*.19,depth),
            (w*.19,depth),(w*.58,depth*.80),(w*.81,-.068),
            (w*.915,-.008),(w*.926,.008),(w*.997,.058),(w,upper)]

def hull():
    V.profile_hull("Fair-plated tapered upper and lower shell",
        [(y,hull_contour(w,y,r)) for y,w,r in HULL],"sea green",
        ["sea green","sea green","boot white","red oxide","red oxide","red keel",
         "red keel","red keel","red oxide","red oxide","boot white","sea green",
         "sea green","deck shade"])
    # A thin external rubbing strake follows the real sheer along both sides.
    for side in (-1,1):
        for (y0,w0,z0),(y1,w1,z1) in zip(HULL,HULL[1:]):
            rod("Hull deck edge rubbing strake",(side*w0,y0,z0-.010),
                (side*w1,y1,z1-.010),.012,"deep green")
    for j in range(15):
        y=-.740+j*.099
        w=width_at(y)
        z=sheer_at(y)
        B("Laser-cut main deck plank",(0,y,z+.001),(max(.065,w*1.83),.089,.007),
          ("deck planks","deck light","deck planks","deck shade")[j%4],.003)
    # Two stern propellers, shaft and a tapering central spade rudder.
    for side in (-1,1):
        x=side*.105
        rod("Shaft supporting skeg",(x,-.578,-.123),(x,-.780,-.092),.013,"red keel")
        C("Propeller hub",(x,-.793,-.097),(x,-.751,-.097),.020,.020,"copper",10)
        for i in range(3):
            angle=2*pi*i/3+.17
            u,v=cos(angle),sin(angle)
            ex,ez=x+.043*u,-.097+.043*v
            a=(x,-.771,-.097)
            b=(ex-v*.014,-.779,ez+u*.013)
            c=(x+.060*u,-.759,-.097+.060*v)
            d=(ex+v*.009,-.751,ez-u*.010)
            verts=[a,b,c,d,(a[0],a[1]+.005,a[2]),(b[0],b[1]+.005,b[2]),
                   (c[0],c[1]+.005,c[2]),(d[0],d[1]+.005,d[2])]
            M("Twisted bronze screw blade",verts,
              ((0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)),"copper")
    V.profile_hull("Under-water tapered steel rudder",[
        (-.853,[(-.012,-.130),(.012,-.130),(.012,-.026),(-.012,-.026)]),
        (-.786,[(-.013,-.161),(.013,-.161),(.013,-.014),(-.013,-.014)]),
    ],"red oxide")

def interp(y, column):
    for p,q in zip(HULL,HULL[1:]):
        if p[0]<=y<=q[0]:
            t=(y-p[0])/(q[0]-p[0])
            return (1-t)*p[column]+t*q[column]
    raise ValueError("deck location is outboard of the hull ends")

def width_at(y):
    return interp(y,1)
def sheer_at(y):
    return interp(y,2)


def side_windows(x,ys,z,w,h,label):
    s=-1 if x<0 else 1
    for y in ys:
        B(label+" cream architrave",(x,y,z),(.013,w+.023,h+.012),"boot white",.006)
        B(label+" deep glazed rebate",(x+s*.009,y,z),(.010,w,h),"dark glass",.008)
        B(label+" sky highlight",(x+s*.016,y-.006,z+.019),(.005,w*.87,h*.22),"light glass",.002)


def stanchion_run(coords, up=.087, *, bar=.0066, color="enamel"):
    for i,(x,y,z) in enumerate(coords):
        C("Deck balustrade foot",(x,y,z-.002),(x,y,z+.012),.010,.009,"deep green",7)
        rod("Passenger deck stanchion",(x,y,z),(x,y,z+up),.0058,color)
        if i:
            a,b,c=coords[i-1]
            for h in (up,up*.48):
                rod("Solid handrail span",(a,b,c+h),(x,y,z+h),
                    bar if h==up else bar*.74,color)


def raft_ring(x,y,z,normal_axis="x"):
    # Alternating red canvas and white reflective strips around a hollow ring.
    for j in range(16):
        s=j*2*pi/16
        t=(j+1)*2*pi/16
        ring=.043
        a=(x,y+ring*cos(s),z+ring*sin(s))
        b=(x,y+ring*cos(t),z+ring*sin(t))
        if normal_axis=="y":
            a=(x+ring*cos(s),y,z+ring*sin(s));b=(x+ring*cos(t),y,z+ring*sin(t))
        rod("Canvas-wrapped life ring",a,b,.0084,"rust" if j//2%2 else "enamel",7)


def bench(x,y,z,upper=True):
    # Open aft seating is actual slatted timber with cast uprights.
    for xx in (x-.044,x+.044):
        B("Aft seat end support",(xx,y,z+.020),(.015,.053,.040),"deep green",.004)
    for v in (-1,1):
        B("Passenger bench slat",(x,y+v*.022,z+.045),(.127,.039,.013),
          "bench wood",.003)
    B("Passenger bench backrest",(x,y-.049,z+.072),(.130,.019,.043),"bench wood",.004)


def levels():
    B("Satin cream main passenger saloon",(0,-.128,.276),(.469,.788,.247),"offwhite",.032)
    B("Coved eaves of main promenade",(0,-.131,.427),(.540,.866,.085),"offwhite",.034)
    B("Slatted upper weather deck",(0,-.145,.474),(.532,.849,.032),"deck planks",.026)
    # A saloon with continuous framed glass rather than a stack of solid boxes.
    for side in (-1,1):
        xx=side*.236
        side_windows(xx,(-.468,-.365,-.241,-.119,.004,.128,.215),.321,.067,.101,"Saloon port")
        B("Saloon cabin sill capping",(side*.244,-.123,.244),(.016,.745,.035),"sea green",.010)
        B("Saloon window belt wood rail",(side*.251,-.126,.264),(.012,.765,.007),"mast gold",.002)
        B("Hinged saloon entry", (side*.240,-.527,.299),(.016,.088,.203),"carved green",.010)
        B("Entry window",(side*.250,-.528,.335),(.012,.049,.077),"dark glass",.006)
        B("Latching cabin doorway handle",(side*.258,-.541,.295),(.014,.019,.012),"copper",.004)
        B("Live harbour name board",(side*.249,-.190,.214),(.017,.300,.055),"deep green",.006)
        V.typeface("Raised harbour name","BELLHAVEN", (side*.261,-.190,.215),.042,side*pi/2,"enamel")
        raft_ring(side*.260,.168,.372)
        # Aft external staircase connects the actual passenger decks.
        for k in range(6):
            y=-.676+k*.027
            z=.172+k*.055
            B("Open weather deck stair tread",(side*.189,y,z),(.116,.055,.016),"deck shade",.003)
        for abs_x in (.135,.243):
            x=side*abs_x
            rod("Aft staircase stringer",(x,-.699,.161),(x,-.526,.472),.009,"deep green")
            rod("Aft staircase handrail",(x,-.694,.222),(x,-.527,.533),.006,"enamel")
            for y,z in ((-.695,.197),(-.613,.332),(-.527,.481)):
                rod("Stair rail support",(x,y,z),(x,y,z+.052),.005,"enamel")
        # Different open promenades on the above-main and aft forefoot decks.
        for y in (-.452,-.233,-.011):
            bench(side*.152,y,.491)
        # Main bow and aft rails end before the side embarkation portal.
        for row in ((-.810,-.744,-.650,-.553,-.448,-.350),
                    (.325,.411,.550,.654,.755,.837,.877)):
            stanchion_run([(side*(width_at(y)-.025),y,sheer_at(y)+.012) for y in row],
                          up=.096)
        stanchion_run([(side*.251,y,.493) for y in (-.513,-.426,-.335,-.245,-.157,-.071,.030,.117,.240)],
                      up=.084)
        # Decorative side embarkation gate on both sides; two columns and
        # low thresholds keep the role of this vessel clear from above.
        B("Passenger gangway inset deck board",(side*.307,.302,.170),(.132,.170,.019),"deck shade",.006)
        for vv in (.236,.372):
            C("Gangway gate iron detail",(side*.343,vv,.176),(side*.343,vv,.275),.014,.011,"deep green",8)
        rod("Suspended gate chain",(side*.348,.235,.254),(side*.348,.308,.232),.004,"mast gold",7)
        rod("Suspended gate chain",(side*.348,.308,.232),(side*.348,.371,.254),.004,"mast gold",7)
    # Aft saloon doors and foredeck machinery are readable from the stern/bow.
    for xx in (-.090,.090):
        B("Aft saloon polished paired door",(xx,-.528,.305),(.149,.017,.190),"carved green",.011)
        B("Aft saloon glazed door",(xx,-.541,.352),(.099,.011,.083),"dark glass",.006)
    for xx in (-.145,.145):
        C("Fore cabin ventilator brass rim",(xx,.259,.317),(xx,.279,.317),.037,.033,"copper",12)
        C("Forward saloon ventilator glass",(xx,.279,.317),(xx,.285,.317),.029,.027,"dark glass",12)
        B("Port ventilator brightness",(xx,.287,.325),(.038,.006,.009),"light glass",.003)
    B("Fore weather door",(0,.273,.284),(.125,.023,.203),"carved green",.009)
    B("Fore weather door glazing",(0,.290,.324),(.085,.013,.080),"dark glass",.005)
    B("Fore weather door threaded handle",(.043,.293,.258),(.023,.011,.022),"copper",.003)
    B("Fore weather door sill",(0,.296,.183),(.152,.090,.030),"deck planks",.007)
    C("Anchor capstan bed",(0,.603,.179),(0,.603,.203),.068,.057,"deep green",12)
    C("Anchor capstan barrel",(0,.603,.203),(0,.603,.257),.029,.024,"steel",10)
    C("Rim of forward warping drum",(0,.603,.251),(0,.603,.272),.042,.044,"copper",12)
    for yy,ww in ((.733,.102),(-.743,.105),(.387,.272)):
        for xx in (-ww,ww):
            C("Rope bollard mounting",(xx,yy,sheer_at(yy)),(xx,yy,sheer_at(yy)+.055),
              .017,.012,"deep green",9)
            C("Rope bollard top lip",(xx,yy,sheer_at(yy)+.050),(xx,yy,sheer_at(yy)+.061),
              .017,.016,"steel",9)


def superstructure():
    # Rounded bridge set forward; pierced details and side treatments are
    # made as geometry and film glazing, no texture-only facade.
    stations=[(.071,.175),(.096,.214),(.292,.214),(.344,.173),(.355,.137)]
    V.profile_hull("Curved pilot house with forward visibility",
        [(y,V.roof_contour(w,.486,.639,.671)) for y,w in stations],"offwhite")
    B("Bridge pronounced wheelhouse roof",(0,.213,.685),(.451,.307,.058),"deep green",.027)
    for side in (-1,1):
        side_windows(side*.213,(.140,.248),.571,.073,.076,"Pilot house side")
        B("Bridge steel hatch",(side*.214,.099,.554),(.018,.061,.123),"carved green",.008)
        B("Raised running/navigation light casing",(side*.226,.320,.602),
          (.050,.038,.036),"deep green",.007)
        B("Navigation lamp lens",(side*.250,.328,.604),(.026,.021,.023),
          "tail" if side<0 else "green light",.005)
    for x,y,w in ((0,.362,.103),(-.111,.355,.080),(.111,.355,.080)):
        B("Bridge forward window frame",(x,y,.581),(w+.013,.014,.087),"enamel",.007)
        B("Bridge forward dark glass",(x,y+.009,.581),(w,.012,.073),"dark glass",.002)
        B("Bridge blue sky reflection",(x,y+.016,.602),(w*.85,.008,.020),"light glass",.002)
    # Distinctive capped funnel, aft of the low wheelhouse roof.
    C("Raised boiler funnel plinth",(0,-.210,.478),(0,-.210,.520),.081,.068,"deep green",18)
    C("Raked boiler funnel",(0,-.210,.512),(0,-.234,.781),.061,.054,"carved green",18)
    C("Original cream funnel identification band",(0,-.226,.687),(0,-.230,.731),.058,.056,
      "offwhite",18)
    C("Chimney hood",(0,-.234,.774),(0,-.238,.801),.069,.065,"chassis",18)
    C("Recessed funnel mouth",(0,-.238,.801),(0,-.238,.803),.041,.041,"rubber",15)
    # Short mast and flag, crew signalling fore and aft.
    rod("Fore signal mast",(0,.302,.711),(0,.317,.886),.010,"mast gold",9)
    rod("Mast horizontal yard",(-.067,.313,.851),(.067,.313,.851),.005,"steel",7)
    B("Masthead warm white navigation lamp",(0,.317,.891),(.021,.019,.024),"bright lamp",.004)
    rod("Aft ensign pole",(0,-.681,.191),(0,-.707,.390),.008,"mast gold")
    rod("Signal guy",(-.061,.313,.851),(-.161,.017,.487),.0026,"steel",5)
    rod("Signal guy",(.061,.313,.851),(.161,.017,.487),.0026,"steel",5)
    flags=[(0,-.704,.349),(-.082,-.719,.351),(-.090,-.720,.387),(0,-.706,.389)]
    M("Twin-side coastal service ensign",flags,[(0,1,2,3),(3,2,1,0)],"sea green")
    # Flared open lifeboats on curved davits and proper seating blocks.
    for side in (-1,1):
        sx=side*.188
        sections=[]
        for y,w,d in ((-.490,.019,.022),(-.456,.060,.056),(-.369,.064,.073),
                      (-.282,.053,.054),(-.254,.010,.016)):
            z=.554
            sections.append((y,[(sx-w,z),(sx-w*.83,z-d*.58),(sx-w*.29,z-d),
                              (sx+w*.29,z-d),(sx+w*.83,z-d*.58),(sx+w,z)]))
        # The underlying bow/stern remain visible; the deck is open (no lid).
        p=len(sections[0][1])
        verts=[(x,y,z) for y,k in sections for x,z in k]
        end=(len(sections)-1)*p
        faces=[tuple(range(p)),tuple(reversed(range(end,end+p)))]
        for a in range(len(sections)-1):
            for j in range(p-1):
                faces += [(a*p+j,(a+1)*p+j,(a+1)*p+j+1,a*p+j+1)]
        M("Clinker-built open lifeboat",verts,faces,"offwhite")
        liner=[(sx+(x-sx)*.97,y,z+.0038) for x,y,z in verts]
        M("Wooden open lifeboat liner",liner,[tuple(reversed(f)) for f in faces],"deck shade")
        for y in (-.446,-.389,-.329,-.287):
            B("Lifeboat timber athwartships bench",(sx,y,.539),(.109,.022,.011),"bench wood",.002)
        for j,(y,w) in enumerate(((-.452,.057),(-.310,.055))):
            arm=side*(.202 if j else .211)
            rod("Curved lifeboat davit lower bent",(arm,y,.496),(arm*.96,y,.612),.009,"deep green")
            rod("Curved lifeboat davit upper bent",(arm*.96,y,.612),(sx,y,.630),.009,"deep green")
            rod("Davit rope fall",(sx,y,.630),(sx,y,.548),.0038,"steel",6)
    B("Aft weatherproof tank vent",(0,-.409,.509),(.131,.047,.037),"deep green",.011)
    raft_ring(0,-.540,.385,"y")


def ferry():
    hull()
    levels()
    superstructure()


def palette():
    row=b"".join(bytes.fromhex(PALETTE[m])*8 for m in V.KEYS)
    assert len(V.KEYS)==32
    def chunk(k,d):
        return struct.pack(">I",len(d))+k+d+struct.pack(">I",zlib.crc32(k+d))
    data=b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",256,8,8,2,0,0,0))
    data+=chunk(b"IDAT",zlib.compress((b"\0"+row)*8))+chunk(b"IEND",b"")
    (ROOT/"mods/luanttd_core/textures/bl_harbor_ferry_palette.png").write_bytes(data)

def merge(shapes):
    bpy.ops.object.select_all(action="DESELECT")
    for o in shapes:
        o.select_set(True)
    bpy.context.view_layer.objects.active=shapes[0]
    bpy.ops.object.join()
    ob=bpy.context.object
    transform=ob.matrix_world.copy()
    ob.matrix_world.identity()
    for v in ob.data.vertices:
        v.co=transform@v.co
    return ob

def export():
    V.begin()
    ferry()
    bpy.context.scene.name="LuanTTD / Bellhaven Harbor Ferry"
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art/harbor_ferry.blend"),compress=True)
    o=merge([o for o in bpy.context.scene.objects if o.type=="MESH"])
    uv=o.data.uv_layers.active or o.data.uv_layers.new()
    for p in o.data.polygons:
        idx=V.KEYS.index(o.data.materials[p.material_index].name)
        for l in p.loop_indices:
            uv.data[l].uv=((idx+.5)/32,.5)
    o.data.update()
    bpy.ops.wm.obj_export(filepath=str(ROOT/"mods/luanttd_core/models/bl_harbor_ferry.obj"),
        export_selected_objects=True,export_materials=False,export_uv=True,export_normals=True,
        export_triangulated_mesh=True,global_scale=10,forward_axis="NEGATIVE_Z",up_axis="Y")

def review(path):
    V.begin()
    for wet in (False,True):
        before=set(bpy.context.scene.objects)
        ferry()
        o=merge([o for o in bpy.context.scene.objects if o not in before])
        for v in o.data.vertices:
            x,y,z=v.co
            v.co=Vector(((x if wet else -x)+(0.89 if wet else -0.93),
                         (y if wet else -y)+(.22 if wet else -.20),z))
    # One exact plane cross-section at Z=0 for the in-water image, and a
    # second hull on low blocks exposing the complete sub-water shape.
    B("Flat test water at design line",(.89,.21,-.050),(1.64,2.60,.100),"night sea",.018)
    for j,(x,y,w) in enumerate(((1.366,-.53,.34),(1.26,.69,.37),
            (.408,.29,.27),(1.238,1.25,.35),(.657,-.86,.44),(1.512,.13,.18))):
        B("Low tidal wash accent",(x,y,.0011),(w,.012,.002),"sea ripple",.001)
    B("Inspection yard base",(-.93,-.20,-.297),(1.48,2.61,.116),"deck shade",.021)
    for y in (-.633,.449):
        B("Timber keel inspection cradle",(-.93,y,-.193),(.670,.09,.095),"deck planks",.006)
    bpy.ops.object.camera_add(location=(4.24,6.6,5.58))
    cam=bpy.context.object
    cam.rotation_euler=(Vector((0,0,.23))-cam.location).to_track_quat("-Z","Y").to_euler()
    cam.data.type="ORTHO"
    cam.data.ortho_scale=5.31
    s=bpy.context.scene
    s.camera=cam
    s.render.engine="BLENDER_WORKBENCH"
    s.render.resolution_x,s.render.resolution_y=1480,1000
    s.render.resolution_percentage=100
    s.world=bpy.data.worlds.new("Soft harbour sky")
    s.world.color=(.162,.183,.184)
    sh=s.display.shading
    sh.light="STUDIO"
    sh.color_type="MATERIAL"
    sh.background_type="WORLD"
    sh.show_shadows=True
    sh.show_cavity=True
    sh.cavity_type="BOTH"
    s.render.filepath=path
    bpy.ops.render.render(write_still=True)

if __name__=="__main__":
    palette()
    export()
    if (p:=os.getenv("BAYLINE_FERRY_REVIEW")):
        review(p)

#!/usr/bin/env python3
"""Original 1970s Bakewell coastal break-bulk ship, OpenTTD 16.0-RC1 #212."""
from math import cos,sin,tau
from pathlib import Path
import os,sys,struct,zlib
import bpy
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,os.getenv("LUANTTD_HELPERS",str(ROOT/"tools")))
import build_ship_facility_art as H
from build_rail_wagon_art import local_obj
from build_chaney_jubilee_art import geometry
B,T,R=H.box,H.tube,H.rail
STEM="stock_bakewell_cargo_ship"
COLORS={
 "Keel brick brown":"733f38","Oxide deep band":"854743","Boot line ink":"233d4a",
 "Deep coastal blue":"2b536e","Westwind blue enamel":"3b6984","York blue line":"6496a8",
 "Cobalt rubbing strakes":"30596c","Weather deck olive-grey":"626855","Pressed steel deck mottling":"6d7360",
 "Dark passage deck":"505c55","Pale green tread marks":"898d70","Dangerous edge yellow":"c8a561",
 "Raised hatch steel slate":"414d51","Hatch seam dark":"28383d","Raised hatch lip":"606b6a",
 "Hatch rail gray":"798682","Winch cast graphite":"303b3b","Crane underside shadow":"934a29",
 "Signal saffron yellow":"ce783b","Lifting paint warm brass":"e99a4f","Oleo steel":"a6a598",
 "Oleo hose":"3c453c","Fairlead gunmetal":"53615d","Anchor chain iron":"515448",
 "Pale powered cabin enamel":"d8d8c7","White sloping lookout":"e9e6d5","Cool cabin edge":"b5c1b6",
 "Square bridge surround greige":"899990","Tight panoramic bridge blue":"274651",
 "Difference in pane light":"668d92","Exhaust capped scarlet":"a84133",
 "Tarnished bronze":"a38454","Liftboat ochre and brown":"bd783f",
 "Bright indicator cream":"edd3a1","Ruby port":"b14b43","Mint starboard":"648b69",
 "Dark closed stern intake":"384e58","Original faded carrier insignia":"97ad9b",
 "Water proof only":"3f7789","Black radiator":"30393c",
}
P={k:i for i,k in enumerate(COLORS)}
FRAME=(
 (-.911,.014,.261,-.053),(-.889,.073,.255,-.071),(-.850,.124,.242,-.103),
 (-.793,.192,.228,-.132),(-.707,.250,.209,-.163),(-.607,.286,.188,-.176),
 (-.466,.325,.178,-.183),(-.290,.345,.174,-.186),(-.069,.347,.171,-.188),
 (.177,.346,.172,-.186),(.360,.338,.176,-.183),(.510,.318,.180,-.174),
 (.651,.292,.187,-.154),(.764,.237,.191,-.126),(.838,.167,.192,-.092),
 (.892,.096,.191,-.058),(.911,.055,.187,-.047),
)

def make_mesh():return R.Mesh(R.terrain_height(0))
def f(m,n,c,p):m.face(n,P[c],p)
def tube(m,n,c,p,q,r,s=None,k=9):T(m,n,c,p,q,r,r if s is None else s,k)
def line(m,n,c,pts,r,k=8):
    for a,b in zip(pts,pts[1:]):tube(m,n,c,a,b,r,k=k)
def sheer(z):
    for a,b in zip(FRAME,FRAME[1:]):
        if a[0]<=z<=b[0]:
            u=(z-a[0])/(b[0]-a[0])
            return tuple(x+(y-x)*u for x,y in zip(a[1:],b[1:]))
    raise ValueError(z)

def hull(m):
    def section(w,y,k):
        return [(-w,y),(-.994*w,y*.55),(-.966*w,.022),(-.94*w,-.013),(-.886*w,-.049),
                (-.736*w,k*.74),(-.542*w,k*.95),(-.26*w,k),(0,k),
                (.26*w,k),(.542*w,k*.95),(.736*w,k*.74),(.886*w,-.049),(.94*w,-.013),
                (.966*w,.022),(.994*w,y*.55),(w,y)]
    rings=[[(x,z,y) for x,y in section(w,h,k)] for z,w,h,k in FRAME]
    n="Closed bending and ram-taper coastal Bakewell pressure hull"
    for a,b in zip(rings,rings[1:]):
        for i,c in enumerate((
           "York blue line","Westwind blue enamel","Boot line ink","Oxide deep band","Keel brick brown",
           "Keel brick brown","Keel brick brown","Keel brick brown","Keel brick brown","Keel brick brown","Keel brick brown","Keel brick brown",
           "Oxide deep band","Boot line ink","Deep coastal blue","Westwind blue enamel","Weather deck olive-grey")):
            j=(i+1)%len(a)
            f(m,n,c,(a[i],b[i],b[j],a[j]))
    f(m,n,"Boot line ink",rings[0]);f(m,n,"Deep coastal blue",rings[-1][::-1])
    for i in range(-8,9):
        for j,(a,b) in enumerate(zip(FRAME,FRAME[1:])):
            pts=[]
            for p,q in ((a,-.47),(b,-.47),(b,.47),(a,.47)):
                z,w,y,_=p; x=(i+q)*w/9.0
                pts.append((x,z,y+.0021))
            f(m,"Individual flush weather deck laid steel strips",
                ("Weather deck olive-grey","Pressed steel deck mottling","Dark passage deck")[(i+j*3)%3],pts)
    for s in (-1,1):
        line(m,"Closed lengthwise seam running below native weather deck","York blue line",
            [(s*w,z,y-.015) for z,w,y,_ in FRAME],.007,8)
        line(m,"Full cool sheer chafing strakes","Cobalt rubbing strakes",
            [(s*w*.988,z,y*.53) for z,w,y,_ in FRAME],.005,8)
        # Two loading-break passages leave open hatch work zones.
        for run in ((-.885,-.832,-.749,-.678,-.597),(-.517,-.386,-.257,-.14,.005),
                    (.093,.234,.371,.495,.626,.740,.826,.882)):
            feet=[]
            for z in run:
                w,y,_=sheer(z)
                p=(s*w*.965,z,y+.002)
                feet.append(p)
                tube(m,"Rolled freighter guard stanchions","Hatch rail gray",p,
                     (p[0],z,p[2]+.079),.0058,k=7)
            for dy,col in ((.038,"Hatch rail gray"),(.078,"Oleo steel")):
                line(m,"Open hollow horizontal guard cables with actual gangway breaks",col,
                     [(x,z,y+dy) for x,z,y in feet],.0045,7)
    tube(m,"True exposed lower propeller shaft","Dark closed stern intake",(0,.641,-.129),(0,.871,-.094),.018,.012,12)
    tube(m,"Bronze four bladed shaft boss","Tarnished bronze",(0,.834,-.108),(0,.891,-.108),.015,.019,14)
    for i in range(4):
        a=i*tau/4
        def p(r,b,z): return (r*cos(a+b),z,-.110+r*sin(a+b))
        points=[p(.012,0,.847),p(.066,.19,.850),p(.059,.66,.866),p(.026,.44,.876)]
        back=[(x,z+.006,y) for x,z,y in points]
        f(m,"Closed pitched individually cast full propeller blades","Tarnished bronze",points)
        f(m,"Closed pitched individually cast full propeller blades","Tarnished bronze",back[::-1])
        for j in range(4):
            k=(j+1)%4;f(m,"Closed pitched individually cast full propeller blades","Tarnished bronze",
                 (points[k],points[j],back[j],back[k]))
    B(m,"True articulated quayside stern rudder plate","Oxide deep band",0,.891,.026,.039,-.151,-.032,.004)

def ground(m):
    for z in (-.777,.808):
        w,h,_=sheer(z)
        for s in (-1,1):
            x=s*w*.53
            B(m,"Stock forged bases for independently modeled twin mooring bitts",
                 "Fairlead gunmetal",x,z,.063,.064,h-.004,h+.017,.007)
            for dz in (-.014,.014):
                tube(m,"Bollard stems and enlarged heads","Fairlead gunmetal",(x,z+dz,h+.013),(x,z+dz,h+.053),
                     .011,.013,11)
    z=-.694;_,h,_=sheer(z)
    B(m,"Motor capstan and anchor drum foundation","Fairlead gunmetal",0,z,.184,.078,h-.003,h+.031,.009)
    tube(m,"Powered bow anchor windlass continuous axle","Oleo steel",(-.094,z,h+.044),(.094,z,h+.044),.016,k=10)
    for s in (-1,1):
        tube(m,"Ribbed split chain windlass drums","Anchor chain iron",(s*.036,z,h+.044),(s*.084,z,h+.044),.029,k=12)
        for j in range(10):
            i=j*.014; xx=s*(.058+.002*j)
            B(m,"Individually laid swivel anchor chain oval links","Anchor chain iron",
                 xx,z-i+.006,.019,.009,h+i*.20+.013,h+i*.20+.021,.003)
        w,y,_=sheer(-.795)
        tube(m,"Hawse bore round socket projecting slightly over the stem","Fairlead gunmetal",
             (s*(w-.006),-.795,y-.052),(s*(w+.006),-.795,y-.052),.021,k=11)
        tube(m,"Dark recess plugged by anchor stem","Boot line ink",
             (s*(w+.006),-.795,y-.052),(s*(w+.008),-.795,y-.052),.014,k=12)
    line(m,"Closed forged fore anchor flukes and shank","Fairlead gunmetal",
        [(.183,-.807,.181),(.198,-.779,.135),(.182,-.756,.126),(.165,-.769,.147)],.008)
    # Closed steel bulwark at whaleback, not the older fully open Yate end.
    for s in (-1,1):
        pts=[]
        for z in (-.889,-.850,-.793,-.707,-.644):
            w,y,_=sheer(z);pts.append((s*w*.932,z,y))
        for a,b in zip(pts,pts[1:]):
            f(m,"Roll formed forward plated breakwater above cargo walk","Westwind blue enamel",
                (a,b,(b[0],b[1],b[2]+.047),(a[0],a[1],a[2]+.047))[::s])
        line(m,"True curved plated breakwater rounded rim","Hatch rail gray",[(a,b,c+.045) for a,b,c in pts],.0068,7)
    tube(m,"Low raised emergency anchor signal mast","Oleo steel",(0,-.842,.241),(0,-.842,.396),.009,.005,9)
    tube(m,"Foredeck original low white watchlight","Bright indicator cream",(0,-.842,.391),(0,-.842,.409),.008,.007,9)

def covers(m):
    for z,ln,w in ((-.391,.321,.442),(.000,.327,.460)):
        h=sheer(z)[1]
        B(m,"Welded hatch coaming rises physically from weather deck","Raised hatch lip",
          0,z,w+.036,ln+.037,h-.016,h+.041,.010)
        B(m,"Twin true watertight dark steel cargo weather covers","Hatch seam dark",
          0,z,w,ln,h+.032,h+.063,.009)
        for i in (-1,1):
            # Each hold is four separate quarter plates over the shut cover.
            for hlf in (-1,1):
                xx=i*w*.238;zz=z+hlf*ln*.243
                B(m,"Independent sealed hinged hatch cover quadrants","Raised hatch steel slate",
                  xx,zz,w*.47,ln*.476,h+.057,h+.073,.004)
                for xx0 in (xx-w*.132,xx+w*.120):
                    tube(m,"Forged steel seam and stiffening rib on pressed leaf","Raised hatch lip",
                       (xx0,zz-ln*.196,h+.073),(xx0,zz+ln*.196,h+.073),.0032,k=7)
                for jj in (-.051,.048):
                    x=i*(w*.495)
                    tube(m,"Pin in exterior cargo cover folding hinge barrel","Hatch rail gray",
                         (x,zz+jj-.011,h+.056),(x,zz+jj+.011,h+.056),.007,k=9)
                for dz in (-.025,.025):
                    B(m,"Square lifting socket inlet in removable steel plate","Hatch seam dark",
                      xx,zz+dz,.020,.013,h+.071,h+.074,.002)
            for zz in (z-ln*.48,z+ln*.48):
                tube(m,"Lift point welded loop and counterweighted lock","Dangerous edge yellow",
                    (i*w*.447,zz,h+.065),(i*w*.447,zz,h+.084),.0044,k=8)
    # Real walkways, keep fully open clean passage between and around covers.
    for z in (-.209,.180):
        y=sheer(z)[1]
        B(m,"Pressed steel transverse cargo crossover walkway","Dark passage deck",0,z,.478,.045,y+.007,y+.021,.004)
        for i in range(-9,10):
            B(m,"True fine-slip crossover grate ribs and expansion joints","Pale green tread marks",
                .023*i,z,.004,.040,y+.021,y+.023,.001)

def cranes(m):
    for z,t,direction in ((-.589,.142,1),(.199,-.093,-1)):
        y=sheer(z)[1]
        tube(m,"Cast fixed circular freighter crane turret bed ring","Fairlead gunmetal",(0,z,y-.003),(0,z,y+.030),
             .067,.064,24)
        tube(m,"Teeth shroud and hydraulic kingpost base for full turning","Crane underside shadow",
             (0,z,y+.028),(0,z,y+.101),.056,.048,17)
        tube(m,"Modern hold-loading orange torque mast","Signal saffron yellow",
             (0,z,y+.091),(0,z,.445),.039,.030,16)
        B(m,"Glazed crane control enclosure and root shoe on slewing post","Signal saffron yellow",
            -.027,z,.086,.076,.355,.425,.009)
        B(m,"Inlaid operator dark windows on crane enclosure","Tight panoramic bridge blue",
            -.048,z+.038,.050,.008,.384,.415,.003)
        # Articulated-looking tapered two segment boom, cylinder and line.
        a=(0,z,.429);b=(-.018,z+direction*.088,.560);c=(t,z+direction*.271,.478)
        tube(m,"First smooth deep cast knuckle boom member","Signal saffron yellow",a,b,.021,.017,7)
        tube(m,"Second longer telescoping genuine hatch crane boom","Lifting paint warm brass",b,c,.017,.010,8)
        tube(m,"Full-width crane arm structural pivot intersecting both forks","Crane underside shadow",
             (b[0]-.027,b[1],b[2]),(b[0]+.026,b[1],b[2]),.023,.021,11)
        d=(0,z-direction*.019,.351);e=(-.056,z+direction*.070,.484)
        tube(m,"Individually mounted boom lift actuation cylinder","Crane underside shadow",d,
            (d[0]*.45+e[0]*.55,d[1]*.45+e[1]*.55,d[2]*.45+e[2]*.55),.012,k=11)
        tube(m,"Exposed chromium hydraulic piston leads into knuckle","Oleo steel",
             (d[0]*.48+e[0]*.52,d[1]*.48+e[1]*.52,d[2]*.48+e[2]*.52),e,.0055,k=8)
        end=(c[0],c[1],.390)
        tube(m,"Hanging wire winch pendant with physical block","Oleo hose",c,end,.0023,k=6)
        tube(m,"Damped freight winch sheave bottom block","Crane underside shadow",end,
             (end[0],end[1],.374),.012,.009,10)
        line(m,"Bent freight lifting hook closes under parked jib","Oleo steel",
             [(end[0],end[1],.375),(end[0],end[1],.356),(end[0]+.011,end[1],.351),
              (end[0]+.017,end[1],.359),(end[0]+.011,end[1],.367)],.0038,7)
        for s in (-1,1):
            x=s*.116
            B(m,"Deck mounted hatch folding hydraulic winch beds","Fairlead gunmetal",x,z-.014,.070,.073,y+.001,y+.036,.006)
            tube(m,"Cross-spun deck cargo winch brake drum","Oleo hose",(x-.040,z-.012,y+.044),(x+.040,z-.012,y+.044),.018,k=12)

def bridge(m):
    # Modern aft accommodation and angular forward bridge glass,
    # three-tiered instead of the narrower Yate house and tall steam funnel.
    for z,w,l,lo,hi,c in ((.543,.498,.379,.176,.362,"Pale powered cabin enamel"),
                          (.522,.440,.337,.359,.424,"Cool cabin edge"),
                          (.514,.438,.281,.422,.588,"Pale powered cabin enamel"),
                          (.513,.471,.309,.578,.609,"White sloping lookout")):
        B(m,"Stacked three-tier aft bridge and lookout cabin",c,0,z,w,l,lo,hi,.021)
    B(m,"Forward overhanging true wheelhouse lookout platform","Cool cabin edge",0,.391,.449,.092,.415,.431,.008)
    # Windshield side returns use real planes on shallow angles.
    for i in range(-3,4):
        x=i*.053;z=.343+max(0,abs(i)-1)*.0040
        q=[(x-.024,z,.473),(x+.024,z,.473),(x+.026,z+.020,.550),(x-.026,z+.020,.550)]
        f(m,"Polished stepped compressed rubber panoramic pilot window bezel","Square bridge surround greige",q)
        q2=[(x-.019,z-.003,.485),(x+.019,z-.003,.485),(x+.021,z+.014,.543),(x-.021,z+.014,.543)]
        f(m,"Raked panoramic cabin window glazing seated across ship bridge","Tight panoramic bridge blue",q2)
        f(m,"Raked panoramic cabin window glint strips","Difference in pane light",
           [(x-.019,z+.008,.518),(x+.019,z+.008,.518),(x+.020,z+.015,.535),(x-.020,z+.015,.535)])
    for s in (-1,1):
        for z in (.408,.467,.527,.588,.648):
            B(m,"Individual row dark side bridge windows set inside seal","Square bridge surround greige",s*.220,z,.014,.050,.465,.544,.004)
            B(m,"Contained rectangular blue glass in upper bridge return","Tight panoramic bridge blue",s*.228,z,.009,.041,.474,.535,.003)
            B(m,"Pale upper haze from 3D window lighting","Difference in pane light",s*.233,z,.004,.038,.518,.531,.0015)
        for z in (.419,.487,.554,.622,.681):
            B(m,"Private officer accommodation window apertures","Tight panoramic bridge blue",s*.253,z,.008,.030,.279,.322,.004)
        B(m,"Vertical passage access door on aft machinery housing","Cool cabin edge",s*.255,.587,.013,.074,.188,.312,.003)
        B(m,"Pressed serviceable dark external handle","Fairlead gunmetal",s*.263,.605,.010,.014,.226,.242,.002)
        # Double launch skiffs on rear wings, safely inside native envelope.
        x=s*.246
        B(m,"Inboard aft accommodation cast davit foundation","Fairlead gunmetal",x,.742,.061,.042,.194,.225,.006)
        line(m,"Separate aft hinged davit arm braced to base","Oleo steel",
             [(x-s*.017,.747,.223),(x-s*.022,.753,.344),(x+s*.033,.753,.340)],.007,8)
        line(m,"Drop wire connects lifeboat to davit crane","Oleo hose",
             [(x+s*.033,.753,.342),(x+s*.023,.748,.253)],.0029,7)
        stations=((.576,.005,.231),(.605,.026,.214),(.664,.044,.199),
                  (.736,.042,.205),(.781,.026,.227),(.803,.004,.244))
        shape=[[(x-u*w,z,h) for u,h in ((1,.260),(.78,(k+.260)/2),(.31,k),
                 (-.31,k),(-.78,(k+.260)/2),(-1,.260))] for z,w,k in stations]
        for a,b in zip(shape,shape[1:]):
            for j in range(6):
                t=(j+1)%6
                f(m,"Taper formed real merchant emergency launch skiff",
                  "Liftboat ochre and brown" if j!=5 else "Dark passage deck",(a[j],b[j],b[t],a[t]))
        f(m,"Closed fore and stern skiff bulkheads","Liftboat ochre and brown",shape[0])
        f(m,"Closed fore and stern skiff bulkheads","Liftboat ochre and brown",shape[-1][::-1])
        for g in (0,5):
            line(m,"Raised skiff cover edge with authentic contour","Oleo steel",[q[g] for q in shape],.0032,7)
        # Ladder physically joins the lower passage and the wheelhouse platform.
        z=.642
        for k in (-1,1):
            tube(m,"Twin steel aft companionway ladder stile","Oleo steel",
                 (s*.256,z+k*.024,.195),(s*.250,z+k*.024,.440),.0036,k=8)
        for i in range(8):
            h=.219+i*.026
            tube(m,"Visible steel companionway horizontal step rung","Hatch rail gray",
                 (s*.257,z-.025,h),(s*.257,z+.025,h),.0033,k=7)
        tube(m,"Independent bridge wing navigation running lamp","Ruby port" if s<0 else "Mint starboard",
             (s*.232,.398,.447),(s*.233,.398,.476),.014,.013,12)
    for s in (-1,1):
        z=.679 if s>0 else .643
        B(m,"Rear integrated diamond maintenance intake housing into accommodation deck","Pale powered cabin enamel",
          s*.065,z,.101,.102,.357,.579,.014)
        B(m,"Split angled red-capped diesel motor exhaust boxes","Exhaust capped scarlet",s*.065,z,.079,.088,.565,.695,.012)
        B(m,"Pressed slanted charcoal louvre cap over diesel uptakes","Black radiator",s*.064,z,.086,.092,.682,.709,.009)
        for i in (-1,1):
            B(m,"Separate rimmed cut exhaust fingers","Dark closed stern intake",s*.064+i*.017,z,.013,.053,.707,.715,.003)
    tube(m,"Low modern radar aerial mast","Oleo steel",(0,.499,.603),(0,.497,.768),.013,.007,10)
    tube(m,"Modern real transverse rotating radar bar","White sloping lookout",(-.072,.501,.745),(.072,.501,.745),.008,.008,10)
    tube(m,"Bridge top long-distance running light lit cream","Bright indicator cream",(0,.497,.760),(0,.497,.786),.009,.007,9)

def atlas():
    row=b"".join(bytes.fromhex(v)*8 for v in COLORS.values())
    def c(t,b):return struct.pack(">I",len(b))+t+b+struct.pack(">I",zlib.crc32(t+b))
    path=ROOT/"mods/luanttd_core/textures"/f"bl_{STEM}_atlas.png"
    path.write_bytes(b"\x89PNG\r\n\x1a\n"+c(b"IHDR",struct.pack(">IIBBBBB",len(P)*8,8,8,2,0,0,0))+
                      c(b"IDAT",zlib.compress((b"\0"+row)*8,9))+c(b"IEND",b""))

def build():
    H.P=P;R.COLORS[:]=COLORS.values()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene
    scene.name="LuanTTD | Bakewell Cargo Ship #212"
    scene["source"]="Original interpretation of 16.0-RC1 stock #212, image 0 shared base 3677. No cargo-state mesh."
    scene["orientation"]="Native bow -Z, unit scale, Y=0 design waterplane including lock lift."
    mats=R.materials()
    for n,mat in zip(P,mats):mat.name=n
    parts=(("01 | Continuous enclosed steel hull and immersed propulsion",hull),
           ("02 | Tackle, anchor and winch gear",ground),
           ("03 | Watertight hatches and walkways",covers),
           ("04 | Two independent hydraulic cargo cranes",cranes),
           ("05 | Tiered aft accommodation and navigation",bridge))
    m=make_mesh()
    for n,fn in parts:
        x=make_mesh();fn(x);geometry(scene,n,x,mats);fn(m)
    p=ROOT/"mods/luanttd_core/models"/f"bl_{STEM}.obj"
    R.export_obj(p,local_obj(m))
    p.write_text("# Original Bakewell Cargo Ship for LuanTTD; stock #212; tools/build_stock_bakewell_cargo_ship_art.py\n"+p.read_text().split("\n",1)[1])
    atlas()
    for s in bpy.data.screens:
        for a in s.areas:
            if a.type=="VIEW_3D":
                q=a.spaces.active;q.shading.color_type="MATERIAL";q.region_3d.view_location=Vector((0,0,.30))
                q.region_3d.view_distance=2.98;q.region_3d.view_rotation=Vector((.78,-.88,.69)).to_track_quat("Z","Y")
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art"/f"{STEM}.blend"),compress=True)
    if d:=os.getenv("BAKEWELL_CARGO_REVIEW"):
        out=Path(d)
        bpy.ops.mesh.primitive_plane_add(size=26,location=(0,0,-.0002))
        bpy.context.object.data.materials.append(bpy.data.materials["Water proof only"])
        water=bpy.context.object
        bpy.ops.object.camera_add()
        cam=bpy.context.object;cam.data.type="ORTHO";scene.camera=cam
        scene.render.engine="BLENDER_WORKBENCH"
        scene.render.resolution_x,scene.render.resolution_y=1150,820
        scene.render.resolution_percentage=100
        scene.display.shading.light="STUDIO";scene.display.shading.color_type="MATERIAL"
        scene.display.shading.show_cavity=True;scene.display.shading.cavity_type="BOTH"
        scene.display.shading.show_shadows=True;scene.display.shading.background_type="WORLD"
        scene.world=bpy.data.worlds.new("Soft daylight at the bluff")
        scene.world.color=(.14,.20,.24)
        scene.view_settings.view_transform="Standard";scene.view_settings.exposure=.28
        scene.render.image_settings.file_format="JPEG";scene.render.image_settings.quality=92
        for tag,p,look,scale in (("bow",(2.44,-3.09,1.64),(0,0,.26),2.53),
                                 ("deck",(-2.35,2.75,2.37),(0,0,.26),2.42),
                                 ("profile",(3.7,-.25,.91),(0,0,.32),2.21),
                                 ("ventral",(2.85,1.98,-1.12),(0,0,.27),2.44)):
            water.hide_render=tag=="ventral"
            cam.location=p;cam.rotation_euler=(Vector(look)-cam.location).to_track_quat("-Z","Y").to_euler()
            cam.data.ortho_scale=scale
            scene.render.filepath=str(out/f"{STEM}-{tag}.jpg")
            bpy.ops.render.render(write_still=True)
if __name__=="__main__":build()

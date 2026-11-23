#!/usr/bin/env python3
"""Original Thomas Grain Truck #142 exterior with independently removable grain."""
from copy import deepcopy
from math import cos, pi, sin, tau
from pathlib import Path
from random import Random
import os
import struct
import sys
import zlib

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
sys.path.append(os.getenv("LUANTTD_HELPERS",str(ROOT/"tools")))
import build_stock_road_primitives as road

w,r,bpy,V=road.w,road.r,road.bpy,road.Vector
B,C,rod=road.B,road.C,road.rod
STEM="stock_thomas_grain_truck"
COL={
    "Axle grey":"555c62","Frame":"323a3e","Rubber":"292c2e","Tyre scuff":"454545",
    "Hub":"616d71","Nurled iron":"4e5758","Rim":"adb4b4","Roof dark":"3a4146",
    "Thomas navy blue":"3b526f","Thomas enamel cobalt":"456e9c","Thomas slate blue":"5c83a4",
    "Thomas shadow":"304962","Deep brass bead":"b09b65","Ivory line":"d5c596",
    "Pressed air dam":"3e515e","Heavy bumper":"536c7a","Machined alloy":"a6b5b8",
    "Modern trim":"43545c","Stainless brushed":"a1b0b3","Recessed grille":"31404a",
    "Glass rim":"263641","Glass":"385265","Glass glint":"86a6b0","Glass rear shade":"4a6476",
    "Lamps warm silver":"f0dba8","Amber marker":"d09c54","Rear cherry lens":"b64c47",
    "Rear clear white":"cfcdc0","Rear lamp mount":"4a4d4e","Registration plate":"daba78",
    "Bed steel low":"707c80","Bed steel bevel":"88969a","Bright rolled lip":"b0bec0",
    "Hopper soft steel":"838f94","Hopper bright steel":"98a5a8","Hopper road face":"6e7f86",
    "Hopper stain dark":"59666c","Hopper dull shadow":"626e76","Hopper floor wear":"697177",
    "Gate flap steel":"82969d","Gate dark seal":"3a4a52","Gate hinges nickel":"9da9a6",
    "Gate linkage dark":"52605b","Gauge brown casting":"6b644f",
    "Grain bottom shadow":"9e7746","Grain margin lighter":"c29656","Grain warm middle":"d3a657",
    "Grain gold daylight":"dbb263","Grain mellow saffron":"dab063","Grain ridge wheat":"e0b86b",
    "Grain spun chaff":"e1b66b","Grain sunbright":"e7bf73","Grain amber kernel":"d4a254",
    "Grain ochre kernel":"b68c55","Grain pale tip":"edc888","Grain toasted germ":"9f794c",
    "Worn hydraulic blue":"647980","Twin deck airflow":"7f939c","Grain protection fastener":"818e8a",
    "Cab cool upper glazing":"577d93","Cool louver shade":"566975","Light asphalt":"5f6668",
    "Lane center chalk":"ddc391","Fleet blue registration":"405676",
}
assert len(COL)==64
P={color:i for i,color in enumerate(COL)}
w.P=road.P=P
r.COLORS[:]=COL.values()
AX=(-.503,.459)
R=.124
T=.222
BED=(-.185,.749)
INSIDE_HALF=.224


def f(m,group,col,pts):
    road.f(m,group,col,pts)


def underframe(m):
    road.wheels(m,*AX,T,R,"Machined alloy",True)
    for s in (-1,1):
        B(m,"Thomas dual dropped ladder frame rails","Frame",s*.154,.002,.052,1.489,.126,.205,.010)
        B(m,"Exposed lower wear flanges","Axle grey",s*.156,.049,.059,1.347,.140,.153,.003)
        for z,k in ((-.505,False),(.459,True)):
            road.fender(m,"Independently formed period rear and front arches",s*.237,z,R,R+.030,.100,
                        "Pressed air dam")
            B(m,"Flexible patterned rubber spray skirt","Rubber",s*.229,z+.130,.121,.026,.053,.196,.006)
            for i in range(3):
                B(m,"True folded axle springs","Nurled iron",s*.146,z,
                  .036,.201-i*.018,.154+i*.009,.160+i*.009,.003)
    for z in (-.631,-.211,.079,.402,.665):
        B(m,"Visible transverse supporting chassis bulkheads","Axle grey",0,z,.334,.045,.145,.212,.006)
    B(m,"Shaped 1970s underframe metal fuel tank","Frame",.159,.164,.147,.278,.100,.197,.018)
    for y in (.085,.246):
        B(m,"Individual fuel straps and casting screws","Modern trim",.160,y,.153,.020,.118,.205,.005)
        C(m,"Pressed tie-down screw and washers","Machined alloy",(.236,y,.168),.008,"x",-.006,.006,8)
    B(m,"Underside towing and tipping oil reservoir","Nurled iron",-.153,.255,.129,.225,.108,.192,.017)
    C(m,"Real central prop shaft","Axle grey",(0,.062,.123),.022,"z",-.431,.385,10)
    C(m,"Locking ram body around tilt rod","Worn hydraulic blue",(-.080,.143,.221),.030,"z",-.108,.178,12)
    C(m,"Chrome tipping piston extension","Stainless brushed",(-.080,.262,.221),.017,"z",-.042,.129,12)


def cab(m):
    def ring(z,half,h,top):
        return z,[(-half*.83,.207),(half*.83,.207),(half,.246),(half,h-.028),
          (half*.96,h),(half*.78,top-.008),(half*.57,top),(-half*.57,top),
          (-half*.78,top-.008),(-half*.96,h),(-half,h-.028),(-half,.246)]
    cabrows=((-.781,.183,.379,.433),(-.759,.221,.423,.465),(-.725,.248,.462,.511),
        (-.678,.262,.508,.570),(-.618,.270,.545,.624),(-.563,.270,.563,.661),
        (-.512,.270,.568,.664),(-.307,.270,.568,.664),(-.236,.246,.551,.645),
        (-.199,.211,.522,.603))
    road.section_hull(m,"Bent late Mid-century Thomas pressed cab shell",
        [ring(*k) for k in cabrows],
        ["Thomas shadow","Pressed air dam","Thomas enamel cobalt","Thomas slate blue",
         "Thomas slate blue","Thomas enamel cobalt","Thomas slate blue","Thomas enamel cobalt",
         "Thomas slate blue","Thomas slate blue","Thomas enamel cobalt","Pressed air dam"],
        "Thomas enamel cobalt")
    def row(q,z):
        for a,b in zip(cabrows,cabrows[1:]):
            if a[0]<=z<=b[0]:
                k=(z-a[0])/(b[0]-a[0])
                return a[q]*(1-k)+b[q]*k
        raise ValueError(z)
    def point(x,z,lift):
        half,h,top=(row(q,z) for q in (1,2,3))
        r=abs(x)
        skin=top
        if r>.57:
            skin=top-.008*(r-.57)/(.78-.57)
        return (x*half,z,skin+lift)
    for name,tone,xlo,xhi,front,rear,lift in (
        ("Deep curved Thomas windshield gasket","Glass rim",.012,.795,-.740,-.567,.008),
        ("Actual opposed triplex front laminated glass panes","Glass",.047,.745,-.732,-.578,.014),
        ("A thin sky stripe along laminated roof apron","Glass glint",.07,.715,-.598,-.583,.017),
    ):
        cuts=[front,*[z for z,*_ in cabrows if front<z<rear],rear]
        for a,b in zip(cuts,cuts[1:]):
            for s in (-1,1):
                f(m,name,tone,(point(s*xlo,a,lift),point(s*xhi,a,lift),
                               point(s*xhi,b,lift),point(s*xlo,b,lift))[::s])
    for s in (-1,1):
        rod(m,"Short dual Thomas parked wiper arm","Glass rim",
            point(s*.180,-.722,.019),point(s*.443,-.697,.021),.0034)
        rod(m,"Separate broad black wiper blade","Glass rim",
            point(s*.443,-.697,.021),point(s*.629,-.660,.023),.0030)
        B(m,"Chassis inset dark door seam","Thomas shadow",s*.270,-.426,.015,.287,.280,.579,.009)
        B(m,"Original recessed lighter Thomas door leaf","Thomas enamel cobalt",s*.279,-.426,
            .013,.267,.293,.566,.010)
        road.panes(m,"Thomas wide driver side dual drop glass",s*.285,-.437,.218,.407,.551,"Glass rim","Cab cool upper glazing")
        B(m,"Narrow blue tinted front side quarter light mullion","Machined alloy",s*.304,-.495,
            .007,.009,.424,.543,.002)
        B(m,"Recessed nickel side pull and door step latch","Stainless brushed",s*.287,-.325,
            .011,.043,.359,.372,.004)
        B(m,"Original harvest painted stripe fading around cab corners","Ivory line",s*.284,-.412,
            .009,.276,.324,.344,.005)
        B(m,"Built-out Thomas anti-slip door step beside axle","Cool louver shade",s*.244,-.277,
            .105,.144,.157,.179,.012)
        for j in range(4):
            B(m,"Independent raised step serrations","Twin deck airflow",s*.252,
                -.324+j*.030,.068,.006,.177,.183,.001)
        rod(m,"Real attached period mirror support on A-pillar","Modern trim",
            (s*.260,-.622,.490),(s*.290,-.622,.536),.0053)
        B(m,"Narrow steel period wing mirror","Pressed air dam",s*.292,-.636,.034,.024,.507,.572,.006)
        B(m,"Rear-facing wing mirror glass and surface","Stainless brushed",s*.292,-.621,.026,.008,.517,.562,.003)
        B(m,"Amber wing corner turn lamp","Amber marker",s*.213,-.767,.052,.017,.357,.380,.004)
    B(m,"Wide separate dock-proof blue front bumper","Heavy bumper",0,-.776,.469,.072,.155,.225,.022)
    B(m,"Inset Thomas wider narrow grille black fascia","Recessed grille",0,-.783,.341,.041,.238,.356,.012)
    for j in range(12):
        B(m,"Thin vertical cast grille bars","Modern trim",(j-5.5)*.014,-.807,.006,.008,.258,.338,.001)
    B(m,"Thomas thin brushed dividing bar above sidelamps","Stainless brushed",0,-.810,.319,.009,.337,.350,.003)
    for s in (-1,1):
        B(m,"Dull matte flush headlamp mounting cups","Modern trim",s*.188,-.783,
            .103,.044,.250,.323,.008)
        B(m,"Actual paired forward lens headlamps","Lamps warm silver",s*.186,-.807,.073,.011,.264,.309,.004)
    B(m,"Separate warm front license panel without branding","Fleet blue registration",0,-.817,.131,.010,.174,.208,.004)
    for j,h in enumerate((.013,.011,.016,.016,.009,.014)):
        B(m,"Pressed vehicle plate inscription strokes","Machined alloy",(j-2.5)*.016,-.824,
            .006,.008,.182,.182+h,.001)
    B(m,"Broad polished roof edge rain visor","Stainless brushed",0,-.568,.366,.033,.662,.675,.006)
    for s in (-1,1):
        B(m,"Separate recessed blue kick panel on cab","Thomas navy blue",s*.276,-.431,.013,.237,.274,.309,.004)
    B(m,"Tall roof basic period vent hatch","Thomas slate blue",0,-.478,.220,.154,.658,.685,.013)
    B(m,"Small rear cab pane overlooking the tipped bed","Glass rim",0,-.197,.291,.022,.459,.552,.012)
    B(m,"Rear visible clouded windscreen separate inset","Glass rear shade",0,-.183,.259,.014,.474,.536,.008)


def hopper(m):
    front,rear=BED
    def rim(x,a,b,c,h):
        return [(-x+c,a,h),(x-c,a,h),(x,a+c,h),(x,b-c,h),
                (x-c,b,h),(-x+c,b,h),(-x,b-c,h),(-x,a+c,h)]
    name="Watertight thin pressed steel open-top tapered hopper shell"
    lo=rim(.177,front+.025,rear-.021,.034,.234)
    keel=rim(.183,front+.021,rear-.015,.036,.268)
    knee=rim(.242,front+.006,rear-.008,.043,.372)
    swage=rim(.245,front+.003,rear-.003,.040,.391)
    lip=rim(.245,front,rear,.037,.474)
    cap=rim(.249,front-.007,rear+.007,.035,.495)
    inner=rim(INSIDE_HALF,front+.013,rear-.013,.035,.494)
    pan=rim(.165,front+.034,rear-.028,.034,.289)
    q=(lo,keel,knee,swage,lip,cap,inner,pan)
    tones=("Hopper stain dark","Bed steel bevel","Bed steel low","Hopper road face",
           "Hopper bright steel","Bright rolled lip","Hopper soft steel")
    f(m,name,"Hopper dull shadow",lo[::-1])
    for mat,a,b in zip(tones,q,q[1:]):
        for i,aa in enumerate(a):
            j=(i+1)%8
            f(m,name,mat,(aa,a[j],b[j],b[i]))
    f(m,name,"Hopper floor wear",pan)
    for z in (-.143,.205,.580,.693):
        B(m,"Heavy transverse hollow sections carry the hopper","Frame",0,z,.429,.048,.208,.241,.007)
    for s in (-1,1):
        for z in (-.092,.083,.265,.436,.600):
            x=s*.248
            road.rod(m,"Distinct pressed trapezoid external stiffeners","Hopper bright steel",
                     (s*.185,z,.267),(x,z,.386),.013)
            B(m,"Bolted upper wall reinforcement plate","Bed steel bevel",x,z,.015,.025,.388,.468,.005)
            C(m,"Separate grizzled pressed-stiffener rivet","Grain protection fastener",(x+s*.011,z,.441),
              .008,"x",-.003,.005,8)
        rod(m,"Long subtle rail behind rolled hopper lip","Twin deck airflow",
            (s*.246,front+.044,.465),(s*.246,rear-.032,.465),.006)
        B(m,"Integral steel under hopper landing brackets","Worn hydraulic blue",s*.142,.368,
          .056,.239,.174,.238,.009)
        rod(m,"Diagonal steel lower tip brace","Gate linkage dark",
            (s*.117,.055,.211),(s*.188,.333,.262),.012)
    B(m,"Rear load gate mechanical independent rubber recess","Gate dark seal",0,.756,
      .405,.024,.281,.470,.011)
    B(m,"Broad shaped rear hopper gate flap steel skin","Gate flap steel",0,.770,
      .383,.023,.290,.455,.010)
    B(m,"Rear independent recessed discharge door on flap","Hopper dull shadow",0,.785,
      .162,.016,.312,.402,.007)
    B(m,"Painted gravity-feed grain slide gate raised panel","Hopper bright steel",0,.795,
      .132,.013,.321,.393,.005)
    rod(m,"Horizontal manual grain gate release handle","Gate hinges nickel",
        (-.037,.804,.373),(.047,.804,.373),.007)
    for x in (-.142,0.,.142):
        C(m,"Top-swing visible greased gate hinge pins","Gate hinges nickel",(x,.771,.478),
          .013,"x",-.028,.027,14)
        B(m,"Attached rear flap hinge plate hardware","Worn hydraulic blue",x,.757,.053,
          .029,.443,.478,.007)
    for s in (-1,1):
        x=s*.209
        C(m,"Retained half-turn gate latch casting","Gauge brown casting",(x,.765,.342),
          .026,"z",-.008,.013,12)
        B(m,"Raised gate locking knob warning bead","Amber marker",x,.783,.031,.007,.364,.375,.002)
        rod(m,"Separately modeled gate lever and crank","Gate linkage dark",
            (x,.778,.334),(x-s*.028,.794,.374),.010)
        B(m,"Rear frame-mounted twin lamp assembly","Rear lamp mount",s*.168,.766,
          .097,.036,.157,.226,.010)
        for j,c in enumerate(("Amber marker","Rear cherry lens","Rear clear white")):
            B(m,"True aft-facing triple lens bars",c,s*(.138+j*.024),.787,
              .021,.012,.178,.211,.004)
    B(m,"Low rear real impact bar with outward corners","Frame",0,.756,.442,.037,.132,.175,.012)
    B(m,"Rear plated warm stamped number registration panel","Registration plate",0,.783,
      .127,.014,.153,.179,.005)
    for j,h in enumerate((.012,.014,.011,.009,.014,.015)):
        B(m,"Original license press marks rear","Fleet blue registration",(j-2.5)*.015,.792,.005,.006,.157,.157+h,.001)


def grain(m):
    """Gravitational mound, nested closed sides and a separately seeded relief."""
    rng=Random(1421978)
    nx,nz=18,36
    z0,z1=-.157,.723
    def pos(i,j):
        u=i/nx
        t=j/nz
        x=(2*u-1)*(.209-.016*(abs(2*t-1)**9))
        z=z0+(z1-z0)*t
        mound=(sin(pi*u)**.9)*(sin(pi*t)**.75)
        gently=(.055+.011*cos(t*tau*1.15-.36)+.013*sin(t*tau*1.64+.9))
        h=.446 + mound*gently + rng.uniform(-.0017,.0017) + (x*.033*cos(t*tau*.8))
        return (x,z,h)
    q=[[pos(i,j) for i in range(nx+1)] for j in range(nz+1)]
    label="Closed molded golden grain volume"
    surface=("Grain margin lighter","Grain warm middle","Grain gold daylight","Grain mellow saffron",
             "Grain ridge wheat","Grain spun chaff","Grain sunbright")
    top_tri=[]
    for j in range(nz):
        for i in range(nx):
            A,B0,C,D=q[j][i],q[j][i+1],q[j+1][i+1],q[j+1][i]
            ts=((A,B0,D),(B0,C,D)) if (i+j)%2 else ((A,B0,C),(C,D,A))
            for t in ts:
                h=sum(p[2] for p in t)/3
                colors=surface[:3] if h<.451 else surface[2:5] if h<.473 else surface[3:7]
                f(m,label,rng.choice(colors),t)
                top_tri.append(t)
    edge=q[0][:-1]+[row[-1] for row in q[:-1]]+q[-1][:0:-1]+[row[0] for row in q[:0:-1]]
    lower=[(x*.752,.283+(z-.283)*.955,.292) for x,z,_ in edge]
    for i,(a,b) in enumerate(zip(edge,lower)):
        j=(i+1)%len(edge)
        f(m,label,"Grain bottom shadow" if i%5 else "Grain margin lighter",(a,b,lower[j],edge[j]))
    for i,b in enumerate(lower):
        nb=lower[(i+1)%len(lower)]
        f(m,label,"Grain bottom shadow",(nb,b,(0,.283,.292)))
    kernels=("Grain amber kernel","Grain ochre kernel","Grain pale tip","Grain toasted germ")
    def kernel(x,z,h,angle,size):
        cs,sn=cos(angle),sin(angle)
        def p(a,b,c):return (x+(a*cs-b*sn)*size,z+(a*sn+b*cs)*size,h+c*size)
        base=[p(1,0,-.26),p(.35,.43,-.01),p(-.54,.43,-.01),p(-1.03,.05,-.14),
              p(-.51,-.42,-.06),p(.30,-.38,-.03)]
        peak=p(-.11,.017,.37)
        color=rng.choice(kernels[:3])
        for i,b in enumerate(base):
            f(m,"Separate real convex hull grain kernels",color if i<4 else kernels[(i-3)%4],
                 (b,base[(i+1)%6],peak))
        f(m,"Separate real convex hull grain kernels",kernels[1],base[::-1])
    for t in rng.sample(top_tri,482):
        a=rng.uniform(.18,.58)
        b=rng.uniform(.13,.77-a)
        c=1-a-b
        x,z,h=(sum(values) for values in zip((v*a for v in t[0]),(v*b for v in t[1]),(v*c for v in t[2])))
        kernel(x,z,h+.00075,rng.uniform(0,tau),rng.uniform(.0033,.0063))


def palette(path):
    def chunk(k,d):return struct.pack(">I",len(d))+k+d+struct.pack(">I",zlib.crc32(k+d))
    row=b"".join(bytes.fromhex(v)*16 for v in COL.values())
    path.write_bytes(b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",1024,16,8,2,0,0,0))
                     +chunk(b"IDAT",zlib.compress((b"\0"+row)*16))+chunk(b"IEND",b""))


def make():
    palette(ROOT/"mods/luanttd_core/textures"/f"bl_{STEM}_atlas.png")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene
    scene.name="LuanTTD | Thomas Grain Truck #142"
    scene["source_version"]="OpenTTD 16.0-RC1"
    scene["stock_engine_id"]=142
    scene["native_setup"]=".42 scale, true tread Y=0, nose −Z"
    m=r.Mesh(r.terrain_height(0))
    underframe(m)
    cab(m)
    hopper(m)
    payload=r.Mesh(r.terrain_height(0))
    grain(payload)
    full=deepcopy(m)
    for name,faces in payload.parts.items():
        for inds,c in faces:
            full.tri(name,c,[payload.vertices[name][i] for i in inds])
    mats=r.materials()
    for name,mat in zip(COL,mats):
        mat.name=name
        p=mat.node_tree.nodes.get("Principled BSDF")
        p.inputs["Roughness"].default_value=(.32 if name.startswith("Glass")
                                             else .82 if name.startswith("Grain") else .60)
        p.inputs["Metallic"].default_value=.31 if name.startswith(("Machined","Bright rolled","Stainless","Gate hinges")) else 0
    base=bpy.data.collections.new("01 • Editable Thomas cab, wheels, doors, hopper")
    load=bpy.data.collections.new("02 • Toggle load: closed grain volume and actual kernels")
    for c in (base,load):scene.collection.children.link(c)
    r.to_blender(m,base,mats)
    r.to_blender(payload,load,mats)
    for tag,mesh in (("",m),("_loaded",full)):
        file=ROOT/"mods/luanttd_core/models"/f"bl_{STEM}{tag}.obj"
        r.export_obj(file,w.local_obj(mesh))
        lines=file.read_text().splitlines()
        lines[0]="# Original Thomas grain road lorry; regenerate with tools/build_stock_thomas_grain_art.py"
        file.write_text("\n".join(lines)+"\n")
    prev=set(scene.objects)
    road.studio(scene)
    studio=bpy.data.collections.new("90 • Studio inspection only (not exported)")
    scene.collection.children.link(studio)
    first=scene.camera
    views=[]
    for index,(name,loc,empty) in enumerate((
        ("front",(2.19,-2.58,1.51),False),("rear",(2.12,2.73,1.65),False),("empty",(2.12,2.73,1.65),True))):
        cam=first
        if index:
            cam=first.copy()
            cam.data=first.data.copy()
            scene.collection.objects.link(cam)
        cam.name=f"{name.title()} inspection"
        cam.location=loc
        cam.data.ortho_scale=1.94
        cam.rotation_euler=(V((0,0,.319))-cam.location).to_track_quat("-Z","Y").to_euler()
        views.append((name,cam,empty))
    for ob in set(scene.objects)-prev:
        for coll in list(ob.users_collection):coll.objects.unlink(ob)
        studio.objects.link(ob)
    scene.render.resolution_x,scene.render.resolution_y=1000,720
    scene.render.resolution_percentage=100
    scene.view_settings.exposure=.43
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art"/f"{STEM}.blend"),compress=True)
    if qa:=os.getenv("THOMAS_GRAIN_QA"):
        scene.render.image_settings.file_format="JPEG"
        scene.render.image_settings.quality=91
        for name,cam,empty in views:
            scene.camera=cam
            load.hide_render=empty
            scene.render.filepath=str(Path(qa)/f"thomas-grain-{name}.jpg")
            bpy.ops.render.render(write_still=True)


if __name__=="__main__":
    make()

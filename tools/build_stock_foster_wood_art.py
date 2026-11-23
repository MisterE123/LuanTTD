#!/usr/bin/env python3
"""Original stock Foster Wood Truck #145 art; .42 scale, −Z nose, Y=0 tread."""
from copy import deepcopy
from math import cos, sin, tau
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
STEM="stock_foster_wood_truck"
COL={
    "Axle grey":"515d57","Frame":"343f38","Rubber":"252c2c","Tyre scuff":"4c534e","Hub":"61716c",
    "Nurled iron":"474e46","Rim":"a6ae9f","Roof dark":"384744",
    "Cab british blue":"3c6f7a","Cab deep blue":"355562","Cab shadow blue":"34505b",
    "Cab sheen":"5a8d92","Cab lifted ridge":"68999a","Cab pale alloy":"a6b1aa",
    "Cab pale sunshade":"7da5a3","Cab darker shade":"26414e","Cab iron blue":"4a6973",
    "Compact grille inset":"263636","Compact grille metal":"788685","Chromed bead":"bdc5b3",
    "Cab door seal":"2d4242","Ivory fleet band":"d1bf82","Ivory fleet shadow":"b29766",
    "Glass rim":"2d3b3c","Glass":"2b4c52","Glass glint":"7899a0","Glass rear shade":"3c5559",
    "Daylight window blue":"526e75","Metal sill":"5b6f6e","Warm headlamp":"f2dfa8",
    "Bright LED white":"e7d8a3","Tail light":"b95342","Signal amber":"ce9650",
    "Cab marker":"dcad65","Plate dark":"344c47","Deck oak":"8e704d","Deck pale timber":"b09766",
    "Deck shadow oak":"776045","Steel structural shade":"556a62","Steel stanchion paint":"638075",
    "Stanchion exposed joint":"829583","Black fastening":"414d45","Slate steel":"6b7a72",
    "Oily grey casting":"425452","Ratchet gold metal":"9c865c","Used timber burnt grey":"554335",
    "Ash grey bark":"726051","Oak rough furrows":"6d4d32","Oak narrow furrow":"57442f",
    "Split rust bark":"816044","Dark mossy bark":"495341","Paler sunfacing bark":"967651",
    "Fawn cambium":"a78354","Fresh quartered blonde wood":"dcad74","Growth ring honey":"bd8952",
    "Warm latewood rings":"96683f","Endgrain core":"c39660","Wood burn marks":"664a37",
    "Metal chain light":"9c9d87","Metal chain dark":"5c675b",
    "Gravel slate":"59635d","Lane marking":"e7c993","Rubber skid":"3c5558","Rear plate warm":"d9b87b",
}
assert len(COL)==64
P={c:i for i,c in enumerate(COL)}
w.P=road.P=P
r.COLORS[:]=COL.values()
AX=(-.497,.468)
R=.126
T=.222
BEDZ=(-.188,.756)
BUNKS=(-.152,.224,.642)


def face(m,label,tone,p):
    road.f(m,label,tone,p)


def chassis(m):
    for s in (-1,1):
        B(m,"Hot rolled longitudinal twin frame rails","Frame",s*.134,.012,.048,1.502,.138,.214,.012)
        B(m,"True contoured inner falling frame lip","Axle grey",s*.148,.017,.018,1.421,.182,.212,.003)
        B(m,"Distinct dry below-frame fuel saddle","Oily grey casting",s*.162,.167,.131,.316,.106,.207,.019)
        for y in (.055,.280):
            B(m,"Stamped fuel tank retainer bands","Metal sill",s*.169,y,.133,.014,.118,.211,.003)
        for z in AX:
            road.fender(m,"Curved deep Foster pressed steel splash guards",s*.241,z,R,R+.032,.091,"Cab iron blue")
            h=.157
            for k in range(3):
                B(m,"Rear and front layered leaf suspension springs","Slate steel",s*.145,z,.031,
                  .208-.023*k,h+k*.008,h+k*.008+.006,.003)
            B(m,"Independent wiped rubber rear mud apron","Rubber",s*.230,z+.126,.124,.027,.045,.211,.005)
        for y in (-.435,-.221,.311,.625):
            C(m,"Bright chassis permanent fasteners","Chromed bead",(s*.162,y,.177),.009,"x",-.004,.004,8)
    for z in (-.647,-.183,.170,.554,.698):
        B(m,"Ladder chassis cross joints","Axle grey",0,z,.332,.070,.139,.203,.010)
    B(m,"Independent driveline transmission case","Oily grey casting",0,-.342,.178,.217,.102,.211,.022)
    C(m,"Propshaft to rear section","Axle grey",(0,.111,.128),.017,"z",-.375,.333,10)
    C(m,"Waxed central rear differential","Oily grey casting",(0,.461,.124),.058,"x",-.077,.078,12)
    road.wheels(m,*AX,T,R,"Cab pale alloy",True)


def cab(m):
    def ring(z,width,floor,hinge,roof):
        return (z,[(-width*.83,floor),(width*.83,floor),(width,floor+.030),
          (width,hinge),(width*.945,roof-.037),(width*.768,roof),(-width*.768,roof),
          (-width*.945,roof-.037),(-width,hinge),(-width,floor+.030)])
    rows=(
        ring(-.786,.191,.221,.397,.461),ring(-.762,.224,.218,.429,.488),
        ring(-.731,.243,.211,.467,.550),ring(-.684,.257,.208,.516,.602),
        ring(-.624,.264,.205,.530,.660),ring(-.540,.264,.205,.541,.670),
        ring(-.271,.264,.205,.541,.670),ring(-.221,.251,.215,.517,.644),
        ring(-.192,.218,.228,.499,.613),
    )
    road.section_hull(m,"Contoured tall pressed steel Foster twin door cab",rows,
      ["Cab shadow blue","Cab deep blue","Cab british blue","Cab sheen","Cab lifted ridge",
       "Cab sheen","Cab lifted ridge","Cab sheen","Cab british blue","Cab deep blue"],"Cab british blue")
    shell=((-.745,.234,.530),(-.731,.243,.550),(-.684,.257,.602),
           (-.624,.264,.660),(-.607,.264,.662))
    for name,tone,marg,lift,rows2 in (
        ("Joined front windshield black rubber reveal","Glass rim",.002,.008,shell),
        ("Large paired Foster laminated curved front panes","Glass",.010,.018,shell[1:-1]),
        ("Windshield clear sky return band","Glass glint",.015,.020,((-.657,.260,.625),(-.638,.262,.646))),
    ):
        for (z0,a,h0),(z1,b,h1) in zip(rows2,rows2[1:]):
            for s in (-1,1):
                q=(s*.012,z0,h0+lift),(s*(a*.74-marg),z0,h0+lift-.006),(
                  s*(b*.74-marg),z1,h1+lift-.006),(s*.012,z1,h1+lift)
                face(m,name,tone,q[::s])
    rod(m,"Black center laminated pane divider","Glass rim",(0,-.741,.545),(0,-.613,.680),.009)
    for s in (-1,1):
        p=s*.041,-.727,.566
        q=s*.124,-.700,.596
        rod(m,"Twin parked drivers' angled wiper arms","Glass rim",p,q,.0036)
        rod(m,"Slender separate black wiper blade","Glass rim",q,(s*.158,-.682,.617),.0031)
        sx=s*.260
        B(m,"Flush inset pressed steel full size cab door","Cab door seal",sx,-.471,.021,.286,.282,.568,.013)
        B(m,"Shaped separate Foster cab door outer skin","Cab british blue",sx+s*.011,-.471,.015,.266,.298,.557,.012)
        road.panes(m,"Large rectangular chromed cab side drop glass",sx+s*.019,-.473,.238,.419,.553,"Cab door seal")
        B(m,"Quarter light vertical mullion on front doors","Cab pale alloy",s*.288,-.551,.006,.010,.433,.545,.002)
        B(m,"Required pair of visibly pressed steel door hinges","Cab deep blue",s*.276,-.594,.013,.025,.326,.389,.004)
        B(m,"Flush nickel release handle in an inset finger grip","Cab pale alloy",s*.284,-.368,.010,.047,.372,.389,.004)
        B(m,"Golden open grain fleet strip along door","Ivory fleet band",s*.272,-.459,.014,.280,.323,.341,.005)
        B(m,"Small aerodynamic roof marker lamp","Cab marker",s*.191,-.599,.036,.024,.656,.668,.004)
        B(m,"Twin checker tread doorstep","Metal sill",s*.235,-.279,.113,.145,.153,.173,.009)
        B(m,"Warm open raised step nosing","Cab pale alloy",s*.288,-.279,.013,.129,.159,.171,.003)
        for j in range(5):
            B(m,"Crosshatched real cab step pressings","Rubber skid",s*.259,-.330+j*.026,.059,.007,.169,.174,.001)
        rod(m,"Door-mounted large period wing mirror bracket","Cab iron blue",(s*.259,-.607,.526),(s*.287,-.626,.543),.006)
        B(m,"Original moulded upper wing mirror","Cab deep blue",s*.288,-.626,.037,.025,.506,.572,.009)
        B(m,"Actual rear-facing directional mirror lenses","Glass rear shade",s*.289,-.611,.029,.010,.519,.560,.004)
    B(m,"Bright front bumper whole wrap return","Cab iron blue",0,-.775,.492,.066,.159,.224,.019)
    B(m,"Visible broad rebated grille panel with intake slats","Compact grille inset",0,-.785,.244,.033,.252,.379,.012)
    for j in range(6):
        B(m,"Cast grille independent horizontal slats","Compact grille metal",0,-.805,.211,.009,
            .263+j*.018,.269+j*.018,.002)
    B(m,"Thin nickel grey upper air vent raised lintel","Chromed bead",0,-.785,.260,.014,.376,.390,.004)
    B(m,"Canted nose warm fleet stripe","Ivory fleet shadow",0,-.768,.357,.019,.403,.423,.004)
    for s in (-1,1):
        x=s*.176
        B(m,"Twin separate oblong heavy front headlamp housings","Cab darker shade",x,-.787,.114,.033,.249,.328,.010)
        B(m,"True forward-facing individually glazed headlamp reflectors","Warm headlamp",x-s*.014,-.807,
          .074,.010,.268,.310,.005)
        B(m,"Secondary front warm dipped beam","Bright LED white",x+s*.028,-.806,.016,.011,.269,.309,.003)
        B(m,"Wrapped original amber front corner winker","Signal amber",s*.211,-.789,.044,.014,.340,.365,.005)
    B(m,"Dark molded front registration plate fixing","Plate dark",0,-.809,.132,.011,.177,.203,.006)
    for x in (-.040,-.025,-.010,.004,.021,.035):
        B(m,"Separate geometric inset front registration marks","Cab pale alloy",x,-.815,.005,.004,
          .183,.196+abs(x)*.049,.001)
    B(m,"Recessed small rubber rear cab window surround","Glass rim",0,-.190,.316,.020,.445,.556,.011)
    B(m,"Driver cab bulkhead inset rear quarter glass","Glass rear shade",0,-.177,.287,.013,.456,.542,.008)
    B(m,"Wide roof crown forward flush escape vent","Cab pale sunshade",0,-.439,.175,.127,.665,.684,.012)
    B(m,"Black power intake just behind door","Rubber skid",-.180,-.188,.038,.048,.308,.520,.009)
    for j in range(4):
        B(m,"Black ribbed intake hoses","Oily grey casting",-.182,-.157,.042,.007,.450+j*.014,.455+j*.014,.002)


def bed(m):
    a,b=BEDZ
    B(m,"Long independent ladder stake-bed support","Steel structural shade",0,(a+b)/2,
      .436,b-a,.209,.255,.013)
    for index in range(10):
        x=(index-4.5)*.044
        tone=("Deck oak","Deck pale timber","Deck shadow oak","Deck oak","Deck oak")[index%5]
        B(m,"Individually laid longitudinal air-dried stake-deck boards",tone,x,.28,.042,.931,
          .254,.274,.003)
    for s in (-1,1):
        x=s*.112
        B(m,"Deep oak truss longitudinal timber saddle","Deck shadow oak",x,.275,.066,.889,.273,.304,.006)
        B(m,"Shaved oak support skid upper faces","Deck pale timber",x,.275,.058,.877,.302,.311,.005)
    for z in BUNKS:
        B(m,"Independent steel cross-bunk tubes with ends","Steel structural shade",0,z,.474,.069,.240,.299,.007)
        for s in (-1,1):
            x0=s*.224
            B(m,"Spring steel removable stake channel cradle socket","Black fastening",x0,z,
              .065,.065,.234,.344,.008)
            xx=s*.239
            shape0=[(xx-.018,.300),(xx+.018,.300),(xx+.022,.414),(xx+.022,.543),
                    (xx-.016,.543),(xx-.021,.414)]
            road.section_hull(m,"Actual folded heavy angled logging stakes",
                 [(z-.017,shape0),(z+.019,shape0)],"Steel stanchion paint")
            B(m,"Separate clipped low-wear silver stake heads","Stanchion exposed joint",s*.240,z,
              .038,.047,.538,.556,.006)
            C(m,"Through stake keeper bolt pressed flange","Ratchet gold metal",(s*.258,z,.322),
              .010,"x",-.005,.010,10)
            B(m,"Exposed lower welded shrinkshoe bracket","Slate steel",s*.242,z,.056,.072,.251,.299,.005)
    for x in (-.202,-.114,-.026,.061,.150,.205):
        rod(m,"Permanent separated forward cab timber guard verticals","Steel structural shade",
            (x,-.171,.260),(x,-.171,.515),.011)
    for h in (.285,.425,.516):
        B(m,"Permanent forward timber guard crossbars","Cab iron blue",0,-.171,.436,.043,h-.013,h+.013,.008)
    for z in (.036,.506):
        for s in (-1,1):
            B(m,"Fixed deck side ratchet mounting bracket","Black fastening",s*.239,z,.040,.067,.248,.330,.006)
            C(m,"Permanent double flange winding spool","Oily grey casting",(s*.256,z,.289),.023,"x",-.007,.007,14)
            C(m,"Independent bronze ratchet teeth and winding pivot","Ratchet gold metal",
                (s*.262,z,.289),.014,"x",-.006,.005,12)
    B(m,"Foster steel rear load apron protecting oak edges","Cab deep blue",0,.753,.488,.050,.201,.267,.010)
    B(m,"Replaceable rear white timber wear lip","Deck pale timber",0,.776,.425,.019,.252,.270,.003)
    B(m,"Rear long inset bumper bridge and towing member","Steel structural shade",0,.752,.490,.048,.126,.179,.015)
    for s in (-1,1):
        x=s*.181
        B(m,"Separate bolted Foster twin rear lamp clusters","Plate dark",x,.773,.104,.036,.161,.236,.009)
        for i,name in enumerate(("Tail light","Signal amber","Cab pale alloy")):
            B(m,"Raised rear rake red amber and white lenses",name,x+s*(i-1)*.024,.796,
                .021,.010,.182,.219,.005)
        rod(m,"Permanent rear tow eyes with steel ears","Stanchion exposed joint",
             (s*.129,.767,.159),(s*.129,.789,.136),.009)
    B(m,"Individual central rear fleet plate recession","Plate dark",0,.778,.130,.021,.152,.197,.005)
    B(m,"Warm rear fleet plate without branding","Rear plate warm",0,.794,.111,.012,.159,.192,.003)
    for x in (-.041,-.025,-.010,.009,.023,.039):
        B(m,"Original raised plate typography segments","Plate dark",x,.801,.005,.005,.165,.182,.001)


def log(m,ihead,x,z0,z1,h,radius,rng):
    """Tapered long-grain bark solid with independently seeded cut ends."""
    n=12
    a0=rng.uniform(-.16,.15)
    sin_noise=[rng.uniform(.91,1.07) for _ in range(n)]
    bend_x=rng.uniform(-.014,.013)
    bend_h=rng.uniform(-.006,.006)
    silhouette=[]
    knots=[rng.randint(0,n-1) for _ in range(2)]
    for t in (0.,.19,.44,.69,1.):
        zz=z0+(z1-z0)*t
        width=radius*(1-.12*t+.036*sin(t*tau*.5))
        t0=zz in (z0,z1)
        ring=[]
        for i in range(n):
            angle=a0+i*tau/n
            mod=width*(sin_noise[i]+(.035 if i in knots else -.009)*sin(t*tau*1.15))
            ring.append((x+bend_x*t+mod*cos(angle),zz+(mod*.12*sin(angle-.1) if t0 else 0),
                        h+bend_h*sin(t*tau*.5)+mod*sin(angle)))
        silhouette.append(ring)
    fk=f"Foster removable round timber {ihead:02}"
    bark=("Ash grey bark","Oak rough furrows","Oak narrow furrow","Split rust bark",
          "Dark mossy bark","Paler sunfacing bark","Used timber burnt grey")
    tones=[rng.choice(bark) for _ in range(n)]
    for j,(a,b) in enumerate(zip(silhouette,silhouette[1:])):
        for i in range(n):
            k=(i+1)%n
            col=tones[i] if (j+i)%8 else rng.choice(bark)
            face(m,fk,col,(a[i],b[i],b[k],a[k]))
    for end,outer,axisco in ((-1,silhouette[0],z0),(1,silhouette[-1],z1)):
        cx=x+(bend_x if end>0 else 0)+radius*.08
        ch=h+radius*rng.uniform(-.07,.08)
        rings=[outer]
        for j,q in enumerate((.90,.79,.64,.59,.42,.36,.19)):
            ring=[]
            for a,z,b in outer:
                ring.append((cx+(a-cx)*q,axisco+(z-axisco)*q+end*.0015*(1-q),ch+(b-ch)*q))
            rings.append(ring)
        for tone,(a,b) in zip(("Fawn cambium","Fresh quartered blonde wood","Growth ring honey",
                              "Warm latewood rings","Fresh quartered blonde wood","Growth ring honey",
                              "Endgrain core"),zip(rings,rings[1:])):
            for i in range(n):
                j=(i+1)%n
                face(m,fk,tone,(a[i],a[j],b[j],b[i])[::-end])
        face(m,fk,"Endgrain core",rings[-1][::-end])
        checks=rng.sample(range(n),2)
        for i in checks:
            a=V(rings[1][i]);b=V(rings[4][(i+1)%n]);c=V(rings[5][(i+1)%n])
            lift=V((0,end*.002,0))
            pts=(a+lift,b+lift,c+lift+V((.001,0,.003)),b+lift+V((.003,0,-.001)))
            face(m,"Irregular seasoning splits across distinct log ends","Wood burn marks",pts[::-end])


def band(m,label,a,b):
    a,b=V(a),V(b)
    v=(b-a).normalized()
    normal=V((0,1,0)).cross(v)
    width=V((0,.0094,0))
    thickness=normal*.0032
    rings=[(p-width-thickness,p+width-thickness,p+width+thickness,p-width+thickness) for p in (a,b)]
    a,b=rings
    face(m,label,"Metal chain dark",a[::-1])
    face(m,label,"Metal chain dark",b)
    for i in range(4):
        j=(i+1)%4
        face(m,label,"Metal chain light" if i==2 else "Metal chain dark",(a[i],a[j],b[j],b[i]))


def cargo(m):
    rng=Random(1451974)
    n=0
    for zs,ze in ((-.153,.222),(.255,.742)):
        for x,h,rr in (
            (-.156,.352,.044),(-.064,.358,.049),(.035,.361,.053),(.135,.356,.047),
            (-.108,.427,.047),(-.010,.435,.050),(.089,.434,.053),(.166,.419,.038),
            (-.057,.501,.044),(.034,.512,.045),(.116,.498,.038),(-.013,.560,.034),
        ):
            n+=1
            log(m,n,x,zs+rng.uniform(-.010,.016),ze-rng.uniform(.0,.033),h,rr,rng)
    for z in (.036,.506):
        contour=((-.253,.299),(-.211,.391),(-.183,.447),(-.146,.480),(-.113,.518),
                 (-.069,.542),(-.043,.580),(-.016,.595),(.018,.581),(.061,.551),
                 (.103,.536),(.149,.513),(.184,.464),(.218,.392),(.252,.301))
        p=[(x,z,h) for x,h in contour]
        for a,b in zip(p,p[1:]):
            band(m,"Loaded-only twin galvanised timber binder straps",a,b)
        for s in (-1,1):
            rod(m,"Tensioned hook linkage from strap to winding pulley","Metal chain light",
                (s*.252,z,.302),(s*.260,z,.289),.006)
            B(m,"Separate raised safety hook closing cleat","Metal chain light",s*.242,z,.021,.023,.320,.342,.003)


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
    scene.name="LuanTTD | Foster Wood Truck #145"
    scene["source_version"]="OpenTTD 16.0-RC1"
    scene["stock_engine_id"]=145
    scene["native_scale"]=.42
    scene["tread_datum"]="Y=0 native; heading −Z"
    m=r.Mesh(r.terrain_height(0))
    chassis(m)
    cab(m)
    bed(m)
    payload=r.Mesh(r.terrain_height(0))
    cargo(payload)
    full=deepcopy(m)
    for group,faces in payload.parts.items():
        for points,color in faces:
            full.tri(group,color,[payload.vertices[group][i] for i in points])
    mats=r.materials()
    for name,mat in zip(COL,mats):
        mat.name=name
        p=mat.node_tree.nodes.get("Principled BSDF")
        p.inputs["Roughness"].default_value=.34 if name.startswith("Glass") else .65
        if name.startswith(("Metal","Chromed","Ratchet")):
            p.inputs["Metallic"].default_value=.35
    base=bpy.data.collections.new("01 • Foster editable truck and permanent stake bed")
    top=bpy.data.collections.new("02 • Toggle load: separate 24 stems plus tie-downs")
    for c in (base,top):scene.collection.children.link(c)
    r.to_blender(m,base,mats)
    r.to_blender(payload,top,mats)
    for label,body in (("",m),("_loaded",full)):
        f=ROOT/"mods/luanttd_core/models"/f"bl_{STEM}{label}.obj"
        r.export_obj(f,w.local_obj(body))
        lines=f.read_text().splitlines()
        lines[0]="# Original Foster road timber lorry; regenerate with tools/build_stock_foster_wood_art.py"
        f.write_text("\n".join(lines)+"\n")
    before=set(scene.objects)
    road.studio(scene)
    studio=bpy.data.collections.new("90 • Studio inspection only (not exported)")
    scene.collection.children.link(studio)
    camera=scene.camera
    views=(("front",camera,(2.08,-2.55,1.28),False),
           ("rear",None,(2.03,2.75,1.58),False),
           ("empty",None,(2.05,2.59,1.465),True))
    named=[]
    for name,c,point,empty in views:
        if c is None:
            c=camera.copy()
            c.data=camera.data.copy()
            scene.collection.objects.link(c)
        c.location=point
        c.rotation_euler=(V((0,0,.319))-c.location).to_track_quat("-Z","Y").to_euler()
        c.data.ortho_scale=1.94
        c.name=f"{name.title()} art inspection"
        named.append((name,c,empty))
    for ob in set(scene.objects)-before:
        for layer in list(ob.users_collection):layer.objects.unlink(ob)
        studio.objects.link(ob)
    scene.render.resolution_x,scene.render.resolution_y=1000,720
    scene.render.resolution_percentage=100
    scene.view_settings.exposure=.53
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art"/f"{STEM}.blend"),compress=True)
    if qa:=os.getenv("FOSTER_WOOD_QA"):
        scene.render.image_settings.file_format="JPEG"
        scene.render.image_settings.quality=91
        for name,c,empty in named:
            scene.camera=c
            top.hide_render=empty
            scene.render.filepath=str(Path(qa)/f"foster-wood-{name}.jpg")
            bpy.ops.render.render(write_still=True)


if __name__=="__main__":
    make()

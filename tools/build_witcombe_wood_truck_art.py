#!/usr/bin/env python3
"""Author the original two-axle Witcombe wood lorry for OpenTTD 14.1.

  blender -b -t 4 --python-exit-code 1 --python tools/build_witcombe_wood_truck_art.py

Set WITCOMBE_WOOD_RENDER=/path/scene.png for the editable-model render.
OpenTTD engine 144, road row 28/image index 7. Independent graphic
reference: OpenGFX first wood truck rows (3348 empty, 3396 loaded).
Blue company-toned short cab, long exposed stake bed, two load packets.
No imported sprite art. Runtime: local -Z nose, h=0 wheel contact, 10 OBJ
units per native node at visual_size 1. Use .42 uniformly.
"""
from math import cos,pi,sin,tau
import os
from pathlib import Path
from random import Random
import struct
import sys
import zlib

import bpy
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_balogh_goods_truck_art as G
S,R=G.soft,G.r
ROOT=R.ROOT
PREFIX="bl_witcombe_wood_truck"
PALETTE={
    "Cobalt steel cab":"497d9c","Lighter azure pressed steel":"6197b4","Deep blue cab trim":"385b72",
    "Soft horizon sheen":"7ca8b7","Thin faded cab band":"cfbf9b","Dark luggage enamel":"3d5c68",
    "Cab seal shadow":"303b40","Windscreen tinted slate":"354d54","Windscreen glint":"789da3",
    "Shadowed grille close":"30363a","Nickel grille rails":"a7aaa0","Pressed grille steel":"738680",
    "Chassis iron":"434b4a","Gear-cast dark":"303834","Used dry nickel":"85928a",
    "Road tyre dark":"303436","Ground contact tread":"41474a","Disced blue hub":"64828a",
    "Cable grease":"554d40","Clear warm headlamps":"fae5ae","Red rear brake lens":"ba5148","Cured road amber":"d79a57",
    "Deck warm oak":"836747","Deck dry oak":"937758","Deck worn oak":"a28560",
    "Steel bunk cradle":"747d72","Flank load strap iron":"706355","Wood cracked end grain":"a37c50",
    "Fresh cut pale sapwood":"d6a470","Golden lignin":"bd8955","Bark ochre edge":"77533d",
    "Bark charcoal furrow":"503c32","Bark dark brown":"624d3c","Bark foliage brown":"8e6a48",
    "Sun warmed bark splinters":"ad8054","Timber ink lot stamp":"745641","Binder bronze":"b49a74",
    "Tension grey chain":"829086","Tension link dark":"5b6862","Company pale type":"dfd7b9",
    "Viewing cobbled dusty earth":"a59173","Viewing road stripes":"f1dcaa"
}
P={n:i for i,n in enumerate(PALETTE)}
G.P=S.P=P
R.COLORS[:]=PALETTE.values()
B,T,C,bar=S.slab,S.circular,G.tube,G.bar
F=G.face
AXLES=(-.470,.479)
WHEEL_X=.223
WHEEL_R=.107

def mesh():
    return R.Mesh(R.terrain_height(0))

def chassis(m):
    B(m,"Genuine long timber lorry ladder chassis","Chassis iron",0,.024,.375,1.414,.119,.193,.022)
    C(m,"Heavy crankcase sump behind radiator","Gear-cast dark",(0,-.594,.139),(0,-.287,.129),.091,.073,14)
    for s in (-1,1):
        B(m,"Deep C-channel chassis spars","Pressed grille steel",s*.164,.017,.037,1.388,.154,.199,.005)
        for z in (-.510,-.141,.243,.498,.615):
            B(m,"Gauge cast rail bolts","Used dry nickel",s*.185,z,.016,.025,.167,.185,.003)
        B(m,"Front cab running toe board","Deep blue cab trim",s*.248,-.329,.085,.224,.130,.160,.009)
        for z in (-.402,-.367,-.324,-.273):
            B(m,"Pressed cab tread anti-slip grooves","Ground contact tread",s*.246,z,.053,.011,.159,.166,.002)
        B(m,"Fuel saddle under platform","Gear-cast dark",s*.181,.186,.104,.285,.108,.212,.025)
        for z in (.097,.278):
            B(m,"Fuel tank painted bracing straps","Used dry nickel",s*.184,z,.108,.018,.124,.216,.004)
    C(m,"Transmission driveshaft","Used dry nickel",(0,-.352,.131),(0,.389,.115),.021,.018,11)
    C(m,"Rounded rear transfer differential","Chassis iron",(0,.378,.12),(0,.538,.120),.083,.071,14)
    C(m,"Long sprung muffler and side exhaust","Gear-cast dark",(.139,-.398,.102),(.147,.572,.095),.013,.011,10)
    C(m,"Exhaust exit pipe pale hot edge","Used dry nickel",(.147,.572,.095),(.194,.654,.076),.011,.009,8)

def wheels(m):
    for idx,z in enumerate(AXLES):
        T(m,"Straight live road axle with cast hubs","Chassis iron",(0,z,WHEEL_R),.019,"x",-.231,.231,14)
        for s in (-1,1):
            x=s*WHEEL_X
            name="L" if s<0 else "R"
            G.axle_tube(m,"Ground contact tyre "+name,"Ground contact tread",[
                (-.037,.076),(-.036,.099),(-.030,WHEEL_R),(.028,WHEEL_R),
                (.036,.097),(.038,.078),(-.037,.076)],(x,z,WHEEL_R))
            T(m,"Dark shaped flexible tyre shoulder","Road tyre dark",(x+s*.031,z,WHEEL_R),.084,"x",-.010,.010,24)
            T(m,"Witcombe raised pressed steel dished rim","Disced blue hub",(x+s*.042,z,WHEEL_R),.054,"x",-.009,.009,21)
            T(m,"Fine spun nickel road wheel grease cap","Nickel grille rails",(x+s*.053,z,WHEEL_R),.026,"x",-.007,.007,18)
            for k in range(6):
                a=k*tau/6
                T(m,"Hex-headed hub lugs","Binder bronze",(x+s*.052,z+.039*cos(a),WHEEL_R+.039*sin(a)),
                   .0053,"x",-.004,.004,7)
            if idx==1:
                T(m,"Pair of visible inboard rear load tyres","Road tyre dark",(x-s*.059,z,WHEEL_R),
                   .098,"x",-.024,.024,20)
            # Pressed moulder has a real rolled fender profile, with rubber
            # envelope clear underneath, not merely colored wheel circles.
            old=None
            for k in range(17):
                a=pi*k/16
                p=[(s*xx,z+r*cos(a),WHEEL_R+r*sin(a)) for xx,r in (
                    (.182,.114),(.271,.115),(.291,.141),(.240,.149),(.181,.145),(.182,.114))]
                if old is not None:
                    for i,c in enumerate(("Deep blue cab trim","Cobalt steel cab","Lighter azure pressed steel",
                                          "Cobalt steel cab","Deep blue cab trim")):
                        co=(old[i],p[i],p[i+1],old[i+1])
                        F(m,"Separately rolled steel mudguards",c,co if s>0 else co[::-1])
                old=p
            for h in (.143,.152,.163):
                B(m,"Rear and front suspension leaf laminations","Used dry nickel",s*.170,z,.040,.190-(h-.142)*1.08,
                  h,h+.004,.002)
            B(m,"Stiff lorry rubber mud flap","Road tyre dark",s*.227,z+.128,.139,.020,.035,.210,.009)

def cab(m):
    # Period short forward-control shape, blue planar-cheeked cab with a
    # shallower, narrower rounded nose than the covered Balogh lorry.
    cb=G.rolled
    G.panel(m,"Tall rolled Witcombe cab sheetwork, compact bonnet",[
      (-.644,cb(.211,.181,.502,.573)),
      (-.582,cb(.243,.181,.550,.617)),
      (-.509,cb(.244,.181,.570,.638)),
      (-.346,cb(.244,.182,.569,.635)),
      (-.245,cb(.237,.181,.544,.601)),
      (-.192,cb(.213,.183,.514,.554)),
    ],"Cobalt steel cab",["Deep blue cab trim"]*3+["Cobalt steel cab"]*2+
      ["Lighter azure pressed steel"]*5+["Cobalt steel cab"]*3)
    G.panel(m,"Separate stub bonnet pressed nose shoulder",[
      (-.743,cb(.116,.175,.335,.354)),(-.714,cb(.171,.174,.361,.379)),
      (-.671,cb(.206,.186,.404,.419)),(-.621,cb(.213,.189,.430,.445)),
      (-.599,cb(.214,.189,.432,.451)),
    ],"Cobalt steel cab",["Deep blue cab trim","Deep blue cab trim","Cobalt steel cab",
      "Lighter azure pressed steel","Soft horizon sheen","Soft horizon sheen"])
    B(m,"Metal dark blue radiator louver bezel","Deep blue cab trim",0,-.752,.246,.047,.176,.370,.021)
    B(m,"Chromed short Witcombe radiator surround","Nickel grille rails",0,-.776,.213,.026,.196,.345,.016)
    B(m,"Visible recessed black radiator core","Shadowed grille close",0,-.792,.183,.018,.206,.333,.013)
    for j in range(8):
        h=.216+j*.013
        B(m,"Horizontal grille sound wave fins","Pressed grille steel",0,-.803,.171-j*.001,.008,h,h+.006,.002)
    B(m,"Cast rail-sized bumper and mounting bolts","Used dry nickel",0,-.761,.440,.077,.107,.149,.013)
    for s in (-1,1):
        T(m,"Two pressed headlamp steel bezels","Pressed grille steel",(s*.179,-.734,.274),.052,"z",-.027,.007,20)
        T(m,"Individual warm headlamp lenses","Clear warm headlamps",(s*.179,-.760,.273),.044,"z",-.011,.003,23)
        for dy in (-.014,.0,.017):
            B(m,"Clear lamp ground fluting","Thin faded cab band",s*.177,-.771,.008,.003,.271+dy,.283+dy,.001)
        T(m,"Front quarter independently orange amber flasher","Cured road amber",(s*.222,-.731,.213),.020,"z",-.014,.003,14)
        x=s*.249
        B(m,"Pressed side cab door seam","Deep blue cab trim",x,-.417,.012,.259,.183,.535,.009)
        B(m,"Visible coachwork blue side inside shadow seam","Cobalt steel cab",s*.256,-.415,.011,.234,.196,.479,.011)
        B(m,"Separate horizontal ivory door paint","Thin faded cab band",s*.261,-.413,.006,.218,.306,.326,.003)
        B(m,"Raised pressed side window weather-strip","Cab seal shadow",s*.256,-.407,.013,.196,.446,.555,.013)
        B(m,"Deep-set side window actual glass relief","Windscreen tinted slate",s*.263,-.416,.008,.174,.455,.548,.008)
        B(m,"Horizon reflected in individual side glass","Windscreen glint",s*.268,-.415,.004,.150,.519,.536,.003)
        B(m,"Raised quarter windshield divider","Nickel grille rails",s*.268,-.442,.005,.011,.458,.548,.002)
        B(m,"Cab door nickel handle and latch","Nickel grille rails",s*.267,-.354,.012,.054,.397,.408,.004)
        for z in (-.508,-.332):
            B(m,"Cab external wrought-hinges under doors","Pressed grille steel",s*.263,z,.010,.019,.224,.260,.003)
        C(m,"Swan-neck side mirror support","Nickel grille rails",(s*.233,-.540,.477),(s*.279,-.565,.514),.007,.006,6)
        B(m,"Offside pilot mirror oval narrow mount","Dark luggage enamel",s*.287,-.568,.038,.029,.492,.543,.008)
        B(m,"Dull light fluting of mirror reflector","Nickel grille rails",s*.287,-.551,.029,.008,.496,.539,.006)
        # Two separate convex-ish windscreen glass planes lean under roof.
        xx=s*.107
        q=[(xx-.098,-.670,.428),(xx+.098,-.670,.428),
           (xx+.090,-.652,.558),(xx-.090,-.652,.558)]
        F(m,"Split front windshield rubber surrounds","Cab seal shadow",q)
        mid=Vector((xx,-.661,.493))
        inner=[tuple(mid+(Vector(p)-mid)*.86+Vector((0,-.002,0))) for p in q]
        F(m,"Visible two independent glazed windshield panels","Windscreen tinted slate",inner)
        B(m,"Rubbed smoky windshield glint line","Windscreen glint",xx,-.660,.147,.004,.524,.540,.003)
        C(m,"Individual spring wiper assembly","Chassis iron",(xx-.041,-.674,.439),(xx+.052,-.670,.454),.0045,.003,6)
        for j in range(6):
            B(m,"Short hood six stamped side louvers","Windscreen tinted slate",s*(.166+j*.007),-.709+j*.016,
              .007,.007,.279,.337,.0015)
    B(m,"Front dark horizontal registration plate","Dark luggage enamel",0,-.804,.152,.013,.137,.174,.008)
    B(m,"Pronounced pressed center rail of windscreen","Lighter azure pressed steel",0,-.648,.019,.037,.424,.557,.006)
    B(m,"Rear cab inspection window rubber","Cab seal shadow",0,-.186,.271,.020,.430,.524,.009)
    B(m,"Rear cab inspection window gloss","Windscreen tinted slate",0,-.176,.250,.016,.440,.512,.008)
    for side in (-1,1):
        B(m,"Rust-worn cab top signal lamp housing","Deep blue cab trim",side*.072,-.479,.040,.041,.614,.648,.009)
        T(m,"Small recessed cab roof amber glass","Cured road amber",(side*.072,-.500,.630),.011,"z",-.008,.003,12)

def bed(m):
    # Permanent longitudinal bed is a real vintage timber platform, with
    # visible planks between three retaining stake pairs and transverse cradles.
    B(m,"Steel longitudinal timber cradle frame","Steel bunk cradle",0,.261,.480,.960,.193,.240,.013)
    for s in (-1,1):
        B(m,"Long hardwood outer timber bed rail","Deck warm oak",s*.232,.268,.035,.960,.225,.307,.009)
        B(m,"Continuous long timber rub strips","Deck worn oak",s*.250,.266,.012,.923,.257,.280,.004)
        for j in range(8):
            z=-.152+j*.118
            B(m,"Rust-burnished bed side bolt heads","Used dry nickel",s*.257,z,.008,.010,.270,.281,.002)
    for i in range(8):
        x=(i-3.5)*.052
        B(m,"Individual full-length hardwood deck boards",("Deck dry oak","Deck worn oak","Deck warm oak")[i%3],
          x,.267,.050,.939,.230,.271,.005)
        for j in range(7):
            z=-.164+j*.128
            B(m,"Discrete plank knot rubbed finish","Wood cracked end grain",x+.007*((j%3)-1),z,.009,.046,.2708,.273,.002)
    for z in (-.165,.183,.540,.688):
        B(m,"Painted solid supporting load cross brace","Steel bunk cradle",0,z,.495,.046,.198,.233,.006)
        for s in (-1,1):
            B(m,"Mitered timber cradle gusset tabs","Used dry nickel",s*.194,z,.089,.060,.188,.222,.008)
    for i,z in enumerate((-.135,.244,.623)):
        B(m,"Three exposed cross bunk saddles over worn deck","Deck dry oak",0,z,.449,.073,.260,.310,.007)
        for s in (-1,1):
            x=s*(.241 if i!=1 else .244)
            B(m,"Cast lift-out bunk socket","Gear-cast dark",x,z,.048,.069,.230,.329,.007)
            # Forged leaning stakes maintain a visible open chassis behind cab.
            bar(m,"Permanent blue-slate log stakes","Steel bunk cradle",
                (x,z,.289),(s*.248,z+.009,.531 if i!=1 else .527),.028,.035)
            B(m,"Dull steel stake end shoe and pin","Used dry nickel",s*.249,z+.009,.038,.044,.508,.543,.006)
            T(m,"Visible removable stake shaft keeper bolt","Binder bronze",(x+s*.019,z,.307),.011,"x",-.008,.008,9)
            if i!=0:
                B(m,"Fixed winch plate inner bearing","Flank load strap iron",s*.259,z,.014,.074,.301,.392,.008)
                T(m,"Exposed log cinch low gear spindle","Binder bronze",(s*.263,z,.354),.022,"x",-.007,.008,12)
                T(m,"Permanently mounted little winding cap","Tension grey chain",(s*.271,z,.354),.014,"x",-.003,.005,12)
    B(m,"Head rack protecting rear of the cab","Steel bunk cradle",0,-.181,.440,.044,.257,.475,.013)
    for x in (-.138,-.046,.046,.138):
        B(m,"Cabward head-rack open steel upright","Deep blue cab trim",x,-.182,.028,.053,.282,.493,.004)
    B(m,"Blue cargo head-rack upper pinned tube","Deep blue cab trim",0,-.181,.470,.046,.473,.501,.008)
    B(m,"Broad scored plank rear bed facing","Deck warm oak",0,.751,.464,.034,.209,.304,.009)
    B(m,"Separate tail oak outer wear rail","Deck worn oak",0,.770,.451,.019,.263,.280,.004)
    for s in (-1,1):
        B(m,"Rear independent lamp bracket on bed","Gear-cast dark",s*.204,.726,.091,.045,.156,.236,.007)
        T(m,"Sector glass rear hitch tail lamp lenses","Red rear brake lens",(s*.215,.752,.212),.022,"z",-.002,.008,16)
        T(m,"Rear separate road amber reflector","Cured road amber",(s*.167,.754,.190),.011,"z",-.004,.009,11)
        B(m,"Visible rear bed hinge link and hardware","Used dry nickel",s*.126,.768,.027,.024,.229,.287,.005)
    B(m,"Shaped two tow-eye bumper rear crossbar","Chassis iron",0,.752,.444,.033,.112,.158,.011)
    T(m,"Central towing clevis bolt","Nickel grille rails",(0,.764,.122),.023,"z",-.001,.017,12)
    B(m,"Rear individual blue license number plate frame","Dark luggage enamel",0,.764,.135,.026,.177,.216,.008)

def numbers(m,word,h,z,reverse=False):
    glyph={
      "1":("010","110","010","010","111"),
      "4":("101","101","111","001","001"),
      "W":("10001","10001","10101","11011","01010"),
      " ":("000","000","000","000","000"),
    }
    step=.0041
    widths=[len(glyph[k][0])+1 for k in word]
    start=-.5*(sum(widths)-1)*step
    for k,w in zip(word,widths):
        for j,row in enumerate(glyph[k]):
            y=h+.5*len(row)*step-j*step
            for i,pixel in enumerate(row):
                if pixel!="1":continue
                x=start+i*step
                if reverse:x=-x-step
                rgba=[(x,z,y-step),(x+step,z,y-step),(x+step,z,y),(x,z,y)]
                F(m,"Raised Witcombe small stamped plate identity","Company pale type",
                  rgba[::-1] if reverse else rgba)
        start+=w*step

def log(m,n,xc,y0,y1,h0,radius,slant,rng):
    # Exact non-repeated cross sections, knot traces, uneven splits,
    # different sapwood/heartwood lengths and real shallow endgrain annuli.
    N=12
    offsets=[rng.uniform(.91,1.08) for _ in range(N)]
    a_ph=rng.uniform(-.051,.052)
    profile=[]
    for t in (0,.12,.43,.78,1.):
        y=y0+(y1-y0)*t
        x=xc+slant*t
        h=h0+.008*sin(pi*t+1)
        rr=radius*(1.-.10*t+.045*sin(pi*t))
        ring=[]
        for j in range(N):
            q=tau*j/N+a_ph
            off=offsets[j]*rng.uniform(.97,1.033)
            p=(x+rr*off*cos(q),y+(sin(q)*.003 if t in (0,1) else 0),h+rr*off*sin(q))
            ring.append(p)
        profile.append(ring)
    bark=("Bark ochre edge","Bark foliage brown","Bark dark brown","Bark charcoal furrow",
          "Bark foliage brown","Bark ochre edge","Sun warmed bark splinters")
    assignment=[rng.randint(0,len(bark)-1) for _ in range(N)]
    for l,(a,b) in enumerate(zip(profile,profile[1:])):
        for i in range(N):
            j=(i+1)%N
            color=bark[(assignment[i]+(1 if (l+i)%8==0 else 0))%len(bark)]
            F(m,"Real separate tapered timber bark solid · "+n,color,(a[i],b[i],b[j],a[j]))
    for e in (0,1):
        rim=profile[-1 if e else 0]
        y=y1 if e else y0
        c=(xc+slant*e+radius*.065,y,h0+.008*sin(pi*e+1)-radius*.032)
        grades=[rim]
        for t in (.92,.79,.739,.520,.476,.231):
            ring=[]
            for xx,yy,hh in rim:
                ring.append((c[0]+(xx-c[0])*t,
                  y+(.0012 if e else -.0012)*(1-t),c[2]+(hh-c[2])*t))
            grades.append(ring)
        for l,(a,b) in enumerate(zip(grades,grades[1:])):
            mat=("Bark charcoal furrow","Fresh cut pale sapwood","Golden lignin","Fresh cut pale sapwood",
                 "Golden lignin","Fresh cut pale sapwood")[l]
            for i in range(N):
                j=(i+1)%N
                p=(a[i],a[j],b[j],b[i])
                F(m,"Cut endgrain annular growth rings · "+n,mat,p[::-1] if e else p)
        p=grades[-1]
        F(m,"Round cut timber heartwood center · "+n,"Fresh cut pale sapwood",p[::-1] if e else p)
        for i,idx in enumerate(rng.sample(range(N),2)):
            va=Vector(grades[1][idx])
            vb=Vector(grades[rng.choice((3,4,5))][(idx+1)%N])
            dep=(.001 if e else -.001)
            va.y+=dep;vb.y+=dep
            d=Vector((.003,0,.002))
            p=(tuple(va),tuple(vb),tuple(vb+d),tuple(va+d*.35))
            F(m,"Split saw checks across log ends","Timber ink lot stamp",p if e else p[::-1])

def loaded(m):
    rng=Random(1441950)
    # The stock profile has two visually separate bundles. Continuous longer
    # logs run underneath, but each upper stack has distinctly cut ends,
    # separate diameters and its own front and rear securement.
    for i,(x,r) in enumerate(((-.136,.054),(-.037,.055),(.058,.049),(.140,.049))):
        log(m,f"lower long stem {i+1}",x,-.145+rng.uniform(-.021,.025),.718-rng.uniform(.0,.04),
            .306+r*.98,r,rng.uniform(-.010,.011),rng)
    for j,(z0,z1) in enumerate(((-.131,.254),(.271,.716)),1):
        for i,(x,r,h) in enumerate(((-.104,.053,.444),(-.015,.057,.437),(.082,.045,.446),
                                    (-.050,.046,.533),(.035,.045,.530))):
            log(m,f"bundle {j} timber {i+1}",x,z0+rng.uniform(-.021,.025),z1-rng.uniform(.0,.049),
                h,r,rng.uniform(-.014,.012),rng)
    for j,z in enumerate((.068,.551),1):
        # Load is properly held by steel strap over both exposed log packets.
        # Empty and full share the permanent ladder hardware under the bunk.
        pts=[(-.245,z,.347),(-.206,z,.429),(-.151,z,.494),(-.100,z,.552),
             (-.048,z,.581),(.037,z,.580),(.109,z,.536),(.166,z,.485),
             (.210,z,.427),(.243,z,.360)]
        for a,b in zip(pts,pts[1:]):
            bar(m,f"Separate load-only cinch band {j}","Tension link dark" if a[0]<0 else "Tension grey chain",a,b,.010,.013)
        for s in (-1,1):
            C(m,"Load-only tightening link on chain","Tension grey chain",
              (s*.223,z,.434),(s*.242,z,.349),.008,.006,8)
            p=(s*.243,z,.352)
            T(m,"Bronzed ratchet link loop","Binder bronze",p,.012,"x",-.004,.004,10)

def make(full=False):
    m=mesh();chassis(m);wheels(m);cab(m);bed(m)
    numbers(m,"W 144",.152,-.812)
    numbers(m,"W 144",.193,.778,True)
    if full:loaded(m)
    return m

def atlas():
    def chunk(tag,data):
        return struct.pack(">I",len(data))+tag+data+struct.pack(">I",zlib.crc32(tag+data))
    row=b"".join(bytes.fromhex(v)*8 for v in PALETTE.values())
    p=R.TEXTURES/(PREFIX+"_atlas.png")
    p.write_bytes(b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",len(PALETTE)*8,8,8,2,0,0,0))
                  +chunk(b"IDAT",zlib.compress((b"\0"+row)*8))+chunk(b"IEND",b""))

def view(mats,body,cargo,dest):
    sc=bpy.context.scene
    for x,z,angle,filled in ((-.62,.18,0,False),(.63,.17,pi,True),(.63,-1.66,0,True),(-.62,-1.66,pi,False)):
        o=R.instance(sc,body,x,z);o.rotation_euler.z=angle
        if filled:
            o=R.instance(sc,cargo,x,z);o.rotation_euler.z=angle
    bpy.ops.mesh.primitive_plane_add(size=100,location=(0,0,-.006))
    mat=mats[P["Viewing cobbled dusty earth"]]
    bpy.context.object.data.materials.append(mat)
    bpy.ops.object.camera_add(location=(2.81,-4.78,3.69))
    ob=bpy.context.object
    ob.rotation_euler=(Vector((0,-.75,.31))-ob.location).to_track_quat("-Z","Y").to_euler()
    ob.data.type="ORTHO";ob.data.ortho_scale=4.40;sc.camera=ob
    sc.render.engine="BLENDER_WORKBENCH"
    sc.render.resolution_x,sc.render.resolution_y=1450,1020
    sc.display.shading.light="STUDIO"
    sc.display.shading.color_type="MATERIAL"
    sc.display.shading.show_shadows=True
    sc.display.shading.show_cavity=True
    sc.display.shading.cavity_type="BOTH"
    sc.display.shading.cavity_ridge_factor=1.12
    sc.display.shading.background_type="WORLD"
    sc.world=bpy.data.worlds.new("Timber yard low spring haze")
    sc.world.color=(.156,.197,.238)
    sc.view_settings.view_transform="Standard"
    sc.render.filepath=dest
    bpy.ops.render.render(write_still=True)

def publish():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    m=make();full=make(True);cargo=mesh();loaded(cargo)
    mats=R.materials()
    for c,i in P.items():
        mats[i].name=c
        node=mats[i].node_tree.nodes.get("Principled BSDF")
        node.inputs["Metallic"].default_value=.57 if "nickel" in c else 0
        node.inputs["Roughness"].default_value=.885 if "Bark" in c or "Deck" in c else .56
    oc=R.stash(m,mats,"Original permanent Witcombe coachwork and stake bed")
    cc=R.stash(cargo,mats,"Original independent removable long stems, two short bundles and ties")
    scene=bpy.context.scene
    scene.name="Witcombe Wood Truck (20 tonnes)"
    scene["Stock catalog"]="OpenTTD 14.1 #144 / road row 28 / image 7. Load view threshold 10 tonnes at default 20 tonnes capacity."
    scene["Native setup"]="Scale .42, h=0 tyre contact plane, local -Z nose."
    scene["Source inspiration"]="OpenGFX removable logs, no imported sprites or original proprietary geometry."
    R.instance(scene,oc,0,0)
    R.instance(scene,cc,0,0)
    for screen in bpy.data.screens:
        for a in screen.areas:
            if a.type=="VIEW_3D":
                v=a.spaces.active
                v.shading.color_type="MATERIAL"
                v.region_3d.view_location=(0,0,.279)
                v.region_3d.view_distance=2.65
                v.region_3d.view_rotation=(Vector((0,0,.28))-Vector((1.40,-2.60,1.31))).to_track_quat("-Z","Y")
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art/witcombe_wood_truck.blend"),compress=True)
    for suffix,x in (("",m),("_loaded",full)):
        p=R.MODELS/(PREFIX+suffix+".obj")
        R.export_obj(p,S.local_obj(x))
        a=p.read_text()
        p.write_text(a.replace(a.splitlines()[0],
           "# Original Witcombe Wood Truck 3D art; tools/build_witcombe_wood_truck_art.py",1))
    atlas()
    if path:=os.getenv("WITCOMBE_WOOD_RENDER"):
        for o in list(scene.collection.objects):
            # Remove parked preview instances; data stays editable at save.
            bpy.data.objects.remove(o,do_unlink=True)
        view(mats,oc,cc,path)

if __name__=="__main__":publish()

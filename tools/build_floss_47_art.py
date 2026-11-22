#!/usr/bin/env python3
"""Original Brush Type 4-inspired stock #15 Floss '47' for LuanTTD.

blender -b -t 3 --python-exit-code 1 --python tools/build_floss_47_art.py
FLOSS_47_REVIEW also writes a two-angle studio view. Each bogie swivels
independently for editing, each axle rolls, and the roof fan blades rotate.
Runtime OBJ is one stock-length static visual, scale 1/-Z forward.
"""
from math import cos, pi, sin, tau
import os
from pathlib import Path
import struct
import sys
import zlib

import bpy
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_chaney_jubilee_art as J
import build_balogh_goods_truck_art as G
R,W=J.R,J.W
B,D,L=J.B,J.Disk,J.Lathe
Pipe=J.Pipe
ROOT=R.ROOT
NAME="bl_rail_floss_47"
PAL={
 "Forest shadow enamel":"27493e","Main deep green enamel":"39644e",
 "Sunlit main green":"4c765c","Light two-tone sage":"87937a","Sage side reflected light":"96a18b",
 "Dark inset green":"2e5547","Primer dark green":"334a3e","Yellow safety enamel":"dfb43c",
 "Yellow highlight enamel":"edc756","Yellow turned below":"ac8b3a","Nose lower graphite":"4b4e40",
 "Slate roof steel":"454b49","Slate shoulder shade":"3c4542","Roof aged crown":"53605b",
 "Black intake": "242f2b","Grille separator":"57645c","Grazing grille nickel":"859385",
 "Body seam green":"244137","Glazing black gasket":"293938","Cab panorama blue-black":"34535a",
 "Glass sky reflection":"769ba0","Side glass dull sheen":"598184","Silver beading":"a2a99b",
 "Number face pale":"ebe0ac","Dark code plate":"36403a","Hood fleet ochre":"d7ab56",
 "Frame graphite":"373d39","Foundry wheel grey":"48514b","Axle bearing bolt":"7b8983",
 "Nickel running edge":"9caaa1","Contact flange steel":"46554e","Buffer beam rust red":"8d5143",
 "Buffer bright face":"a1a89d","Draw arm steel":"697970","Machined bracket bronze":"927e58",
 "Tube steel":"626b61","Red marker glass":"b95448","Warm headlamp":"f6dfa0",
 "Heat patinated black":"323831","Fan wheel grey":"53594f","Fan blade edge":"788176","Review ballast":"827d71",
}
P={key:i for i,key in enumerate(PAL)}
RAD=.045
AXLES=(-.307,-.242,-.174,.174,.242,.307)
BOGIE=.242
FAN_CENTERS=(-.097,.095)
CROWN=.590
FAN_SQUARE=.079
FAN_RADIUS=.065
STATIONS=((.000,.231,.206,CROWN),(.186,.231,.206,CROWN),(.236,.218,.206,.588),
      (.287,.211,.210,.584),(.325,.201,.215,.575),(.361,.188,.219,.551),
      (.401,.168,.222,.519),(.424,.154,.225,.495))


def palette():
    R.COLORS[:]=PAL.values()
    J.P=W.P=G.P=P


def mesh():
    return R.Mesh(R.terrain_height(0))


def F(m,n,c,v):
    m.face(n,P[c],v)


def yz(x,y,z,end):
    # Mirror the complete cab via a horizontal 180-degree rotation.
    return (end*x,end*y,z)


def patch(m,label,color,pts,end):
    F(m,label,color,[yz(x,z,h,end) for x,z,h in pts])


def profile(width,bottom,top):
    dh=top-bottom
    at=lambda t:bottom+dh*t
    return [(-.79*width,bottom),(.79*width,bottom),(.966*width,at(.075)),
      (width,at(.205)),(width,at(.453)),(width,at(.654)),
      (.97*width,at(.785)),(.80*width,at(.897)),(.104 if width>=.2 else .59*width,top),
      (-.104 if width>=.2 else -.59*width,top),(-.80*width,at(.897)),
      (-.97*width,at(.785)),(-width,at(.654)),(-width,at(.453)),
      (-width,at(.205)),(-.966*width,at(.075))]


def shell(m):
    # Locomotive's continuous pressure-formed frame. The shoulders and crown
    # die down through each cab. The two real fan hatches remove the center
    # roof panel between stations; another physical slab is not hidden under them.
    sections=[(-z,profile(w,b,t)) for z,w,b,t in STATIONS[:0:-1]]+[(z,profile(w,b,t)) for z,w,b,t in STATIONS]
    for i,((az,a),(bz,b)) in enumerate(zip(sections,sections[1:])):
        y=(az+bz)/2
        for k in range(len(a)):
            if k==8 and -.185<y<.185:
                continue
            l=(k+1)%len(a)
            roof=k in (6,7,8,9,10)
            if roof:
                color="Roof aged crown" if k in (7,8,9) else "Slate shoulder shade"
            elif abs(y)>.345:
                color="Yellow turned below" if k in (0,1,2,14,15) else "Yellow safety enamel"
            elif k in (3,13):
                color="Light two-tone sage"
            elif k in (5,11):
                color="Sunlit main green"
            elif k in (0,1,15):
                color="Forest shadow enamel"
            else:
                color="Main deep green enamel"
            # Separate broad continuous side panels from roof and cab
            # shoulders for reliable shape editing and baked rail shades.
            part=("Faceted shoulder falling into both cabs" if roof and abs(y)>.25 else
                  "Raised central roof and curved cooler shoulders" if roof else
                  "Lofted twin tapering Floss front hoods" if abs(y)>.236 else
                  "Long two-tone deep green and sage locomotive sidewalls")
            F(m,part,color,((a[k][0],az,a[k][1]),(b[k][0],bz,b[k][1]),
                    (b[l][0],bz,b[l][1]),(a[l][0],az,a[l][1])))
    for z,prof in (sections[0],sections[-1]):
        p=[(x,z,h) for x,h in prof]
        F(m,"Two formed iconic aprons with yellow end plates","Yellow safety enamel",p if z<0 else p[::-1])
    # Two side strips and three cross strips replace the removed center
    # strip, leaving the square fan openings precisely bounded.
    def infill(x0,x1,z0,z1):
        if z1>z0:
            F(m,"Distinct replaceable roof fan opening deck","Roof aged crown",
              ((x0,z0,CROWN),(x1,z0,CROWN),(x1,z1,CROWN),(x0,z1,CROWN)))
    for a,b in ((-.104,-FAN_SQUARE),(FAN_SQUARE,.104)):
        infill(a,b,-.186,.186)
    start=-.186
    for z in FAN_CENTERS:
        infill(-FAN_SQUARE,FAN_SQUARE,start,z-FAN_SQUARE)
        start=z+FAN_SQUARE
    infill(-FAN_SQUARE,FAN_SQUARE,start,.186)


def emit_quad(m,n,c,x0,x1,z,h0,h1,end):
    patch(m,n,c,((x0,z,h0),(x1,z,h0),(x1,z,h1),(x0,z,h1)),end)


def cabs(m):
    # Formed faceted dual green hood with deep rectangular glazing. The two
    # upper planes slope toward the roof rather than being pasted on a cube.
    for end in (-1,1):
        for sx in (-1,1):
            x0,x1=sorted((sx*.009,sx*.126))
            outer=((x0,-.426,.395),(x1,-.426,.398),(x1,-.426,.476),(x0,-.426,.474))
            inner=((x0+.004,-.428,.403),(x1-.005,-.428,.405),(x1-.006,-.428,.468),(x0+.005,-.428,.467))
            patch(m,"Twin thick wraparound windscreen rubber seats","Glazing black gasket",outer,end)
            patch(m,"Real inserted dark cab windscreen panes","Cab panorama blue-black",inner,end)
            emit_quad(m,"Reflective top edge on twin windscreens","Glass sky reflection",x0+.008,x1-.008,-.430,.450,.463,end)
            Pipe(m,"Textured wrapped windscreen wipers",
                 "Glazing black gasket",yz(sx*.082,-.432,.410,end),
                 yz(sx*.037,-.432,.450,end),.0034,7)
            D(m,"Round headcode warning end lamp reflectors","Glazing black gasket",
              yz(sx*.066,-.431,.319,end),.0135,"z",-.004,.004,16)
            D(m,"Lightly patinated lamp lenses above beam","Warm headlamp",
              yz(sx*.066,-.436,.319,end),.0093,"z",-.002,.0025,14)
            D(m,"Small ruby marker lens outboard","Red marker glass",
              yz(sx*.108,-.430,.296,end),.0067,"z",-.003,.003,12)
            # Framed buffer ends mirrored around body center; enough modular
            # breathing room that this is not a scale British clearance spec.
            stem=yz(sx*.080,-.418,.165,end)
            D(m,"Paired buffer sleeves pressed from cast steel","Frame graphite",stem,.018,
              "z",-.013,.013,18)
            D(m,"Polished round buffer head face","Buffer bright face",
              yz(sx*.080,-.433,.165,end),.021,"z",-.004,.004,18)
            for j in range(3):
                z=-.434-j*.004
                Pipe(m,"Swaying under-buffer air pipes","Tube steel",
                     yz(sx*(.047+j*.008),z,.164,end),yz(sx*(.037+j*.009),z,.120,end),.0045,8)
        B(m,"Aged cast rust-red buffer beam profile","Buffer beam rust red",
          0,end*.416,.219,.037,.127,.222,.009)
        B(m,"Original inset central headcode in yellow hood","Yellow turned below",
          0,end*.426,.131,.010,.334,.371,.004)
        B(m,"Black double window headcode plate","Dark code plate",
          0,end*.432,.117,.007,.339,.366,.003)
        emit_quad(m,"Pressed horizontal bright nose grab rail","Silver beading",-.104,.104,-.435,.380,.384,end)
        emit_quad(m,"Narrow divided beam bracing strip","Yellow highlight enamel",-.118,.118,-.428,.226,.235,end)
        B(m,"Draw guides cast near the buffer beam","Frame graphite",
          0,end*.447,.054,.051,.133,.183,.005)
        B(m,"Underlying bolted center coupler arm","Draw arm steel",
          0,end*.478,.024,.025,.143,.171,.003)
        B(m,"Coupler knuckles","Buffer bright face",
          0,end*.494,.0105,.010,.146,.168,.002)

    for z in (-.307,.307):
        for s in (-1,1):
            side_patch(m,"Deep-set separate driver door shells","Body seam green",
              s,z-.036,z+.035,.231,.494,.0022)
            side_patch(m,"Stenciled lighter cab door surface","Dark inset green",
              s,z-.031,z+.030,.238,.481,.0041)
            side_patch(m,"Heavy inset driver side gasket frame","Glazing black gasket",
              s,z-.026,z+.025,.407,.479,.0062)
            side_patch(m,"Smoky inset driver side panes","Cab panorama blue-black",
              s,z-.023,z+.022,.414,.475,.0076)
            side_patch(m,"Small line of reflective side-window glass","Side glass dull sheen",
              s,z-.018,z+.019,.455,.467,.0088)
            side_patch(m,"Dual-window silver center divider","Silver beading",
              s,z+.004,z+.008,.411,.475,.0098)
            grip=lambda w,h:(s*(side_at(w,h)+.008),w,h)
            Pipe(m,"Driver grab rails spot welded to frame","Silver beading",
                 grip(z-.023,.244),grip(z-.023,.347),.0034,8)
            Pipe(m,"Heavy door pull just outside the seal","Silver beading",
                 grip(z+.022,.362),grip(z+.022,.382),.0042,8)
            for h in (.157,.185,.207):
                B(m,"Exterior folded steel crew step treads","Tube steel",
                  s*.178,z,.052,.047,h,h+.008,.001)


def side_at(z,h):
    z=abs(z)
    for a,b in zip(STATIONS,STATIONS[1:]):
        if a[0]<=z<=b[0]:
            t=(z-a[0])/(b[0]-a[0])
            p=[((1-t)*x+t*y,(1-t)*u+t*v) for (x,u),(y,v) in
               zip(profile(*a[1:]),profile(*b[1:]))]
            for (x0,h0),(x1,h1) in zip(p[1:8],p[2:9]):
                if h0<=h<=h1:
                    return x0+(x1-x0)*(h-h0)/(h1-h0)
    raise ValueError((z,h))


def side_patch(m,n,c,s,z0,z1,h0,h1,offset):
    coords=(z0,*[t for t in sorted(v[0]*j for v in STATIONS[1:] for j in (-1,1))
                 if z0<t<z1],z1)
    # Match the body shape and declutter the floating door glass at the
    # steep hood transition.
    for za,zb in zip(coords,coords[1:]):
        grids=((za,h0),(zb,h0),(zb,h1),(za,h1))
        p=[(s*(side_at(z,h)+offset),z,h) for z,h in grids]
        F(m,n,c,p if s>0 else p[::-1])

def vents(m):
    for s in (-1,1):
        # Four individually framed banks are dark hollows between genuine
        # slats, at the characteristic Class 47 roof-to-body transition.
        for j,(z0,span) in enumerate(((-.222,.082),(-.120,.092),(.003,.089),(.120,.091))):
            x,h=s*.198,.518
            F(m,"Cooling group shadow housings behind actual slats","Black intake",[
                (s*.228,z0,h-.025),(s*.228,z0+span,h-.025),
                (s*.185,z0+span,h+.029),(s*.185,z0,h+.029)] if s>0 else
                [(s*.185,z0,h+.029),(s*.185,z0+span,h+.029),
                (s*.228,z0+span,h-.025),(s*.228,z0,h-.025)])
            for i in range(6):
                shift=i/5
                x=s*(.230-.044*shift)
                h=.491+.056*shift
                G.bar(m,"Distinct profiled long cooler hood louvres",
                  "Grazing grille nickel" if (i+j)%3==0 else "Grille separator",
                  (x,z0,h),(x,z0+span,h),.0049,.0064)
            for z in (z0,z0+span):
                Pipe(m,"Polished structural ribs at radiator bays","Grazing grille nickel",
                  (s*.233,z,.491),(s*.187,z,.55),.0042,8)
        B(m,"Upper gloss orange-green body boundary","Hood fleet ochre",
          s*.231,.001,.005,.447,.473,.477,.0007)
        for z in (-.170,.025,.177):
            B(m,"Recessed access door under cooler bank","Dark inset green",
              s*.232,z,.005,.067,.260,.376,.003)
            for h in (.281,.348):
                B(m,"Riveted mechanical latch on access panel","Grille separator",
                  s*.235,z-.018,.006,.022,h,h+.007,.001)
        B(m,"Original inset Floss number panel","Dark code plate",
          s*.233,.006,.010,.126,.301,.335,.002)
        for c,row in ((0,(1,0,0,1,1)),(1,(1,1,1,0,0)),(2,(1,0,1,0,1)),(3,(1,0,0,1,0))):
            # Abstract four-slot headcode / side builder plate embossment,
            # no real British Rail trademark or extracted registries.
            for k,on in enumerate(row):
                if on:
                    B(m,"Raised pale fleet plate strokes","Number face pale",
                      s*.239,.006+s*((c*2.3)-3.4)*.010,.003,.006,
                      .309+k*.0035,.312+k*.0035,.0004)


def fan_rings(m,z):
    n=32
    cs=[]
    for i in range(n):
        a=tau*i/n
        x,y=cos(a),sin(a)
        scale=FAN_SQUARE/max(abs(x),abs(y))
        cs.append(((x*scale,z+y*scale,CROWN),
                   (x*(FAN_RADIUS+.004),z+y*(FAN_RADIUS+.004),CROWN),
                   (x*FAN_RADIUS,z+y*FAN_RADIUS,CROWN+.0034),
                   (x*FAN_RADIUS,z+y*FAN_RADIUS,CROWN-.032)))
    for a,b in zip(cs,cs[1:]+cs[:1]):
        for j,mat in enumerate(("Roof aged crown","Grazing grille nickel","Black intake")):
            F(m,"Open cylindrical roof fan well and exterior retainer",mat,
                 (a[j],b[j],b[j+1],a[j+1]))
    D(m,"Fan casing lower interior, recessed from roof","Heat patinated black",
      (0,z,0),FAN_RADIUS,"h",CROWN-.038,CROWN-.035,32)
    for v in (0,pi/2):
        Pipe(m,"Fine crossed steel reach guard above individual fan blades",
          "Grille separator",(-cos(v)*.063,z-sin(v)*.063,CROWN+.002),
          (cos(v)*.063,z+sin(v)*.063,CROWN+.002),.0015,6)


def fan(m,z):
    h=CROWN-.014
    D(m,"Central drilled radiator fan hub","Axle bearing bolt",(0,z,h),.0125,"h",-.005,.005,16)
    for i in range(9):
        a=tau*i/9
        blade=[(.011,a-.14,.002),(.024,a-.02,.004),(.056,a+.111,.006),(.059,a+.34,.001),
               (.039,a+.314,-.003),(.019,a+.205,-.002),(.011,a+.09,-.002)]
        p=[(r*cos(t),z+r*sin(t),h+dh) for r,t,dh in blade]
        q=[(x,y,z-.0033) for x,y,z in p]
        F(m,"Nine angled individual radiator fan blades","Fan wheel grey",p)
        F(m,"Nine angled individual radiator fan blades","Fan wheel grey",q[::-1])
        for k in range(len(p)):
            j=(k+1)%len(p)
            F(m,"Shaped fine beveled radiator fan edges","Fan blade edge",(p[k],q[k],q[j],p[j]))


def frame(m):
    J.shaped(m,"Machined long sill foundation","Primer dark green",[
      (-.125,-.402),(.125,-.402),(.176,-.333),(.185,-.204),(.185,.204),
      (.176,.333),(.125,.402),(-.125,.402),(-.176,.333),(-.185,.204),(-.185,-.204),(-.176,-.333)],
      .156,.211,"Forest shadow enamel")
    B(m,"Diesel day tank between bogie trucks","Frame graphite",0,0,.247,.198,.079,.163,.027)
    for s in (-1,1):
        D(m,"Two torque-mounted heavy diesel air reservoirs","Tube steel",
          (s*.110,.011,.121),.045,"z",-.109,.104,20)
        for z in (-.063,.062):
            D(m,"Air reservoir steel girdling fastener band","Frame graphite",
              (s*.110,z,.121),.047,"z",-.010,.010,20)
        B(m,"Lateral battery cover lower louvers","Foundry wheel grey",
          s*.139,0,.032,.132,.077,.119,.007)
        for i in range(7):
            B(m,"Individual battery box vent slits","Heat patinated black",
              s*.157,-.047+i*.015,.005,.005,.083,.104,.0008)
        Pipe(m,"Lateral diesel service pipe and brake line","Tube steel",
             (s*.167,-.131,.137),(s*.167,.131,.137),.0055,8)
    for z in (-.159,.027,.164):
        D(m,"Separate exhaust opening forward of roof fan well","Heat patinated black",
          (-.086,z,CROWN),.014,"h",-.001,.008,14)
        B(m,"Short separate service walk plate","Grille separator",
          .089,z,.017,.042,CROWN-.002,CROWN+.002,.0015)


def skeleton(m,z):
    guide=[
      (-.173,z-.104),(.173,z-.104),(.189,z-.076),(.189,z+.077),(.171,z+.105),
      (-.171,z+.105),(-.189,z+.074),(-.189,z-.074)]
    J.shaped(m,"Complete three-axle bogie casting and bolster", "Frame graphite",
            guide,.076,.114,"Foundry wheel grey")
    for s in (-1,1):
        B(m,"Forward cast bogie wing plate above wheels","Frame graphite",
          s*.224,z,.037,.185,.091,.124,.008)
        B(m,"Bogie horizontal sprung driving unit rails","Foundry wheel grey",
          s*.176,z,.031,.185,.076,.104,.006)
        for v in (z-.075,z+.074):
            B(m,"Visible triangular bolster side frame foot","Tube steel",
              s*.182,v,.033,.032,.055,.117,.005)
        for v in (z-.038,z+.036):
            # Visible shallow spring stack over both fulcrum bearings.
            for j in range(4):
                D(m,"Four stacked boss edges of bogie helical springs","Tube steel",
                  (s*.179,v,0),.011,"h",.086+j*.007,.090+j*.007,12)
        for v in (z-.066,z,z+.065):
            B(m,"Axlebox retainers on outside wheel guides","Frame graphite",
              s*.191,v,.027,.034,.043,.071,.005)
            D(m,"Exposed axlebox locking bolt","Axle bearing bolt",
              (s*.207,v,.058),.005,"x",-.002,.002,7)


def rolling(m,z):
    D(m,"Full width 0.424-gauge road axle","Frame graphite",(0,z,RAD),.010,"x",-.221,.221,12)
    for s,side in ((-1,"L"),(1,"R")):
        x=s*.212
        lo,hi=sorted((s*.048,-s*.028))
        L(m,"Rolling tread Floss "+side,[(lo,RAD*.75),(lo,RAD),
                (-.006,RAD),(.006,RAD),(hi,RAD),(hi,RAD*.75),(lo,RAD*.75)],"x",(x,z,RAD),
                ("Frame graphite","Contact flange steel","Axle bearing bolt","Foundry wheel grey",
                 "Frame graphite","Frame graphite"),24,False,False)
        left,right=sorted((-s*.042,-s*.035))
        L(m,"True inner Floss guide flanges",[(left,RAD*.72),(left,RAD+.009),
                (right,RAD+.009),(right,RAD*.72),(left,RAD*.72)],"x",(x,z,RAD),
                ("Contact flange steel",),24,False,False)
        D(m,"Pressed plate diesel wheel with exposed dish shoulder","Foundry wheel grey",
          (x+s*.038,z,RAD),.035,"x",-.006,.006,20)
        D(m,"Separate spline cap with wear-bright perimeter","Axle bearing bolt",
          (x+s*.045,z,RAD),.012,"x",-.004,.004,14)
        for k in range(5):
            a=tau*k/5
            D(m,"Individual locknuts on outboard diesel axle","Tube steel",
               (x+s*.043,z+.021*cos(a),RAD+.021*sin(a)),.0027,"x",-.002,.003,6)


def permanent():
    m=mesh()
    shell(m)
    cabs(m)
    vents(m)
    frame(m)
    for z in FAN_CENTERS:
        fan_rings(m,z)
    return m


def whole():
    m=permanent()
    for z in (-BOGIE,BOGIE):skeleton(m,z)
    for z in AXLES:rolling(m,z)
    for z in FAN_CENTERS:fan(m,z)
    return m


def atlas():
    row=b"".join(bytes.fromhex(v)*8 for v in PAL.values())
    def c(x,d):
        return struct.pack(">I",len(d))+x+d+struct.pack(">I",zlib.crc32(x+d))
    (R.TEXTURES/(NAME+".png")).write_bytes(b"\x89PNG\r\n\x1a\n"+
      c(b"IHDR",struct.pack(">IIBBBBB",len(P)*8,8,8,0x02,0,0,0))+
      c(b"IDAT",zlib.compress((b"\0"+row)*8))+c(b"IEND",b""))


def colors():
    m=R.materials()
    for mat,label in zip(m,P):
        mat.name=label
        n=mat.node_tree.nodes.get("Principled BSDF")
        n.inputs["Metallic"].default_value=.35 if "steel" in label or "nickel" in label.lower() else .05
        n.inputs["Roughness"].default_value=.36 if "glass" in label.lower() else .67
    return m


def pivot(sc,label,mats,parts,px,parent=None,axis=None,turn=None):
    box=J.geometry(sc,label,parts,mats)
    p=bpy.data.objects.new(label+" pivot",None)
    p.empty_display_type="CIRCLE"
    p.empty_display_size=.053 if axis!=2 else .077
    box.objects.link(p)
    if parent:
        p.parent=parent
        p.location=Vector(px)-parent.location
    else:
        p.location=px
    for o in list(box.objects):
        if o!=p:
            o.parent=p
            o.location=-Vector(px)
    if turn:
        for time,value in ((1,0),(49,turn)):
            p.rotation_euler[axis]=value
            p.keyframe_insert(data_path="rotation_euler",index=axis,frame=time)
        J.linear(p.animation_data.action.fcurves)
    return p


def editable(m,path=None):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    sc=bpy.context.scene
    sc.name="LuanTTD · Floss '47' #15 standard rail diesel"
    sc.view_settings.view_transform="Standard"
    sc["Mount"]="Standard .424 gauge and .614 level deck. Unit size; -Z nominal front."
    sc["References"]="Original Class 47-inspired art, no photo or pixel transfers. art/rail_floss_47.md"
    sc["Rig"]="Two independently swiveling bogies, each with 3 wheel pivots; side fan accesses and two moving rotor pivots. Runtime OBJ is static."
    sc.frame_start,sc.frame_end=1,49
    mats=colors()
    J.geometry(sc,"Original chassis, dual cabs, shell and cooler grilles",permanent(),mats)
    for i,z in enumerate((-BOGIE,BOGIE),1):
        sub=mesh()
        skeleton(sub,z)
        deck=pivot(sc,f"Bogie {i} · central pivot",mats,sub,(0,z,.093))
        for j,t in enumerate(AXLES[(i-1)*3:i*3],1):
            sub=mesh()
            rolling(sub,t)
            pivot(sc,f"Bogie {i} · axle {j}",mats,sub,(0,t,RAD),deck,0,2*tau)
    for i,z in enumerate(FAN_CENTERS,1):
        sub=mesh()
        fan(sub,z)
        pivot(sc,f"Roof fan {i}",mats,sub,(0,z,CROWN-.014),None,2,6*tau)
    sc.frame_set(1)
    for screen in bpy.data.screens:
        for a in screen.areas:
            if a.type=="VIEW_3D":
                v=a.spaces.active
                v.shading.color_type="MATERIAL"
                v.region_3d.view_location=(0,0,.294)
                v.region_3d.view_distance=1.85
                v.region_3d.view_rotation=Vector((.73,-.91,.44)).to_track_quat("Z","Y")
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art/rail_floss_47.blend"),compress=True)
    if path:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        J.render(bpy.context.scene,R.stash(m,colors(),"Original Floss '47' review"),path)


def main():
    palette()
    m=whole()
    path=R.MODELS/(NAME+".obj")
    R.export_obj(path,W.local_obj(m))
    content=path.read_text()
    path.write_text("# Original stock Floss '47' · tools/build_floss_47_art.py\n"+content.split("\n",1)[1])
    atlas()
    editable(m,os.getenv("FLOSS_47_REVIEW"))


if __name__=="__main__":
    main()

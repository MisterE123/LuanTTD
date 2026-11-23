#!/usr/bin/env python3
"""Original Tricario helicopter with separately driven main and tail rotors."""
# SPDX-License-Identifier: GPL-2.0-only
from math import cos, pi, sin, sqrt, tau
from pathlib import Path
from types import SimpleNamespace
import os
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_stock_darwin_family_art as D
from mathutils import Vector
E,Art,B,C,Mesh=D.e,D.art,D.B,D.C,D.M
bpy=D.bpy
PAL=Art.PAL | {
    "Crown ivory":"e9dfc3","Panel ivory":"e3d4ad","Silver pressure hull":"b6bba4",
    "Dark coastal cobalt":"3b656b","Blue taper":"517a76","Lit blue":"52837b","Copper pinstripe":"c68a57",
    "Cab glass":"254a56","Window glint":"779fa6","Glazing bezel":"536466",
    "Skinned wing alloy":"657778","Pale spinner alloy":"a4b2aa","Exhaust patina bronze":"765c4b",
    "Port marker ruby":"c2534b","Starboard marker mint":"529d80",
}
PROFILE=(
    (-.256,.073,.210,.061,.052),(-.208,.103,.206,.082,.076),
    (-.151,.127,.198,.105,.086),(-.081,.144,.198,.118,.096),
    (.072,.148,.200,.123,.095),(.198,.142,.198,.117,.092),
    (.273,.119,.192,.104,.086),(.328,.089,.175,.089,.075),
    (.369,.057,.162,.058,.056),(.391,.027,.154,.025,.028),(.396,.008,.153,.008,.011),
)
PIVOT=(0,.016,.407)
TAIL=(-.037,-.605,.256)

def k(y,s,f,out):
    w,h,t,b=E.interp(PROFILE,y)
    return (s*(w*sqrt(1-f*f)+out),y,h+f*(t if f>=0 else b))

def side(name,color,y,f,ay,af,side,margin):
    # A single polygon would chord across the curved hull and intersect
    # the very paint/glazing it is meant to cover. Conform finely at both
    # the profile and the panel bevel so either camera direction is clean.
    nx,nz=8,6
    points=[]
    for j in range(nz+1):
        v=-1+2*j/nz
        width=1-.25*max(0,(abs(v)-.61)/.39)
        for i in range(nx+1):
            u=(-1+2*i/nx)*width
            points.append(k(y+u*ay,side,f+v*af,margin))
    faces=[(j*(nx+1)+i,j*(nx+1)+i+1,(j+1)*(nx+1)+i+1,(j+1)*(nx+1)+i)[::side]
           for i in range(nx) for j in range(nz)]
    Mesh(name,points,faces,color)

def cabin():
    angles=[tau*j/56 for j in range(56)]
    colors=["Crown ivory" if sin(t+pi/56)>.53 else "Panel ivory" if sin(t+pi/56)>.19 else
        "Lit blue" if sin(t+pi/56)>-.29 else "Copper pinstripe" if sin(t+pi/56)>-.39 else
        "Silver pressure hull" if sin(t+pi/56)>-.68 else "Dark coastal cobalt" for t in angles]
    Art.sections("Compact pressure shell with a rounded amphibious keel",
        [(y,[(w*cos(t),h+(top if sin(t)>=0 else bottom)*sin(t)) for t in angles])
            for y,w,h,top,bottom in PROFILE],"Panel ivory",colors)
    # The two wide cockpit faces form a wraparound glazed nose with a
    # visible central mullion, not side decals that disappear head-on.
    for s in (-1,1):
        def wind(name,color,begin,end,t0,t1,d):
            v=[]
            for i in range(11):
                y=begin+(end-begin)*i/10
                w,h,top,_=E.interp(PROFILE,y)
                for j in range(12):
                    p=t0+(t1-t0)*j/11
                    angle=.17+p*(pi/2-.17)
                    v.append((s*(w+d)*cos(angle),y,h+(top+d)*sin(angle)))
            faces=[(i*12+j,i*12+j+1,(i+1)*12+j+1,(i+1)*12+j)[::-s] for i in range(10) for j in range(11)]
            Mesh(name,v,faces,color)
        wind("Visible two-piece curved windscreen seal","Glazing bezel",.251,.375,.035,.963,.0017)
        wind("Curved inset large pilot glazing","Cab glass",.260,.368,.067,.931,.0030)
        wind("High reflection in cockpit glazing","Window glint",.298,.351,.689,.755,.0035)
        for n,y in enumerate((-.145,-.062,.019,.103,.182)):
            side("Inset pressure window rubber frame","Glazing bezel",y,.37,.033,.235,s,.0017)
            side("Distinguished cabin side window","Cab glass",y,.37,.028,.183,s,.0032)
            side("Window horizon reflection","Window glint",y-.007,.47,.015,.029,s,.0039)
        side("Right sized seated passenger entry outline","Pressure door seal",-.082,-.275,.056,.515,s,.0027)
        # Opening is interrupted around the two actual windows. Relief
        # details are small enough not to cover them or the front glazing.
        side("Painted lower sliding boarding door","Panel ivory",-.082,-.34,.051,.486,s,.0044)
        side("Boarding handle","Landing gear chrome",-.052,-.14,.011,.035,s,.0051)
        side("Pilot side quarter light","Cab glass",.221,.31,.028,.225,s,.0030)
        b=.127
        B("Raised personnel step gripping surface",(s*(b+.021),-.075,.068),(.041,.169,.010),"Landing gear chrome",.004)
        for y in (-.128,-.014):
            C("Independent boarding step bracket",(s*b,y,.102),(s*(b+.024),y,.069),.007,.004,"Well shadow",7)
        c="Port marker ruby" if s<0 else "Starboard marker mint"
        C("Side navigation marker",(s*.141,-.187,.210),(s*.150,-.187,.210),.010,.008,c,12)

def mechanics():
    # Tapering tail tube with raised tail gearbox, fins and open vents.
    angles=[tau*j/24 for j in range(24)]
    Art.sections("Tapered tail cone with a proper boom cross section",
        [(y,[(w*cos(t),h+d*sin(t)) for t in angles]) for y,w,h,d in
        ((-.608,.022,.248,.024),(-.522,.030,.229,.030),(-.399,.041,.217,.040),(-.267,.057,.210,.052),(-.210,.073,.207,.061))],
        "Panel ivory",["Dark coastal cobalt" if sin(t)<-.28 else "Panel ivory" for t in angles])
    a=[(-.016,-.590,.253),(-.014,-.635,.294),(-.012,-.627,.415),(-.013,-.597,.413),
        (-.016,-.557,.363),(-.020,-.533,.259)]
    vs=a+[(-x,y,z) for x,y,z in a]
    Art.close_mesh("Solid swept tail fin and visible upper paint cap",vs,
        [(0,1,2,3,4,5),(11,10,9,8,7,6)]+[(i,(i+1)%6,(i+1)%6+6,i+6) for i in range(6)],
        ["Lit blue","Lit blue","Wing leading trim","Copper pinstripe","Crown ivory","Crown ivory","Blue taper","Dark coastal cobalt"])
    for s in (-1,1):
        pts=[(0,-.517,.214),(s*.163,-.518,.216),(s*.164,-.544,.213),(0,-.567,.216)]
        Mesh("Left or right horizontal stabilizer",pts,[tuple(range(4))[::s]],"Dark coastal cobalt")
    for s in (-1,1):
        w=s*.073
        # Engine exhausts have actual open recesses around their bore.
        Art.turbojet("Open oval turboshaft exhaust without a painted cap",w,
            ((-.146,.037,.332,"Copper pinstripe"),(-.158,.034,.332,"Exhaust patina bronze"),
            (-.158,.025,.332,"Dark intake"),(-.122,.019,.333,"Dark intake")),"Exhaust patina bronze")
        B("Rounded service housing above cabin pressure roof",(w,-.036,.313),(.091,.227,.101),"Blue taper",.035)
        for j in range(6):
            B("Lifted upper cooling louver",(w,-.009+j*.016,.365),(.035,.005,.005),"Well shadow",.0018)
        C("Real aft damping cylinder",(w,-.219,.294),(w,-.181,.295),.019,.015,"Landing gear chrome",10)
    C("Signed main gearbox mast",(0,PIVOT[1],.331),PIVOT,.026,.012,"Landing gear chrome",14)
    C("Cross-tail rotor live gearbox",(-.014,TAIL[1],TAIL[2]),TAIL,.019,.014,"Landing gear chrome",14)
    C("Post-mounted tail marker lens",(0,-.609,.414),(0,-.612,.425),.009,.008,"Port marker ruby",10)

def wheels():
    for s in (-1,1):
        x=s*.136
        C("Main outrigger leg",(s*.089,-.026,.145),(x,-.019,.037),.014,.012,"Landing gear chrome",9)
        C("Main strut cross brace",(s*.071,.038,.124),(x,-.019,.037),.009,.006,"Shadowed flap",8)
        C("Balanced fixed landing wheel on main strut",(x-.010,-.019,.037),(x+.010,-.019,.037),.037,.037,"Dull tire",24)
        C("Separate polished bearing cap",(x+s*.009,-.019,.037),(x+s*.013,-.019,.037),.016,.012,"Landing gear chrome",12)
    C("Fixed nose gear compression column",(0,.228,.143),(0,.239,.027),.012,.010,"Landing gear chrome",10)
    C("Nose fork fixed leading wheel",(-.011,.239,.028),(.011,.239,.028),.028,.028,"Dull tire",24)
    C("Protective tail strike curved bump stop",(0,-.555,.196),(0,-.586,.136),.013,.009,"Well shadow",9)

def rotor(tail=False):
    count=3 if tail else 4
    axis="tail" if tail else "main"
    def coord(x,y,z,a):
        x,y=x*cos(a)-y*sin(a),x*sin(a)+y*cos(a)
        return (z,x,y) if tail else (x,y,z)
    center=lambda z: (z,0,0) if tail else (0,0,z)
    C(f"Separate {axis} rotor hub",center(-.009 if tail else -.014),center(.014 if tail else .029),
        .023 if tail else .043,.014 if tail else .025,"Landing gear chrome",12)
    for j in range(count):
        a=tau*j/count+(pi/7 if tail else pi/11)
        r=(.023,.052,.108,.140,.155) if tail else (.047,.161,.413,.519,.56)
        w=(.006,.012,.014,.012,.007) if tail else (.014,.031,.026,.022,.012)
        t=(.003,.004,.003,.002,.002) if tail else (.008,.009,.006,.004,.003)
        vs=[]
        for u,s,v in zip(r,w,t):
            center_dist=-.025*(u/r[-1])**2 if not tail else 0
            vs.extend(coord(center_dist+q,u,k,a) for q,k in ((-s,-v),(s,-v),(s,v),(-s,v)))
        faces=[(3,2,1,0)]
        inks=["Shadowed flap"]
        for i in range(4):
            for p in range(4):
                q=(p+1)%4
                faces.append((i*4+p,i*4+q,(i+1)*4+q,(i+1)*4+p))
                inks.append(("Skinned wing alloy","Silver pressure hull","Crown ivory","Copper pinstripe")[i])
        faces.append((16,17,18,19));inks.append("Copper pinstripe")
        Art.close_mesh(f"Cambered independent {axis} blade {j+1}",vs,faces,inks)
        C(f"Exposed blade pitch link {j+1}",coord(-.010,r[0]*.60,.007,a),coord(-.014,r[1],.006,a),
            .005 if tail else .009,.003 if tail else .005,"Landing gear chrome",7)

def main():
    colors=PAL
    D.base.PALETTE=colors;D.base.KEYS=list(colors)
    D.base.begin();bpy.context.preferences.filepaths.save_version=0
    E.export_atlas("tricario_heli", colors)
    sc=bpy.context.scene
    sc.name="LuanTTD | Tricario Helicopter #253"
    sc["Provenance"]="Original LuanTTD prop and invented livery; OpenTTD 16.0-RC1 engine #253 / AVI 38 parameter source only"
    sc["Native model"]="Nose −Z / wheel contact Y=0; separate main (+Y spin) and tail (X spin) rotor pivots"
    sc["Native main mount offset"]=list(PIVOT)
    sc["Native tail mount offset"]=list(TAIL)
    def group(title,fn):
        before=set(sc.objects);fn()
        return Art.new_collection(sc,title,[ob for ob in sc.objects if ob not in before])
    airframe=[]
    for name,fn in (("01 | Cabin shell, glazing and deck step",cabin),("02 | Turboshafts and tail cone",mechanics),
                    ("03 | Fixed wheel contacts",wheels)):
        airframe.extend(group(name,fn).objects)
    D.write_native(SimpleNamespace(series=253,stem="tricario_heli",export_name="Tricario Helicopter"),sc,airframe,"ground",colors)
    for title,tail,piv in (("Main rotor",False,PIVOT),("Tail rotor",True,TAIL)):
        g=group(title,lambda:rotor(tail))
        D.write_native(SimpleNamespace(series=253,stem="tricario_heli_"+("tail" if tail else "rotor"),export_name=title),
                       sc,list(g.objects),"ground",colors)
        for ob in g.objects:
            ob.location+=Vector(piv)
    look=(0,-.077,.209)
    camera=group("90 | Inspection only",lambda:bpy.ops.object.camera_add(location=(1.71,2.17,1.37)))
    cam=next(iter(camera.objects))
    cam.rotation_euler=(Vector(look)-cam.location).to_track_quat("-Z","Y").to_euler()
    cam.data.type="ORTHO";cam.data.ortho_scale=1.52;sc.camera=cam
    sc.render.engine="BLENDER_WORKBENCH";sc.render.resolution_x=1260;sc.render.resolution_y=930
    s=sc.display.shading;s.light="STUDIO";s.color_type="MATERIAL";s.show_shadows=True
    s.show_cavity=True;s.cavity_type="BOTH";s.cavity_ridge_factor=1.28
    sc.view_settings.view_transform="Standard"
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":
                view=area.spaces.active
                view.shading.color_type="MATERIAL"
                view.region_3d.view_location=look;view.region_3d.view_distance=1.9
                view.region_3d.view_rotation=cam.rotation_euler.to_quaternion()
    bpy.ops.wm.save_as_mainfile(filepath=str(D.ROOT/"art/stock_tricario_heli.blend"),compress=True)
    if out:=os.getenv("TRICARIO_RENDER"):
        sc.render.filepath=out;bpy.ops.render.render(write_still=True)

if __name__=="__main__":
    main()

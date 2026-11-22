#!/usr/bin/env python3
"""Author two original full-scale rail visuals for trains #13 and #14.
Run: blender -b -t 3 --python-exit-code 1 --python tools/build_early_diesel_art.py
Artwork and source-row references: art/rail_early_diesels.md.
"""
from math import tau
import os
from pathlib import Path
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_floss_47_art as K

R,J=K.R,K.J
F,B,D,Pipe=K.F,K.B,K.D,K.Pipe
AR=R.ROOT/"art"

VARIANTS={
    "hendry_25": dict(title="SH/Hendry '25' · #13", body="285d61", light="4c8086", stripe="c7be88",
        roof="435758", shoulder="35484b", bonnet="c59137", noses=False,
        bogies=(-.260,.260), axle=(-.051,.051),
        loft=((0,.220,.210,.560),(.243,.220,.210,.560),(.339,.218,.211,.551),
              (.390,.204,.216,.525),(.418,.190,.224,.499),(.429,.178,.224,.484))),
    "uu_37": dict(title="UU '37' · #14", body="8a5140", light="ac7765", stripe="ded0a5",
        roof="484448", shoulder="3e3a40", bonnet="d8a643", noses=True,
        bogies=(-.252,.252), axle=(-.062,0,.062),
        loft=((0,.218,.210,.570),(.185,.218,.210,.570),(.255,.222,.210,.567),
              (.312,.214,.215,.554),(.338,.196,.220,.510),(.360,.190,.224,.433),
              (.416,.177,.225,.416),(.439,.160,.235,.397),(.452,.144,.245,.380))),
}


def outline(w,b,t):
    """Eight-sided body with rounded upper shoulders and recessed solebar."""
    h=t-b
    return [(-.84*w,b),(.84*w,b),(.99*w,b+.12*h),(w,b+.72*h),
            (.96*w,b+.85*h),(.76*w,b+.96*h),(.49*w,t),
            (-.49*w,t),(-.76*w,b+.96*h),(-.96*w,b+.85*h),
            (-w,b+.72*h),(-.99*w,b+.12*h)]


def shell(m,p):
    specs=p["loft"]
    sections=[(-z,outline(w,b,t)) for z,w,b,t in specs[:0:-1]]
    sections += [(z,outline(w,b,t)) for z,w,b,t in specs]
    for (z0,a),(z1,b) in zip(sections,sections[1:]):
        mid=abs((z0+z1)/2)
        for k in range(len(a)):
            j=(k+1)%len(a)
            paint=("Roof aged crown" if k==6 else "Slate shoulder shade") if 3<=k<=8 else "Main deep green enamel"
            if k in (0,1,11): paint="Forest shadow enamel"
            group="Formed roof shoulder" if 3<=k<=8 else "Welded side enclosure"
            if mid > (.343 if p["noses"] else .398):
                paint="Yellow safety enamel" if 1<k<10 else "Yellow turned below"
                group="Rounded nose panel" if p["noses"] else "Shallow cab front"
            F(m,group,paint,[(a[k][0],z0,a[k][1]),(b[k][0],z1,b[k][1]),
                           (b[j][0],z1,b[j][1]),(a[j][0],z0,a[j][1])])
    for z,profile in (sections[0],sections[-1]):
        face=[(x,z,y) for x,y in profile]
        F(m,"Full formed cab end","Yellow safety enamel",face if z>0 else face[::-1])


def window(m,s,z_top,z_bot,h0,h1,w):
    L="Glazing black gasket"
    # Face of each cab is genuinely raked. Install separate glass pieces
    # on that moving plane, with a gasket and an upper reflected band.
    def pane(a,b,low,high,material,lift):
        points=[(x,s*(z_bot+(z_top-z_bot)*(y-h0)/(h1-h0)+lift),y)
                for x,y in ((a,low),(b,low),(b,high),(a,high))]
        F(m,"Driver's raked screen and seal",material,points if s<0 else points[::-1])
    for k in (-1,1):
        a,b=sorted((k*.010,k*w))
        pane(a,b,h0,h1,L,.004)
        pane(a+.006,b-.006,h0+.007,h1-.008,"Cab panorama blue-black",.006)
        pane(a+.009,b-.009,h1-.023,h1-.011,"Glass sky reflection",.008)
        z=lambda y:s*(z_bot+(z_top-z_bot)*(y-h0)/(h1-h0)+.010)
        Pipe(m,"Separate dash windscreen wiper",L,(k*.034,z(h0+.015),h0+.015),
             (k*.075,z(h1-.024),h1-.024),.0030,8)


def cabs(m,p):
    c=p["noses"]
    end=p["loft"][-1][0]
    for s in (-1,1):
        if c:
            window(m,s,.338,.366,.435,.516,.140)
            # Split nose code boxes and center opening, without tracing decals.
            for x in (-.084,.084):
                B(m,"Split headcode pod","Yellow turned below",x,s*(end+.001),.080,.012,.334,.372,.004)
                B(m,"Recessed headcode glazing","Dark code plate",x,s*(end+.008),.067,.006,.341,.366,.003)
                for off in (-.012,.012):
                    D(m,"Headcode lamp circles","Warm headlamp",(x+off,s*(end+.012),.352),.006,"z",-.001,.001,12)
            for dx in range(5):
                B(m,"Separate vertical nose intake bars","Black intake",.009*(dx-2),s*(end+.007),
                  .004,.009,.300,.323,.0005)
        else:
            window(m,s,.430,.432,.338,.463,.151)
            B(m,"Central headcode inset","Dark code plate",0,s*(end+.005),.116,.009,.286,.317,.004)
            for x in (-.038,-.015,.015,.038):
                B(m,"Separate headcode characters on dark roller","Number face pale",x,s*(end+.011),
                  .010,.003,.292,.309,.001)
        for x in (-.115,.115):
            D(m,"Round ruby marker built in beaded bezel","Red marker glass",(x,s*(end+.008),.276),.008,
              "z",-.004,.005,16)
            D(m,"Full steel buffer stem","Frame graphite",(x*.75,s*(end+.005),.175),.019,
              "z",-.018,.019,16)
            D(m,"Round scuffed buffer pad","Buffer bright face",(x*.75,s*(end+.022),.175),.022,
              "z",-.004,.004,20)
            Pipe(m,"Slack air hose to buffer beam","Tube steel",(x*.42,s*(end+.001),.183),
                (x*.68,s*(end+.020),.119),.004,8)
        B(m,"Welded buffer beam","Buffer beam rust red",0,s*(end-.004),.244,.033,.136,.203,.006)
        B(m,"Yoke and centered drawgear","Draw arm steel",0,s*.475,.033,.040,.138,.170,.003)
        B(m,"Independent coupler knuckle","Buffer bright face",0,s*.491,.029,.016,.143,.168,.003)


def lateral(m,p):
    for s in (-1,1):
        x=s*.219
        B(m,"Low tucked running solebar","Frame graphite",s*.171,0,.074,.782,.118,.193,.006)
        B(m,"Original cream belt and thin riser","Light two-tone sage",x,0,.008,.451,.358,.379,.002)
        # Raised intakes, open gaps and separate metallic grille slats.
        vents=((-.071,.112),(.058,.111)) if p["noses"] else ((-.126,.098),(.017,.101),(.132,.065))
        for z,n in vents:
            B(m,"Recessed louvre bed","Black intake",x,z,.012,n,.394,.495,.003)
            for i in range(8):
                y=.401+i*.0115
                B(m,"Pressed intake louvre with projected visor","Grille separator",s*.230,z,
                  .010,n-.008,y,y+.004,.0016)
            B(m,"Intake frost bead along upper edge","Grazing grille nickel",s*.231,z,.007,n,.493,.497,.0011)
        for z in (-.269,.269):
            xx=s*(.211 if p["noses"] else .218)
            B(m,"Cab access door welded flange","Body seam green",xx,z,.008,.062,.219,.492,.003)
            B(m,"Cab access door center","Dark inset green",xx+s*.005,z,.006,.050,.237,.482,.002)
            B(m,"Separate side cab glass","Side glass dull sheen",xx+s*.009,z,.006,.038,.399,.464,.002)
            Pipe(m,"Driver's forged door handle","Silver beading",(xx+s*.011,z-.013,.335),
                (xx+s*.011,z+.006,.335),.0025,6)
            for h in (.147,.171,.199):
                B(m,"Crew stair grated carriage step","Tube steel",s*.199,z,.073,.062,h,h+.007,.001)
        for z in (-.19,.184):
            Pipe(m,"Thin raised engine access separation","Body seam green",(x+s*.008,z,.227),
                 (x+s*.008,z,.347),.0016,6)
        B(m,"Cast and embossed fleet plate","Hood fleet ochre",s*.228,-.006,.004,.075,.303,.332,.002)
    # Fuel tank, traction component boxes and underframe cylinders.
    B(m,"Central chamfered steel fuel reservoir","Frame graphite",0,0,.301,.245,.071,.150,.018)
    for x,z in ((-.172,-.094),(.175,.119)):
        D(m,"Air cylinder shell with turned ends","Tube steel",(x,z,.105),.026,"z",-.086,.083,16)
        for j in (-1,1):
            D(m,"Separate reservoir weld band","Axle bearing bolt",(x,z+j*.034,.105),.028,"z",-.004,.006,16)
    # Roof has a raised fan grille, individual bars and separate exhaust ports.
    h=p["loft"][0][3]
    D(m,"Raised fan aperture collar","Heat patinated black",(0,-.078,0),.066,"h",h,h+.009,28)
    D(m,"Dark perforated roof fan well","Black intake",(0,-.078,0),.057,"h",h+.009,h+.011,28)
    for i in range(-4,5):
        x=i*.011
        span=(.052**2-x*x)**.5
        Pipe(m,"Physical formed roof fan guard","Grazing grille nickel",(x,-.078-span,h+.014),
             (x,-.078+span,h+.014),.0015,6)
    for z in (.067,.096):
        B(m,"Heat-stained paired engine exhaust paths","Heat patinated black",0,z,.053,.019,h,h+.011,.003)
        B(m,"Soot-black opening under raised exhaust rim","Black intake",0,z,.041,.013,h+.011,h+.013,.002)


def bogie(m,p,z):
    for s in (-1,1):
        B(m,"Equalizing bogie frame web","Frame graphite",s*.171,z,.061,.170 if p["noses"] else .147,.061,.122,.008)
        for offset in p["axle"]:
            at=z+offset
            B(m,"Visible axlebox and leaf grip","Foundry wheel grey",s*.193,at,.044,.032,.040,.084,.005)
            D(m,"Outboard bearing shoulder","Axle bearing bolt",(s*.22,at,.058),.010,"x",-.004,.005,14)
        for offset in (-.028,.031):
            for i in range(3):
                D(m,"Distinct spring pack per bogie frame","Tube steel",(s*.181,z+offset,0),.012,"h",
                  .097+.006*i,.101+.006*i,12)


def finish(tag,p):
    K.NAME="bl_rail_"+tag
    colors={"Main deep green enamel":p["body"],"Light two-tone sage":p["stripe"],
            "Sunlit main green":p["light"],"Dark inset green":p["light"],
            "Roof aged crown":p["roof"],"Slate shoulder shade":p["shoulder"],"Yellow safety enamel":p["bonnet"]}
    originals={k:K.PAL[k] for k in colors}
    K.PAL.update(colors)
    K.palette()
    def frame(m):
        shell(m,p)
        cabs(m,p)
        lateral(m,p)
    runtime=K.mesh()
    frame(runtime)
    for z in p["bogies"]:
        bogie(runtime,p,z)
        for d in p["axle"]: K.rolling(runtime,z+d)
    asset=R.MODELS/(K.NAME+".obj")
    R.export_obj(asset,K.W.local_obj(runtime))
    content=asset.read_text()
    asset.write_text("# Original LuanTTD diesel rail art; tools/build_early_diesel_art.py\n"+content.split("\n",1)[1])
    K.atlas()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene
    scene.name="LuanTTD · "+p["title"]
    scene["Reference"]="Original 3D art; see art/rail_early_diesels.md"
    scene["Mount"]="Stock length and rail .424 track gauge; runtime -Z forward."
    scene.view_settings.view_transform="Standard"
    mats=K.colors()
    permanent=K.mesh()
    frame(permanent)
    J.geometry(scene,"Dual cabs, chassis, glazing and machinery",permanent,mats)
    for i,z in enumerate(p["bogies"],1):
        support=K.mesh()
        bogie(support,p,z)
        parent=K.pivot(scene,f"Bogie {i}",mats,support,(0,z,.088))
        for j,d in enumerate(p["axle"],1):
            parts=K.mesh()
            K.rolling(parts,z+d)
            K.pivot(scene,f"Bogie {i} axle {j}",mats,parts,(0,z+d,K.RAD),parent,0,2*tau)
    scene.frame_start,scene.frame_end=1,49
    scene.frame_set(1)
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":
                view=area.spaces.active
                view.shading.color_type="MATERIAL"
                view.region_3d.view_location=(0,0,.29)
                view.region_3d.view_distance=1.55
                view.region_3d.view_rotation=Vector((.73,-.91,.44)).to_track_quat("Z","Y")
    bpy.ops.wm.save_as_mainfile(filepath=str(AR/("rail_"+tag+".blend")),compress=True)
    if review:=os.getenv("LUANTTD_DIESEL_REVIEW"):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        J.render(bpy.context.scene,R.stash(runtime,K.colors(),"Stock early diesel "+tag),str(Path(review)/(tag+".png")))
    K.PAL.update(originals)


if __name__=="__main__":
    for tag,variant in VARIANTS.items(): finish(tag,variant)

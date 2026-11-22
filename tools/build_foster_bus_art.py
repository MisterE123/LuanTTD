"""Original OpenTTD 14.1 Foster Bus #118 3D interpretation.
In Blender +Y is the nose and +Z is up; native OBJ has -Z nose, +Y up.
Native runtime uses uniform .40 visual size, origin at true tyre contact.
Optional FOSTER_REVIEW=/path/image.png renders an apron view.
"""
from math import cos, pi, sin, sqrt
import os
from pathlib import Path
import struct
import sys
import zlib

import bpy
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_extra_road_vehicle_art as V

ROOT=V.ROOT
B,C,M=V.bevel_box,V.round_between,V.add_mesh
PALETTE={
 "side blue":"4088bb","blue shoulder":"589dca","bottom blue":"2f6588",
 "navy sill":"24485f","rubber bumper":"2e3940","bumper bead":"48545a",
 "roof ice":"a7c3cd","roof high":"becbd0","cool steel":"7b9199","alloy face":"b3beb9",
 "glass seal":"2b3b45","dark glass":"223b4a","sky reflection":"496e84","glass tint":"365768",
 "fleet ivory":"e8e2c8","cool cream":"cad7d3","bright lamp":"ffdd9c","amber lens":"d89a49",
 "tail ruby":"bc4d45","clear lens":"c8c5b4","route black":"283839","amber text":"e3a663",
 "tyre outer":"272b31","tyre tread":"353a40","tyre side":"42494f","brake plate":"626d72",
 "warm underframe":"4c4a45","warm grille":"4a575a","gray door":"718d98",
 "cabin tread":"7f8a86","asphalt":"677078","road paint":"eac990",
}
KEYS=tuple(PALETTE)
STEM="bl_foster_bus"
WHEELS=(-.496,.482)
R=.114
TREAD_X=.252
NOSE=.830
TAIL=-.829
# Main panel run stations preserve the stock short single-floor proportions.
# Tapered end corners keep the swept body off the inside shoulder.
HULL=(
  (TAIL,.232),(-.813,.266),(-.782,.283),(-.727,.287),
  (.694,.287),(.764,.285),(.807,.270),(NOSE,.224),
)

def rod(n,a,b,r,c,k=8):
    return C(n,a,b,r,r,c,k)

def width(y):
    for (a,w),(b,q) in zip(HULL,HULL[1:]):
        if a<=y<=b:
            return w+(q-w)*(y-a)/(b-a)
    return HULL[0 if y<TAIL else -1][1]

def apron(y):
    d=min(abs(y-a) for a in WHEELS)
    if d >= .151:
        return .141
    # Flatten to a faceted but visibly sprung steel wheel well arch.
    return max(.141,.114+sqrt(max(0,.151**2-d*d)))

def lower():
    # Solid floor/body section is cut up to .265 through wheel apertures.
    # Beneath the shell, actual axles/springs bridge the three model pieces.
    wcurves=[y for y,_ in HULL]
    for loc in WHEELS:
        # Include exact intersections of arch with lower sill as boundaries.
        corner=sqrt(.151**2-(.141-.114)**2)
        wcurves += [loc+u*corner/7 for u in range(-7,8)]
    rings=[]
    for y in sorted(set(wcurves)):
        w,h=width(y),apron(y)
        rings.append((y,[(-w*.90,h+.015),(-w*.72,h),(w*.72,h),(w*.90,h+.015),
          (w,h+.029),(w,.340),(w*.98,.388),(-w*.98,.388),(-w,.340),(-w,h+.029)]))
    V.profile_hull("Stamped one-piece lower vehicle with four open wheel wells",rings,"side blue",
      ["bottom blue","navy sill","bottom blue","bottom blue","side blue",
       "side blue","blue shoulder","side blue","side blue","bottom blue"])
    for s in (-1,1):
        for aw in WHEELS:
            # Curved trim follows the actual apertures instead of being
            # painted on intact blue faces. It never intersects the tyre.
            V.wheel_arch(s*.290,aw,.113,.146,.024,"navy sill")
        for y,yspan in ((-.740,.090),(-.005,.600),(.748,.112)):
            B("Low replaced skirt rub strip",(s*(width(y)+.001),y,.187),
              (.013,yspan,.021),"navy sill",.006)
        # Side maintenance panels step out from metal by 1–2mm in world.
        for y,wide,h in ((-.687,.151,.255),(-.007,.265,.243)):
            x=s*(width(y)+.001)
            B("Rounded cut line around lower service hatch",(x,y,h),(.011,wide,.101),"bottom blue",.009)
            B("Pressed alloy service hatch center",(x+s*.007,y,h),
              (.009,wide-.012,.084),"side blue",.005)
            rod("Inset steel service lock",(x+s*.012,y-.031,h+.020),
                (x+s*.012,y+.022,h+.020),.0037,"alloy face",7)
    B("Strong steel lower splice channel", (0,-.010,.152),(.337,1.491,.043),"warm underframe",.015)
    C("Transverse forward torsion shaft",(-.252,.482,.114),(.252,.482,.114),.025,.025,"warm underframe",10)
    C("Transverse final drive and rear axle",(-.248,-.496,.114),(.248,-.496,.114),.033,.033,"warm underframe",12)
    for side in (-1,1):
        for yy in WHEELS:
            x=side*.20
            rod("Raked torsion pivot to lower frame",(x,yy,.112),(x*.67,yy+.175,.154),
                .014,"brake plate")
        rod("Lower bus control linkage",(side*.128,-.560,.146),(side*.128,.518,.146),
            .012,"brake plate")


def side_glazing():
    # Torso shell has taper at the pressed body ends but long low window
    # belt; satin dark windows are slabs with molded rubber surround.
    V.profile_hull("Integral wide low window bay",
      [(y,V.roof_contour(w*.989,.370,.631,.663)) for y,w in HULL],"side blue",
      ["bottom blue","bottom blue","side blue","side blue","blue shoulder","roof ice",
       "roof ice","roof ice","roof ice","blue shoulder","side blue","side blue","bottom blue"])
    for side in (-1,1):
        x=side*.285
        B("Continuous lower tinted body belt rail",(x,-.010,.398),(.019,1.560,.033),
            "blue shoulder",.007)
        B("Continuous rolled gutter above glazing",(x*.982,-.015,.594),(.017,1.548,.025),
            "roof ice",.006)
        # Narrow posts between tall integral windows evoke the single
        # continuous original OpenGFX window band from surveillance height.
        panels=[(-.649,.133),(-.442,.224),(-.188,.225),(.068,.226),(.316,.221)]
        if side<0: panels +=[(.548,.195),(.714,.093)]
        for yy,span in panels:
            xx=side*(width(yy)*.990)
            B("Rebated full-height public service window frame",(xx,yy,.510),
              (.017,span,.153),"glass seal",.009)
            B("Smoke-tinted passenger pane",(xx+side*.009,yy,.510),
              (.012,span-.019,.133),"dark glass",.007)
            B("Satin glazed sky return",(xx+side*.015,yy-.004,.543),
              (.006,span-.029,.034),"glass tint",.004)
            if yy not in (-.649,.714):
                B("Side sliding emergency window divider",(xx+side*.018,yy+span*.25,.531),
                  (.004,.007,.084),"cool steel",.001)
        # Passenger entrance is near-side only (x+ authoring, world x-
        # for local -Z heading) with real step recesses and threshold parts.
        if side>0:
            for yy in (.526,.670):
                xx=side*(width(yy)+.003)
                B("Glazed two-leaf inward folding door reveal",(xx,yy,.397),
                  (.021,.132,.370),"glass seal",.007)
                B("Boarding door deep smoke glazing",(xx+.011,yy,.470),
                  (.012,.110,.196),"dark glass",.006)
                B("Passenger door reflection band",(xx+.016,yy,.530),
                  (.008,.094,.043),"sky reflection",.003)
                B("Pressed blue kick plate",(xx+.011,yy,.299),
                  (.012,.110,.124),"side blue",.006)
                rod("Door leaf linkage pivot",(xx+.019,yy,.351),(xx+.019,yy,.396),
                  .0029,"alloy face",7)
            for xstep,level in ((.290,.198),(.282,.224),(.272,.250)):
                B("Raised entrance step tread",(xstep,.601,level),(.038,.282,.012),
                  "cabin tread",.004)
                B("Amber stainless steel tread nosing",(xstep+.018,.601,level+.006),
                  (.007,.279,.005),"fleet ivory",.001)
        V.typeface("Original side lettering FOSTER","FOSTER",(side*.296,-.111,.324),
            .041,side*pi/2,"fleet ivory")
        # Tucked-in mirror heads do not cross the lane center when split.
        rod("Foldable bus mirror arm",(side*.266,.742,.554),(side*.304,.759,.558),
            .006,"bumper bead",8)
        B("Rectangular modern road mirror housing",(side*.302,.763,.568),
          (.039,.030,.069),"rubber bumper",.008,(0,0,side*.12))
        B("Tinted back-facing mirror face",(side*.302,.747,.569),
          (.028,.010,.056),"alloy face",.005,(0,0,side*.12))


def ends():
    # Driver's pressed wrap windshield, split by a narrow structural mullion.
    # Its coordinates follow the two tapered end corners; one near edge
    # reaches slightly farther around the body than the other.
    for s in (-1,1):
        v=[(s*.008,.834,.428),(s*.175,.833,.429),(s*.228,.827,.435),
           (s*.247,.819,.468),(s*.236,.819,.570),(s*.206,.823,.589),
           (s*.172,.835,.600),(s*.008,.834,.600)]
        f=[tuple(range(len(v))) if s<0 else tuple(reversed(range(len(v))))]
        M("Pressed continuous panorama rubber trim",v,f,"glass seal")
        pivot=Vector((s*.115,.840,.516))
        p=[pivot+(Vector(x)-pivot)*.91+Vector((0,.008,0)) for x in v]
        M("Wide corner wraparound windscreen",p,f,"dark glass")
        glints=[(s*.023,.846,.569),(s*.163,.846,.564),
          (s*.186,.843,.570),(s*.178,.846,.578),(s*.023,.847,.585)]
        g=[tuple(range(len(glints))) if s<0 else tuple(reversed(range(len(glints))))]
        M("Sky reflected on flat forward glass",glints,g,"sky reflection")
        rod("Distinct manual windscreen wiper track",(s*.026,.850,.439),(s*.131,.850,.461),
            .0045,"rubber bumper",7)
        rod("Thin edge of forward wiper blade",(s*.099,.850,.458),(s*.194,.849,.472),
            .0036,"bumper bead",7)
    B("Forward windscreen mullion",(0,.839,.512),(.013,.018,.176),"glass seal",.004)
    B("Sunken destination display mounting",(0,.826,.616),
      (.376,.033,.055),"bottom blue",.009)
    B("Dark period rollsign glass",(0,.846,.615),(.355,.020,.045),"route black",.006)
    V.typeface("Raised rollsign route 08 TOWN","08 TOWN",(0,.858,.615),
        .038,pi,"amber text")
    B("Modern dark front fender bumper",(0,.826,.183),(.548,.060,.068),"rubber bumper",.015)
    B("Soft bumper front bead moulding",(0,.855,.204),(.460,.014,.020),"bumper bead",.006)
    B("Nose lightplate mounting",(0,.834,.265),(.487,.032,.109),"navy sill",.011)
    for s in (-1,1):
        x=s*.155
        B("Twin flush rectangular forward main lamps",(x,.859,.284),(.132,.017,.065),
          "alloy face",.005)
        B("Bright fluted headlight lens",(x,.869,.283),(.112,.016,.047),"bright lamp",.005)
        for d in (-.031,-.012,.010,.029):
            B("Fine pressed headlight glass ridges",(x+d,.879,.281),(.003,.005,.034),
                "clear lens",.001)
        B("Outer amber marker and turn lens",(s*.238,.851,.249),(.052,.028,.037),
          "amber lens",.007,(0,0,-s*.19))
        B("Outside hand mirror bracket reinforcement",(s*.264,.780,.478),
          (.024,.029,.045),"navy sill",.005)
        for k,ink in enumerate(("tail ruby","amber lens","tail ruby","clear lens")):
            B("Stacked molded rear illumination lens",(s*.202,-.844,.258+k*.022),
              (.074,.018,.016),ink,.005)
    B("Front lower radial grille inset",(0,.855,.278),(.114,.024,.077),"warm grille",.009)
    for n in range(5):
        B("Pressed horizontal grille slat",(0,.870,.251+n*.013),(.108,.006,.004),
            "cool steel",.001)
    B("Reflecting dark front number plate",(0,.859,.183),(.122,.020,.028),"route black",.005)
    V.typeface("County Fleet number 118","118",(0,.872,.183),.025,pi,"fleet ivory")
    B("Rear panoramic window pressure seal",(0,-.832,.504),(.438,.025,.166),"glass seal",.014)
    B("Broad rear panoramic ventilation glass",(0,-.850,.503),(.401,.018,.131),"dark glass",.012)
    B("Rear glass cool sky reflection",(0,-.861,.538),(.356,.007,.022),"glass tint",.005)
    B("Rear hinged access panel inset",(0,-.835,.266),(.317,.027,.158),"bottom blue",.010)
    for n in range(6):
        B("Deep cooling louver and vertical grille blade",(0,-.851,.222+n*.018),(.270,.009,.008),
            "warm grille",.003)
    B("Modern dark rear impact bumper",(0,-.826,.181),(.545,.061,.067),"rubber bumper",.015)
    B("Rear license insert",(0,-.860,.173),(.122,.013,.029),"fleet ivory",.005)
    V.typeface("County rear Fleet 118","118",(0,-.870,.174),.025,0,"route black")
    rod("Short rear exit pipe",(.135,-.763,.104),(.145,-.848,.103),.013,
        "warm grille",9)


def ventilation():
    V.profile_hull("Pressed ventilator unit with convex overhanging shell",
      [(y,V.roof_contour(w,.653,.694,.714)) for y,w in ((-.607,.128),(-.586,.171),
      (-.354,.171),(-.324,.137))],"roof ice",
      ["roof ice","roof ice","roof ice","roof high","roof high","roof high",
       "roof high","roof high","roof high","roof high","roof ice","roof ice","roof ice"])
    B("Roof induction shallow access door",(0,.327,.671),(.261,.186,.029),"roof high",.012)
    for s in (-1,1):
        for d in range(7):
            y=-.565+d*.030
            B("Slotted roof induction relief fan grille",(s*.162,y,.683),
              (.017,.014,.017),"cool steel",.002)
        for y in (-.092,.452):
            rod("Period gutters terminate below roof lip",(s*.224,y,.642),
                (s*.224,y+.091,.642),.0039,"cool cream",7)
    B("Convex clear roof escape panel",(0,-.066,.665),(.305,.099,.031),"roof high",.006)
    B("Escape hatch hinge on aft edge",(0,-.117,.671),(.259,.016,.013),"cool steel",.004)
    rod("Short rubber mounted original survey antenna",(.065,.174,.662),(.071,.214,.704),
        .0034,"warm grille",6)


def running_gear():
    # 24 ring facets give exact bottom tread edges. Parent each hub and tyre on
    # its own real axle pivot so wheel rigging does not require re-separating OBJ.
    for y,label in zip(WHEELS,("Rear","Front")):
        for s,side in ((-1,"off-side"),(1,"boarding side")):
            x=s*TREAD_X
            before=set(bpy.context.scene.objects)
            C("Rubber tyre shoulders and sidewall",(x-s*.029,y,R),(x+s*.028,y,R),
              R*.957,R*.957,"tyre outer",24)
            C("Certified tyre lower edge, contact Z=0",(x-s*.022,y,R),(x+s*.022,y,R),
              R,R,"tyre tread",24)
            C("Separate radial tyre finish ring",(x+s*.026,y,R),(x+s*.033,y,R),
              R*.838,R*.751,"tyre side",20)
            C("Brake drum behind scalloped steel hub",(x+s*.030,y,R),(x+s*.040,y,R),
              .069,.069,"brake plate",20)
            C("Stamped and lightly polished outer hub",(x+s*.040,y,R),(x+s*.049,y,R),
              .063,.056,"alloy face",20)
            C("Coaxial dark inner steel spindle",(x+s*.048,y,R),(x+s*.055,y,R),
              .022,.020,"cool steel",16)
            for j in range(6):
                a=j*pi/3
                yy,zz=y+.041*cos(a),R+.041*sin(a)
                C("Real recessed dark hub vent",(x+s*.048,yy,zz),(x+s*.050,yy,zz),
                  .006,.006,"brake plate",9)
                a+=pi/6
                yy,zz=y+.032*cos(a),R+.032*sin(a)
                C("Original axle retaining lug",(x+s*.049,yy,zz),(x+s*.054,yy,zz),
                  .0038,.0038,"cool cream",7)
            pivot=bpy.data.objects.new(f"{label} {side} wheel axle pivot",None)
            bpy.context.collection.objects.link(pivot)
            pivot.location=(x,y,R)
            pivot.empty_display_type="CIRCLE"
            pivot.empty_display_size=.038
            bpy.context.view_layer.update()
            for ob in list(bpy.context.scene.objects):
                if ob not in before and ob!=pivot:
                    w=ob.matrix_world.copy()
                    ob.parent=pivot
                    ob.matrix_world=w


def bus():
    lower()
    side_glazing()
    ends()
    ventilation()
    running_gear()


def begin():
    V.PALETTE=PALETTE
    V.KEYS=list(KEYS)
    V.begin()


def atlas():
    row=b"".join(bytes.fromhex(PALETTE[k])*8 for k in KEYS)
    assert len(KEYS)==32
    def chunk(k,d):
        return struct.pack(">I",len(d))+k+d+struct.pack(">I",zlib.crc32(k+d))
    out=b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",256,8,8,2,0,0,0))
    out+=chunk(b"IDAT",zlib.compress((b"\0"+row)*8))+chunk(b"IEND",b"")
    (ROOT/"mods/luanttd_core/textures"/f"{STEM}_atlas.png").write_bytes(out)


def export():
    begin()
    bus()
    s=bpy.context.scene
    s.name="LuanTTD · Foster Bus #118"
    s["openTTD_stock_engine_id"]=118
    s["forward_axis"]="+Y authoring, -Z native"
    s["native_scale"]=.40
    s["tread_contact_z"]=0.
    bpy.ops.object.select_all(action="DESELECT")
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":
                default=area.spaces.active
                default.region_3d.view_distance=3.3
                default.region_3d.view_location=Vector((0,0,.30))
                default.region_3d.view_rotation=Vector((.9,.59,.45)).to_track_quat("Z","Y")
                default.shading.color_type="MATERIAL"
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art/foster_bus.blend"),compress=True)
    pieces=[ob for ob in s.objects if ob.type=="MESH"]
    for ob in pieces: ob.select_set(True)
    bpy.context.view_layer.objects.active=pieces[0]
    bpy.ops.object.join()
    ob=bpy.context.object
    t=ob.matrix_world.copy()
    ob.matrix_world.identity()
    for v in ob.data.vertices:v.co=t@v.co
    ob.name="Foster_Bus_118"
    uv=ob.data.uv_layers.active or ob.data.uv_layers.new()
    for p in ob.data.polygons:
        idx=KEYS.index(ob.data.materials[p.material_index].name)
        for l in p.loop_indices:
            uv.data[l].uv=((idx+.5)/len(KEYS),.5)
    ob.data.update()
    bpy.ops.wm.obj_export(filepath=str(ROOT/"mods/luanttd_core/models"/f"{STEM}.obj"),
        export_selected_objects=True,export_materials=False,export_uv=True,export_normals=True,
        export_triangulated_mesh=True,global_scale=10,forward_axis="NEGATIVE_Z",up_axis="Y")


def review(path):
    begin()
    bus()
    B("Exact deck tire-contact at height zero",(0,0,-.034),
        (3.4,4.94,.068),"asphalt",.016)
    for y in (-1.54,-.94,-.35,.25,.85,1.45):
        B("Straight road centerline apron mark",( .49,y,.0008),(.038,.34,.0016),"road paint")
    bpy.ops.object.camera_add(location=(3.35,4.12,2.32))
    cam=bpy.context.object
    cam.rotation_euler=(Vector((0,0,.309))-cam.location).to_track_quat("-Z","Y").to_euler()
    cam.data.type="ORTHO"
    cam.data.ortho_scale=2.58
    s=bpy.context.scene
    s.camera=cam
    s.render.engine="BLENDER_WORKBENCH"
    s.render.resolution_x,s.render.resolution_y=1320,900
    s.render.resolution_percentage=100
    s.world=bpy.data.worlds.new("County streets midday")
    s.world.color=(.150,.170,.183)
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
    atlas()
    export()
    if (p:=os.getenv("FOSTER_REVIEW")):
        review(p)

"""Build the original Bayshore Trimotor (Blender 4.3 or later).

blender -b -t 2 --python-exit-code 1 --python tools/build_bayshore_trimotor_art.py
Set BAYLINE_TRIMOTOR_REVIEW=/tmp/trimotor.png to render front/rear apron views.
The passenger-aircraft archetype is OpenTTD 14.1 Sampson U52 (first small
engine, based on a Ju 52); this design imports no third-party art.
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

ROOT=V.ROOT
PALETTE={
    "chassis":"353b47", "rubber":"242931", "tread":"414958", "silver":"c6c8ba",
    "steel":"8397a2", "nozzle":"4c5b69", "bright lamp":"fff1ba", "tail":"bb604b",
    "dark glass":"294453", "light glass":"7399a7", "offwhite":"f0e1be", "enamel":"f6e8c6",
    "door rubber":"36434f", "aluminium":"abbaba", "cowl navy":"2b495f", "navy shade":"263e51",
    "fuselage ivory":"dacbad", "lining orange":"b95640", "rib light":"b6c5c4", "rib dark":"879b9e",
    "wood prop":"694d38", "wood prop edge":"987354", "tip cream":"d9b279", "engine rim":"b3b9b0",
    "radiator dark":"373942", "nav ruby":"d95b4a", "nav jade":"58ad9c", "exhaust bronze":"81604e",
    "grass":"5c6552", "pavement":"747a76", "stripe":"c8b790","wax red":"95513c",
}
V.PALETTE=PALETTE
V.KEYS=list(PALETTE)
B=V.bevel_box
C=V.round_between
M=V.add_mesh

# The nose is local +Y in Blender; export maps it into native local -Z.
# Wings aim to fit the two-node plan of one default OpenTTD taxi tile.
RIGHT_WING=(
    # x, leading y, trailing y, middle elevation, thickness
    (.067,.361,-.304,.340,.086),
    (.182,.328,-.382,.337,.083),
    (.438,.268,-.378,.340,.060),
    (.684,.184,-.328,.354,.045),
    (.882,.105,-.249,.365,.030),
    (.958,.041,-.167,.370,.017),
    (.978,.000,-.114,.370,.008),
)


def rod(name,a,b,r,material,n=8):
    return C(name,a,b,r,r,material,n)


def tube(name, radii, material, center_x=0, center_z=.4):
    seq=[]
    for y, radius, vertical in radii:
        seq.append((y,[(center_x+radius*cos(2*pi*k/16),center_z+vertical*sin(2*pi*k/16))
                       for k in range(16)]))
    return V.profile_hull(name,seq,material)


def barrel_shape(w, low, shoulder, top):
    # A torpedo cabin with the period-specific squared corrugated sidewalls.
    return [(-w*.67,low),(w*.67,low),(w*.89,low+.034),(w,low+.069),
            (w,shoulder),(w*.83,top-.025),(w*.52,top),(0,top+.004),
            (-w*.52,top),(-w*.83,top-.025),(-w,shoulder),(-w,low+.069),
            (-w*.89,low+.034)]


def hull():
    # Tail shrinks toward the post. The taper begins aft of the passenger cabin.
    spec=[(-.850,.031,.264,.323,.358),(-.738,.063,.231,.377,.413),
          (-.591,.094,.207,.404,.455),(-.407,.130,.199,.445,.494),
          (-.235,.145,.203,.478,.520),(.149,.148,.213,.496,.537),
          (.360,.150,.217,.494,.541),(.501,.149,.223,.482,.530),
          (.594,.134,.228,.435,.500),(.653,.110,.267,.395,.446),
          (.713,.094,.280,.363,.414)]
    V.profile_hull("Corrugated monocoque passenger fuselage",
        [(y,barrel_shape(w,a,b,c)) for y,w,a,b,c in spec],"fuselage ivory",
        ["aluminium","aluminium","aluminium","fuselage ivory","aluminium","aluminium",
         "rib light","rib light","aluminium","aluminium","fuselage ivory","aluminium","aluminium"])
    for s in (-1,1):
        for y in (-.370,-.278,-.181,-.082,.014,.112,.215,.310):
            V.side_windows(s*(.142 if y>-.295 else .132), y,.420,.063,.075,"offwhite")
        for now,next_ in zip(spec,spec[1:]):
            ya,wa,ha,_,tpa=now
            yb,wb,hb,_,tpb=next_
            if ya<-.59 or yb>.606:
                continue
            for h in range(7):
                t=h/6
                # Longitudinal strakes actually stand proud of the fuselage
                # shell; glazing and livery are kept clear of their silhouette.
                za=.262+.080*t+min(0,(ya+.35)*.08)
                zb=.262+.080*t+min(0,(yb+.35)*.08)
                for q,r in ((wa,wb),):
                    rod("Side pressed corrugation bead",(s*(q+.001),ya,za),
                        (s*(r+.001),yb,zb),.0018,"rib light",5)
            for off in (.352,.363):
                rod("Bayshore stripe roof-side molding",(s*(wa+.004),ya,off),
                    (s*(wb+.004),yb,off),.0045 if off==.352 else .0040,
                    "cowl navy" if off==.352 else "lining orange",6)
        # Wing-body fairing, rounded and low over the actual wing carry-through.
        B("Wing root fillet",(s*.136,.003,.332),(.087,.536,.085),"cowl navy",.021,(0,0,s*.066))
        # Corner of the same real cabin front roof is cut obliquely as glass.
        B("Flight deck side surround",(s*.136,.493,.466),(.018,.127,.079),"navy shade",.008,(0,0,s*.125))
        B("Flight deck side glazing",(s*.146,.497,.470),(.013,.110,.061),"dark glass",.006,(0,0,s*.125))
        B("Side weather reflection",(s*.154,.502,.483),(.007,.091,.012),"light glass",.002,(0,0,s*.125))
        V.typeface("Bayshore painted raised cabin legend","BAYSHORE",
            (s*.153,.097,.388),.041,s*pi/2,"cowl navy")
        B("Crew entry door edge",(s*.137,-.434,.362),(.013,.117,.179),"navy shade",.009)
        B("Crew entry door paint",(s*.146,-.437,.361),(.011,.106,.164),"fuselage ivory",.005)
        B("Passenger door window frame",(s*.152,-.433,.399),(.008,.053,.063),"enamel",.004)
        B("Passenger door glazed panel",(s*.158,-.433,.399),(.007,.040,.052),"dark glass",.003)
        B("Cabin door handle",(s*.163,-.465,.357),(.009,.029,.007),"steel",.002)
        B("Ground door threshold",(s*.157,-.434,.280),(.046,.112,.011),"cowl navy",.004)

    # Multi-pane cockpit: two intersecting windshield planes on the tapered brow.
    for s in (-1,1):
        pts=[(s*.008,.668,.415),(s*.093,.649,.413),(s*.117,.616,.429),
             (s*.107,.582,.491),(s*.087,.594,.497),(s*.008,.623,.494)]
        faces=[tuple(reversed(range(6))) if s>0 else tuple(range(6))]
        M("Cockpit windshield brass-edged surround",pts,faces,"navy shade")
        center=Vector((s*.064,.622,.450))
        panes=[center+(Vector(p)-center)*.90+Vector((0,.004,0)) for p in pts]
        M("Flat panoramic pilot glass",panes,faces,"dark glass")
        # The two planes' sky glints visibly show the nose orientation.
        for a,b in ((panes[4],panes[5]),):
            rod("Cockpit top glint",a+Vector((0,.002,-.008)),b+Vector((0,.002,-.008)),.0035,"light glass",6)
    rod("Vertical cockpit divider",(0,.670,.412),(0,.625,.496),.008,"silver",8)
    B("Cockpit top eyebrow",(0,.580,.510),(.195,.113,.029),"cowl navy",.011)
    B("Metal nose engine bearer",(0,.709,.371),(.190,.170,.157),"navy shade",.022)


def section(x,y0,y1,z,t):
    chord=y0-y1
    # Closed low-wing profile: leading edge, cambered top, thin trailing edge,
    # convex underside. Coordinate Y points into the leading edge.
    return [(x,y0-chord*f,z+t*h) for f,h in (
        (0,0),(.054,.276),(.178,.532),(.342,.566),(.599,.426),(.842,.212),
        (1,.013),(.820,-.095),(.531,-.220),(.243,-.308),(.072,-.228),
    )]

def wing_shell(side, stations, name, material, detail=True):
    rings=[section(side*x,lead,trail,z,t) for x,lead,trail,z,t in stations]
    q=len(rings[0]); n=len(rings)
    verts=[v for row in rings for v in row]
    f=[tuple(reversed(range(q))),tuple(range((n-1)*q,n*q))]
    cols=[material,material]
    for k in range(n-1):
        for j in range(q):
            nxt=(j+1)%q
            f.append((k*q+j,(k+1)*q+j,(k+1)*q+nxt,k*q+nxt))
            cols.append(("rib light","aluminium","aluminium","aluminium","rib light","rib dark",
                         "rib dark","nozzle","nozzle","aluminium","aluminium")[j] if detail else material)
    # Right-wing cross section order gives an inward zero-X first cap with
    # this profile; a reflected wing reverses all its normals.
    if side<0:
        f=[tuple(reversed(face)) for face in f]
    ob=M(name,verts,f,cols)
    # Recalculate after triangulated camber is assembled to preserve watertight
    # exterior normals under Luanti backface culling.
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active=ob
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    return ob


def wing_interpolate(x):
    for a,b in zip(RIGHT_WING,RIGHT_WING[1:]):
        if a[0]<=x<=b[0]:
            t=(x-a[0])/(b[0]-a[0])
            return (x,*((1-t)*p+t*q for p,q in zip(a[1:],b[1:])))
    raise ValueError(x)


def wing_corrugation(side):
    # At survey distance the corrugation still reads through the upper
    # alternating light/dark strips, and has actual mesh relief.
    for x0 in (.269,.583,.712):
        x1={.269:.369,.583:.694,.712:.899}[x0]
        for j in range(6):
            t=.202+j*.092
            for side_tone,r1 in (("rib light",.0027),):
                f=[]
                for x in (x0,(x0+x1)*.5,x1):
                    _,yl,yt,z,th=wing_interpolate(x)
                    # Linear knots reproduce the exact top foil and keep each
                    # rib in front of, rather than inside, its sloping foil.
                    knots=((.178,.532),(.342,.566),(.599,.426),(.842,.212))
                    for (a,h),(b,i) in zip(knots,knots[1:]):
                        if a<=t<=b:
                            h=h+(i-h)*(t-a)/(b-a)
                            f.append((side*x,yl-t*(yl-yt),z+th*h+.0022))
                            break
                for a,b in zip(f,f[1:]):
                    rod("Wing pressed corrugation strip",a,b,r1,side_tone,6)


def upper_text(tag,value,x,y,z,size):
    cr=bpy.data.curves.new(tag,"FONT")
    cr.body=value
    cr.align_x="CENTER"
    cr.align_y="CENTER"
    cr.size=size
    cr.extrude=.00065
    cr.resolution_u=2
    ob=bpy.data.objects.new(tag,cr)
    bpy.context.collection.objects.link(ob)
    ob.location=(x,y,z)
    ob.rotation_euler.z=0
    ob.data.materials.append(V.MATS["cowl navy"])
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active=ob
    bpy.ops.object.convert(target="MESH")


def airframe():
    for s in (-1,1):
        wing_shell(s,RIGHT_WING,"Heavy tapered metal wing and integral root","aluminium")
        wing_corrugation(s)
        actuated=[(.577,-.201,-.370,.351,.025),(.712,-.185,-.343,.357,.022),
                  (.867,-.159,-.272,.367,.014),(.950,-.126,-.183,.368,.009)]
        wing_shell(s,actuated,"Distinct corrugated wing aileron","aluminium",False)
        rod("Visible flap hinge line",(s*.602,-.254,.368),(s*.876,-.207,.372),.003,
          "navy shade",7)
        for x in (.622,.725,.819):
            _,lead,trail,z,t=wing_interpolate(x)
            y=(lead+.078)-.44*(lead-trail)
            B("Inspection plate atop outer wing",(s*x,y,z+t*.53),(.049,.064,.006),"rib dark",.006)
        B("Outer wing navigation light shoe",(s*.948,-.017,.372),(.035,.083,.018),"cowl navy",.006)
        B("Wingtip navigation light lens",(s*.973,-.016,.370),(.019,.039,.014),
          "nav ruby" if s<0 else "nav jade",.004)
        # A navy tailplane with warm leading hem and independent elevator.
        tail=[(.035,-.500,-.805,.355,.039),(.185,-.556,-.824,.365,.030),
              (.291,-.635,-.832,.373,.021),(.334,-.744,-.813,.373,.009)]
        wing_shell(s,tail,"Horizontal roofless tail stabilizer","cowl navy",False)
        lift=[(.057,-.736,-.847,.355,.022),(.259,-.732,-.845,.372,.011),
              (.332,-.758,-.803,.370,.005)]
        wing_shell(s,lift,"Metal elevator trailing edge","lining orange",False)
        rod("Tail trim hinge",(s*.074,-.727,.364),(s*.328,-.748,.375),.0032,"silver",6)
    # Vertical tail is a real paired contour, two sides are not a paper decal.
    y_z=[(-.541,.441),(-.618,.536),(-.719,.665),(-.785,.676),(-.830,.644),
         (-.863,.553),(-.857,.380),(-.699,.394)]
    verts=[]
    for t in (-1,1):
        verts.extend((t*(.026-.012*(z-.38)/.30),y,z) for y,z in y_z)
    q=len(y_z)
    faces=[tuple(range(q)),tuple(reversed(range(q,q*2)))]
    faces += [(i,q+i,q+((i+1)%q),(i+1)%q) for i in range(q)]
    M("Dark blue dorsal fin with solid ribs",verts,faces,"cowl navy")
    for side in (-1,1):
        # Deliberately simple original identity marks: not a real line or airline.
        for j,mat in enumerate(("lining orange","offwhite","lining orange")):
            B("Fin registration color flash",(side*.025,-.759,.558-j*.025),(.006,.101,.017),
              mat,.002,(0,0,side*.045))
        B("Tail trim tab cast hinge",(side*.022,-.811,.484),(.022,.018,.108),"steel",.004)
    B("Trailing rudder", (0,-.855,.503),(.031,.067,.245),"navy shade",.011,
      (0,0,.034))
    upper_text("Wartime-style civilian upper wing registration","BA 024",.750,-.031,.391,.054)
    upper_text("Civil transit plate","BAY",-.751,-.031,.389,.055)


def blades(p,blade_count=2,initial=0):
    x,y,z=p
    before=set(bpy.context.scene.objects)
    # Two fixed-pitch period blades each deliberately rotated out of plane
    # for a tapered wood profile, with a sharply readable bright tip.
    for i in range(blade_count):
        a=initial+2*pi*i/blade_count
        verts=[]
        stations=((.014,.018,.002),(.038,.022,.010),(.092,.027,.016),
                  (.136,.022,.021),(.163,.016,.023),(.181,.0039,.024))
        for rr,hh,n in stations:
            for tang,depth in ((-hh,-.005),(hh,-.004),(hh,+.007),(-hh,.005)):
                xx=x+rr*cos(a)-tang*sin(a)
                zz=z+rr*sin(a)+tang*cos(a)
                verts.append((xx,y+depth+(n if tang>0 else 0),zz))
        faces=[(3,2,1,0),(20,21,22,23)]
        mats=["wood prop","tip cream"]
        for j in range(5):
            for k in range(4):
                faces.append((j*4+k,j*4+(k+1)%4,(j+1)*4+(k+1)%4,(j+1)*4+k))
                mats.append("tip cream" if j==4 else ("wood prop edge" if k in (1,2) else "wood prop"))
        ob=M("Carved fixed-pitch wooden propeller blade",verts,faces,mats)
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True)
        bpy.context.view_layer.objects.active=ob
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.normals_make_consistent(inside=False)
        bpy.ops.object.mode_set(mode="OBJECT")
    C("Metal propeller boss and bearing",(x,y-.018,z),(x,y+.027,z),.030,.024,"engine rim",12)
    C("Small period spinner",(x,y+.022,z),(x,y+.051,z),.024,.009,"offwhite",12)

    parts=[o for o in bpy.context.scene.objects if o not in before]
    station="port" if x<-.01 else ("starboard" if x>.01 else "nose")
    pivot=bpy.data.objects.new("Propeller pivot · "+station,None)
    bpy.context.collection.objects.link(pivot)
    pivot.location=p
    pivot.empty_display_type="PLAIN_AXES"
    pivot.empty_display_size=.055
    bpy.context.view_layer.update()
    for part in parts:
        world=part.matrix_world.copy()
        part.parent=pivot
        part.matrix_world=world


def powerplants():
    # Three distinctly modeled radial nacelles with engine cylinders, cowling
    # rings, air inlet and original matching livery cuffs.
    for x,y,z,phase in ((-.430,.400,.373,-.63),(0,.754,.357,.15),(.430,.400,.373,1.12)):
        r=.106 if x else .110
        body=[(y-.125,r*.58,r*.58),(y-.081,r*.92,r*.92),(y-.040,r,r),
              (y+.021,r*.991,r*.98),(y+.050,r*.78,r*.78)]
        tube("All-metal radial engine cowling envelope",body,"cowl navy",center_x=x,center_z=z)
        C("Red engine banding",(x,y+.026,z),(x,y+.045,z),r*.961,r*.873,"lining orange",16)
        C("Rounded metal cowling leading edge",(x,y+.040,z),(x,y+.057,z),r*.884,r*.760,
          "engine rim",18)
        C("Dark face behind engine cylinders",(x,y+.056,z),(x,y+.061,z),r*.735,r*.731,
          "radiator dark",18)
        C("Central radial casing",(x,y+.061,z),(x,y+.069,z),r*.278,r*.273,"steel",12)
        for i in range(7):
            a=2*pi*i/7
            u,v=cos(a),sin(a)
            ra,rb=r*.28,r*.62
            rod("Visible radial cylinder",(x+u*ra,y+.064,z+v*ra),(x+u*rb,y+.066,z+v*rb),.012,
              "steel",8)
            for j in range(2):
                a1=(ra+(.012+j*.016))
                rod("Cylinder fin line",(x+u*a1-v*.012,y+.070,z+v*a1+u*.012),
                    (x+u*a1+v*.012,y+.072,z+v*a1-u*.012),.0026,"radiator dark",6)
        # Each individual prop is editable and kept as a distinct rotating
        # assembly in Blender; the native OBJ is the static display mesh.
        blades((x,y+.088,z),initial=phase)
        for side in (-1,1):
            rod("Short radial exhaust stub",(x+side*r*.61,y-.03,z-r*.50),
                (x+side*r*.76,y-.106,z-r*.58),.0135,"exhaust bronze",8)
        if x:
            tube("Inner fixed gear nacelle continuation",
                 [(y-.348,r*.39,r*.35),(y-.275,r*.63,r*.59),(y-.084,r*.82,r*.69)],
                 "aluminium",center_x=x,center_z=z-.010)


def undercarriage():
    # Fixed period main wheels, not gear plates painted on the side.
    for side in (-1,1):
        x=side*.416
        z=.105
        y=.118
        struts=((side*.305,.214,.340),(side*.449,.133,.350),(side*.334,-.036,.327))
        for at in struts:
            rod("Triangulated main landing strut",(x,y,z),at,.0115,"steel",10)
        C("Fixed oil damper jacket",(x,y,.117),(side*.443,.134,.259),.024,.018,"cowl navy",12)
        C("Bulged rubber tyre",(x-side*.028,y,z),(x+side*.027,y,z),.105,.105,"rubber",24)
        C("Main wheel silver hubcap",(x+side*.025,y,z),(x+side*.032,y,z),.067,.052,"silver",16)
        C("Main axle bearing",(x+side*.030,y,z),(x+side*.036,y,z),.026,.022,"steel",12)
        for l in range(5):
            a=2*pi*l/5
            p=(x+side*.034,y+.037*cos(a),z+.037*sin(a))
            q=(x+side*.039,p[1],p[2])
            rod("Wheel stud cap",p,q,.0057,"navy shade",5)
        B("Lower leg aerodynamic wheel spat",(x,.146,.213),(.095,.165,.178),"aluminium",.023,(.14,0,0))
    rod("Castoring tail spring",(0,-.709,.247),(0,-.748,.052),.0083,"steel",9)
    rod("Tailwheel damped trailing arm",(0,-.703,.192),(0,-.748,.063),.012,"cowl navy",8)
    C("Fixed tailwheel tire",(-.019,-.748,.053),(.019,-.748,.053),.053,.053,"rubber",20)
    C("Tailwheel hub",(-.023,-.748,.053),(.023,-.748,.053),.028,.028,"steel",12)


def trimotor():
    hull()
    airframe()
    powerplants()
    undercarriage()


def palette():
    assert len(PALETTE)==32
    line=b"".join(bytes.fromhex(PALETTE[key])*8 for key in V.KEYS)
    def chunk(tag,data):
        return struct.pack(">I",len(data))+tag+data+struct.pack(">I",zlib.crc32(tag+data))
    data=b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR", struct.pack(">IIBBBBB",256,8,8,2,0,0,0))
    data+=chunk(b"IDAT",zlib.compress((b"\0"+line)*8))+chunk(b"IEND",b"")
    (ROOT/"mods/luanttd_core/textures/bl_bayshore_trimotor_palette.png").write_bytes(data)


def merge(shapes):
    bpy.ops.object.select_all(action="DESELECT")
    for ob in shapes:
        ob.select_set(True)
    bpy.context.view_layer.objects.active=shapes[0]
    bpy.ops.object.join()
    o=bpy.context.object
    transform=o.matrix_world.copy()
    o.matrix_world.identity()
    for v in o.data.vertices:
        v.co=transform@v.co
    return o


def export():
    V.begin()
    trimotor()
    bpy.context.scene.name="LuanTTD / Bayshore Trimotor"
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art/bayshore_trimotor.blend"),compress=True)
    o=merge([ob for ob in bpy.context.scene.objects if ob.type=="MESH"])
    uv=o.data.uv_layers.active or o.data.uv_layers.new()
    for face in o.data.polygons:
        k=V.KEYS.index(o.data.materials[face.material_index].name)
        for l in face.loop_indices:
            uv.data[l].uv=((k+.5)/32,.5)
    o.data.update()
    bpy.ops.wm.obj_export(filepath=str(ROOT/"mods/luanttd_core/models/bl_bayshore_trimotor.obj"),
        export_selected_objects=True,export_materials=False,export_uv=True,export_normals=True,
        export_triangulated_mesh=True,global_scale=10,forward_axis="NEGATIVE_Z",up_axis="Y")


def preview(path):
    V.begin()
    for reverse in (False,True):
        before=set(bpy.context.scene.objects)
        trimotor()
        o=merge([ob for ob in bpy.context.scene.objects if ob not in before and ob.type=="MESH"])
        for v in o.data.vertices:
            x,y,z=v.co
            v.co=Vector(((x if not reverse else -x)+(1.06 if reverse else -1.06),
                         (y if not reverse else -y)+(.42 if reverse else -.34),z))
    B("Field and concrete apron", (0,0,-.060),(4.46,2.91,.118),"grass",.032)
    B("Parked aircraft concrete hardstand", (0,.10,-.032),(4.31,2.67,.064),"pavement",.017)
    for x in (-1.63,-.81,0,.81,1.63):
        B("Apron joint",(x,.10,.002),( .010,2.59,.004),"nozzle",.001)
    for y in (-.71,.110,.92):
        B("Apron joint",(0,y,.0018),(4.26,.010,.004),"nozzle",.001)
    for x in (-1.06,1.06):
        for y in (-1.02,1.28):
            B("Apron yellow taxi stand line",(x,y,.004),(.052,.213,.008),"stripe",.002)
    bpy.ops.object.camera_add(location=(3.0,7.6,5.4))
    cam=bpy.context.object
    cam.rotation_euler=(Vector((0,0,.26))-cam.location).to_track_quat("-Z","Y").to_euler()
    cam.data.type="ORTHO"
    cam.data.ortho_scale=5.63
    s=bpy.context.scene
    s.camera=cam
    s.render.engine="BLENDER_WORKBENCH"
    s.render.resolution_x,s.render.resolution_y=1500,1020
    s.render.resolution_percentage=100
    s.world=bpy.data.worlds.new("Aerodrome review sky")
    s.world.color=(.145,.174,.180)
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
    if (p:=os.getenv("BAYLINE_TRIMOTOR_REVIEW")):
        preview(p)

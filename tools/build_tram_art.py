"""Build original LuanTTD streetcar, embedded tramway and single side masts.

Run Blender 4.3+: blender -b -t 2 --python-exit-code 1 --python tools/build_tram_art.py
Set BAYLINE_TRAM_REVIEW=/tmp/tram.png for a front/rear and trackwork preview.

Road notation: bit 1=-Z, 2=+X, 4=+Z, 8=-X. Track overlays sit at the
even x/z corner and one node above flat grade (grade is local Y=-.5);
the streetcar is an entity (10 OBJ units per node) with local -Z nose.
"""
import math
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
COLORS={
    # Preserve shared helper material names; values are purpose-made for this kit.
    "chassis":"33343a","rubber":"2a2d2c","tread":"3b4140","silver":"c8c7ae",
    "steel":"82918f","nozzle":"4c5049","bright lamp":"ffe7a3","tail":"ca5141",
    "dark glass":"263e43","light glass":"6e969f","offwhite":"ead9aa","enamel":"fbebc6",
    "wine shade":"543534","interior":"846144","sign black":"344748","indicator":"df8e52",
    "door rubber":"363e3a","trolley green":"356655","trolley dark":"274d3c","trolley light":"7ca18a",
    "red brown":"8d503b","copper":"b68450","weathered black":"394743","clay":"b78865",
    "ceramic":"e2ddc0","rail matt":"596365","rail head":"babbb1","groove":"343739",
    "wire copper":"705740","concrete":"a09987","brass":"dba56a",
}
V.PALETTE=COLORS
V.KEYS=list(COLORS)
B=V.bevel_box
C=V.round_between
M=V.add_mesh

SCALE=.40
TRAM_GRADE=.012
CONTACT=.500
PANTOGRAPH=(CONTACT-TRAM_GRADE)/SCALE
LANE=.155
GAUGE=.106
BEND_RADIUS=.36


def rod(tag, a,b, radius, surf, facets=8):
    return C(tag,a,b,radius,radius,surf,facets)


def streetcar():
    # Enclosed, double-ended single car with arched clerestory, full-length
    # below-floor traction pack, and offside steps at both ends.
    positions=[(-.883,.208),(-.856,.261),(-.796,.278),(.797,.278),(.858,.260),(.885,.208)]
    B("Channel underframe",(0,0,.139),(.419,1.55,.081),"chassis",.010)
    B("Traction resistor box",(0,.108,.121),(.319,.354,.10),"weathered black",.018)
    for i in (-1,1):
        B("Electrical motor housing",(i*.092,-.315,.118),(.088,.223,.071),"nozzle",.012)
    V.profile_hull("Steel lower body with sloping buffer beams",
        [(y,V.roof_contour(w,.185,.391,.421)) for y,w in positions],"trolley green",
        ["trolley dark","trolley dark","trolley green","trolley light","trolley green","trolley green",
         "trolley green","trolley green","trolley green","trolley green","trolley light","trolley green","trolley dark"])
    V.profile_hull("Cream sash and rounded vestibules",
        [(y,V.roof_contour(w*.985,.376,.660,.696)) for y,w in positions],"offwhite")
    V.profile_hull("Centred clerestory arch",
        [(y,V.roof_contour(w*.89,.674,.744,.786)) for y,w in positions[1:-1]],"trolley dark")
    V.profile_hull("Raised centre crown",
        [(y,V.roof_contour(w*.746,.738,.774,.800)) for y,w in positions[2:-2]],"weathered black")
    for sign in (-1,1):
        # Six large rectangular coachwork sashes, with genuine door openings
        # distinguished by inset frame, lower steps and kick plates.
        sashes=[(-.66,.143),(-.457,.172),(-.255,.170),(-.052,.169),
                (.155,.167),(.361,.166),(.566,.170)]
        if sign==-1:
            sashes=[(-y,w) for y,w in sashes]
        for y,w in sashes:
            V.side_windows(sign*.274,y,.523,w,.176)
        door=sign*.708
        for y in (door-.063,door+.063):
            B("Vestibule folding door frame",(sign*.275,y,.446),(.022,.131,.407),"door rubber",.008)
            B("Door steel lower panel",(sign*.290,y,.316),(.016,.117,.139),"trolley green",.004)
            V.side_windows(sign*.290,y,.502,.102,.178)
            B("Brass grab handle",(sign*.303,y+.030,.298),(.011,.011,.074),"brass",.002)
        B("First running step",(sign*.274,door,.160),(.097,.288,.036),"chassis",.005)
        B("Enamel side skirt belt",(sign*.280,0,.384),(.014,1.52,.020),"trolley light",.004)
        B("Bright lower waist rail",(sign*.281,0,.367),(.016,1.50,.010),"brass",.002)
        B("Inset city plate",(sign*.285,0,.296),(.013,.271,.087),"trolley dark",.004)
        V.typeface("Raised city side lettering","QUAY", (sign*.294,.0,.296),.064,sign*math.pi/2,"offwhite")
        for j in range(7):
            B("Clerestory ventilation pane",(sign*.204,(j-3)*.178,.749),(.017,.145,.038),"dark glass",.004)
        B("Clerestory edge moulding",(sign*.211,0,.777),(.027,1.53,.019),"trolley light",.004)
    for end in (-1,1):
        for side in (-1,1):
            # The end section is slightly tapered; all glazing is ahead of
            # the base hull, and not a texture painted on the grille.
            B("Double-ended cab windshield frame",(side*.092,end*.891,.530),(.158,.024,.180),"door rubber",.012)
            B("Double-ended cab windshield",(side*.092,end*.906,.531),(.138,.012,.155),"dark glass",.008)
            B("End glass glint",(side*.094,end*.913,.584),(.116,.006,.027),"light glass",.004)
            B("Cab window wiper",(side*.088,end*.915,.487),(.059,.006,.010),"silver",.002,(0,.19*side,0))
            B("Rail marker lens",(side*.173,end*.898,.268),(.044,.024,.031),"tail",.006)
        B("Front destination sign enamel surround",(0,end*.888,.646),(.259,.029,.050),"silver",.004)
        B("Front destination roller blind",(0,end*.907,.647),(.239,.014,.038),"sign black",.003)
        V.typeface("Destination: Quay 2","2  QUAY",(0,end*.919,.648),.048,
                   math.pi if end==1 else 0,"enamel")
        C("Central headlamp body",(0,end*.857,.309),(0,end*.911,.309),.055,.052,"trolley dark")
        C("Headlamp retaining rim",(0,end*.907,.309),(0,end*.921,.309),.049,.043,"silver")
        C("Glass of working end",(0,end*.918,.309),(0,end*.925,.309),.041,.037,"bright lamp")
        B("Buffed vehicle impact rail",(0,end*.889,.188),(.408,.066,.045),"steel",.011)
        B("Folded coupling block",(0,end*.921,.152),(.104,.086,.059),"chassis",.008)
        B("End step mounting",(0,end*.846,.130),(.331,.076,.027),"nozzle",.004)
    # Gauge measured from wheel centres. Segment thickness gives positive
    # contact at rail flange; no road tyres on the streetcar.
    wheel_x=GAUGE/(2*SCALE)
    for y in (-.517,.517):
        rod("Wheelset live shaft",(-.187,y,.109),(.187,y,.109),.026,"steel")
        for s in (-1,1):
            x=s*wheel_x
            C("Forged tram wheel",(x-s*.035,y,.109),(x+s*.032,y,.109),.109,.109,"chassis",20)
            C("Turned running tread",(x-s*.023,y,.109),(x+s*.015,y,.109),.109,.109,"steel",20)
            C("Flange and press-fit wheel boss",(x+s*.031,y,.109),(x+s*.045,y,.109),.075,.065,"nozzle",16)
            C("Lubrication hub",(x+s*.041,y,.109),(x+s*.059,y,.109),.036,.035,"steel",12)
            B("Side truck primary suspension",(s*.192,y,.145),(.048,.226,.061),"chassis",.006)
            for j in range(4):
                B("Leaf spring face",(s*.220,y,.132+j*.008),(.015,.142-j*.009,.005),"steel",.001)
    # Raised diamond pantograph, transverse collector at the exact wire datum.
    # Roof assembly has separate ceramic shoes and visible scissor hinges.
    B("Pantograph footboard",(0,-.048,.824),(.374,.326,.079),"weathered black",.010)
    for xs in (-1,1):
        for ys in (-1,1):
            C("Ribbed base ceramic insulator",(xs*.116,ys*.108,.858),(xs*.116,ys*.108,.909),
              .041,.030,"ceramic",12)
            for j in range(3):
                C("Insulator skirt",(xs*.116,ys*.108,.859+j*.016),
                  (xs*.116,ys*.108,.868+j*.016),.036,.043,"enamel",12)
        for ys in (-1,1):
            rod("Lower pantograph arm",(xs*.105,ys*.068,.913),(xs*.112,ys*.256,1.043),.0129,"weathered black")
            rod("Upper pantograph arm",(xs*.112,ys*.256,1.043),(xs*.100,ys*.061,1.187),.0130,"steel")
            C("Scissor arm pin",(xs*.112-.014,ys*.256,1.043),(xs*.112+.014,ys*.256,1.043),
              .018,.018,"brass",9)
        rod("Collector head bridle",(xs*.083,-.079,1.186),(xs*.083,.079,1.186),.013,"steel")
    for y in (-.044,.044):
        rod("Copper contact reach",(-.165,y,PANTOGRAPH-.008),(.165,y,PANTOGRAPH-.008),.008,"copper",12)
        rod("Contact bar turned tips",(-.221,y,PANTOGRAPH-.024),(-.162,y,PANTOGRAPH-.0075),.0065,"copper",8)
        rod("Contact bar turned tips",(.162,y,PANTOGRAPH-.0075),(.221,y,PANTOGRAPH-.024),.0065,"copper",8)
    B("Carbon shoe under copper wire",(0,0,PANTOGRAPH-.006),(.233,.081,.012),"weathered black",.002)
    for y in (-.592,.592):
        B("Metal roof electrical hatch",(0,y,.811),(.219,.160,.039),"trolley dark",.013)
        for j in range(3):
            B("Roof vent slot",(0,y+(j-1)*.030,.831),(.136,.010,.007),"steel",.002)


ARM=((0,-1),(1,0),(0,1),(-1,0)) # world x,z
def path_spans(mask):
    arms=[i for i in range(4) if mask&(1<<i)]
    # A stub has two visually ended tracks up to its exact tile centre.
    if len(arms)==1:
        key=arms[0]
        x,z=ARM[key]
        return [[(x,z,-x,-z),(0,0,-x,-z)]]
    out=[]
    for n,i in enumerate(arms):
        for j in arms[n+1:]:
            ax,az=ARM[i]; bx,bz=ARM[j]
            if (i-j)%2==0:
                out.append([(ax,az,-ax,-az),(-ax,-az,-ax,-az)])
                continue
            r=BEND_RADIUS
            points=[(ax,az,-ax,-az)]
            for k in range(13):
                t=k/12
                q=1-t
                x,z=r*(q*q*ax+t*t*bx),r*(q*q*az+t*t*bz)
                vx,vz=-q*ax+t*bx,-q*az+t*bz
                norm=math.hypot(vx,vz)
                points.append((x,z,vx/norm,vz/norm))
            points.append((bx,bz,bx,bz))
            out.append(points)
    return out

def segment(name, a,b, lateral, width, y0,y1, color):
    ax,az,adx,adz=a; bx,bz,bdx,bdz=b
    def point(x,z,dx,dz,offset,h):
        # World X/Z direction is transformed into the reflected OBJ axes.
        return (-x-dz*offset,-z+dx*offset,h)
    lo,hi=lateral-width*.5,lateral+width*.5
    verts=[point(x,z,dx,dz,m,h) for x,z,dx,dz in (a,b) for m in (lo,hi) for h in (y0,y1)]
    # Box strips have outward faces: expose head, retaining sides and feet.
    faces=((0,4,5,1),(2,3,7,6),(1,5,7,3),(0,2,6,4),(0,1,3,2),(4,6,7,5))
    if (Vector(verts[5])-Vector(verts[1])).cross(Vector(verts[7])-Vector(verts[1])).z<0:
        faces=[tuple(reversed(face)) for face in faces]
    return M(name,verts,faces,color)

def tramway(mask, wires=False):
    seen=set()
    # Shared geometric spans are deduplicated on 3/4-arm turnout meshes.
    for p in path_spans(mask):
        for a,b in zip(p,p[1:]):
            for lane in (-LANE,LANE):
                pieces=[(lane,.012,CONTACT,CONTACT+.013,"wire copper")] if wires else []
                if not wires:
                    for side in (-1,1):
                        r=lane+side*GAUGE*.5
                        pieces += [(r,.032,.001,.006,"groove"),(r,.013,.006,TRAM_GRADE,"rail head")]
                for lateral,width,y0,y1,col in pieces:
                    center_a=(round(a[0]+lateral*a[3],4),round(a[1]-lateral*a[2],4))
                    center_b=(round(b[0]+lateral*b[3],4),round(b[1]-lateral*b[2],4))
                    key=tuple(sorted((center_a,center_b)))+(col,)
                    if key not in seen:
                        seen.add(key)
                        segment("Contact conductor" if wires else "Embedded grooved rail",
                                a,b,lateral,width,y0,y1,col)
    if wires:
        return
    # Neutral point blades at multi-arm crossing are purely physical guide
    # edges, posed along the original direction. Traffic routing is distinct.
    if mask.bit_count()>2:
        B("Trackwork contact box",(-.393,.340,.012),(.136,.064,.024),"weathered black",.005)
        B("Turnout mechanism bolts",(-.395,.340,.024),(.074,.025,.006),"rail head",.002)

def mast():
    # Base off paved shoulders: runtime x=.57 east of the tile center.
    # Arm crosses both live tracks and carries two short wire drop rods.
    x=-.572
    B("Mast footing and cover plate",(x,0,.032),(.166,.183,.060),"concrete",.010)
    C("Cast iron pole socket",(x,0,.059),(x,0,.161),.062,.041,"weathered black",12)
    C("Tapered catenary stanchion",(x,0,.140),(x,0,.632),.025,.016,"trolley dark",12)
    C("Sector mast collar",(x,0,.492),(x,0,.532),.036,.034,"weathered black",10)
    C("Machined mast cap",(x,0,.633),(x,0,.666),.038,.027,"steel",12)
    rod("Stiffened transverse span arm",(x,0,.597),(.326,0,.566),.013,"trolley dark")
    rod("Cross-arm tension diagonal",(x+.018,0,.515),(x+.281,0,.586),.009,"steel")
    rod("Arm suspension cable",(x+.028,0,.642),(.311,0,.574),.006,"weathered black",5)
    for drop in (-LANE,LANE):
        C("Cross-arm ceramic suspension nipple",(drop,0,.558),(drop,0,.589),
          .025,.027,"ceramic",12)
        for j in range(3):
            C("Ceramic isolator skirt",(drop,0,.550+j*.011),
              (drop,0,.557+j*.011),.033,.027,"enamel",12)
        rod("Wire drop",(drop,0,CONTACT+.008),(drop,0,.555),.0057,"wire copper",6)
        rod("Hot-wire attachment clip",(drop,-.03,CONTACT+.008),(drop,.03,CONTACT+.008),
            .0102,"brass",8)
    for i in (-1,1):
        C("Foundation anchor bolt",(x+i*.046,0,.061),(x+i*.046,0,.076),.012,.012,"steel",8)


def palette():
    names=(V.KEYS+["enamel"]*32)[:32]
    assert len(V.KEYS)<=32
    line=b"".join(bytes.fromhex(COLORS[key])*8 for key in names)
    def chunk(tag,data):
        return struct.pack(">I",len(data))+tag+data+struct.pack(">I",zlib.crc32(tag+data))
    img=b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",256,8,8,2,0,0,0))
    img+=chunk(b"IDAT",zlib.compress((b"\0"+line)*8))+chunk(b"IEND",b"")
    (ROOT/"mods/luanttd_core/textures/bl_tram_palette.png").write_bytes(img)

def merge(objects):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.object.join()
    ob=bpy.context.object
    mat=ob.matrix_world.copy()
    ob.matrix_world.identity()
    for v in ob.data.vertices:
        v.co=mat@v.co
    return ob

def export(stem, *, static=False, quarter=False, blend=None):
    if blend:
        bpy.context.scene.name="LuanTTD / "+blend.replace("_"," ")
        bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/f"art/{blend}.blend"),compress=True)
    ob=merge([o for o in bpy.context.scene.objects if o.type=="MESH"])
    if static:
        for v in ob.data.vertices:
            x,y,z=v.co
            v.co=Vector((-y-.5,x-.5,z-.5) if quarter else (x-.5,y-.5,z-.5))
    uv=ob.data.uv_layers.active or ob.data.uv_layers.new()
    for p in ob.data.polygons:
        k=V.KEYS.index(ob.data.materials[p.material_index].name)
        for li in p.loop_indices:
            uv.data[li].uv=((k+.5)/32,.5)
    ob.data.update()
    bpy.ops.wm.obj_export(filepath=str(ROOT/f"mods/luanttd_core/models/bl_{stem}.obj"),
        export_selected_objects=True,export_materials=False,export_uv=True,
        export_normals=True,export_triangulated_mesh=True,
        global_scale=1 if static else 10,forward_axis="NEGATIVE_Z",up_axis="Y")

def review(path, save=False):
    V.begin()
    for index,(label,mask) in enumerate((("straight",5),("quarter turn",6),("junction",15))):
        prior={o.name for o in bpy.context.scene.objects}
        tramway(mask)
        tramway(mask,True)
        if mask==5:
            mast()
        box=B("Street test inset",(0,0,-.064),(1.99,1.99,.128),"chassis",.024)
        for o in bpy.context.scene.objects:
            if o.name not in prior:
                o.location.y+=(1-index)*2.52
    for reverse in (0,1):
        prior={o.name for o in bpy.context.scene.objects}
        streetcar()
        ob=merge([o for o in bpy.context.scene.objects if o.name not in prior])
        for p in ob.data.vertices:
            x,y,z=p.co
            p.co=Vector(((x if not reverse else -x)+2.14,
                        (y if not reverse else -y)+(1.55 if not reverse else -.65),z))
    if save:
        bpy.context.scene.name="LuanTTD / tram track and wire construction"
        bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art/tramway_kit.blend"),compress=True)
    if not path:
        return
    bpy.ops.object.camera_add(location=(6.6,9.9,10.2))
    cam=bpy.context.object
    cam.rotation_euler=(Vector((.61,0,.25))-cam.location).to_track_quat("-Z","Y").to_euler()
    cam.data.type="ORTHO"
    cam.data.ortho_scale=9.26
    s=bpy.context.scene
    s.camera=cam
    s.render.engine="BLENDER_WORKBENCH"
    s.render.resolution_x,s.render.resolution_y=1440,1110
    s.render.resolution_percentage=100
    s.world=bpy.data.worlds.new("Tram studio matte")
    s.world.color=(.14,.168,.162)
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
    V.begin()
    streetcar()
    export("streetcar",blend="streetcar")
    for bits in range(1,16):
        V.begin()
        tramway(bits)
        export(f"tram_rails_{bits}",static=True)
        V.begin()
        tramway(bits,True)
        export(f"tram_wire_{bits}",static=True)
    for stem,quarter in (("ns",False),("ew",True)):
        V.begin()
        mast()
        export(f"tram_mast_{stem}",static=True,quarter=quarter)
    review(os.getenv("BAYLINE_TRAM_REVIEW"),save=True)

#!/usr/bin/env python3
"""Original Darwin 100 #226 tri-jet art for the OpenTTD 16.0-RC1 role.

blender -b -t 2 --python-exit-code 1 --python tools/build_stock_darwin_100_art.py
DARWIN_REVIEW=/absolute/directory adds original apron and ventral JPEG views.
Native: one direction-only exterior as stock, unit scale, nose −Z and Y=0 tires.
"""
from math import cos, pi, sin, sqrt, tau
from pathlib import Path
import os
import struct
import sys
import zlib

import bmesh
import bpy
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,os.getenv("LUANTTD_HELPERS",str(ROOT/"tools")))
import build_extra_road_vehicle_art as base
from build_coleman_count_art import merge
from build_bakewell_cotswald_art import compact_obj

STEM="bl_stock_darwin_100"
B,C,M=base.bevel_box,base.round_between,base.add_mesh
PAL={
 "Crown ivory":"eee6d3","Panel ivory":"e5deca","Silver pressure hull":"aebcc1",
 "Bellying brushed alloy":"82949e","Blue taper":"3b71a2","Lit blue":"457cab",
 "Dark coastal cobalt":"305577","Copper pinstripe":"d0a76e","Cab glass":"284553",
 "Glazing bezel":"52606a","Window glint":"75949a","Aluminium bezel":"b7c5c4",
 "Skinned wing alloy":"b5c1c4","Wing leading trim":"d1d7d2","Shadowed flap":"8c9fa8",
 "Rib inset":"5e7682","Pressure door seal":"74868e","Shadowed nacelle steel":"758b92",
 "Fan deep metal":"54636b","Dark intake":"26363d","Pale spinner alloy":"a0a9a3",
 "Exhaust patina bronze":"7b6b56","Warm burner rivets":"a38d70",
 "Landing gear chrome":"9aa7a9","Well shadow":"404a4e","Dull tire":"2b3031",
 "Road contact tread":"3c4445","Bright cap light":"e4d3a2","Port marker ruby":"b2474c",
 "Starboard marker mint":"518e74","Studio slab":"606a6c","Studio join":"738184",
}
assert len(PAL)==32
KEY=tuple(PAL)
# Blender +Y is the nose. This longer tri-jet has a duration/volume silhouette
# distinct from the compact two-engine LB-9, without airport-driven shrink.
F=(
 (-1.127,.008,.235,.019,.013),(-1.096,.030,.241,.039,.025),
 (-1.045,.056,.255,.060,.045),(-.983,.082,.271,.083,.069),
 (-.910,.108,.281,.109,.088),(-.820,.130,.284,.125,.109),
 (-.695,.151,.287,.142,.125),(-.530,.161,.290,.150,.138),
 (-.221,.164,.291,.152,.145),(.189,.164,.291,.152,.145),
 (.489,.162,.292,.151,.145),(.661,.157,.293,.149,.139),
 (.781,.143,.293,.142,.128),(.897,.114,.291,.124,.108),
 (.984,.076,.287,.096,.076),(1.043,.039,.281,.063,.042),
 (1.069,.013,.276,.031,.019),
)


def sections(name,kk,ink,tints=None):
    obj=base.profile_hull(name,kk,ink,tints)
    for p in obj.data.polygons:
        p.use_smooth=len(p.vertices)==4
    return obj


def close_mesh(name,vertices,faces,materials,smooth=False):
    obj=M(name,vertices,faces,materials)
    mesh=bmesh.new()
    mesh.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(mesh,faces=mesh.faces)
    mesh.to_mesh(obj.data)
    mesh.free()
    if smooth:
        for p in obj.data.polygons:
            p.use_smooth=True
    return obj


def interp(y):
    for a,b in zip(F,F[1:]):
        if a[0]<=y<=b[0]:
            t=(y-a[0])/(b[0]-a[0])
            return [x+t*(v-x) for x,v in zip(a[1:],b[1:])]
    raise ValueError(y)


def pressure():
    n=40
    angles=[tau*(i/n+.25) for i in range(n)]
    def ring(w,c,top,bottom):
        return [(w*cos(a),c+(top if sin(a)>=0 else bottom)*sin(a)) for a in angles]
    tones=[]
    for i,a in enumerate(angles):
        sn=sin(a+pi/n)
        tone=("Crown ivory" if sn>.66 else "Panel ivory" if sn>.23 else
              "Lit blue" if sn>.06 else "Dark coastal cobalt" if sn>-.16 else
              "Copper pinstripe" if sn>-.32 else "Silver pressure hull" if sn>-.77 else "Bellying brushed alloy")
        tones.append(tone)
    sections("Long rounded Darwin 100 integral pressure fuselage and cheatline",
        [(y,ring(w,c,a,b)) for y,w,c,a,b in F],"Silver pressure hull",tones)
    # Analytic side trim follows the pressure hull section/radius projection.
    def skin(side,y,h,lift):
        w,c,a,b=interp(y)
        rr=(h-c)/(a if h>=c else b)
        assert abs(rr)<1,(y,h,rr)
        return (side*(w*sqrt(1-rr*rr)+lift),y,h)
    def rect(side,key,tone,y,h,hl,wh,lift,cut=.004,outline=False):
        raw=[(y-hl+cut,h-wh),(y+hl-cut,h-wh),(y+hl,h-wh+cut),(y+hl,h+wh-cut),
             (y+hl-cut,h+wh),(y-hl+cut,h+wh),(y-hl,h+wh-cut),(y-hl,h-wh+cut)]
        # Three nested outlines follow the actual shell; a large planar
        # chord would otherwise disappear inside the rounded pressure hull.
        if outline:
            co=[skin(side,y+(a-y)*scale,h+(b-h)*scale,lift) for scale in (.94,1.) for a,b in raw]
            faces=[(i,(i+1)%8,8+(i+1)%8,8+i)[::side] for i in range(8)]
        else:
            co=[skin(side,y,h,lift)]
            for scale in (.34,.67,1.):
                co.extend(skin(side,y+(a-y)*scale,h+(b-h)*scale,lift) for a,b in raw)
            faces=[(0,i+1,1+(i+1)%8)[::side] for i in range(8)]
            for layer in (1,9):
                faces.extend((layer+i,layer+(i+1)%8,layer+8+(i+1)%8,layer+8+i)[::side] for i in range(8))
        return M(key,co,faces,tone)
    for s in (-1,1):
        for j in range(24):
            y=.766-j*.060-(.018 if j>8 else 0)-(.021 if j>16 else 0)
            h=.330 - max(0,j-21)*.002
            rect(s,"Stamped individual recessed cabin window frame","Aluminium bezel",y,h,.0158,.016,.0021)
            rect(s,"Dark rounded period window in cabin pressure shell","Cab glass",y,h,.0126,.0124,.0034)
            rect(s,"Thin reflected light along cabin glass","Window glint",y-.002,h+.006,.0082,.0021,.0043,.0016)
        for y,h,d in ((.846,.291,.036),(-.555,.291,.038),(.097,.283,.024)):
            rect(s,"Independent reamed passenger and emergency door perimeter","Pressure door seal",y,h,d,.060,.0035,.009,True)
            rect(s,"Separate bowed door quarter window","Cab glass",y+.002,h+.022,.012,.014,.0047)
            rect(s,"Thin painted grip and rear access latch","Rib inset",y-.012,h-.018,.010,.0024,.0055,.001)
        for y,h,d in ((.575,.221,.060),(-.390,.220,.065)):
            rect(s,"Separate postal and luggage hatch seal","Pressure door seal",y,h,d,.032,.0020,.006)
            rect(s,"Large flush silver luggage hatch","Silver pressure hull",y,h,d-.004,.027,.0032,.006)
            rect(s,"Short flush hold hinge lines","Rib inset",y+.020,h+.022,.015,.0016,.004,.0013)
        # A hand-authored three-stroke flash in original company tones.
        for i in range(3):
            y=.610+i*.065
            co=[skin(s,y+.075,h,.0045) for h in (.372+i*.006,.379+i*.006)]
            co.extend(skin(s,y,h,.0045) for h in (.374+i*.006,.369+i*.006))
            M("Original stepped Darwin period company flash",co,[(0,1,2,3)[::s]],"Dark coastal cobalt")
        # Cockpit glazing curves along the nose and occupies a distinctive
        # forward sweep rather than floating above or copying sprite pixels.
        def screen(name,tone,rows,lift):
            # x fraction of half-width in this bulbous nose and h near crest.
            dims=[]
            q=8
            for a,b in zip(rows,rows[1:]):
                for i in range(4):
                    t=i/4
                    y,g,k=(x+(z-x)*t for x,z in zip(a,b))
                    dims.append((y,g,k))
            dims.append(rows[-1])
            vertices=[]
            for y,g,k in dims:
                w,c,a,b=interp(y)
                for i in range(q+1):
                    x=g+(k-g)*i/q
                    vertices.append((s*w*x,y,c+a*sqrt(1-x*x)+lift))
            faces=[(i*(q+1)+j,i*(q+1)+j+1,(i+1)*(q+1)+j+1,(i+1)*(q+1)+j)[::s]
                for i in range(len(dims)-1) for j in range(q)]
            M(name,vertices,faces,tone)
        screen("Dark wraparound recessed angled cockpit gasket","Glazing bezel",
             ((.858,.085,.84),(.897,.065,.83),(.950,.081,.77),(.986,.109,.625)),.0031)
        screen("Actual raised curved six-light windscreen pane","Cab glass",
             ((.865,.13,.77),(.897,.12,.78),(.950,.14,.710),(.976,.15,.575)),.0059)
        screen("Small bright reflected strip on curved pilot glass","Window glint",
             ((.885,.19,.718),(.897,.19,.720)),.0081)
        for k in (.337,.548):
            def p(y):
                w,c,a,b=interp(y)
                return (s*w*k,y,c+a*sqrt(1-k*k)+.0082)
            C("Real lean cockpit glazing divisions",p(.870),p(.964),.0025,.0021,"Glazing bezel",8)
    B("Dull black shallow nose weather radar band",(0,1.059,.264),(.027,.011,.012),
      "Rib inset",.003)


def foil(name,rows,side,root=False):
    # x, leading y, trailing y, root height, thickness. Swept leading
    # edge, positively cambered upper wing and true planar lower foil.
    inks=("Wing leading trim","Skinned wing alloy","Skinned wing alloy","Skinned wing alloy","Shadowed flap",
          "Shadowed flap","Rib inset","Shadowed flap","Shadowed flap","Silver pressure hull","Wing leading trim")
    airfoil=((0.,0.),(.112,.40),(.269,.77),(.52,.66),(.77,.38),(.93,.14),
             (1.,0.),(.82,-.071),(.55,-.18),(.27,-.25),(.094,-.19))
    loops=[[(side*x,lead+(tail-lead)*a,h+th*b) for a,b in airfoil] for x,lead,tail,h,th in rows]
    n=len(airfoil)
    coords=sum(loops,[])
    faces=[tuple(range(n))]
    col=["Silver pressure hull"]
    for j in range(len(loops)-1):
        for i in range(n):
            k=(i+1)%n
            faces.append((j*n+i,j*n+k,(j+1)*n+k,(j+1)*n+i))
            col.append(inks[i])
    faces.append(tuple(range((len(loops)-1)*n,len(loops)*n))[::-1])
    col.append("Silver pressure hull")
    return close_mesh(name,coords,faces,col)


def wings():
    main=((.093,.260,-.475,.207,.101),(.196,.233,-.467,.207,.092),
          (.373,.124,-.452,.218,.077),(.556,.001,-.453,.236,.056),
          (.719,-.115,-.467,.252,.039),(.863,-.215,-.474,.268,.024),
          (.916,-.258,-.466,.273,.015),(.947,-.293,-.449,.279,.006))
    stabilizer=((.012,-.702,-1.052,.618,.041),(.108,-.741,-1.056,.621,.035),
                (.220,-.807,-1.054,.633,.026),(.312,-.872,-1.052,.643,.014),
                (.345,-.899,-1.039,.647,.008))
    for s in (-1,1):
        foil("Swept press-rolled aluminum main wing with dihedral",main,s)
        foil("At-top true high tailplane stabilizer and elevator foils",stabilizer,s)
        tip=(s*.951,-.303,.279)
        C("Bright visible wing navigation lights",tip,(s*.954,-.328,.281),.008,.006,
          "Port marker ruby" if s<0 else "Starboard marker mint",9)
        # Three real flap-track fairing lobes run behind the main wing.
        for x,y,h,l in ((.290,-.339,.177,.164),(.475,-.359,.198,.159),(.660,-.370,.230,.139)):
            C("Underside separate swept flap track hinge fairings",(s*x,y+.065,h),(s*(x+.048),y-l,h+.008),
              .018,.008,"Shadowed flap",10)
        for x,y,h,n in ((.28,-.338,.254,.176),(.527,-.371,.267,.181),(.751,-.409,.273,.135)):
            C("Separate flap panel hinge seam recessed in wing skin",(s*x,y,h),(s*(x+n),y-.027,h+.012),
              .0023,.0019,"Rib inset",6)
        B("Country-of-origin neutral segmented flap strips",(s*.253,-.408,.214),
          (.111,.067,.012),"Shadowed flap",.004,(0,s*.034,s*.08))
    # Fin thickest low, swept toward aft as it reaches the tailplane.
    rows=((.008,.269,-.585,-1.087),(.041,.347,-.641,-1.074),(.049,.428,-.706,-1.069),
          (.033,.527,-.757,-1.057),(.025,.607,-.824,-1.051),(.018,.660,-.891,-1.037),
          (.010,.681,-.919,-1.014))
    contour=((0,0),(.12,-.48),(.38,-1),(.69,-.68),(.88,-.34),(1,0),(.88,.34),(.69,.68),(.38,1),(.12,.48))
    vn=[];faces=[];col=[]
    for w,h,a,b in rows:
        vn.extend((w*k,a+(b-a)*t,h) for t,k in contour)
    n=len(contour)
    faces.append(tuple(range(n))[::-1]);col.append("Dark coastal cobalt")
    for i in range(len(rows)-1):
        for j in range(n):
            k=(j+1)%n
            faces.append((i*n+j,i*n+k,(i+1)*n+k,(i+1)*n+j))
            c=("Copper pinstripe" if i==4 and j in (1,2,3,6,7,8) else "Dark coastal cobalt" if i>2
               else "Lit blue" if j not in (0,5) else "Blue taper")
            col.append(c)
    faces.append(tuple(range((len(rows)-1)*n,len(rows)*n)));col.append("Dark coastal cobalt")
    close_mesh("Darwin tall swept two-plane tail with colored fin panels",vn,faces,col)
    C("Small tail anticollision light",(0,-1.040,.646),(0,-1.055,.647),.007,.004,"Bright cap light",8)


def turbojet(name,x,sections,hue):
    """Closed annular nacelle with open nose and tail bores, not painted disks."""
    ring_n=26
    verts=[(x+rr*cos(tau*i/ring_n),y,c+rr*sin(tau*i/ring_n))
           for y,rr,c,tone in sections for i in range(ring_n)]
    faces=[]
    colors=[]
    for k,(*_,tone) in enumerate(sections):
        j=(k+1)%len(sections)
        for a in range(ring_n):
            b=(a+1)%ring_n
            faces.append((k*ring_n+a,k*ring_n+b,j*ring_n+b,j*ring_n+a))
            colors.append(tone)
    close_mesh(name,verts,faces,colors,True)
    front=sections[0][0]
    a=-.003 if x else -.010
    fan_y=front-.052
    rr=sections[0][1]*.65
    fy=sections[0][2]+a
    for i in range(12):
        theta=tau*i/12
        def p(r,b,dy):
            return (x+r*cos(theta+b),fan_y+dy,fy+r*sin(theta+b))
        faces=(p(.011,-.42,.001),p(rr,.12,-.009),p(rr,.281,-.009),p(.011,.27,.002))
        M("Individually pitched compressor fan vanes in open bore",faces,[(3,2,1,0)],"Fan deep metal")
    C("Whole exposed central turbine compressor spinner",(x,fan_y-.016,fy),(x,fan_y+.018,fy),rr*.34,rr*.10,
       "Pale spinner alloy",14)
    ey=sections[len(sections)//2][0]
    eh=sections[len(sections)//2][2]
    for i in range(9):
        theta=tau*i/9
        def rp(r,b,d):
            return (x+rr*r*cos(theta+b),ey+d,eh+rr*r*sin(theta+b))
        M("Actual recessed exhaust swirl vanes",[rp(.35,0,.018),rp(.57,.43,.033),rp(.56,.69,.031),rp(.34,.28,.018)],
          [(0,1,2,3)],"Warm burner rivets")
    C("Brushed heat-stained conical exhaust plug",(x,ey+.067,eh),(x,ey-.022,eh),rr*.36,rr*.11,
      hue,14)


def jets():
    for s in (-1,1):
        tube=(
          (-.497,.066,.329,"Wing leading trim"),(-.514,.080,.327,"Skinned wing alloy"),
          (-.562,.084,.322,"Silver pressure hull"),(-.648,.084,.318,"Silver pressure hull"),
          (-.762,.080,.314,"Shadowed nacelle steel"),(-.870,.064,.309,"Exhaust patina bronze"),
          (-.930,.054,.304,"Dark intake"),(-.939,.043,.304,"Exhaust patina bronze"),
          (-.911,.038,.304,"Warm burner rivets"),(-.825,.035,.308,"Dark intake"),
          (-.572,.059,.324,"Dark intake"),(-.514,.060,.329,"Shadowed nacelle steel"),
        )
        turbojet("Hollow full-length skirted outer rear turbine nacelle",s*.229,tube,"Exhaust patina bronze")
        B("Thick rooted rear nacelle pylon sweeps into fuselage",(s*.158,-.670,.311),
          (.118,.240,.068),"Shadowed nacelle steel",.015,(0,0,-s*.219))
    tube=(
      (-.647,.057,.449,"Wing leading trim"),(-.662,.068,.445,"Silver pressure hull"),
      (-.705,.071,.431,"Lit blue"),(-.772,.066,.412,"Blue taper"),
      (-.864,.060,.377,"Dark coastal cobalt"),(-.959,.054,.346,"Blue taper"),
      (-1.054,.046,.308,"Shadowed nacelle steel"),(-1.117,.039,.283,"Exhaust patina bronze"),
      (-1.141,.033,.278,"Dark intake"),(-1.139,.024,.279,"Warm burner rivets"),
      (-1.072,.022,.303,"Dark intake"),(-.949,.025,.338,"Dark intake"),
      (-.851,.039,.378,"Dark intake"),(-.740,.047,.417,"Dark intake"),
      (-.666,.051,.443,"Shadowed nacelle steel"),
    )
    turbojet("True open dorsal S-duct with a third turbine and bent metallic exhaust",0,tube,"Exhaust patina bronze")


def gear():
    # Six physical tires. Contacts all end exactly at Blender Z=0.
    for x,y,tire_r,wheel_w,mount,boxw,boxl in (
        (-.243,-.148,.068,.028,.162,.138,.167),(.243,-.148,.068,.028,.162,.138,.167),
        (0,.717,.048,.022,.151,.091,.126),
    ):
        B("Dark extended landing gear wheel-well face",(x,y,mount+.001),
          (boxw,boxl,.007),"Well shadow",.003)
        for s in (-1,1):
            B("Opened separate undercarriage bay doors",(x+s*boxw*.466,y,mount-.023),
              (.008,boxl*.89,.053),"Shadowed flap" if x else "Silver pressure hull",
              .003,(0,-s*.24,0))
        C("Real raised hydraulic tricycle landing shock strut",(x,y,tire_r),(x,y-.014,mount+.026),
          .013 if x else .009,.020 if x else .012,"Landing gear chrome",13)
        C("Connected oleo scissor drag brace linkage",(x,y+.007,tire_r+.009),(x,y+.073,mount+.010),
          .008 if x else .005,.010 if x else .006,"Fan deep metal",10)
        C("Two tires share an actual transverse metal axle",(x-wheel_w*1.58,y,tire_r),(x+wheel_w*1.58,y,tire_r),
          .007,.007,"Landing gear chrome",9)
        for s in (-1,1):
            xx=x+s*wheel_w*.774
            n=20
            vertices=[(u,y+tire_r*cos(-pi/2+a*tau/n),tire_r+tire_r*sin(-pi/2+a*tau/n))
              for u in (xx-wheel_w*.5,xx+wheel_w*.5) for a in range(n)]
            faces=[tuple(range(n))[::-1],tuple(range(n,n*2))]
            faces.extend((i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n))
            close_mesh("True runway contact tire, no mesh left below datum",vertices,faces,
              ["Dull tire"]*2+["Road contact tread"]*n)
            C("Separate spun concave wheel hub",(xx+s*wheel_w*.495,y,tire_r),
              (xx+s*wheel_w*.53,y,tire_r),tire_r*.49,tire_r*.421,"Landing gear chrome",14)
            C("Small hub center dust seal",(xx+s*wheel_w*.535,y,tire_r),
              (xx+s*wheel_w*.56,y,tire_r),tire_r*.21,tire_r*.18,"Fan deep metal",10)


def atlas():
    def chunk(k,d):return struct.pack(">I",len(d))+k+d+struct.pack(">I",zlib.crc32(k+d))
    row=b"".join(bytes.fromhex(v)*8 for v in PAL.values())
    target=ROOT/"mods/luanttd_core/textures"/f"{STEM}_atlas.png"
    target.write_bytes(b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",256,8,8,2,0,0,0))
                       +chunk(b"IDAT",zlib.compress((b"\0"+row)*8,9))+chunk(b"IEND",b""))


def new_collection(scene,name,objects):
    c=bpy.data.collections.new(name)
    scene.collection.children.link(c)
    for obj in objects:
        for prev in list(obj.users_collection):prev.objects.unlink(obj)
        c.objects.link(obj)
    return c


def make():
    atlas()
    base.PALETTE=PAL
    base.KEYS=list(KEY)
    base.begin()
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene
    scene.name="LuanTTD | Darwin 100 #226"
    scene["source"]="OpenTTD 16.0-RC1, Darwin 100, engine 226, AVI row 11, stock shape 3781"
    scene["proportions"]="Rounded 1960s rear tri-jet original interpretation, not a licensed aircraft or stock sprite"
    scene["native"]="scale 1; actual ground datum Y=0, nose −Z; stock visual invariant by ground and altitude"
    for i,(stage,builder) in enumerate((("Pressure fuselage and glass",pressure),("Main wings and high-mounted tail",wings),
                                       ("Three genuine jet bores",jets),("Extended tricycle gear",gear)),1):
        start=set(scene.objects)
        builder()
        new_collection(scene,f"{i:02} • {stage}",[o for o in scene.objects if o not in start])
    sources=list(scene.objects)
    start=set(scene.objects)
    B("Studio pavement at real tire datum",(0,0,-.041),(11,11,.081),"Studio slab",.009)
    for p in (-2,-1,0,1,2):
        B("Subtle original apron expansion seam",(p,0,-.00039),(.007,8,.0005),"Studio join")
        B("Subtle original apron expansion seam",(0,p,-.00039),(8,.007,.0005),"Studio join")
    named=[]
    for name,where in (("front",(2.91,3.62,1.95)),("rear",(-3.21,-3.41,1.69)),
                       ("ventral",(2.98,-3.32,-1.21))):
        bpy.ops.object.camera_add(location=where)
        camera=bpy.context.object
        camera.name=f"{name.title()} inspection camera"
        camera.rotation_euler=(Vector((0,0,.282))-camera.location).to_track_quat("-Z","Y").to_euler()
        camera.data.type="ORTHO"
        camera.data.ortho_scale=2.56 if name!="ventral" else 2.75
        named.append((name,camera))
    studio=new_collection(scene,"90 • Inspection cameras and apron only",[o for o in scene.objects if o not in start])
    scene.camera=named[0][1]
    scene.render.engine="BLENDER_WORKBENCH"
    scene.render.resolution_x,scene.render.resolution_y=1160,820
    scene.render.resolution_percentage=100
    scene.display.shading.light="STUDIO"
    scene.display.shading.studiolight_rotate_z=.57
    scene.display.shading.color_type="MATERIAL"
    scene.display.shading.show_shadows=True
    scene.display.shading.show_cavity=True
    scene.display.shading.cavity_type="BOTH"
    scene.world=bpy.data.worlds.new("Blue-grey apron environment")
    scene.world.color=(.137,.159,.183)
    scene.display.shading.background_type="WORLD"
    scene.view_settings.view_transform="Standard"
    scene.view_settings.exposure=.33
    for area in (a for screen in bpy.data.screens for a in screen.areas if a.type=="VIEW_3D"):
        v=area.spaces.active
        v.shading.color_type="MATERIAL"
        v.region_3d.view_location=Vector((0,0,.28))
        v.region_3d.view_distance=2.95
        v.region_3d.view_rotation=Vector((.8,.84,.52)).to_track_quat("Z","Y")
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art/stock_darwin_100.blend"),compress=True)
    copies=[]
    for ob in sources:
        shell=ob.copy()
        shell.data=ob.data.copy()
        scene.collection.objects.link(shell)
        copies.append(shell)
    bpy.context.view_layer.update()
    ob=merge(copies)
    ob.name="Stock_Darwin_100_226"
    uv=ob.data.uv_layers.active or ob.data.uv_layers.new()
    uv.active_render=True
    for p in ob.data.polygons:
        idx=KEY.index(ob.data.materials[p.material_index].name)
        for i in p.loop_indices:uv.data[i].uv=((idx+.5)/len(KEY),.5)
    p=ROOT/"mods/luanttd_core/models"/f"{STEM}.obj"
    bpy.ops.wm.obj_export(filepath=str(p),export_selected_objects=True,export_materials=False,
      export_uv=True,export_normals=True,export_triangulated_mesh=False,global_scale=10,
      forward_axis="NEGATIVE_Z",up_axis="Y")
    compact_obj(p)
    bpy.data.objects.remove(ob,do_unlink=True)
    if q:=os.getenv("DARWIN_REVIEW"):
        scene.render.image_settings.file_format="JPEG"
        scene.render.image_settings.quality=91
        apron=[o for o in studio.objects if o.type=="MESH"]
        for name,cam in named:
            scene.camera=cam
            for o in apron:o.hide_render=name=="ventral"
            scene.render.filepath=str(Path(q)/f"darwin100-{name}.jpg")
            bpy.ops.render.render(write_still=True)


if __name__=="__main__":
    make()

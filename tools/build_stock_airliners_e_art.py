#!/usr/bin/env python3
"""Editable original FFP Dart and YAC 1-11. Nose +Y/+Z up in Blender, −Z/Y up in Luanti."""
from dataclasses import dataclass
from math import sin, cos, pi, tau, sqrt
from pathlib import Path
import os,sys,zlib,struct
import bpy
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,os.getenv("LUANTTD_HELPERS",str(ROOT/"tools")))
import build_stock_darwin_100_art as art
base=art.base
C,M=art.C,art.M
def B(name,p,dims,ink,bevel=0,rot=None):
    return art.B(name,p,dims,ink,min(bevel,min(dims)*.38),rot)

@dataclass(frozen=True)
class Shape:
    stem:str; title:str; engine:int; tag:str
    palette:dict; fuselage:tuple; wing:tuple; tail:tuple; fin:tuple
    nacelle:tuple; engine_x:float; gear:tuple; window:tuple; doors:tuple

dart=Shape(
 'ffp_dart','FFP Dart',217,'Rounded 1950s first-generation twinjet, low horizontal stabilizer and tapered ogive.',
 {'Crown ivory':'f4efde','Panel ivory':'ebe4d6','Lit blue':'a33e32','Dark coastal cobalt':'792e29',
  'Blue taper':'943b34','Copper pinstripe':'c8954e','Bellying brushed alloy':'94a2a5','Rib inset':'63747c',
  'Silver pressure hull':'c3ccd0','Port marker ruby':'ba3939'},
 # longitudinal station, half width, belt height, crown radius, belly radius
 ((-.884,.010,.194,.013,.010),(-.842,.027,.186,.034,.026),(-.755,.066,.191,.075,.052),
  (-.671,.100,.191,.094,.074),(-.545,.116,.193,.106,.090),(-.411,.125,.194,.109,.094),
  (-.241,.129,.196,.109,.096),(.271,.128,.196,.108,.095),(.489,.124,.197,.103,.091),
  (.589,.115,.196,.100,.086),(.666,.096,.195,.091,.072),(.724,.071,.192,.075,.053),
  (.772,.045,.189,.054,.035),(.803,.021,.185,.028,.018),(.818,.005,.184,.008,.005)),
 ((.083,.183,-.356,.149,.074),(.193,.151,-.354,.157,.068),(.342,.083,-.342,.172,.052),
  (.499,.003,-.332,.192,.038),(.637,-.065,-.331,.214,.025),(.747,-.113,-.315,.229,.013),
  (.777,-.139,-.297,.234,.007)),
 ((.026,-.566,-.861,.293,.038),(.115,-.600,-.865,.298,.033),
  (.227,-.661,-.864,.314,.026),(.302,-.720,-.849,.328,.016),(.333,-.750,-.828,.334,.009)),
 # (fin width, height, leading, trailing)
 ((.020,.199,-.447,-.865),(.038,.267,-.515,-.863),(.040,.350,-.562,-.862),
  (.028,.422,-.621,-.852),(.020,.494,-.689,-.838),(.010,.529,-.733,-.814)),
 (-.438,-.787,.237,.063,.061),.172,
 ((-.182,-.130,.053,.022,.130),(.182,-.130,.053,.022,.130),(0,.554,.037,.016,.121)),
 (18,.554,.055,.231,'triangle'),((.617,.212,.029),(-.453,.215,.034),(-.006,.229,.017)))
yate=Shape(
 'yate_yac_1_11','Yate Aerospace YAC 1-11',225,'Compact 1960s British short-haul rear twinjet with cruciform-free full T-tail.',
 {'Crown ivory':'eeeada','Panel ivory':'e7e9d9','Lit blue':'388681','Dark coastal cobalt':'205951',
  'Blue taper':'26716b','Copper pinstripe':'c7a64d','Silver pressure hull':'aebbc1',
  'Bellying brushed alloy':'839aa3','Wing leading trim':'ccd0c4','Exhaust patina bronze':'7f6e5d'},
 ((-.930,.008,.215,.012,.010),(-.886,.035,.215,.037,.033),(-.813,.067,.213,.062,.055),
  (-.713,.095,.209,.088,.076),(-.596,.116,.207,.104,.090),(-.462,.129,.205,.115,.101),
  (-.280,.134,.204,.117,.103),(.226,.135,.204,.118,.104),(.494,.133,.203,.117,.101),
  (.581,.129,.201,.110,.095),(.659,.111,.197,.100,.084),(.731,.083,.191,.082,.061),
  (.777,.052,.183,.061,.039),(.802,.021,.177,.031,.015),(.810,.005,.177,.010,.006)),
 ((.086,.130,-.409,.155,.079),(.207,.094,-.395,.158,.070),(.358,-.004,-.387,.171,.052),
  (.505,-.087,-.369,.186,.039),(.629,-.155,-.358,.202,.024),(.728,-.205,-.346,.213,.013),
  (.760,-.229,-.324,.216,.007)),
 ((.021,-.669,-.912,.555,.034),(.120,-.693,-.918,.563,.028),(.222,-.744,-.920,.572,.018),
  (.290,-.779,-.911,.580,.012),(.316,-.804,-.895,.582,.006)),
 ((.014,.211,-.435,-.918),(.041,.279,-.491,-.917),(.041,.362,-.560,-.920),
  (.031,.440,-.625,-.917),(.025,.506,-.674,-.913),(.017,.554,-.723,-.905),
  (.011,.589,-.766,-.892)),
 (-.475,-.833,.259,.067,.071),.184,
 ((-.202,-.162,.052,.020,.134),(.202,-.162,.052,.020,.134),(0,.543,.039,.016,.120)),
 (20,.547,.049,.242,'square'),((.618,.224,.031),(-.465,.223,.037),(-.084,.239,.019)))

def interp(rs,y):
    for a,b in zip(rs,rs[1:]):
        if a[0]<=y<=b[0]:
            u=(y-a[0])/(b[0]-a[0]); return tuple(x+(z-x)*u for x,z in zip(a[1:],b[1:]))
    raise ValueError(y)

def pressure(q):
    n=44
    angles=[tau*(j/n+.25) for j in range(n)]
    ink=[]
    for a in angles:
        h=sin(a+pi/n)
        ink.append("Crown ivory" if h>.69 else "Panel ivory" if h>.47 else "Lit blue" if h>.22 else
                   "Dark coastal cobalt" if h>.02 else "Copper pinstripe" if h>-.14 else
                   "Silver pressure hull" if h>-.69 else "Bellying brushed alloy")
    art.sections("Independent lofted pressure hull and painted period stripe",
        [(y,[(w*cos(a),b+(t if sin(a)>=0 else l)*sin(a)) for a in angles])
         for y,w,b,t,l in q.fuselage],"Silver pressure hull",ink)
    def xy(s,y,h,lift):
        w,b,t,l=interp(q.fuselage,y)
        f=(h-b)/(t if h>=b else l)
        assert abs(f)<1,(q.stem,y,h,f)
        return (s*(w*sqrt(1-f*f)+lift),y,h)
    def badge(s,key,tone,y,h,ry,rh,lift,style="square",rim=False):
        ring=(0.,1.) if rim else (.34,.68,1.)
        corners=6 if style=="triangle" else 8
        raw=((-.99,.69),(-.49,-.99),(.44,-.99),(.99,.69),(.32,1.),(-.29,1.)) if corners==6 else (
                     (-1,-.57),(-.59,-1),(.59,-1),(1,-.56),(1,.56),(.59,1),(-.59,1),(-1,.56))
        if rim: ring=(.88,1.)
        vs=[xy(s,y+a*ry*g,h+b*rh*g,lift) for g in ring for a,b in raw]
        fs=[(j*corners+i,j*corners+(i+1)%corners,(j+1)*corners+(i+1)%corners,(j+1)*corners+i)[::s]
            for j in range(len(ring)-1) for i in range(corners)]
        if not rim: fs.append(tuple(range(corners))[::s])
        return M(key,vs,fs,tone)
    n,first,spacing,height,style=q.window
    for s in (-1,1):
        for j in range(n):
            p=first-j*spacing-((.013 if q.engine==217 else .007) if j>=8 else 0)
            badge(s,"Independent recessed window surround","Aluminium bezel",p,height,.0135,.015,.0024,style)
            badge(s,"Cabin glazing shaped to the actual hull","Cab glass",p,height,.0106,.012,.0037,style)
            badge(s,"Tiny pane glint","Window glint",p-.0028,height+.005,.0057,.0017,.0046,style)
        for y,h,w in q.doors:
            hh=.052 if w>.023 else .031
            badge(s,"Inset passenger door and emergency perimeter","Pressure door seal",y,h,w,hh,.0041,rim=True)
            badge(s,"Glazed door quarter light","Cab glass",y+.002,h+.015,.010,.012,.0049)
            badge(s,"Closed door flush grip","Rib inset",y-.008,h-.008,.011,.002,.0052)
        for y in (-.277,.403):
            badge(s,"Sealed lower luggage hatch perimeter","Pressure door seal",y,.149,.054,.026,.0024,rim=True)
            badge(s,"Short lower hold access handle","Rib inset",y,.154,.017,.0026,.0047)
        # Own livery mark, conformal separate geometry rather than external sprite/decals.
        for i in range(3):
            yy=.439-i*.037
            vs=[xy(s,yy+d,h+i*.002,.0049) for d,h in ((-.008,.263),(.013,.282),(.026,.282),(.003,.263))]
            M("Original flying chevron emblem",vs,[(0,1,2,3)[::s]],"Dark coastal cobalt")
        def screen(key,tone,y0,y1,f0,f1,lift):
            vs=[]
            for j in range(8):
                k=j/7;y=y0+(y1-y0)*k
                w,b,t,_=interp(q.fuselage,y)
                for l in range(6):
                    g=l/5; u=f0+(f1-f0)*g+(g-.77)*k*.19
                    vs.append((s*w*u,y,b+t*sqrt(1-u*u)+lift))
            fs=[(j*6+i,j*6+i+1,(j+1)*6+i+1,(j+1)*6+i)[::s] for j in range(7) for i in range(5)]
            return M(key,vs,fs,tone)
        y= .616 if q.engine==217 else .631
        screen("Seated tapered pilot screen gasket","Glazing bezel",y,y+.127,.155,.920,.0034)
        screen("Curved glazed pilot eye-line","Cab glass",y+.010,y+.116,.211,.861,.0052)
        screen("Short reflection over actual central glass","Window glint",y+.039,y+.055,.235,.501,.0069)
        for u in (.39,.64):
            def p(v):
                w,b,t,_=interp(q.fuselage,v)
                return (s*w*u,v,b+t*sqrt(1-u*u)+.0072)
            C("Real windscreen intermediate mullion",p(y+.009),p(y+.122),.0025,.0017,"Glazing bezel",8)

def wings(q):
    for s in (-1,1):
        art.foil("Rooted swept aluminium wing, true camber and retreating tip",q.wing,s)
        art.foil("Cambered horizontal stabilizer at stock-model period location",q.tail,s)
        x,a,b,h,t=q.wing[-1]
        C("Fixed colored wing end navigation lights",(s*x,a+.009,h),(s*x,a-.018,h),.007,.006,
            "Port marker ruby" if s<0 else "Starboard marker mint",10)
        for x,y,h in ((.244,-.287,.119),(.420,-.307,.147),(.545,-.317,.164)):
            if q.engine==225:y-=.025
            C("Small separate underside flap-track fairing",(s*x,y+.042,h),
              (s*(x+.034),y-.066,h+.011),.014,.006,"Shadowed flap",12)
    contour=((0,0),(.12,-.54),(.35,-1),(.65,-.77),(.86,-.35),(1,0),(.86,.35),(.65,.77),(.35,1),(.12,.54))
    n=len(contour)
    vs=[(x*p,a+(b-a)*z,y) for x,y,a,b in q.fin for z,p in contour]
    fs=[tuple(range(n))]
    tones=["Blue taper"]
    for z in range(len(q.fin)-1):
        for k in range(n):
            a,b=z*n+k,z*n+(k+1)%n
            fs.append((a,b,b+n,a+n))
            shades=("Panel ivory","Lit blue","Dark coastal cobalt","Copper pinstripe","Blade white","Dark coastal cobalt")
            tones.append(shades[z] if shades[z]!="Blade white" else "Crown ivory")
    fs.append(tuple(range(len(vs)-n,len(vs))))
    tones.append("Aluminium bezel")
    art.close_mesh("Footed main fin with applied stripe panels and early swept shape",vs,fs,tones)
    _,h,a,b=q.fin[-1]
    C("Tail anticollision lamp",(0,b+.026,h),(0,b+.013,h+.006),.008,.005,"Bright cap light",8)

def jet(q):
    a,b,h,r,t=q.nacelle
    def station(f,r,h,tone):
        return (a+(b-a)*f,r,h,tone)
    tube=(station(0,r*.88,h,"Wing leading trim"),station(.052,r,h,"Skinned wing alloy"),
          station(.205,t,h-.003,"Silver pressure hull"),station(.44,t*.99,h-.005,"Silver pressure hull"),
          station(.66,t*.91,h-.008,"Shadowed nacelle steel"),station(.83,t*.78,h-.010,"Exhaust patina bronze"),
          station(1,t*.64,h-.011,"Dark intake"),station(.994,t*.54,h-.011,"Warm burner rivets"),
          station(.855,t*.46,h-.011,"Dark intake"),station(.153,r*.80,h-.001,"Dark intake"),
          station(.024,r*.71,h,"Shadowed nacelle steel"))
    for s in (-1,1):
        art.turbojet("Opened annular twinjet shrouds and spinners",s*q.engine_x,tube,"Exhaust patina bronze")
        B("Engine root pylon fillet into pressure shell", (s*(q.engine_x-.058),(a+b)/2+.011,h-.018),
          (.096,.159,.041),"Shadowed nacelle steel",.014,(0,0,-s*.128))
        if q.engine==225:
            B("Under-pod separate tapered reverser shroud hinge",(s*q.engine_x,b+.059,h-.057),
              (.061,.078,.018),"Warm burner rivets",.008,(0,0,s*.042))
    if q.engine==217:
        B("Forward ventral antenna blade",(0,.385,.099),(.013,.068,.042),"Rib inset",.004)
    else:
        # Folded airstair panels model geometry, not a texture painted on a flat tail.
        B("Ventral closed rear airstair fairing",(0,-.443,.099),(.089,.165,.026),"Shadowed flap",.011)
        B("Ventral rear stair seam inset at each edge",(0,-.461,.084),(.084,.008,.004),"Rib inset",.004)
        B("Communication fairing on flight deck crown",(0,.432,.323),(.017,.079,.023),"Aluminium bezel",.006)

def gear(q):
    for x,y,r,w,mount in q.gear:
        B("Formed root landing gear well into airframe",(x,y,mount+.018),(w*3.6,r*1.87,.041),"Silver pressure hull",.011)
        B("Gear well shadow face",(x,y,mount+.005),(w*4.5,r*2.4,.015),"Well shadow",.007)
        for s in (-1,1):
            B("Open bay door on realistic hinge",(x+s*w*2.10,y,mount-.010),(.006,r*2.38,.044),
              "Shadowed flap",.005,(0,-s*.26,0))
        C("Extended polished oleo and suspension",(x,y,r),(x,y-.012,mount+.023),.009,.014,"Landing gear chrome",12)
        C("Oleo scissor linkage to well",(x,y+.010,r+.004),(x,y+.048,mount+.006),.005,.007,"Fan deep metal",10)
        C("Solid axle passes both tire hubs",(x-w*1.52,y,r),(x+w*1.52,y,r),.007,.007,"Landing gear chrome",12)
        for s in (-1,1):
            xx=x+s*w*.790;n=24
            vs=[(u,y+r*cos(-pi/2+j*tau/n),r+r*sin(-pi/2+j*tau/n))
                for u in (xx-w*.5,xx+w*.5) for j in range(n)]
            faces=[tuple(range(n))[::-1],tuple(range(n,n*2))]
            faces.extend((i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n))
            art.close_mesh("Runway contact tire at exact datum",vs,faces,["Dull tire"]*2+["Road contact tread"]*n)
            C("Independently machined wheel hub",(xx+s*w*.49,y,r),(xx+s*w*.55,y,r),r*.49,r*.41,"Landing gear chrome",14)
            C("Hub center cap",(xx+s*w*.55,y,r),(xx+s*w*.58,y,r),r*.21,r*.17,"Fan deep metal",10)

def export_atlas(stem,pal):
    def chunk(s,b): return struct.pack(">I",len(b))+s+b+struct.pack(">I",zlib.crc32(s+b))
    row=b"".join(bytes.fromhex(v)*8 for v in pal.values())
    (ROOT/"mods/luanttd_core/textures"/f"bl_stock_{stem}_atlas.png").write_bytes(
      b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",256,8,8,2,0,0,0))
      +chunk(b"IDAT",zlib.compress((b"\0"+row)*8,9))+chunk(b"IEND",b""))

def make(q):
    pal=art.PAL | q.palette
    base.PALETTE=pal; keys=base.KEYS=list(pal)
    assert len(pal)==32
    export_atlas(q.stem,pal)
    base.begin()
    scene=bpy.context.scene
    scene.name=f"LuanTTD | {q.title} #{q.engine}"
    scene["source"]=f"OpenTTD 16.0-RC1 #{q.engine}; J=fast CTOL; stock direction-only sprite base 3781"
    scene["art"]=q.tag
    scene["datum"]="Native Y=0 and nose −Z; unit scale; one stock exterior by altitude"
    for i,(n,fn) in enumerate((("Pressure shell · glazing · door skins",pressure),("Swept wings and empennage",wings),
                                ("Open turbine nacelles and authentic ancillaries",jet),("Grounded tricycle gear",gear)),1):
        before=set(scene.objects)
        fn(q)
        art.new_collection(scene,f"{i:02} | {n}",[o for o in scene.objects if o not in before])
    sources=list(scene.objects)
    before=set(sources)
    B("Neutral airport review apron",(0,0,-.0405),(8,8,.080),"Studio slab",.009)
    for i in (-2,-1,0,1,2):
        B("Faint original airport apron seam",(i,0,-.00030),(.006,7,.00035),"Studio join")
        B("Faint original airport apron seam",(0,i,-.00030),(7,.006,.00035),"Studio join")
    cameras=[]
    for n,p in (("front",(2.9,3.55,1.95)),("rear",(-3.2,-3.42,1.59)),("ventral",(2.98,-3.30,-1.41))):
        bpy.ops.object.camera_add(location=p)
        cam=bpy.context.object
        cam.name=f"{n.title()} inspection"
        cam.rotation_euler=(Vector((0,0,.218))-cam.location).to_track_quat("-Z","Y").to_euler()
        cam.data.type="ORTHO";cam.data.ortho_scale=2.18
        cameras.append((n,cam))
    studio=art.new_collection(scene,"90 | Review apron and cameras (not included in OBJ)",[o for o in scene.objects if o not in before])
    scene.camera=cameras[0][1]
    scene.render.engine="BLENDER_WORKBENCH"
    scene.render.resolution_x,scene.render.resolution_y=1060,760
    scene.render.resolution_percentage=100
    scene.display.shading.light="STUDIO"
    scene.display.shading.studiolight_rotate_z=.57
    scene.display.shading.color_type="MATERIAL"
    scene.display.shading.show_shadows=True
    scene.display.shading.show_cavity=True
    scene.display.shading.cavity_type="BOTH"
    scene.world=bpy.data.worlds.new("Original blue shadow environment")
    scene.world.color=(.137,.159,.183)
    scene.display.shading.background_type="WORLD"
    scene.view_settings.view_transform="Standard"
    scene.view_settings.exposure=.28
    for a in (a for screen in bpy.data.screens for a in screen.areas if a.type=="VIEW_3D"):
        v=a.spaces.active
        v.shading.color_type="MATERIAL"
        v.region_3d.view_location=Vector((0,0,.22))
        v.region_3d.view_distance=2.56
        v.region_3d.view_rotation=Vector((.86,1,.52)).to_track_quat("Z","Y")
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/f"art/stock_{q.stem}.blend"),compress=True)
    copies=[]
    for o in sources:
        x=o.copy();x.data=o.data.copy();scene.collection.objects.link(x);copies.append(x)
    bpy.context.view_layer.update()
    ob=art.merge(copies);ob.name=f"Stock_{q.stem}_{q.engine}"
    uv=ob.data.uv_layers.active or ob.data.uv_layers.new();uv.active_render=True
    for p in ob.data.polygons:
        idx=keys.index(ob.data.materials[p.material_index].name)
        for i in p.loop_indices:uv.data[i].uv=((idx+.5)/len(keys),.5)
    target=ROOT/f"mods/luanttd_core/models/bl_stock_{q.stem}.obj"
    bpy.ops.wm.obj_export(filepath=str(target),export_selected_objects=True,export_materials=False,
      export_uv=True,export_normals=True,export_triangulated_mesh=False,global_scale=10,
      forward_axis="NEGATIVE_Z",up_axis="Y")
    art.compact_obj(target)
    bpy.data.objects.remove(ob,do_unlink=True)
    if review:=os.getenv("AIR_E_REVIEW"):
        scene.render.image_settings.file_format="JPEG"
        scene.render.image_settings.quality=91
        apron=[o for o in studio.objects if o.type=="MESH"]
        for name,camera in cameras:
            scene.camera=camera
            for o in apron:o.hide_render=name=="ventral"
            scene.render.filepath=str(Path(review)/f"{q.stem}-{name}.jpg")
            bpy.ops.render.render(write_still=True)

if __name__=="__main__":
    for q in (dart,yate):make(q)

#!/usr/bin/env python3
"""Four original Darwin twinjet airframes for RC1 #227/#229/#230/#231.

DARWIN_FAMILY_REVIEW=/dir blender -b -t 2 --python-exit-code 1 --python tools/build_stock_darwin_family_art.py
Optional DARWIN_FAMILY_IDS='227 231' limits export. No third-party art is imported.
"""
from dataclasses import dataclass
from math import cos, pi, sin, sqrt, tau
from pathlib import Path
import os
import sys

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import build_stock_airliners_e_art as e

art, base, B, C, M = e.art, e.base, e.B, e.C, e.M

@dataclass(frozen=True)
class Frame:
    series: int
    id: int
    description: str
    color: tuple
    fuselage: tuple  # nose, tail, max half-width, crown belt, upper/lower radius
    wing: tuple      # span, root LE/TE, outer LE/TE, root Y, dihedral, thickness
    stabilizer: tuple
    fin: tuple       # root leading edge, tip leading edge, top height
    motor: tuple     # lateral, front/back, center height, intake radius, nozzle radius
    gear: tuple      # main X/Y, main tire radius, axle pitch/count, nose Y/nose radius
    windows: int
    raked: bool = False

    @property
    def stem(self):
        return f"darwin_{self.series}"

FRAMES = [
    Frame(200,227,"Compact first-generation underwing twinjet; short gear and slim long nacelles",
          ("eee9d6","e9ddc3","a94337","783b35","b66336","c19a57"),
          (.79,.76,.122,.208,.112,.105),(.701,.221,-.305,-.134,-.282,.142,.085,.084),
          (.291,-.493,-.747,.250,.026),(-.354,-.613,.476),
          (.261,.197,-.175,.112,.052,.027),(.194,-.098,.047,0,1,.511,.033),18),
    Frame(400,229,"Stretched narrow-body; taller landing gear, slender cabin and curved late-era wing tip",
          ("f1ecda","e3ddd6","446288","303b60","4a4d87","bf9860"),
          (1.051,.992,.135,.279,.131,.116),(.881,.291,-.439,-.234,-.411,.184,.102,.101),
          (.336,-.655,-.973,.338,.034),(-.423,-.772,.608),
          (.322,.165,-.246,.147,.096,.046),(.235,-.137,.054,.059,2,.719,.038),26),
    Frame(500,230,"Mid-era wide-body twinjet; broader cabin, double axle gear and tapered broad fans",
          ("e5eeea","d0e2da","327f79","286061","337e80","cba36c"),
          (.995,1.021,.178,.277,.146,.141),(.927,.339,-.458,-.219,-.436,.196,.110,.110),
          (.385,-.639,-.982,.365,.044),(-.447,-.790,.650),
          (.358,.212,-.238,.158,.113,.051),(.244,-.163,.059,.070,2,.689,.040),25),
    Frame(600,231,"Heavy long-body twinjet; deep pressure shell, swept raked tips and six-wheel main bogies",
          ("e9e9e3","d6dcdf","744c72","4b365f","654774","a99c62"),
          (1.075,1.054,.201,.306,.163,.159),(.975,.365,-.469,-.243,-.467,.212,.133,.124),
          (.427,-.656,-1.021,.392,.047),(-.438,-.832,.715),
          (.387,.221,-.278,.169,.129,.057),(.256,-.177,.062,.068,3,.744,.044),27,True),
]

def profile(q):
    front, aft, w, h, a, b = q.fuselage
    # Explicit elliptical station topology: the variants have unique nose
    # curvature, dimensions, window rows, tail-cone contours and bays.
    forward = (
        (.35,1,.999,1),(.58,.997,1,1),(.68,.977,.986,.974),(.76,.932,.951,.887),
        (.83,.840,.893,.766),(.89,.696,.808,.618),(.934,.532,.683,.455),
        (.968,.354,.501,.302),(.988,.198,.311,.157),(1,.040,.074,.037),
    )
    if q.series == 400:
        forward = forward[:4] + ((.83,.792,.854,.804),(.89,.624,.759,.651),(.934,.442,.590,.451),
             (.968,.268,.406,.288),(.988,.129,.218,.145),(1,.023,.047,.035))
    aft_form = (
        (1,.040,.057,.055),(.977,.185,.215,.190),(.92,.363,.400,.341),(.846,.546,.588,.490),
        (.73,.740,.770,.700),(.59,.876,.913,.881),(.445,.965,.971,.974),(.31,1,1,1),
    )
    return tuple((-aft*t,w*u,h+.043*max(0,t-.40),a*v,b*k) for t,u,v,k in aft_form) + (
        (0,w,h,a,b),) + tuple((front*t,w*u,h-.031*max(0,t-.70),a*v,b*k) for t,u,v,k in forward)

def pressure(q):
    rs=profile(q)
    n=52
    angles=[tau*i/n for i in range(n)]
    tones=[]
    for t in angles:
        s=sin(t+pi/n)
        tones.append("Crown ivory" if s>.82 else "Panel ivory" if s>.37 else
                     "Lit blue" if s>.23 else "Dark coastal cobalt" if s>.025 else
                     "Copper pinstripe" if s>-.075 else "Silver pressure hull" if s>-.67 else "Bellying brushed alloy")
    art.sections("Lofted pressure cylinder, taper and original cheatline",
                 [(y,[(w*cos(t),h+(a if sin(t)>0 else b)*sin(t)) for t in angles]) for y,w,h,a,b in rs],
                 "Silver pressure hull",tones)

    def side(s,y,z,lift):
        w,c,a,b=e.interp(rs,y)
        k=(z-c)/(a if z>=c else b)
        assert abs(k)<1,(q.series,y,z,k)
        return (s*(w*sqrt(1-k*k)+lift),y,z)

    outline=((-1,-.52),(-.63,-1),(.63,-1),(1,-.52),(1,.52),(.63,1),(-.63,1),(-1,.52))
    def trim(name,ink,s,y,z,a,b,depth,frame=False):
        loops=(1,.85) if frame else (1,.62,.29)
        vs=[side(s,y+u*a*k,z+v*b*k,depth) for k in loops for u,v in outline]
        faces=[(j*8+i,j*8+(i+1)%8,(j+1)*8+(i+1)%8,(j+1)*8+i)[::s]
               for j in range(len(loops)-1) for i in range(8)]
        if not frame:
            faces.append(tuple(range(16,24))[::s])
        return M(name,vs,faces,ink)

    front,aft,_,h,_,_=q.fuselage
    for s in (-1,1):
        for j in range(q.windows):
            u=j/(q.windows-1)
            y=(.69*front)*(1-u)-.56*aft*u-(j in (6,7))*.008-(j in (15,16))*.005
            z=h+.044
            trim("Machined pressure-frame surround","Aluminium bezel",s,y,z,.0131,.0162,.0024)
            trim("Curved insulated passenger glazing","Cab glass",s,y,z,.0109,.0121,.0039)
            trim("Slim cabin reflection","Window glint",s,y-.0012,z+.0045,.0062,.0016,.0050)
        door_list=[(.748*front,.0240,.055),(-.621*aft,.029,.055)]
        if q.series != 200:
            door_list.append((.293*front,.020,.038))
        if q.series>=500:
            door_list.append((-.297*aft,.023,.039))
        for y,a,b in door_list:
            trim("Independent pressurized cabin door perimeter","Pressure door seal",s,y,h-.006,a,b,.0044,True)
            trim("Door quarter-light","Cab glass",s,y+.001,h+.017,.0082,.0091,.0057)
            trim("Closed latch slot","Rib inset",s,y-a*.50,h-.013,.0082,.0019,.0065)
        for y in (-.439*aft,.384*front):
            trim("Conformal belly freight-door seam","Pressure door seal",s,y,h-.055,.052,.030,.0044,True)
            trim("Belly freight-door hinged access grip","Rib inset",s,y,h-.049,.015,.0022,.0058)
        for i in range(3):
            y=front*(.56-.036*i)
            vertices=[side(s,y+d,h+k,.006) for d,k in
                      ((-.015,.073),(.013,.092),(.022,.090),(-.006,.071))]
            M("Original Darwin flying-ribbon crest",vertices,[(0,1,2,3)[::s]],"Blue taper")

        def screen(name,ink,from_,to,x0,x1,lift):
            points=[]
            for j in range(9):
                t=j/8
                y=front*(from_*(1-t)+to*t)
                w,c,a,_=e.interp(rs,y)
                for k in range(8):
                    u=x0+(x1-x0)*k/7+(k/7-.74)*t*.12
                    points.append((s*w*u,y,c+a*sqrt(1-u*u)+lift))
            faces=[(j*8+k,j*8+k+1,(j+1)*8+k+1,(j+1)*8+k)[::s] for j in range(8) for k in range(7)]
            M(name,points,faces,ink)
        screen("Curved tapering wraparound windscreen gasket","Glazing bezel",.750,.936,.11,.89,.0022)
        screen("Recessed windscreen with separate front and quarter lites","Cab glass",.763,.922,.16,.856,.0043)
        screen("Dull polished curve reflected in the windshield","Window glint",.801,.832,.197,.527,.0054)
        for x in (.366,.629):
            def p(y):
                w,c,a,_=e.interp(rs,front*y)
                return (s*w*x,front*y,c+a*sqrt(1-x*x)+.0061)
            C("Recessed pressure-glass intermediate mullion",p(.760),p(.924),.0024,.0015,"Glazing bezel",8)
    C("Upper fuselage radio aerial at original deck center",(0,.11,h+q.fuselage[4]),
      (0,.085,h+q.fuselage[4]+.027),.006,.001,"Wing leading trim",9)

def control_surfaces(q):
    span,leading,edge,tip,tipedge,root,dihedral,thick=q.wing
    main=[]
    for f in (.12,.25,.40,.57,.73,.86,.94,1):
        a=leading+(tip-leading)*f**(.95 if not q.raked else .74)
        b=edge+(tipedge-edge)*f
        if q.raked and f>.85:
            a-=.056*((f-.85)/.15)**1.55
        main.append((span*f,a,b,root+dihedral*f**1.18,thick*(1-.94*f)))
    tailspan,a,b,y,t=q.stabilizer
    tail=[(tailspan*f,a-.155*f,b+.024*f,y+.049*f,t*(1-.93*f))
          for f in (.055,.27,.49,.75,.895,1)]
    for side in (-1,1):
        art.foil("Raked swept main wing with camber" if q.raked else "Swept main wing with authentic camber",main,side)
        art.foil("Conventional low tailplane with elevator foil",tail,side)
        x,lead,end,top,_=main[-1]
        C("Fitted wingtip navigation lamp",(side*x,lead+.005,top),(side*x,lead-.022,top),.0078,.0047,
          "Port marker ruby" if side<0 else "Starboard marker mint",10)
        for f in (.32,.52,.70,.83):
            z=edge+(tipedge-edge)*f+.077
            yy=root+dihedral*f*.80-.027
            C("Slotted lower flap-track mechanism fairing",(side*span*f,z+.041,yy),
              (side*span*(f+.038),z-.088,yy+.019),.019,.0055,"Shadowed flap",10)
            z2=edge+(tipedge-edge)*f+.084
            C("Independent flap and spoiler seam",(side*span*f,z2,yy+.088),
              (side*span*(f+.115),z2-.012,yy+.092),.00165,.00153,"Rib inset",6)
    flare, tipa, top = q.fin
    aft=q.fuselage[1]
    stations=tuple((w,q.stabilizer[3]-.061+(top-q.stabilizer[3]+.061)*k,
                    flare+(tipa-flare)*k**.76,-aft*(.99-.064*k)) for k,w in
                   ((0,.019),(.15,.047),(.31,.048),(.52,.039),(.72,.027),(.9,.019),(1,.010)))
    contour=((0,0),(.12,-.48),(.33,-1),(.69,-.67),(.86,-.32),(1,0),(.86,.32),(.69,.67),(.33,1),(.12,.48))
    n=len(contour)
    vs=[(p*w,a+(b-a)*t,y) for w,y,a,b in stations for t,p in contour]
    polys=[tuple(range(n))]
    inks=["Dark coastal cobalt"]
    for j,hue in enumerate(("Dark coastal cobalt","Dark coastal cobalt","Blue taper","Lit blue","Copper pinstripe","Crown ivory")):
        for k in range(n):
            d=(k+1)%n
            polys.append((j*n+k,j*n+d,(j+1)*n+d,(j+1)*n+k));inks.append(hue)
    polys.append(tuple(range(len(vs)-n,len(vs))));inks.append("Crown ivory")
    art.close_mesh("Solid swept vertical fin with inset Darwin fleet stripe",vs,polys,inks)
    _,y,_,b=stations[-1]
    C("Rear white anticollision lamp",(0,b+.025,y),(0,b+.010,y+.003),.008,.0047,"Bright cap light",8)

def engines(q):
    x,nose,tail,h,r,nozzle=q.motor
    def s(u,rr,dy,c):
        return (nose+(tail-nose)*u,rr,h+dy,c)
    hull=(s(0,r*.84,0,"Wing leading trim"),s(.05,r,0,"Skinned wing alloy"),s(.24,r*1.035,-.001,"Silver pressure hull"),
          s(.49,r*.91,.002,"Panel ivory"),s(.68,r*.73,.008,"Shadowed nacelle steel"),s(.85,nozzle*1.20,.013,"Exhaust patina bronze"),
          s(1,nozzle,.016,"Dark intake"),s(.993,nozzle*.82,.016,"Exhaust patina bronze"),
          s(.88,nozzle*.70,.013,"Dark intake"),s(.28,r*.57,.001,"Dark intake"),s(.028,r*.71,0,"Shadowed nacelle steel"))
    for sign in (-1,1):
        art.turbojet("Open individual intake, fan core and annular nacelle",sign*x,hull,"Exhaust patina bronze")
        B("Structural nacelle pylon and pressure fairing",(sign*x,(nose+tail)*.5+.027,h+r*.648),
          (r*.72,(nose-tail)*.52,max(.031,q.wing[5]+.071-h)),"Shadowed nacelle steel",.014,(0,0,sign*.09))
        B("Pylon crown continuation to wing root",(sign*x,(nose+tail)*.5-.056,q.wing[5]+.027),
          (r*.61,.143,.052),"Skinned wing alloy",.013,(0,sign*.04,0))
        C("Separate heat-stained nacelle drain",(sign*x,tail+.055,h-.65*nozzle),
          (sign*x,tail+.022,h-.68*nozzle),.004,.0021,"Warm burner rivets",8)

def gear(q,extended):
    mx,my,r,pitch,n,ny,nr=q.gear
    settings=[(0,ny,nr,1,0,q.fuselage[3]-q.fuselage[5]+.016)]
    settings+= [(side*mx,my,r,n,pitch,q.wing[5]-.017) for side in (-1,1)]
    for x,y,radius,count,spacing,top in settings:
        w=.021 if x else .017
        length=(count-1)*spacing+radius*2.10
        broad=.108 if x else .067
        if not extended:
            B("Flush retracted gear bay with separate hinged door skins",(x,y,top+.002),
              (broad,length,.012),"Shadowed flap",.006)
            C("Closed undercarriage door meeting seam",(x,y-length*.46,top-.005),
              (x,y+length*.46,top-.005),.0018,.0018,"Rib inset",6)
            continue
        B("Dark recessed landing bay throat",(x,y,top+.007),(broad,length,.012),"Well shadow",.003)
        for s in (-1,1):
            B("Open hinged undercarriage bay door",(x+s*broad*.48,y,top-.011),
              (.006,length*.90,.033),"Shadowed flap",.002,(0,-s*.48,0))
        C("Hydraulic telescoping landing-gear strut",(x,y,radius),(x,y-.012,top+.019),
          .0094,.017 if x else .010,"Landing gear chrome",14)
        C("Landing strut real folded torque links",(x,y+.004,radius),(x,y+.056,top+.007),
          .007,.010,"Fan deep metal",10)
        if count>1:
            B("Bogie truck elongated pivot beam",(x,y,radius),(.032,length*.70,.018),"Shadowed nacelle steel",.007)
        for a in range(count):
            axis=y+(a-(count-1)*.5)*spacing
            C("Physical axle passing through both hubs",(x-w*1.53,axis,radius),(x+w*1.53,axis,radius),
              .007,.007,"Landing gear chrome",10)
            for s in (-1,1):
                cx=x+s*w*.82
                npoints=20
                vertices=[(j,axis+radius*cos(-pi/2+i*tau/npoints),radius+radius*sin(-pi/2+i*tau/npoints))
                          for j in (cx-w*.50,cx+w*.50) for i in range(npoints)]
                faces=[tuple(range(npoints))[::-1],tuple(range(npoints,2*npoints))]
                faces.extend((i,(i+1)%npoints,(i+1)%npoints+npoints,i+npoints) for i in range(npoints))
                art.close_mesh("Ground contact tire with exact level runway datum",vertices,faces,
                               ["Dull tire"]*2+["Road contact tread"]*npoints)
                C("Real convex machined wheel hub",(cx+s*w*.48,axis,radius),(cx+s*w*.60,axis,radius),
                  radius*.525,radius*.405,"Landing gear chrome",13)

def write_native(q,scene,objects,mode,colors):
    copies=[]
    for obj in objects:
        copy=obj.copy()
        copy.data=obj.data.copy()
        scene.collection.objects.link(copy)
        copies.append(copy)
    bpy.context.view_layer.update()
    mesh=art.merge(copies)
    mesh.name=getattr(q,"export_name",f"Darwin_{q.series}")+f"_{mode}"
    uv=mesh.data.uv_layers.active or mesh.data.uv_layers.new()
    uv.active_render=True
    indices={name:i for i,name in enumerate(colors)}
    for face in mesh.data.polygons:
        i=indices[mesh.data.materials[face.material_index].name]
        for loop in face.loop_indices:
            uv.data[loop].uv=((i+.5)/len(colors),.5)
    suffix="_flight" if mode=="flight" else ""
    obj=ROOT/f"mods/luanttd_core/models/bl_stock_{q.stem}{suffix}.obj"
    bpy.ops.wm.obj_export(filepath=str(obj),export_selected_objects=True,export_materials=False,
                          export_uv=True,export_normals=True,export_triangulated_mesh=False,global_scale=10,
                          forward_axis="NEGATIVE_Z",up_axis="Y")
    art.compact_obj(obj)
    bpy.data.objects.remove(mesh,do_unlink=True)

def make(q, *, title=None, sprite_family=4, engine_title="Twin open fan nacelles", engine_mesh=engines):
    colors=art.PAL | dict(zip(("Crown ivory","Panel ivory","Lit blue","Dark coastal cobalt","Blue taper","Copper pinstripe"),q.color))
    base.PALETTE=colors
    base.KEYS=list(colors)
    base.begin()
    bpy.context.preferences.filepaths.save_version=0
    e.export_atlas(q.stem,colors)
    scene=bpy.context.scene
    scene.name=f"LuanTTD | {title or f'Darwin {q.series}'} · #{q.id}"
    scene["metadata"]=f"OpenTTD 16.0-RC1 src/table/engines.h #{q.id}: J / fast CTOL; sprite family image {sprite_family}"
    scene["original_art"]=q.description+"; original LuanTTD mesh and invented livery, no third-party image assets"
    scene["native"]= "Nose −Z; deployed gear contacts Luanti Y=0. Flight variant differs only in gear and bay doors."
    def group(title,fn):
        before=set(scene.objects)
        fn()
        return art.new_collection(scene,title,[ob for ob in scene.objects if ob not in before])
    common=[]
    for title,fn in (("01 · Sectioned pressure shell and cabin glazing",pressure),
                     ("02 · Cambered wings, tail, and control surfaces",control_surfaces),
                     (f"03 · {engine_title}",engine_mesh)):
        common.extend(group(title,lambda:fn(q)).objects)
    taxi=group("04 · Deployed struts, bogies and open bays",lambda:gear(q,True))
    flight=group("05 · Closed in-flight gear bays",lambda:gear(q,False))
    for o in flight.objects:
        o.hide_viewport=True
        o.hide_render=True
    def stage():
        B("Review apron, not exported",(0,0,-.041),(7,7,.080),"Studio slab",.006)
        for v in (-2,-1,0,1,2):
            B("Fine apron concrete join",(v,0,-.00045),(.006,7,.0002),"Studio join")
            B("Fine apron concrete join",(0,v,-.00045),(7,.006,.0002),"Studio join")
        for name,p in (("Apron",(2.9,3.4,1.84)),("Ventral",(2.7,-3.2,-1.60))):
            bpy.ops.object.camera_add(location=p)
            cam=bpy.context.object
            cam.name=name
            cam.data.type="ORTHO"
            cam.data.ortho_scale=2.74
            cam.rotation_euler=(Vector((0,0,.25))-cam.location).to_track_quat("-Z","Y").to_euler()
    studio=group("90 · Review apron and cameras, not exported",stage)
    scene.camera=next(o for o in studio.objects if o.name.startswith("Apron"))
    scene.render.engine="BLENDER_WORKBENCH"
    scene.render.resolution_x,scene.render.resolution_y=1120,760
    scene.render.resolution_percentage=100
    scene.display.shading.color_type="MATERIAL"
    scene.display.shading.light="STUDIO"
    scene.display.shading.show_shadows=True
    scene.display.shading.show_cavity=True
    scene.display.shading.cavity_type="BOTH"
    scene.view_settings.view_transform="Standard"
    scene.view_settings.exposure=.28
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":
                v=area.spaces.active
                v.shading.color_type="MATERIAL"
                v.region_3d.view_location=Vector((0,0,.25))
                v.region_3d.view_distance=2.9
                v.region_3d.view_rotation=Vector((1,1.20,.63)).to_track_quat("Z","Y")
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/f"art/stock_{q.stem}.blend"),compress=True)
    write_native(q,scene,common+list(taxi.objects),"ground",colors)
    for o in flight.objects:
        o.hide_viewport=False
        o.hide_render=False
    write_native(q,scene,common+list(flight.objects),"flight",colors)
    if dest:=os.getenv("DARWIN_FAMILY_REVIEW"):
        Path(dest).mkdir(parents=True,exist_ok=True)
        scene.render.image_settings.file_format="JPEG"
        for stage_name in ("apron","ventral"):
            if stage_name=="ventral":
                scene.camera=next(o for o in studio.objects if o.name.startswith("Ventral"))
            for o in studio.objects:
                if o.type=="MESH": o.hide_render=stage_name=="ventral"
            for o in taxi.objects: o.hide_render=stage_name=="ventral"
            for o in flight.objects: o.hide_render=stage_name!="ventral"
            scene.render.filepath=str(Path(dest)/f"{q.stem}-{stage_name}.jpg")
            bpy.ops.render.render(write_still=True)

if __name__=="__main__":
    subset=set(map(int,os.getenv("DARWIN_FAMILY_IDS","").split()))
    for frame in FRAMES:
        if not subset or frame.id in subset:
            make(frame)

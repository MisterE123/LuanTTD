"""Build original late-Victorian masonry road tunnel portals for LuanTTD.

blender -b -t 3 --python-exit-code 1 --python tools/build_road_tunnel_art.py
Optional ROAD_TUNNEL_RENDER=/tmp/portal.png renders the editable showcase.
"""
from math import cos, pi, sin
from pathlib import Path
import os
from random import Random
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_road_bridge_art as common

bpy=common.bpy
Vector=common.Vector
PREFIX="bl_road_tunnel_portal"
COLORS={
    "Asphalt":"4f5255","Road shoulder":"9a937e","Road centre marking":"efe3b6",
    "Grass":"57814c","Grass light":"5a8450","Grass shade":"527c48",
    "Bank gravel":"93868b","Limestone coping":"bbb098","Limestone shadow":"8e8571",
    "Stone field":"a29a84","Stone blue":"92968d","Stone warm":"aaa087","Stone shade":"827f73",
    "Mortar":"66675e","Arch brick":"af6d53","Arch clay":"995a47",
    "Arch rust":"8c5849","Arch mortar":"5d504b","Brick shadow":"744a42",
    "Barrel shadow":"343537","Barrel brick":"3d3a38","Barrel alt":"44423f",
    "Dark curb":"7c7a68","Post ivory":"d5c9a7","Marker enamel":"cb8646",
}
BASE=.5
FACE=.390
REAR=.610
HALF=.422
SPRING=.383
RISE=.270
RING_H=.728
RING_W=.516
STEPS=16


def ground(v):
    return BASE+(v+1)/2


def clear_width(v):
    # The cut necks down onto the retaining masonry without a kink.
    return .5+.233*(FACE-v)/(FACE+1)


def side_poly(m,g,color,points,side):
    m.poly(g,color,*(points if side>0 else points[::-1]))


def between(m,g,color,near,far,v0,v1,side,h):
    side_poly(m,g,color,[(side*near(v0),v0,h(v0)),(side*far(v0),v0,h(v0)),
                         (side*far(v1),v1,h(v1)),(side*near(v1),v1,h(v1))],side)


def front_panel(m,g,color,low,high,y,top,front,back):
    m.box(g,color,low,high,front,back,y,top)


def pavement(v):
    # Physical ground cubes remain below this inclined tile overlay. A
    # microscopic raster bias lifts the painted floor from the cube top,
    # fading to exactly zero at both ends for shared-edge joining.
    return BASE+.004*min(1,8*(1-abs(v)))


def road_deck(m):
    for side in (-1,1):
        a,b=sorted((side*.3125,side*.375))
        for c,d in ((-1,-.875),(-.875,.875),(.875,1)):
            m.section("Shoulder slab","Road shoulder",a,b,c,d,pavement)
    stripes=common.STRIPES
    bounds=sorted({0,32,*(i for span in stripes for i in span)})
    for a,b in zip(bounds,bounds[1:]):
        v0,v1=a/16-1,b/16-1
        if (a,b) in stripes:
            for u0,u1 in ((-.3125,-.0625),(.0625,.3125)):
                m.section("Running asphalt","Asphalt",u0,u1,v0,v1,pavement)
            m.section("Inlaid centre markings","Road centre marking",-.0625,.0625,v0,v1,pavement)
        else:
            m.section("Running asphalt","Asphalt",-.3125,.3125,v0,v1,pavement)


def exterior(m):
    road_deck(m)
    cols=("Grass","Grass light","Grass shade","Grass","Grass")
    rng=Random(0x35515)
    for side in (-1,1):
        # Layers split at the base of the parapet and match the four corners
        # of ordinary stock terrain all the way around the replaced tile.
        widths=tuple(-1+i*(FACE+1)/10 for i in range(11))
        for a,b in zip(widths,widths[1:]):
            between(m,"Approach gravel shoulders","Bank gravel",lambda _:.375,clear_width,a,b,side,pavement)
            between(m,"Wing coping","Limestone coping",clear_width,lambda v:clear_width(v)+.082,
                    a,b,side,ground)
            between(m,"Excavated turf flanks",rng.choice(cols),
                    lambda v:clear_width(v)+.082,lambda _:1.,a,b,side,ground)
            # Model coursed stone faces as separate tilted strip polygons,
            # so the grass is never painted across the road cut.
            for course in range(7):
                brick_h=.097
                lo=BASE+course*brick_h
                ceil=lambda v,l=lo:min(l+brick_h,ground(v))
                floor=lambda v,l=lo:min(l,ground(v))
                start=max(a,2*(lo-BASE)-1)
                if start>=b:
                    continue
                # Keep grout slender but skip degenerate ends at the taper.
                s=min(b,start+.002)
                if s>=b: continue
                panel=[(side*clear_width(s),s,floor(s)),(side*clear_width(b),b,floor(b)),
                       (side*clear_width(b),b,ceil(b)),(side*clear_width(s),s,ceil(s))]
                # Inner wall normals face the roadway.
                side_poly(m,"Dressed wing masonry",("Stone field","Stone blue","Stone warm","Stone shade")[(course+int((a+1)*6))%4],
                          panel,-side)
    # Stone end wall and soil slope merge behind the crown. Full width of
    # the high edge is preserved at exactly .5+1, with the barrel open.
    for side in (-1,1):
        between(m,"Main slope outer grass","Grass",lambda _:.65,lambda _:1.,FACE,REAR,side,ground)
    m.box("Limestone lintel","Limestone shadow",-.65,.65,FACE-.055,REAR,
          BASE+.728,BASE+.745,end_faces=True,face_colors={"top":"Limestone coping"})
    # Turf bed stitches the top of the lintel back to the higher original
    # incline. Fill the neck rather than leave a skyline gap behind the cap.
    front=FACE+.002
    for u0,u1 in ((-.65,-.55),(-.55,.55),(.55,.65)):
        low0=ground(front) if abs(u0)==.65 else BASE+.745
        low1=ground(front) if abs(u1)==.65 else BASE+.745
        m.poly("Lintel crown embankment","Grass",(u0,front,low0),(u1,front,low1),
               (u1,REAR,ground(REAR)),(u0,REAR,ground(REAR)))
    for i in range(6):
        a=REAR+i*(1-REAR)/6
        b=REAR+(i+1)*(1-REAR)/6
        for j in range(8):
            m.section("Crown turf",rng.choice(cols),-1+j*.25,-1+(j+1)*.25,a,b,ground)


def arch(theta,width,rise):
    return width*cos(theta),BASE+SPRING+rise*sin(theta)


def arch_recess(m):
    # The face is not a textured quad: these jambs and voussoirs are all
    # outside the clear cross-section of the bored brick barrel.
    for sign in (-1,1):
        a,b=sorted((sign*.421,sign*.537))
        front_panel(m,"Historic brick jambs","Arch mortar",a,b,BASE,BASE+SPRING,FACE-.009,REAR)
        for i in range(6):
            lo=BASE+i*SPRING/6
            tone=("Arch rust","Arch brick","Arch clay")[i%3]
            front_panel(m,"Jamb brick courses",tone,a-.004,b+.004,lo+.003,lo+SPRING/6-.002,
                       FACE-.032,FACE)
        lo_u,hi_u=sorted((sign*.535,sign*.651))
        for i in range(10):
            lo=BASE+i*.073
            c=("Stone field","Stone blue","Stone warm","Stone shade")[(i+sign+1)%4]
            front_panel(m,"Portal dressed-stone flanks",c,lo_u,hi_u,lo+.001,lo+.072,
                       FACE-.013+(i%2)*.005,REAR)
        lo_u,hi_u=sorted((sign*.374,sign*.418))
        front_panel(m,"Low barrel curbs","Dark curb",lo_u,hi_u,BASE,BASE+.020,FACE-.011,1)
        lo_u,hi_u=sorted((sign*.409,sign*.428))
        for i,v in enumerate((-.18,FACE-.087)):
            # Enamel reflector tablets outside either live lane.
            m.box("Approach reflector tablet","Post ivory",lo_u,hi_u,v-.015,v+.015,
                  BASE+.005,BASE+.06)
            m.box("Approach enamel marker","Marker enamel",lo_u,hi_u,v-.017,v+.007,
                  BASE+.035,BASE+.053)
    for i in range(STEPS):
        dt=pi/STEPS
        ta,tb=pi-i*dt,pi-(i+1)*dt
        ix,ih=arch(ta,HALF,RISE)
        jx,jh=arch(tb,HALF,RISE)
        ox,oh=arch(ta,RING_W,RING_H-SPRING)
        px,ph=arch(tb,RING_W,RING_H-SPRING)
        ng="Mortared arch backing"
        m.poly(ng,"Arch mortar",(ix,FACE,ih),(jx,FACE,jh),(px,FACE,ph),(ox,FACE,oh))
        # Retaining spandrel above the voussoir, with no geometry spanning
        # the inner arch. Fill to the independent limestone crown.
        m.poly("Stone spandrel face",("Stone field","Stone warm","Stone blue","Stone field")[i%4],
               (ox,FACE,oh),(px,FACE,ph),(px,FACE,BASE+.744),(ox,FACE,BASE+.744))
        if i==0 or i==STEPS-1:
            a,b=(sorted((ox,-.537)) if i==0 else sorted((px,.537)))
            m.box("Springing block","Limestone shadow",a,b,FACE-.01,REAR,BASE+SPRING,BASE+.73)
        t0,t1=ta-.012,tb+.012
        points=[arch(t0,HALF+.002,RISE+.002),arch(t1,HALF+.002,RISE+.002),
                arch(t1,RING_W-.005,RING_H-SPRING-.004),arch(t0,RING_W-.005,RING_H-SPRING-.004)]
        tone=("Arch brick","Arch clay","Arch rust","Arch clay")[(i+1)%4]
        m.poly("Raised fired-brick voussoirs",tone,*[(x,FACE-.043,h) for x,h in points])
        for j in range(4):
            (x,h),(u,g)=points[j],points[(j+1)%4]
            m.poly("Voussoir return faces","Brick shadow",(u,FACE-.043,g),(x,FACE-.043,h),
                   (x,FACE+.002,h),(u,FACE+.002,g))
        # Exposed rib is genuinely hollow and open at the rear face. Each
        # intrados face normal points into the tunnel, not up into the hill.
        for row in range(8):
            a=FACE+row*(1-FACE)/8
            b=FACE+(row+1)*(1-FACE)/8
            tone=("Brick shadow","Barrel brick","Barrel alt","Barrel shadow")[
                min(3,row//2) if i%2 else min(3,(row+1)//2)]
            m.poly("Recessed vaulted brick barrel",tone,(ix,a,ih),(ix,b,ih),(jx,b,jh),(jx,a,jh))
    # Tunnel walls remain just outside the arch's footprint. No dark plane
    # crosses the opening at either side of the tile.
    for side in (-1,1):
        for i in range(8):
            v0=FACE+i*(1-FACE)/8;v1=FACE+(i+1)*(1-FACE)/8
            for course in range(5):
                a=BASE+course*SPRING/5
                b=BASE+(course+1)*SPRING/5
                tone=("Brick shadow","Barrel brick","Barrel alt","Barrel shadow")[
                    min(3,(i+(course%2))//2)]
                g="Recessed barrel brick walls"
                side_poly(m,g,tone,[(side*HALF,v0,a),(side*HALF,v1,a),
                    (side*HALF,v1,b),(side*HALF,v0,b)],-side)
    m.box("Arch keystone","Limestone coping",-.036,.036,FACE-.078,FACE+.005,
           BASE+.664,BASE+.743,face_colors={"left":"Limestone shadow","right":"Stone warm"})


def lowered(shape):
    result=common.Mesh()
    for g,faces in shape.groups.items():
        for color,points in faces:
            result.groups[g].append((color,tuple((x,z,y-1) for x,z,y in points)))
    return result


def showcase(collection):
    scene=bpy.context.scene
    common.instance(collection,(0,0,0))

    def cube(name,loc,scale,rgb):
        bpy.ops.mesh.primitive_cube_add(size=1,location=loc)
        ob=bpy.context.object;ob.name=name;ob.scale=scale
        mat=bpy.data.materials.new(name);mat.diffuse_color=(*rgb,1)
        ob.data.materials.append(mat)
    # Nearby banks situate the portal while exposing the actual aperture.
    # The hill mass begins behind the art's mesh at v=1.
    cube("Lower valley bank",(0,-2.6,.18),(8,3.2,.64),(.117,.238,.105))
    # This sectional showcase keeps the two-lane bore open beyond the
    # portal, with its first dark retaining course visible in the distance.
    cube("Nearby crest",(0,2.5,1.36),(8,3,.28),(.117,.238,.105))
    for x in (-2.21,2.21):
        cube("Crest sides",(x,2.5,.64),(3.58,3,1.28),(.117,.238,.105))
    cube("Deep interior stone",(0,3.83,.64),(.845,.13,1.29),(.018,.019,.021))
    cube("Deep roadway",(0,2.5,.490),(.75,3,.020),(.035,.037,.041))
    cube("Continuation roadway",(0,-2.59,.493),(.629,3.18,.016),(.078,.084,.092))
    bpy.ops.object.camera_add(location=(2.30,-4.85,2.08))
    camera=bpy.context.object
    camera.rotation_euler=(Vector((0,.04,.78))-camera.location).to_track_quat("-Z","Y").to_euler()
    camera.data.type="ORTHO";camera.data.ortho_scale=4.10
    scene.camera=camera
    scene.render.engine="BLENDER_WORKBENCH"
    scene.render.resolution_x=1400;scene.render.resolution_y=940
    scene.display.shading.light="STUDIO"
    scene.display.shading.studio_light="paint.sl"
    scene.display.shading.color_type="MATERIAL"
    scene.display.shading.show_shadows=True
    scene.display.shading.show_cavity=True
    scene.display.shading.cavity_type="BOTH"
    scene.display.shading.cavity_ridge_factor=1.32
    scene.display.shading.background_type="WORLD"
    scene.world=bpy.data.worlds.new("Cloudy valley")
    scene.world.color=(.14,.19,.25)
    scene.view_settings.view_transform="Standard"


def main():
    common.PREFIX=PREFIX
    common.COLORS=COLORS
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    bpy.context.scene.name="LuanTTD | Historic road tunnel portal"
    shapes=common.Mesh()
    exterior(shapes);arch_recess(shapes)
    materials=common.materials()
    parts={}
    for d in range(4):
        model=shapes.oriented(d)
        # Export with no double elevation: the occupied node is base+1.
        common.export(str(d),lowered(model))
        parts[d]=common.author(model,f"Portal dir {d}",materials)
    common.atlas()
    showcase(parts[1])
    bpy.ops.wm.save_as_mainfile(filepath=str(common.ROOT/"art"/"road_tunnel_portal.blend"),compress=True)
    if out:=os.getenv("ROAD_TUNNEL_RENDER"):
        bpy.context.scene.render.filepath=out
        bpy.ops.render.render(write_still=True)


if __name__=="__main__":
    main()

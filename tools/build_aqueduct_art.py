"""Author LuanTTD's original cut-masonry aqueduct kit.

blender -b -t 3 --python-exit-code 1 --python tools/build_aqueduct_art.py
AQUEDUCT_RENDER=/tmp/aqueduct.png optionally renders the editable scene.
"""
import os
from pathlib import Path
from random import Random
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_road_bridge_art as common
from build_road_bridge_girder_art import bevel_footprint, prism

bpy=common.bpy
Vector=common.Vector
PREFIX="bl_aqueduct"
COLORS={
    "Canal water":"2a617e", "Canal ripple":"45849e",
    "Sloped grass":"57814c", "Outer grass":"527c48", "Underbank soil":"6a6252",
    "Sill limestone":"a4a191", "Light limestone":"b8af99",
    "Stone ochre":"98907b", "Grey limestone":"7f8279",
    "Dressed masonry":"908779", "Rusticated stone":"a09784",
    "Dark mortar":"706f62", "Wet stone":"677b78", "Wet green":"627373",
    "Algae by water":"648376", "Dark landing":"605f53",
    "Dark soffit":"77766c", "Bronze chisel":"89816a",
    "Waterline trim":"a0a592", "Iron weep holes":"484f4e",
}
WATER=.5
CHANNEL=.56
WALL=.705
SILL=.115
WALL_TOP=.828


def mix(a,b,t):
    return a+(b-a)*t


def head_width(v):
    # Wider opening at the real neighbouring canal tile; the last 55% of
    # the head has exactly the same bore as the middle repeating piece.
    return mix(1.,CHANNEL,min(1,max(0,(v+1)/1.10)))


def head_wall(v):
    return mix(WATER,WALL_TOP,min(1,max(0,(v+.969)/.515)))


def surface(m,is_head):
    """Watertight shared top; ripples share the ground water palette."""
    rng=Random(19781)
    N=36
    rows=sorted({-1+i*2/N for i in range(N+1)}|({.10} if is_head else set()))
    for i,(a,b) in enumerate(zip(rows,rows[1:])):
        w0,w1=(head_width(a),head_width(b)) if is_head else (CHANNEL,CHANNEL)
        den=16
        # Occasional two short ripples, never on either end seam.
        ripples=({rng.randrange(2,den-2)} if (i not in (0,len(rows)-2) and i%4 in (1,2)) else set())
        cuts=sorted({0,den}|{k for r in ripples for k in (r,r+1)})
        for low,high in zip(cuts,cuts[1:]):
            p,q=2*low/den-1,2*high/den-1
            # Fade water pattern geometrically into the uniform identical
            # adjoining water color.
            m.poly("Continuous level water", "Canal ripple" if low in ripples else "Canal water",
                   (p*w0,a,WATER),(q*w0,a,WATER),(q*w1,b,WATER),(p*w1,b,WATER))


def varying_box(m,g,color,side,a,b,inner,outer,h0,h1,ends=True):
    """Loft one waterway course; all attached members have real faces."""
    low=lambda v:h0(v) if callable(h0) else h0
    high=lambda v:h1(v) if callable(h1) else h1
    # Iterate constants in sorted cross-track order for exterior winding.
    def at(v):
        return sorted((side*inner(v),side*outer(v)))
    u0,u1=at(a);w0,w1=at(b)
    p=((u0,a,low(a)),(u1,a,low(a)),(w1,b,low(b)),(w0,b,low(b)),
       (u0,a,high(a)),(u1,a,high(a)),(w1,b,high(b)),(w0,b,high(b)))
    for j,ids in enumerate(((0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7))):
        if ends or j not in (2,4):
            m.poly(g,color,*(p[i] for i in ids))


def flat_width(v):
    return CHANNEL


def parapet(m,is_head):
    w=head_width if is_head else flat_width
    height=head_wall if is_head else lambda _v:WALL_TOP
    def inset(v,amount):
        return w(v)+amount*min(1.,(1.-w(v))/.18)
    outer=lambda v:inset(v,WALL-CHANNEL)
    narrow=lambda v:inset(v,.108)
    lintel=lambda v:inset(v,.160)
    a=-.9375 if is_head else -1.
    has_shoulder=(-1.,-.5,0.,.5,1.)
    if is_head:
        has_shoulder=(a,-.90,-.78,-.65,-.58,-.454,-.30,.10,.4,.7,1.)
    for side in (-1,1):
        for i,(v0,v1) in enumerate(zip(has_shoulder,has_shoulder[1:])):
            # Continuous wet lining and upper limestone coping preserve
            # lateral width and seam, despite actual laid exterior courses.
            varying_box(m,"Continuous watertight trough lining","Wet stone",side,v0,v1,w,narrow,
                        .195,lambda v:height(v)-.008,ends=False)
            varying_box(m,"Individually laid upper coping",
                        ("Light limestone","Sill limestone","Light limestone")[i%3],
                        side,v0,v1,w,lintel,lambda v:height(v)-.008,height,ends=False)
            # Visible distinctive bands on the outer masonry retaining wall.
            # Subdegree strips keep every swimming contact face flush.
            varying_box(m,"Continuously profiled masonry band",
                        ("Grey limestone","Rusticated stone","Dressed masonry")[i%3],
                        side,v0,v1,narrow,outer,.245,lambda v:height(v)-.021,ends=False)
        # Original staggered external masonry relief, shallow enough not
        # to change the assembled footprint. The continuous base underneath
        # stays solid; the reveal is real geometry, not projected texture.
        for course in range(3):
            limits=sorted({-1.,1.}|{i*.232+.109*(course%2)-1 for i in range(1,9)})
            for j,(left,right) in enumerate(zip(limits,limits[1:])):
                left=max(left,.102) if is_head else left
                left+=.005
                right-=.005
                if right-left<.016:
                    continue
                y=.396+course*.117
                material=("Rusticated stone","Dressed masonry","Stone ochre","Sill limestone","Grey limestone")[(2*j+course)%5]
                varying_box(m,"Staggered laid limestone blocks",material,side,left,right,
                            lambda q:WALL-.004,lambda q:WALL+.006+(j%3)*.001,
                            y,y+.108)
        # High inner stone above the water and behind the original bore
        # plane. This recessed part cannot reach into the ferry clearance.
        for i,v in enumerate((-.74,-.37,0,.37,.74)):
            if is_head and v<.1:
                continue
            varying_box(m,"Inset inner bank stones","Light limestone" if i%2 else "Waterline trim",
                        side,v-.173,v+.173,lambda q:CHANNEL+.001,lambda q:CHANNEL+.007,
                        .665,.779)
        # Real course variation, a damp lower band and a raised stone string.
        for i in range(12):
            v0= -1+i/6;v1=v0+1/6
            if is_head and v0<.1:
                continue
            gap=.004 if i in (1,4,6,8,10) else 0.
            varying_box(m,"Aged external ashlar courses",
                        ("Stone ochre","Dressed masonry","Rusticated stone","Sill limestone")[i%4],
                        side,v0+gap,v1-gap,lambda q:WALL-.012,lambda q:WALL+.020,
                        .247,.347)
        start=-.935 if is_head else -1
        breaks=(start,-.454,.10,1) if is_head else (start,1)
        for v0,v1 in zip(breaks,breaks[1:]):
            varying_box(m,"Continuous submerged reinforcing band","Algae by water",side,
                        v0,v1,lambda v:w(v)+.001,narrow,.440,.481,ends=False)
        start=-.907 if is_head else -1
        breaks=(start,.10,1) if is_head else (start,1)
        for v0,v1 in zip(breaks,breaks[1:]):
            varying_box(m,"Continuous masonry exterior string","Sill limestone",side,v0,v1,
                        narrow,lintel,.352,.382,ends=False)


def span(m):
    surface(m,False)
    parapet(m,False)
    m.box("Water-retaining solid floor","Dressed masonry",-.708,.708,-1,1,SILL,.215,
          end_faces=False,face_colors={"under":"Dark soffit"})
    for v in (-.683,-.224,.224,.683):
        m.box("Under-deck engaged spandrel","Dark soffit",-.678,.678,v-.066,v+.066,.083,.117)
    for side in (-1,1):
        l,r=sorted((side*.676,side*.721))
        for v in (-.50,.50):
            m.box("Dark weep openings","Iron weep holes",l,r,v-.021,v+.021,.265,.305)
    # Facing blocks are supported by this continuous sculpted lower string.
    for side in (-1,1):
        a,b=sorted((side*.642,side*.712))
        m.box("Restrain course beneath wet liner","Grey limestone",a,b,-1,1,
              .191,.247,end_faces=False)


def head(m):
    surface(m,True)
    parapet(m,True)
    # The stock head has a level water floor but its bank slopes down
    # toward the aqueduct; the wing stone partially encloses that bank.
    # Core flood lining merges at exactly the span seam.
    for a,b in ((-1,-.80),(-.8,-.45),(-.45,-.19),(-.19,.10),(.10,1)):
        w0,w1=head_width(a),head_width(b)
        h0=.5-(a+1)/2
        h1=.5-(b+1)/2
        m.poly("Basin rubble underlining","Underbank soil",
               (-w0,a,min(.215,h0)),(-w1,b,min(.215,h1)),
               (w1,b,min(.215,h1)),(w0,a,min(.215,h0)))
        for side in (-1,1):
            u0,u1=sorted((side*min(1,w0+.161),side*1))
            s0,s1=sorted((side*min(1,w1+.161),side*1))
            # Skip a zero-area first sliver. Outermost terrain x/z corner
            # still occupied by full canal water at the former high edge.
            # Each sloped flank is anchored into the native row at y=-.5..+.5.
            if u0==u1 and s0==s1:
                continue
            m.poly("Natural sloping head banks","Sloped grass",
                   (u0,a,h0),(u1,a,h0),(s1,b,h1),(s0,b,h1)) if u0!=u1 else (
                m.poly("Natural sloping head banks","Sloped grass",(u0,a,h0),(s1,b,h1),(s0,b,h1)))
    m.box("Water-retaining solid floor","Dressed masonry",-.708,.708,.10,1,SILL,.215,
          end_faces=False,face_colors={"under":"Dark soffit"})
    for side in (-1,1):
        a,b=sorted((side*.642,side*.712))
        m.box("Restrain course beneath wet liner","Grey limestone",a,b,.10,1,
              .191,.247,end_faces=False)
        for i,pos in enumerate((-.19,.10,.39,.68)):
            phase=(pos+1)/2
            h= .21 - .46*phase
            low,high=sorted((side*.642,side*.775))
            m.box("Laid abutment retaining courses",("Dressed masonry","Sill limestone","Stone ochre")[i%3],
                  low,high,pos-.102,pos+.102,h-.15,.193)
        a,b=sorted((side*.626,side*.79))
        m.box("End abutment coping","Waterline trim",a,b,-.31,-.13,.22,.248)
        # A flush brass notch is inset on each shore, not hanging over
        # or blocking a naval mast anywhere in the channel.
        v=-.315
        if side>0: a,b=(.83,.872)
        else: a,b=(-.872,-.83)
        m.box("Masonry survey benchmark","Bronze chisel",a,b,v-.032,v+.032,.436,.451)


def pier(m,top):
    column=bevel_footprint(.626,.322,.059)
    if top:
        shaft=bevel_footprint(.638,.345,.059)
        crown=bevel_footprint(.785,.485,.080)
        ledge=bevel_footprint(.902,.505,.071)
        prism(m,"Raked upper pier shaft","Dressed masonry",column,shaft,-.5,.767,under=False)
        prism(m,"Spreading capital","Stone ochre",shaft,crown,.767,.963)
        prism(m,"Bearing block and slab","Sill limestone",crown,ledge,.963,1.115,
              above=False)
        extent=1.12
    else:
        prism(m,"Repeating lower pier shaft","Dressed masonry",column,column,-.5,.5,
              above=False,under=False)
        extent=.5
    for i,h in enumerate((-.402,-.127,.148,.342,.648) if top else (-.352,-.081,.194,.403)):
        foot=bevel_footprint(.653+i%2*.006,.345,.060)
        prism(m,"Jointed masonry columns",("Rusticated stone","Grey limestone","Sill limestone")[i%3],
              foot,foot,h-.057,min(extent,h+.06))


def showcase(parts):
    scene=bpy.context.scene
    for x in (-4,4):
        direction=2 if x<0 else 0
        common.instance(parts[f"head_{direction}"],(x,0,1.28))
    for x in (-2,0,2):
        common.instance(parts["span_0"],(x,0,1.28))
        if x!=0:
            common.instance(parts["pier_head_0"],(x,0,.28))
            common.instance(parts["pier_0"],(x,0,-.72))

    def block(name,loc,scale,rgb):
        bpy.ops.mesh.primitive_cube_add(size=1,location=loc)
        o=bpy.context.object;o.name=name;o.scale=scale
        mat=bpy.data.materials.new(name);mat.diffuse_color=(*rgb,1);o.data.materials.append(mat)
    block("Below, a level valley",(0,0,-.40),(19,14,.30),(.15,.245,.103))
    block("Masonry railway bed",(0,0,-.222),(1.4,16,.08),(.194,.19,.166))
    # Cropped aqueduct ends reveal that the channel matches the upper canal.
    for sign in (-1,1):
        block("Upland bank",(sign*6.6,0,.743),(3.2,9,2.074),(.15,.27,.114))
        block("Joined elevated canal",(sign*6.6,0,1.783),(3.2,1.99,.010),(.0178,.12,.208))
    bpy.ops.object.camera_add(location=(10,-12,7.4))
    camera=bpy.context.object
    camera.rotation_euler=(Vector((0,0,1.0))-camera.location).to_track_quat("-Z","Y").to_euler()
    camera.data.type="ORTHO";camera.data.ortho_scale=13.
    scene.camera=camera
    scene.render.engine="BLENDER_WORKBENCH"
    scene.render.resolution_x=1440;scene.render.resolution_y=810
    scene.display.shading.light="STUDIO"
    scene.display.shading.studio_light="paint.sl"
    scene.display.shading.color_type="MATERIAL"
    scene.display.shading.show_shadows=True
    scene.display.shading.show_cavity=True
    scene.display.shading.cavity_type="BOTH"
    scene.display.shading.cavity_ridge_factor=1.38
    scene.display.shading.background_type="WORLD"
    scene.world=bpy.data.worlds.new("Upland aqueduct sky")
    scene.world.color=(.13,.19,.25)
    scene.view_settings.view_transform="Standard"


def main():
    common.PREFIX=PREFIX
    common.COLORS=COLORS
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    bpy.context.scene.name="LuanTTD | Cut limestone aqueduct"
    m=common.Mesh();head(m)
    files={f"head_{d}":m.oriented(d) for d in range(4)}
    for key,build in (("span",span),("pier_head",lambda m:pier(m,True)),("pier",lambda m:pier(m,False))):
        m=common.Mesh();build(m)
        for axis,d in ((0,2),(1,1)):
            files[f"{key}_{axis}"]=m.oriented(d)
    mats=common.materials()
    parts={}
    for key,shape in files.items():
        common.export(key,shape)
        parts[key]=common.author(shape,key,mats)
    common.atlas()
    showcase(parts)
    bpy.ops.wm.save_as_mainfile(filepath=str(common.ROOT/"art"/"aqueduct.blend"),compress=True)
    if target:=os.getenv("AQUEDUCT_RENDER"):
        bpy.context.scene.render.filepath=target
        bpy.ops.render.render(write_still=True)


if __name__=="__main__":
    main()

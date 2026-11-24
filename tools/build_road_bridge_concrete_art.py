"""Author a stock-compatible original short cast-concrete bridge in Blender.

blender -b -t 3 --python-exit-code 1 --python tools/build_road_bridge_concrete_art.py
CONCRETE_BRIDGE_RENDER=/tmp/concrete.png additionally renders the showcase.
"""
from math import cos, pi, sin
import os
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_road_bridge_art as common
from build_road_bridge_girder_art import bevel_footprint, prism

bpy=common.bpy
PREFIX="bl_road_bridge_concrete"
COLORS={
    "Asphalt":"4f5255", "Road shoulder":"9a937e", "Road centre marking":"efe3b6",
    "Concrete pale":"bab39d", "Concrete warm":"a8a28c", "Concrete mid":"9c9a89",
    "Concrete shade":"82847b", "Concrete edge":"c4baa3", "Concrete soffit":"807c6e",
    "Red oxide fascia":"92604f", "Red oxide varied":"9d6956", "Red oxide recess":"79564c",
    "Dressed masonry":"a29580", "Quoins":"b3a58c", "Mortar strip":"827e71",
    "Stained pier base":"738078", "Drain opening":"393d39", "Bronze inscription":"686957",
}


def pair(side,a,b):
    return sorted((side*a,side*b))


def depth(v):
    """Haunches pass over the bent; paired half arches join at span edges."""
    return .237+.17*cos(pi*v/2)**2


def ring(front,inside,span,h,side):
    """Two faces of a small cast drain, round rather than planar rivet dots."""
    def points(offset,r):
        return [(side*offset,span+r*cos(i*pi/3),h+side*r*sin(i*pi/3)) for i in range(6)]
    return points(front,.028),points(inside,.018)


def drain(m,h,side,v):
    rim,inner=ring(.477,.484,v,h(v)-.139,side)
    bore=[(side*.470,z,y) for _,z,y in inner]
    for i in range(6):
        j=(i+1)%6
        m.poly("Cantilevered drainage relief","Concrete shade",rim[i],rim[j],inner[j],inner[i])
        m.poly("Cantilevered drainage relief","Concrete soffit",inner[i],inner[j],bore[j],bore[i])
    m.poly("Cast drain shade","Drain opening",*bore)


def deck(m,h,is_head,*,road_surface=True):
    if road_surface:
        common.running_surface(m,h)
    m.box("Continuous cast roadway slab","Concrete warm",-.463,.463,-1,1,
          lambda v:h(v)-.105,lambda v:h(v)-.004,end_faces=False,
          face_colors={"under":"Concrete soffit"})
    steps=tuple(-1+i/12 for i in range(25))
    # Tapered concrete soffit. It is a shaped load-bearing section, without
    # flat decorative edges painted onto a box. Through lanes clear it at
    # one logical height level below the deck away from the interior piers.
    for a,b in zip(steps,steps[1:]):
        m.box("Continuous load-bearing haunch","Concrete mid",-.431,.431,a,b,
              lambda q:h(q)-depth(q),lambda q:h(q)-.102,end_faces=False,
              face_colors={"under":"Concrete soffit"})
    for side in (-1,1):
        a,b=pair(side,.412,.480)
        m.box("Continuous projecting cornice","Concrete edge",a,b,-1,1,
              lambda q:h(q)-.101,lambda q:h(q)-.038,end_faces=False,
              face_colors={"under":"Concrete shade"})
        # Pigmented concrete panels, matching the stock palette idea but
        # designed independently, with real set-back vertical channels.
        a,b=pair(side,.429,.455)
        for i,(lo,hi) in enumerate(zip(steps,steps[1:])):
            if i not in (0,len(steps)-2):
                inset=.0018 if i%3==0 else 0.
                lo+=inset;hi-=inset
            paint=("Red oxide fascia","Red oxide recess","Red oxide varied")[i%3]
            m.box("Continuous pigmented concrete fascia",paint,a,b,lo,hi,
                  lambda q:h(q)-depth(q)+.019,lambda q:h(q)-.102,end_faces=False,
                  face_colors={"under":"Red oxide recess"})
        for v in (-.47,.48):
            drain(m,h,side,v)


def parapet(m,h,is_head):
    for side in (-1,1):
        a,b=pair(side,.383,.459)
        lead=-.815 if is_head else -1.
        for lo,hi,g,c in ((.005,.082,"Continuous parapet base","Concrete warm"),
                           (.240,.307,"Continuous parapet coping","Concrete pale")):
            m.box(g,c,a,b,lead,1,
                  lambda q,k=lo:h(q)+k,lambda q,k=hi:h(q)+k,end_faces=False,
                  face_colors={"top":"Concrete edge","under":"Concrete shade"})
        centers=((-.675 if is_head else -.735),-.36,0,.36,.735)
        # Cast balustrade relief is backed only above each actual aperture.
        thick=pair(side,.389,.454)
        for i,center in enumerate(centers):
            if i==0 and is_head:
                low=lead
            else:
                low=(-1, -.548,-.18,.18,.548)[i]
            high=(-.548,-.18,.18,.548,1)[i]
            rad=.118
            for q,w in ((low,center-rad),(center+rad,high)):
                m.box("Solid cast parapet webs","Concrete mid",*thick,q,w,
                      lambda v:h(v)+.081,lambda v:h(v)+.241,end_faces=False,
                      face_colors={"under":"Concrete shade"})
            for j in range(8):
                u=center+rad*cos(pi*(8-j)/8)
                v=center+rad*cos(pi*(7-j)/8)
                lower=lambda x,c=center:h(x)+.158+.068*sin(pi*(8-j)/8) if abs(x-u)<1e-9 else h(x)+.158+.068*sin(pi*(7-j)/8)
                m.box("True recessed arch apertures","Concrete warm",*thick,u,v,lower,
                      lambda q:h(q)+.241,end_faces=False,
                      face_colors={"under":"Concrete soffit","right":"Concrete pale"})
            a,b=pair(side,.450,.471)
            if i%2==0:
                m.box("Parapet pilaster ribs","Concrete pale",a,b,low+.018,low+.038,
                      lambda q:h(q)+.029,lambda q:h(q)+.260)
        # Continuous aperture webs are already closed where the approach
        # arch begins. Finish the outer edge with a tapered stone post.
        if is_head:
            a,b=pair(side,.379,.479)
            m.box("Chamfered terminal pilasters","Quoins",a,b,lead-.041,lead+.032,
                  lambda q:h(q)-.012,lambda q:h(q)+.287)
            m.box("Terminal pilaster cap","Concrete edge",a-.005,b+.005,lead-.048,lead+.044,
                  lambda q:h(q)+.287,lambda q:h(q)+.323)


def abutment(m,h):
    m.box("Head bearing shelf","Concrete shade",-.478,.478,-.55,.45,
          lambda q:h(q)-depth(q)-.081,lambda q:h(q)-depth(q)+.018)
    for side in (-1,1):
        a,b=pair(side,.323,.48)
        for i in range(4):
            a0=-.55+i*.235;b0=a0+.225
            m.box("Cast wing and masonry coursing","Dressed masonry",a,b,a0,b0,
                  lambda v:h(v)-depth(v)-.247,lambda v:h(v)-depth(v)-.105,
                  face_colors={"under":"Mortar strip"})
            a,b=pair(side,.323,.48-i*.008)


def shifted(poly,u,v):
    return tuple((x+u,z+v) for x,z in poly)


def footing():
    return bevel_footprint(.089,.179,.021)


def cap(m):
    # Two shallow beams above the clearance envelope. Four offset
    # legs avoid both legal road orientations under a lowest live span.
    for v in (-.625,.625):
        ledge=shifted(bevel_footprint(.985,.265,.035),0,v)
        prism(m,"Integral bent support head","Concrete shade",ledge,ledge,-.112,.184)
        for u in (-.445,.445):
            pier=shifted(footing(),u,v)
            crown=shifted(bevel_footprint(.104,.219,.024),u,v)
            prism(m,"Tapered cast shoulder","Concrete warm",pier,crown,-.27,-.112)
            prism(m,"Continue to pier course","Dressed masonry",pier,pier,-.500,-.27,under=False)


def pier(m):
    for u in (-.445,.445):
        for v in (-.625,.625):
            section=shifted(footing(),u,v)
            prism(m,"Pier stack load-bearing core","Dressed masonry",section,section,-.5,.5,
                  under=False,above=False)
            for i in range(5):
                lo=-.489+i*.195
                c=("Concrete warm","Concrete mid","Dressed masonry","Quoins","Concrete warm")[i]
                belt=shifted(bevel_footprint(.094+i%2*.008,.196,.022),u,v)
                prism(m,"Detailed cast pier face courses",c,belt,belt,lo,lo+.178)
            stripe=shifted(bevel_footprint(.102,.209,.026),u,v)
            prism(m,"Stacked pier plinth course","Stained pier base",stripe,stripe,-.408,-.329)


def main():
    common.PREFIX=PREFIX
    common.COLORS=COLORS
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    bpy.context.scene.name="LuanTTD | Pigmented cast concrete road bridge"
    mats=common.materials()
    model={}
    for kind,head,ground in (("span",False,lambda v:.5),
                              ("head_flat",True,lambda v:.5),
                              ("head_ramp",True,lambda v:.5+(v-1)/2)):
        m=common.Mesh()
        deck(m,ground,head)
        parapet(m,ground,head)
        if head:
            abutment(m,ground)
        else:
            cap(m)
        for key,d in (enumerate(range(4)) if head else ((0,2),(1,1))):
            model[f"{kind}_{key}"]=m.oriented(d)
    m=common.Mesh()
    pier(m)
    for axis,d in ((0,2),(1,1)):
        model[f"pier_{axis}"]=m.oriented(d)
    parts={}
    for name,shape in model.items():
        common.export(name,shape)
        parts[name]=common.author(shape,name,mats)
    common.atlas()
    common.showcase(parts)
    scene=bpy.context.scene
    # The concrete catalogue limits the span to two middle tiles. Trim the
    # common scene's longer wooden showcase without changing asset geometry.
    for ob in list(scene.objects):
        if ob.instance_type=="COLLECTION":
            if abs(ob.location.x)<.01:
                bpy.data.objects.remove(ob,do_unlink=True)
            else:
                ob.location.x+=-1 if ob.location.x>0 else 1
        elif ob.name=="Upper bank":
            ob.location.x-=1
        elif ob.name=="Lower bank":
            ob.location.x+=1
    scene.camera.data.ortho_scale=11.3
    scene.display.shading.studio_light="paint.sl"
    scene.display.shading.cavity_ridge_factor=1.43
    scene.display.shading.cavity_valley_factor=.82
    bpy.ops.wm.save_as_mainfile(filepath=str(common.ROOT/"art"/"road_bridge_concrete.blend"),compress=True)
    if out:=os.getenv("CONCRETE_BRIDGE_RENDER"):
        scene.render.filepath=out
        bpy.ops.render.render(write_still=True)


if __name__=="__main__":
    main()

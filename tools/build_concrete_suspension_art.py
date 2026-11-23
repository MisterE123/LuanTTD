"""Original reinforced-concrete suspension kit for RC1 stock bridge #3."""
from math import sin, cos, pi
from pathlib import Path
from sys import path

path.insert(0,str(Path(__file__).resolve().parent))
import build_fast_girder_art as base
from build_bridge_clearance_meshes import clear_span
from build_bridge_pier_feet import write_feet

kit,rail,geo,bpy=base.kit,base.rail,base.geometry,base.bpy
COLORS={**base.COLORS,"Concrete pearl":"aaa89b","Concrete satin":"b3b2a6",
  "Concrete deep":"737873","Cable metal":"4e5351","Cable highlight":"74796e",
  "Girder shadow":"76766b","Deck trim":"93968a","Rusted washer":"886552",
  "Brace collar":"8e9081","Cast bearing":"858d84"}
PIECES={"plus":(1,),"minus":(-1,),"double":(-1,1),"clear":()}
BEARING={"Suspension_support_skirt","Suspension_bearing_ledge"}


def height(lead,trail,v):
    t=(v+1)/2
    # At model boundaries the cable meets the transferable cast saddle or
    # the slack cable on the adjoining section. Use the same end tangent.
    smooth=t*t*(3-2*t)
    return lead+(trail-lead)*smooth-.132*sin(pi*t)**2


def pipe(m,name,u,points,r):
    def ring(v,h):
        return [(u+r*cos(2*pi*i/6),v,h+r*sin(2*pi*i/6)) for i in range(6)]
    for p,q in zip(points,points[1:]):
        a,b=ring(*p),ring(*q)
        for i in range(6):
            j=(i+1)%6
            col="Cable highlight" if i in (0,1) else "Cable metal"
            m.poly(name,col,a[i],b[i],b[j],a[j])


def block(m,group,col,cx,v0,v1,width,y0,y1):
    m.box(group,col,cx-width/2,cx+width/2,v0,v1,y0,y1,end_faces=False)


def towers(m,ends):
    for end in ends:
        a,b=sorted((end*.83,float(end)))
        for u in (-.445,.445):
            cap,neck=sorted((end*.782,float(end)))
            block(m,"Buttressed half-tower","Concrete pearl",u,a,b,.177,.255,1.405)
            block(m,"Struck formwork outer chamfer","Concrete satin",u,cap,neck,.135,.328,1.414)
            block(m,"Saddle sleeve","Concrete deep",u,cap,neck,.204,1.380,1.443)
            block(m,"Cast saddle roof","Concrete satin",u,cap,neck,.230,1.443,1.476)
            block(m,"Suspension support skirt","Cast bearing",u,a,b,.177,-.5,.250)
            block(m,"Suspension bearing ledge","Girder shadow",u,a,b,.208,.035,.228)
        block(m,"Pier bridge portal bar","Concrete pearl",0,cap,neck,.959,1.223,1.388)
        block(m,"Horizontal cast band","Concrete satin",0,cap,neck,.964,1.264,1.296)


def roadway(m,h,mode,head):
    if mode=="road": kit.running_surface(m,h)
    else: rail.full_track(m,h,"full" if head else None,guards="head" if head else "span")
    w=.50 if mode=="road" else .54
    for lo,hi,extra,group,color in ((-.22,-.02,0,"Concrete deck diaphragm","Concrete pearl"),
           (-.215,-.176,.013,"Cast fascia band","Concrete deep"),
           (-.047,-.008,.012,"Cast coping","Concrete satin")):
        m.box(group,color,-w-extra,w+extra,-1,1,lambda v,k=lo:h(v)+k,lambda v,k=hi:h(v)+k,
              end_faces=False,face_colors={"under":"Girder shadow"})
    for sg in (-1,1):
        mid=sg*.455
        v0=-.79 if head else -1.
        m.box("Low precast safety railing","Concrete satin",mid-.027,mid+.027,v0,1,
              lambda v:h(v)+.099,lambda v:h(v)+.132,end_faces=False)
        for v in (-.69,-.31,.07,.45,.83):
            m.box("Clear baluster slots","Concrete pearl",mid-.036,mid+.036,v-.023,v+.023,
                  lambda q:h(q)+.012,lambda q:h(q)+.143)
        for v in (-.40,.36):
            m.box("Formwork scarf seam","Deck trim",
                  *sorted((sg*(w+.013),sg*(w+.018))),v-.006,v+.008,
                  lambda q:h(q)-.177,lambda q:h(q)-.054)


def suspension(mode,ends):
    m=kit.Mesh()
    roadway(m,lambda v:.5,mode,False)
    towers(m,ends)
    n,s=1.451 if -1 in ends else .835,1.451 if 1 in ends else .835
    for sign in (-1,1):
        u=sign*.445
        segments=[-1+i/12 for i in range(25)]
        pipe(m,"Catenary cable",u,[(v,height(n,s,v)) for v in segments],.015)
        for v in (-.72,-.41,-.11,.18,.48,.76):
            y=height(n,s,v)
            m.box("Steel hanger","Cable metal",u-.006,u+.006,v-.006,v+.006,.636,y)
            m.box("Threaded hanger anchor","Rusted washer",u-.018,u+.018,v-.017,v+.017,.615,.655)
    return m


def head_mesh(mode,flat):
    m=kit.Mesh()
    h=(lambda v:.5) if flat else (lambda v:v/2)
    if flat and mode=="rail": rail.descending_land(m)
    roadway(m,h,mode,True)
    for u in (-.445,.445):
        block(m,"Land cable anchorage","Concrete pearl",u,.53,.99,.172,.282,.719)
        block(m,"Bolted cable end block","Concrete satin",u,.63,.97,.145,.703,.822)
        pipe(m,"Short approach cable",u,[(.77,.790),(.88,.808),(1,.835)],.015)
        block(m,"Land approach wing wall","Concrete deep",u,-.48,.52,.16,h(-.45)-.40,h(-.45)-.13)
    return m


def pier_mesh(ends):
    m=kit.Mesh()
    for end in ends:
        a,b=sorted((end*.83,float(end)))
        for u in (-.445,.445):
            block(m,"Concrete suspension core","Cast bearing",u,a,b,.177,-.5,.5)
            block(m,"Lift seam","Brace collar",u,a,b,.189,-.153,-.126)
    return m


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    bpy.context.scene.name="LuanTTD | Concrete suspension, high and low stock segments"
    kit.COLORS=COLORS
    mats=kit.materials()
    showcase={}
    for mode in ("road","rail"):
        stem=f"{mode}_bridge_suspension_concrete"
        kit.PREFIX="bl_"+stem
        parts={}
        for name in ("head_flat","head_ramp"):
            m=head_mesh(mode,name=="head_flat")
            for d in range(4): parts[f"{name}_{d}"]=m.oriented(d)
        for key,ends in PIECES.items():
            m=suspension(mode,ends)
            p=pier_mesh(ends)
            for axis,d in ((0,2),(1,1)):
                parts[f"span_{axis}_{key}"]=m.oriented(d)
                if ends: parts[f"pier_{axis}_{key}"]=p.oriented(d)
        kit.atlas()
        for name,shape in parts.items():
            kit.export(name,shape)
            coll=kit.author(shape,mode.capitalize()+" "+name,mats)
            if mode=="road": showcase[name]=coll
        for key,ends in PIECES.items():
            if not ends: continue
            for axis in (0,1):
                span=kit.MODELS/f"{kit.PREFIX}_span_{axis}_{key}.obj"
                span.with_name(span.stem+"_road_clear.obj").write_text(clear_span(span,BEARING))
                # The generic foot maker accepts axis followed by the suffix;
                # use the original course by passing a distinct pier basename.
                for depth in (1,2,"water"):
                    write_feet(stem,"Concrete_suspension_core",axis,depth,variant=key)
    kit.showcase({"head_ramp_2":showcase["head_ramp_2"],"head_flat_0":showcase["head_flat_0"],
      "span_0":showcase["span_0_plus"],"pier_0":showcase["pier_0_plus"]})
    # The exact length-three stock composition is plus, double, minus.
    for ob in list(bpy.context.scene.objects):
        if ob.instance_type!="COLLECTION": continue
        if "_plus" not in ob.instance_collection.name: continue
        wanted="minus" if ob.location.x>0 else "double" if ob.location.x==0 else "plus"
        key=("span" if "span" in ob.instance_collection.name else "pier")+"_0_"+wanted
        ob.instance_collection=showcase[key]
    bpy.ops.wm.save_as_mainfile(filepath=str(kit.ROOT/"art"/"concrete_suspension.blend"),compress=True)


if __name__=="__main__":
    main()

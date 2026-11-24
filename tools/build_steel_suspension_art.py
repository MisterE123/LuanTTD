"""Original lattice steel deck and towers for OpenTTD RC1 stocks #4/#5."""
from pathlib import Path
from sys import path
path.insert(0,str(Path(__file__).resolve().parent))
import build_concrete_suspension_art as family

kit, rail, geometry = family.kit, family.rail, family.geo
COLORS={**family.COLORS, "Rolled angle":"5f6560","Angle flange":"7c8073",
  "Painted plate":"68675d","Riveted gusset":"58594d","Bridge guard":"7a7e71",
  "Bearing steel":"515750","Zinc fastener":"92947d","Cast jacket":"838174"}
YELLOW={**COLORS, "Rolled angle":"bc8b39","Angle flange":"d5aa55",
  "Painted plate":"b18a41","Riveted gusset":"926837","Bridge guard":"d5aa55",
  "Bearing steel":"737060","Zinc fastener":"8d8775"}
PARTS={"Steel_lattice_column_base","Cast_web_seat"}


def member(m,group,a,b,w,depth,color="Rolled angle"):
    A,B=kit.Vector(a),kit.Vector(b)
    direction=(B-A).normalized()
    axis=kit.Vector((0,1,0)) if abs(direction.y)<.85 else kit.Vector((1,0,0))
    along=direction.cross(axis).normalized()
    across=along.cross(direction).normalized()
    shape=[along*(sx*w/2)+across*(sy*depth/2) for sx,sy in ((-1,-1),(1,-1),(1,1),(-1,1))]
    begin=[tuple(A+v) for v in shape];end=[tuple(B+v) for v in shape]
    for i in range(4):
        j=(i+1)%4
        m.poly(group,"Angle flange" if i==1 else color,begin[i],begin[j],end[j],end[i])
    m.poly(group,color,*begin[::-1]);m.poly(group,color,*end)


def deck(m,h,mode,head):
    if mode=="road": kit.running_surface(m,h)
    else: rail.full_track(m,h,"full" if head else None,guards="head" if head else "span")
    width=.49 if mode=="road" else .54
    m.box("Riveted slab diaphragms","Concrete deep",-width,width,-1,1,
          lambda v:h(v)-.092,lambda v:h(v)-.007,end_faces=False)
    for side in (-1,1):
        u=side*(width-.043)
        m.box("Continuous steel deck joists","Painted plate",u-.036,u+.036,-1,1,
              lambda v:h(v)-.215,lambda v:h(v)-.085,end_faces=False)
        for y in (-.224,-.099):
            m.box("Double rolled flange","Angle flange",u-.059,u+.059,-1,1,
                  lambda v,k=y:h(v)+k,lambda v,k=y:h(v)+k+.018,end_faces=False)
        for v in (-.69,-.268,.154,.576):
            m.box("Riveted flange stiffener","Riveted gusset",u-.041,u+.041,v-.032,v+.024,
                  lambda q:h(q)-.207,lambda q:h(q)-.099)
        v0=-.78 if head else -1.
        for lo in (.071,.167):
            m.box("Bridge angle guardbar","Bridge guard",u-.019,u+.019,v0,1,
                  lambda v,k=lo:h(v)+k,lambda v,k=lo:h(v)+k+.024,end_faces=False)
        for v in (-.68,-.345,-.01,.325,.66):
            m.box("Bolted guard stanchion","Rolled angle",u-.022,u+.022,v-.018,v+.018,
                  lambda q:h(q)+.004,lambda q:h(q)+.196)
    if not head:
        for v in (-.73,.73):
            m.box("Steel transverse tie","Bearing steel",-width,width,v-.042,v+.042,.283,.414)


def towers(m,ends):
    for end in ends:
        begin,finish=sorted((end*.775,float(end)))
        inner=end*.836
        for side in (-1,1):
            u=side*.464
            for delta in (-.045,.045):
                m.box("Portal riveted vertical chords","Rolled angle",u+delta-.023,u+delta+.023,begin,finish,
                      .317,1.454,end_faces=False)
                m.box("Steel lattice column base","Bearing steel",u+delta-.023,u+delta+.023,begin,finish,
                      -.5,.317,end_faces=False)
            for a in (.378,.694,1.01):
                b=a+.26
                member(m,"Portal open crossing straps",(u-.045,inner,a),(u+.045,inner,b),.029,.024,"Painted plate")
                member(m,"Portal open crossing straps",(u+.045,inner,a),(u-.045,inner,b),.027,.024,"Painted plate")
            m.box("Cast web seat","Cast jacket",u-.106,u+.106,begin,finish,.159,.323,end_faces=False)
            m.box("Cable roller cap","Zinc fastener",u-.094,u+.094,begin,finish,1.413,1.474,end_faces=False)
        for lo,hi in ((1.152,1.194),(1.326,1.378)):
            m.box("Frame portal truss chord","Angle flange",-.47,.47,begin,finish,lo,hi,end_faces=False)
        for i in range(6):
            a=-.465+i*.155;b=a+.155
            member(m,"Open portal truss",(a,inner,1.174 if i%2==0 else 1.348),
                   (b,inner,1.348 if i%2==0 else 1.174),.024,.041)


def pier(ends):
    m=kit.Mesh()
    for end in ends:
        a,b=sorted((end*.775,float(end)))
        for side in (-1,1):
            u=side*.464
            for delta in (-.045,.045):
                m.box("Steel lattice core","Bearing steel",u+delta-.023,u+delta+.023,a,b,-.5,.5,end_faces=False)
            mid=end*.826
            member(m,"Riveted pier bracing",(u-.045,mid,-.415),(u+.045,mid,.415),.024,.024)
            member(m,"Riveted pier bracing",(u+.045,mid,-.415),(u-.045,mid,.415),.024,.024)
    return m


if __name__=="__main__":
    family.build("steel",COLORS,deck,towers,pier,PARTS,"Steel_lattice_core",
                 alternate={"yellow":YELLOW})

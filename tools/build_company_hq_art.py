#!/usr/bin/env python3
"""Author the five original Temperate HQ appearances in native 3D."""
from argparse import ArgumentParser
from math import cos, pi, sin
from pathlib import Path
from PIL import Image, ImageDraw

parser = ArgumentParser(description=__doc__)
parser.add_argument("--check", action="store_true")
check = parser.parse_args().check
root = Path(__file__).resolve().parents[1] / "mods/luanttd_core"
colors = [(91,96,98),(152,153,142),(185,175,148),(205,188,155),(113,118,126),
          (113,70,52),(146,91,68),(178,110,81),(240,210,155),(65,65,69),
          (38,67,78),(54,93,107),(103,145,153),(151,182,182),(35,55,61),
          (105,123,77),(143,156,101),(59,84,61),(75,108,68),(104,137,79),
          (85,66,48),(218,194,125),(45,90,115),(88,137,154)]
def output(path,data):
    if check: assert path.read_text()==data,path
    else: path.write_text(data)
def png(path,image):
    if check: assert Image.open(path).convert(image.mode).tobytes()==image.tobytes(),path
    else: image.save(path,optimize=True)
pal=Image.new("RGB",(8*len(colors),8))
for i,c in enumerate(colors): pal.paste(c,(i*8,0,(i+1)*8,8))
png(root/"textures/bl_stock_company_hq.png",pal)
icon=Image.new("RGBA",(192,192));d=ImageDraw.Draw(icon)
def poly(pts,color): d.polygon([(4*x,4*y) for x,y in pts],fill=color)
poly([(3,34),(24,24),(45,33),(24,45)],"#8e927f")
poly([(8,30),(8,16),(23,10),(23,37)],"#518494")
poly([(23,10),(37,17),(37,31),(23,37)],"#224e61")
poly([(8,16),(23,10),(37,17),(23,23)],"#a1cbd1")
poly([(13,13),(13,8),(21,5),(21,17)],"#6699aa")
poly([(21,5),(31,9),(31,13),(21,17)],"#356478")
poly([(13,8),(21,5),(31,9),(21,13)],"#c0d2c8")
for y in (20,25,30):
    poly([(10,y),(21,y+4),(21,y+6),(10,y+2)],"#a2c1c1")
png(root/"textures/bl_dispatch_company_hq.png",icon.resize((48,48),Image.Resampling.LANCZOS))

class Mesh:
    def __init__(self):
        self.v=[];self.f=[]
    def pts(self,points):
        k=len(self.v)+1
        self.v.extend((-.5-x,y-.5,.5+z) for x,y,z in points)
        return list(range(k,len(self.v)+1))
    def face(self,ids,c):
        self.f.append("f "+" ".join(f"{n}/{c+1}" for n in ids))
    def box(self,x0,z0,x1,z1,y0,y1,body,top=None):
        t=self.pts([(x0,y0,z0),(x1,y0,z0),(x1,y0,z1),(x0,y0,z1),
                    (x0,y1,z0),(x1,y1,z0),(x1,y1,z1),(x0,y1,z1)])
        for indices,col in [((0,3,2,1),body),((4,5,6,7),top if top is not None else body),
          ((0,1,5,4),body),((1,2,6,5),body),((2,3,7,6),body),((3,0,4,7),body)]:
            self.face([t[i] for i in indices],col)
    def ring(self,x,z,rows,colors_,n=8):
        ids=[]
        for y,r in rows:
            ids.append(self.pts([(x+r*cos(i*2*pi/n),y,z+r*sin(i*2*pi/n)) for i in range(n)]))
        self.face(ids[0][::-1],colors_[0])
        for row,(a,b) in enumerate(zip(ids,ids[1:])):
            for i in range(n):
                j=(i+1)%n
                self.face((a[i],a[j],b[j],b[i]),colors_[min(row,len(colors_)-1)])
        self.face(ids[-1],colors_[-1])
    def tree(self,x,z,y=0):
        self.ring(x,z,[(y,.04),(y+.42,.025)], [20])
        self.ring(x,z,[(y+.25,.10),(y+.37,.24),(y+.54,.17),(y+.74,0.005)],[17,18,19],7)
    def facade(self,x0,z0,x1,z1,y0,y1,windows,wall,glass,trim):
        self.box(x0,z0,x1,z1,y0,y1,wall,trim)
        n=windows
        for k in range(n):
            y=y0+.22+k*(y1-y0-.29)/n
            h=min(.40,(y1-y0-.24)/n*.68)
            for j in range(3):
                x=x0+(j+.2)*(x1-x0)/3
                w=(x1-x0)*.19
                for zz in (z0-.014,z1-.005):
                    self.box(x,zz,x+w,zz+.02,y,y+h,glass,12)
                z=z0+(j+.2)*(z1-z0)/3
                for xx in (x0-.012,x1-.005):
                    self.box(xx,z,xx+.019,z+(z1-z0)*.19,y,y+h,glass,13)
            self.box(x0-.024,z0-.024,x1+.024,z1+.024,y-.055,y-.032,trim)
        self.box(x0-.045,z0-.045,x1+.045,z1+.045,y1,y1+.052,trim,4)
    def roof(self,x0,z0,x1,z1,base,rise,col):
        mid=(z0+z1)*.5
        j=self.pts([(x0,base,z0),(x1,base,z0),(x1,base,z1),(x0,base,z1),(x0,base+rise,mid),(x1,base+rise,mid)])
        for ix,c in [((0,1,5,4),col),((4,5,2,3),col),((0,4,3),3),((1,2,5),3)]:
            self.face([j[i] for i in ix],c)
    def write(self,path):
        output(path,"# Original Luanti Company HQ architecture\n"+
               "".join(f"vt {(i+.5)/len(colors):.6f} .5\n" for i in range(len(colors)))+
               "".join("v %.5f %.5f %.5f\n"%v for v in self.v)+"\n".join(self.f)+"\n")

for stage in range(5):
    for part in range(1,5):
        m=Mesh()
        m.box(-.5,-.5,1.5,1.5,-.045,.02,0,1)
        m.box(-.44,-.44,1.44,1.44,.02,.046,1,2)
        if part==4: # stock open south quadrant: entrances and paved approach
            m.box(-.37,-.37,1.37,1.37,.046,.064,1,0)
            for x in (-.21,.06,.33,.60,.87,1.14):
                m.box(x,-.25,x+.03,.21,.064,.071,21)
            m.box(.44,.42,1.27,1.25,.06,.13,2,15)
            for x,z in [(.56,.70),(1.08,1.06)]:m.tree(x,z,.13)
            if stage>=2:
                m.ring(.10,.90,[(.06,.29),(.12,.31),(.18,.28)],[2,1])
                m.ring(.10,.90,[(.18,.26),(.20,.26)],[22,23])
                m.ring(.10,.90,[(.20,.05),(.45,.06),(.49,.01)],[3,12])
        elif stage==0:
            if part==1:
                m.facade(-.22,-.15,1.13,1.00,.05,.73,1,3,22,2)
                m.roof(-.30,-.23,1.22,1.09,.75,.23,6)
                m.box(.54,-.186,.79,-.12,.05,.49,5)
                m.box(.89,.26,1.01,.43,.71,1.02,7)
            else:
                m.box(-.22,-.24,1.25,.85,.04,.067,2,15)
                for x,z in [(0,0),(.93,.58)]:m.tree(x,z,.06)
                m.box(-.25,1.00,1.31,1.33,.04,.095,1,3)
                m.box(.12,1.08,.72,1.26,.15,.20,20)
        elif stage<=2:
            modern=stage==2
            floors=3 if modern else 2
            top=2.01 if modern else 1.33
            # Compound body across the north/west/east rooms; recessed glass
            # and smaller service wings distinguish the 3 original quadrants.
            r={1:(-.38,-.38,1.37,1.36),2:(-.36,-.22,1.37,1.25),3:(-.22,-.37,1.25,1.37)}[part]
            m.facade(*r,.045,top if part==1 else top-.23,floors,3 if modern else 6,22,2 if modern else 8)
            if modern:
                m.box(.01,.08,.80,.82,top-.16,top+.19,4,0)
                m.box(.15,.23,.50,.54,top+.19,top+.25,0,4)
            else:
                m.roof(r[0]-.07,r[1]-.07,r[2]+.07,r[3]+.07,top if part==1 else top-.23,.32,9)
            if part==2: m.box(.22,-.34,.84,-.20,.06,.54,9,3)
        else:
            # Large tower and setback glass spire. Divide material bands
            # by corresponding physical quadrants rather than using billboards.
            top=(3.4 if stage==3 else 4.5) if part==1 else (2.4 if stage==3 else 2.85)
            m.facade(-.43,-.43,1.41,1.41,.046,min(top,2.3),4,4,10,2)
            if top>2.3:
                m.facade(-.27,-.26,1.22,1.20,2.28,top,3 if part==1 else 1,10,12,4)
            if part==1:
                m.box(.04,.02,.97,.92,top,top+.20,10,13)
                m.ring(.53,.50,[(top+.16,.027),(top+.59,.018),(top+.75,.01)],[9],6)
            if part==3:
                m.box(.14,.77,.95,.97,top,top+.075,13,21)
        m.write(root/"models"/f"bl_stock_company_hq_{stage}_{part}.obj")
print("PASS 20 original stock Company HQ quarters, across all five phases")

#!/usr/bin/env python3
"""Original OpenTTD 16.0-RC1 #147/#148/#149 closed steel tippers and independent iron-ore covers."""
from copy import deepcopy
from dataclasses import dataclass
from math import sin,cos,pi,tau
from pathlib import Path
from random import Random
import os,sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,os.getenv("LUANTTD_HELPERS",str(ROOT/"tools")))
import build_stock_road_fleet_d_art as D
from build_chaney_jubilee_art import geometry
road,w,r,bpy,V=D.road,D.w,D.r,D.bpy,D.V
B,C,rod=road.B,road.C,road.rod

@dataclass(frozen=True)
class Truck:
    number:int; name:str; maker:str; day:int; row:int; image:int; capacity:int; sprite:int
    tones:tuple; axles:tuple; wheels:float; radius:float
    cabinet:tuple; cabin_side:tuple; nose:float; bed:tuple; lumps:tuple
    @property
    def stem(self):return f"stock_{self.maker}_iron_ore_truck"
    @property
    def rear(self):return self.bed[1]

mps=Truck(147,"MPS Iron Ore Truck","mps",5479,31,8,22,3364,
 ("466c7b","35505e","5d8490","a1a799","31414a","b8b9a5","7996a0","36434b","d0bf96",
  "52717d","759099","475a62","5c5c54","9aa5a0","5d747a"),
 (-.536,.425),.220,.129,
 ((-.583,.198,.535,.231),(-.551,.228,.606,.218),(-.481,.242,.639,.219),(-.377,.244,.637,.215),
  (-.273,.239,.623,.218),(-.230,.213,.582,.228)),
 (-.430,.239,.417,.539),-.583,(-.192,.736,.234,.493,.295,6,.087),(6,13))
uhl=Truck(148,"Uhl Iron Ore Truck","uhl",20820,32,25,25,3172,
 ("4a718f","38546d","6989a0","aeb3ad","384b62","acbdc7","769fb4","333f53","c9bf9e",
  "466b83","7390a5","374e62","595d5b","a4afa8","537381"),
 (-.528,.437),.224,.133,
 ((-.755,.236,.560,.211),(-.727,.255,.622,.207),(-.639,.261,.642,.205),(-.345,.261,.642,.207),
  (-.276,.251,.624,.211),(-.220,.221,.581,.220)),
 (-.489,.258,.409,.550),-.743,(-.179,.752,.247,.523,.295,8,.069),(7,14))
chippy=Truck(149,"Chippy Iron Ore Truck","chippy",33238,33,42,27,3556,
 ("586a8e","3f4b68","7487a6","8e9ab2","353f57","a9b2c2","667fa4","363d59","b8c8cb",
  "425f82","68849c","344a67","555c64","92a9bc","4b6a88"),
 (-.533,.329,.584),.222,.124,
 ((-.786,.162,.410,.192),(-.772,.209,.484,.193),(-.738,.244,.540,.199),(-.695,.258,.597,.198),
  (-.619,.264,.657,.203),(-.557,.265,.671,.205),(-.286,.264,.670,.203),(-.202,.230,.630,.215)),
 (-.431,.258,.395,.548),-.780,(-.154,.769,.253,.548,.288,10,.059),(8,15))
FLEET=(mps,uhl,chippy)
SWATCHES=("Cab main","Cab shade","Cab shoulder","Cab peak","Cab recess","Cab trim","Hood highlight","Front grille","Overpaint band",
          "Load skin","Load bevel","Load shadow","Load pan","Load silvery rim","Load steel fold")
ORE={"Iron dense hematite":"743f32","Iron oxide terracotta":"9c5239","Iron fractured branch brown":"854936",
     "Iron cold glint":"ad6b4d","Iron muted dust and earth":"825841","Iron underlayer sienna":"673e35",
     "Iron rust surface flare":"a85d43","Iron black seam":"50403b","Grimy cylinder":"526167",
     "Steel piston":"a4b1ad","Gate keeper":"596761","Dry mud ochre":"795744",
     "Pressed gunmetal":"5d6767","Gold strip":"bda26c"}
ORE_FACE=tuple(ORE)[:8]

def setup(t):
    pal=D.G|dict(zip(SWATCHES,t.tones))|ORE
    while len(pal)<64:pal[f"Neutral {len(pal)}"]="747c76"
    assert len(pal)==64
    w.P=road.P={k:i for i,k in enumerate(pal)}
    r.COLORS[:]=pal.values()
    return pal

def mesh():return r.Mesh(r.terrain_height(0))
def face(m,n,c,p):road.f(m,n,c,p)

def chassis(m,t):
    f,rr,*rx=t.axles;rad=t.radius
    road.wheels(m,f,rr,t.wheels,rad,"Cab trim",True,tuple(rx))
    for s in (-1,1):
        B(m,"Separate formed crossbraced longitudinal load chassis", "Frame",s*.134,.014,.061,1.454,.136,.212,.009)
        B(m,"Reinforced low separate rippled support flange","Axle grey",s*.151,.038,.061,1.395,.145,.169,.006)
        for z in t.axles:
            road.fender(m,"Each louvered separate rolled heavy wheel guard",s*.235,z,rad,rad+.025,.099,"Cab shade")
            for j in range(3):
                B(m,"Spring stack for each correctly separate axle","Floor underbody",s*.139,z,.049,
                 .225-.017*j,.138+.011*j,.149+.011*j,.003)
        for z in [rr,*rx]:
            B(m,"Real flexible muck flap behind heavy ore load tyres","Deep rubber",s*.223,z+rad+.010,.136,
              .014,.040,.194,.003)
        for x,y in ((s*.237,-.253),(s*.238,-.302)):
            B(m,"Two independent anti-slip steps","Floor underbody",x,y,.107,.069,.144,.174,.006)
        for j in range(4):
            B(m,"Raised cold-forged step tread ribs","Deep rubber",s*.258,-.327+j*.024,.064,.006,
              .173,.180,.0016)
        for yo in (-.122,.338,.635):
            C(m,"Frame cross through-bolts and bush pins","Nickel",(s*.158,yo,.181),.007,"x",
              -.004,.007,8)
    for z in (-.639,-.219,.014,.359,.684):
        B(m,"Genuine welded crossed frame bulkhead","Frame",0,z,.342,.047,.149,.211,.011)
    B(m,"Exposed single under-chassis fuel tank","Nurled iron",.159,.105,.137,.279,.092,.194,.018)
    C(m,"Closed centered axle differential","Floor underbody",(0,rr,.119),.039,"x",-.066,.066,13)
    rod(m,"Enclosed two-section drive shaft under ore bed","Axle grey",(0,-.389,.089),(0,rr,.124),.017)

def pane_roof(m,t):
    def point(s,f,z,lift):
        for a,b in zip(t.cabinet,t.cabinet[1:]):
            if a[0]<=z<=b[0]:
                u=(z-a[0])/(b[0]-a[0])
                w,h=(a[i]+(b[i]-a[i])*u for i in (1,2))
                return s*w*f,z,h+lift-max(0,f-.73)*.145
        raise ValueError(z)
    for side in (-1,1):
        for n,c,z0,z1,fm,lift in (
          ("Sculpted steep front dark wide windscreen trim","Glass rim",-.769,-.637,.86,.007),
          ("Angled Chippy wide convex original separate windscreen","Glass",-.760,-.649,.80,.012),
          ("Low soft streak reflection in upper aerodynamic windscreen","Glass glint",-.669,-.653,.72,.016)):
            zs=[z0]+[z for z,*_ in t.cabinet if z0<z<z1]+[z1]
            xs=(.035,.259,.511,fm)
            for a,b in zip(zs,zs[1:]):
                for p,q in zip(xs,xs[1:]):
                    face(m,n,c,(point(side,p,a,lift),point(side,q,a,lift),point(side,q,b,lift),point(side,p,b,lift))[::side])
        rod(m,"Genuine angled arm against slanted screen",
            "Glass rim",point(side,.19,-.744,.018),point(side,.58,-.708,.019),.0036)

def cab(m,t):
    D.cab_shape(m,t.cabinet)
    D.side_cab(m,*t.cabin_side)
    if t.number==147:
        # Slim pre-war/early post-war conventional hood with two separate
        # flowing wings and exposed vertical radiator.
        z0=-.782
        rows=[
          (z0,[(-.118,.225),(.118,.225),(.118,.385),(.094,.420),(-.094,.420),(-.118,.385)]),
          (z0+.026,[(-.123,.219),(.123,.219),(.123,.394),(.099,.429),(-.099,.429),(-.123,.394)]),
          (-.575,[(-.152,.213),(.152,.213),(.152,.390),(.126,.429),(-.126,.429),(-.152,.390)])]
        road.section_hull(m,"Independent rounded conventional MPS engine bonnet and folded rails",rows,
                          ["Cab shade","Cab main","Hood highlight","Hood highlight","Hood highlight","Cab main"],"Cab shoulder")
        B(m,"Early inset vertical radiator casing with satin surround","Cab trim",0,z0-.006,.233,.018,.235,.410,.009)
        B(m,"Dark actual radiator opening","Front grille",0,z0-.018,.196,.011,.252,.397,.006)
        for i in range(-4,5):
            B(m,"Pressed rounded vertical old-fashioned radiator wing blade","Cold roller wear",i*.020,z0-.025,.005,.007,.254,.394,.002)
        for s in (-1,1):
            for i in range(5):
                B(m,"Ribbed stamped MPS hood side vent fingers","Front grille",s*.137,-.718+i*.018,.011,.007,.297,.351,.0018)
            B(m,"Bulb fender frontal splash apron ahead of wheel","Cab main",s*.202,-.663,.128,.133,.185,.276,.014)
        D.face_panes(m,-.598,.423,.546,.175)
        D.front_bumper(m,-.777,.486,"round")
        B(m,"Separate modest silver split line on original hood","Cab trim",0,-.695,.012,.147,.419,.431,.003)
    elif t.number==148:
        D.face_panes(m,-.760,.418,.572,.207)
        D.front_bumper(m,-.759,.508,"square")
        B(m,"Uhl two-piece coarse face inlet stamped surround","Cab trim",0,-.764,.420,.017,.294,.362,.005)
        B(m,"Uhl black broad low cooling aperture","Front grille",0,-.778,.394,.011,.301,.354,.004)
        for z in (.310,.329,.347):
            B(m,"Uhl genuine raised broad radiator stiffeners","Cab shoulder",0,-.786,.372,.008,z-.002,z+.002,.0014)
        B(m,"Separate rectangular Uhl cab frontal pale band","Overpaint band",0,-.763,.461,.023,.367,.395,.005)
    else:
        pane_roof(m,t)
        D.front_bumper(m,-.764,.486,"square")
        B(m,"Wide molded Chippy lower frontal mouth with divided intakes","Front grille",0,-.782,.279,.023,.264,.360,.009)
        for col,lo,hi,zz in (("Cab trim",.272,.279,-.797),("Cab shoulder",.301,.306,-.796),("Cab trim",.344,.349,-.794)):
            B(m,"Independent angled satin band across continuous Chippy grille",col,0,zz,.254,.012,lo,hi,.002)
        for s in (-1,1):
            B(m,"Raised shaped bumper air guide under headlamp","Cab shade",s*.197,-.769,.084,.030,.188,.233,.007)
            for i in range(3):
                B(m,"Visible late diesel front bumper airflow louvers","Glass rim",s*.196,-.795,.080,.010,.203+i*.006,.205+i*.006,.001)
        B(m,"Sleek modern integrated low rooftop intake panel","Cab recess",0,-.307,.145,.128,.652,.671,.010)
    D.tail_lighting(m,t.rear+.008)

def open_hopper(m,t):
    a,b,x,top,low,n,width=t.bed
    # Physical tapered closed shell loop (open working volume, sealed thickness).
    # 1950s folded side, later progressively taller walls, bracing more granular.
    cham=.027 if t.number!=149 else .047
    rsection=D.rim_section
    rings=(
      rsection(x-.060,a+.029,b-.027,cham,.239),
      rsection(x-.040,a+.015,b-.012,cham,.276),
      rsection(x-.009,a,b-.004,cham,top-.022),
      rsection(x,a-.004,b+.005,cham,top),
      rsection(x-.024,a+.019,b-.022,cham-.004,top),
      rsection(x-.059,a+.040,b-.035,cham-.003,low),
    )
    tag="Watertight reinforced open tipped iron ore hopper with actual steel thickness"
    face(m,tag,"Load shadow",rings[0][::-1])
    for c,p,q in zip(("Load shadow","Load skin","Load bevel","Load silvery rim","Load steel fold"),rings,rings[1:]):
        for i,j in enumerate(range(1,9)):
            j%=8
            face(m,tag,c,(p[i],p[j],q[j],q[i]))
    face(m,tag,"Load pan",rings[-1])
    for s in (-1,1):
        for idx in range(n):
            z=a+.040+(b-a-.098)*idx/(n-1)
            if t.number==147:
                rod(m,"Wide early structural open ore bed hot-rolled stamped ribs","Load bevel",
                  (s*(x-.037),z,.290),(s*(x+.003),z,top-.045),.0143)
                B(m,"Early lower steel rib relief shoe","Load shadow",s*(x-.039),z,.013,width*.48,.278,.310,.002)
            else:
                h0=.307 if t.number==149 else .300
                shape=((s*(x-.036),z+.014,h0),(s*(x-.015),z+.011,.365),
                       (s*(x+.003),z-.002,top-.045))
                for u,v in zip(shape,shape[1:]):
                    rod(m,"Independent high strength swept cold formed ore tipper rib","Load bevel",u,v,.0109 if t.number==149 else .0127)
                B(m,"Original staked upper strength lip and guide tube bracket","Cold roller wear",
                  s*(x+.008),z,.013,width*.40,top-.059,top-.036,.003)
        for h in ((top-.012,) if t.number!=149 else (top-.012,.368)):
            rod(m,"Knobbed long exterior bed folded reinforcing beam","Load silvery rim",
                 (s*(x+.001),a+.031,h),(s*(x+.001),b-.030,h),.0068)
        # Tiny practical dust-lined lower abrasion panel.
        rod(m,"Bilateral boxed hydraulic tipper guide socket","Grimy cylinder",
          (s*.151,a+.037,.171),(s*(x-.070),a+.361,.258),.013)
        B(m,"Bolt pillow at rear real tipper trunnion","Load shadow",s*.166,b-.082,.067,.091,.187,.279,.009)
        C(m,"Pair of transversely pinned rear rocking joints","Steel piston",(s*.174,b-.090,.228),.030,
          "x",-.018,.017,11)
    # Telescopic stainless ram originates at frame, goes under tilted body front.
    rod(m,"Under-bed cylindrical hoist with continuous physical connection","Grimy cylinder",(0,a+.010,.166),(0,a+.250,.224),.026)
    rod(m,"Full actual twin-stage chromium piston cylinder and drive links","Steel piston",(0,a+.202,.209),(0,a+.420,.262),.014)
    B(m,"Closed swing tailgate in its shore load retaining position","Load skin",0,b+.009,x*1.82,.030,.278,top-.011,.012)
    for xx in (-x*.72,0,x*.72):
        C(m,"Physical top hinged retaining gate axle segments","Gate keeper",(xx,b+.024,top-.018),.013,"x",-.032,.032,13)
        B(m,"Stamped ore tailgate strengthening edge","Load shadow",xx,b+.026,.024,.018,.300,top-.034,.006)
    B(m,"Warm lower back plate with side tailgate retention slots","Load bevel",0,b+.031,x*1.65,.015,.297,.340,.005)
    rod(m,"Separate actual safety retaining shaft on ore tailgate","Gate keeper",
        (-x*.23,b+.041,.315),(-x*.65,b+.036,.420),.0089)
    for s in (-1,1):
        B(m,"Pressed rectangular originals reflective tipper markers", "Gold strip",s*x*.660,b+.043,.029,.006,.312,.336,.002)

def cargo(m,t):
    a,b,x,h,low,*_=t.bed
    z0,z1=a+.040,b-.038
    radius=x-.043
    rx=Random(t.number*99647)
    def elevation(x,z):
        p=(z-z0)/(z1-z0)
        return h-.061 + .047*(max(0,1-(x/radius)**2))*max(0,sin(p*pi))**.60 + .0050*cos(tau*p*2+.41)
    nx,nz=12,25
    g=[[(u,z,elevation(u,z)+rx.uniform(-.0048,.0048)) for u in (-radius+2*radius*i/nx for i in range(nx+1))]
       for z in (z0+(z1-z0)*j/nz for j in range(nz+1))]
    q="Closed independent solid crushed iron ore cargo mass below granular top"
    for j,(p,a0) in enumerate(zip(g,g[1:])):
        for i in range(nx):
            face(m,q,rx.choice(ORE_FACE[:7]),(p[i],p[i+1],a0[i+1],a0[i]))
    border=g[0][:-1]+[row[-1] for row in g[:-1]]+g[-1][:0:-1]+[row[0] for row in g[:0:-1]]
    bottom=[(xx*.87,zz,low+.003) for xx,zz,hh in border]
    for i,p in enumerate(border):
        j=(i+1)%len(border)
        face(m,q,"Iron underlayer sienna",(p,bottom[i],bottom[j],border[j]))
        face(m,q,"Iron black seam",(bottom[j],bottom[i],(0,(z0+z1)*.5,low+.003)))
    index=0
    ncol,nrow=t.lumps
    for iz in range(nrow):
        for ix in range(ncol):
            index+=1
            x=radius*1.79*((ix+.52)/ncol-.5)+rx.uniform(-.012,.012)
            z=z0+(z1-z0)*(.031+.938*(iz+.5)/nrow)+rx.uniform(-.011,.011)
            y=elevation(x,z)+rx.uniform(-.005,.006)
            long=rx.uniform(.019,.036)*(1.05 if t.number==149 else 1.)
            rad=rx.uniform(.017,.033)
            ht=rx.uniform(.010,.034)
            n=5+index%3
            a0=rx.random()*tau
            shape=[(cos(a0+i*tau/n)*rad*rx.uniform(.72,1.12),sin(a0+i*tau/n)*long*rx.uniform(.75,1.15)) for i in range(n)]
            lo=[(x+a*.72,z+b*.72,y-.012) for a,b in shape]
            mid=[(x+a,z+b,y+rx.uniform(-.003,.009)) for a,b in shape]
            high=[(x+a*.53+.003,z+b*.55-.002,y+ht+rx.uniform(-.006,.006)) for a,b in shape]
            tag=f"Individual closed hematite and limonite iron ore stone {index:03d}"
            face(m,tag,ORE_FACE[7],lo[::-1])
            for j in range(n):
                k=(j+1)%n
                face(m,tag,ORE_FACE[(j+index)%5+1],(lo[j],lo[k],mid[k],mid[j]))
                face(m,tag,ORE_FACE[(2*j+index)%6],(mid[j],mid[k],high[k],high[j]))
                face(m,tag,ORE_FACE[(j+2*index)%7],(high[j],high[k],(x+.003,z-.002,y+ht+.002)))

def build(t):
    pal=setup(t)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    sc=bpy.context.scene
    sc.name=f"LuanTTD | {t.name} #{t.number}"
    sc["stock"]=f"OpenTTD 16.0-RC1 # {t.number} image {t.image}, sprite {t.sprite}, load adder 48 at {t.capacity//2}/{t.capacity}."
    sc["native"]="Luanti -Z nose / Y=0 literal tyres / visually scale .42. Blender -Y nose and +Z up."
    mats=r.materials()
    for n,mat in zip(pal,mats):mat.name=n
    bod=mesh()
    for title,fn in (("01 • Axles, chassis, suspension and underfloor",chassis),
                     ("02 • Independent pressed cab, glass and trim",cab),
                     ("03 • Reinforced open tipper and retaining tailgate",open_hopper)):
        a=mesh();fn(a,t);geometry(sc,title,a,mats);fn(bod,t)
    material=mesh();cargo(material,t)
    cc=geometry(sc,"04 • Individually formed original iron ore stones and load surface",material,mats)
    full=deepcopy(bod)
    for name,fs in material.parts.items():
        for face0,col in fs:full.tri(name,col,[material.vertices[name][i] for i in face0])
    models=ROOT/"mods/luanttd_core/models"
    text=ROOT/"mods/luanttd_core/textures"
    for tag,m in (("",bod),("_loaded",full)):
        p=models/f"bl_{t.stem}{tag}.obj"
        r.export_obj(p,w.local_obj(m))
        p.write_text(f"# Original LuanTTD {t.name} #{t.number}; tools/build_stock_iron_ore_road_art.py\n"+p.read_text().split("\n",1)[1])
    D.save_atlas(text/f"bl_{t.stem}_atlas.png",pal)
    original=set(sc.objects)
    road.studio(sc)
    first=sc.camera
    poses=[("front",(2.09,-2.64,1.56)),("rear",(2.05,2.72,1.66)),("empty",(2.15,2.62,1.60))]
    cameras=[]
    for tag,p in poses:
        ob=first if not cameras else first.copy()
        if cameras:
            ob.data=first.data.copy();sc.collection.objects.link(ob)
        ob.name=f"{tag.title()} inspection"
        ob.location=p
        ob.rotation_euler=(V((0,0,.324))-ob.location).to_track_quat("-Z","Y").to_euler()
        ob.data.ortho_scale=2.04
        cameras.append((tag,ob))
    set0=bpy.data.collections.new("90 • Review camera and neutral pavement only")
    sc.collection.children.link(set0)
    for obj in set(sc.objects)-original:
        for col in list(obj.users_collection):col.objects.unlink(obj)
        set0.objects.link(obj)
    sc.camera=cameras[0][1]
    sc.view_settings.exposure=.47
    sc.display.shading.studiolight_rotate_z=.39
    sc.render.resolution_x,sc.render.resolution_y=1100,790
    sc.render.resolution_percentage=100
    for scr in bpy.data.screens:
        for ar in scr.areas:
            if ar.type=="VIEW_3D":
                v=ar.spaces.active
                v.shading.color_type="MATERIAL";v.region_3d.view_location=V((0,0,.32))
                v.region_3d.view_distance=2.35;v.region_3d.view_rotation=V((.8,-.8,.62)).to_track_quat("Z","Y")
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art"/f"{t.stem}.blend"),compress=True)
    if review:=os.getenv("IRON_ORE_REVIEW"):
        sc.render.image_settings.file_format="JPEG";sc.render.image_settings.quality=92
        for tag,cam in cameras:
            cc.hide_render=tag=="empty"
            sc.camera=cam
            sc.render.filepath=str(Path(review)/f"{t.stem}-{tag}.jpg")
            bpy.ops.render.render(write_still=True)

if __name__=="__main__":
    which=set(os.getenv("IRON_ORE_ONLY","mps,uhl,chippy").split(","))
    for t in FLEET:
        if t.maker in which:build(t)

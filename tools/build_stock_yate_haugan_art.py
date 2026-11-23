#!/usr/bin/env python3
"""Original RC1 Yate Haugan: slender delta, four intakes and a two-pose drooping nose."""
from math import cos, pi, sin, sqrt, tau
from pathlib import Path
import os
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_stock_darwin_family_art as D

E,art,B,C=D.e,D.art,D.B,D.C
ROOT=D.ROOT
class Haugan(D.Frame):
    @property
    def stem(self):
        return "yate_haugan"

q=Haugan(218,218,"Original fast CTOL Yate Haugan supersonic aircraft",
    ("eeefe7","d1e6e2","3a8a92","23435b","3b7680","a8704b"),
    (1.126,.992,.096,.256,.091,.080),
    (.684,.643,-.757,-.543,-.700,.182,.069,.088),
    (.1,-.68,-.91,.264,.021),(-.373,-.772,.576),
    (.219,.016,-.67,.124,.039,.028),
    (.189,-.234,.048,.058,2,.674,.032),25,True)

PROFILE=(
    (-.996,.007,.277,.010,.008),(-.945,.022,.278,.030,.022),
    (-.850,.045,.274,.050,.040),(-.734,.064,.270,.070,.055),
    (-.594,.083,.265,.081,.070),(-.381,.092,.260,.090,.077),
    (-.096,.096,.257,.091,.081),(.427,.096,.256,.091,.080),
    (.566,.095,.256,.091,.080),(.658,.092,.256,.089,.077),
    (.724,.087,.259,.083,.072),(.780,.079,.265,.074,.064),
    (.834,.070,.268,.062,.055),(.881,.059,.266,.045,.045),
    (.942,.048,.263,.036,.037),(1.005,.036,.260,.028,.027),
    (1.067,.022,.254,.017,.016),(1.109,.008,.249,.007,.007),
    (1.126,.003,.248,.003,.003),
)
def drawn_nose(y):
    # Fit the precise articulated turn by the City service power cabinet.
    # Only the needle ahead of the cockpit is shortened; tire and wing
    # dimensions/cockpit group stay physically identical.
    return .855+(y-.855)*.70 if y>.855 else y

PROFILE=tuple((drawn_nose(y),*section) for y,*section in PROFILE)

def pressure(frame):
    n=52
    angles=[tau*i/n for i in range(n)]
    panel=[]
    for t in angles:
        h=sin(t+pi/n)
        panel.append("Crown ivory" if h>.77 else "Panel ivory" if h>.36 else "Lit blue" if h>.15 else
                     "Dark coastal cobalt" if h>-.03 else "Copper pinstripe" if h>-.12 else
                     "Silver pressure hull" if h>-.65 else "Bellying brushed alloy")
    art.sections("Lofted slim Haugan fuselage with continuous needle radome",
        [(y,[(w*cos(t),h+(a if sin(t)>0 else b)*sin(t)) for t in angles])
           for y,w,h,a,b in PROFILE],"Silver pressure hull",panel)
    def conform(s,y,f,lift):
        d,h,a,b=E.interp(PROFILE,y)
        return (s*(d*sqrt(1-f*f)+lift),y,h+f*(a if f>=0 else b))
    def skin(s,name,ink,y,k,dy,dk,off):
        ps=[conform(s, y+dy*u,k+dk*v,off) for u,v in
            ((-.6,-1),(.6,-1),(1,-.62),(1,.62),(.6,1),(-.6,1),(-1,.62),(-1,-.62))]
        return D.M(name,ps,[tuple(range(len(ps)))[::s]],ink)
    for s in (-1,1):
        for i in range(27):
            y=.522-i*.039
            skin(s,"Independent small framed pressure window","Aluminium bezel",y,.44,.012,.139,.002)
            skin(s,"Inset cabin sight line","Cab glass",y,.44,.0094,.099,.0033)
            skin(s,"Small sky reflection on glazing","Window glint",y-.001,.484,.0049,.022,.0041)
        for y in (.562,-.552):
            skin(s,"Port and starboard full-height door seal","Glazing bezel",y,.035,.017,.660,.0028)
            skin(s,"Rebated pressure door painted surface","Panel ivory",y,.045,.013,.581,.0041)
            skin(s,"Airliner door recessed quarter light","Cab glass",y,.45,.007,.100,.0055)
            skin(s,"Subtle door handle","Silver pressure hull",y-.005,.025,.0042,.022,.0064)
        for y in (.309,-.325):
            skin(s,"Individual belly cargo door","Glazing bezel",y,-.57,.056,.168,.0031)
            skin(s,"Sealed flush cargo door","Silver pressure hull",y,-.57,.052,.134,.0041)
        def glass(name,col,z0,z1,k0,k1,off):
            vs=[]
            for j in range(9):
                f=j/8
                y=z0+(z1-z0)*f
                w,h,a,_=E.interp(PROFILE,y)
                for i in range(7):
                    k=(k0+(k1-k0)*i/6)*(1-.06*f)
                    vs.append((s*w*k,y,h+a*sqrt(1-k*k)+off))
            faces=[(j*7+i,j*7+i+1,(j+1)*7+i+1,(j+1)*7+i)[::s] for j in range(8) for i in range(6)]
            D.M(name,vs,faces,col)
        glass("Seated inclined windshield rubber","Glazing bezel",.685,.843,.08,.94,.0026)
        glass("Distinct thin supersonic windscreen optical band","Cab glass",.696,.832,.14,.88,.0044)
        glass("Grazing upper pilot reflection","Window glint",.750,.767,.17,.62,.0051)
    C("Fuselage radio aerial",(0,.143,.344),(0,.100,.377),.005,.0015,"Wing leading trim",9)

def controls(frame):
    for side in (-1,1):
        # Measured curves are a double-curvature ogive delta, not a swept
        # rectangular stock wing. The center root covers the entire pylon.
        stations=((.051,.649,-.741,.183,.084),(.115,.472,-.746,.187,.078),
            (.182,.274,-.745,.193,.072),(.255,.104,-.732,.202,.063),
            (.348,-.072,-.723,.213,.052),(.447,-.232,-.711,.224,.040),
            (.542,-.382,-.693,.238,.027),(.623,-.487,-.676,.245,.016),
            (.677,-.565,-.658,.250,.007))
        art.foil("Continuous rounded ogive delta with no conventional tailplane",stations,side)
        for x,z,h in ((.256,-.619,.232),(.355,-.616,.245),(.447,-.606,.249),(.522,-.598,.257)):
            C("Segmented delta elevon and hinge seal",(side*x,z,h),(side*(x+.08),z+.011,h+.008),
              .0018,.0015,"Rib inset",6)
        C("Sealed colored wingtip lens",(side*.677,-.592,.251),(side*.677,-.614,.251),.008,.006,
          "Port marker ruby" if side<0 else "Starboard marker mint",10)
    stations=((.013,.245,-.454,-.967),(.035,.299,-.482,-.966),(.037,.356,-.554,-.963),
      (.032,.427,-.618,-.959),(.023,.492,-.686,-.952),(.016,.548,-.752,-.944),(.008,.576,-.791,-.918))
    contour=((0,0),(.14,-.58),(.34,-1),(.64,-.72),(.85,-.35),(1,0),(.85,.35),(.64,.72),(.34,1),(.14,.58))
    N=len(contour)
    vertices=[(u*w,lead+(trailing-lead)*t,h) for w,h,lead,trailing in stations for t,u in contour]
    faces=[tuple(range(N))];inks=["Dark coastal cobalt"]
    for j,c in enumerate(("Dark coastal cobalt","Blue taper","Lit blue","Crown ivory","Panel ivory","Copper pinstripe")):
        for i in range(N):
            k=(i+1)%N;faces.append((j*N+i,j*N+k,(j+1)*N+k,(j+1)*N+i));inks.append(c)
    faces.append(tuple(range((len(stations)-1)*N,len(stations)*N)));inks.append("Panel ivory")
    art.close_mesh("Distinct swept vertical fin and colored rudder",vertices,faces,inks)

def fairings(frame):
    for side in (-1,1):
        for x in (.136,.218):
            x*=side
            # Bicolor rectangular intake cast profiles around a genuinely
            # recessed open throat; no plug printed as a dark square.
            half,hh=.040,.038
            def section(y,a,b,m):
                return [(x-a,y,m-b),(x+a,y,m-b),(x+a,y,m+b),(x-a,y,m+b)]
            rs=(section(.094,half*.88,hh*.85,.151),section(.071,half,hh,.145),
                section(-.51,half*.97,hh*.97,.133),section(-.555,half*.91,hh*.90,.132))
            cave=(section(.096,.033,.024,.152),section(.034,.032,.022,.149),
                  section(-.017,.028,.018,.147))
            V=[v for row in rs+cave for v in row]
            names=("Wing leading trim","Silver pressure hull","Shadowed nacelle steel")
            faces=[];inks=[]
            def section_pair(a,b,c):
                for i in range(4):
                    j=(i+1)%4;faces.append((a*4+i,a*4+j,b*4+j,b*4+i));inks.append(c)
            for i,c in enumerate(names):section_pair(i,i+1,c)
            section_pair(0,4,"Wing leading trim");section_pair(4,5,"Dark intake");section_pair(5,6,"Dark intake")
            faces.append((24,25,26,27));inks.append("Dark intake")
            art.close_mesh("Separately recessed rectangular variable-ramp turbojet intake",V,faces,inks)
            for off in (-.021,.021):
                B("Metallic guide around supersonic diffuser",(x+off,.037,.174),(.006,.064,.006),"Rib inset",.001)
            rings=((-.478,.033,.133,"Shadowed nacelle steel"),(-.532,.034,.131,"Warm burner rivets"),
                   (-.579,.028,.129,"Exhaust patina bronze"),(-.619,.023,.128,"Dark intake"),
                   (-.62,.017,.128,"Warm burner rivets"),(-.59,.014,.128,"Dark intake"),
                   (-.55,.010,.129,"Dark intake"),(-.482,.012,.132,"Dark intake"))
            art.turbojet("Independent converging round nozzle on each of four engines",x,rings,"Exhaust patina bronze")
            B("Low clipped shroud between wing and each real pod",(x,-.252,.188),(.058,.437,.054),"Silver pressure hull",.011)
    C("Pitot probe on pointed supersonic radome",(0,drawn_nose(1.117),.248),(0,drawn_nose(1.165),.250),.0025,.0013,"Wing leading trim",12)
    B("Retractable tail bumper fairing",(0,-.838,.216),(.022,.057,.034),"Shadowed flap",.005)

def make():
    D.pressure=pressure;D.control_surfaces=controls;D.engines=fairings
    original_write=D.write_native
    def exporter(frame,scene,objects,mode,colors):
        # Pointed radome below the pilot's vision on ground. Do not deform
        # the flight mesh, windows, cabin or undercarriage when changing
        # the final 0.28 units. Restore the editable physical loft after export.
        changed=[]
        if mode=="ground":
            for ob in objects:
                if ob.type!="MESH" or not (ob.name.startswith("Lofted slim Haugan") or "Pitot probe" in ob.name):
                    continue
                mat=ob.matrix_world
                inv=mat.inverted()
                for v in ob.data.vertices:
                    world=mat@v.co
                    if world.y>drawn_nose(.880):
                        projected=.855+(world.y-.855)/.70
                        old=v.co.copy();world.z-=.24*(projected-.880)**1.28;v.co=inv@world
                        changed.append((v,old))
        original_write(frame,scene,objects,mode,colors)
        for v,old in changed:v.co=old
    D.write_native=exporter
    if dest:=os.getenv("HAUGAN_REVIEW"):os.environ["DARWIN_FAMILY_REVIEW"]=dest
    D.make(q)
    sc=D.bpy.context.scene
    sc.name="LuanTTD | Yate Haugan #218"
    sc["metadata"]="OpenTTD 16.0-RC1 src/table/engines.h #218; J fast CTOL; sprite image 8."
    sc["native"]="City Airport. Shared gear datum, 4 working visible nozzles and independent drooped ground outline."
    # Keep both reviewing states available to the editor, not only in the
    # exports. This shape key is independent of the two selectable gear sets.
    sc.camera=next(cam for cam in sc.objects if cam.type=="CAMERA" and cam.name.startswith("Apron"))
    for group in sc.collection.children:
        for ob in group.objects:
            ob.hide_render=group.name.startswith("05")
            if ob.type!="MESH" or not (ob.name.startswith("Lofted slim Haugan") or "Pitot probe" in ob.name):
                continue
            ob.shape_key_add(name="Clean cruise reference",from_mix=False)
            droop=ob.shape_key_add(name="Ground approach nose droop",from_mix=False)
            mat=ob.matrix_world
            inv=mat.inverted()
            for v in droop.data:
                w=mat@v.co
                if w.y>drawn_nose(.880):
                    y=.855+(w.y-.855)/.70
                    w.z-=.24*(y-.880)**1.28
                    v.co=inv@w
            droop.value=1
    D.bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art/stock_yate_haugan.blend"),compress=True)

if __name__=="__main__":
    make()

#!/usr/bin/env python3
"""Original stock YAe46 and A31, authored apertures, wheels and liveries.

No sprite or third-party geometry is imported. Reuse the mesh export and
parametric pressure-shell/foil tooling from the first jet families.
"""
from dataclasses import dataclass
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent))
from build_stock_guru_airtaxi_art import Variant
import build_stock_darwin_family_art as d

@dataclass(frozen=True)
class HighTail(Variant):
    fin_root: float = .257


YATE=HighTail(
    146,237,"Compact shoulder-wing regional jet with four small turbofans and elevated tailplane",
    ("f1eee2","dfddcd","385ba3","2c3a68","496eac","c2a64d"),
    (.767,.732,.133,.226,.111,.103),
    (.806,.148,-.308,-.153,-.227,.312,.056,.068),
    (.292,-.471,-.679,.569,.023),(-.322,-.559,.604),
    (.244,.172,-.178,.248,.060,.032),
    (.166,-.067,.043,.052,2,.540,.031),18,False,"yate_yae46","Yate_YAe46")

A31=Variant(
    431,234,"Shorter derivative of the widebody with tapered tail, twin high-bypass nacelles and split tip fences",
    ("eee9df","ddd3c9","9c485f","533449","b75d64","caab55"),
    (.956,.903,.186,.278,.153,.145),
    (.893,.357,-.440,-.195,-.420,.183,.116,.113),
    (.376,-.594,-.879,.348,.040),(-.353,-.732,.626),
    (.321,.208,-.250,.155,.122,.058),
    (.238,-.138,.058,.076,2,.666,.041),23,True,"airtaxi_a31","Airtaxi_A31")


def yate_engines(q):
    for sign in (-1,1):
        for x,front,back,h,r,nozzle in (
          (.248,.169,-.193,.258,.061,.034),(.477,.092,-.196,.272,.055,.029)):
            def u(f,rad,rise,color):
                return (front+(back-front)*f,rad,h+rise,color)
            rings=(u(0,r*.88,0,"Wing leading trim"),u(.07,r,.002,"Panel ivory"),
                   u(.30,r*.99,.006,"Silver pressure hull"),u(.55,r*.82,.004,"Lit blue"),
                   u(.81,nozzle*1.10,.006,"Exhaust patina bronze"),u(1,nozzle,.007,"Dark intake"),
                   u(.994,nozzle*.82,.007,"Fan deep metal"),u(.85,nozzle*.62,.006,"Dark intake"),
                   u(.22,r*.73,.002,"Dark intake"),u(.019,r*.74,0,"Shadowed nacelle steel"))
            d.art.turbojet("Independent short-haul open turbine",sign*x,rings,"Exhaust patina bronze")
            wing=q.wing[5]+.026*x/q.wing[0]
            d.B("Compact nacelle pylon meets high wing underside",(sign*x,(front+back)/2+.013,(wing+h)/2),
                (.035,.113,wing-h+.019),"Silver pressure hull",.009)
        d.B("Independent main landing gear side fairing",(sign*.126,-.079,.173),
            (.094,.318,.087),"Panel ivory",.027,(0,0,sign*.072))


def a31_engines(q):
    d.engines(q)
    # Inverted lower fin and rising top fence have their own mesh planes;
    # the stock wing position is preserved, so its clipping bound does not grow.
    for sign in (-1,1):
        tip=q.wing[0]
        y=q.wing[5]+q.wing[6]
        d.art.close_mesh("Split wingtip fence with beveled root",
           [(sign*(tip-.027),-.264,y+.008),(sign*(tip-.011),-.420,y+.001),
            (sign*(tip-.006),-.396,y+.097),(sign*(tip-.017),-.339,y+.106),
            (sign*(tip-.043),-.270,y+.011),(sign*(tip-.028),-.420,y+.004),
            (sign*(tip-.018),-.400,y+.097),(sign*(tip-.029),-.340,y+.106)],
           [(0,1,2,3),(7,6,5,4),(4,5,1,0),(0,3,7,4),(3,2,6,7),(6,2,1,5)],
           ["Lit blue","Panel ivory","Aluminium bezel","Aluminium bezel","Crown ivory","Blue taper"])


if __name__=="__main__":
    d.make(YATE,title="Yate Aerospace YAe46",sprite_family=6,class_tag="P / conventional CTOL",
           engine_title="Four short-haul open fan nacelles",engine_mesh=yate_engines)
    d.make(A31,title="Airtaxi A31",sprite_family=4,
           engine_title="Twin nacelles and split wingtip fences",engine_mesh=a31_engines)

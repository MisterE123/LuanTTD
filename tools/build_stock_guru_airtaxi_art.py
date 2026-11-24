#!/usr/bin/env python3
"""Original RC1 Guru Galaxy and Airtaxi A21, taxi and clean-flight meshes.

DARWIN_FAMILY_REVIEW=/tmp/airline-review blender -b -t 2 --python-exit-code 1 \
  --python tools/build_stock_guru_airtaxi_art.py
No third-party sprite, image, livery or geometry is embedded.
"""
from dataclasses import dataclass
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_stock_darwin_family_art as d

@dataclass(frozen=True)
class Variant(d.Frame):
    shape: str = ""
    export_name: str = ""

    @property
    def stem(self):
        return self.shape


GALAXY=Variant(
    420,232,"First-generation wide-body tri-jet with an independent dorsal turbine and high-fin root",
    ("eee7d5","efe1ca","217e79","275652","368d7e","d0a351"),
    (1.07,1.07,.192,.290,.148,.147),
    (.923,.294,-.508,-.251,-.460,.202,.111,.111),
    (.400,-.658,-1.028,.334,.043),(-.430,-.881,.764),
    (.350,.206,-.242,.158,.106,.053),
    (.243,-.196,.057,.079,2,.756,.039),27,False,"guru_galaxy","Guru_Galaxy")

A21=Variant(
    421,233,"Early high-capacity Airbus-era twinjet, broad nose ring and a forward cabin extending to a slimmer tail",
    ("f2ece0","efdfd0","bd693d","8c4535","c58751","333f5c"),
    (1.121,1.025,.177,.288,.158,.135),
    (.889,.318,-.413,-.180,-.420,.191,.117,.109),
    (.353,-.675,-.996,.349,.042),(-.477,-.826,.630),
    (.293,.263,-.231,.168,.114,.060),
    (.227,-.126,.058,.072,2,.782,.040),28,False,"airtaxi_a21","Airtaxi_A21")


def galaxy_engines(q):
    d.engines(q)
    # The third engine is ahead of the vertical fin at its inlet and
    # opens behind it at the nozzle; no wheel, mounting block, or wing
    # crosses either recessed opening.
    a,b,h,r,out=-.581,-1.144,.570,.093,.059
    def ring(u,rad,rise,color):
        return (a+(b-a)*u,rad,h+rise,color)
    hoops=(ring(0,r*.91,0,"Wing leading trim"),ring(.07,r,0,"Crown ivory"),
           ring(.30,r*1.011,.006,"Panel ivory"),ring(.49,r*.94,.010,"Lit blue"),
           ring(.72,r*.80,.011,"Silver pressure hull"),ring(.88,out*1.06,.008,"Exhaust patina bronze"),
           ring(1,out,.008,"Dark intake"),ring(.994,out*.80,.008,"Exhaust patina bronze"),
           ring(.86,out*.62,.008,"Dark intake"),ring(.17,r*.74,.003,"Dark intake"),
           ring(.021,r*.76,0,"Shadowed nacelle steel"))
    d.art.turbojet("Independent third fan with recessed hub and exhaust",0,hoops,"Exhaust patina bronze")
    d.B("Molded saddle supporting the dorsal turbine at the fin root",(0,-.788,.473),
        (.103,.306,.124),"Panel ivory",.037,(.067,0,0))
    for side in (-1,1):
        d.C("Fin root saddle runs down to the fuselage",
          (side*.058,-.663,.512),(side*.046,-.931,.436),.012,.0062,"Skinned wing alloy",10)


def airtaxi_engines(q):
    d.engines(q)
    for side in (-1,1):
        # Early forward-mounted turbofans have visible cowl plates and
        # separate service doors in the nacelle behind the intake lip.
        x=side*(q.motor[0]+q.motor[4]*.925)
        for delta in (-.045,.069):
            d.C("Concentric shallow turbofan inspection seam",
                (x,.059+delta,.182),(x+side*.002,.125+delta,.185),
                .0017,.0017,"Rib inset",6)
        d.B("Oval nacelle emergency release panel",(x,.002,.151),
            (.003,.047,.018),"Panel ivory",.004)


if __name__=="__main__":
    d.make(GALAXY,title="Guru Galaxy",sprite_family=3,
           engine_title="Three open turbine inlets",engine_mesh=galaxy_engines)
    d.make(A21,title="Airtaxi A21",sprite_family=4,
           engine_title="Forward wide-bypass twin nacelles",engine_mesh=airtaxi_engines)

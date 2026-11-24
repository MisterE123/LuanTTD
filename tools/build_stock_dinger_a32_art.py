#!/usr/bin/env python3
"""Original RC1 #238 Dinger 100 / #235 Airtaxi A32 with separately retractable gear."""
from dataclasses import dataclass
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent))
from build_stock_guru_airtaxi_art import Variant
import build_stock_darwin_family_art as d

@dataclass(frozen=True)
class HighTail(Variant):
    fin_root: float=.215


DINGER=HighTail(
    100,238,"Compact rear-engined regional jet with long narrow cabin, swept wings and a true T-tail",
    ("eeebdc","e8d7bd","46716a","2e474e","627c64","ac7b35"),
    (.834,.809,.108,.218,.107,.094),
    (.689,.119,-.351,-.170,-.302,.145,.091,.083),
    (.269,-.616,-.765,.518,.029),(-.343,-.669,.564),
    (.155,-.368,-.722,.247,.060,.033),
    (.140,-.095,.044,0,1,.584,.034),21,False,"dinger_100","Dinger_100")

A32=Variant(
    432,235,"Shortened conventional derivative with rematched low-bypass nacelles and polished curved wingtip",
    ("efebd6","e6ddc6","ca7938","53466a","d29755","b6ad83"),
    (.877,.864,.159,.252,.139,.124),
    (.818,.290,-.400,-.186,-.383,.163,.103,.093),
    (.321,-.566,-.839,.308,.039),(-.359,-.716,.591),
    (.291,.213,-.214,.135,.096,.046),
    (.211,-.131,.051,.065,2,.585,.037),21,True,"airtaxi_a32","Airtaxi_A32")

def rear_jets(q):
    x,front,back,h,r,tail=q.motor
    def k(f,rad,rise,c):
        return (front+(back-front)*f,rad,h+rise,c)
    rings=(k(0,r*.89,0,"Wing leading trim"),k(.064,r,0,"Panel ivory"),
           k(.34,r*.96,.002,"Silver pressure hull"),k(.55,r*.83,.005,"Lit blue"),
           k(.80,tail*1.16,.009,"Exhaust patina bronze"),k(1,tail,.011,"Dark intake"),
           k(.995,tail*.82,.011,"Fan deep metal"),k(.87,tail*.69,.009,"Dark intake"),
           k(.21,r*.70,.001,"Dark intake"),k(.02,r*.75,0,"Shadowed nacelle steel"))
    for sign in (-1,1):
        d.art.turbojet("Open side nacelle with separate fan and annular exhaust",sign*x,rings,"Exhaust patina bronze")
        d.B("Root pylon flows directly into the tapering pressure shell",(sign*.111,-.514,h+.003),
            (.106,.173,.048),"Silver pressure hull",.026,(0,sign*.073,sign*.093))
        d.C("Pylon aft fillet",(sign*.097,-.474,h-.019),(sign*.131,-.649,h+.014),
            .018,.013,"Panel ivory",11)


if __name__=="__main__":
    d.make(DINGER,title="Dinger 100",sprite_family=2,class_tag="P / conventional CTOL",
           engine_title="Rear-mounted open turbofan pair",engine_mesh=rear_jets)
    d.make(A32,title="Airtaxi A32",sprite_family=4,engine_title="Short underwing open fan nacelles")

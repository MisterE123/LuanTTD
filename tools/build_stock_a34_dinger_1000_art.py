#!/usr/bin/env python3
"""Two original late-era native airframes: short-runway A34 and tailless Dinger 1000."""
from dataclasses import dataclass
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent))
from build_stock_guru_airtaxi_art import Variant
import build_stock_darwin_family_art as d

@dataclass(frozen=True)
class Delta(Variant):
    fin_root: float=.169
    tailless: bool=True
    native_scale: float=.88


A34=Variant(
    434,239,"A compact modern small-field transport, high-lift swept wing, curved tips and forward twin fans",
    ("e4e9e6","dce6df","2e8176","324e53","508b83","c5b965"),
    (.802,.785,.126,.245,.115,.109),
    (.762,.201,-.333,-.145,-.324,.162,.095,.089),
    (.302,-.514,-.762,.323,.037),(-.346,-.632,.571),
    (.250,.203,-.166,.131,.086,.045),
    (.188,-.100,.048,0,1,.550,.034),18,True,"airtaxi_a34_1000","Airtaxi_A34_1000")

DINGER=Delta(
    1000,247,"Long slender supersonic transport with tailless broad delta and paired four-engine pack",
    ("f1ede0","e8e1d8","7e3d49","3b4157","a85f57","b59871"),
    (1.186,1.107,.107,.223,.098,.105),
    (.790,.531,-.835,-.581,-.774,.168,.036,.077),
    (.076,-.740,-1.070,.287,.015),(-.554,-.912,.620),
    (.225,.186,-.586,.099,.044,.032),
    (.195,-.302,.046,.076,2,.746,.033),22,False,"dinger_1000","Dinger_1000")


def delta_power(q):
    for side in (-1,1):
        for x,fore,aft,h,r,nozzle in ((.159,.105,-.674,.119,.048,.033),(.272,.031,-.659,.115,.048,.035)):
            def u(f,rad,dy,ink):
                return (fore+(aft-fore)*f,rad,h+dy,ink)
            hoops=(u(0,.86*r,0,"Wing leading trim"),u(.070,r,.001,"Panel ivory"),
                   u(.251,r,.002,"Silver pressure hull"),u(.57,.90*r,.002,"Silver pressure hull"),
                   u(.84,nozzle*1.07,.005,"Shadowed nacelle steel"),u(1,nozzle,.005,"Exhaust patina bronze"),
                   u(.992,nozzle*.79,.005,"Dark intake"),u(.90,nozzle*.66,.003,"Dark intake"),
                   u(.17,r*.75,.002,"Dark intake"),u(.02,r*.72,0,"Shadowed nacelle steel"))
            d.art.turbojet("Supersonic hollow inlet, blade and independent ejector",side*x,hoops,"Exhaust patina bronze")
            d.B("Tapered joined wing-engine pack seam",(side*x,-.290,h+.048),
                (.073,.500,.058),"Skinned wing alloy",.020,(0,0,side*.020))
        d.B("Visible common wing pylon fairing joining the two engines",(side*.215,-.355,.174),
            (.143,.510,.053),"Panel ivory",.017)
    d.C("Separate nose probe and polished button",(0,1.168,.234),(0,1.250,.219),
        .008,.0035,"Landing gear chrome",10)


if __name__=="__main__":
    d.make(A34,title="AirTaxi A34-1000",sprite_family=11,class_tag="P / conventional CTOL",
           engine_title="High-lift short-field twin fans")
    d.make(DINGER,title="Dinger 1000",sprite_family=18,engine_title="Four hollow supersonic engine pods",
           engine_mesh=delta_power)

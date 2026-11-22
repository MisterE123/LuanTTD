#!/usr/bin/env python3
"""Build the original Bayline dispatch icons and an optional review sheet.

Requires Pillow. Run: python tools/build_dispatch_icons.py
Pass --review /tmp/dispatch-icons.png to render a large, labeled review sheet.
"""
import argparse
from collections import OrderedDict
from math import hypot
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parents[1] / "mods/bayline/textures"
# Mid-century transport enamel: steel blue, cream lettering, muted glass and red brick.
INK="#0d202a"; EDGE="#55777d"; WELL="#172d38"; WELL_LIGHT="#253f49"
CREAM="#ffe9be"; BRASS="#dea956"; TEAL="#75ad9f"; TEAL_DARK="#386a61"
SLATE="#607279"; SLATE_DARK="#384951"; BLUE="#85bacc"; RED="#af6d53"
BRICK="#e0986e"; WHITE="#fff6d9"; GLASS="#254752"; SAGE="#75915c"
PX=4
SIZE=48

class Icon:
    def __init__(self):
        self.src = Image.new("RGBA",(SIZE*PX,SIZE*PX))
        self.d = ImageDraw.Draw(self.src)
    def p(self, pts):
        return [(round(x*PX),round(y*PX)) for x,y in pts]
    def rect(self, bbox, fill, outline=None, width=1):
        self.d.rectangle(tuple(round(i*PX) for i in bbox), fill=fill, outline=outline, width=max(1,round(width*PX)))
    def round(self, bbox, r, fill, outline=None, width=1):
        self.d.rounded_rectangle(tuple(round(i*PX) for i in bbox),radius=round(r*PX), fill=fill,outline=outline,width=max(1,round(width*PX)))
    def oval(self, bbox, fill, outline=None, width=1):
        self.d.ellipse(tuple(round(i*PX) for i in bbox), fill=fill, outline=outline, width=max(1,round(width*PX)))
    def path(self, points, fill, width=1):
        self.d.line(self.p(points),fill=fill,width=max(1,round(width*PX)),joint="curve")
    def poly(self, points, fill):
        self.d.polygon(self.p(points),fill=fill)
    def frame(self):
        self.round((1.2,1.2,46.8,46.8),8.6,INK,EDGE,1.15)
        self.round((3.4,3.4,44.6,44.6),6.65,WELL)
        self.path([(8,7.4),(40,7.4)],WELL_LIGHT,1.0)
        self.path([(8,41.7),(40,41.7)],INK,1.2)
    def flatten(self):
        return self.src.resize((SIZE,SIZE),Image.Resampling.LANCZOS)

def inspect(i):
    i.oval((10,10,33,33),INK)
    i.poly([(27.0,28),(31.6,25.4),(41.4,35),(39.9,39.6),(35.8,40.8)],INK)
    i.path([(27.9,28.0),(38.0,38.1)],BRASS,5.0)
    i.path([(29.5,29.2),(37.5,36.8)],CREAM,1.3)
    i.oval((9,8.5,32.3,31.8),CREAM)
    i.oval((12.5,12,28.75,28.25),GLASS)
    i.path([(14.9,22.1),(21.2,22.1),(21.2,16.6),(25.4,16.6)],BLUE,2.2)
    i.oval((19.4,20.4,23.1,24.1),WHITE)

def road(i):
    i.poly([(8,38),(18,10),(28,10),(40,38)],INK)
    i.poly([(9,37),(18.6,10),(28.6,10),(39,37)],BRASS)
    i.poly([(12,37),(20,10),(27.1,10),(36,37)],SLATE_DARK)
    i.path([(13.1,36.6),(20.2,10.3)],SLATE,1.55)
    i.path([(34.8,36.6),(27.1,10.3)],SLATE,1.55)
    for z,w,h in ((14,1.15,3.2),(20.0,1.55,3.9),(28.1,2.05,6.5)):
        i.poly([(24-w/2,z),(24+w/2,z),(24+w*.62,z+h),(24-w*.62,z+h)],CREAM)

def stop(i):
    i.round((9,34.7,40.1,38.9),1.4,CREAM)
    i.path([(13.0,34.8),(13.0,19.0),(32.0,19.0),(32.0,34.8)],TEAL,2.7)
    i.rect((15,21.4,30,25.6),GLASS)
    i.path([(15.1,26.5),(29.7,26.5)],CREAM,1.3)
    i.path([(17,34),(17,29),(28,29),(28,34)],RED,2.15)
    i.poly([(9.8,20),(13.5,15.4),(30.8,15.4),(34.5,20)],TEAL)
    i.path([(10.5,20),(34,20)],CREAM,1.7)
    i.path([(38.5,34.7),(38.5,12.7)],TEAL,1.9)
    i.round((34.5,9.7,41.1,15.9),1.1,BRASS)
    i.path([(36.0,12.7),(39.3,12.7)],INK,1.2)

def depot(i):
    i.round((10,34.5,38,38.6),1.1,CREAM)
    i.rect((11,20,37,35.7),RED)
    i.poly([(8,21.5),(24,10.8),(40,21.5),(36.4,23.8),(24,15.7),(11.2,23.8)],CREAM)
    i.poly([(9,20.4),(24,10.2),(39.1,20.4),(38.4,21.7),(24,12.7),(10,22.2)],SLATE)
    i.rect((16.7,24.8,31.3,35.8),INK)
    i.path([(12.2,28),(16,28)],BRICK,1.25)
    i.path([(32,28),(35.8,28)],BRICK,1.25)
    i.path([(17,25.5),(31,25.5)],BRICK,2.0)
    i.round((19.6,21.0,28.4,23.9),.45,TEAL)
    i.path([(21.6,22.4),(26.5,22.4)],CREAM,1.05)
    i.path([(18.5,37.3),(29.4,37.3)],SLATE_DARK,1.3)

def bus(i, offset_x, offset_y, tint, windows, small=False):
    x,y=offset_x,offset_y
    i.round((x,y,x+21,y+17),3.0,tint,INK,1.2)
    i.round((x+2.3,y+3.0,x+18.7,y+9.9),1.45,windows)
    i.path([(x+10.4,y+3.2),(x+10.4,y+9.5)],tint,1.1)
    i.round((x+2.2,y+15,x+6,y+19),1.4,INK)
    i.round((x+15,y+15,x+18.8,y+19),1.4,INK)
    i.oval((x+3.1,y+11.3,x+5.8,y+13.9),WHITE)
    i.oval((x+15.2,y+11.3,x+17.9,y+13.9),WHITE)
    if not small:
        i.path([(x+8.7,y+13),(x+12.4,y+13)],INK,1.25)

def fleet(i):
    bus(i,8,11,SLATE,INK,True)
    bus(i,17,19,TEAL,GLASS)
    i.path([(21.4,23.4),(26.8,23.4)],BLUE,1.15)
    i.path([(29.5,23.4),(34.0,23.4)],BLUE,1.15)

def finance(i):
    i.round((10,10,38,38),2.1,CREAM,INK,1.4)
    i.rect((13.1,14,35,34.9),SLATE_DARK)
    i.path([(16,29.2),(31.9,29.2)],SLATE,1.0)
    i.rect((16,25.8,19.2,33),TEAL)
    i.rect((22.0,21.9,25.2,33),TEAL)
    i.rect((28.0,17.8,31.3,33),BRASS)
    i.path([(15.2,25),(22.1,19.2),(24.7,20.4),(31.4,15.4)],CREAM,1.4)
    i.poly([(28.2,15.3),(32.5,14.8),(31.7,19)],CREAM)

def jump(i):
    i.poly([(8,15),(17.8,12),(28.8,15.2),(39.9,11.7),(39.9,34.4),(29,37.4),(17.8,34.1),(8,37.9)],CREAM)
    i.poly([(9.8,17),(17.9,14.5),(29,17.6),(38,14.5),(38,32.6),(28.9,35.4),(17.7,31.9),(9.8,35)],SAGE)
    i.path([(18.1,14.7),(18.1,31.6)],TEAL_DARK,1.1)
    i.path([(29.1,17.6),(29.1,34.7)],TEAL_DARK,1.1)
    i.path([(10.3,29),(17.7,24.9),(23.9,28.2),(29.3,24),(37.6,23)],CREAM,1.15)
    i.poly([(23.6,22.5),(36.6,22.5),(30.1,32.3)],INK)
    i.oval((23.1,16.1,37.1,29.1),INK)
    i.poly([(25.6,23.2),(34.8,23.2),(30.2,30.0)],BRASS)
    i.oval((25.0,17.6,35.5,27.8),BRASS)
    i.oval((28.5,20.8,32.0,24.4),INK)

def controls(i):
    for y,x in ((14,18),(24,30),(34,21)):
        i.path([(9.8,y),(38.1,y)],INK,4)
        i.path([(10.8,y),(37.1,y)],SLATE,1.8)
        i.path([(11,y),(x,y)],TEAL,1.8)
        i.round((x-3.5,y-3.5,x+3.5,y+3.5),1.75,CREAM,INK,.75)
        i.path([(x,y-2.1),(x,y+2.1)],BRASS,.8)

def back(i):
    i.path([(13,22),(32,22),(37,25),(37,34)],INK,6.0)
    i.path([(13,22),(31.5,22),(36.5,24.9),(36.5,33)],TEAL,3.4)
    i.poly([(9.8,21.9),(22.7,12.1),(22.7,31.7)],CREAM)
    i.path([(12.6,21.8),(21.1,15.25)],WHITE,1.1)

def bulldoze(i):
    i.round((8.6,29.4,32.2,38.1),4.1,INK,SLATE,1.35)
    for x in (13.7,19.0,24.3,28.4):
        i.oval((x-1.3,32.4,x+1.3,35.0),SLATE)
    i.poly([(13.1,28.8),(13.1,14.2),(23.1,14.2),(25.7,21.3),(31.2,21.3),(31.2,30.4),(13.1,30.4)],BRASS)
    i.poly([(15.3,16.3),(21.8,16.3),(23.4,22.1),(15.3,22.1)],GLASS)
    i.path([(24.6,26.6),(33.1,26.6),(37.9,31.1)],CREAM,1.55)
    i.poly([(35.6,23.3),(40.9,26.0),(40.9,36.8),(38.4,38.0),(33.8,34.9)],TEAL)
    i.path([(40.1,27.1),(40.1,36.5),(38.2,37.0)],CREAM,1.45)
    i.path([(10,38.8),(41,38.8)],SLATE,1.15)

def bend(i):
    center=[(17,37),(17,22),(19,16),(24,13),(38,13)]
    i.path(center,INK,13)
    i.path(center,BRASS,10.8)
    i.path(center,SLATE_DARK,8.4)
    i.path([(17,34.5),(17,29.5)],CREAM,1.45)
    i.path([(17,25.6),(17.3,21.7),(18.35,18.9)],CREAM,1.45)
    i.path([(21.9,15.2),(24.2,13.1),(27,13)],CREAM,1.45)
    i.path([(31.1,13),(35.0,13)],CREAM,1.45)
    i.poly([(8.8,32.4),(12.3,31.0),(12.3,39.9),(8.8,38.5)],TEAL)
    i.poly([(34.0,6.4),(40.2,6.4),(38.9,8.7),(35.3,8.7)],TEAL)

def cancel(i):
    i.poly([(19,10),(29,10),(37.2,17.5),(37.2,30.5),(29,38),(19,38),(10.8,30.5),(10.8,17.5)],INK)
    i.poly([(19.1,11.8),(28.9,11.8),(35.5,18.4),(35.5,29.6),(28.9,36.2),(19.1,36.2),(12.5,29.6),(12.5,18.4)],BRICK)
    i.poly([(19.8,14),(28.2,14),(33.2,19.1),(33.2,28.9),(28.2,34),(19.8,34),(14.8,28.9),(14.8,19.1)],RED)
    i.path([(19.7,19.4),(28.3,28.6)],CREAM,3.0)
    i.path([(28.3,19.4),(19.7,28.6)],CREAM,3.0)

def time(i):
    i.path([(15.3,18.6),(11.5,18.6)],SLATE,1.8)
    i.path([(12.2,23.2),(8.9,23.2)],TEAL,1.9)
    i.path([(13.9,28.0),(10.5,28.0)],SLATE,1.8)
    i.round((22.6,8.5,30.6,11.2),.7,BRASS)
    i.rect((25.4,10.4,27.6,15.0),BRASS)
    i.path([(34.9,15.8),(37.3,12.9)],TEAL,2.0)
    i.oval((13.8,13.1,39.6,38.9),INK)
    i.oval((15.3,14.3,38.4,37.8),CREAM)
    i.oval((18.1,17.1,35.5,35.0),GLASS)
    i.path([(26.8,25.7),(26.8,19.0)],CREAM,1.8)
    i.path([(26.8,25.7),(31.9,27.9)],BRASS,1.65)
    i.oval((25.4,24.3,28.3,27.2),CREAM)

def terrain(i):
    i.poly([(6,30),(23,17),(42,29),(23,42)],TEAL_DARK)
    i.path([(6,30),(17,21),(23,15),(29,21),(42,29)],TEAL,2.5)
    i.path([(14,33),(23,25),(33,32)],CREAM,2.0)
    i.path([(20,37),(24,34),(28,36)],BRASS,1.5)

def ground_tool(i,which):
    i.poly([(7,31),(18,25),(30,28),(41,23),(41,31),(30,37),(18,34),(7,39)],TEAL_DARK)
    i.path([(7,31),(18,25),(30,28),(41,23)],TEAL,2.2)
    if which=="level":
        i.path([(10,18),(38,18)],CREAM,3.0)
        i.oval((20,14,27,22),BRASS,WHITE,1)
    else:
        tip,end=(10,27) if which=="raise" else (25,9)
        i.path([(24,end),(24,tip)],CREAM,3.5)
        flank=tip+6 if which=="raise" else tip-6
        i.path([(17,flank),(24,tip),(31,flank)],BRASS,3.5)

def bridgework(i,steel=False):
    support=SLATE if steel else BRASS
    i.path([(5,31),(13,23),(34,23),(43,31)],support,4)
    for x in (15,24,33):
        i.path([(x,26),(x,38)],support,4)
        i.path([(x-3,37),(x+3,37)],CREAM,2)
    i.path([(13,19),(35,19)],TEAL if steel else CREAM,2)
    for x in (15,22,29,34):
        i.path([(x,19),(x,25)],CREAM,2)

def concrete(i):
    i.poly([(5,33),(13,24),(34,24),(43,33),(33,32),(28,28),(20,28),(14,32)],SLATE)
    i.path([(7,32),(14,24),(33,24),(41,32)],BRASS,2)
    i.path([(14,19),(33,19)],CREAM,2)
    for x in (14,21,27,33):
        i.path([(x,19),(x,23)],CREAM,2)
    i.path([(18,28),(18,36)],SLATE,4)
    i.path([(30,28),(30,36)],SLATE,4)

def tunnel(i):
    i.poly([(5,33),(5,26),(13,15),(25,10),(35,17),(43,32),(43,37),(5,37)],TEAL_DARK)
    i.oval((14,16,34,36),CREAM)
    i.rect((14,26,34,37),CREAM)
    i.oval((18,20,30,33),INK)
    i.rect((18,26,30,36),INK)
    i.path([(16,38),(32,38)],BRASS,2)
    i.path([(24,31),(24,38)],CREAM,1.2)

def tram(i,part):
    if part=="rotate":
        i.path([(30,13),(20,12),(13,18),(12,28),(20,35),(30,33)],BRASS,3.5)
        i.path([(23,8),(32,13),(28,21)],CREAM,3.5)
    elif part=="depot":
        i.poly([(6,21),(24,9),(42,21),(42,38),(6,38)],TEAL_DARK)
        i.path([(6,21),(24,9),(42,21)],BRASS,3)
        i.rect((15,24,33,37),CREAM)
        i.rect((19,28,29,37),INK)
        i.path([(20,32),(18,40)],SLATE,2)
        i.path([(28,32),(30,40)],SLATE,2)
    elif part=="stop":
        i.path([(8,33),(40,33)],SLATE,3)
        i.path([(8,38),(40,38)],SLATE,3)
        i.path([(9,29),(9,15),(39,15),(39,29)],TEAL,4)
        i.path([(13,27),(35,27)],CREAM,3)
        i.path([(11,18),(38,18)],BRASS,2)
    else:
        lower=39 if part=="full" else 29
        i.path([(15,12),(15,lower)],SLATE,4)
        i.path([(33,12),(33,lower)],SLATE,4)
        for y in range(15,lower,7): i.path([(12,y),(36,y)],BRASS,2)
        if part=="full":
            i.rect((17,19,31,33),TEAL)
            i.path([(19,20),(29,20)],CREAM,3)
            i.path([(17,15),(24,11),(32,15)],BRASS,2)
        else:
            i.path([(15,31),(33,31)],CREAM,3)

def harbor(i,depot=False):
    for y in (30,36):
        i.path([(7,y),(14,y-2),(21,y),(28,y-2),(35,y),(41,y-2)],TEAL,2.3)
    if depot:
        i.poly([(8,21),(24,10),(40,21),(40,32),(8,32)],TEAL_DARK)
        i.path([(8,21),(24,10),(40,21)],CREAM,3)
        i.rect((17,23,31,31),INK)
        i.path([(19,30),(24,27),(29,30)],BRASS,1.8)
    else:
        i.path([(8,17),(30,17),(36,23)],CREAM,3.5)
        i.path([(11,21),(29,21),(36,26)],BRASS,2)
        i.path([(14,20),(14,32)],SLATE,3)
        i.path([(27,20),(27,32)],SLATE,3)
        i.path([(31,30),(37,33),(40,30)],CREAM,2)

def aqueduct(i):
    i.path([(6,19),(42,19)],TEAL,4)
    i.path([(6,23),(42,23)],CREAM,2.8)
    for x in (10,24,38):
        i.path([(x,23),(x,39)],SLATE,3.8)
    i.path([(10,35),(15,28),(20,28),(24,35),(29,28),(34,28),(38,35)],BRASS,2.6)

def canal(i):
    i.poly([(10,12),(38,12),(38,38),(10,38)],TEAL_DARK)
    i.path([(12,12),(12,38)],BRASS,3)
    i.path([(36,12),(36,38)],BRASS,3)
    for y in (19,26,33): i.path([(16,y),(21,y-2),(26,y),(31,y-2)],TEAL,2)

def lock(i):
    i.poly([(10,10),(38,10),(38,39),(10,39)],TEAL_DARK)
    i.path([(12,12),(12,39)],SLATE,3.5)
    i.path([(36,12),(36,39)],SLATE,3.5)
    for y in (14,32):
        i.path([(12,y),(24,y+5),(36,y)],CREAM,3)
    i.path([(24,29),(24,19)],BRASS,3)
    i.path([(19,24),(24,19),(29,24)],BRASS,2)

def airfield(i):
    i.path([(12,36),(35,12)],INK,12)
    i.path([(12,36),(35,12)],SLATE,9.3)
    i.path([(11,33),(16,38)],CREAM,1.5)
    i.path([(33,10),(38,15)],CREAM,1.5)
    for x,y in ((17,31),(22,26),(27,21),(32,16)):
        i.path([(x-.9,y+.95),(x+.9,y-.95)],CREAM,1.4)
    i.poly([(7,25),(7,19),(13,14),(19,19),(19,25)],TEAL)
    i.rect((11.7,21,15.3,25),INK)
    i.path([(7,19),(13,14),(19,19)],BRASS,1.4)

def trimotor(i):
    # Face-on trimotor: central glazed cabin and three individual nacelles.
    i.path([(9,23),(39,23)],INK,8.4)
    i.path([(9,22.8),(39,22.8)],TEAL,5)
    i.path([(24,11),(24,34)],BRASS,4)
    i.path([(18,32),(30,32)],TEAL,2.2)
    for x in (14,24,34):
        i.oval((x-2.7,20,x+2.7,25.4),BRASS,INK,.8)
        i.oval((x-.95,21.6,x+.95,23.5),CREAM)
    i.path([(22.2,16.8),(25.8,16.8)],GLASS,2.0)
    i.poly([(11,31),(16,30),(16,34)],CREAM)
    i.poly([(37,31),(32,30),(32,34)],CREAM)

def ferry(i):
    i.path([(7,36),(15,34),(23,36),(31,34),(41,36)],TEAL,2.5)
    i.poly([(7,26),(41,26),(35,34),(14,34)],TEAL_DARK)
    i.path([(7,26),(41,26),(35,34),(14,34),(7,26)],CREAM,1.6)
    i.rect((15,19,33,26),BRASS)
    i.path([(14,18),(34,18)],CREAM,2.6)
    i.rect((22,11,26,18),SLATE)
    for x in (18,23,28): i.rect((x,21,x+2.1,24),GLASS)

def oneway_road(i):
    i.path([(9,25),(39,25)],BRASS,16)
    i.path([(9,25),(39,25)],SLATE_DARK,13.4)
    i.path([(11,25),(35,25)],TEAL,3.6)
    i.poly([(31,18.4),(40,25),(31,31.6)],CREAM)
    i.path([(13,18),(20,18)],CREAM,1.2)
    i.path([(21,32),(26,32)],CREAM,1.2)

def level_crossing(i):
    i.path([(10,24),(38,24)],SLATE,10.5)
    for x in (12,18,30,36):
        i.path([(x,24),(x+2,24)],CREAM,1.2)
    for y in (10,16,22,28,34,39):
        i.path([(17,y),(31,y)],BRASS,1.85)
    for x in (20,28): i.path([(x,9),(x,39)],CREAM,2.2)
    i.path([(12,30),(34,19)],INK,5)
    i.path([(12,30),(34,19)],CREAM,2.4)
    for x,y in ((15,28.5),(21,25.5),(27,22.5),(33,19.5)):
        i.path([(x-1,y+.5),(x+1,y-.5)],RED,2.45)
    i.oval((9.7,27.9,14.3,32.5),BRICK,INK,.8)

def rail_piece(i,part):
    paths={
        "x":[(7,24),(41,24)],"y":[(24,7),(24,41)],
        "upper":[(24,8),(23,17),(17,22),(8,24)],
        "lower":[(24,40),(25,31),(31,26),(40,24)],
        "left":[(8,24),(17,25),(22,31),(24,40)],
        "right":[(40,24),(31,23),(26,17),(24,8)],
    }
    track=paths[part]
    i.path(track,SLATE,9)
    i.path(track,CREAM,2.5)
    for x,y in track:
        i.oval((x-2,y-2,x+2,y+2),BRASS)

def rail_platform(i):
    i.path([(7,19),(41,19)],SLATE,6)
    i.path([(7,19),(41,19)],CREAM,1.3)
    i.rect((8,25,39,34),TEAL)
    i.path([(8,25),(39,25)],BRASS,2)
    i.rect((16,24,30,31),TEAL_DARK)

def rail_signal(i,oneway=False):
    i.path([(19,18),(19,39)],SLATE,3.5)
    i.rect((13,10,25,28),INK)
    i.oval((16,12,22,18),BRASS)
    i.oval((16,20,22,26),TEAL)
    if oneway:
        i.path([(26,34),(38,34)],CREAM,2)
        i.path([(34,30),(38,34),(34,38)],CREAM,2)

def freight(i):
    i.poly([(8,20),(38,20),(34,32),(11,32)],SLATE)
    i.poly([(13,19),(19,12),(24,15),(28,10),(34,19)],INK)
    i.path([(9,23),(35,23)],CREAM,2)
    i.oval((12,29,21,38),INK)
    i.oval((28,29,37,38),INK)
    i.oval((14,31,19,36),BRASS)
    i.oval((30,31,35,36),BRASS)

ART=OrderedDict((("inspect",inspect),("road",road),("stop",stop),("depot",depot),
                 ("fleet",fleet),("finance",finance),("jump",jump),("controls",controls),
                 ("back",back),("bulldoze",bulldoze),("bend",bend),("cancel",cancel),("time",time),
                 ("terrain",terrain),("raise",lambda i: ground_tool(i,"raise")),
                 ("lower",lambda i: ground_tool(i,"lower")),("level",lambda i: ground_tool(i,"level")),
                 ("bridge",bridgework),("girder",lambda i:bridgework(i,True)),("concrete",concrete),("tunnel",tunnel),
                 ("tram",lambda i:tram(i,"full")),("tram_stop",lambda i:tram(i,"stop")),
                 ("tram_depot",lambda i:tram(i,"depot")),("tram_half",lambda i:tram(i,"half")),
                 ("tram_rotate",lambda i:tram(i,"rotate")),
                 ("harbor",harbor),("ship_depot",lambda i:harbor(i,True)),("aqueduct",aqueduct),("canal",canal),("lock",lock),("airfield",airfield),("trimotor",trimotor),("ferry",ferry),("level_crossing",level_crossing),("oneway_road",oneway_road),("rail_platform",rail_platform),
                 ("rail_signal",rail_signal),("rail_oneway",lambda i:rail_signal(i,True)),("freight",freight))+
                tuple(("rail_"+key,lambda i,k=key:rail_piece(i,k)) for key in ("x","y","upper","lower","left","right")))

# Keep section pictograms distinct from their individual tools. These common
# primitives are also shared by related tools, but each full glyph has its
# own silhouette, composition, or action mark.
def arrow(i, a, b, color=CREAM, double=False):
    x,y=a; u,v=b
    length=hypot(u-x,v-y)
    dx,dy=(u-x)/length,(v-y)/length
    def head(x,y,dx,dy):
        i.poly([(x,y),(x-7*dx-4.6*dy,y-7*dy+4.6*dx),
                (x-7*dx+4.6*dy,y-7*dy-4.6*dx)],color)
    i.path([(x,y),(u,v)],color,2.8)
    head(u,v,dx,dy)
    if double: head(x,y,-dx,-dy)

def cross(i,x=35,y=13):
    i.oval((x-6.2,y-6.2,x+6.2,y+6.2),RED,INK,1.1)
    i.path([(x-2.8,y-2.8),(x+2.8,y+2.8)],CREAM,1.95)
    i.path([(x+2.8,y-2.8),(x-2.8,y+2.8)],CREAM,1.95)

def plus(i,x=35,y=13):
    i.oval((x-6.2,y-6.2,x+6.2,y+6.2),TEAL_DARK,INK,1.1)
    i.path([(x-3,y),(x+3,y)],WHITE,1.9)
    i.path([(x,y-3),(x,y+3)],WHITE,1.9)

def folder(i):
    i.poly([(8,13),(20,13),(24,17),(40,17),(40,36),(8,36)],BRASS)
    i.poly([(8,21),(41,21),(38,38),(8,38)],TEAL)
    i.path([(11,23),(37,23)],BLUE,2)
    i.path([(17,31),(30,31)],CREAM,3)

def wrench(i, a=(15,35), b=(29,20)):
    i.path([a,b],CREAM,4.2)
    i.oval((a[0]-3.5,a[1]-3.5,a[0]+3.5,a[1]+3.5),CREAM)
    i.oval((b[0]-6,b[1]-6,b[0]+6,b[1]+6),CREAM)
    i.poly([(b[0]-1,b[1]-1),(b[0]+1,b[1]-7),(b[0]+7,b[1]-6),(b[0]+7,b[1]-1)],WELL)

def tracks(i, y, x=8, end=40):
    for p in range(x+2,end,6): i.path([(p,y-4),(p,y+4)],BRASS,1.5)
    for k in (-2,2): i.path([(x,y+k),(end,y+k)],CREAM,1.3)

def train(i,x,y,color=TEAL,w=24):
    i.poly([(x,y),(x+w-6,y),(x+w,y+5),(x+w,y+10),(x,y+10)],color)
    i.rect((x+3,y+2,x+8,y+5),GLASS)
    i.rect((x+10,y+2,x+15,y+5),GLASS)
    i.path([(x+3,y+8),(x+w-1,y+8)],CREAM,1.1)
    for k in (4,w-5): i.oval((x+k-2,y+9,x+k+2,y+13),INK,SLATE,.7)

def waves(i,y=37):
    i.path([(7,y),(13,y-2),(19,y),(25,y-2),(31,y),(37,y-2),(42,y)],BLUE,2)

def light(i,x,y,color):
    i.oval((x-3.5,y-3.5,x+3.5,y+3.5),color,INK,.8)

def airplane(i,x=24,y=24):
    i.poly([(x-2,y-14),(x+2,y-14),(x+3,y-4),(x+15,y+3),
            (x+15,y+6),(x+3,y+3),(x+2,y+8),(x+7,y+12),
            (x-7,y+12),(x-2,y+8),(x-3,y+3),(x-15,y+6),
            (x-15,y+3),(x-3,y-4)],CREAM)

def category(i, kind):
    if kind=="survey_map":
        for j in range(3):
            i.path([(8,13+7*j),(17,11+8*j),(25,16+7*j),(38,13+8*j)],TEAL,2.2)
        for p in ((13,15),(25,28),(36,19)):
            x,y=p; i.path([(x-4,y),(x+4,y)],BRASS,2); i.path([(x,y-4),(x,y+4)],BRASS,2)
    elif kind=="roadworks":
        i.round((8,17,40,31),2,SLATE,CREAM,1.4)
        for x in (12,21,30):
            i.path([(x,28),(x+7,20)],BRASS,3.4)
        for x in (12,35): i.path([(x,31),(x,38)],CREAM,3)
    elif kind=="fleet_garage":
        i.poly([(7,18),(24,9),(41,18),(41,39),(7,39)],TEAL_DARK)
        i.path([(7,18),(24,9),(41,18)],CREAM,3)
        i.rect((10,21,38,37),INK)
        for x,c in ((11,TEAL),(26,BRASS)):
            i.round((x,24,x+11,36),2,c)
            i.rect((x+2,26,x+9,30),GLASS)
            i.path([(x+2,33),(x+9,33)],CREAM,1.4)
    elif kind=="company_index":
        i.rect((17,10,39,36),SLATE,CREAM,1.5)
        for y in (16,23,30):
            for x in (21,31): i.rect((x,y,x+4,y+3),GLASS)
        i.rect((8,22,18,36),TEAL_DARK,TEAL,1.2)
        i.path([(7,37),(41,37)],BRASS,2.4)
    elif kind=="navigation_compass":
        i.oval((9,9,39,39),GLASS,CREAM,2.0)
        for x,y in ((24,12),(24,35),(12,24),(35,24)):
            i.oval((x-1,y-1,x+1,y+1),BLUE)
        i.poly([(31,15),(28,27),(17,33),(20,21)],BRASS)
        i.poly([(31,15),(28,27),(20,21)],CREAM)
        i.oval((22.5,22.5,25.5,25.5),INK)
    elif kind=="settings_menu":
        i.round((8,16,40,34),3,TEAL_DARK,CREAM,1.5)
        for y in (20,25):
            for x in (12,18,24,30,36): i.rect((x-1.4,y,x+1.4,y+2),BLUE)
        i.round((15,30,33,31.7),.5,BRASS)
    elif kind=="workbenches":
        folder(i)
        wrench(i,(22,31),(32,22))
    elif kind=="road_tools":
        i.path([(9,32),(22,14),(39,14)],SLATE,9)
        i.path([(9,32),(22,14),(39,14)],CREAM,1.1)
        wrench(i,(23,36),(35,28))
    elif kind=="structure_index":
        i.path([(7,22),(41,22)],CREAM,3)
        i.path([(11,22),(11,34),(37,34),(37,22)],SLATE,2.5)
        i.path([(15,33),(15,28),(19,25),(29,25),(33,28),(33,33)],BRASS,3.1)
        i.path([(8,16),(40,16)],TEAL,2)
        for x in (13,24,35): i.path([(x,16),(x,22)],TEAL,2)
    elif kind=="tramways":
        i.path([(9,13),(39,13)],BRASS,2.7)
        i.path([(11,37),(37,37)],SLATE,2)
        for x in (10,26):
            i.round((x,19,x+12,34),2,TEAL)
            i.rect((x+1.8,22,x+10.2,27),GLASS)
            i.path([(x+2,30),(x+10,30)],CREAM,2)
            i.path([(x+4,18),(x+8,13)],CREAM,1.6)
    elif kind=="harbor_index":
        i.path([(24,17),(24,37)],CREAM,3)
        i.oval((20,9,28,17),None,CREAM,2)
        i.path([(14,22),(34,22)],BRASS,2.5)
        i.path([(11,28),(14,33),(24,37),(34,33),(37,28)],CREAM,2.7)
        i.poly([(10,25),(17,28),(10,32)],CREAM)
        i.poly([(38,25),(31,28),(38,32)],CREAM)
    elif kind=="airfields_index":
        airplane(i); i.path([(8,10),(14,10)],BLUE,2)
        i.path([(34,37),(40,37)],BRASS,2)
        i.path([(34,33),(40,33)],BRASS,2)
    elif kind=="port_air":
        # Airplane profile above an unmistakable ship hull with a wake.
        i.path([(8,35),(14,36),(21,35),(28,36),(35,35),(41,36)],BLUE,2.5)
        i.poly([(10,28),(37,28),(33,34),(16,34)],TEAL)
        i.rect((19,25,29,28),CREAM)
        i.path([(13,28),(36,28)],CREAM,1.4)
        i.poly([(8,16),(24,16),(20,10),(23,10),(29,16),(39,16),(39,18),(28,20),
                (23,25),(20,25),(23,20),(10,20)],BRASS)
    elif kind=="waterworks":
        i.poly([(24,8),(33,21),(35,27),(33,34),(28,38),(20,38),(15,34),(13,27),(15,21)],TEAL_DARK)
        i.path([(24,8),(33,21),(35,27),(33,34),(28,38),(20,38),(15,34),(13,27),(15,21),(24,8)],BLUE,2)
        for y in (26,31): i.path([(18,y),(23,y-2),(29,y),(32,y-1)],CREAM,1.7)
    elif kind=="harbor_ops":
        i.path([(8,15),(25,13),(37,22),(33,32),(19,34)],BLUE,2.5)
        for x,y in ((8,15),(25,13),(37,22),(19,34)):
            i.oval((x-2.4,y-2.4,x+2.4,y+2.4),BRASS)
        i.poly([(14,23),(28,23),(25,28),(17,28)],CREAM)
        i.rect((18,19,24,23),TEAL)
    elif kind=="railworks":
        tracks(i,31)
        i.path([(9,16),(39,16)],SLATE,5)
        i.path([(9,16),(33,16)],TEAL,1.5)
        for x in (11,21,31): i.path([(x,21),(x+6,11)],CREAM,2)
    elif kind=="rail_engineering":
        tracks(i,35)
        wrench(i,(12,27),(31,17))
    elif kind=="rail_signals":
        for x,h in ((16,22),(31,15)):
            i.path([(x,h),(x,36)],SLATE,3)
            i.round((x-5,h-6,x+5,h+7),2,INK,CREAM,1)
            light(i,x,h,BRASS if x==16 else TEAL)
        i.path([(8,37),(40,37)],BRASS,2)
    elif kind=="rail_ops":
        i.round((10,11,38,36),3,SLATE_DARK,CREAM,1.6)
        i.path([(15,29),(15,21),(26,21),(26,16),(32,16)],BLUE,2.2)
        i.path([(21,21),(21,27),(33,27)],BRASS,2.2)
        for x,y in ((15,29),(32,16),(33,27)): i.oval((x-2,y-2,x+2,y+2),TEAL)
    elif kind=="rail_pieces":
        for p in ((9,13,22,13),(27,12,38,20),(10,24,21,36),(30,26,30,38)):
            x,y,u,v=p; i.path([(x,y),(u,v)],SLATE,6); i.path([(x,y),(u,v)],CREAM,1.45)
    elif kind=="rail_types":
        tracks(i,32,8,39)
        i.path([(9,18),(39,18)],TEAL,2.0)
        for x in (11,36): i.path([(x,18),(x,30)],TEAL,1.7)
        i.poly([(26,9),(18,22),(23,22),(21,29),(31,17),(25,17)],BRASS)
    elif kind=="rail_freight":
        tracks(i,35)
        for x,c in ((9,TEAL_DARK),(26,SLATE)):
            i.rect((x,17,x+13,29),c,CREAM,1.25)
            i.path([(x+3,20),(x+10,26)],BRASS,2)
            i.oval((x+2,28,x+5,32),INK); i.oval((x+9,28,x+12,32),INK)
    elif kind=="bus_stops":
        i.path([(14,14),(14,36)],BRASS,2.2)
        i.path([(32,19),(32,36)],BRASS,2.2)
        for x,y in ((14,15),(32,20)):
            i.round((x-6,y-5,x+6,y+5),2,TEAL,CREAM,1.2)
            i.path([(x-3,y),(x+3,y)],GLASS,2)
        i.path([(8,37),(40,37)],CREAM,2)
    else: raise ValueError(kind)

def area_icon(i, kind):
    grid=[(8,28),(24,20),(40,28),(24,37),(8,28)]
    i.poly(grid, SLATE_DARK if kind=="clear_area" else TEAL_DARK)
    i.path(grid,CREAM,2)
    i.path([(16,24),(32,33)],TEAL,1.8)
    i.path([(16,33),(32,24)],TEAL,1.8)
    if kind=="clear_area":
        i.poly([(20,12),(27,11),(31,16),(28,24),(17,26),(13,22)],BRICK)
        i.path([(20,13),(29,20)],CREAM,2)
    elif kind=="raise_area":
        arrow(i,(16,24),(16,11),BRASS); arrow(i,(32,24),(32,11),CREAM)
    else:
        arrow(i,(16,11),(16,24),BRASS); arrow(i,(32,11),(32,24),CREAM)

def playback(i, kind):
    if kind=="pause":
        for x in (15,27): i.round((x,11,x+6,37),1.4,BRASS)
    elif kind=="normal_speed":
        i.poly([(16,10),(16,38),(37,24)],TEAL)
        i.path([(16,10),(16,38)],CREAM,2)
    else:
        for x in (9,24): i.poly([(x,12),(x,36),(x+16,24)],CREAM if x==24 else BRASS)

def bridge_mode(i, kind):
    if kind=="rail_tunnel":
        i.poly([(6,33),(11,19),(19,10),(29,12),(40,23),(42,33)],SLATE)
        i.path([(14,32),(14,26),(18,20),(30,20),(34,26),(34,32)],CREAM,3.0)
        i.poly([(16,33),(18,25),(30,25),(33,33)],INK)
        for k in (19,29): i.path([(24+(k-24)*.55,27),(k,39)],BRASS,2.0)
        i.path([(19,34),(29,34)],CREAM,1.1)
    else:
        i.path([(8,27),(40,27)],SLATE if kind=="rail_bridge_picker" else BRASS,4)
        i.path([(8,38),(16,27),(24,38),(32,27),(40,38)],TEAL,2)
        if kind=="road_bridge_picker":
            i.path([(8,22),(40,22)],CREAM,3)
            i.path([(12,22),(18,22)],INK,1.25)
            i.path([(24,22),(30,22)],INK,1.25)
            plus(i)
        elif kind=="rail_bridge_picker":
            tracks(i,21); plus(i)
        elif kind=="rail_span_bridge":
            for x in (13,23,33):
                i.path([(x,27),(x,38)],BRASS,3)
            tracks(i,19)
        elif kind=="rail_span_clear":
            i.path([(8,21),(22,21)],CREAM,3)
            cross(i)
        else:
            tracks(i,24)
            train(i,11,12,TEAL)

def remove_fitting(i, kind):
    if kind in {"ship_remove","ship_clear"}:
        waves(i)
        if kind=="ship_remove":
            i.path([(8,17),(29,17),(37,23)],CREAM,3.4)
            for x in (14,24,32): i.path([(x,20),(x,32)],BRASS,2.6)
        else:
            i.poly([(9,25),(38,25),(32,33),(15,33)],TEAL)
            i.rect((15,19,29,25),CREAM)
            i.rect((20,13,25,19),SLATE)
    elif kind in {"airfield_remove","airfield_clear"}:
        if kind=="airfield_clear":
            airplane(i,22,25)
        else:
            i.path([(11,37),(30,16)],SLATE,9)
            i.path([(11,37),(30,16)],CREAM,1.6)
            i.path([(10,34),(14,38)],BRASS,1.6)
    elif kind=="rail_signal_remove":
        i.path([(17,24),(17,38)],SLATE,3)
        i.round((11,12,23,28),2,INK,CREAM,1.1)
        light(i,17,17,BRASS); light(i,17,23,TEAL)
    elif kind=="rail_piece_remove":
        tracks(i,29,9,39)
        i.path([(12,15),(29,32)],BRICK,3)
    elif kind=="rail_clear_run":
        tracks(i,33,8,40); train(i,8,21,SLATE,23)
    else: raise ValueError(kind)
    cross(i)

def rotate_fitting(i, kind):
    if kind=="ship_rotate":
        waves(i,36)
        i.poly([(10,27),(29,27),(34,31),(32,35),(14,35)],CREAM)
        i.path([(10,22),(14,15),(24,12),(34,17)],BRASS,2.7)
        i.poly([(37,21),(27,18),(35,12)],BRASS)
    elif kind=="rail_rotate":
        i.path([(13,20),(20,12),(29,12),(34,16)],BRASS,2.7)
        i.poly([(39,19),(30,17),(36,11)],CREAM)
        tracks(i,32)
    else:
        i.rect((10,14,38,19),SLATE)
        i.rect((10,30,38,35),TEAL_DARK,TEAL,1.1)
        arrow(i,(11,24),(37,24),CREAM,True)
        for x in (16,24,32): i.oval((x-1.6,32-1.6,x+1.6,32+1.6),BRASS)

def rail_variant(i, kind):
    if kind=="rail_auto":
        tracks(i,31)
        i.path([(10,30),(19,27),(24,22),(24,15)],TEAL,2.2)
        for x,y,n in ((32,16,6),(14,13,4)):
            i.poly([(x,y-n),(x+2,y-2),(x+n,y),(x+2,y+2),(x,y+n),(x-2,y+2),(x-n,y),(x-2,y-2)],BRASS)
    elif kind=="rail_depot":
        i.poly([(8,22),(24,9),(40,22),(40,34),(8,34)],SLATE)
        i.path([(8,22),(24,9),(40,22)],CREAM,2.9)
        i.round((16,21,32,36),2,INK,BRASS,1.4)
        i.path([(18,29),(15,40)],TEAL,2)
        i.path([(30,29),(33,40)],TEAL,2)
    elif kind=="rail_order_one":
        train(i,12,13,TEAL)
        arrow(i,(10,32),(38,32),BRASS)
    elif kind=="rail_shuttle":
        train(i,12,13,BRASS)
        arrow(i,(10,32),(38,32),CREAM,True)
    elif kind=="rail_pair":
        train(i,8,12,TEAL); train(i,16,23,BRASS)
    elif kind=="block_signal":
        i.path([(24,16),(24,37)],SLATE,4)
        i.round((15,11,33,27),2,INK,CREAM,1.2)
        light(i,24,19,BRICK)
        i.path([(17,37),(31,37)],BRASS,2.5)
    elif kind=="rail_order_block":
        i.path([(33,13),(33,37)],SLATE,3)
        light(i,33,15,BRASS)
        tracks(i,36,8,37)
        train(i,8,21,TEAL,22)
    elif kind=="rail_electrify":
        tracks(i,34,8,40)
        i.poly([(25,8),(14,24),(23,24),(19,36),(34,17),(25,17),(29,8)],BRASS)
    elif kind=="rail_deelectrify":
        tracks(i,34,8,40)
        i.path([(10,14),(38,14)],TEAL,2)
        i.path([(13,14),(13,27)],TEAL,2)
        i.path([(35,14),(35,27)],TEAL,2)
        i.path([(15,9),(33,25)],BRICK,4)
    else: raise ValueError(kind)

def cargo(i, kind, x=21, y=18):
    if kind=="coal":
        i.poly([(x-9,y+7),(x-6,y-1),(x-2,y-3),(x+1,y-1),
                (x+4,y-7),(x+9,y-3),(x+10,y+7)],SLATE)
        i.path([(x-8,y+5),(x-4,y),(x+1,y+3),(x+5,y-2),(x+8,y+4)],CREAM,1.25)
    elif kind=="goods":
        i.rect((x-8,y-6,x+8,y+7),BRASS)
        i.path([(x-7,y-5),(x+7,y+6)],SLATE_DARK,2)
        i.path([(x+7,y-5),(x-7,y+6)],SLATE_DARK,2)
        i.path([(x-8,y-6),(x+8,y-6)],CREAM,1.2)
    elif kind=="oil":
        i.poly([(x,y-8),(x+6,y),(x+8,y+4),(x+6,y+8),(x,y+10),
                (x-6,y+8),(x-8,y+4),(x-6,y)],BLUE)
        i.path([(x-5,y+3),(x-4,y+6),(x,y+8)],CREAM,1.5)

def cargo_tool(i, kind, action):
    i.path([(9,30),(39,30)],TEAL,3)
    tracks(i,36,8,40)
    if action=="load":
        cargo(i,kind,16,20)
        arrow(i,(32,12),(32,26),CREAM)
    else:
        cargo(i,kind,31,20)
        arrow(i,(16,26),(16,12),BRASS)

def transit(i,kind):
    if kind=="ship_coal_order":
        waves(i,37)
        i.poly([(8,25),(39,25),(34,34),(15,34)],TEAL)
        i.rect((28,20,36,25),CREAM)
        cargo(i,"coal",19,19)
        i.path([(9,26),(37,26)],BRASS,1.7)
    elif kind in ("tram_order","tram_clear"):
        delta=-3 if kind=="tram_order" else 3
        i.round((13+delta,18,35+delta,32),3,TEAL,CREAM,1.4)
        i.rect((16+delta,21,32+delta,25),GLASS)
        i.path([(17+delta,28),(31+delta,28)],BRASS,1.7)
        i.path([(20+delta,17),(26+delta,11),(30+delta,17)],CREAM,1.5)
        tracks(i,36,9,40)
        if kind=="tram_order":
            arrow(i,(31,13),(39,13),BRASS)
        else:
            i.path([(30,15),(39,24)],BRICK,3.2)
            i.path([(39,15),(30,24)],BRICK,3.2)
    elif kind=="truck_stop":
        i.path([(8,35),(40,35)],CREAM,2.5)
        i.rect((11,19,27,30),TEAL)
        i.poly([(27,22),(34,22),(38,27),(38,30),(27,30)],BRASS)
        i.rect((30,23,34,26),GLASS)
        for x in (16,32): i.oval((x-3,28,x+3,34),INK,SLATE,1)
        i.path([(9,18),(9,14),(26,14)],CREAM,2)
    elif kind=="bus_terminus":
        i.path([(8,34),(8,13),(39,13),(39,34),(8,34)],TEAL,2.5)
        i.path([(24,13),(24,34)],TEAL,1.5)
        for x,c in ((11,BRASS),(27,TEAL)):
            i.round((x,18,x+10,31),2,c)
            i.rect((x+1.5,20,x+8.5,24),GLASS)
            i.path([(x+2,27),(x+8,27)],CREAM,1.3)
        i.path([(12,38),(37,38)],BRASS,1.7)
    else: raise ValueError(kind)

# Use default arguments rather than close over the last loop variable.
for draw, names in (
    (category, "survey_map roadworks fleet_garage company_index navigation_compass settings_menu "
        "workbenches road_tools structure_index tramways harbor_index airfields_index port_air waterworks "
        "harbor_ops railworks rail_engineering rail_signals rail_ops rail_pieces rail_types rail_freight bus_stops"),
    (area_icon, "raise_area lower_area clear_area"),
    (playback, "pause normal_speed fast_forward"),
    (bridge_mode, "road_bridge_picker rail_bridge_picker rail_span_bridge rail_tunnel rail_span_clear rail_order_span"),
    (remove_fitting, "ship_remove ship_clear airfield_remove airfield_clear rail_signal_remove rail_piece_remove rail_clear_run"),
    (rotate_fitting, "ship_rotate rail_rotate coal_flip"),
    (rail_variant, "rail_auto rail_depot rail_order_one rail_shuttle rail_pair block_signal rail_order_block rail_electrify rail_deelectrify"),
    (transit, "ship_coal_order truck_stop bus_terminus tram_order tram_clear"),
):
    for name in names.split():
        ART[name] = lambda i, n=name, painter=draw: painter(i,n)
for kind in ("coal","goods","oil"):
    for action in ("load","unload"):
        ART[kind+"_"+action] = lambda i, c=kind, a=action: cargo_tool(i,c,a)

def order_icon(i, done):
    # Two route points and a finish check are separate from construction.
    i.path([(11,33),(19,33),(19,17),(34,17)],TEAL,3)
    i.oval((8,29,16,37),CREAM)
    i.oval((31,13,39,21),BRASS)
    if done:
        i.path([(21,29),(26,35),(39,25)],BRASS,3.5)
    else:
        i.path([(29,26),(29,37)],CREAM,2.7)
        i.path([(24,31.5),(34,31.5)],CREAM,2.7)

ART["order_stop"] = lambda i: order_icon(i, False)
ART["order_done"] = lambda i: order_icon(i, True)

def ship_buoy(i, remove):
    i.path([(7,37),(15,36),(22,38),(30,38),(39,36)],BLUE,2)
    i.poly([(13,27),(35,27),(32,34),(17,34)],BRASS)
    i.path([(24,13),(24,28)],CREAM,3)
    i.round((16,10,32,17),1.4,TEAL_DARK,BRASS,1.5)
    if remove: i.path([(31,21),(41,21)],BRICK,3)
    else: i.path([(35,17),(35,25)],CREAM,1.8); i.path([(31,21),(39,21)],CREAM,1.8)

ART["ship_buoy"] = lambda i: ship_buoy(i, False)
ART["ship_buoy_remove"] = lambda i: ship_buoy(i, True)

def rail_waypoint(i, style):
    # Track direction markers, rather than a stop canopy or signal lamp.
    tracks(i,35,8,40)
    i.path([(24,13),(24,34)],SLATE,2.5)
    i.round((11,10,37,27),2,TEAL_DARK,TEAL,1.5)
    i.path([(15,14),(19,23),(23,16),(27,23),(32,14)],CREAM,1.9)
    if style=="menu":
        i.oval((34,27,42,35),BRASS)
    elif style=="remove":
        i.path([(24,34),(39,34)],BRICK,3.5)
    else:
        i.path([(33,28),(40,28),(40,36)],BRASS,2)

ART["rail_waypoints"] = lambda i: rail_waypoint(i, "menu")
ART["rail_waypoint"] = lambda i: rail_waypoint(i, "place")
ART["rail_waypoint_remove"] = lambda i: rail_waypoint(i, "remove")

def teleport_tile(i):
    # A tile and rising beam, deliberately unlike the folded Jump Map.
    diamond=[(8,33),(24,25),(40,33),(24,41),(8,33)]
    i.poly(diamond,TEAL_DARK)
    i.path(diamond,CREAM,2)
    i.path([(13,25),(13,14)],BLUE,1.8)
    i.path([(35,14),(35,25)],BLUE,1.8)
    arrow(i,(24,31),(24,9),BRASS)

ART["teleport_tile"] = teleport_tile

def review(icons, target):
    sheet=Image.new("RGB",(712,162*((len(icons)+3)//4)),"#101d26")
    d=ImageDraw.Draw(sheet)
    font=ImageFont.load_default(size=14)
    for idx,(name,icon) in enumerate(icons.items()):
        x,y=(idx%4)*178,(idx//4)*162
        d.rounded_rectangle((x+10,y+11,x+168,y+151),radius=9,fill="#203440")
        enlarged=icon.resize((84,84),Image.Resampling.LANCZOS)
        sheet.paste(enlarged,(x+23,y+29),enlarged)
        tiny=icon.resize((32,32),Image.Resampling.LANCZOS)
        sheet.paste(tiny,(x+122,y+58),tiny)
        d.text((x+23,y+119),name.upper(),font=font,fill=CREAM)
    sheet.save(target)

def save_hotbar_legend(target):
    # Fixed-pixel HUD plate, centered above the engine hotbar.
    base=Image.new("RGBA",(640,72))
    draw=ImageDraw.Draw(base)
    draw.rounded_rectangle((1,1,638,70),radius=9,fill=(14,29,39,224),outline=(80,107,115,230))
    draw.line((17,5,622,5),fill=(165,136,87,208),width=1)
    base.save(target,optimize=True)

def main():
    cli=argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--review",type=Path)
    args=cli.parse_args()
    icons={}
    for name,draw in ART.items():
        icon=Icon()
        icon.frame()
        draw(icon)
        image=icon.flatten()
        assert image.mode=="RGBA" and image.size==(48,48)
        assert image.getpixel((0,0))[3]==image.getpixel((47,47))[3]==0
        assert image.getpixel((24,24))[3]==255
        path=OUT/f"bl_dispatch_{name}.png"
        image.save(path,optimize=True)
        icons[name]=image
    assert len({im.tobytes() for im in icons.values()})==len(ART)
    save_hotbar_legend(OUT/"bl_hotbar_legend.png")
    if args.review:
        review(icons,args.review)
    print(f"PASS: {len(icons)} distinct 48×48 hotbar icons with transparent corner margins")

if __name__=="__main__":
    main()

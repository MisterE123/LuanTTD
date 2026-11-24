#!/usr/bin/env python3
"""Model the original temperate wildlife pack. Run via Blender's Python.

blender -b -t 3 --python-exit-code 1 --python tools/build_wildlife_art.py
Set LUANTTD_WILDLIFE_REVIEW=/absolute/file.png for an optional lit model sheet.
The engine uses ten OBJ units per node; +Y up, +Z forward.
"""
# SPDX-License-Identifier: GPL-2.0-only
import os
from math import cos, pi, sin, sqrt
from pathlib import Path
from struct import pack
from zlib import compress, crc32

import bmesh
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / "mods" / "luanttd_core"
PALETTE = {
    "whale_slate": "364c5e", "whale_storm": "263b4b", "whale_sea": "405d70",
    "whale_faded": "597789", "whale_belly": "c5ced0", "whale_throat": "9baeb6",
    "whale_lip": "223846", "whale_knuckle": "6d8b9c",
    "porpoise_cap": "314654", "porpoise_side": "708d9a", "porpoise_flank": "8da5ab",
    "porpoise_belly": "d7e0da", "porpoise_fin": "415968",
    "brine": "132730", "glint": "eaf3ee",
    "gull_snow": "f7f3df", "gull_cream": "dedfd3", "gull_shadow": "b9c2c0",
    "gull_gray": "82929a", "gull_gray_lit": "aab8bb", "gull_dark": "313840",
    "gull_dark_lit": "495763", "gull_yellow": "e7ab43", "gull_coral": "b95e49",
    "eagle_soot": "3c2b24", "eagle_tail": "e3ddca", "eagle_feather": "573e2f",
    "eagle_flight": "2f2723", "eagle_down": "83664e", "eagle_shoulder": "75583f",
    "eagle_head": "f5eed4", "eagle_bill": "dbab49", "eagle_iris": "ead984",
    "fox_russet": "a34b2a", "fox_ginger": "c36735", "fox_gold": "d38042",
    "fox_cinnamon": "8b492e", "fox_cream": "eadcc0", "fox_neck": "c7ae8e",
    "fox_socks": "342b2b", "fox_ears": "533a36", "fox_eye": "b58b45",
    "charcoal": "2e2728",
}
SWATCH = {name: i for i, name in enumerate(PALETTE)}
COLS, ROWS, CELL = 8, 8, 16

def atlas_path():
    return MOD / "textures" / "bl_wildlife_atlas.png"

def texcoord(key):
    i = SWATCH[key]
    return ((i % COLS + .5) / COLS, 1 - (i // COLS + .5) / ROWS)

def make_atlas():
    def chunk(kind, data):
        return pack("!I", len(data)) + kind + data + pack("!I", crc32(kind+data)&0xffffffff)
    values = [bytes.fromhex(x) for x in PALETTE.values()]
    values += [values[0]]*(COLS*ROWS-len(values))
    raw = bytearray()
    for y in range(ROWS*CELL):
        raw += b"\0"
        for x in range(COLS*CELL):
            base = values[(y//CELL)*COLS+x//CELL]
            # A subtle brushed stipple, shared between all vertices in a
            # face swatch. Its center square matches the planned pigment.
            bias = ((x*41+y*29+(x*y)%13)%9)-4
            raw += bytes(max(0,min(255,b+(bias if x%CELL in (4,5,10,11) else 0))) for b in base)
    atlas_path().write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR",pack("!IIBBBBB",COLS*CELL,ROWS*CELL,8,2,0,0,0))
        + chunk(b"IDAT",compress(bytes(raw),9)) + chunk(b"IEND",b""))

def vadd(a,b):
    return tuple(x+y for x,y in zip(a,b))

def unit(v):
    n=sqrt(sum(x*x for x in v))
    return tuple(x/n for x in v)

def cross(a,b):
    return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])

def rotate_x(p, angle, origin=(0,0,0)):
    x,y,z=(a-b for a,b in zip(p,origin)); c,s=cos(angle),sin(angle)
    return vadd((x,y*c-z*s,y*s+z*c),origin)

def flap(p, angle, side, pivot):
    x,y,z=p; dx=x-side*pivot
    c,s=cos(angle),sin(angle)*side
    return (side*pivot+dx*c-y*s,dx*s+y*c,z)

class Work:
    def __init__(self):
        self.parts=[]
    def add(self, name, points, faces, paint, smooth=True):
        self.parts.append((name,points,faces,paint,smooth))
    def closed(self,name,rings,paint,n=12,smooth=True):
        verts=[p for ring in rings for p in ring]
        faces=[tuple(range(n-1,-1,-1))]
        for r in range(len(rings)-1):
            for k in range(n):
                a=r*n+k;b=r*n+(k+1)%n
                faces.append((a,b,b+n,a+n))
        faces.append(tuple(range((len(rings)-1)*n,len(rings)*n)))
        colors=[]
        for i,f in enumerate(faces):
            p=tuple(sum(verts[k][j] for k in f)/len(f) for j in range(3))
            colors.append(paint(p, i//n, ((i-1)%n+.5)*2*pi/n) if callable(paint) else paint)
        self.add(name, verts, faces, colors, smooth)
    def hull(self,name,profile,col,n=14):
        # Each station is (Z, center Y, horizontal radius, vertical radius).
        rings=[[(w*cos(2*pi*i/n),cy+h*sin(2*pi*i/n),z) for i in range(n)] for z,cy,w,h in profile]
        self.closed(name,rings,col,n)
    def ball(self,name,center,dim,color,n=12):
        x,y,z=center;w,h,d=dim
        self.hull_at(name,(x,y,z),w,h,d,color,n)
    def hull_at(self,name,centre,w,h,d,color,n):
        x,y,z=centre
        rings=[]
        for f in (-1.56,-1.16,-.75,-.35,0,.35,.75,1.16,1.56):
            rings.append([(x+w*cos(f)*cos(2*pi*i/n),y+h*cos(f)*sin(2*pi*i/n),z+d*sin(f)) for i in range(n)])
        self.closed(name,rings,color,n)
    def tube(self,name,stations,colors,n=8):
        # Swept tapered limbs, jaw lines, carpal feathers and talons.
        rings=[]
        for i,(centre,r1,r2) in enumerate(stations):
            diff=tuple(x-y for x,y in zip(stations[min(i+1,len(stations)-1)][0],stations[max(i-1,0)][0]))
            axis=unit(diff)
            ref=(1,0,0) if abs(axis[0])<.85 else (0,1,0)
            first=unit(cross(axis,ref)); second=cross(axis,first)
            rings.append([tuple(centre[j]+r1*cos(2*pi*k/n)*first[j]+r2*sin(2*pi*k/n)*second[j]
                           for j in range(3)) for k in range(n)])
        def paint(p,i,a):
            return colors[min(i,len(colors)-1)] if isinstance(colors,tuple) else colors
        self.closed(name,rings,paint,n)
    def foil(self,name,rows,paint,n=10,transform=lambda p:p):
        # Stations across either wing, fin or fluke with a nonzero
        # airfoil thickness and tapered angled tips.
        rings=[]
        for x,y,front,back,th in rows:
            ring=[]
            for k in range(n):
                a=k*2*pi/n
                q=(1+cos(a))*.5
                ring.append(transform((x,y+th*sin(a)*(.6+.4*q),back+(front-back)*q)))
            rings.append(ring)
        self.closed(name,rings,paint,n)
    def ray(self,name,pts,front,back):
        # Solid triangle/quad for a small brow or patch of fur.
        n=len(pts)
        upper=[(x,y,z+.018) for x,y,z in pts]
        lower=[(x,y,z-.012) for x,y,z in pts]
        self.add(name,upper+lower,[tuple(range(n)),tuple(range(2*n-1,n-1,-1))]
                  +[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],
                  [front,back]+[front]*n,False)

def whale():
    m=Work()
    def skin(p,i,a):
        h=sin(a)
        if h<-.60 and p[2]>-10:return "whale_belly" if h<-.83 else "whale_throat"
        if h>.62:return "whale_storm"
        return "whale_slate" if h>.04 else "whale_sea"
    m.hull("Long streamlined humpback body and domed rostrum",[
        (-18.2,-.83,.34,.42),(-16.4,-.85,.64,.56),(-13,-1.14,1.25,1.08),
        (-9.3,-1.22,2.1,1.67),(-6.05,-1.28,3.02,2.31),(-2,-1.50,3.73,2.74),
        (2.2,-1.48,4.10,2.94),(6.5,-1.27,4.08,2.87),(9.9,-1.02,3.76,2.41),
        (12.3,-.69,3.10,1.73),(14.17,-.40,2.30,1.14),(15.53,-.31,1.45,.62),
        (16.5,-.32,.49,.33),(16.72,-.36,.13,.11)],skin,20)
    for s in (-1,1):
        m.foil("Long mottled pectoral flipper",[
            (s*2.69,-2.06,6.0,2.2,.31),(s*4.75,-2.60,5.95,2.70,.32),
            (s*6.75,-3.13,5.50,3.11,.23),(s*8.55,-3.79,4.98,3.16,.14),
            (s*10.24,-4.29,3.98,3.23,.09),(s*11.06,-4.51,3.52,3.36,.025)],
            lambda p,i,a: "whale_storm" if sin(a)>.3 else
              ("whale_faded" if (i+round(2*a))%4==0 else "whale_belly"),12)
        for i,(x,y,z) in enumerate(((4.3,-2.48,5.85),(5.47,-2.78,5.62),(6.74,-3.11,5.35),
                                     (8.02,-3.54,5.05),(9.05,-3.87,4.70))):
            m.ball("Humpback leading-edge tubercle",(s*x,y,z),(.23,.10,.24-i*.023),"whale_knuckle",8)
        m.foil("Distinct broad, notched caudal fluke",[
            (s*.08,-.82,-17.2,-21.2,.28),(s*1.96,-.77,-17.46,-22.18,.27),
            (s*4.11,-.65,-17.99,-22.55,.21),(s*6.01,-.43,-18.80,-22.15,.13),
            (s*7.55,-.06,-19.75,-21.38,.08),(s*8.51,.14,-20.48,-20.68,.025)],
            lambda p,i,a: "whale_storm" if sin(a)>.5 else "whale_slate" if sin(a)>0 else
              ("whale_belly" if i<=4 else "whale_faded"),12)
        m.tube("Curved lip seam",[
            ((s*3.97,-1.05,7.6),.044,.029),((s*3.68,-1.20,10.1),.065,.048),
            ((s*2.63,-1.02,13.5),.058,.038),((s*1.22,-.78,15.85),.040,.025)],
            "whale_lip")
        m.ball("Small set-in cetacean eye",(s*3.94,-.12,8.85),(.105,.195,.238),"brine",9)
        m.ball("Warm eye reflection",(s*4.026,-.065,8.914),(.024,.043,.052),"whale_faded",7)
    for x,z,h in ((0,15.6,.24),(-.54,15.24,.30),(.54,15.24,.30),(-1.24,14.63,.46),
                  (1.24,14.63,.46),(-.62,14.3,.53),(.62,14.3,.53),(0,14.9,.42),(0,13.9,.72)):
        m.ball("Rounded rostral tubercle",(x,h,z),(.22,.12,.23),"whale_faded",8)
    for j in range(-5,6):
        x=j*.375
        m.tube("Pleated ventral groove",[
            ((x*.72,-2.30+abs(x)*.16,11.1),.045,.043),
            ((x,-3.24+abs(x)*.14,8.0),.062,.039),
            ((x*1.2,-4.34+abs(x)*.16,3.3),.053,.038),
            ((x*1.07,-4.11+abs(x)*.18,-1.15),.027,.024)],
            "whale_throat",6)
    # Sweep a small sickle high above the rolling caudal peduncle.
    m.tube("Hooked humpback dorsal fin",[
        ((0,.02,-6.1),.46,1.75),((0,.77,-6.75),.41,1.38),
        ((0,1.76,-7.20),.27,.87),((0,2.46,-7.85),.15,.43),
        ((0,2.66,-8.46),.035,.13)],("whale_slate","whale_storm"),10)
    for x in (-.21,.21):
        m.ball("Paired arched blowholes",(x,1.80,8.25),(.14,.05,.31),"whale_lip",8)
    return m

def porpoise():
    m=Work()
    def skin(p,i,a):
        return ("porpoise_cap" if sin(a)>.35 else
                "porpoise_belly" if sin(a)<-.48 else ("porpoise_side" if i%3 else "porpoise_flank"))
    m.hull("Rounded forehead, blunt snout and tubby grey body",[
        (-4.49,-.26,.13,.13),(-3.64,-.33,.235,.23),(-2.7,-.47,.53,.46),
        (-1.63,-.45,.89,.76),(-.25,-.46,1.08,.88),
        (1.16,-.43,1.10,.91),(2.44,-.43,.99,.77),(3.39,-.46,.78,.59),
        (4.14,-.47,.54,.40),(4.6,-.49,.345,.22),(4.82,-.47,.106,.10)],skin,16)
    m.tube("Low triangular porpoise dorsal fin",[
        ((0,.23,-.47),.17,.79),((0,.59,-.72),.14,.61),((0,.99,-.96),.075,.34),
        ((0,1.31,-1.16),.015,.083)],"porpoise_fin",10)
    for s in (-1,1):
        m.foil("Short dark tapered flipper",[
            (s*.70,-.70,2.0,.57,.115),(s*1.22,-1.09,1.68,.20,.092),
            (s*1.64,-1.42,1.21,.19,.061),(s*2.05,-1.65,.49,.32,.023)],
            lambda p,i,a:"porpoise_fin" if sin(a)>.13 else "porpoise_side")
        m.foil("Twin notched porpoise fluke",[
            (s*.016,-.28,-4.36,-5.0,.095),(s*.42,-.27,-4.28,-5.28,.10),
            (s*1.04,-.24,-4.44,-5.46,.071),(s*1.69,-.13,-4.78,-5.39,.043),
            (s*2.03,-.079,-5.09,-5.15,.014)],"porpoise_cap")
        m.tube("Short blunt mouth line",[
            ((s*.72,-.60,3.50),.029,.021),((s*.52,-.64,4.19),.024,.015),
            ((s*.22,-.62,4.71),.016,.01)],"brine")
        m.ball("Small dark eye",(s*.865,-.271,2.97),(.058,.092,.114),"brine",8)
        m.ball("Eye spark",(s*.916,-.242,3.004),(.018,.023,.030),"glint",8)
    m.ball("Single crescent breath opening",(0,.476,1.67),(.18,.039,.091),"porpoise_fin",9)
    return m

def bird(eagle=False,angle=0):
    m=Work()
    if eagle:
        dark,midtone,shade,light,white,head,bill = ("eagle_flight","eagle_feather","eagle_down","eagle_shoulder",
                                                    "eagle_tail","eagle_head","eagle_bill")
        scale=1.47
    else:
        dark,midtone,shade,light,white,head,bill = ("gull_dark","gull_gray","gull_shadow","gull_gray_lit",
                                                    "gull_cream","gull_snow","gull_yellow")
        scale=1
    def shell(p,i,a):
        if sin(a)>.27:return midtone if sin(a)>.6 else light
        return shade if eagle else head if sin(a)<-.2 else white
    m.hull("Deep chest, narrow shoulders and swept rump",[(scale*z,cy*scale,w*scale,h*scale) for z,cy,w,h in (
        (-1.14,-.06,.12,.14),(-.89,-.04,.29,.29),(-.56,-.05,.438,.38),
        (-.19,-.06,.52,.458),(.23,-.078,.49,.48),(.56,-.04,.388,.416),
        (.87,.045,.272,.31),(1.08,.129,.187,.215))],shell,14)
    m.ball("Pale rounded head and feathered neck",(0,.249*scale,1.16*scale),(.278*scale,.282*scale,.42*scale),head,12)
    for s in (-1,1):
        m.ball("Iris and tight dark lid",(s*.246*scale,.301*scale,1.315*scale),
               (.049*scale,.072*scale,.085*scale),dark,8)
        m.ball("Clear light iris",(s*.286*scale,.305*scale,1.33*scale),
               (.022*scale,.051*scale,.048*scale),"eagle_iris" if eagle else bill,8)
        m.ball("Deep-set pupil",(s*.305*scale,.31*scale,1.348*scale),
               (.014*scale,.030*scale,.026*scale),"brine",8)
    if eagle:
        m.hull("Hooked golden beak",[(2.01,.14,.165,.138),(2.27,.13,.207,.174),(2.49,.047,.157,.166),
                (2.64,-.099,.105,.124),(2.65,-.198,.066,.058),(2.632,-.237,.021,.026)],bill,12)
        for s in (-1,1):
            m.ball("Brow of pale forehead feathers",(s*.305,.49,2.016),(.098,.087,.217),head,8)
            m.ball("Naris on hooked beak",(s*.17,.19,2.36),(.036,.027,.069),"eagle_soot",8)
    else:
        m.hull("Tapered yellow gull bill",[(1.38,.169,.128,.094),(1.61,.168,.122,.09),
            (1.83,.157,.079,.067),(1.98,.136,.050,.058),(2.01,.119,.023,.027)],bill,10)
        for s in (-1,1):
            m.ball("Small red mark on lower bill",(s*.072,.125,1.82),(.018,.028,.061),"gull_coral",8)
    for s in (-1,1):
        wing=lambda p: flap(p,angle,s,.30*scale)
        rows=[(.26,.035,.61,-.76,.11),(.69,.124,.70,-.73,.145),
              (1.15,.16,.64,-.75,.13),(1.63,.14,.49,-.94,.11),
              (2.05,.13,.23,-1.13,.078),(2.46,.14,.019,-1.25,.058),
              (2.80,.176,-.35,-1.23,.034),(3.21,.23,-.72,-.99,.018),
              (3.53,.28,-1.07,-1.11,.004)]
        if eagle:
            rows.extend(((3.75,.32,-1.26,-1.29,.005),))
        m.foil("Tapered cambered airfoil from shoulder to tip",
            [(s*x*scale,y*scale,f*scale,b*scale,t*scale) for x,y,f,b,t in rows],
            lambda p,i,a: (dark if i>=6 else (midtone if sin(a)>.52 else light)) if sin(a)>.14 else shade,
            12, wing)
        # Rounded notches and separately modeled flight feathers remain
        # recognizable against sky, not just a solid triangular wing.
        count=9 if eagle else 7
        for j in range(count):
            frac=j/(count-1)
            root=(.73+frac*2.26)*scale
            start=(s*root, (.12+.08*frac)*scale,(-.15-.43*frac)*scale)
            mid=(s*(root+.23*scale),(.113+.076*frac)*scale,(-.55-.54*frac)*scale)
            end=(s*(root+(.12+.38*frac)*scale),(.073+.195*frac)*scale,
                 (-1.02-.34*sin(frac*pi*.94)-.39*frac)*scale)
            dye=(light if j%3==0 else midtone, dark if j>=3 or eagle else midtone,
                 dark if j>=2 or eagle else light)
            m.tube("Individual broad primary feather" if eagle else "Feathered dark wingtip",
                   [(wing((start[0],start[1]-.035*scale,start[2])),.061*scale,.109*scale),
                    (wing((mid[0],mid[1]-.048*scale,mid[2])),.039*scale,.081*scale),
                    (wing((end[0],end[1]-.018*scale,end[2])),.010*scale,.018*scale)],dye,8)
        for i in range(3):
            root=s*(.64+i*.28)*scale
            m.tube("Small overlapping shoulder coverts",[(wing((root,.235*scale,.38*scale)),.11,.05),
                   (wing((root+s*.16*scale,.240*scale,-.02*scale)),.093,.067),
                   (wing((root+s*.27*scale,.228*scale,-.36*scale)),.031,.025)],
                   (light,midtone),8)
        leg1=(s*.176*scale,-.35*scale,-.23*scale)
        leg2=(s*.204*scale,-.50*scale,-.52*scale)
        m.tube("Tucked yellow legs",[(leg1,.064,.054),(leg2,.042,.05)],bill,8)
        for j in (-1,0,1):
            m.tube("Three tucked toes with terminal claw",[(leg2,.025,.026),
                   ((leg2[0]+j*.058*scale,-.547*scale,-.70*scale),.021,.019),
                   ((leg2[0]+j*.072*scale,-.537*scale,-.83*scale),.008,.01)],
                   (bill,bill,dark),7)
    for i in range(-3,4):
        m.tube("Layered tail fan",[
            ((i*.062*scale,-.01*scale,-.90*scale),.043*scale,.096*scale),
            ((i*.10*scale,-.047*scale,-1.37*scale),.038*scale,.099*scale),
            ((i*.148*scale,-.072*scale,(-1.79+abs(i)*.05)*scale),.016*scale,.067*scale)],
            (white,head,white),8)
    return m

def fox(stride=False):
    m=Work()
    def fur(p,i,a):
        if sin(a)<-.44:return "fox_neck" if p[2]<.35 else "fox_cream"
        return "fox_russet" if sin(a)>.60 else "fox_gold" if -0.05<sin(a)<.32 else "fox_ginger"
    m.hull("Lean red fox torso with high shoulder and slim waist",[
        (-2.05,2.26,.31,.43),(-1.74,2.28,.54,.66),(-1.20,2.25,.66,.74),
        (-.57,2.22,.59,.64),(.03,2.26,.55,.61),(.49,2.31,.63,.72),
        (.99,2.46,.64,.79),(1.42,2.56,.52,.62),(1.74,2.63,.30,.36)],fur,14)
    m.hull("Angular wedge-shaped head and narrow forward muzzle",[
        (1.10,2.77,.37,.41),(1.49,2.94,.46,.49),(1.86,3.02,.51,.51),
        (2.11,2.99,.47,.38),(2.36,2.91,.34,.25),(2.68,2.79,.235,.16),
        (2.98,2.765,.137,.109),(3.08,2.77,.099,.078)],
        lambda p,i,a:"fox_cream" if sin(a)<-.08 else "fox_cinnamon" if p[2]>2.38 else "fox_ginger",14)
    m.ball("Black nose leather",(0,2.797,3.058),(.149,.112,.125),"charcoal",10)
    for s in (-1,1):
        m.ray("Upright pointed ear with dark outer rim",
            [(s*.19,3.25,1.48),(s*.50,3.35,1.60),(s*.516,4.08,1.45),
             (s*.368,3.91,1.50)],"fox_ears","fox_russet")
        m.ray("Warm inner ear triangle",[(s*.237,3.39,1.63),(s*.47,3.43,1.651),(s*.500,3.97,1.55)],
                "fox_neck","fox_russet")
        m.ball("Dark narrow rim around fox eye",(s*.405,3.047,2.258),(.077,.087,.14),"charcoal",9)
        m.ball("Amber fox iris",(s*.456,3.059,2.295),(.037,.063,.077),"fox_eye",8)
        m.ball("Vertical dark fox pupil",(s*.486,3.059,2.316),(.019,.043,.022),"charcoal",7)
        # Each leg has genuine bent hock, lower black stocking and paw;
        # the stride variant is compatible with the intact base silhouette.
        for front in (False,True):
            root=.91 if front else -1.43
            phase=s*(-1 if front else 1)
            swing=phase*.44 if stride else (.08 if s>0 else -.08)
            lift=.12 if stride and phase>0 else 0
            elev=2.57 if front else 2.38
            joints=[((s*.46,elev,root),.20,.245),
                    ((s*.504,1.76,root+(.08 if front else -.22)+swing*.4),.166,.187),
                    ((s*.494,.95,root+(-.11 if front else -.37)+swing*.72),.108,.108),
                    ((s*.49,.19+lift,root+(.13 if front else -.015)+swing),.083,.084)]
            m.tube("Bent foreleg and elbow" if front else "Digitigrade rear leg and hock",
                   joints,("fox_russet","fox_ginger","fox_cinnamon","fox_socks"),10)
            m.ball("Black oval paw",(s*.49,.13+lift,root+(.24 if front else .10)+swing),(.134,.13,.209),
                   "fox_socks",10)
    reach=(.24 if stride else 0)
    m.tube("Full white-tipped fox brush",[
        ((0,2.28,-1.65),.256,.262),((.11,2.12,-2.18),.37,.33),
        ((.28+reach*.35,1.96,-2.83),.523,.48),((.49+reach*.6,1.99,-3.49),.525,.48),
        ((.66+reach,2.11,-4.08),.441,.405),((.80+reach,2.29,-4.46),.324,.295),
        ((.92+reach,2.39,-4.80),.194,.166),((1.0+reach,2.44,-5.00),.041,.041)],
        ("fox_russet","fox_russet","fox_russet","fox_russet","fox_russet","fox_cream","fox_cream","fox_cream"),16)
    return m

def material():
    material=bpy.data.materials.new("Original temperate wildlife coloration | textured atlas")
    material.use_nodes=True
    nodes=material.node_tree.nodes
    image=nodes.new("ShaderNodeTexImage")
    image.image=bpy.data.images.load(str(atlas_path()))
    image.image.pack()
    image.image.filepath="//../mods/luanttd_core/textures/bl_wildlife_atlas.png"
    image.interpolation="Closest"
    bsdf=nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value=.74
    material.node_tree.links.new(image.outputs["Color"],bsdf.inputs["Base Color"])
    return material

def to_blender(v):
    x,y,z=v
    return x,-z,y

def to_obj(v):
    x,y,z=v
    return -x,z,-y

def authored_variant(name,work,mat,export=True):
    col=bpy.data.collections.new(name.replace("_"," ").title())
    bpy.context.scene.collection.children.link(col)
    stored=[]
    for label,points,faces,colors,smooth in work.parts:
        mesh=bpy.data.meshes.new(label)
        mesh.from_pydata([to_blender(v) for v in points],[],faces)
        mesh.update()
        # Compare the normals to a geometric outside, regardless of
        # whether the species row is mirrored or follows a bent sweep.
        bm=bmesh.new()
        bm.from_mesh(mesh)
        bmesh.ops.recalc_face_normals(bm,faces=bm.faces[:])
        bm.to_mesh(mesh);bm.free()
        mesh.update()
        obj=bpy.data.objects.new(label,mesh)
        col.objects.link(obj)
        mesh.materials.append(mat)
        uv=mesh.uv_layers.new(name="Swatch coordinates")
        for p,color in zip(mesh.polygons,colors):
            p.use_smooth=smooth
            for loop in p.loop_indices:
                uv.data[loop].uv=texcoord(color)
        stored.append((label,mesh,colors,smooth))
    if export:
        out=["# Original LuanTTD wildlife, authored in Blender; +Y up and +Z forward.",
            "# Ten OBJ units per Luanti node. Packed source: art/wildlife.blend."]
        # They share one opaque atlas in the native entity. OBJ groups
        # otherwise become separate buffers in the Luanti mesh loader.
        # Preserve editorial parts in the Blender collection and comments.
        out.append("g Wildlife")
        out.extend("vt %.7f %.7f" % texcoord(key) for key in PALETTE)
        vbase=nbase=0
        for label,mesh,colors,smooth in stored:
            out.append("# part "+label.replace(" ","_"))
            out.extend("v %.5f %.5f %.5f" % to_obj(v.co) for v in mesh.vertices)
            normals=[v.normal for v in mesh.vertices] if smooth else [p.normal for p in mesh.polygons]
            out.extend("vn %.6f %.6f %.6f" % to_obj(v) for v in normals)
            for poly,color in zip(mesh.polygons,colors):
                indices=list(poly.vertices)[::-1] # reflection to match Luanti OBJ facing
                out.append("f "+" ".join(f"{vbase+i+1}/{SWATCH[color]+1}/{nbase+(i if smooth else poly.index)+1}" for i in indices))
            vbase+=len(mesh.vertices);nbase+=len(normals)
        (MOD / "models" / f"bl_wildlife_{name}.obj").write_text("\n".join(out)+"\n")
    return col

def showcase(collections):
    scene=bpy.context.scene
    # A scale-normalized studio sheet. Instances do not change source or exported scale.
    review=bpy.data.collections.new("Review sheet | normalized display scale")
    scene.collection.children.link(review)
    panels=(("whale",(-5.8,3.2,0),.22),("porpoise",(4.9,3.2,0),.74),
            ("seagull",(-7.2,-3.2,0),.80),("eagle",(-.2,-3.2,0),.55),("fox",(8.15,-3.9,0),.68))
    for name,loc,scale in panels:
        inst=bpy.data.objects.new(name.title()+" | review",None)
        inst.instance_type="COLLECTION";inst.instance_collection=collections[name]
        inst.location=loc;inst.scale=(scale,)*3;inst.rotation_euler.z=.46 if name=="fox" else -.60
        review.objects.link(inst)
    for col in collections.values():
        scene.collection.children.unlink(col)
        col.use_fake_user=True
    bpy.ops.object.camera_add(location=(.15,-15,25))
    cam=bpy.context.object;cam.name="Review sheet camera"
    cam.rotation_euler=(Vector((.1,0,.1))-cam.location).to_track_quat("-Z","Y").to_euler()
    cam.data.type="ORTHO";cam.data.ortho_scale=25.0;scene.camera=cam
    for loc,power,size in (((-8,0,13),2900,14),((6,-3,10),1600,13),((2,8,15),2300,11)):
        bpy.ops.object.light_add(type="AREA",location=loc)
        light=bpy.context.object;light.data.energy=power;light.data.shape="DISK";light.data.size=size
        light.rotation_euler=(-light.location).to_track_quat("-Z","Y").to_euler()
    scene.world=bpy.data.worlds.new("Temperate review studio")
    scene.world.color=(.115,.139,.164)
    scene.render.engine="CYCLES"
    scene.cycles.samples=36
    scene.cycles.use_denoising=False
    scene.render.resolution_x=1250;scene.render.resolution_y=695;scene.render.resolution_percentage=100
    scene.view_settings.view_transform="Standard"
    # Source mode starts with the areas left editable in scene-only collections.
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":
                view=area.spaces.active
                view.shading.type="MATERIAL"
                view.region_3d.view_distance=29
                view.region_3d.view_rotation=cam.rotation_euler.to_quaternion()

def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    make_atlas()
    mat=material()
    poses={"whale":whale(),"porpoise":porpoise(),"seagull":bird(),"eagle":bird(True),
           "fox":fox(),"seagull_wing_up":bird(angle=.48),"seagull_wing_down":bird(angle=-.38),
           "eagle_wing_up":bird(True,.43),"eagle_wing_down":bird(True,-.33),"fox_stride":fox(True)}
    cols={name:authored_variant(name,work,mat) for name,work in poses.items()}
    showcase(cols)
    # An explicit editable animal scene alongside the scale-normalized render.
    scene=bpy.data.scenes.new("Workshop | originals, runtime scale")
    for name,col in cols.items():
        # The source collection remains genuine, not a flattened export.
        if name in ("whale","porpoise","seagull","eagle","fox"):
            scene.collection.children.link(col)
    info=bpy.data.texts.new("WILDLIFE | source guide")
    info.write("Original stylized temperate animals modeled by build_wildlife_art.py.\n"
               "All geometry and packed painted atlas are editable.\n"
               "Use the Workshop scene and isolate a species collection; named parts can be edited independently.\n"
               "Rest and alternate wing/stride collections are kept in the data-block library.\n"
               "Cetacean Y=0 is intended waterline, fox Y=0 is the standing contact, birds origin at torso.\n"
               "Blender uses Z up and negative Y forward. Engine export reflects X and uses +Z forward.\n"
               "No third-party art or photography was imported.\n")
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art"/"wildlife.blend"),compress=True)
    if output:=os.environ.get("LUANTTD_WILDLIFE_REVIEW"):
        bpy.context.scene.render.filepath=output
        bpy.ops.render.render(write_still=True)

if __name__=="__main__":
    main()

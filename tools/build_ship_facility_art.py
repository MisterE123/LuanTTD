#!/usr/bin/env python3
"""Original stock-footprint harbour art for LuanTTD. No imported OpenTTD art.

blender -b -t 4 --python-exit-code 1 --python tools/build_ship_facility_art.py
SHIP_FACILITY_RENDER=/tmp/ship-facilities.png blender -b -t 4 --python tools/build_ship_facility_art.py

The mesh overlay origin is the north-west even cell at base+1. Geometry
is in native node units relative to height .5 above ground stock base
and the two-node tile center. The seaward direction of the seed is +Z.
"""
from math import cos, sin, pi
from pathlib import Path
import os
import struct
import sys
import zlib

import bpy
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_rail_art as rail

PALETTE = {
    "Stone foundation":"818581", "Cut harbour granite":"a1a198", "Dressed granite edge":"b2b4a8",
    "Weathered timber":"896b4e", "Wet timber":"625347", "Front plank":"ae926d",
    "Sun-bleached plank":"ac9678", "Warm plank":"9d7f5d", "Grey plank":"8c826e",
    "Blackened marine hardware":"414b4c", "Cast steel":"68756e", "Dull brass":"ab9367",
    "Rope fender":"9e8c64", "Fender rubber":"3e4643", "White enamel":"e7d7ae",
    "Sign dark":"34534e", "Harbour green":"486e61", "Harbour trim":"678178",
    "Lamp warm":"edc47e", "Roof slate":"617178", "Roof dark":"48595f",
    "Roof flashing":"829397", "Glazing frame":"4c6263", "Glass blue":"73969c",
    "Glazing glint":"a2b8b4", "Dark glazing":"586a6f", "Fired brick":"a36b51",
    "Brick dark":"865b4c", "Brick bright":"ba7d59", "Mortar":"847770",
    "Soot under eave":"494d48", "Wet inspection deck":"6d7c77", "Hazard yellow":"c79b59",
    "Galvanised gray":"84908a", "Grassy grade":"57814c",
}
P={k:i for i,k in enumerate(PALETTE)}
rail.COLORS[:]=PALETTE.values()
WIDTH,HEIGHT=512,64
GRASS=(4,4,32)
ATLAS_NAME="bl_ship_facilities_atlas.png"
HALF_RAMP=.335
PIER_DECK=.180
DECK_UNDER=.124
DEPOT_HALF=.520  # physically unobstructed transverse channel at vessel height
DEPOT_CLEAR=1.200


def as_point(h):
    return h if callable(h) else lambda x,z:h


def prism(m,n,c,poly,start,end,top=None,no_endcaps=()):
    if rail.signed_area(poly)<0:
        poly=poly[::-1]
    lo,hi=as_point(start),as_point(end)
    a,b=([(x,z,h(x,z)) for x,z in poly] for h in (lo,hi))
    m.face(n,P[c],a[::-1]);m.face(n,P[top or c],b)
    for i in range(len(a)):
        j=(i+1)%len(a)
        if abs(a[i][1]-a[j][1])<1e-8 and any(abs(a[i][1]-e)<1e-8 for e in no_endcaps):
            continue
        m.face(n,P[c],(a[i],a[j],b[j],b[i]))


def quad(x,z,w,l,bevel=0):
    a,b=x-w/2,x+w/2
    c,d=z-l/2,z+l/2
    u=max(0,min(bevel,w/3,l/3))
    if u==0:return [(a,c),(b,c),(b,d),(a,d)]
    return [(a+u,c),(b-u,c),(b,c+u),(b,d-u),(b-u,d),(a+u,d),(a,d-u),(a,c+u)]


def box(m,n,c,x,z,w,l,low,high,ch=0,top=None,no_endcaps=()):
    prism(m,n,c,quad(x,z,w,l,ch),low,high,top,no_endcaps)


def tube(m,n,c,a,b,ra,rb=None,N=12):
    # Arbitrary-axis tube for railings, marine cleats, ropes and lamps;
    # use local x/z/elevation coordinates throughout.
    va,vb=Vector(a),Vector(b)
    axis=(vb-va).normalized()
    reference=Vector((0,0,1)) if abs(axis.z)<.85 else Vector((1,0,0))
    u=axis.cross(reference).normalized()
    v=axis.cross(u).normalized()
    rb=ra if rb is None else rb
    def ring(center,r):
        return [tuple(center+r*(u*cos(i*2*pi/N)+v*sin(i*2*pi/N))) for i in range(N)]
    lo,hi=ring(va,ra),ring(vb,rb)
    m.face(n,P[c],lo[::-1]);m.face(n,P[c],hi)
    for i in range(N):
        j=(i+1)%N
        m.face(n,P[c],(lo[i],lo[j],hi[j],hi[i]))


def turn(m,quarter):
    out=rail.Mesh(rail.terrain_height(0))
    for name,faces in m.parts.items():
        for ids,col in faces:
            out.face(name,col,[((x,z,h),(-z,x,h),(-x,-z,h),(z,-x,h))[quarter]
                               for x,z,h in (m.vertices[name][i] for i in ids)])
    return out


def slope(x,z): return (1-z)/2


def ramp_height(x,z):
    # Seamless footway at the landward and waterward edges. Never floats
    # arbitrarily above or cuts an extra land block into the real slope.
    return slope(x,z)+.011+(PIER_DECK-.011)*(z+1)/2


def strips(m,kind,w,z0,z1,height,N=18,thickness=.014):
    for j in range(N):
        a=z0+(z1-z0)*j/N
        b=z0+(z1-z0)*(j+1)/N
        if j>0:a+=.002
        if j<N-1:b-=.002
        col=("Warm plank","Sun-bleached plank","Grey plank","Front plank","Weathered timber")[(j*17+5)%5]
        box(m,kind,col,0,(a+b)/2,w,b-a,lambda x,z:height(x,z)-thickness,height,
            no_endcaps=(-1,1))


def gangway():
    m=rail.Mesh(rail.terrain_height(0))
    land=[(-1,-1,1),(1,-1,1),(1,1,0),(-1,1,0)]
    m.face("Shared corner ground",P["Grassy grade"],land)
    box(m,"Paired timber gangway stringer","Wet timber",0,0,2*HALF_RAMP,2,
        lambda x,z:max(slope(x,z)-.008,ramp_height(x,z)-(PIER_DECK-DECK_UNDER)),
        lambda x,z:ramp_height(x,z)-.006,no_endcaps=(1,))
    strips(m,"Staggered non-slip footway boards",2*HALF_RAMP,-1,1,ramp_height,21,.010)
    # Low dressed sill where the actual timber meets the level inland tile.
    box(m,"Landward quiet granite threshold","Cut harbour granite",0,-.943,.740,.114,
        lambda x,z:slope(x,z)-.010,lambda x,z:slope(x,z)+.007,.004)
    for x in (-.338,.338):
        box(m,"Side gangway running boards","Weathered timber",x,0,.043,2,
            lambda x,z:max(slope(x,z),ramp_height(x,z)-.037),
            lambda x,z:ramp_height(x,z)+.006,no_endcaps=(1,))
        for z in (-.894,-.518,-.141,.238,.608,.929):
            h=ramp_height(x,z)
            box(m,"Morticed hardwood uprights","Weathered timber",x,z,.041,.042,h-.008,h+.260,.006)
            box(m,"Blackened strap joins","Blackened marine hardware",x,z,.043,.041,
                h+.197,h+.222,.004)
        for level in (.139,.251):
            box(m,"Timber gangway handrails","Front plank",x,.042,.034,1.916,
                lambda x,z:ramp_height(x,z)+level-.014,lambda x,z:ramp_height(x,z)+level+.014,
                no_endcaps=(1,))
    # Dressed finish in the waterward end against the stone bank, entirely
    # below the actual deck and inside this tile's gangway footprint.
    box(m,"Shore landing tie and abutment","Stone foundation",0,.917,.723,.166,
        .004,lambda x,z:ramp_height(x,z)-.059,.011)
    lamp_x=.467
    box(m,"Slope lantern stone base","Cut harbour granite",lamp_x,-.780,.075,.072,
        slope(0,-.78),slope(0,-.78)+.073,.007)
    tube(m,"Green casthouse lantern post","Harbour green",
         (lamp_x,-.780,slope(0,-.78)+.040),
         (lamp_x,-.780,slope(0,-.78)+.424),.014,.011,10)
    h=slope(0,-.78)+.397
    box(m,"Landward lantern glazing","Lamp warm",lamp_x,-.78,.069,.067,h,h+.071,.007)
    box(m,"Landward lantern cap","Blackened marine hardware",lamp_x,-.78,.086,.081,h+.064,h+.087,.008)
    return m


def bollard(m,x,z,deck=PIER_DECK):
    box(m,"Cast mooring bollard feet","Blackened marine hardware",x,z,.075,.063,deck,deck+.016,.008)
    tube(m,"Mooring horn posts","Cast steel",(x,z,deck+.011),(x,z,deck+.103),.022,.019,12)
    tube(m,"Mooring horn arms","Blackened marine hardware",
         (x-.030,z,deck+.093),(x+.030,z,deck+.093),.016,.014,12)


def iron_lamp(m,x,z,base,h):
    tube(m,"Riveted pier lamp pole","Harbour green",(x,z,base),(x,z,h),.014,.010,14)
    box(m,"Pier lamp warm glazing","Lamp warm",x,z,.070,.067,h-.007,h+.065,.010)
    box(m,"Pier lamp metal roof","Blackened marine hardware",x,z,.083,.080,h+.059,h+.082,.009)


def dock_pier():
    m=rail.Mesh(rail.terrain_height(0))
    outline=[(-HALF_RAMP,-1),(HALF_RAMP,-1),(.335,-.79),(.475,-.598),(.475,.854),
             (.433,.913),(-.433,.913),(-.475,.854),(-.475,-.598),(-.335,-.79)]
    prism(m,"Joined wharf decking and edge stringer","Wet timber",outline,DECK_UNDER,PIER_DECK-.011,
          "Weathered timber",(-1,))
    for i in range(21):
        z0=-1+i*1.909/21+.002*(i!=0)
        z1=-1+(i+1)*1.909/21-.002*(i!=20)
        z=(z0+z1)/2
        side=max(.335,min(.470,.335+(z+.790)*.73,.470-(z-.850)*.35 if z>.85 else .470))
        col=("Warm plank","Sun-bleached plank","Grey plank","Front plank","Weathered timber")[(i*13)%5]
        box(m,"Individually laid harbour planks",col,0,z,2*side,z1-z0,
            PIER_DECK-.011,PIER_DECK,no_endcaps=(-1,))
    # Tide-facing battered piles and dark marine fenders.
    for z in (-.740,-.227,.326,.818):
        for x in (-.393,.393):
            tube(m,"Pressure-driven main wharf piles","Wet timber",(x,z,-.642),(x,z,.195),.051,.044,12)
            tube(m,"Capped piling core","Front plank",(x,z,.190),(x,z,.218),.046,.039,12)
            if abs(z)<.65:
                tube(m,"Twin piling cross braces","Weathered timber",
                     (x,z-.12,-.389),(x,z+.141,.106),.022,None,8)
            tube(m,"Grey wharf fender ring","Fender rubber",
                 (x+.047*(1 if x>0 else -1),z,-.116),
                 (x+.047*(1 if x>0 else -1),z,.091),.027,.025,10)
    for x in (-.338,.338):
        for z in (-.455,.155,.598,.827):
            bollard(m,x,z)
        for z in (-.966,-.800):
            box(m,"Lead-on guard post","Weathered timber",x,z,.042,.042,.170,.439,.006)
        for h in (.319,.431):
            box(m,"Joined landing handrails","Front plank",x,-.889,.034,.222,h-.014,h+.014,
                no_endcaps=(-1,))
    # Tucked side shelter leaves the middle and seaward berth lip free.
    for z in (-.590,-.155):
        for x in (-.427,-.173):
            box(m,"Pier shelter cast posts","Harbour green",x,z,.027,.027,.177,.653,.004)
    box(m,"Slatted timber boarding bench","Weathered timber",-.326,-.367,.149,.364,.258,.300,.008)
    box(m,"Slatted timber boarding bench back","Warm plank",-.383,-.367,.030,.351,.332,.387,.005)
    for q in range(4):
        z=-.566+q*.129
        box(m,"Harbour shelter glazed rear","Glazing frame",-.423,z,.028,.122,.369,.591,.003)
        box(m,"Harbour shelter glazed rear","Glass blue",-.406,z,.012,.098,.387,.564,.006)
        box(m,"Harbour shelter glazed rear","Glazing glint",-.398,z-.015,.007,.017,.406,.553,.003)
    ridge=lambda x,z:.693-abs(x+.294)*.29
    for a,b in ((-.455,-.294),(-.294,-.139)):
        box(m,"Storm slatted shelter roof","Roof slate",(a+b)/2,-.359,b-a,.624,
            lambda x,z:ridge(x,z)-.031,ridge)
        for z in (-.623,-.476,-.331,-.186,-.043):
            box(m,"Standing seam shelter roof","Roof flashing",(a+b)/2,z,b-a,.015,
                ridge,lambda x,z:ridge(x,z)+.009)
    box(m,"Coastal cream shelter fascia","White enamel",-.132,-.359,.028,.639,.612,.662,.005)
    box(m,"Painted harbour timetable emblem","Sign dark",-.118,-.316,.012,.236,.566,.623,.005)
    for z in (-.390,-.350,-.310,-.270,-.230):
        box(m,"Painted enamel timetable marks","White enamel",-.110,z,.007,.014,.582,.606,.002)
    iron_lamp(m,.386,.646,.174,.633)
    iron_lamp(m,-.348,-.701,.176,.624)
    # Stern fender pilot edge and embedded ladders. No part reaches into the
    # neighboring docking tile: a real 1.817-node ferry can sit there.
    for x in (-.253,.253):
        tube(m,"Head piling oak inner fenders","Weathered timber",
             (x,.873,-.361),(x,.873,.324),.046,.038,12)
        box(m,"Head bollard cap","Blackened marine hardware",x,.871,.099,.083,.319,.355,.009)
    for x in (.222,.325):
        tube(m,"Pier head boarding ladder","Cast steel",(x,.901,-.252),
             (x,.901,.159),.012,None,8)
    for h in (-.232,-.166,-.100,-.033,.033,.100,.155):
        tube(m,"Pier head boarding ladder rungs","Cast steel",(.222,.905,h),(.325,.905,h),.009,None,8)
    return m


def depot_part():
    # Seed has open portal to -Z; +Z is an internal seam with no dividing wall.
    m=rail.Mesh(rail.terrain_height(0))
    for sign in (-1,1):
        x=sign*.687
        box(m,"Marine stone piling wall","Stone foundation",x,.046,.286,1.908,-.656,.129,.011,
            "Cut harbour granite",no_endcaps=(1,))
        box(m,"Covered service catwalk and joists","Wet inspection deck",sign*.652,.034,
            .238,1.932,.120,.209,0,"Weathered timber",no_endcaps=(1,))
        for z in (-.823,-.420,.008,.432,.853):
            box(m,"Grooved walkway tread ends","Grey plank",sign*.655,z,.222,.028,.207,.219,.004)
            tube(m,"Railing posts, sea-green iron","Harbour green",
                 (sign*.545,z,.222),(sign*.545,z,.566),.016,None,8)
            tube(m,"Railing post cap","Cast steel",(sign*.545,z,.554),(sign*.545,z,.579),.025,.021,10)
        for h in (.381,.557):
            tube(m,"Catwalk long safety bar","Harbour green",
                 (sign*.541,-.858,h),(sign*.541,1,h),.013,None,8)
        for z in (-.937,-.427,.103,.635):
            tube(m,"Submerged side wall splayed fenders","Wet timber",
                 (sign*.754,z,-.539),(sign*.774,z,.452),.036,.032,10)
            tube(m,"Depot upper side fender wraps","Fender rubber",
                 (sign*.774,z,.104),(sign*.774,z,.226),.040,.040,10)
        box(m,"Long side masonry","Fired brick",sign*.764,.074,.141,1.852,.137,1.350,0,
            no_endcaps=(1,))
        for j in range(15):
            h=.215+.073*j
            box(m,"Cement mortar side courses","Mortar",sign*.836,.073,.010,1.854,h,h+.009,
                no_endcaps=(1,))
            for k in range(7):
                if (j*19+k*11)%13>4: continue
                z=-.699+k*.241+.049*(j%2)
                box(m,"Contrasting workbrick tone","Brick bright",sign*.839,z,.006,.133,h+.013,h+.056)
        for z in (-.502,.045,.590):
            box(m,"Cut stone waterworks sill","Cut harbour granite",sign*.844,z,.071,.270,.631,.682,.006)
            box(m,"Tall depot steel casement","Harbour green",sign*.844,z,.046,.233,.674,1.049,.010)
            for dz in (-.060,.060):
                box(m,"Tall shaded depot glazing","Glass blue",sign*.875,z+dz,.018,.099,.700,1.021,.007)
                box(m,"Tall depot glazing reflections","Glazing glint",sign*.885,z+dz-.018,
                    .007,.018,.730,.974,.004)
            box(m,"Tall depot window cross frame","Harbour trim",sign*.884,z,.019,.206,.856,.883,.004)
            box(m,"Cut stone waterworks lintel","Dressed granite edge",sign*.844,z,.062,.294,1.036,1.094,.006)
        for z in (-.420,.126,.710):
            box(m,"Workshop side locker","Harbour green",sign*.681,z,.130,.190,.212,.539,.012)
        # Broad open end. Every solid at working water height is outside
        # the vessel envelope; door is genuinely retracted above the passage.
        box(m,"Dressed marine portal pier","Cut harbour granite",sign*.647,-.779,.234,.174,
            -.504,1.337,.011)
        box(m,"Painted timber door jamb","Harbour green",sign*.544,-.839,.042,.061,.174,1.277,.007)
        for z in (-.895,-.760):
            box(m,"Vertical oak portal fenders","Weathered timber",sign*.554,z,.065,.040,-.244,.638,.008)
        x=sign*.653
        box(m,"Portal quay lantern body","Blackened marine hardware",x,-.896,.086,.072,.790,.937,.010)
        box(m,"Portal quay lantern glazing","Lamp warm",x,-.933,.066,.038,.814,.908,.007)
    box(m,"Head architrave across the open dock","Dressed granite edge",0,-.774,1.523,.182,
        DEPOT_CLEAR,1.373,.011)
    box(m,"Fully raised salvage door","Harbour green",0,-.806,1.033,.061,
        DEPOT_CLEAR+.013,1.351,.008)
    for h in (1.230,1.262,1.294,1.326):
        box(m,"Raised door panel bookend","Harbour trim",0,-.843,1.022,.016,h,h+.010,.004)
    for x in (-.425,-.232,.232,.425):
        box(m,"Door vertical sap bars","Wet timber",x,-.854,.032,.012,1.214,1.337,.003)
    # Gable sign intentionally mounted ahead of the fascia, not clipped
    # into roof; the seam at +1 remains a visibly continuous roof surface.
    box(m,"Dockyard porcelain board","Blackened marine hardware",0,-.919,.428,.040,1.369,1.482,.012)
    box(m,"Dockyard porcelain board","White enamel",0,-.942,.391,.014,1.384,1.464,.009)
    for x in (-.14,-.085,-.027,.030,.089,.144):
        box(m,"Dockyard enamel raised lettering","Sign dark",x,-.952,.016,.007,1.400,1.454,.002)
        box(m,"Dockyard enamel raised lettering","Sign dark",x+.010,-.952,.022,.007,1.399,1.412,.002)
    roof_h=lambda x,z:1.354+.315*(1-abs(x)/.868)
    for a,b in ((-.725,0),(0,.725)):
        box(m,"Weatherboard gable above open portal","Harbour green",(a+b)/2,-.832,b-a,.093,1.361,
            lambda x,z:roof_h(x,z)-.006)
    box(m,"Upper gable cross timbers","Weathered timber",0,-.879,.589,.035,1.478,1.516,.003)
    box(m,"Upper gable central timber","Weathered timber",0,-.879,.040,.038,1.400,1.662,.003)
    for a,b in ((-.868,0),(0,.868)):
        box(m,"Two-piece standing seam roof","Roof slate",(a+b)/2,.017,b-a,1.966,
            roof_h,lambda x,z:roof_h(x,z)+.048,no_endcaps=(1,))
        for z in (-.912,-.708,-.504,-.296,-.088,.120,.324,.528,.732,.936):
            box(m,"Standing roof seam ribs","Roof flashing",(a+b)/2,z,b-a,.013,
                lambda x,z:roof_h(x,z)+.046,lambda x,z:roof_h(x,z)+.058)
        box(m,"Gable dark verge board","Roof dark",(a+b)/2,-.959,b-a,.042,
            lambda x,z:roof_h(x,z)-.015,lambda x,z:roof_h(x,z)+.056)
    box(m,"Continuous ridge cap","Roof flashing",0,.018,.085,1.964,
        1.685,1.727,0,no_endcaps=(1,))
    # Each half has its own small ventilation cupola. Never a full opaque
    # bulkhead in the center: the visible water channel runs through both.
    box(m,"Roof cupola foundation","Roof dark",0,.392,.387,.511,1.618,1.705,.013)
    box(m,"Roof cupola glazing frame","Harbour green",0,.392,.324,.459,1.691,1.865,.011)
    for x in (-.164,.164):
        for z in (.231,.392,.544):
            box(m,"Roof cupola blue glazing","Dark glazing",x,z,.017,.123,1.726,1.829,.006)
    for a,b in ((-.204,0),(0,.204)):
        roof=lambda x,z:1.923-.220*abs(x)
        box(m,"Cupola cap","Roof dark",(a+b)/2,.392,b-a,.529,
            lambda x,z:roof(x,z)-.035,roof)
    return m


def read_source_rgba(path):
    data=path.read_bytes()
    assert data[:8]==b"\x89PNG\r\n\x1a\n"
    pos=8;payload=[]
    while pos<len(data):
        size=struct.unpack_from(">I",data,pos)[0];kind=data[pos+4:pos+8];body=data[pos+8:pos+8+size]
        pos+=12+size
        if kind==b"IHDR":
            w,h,depth,mode,c,f,i=struct.unpack(">IIBBBBB",body)
            assert (w,h,depth,mode,c,f,i)==(32,32,8,6,0,0,0)
        if kind==b"IDAT":payload.append(body)
    raw=zlib.decompress(b"".join(payload))
    rows=[]
    prev=[0]*(w*4)
    def paeth(a,b,c):
        p=a+b-c
        da,db,dc=abs(p-a),abs(p-b),abs(p-c)
        return a if da<=db and da<=dc else b if db<=dc else c
    for y in range(h):
        flag=raw[y*(w*4+1)]
        row=list(raw[y*(w*4+1)+1:(y+1)*(w*4+1)])
        for x in range(len(row)):
            a=row[x-4] if x>=4 else 0
            b=prev[x];c=prev[x-4] if x>=4 else 0
            row[x]=(row[x]+((0,a,b,(a+b)//2,paeth(a,b,c))[flag]))&255
        rows.append([tuple(row[x:x+3]) for x in range(0,len(row),4)])
        prev=row
    return rows


def atlas():
    def chunk(tag,payload):
        return struct.pack(">I",len(payload))+tag+payload+struct.pack(">I",zlib.crc32(tag+payload))
    grass=read_source_rgba(rail.TEXTURES/"bl_grass0.png")
    palette=[bytes.fromhex(p) for p in PALETTE.values()]
    rows=[]
    x0,y0,n=GRASS
    for y in range(HEIGHT):
        row=bytearray()
        for x in range(WIDTH):
            if y>=44:
                row.extend(palette[min(x//8,len(palette)-1)])
            elif y0-3<=y<y0+n+3 and x0-3<=x<x0+n+3:
                row.extend(grass[max(0,min(n-1,y-y0))][max(0,min(n-1,x-x0))])
            else:
                row.extend(b"\x57\x81\x4c")
        rows.append(b"\0"+bytes(row))
    out=b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",WIDTH,HEIGHT,8,2,0,0,0))
    out+=chunk(b"IDAT",zlib.compress(b"".join(rows)))+chunk(b"IEND",b"")
    (rail.TEXTURES/ATLAS_NAME).write_bytes(out)


def export(mesh,path):
    # Identical north-west node transform as other architecture exports, but
    # texture varies over the slope rather than a single flat-color cell.
    text=["# Original LuanTTD ship facilities; Blender source in art/ship_facilities.blend"]
    texture=[((i*8+4)/WIDTH,.125) for i in range(len(PALETTE))]
    uvs={u:i+1 for i,u in enumerate(texture)}
    vertex_off=1
    normal_off=1
    geometry=[]
    u,v,n=GRASS
    for group,fs in mesh.parts.items():
        geometry.append("o "+group.replace(" ","_"))
        raw=mesh.vertices[group]
        points=[(-x-.5,h-.5,z+.5) for x,z,h in raw]
        geometry.extend("v %.6f %.6f %.6f"%p for p in points)
        normals=[]
        norm_index={}
        refs=[]
        for ids,c in fs:
            a,b,d=(Vector(points[i]) for i in ids)
            normal=(b-a).cross(d-a)
            if normal.length_squared<1e-16: continue
            nk=tuple(round(q,6) for q in normal.normalized())
            if nk not in norm_index:
                norm_index[nk]=len(normals)
                normals.append(nk)
            face=[]
            for i in ids:
                if c==P["Grassy grade"]:
                    x,z,_=raw[i]
                    tex=((u+.5+(n-1)*(x+1)/2)/WIDTH,1-(v+.5+(n-1)*(z+1)/2)/HEIGHT)
                    if tex not in uvs:
                        texture.append(tex);uvs[tex]=len(texture)
                    t=uvs[tex]
                else:t=c+1
                face.append(f"{vertex_off+i}/{t}/{normal_off+norm_index[nk]}")
            refs.append("f "+" ".join(face))
        geometry.extend("vn %.6f %.6f %.6f"%v for v in normals)
        geometry+=refs
        vertex_off+=len(points)
        normal_off+=len(normals)
    text.extend("vt %.7f %.7f"%t for t in texture)
    text.extend(geometry)
    path.write_text("\n".join(text)+"\n")


def terrain_material(mats):
    material=mats[P["Grassy grade"]]
    img=bpy.data.images.load(str(rail.TEXTURES/"bl_grass0.png"),check_existing=True)
    img.pack()
    shader=material.node_tree.nodes.get("Principled BSDF")
    texture=material.node_tree.nodes.new("ShaderNodeTexImage")
    texture.image=img
    texture.interpolation="Closest"
    material.node_tree.links.new(texture.outputs["Color"],shader.inputs["Base Color"])


def assign_grade_uv(collection):
    for ob in collection.objects:
        if not ob.name.startswith("Shared corner ground"):
            continue
        mesh=ob.data
        uv=mesh.uv_layers.new(name="Inherited slope ground UV")
        for loop in mesh.loops:
            p=mesh.vertices[loop.vertex_index].co
            uv.data[loop.index].uv=((1+p.x)/2,(1-p.y)/2)


def show_scene(scene,path):
    def background(name,loc,dimensions,color):
        bpy.ops.mesh.primitive_cube_add(size=1,location=loc)
        ob=bpy.context.object;ob.name=name;ob.dimensions=dimensions
        mat=bpy.data.materials.new(name)
        mat.diffuse_color=color;ob.data.materials.append(mat)
    background("Open coastal water",(0,0,-.28),(200,200,.55),(.059,.192,.284,1))
    background("Higher approach land",(-1.970,-2.007,.492),(1.990,1.980,1.0),(.16,.24,.107,1))
    sky=bpy.data.worlds.new("Coastal ambient sky")
    sky.color=(.39,.45,.52);scene.world=sky
    bpy.ops.object.light_add(type="AREA",location=(-2.1,-3.9,6.0))
    key=bpy.context.object
    key.data.energy=970
    key.data.size=5.5
    key.rotation_euler=(Vector((-.1,.6,.25))-key.location).to_track_quat("-Z","Y").to_euler()
    bpy.ops.object.camera_add(location=(7.5,-10.0,10.1))
    cam=bpy.context.object
    cam.rotation_euler=(Vector((-.1,1.10,.25))-cam.location).to_track_quat("-Z","Y").to_euler()
    cam.data.type="ORTHO";cam.data.ortho_scale=9.10;scene.camera=cam
    scene.render.engine="BLENDER_EEVEE_NEXT";scene.eevee.taa_render_samples=27
    scene.render.resolution_x=1540;scene.render.resolution_y=1150
    scene.render.resolution_percentage=100;scene.render.filepath=path
    bpy.ops.render.render(write_still=True)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene
    scene.name="LuanTTD / open harbour and two-tile stock facility kit"
    scene.view_settings.view_transform="Standard"
    mats=rail.materials()
    for k,i in P.items():
        mat=mats[i];mat.name=k
        shader=mat.node_tree.nodes.get("Principled BSDF")
        shader.inputs["Roughness"].default_value=.22 if "glass" in k.lower() else .78
        shader.inputs["Metallic"].default_value=.35 if k in ("Galvanised gray","Cast steel","Blackened marine hardware") else .02
    terrain_material(mats)
    atlas()
    ramp,pier,depot=gangway(),dock_pier(),depot_part()
    for direction,q in enumerate((1,0,3,2)):
        for name,raw,z in (("ramp",ramp,0),("pier",pier,2)):
            mesh=turn(raw,q)
            stem=f"ship_dock_{name}_{direction}"
            collection=rail.stash(mesh,mats,stem)
            if name=="ramp":assign_grade_uv(collection)
            if direction==1:rail.instance(scene,collection,-1.970,z)
            export(mesh,rail.MODELS/f"bl_{stem}.obj")
    for axis in (0,1):
        for part in (0,1):
            q=(0 if axis==1 else 3)+2*part
            mesh=turn(depot,q%4)
            stem=f"ship_depot_{axis}_{part}"
            collection=rail.stash(mesh,mats,stem)
            if axis==1:rail.instance(scene,collection,1.66,2*part-.26)
            export(mesh,rail.MODELS/f"bl_{stem}.obj")
    bpy.ops.wm.save_as_mainfile(filepath=str(rail.ROOT/"art/ship_facilities.blend"),compress=True)
    if os.getenv("SHIP_FACILITY_RENDER"):show_scene(scene,os.environ["SHIP_FACILITY_RENDER"])


if __name__=="__main__":
    main()

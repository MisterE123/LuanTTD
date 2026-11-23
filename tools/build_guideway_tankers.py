#!/usr/bin/env python3
"""Original native RC1 #60 and #92 sealed oil tanker meshes."""
# SPDX-License-Identifier: GPL-2.0-only
from math import cos, sin, pi
from pathlib import Path
import sys
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_stock_rail_f_art as F
import build_stock_x2001_art as Mono
import build_stock_lev1_art as Mag

B, D, Pipe = F.B, F.D, F.Pipe
M, R, W, J, G = F.M, F.R, F.W, F.J, F.G
FAMILIES = {
    "mono": (60, ("4d6158", "839277", "425551", "9caa91")),
    "maglev": (92, ("4b676e", "90aeab", "314952", "a9bbb8")),
}

def loft(m, name, paint, sections, height, steps=32):
    rings = [[(cos(2*pi*j/steps)*r,z,height+sin(2*pi*j/steps)*r)
              for j in range(steps)] for z,r in sections]
    for a,b in zip(rings,rings[1:]):
        for j in range(steps):
            k=(j+1)%steps
            color=paint[0 if j in range(2,14) else 1]
            F.face(m,name,color,(a[j],b[j],b[k],a[k]))
    F.face(m,name,paint[0],rings[0])
    F.face(m,name,paint[0],rings[-1][::-1])

def body(m, family):
    B(m,"Continuous spine and collision beam","Spine",0,0,.334,.86,.045,.117,.014)
    r=.150 if family=="maglev" else .142
    sections=((-0.389,.041),(-.381,.086),(-.367,.117),(-.342,r-.008),
              (-.310,r),(.310,r),(.342,r-.008),(.367,.117),(.381,.086),(.389,.041))
    loft(m,"Closed hydrocarbon vessel and dished endheads",("Tank enamel","Tank shade"),sections,.257)
    for z in (-.231,.231):
        loft(m,"Rolled retaining bands",("Band","Band"),((z-.016,r+.003),(z+.016,r+.003)),.257)
        B(m,"Ribbed saddle brace","Spine",0,z,.312,.049,.095,.174,.01)
        for x in (-.156,.156):
            B(m,"Visible maintenance saddle bolt","Bright",x,z,.011,.030,.135,.161,.002)
    for z in (-.149,.143):
        D(m,"Closed filling cover","Bright",(0,z,.415),.043,"h",-.015,.012,20)
        D(m,"Raised sealed manway hatch","Spine",(0,z,.429),.035,"h",-.006,.013,20)
        Pipe(m,"Flood guarded manway handles","Band",(-.018,z,.444),(.018,z,.444),.0035,8)
    B(m,"Nonslip maintenance running board","Spine",-.069,-.016,.055,.716,.390,.402,.003)
    for z in (-.304,-.201,-.098,.005,.108,.211,.314):
        B(m,"Cross-hatched tread cleats","Band",-.069,z,.044,.008,.402,.407,.001)
    for sign in (-1,1):
        for z in (-.345,.344):
            B(m,"Low sill overhang and access steps","Spine",sign*.123,z,.069,.064,.094,.115,.003)
        B(m,"Amber hazard strip","Reflector",sign*.169,0,.008,.677,.095,.108,.001)
        B(m,"Coupling socket at guideway height","Spine",0,sign*.448,.092,.037,.074,.115,.005)
        for i in (-1,1):
            Pipe(m,"Longitudinal access ladder stiles","Band",(i*.042,sign*.384,.167),(i*.042,sign*.373,.358),.0045,8)
        for y in (.188,.218,.248,.278,.308,.338):
            Pipe(m,"Open ladder rungs at vessel end","Bright",(-.041,sign*.385,y),(.041,sign*.385,y),.0035,8)
    # Real underbody outlet, valve body, pull rod and protected elbow.
    D(m,"Gravity sump with enclosed valve","Spine",(0,.031,.106),.029,"h",-.024,.023,16)
    Pipe(m,"Drain manifold swivel joint","Band",(0,.031,.091),(.063,.031,.091),.009,10)
    Pipe(m,"Sealed unloading pipe","Spine",(.063,.031,.091),(.106,.041,.11),.010,10)
    D(m,"Service handwheel","Reflector",(.104,.041,.112),.014,"x",-.005,.006,14)
    for sign in (-1,1):
        marker=[(sign*.152,-.052,.251),(sign*.152,0,.304),(sign*.152,.052,.251),(sign*.152,0,.198)]
        F.face(m,"Diamond load indicator with enamel edge","Reflector",marker if sign<0 else marker[::-1])
        B(m,"Embossed drop profile","Spine",sign*.154,0,.006,.019,.237,.271,.003)

def make(family, spec):
    id,paint=spec
    keys=("Tank enamel","Bright","Spine","Band")
    palette=dict(zip(keys,paint)) | {"Tank shade":"3b4748","Reflector":"e49747","Review ballast":"5f665b"}
    gear=F.make_mesh()
    if family=="mono":
        Mono.setup()
        for z in Mono.LOCKS: Mono.bogie(gear,57,z)
        lookup=list(Mono.PALETTE)
        gear_palette=Mono.PALETTE
    else:
        Mag.prepare()
        for z in Mag.PIVOTS: Mag.truck(gear,z)
        lookup=list(Mag.PALETTE)
        gear_palette=Mag.PALETTE
    for _,faces in gear.parts.items():
        for _,col in faces:
            color=lookup[col]
            palette[color]=gear_palette[color]
    fmap={n:i for i,n in enumerate(palette)}
    F.P=M.P=J.P=W.P=G.P=fmap
    M.PAL=palette
    R.COLORS[:]=palette.values()
    m=F.make_mesh()
    body(m,family)
    combined=F.make_mesh()
    for group,faces in m.parts.items():
        for face,col in faces:
            combined.face(group,col,[m.vertices[group][i] for i in face])
    native_gear=F.make_mesh()
    for group,faces in gear.parts.items():
        for face,col in faces:
            points=[gear.vertices[group][i] for i in face]
            native_gear.face(group,fmap[lookup[col]],points)
            combined.face(group,fmap[lookup[col]],points)
    stem="rail_"+family+"_oil_tanker"
    for suffix,mesh in (("_body",m),("",combined)):
        R.export_obj(R.MODELS/f"bl_{stem}{suffix}.obj",W.local_obj(mesh),generator=Path(__file__).name)
    F.atlas(stem,list(palette.values()))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    sc=bpy.context.scene;sc.name=f"LuanTTD | {family} Oil Tanker #{id}"
    sc["Provenance"]=f"OpenTTD 16.0-RC1 stock trailer #{id}; original native closed tank, ladder, service manifold and chassis."
    sc["Placement"]="The host projects the family-specific guideway suspension and each independent drawbar."
    mats=M.colors()
    J.geometry(sc,"Pressure vessel, ladder, valves and mounting socket",m,mats)
    J.geometry(sc,"Independent native guideway carriers",native_gear,mats)
    F.render(sc,stem,None,center=.212)

if __name__=="__main__":
    for family,spec in FAMILIES.items():
        make(family,spec)

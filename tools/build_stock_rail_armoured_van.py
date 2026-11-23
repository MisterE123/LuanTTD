#!/usr/bin/env python3
"""Original closed steel RC1 #37 conventional Armoured Van (one stock sprite set)."""
from math import pi, cos, sin
from pathlib import Path
import os
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_stock_rail_metals_art as M
from build_stock_rail_metals_art import B,T,bar,J,r,w,bpy,V
ROOT = Path(__file__).resolve().parents[1]
STEM = "rail_armoured_van"

def palette():
    p = M.setup(35)
    p.update({
        "Mineral enamel navy":"225187","Mineral top milled rim blue":"5b88aa",
        "Mineral weathered highlight":"3e6b9b","Well inner soot":"162e4b",
        "Mineral steep metal pan":"23405e","Original wagon stencil straw":"bac3a6",
        "Original wagon stencil background":"202e47","Guide iron":"535e67",
        "Cold rolled coil edge":"858b88","Cold rolled shaded rim":"424a59",
        "Deep chassis iron":"20252c","Warm bauxite buffer beam":"353e4a",
    })
    r.COLORS[:]=p.values()
    return p

def shell(o):
    # Single closed heat-formed roof/side silhouette, beveled corners and
    # cropped end plating, inspired by the blue single-sprite secure van.
    body = "Fully enclosed rolled armour cabin"
    profile=[(-.205,.202),(.205,.202),(.210,.245),(.205,.428),
             (.187,.460),(.153,.492),(.106,.508),(-.106,.508),
             (-.153,.492),(-.187,.460),(-.205,.428),(-.210,.245)]
    end=[(x*.955,.213+(h-.202)*.982) for x,h in profile]
    rings=[[(x,z,h) for x,h in section] for z,section in ((-.407,end),(-.383,profile),(.383,profile),(.407,end))]
    M.f(o,body,"Mineral steep metal pan",rings[0])
    tint=("Well inner soot","Mineral steep metal pan","Mineral enamel navy",
          "Mineral weathered highlight","Mineral top milled rim blue","Mineral weathered highlight","Mineral top milled rim blue")
    for a,b in zip(rings,rings[1:]):
        for i in range(len(a)):
            j=(i+1)%len(a)
            M.f(o,body,tint[min(i,len(a)-i)],(a[j],a[i],b[i],b[j]))
    M.f(o,body,"Mineral steep metal pan",rings[-1][::-1])
    for s in (-1,1):
        # Prominent steel frame, central double secure door, external clamp.
        B(o,"Recessed side door slot","Well inner soot",s*.205,0,.015,.231,.229,.430,.008)
        for a in (-1,1):
            z=a*.052
            B(o,"Rolled and sealed steel armoured door leaves","Cold rolled shaded rim",s*.216,z,.016,.097,.237,.418,.005)
            B(o,"Raised armoured door leaf skins","Mineral steep metal pan",s*.223,z,.005,.086,.246,.411,.004)
            for h in (.268,.323,.389):
                B(o,"Short forged door hinge straps","Guide iron",s*.228,z+a*.042,.011,.023,h-.005,h+.005,.002)
                T(o,"Visible door hinge pins","Cold rolled coil edge",(s*.235,z+a*.048,h),.004,"h",-.008,.008,8)
        B(o,"Door registration guard along side of van","Well inner soot",s*.224,0,.027,.024,.284,.383,.004)
        T(o,"Original star-shaped six sided secure lock guard","Cold rolled coil edge",(s*.240,0,.332),.015,"x",-.003,.003,6)
        T(o,"Black key recess as a separate disk","Well inner soot",(s*.244,0,.332),.007,"x",-.001,.001,10)
        B(o,"Inboard loading foot rest","Guide iron",s*.221,0,.031,.235,.197,.210,.003)
        for z in (-.344,-.226,-.133,.133,.226,.344):
            bar(o,"Vertical hot riveted outer armour channel","Mineral weathered highlight",
               (s*.211,z,.221),(s*.209,z,.417),.014,.019)
            for h in (.237,.286,.345,.390):
                T(o,"Tiny independent round headed rivets along armour channels",
                  "Mineral top milled rim blue",(s*.218,z,h),.0044,"x",-.002,.002,7)
        bar(o,"Rounded continuous roof drainage flashing","Mineral top milled rim blue",
           (s*.199,-.372,.438),(s*.199,.372,.438),.013,.016)
        bar(o,"Dark splash apron under rolled long edge","Well inner soot",
           (s*.210,-.388,.221),(s*.210,.388,.221),.012,.022)
        B(o,"Original plain marker for valuable freight","Original wagon stencil background",s*.213,.272,.008,.083,.348,.386,.004)
        for j in range(3):
            B(o,"Small distinct embossed armour badge","Original wagon stencil straw",s*.218,.251+j*.020,.003,.009,.359,.376,.001)
        # End access hardware stays entirely behind the gauge envelope.
        z=s*.409
        B(o,"Strengthened welded end-plate end cheeks","Mineral enamel navy",0,z,.289,.013,.259,.424,.009)
        for x in (-.142,.142):
            bar(o,"Short handhold on solid end","Guide iron",(x,z,.259),(x,z,.330),.008,.015)
            for h in (.348,.394):
                T(o,"Staggered end-plate rivets","Mineral weathered highlight",(x,z,h),.005,"z",-.005,.005,8)
        B(o,"End slip step","Deep chassis iron",0,s*.420,.205,.036,.206,.224,.004)
        for x in (-.097,.097):
            B(o,"Small rear roof detail pads","Mineral steep metal pan",x,s*.312,.028,.047,.503,.515,.005)
            for j in range(3):
                B(o,"Weathered vents represented by three independent raised stamps","Well inner soot",
                  x,s*.312+j*.009-.009,.018,.003,.514,.517,.001)

def main():
    p = palette()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    sc=bpy.context.scene
    sc.name="LuanTTD • Armoured Van #37"
    sc["stock"]="OpenTTD 16.0-RC1 #37, fixed sprite base 2777, 20 bags of Valuables, 30 t tare"
    sc["native"]="8 stock length units; .424 gauge; standard 1.00 node coupler spacing"
    mats=r.materials()
    for name,mat in zip(p,mats): mat.name=name
    gear=M.m();M.underframe(gear,False)
    body=M.m();shell(body)
    J.geometry(sc,"01 • Standard rolling stock frame and couplers",gear,mats)
    compartment=J.geometry(sc,"02 • Original closed armoured bodywork and secure hardware",body,mats)
    combined=M.m();M.underframe(combined,False);shell(combined)
    path=ROOT/"mods/luanttd_core/models"/f"bl_{STEM}.obj"
    r.export_obj(path,w.local_obj(combined))
    path.write_text("# Original Armoured Van, RC1 #37; tools/build_stock_rail_armoured_van.py\n"+path.read_text().split("\n",1)[1])
    M.palette(ROOT/"mods/luanttd_core/textures"/f"bl_{STEM}_atlas.png",p)
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":
                v=area.spaces.active;v.shading.color_type="MATERIAL"
                v.region_3d.view_location=V((0,0,.26));v.region_3d.view_distance=1.75
                v.region_3d.view_rotation=V((.76,-.82,.61)).to_track_quat("Z","Y")
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art"/f"{STEM}.blend"),compress=True)
    if "METALS_REVIEW" in os.environ:
        temp=bpy.data.collections.new("Empty preview toggle placeholder")
        sc.collection.children.link(temp)
        M.render(sc,STEM,temp)

if __name__=="__main__":
    main()

#!/usr/bin/env python3
"""Original Leviathan magnetic train and separately pitched Temperate cars."""
# SPDX-License-Identifier: GPL-2.0-only
from pathlib import Path
import os
import sys
import bpy
sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_stock_rail_f_art as f

M,R,W,J,G=f.M,f.R,f.W,f.J,f.G
B,D,Pipe=f.B,f.D,f.Pipe
REG={84:("Lev1 Leviathan","lev1"),
     89:("Maglev Passenger Carriage","maglev_passenger"),90:("Maglev Mail Van","maglev_mail")}
PALETTE={**f.PAL,
  "Burgundy primary":"70414f","Burgundy shaded":"502d3b","Wine shoulder":"9e6570",
  "Oxide orange":"b76944","Warm pearl":"d8d6c9","Silver pearl roof":"d1dde0",
  "Aluminum cool":"839ca2","Curtain jet":"202e3b","Polarized indigo":"3c6689",
  "Glazed ocean":"6b93aa","Tungsten glare":"bdd0d8","Red ruby":"b45142",
  "Airframe deck":"586170","Galvanized rail":"689399","Copper bus bar":"a67649",
  "Polished black ferrite":"303e46","UVC running headlamp":"ebefe7",
  "Low chamfer skin":"788a88","Wheel-less crush rail":"879294",
}
P={n:i for i,n in enumerate(PALETTE)}
# The Leviathan has a high-shoulder pressure hull with a short, swept nose.
# Trailers have their own complete saloon or mail body and two operating doors.
POWER=(
  (-.441,.119,.226,.099,.184),(-.430,.161,.265,.101,.217),
  (-.401,.181,.299,.103,.260),(-.368,.195,.358,.112,.310),
  (-.328,.211,.420,.117,.377),(-.283,.218,.451,.119,.399),
  (-.208,.224,.473,.119,.414),(-.095,.226,.483,.120,.423),
  (.290,.226,.483,.120,.423),(.383,.211,.472,.124,.409),(.426,.179,.438,.127,.379),
)
CARS=(
  (-.424,.183,.437,.124,.376),(-.401,.206,.461,.122,.400),
  (-.350,.219,.479,.119,.417),(-.276,.224,.482,.118,.423),
  (.276,.224,.482,.118,.423),(.350,.219,.479,.119,.417),
  (.401,.206,.461,.122,.400),(.424,.183,.437,.124,.376),
)
PIVOTS=(-.259,.246)

def prepare():
    f.P=M.P=J.P=W.P=G.P=P
    M.PAL=PALETTE
    R.COLORS[:]=PALETTE.values()

def vessel(m,id):
    sections=POWER if id==84 else CARS
    for (z,*l),(q,*r) in zip(sections,sections[1:]):
        a,b=f.body_contour(*l),f.body_contour(*r)
        for i in range(len(a)):
            j=(i+1)%len(a)
            color=("Burgundy shaded" if i in (0,1,18) else "Burgundy primary" if i in (2,3,16,17)
                   else "Wine shoulder" if i in (4,15) else "Silver pearl roof" if 7<=i<=12
                   else "Aluminum cool" if id==84 else "Warm pearl")
            f.face(m,"Load-bearing swept magnetic pressure hull",color,
                   [(a[i][0],z,a[i][1]),(b[i][0],q,b[i][1]),(b[j][0],q,b[j][1]),(a[j][0],z,a[j][1])])
    for i in (0,-1):
        z,*section=sections[i]
        pts=[(w,z,h) for w,h in f.body_contour(*section)]
        f.face(m,"Closed end pressure containment","Burgundy primary",pts if i==0 else pts[::-1])

def crest_window(m):
    # Set glass immediately above the real shell cross-sections. Preserve
    # both the longitudinal loft and the crown at the riveted center spine.
    def on_shell(z,w,dz):
        for (a,*aa),(b,*bb) in zip(POWER,POWER[1:]):
            if a<=z<=b:
                t=(z-a)/(b-a)
                ww,h,g,s=(x+(y-x)*t for x,y in zip(aa,bb))
                upper=sorted(f.body_contour(ww,h,g,s)[7:14])
                u=w*ww
                for (x,y),(x1,y1) in zip(upper,upper[1:]):
                    if x<=u<=x1:
                        return u,z,y+(y1-y)*(u-x)/(x1-x)+dz
        raise ValueError((z,w))
    def strip(start,end,x,y,mat,lift,name):
        zvals=[start]+[row[0] for row in POWER if start<row[0]<end]+[end]
        xvals=sorted({x,y,*[a for a in (-.544,-.282,0,.282,.544) if x<a<y]})
        for a,b in zip(zvals,zvals[1:]):
            for u,v in zip(xvals,xvals[1:]):
                f.face(m,name,mat,[on_shell(a,u,lift),on_shell(a,v,lift),on_shell(b,v,lift),on_shell(b,u,lift)])
    strip(-.366,-.249,-.807,.807,"Curtain jet",.003,"Recessed black windscreen frame")
    for i in (-1,1):
        x,y=sorted((i*.034,i*.775))
        strip(-.360,-.253,x,y,"Polarized indigo",.006,"Two magnet-train panoramic cab windscreens")
        strip(-.277,-.254,x,y,"Tungsten glare",.007,"Independent windscreen reflections")
        Pipe(m,"Driver windscreen wipers","Curtain jet",
             on_shell(-.351,i*.26,.010),on_shell(-.318,i*.56,.010),.002,8)
    B(m,"Continuous forward pilot band","Curtain jet",0,-.440,.205,.022,.155,.192,.006)
    for x in (-.061,.061):
        B(m,"Twin recessed LED facility lenses","UVC running headlamp",x,-.452,.043,.004,.163,.182,.004)
    for x in (-.11,.11):
        D(m,"Measured marker light housings","Red ruby",(x,.426,.234),.008,"z",.003,.008,14)

def facilities(m,id):
    sections=POWER if id==84 else CARS
    for side in (-1,1):
        def panel(group,color,a,b,y,z,o=.003):
            f.skin_panels(m,group,color,sections,side,a,b,y,z,o)
        panel("Distinct continuous burgundy fascia","Burgundy primary",-.22,.339,.205,.231,.0018)
        if id==84:
            panel("Side cab shoulder window bezel","Curtain jet",-.286,-.142,.285,.402,.002)
            panel("Side cab laminated wraparound glazing","Glazed ocean",-.282,-.146,.291,.395,.004)
            panel("Inverter access door capsule","Burgundy primary",.235,.345,.247,.376,.004)
            for k in range(9):
                a=-.126+k*.031
                panel("Tall liquid-cooled inverter louvers","Curtain jet",a,a+.012,.285,.361,.0045)
            panel("Legible guideway safety band","Oxide orange",-.202,.287,.237,.252,.004)
        elif id==89:
            panel("Continuous acrylic passenger window band","Curtain jet",-.344,.344,.282,.407,.002)
            for a,b in ((-.340,-.277),(-.159,-.102),(-.087,-.03),(-.015,.042),(.057,.114),
                         (.130,.186),(.281,.340)):
                panel("Separately framed saloon windows","Polarized indigo",a,b,.292,.397,.0043)
                panel("Laminated upper window sky","Glazed ocean",a+.003,b-.003,.362,.395,.0058)
            for a,b in ((-.266,-.173),(.197,.273)):
                panel("Accessible station sliding leaf in glass wall","Aluminum cool",a,b,.190,.406,.005)
                panel("Glazed sliding platform door","Polarized indigo",a+.005,b-.005,.295,.391,.006)
                panel("Visible orange request buttons","Oxide orange",a+.008,a+.017,.253,.273,.007)
        else:
            for a,b in ((-.320,-.114),(.106,.315)):
                panel("Two explicit postal loading bays","Curtain jet",a,b,.193,.391,.0038)
                panel("Beveled insulated postal bay doors","Burgundy primary",a+.005,b-.005,.201,.382,.0055)
                for j in range(6):
                    y=.222+j*.023
                    panel("Stamped postal bay horizontal ribs","Wine shoulder",a+.014,b-.014,y,y+.005,.0075)
                panel("Bright grab latch","Warm pearl",a+.047,b-.043,.217,.235,.009)
            panel("Sorting crew's small mid-car light","Glazed ocean",-.068,.083,.321,.386,.004)
            for y,z in ((.268,-.04),(.253,0),(.268,.04)):
                B(m,"Brushed sorting-company badges","Warm pearl",side*.228,z,.005,.024,y,y+.014,.002)
    for v in (-.16,.055,.260):
        B(m,"Low hooded intake casings","Aluminum cool",0,v,.111,.067,.467,.493,.008)
        for x in (-.031,-.010,.010,.031):
            B(m,"Visible intake cooling slots","Curtain jet",x,v,.008,.043,.490,.495,.0013)
    for direction in (-1,1):
        if direction==-1 and id==84:continue
        B(m,"Solid reciprocal bellows connection","Burgundy shaded",0,direction*.433,.169,.029,.149,.352,.005)
        B(m,"Contact-free mechanical draw link pocket","Airframe deck",0,direction*.455,.075,.048,.077,.111,.006)

def truck(m,z):
    # Trough center shelf is .162 and its side guide top is .213. Height 0
    # in this model is the guide rim; shoes float .021 node above the stator.
    # There are no rolling tires, wheel flanges or fake ballast contacts.
    B(m,"Pivoted non-contact levitation carrier","Airframe deck",0,z,.311,.149,.014,.106,.010)
    B(m,"Central magnetic flux return spine","Polished black ferrite",0,z,.129,.176,-.028,.022,.006)
    for v in (-.056,.056):
        B(m,"Four genuine magnetic load shoes","Polished black ferrite",0,z+v,.144,.047,-.030,.014,.006)
        B(m,"Inspected copper winding strip","Copper bus bar",0,z+v,.087,.026,-.029,-.025,.003)
        for i in (-1,1):
            B(m,"Independent lateral stabilization fin","Galvanized rail",i*.165,z+v,.019,.051,-.041,.045,.004)
            B(m,"Recessed insulating pad","Copper bus bar",i*.152,z+v,.019,.046,-.017,.005,.003)
    for i in (-1,1):
        Pipe(m,"Visible flexible three-phase bundle","Copper bus bar",
             (i*.134,z-.046,.071),(i*.085,z+.041,.061),.0045,8)

def make(id):
    prepare()
    title,asset=REG[id];asset="rail_"+asset
    shell=f.make_mesh();detail=f.make_mesh();gear=f.make_mesh();all_geometry=f.make_mesh()
    vessel(shell,id);vessel(all_geometry,id)
    facilities(detail,id);facilities(all_geometry,id)
    if id==84:crest_window(detail);crest_window(all_geometry)
    for v in PIVOTS:truck(all_geometry,v)
    keys=sorted({c for data in all_geometry.parts.values() for _,c in data})
    indices={p:i for i,p in enumerate(keys)}
    shade=list(PALETTE.values())
    R.COLORS[:]=[shade[i] for i in keys]
    def export(name,*sets):
        out=f.make_mesh()
        for src in sets:
            for group,faces in src.parts.items():
                for poly,color in faces:
                    out.face(group,indices[color],[src.vertices[group][x] for x in poly])
        R.export_obj(R.MODELS/f"bl_{name}.obj",W.local_obj(out),generator=Path(__file__).name)
    export(asset,all_geometry)
    export(asset+"_body",shell,detail)
    f.atlas(asset,R.COLORS)
    if id==84:
        truck(gear,0);export("rail_maglev_suspension",gear)
        coupler=f.make_mesh()
        B(coupler,"Reciprocal magnetic stock drawbar shaft","Airframe deck",0,0,.061,.124,-.018,.015,.004)
        for z in (-.046,.046):
            B(coupler,"Resilient ferrite mounting face","Polished black ferrite",0,z,.082,.021,-.030,.024,.004)
        export("rail_maglev_drawbar",coupler)
    prepare()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    sc=bpy.context.scene;sc.name=f"LuanTTD stock {title} #{id}"
    sc["Provenance"]=f"OpenTTD 16.0-RC1 src/table/engines.h #{id}; all meshes and textures are original."
    sc["Datum"]="Neutral nose -Z; rest plane is the guide rim; shoes hover 0.021 node above the native stator."
    mats=M.colors()
    J.geometry(sc,"01 Extruded magnetic pressure containment",shell,mats)
    J.geometry(sc,"02 Optics, working doors, intakes and end fittings",detail,mats)
    for i,v in enumerate(PIVOTS,3):
        assembly=f.make_mesh();truck(assembly,0)
        coll=J.geometry(sc,f"{i:02} Independent non-contact carrier",assembly,mats)
        pivot=bpy.data.objects.new("Independent maglev pivot",None)
        pivot.location=(0,v,0);pivot.empty_display_type="CIRCLE";pivot.empty_display_size=.06
        coll.objects.link(pivot)
        for ob in tuple(coll.objects):
            if ob!=pivot:ob.parent=pivot
    if id==84: J.geometry(sc,"05 Reciprocating drawbar export",coupler,mats)
    f.render(sc,asset,os.getenv("MAGLEV_REVIEW"),center=.218)

if __name__=="__main__":
    for id in REG:make(id)

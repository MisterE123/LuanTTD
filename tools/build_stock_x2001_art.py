#!/usr/bin/env python3
"""Model the first stock monorail consist without conventional rail bogies."""
# SPDX-License-Identifier: GPL-2.0-only
from pathlib import Path
import os
import sys
import bpy

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_stock_rail_f_art as F

B,D,Pipe=F.B,F.D,F.Pipe
M,R,W,J,G=F.M,F.R,F.W,F.J,F.G
PALETTE={**F.PAL,
    "Wave blue":"2d7290","Wave shadow":"255265","Sunlit ivory":"f0ecdc",
    "Ceramic ivory":"d5d5c6","Titanium roof":"a3b3b4",
    "Windshield rim":"263648","Cab glass":"375867","Cab reflected sky":"8eacb0",
    "Brass yellow":"f7b557","Armature iron":"445256","Carriage ruby":"b45240",
    "Mail red":"af5541","Mail cream":"ecdbb0","Rubber":"333a3d",
    "Suspension steel":"65767a","Amber tail":"ab4a3e"}
P={k:i for i,k in enumerate(PALETTE)}
REG={54:("X2001","x2001"),57:("Monorail Passenger Carriage","mono_passenger"),
     58:("Monorail Mail Van","mono_mail")}
# width, roof, belly and shoulder for each transverse station. The leading
# vehicle has a real tapered and raked airfoil cab; the stock trailers have
# bi-directional couplers and deliberately boxier, rounded body shells.
ENGINE=(
    (-.438,.108,.226,.132,.192),(-.424,.131,.247,.130,.215),
    (-.398,.153,.282,.129,.244),(-.372,.172,.332,.130,.285),
    (-.341,.187,.390,.134,.337),(-.303,.197,.442,.137,.388),
    (-.246,.203,.466,.139,.407),(-.136,.205,.472,.141,.416),
    (.288,.204,.471,.141,.415),(.394,.192,.455,.144,.398),(.421,.170,.428,.145,.373),
)
TRAILER=(
    (-.421,.165,.426,.145,.375),(-.400,.188,.447,.144,.393),
    (-.348,.199,.462,.141,.408),(-.268,.201,.468,.141,.412),
    (.268,.201,.468,.141,.412),(.348,.199,.462,.141,.408),
    (.400,.188,.447,.144,.393),(.421,.165,.426,.145,.375),
)
LOCKS=(-.259,.246)


def setup():
    F.P=M.P=J.P=W.P=G.P=P
    M.PAL=PALETTE
    R.COLORS[:]=PALETTE.values()


def shell(m,stock):
    path=ENGINE if stock==54 else TRAILER
    for (a,*x),(b,*y) in zip(path,path[1:]):
        q,r=F.body_contour(*x),F.body_contour(*y)
        for i in range(len(q)):
            j=(i+1)%len(q)
            if i in (0,1,17,18): c="Wave shadow"
            elif i in (2,3,15,16): c="Mail red" if stock==58 else "Wave blue"
            elif i in (8,9,10,11): c="Titanium roof"
            else:c="Mail cream" if stock==58 else "Sunlit ivory" if 6<=i<=13 else "Ceramic ivory"
            F.face(m,"Continuous extruded aluminum pressure shell",c,
              [(q[i][0],a,q[i][1]),(r[i][0],b,r[i][1]),(r[j][0],b,r[j][1]),(q[j][0],a,q[j][1])])
    for i in (0,-1):
        z,*path_section=path[i]; top=[(x,z,y) for x,y in F.body_contour(*path_section)]
        F.face(m,"Closed aerodynamic nose and end bulkheads","Ceramic ivory",top if i==0 else top[::-1])


def doors_and_windows(m,stock):
    path=ENGINE if stock==54 else TRAILER
    for s in (-1,1):
        def panel(name,color,a,b,l,h,offset=.002):
            F.skin_panels(m,name,color,path,s,a,b,l,h,offset)
        if stock==54:
            for a,b,l,h in ((-.332,-.303,.276,.338),(-.302,-.249,.313,.389),(-.248,-.198,.328,.405)):
                panel("Raked wraparound driver glazing","Windshield rim",a,b,l,h,.003)
                panel("Isolated polarized cab panes","Cab glass",a+.003,b-.003,l+.008,h-.010,.0045)
                panel("Sky reflected on curved driver glazing","Cab reflected sky",a+.005,b-.005,h-.026,h-.012,.006)
            for i in range(10):
                z=-.108+i*.023
                panel("Recessed motor intake ribs","Armature iron",z,z+.009,.260,.330,.003)
            panel("Maintenance hatch","Wave shadow",.174,.345,.219,.370,.003)
            panel("Service door pressed panel","Titanium roof",.179,.340,.223,.365,.005)
            panel("Service door catch","Suspension steel",.307,.329,.279,.288,.006)
        elif stock==57:
            for a,b in ((-.326,-.266),(-.156,-.096),(-.080,-.020),(-.004,.056),(.072,.132),(.238,.298),(.314,.362)):
                panel("Individual saloon window gaskets","Windshield rim",a,b,.303,.390)
                panel("Isolated saloon glass","Cab glass",a+.003,b-.003,.310,.383,.004)
                panel("Light at upper window edge","Cab reflected sky",a+.005,b-.005,.363,.380,.0054)
            for a,b in ((-.253,-.165),(.147,.230)):
                panel("Twin leaf flush passenger door recess","Wave shadow",a,b,.200,.394)
                for lo,hi in ((a+.004,(a+b)/2-.002),((a+b)/2+.002,b-.004)):
                    panel("Two formed passenger door leaves","Ceramic ivory",lo,hi,.205,.388,.004)
                    panel("Small rectangular door glass","Cab glass",lo+.004,hi-.004,.323,.377,.006)
                    panel("Reachable raised door control","Brass yellow",lo+.007,lo+.013,.253,.266,.008)
        else:
            for a,b in ((-.300,-.112),(.108,.296)):
                panel("Twin postal loading roller-door recesses","Wave shadow",a,b,.207,.385,.003)
                panel("Stamped mail rolling leaves","Mail cream",a+.004,b-.004,.216,.378,.005)
                for j in range(8):
                    y=.223+j*.020
                    panel("Raised horizontal shutter slats","Mail red",a+.010,b-.010,y,y+.004,.006)
                panel("Postal handling drop handle","Armature iron",a+.052,b-.052,.232,.244,.008)
            panel("Small sorting compartment glass","Cab glass",-.070,.071,.315,.380,.004)
            # Letter symbol assembled from separate polished metal strokes.
            for x0,z0,x1,z1 in ((.002,-.035,.002,.035),(.044,-.035,.044,.035),
                                 (.002,-.035,.044,-.035),(.002,.035,.044,.035),
                                 (.044,-.035,.026,0),(.026,0,.044,.035)):
                Pipe(m,"Postal envelope enamel badge","Mail cream",
                     (s*.205,z0,.254+x0),(s*.205,z1,.254+x1),.0025,8)
        band="Mail red" if stock==58 else "Wave blue"
        panel("Wheel-cover service belt",band,-.179,.230,.210,.225,.0025)
    for z in (-.120,.047,.198):
        B(m,"Recessed roof heat exchangers","Titanium roof",0,z,.135,.059,.452,.487,.009)
        for x in (-.035,-.012,.011,.034):
            B(m,"Slotted roof duct","Armature iron",x,z,.009,.043,.481,.488,.0018)


def cab_optics(m,stock):
    if stock==54:
        # Bonded glazing follows the actual longitudinal loft. The two
        # panes are offset above the surface, with a visible central gap.
        def hood(z,u,offset):
            for (za,*ca),(zb,*cb) in zip(ENGINE,ENGINE[1:]):
                if za<=z<=zb:
                    q=(z-za)/(zb-za)
                    w,h,belly,shoulder=(a+(b-a)*q for a,b in zip(ca,cb))
                    top=sorted(F.body_contour(w,h,belly,shoulder)[7:14])
                    x=u*w
                    for (x0,h0),(x1,h1) in zip(top,top[1:]):
                        if x0<=x<=x1: return x,z,h0+(h1-h0)*(x-x0)/(x1-x0)+offset
            raise ValueError((z,u))
        def glass(name,mat,range_,edges,offset):
            za,zb=range_
            zs=[za]+[row[0] for row in ENGINE if za<row[0]<zb]+[zb]
            lo,hi=edges
            us=sorted({lo,hi,*[u for u in (-.544,-.282,0,.282,.544) if lo<u<hi]})
            for za,zb in zip(zs,zs[1:]):
                for a,b in zip(us,us[1:]):
                    F.face(m,name,mat,[hood(za,a,offset),hood(za,b,offset),
                        hood(zb,b,offset),hood(zb,a,offset)])
        glass("Inset into the cab shell at its actual rake","Windshield rim",(-.361,-.249),(-.77,.77),.0033)
        for s in (-1,1):
            limits=tuple(sorted((s*.024,s*.735)))
            glass("Twin bonded driver panes with physical centre mullion","Cab glass",(-.355,-.255),limits,.0057)
            glass("Two individual laminated sky glare strips","Cab reflected sky",(-.277,-.257),limits,.0069)
            Pipe(m,"Windscreen washing blade","Armature iron",
                 hood(-.351,s*.26,.009),hood(-.312,s*.47,.009),.002,8)
        B(m,"Shallow fairing around traction lamps","Wave shadow",0,-.437,.169,.020,.158,.206,.006)
        for x in (-.062,.062):
            D(m,"Clearly separated halogen headlights","Brass yellow",(x,-.449,.183),.013,"z",-.006,.002,18)
    else:
        for z in (-.420,.420):
            sg=1 if z>0 else -1
            for x in (-.127,.127):
                D(m,"Bi-directional ruby marker housings","Amber tail",(x,z,.249),.010,"z",
                  -.009 if sg<0 else .002,-.002 if sg<0 else .009,18)
            B(m,"Transverse fire and nose bulkhead","Wave shadow",0,z,.185,.012,.192,.356,.009)
            B(m,"Ribbed offset vestibule bellows","Rubber",0,z+sg*.007,.133,.023,.203,.335,.008)


def bogie(m,stock,z):
    sides=(-1,1)
    B(m,"Independent straddle-bogie pivot","Suspension steel",0,z,.233,.093,.072,.125,.008)
    for dz in (-.040,.040):
        for s in sides:
            # Four tire treads entirely on the flat running head (+/-
            # .096 at a straight section), spanning both bogie rows.
            D(m,"Load tires seated on beam crown","Rubber",(s*.040,z+dz,.036),.036,"x",-.020,.020,28)
            D(m,"Visible centerline load tire hubs","Titanium roof",(s*.040,z+dz,.036),.016,"x",-.023,.023,16)
    for s in sides:
        B(m,"Open side clearance yoke castings","Suspension steel",s*.135,z,.029,.140,-.074,.108,.007)
        for dz in (-.043,.043):
            # Horizontal anti-roll rollers guide below the wear surface.
            # Their inner face is x=.118, never a standard flange axle.
            D(m,"Under-beam side guide rollers","Rubber",(s*.137,z+dz,-.048),.019,"h",-.010,.010,20)
            B(m,"Visible side guidance cage","Wave shadow",s*.152,z+dz,.018,.048,-.066,.042,.004)
def chassis(m,stock):
    B(m,"Torsion box chassis","Armature iron",0,0,.312,.724,.097,.167,.010)
    for z in ([-.433,.432] if stock!=54 else [.431]):
        B(m,"Independent automatic coupler pocket","Suspension steel",0,z,.075,.073,.076,.112,.006)


def vehicle(stock):
    title,key=REG[stock];name="rail_"+key
    setup()
    parts=(("01 Formed aerodynamic pressure hull",shell),
           ("02 Distinct saloon, cargo or power-car detail",doors_and_windows),
           ("03 Cabin or opposing corridor and optic work",cab_optics),
           ("04 Central underframe and automatic couplers",chassis))
    full=F.make_mesh()
    for label,fun in parts:fun(full,stock)
    for z in LOCKS:bogie(full,stock,z)
    colors=tuple(PALETTE.values())
    idx={old:i for i,old in enumerate(sorted({c for fs in full.parts.values() for _,c in fs}))}
    packed=F.make_mesh()
    for group,fs in full.parts.items():
        for poly,col in fs:
            packed.face(group,idx[col],[full.vertices[group][i] for i in poly])
    R.COLORS[:]=[colors[i] for i in idx]
    R.export_obj(F.ROOT/"mods/luanttd_core/models"/f"bl_{name}.obj",W.local_obj(packed),
                 generator=Path(__file__).name)
    F.atlas(name,R.COLORS)
    setup()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene
    scene.name=f"LuanTTD stock {title} #{stock}"
    scene["Upstream"]=f"OpenTTD 16.0-RC1 table/engines.h #{stock}. Original LuanTTD art; no upstream sprites copied."
    scene["Envelope"]="Neutral nose -Z; baseline is monorail beam crown, height +.246 relative to grade."
    mats=M.colors()
    for label,fun in parts:
        mesh=F.make_mesh()
        fun(mesh,stock)
        J.geometry(scene,label,mesh,mats)
    for i,z in enumerate(LOCKS,5):
        mesh=F.make_mesh()
        bogie(mesh,stock,0)
        col=J.geometry(scene,f"{i:02} Independent pivot, tires and guidance rollers",mesh,mats)
        pivot=bpy.data.objects.new("Bogie pivot",None)
        pivot.location=(0,z,0);pivot.empty_display_type="CIRCLE";pivot.empty_display_size=.065
        col.objects.link(pivot)
        for ob in tuple(col.objects):
            if ob!=pivot: ob.parent=pivot
    # Moving bodies keep separate bogie pivots. The split runtime may
    # yaw each shared physical casting against the continuous guideway.
    R.COLORS[:]=[colors[i] for i in idx]
    body=F.make_mesh()
    for label,fun in parts:fun(body,stock)
    split_assets=[(name+"_body",body)]
    if stock==54:
        gear=F.make_mesh()
        bogie(gear,stock,0)
        split_assets.append(("rail_mono_bogie",gear))
        link=F.make_mesh()
        B(link,"Forged variable visible draw link","Armature iron",0,0,.026,.12,-.011,.011,.004)
        B(link,"Stainless coupling tube crown","Suspension steel",0,0,.014,.087,.006,.015,.003)
        split_assets.append(("rail_mono_drawbar",link))
        device=J.geometry(scene,"09 Adjustable drawbar (isolated editable part)",link,mats)
        device.hide_render=True
        device.hide_viewport=True
    for split_name,src in split_assets:
        split=F.make_mesh()
        for group,fs in src.parts.items():
            for poly,col in fs:
                split.face(group,idx[col],[src.vertices[group][i] for i in poly])
        R.export_obj(F.ROOT/"mods/luanttd_core/models"/f"bl_{split_name}.obj",W.local_obj(split),
                     generator=Path(__file__).name)
    F.render(scene,name,os.getenv("MONORAIL_REVIEW"),center=.215)


if __name__=="__main__":
    for stock in REG:
        vehicle(stock)

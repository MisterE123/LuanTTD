#!/usr/bin/env python3
"""Original 3D stock #208 Bakewell 300 Hovercraft for OpenTTD 16.0-RC1."""
from math import sin,cos,pi,tau
from pathlib import Path
import bpy
from mathutils import Vector as V
import os,sys,struct,zlib
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,os.getenv("LUANTTD_HELPERS",str(ROOT/"tools")))
import build_ship_facility_art as H
from build_rail_wagon_art import local_obj
B,T,R=H.box,H.tube,H.rail
STEM="stock_bakewell_300_hovercraft"
PAL=dict(black="293039",skirt="333740",skirt_dark="292b33",skirt_light="41464d",
    rubber_ring="626168",skirt_edge="101921",skirt_brush="4e4d53",navy="243d55",
    lower="315368",base="4e6d7d",top="e3e5db",canvas="cdd5cc",cream="f0eee2",
    paper="f4ead4",blue="66828c",silver="9faeb0",grey="6e7e83",alum="b8c2be",
    muted="909d9d",boat_gray="a2b0ad",deck="9ca8a6",wood="968673",gun="4c5961",
    dark="354b56",dark_glass="2f4a57",glass="496d79",glass_blue="618391",glass_light="a8c2c4",
    white_window="c8dbd6",seal="35404a",red="b74537",scarlet="d86049",red_dark="92392f",
    charcoal="374049",guard="68757c",steel="84929a",iron="65737b",yellow="d2ae69",
    prop_base="6e7573",prop_gray="bbc6c1",prop_dark="8e9e9b",prop_signal="e5c374",
    duct_dark="535d65",duct_skin="b4c4c5",duct_lip="d2d8cf",duct_inside="666e73",
    vent="626d78",vent_edge="8f9898",vent_lid="b4c2c4",strap="758b8c",brown="977963",
    rescue="c5724c",mint="559678",port="d1403e",deck_wash="748888",cabin_floor="465359",
    warm="e5ddc7",hatch="bdc6ba",tread="96a4a3",nav_black="414d53",boot_top="575664",
    gasket="67757c",marker="c39754",shadow="5f5d63")
P={c:i for i,c in enumerate(PAL)}
assert len(P)==64
H.P=P;R.COLORS[:]=PAL.values()
# z, half breadth, deck sheer. Broad shovel nose, racetrack edges and a
# softly near-square stern, kept clear of City/Yate marine structure scale.
FRAMES=((- .862,.060,.203),(-.837,.145,.204),(-.785,.237,.203),
         (-.708,.313,.200),(-.591,.358,.194),(-.407,.371,.193),
         ( .431,.371,.193),( .582,.364,.194),(.698,.327,.193),(.774,.274,.188),
         (.822,.179,.187),(.849,.061,.186))
def f(m,n,c,p):m.face(n,P[c],p)
def rail(m,n,c,a,b,r=.006,npoints=8):T(m,n,c,a,b,r,r,npoints)
def line(m,n,c,pts,r=.006,npoints=8):
    for a,b in zip(pts,pts[1:]):rail(m,n,c,a,b,r,npoints)

def station(z):
    for a,b in zip(FRAMES,FRAMES[1:]):
        if a[0]-1.e-6<=z<=b[0]+1.e-6:
            fac=(z-a[0])/(b[0]-a[0])
            return tuple(a0+(b0-a0)*fac for a0,b0 in zip(a[1:],b[1:]))
    raise ValueError(z)

def outline(fr=FRAMES):
    return [(w,z) for z,w,_ in fr]+[(-w,z) for z,w,_ in reversed(fr)]
def vess_closed(m,name,list_,caps="lower"):
    for row1,row2 in zip(list_,list_[1:]):
        a,c=row1;b,d=row2
        n=len(a)
        for j in range(n):
            k=(j+1)%n
            f(m,name,c if (j%2==0 or c not in ("skirt","skirt_light")) else d,(a[j],a[k],b[k],b[j]))
    f(m,name,caps,list_[0][0][::-1]);f(m,name,caps,list_[-1][0])

def hull(m):
    # Closed contact cushion below the solid shallow amphibious deck. Tubed
    # lower plenum and raised belt are separate volumes.
    lo=outline()
    if R.signed_area(lo)<0:lo=lo[::-1]
    def v(q,y,k=1.,j=1.):return [(x*k,z*j,y) for x,z in q]
    stack=((-.099,.884,.952,"skirt_edge"),(-.079,.971,.987,"skirt_dark"),
         (-.036,1.02,1.0,"skirt"),(.034,1.022,1.004,"skirt_light"),
         (.101,.981,1.0,"skirt"),(.126,.966,.991,"rubber_ring"))
    vess_closed(m,"Sealed separate amphibious pneumatic skirt and central air plenum",
        [(v(lo,h,k,j),co) for h,k,j,co in stack],"skirt_edge")
    body=((.111,.955,.982,"lower"),(.127,.999,1.,"navy"),
          (.154,1.016,1.,"top"),(.181,1.006,.998,"top"),(.197,.968,.985,"deck"))
    vess_closed(m,"Separate rigid sealed aluminium load deck and vehicle shell",
        [(v(lo,h,k,j),co) for h,k,j,co in body],"base")
    for s in (-1,1):
        line(m,"Riveted white load-bearing skirt attachment ring","cream",
                [(s*w*1.002,z,.158) for z,w,_ in FRAMES],.008,8)
        line(m,"Continuous bright anodized upper ferry boarding belt","alum",
                [(s*w*.963,z*.988,.199) for z,w,_ in FRAMES],.007,7)
    # Independent curved bag sectors adjacent to black gaps. Instead of
    # painted vertical ticks the actual surface has visibly modelled folds.
    for s in (-1,1):
        for i in range(28):
            z=-.819+1.638*i/28
            z1=z+.0417
            w,_=station(z);w1,_=station(z1)
            # Outer curves turn shallow each end so the silhouette preserves
            # full-seal envelope; in export they cast visible face shading.
            def a(t,z0,w0):
                rr=(.993+.024*sin(pi*t))*.996
                return (s*(w0*rr+.002),z0,-.084+.197*t)
            for j in range(4):
                t=j/4;n=(j+1)/4
                f(m,"Independent rounded flexible black apron skirt fingers",
                  ("skirt","skirt_brush","skirt_dark","skirt","skirt_light")[(i+j)%5],
                  [a(t,z,w),a(t,z1,w1),a(n,z1,w1),a(n,z,w)][::s])
            for zz,ww in ((z,w),(z1,w1)):
                b=(s*(ww*.967+.004),zz,-.06)
                c=(s*(ww*.969+.002),zz,.095)
                rail(m,"Independently modelled skirt seam stitch edge","skirt_dark",b,c,.0024,7)
    # Internal air channels and the structure that can support an amphibious
    # craft at rest, never mistaken for wheels or a hydrodynamic screw.
    for s in (-1,1):
        B(m,"Inside skirt independently visible dry-ramp skid strips","skirt_edge",s*.171,.073,.032,1.031,-.094,-.080,.004)
        B(m,"Transverse internal lift air duct root housings","charcoal",s*.12,.003,.086,.433,-.091,-.062,.012)
    B(m,"Centre closed air chamber shield beneath deck","black",0,.008,.309,.751,-.084,-.062,.014)

def cabin(m):
    # Signed horizontal sections for a clearly white streamlined profile in
    # which the cockpit and passenger salon share one weather deck.
    body=[(-.644,.128,.245,.286),(-.602,.199,.241,.347),(-.548,.254,.229,.419),
         (-.434,.275,.225,.467),(-.190,.281,.219,.467),(.181,.278,.217,.459),
         (.352,.248,.221,.446),(.471,.169,.224,.389),(.491,.126,.225,.369)]
    rings=[]
    for z,w,l,h in body:
        q=[(-w*.87,z,l),(w*.87,z,l),(w,z,l+.037),(w,z,h-.054),(w*.90,z,h),
           (-w*.90,z,h),(-w,z,h-.054),(-w,z,l+.037)]
        rings.append(q)
    for a,b in zip(rings,rings[1:]):
        for j,co in enumerate(("grey","base","top","canvas","top","canvas","top","grey")):
            k=(j+1)%8
            f(m,"Original low rounded full-width glazed passenger shell",co,(a[k],a[j],b[j],b[k]))
    f(m,"Aircraft-like blunt front cabin pressure cap","top",rings[0])
    f(m,"Gently rounded aft cabin bulkhead","top",rings[-1][::-1])
    B(m,"White shallow roof crown between hidden duct channels","cream",0,-.107,.413,.874,.436,.482,.029)
    B(m,"Smooth clean upper saloon corrugated roof seam","canvas",0,-.122,.309,.669,.477,.493,.012)
    B(m,"Dorsal short open radar mast foot","dark",0,-.312,.044,.064,.479,.507,.007)
    T(m,"Original light communication cabin relay","steel",(0,-.312,.506),(0,-.306,.620),.007,.005,9)
    T(m,"Small lowered front radio radar housing","silver",(-.070,-.307,.602),(.070,-.307,.602),.007,.006,9)
    # Fleet glass follows body width and height. Angle-preserving windows,
    # each shade and mullion edge is actual geometry on side and brow.
    def b(z):
        for a,b1 in zip(body,body[1:]):
            if a[0]<=z<=b1[0]:
                k=(z-a[0])/(b1[0]-a[0])
                return tuple(aa+(bb-aa)*k for aa,bb in zip(a[1:],b1[1:]))
        raise ValueError(z)
    for s in (-1,1):
        for i in range(12):
            z=-.466+i*.072
            w,l,h=b(z)
            lo,hi=(.323,.389) if z<.23 else (.315,.377)
            q=lambda z,y,d:(s*(b(z)[0]+d),z,y)
            for tag,mat,d,v0,v1,hh,rr in (
                ("Separate saloon bus windows outward moldings","seal",.003,-.026,.026,lo-.008,hi+.008),
                ("Small individual glazed saloon side windows","glass",.005,-.022,.022,lo,hi),
                ("Faint light along front-facing saloon glass","glass_light",.008,-.018,.018,hi-.011,hi-.003)):
                f(m,tag,mat,[q(z+v0,hh,d),q(z+v1,hh,d),q(z+v1,rr,d),q(z+v0,rr,d)][::s])
        for z in (-.435,.199):
            w,l,h=b(z)
            B(m,"Independently modelled hinged passenger side service doors","boat_gray",s*w,z,.014,.066,.238,.365,.004)
            B(m,"Recessed rectangular vertical passenger cabin door window","glass",s*(w+.010),z,.005,.042,.296,.345,.003)
            B(m,"Black close grip for side-lock passenger door","seal",s*(w+.014),z+.007,.013,.022,.271,.286,.001)
            B(m,"Real landing non-slip passenger gangplank near door","tread",s*.310,z,.088,.104,.201,.221,.006)
            for zz in (z-.047,z+.044):
                line(m,"Original metal gangway outside handrails","alum",[(s*.321,zz,.206),(s*.321,zz,.276),
                     (s*(w+.011),zz,.302)],.004,7)
        # Fixed red strip and bow side panels suggest original paint, no logo.
        B(m,"Distinct lower original orange-red passenger cabin belt","red",s*.274,-.096,.014,.536,.287,.306,.005)
        B(m,"Small plain ship-name plate without real operator logo","paper",s*.283,.156,.008,.065,.263,.279,.002)
        B(m,"Cabin navigation fitting","nav_black",s*.261,-.425,.037,.060,.393,.422,.007)
        B(m,"Separate port and starboard colored lens","port" if s<0 else "mint",s*.282,-.427,.011,.034,.400,.417,.003)
    glass=[(z,b(z)[0]*.94,b(z)[2]) for z in (-.604,-.602,-.573,-.548,-.506,-.467)]
    for x0,x1 in ((-.76,-.40),(-.34,-.02),(.02,.34),(.40,.76)):
        for j,(a,b0) in enumerate(zip(glass,glass[1:])):
            z,w,h=a;zz,ww,hh=b0
            f(m,"Curved separate pilot bridge front windshields","glass_blue" if j>=3 else "dark_glass",
                [(x0*w,z,h+.005),(x1*w,z,h+.005),(x1*ww,zz,hh+.005),(x0*ww,zz,hh+.005)])
        for x in (x0,x1):
            line(m,"Physical cream panoramic bridge vertical frame","paper",
                 [(x*w,z,h+.006) for z,w,h in glass],.0047,7)
    B(m,"Neutral aerodynamic lower bow lip identification marker","alum",0,-.624,.207,.011,.252,.271,.003)
    for s in (-1,1):
        B(m,"Passenger raised projection bow lamp enclosure","shadow",s*.151,-.676,.048,.034,.208,.249,.005)
        B(m,"Warm low output face rescue docking lamps","paper",s*.150,-.697,.034,.008,.217,.242,.003)
        T(m,"Small bow anti-scuff working winch","grey",(s*.054,-.735,.215),(s*.119,-.735,.215),.014,.012,10)
        for z in (-.704,.598):
            rail(m,"Real ship through-ramp tiedown post exterior","steel",(s*.126,z,.201),(s*.126,z,.240),.009,8)

def propulsor(m):
    for s in (-1,1):
        x=s*.243;y=.415
        B(m,"Real actual rear engine pod fairing foundations","red_dark",x,.475,.137,.141,.198,.275,.014)
        B(m,"Slender original red lift and aft propulsion pilasters","red",x,.511,.092,.087,.267,.438,.012)
        B(m,"Rounded red deck pylons frame stock silhouette","scarlet",x,.509,.073,.064,.429,.464,.011)
        # Annular aft-facing duct has two open ends and a recessed real prop
        # disk with independent, swept blade geometry. No opaque cap.
        positions=((.510,.097,"duct_lip"),(.526,.106,"duct_skin"),(.596,.103,"duct_skin"),
                   (.625,.094,"duct_lip"),(.622,.081,"duct_inside"),(.547,.079,"duct_dark"),(.513,.083,"duct_inside"))
        n=32
        rings=[[(x+r*cos(tau*j/n),z,y+r*sin(tau*j/n)) for j in range(n)] for z,r,_ in positions]
        for i,a in enumerate(rings):
            b=rings[(i+1)%len(rings)]
            for j in range(n):
                k=(j+1)%n
                f(m,"Real open annular rear thrust ducts",positions[i][2],(a[j],b[j],b[k],a[k]))
        T(m,"Original visible sealed fan hub and aft motor spinner","prop_gray",(x,.540,y),(x,.620,y),.025,.018,16)
        # Two genuine tube struts across the forward engine aperture.
        for i in range(3):
            th=tau*i/3
            rail(m,"Three fixed swept support stators ahead of rotating fan","duct_inside",
                     (x+.020*cos(th),.573,y+.020*sin(th)),(x+.080*cos(th+.10),.557,y+.080*sin(th+.10)),.006,8)
        for i in range(5):
            th=tau*i/5+s*.11
            def v(r,da,z):return (x+r*cos(th+da*s),z,y+r*sin(th+da*s))
            a=[v(.016,-.28,.583),v(.036,-.21,.579),v(.074,-.12,.580),v(.076,.03,.589),
               v(.059,.24,.594),v(.024,.32,.592)]
            b=[(X,z+.004,h) for X,z,h in a]
            f(m,"Five full swept metal thrust fan blades out and inside","prop_gray",a[::s])
            f(m,"Five full swept metal thrust fan blades out and inside","prop_dark",b[::-s])
            for j in range(6):
                k=(j+1)%6
                f(m,"Five swept fan individual blade machined tips","prop_signal" if j==2 else "prop_dark",
                    (a[j],a[k],b[k],b[j])[::-s])
        # Side lift-air intake housings forward echo the early stock four
        # red-red outlines, and do not masquerade as second aft thrusters.
        xx=s*.299;zz=-.337
        B(m,"Shallow forward outrigger red frame for lift engine","red_dark",xx,zz,.100,.092,.202,.341,.010)
        B(m,"Raised independent forward lift-air bleed intake aft-outlet","scarlet",xx,zz,.082,.071,.334,.380,.010)
        B(m,"Protected gray slatted lift-air deck fan cover","steel",xx,zz,.074,.064,.375,.389,.007)
        for i in range(6):
            B(m,"Real separate inset lift air intake louvers","vent",xx,zz-.025+i*.010,.053,.005,.387,.393,.0015)
        rail(m,"Red iron danger rail outside lift motor","red", (s*.324,zz-.104,.209),(s*.324,zz-.048,.296),.006,7)
        # Stern gate has distinct central landing footprint and cold rails;
        # overhead fans sit outboard and do not block it.
        B(m,"Stern boarding red crash rim and thick hinged shell","red",s*.102,.729,.051,.037,.208,.262,.005)
        for z in (.591,.712):
            rail(m,"Guarded rear deck booth light and rail", "silver",(s*.171,z,.201),(s*.171,z,.295),.005,7)
        line(m,"Real aft central access guard bars","alum",[(s*.171,.585,.290),(s*.171,.717,.290)],.006,7)
        B(m,"Removable surface red flotation capsule","rescue",s*.156,.377,.063,.125,.201,.247,.012)
    B(m,"Independent shallow closed tail boarding ramp under passenger cabin","steel",0,.630,.294,.300,.197,.220,.011)
    for z in (.526,.559,.596,.632,.668,.704,.743):
        B(m,"Individual nonslip aft passenger boarding stair tread strip","tread",0,z,.263,.007,.215,.224,.0018)
    B(m,"Warm hull engraved back per-side registration plate","paper",0,.790,.171,.009,.155,.178,.003)

def submodel(fn):
    m=R.Mesh(R.terrain_height(0));fn(m);return m
def atlas():
    def chunk(t,p):return struct.pack(">I",len(p))+t+p+struct.pack(">I",zlib.crc32(t+p))
    data=b"".join(bytes.fromhex(c)*8 for c in PAL.values())
    (ROOT/"mods/luanttd_core/textures"/f"bl_{STEM}_atlas.png").write_bytes(b"\x89PNG\r\n\x1a\n"+
      chunk(b"IHDR",struct.pack(">IIBBBBB",512,8,8,2,0,0,0))+chunk(b"IDAT",zlib.compress((b"\0"+data)*8,9))+chunk(b"IEND",b""))
def export():
    bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene
    scene.name="LuanTTD | #208 Bakewell 300 Hovercraft"
    scene["source"]="OpenTTD 16.0-RC1 engine 208, stock ship image 3 = 3693. Original 3D geometry and palette."
    scene["pose"]="Native nose -Z, waterline Y=0, scale 1.0. Authoring Blender forward -Y."
    mats=R.materials()
    for n,mat in zip(P,mats):mat.name=n
    all_=R.Mesh(R.terrain_height(0))
    for title,fn in (("01 Native pressure hull and inflatable underside skirt",hull),
                ("02 Glazed passenger cabin, entry doors and upper deck",cabin),
                ("03 Annular thrust ducts, five-blade propellers and lift-intake hatches",propulsor)):
        c=bpy.data.collections.new(title);scene.collection.children.link(c);R.to_blender(submodel(fn),c,mats)
        fn(all_)
    p=ROOT/"mods/luanttd_core/models"/f"bl_{STEM}.obj";R.export_obj(p,local_obj(all_))
    p.write_text("# Original stock #208 hovercraft; tools/build_stock_hovercraft_art.py\n"+
      p.read_text().split("\n",1)[1]);atlas()
    for screen in bpy.data.screens:
        for a in screen.areas:
            if a.type=="VIEW_3D":
                v=a.spaces.active;v.shading.color_type="MATERIAL"
                v.region_3d.view_location=V((0,0,.22));v.region_3d.view_distance=3.22
                v.region_3d.view_rotation=V((.76,-.82,.62)).to_track_quat("Z","Y")
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art"/f"{STEM}.blend"),compress=True)
    if dest:=os.getenv("HOVERCRAFT_REVIEW"):review(scene,Path(dest))
def review(scene,dest):
    bpy.ops.mesh.primitive_plane_add(size=22,location=(0,0,-.0004))
    water=bpy.context.object
    mat=bpy.data.materials.new("Review only datum waterplane")
    mat.diffuse_color=(.070,.204,.254,1);water.data.materials.append(mat)
    cam=bpy.data.cameras.new("Hovercraft review");ob=bpy.data.objects.new("Hovercraft review",cam)
    scene.collection.objects.link(ob);scene.camera=ob;cam.type="ORTHO";cam.ortho_scale=2.30
    scene.render.engine="BLENDER_WORKBENCH"
    sh=scene.display.shading;sh.light="STUDIO";sh.studio_light="paint.sl";sh.color_type="MATERIAL"
    sh.show_shadows=True;sh.show_cavity=True;sh.cavity_type="BOTH"
    scene.world=bpy.data.worlds.new("Overcast hull proof");scene.world.color=(.15,.20,.23)
    sh.background_type="WORLD";scene.view_settings.view_transform="Standard"
    scene.render.image_settings.file_format="JPEG";scene.render.resolution_x=900;scene.render.resolution_y=620
    scene.render.resolution_percentage=100
    for tag,xyz in (("bow",(2.7,-2.8,1.57)),("stern",(-2.5,2.76,1.46)),("apron",(1.82,-2.32,-.59))):
        ob.location=xyz;ob.rotation_euler=(V((0,0,.23))-ob.location).to_track_quat("-Z","Y").to_euler()
        water.hide_render=tag=="apron";sh.show_shadows=tag!="apron"
        scene.render.filepath=str(dest/f"hovercraft_{tag}.jpg");bpy.ops.render.render(write_still=True)
if __name__=="__main__":export()

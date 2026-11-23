#!/usr/bin/env python3
"""Author original editable #22 SH 125 and #28 stock Mail Van, exact native gauge."""
from math import cos,sin,pi,tau
from pathlib import Path
import os,struct,sys,zlib
import bpy
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,os.getenv("LUANTTD_HELPERS",str(ROOT/"tools")))
import build_manley_morel_art as M
R,W,J,G=M.R,M.W,M.J,M.G
B,D,Pipe=J.B,J.Disk,J.Pipe

# Shared physical wheelset primitives. Bodies use their own invented livery.
PAL={**M.PAL,**{
 "Express Pacific blue":"27648a","Deep western blue":"224756","Light ensign blue":"4080a0",
 "Satin aluminum lining":"c5c8be","Warm slab yellow":"e3ad3a","Glancing train yellow":"f1c96d",
 "Blue dark moulding":"354653","Bonnet apron shadow":"a47033","Cab curved windshield":"263d47",
 "Cab blue glass tint":"567786","Cab sky reflection":"8fadb5","Warm cab halogen":"f2dfac",
 "Cooling rack black":"273638","Grille polished lip":"719095","Cooling rack gray":"46565c",
 "Mail oxblood enameled steel":"864542","Mail cinnabar panel":"a34f46","Mail deep frame":"633c3b",
 "Post lower enamel":"713f3e","Mail buttercream stenciling":"e6d1a3",
 "Mail brass edge":"b3a07a","Mail framed window":"485455","Mail smoked upper glass":"55707a",
 "Mail relieved hinge steel":"686c63","Mail dusty concrete":"8d8274",
 "Plate lamp cast iron":"394148","Neutral imperial platform":"778386",
}}
P={k:i for i,k in enumerate(PAL)}
CABS=(-.271,-.177,.175,.269)
VANS=(-.286,-.191,.191,.286)
POWER="rail_sh_125"; VAN="rail_mail_van"
def make_mesh():return R.Mesh(R.terrain_height(0))
def face(m,n,c,p):m.face(n,P[c],p)

def body_contour(w,h,belly,shoulder):
    # Crown radius and cab shoulders are derived from the closed pressure shell
    # cross-section, not a triangular cab sitting in front of a rectangular box.
    return tuple((a*w,b) for a,b in (
       (-.75,belly),(.75,belly),(.93,belly+.022),(1,belly+.064),
       (1,shoulder-.045),(.994,shoulder),(.946,shoulder+.022),
       (.808,h-.020),(.544,h-.008),(.282,h-.002),(0,h),
       (-.282,h-.002),(-.544,h-.008),(-.808,h-.020),
       (-.946,shoulder+.022),(-.994,shoulder),(-1,shoulder-.045),(-1,belly+.064),(-.93,belly+.022)))

POWER_S=(
 (-.440,.122,.301,.151,.267),(-.426,.150,.325,.154,.286),(-.399,.179,.366,.157,.320),
 (-.358,.203,.420,.164,.371),(-.320,.214,.463,.171,.414),(-.281,.218,.510,.173,.447),
 (-.231,.220,.537,.174,.466),(-.159,.220,.542,.174,.471),(.163,.220,.542,.174,.471),
 (.337,.219,.540,.174,.469),(.396,.211,.531,.174,.465),(.417,.187,.514,.176,.452),
)
VAN_S=(
 (-.427,.179,.504,.185,.436),(-.407,.194,.524,.184,.459),(-.365,.209,.537,.184,.468),
 (-.321,.217,.542,.184,.471),(.321,.217,.542,.184,.471),(.365,.209,.537,.184,.468),
 (.407,.194,.524,.184,.459),(.427,.179,.504,.185,.436),
)
def skin(sections,z,h,s,offset):
    for (a,wa,ha,ba,sa),(b,wb,hb,bb,sb) in zip(sections,sections[1:]):
        if a<=z<=b:
            u=(z-a)/(b-a)
            sect=body_contour(*(v+(w-v)*u for v,w in zip((wa,ha,ba,sa),(wb,hb,bb,sb))))
            for (xx,aa),(yy,bb) in zip(sect[1:10],sect[2:11]):
                if aa<=h<=bb and bb-aa>1e-7:
                    return s*(xx+(yy-xx)*(h-aa)/(bb-aa)+offset),z,h
    raise ValueError((z,h,s,offset))
def skin_panels(m,n,c,sections,s,z0,z1,h0,h1,offset):
    zs=[z0]+[u[0] for u in sections if z0<u[0]<z1]+[z1]
    for a,b in zip(zs,zs[1:]):
        q=[skin(sections,z,h,s,offset) for z,h in ((a,h0),(b,h0),(b,h1),(a,h1))]
        face(m,n,c,q if s>0 else q[::-1])

def loft(m,sets,power):
    nn="Closed formed SH 125 monocoque pressure hull" if power else "Closed steel postal van monocoque with rounded clerestory"
    for (a,*A),(b,*B) in zip(sets,sets[1:]):
        l=body_contour(*A);r=body_contour(*B)
        for t in range(len(l)):
            u=(t+1)%len(l)
            roof=6<=t<=13
            if power:
                c=("Roof silver grey" if 8<=t<=11 else "Roof lead blue") if roof else (
                   "Express Pacific blue" if t not in (0,1,18) else "Deep western blue")
                if b<=-.319:
                    c="Glancing train yellow" if roof else ("Bonnet apron shadow" if t in (0,1,18) else "Warm slab yellow")
                elif b<=-.28 and t in (0,1,2,3,16,17,18):
                    c="Warm slab yellow" if t in (3,16) else "Bonnet apron shadow"
            else:
                c=("Roof silver grey" if 8<=t<=11 else "Roof weather warm") if roof else (
                   "Mail deep frame" if t in (0,1,18) else "Mail oxblood enameled steel" if t in (2,17,3,16) else "Mail cinnabar panel")
            p=[(l[t][0],a,l[t][1]),(r[t][0],b,r[t][1]),(r[u][0],b,r[u][1]),(l[u][0],a,l[u][1])]
            face(m,nn,c,p)
    for sign in (-1,1):
        z,*profile=sets[0 if sign<0 else -1]
        p=[(x,z,h) for x,h in body_contour(*profile)]
        face(m,nn,("Warm slab yellow" if sign<0 else "Deep western blue") if power else "Mail deep frame",
             p if sign<0 else p[::-1])

def cab(m):
    def pocket(n,c,span,start,end,lift):
        a,b=span
        V=[]
        for z,*f in [start]+[u for u in POWER_S if start[0]<u[0]<end[0]]+[end]:
            sec=body_contour(*f)
            p=sorted(sec[6:11]+sec[11:15])
            def profile(x):
                for (a,b),(c,d) in zip(p,p[1:]):
                    if a<=x<=c and c>a:return b+(d-b)*(x-a)/(c-a)
                raise ValueError((z,x,p))
            V.append([(f[0]*r,z,profile(f[0]*r)+lift) for r in (a,(2*a+b)/3,(a+2*b)/3,b)])
        for A,B in zip(V,V[1:]):
            for i in range(3):face(m,n,c,(A[i],A[i+1],B[i+1],B[i]))
    for s in (-1,1):
        def span(a,b):return tuple(sorted((s*a,s*b)))
        pocket("Shallow swept SH125 two-light windscreen rubber surround","Blue dark moulding",
            span(.020,.774),POWER_S[3],POWER_S[6],.00315)
        pocket("Raked two separately glazed broad cab panes","Cab curved windshield",
            span(.058,.713),POWER_S[3],POWER_S[6],.005)
        pocket("Wide angled terminal strip on both blue pilot panes","Cab sky reflection",
            span(.086,.680),POWER_S[5],POWER_S[6],.0068)
        Pipe(m,"Single long driver wiper seated inside the raked screen angle","Slate black rail equipment",
            (s*.079,-.323,.455),(s*.120,-.272,.513),.003,7)
        # Lights have separate troughs, unlit marker, and bright older halogen.
        B(m,"Frontal cast black lamp bucket and headlamp wall","Plate lamp cast iron",
            s*.079,-.439,.067,.018,.197,.244,.005)
        D(m,"Outward white upper twin signal lamps","Warm cab halogen",(s*.086,-.451,.222),.011,"z",-.004,.002,16)
        D(m,"Older ruby light recessed below the white driving horn","Warm rear ruby",(s*.051,-.450,.211),.0072,"z",-.004,.001,12)
    B(m,"Low black fairing skirting the headstock beneath original sloped nose","Plate lamp cast iron",0,-.429,.235,.045,.149,.176,.008)
    B(m,"Center blank late model number plate without registered insignia","Deep western blue",0,-.447,.062,.009,.258,.280,.003)
    glyphs(m,"125",0,-.453,.264,.0032,"Mail buttercream stenciling")

def glyphs(m, word, x, z, h, unit, color, side=0):
    font={
        "1":("010","110","010","010","111"),"2":("110","001","010","100","111"),
        "5":("111","100","110","001","110"),"M":("101","111","101","101","101"),
        "A":("010","101","111","101","101"),"I":("111","010","010","010","111"),
        "L":("100","100","100","100","111"),"8":("111","101","111","101","111"),
        "P":("110","101","110","100","100"),"O":("010","101","101","101","010"),
        "S":("011","100","010","001","110"),"T":("111","010","010","010","010"),
    }
    for i,k in enumerate(word):
        for j,row in enumerate(font[k]):
            for c,t in enumerate(row):
                if t=="1":
                    v=(i*4+c-2*len(word)+.5)*unit
                    B(m,"Original subtle fleet stencil raised onto paint",color,
                      x if side else x+v,z+side*v, .002 if side else unit*.86,
                      unit*.86 if side else .002,h+(4-j)*unit,h+(4-j+.86)*unit,.0002)

def power_panels(m):
    def panel(n,c,s,z0,z1,y0,y1,lift):
        skin_panels(m,n,c,POWER_S,s,z0,z1,y0,y1,lift)
    for s in (-1,1):
        # Four genuine sliding cab/parcel doors; no passenger-saloon windows.
        for lo,hi,h0,h1,parcel in ((-.23,-.126,.219,.445,False),(.277,.376,.217,.451,True)):
            panel("Recess around pressed crew or parcel access door","Deep western blue",s,lo,hi,h0,h1,.0021)
            panel("Individual inset crew and parcel door skin","Light ensign blue",s,lo+.004,hi-.004,h0+.005,h1-.005,.0042)
            panel("Light aluminum compressed window seal","Satin aluminum lining",s,lo+.013,hi-.013,.362,.433,.0054)
            panel("Flush rectangular postal and crew door quarter panes","Cab curved windshield",s,lo+.017,hi-.017,.368,.426,.0073)
            panel("Glaze high blue reflection across small crew pane","Cab blue glass tint",s,lo+.019,hi-.019,.408,.423,.0079)
            panel("Raised maintenance handle and emergency key plate","Satin aluminum lining",s,hi-.026,hi-.008,.282,.292,.0071)
            B(m,"Three-step crew and parcel access ledges","Tire scuff" if "Tire scuff" in P else "Dry tire iron",s*.204,(lo+hi)/2,
              .044,hi-lo-.010,.135,.174,.006)
        panel("Dark engine radiator bay recess with independent edges","Cooling rack black",s,-.088,.249,.317,.452,.0054)
        for j in range(15):
            z=-.079+j*.0222
            # A thin lifted mounting flange on each raised slat reads at game scale.
            B(m,"Fifteen distinct steel radiator louvres on each drive side","Cooling rack gray",
              s*.225,z,.010,.0088,.324,.444,.0015)
        B(m,"Rolled metallic upper edge over radiator grille","Grille polished lip",s*.225,.081,.010,.339,.444,.452,.0018)
        for (a,b) in ((-.305,-.107),(-.091,.248),(.269,.393)):
            panel("Pale nickel pressed lower waist lining","Satin aluminum lining",s,a,b,.253,.266,.0031)
            panel("Dark stripe shot through underfloor girder","Deep western blue",s,a,b,.207,.231,.0029)
        panel("Sunward navy fleet identification enamel","Deep western blue",s,-.067,.070,.273,.308,.0050)
        glyphs(m,"125",s*.226,.007,.281,.005,"Satin aluminum lining",s)
        for z in (-.104,.012,.122,.234):
            B(m,"Individually mounted pressed engine skirt service latches","Blue dark moulding",
              s*.207,z,.014,.022,.187,.207,.003)

def bonnet(m):
    # Two real shuttered fan grilles, plus high exhaust stack just inside rear cap.
    for z in (-.033,.137):
        D(m,"Press-formed circular roof fan grille housing","Cooling rack black",(0,z,0),.058,"h",.535,.548,24)
        D(m,"Center sunken cold fan hub mounted in grille","Grille polished lip",(0,z,0),.016,"h",.546,.550,14)
        for i in range(13):
            a=i*tau/13
            p=(.014*cos(a),z+.014*sin(a),.5500)
            q=(.052*cos(a+.15),z+.052*sin(a+.15),.5500)
            Pipe(m,"Open-plan radial powder-coated fan grille ribs","Cooling rack gray",p,q,.0020,7)
    for x,z in ((-.062,.286),(.062,.261)):
        B(m,"Stamped louvered heater and rear power exhaust brow","Roof end band",x,z,.054,.086,.533,.554,.007)
        B(m,"Inset open exhaust throat dark rim","Cooling rack black",x,z,.031,.049,.552,.556,.003)
    for x in (-.150,.150):
        for z in (-.099,.081,.222):
            B(m,"Roof side equipment hinge flush with cambered steel","Roof weather warm",x,z,.030,.044,.512,.526,.005)

def vestibule(m,sh,side):
    z0=.417 if sh else .427
    z=lambda a:side*(z0+a)
    k="Deep western blue" if sh else "Mail deep frame"
    B(m,"Squared rear steel vestibule with room for next stock vehicle","Cooling rack black",0,z(.008),
      .163,.024,.208,.456,.009)
    B(m,"Milled inset gangway end door pressure leaf",k,0,z(.021),.093,.010,.218,.448,.005)
    for s in (-1,1):
        for j in range(3):
            B(m,"Individual compressed rear gangway rubber bellows ribs","Inner gangway bellows",s*.061,
              z(.016+j*.006),.020,.005,.221,.448,.0014)
        B(m,"Dark trim tying roof shroud to rear-end corridor rubber","Inner gangway bright edge",s*.057,
          z(.009),.011,.018,.221,.453,.0027)
        Pipe(m,"Real gangway bar attaches to stop ends","Pane cream rubber",
             (s*.090,z(.007),.263),(s*.090,z(.007),.360),.0020,8)
    B(m,"Separate corridor head shroud across accordion lips","Inner gangway bellows",0,z(.021),
      .141,.023,.444,.462,.005)
    B(m,"Shallow end window gasket on internal door","Glazing bezel" if "Glazing bezel" in P else "Lower seal graphite",
      0,z(.027),.069,.004,.329,.403,.002)
    B(m,"Distinct rear vestibule inset small window glass","Mid glass blue",
      0,z(.030),.057,.003,.337,.396,.002)
    B(m,"Rail end step stays inside stock 1.0 spacing","Brake link iron",0,z(.021),.134,.023,.197,.211,.003)

def van_panels(m):
    for s in (-1,1):
        def panel(n,c,z0,z1,h0,h1,lift):skin_panels(m,n,c,VAN_S,s,z0,z1,h0,h1,lift)
        for h in (.231,.432):
            panel("Original long ivory post-rail waist lining","Mail buttercream stenciling",-.399,.399,h,h+.006,.0028)
        for z0 in (-.258,.228):
            panel("Four quarter-height guard window recesses","Mail deep frame",z0-.035,z0+.035,.333,.405,.0041)
            panel("Pressed upper brass rebate around guard window","Mail brass edge",z0-.033,z0+.033,.339,.400,.0054)
            panel("Dark quarter-light guarded on the outside","Mail framed window",z0-.026,z0+.026,.345,.394,.0078)
            panel("Upper smoked blue light on guarded postal glass","Mail smoked upper glass",z0-.025,z0+.025,.378,.392,.0083)
            for z in (z0-.013,z0,z0+.013):
                panel("Three physically raised vertical guard window bars","Mail relieved hinge steel",
                      z-.00165,z+.00165,.346,.393,.012)
        for side in (-1,1):
            a,b=(-.150,-.003) if side<0 else (.003,.150)
            z=(a+b)/2
            B(m,"Two separate inset double loading door leaves on each side","Mail deep frame",s*.206,z,.038,b-a,.213,.426,.005)
            B(m,"Hinged postal door leaf outer formed steel panel","Mail cinnabar panel",s*.222,z,.019,b-a-.010,.229,.414,.0035)
            for h in (.254,.285):
                B(m,"Pressed strengthening rails integral with postal door leaf","Mail oxblood enameled steel",
                  s*.235,z,.012,b-a-.017,h,h+.009,.002)
            B(m,"Smoked parcel-security door glazing steel frame","Mail framed window",s*.235,z,.010,.073,.345,.398,.004)
            B(m,"Guarded dark aperture glazing fitted into a mail door","Mail smoked upper glass",
              s*.241,z,.004,.063,.351,.390,.0015)
            for dz in (-.017,0,.017):
                B(m,"External real bars on separate monitored pane","Mail brass edge",s*.245,z+dz,.006,.003,.348,.393,.0007)
            zhinge=side*.143
            for h in (.251,.374):
                # Contiguous physical hinge barrels with pins. Separate leaf
                # and mounting brackets remain independently editable in .blend.
                B(m,"Load door rolled steel articulated strap hinge leaf","Mail relieved hinge steel",
                  s*.237,zhinge-side*.031,.014,.062,h,h+.011,.002)
                D(m,"True vertical hinge knuckles and exposed pins","Greased cast hinge joint" if "Greased cast hinge joint" in P else "Steel running strip",
                  (s*.246,zhinge,0),.0079,"h",h-.006,h+.016,12)
                D(m,"Central strike fastener holding strap to leaf","Mail brass edge",(s*.245,zhinge-side*.020,h+.005),.0036,"x",-.001,.0025,8)
            Pipe(m,"Short proud easy-reach postal loading handle","Mail brass edge",
                 (s*.245,side*.030,.300),(s*.246,side*.067,.313),.0032,9)
        B(m,"Separate recessed mail catch plate and spring latch housing","Mail deep frame",
          s*.237,0,.013,.031,.279,.323,.003)
        B(m,"Shallow postal-loading anti-slip low running board","Brake link iron",
          s*.213,0,.055,.311,.157,.177,.004)
        for z in (-.096,0,.096):
            B(m,"Riveted steel outer step hanger","Dark under sill green",s*.221,z,.023,.022,.147,.196,.003)
        glyphs(m,"MAIL",s*.222,-.259,.277,.0056,"Mail buttercream stenciling",s)
        glyphs(m,"POST",s*.222,.227,.277,.0056,"Mail buttercream stenciling",s)
        for z in (-.323,-.245,-.165,.166,.247,.321):
            for h in (.219,.450):
                D(m,"Side panel proper raised flush countersunk fasteners","Mail brass edge",
                  (s*.220,z,h),.0022,"x",-.001,.002,7)
    for z in (-.303,-.185,-.064,.063,.182,.303):
        B(m,"Individually formed ventilator housings on arched postal roof","Roof lead blue",0,z,
          .045,.044,.538,.551,.006)

def underframe(m,is_power,ax):
    # Conventional passenger-scale 424mm relative native gauge retained.
    J.shaped(m,"Solid tapered full-width rolling stock chassis sill","Cast underframe graphite",
      [(-.112,-.433),(.112,-.433),(.161,-.397),(.180,-.275),(.180,.272),(.154,.395),(.112,.435),
       (-.112,.435),(-.154,.395),(-.180,.272),(-.180,-.275),(-.161,-.397)],.106,.179,"Dry tire iron")
    for z in ((ax[0]+ax[1])/2,(ax[2]+ax[3])/2):M.bogies(m,z)
    for s in (-1,1):
        B(m,"Native central short-shank draw pocket casting","Cast underframe graphite",0,s*.435,
          .060,.054,.128,.180,.006)
        B(m,"Native solid short drawbar fits behind vehicle faces","Brake link iron",0,s*.473,
          .025,.032,.143,.171,.005)
        B(m,"Coupler knuckles","Buffer mark grey",0,s*.494,.010,.010,.146,.168,.0017)
        for x in (-.077,.077):
            D(m,"Protected inboard recessed sprung buffers","Dry tire iron",(x,s*.434,.164),.016,"z",-.005,.005,14)
        # Reservoir, brake hoses, and clearly distinct underfloor equipment.
        D(m,"Actual underfloor pressurized brake reservoir","Air reservoir blue-grey",
          (s*.110,s*.073,.109),.022,"z",-.076,.068,14)
        for i,z in enumerate((-.107,.065)):
            B(m,"Pressed underframe fuel tank or mail battery enclosure",
                "Blue dark moulding" if is_power else "Cast underframe graphite",s*.098,z,
              .128,.106,.080,.149,.008)
            for j in range(5):
                B(m,"Scored bolt-on underfloor equipment inspection ribs","Brake link iron",s*.163,z-.033+j*.016,
                  .013,.007,.089,.136,.001)

def setup():
    R.COLORS[:]=PAL.values()
    M.P=J.P=W.P=G.P=P

def atlas(name,colors):
    def ch(k,s):return struct.pack(">I",len(s))+k+s+struct.pack(">I",zlib.crc32(k+s))
    row=b"".join(bytes.fromhex(v)*8 for v in colors)
    p=ROOT/"mods/luanttd_core/textures"/f"bl_{name}.png"
    p.write_bytes(b"\x89PNG\r\n\x1a\n"+ch(b"IHDR",struct.pack(">IIBBBBB",len(colors)*8,8,8,2,0,0,0))+
      ch(b"IDAT",zlib.compress((b"\0"+row)*8,9))+ch(b"IEND",b""))

def render(sc,name,review,center=.261,side_scale=1.27):
    s=bpy.data.collections.new("90 • Optional inspection camera and ballast")
    sc.collection.children.link(s)
    bpy.ops.mesh.primitive_plane_add(size=10,location=(0,0,-.010))
    plane=bpy.context.object
    plane.name="Optional neutral ballast and lighting proxy"
    a=bpy.data.materials["Review ballast"]
    plane.data.materials.append(a)
    def move(ob):
        for c in list(ob.users_collection):c.objects.unlink(ob)
        s.objects.link(ob)
    move(plane)
    cs=[]
    for n,p in (("cab",(2.1,-3.0,1.8)),("rear",(-2.9,2.6,1.47)),("side",(4,-.88,1.14))):
        bpy.ops.object.camera_add(location=p)
        c=bpy.context.object
        c.name=n.title()+" art inspection"
        c.rotation_euler=(Vector((0,0,center))-c.location).to_track_quat("-Z","Y").to_euler()
        c.data.type="ORTHO";c.data.ortho_scale=side_scale if n=="side" else 1.45
        move(c);cs.append((n,c))
    sc.camera=cs[0][1]
    sc.render.engine="BLENDER_WORKBENCH"
    sc.render.resolution_x,sc.render.resolution_y=1130,820
    sc.render.resolution_percentage=100
    sc.display.shading.light="STUDIO"
    sc.display.shading.studiolight_rotate_z=.35
    sc.display.shading.color_type="MATERIAL"
    sc.display.shading.show_shadows=True
    sc.display.shading.show_cavity=True
    sc.display.shading.cavity_type="BOTH"
    sc.display.shading.background_type="WORLD"
    sc.world=bpy.data.worlds.new("Neutral light blue sky")
    sc.world.color=(.170,.192,.214)
    sc.view_settings.view_transform="Standard"
    sc.view_settings.exposure=.15
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":
                v=area.spaces.active;v.shading.color_type="MATERIAL"
                v.region_3d.view_location=Vector((0,0,.26))
                v.region_3d.view_rotation=Vector((.90,-.80,.60)).to_track_quat("Z","Y")
                v.region_3d.view_distance=1.74
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art"/f"{name}.blend"),compress=True)
    if review:
        sc.render.image_settings.file_format="JPEG";sc.render.image_settings.quality=93
        for n,c in cs:
            sc.camera=c
            sc.render.filepath=str(Path(review)/f"{name}-{n}.jpg")
            bpy.ops.render.render(write_still=True)

def build(is_power):
    setup()
    name,ax=(POWER,CABS) if is_power else (VAN,VANS)
    p=POWER_S if is_power else VAN_S
    specs=[("01 • Main rolled steel shell",lambda m:loft(m,p,is_power)),
           ("02 • Roof cooling or ventilation and side door systems",lambda m:(power_panels(m),bonnet(m)) if is_power else van_panels(m)),
           ("03 • Cab and inboard corridor faces" if is_power else "03 • Postal vestibules at both ends",
            lambda m:(cab(m),vestibule(m,True,1)) if is_power else (vestibule(m,False,1),vestibule(m,False,-1))),
           ("04 • Chassis, reservoirs and bolster assemblies",lambda m:underframe(m,is_power,ax))]
    out=make_mesh()
    for _,f in specs:f(out)
    for z in ax:M.wheel(out,z)
    path=ROOT/"mods/luanttd_core/models"/f"bl_{name}.obj"
    active=sorted({col for group in out.parts.values() for _,col in group})
    sub=[tuple(PAL.values())[c] for c in active]
    recode={col:i for i,col in enumerate(active)}
    packed=make_mesh()
    for key,fs in out.parts.items():
        for poly,col in fs:
            packed.face(key,recode[col],[out.vertices[key][i] for i in poly])
    R.COLORS[:]=sub
    R.export_obj(path,W.local_obj(packed))
    first,*other=path.read_text().splitlines()
    path.write_text("# Original native LuanTTD rolling stock from tools/build_stock_rail_f_art.py\n"+"\n".join(other)+"\n")
    atlas(name,sub)
    setup()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    sc=bpy.context.scene
    sc.name="LuanTTD stock SH 125 #22" if is_power else "LuanTTD stock Rail Mail Van #28"
    sc["Upstream"]="OpenTTD 16.0-RC1 stock full length. Original imagery, not sprite extraction."
    sc["Datum"]="Native Y=0 tire contact; stock entity origin +.614; nose neutral -Z; .424 rail centers, coupler tips +- .499 at Y=.157"
    sc["Assembly"]="This is one end only. Runtime independently draws powered partner backwards." if is_power else "Standalone sealed double-leaf side load wagon. No visual load swap."
    mats=M.colors()
    for n,f in specs:
        m=make_mesh();f(m);J.geometry(sc,n,m,mats)
    # Visible wheelset editable rotations without rotating the chassis or shell.
    for i,z in enumerate(ax,1):
        mm=make_mesh();M.wheel(mm,z)
        c=J.geometry(sc,f"{5+i:02} • Axle {i}: 0.424 native alignment",mm,mats)
        pivot=bpy.data.objects.new(f"Wheelset {i} pivot",None)
        pivot.location=(0,z,M.RAD);pivot.empty_display_type="CIRCLE";pivot.empty_display_size=.045
        c.objects.link(pivot)
        for o in tuple(c.objects):
            if o!=pivot:o.parent=pivot;o.location=(0,-z,-M.RAD)
    render(sc,name,os.getenv("RAIL_F_REVIEW"))

if __name__=="__main__":
    for power in (True,False):build(power)

#!/usr/bin/env python3
"""Original Uhl Livestock Van #136, source-identical runtime geometry."""
from math import cos, pi, sin
from pathlib import Path
import os
import struct
import sys
import zlib

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
sys.path.append(os.getenv("LUANTTD_HELPERS",str(ROOT/"tools")))
import build_stock_road_primitives as road

w,r,bpy,V=road.w,road.r,road.bpy,road.Vector
B,C,rod=road.B,road.C,road.rod
STEM="stock_uhl_livestock_van"
COL={
 "Axle grey":"565e5c","Frame":"3a4443","Rubber":"262c30","Tyre scuff":"4b5051",
 "Hub":"677773","Nurled iron":"53615e","Rim":"acb1a5","Roof dark":"3b4648",
 "Stock Uhl midnight":"344d65","Uhl dark petrol enamel":"3f657e","Uhl storm enamel":"528099",
 "Uhl sky face enamel":"6291a7","Uhl pinstripe brass":"bea978","Uhl warm door ivory":"c7c2a3",
 "Uhl cabin surround":"314756","Uhl grille dark":"344754","Uhl cast trim":"748d95",
 "Tarnished bright alloy":"a7b8b8","Uhl bumper painted steel":"4d6675","Uhl lower sill":"3e5361",
 "Glass rim":"2a3941","Glass":"3b5969","Glass glint":"7c9ba9","Glass rear shade":"435d67",
 "Lens bright warm":"ebd3a6","Red lens":"b85344","Clear lens":"bfc7ba","Amber signal":"d59c5b",
 "Number plate dark":"344044","Number plate yellow":"ddbf81","Deck steel":"69757a",
 "Deck charcoal oak":"5d5347","Deck warm oak":"716754","Cambered roof outer charcoal":"454c4b",
 "Canvas shade seam":"393f3f","Tarpaulin bump shade":"505956","Canvas broad daylight":"59615e",
 "Steel rafters":"435a63","Painted uprights steel blue":"527589","Steel uprights shadow":"3e5a6f",
 "Vent top canopy edges":"6b8c99","Vent slat enamel blue":"658fa2","Vent slat low shadow":"4d7082",
 "Vent exposed worn edges":"8ea8ae","Galvanized vent support":"7f9698","Vent rear tab":"849196",
 "Aged low panel screws":"a6aea2","Panel lower rub rail":"56778a","Seaworn lower panels":"577f93",
 "Door retaining dark":"3c4f59","Door hinge body warm":"788781","Door handle bent nickel":"9fa9a3",
 "Dark canvas roof rings":"566062","Rope loop fiber":"948975","Stamp contrast":"cfc9ad",
 "Pavement cool":"586566","Lanes wheat":"dcc496","Dull warm step":"757e78",
}
while len(COL)<64:
    COL[f"Material reserve {len(COL)}"]="687478"
P={c:i for i,c in enumerate(COL)}
w.P=road.P=P
r.COLORS[:]=COL.values()
AX=(-.502,.461)
R=.128
T=.223
FRONT,REAR=-.178,.758


def f(m,g,c,pts):
    road.f(m,g,c,pts)


def chassis(m):
    road.wheels(m,*AX,T,R,"Uhl cast trim",True)
    for s in (-1,1):
        B(m,"Independent long C-channel chassis","Frame",s*.150,.005,.046,1.466,.140,.206,.008)
        B(m,"Continuous worn bottom steel lip","Axle grey",s*.153,.053,.054,1.382,.141,.152,.004)
        for z in AX:
            road.fender(m,"Real shaped removable splash guards",s*.237,z,R,R+.036,.102,"Uhl lower sill")
            B(m,"Heavy hanging mudflap with mounting bolt","Rubber",s*.221,z+.135,.120,.025,.062,.209,.004)
            for k in range(3):
                B(m,"Nested transverse laminated suspension leaf spring","Nurled iron",s*.145,z,.036,
                  .198-k*.023,.143+k*.008,.148+k*.008,.003)
        B(m,"Cab access checker step behind steering axle","Dull warm step",s*.236,-.273,
          .110,.144,.155,.178,.009)
        for z in (-.319,-.293,-.267,-.241):
            B(m,"Separate anti-skid ridges on step","Uhl lower sill",s*.248,z,.052,.006,.176,.181,.001)
    for z in (-.662,-.218,.086,.387,.673):
        B(m,"Wide welded transverse ladder joints","Frame",0,z,.334,.050,.143,.219,.012)
    B(m,"Old forward-control compensating fuel tank","Nurled iron",.154,.151,.135,.263,.104,.201,.017)
    for z in (.084,.232):
        B(m,"Fuel metal safety bands around tank","Uhl cast trim",.155,z,.142,.021,.118,.202,.005)
    C(m,"Dark drive shaft beneath platform","Frame",(0,.032,.120),.017,"z",-.366,.421,12)
    C(m,"Rear axle crown torque housing","Axle grey",(0,.469,.128),.060,"x",-.074,.074,12)
    B(m,"Rear enclosed road toolkit","Nurled iron",-.168,.153,.130,.265,.117,.213,.017)
    B(m,"Toolkit pressed inset door","Uhl lower sill",-.237,.154,.016,.212,.141,.201,.003)
    B(m,"Independent nickel toolkit pull","Uhl cast trim",-.247,.190,.011,.044,.166,.183,.004)


def cab(m):
    def line(z,h,half,low):
        return z,[(-half*.82,low),(half*.82,low),(half,low+.035),(half,h-.081),
          (half*.91,h-.026),(half*.72,h),(-half*.72,h),(-half*.91,h-.026),
          (-half,h-.081),(-half,low+.035)]
    rows=(line(-.780,.415,.199,.215),line(-.743,.513,.243,.214),
          line(-.700,.596,.258,.210),line(-.653,.640,.265,.205),
          line(-.564,.651,.269,.205),line(-.318,.651,.269,.205),
          line(-.242,.635,.252,.212),line(-.200,.591,.227,.225))
    road.section_hull(m,"Sculpted Uhl sloping cab-over body under canvas van",
      rows,["Stock Uhl midnight","Uhl lower sill","Uhl dark petrol enamel","Uhl storm enamel",
            "Uhl sky face enamel","Uhl storm enamel","Uhl sky face enamel","Uhl storm enamel",
            "Uhl dark petrol enamel","Uhl lower sill"],"Uhl dark petrol enamel")
    verts=((-.753,.228,.487),(-.743,.243,.513),(-.700,.258,.596),(-.653,.265,.640),(-.634,.265,.642))
    for name,color,span,lift,data in (
       ("Continuous formed rubber screen surround","Glass rim",.76,.010,verts),
       ("Uhl twin wide deep laminations","Glass",.696,.016,verts[1:-1]),
       ("Skylight return along swept screen top","Glass glint",.675,.018,((-.677,.261,.618),(-.662,.264,.628))),
    ):
        for (z0,w0,h0),(z1,w1,h1) in zip(data,data[1:]):
            for s in (-1,1):
                f(m,name,color,((s*.012,z0,h0+lift),(s*w0*span,z0,h0+lift),
                  (s*w1*span,z1,h1+lift),(s*.012,z1,h1+lift))[::s])
    for s in (-1,1):
        rod(m,"Split double wiper arm projectors","Glass rim",
            (s*.040,-.737,.544),(s*.123,-.714,.586),.0035)
        rod(m,"Short thin wiper blade","Glass rim",
            (s*.123,-.714,.586),(s*.147,-.695,.615),.0030)
        B(m,"Side deep cab door rubber reveal","Uhl cabin surround",s*.270,-.441,.015,.282,
            .278,.564,.009)
        B(m,"Cab door independent cobalt outer pressing","Uhl dark petrol enamel",s*.277,-.441,.014,.269,
            .286,.555,.007)
        road.panes(m,"Period tall single-stage driver window",s*.284,-.443,.224,.406,.541,
                   "Glass rim","Glass")
        B(m,"Window fixed quarter slider guide","Tarnished bright alloy",s*.301,-.513,.007,.013,
            .417,.526,.002)
        B(m,"Faded two-tone mid door waist paint","Uhl warm door ivory",s*.286,-.439,.011,.244,
            .345,.361,.003)
        B(m,"Independent nickel door handle","Tarnished bright alloy",s*.292,-.342,.010,.041,
            .367,.383,.004)
        rod(m,"Tucked wheel envelope mirror short stem","Uhl grille dark",
            (s*.261,-.635,.496),(s*.285,-.643,.541),.006)
        B(m,"Original period blue rounded square mirrors","Uhl dark petrol enamel",s*.291,-.644,
            .037,.027,.509,.568,.006)
        B(m,"Rearward facing mirror bright silver","Tarnished bright alloy",s*.292,-.626,.030,
            .009,.519,.558,.004)
        B(m,"Front flank oval amber winker","Amber signal",s*.214,-.775,.045,.017,.357,.381,.004)
        B(m,"Original outboard matching headlamp recess","Uhl grille dark",s*.174,-.780,.122,
            .037,.250,.344,.009)
        B(m,"Actual wide forward frosted warm lamp","Lens bright warm",s*.172,-.801,.097,
            .012,.264,.327,.006)
    B(m,"Independent broad 1970s Uhl stamp bumper","Uhl bumper painted steel",0,-.777,
        .497,.069,.157,.224,.014)
    B(m,"True inset broad crosshatch radiator grille aperture","Uhl grille dark",0,-.785,
        .201,.037,.256,.351,.010)
    for i in range(5):
        B(m,"Horizontal pressed grille detail distinct from coal Uhl","Uhl cast trim",0,-.808,
          .174,.008,.266+i*.015,.269+i*.015,.001)
    for y in (-.812,-.818):
        B(m,"Front unbranded number plate backing","Number plate dark",0,y,.125,.011,.178,.205,.006)
    for j in range(7):
        B(m,"Tiny pressed white ID segments","Uhl warm door ivory",(j-3)*.014,-.825,
          .006,.006,.183,.195+(.004*(j%2)),.001)
    B(m,"Low rounded painted upper cab vent","Uhl sky face enamel",0,-.438,.192,.184,.640,.669,.012)
    B(m,"Rear tempered cab look-through control pane","Glass rear shade",0,-.194,.290,.015,.439,.524,.005)


def slat(m,s,z,span,h,name):
    """Thin projecting horizontal rain-louver, with cross-section pitching out."""
    x=s*.241
    shape=[(x-s*.010,h+.006),(x+s*.010,h-.008),
           (x+s*.010,h-.018),(x-s*.010,h-.004)]
    if s>0:
        shape.reverse()
    road.section_hull(m,name,[(z-span/2,shape),(z+span/2,shape)],
      ["Vent slat enamel blue","Vent slat low shadow","Vent exposed worn edges","Vent slat low shadow"],
      "Vent exposed worn edges")


def van(m):
    f0,f1=FRONT,REAR
    dist=f1-f0
    center=(f0+f1)/2
    B(m,"Independent hardwood livestock deck under cattle van","Deck steel",0,center,
      .485,dist,.230,.268,.012)
    for j in range(10):
        x=(j-4.5)*.042
        B(m,"Actual separate heavily worn truck livestock floorboards",
          "Deck charcoal oak" if j%3 else "Deck warm oak",x,center,.040,dist-.019,.265,.282,.0016)
    for z in (-.110,.146,.413,.672):
        B(m,"True inner anti-slip transverse livestock mat rib","Rubber",0,z,.421,.021,.282,.289,.002)
    B(m,"Opaque front cabin protection bulkhead","Seaworn lower panels",0,f0,.450,.031,.268,.560,.010)
    B(m,"Crossbar at steel upper bulkhead enclosure","Uhl lower sill",0,f0,.471,.042,.468,.492,.005)
    posts=(f0+.016,.048,.279,.511,.739)
    for s in (-1,1):
        x=s*.236
        B(m,"Continuous solid lower period stamped stock side walls","Seaworn lower panels",
          x,center,.029,dist-.022,.266,.411,.009)
        B(m,"Horizontal low panel rub bars and load marker","Panel lower rub rail",x+s*.009,center,
          .022,dist-.047,.299,.325,.006)
        B(m,"Slit surround lower blue pressed eave rail","Steel uprights shadow",x+s*.004,center,
          .041,dist-.012,.405,.434,.005)
        B(m,"Cold forged strip just below upper louvers","Vent top canopy edges",x+s*.011,center,
          .017,dist-.028,.426,.437,.002)
        B(m,"Steel upper straight eave canopy mounting channels","Vent top canopy edges",x+s*.003,center,
          .038,dist,.554,.586,.006)
        for z in posts:
            B(m,"Reinforced steel uprights bridging side vent openings","Steel uprights shadow",x,z,
              .040,.032,.265,.590,.007)
            B(m,"Pressed flare on upright face","Painted uprights steel blue",x+s*.012,z,
              .020,.022,.288,.571,.003)
            for h in (.310,.551):
                C(m,"True separate bolted upright mounting","Aged low panel screws",(x+s*.021,z,h),
                  .005,"x",-.003,.003,6)
        for a,b in zip(posts,posts[1:]):
            span=(b-a)-.026
            for y in (.457,.501,.545):
                slat(m,s,(a+b)/2,span,y,"Individually pitched open side livestock ventilation slats")
            for fraction in (.34,.67):
                z=a+(b-a)*fraction
                B(m,"Narrow internal captive vent slat hanger ties","Galvanized vent support",s*.228,z,
                  .013,.010,.435,.554,.0018)
        rod(m,"Inside low livestock rub guard","Deck steel",
            (s*.206,f0+.018,.360),(s*.206,f1-.022,.360),.0095)
        for z in (.180,.517):
            B(m,"Separate exterior canvas hook clip brackets","Dark canvas roof rings",x+s*.021,z,
              .025,.040,.559,.581,.006)
            rod(m,"Small original tarpaulin binding loops","Rope loop fiber",
                 (x+s*.022,z-.016,.576),(x+s*.010,z+.008,.599),.0032)
    for z in (.156,.473):
        for x in (-.182,.182):
            B(m,"Interior static livestock partition stanchions","Deck steel",x,z,.019,.027,
              .278,.487,.004)
        for h in (.358,.428,.477):
            rod(m,"Individual lower interior cattle partition crossrails","Steel rafters",
                (-.185,z,h),(.185,z,h),.007)
    for s in (-1,1):
        z=f1+.004
        mid=s*.119
        B(m,"Two independent large rear lower loader doors","Seaworn lower panels",mid,z,.222,.031,.265,.448,.009)
        B(m,"One rectangular upper loader door perimeter outer handle rail","Door retaining dark",s*.221,z,
            .024,.038,.442,.591,.003)
        B(m,"One rectangular upper loader door perimeter inner join rail","Door retaining dark",s*.013,z,
            .023,.038,.442,.591,.003)
        B(m,"Two rear full door header bars","Painted uprights steel blue",mid,z,.223,.038,.565,.590,.007)
        for h in (.477,.522,.557):
            B(m,"Independent rear door ventilating short slats","Vent slat enamel blue",mid,z+.003,
              .182,.025,h-.021,h-.005,.003)
            B(m,"Thin worn edge of rear hatch ventilation slat","Vent exposed worn edges",
              mid,z+.017,.182,.008,h-.022,h-.015,.002)
        for h in (.320,.401,.546):
            x=s*.221
            C(m,"Loading door complete hinge barrel","Door hinge body warm",(x,z+.023,h),.010,
              "h",-.013,.013,10)
            B(m,"Separate gate door mounting hinge tongue","Door hinge body warm",s*.193,z+.020,
              .045,.014,h-.010,h+.008,.002)
        B(m,"Detachable door latch pivot plates","Door retaining dark",s*.045,z+.019,.044,.013,
          .339,.390,.005)
        rod(m,"Actual long outside vertical loader latching bar","Door handle bent nickel",
            (s*.035,z+.027,.299),(s*.036,z+.027,.523),.0054)
        rod(m,"Latch lever small angled locking handle","Door handle bent nickel",
            (s*.036,z+.028,.413),(s*.082,z+.035,.431),.0046)
        B(m,"Separate rear lighting pods mounted below van","Number plate dark",s*.159,.762,
          .106,.046,.166,.239,.008)
        for j,c in enumerate(("Clear lens","Red lens","Amber signal")):
            B(m,"Directional replacement rear lamp lenses","Amber signal" if j==2 else c,s*(.135+j*.023),.789,
              .020,.011,.186,.221,.003)
    B(m,"Independent tail drop ramp sill treadplate","Uhl lower sill",0,.761,.451,.060,.232,.259,.007)
    B(m,"Rear livestock loader underride bumper","Frame",0,.753,.492,.034,.136,.179,.013)
    B(m,"Original plain rear registration plate","Number plate yellow",0,.788,.132,.014,.152,.180,.004)
    for j in range(7):
        B(m,"Unbranded low contrast rear plate markings","Number plate dark",(j-3)*.015,.798,
          .005,.006,.156,.166+(j%3)*.003,.001)


def roof(m):
    records=((-.192,.228,.614),(-.163,.248,.667),(-.115,.254,.692),(-.072,.254,.684),
             (.033,.254,.681),(.126,.254,.692),(.174,.254,.683),(.274,.254,.682),
             (.362,.254,.691),(.409,.254,.683),(.528,.254,.682),(.618,.254,.691),
             (.664,.254,.685),(.724,.252,.685),(.767,.245,.656),(.789,.229,.616))
    def ridge(w,h,s=0):
        th=[pi-i*pi/16 for i in range(17)]
        return [((w-s)*cos(a),.574 + (h-.574-s)*sin(a)) for a in th]
    rings=[(z,ridge(w,h)+list(reversed(ridge(w,h,.011)))) for z,w,h in records]
    col=("Canvas shade seam","Canvas shade seam","Cambered roof outer charcoal",
         "Tarpaulin bump shade","Tarpaulin bump shade","Canvas broad daylight","Canvas broad daylight",
         "Canvas broad daylight","Canvas broad daylight","Canvas broad daylight","Canvas broad daylight",
         "Tarpaulin bump shade","Tarpaulin bump shade","Cambered roof outer charcoal",
         "Canvas shade seam","Canvas shade seam")
    tag="Closed thin charcoal canvas cover arched across the van"
    for (z0,a),(z1,b) in zip(rings,rings[1:]):
        for i,v0 in enumerate(a):
            j=(i+1)%len(a)
            tone=col[i] if i<16 else "Steel rafters"
            f(m,tag,tone,((v0[0],z0,v0[1]),(b[i][0],z1,b[i][1]),
                          (b[j][0],z1,b[j][1]),(a[j][0],z0,a[j][1]))[::-1])
    for direction,(z,ring) in ((-1,rings[0]),(1,rings[-1])):
        for i in range(16):
            a,b,c,d=ring[i],ring[i+1],ring[-i-2],ring[-i-1]
            f(m,tag,"Canvas shade seam",[(x,z,h) for x,h in (a,b,c,d)][::direction])
    for z in (-.091,.126,.361,.618,.726):
        profile=[(x,z,h-.008) for x,h in ridge(.245,.686)]
        for a,b in zip(profile,profile[1:]):
            rod(m,"Separately modeled ventilated roof support bows","Steel rafters",a,b,.006)
    for s in (-1,1):
        rod(m,"Canvas visible sewn hem alongside frame","Canvas shade seam",
            (s*.250,FRONT,.582),(s*.250,REAR,.582),.0065)
        for z in (-.083,.034,.147,.268,.387,.504,.624,.721):
            C(m,"Tarpaulin cover grommets pressed into the hem","Dark canvas roof rings",
                (s*.253,z,.583),.005,"x",-.002,.003,8)


def palette(path):
    def chunk(k,d):return struct.pack(">I",len(d))+k+d+struct.pack(">I",zlib.crc32(k+d))
    row=b"".join(bytes.fromhex(v)*16 for v in COL.values())
    path.write_bytes(b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",1024,16,8,2,0,0,0))+
                     chunk(b"IDAT",zlib.compress((b"\0"+row)*16))+chunk(b"IEND",b""))


def make():
    palette(ROOT/"mods/luanttd_core/textures"/f"bl_{STEM}_atlas.png")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene
    scene.name="LuanTTD | Uhl Livestock Van #136"
    scene["source_version"]="OpenTTD 16.0-RC1"
    scene["stock_engine_id"]=136
    scene["body_view_rule"]="One exterior: OpenTTD image 21 full-state offset is 0."
    scene["native_setup"]=".42 scale, true tire contact Y=0, nose −Z"
    mats=r.materials()
    for name,mat in zip(COL,mats):
        mat.name=name
        p=mat.node_tree.nodes.get("Principled BSDF")
        p.inputs["Roughness"].default_value=.35 if name.startswith("Glass") else .86 if "Canvas" in name else .61
        p.inputs["Metallic"].default_value=.32 if "alloy" in name or name.startswith("Galvanized") else 0
    for i,(name,builder) in enumerate((("Frame, axles and steps",chassis),("Original Uhl forward-control cab",cab),
                                       ("Breathing enclosure, deck and loader doors",van),
                                       ("Independent arched storm canopy",roof)),1):
        c=bpy.data.collections.new(f"{i:02} • {name}")
        scene.collection.children.link(c)
        if i==1:
            m=r.Mesh(r.terrain_height(0))
        prev=set(m.parts)
        builder(m)
        work=r.Mesh(r.terrain_height(0))
        for group in set(m.parts)-prev:
            work.parts[group]=m.parts[group]
            work.vertices[group]=m.vertices[group]
        r.to_blender(work,c,mats)
    file=ROOT/"mods/luanttd_core/models"/f"bl_{STEM}.obj"
    r.export_obj(file,w.local_obj(m))
    lines=file.read_text().splitlines()
    lines[0]="# Original Uhl livestock road lorry; regenerate with tools/build_stock_uhl_livestock_art.py"
    file.write_text("\n".join(lines)+"\n")
    prev=set(scene.objects)
    road.studio(scene)
    studio=bpy.data.collections.new("90 • Studio views only (not exported)")
    scene.collection.children.link(studio)
    front=scene.camera
    views=[]
    for i,(name,loc) in enumerate((("front",(2.14,-2.54,1.53)),
                                  ("rear",(2.09,2.65,1.46)),("vents",(2.61,.28,.82)))):
        cam=front
        if i:
            cam=front.copy()
            cam.data=front.data.copy()
            scene.collection.objects.link(cam)
        cam.name=f"{name.title()} inspection"
        cam.location=loc
        cam.data.ortho_scale=1.96
        cam.rotation_euler=(V((0,0,.338))-cam.location).to_track_quat("-Z","Y").to_euler()
        views.append((name,cam))
    for ob in set(scene.objects)-prev:
        for c in list(ob.users_collection):c.objects.unlink(ob)
        studio.objects.link(ob)
    scene.render.resolution_x,scene.render.resolution_y=1000,720
    scene.render.resolution_percentage=100
    scene.view_settings.exposure=.48
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art"/f"{STEM}.blend"),compress=True)
    if qa:=os.getenv("UHL_LIVESTOCK_QA"):
        scene.render.image_settings.file_format="JPEG"
        scene.render.image_settings.quality=91
        for name,cam in views:
            scene.camera=cam
            scene.render.filepath=str(Path(qa)/f"uhl-livestock-{name}.jpg")
            bpy.ops.render.render(write_still=True)


if __name__=="__main__":
    make()

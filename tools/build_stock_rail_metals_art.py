#!/usr/bin/env python3
"""Original stock #35 Iron Ore Hopper and #36 Steel Truck for OpenTTD 16.0-RC1."""
from copy import deepcopy
from math import cos,sin,pi,tau,sqrt
from pathlib import Path
from random import Random
import os,sys,struct,zlib
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,os.getenv("LUANTTD_HELPERS",str(ROOT/"tools")))
import build_rail_coal_wagon_art as C
import build_chaney_jubilee_art as J
r,w,bpy,V=C.r,C.w,C.bpy,C.Vector
B,T,bar=w.slab,w.circular,C.bar
STOCK=(("rail_iron_ore_hopper",35,"Iron Ore Hopper",30,2773),("rail_steel_truck",36,"Steel Truck",20,2769))
EXTRA={
 "Mineral enamel navy":"3f647d","Mineral top milled rim blue":"7794a6","Mineral weathered highlight":"5f7f91",
 "Well inner soot":"41494b","Mineral steep metal pan":"59626a","Iron oxidized upper":"94593d",
 "Iron heat glint":"a3614b","Iron density dark":"734535","Iron ochre facet":"8b6749","Iron recess dust":"654138",
 "Iron raw terracotta":"a55a41","Iron wet seam":"543a34","Flatcar hardwood brown":"78634b",
 "Flatcar hardwood sunward":"8d7657","Flatcar hardwood dark wet":"61584a","Flatcar faded carrier enamel":"527887",
 "Cold rolled coil galvanized flank":"757e86","Cold rolled coil edge":"9eaaa9","Cold rolled shaded rim":"596568",
 "Iron mill scale":"535e63","Polished steel pack circumferential lines":"a2afab","Cold coil bore darkness":"434b4d",
 "Blue black steel bands":"3c4d51","Rolling stock clamp iron":"7d8c85","Brace guide primer red":"8b664d",
 "Original wagon stencil straw":"e1cda3","Original wagon stencil background":"384955",
}
P={}
def setup(i):
    global P
    base={k:v for k,v in C.P.items() if not k.startswith(("Coal ","Ash "))}
    pal=base|EXTRA
    if i==36:
        pal|={"Beam highlights":"7e7b69","Warm bauxite buffer beam":"6c664b","Body graphite":"54696d"}
    while len(pal)<64:pal[f"Unused neutral {len(pal)}"]="778082"
    assert len(pal)==64
    r.COLORS[:]=pal.values()
    P=w.P={k:i for i,k in enumerate(pal)}
    return pal

def m():return r.Mesh(r.terrain_height(0))
def f(o,n,c,p):o.face(n,P[c],p)

def underframe(o,steel):
    rim="Flatcar faded carrier enamel" if steel else "Mineral enamel navy"
    C.wheelset(o)
    w.faces_xz(o,"Tapered formed cargo wagon closed center chassis", "Deep chassis iron",
       [(-.109,-.416),(.109,-.416),(.155,-.376),(.191,-.329),(.191,.329),(.152,.376),(.109,.416),(-.109,.416),(-.152,.376),(-.191,.329),(-.191,-.329),(-.155,-.376)],.127,.191,"Worn chassis edges")
    for s in (-1,1):
        x=s*.202
        B(o,"Pressed long bridge side sill beneath independent load body","Deep chassis iron",x,0,.043,.746,.141,.209,.007)
        B(o,"Pressed horizontal thin chassis side toe sleeve",rim,s*.224,0,.018,.731,.190,.209,.003)
        for z in (-.363,-.227,.226,.365):
            T(o,"Original paired side rivets on strengthened frame shoulder","Rivet polished",(s*.234,z,.182),.005,
              "x",-.002,.002,8)
        bar(o,"Actual slanted handbrake lever meets the audible rocking tie","Guide iron",
            (s*.218,-.125,.151),(s*.240,.145,.243),.017,.016)
        bar(o,"Polished visible narrow end of articulated handbrake lever","Rubbed brake steel",
            (s*.242,.111,.233),(s*.248,.168,.259),.009,.008)
        for z in (-.351,.351):
            B(o,"Original protective footsteps flange secured to end beam","Deep chassis iron",
             s*.210,z,.066,.041,.099,.158,.006)
            B(o,"Independent riveted anti-slip step footplate","Guide iron",s*.209,z,.067,.033,.095,.109,.006)
    for s in (-1,1):
        z=s*.397
        B(o,"Original ribbed carriage headstock fits between narrow buffer pairs","Warm bauxite buffer beam",
          0,z,.261,.032,.132,.210,.006,"Beam highlights")
        B(o,"Boxed sprung short central draw pocket","Deep chassis iron",0,s*.445,.106,.042,.123,.182,.008)
        B(o,"Short solid drawbar at full stock length","Blackened buffers",0,s*.468,.042,.032,.141,.175,.006)
        B(o,"Coupler knuckles","Knuckles",0,s*.490,.032,.018,.146,.168,.005)
        for x in (-.105,.105):
            T(o,"Short inboard buffer pair, backed not protruding","Blackened buffers",
              (x,s*.418,.164),.030,"z",-.009,.009,14)
            T(o,"Pressed nickel buffer end faces","Worn chassis edges",(x,s*.427,.164),.023,
              "z",-.002,.002,14)
        bar(o,"Separate brake hose lowering away from pivot and coupling envelope","Guide iron",
            (-.072,s*.426,.151),(-.080,s*.455,.112),.009,.013)

def ring(x,z,h,c):
    return [(a,b,h) for a,b in w.rect(0,0,x*2,z*2,c)]

def hopper(o):
    # Real open volume and steel wall thickness as one closed extruded skin.
    rows=(ring(.162,.357,.204,.028),ring(.174,.373,.227,.027),
          ring(.222,.399,.466,.031),ring(.231,.409,.485,.032),
          ring(.206,.386,.483,.028),ring(.154,.354,.271,.024))
    n="Continuous watertight steep sided pressed iron ore hopper and floor"
    f(o,n,"Mineral steep metal pan",rows[0][::-1])
    for k,(a,b) in enumerate(zip(rows,rows[1:])):
        for j in range(8):
            i=(j+1)%8
            color=("Mineral weathered highlight","Mineral enamel navy","Mineral top milled rim blue","Mineral top milled rim blue","Well inner soot")[k]
            f(o,n,color,(a[j],a[i],b[i],b[j]))
    f(o,n,"Mineral steep metal pan",rows[-1])
    for s in (-1,1):
        # Eight raised structural fins on each side. Narrow pads and actual
        # angle transitions differ from the horizontally planked stock van.
        for i in range(8):
            z=-.333+i*.095
            p=((s*.180,z,.234),(s*.199,z+.006,.327),(s*.225,z+.013,.460))
            for a,b in zip(p,p[1:]):
                bar(o,"Pronounced rolled tapered vertical ore hopper strengthening ribs","Mineral weathered highlight",a,b,.022,.021)
            B(o,"Independent riveted saddle shoe behind each rib","Mineral enamel navy",
              s*.181,z,.020,.035,.228,.257,.005)
        bar(o,"Continuous physically rolled upper hatch safe edge","Mineral top milled rim blue",
          (s*.227,-.366,.477),(s*.227,.366,.477),.011,.012)
        B(o,"Low longitudinal fake-free welded lower ore latch rail","Mineral weathered highlight",
          s*.177,0,.021,.710,.244,.262,.004)
        for z in (-.225,.191):
            B(o,"Bauxite hinge mounts for separate bottom dump hatches","Oxidised irons",
               s*.141,z,.046,.271,.205,.229,.004)
            T(o,"Visible discharge linkage pinned in levers","Guide iron",(s*.160,z,.216),.012,"z",-.073,.073,10)
            bar(o,"Separate articulated discharge rocker links to a dump door",
                "Oxidised irons",(s*.143,z-.080,.218),(s*.220,z-.045,.175),.017,.019)
        B(o,"Little recessed industrial railway mineral identification plaque", "Original wagon stencil background",
          s*.213,-.037,.014,.114,.374,.419,.005)
        for j in range(3):
            B(o,"Faint original pale three-bar ore identification", "Original wagon stencil straw",
               s*.222,-.058+j*.021,.004,.010,.383,.410,.001)
    for s in (-1,1):
        for h in (.304,.404):
            B(o,"Outer pressed panel stiffener rib on sloping hopper end",
                "Mineral weathered highlight",0,s*(.374+(h-.23)*.11),.351,.016,h-.008,h+.008,.003)
        for x in (-.167,.167):
            bar(o,"Single physical end ladder rail climbing from platform to top lip","Guide iron",
                (s*x,-.388,.241),(s*x,-.411,.470),.008,.009)
    for h in (.281,.328,.373,.418):
        z=-.389-(h-.24)*.093
        bar(o,"Individual end ladder footholds clear inside coupler envelope","Rubbed brake steel",
            (-.172,z,h),(.172,z,h),.008,.008)

def steel_deck(o):
    # Low platform and permanently fitted timber coil cradle. The separate
    # raised weather wood is along the deck and remains when unloaded.
    w.faces_xz(o,"Original broad low cargo-only steel deck shell",
       "Flatcar faded carrier enamel",w.rect(0,0,.433,.847,.032),.187,.234,"Flatcar hardwood dark wet")
    for i in range(13):
        x=(i-6)*.030
        color=("Flatcar hardwood brown","Flatcar hardwood sunward","Flatcar hardwood dark wet")[(i+1)%3]
        B(o,"Distinct individual longitudinal recessed wooden deck strips",color,x,0,
           .029,.778,.226,.241,.002)
    for s in (-1,1):
        B(o,"Cold rolled low end platform edge and four attachment ears","Flatcar faded carrier enamel",
           0,s*.410,.414,.029,.224,.252,.005)
        for z in (-.374,-.118,.118,.374):
            B(o,"Fixed short external coil stops and anchoring bolster heels",
              "Steel shade under sill",s*.193,z,.038,.025,.222,.280,.004)
            T(o,"Separately bored anchor tie ring in sleeping bed",
              "Brace guide primer red",(s*.212,z,.253),.0078,"x",-.0025,.004,9)
        for z in (-.249,0,.249):
            for u in (-1,1):
                dz=z+u*.079
                bar(o,"True cut wooden cradle wedge under each removable steel coil","Flatcar hardwood dark wet",
                    (s*.027,dz,.263),(s*.185,dz,.263),.027,.038)
                B(o,"Angle-iron cradles bolted across both side plates","Guide iron",
                   s*.173,dz,.053,.030,.233,.267,.004)
        B(o,"Short raised clip fastener cover gauge plate","Original wagon stencil background",
          s*.219,.032,.009,.133,.186,.218,.004)
        for i in range(4):
            B(o,"Original pale four-square steel carrier index marks","Original wagon stencil straw",
                s*.225,-.000+i*.020,.003,.011,.195,.209,.0012)

def iron(o):
    n="Closed original taper packed hematite mass behind iron ore rim"
    rng=Random(3516048)
    z0,z1=-.361,.361
    def h(x,z):
        return .428 + (.028-.018*(x/.166)**2)*max(0,sin(pi*(z-z0)/(z1-z0)))**.62+.006*cos(z*23)
    row=[[(i*.027-.162,z,h(i*.027-.162,z)+rng.uniform(-.00372,.00372))
          for i in range(13)] for z in (z0+(z1-z0)*i/25 for i in range(26))]
    cols=("Iron density dark","Iron oxidized upper","Iron ochre facet","Iron raw terracotta","Iron heat glint")
    for a,b in zip(row,row[1:]):
        for i in range(12):f(o,n,rng.choice(cols),(a[i],a[i+1],b[i+1],b[i]))
    edge=row[0][:-1]+[a[-1] for a in row[:-1]]+row[-1][:0:-1]+[a[0] for a in row[:0:-1]]
    base=[(x*.89,z*.97,.275) for x,z,_ in edge]
    for i,a in enumerate(edge):
        j=(i+1)%len(edge)
        f(o,n,"Iron wet seam",(a,base[i],base[j],edge[j]))
        f(o,n,"Iron recess dust",(base[j],base[i],(0,0,.275)))
    # Tiny fragmented 3D ore stays strictly under the metal rim.
    for j in range(13):
        for i in range(6):
            x=(i-2.5)*.046+rng.uniform(-.012,.012)
            z=-.328+j*.054+rng.uniform(-.014,.014)
            y=h(x,z)
            angle=rng.random()*tau
            arr=[(cos(angle+tau*k/6)*rng.uniform(.015,.030),sin(angle+tau*k/6)*rng.uniform(.016,.029)) for k in range(6)]
            a=[(x+u*.78,z+v*.78,y-.013) for u,v in arr]
            b=[(x+u,z+v,y+rng.uniform(-.0044,.0035)) for u,v in arr]
            t=[(x+u*.52,z+v*.51,min(.478,y+rng.uniform(.012,.026))) for u,v in arr]
            name=f"Individual closed railway hematite ore rock {j*6+i+1:03d}"
            f(o,name,"Iron wet seam",a[::-1]);f(o,name,"Iron oxidized upper",t)
            for k in range(6):
                u=(k+1)%6
                f(o,name,cols[(k+j)%5],(a[k],a[u],b[u],b[k]))
                f(o,name,cols[(k+i+2)%5],(b[k],b[u],t[u],t[k]))

def coils(o):
    # Three single shipped coils. Wide transverse rolled-strip axes visibly
    # have empty circular bores, with authentic concentric winding seams.
    r0=.100;cy=.323
    contour=((- .160,.066),(-.172,.066),(-.172,.084),(-.167,.092),(-.162,r0),
             (-.154,r0),(-.145,r0*.991),(.145,r0*.991),(.154,r0),(.162,r0),
             (.167,.092),(.172,.084),(.172,.066),(.160,.066))
    ink=("Cold coil bore darkness","Cold rolled shaded rim","Cold rolled coil edge",
         "Cold rolled coil edge","Cold rolled coil galvanized flank","Iron mill scale","Cold rolled coil galvanized flank",
         "Iron mill scale","Cold rolled coil galvanized flank","Cold rolled coil edge","Cold rolled shaded rim",
         "Cold rolled coil edge","Cold coil bore darkness","Cold coil bore darkness")
    for j,z in enumerate((-.249,0,.249),1):
        q=tau/32
        coords=[[(x,z+a*cos(i*q),cy+a*sin(i*q)) for i in range(32)] for x,a in contour]
        name=f"Real closed annular transverse cold rolled steel coil {j}"
        for k,a in enumerate(coords):
            b=coords[(k+1)%len(coords)]
            for i in range(32):
                n=(i+1)%32
                f(o,name,ink[k],(a[i],a[n],b[n],b[i]))
        for s in (-1,1):
            for v in (.071,.078,.085,.092):
                x=s*(.1724 if v<.084 else .1695 if v<.09 else .1682)
                # Two paired rings are genuine wound stock engravings.
                p=[(x,z+v*cos(i*q),cy+v*sin(i*q)) for i in range(33)]
                c="Polished steel pack circumferential lines" if int(v*1000)%2 else "Iron mill scale"
                # Surface-strip rings visually read as winding, with no
                # extra silhouette or allowance needed for track clearances.
                for i in range(32):
                    a,b=p[i:i+2];x1,z1,y1=a;_,z2,y2=b
                    n=.0014
                    f(o,"Visible wound metal concentric rim band grooves",c,
                       (a,b,(x1,z+((z2-z)*(v+n)/v),cy+(y2-cy)*(v+n)/v),
                        (x1,z+((z1-z)*(v+n)/v),cy+(y1-cy)*(v+n)/v))[::s])
        for x in (-.072,.072):
            # Full wrap closed intact. Thin strip joins an external buckle.
            loops=[[(v,z+u*cos(i*q),cy+u*sin(i*q)) for i in range(32)]
                   for v,u in ((x-.004,.0999),(x-.004,.103),(x+.004,.103),(x+.004,.0999))]
            for k,a in enumerate(loops):
                b=loops[(k+1)%4]
                for i in range(32):
                    f(o,"Separate closed rolled packing straps around each coil","Blue black steel bands",
                      (a[i],a[(i+1)%32],b[(i+1)%32],b[i]))
            B(o,"Practical forged transport strap clamp crimped above face seam","Rolling stock clamp iron",
               x,z+.009,.018,.023,.423,.435,.003)

def palette(path,p):
    row=b"".join(bytes.fromhex(k)*8 for k in p.values())
    def c(a,b):return struct.pack(">I",len(b))+a+b+struct.pack(">I",zlib.crc32(a+b))
    path.write_bytes(b"\x89PNG\r\n\x1a\n"+c(b"IHDR",struct.pack(">IIBBBBB",512,8,8,2,0,0,0))
                     +c(b"IDAT",zlib.compress((b"\0"+row)*8,9))+c(b"IEND",b""))

def render(sc,stem,cargo):
    from mathutils import Vector
    bpy.ops.mesh.primitive_plane_add(size=10,location=(0,0,-.011))
    ground=bpy.data.materials.new("Warm studio ballast gray");ground.diffuse_color=(.151,.160,.141,1)
    bpy.context.object.data.materials.append(ground)
    bpy.ops.object.camera_add()
    cam=bpy.context.object;sc.camera=cam;cam.data.type="ORTHO"
    sc.render.engine="BLENDER_WORKBENCH"
    sh=sc.display.shading;sh.light="STUDIO";sh.color_type="MATERIAL";sh.show_cavity=True
    sh.cavity_type="BOTH";sh.show_shadows=True;sh.background_type="WORLD"
    sc.world=bpy.data.worlds.new("Clouded slate")
    sc.world.color=(.145,.179,.221)
    sc.view_settings.view_transform="Standard";sc.view_settings.exposure=.42
    sc.render.resolution_x,sc.render.resolution_y=1120,800
    sc.render.resolution_percentage=100
    sc.render.image_settings.file_format="JPEG";sc.render.image_settings.quality=92
    for name,where in (("loaded",(2.65,-3.08,2.02)),("empty",(2.65,-3.08,2.02)),("side",(-3.65,.435,1.07))):
        cargo.hide_render=name=="empty"
        cam.location=where;cam.rotation_euler=(Vector((0,0,.273))-cam.location).to_track_quat("-Z","Y").to_euler()
        cam.data.ortho_scale=1.39
        sc.render.filepath=str(Path(os.environ["METALS_REVIEW"])/f"{stem}-{name}.jpg")
        bpy.ops.render.render(write_still=True)

def build(stem,id,title,cap,image):
    p=setup(id)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    sc=bpy.context.scene
    sc.name=f"LuanTTD • {title} #{id}"
    sc["stock"]=f"OpenTTD 16.0-RC1 conventional wagon {id}; sprite base {image}, plus24 at {cap//2}/{cap}"
    sc["native"]="8 stock units, .424 gauge, 1.00 node center spacing; -Z forward, Y=0 treads"
    mat=r.materials()
    for n,c in zip(p,mat):c.name=n
    chassis=m();underframe(chassis,id==36);J.geometry(sc,"01 • Independent rolling gear, standard stock knuckles and chassis",chassis,mat)
    fn=hopper if id==35 else steel_deck
    b=m();fn(b);J.geometry(sc,"02 • Original cargo-specific independent wagon shell or cradle deck",b,mat)
    material=m();(iron if id==35 else coils)(material)
    c=J.geometry(sc,"03 • Independently editable visible cargo",material,mat)
    body=deepcopy(chassis);fn(body)
    full=deepcopy(body)
    for name,parts in material.parts.items():
        for p0,cl in parts:full.tri(name,cl,[material.vertices[name][i] for i in p0])
    for s,o in (("empty",body),("loaded",full)):
        path=ROOT/"mods/luanttd_core/models"/f"bl_{stem}_{s}.obj"
        r.export_obj(path,w.local_obj(o))
        path.write_text(f"# Original {title}, RC1 stock {id}; tools/build_stock_rail_metals_art.py\n"+path.read_text().split("\n",1)[1])
    palette(ROOT/"mods/luanttd_core/textures"/f"bl_{stem}_atlas.png",p)
    for scr in bpy.data.screens:
        for area in scr.areas:
            if area.type=="VIEW_3D":
                v=area.spaces.active;v.shading.color_type="MATERIAL"
                v.region_3d.view_location=V((0,0,.26));v.region_3d.view_distance=1.85
                v.region_3d.view_rotation=V((.76,-.82,.61)).to_track_quat("Z","Y")
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art"/f"{stem}.blend"),compress=True)
    if "METALS_REVIEW" in os.environ:render(sc,stem,c)

if __name__=="__main__":
    for s in STOCK:build(*s)

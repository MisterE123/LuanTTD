#!/usr/bin/env python3
"""Original 8-unit Coal Truck #29: riveted steel open mineral wagon."""
from math import cos, pi, sin, tau
from pathlib import Path
from random import Random
import os
import struct
import sys
import zlib

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_rail_wagon_art as w

r=w.rail
bpy=w.bpy
Vector=w.Vector
NAME="bl_rail_coal_wagon"
AXLES=(-.269,.269)
TREAD_R=.098
BOX_HEIGHT=.437
P={
    "Deep chassis iron":"3d4646","Worn chassis edges":"575f5a","Wheel face":"4a5051",
    "Wheel cheek":"69706b","Tyre grey":"7e8780","Dark flange":"4d5353","Weathered hubs":"a2a497",
    "Axle grease":"474844","Guide iron":"666659","Rubbed brake steel":"9b9e8c",
    "Warm bauxite buffer beam":"865443","Beam highlights":"a06952","Knuckles":"6b6e62","Blackened buffers":"434b4a",
    "Body graphite":"545e5e","Body gunmetal":"687471","Body sunward":"75827b","Body low oxide":"655a4e",
    "Body edge bright":"88938a","Steel shade under sill":"495454","Steel inside":"535956","Steel interior soot":"414c49",
    "Rivet polished":"93988a","Oxidised irons":"836557","Oxide ochre":"977258","Oxide shadow":"6c5045",
    "Door chalk cream":"d9cab0","Plate letters":"dcccaa","Plate coal":"3b4641","Letter shadow":"49443b",
    "Coal inter-pile shadow":"282e31","Coal grey fines":"404646","Glassy anthracite":"434e4c",
    "Coal matte black":"333a3a","Coal crumb":"515954","Coal amber fleck":"5f6156","Ash fine":"524d41",
}
w.P={k:i for i,k in enumerate(P)}
r.COLORS[:]=P.values()
B=w.slab
T=w.circular
R=w.faces_xz


def face(m,g,col,points):
    m.face(g,w.P[col],points)


def bar(m,g,c,a,b,thick,deep):
    a,b=Vector(a),Vector(b)
    d=(b-a).normalized()
    u=d.cross(Vector((0,0,1) if abs(d.z)<.80 else (1,0,0))).normalized()*thick/2
    v=d.cross(u).normalized()*deep/2
    cross=(u+v,-u+v,-u-v,u-v)
    lo,hi=([tuple(q+k) for k in cross] for q in (a,b))
    face(m,g,c,lo[::-1]);face(m,g,c,hi)
    for i in range(4):
        j=(i+1)%4
        face(m,g,c,(lo[i],lo[j],hi[j],hi[i]))


def sided(m,g,c,s,z,h,wid,H,x=.225,d=.012,r0=.005):
    B(m,g,c,s*x,z,d,wid,h,h+H,r0)


def annulus(m,g,c,xc,z,rows):
    rings=[]
    for u,r in rows:
        rings.append([(xc+u,z+r*cos(tau*k/24),TREAD_R+r*sin(tau*k/24)) for k in range(24)])
    for a,b in zip(rings,rings[1:]):
        for i in range(24):
            j=(i+1)%24
            face(m,g,c,(a[i],a[j],b[j],b[i]))


def wheelset(m):
    for z in AXLES:
        T(m,"Full width steel axles","Axle grease",(0,z,TREAD_R),.021,"x",-.208,.208,14)
        for s in (-1,1):
            x=s*.212
            suffix="L" if s<0 else "R"
            annulus(m,"Rolling tread "+suffix,"Tyre grey",x,z,[
                (-.026,.064),(-.026,TREAD_R),(.026,TREAD_R),(.026,.064),(-.026,.064)
            ])
            lo,hi=sorted((-.041*s,-.034*s))
            annulus(m,"Inner wheel flange","Dark flange",x,z,[(lo,.064),(lo,.108),
                   (hi,.108),(hi,.064),(lo,.064)])
            T(m,"Recessed mineral wagon steel wheels","Wheel face",(s*.217,z,TREAD_R),
              .078,"x",-.015,.015,22)
            T(m,"Pressed wheel web plate","Wheel cheek",(s*.234,z,TREAD_R),.039,"x",-.005,.005,16)
            T(m,"Sealed axle grease caps","Weathered hubs",(s*.239,z,TREAD_R),.023,"x",-.004,.004,12)
            for i in range(4):
                a=(i+.16)*pi/2
                p=(s*.241,z+.055*cos(a),TREAD_R+.055*sin(a))
                T(m,"Visible wheel casting indentations","Axle grease",p,.010,"x",-.002,.002,10)
            # Independently modeled wedge axlebox, guide and laminated leaf.
            for t in (-1,1):
                bar(m,"Pressed W-iron axle guide","Guide iron",(s*.198,z+t*.074,.200),(s*.201,z+t*.031,.109),
                    .020,.023)
                B(m,"Axle guide pedestal bolt flange","Deep chassis iron",s*.208,z+t*.026,.049,.011,.104,.172,.002)
            q=w.rect(s*.202,z,.073,.061,.009)
            R(m,"Oil axle boxes at native wheel center","Deep chassis iron",q,.120,.203,"Wheel cheek")
            for k in range(4):
                B(m,"Individual laminated suspension leaves","Guide iron",s*.183,z,
                    .036,.127-k*.016,.157-k*.008,.161-k*.008,.004)
            for dz in (-.053,.053):
                T(m,"Cast suspension hanger pins","Weathered hubs",(s*.214,z+dz,.174),.011,"x",-.005,.005,10)
            # Brake shoe supported on each front/rear wheel face clear of the crown.
            z0=z-.075 if z>0 else z+.075
            B(m,"Cast brake shoe and guide","Deep chassis iron",s*.201,z0,.046,.030,.080,.129,.006)
            bar(m,"Independent wheel brake rod","Guide iron",(s*.182,z0,.127),(s*.165,z/2,.195),.014,.017)


def frame(m):
    R(m,"Riveted mineral underframe","Deep chassis iron",w.rect(0,0,.407,.850,.038),
      .126,.205,"Worn chassis edges")
    for s in (-1,1):
        B(m,"Forged deep side sill","Deep chassis iron",s*.213,0,.041,.840,.143,.224,.008)
        B(m,"Long sill angle edge","Worn chassis edges",s*.226,0,.022,.821,.204,.220,.003)
        B(m,"Sill flat exposed toe","Knuckles",s*.228,0,.013,.811,.143,.151,.003)
        for z in (-.393,-.284,-.177,.180,.285,.390):
            T(m,"Sill washer bolts","Rivet polished",(s*.236,z,.177),.0058,"x",-.002,.003,7)
        bar(m,"Hand-brake lever and stepped handle","Guide iron",(s*.230,-.146,.143),(s*.247,.165,.224),.020,.018)
        bar(m,"Rubbed hand-brake lever highlight","Rubbed brake steel",(s*.247,-.119,.151),(s*.250,.150,.219),.008,.006)
        bar(m,"Brake foot latch shaft","Guide iron",(s*.229,.172,.222),(s*.240,.260,.241),.013,.013)
        for end in (-1,1):
            B(m,"Formed iron crew stirrup","Deep chassis iron",s*.206,end*.385,.064,.047,.112,.162,.010)
            B(m,"Lower stirrup tread","Knuckles",s*.220,end*.392,.058,.044,.104,.117,.005)
    for s in (-1,1):
        B(m,"Formed mineral wagon headstock","Warm bauxite buffer beam",0,s*.430,.405,.036,.132,.226,.009,"Beam highlights")
        B(m,"Square boxed coupler draft pocket","Deep chassis iron",0,s*.438,.123,.045,.114,.188,.010)
        B(m,"Forged drawbar shaft","Blackened buffers",0,s*.465,.064,.030,.132,.182,.007)
        B(m,"Coupler knuckles","Knuckles",0,s*.483,.087,.032,.1305,.1835,.009)
        for x in (-.157,.157):
            T(m,"Bushed cast buffer mounting","Deep chassis iron",(x,s*.449,.177),.028,"z",-.010,.010,16)
            T(m,"Shrunk buffer shaft","Knuckles",(x,s*.460,.177),.019,"z",-.013,.013,16)
            T(m,"Wide wagon buffer pad","Blackened buffers",(x,s*.471,.177),.034,"z",-.008,.008,18)
            T(m,"Buffer face chamfer","Worn chassis edges",(x,s*.478,.177),.027,"z",-.001,.003,18)
        bar(m,"Short drooped mineral air hose","Blackened buffers",(-.088,s*.446,.165),(-.096,s*.471,.105),.012,.014)
        B(m,"Tight-brake hose brass terminations","Oxidised irons",-.091,s*.475,.023,.013,.102,.117,.003)


GLYPHS={
  "C":("011","100","100","100","011"),"E":("111","100","110","100","111"),
  "D":("110","101","101","101","110"),"A":("010","101","111","101","101"),
  "R":("110","101","110","101","101"),"2":("110","001","010","100","111"),
  "9":("111","101","111","001","110"),
}


def letters(m,s,text,z,h,k=.0041):
    count=len(text)*4-1
    for j,c in enumerate(text):
        for row,line in enumerate(GLYPHS[c]):
            for i,on in enumerate(line):
                if on=="0":continue
                v=z+s*(j*4+i+.5-count/2)*k
                y=h+(4-row)*k
                sided(m,"Stencil raised from soot-grey placard","Plate letters",s,v,y,k*.88,k*.90,.245,.0013,.0002)


def boxwork(m):
    # Side, end, and floor are all distinct volumes. Side taper is below
    # the rolled rim and no geometry covers the open cargo space.
    R(m,"Solid steel cargo floor","Steel interior soot",w.rect(0,0,.418,.783,.028),
      .217,.244,"Steel inside")
    for z in (-.319,-.229,-.139,-.049,.041,.131,.221,.311):
        B(m,"Interior wear floor weld seam","Steel interior soot",0,z,.371,.009,.243,.246,.003)
        for x in (-.173,.172):
            T(m,"Interior floor seam fastener","Rivet polished",(x,z,.247),.004,"h",0,.002,8)
    for s in (-1,1):
        for (a,b,col) in ((-.397,-.15,"Body gunmetal"),(-.15,.151,"Body graphite"),(.151,.397,"Body gunmetal")):
            for (h0,h1,x0,x1,kind) in ((.235,.289,.195,.220,"Body low oxide"),
                    (.289,.368,.220,.227,col),(.368,.433,.227,.224,"Body sunward")):
                pts=((s*x0,a,h0),(s*x0,b,h0),(s*x1,b,h1),(s*x1,a,h1))
                face(m,"Sloped mineral steel body panels",kind,pts if s>0 else pts[::-1])
                inside=tuple((x-s*.026,z,y) for x,z,y in pts)
                face(m,"Visible inside open steel bin","Steel inside",inside[::-1] if s>0 else inside)
        B(m,"Rolled solid upper rim","Body edge bright",s*.223,0,.034,.844,.422,.447,.009)
        B(m,"Dark recessed line below rolled rim","Steel shade under sill",s*.229,0,.011,.812,.416,.424,.003)
        B(m,"Sill angle and welding strip","Oxide shadow",s*.212,0,.024,.821,.239,.256,.005)
        for i,z in enumerate((-.384,-.149,.149,.385)):
            sided(m,"Riveted separate steel door stanchions","Steel shade under sill",s,z,.229,.032,.205,.227,.023)
            sided(m,"Bevels on sloped diamond stanchions","Body edge bright",s,z,.267,.013,.157,.242,.007,.003)
            for k in range(5):
                T(m,"Pressed side stanchion rivets","Rivet polished",(s*.248,z,.279+.031*k),.0043,"x",-.002,.002,8)
        # Central riveted double door in the real plate, two barrel hinges
        # and a visibly raised operating latch/linkage.
        for z in (-.141,.141):
            sided(m,"Bottom door inset black reveal","Steel shade under sill",s,z,.251,.009,.154,.230,.004)
        sided(m,"Bottom door pressed skirting rib","Oxidised irons",s,.0,.245,.267,.021,.232,.012)
        sided(m,"Side unloading door lower sheet","Body gunmetal",s,-.000,.263,.246,.102,.229,.009)
        sided(m,"Upper inward flap steel lip","Steel shade under sill",s,0,.372,.258,.012,.231,.011)
        for z in (-.100,.100):
            T(m,"Forged hinge barrels for dropping coal gate","Oxide shadow",(s*.239,z,.261),
              .012,"z",-.028,.028,12)
            sided(m,"Dark hinge pin plate","Oxidised irons",s,z,.244,.048,.049,.239,.007,.003)
            T(m,"End of hinge pin shank","Knuckles",(s*.241,z-.031,.258),.007,"z",-.005,.005,8)
        sided(m,"Central open lever face","Deep chassis iron",s,.019,.286,.063,.055,.236,.011)
        bar(m,"Visible wagon side release latch","Rubbed brake steel",(s*.244,.041,.277),(s*.250,.083,.339),.010,.012)
        sided(m,"Three access catch sockets","Guide iron",s,-.036,.295,.024,.040,.237,.009)
        for z,h,len_ in ((-.18,.250,.047),(.207,.259,.061),(.303,.399,.040),(-.346,.285,.062),(.271,.263,.025)):
            # Small differently colored abrasion scars stay conformal.
            sided(m,"Adjacent mineral rust scuffs","Oxide ochre" if h<.30 else "Body edge bright",
                  s,z,h,len_,.005,.228,.004,.001)
        sided(m,"Oblong Cedar running-number board","Plate coal",s,-.270,.323,.104,.044,.237,.010)
        letters(m,s,"CEDAR",-.270,.334)
        sided(m,"Small Class 29 dark capacity card","Plate coal",s,.286,.334,.058,.041,.237,.010)
        letters(m,s,"29",.286,.342,.0048)
    for s in (-1,1):
        # Ribbed pressed end with a genuine hinged drop-gate on one end.
        B(m,"Ribbed mineral end sheets","Body graphite",0,s*.394,.425,.028,.229,.435,.012,"Body sunward")
        for x in (-.136,0,.136):
            B(m,"Formed end-gate star stiffeners","Body sunward",x,s*.414,.018,.020,.256,.418,.005)
            for h in (.273,.332,.394):
                T(m,"Visible end-gate rivets","Rivet polished",(x,s*.426,h),.0051,"z",-.003,.003,8)
        B(m,"Double rolled end plate upper channel","Body edge bright",0,s*.408,.447,.031,.424,.446,.007)
        for x in (-.179,.179):
            B(m,"Angle steel corner columns","Oxidised irons",x,s*.405,.041,.037,.223,.432,.009,"Oxide ochre")
            T(m,"Corner fall-gate pin stop","Knuckles",(x,s*.425,.390),.009,"z",-.004,.006,8)
        if s>0:
            for x in (-.134,.134):
                T(m,"Drop gate upper hinge shaft","Deep chassis iron",(x,.427,.394),.012,"x",-.049,.049,12)
            B(m,"Mechanical end gate releasing snap latch","Deep chassis iron",.018,.422,.034,.022,.251,.315,.006)
            bar(m,"Long end release bar","Rubbed brake steel",(-.042,.439,.292),(.075,.440,.298),.013,.013)
        B(m,"Number board below drop stop","Plate coal",-.068,s*.413,.077,.016,.320,.353,.005)
        for x in (-.078,-.057):
            B(m,"End etched capacity marks","Plate letters",x,s*.422,.007,.005,.330,.342,.001)


def heap(m):
    # Three longitudinal lobes from loader passes. The pile is not an
    # undifferentiated prism: the raised triangulated aggregate surface
    # sinks beneath the rolled rim on every boundary.
    rng=Random(739829)
    def profile(x,z):
        a=max(0.,1-(abs(x)/.191)**1.64)
        b=max(0.,1-(abs(z)/.378)**3.10)
        lobes=(.081+.023*cos(16*z+.42)+.012*cos(30*z+.51))
        return .408+a*b*lobes
    rows=[]
    segments_z,segments_x=33,18
    cola=("Coal matte black","Coal grey fines","Coal inter-pile shadow","Glassy anthracite",
          "Coal matte black","Coal crumb","Coal grey fines","Ash fine")
    for i in range(segments_z+1):
        row=[]
        z=-.377+.754*i/segments_z
        for j in range(segments_x+1):
            x=-.192+.384*j/segments_x
            edge=i in (0,segments_z) or j in (0,segments_x)
            px=x if edge else x+rng.uniform(-.0049,.0058)
            pz=z if edge else z+rng.uniform(-.006,.006)
            h=profile(px,pz)+(0 if edge else rng.uniform(-.007,.007))
            row.append((px,pz,h))
        rows.append(row)
    for i in range(segments_z):
        for j in range(segments_x):
            a,b,c,d=rows[i][j],rows[i][j+1],rows[i+1][j+1],rows[i+1][j]
            first,second=((a,b,c),(a,c,d)) if (i+j)%2 else ((a,b,d),(b,c,d))
            for tri in (first,second):
                face(m,"Coal payload irregular ridged base",rng.choice(cola),tri)
    colors=("Coal matte black","Coal grey fines","Glassy anthracite","Coal crumb",
            "Coal amber fleck","Coal inter-pile shadow")
    for i in range(133):
        # Vary fragment size/angle and keep every tip in the bin silhouette.
        x=rng.uniform(-.177,.177)
        z=rng.uniform(-.360,.360)
        h=profile(x,z)-rng.uniform(.002,.012)
        size=rng.uniform(.0045,.0197)
        ring=[]
        phi=rng.uniform(0,tau)
        n=rng.choice((4,5,5,6))
        for j in range(n):
            a=phi+tau*j/n
            rx=size*rng.uniform(.6,1.05)
            rz=size*rng.uniform(.55,1.15)
            u=max(-.189,min(.189,x+rx*cos(a)))
            v=max(-.374,min(.374,z+rz*sin(a)))
            ring.append((u,v,h-rng.uniform(.003,.010)))
        apex=(x+size*cos(phi)*.26,z+size*sin(phi)*.27,min(.542,h+size*1.1))
        for j in range(n):
            q=(j+1)%n
            col=rng.choices(colors,weights=(5,5,5,2,1,6))[0]
            face(m,"Visible angular lumps of coal in the wagon",col,(ring[j],ring[q],apex))


def wagon(loaded):
    m=r.Mesh(r.terrain_height(0))
    frame(m)
    wheelset(m)
    boxwork(m)
    if loaded:
        heap(m)
    return m


def atlas():
    def chunk(tag,data):
        return struct.pack(">I",len(data))+tag+data+struct.pack(">I",zlib.crc32(tag+data))
    row=b"".join(bytes.fromhex(c)*8 for c in P.values())
    content=b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",8*len(P),8,8,2,0,0,0))
    content+=chunk(b"IDAT",zlib.compress((b"\0"+row)*8))+chunk(b"IEND",b"")
    (r.TEXTURES/(NAME+"_atlas.png")).write_bytes(content)


def studio(scene,parts):
    r.instance(scene,parts["empty"],-.410,0)
    r.instance(scene,parts["loaded"],.410,0)
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.014))
    mat=bpy.data.materials.new("Muted blue-grey depot surroundings")
    mat.diffuse_color=(.155,.209,.21,1)
    bpy.context.object.data.materials.append(mat)
    bpy.ops.object.camera_add(location=(1.72,-3.15,2.38))
    camera=bpy.context.object
    camera.rotation_euler=(Vector((.05,0,.205))-camera.location).to_track_quat("-Z","Y").to_euler()
    camera.data.type="ORTHO";camera.data.ortho_scale=2.00;scene.camera=camera
    scene.render.engine="BLENDER_WORKBENCH"
    scene.render.resolution_x=1540;scene.render.resolution_y=1040
    scene.display.shading.light="STUDIO"
    scene.display.shading.color_type="MATERIAL"
    scene.display.shading.show_shadows=True
    scene.display.shading.show_cavity=True
    scene.display.shading.cavity_type="BOTH"
    scene.display.shading.cavity_ridge_factor=1.25
    scene.display.shading.cavity_valley_factor=1.16
    scene.display.shading.background_type="WORLD"
    scene.world=bpy.data.worlds.new("Mild steel-grey industrial daylight")
    scene.world.color=(.163,.204,.253)
    scene.view_settings.view_transform="Standard"


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene
    scene.name="LuanTTD | Coal Truck #29, open mineral wagon"
    mats=r.materials()
    for i,name in enumerate(P):
        mat=mats[i];mat.name=name
        principled=mat.node_tree.nodes.get("Principled BSDF")
        principled.inputs["Metallic"].default_value=.55 if ("steel" in name.lower() or "glassy" in name.lower()) else .12
        principled.inputs["Roughness"].default_value=.49 if "anthracite" in name else .73
    parts={}
    for state in ("empty","loaded"):
        m=wagon(state=="loaded")
        parts[state]=r.stash(m,mats,f"29 Cedar coal truck — {state}")
        r.export_obj(r.MODELS/(NAME+"_"+state+".obj"),w.local_obj(m))
    atlas()
    studio(scene,parts)
    bpy.ops.wm.save_as_mainfile(filepath=str(r.ROOT/"art"/"rail_coal_wagon.blend"),compress=True)
    if target:=os.getenv("RAIL_COAL_WAGON_RENDER"):
        scene.render.filepath=target
        bpy.ops.render.render(write_still=True)

if __name__=="__main__":
    main()

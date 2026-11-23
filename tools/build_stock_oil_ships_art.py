#!/usr/bin/env python3
"""Original Blender tanker silhouettes for the shared RC1 ship #204/#205 sprite slot."""
from math import cos,sin,tau
from pathlib import Path
from mathutils import Vector as V
import os,sys,struct,zlib
import bpy
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,os.getenv("LUANTTD_HELPERS",str(ROOT/"tools")))
import build_ship_facility_art as H
from build_rail_wagon_art import local_obj

B,T,R=H.box,H.tube,H.rail
OLD="stock_mps_oil_tanker"
NEW="stock_cs_inc_oil_tanker"
STOCK={OLD:(204,"MPS Oil Tanker"),NEW:(205,"CS-Inc. Oil Tanker")}
PALETTE=dict(navy="214466",hull="366584",hull_top="43799b",hull_light="5887a4",
    boot="263d53",under="823f36",under_shade="653633",deck="5b5b49",
    charcoal="313f47",deep="293744",steel="657b80",silver="99a9a6",
    blue_dark="395f77",blue_light="6d97a8",deck_light="787461",deck_warm="655d49",
    walnut="826f59",brick="835346",red="ac493c",red_lens="d05242",
    cream="e2dac2",cream_light="f5ead1",cream_shade="c4bca4",cream_old="d1c6a4",
    glow="e2b260",vent="a1a79d",brass="ad8b59",gunmetal="4b5254",
    glass="375664",glass_light="7b9b9f",glazing="273f4c",mint="5b937e",
    hull_mid="406e91",hull_cold="315671",black="272c33",black_pipe="323b3e",
    bridge="d3d6cc",bridge_high="ecede3",bridge_low="b1bbba",wheelhouse="627a80",
    radar="9aaba6",tanker_orange="ac613b",deck_pipe="695e4c",pipe_warm="867c6a",
    valve_body="455e5a",green="5b8069",rail_gold="a29880",rail_iron="889995",
    deck_berth="757970",nav_port="ce433e",nav_star="78ab70",cloud="bdccd3",
    stack_blue="3b607a",stack_black="343a3d",orange_buoy="c98856",raft="a76e4c",
    white_mark="e0dfcf",paint="b5c5b8",desk="5f6864",tube="3b454c",
    shaft="51716d",cab_dark="55696c",anchor="5d6567",ring="807a5f")
P={k:i for i,k in enumerate(PALETTE)}
assert len(P)==64
H.P=P;R.COLORS[:]=PALETTE.values()

# section z, half deck beam, sheer y, local keel y. Origin is genuine
# waterline, and the existing split depot and lock gate keep native scale.
FRAMES={
OLD:((- .872,.023,.201,-.061),(-.835,.093,.206,-.092),(-.771,.153,.190,-.131),
     (-.627,.239,.176,-.163),(-.403,.285,.156,-.173),(-.191,.298,.150,-.175),
     (.064,.298,.150,-.175),(.302,.286,.151,-.171),(.504,.274,.157,-.157),
     (.636,.241,.171,-.126),(.746,.178,.188,-.095),(.822,.113,.191,-.066),
     (.859,.043,.188,-.046)),
NEW:((-.913,.022,.238,-.059),(-.886,.127,.240,-.091),(-.811,.206,.231,-.127),
     (-.674,.279,.209,-.160),(-.467,.321,.184,-.180),(-.227,.333,.178,-.183),
     (.039,.334,.173,-.185),(.289,.331,.172,-.180),(.523,.318,.174,-.172),
     (.683,.287,.187,-.148),(.793,.244,.194,-.110),(.873,.169,.195,-.071),
     (.909,.080,.195,-.049)),
}

def f(m,n,c,xyz):m.face(n,P[c],xyz)
def rail(m,n,c,a,b,r=.007,k=8):T(m,n,c,a,b,r,r,k)
def lines(m,n,c,pts,r=.007,k=8):
    for a,b in zip(pts,pts[1:]):rail(m,n,c,a,b,r,k)
def section(w,y,k):
    return [(-w,y),(-w,.096),(-w*.994,.019),(-w*.965,-.013),(-w*.926,-.049),
           (-w*.700,k*.81),(-w*.338,k), (w*.338,k),(w*.700,k*.81),
           (w*.926,-.049),(w*.965,-.013),(w*.994,.019),(w,.096),(w,y)]

def hull(m,key):
    frames=FRAMES[key]
    n="Native continuous watertight pressure hull and weather deck"
    rings=[[(x,z,h) for x,h in section(w,y,k)] for z,w,y,k in frames]
    for a,b in zip(rings,rings[1:]):
        for i in range(len(a)):
            j=(i+1)%len(a)
            c=("hull_top","hull","boot","under","under","under_shade","under_shade","under_shade",
                "under","under","boot","hull","hull_top","deck")[i]
            if key==NEW and c=="hull":c="hull_mid"
            f(m,n,c,(a[i],b[i],b[j],a[j]))
    f(m,n,"hull",rings[0]);f(m,n,"hull",rings[-1][::-1])
    # Tapered original deck plates, drawn as exact per-station hull fit.
    for i in range(-7,8):
        d=i/8
        for j,((a,w,h,_),(b,x,y,_)) in enumerate(zip(frames,frames[1:])):
            f(m,"Individual cured steel weather deck planks",
              ("deck_light","deck_warm","deck","deck")[(i+j*3)%4],
              [(w*(d-.056),a,h+.002),(w*(d+.056),a,h+.002),
               (x*(d+.056),b,y+.002),(x*(d-.056),b,y+.002)])
    for s in (-1,1):
        lines(m,"Continuous closed painted aft and forward deck sheer rubbing rail","blue_light",
            [(s*w,z,y+.002) for z,w,y,k in frames],.009,7)
        lines(m,"Wide continuous dark blue stock external rubbing strake","hull_cold",
            [(s*w*.996,z,y-.058) for z,w,y,k in frames],.005,7)
        for i in range(1,len(frames)-1):
            z,w,y,k=frames[i]
            # Slim gunwale bases and actual high polished rails. End posts
            # remain below the deliberate roof and lock overhead envelope.
            rail(m,"Separate fixed polished steel safety railing stanchions","silver",
                (s*w*.93,z,y+.002),(s*w*.93,z,y+.094),.006,7)
        for h,co in ((.046,"rail_iron"),(.087,"silver")):
            lines(m,"Two real narrow sweeper-free guard chains","rail_iron" if key==NEW else co,
                [(s*w*.93,z,y+h) for z,w,y,_ in frames[1:-1]],.0045,7)
    stern=frames[-1][0]
    rail(m,"Below-water centreline propeller shaft","shaft",(0,stern-.24,-.101),(0,stern-.017,-.091),.023,11)
    for j in range(3 if key==OLD else 4):
        a=tau*j/(3 if key==OLD else 4)
        pts=[(.016*cos(a),stern-.050,-.097+.016*sin(a)),
             (.065*cos(a+.19),stern-.045,-.097+.065*sin(a+.19)),
             (.059*cos(a+.56),stern-.039,-.097+.059*sin(a+.56)),
             (.021*cos(a+.44),stern-.052,-.097+.021*sin(a+.44))]
        ps=[(x,z+.006,y) for x,z,y in pts]
        f(m,"Modelled bronze trailing screw petals","brass",pts)
        f(m,"Modelled bronze trailing screw petals","brass",ps[::-1])
        for k in range(4):
            j=(k+1)%4
            f(m,"Raked bronze screw blade edges","brass",(pts[j],pts[k],ps[k],ps[j]))
    B(m,"Closed separate steering rudder below stern normal waterline","under",0,stern-.025,.027,.044,-.137,-.020,.005)

def bollards(m,key):
    for z in ((-.729,.743) if key==OLD else (-.759,.816)):
        y=.199
        for s in (-1,1):
            x=s*.104
            B(m,"Paired corner mooring fairlead bedplate","steel",x,z,.075,.052,y-.008,y+.016,.005)
            T(m,"Mooring paired cylindrical same-end bollards","black",
             (x-.013,z,y+.009),(x-.013,z,y+.053),.013,.017,10)
            T(m,"Mooring paired cylindrical same-end bollards","black",
             (x+.013,z,y+.009),(x+.013,z,y+.053),.013,.017,10)
    z=-.686 if key==OLD else -.739
    B(m,"Bow anchor windlass metal brake motor enclosure","black",0,z,.154,.082,.199,.241,.011)
    for s in (-1,1):
        T(m,"Paired rotating windlass drum moulded round flanges","gunmetal",(s*.021,z,.241),(s*.088,z,.241),.025,.025,12)
        B(m,"Separate triangular fore deck anchor spurling covers","anchor",s*.064,z-.055,.038,.062,.209,.230,.009)
        B(m,"Original anchor fluke mount beside bow","anchor",s*.128,z-.073,.028,.062,.132,.191,.004)
        lines(m,"Modelled paired fore anchor winch chains","anchor",[(s*.083,z-.024,.240),(s*.074,z-.060,.221),
               (s*.061,z-.102,.225)],.008,8)

def ladder(m,n,x,z,b,t,c="silver",w=.057):
    for s in (-1,1):
        rail(m,n+" two actual outside uprights",c,(x+s*w/2,z,b),(x+s*w/2,z,t),.005,8)
    j=max(1,int((t-b)/.034))
    for k in range(j):
        y=b+(k+.33)*(t-b)/j
        rail(m,n+" separate non-slip rungs",c,(x-w/2,z,y),(x+w/2,z,y),.004,7)

def bridge(m,key):
    old=key==OLD
    z=.551 if old else .584
    p="cream" if old else "bridge"
    lit="cream_light" if old else "bridge_high"
    shade="cream_shade" if old else "bridge_low"
    w=.333 if old else .415
    d=.292 if old else .335
    top=.483 if old else .504
    if not old:
        B(m,"Late swept sea-service engine room first tier","bridge_low",0,.603,.452,.341,.173,.351,.020)
        B(m,"Wide distinct aft second superstructure cabin deck","bridge",0,z+.030,.455,.324,.351,.403,.020)
    B(m,"Distinct original aft raised tanker bridge cabin",p,0,z,w,d,.224 if old else .391,top,.021)
    B(m,"Separate full ivory bridge flying roof copings",lit,0,z+.004,w+.025,d+.039,top-.010,top+.033,.021)
    B(m,"Original painted cream bridge shadow roof cap","blue_dark" if old else "steel",0,z+.010,
      w-.018,d-.022,top+.021,top+.047,.020)
    if not old:
        B(m,"Light aft tanker flybridge additional compact upper deck","bridge_high",0,z-.015,.272,.217,.529,.584,.016)
        B(m,"Mid-level broad original aft wheelhouse clear window bank","wheelhouse",0,z-.124,.247,.012,.541,.574,.006)
        B(m,"Late antenna console cover steel-blue","blue_dark",0,z-.008,.235,.197,.583,.605,.012)
    y1=top-.093
    for x in (-.111,-.057,0,.057,.111):
        zz=z-d/2-.005
        B(m,"Independently fitted forward oil freighter bridge glazing rebates","glazing",x,zz,.045,.013,y1,top-.024,.003)
        B(m,"Original forward wheelhouse panoramic sea-blue glass","glass",x,zz-.008,.036,.008,y1+.007,top-.035,.002)
        B(m,"Original bridge daylight reflecting tint","glass_light",x,zz-.013,.031,.003,top-.053,top-.044,.001)
    for s in (-1,1):
        x=s*(w/2)
        for dz in (-.081,-.025,.044,.099):
            B(m,"Bridge side dark maritime rectangular cabin ports","glazing",x,z+dz,.015,.043,y1,top-.028,.004)
            B(m,"Visible marine cabin porthole glazing","glass",x+s*.009,z+dz,.006,.037,y1+.007,top-.035,.002)
        B(m,"Aft bridge lower emergency escape door","wheelhouse",s*.111,z+d/2+.003,.064,.011,.242 if old else .395,top-.044,.003)
        B(m,"Navigation light permanent mast cabinet","black",s*(w/2+.012),z-.056,.037,.047,top-.018,top+.015,.005)
        B(m,"Real red port and green starboard navigation lenses","nav_port" if s<0 else "nav_star",
            s*(w/2+.031),z-.055,.011,.030,top-.013,top+.008,.004)
        ladder(m,"Visible aft bridge maintenance ladder",s*.125,z+d/2+.014,.190,top-.011,"rail_iron",.045)
    if old:
        x=.031;zz=.664
        T(m,"Classic tall forward-raked steam funnel","red",(x,zz,.481),(x+.006,zz+.016,.721),.047,.054,14)
        T(m,"Old warm funnel cream head ring","cream",(x+.006,zz+.014,.685),(x+.007,zz+.016,.704),.053,.055,14)
        T(m,"Black funnel smoke rim","black",(x+.006,zz+.016,.719),(x+.007,zz+.018,.742),.055,.056,14)
        rail(m,"Classic short aft telegraph steel mast","steel",(-.108,.659,.513),(-.110,.662,.775),.008,8)
        rail(m,"Early light cross-spar on stern steam bridge","silver",
            (-.180,.661,.735),(-.049,.661,.735),.004,7)
    else:
        for s in (-1,1):
            x=s*.122;zz=.668
            B(m,"Later short paired offset motors exhaust casing","stack_blue",x,zz,.082,.085,.521,.681,.010)
            B(m,"Deep black twin exhaust sealed pipe shadow recess","stack_black",x,zz,.069,.068,.673,.705,.009)
            B(m,"Cream protective exhaust rail stripes","bridge_low",x,zz,.084,.087,.606,.624,.006)
        rail(m,"Powered radar and radio aft bridge tripod riser","radar",(0,.536,.600),(0,.536,.768),.012,9)
        rail(m,"Permanent original horizontal bridge radar scanner","bridge_high",(-.119,.536,.766),(.119,.536,.766),.010,9)
        rail(m,"Small fore and aft tall communication whip antenna","steel",(0,.536,.763),(0,.539,.816),.0045,8)
        for s in (-1,1):
            rail(m,"Original diagonal radar support foot","silver",(s*.066,.536,.610),(0,.536,.710),.006,8)
    for s in (-1,1):
        rail(m,"Aft wheelhouse roof rail exposed fore spar","silver",(s*.134,z-.128,top+.044),(s*.134,z+.108,top+.043),.004,7)
        for zz in (z-.097,z+.095):
            rail(m,"Four removable bridge safety rail uprights","steel",(s*.134,zz,top+.002),(s*.134,zz,top+.046),.005,7)
    # Secure separate aft lifeboats, outside the weather house.
    if old:
        B(m,"Original aft work skiff above davit bracket","raft",-.211,.589,.076,.170,.264,.315,.012)
        B(m,"Original canvas cap on sheltered aft skiff","cream_old",-.211,.588,.071,.145,.313,.334,.012)
        for zz in (.520,.644):rail(m,"On-ramp mechanical deck davit legs","steel",(-.189,zz,.191),(-.230,zz,.337),.007,8)
    else:
        for s in (-1,1):
            T(m,"Liferaft both sides original steel strapped capsules","cream",
                (s*.242,.568,.271),(s*.242,.686,.271),.033,.027,11)
            for zz in (.589,.665):
                B(m,"Heavy real liferaft weather chamber web straps","blue_dark",s*.242,zz,.068,.014,.242,.302,.006)

def piping(m,key):
    old=key==OLD
    grid=(-.538,-.315,-.080,.145,.303) if old else (-.618,-.407,-.149,.097,.273,.353)
    vheight=.211 if old else .229
    for j,z in enumerate(grid):
        # Paired actual lid coamings mark the separate liquid holds, not
        # generic freight hatches. Heights and valves match visual manifolds.
        for s in (-1,1):
            xx=s*(.118 if old else .144)
            B(m,"Low odd vessel independent tank aperture foundation","blue_dark",xx,z,.095,.097,vheight-.039,vheight-.014,.012)
            T(m,"Real separately capped flush oil port coamings","steel",(xx,z,vheight-.022),(xx,z,vheight+.021),.039 if old else .044,.033,16)
            T(m,"Circular separately tinted tank access lid","vent",(xx,z,vheight+.021),(xx,z,vheight+.030),.032,.030,13)
            rail(m,"Small protective port hatch locking strap","silver",(xx-.023,z,vheight+.031),(xx+.023,z,vheight+.031),.0035,7)
            pipe0=s*(.057 if old else .083)
            pipe1=s*(.107 if old else .128)
            lines(m,"Welded real tubing between each cargo hold and transfer manifold","pipe_warm",
                [(pipe0,z-.013,vheight+.012),(pipe1,z-.013,vheight+.012),(pipe1,z,vheight+.032)],.009 if old else .012,8)
        B(m,"Dedicated whole-deck anti-slip plate transverse frames","deck_berth",0,z+.052,
            .474 if old else .534,.025,vheight-.037,vheight-.029,.004)
    for s in (-1,1):
        x=s*(.058 if old else .084)
        y=vheight+.014
        lines(m,"Long running raised pressure transfer main lines","deck_pipe",
            [(x,grid[0],y),(x,grid[1]-.048,y),(x,grid[-1],y),(x*.84,grid[-1]+.044,y-.017)],
            .013 if old else .016,11)
        for z in (grid[0]+.011,grid[2],grid[-1]-.007):
            B(m,"Physically supported whole ship deck oil pipe clamps","silver",x,z,.041,.024,y-.061,y+.009,.004)
        x1=s*(.222 if old else .275)
        zz=.018 if old else -.047
        lines(m,"Real working port and starboard oil transfer outlets","pipe_warm",
            [(x,zz,y),(x1*.85,zz,y+.016),(x1,zz,y+.016),(x1,zz,y+.043)],.017 if old else .022,12)
        T(m,"Distinct capped outward loading manifold flanges","silver",(x1,zz,y+.040),(x1+s*.011,zz,y+.043),.025,.027,12)
        bx=x1-s*.055
        T(m,"Fixed closed cargo isolating valve bodies","valve_body",(bx,zz,y+.010),(bx,zz,y+.053),.022,.019,12)
        T(m,"Independent original red valve hand wheels","red",(bx,zz,y+.052),(bx,zz,y+.062),.021,.015,12)
        for z in ((-.286,.251) if old else (-.489,-.234,.190)):
            xx=s*(.187 if old else .192)
            yy=vheight+.063
            lines(m,"Real curved reserve deck tank vent lines","steel",
              [(xx,z,vheight-.034),(xx,z,yy-.020),(xx-s*.013,z,yy),(xx-s*.044,z,yy)],.009,9)
            T(m,"Rounded protective pressure relief vent heads","vent",(xx-s*.052,z,yy),(xx-s*.032,z,yy),.014,.014,10)
    zz=.027 if old else -.026
    B(m,"Modelled distinct textured slatted loading crossover platform","deck_berth",0,zz,.205,.120,vheight-.018,vheight+.001,.006)
    for x in (-.087,-.054,-.021,.021,.054,.087):
        B(m,"Individual non-slip crossover ladder grate ribs","rail_iron",x,zz,.011,.110,vheight-.002,vheight+.008,.001)
    # Floating deck relief and crossbeam appearance is source-like; larger
    # CS unit uses a white portal rack and slender cargo hose boom.
    if not old:
        for s in (-1,1):
            x=s*.109;z=-.166
            rail(m,"CS oil transfer portal column","bridge_low",(x,z,.208),(x,z,.413),.012,9)
            rail(m,"Independent braced portal deck-side gusset","silver",(x+s*.056,z,.218),(x,z,.284),.006,8)
        rail(m,"CS oil transfer facility distinct transverse gantry","bridge_low",(-.115,-.166,.413),(.115,-.166,.413),.014,10)
        rail(m,"CS swivelling oil load boom stows parallel to keel","silver",(0,-.166,.409),(0,-.443,.333),.012,8)
        lines(m,"Real CS pendant small operating transfer bell","steel",[(0,-.443,.335),(0,-.440,.277),(0,-.396,.263)],.008,9)
    else:
        rail(m,"Small original early hose crane","steel",(.132,-.055,.207),(.130,-.056,.389),.010,8)
        rail(m,"Old short fixed articulated lifting arm","silver",(.130,-.056,.389),(.020,-.180,.329),.008,9)

def mesh(key):
    m=R.Mesh(R.terrain_height(0))
    hull(m,key);bollards(m,key);piping(m,key);bridge(m,key)
    return m

def atlas(key):
    def chunk(t,p):return struct.pack(">I",len(p))+t+p+struct.pack(">I",zlib.crc32(t+p))
    data=b"".join(bytes.fromhex(c)*8 for c in PALETTE.values())
    (ROOT/"mods/luanttd_core/textures"/f"bl_{key}_atlas.png").write_bytes(b"\x89PNG\r\n\x1a\n"+
      chunk(b"IHDR",struct.pack(">IIBBBBB",512,8,8,2,0,0,0))+chunk(b"IDAT",zlib.compress((b"\0"+data)*8,9))+
      chunk(b"IEND",b""))
def export(key):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene
    idx,name=STOCK[key]
    scene.name=f"LuanTTD | Stock #{idx} {name}"
    scene["stock_engine_id"]=idx
    scene["native_scale"]=1.0
    scene["pose"]="Authoring: bow -Y. Luanti production: bow -Z, Y=0 design waterline."
    scene["source"]="RC1 stock same sprite 3669; original distinct period interpretation."
    z=mesh(key)
    mats=R.materials()
    for n,mat in zip(P,mats):mat.name=n
    for title,fn in (("01 Sealed steel hull, steering, rails and deck",hull),
                ("02 Bow and stern ground tackle",bollards),("03 Independent cargo holds and raised transfers",piping),
                ("04 After bridge, navigation, cabin and exhaust",bridge)):
        c=bpy.data.collections.new(title);scene.collection.children.link(c)
        a=R.Mesh(R.terrain_height(0));fn(a,key);R.to_blender(a,c,mats)
    path=ROOT/"mods/luanttd_core/models"/f"bl_{key}.obj"
    R.export_obj(path,local_obj(z))
    path.write_text(f"# Original RC1 stock tanker #{idx}; tools/build_stock_oil_ships_art.py\n"+
        path.read_text().split("\n",1)[1])
    atlas(key)
    for screen in bpy.data.screens:
        for a in screen.areas:
            if a.type=="VIEW_3D":
                sp=a.spaces.active;sp.shading.color_type="MATERIAL"
                sp.region_3d.view_location=V((0,0,.22));sp.region_3d.view_distance=3.17
                sp.region_3d.view_rotation=V((.77,-.81,.68)).to_track_quat("Z","Y")
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art"/f"{key}.blend"),compress=True)
    if dest:=os.getenv("OIL_SHIP_REVIEW"):review(scene,Path(dest),key)
def review(scene,dest,key):
    bpy.ops.mesh.primitive_plane_add(size=28,location=(0,0,-.0004))
    w=bpy.data.materials.new("Art-only backdrop; design waterline");w.diffuse_color=(.072,.229,.278,1)
    bpy.context.object.data.materials.append(w)
    cam=bpy.data.cameras.new("Tanker survey"); ob=bpy.data.objects.new("Tanker survey",cam)
    scene.collection.objects.link(ob);scene.camera=ob;cam.type="ORTHO"
    scene.render.engine="BLENDER_WORKBENCH"
    sh=scene.display.shading;sh.light="STUDIO";sh.studio_light="paint.sl";sh.color_type="MATERIAL";sh.show_shadows=True
    sh.show_cavity=True;sh.cavity_type="BOTH";sh.show_object_outline=False
    scene.view_settings.view_transform="Standard"
    scene.render.image_settings.file_format="JPEG"
    scene.render.resolution_x=860;scene.render.resolution_y=605;scene.render.resolution_percentage=100
    for tag,xyz,look,scale in (
       ("bow",(2.51,-2.96,1.78),(0,0,.17),2.45),("deck",(-2.12,2.36,2.53),(0,0,.23),2.31)):
        ob.location=xyz
        ob.rotation_euler=(V(look)-ob.location).to_track_quat("-Z","Y").to_euler()
        cam.ortho_scale=scale
        scene.render.filepath=str(dest/f"{key}_{tag}.jpg")
        bpy.ops.render.render(write_still=True)
if __name__=="__main__":
    for k in STOCK:export(k)

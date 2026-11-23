#!/usr/bin/env python3
"""Original passenger platform and single-portal engine shed for LuanTTD.

Run: blender -b -t 4 --python-exit-code 1 --python tools/build_rail_architecture.py
Uses the authored stock-gauge track generator already in this checkout.
"""
from pathlib import Path
from math import cos, sin, pi
import struct
import sys
import zlib

import bpy

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_rail_art as rail

EXTRA = {
    "Flagstone shadow":"777468", "Dressed platform stone":"a39d8a",
    "Weathered pavers":"8d8b7c", "Paver highlight":"b6ab91",
    "Cream paint":"ded2b1", "Forest ironwork":"354a43",
    "Green enamel":"597659", "Bronze":"a88350",
    "Bench timber":"936b4d", "Window glass":"718e97", "Window glint":"a9bec0",
    "Soot":"3b3b3a", "Slate":"555b5b", "Slate seam":"78817d", "Slate shade":"41494b",
    "Old brick":"a46148", "Light brick":"bc7d56", "Brick shadow":"845542",
    "Stone arch":"c8ae85", "Stone bevel":"ab9273", "Workshop door wood":"605841",
    "Signal gold":"dbad65", "Iron base":"4d5352",
}
P={k:i+len(rail.COLORS) for i,k in enumerate(EXTRA)}
rail.COLORS.extend(EXTRA.values())

def hp(v):
    return v if callable(v) else lambda x,z:v


def solid(mesh,name,color,ring,low,high,top=None,open_x=False,top_skin=True,bottom_skin=True):
    """Vertical prism with optional open joins; either height can be a plane."""
    lo,hi=hp(low),hp(high)
    if rail.signed_area(ring)<0:
        ring=ring[::-1]
    bottom=[(x,z,lo(x,z)) for x,z in ring]
    surface=[(x,z,hi(x,z)) for x,z in ring]
    if top_skin:
        mesh.face(name,P[color if top is None else top],surface)
    if bottom_skin:
        mesh.face(name,P[color],bottom[::-1])
    for i,a in enumerate(ring):
        j=(i+1)%len(ring)
        b=ring[j]
        if open_x and a[0]==b[0] and abs(a[0])==1:
            continue
        mesh.face(name,P[color],(surface[i],bottom[i],bottom[j],surface[j]))


def corners(x,z,dx,dz,chamfer=0):
    a,b=x-dx/2,x+dx/2
    c,d=z-dz/2,z+dz/2
    s=chamfer
    return ([(a,c),(b,c),(b,d),(a,d)] if s==0 else
            [(a+s,c),(b-s,c),(b,c+s),(b,d-s),(b-s,d),(a+s,d),(a,d-s),(a,c+s)])


def slab(mesh,name,color,x,z,dx,dz,lo,hi,chamfer=0,top=None,open_x=False,top_skin=True,bottom_skin=True):
    solid(mesh,name,color,corners(x,z,dx,dz,chamfer),lo,hi,top,open_x,top_skin,bottom_skin)


def portrait(mesh,name,color,coords,front,back):
    """Convex shape in X/height, extruded along +Z toward the track."""
    right=[(x,front,h) for x,h in coords]
    left=[(x,back,h) for x,h in coords]
    if rail.signed_area(coords)>0:
        right.reverse()
        left.reverse()
    mesh.face(name,P[color],right)
    mesh.face(name,P[color],left[::-1])
    for i,p in enumerate(right):
        j=(i+1)%len(right)
        mesh.face(name,P[color],(p,left[i],left[j],right[j]))


def clip_behind(mesh,zmin):
    out=rail.Mesh(rail.terrain_height(0))
    for name,faces in mesh.parts.items():
        verts=mesh.vertices[name]
        for face,col in faces:
            result=[]
            for i,index in enumerate(face):
                a,b=verts[face[i-1]],verts[index]
                if (a[1]<zmin)!=(b[1]<zmin):
                    f=(zmin-a[1])/(b[1]-a[1])
                    result.append((a[0]+f*(b[0]-a[0]),zmin,a[2]+f*(b[2]-a[2])))
                if b[1]>=zmin:
                    result.append(b)
            out.face(name,col,result)
    return out


def rotated(mesh,quarter):
    out=rail.Mesh(rail.terrain_height(0))
    for name,faces in mesh.parts.items():
        verts=mesh.vertices[name]
        for face,col in faces:
            points=[]
            for i in face:
                x,z,h=verts[i]
                points.append(((x,z,h),(-z,x,h),(-x,-z,h),(z,-x,h))[quarter])
            out.face(name,col,points)
    return out


def platform(geos):
    m=rail.rail_geometry(1,0,geos)
    # Structural faces join the neighboring tile at +/-1, never sitting
    # on top of its geometry. No floor shares the terrain's height plane.
    slab(m,"Dressed stone platform","Flagstone shadow",0,.650,2,.582,0,.21,open_x=True,bottom_skin=False)
    slab(m,"Dressed stone platform","Dressed platform stone",0,.64,2,.56,.210,.266,open_x=True,bottom_skin=False)
    slab(m,"Platform coping and tactile edge","Paver highlight",0,.395,2,.092,.251,.282,open_x=True)
    slab(m,"Platform coping and tactile edge","Cream paint",0,.427,2,.020,.282,.284,open_x=True,bottom_skin=False)
    slab(m,"Platform paving","Weathered pavers",0,.682,2,.480,.266,.280,
         open_x=True,top_skin=False,bottom_skin=False)
    # Mortar and flagstones use the same top plane and partition it.
    # A raised crossing stripe made two faces cover exactly the same
    # area; even where they didn't cross, it hovered just .001 up.
    full=geos.union([corners(0,.682,2,.480)])
    joints=geos.union([corners(0,.715,2,.009)]+[
        corners(-.9+.2*i,.680,.009,.462) for i in range(10)])
    flags=geos.difference(full,joints)
    m.skin(flags,"Platform paving",P["Weathered pavers"],lambda x,z:.280,geos)
    m.skin(joints,"Scored paving joints",P["Flagstone shadow"],lambda x,z:.280,geos)
    geos.free(full,joints,flags)
    for i in range(0,10,2):
        slab(m,"Dressed blockwork","Flagstone shadow",-.9+.2*i,.356,.012,.009,.04,.245)

    # Recess the finished end to leave a deliberate shallow shadow line.
    # The end walls of adjacent platform tiles have a real .048-node
    # separation, while their tread/coping and both rails still join at 1.
    for x in (-.976,.976):
        def cap(color,z0,z1,lo,hi):
            f=((x,z0,lo),(x,z1,lo),(x,z1,hi),(x,z0,hi))
            m.face("Recessed ashlar platform ends",P[color],f if x>0 else f[::-1])
        cap("Flagstone shadow",.359,.941,.002,.210)
        cap("Dressed platform stone",.360,.920,.210,.251)
        cap("Dressed platform stone",.441,.920,.251,.266)
        cap("Paver highlight",.349,.441,.251,.282)
        cap("Weathered pavers",.442,.922,.266,.280)
    # Wooden rear balustrade and a small shelter with a readable enamel sign.
    for x in (-.91,-.66,-.41,.43,.68,.92):
        slab(m,"Rear platform railing","Forest ironwork",x,.884,.028,.027,.280,.570,.004)
    for start,width in ((-.665,.53),(.665,.52)):
        slab(m,"Rear platform railing","Forest ironwork",start,.884,width,.025,.523,.546)
        slab(m,"Rear platform railing","Forest ironwork",start,.884,width,.018,.430,.444)
    for x in (-.29,.29):
        for z in (.54,.839):
            slab(m,"Cast shelter posts","Forest ironwork",x,z,.031,.032,.276,.791,.004)
            slab(m,"Cast shelter posts","Iron base",x,z,.063,.064,.280,.318,.006)
    slab(m,"Shelter rear glazing","Green enamel",0,.848,.588,.037,.388,.463)
    for h0,h1 in ((.458,.478),(.711,.734)):
        slab(m,"Shelter rear glazing","Forest ironwork",0,.848,.588,.039,h0,h1)
    for x in (-.284,-.098,.098,.284):
        slab(m,"Shelter rear glazing","Forest ironwork",x,.848,.023,.041,.461,.728,.003)
    for x in (-.188,0,.188):
        slab(m,"Shelter rear glazing","Window glass",x,.845,.177,.019,.472,.718,.008)
        slab(m,"Shelter rear glazing","Window glint",x-.052,.834,.014,.003,.491,.696)
    for x in (-.13,.13):
        slab(m,"Timber seat","Forest ironwork",x,.715,.039,.083,.278,.416,.005)
    slab(m,"Timber seat","Bench timber",0,.711,.414,.105,.407,.442,.006)
    slab(m,"Timber seat","Bench timber",0,.775,.414,.028,.458,.544,.004)
    for a,b in ((.495,.696),(.696,.893)):
        y=lambda x,z:.842-abs(z-.696)*.31
        slab(m,"Platform canopy","Slate",0,(a+b)/2,.687,b-a,lambda x,z:y(x,z)-.028,y,.0)
        for x in (-.245,-.123,0,.123,.245):
            slab(m,"Platform canopy","Slate seam",x,(a+b)/2,.012,b-a,lambda x,z:y(x,z),
                 lambda x,z:y(x,z)+.012)
    slab(m,"Platform canopy","Slate shade",0,.496,.704,.022,.747,.786)
    slab(m,"Porcelain station sign","Green enamel",0,.484,.251,.018,.686,.759,.008)
    slab(m,"Porcelain station sign","Cream paint",0,.472,.209,.006,.706,.739,.005)
    for x in (-.064,-.021,.022,.065):
        slab(m,"Porcelain station sign","Green enamel",x,.468,.020,.003,.716,.730)
    for x in (-.76,.77):
        slab(m,"Platform coach lamps","Forest ironwork",x,.767,.030,.030,.278,.753,.006)
        slab(m,"Platform coach lamps","Signal gold",x,.767,.072,.071,.725,.788,.014)
        slab(m,"Platform coach lamps","Forest ironwork",x,.767,.080,.079,.785,.800,.011)
    def platform_profile(_,x,z,h):
        # Keep the flush join and boarding level. Size railings,
        # benches, lighting and canopy to the pedestrian palette.
        return x,z,h if h<=.284 else .284+(h-.284)*.78
    return rail.reprofile(m,platform_profile)


def shed(geos):
    m=clip_behind(rail.rail_geometry(2,0,geos),-.831)
    running_groups=set(m.parts)
    running_groups.update(("Cast end-of-track buffer",))
    # Stock depot faces +Z before the rotated variants are generated.
    outline=.756
    arch=.442
    spring=.759
    eave=1.186
    apex=1.505
    roof=lambda x,z:apex-abs(x)*((apex-eave)/outline)
    for x in (-.605,.605):
        slab(m,"Masonry foundation","Flagstone shadow",x,-.154,.247,1.566,0,.095,.0,"Stone bevel")
        slab(m,"Brick side walls","Old brick",x+(.067 if x>0 else -.067),-.165,.156,1.584,.089,1.186)
        for j in range(13):
            h=.134+.075*j
            side=1 if x>0 else -1
            # Thin mortar-reveal lines and individual toned bricks.
            slab(m,"Side wall coursing","Brick shadow",side*.752,-.165,.015,1.57,h,h+.012)
            for k in range(6):
                if (j*53+k*97)%7>2:
                    continue
                z=-.815+k*.203+(j%2)*.079
                slab(m,"Side wall coursing","Light brick",side*.757,z,.006,.095,h+.019,h+.071)
        for z in (-.62,-.22,.18):
            side=1 if x>0 else -1
            slab(m,"Workshop casement windows","Stone bevel",side*.756,z,.044,.219,.502,.548,.004)
            slab(m,"Workshop casement windows","Forest ironwork",side*.757,z,.038,.203,.540,.812,.004)
            for dz in (-.044,.049):
                slab(m,"Workshop casement windows","Window glass",side*.783,z+dz,.012,.077,.567,.775,.004)
            slab(m,"Workshop casement windows","Stone arch",side*.784,z,.012,.195,.657,.674)
            slab(m,"Workshop casement windows","Brick shadow",side*.753,z,.029,.245,.814,.856)
        slab(m,"Shop interior floor","Weathered pavers",x*.83,-.219,.276,1.345,.006,.061,.012)
    # Closed masonry back. The internal end-of-line buffer physically spans
    # the rolling channels; there is no rail or opening at the back edge.
    for lo,hi,material in ((.0,.17,"Stone bevel"),(.168,1.188,"Old brick")):
        slab(m,"Blind rear wall",material,0,-.883,1.518,.163,lo,hi)
    portrait(m,"Blind rear gable","Old brick",[(-.756,1.185),(.756,1.185),(0,1.508)],-.799,-.948)
    for x in (-.208,.208):
        slab(m,"Cast end-of-track buffer","Soot",x,-.762,.082,.105,.065,.241,.008)
    slab(m,"Cast end-of-track buffer","Workshop door wood",0,-.727,.591,.055,.202,.254,.007)
    for x in (-.206,.208):
        slab(m,"Cast end-of-track buffer","Brick shadow",x,-.694,.136,.023,.207,.248,.005)
    for side in (-1,1):
        x=side*(arch+outline)/2
        slab(m,"Masonry porch piers","Stone bevel",x,.564,outline-arch,.183,0,.111,.007)
        slab(m,"Masonry porch piers","Old brick",x,.564,outline-arch,.183,.11,1.180)
        for j in range(13):
            h=.148+.075*j
            slab(m,"Front wall coursing","Brick shadow",x,.663,outline-arch,.015,h,h+.011)
    # Fill front above the actual semicircular opening. These are solid
    # extruded masonry faces, with separately modeled beveled arch stones.
    for sign in (-1,1):
        portrait(m,"Masonry gable","Old brick",[(sign*arch,1.180),(sign*outline,1.180),
                 (sign*outline,eave),(sign*arch,roof(arch,0))],.645,.463)
    for i in range(16):
        a,b=pi*i/16,pi*(i+1)/16
        x0,x1=arch*cos(a),arch*cos(b)
        y0,y1=spring+arch*sin(a),spring+arch*sin(b)
        portrait(m,"Masonry gable","Old brick",[(x0,y0),(x1,y1),
                 (x1,roof(x1,0)),(x0,roof(x0,0))],.645,.463)
    for i in range(13):
        a=pi*(i+.045)/13
        b=pi*(i+.955)/13
        outer=arch+(.094 if i==6 else .066)
        coords=[(arch*cos(a),spring+arch*sin(a)),(arch*cos(b),spring+arch*sin(b)),
                (outer*cos(b),spring+outer*sin(b)),(outer*cos(a),spring+outer*sin(a))]
        portrait(m,"Dressed stone arch voussoirs","Stone bevel" if i%3==0 else "Stone arch",
                 coords,.687,.633)
    for x in (-.469,.469):
        for j in range(7):
            h=.092+j*.094
            slab(m,"Stone jambs","Stone arch" if j%3 else "Stone bevel",x,.667,.054,.057,h,h+.086,.003)
    # Slate roof with a standing seam and thin contrasting verge trim.
    for a,b in ((-.800,0),(0,.800)):
        slab(m,"Slate roof","Slate", (a+b)/2,-.143,b-a,1.701,roof,
             lambda x,z:roof(x,z)+.060)
        for j in range(10):
            z=-.920+.17*j
            slab(m,"Standing seam roof","Slate seam",(a+b)/2,z,b-a,.015,
                 lambda x,z:roof(x,z)+.058,lambda x,z:roof(x,z)+.071)
        for z in (-.972,.688):
            slab(m,"Slate roof fascia","Slate shade",(a+b)/2,z,b-a,.035,
                 lambda x,z:roof(x,z)-.016,lambda x,z:roof(x,z)+.068)
    slab(m,"Slate ridge","Slate seam",0,-.141,.086,1.709,1.525,1.577,.016)
    slab(m,"Brick chimney","Old brick",-.49,-.591,.184,.185,1.286,1.632,.011)
    slab(m,"Brick chimney","Stone bevel",-.49,-.591,.222,.221,1.618,1.654,.008)
    slab(m,"Brick chimney","Soot",-.49,-.591,.129,.126,1.653,1.668,.011)
    slab(m,"Porcelain portal plaque","Green enamel",0,.669,.240,.036,1.335,1.438,.013)
    slab(m,"Porcelain portal plaque","Cream paint",0,.692,.194,.017,1.359,1.414,.006)
    for x in (-.055,0,.055):
        slab(m,"Porcelain portal plaque","Forest ironwork",x,.704,.027,.007,1.370,1.401,.003)
    for x in (-.622,.622):
        slab(m,"Workshop sconces","Forest ironwork",x,.704,.072,.082,.818,.934,.008)
        slab(m,"Workshop sconces","Signal gold",x,.731,.064,.070,.846,.910,.010)
        slab(m,"Workshop sconces","Forest ironwork",x,.734,.083,.081,.908,.941,.014)
        slab(m,"Bollards","Iron base",x,.833,.103,.097,.002,.063,.010)
        slab(m,"Bollards","Signal gold",x,.833,.061,.058,.053,.242,.011)
        slab(m,"Bollards","Iron base",x,.833,.061,.058,.134,.178,.011)
    def depot_profile(group,x,z,h):
        # Station coordinates/portal direction and running way stay
        # stock. Refit the oversized brick shell to one road-size shed.
        if group in running_groups:
            return x,z,h
        return .82*x,z,h if h<=.128 else .128+(h-.128)*.79
    return rail.reprofile(m,depot_profile)


def atlas():
    def chunk(tag,data):
        return struct.pack(">I",len(data))+tag+data+struct.pack(">I",zlib.crc32(tag+data))
    raw=b"".join(bytes.fromhex(c)*8 for c in rail.COLORS)
    png=b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",8*len(rail.COLORS),8,8,2,0,0,0))
    png+=chunk(b"IDAT",zlib.compress((b"\0"+raw)*8))+chunk(b"IEND",b"")
    (rail.TEXTURES/"bl_rail_architecture_atlas.png").write_bytes(png)


def main():
    geos=rail.Geos()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    bpy.context.scene.name="LuanTTD / rail station and engine shed"
    bpy.context.scene.view_settings.view_transform="Standard"
    mats=rail.materials()
    # Rail metallic luster, not shiny bricks or wooden benches.
    for mat in mats[len(rail.COLORS)-len(EXTRA):]:
        node=mat.node_tree.nodes.get("Principled BSDF")
        node.inputs["Roughness"].default_value=.83
        node.inputs["Metallic"].default_value=0
    p=platform(geos)
    d=shed(geos)
    assets=[("platform_1",p,(-1.5,0)),("platform_2",rotated(p,3),(1.5,0))]
    assets.extend((f"depot_{direction}",rotated(d,turn),((direction-1.5)*2.6,3.2))
                  for direction,turn in enumerate((1,0,3,2)))
    for stem,mesh,(x,z) in assets:
        collection=rail.stash(mesh,mats,stem)
        rail.instance(bpy.context.scene,collection,x,z)
        rail.export_obj(rail.MODELS/f"bl_rail_{stem}.obj",mesh)
    atlas()
    bpy.ops.wm.save_as_mainfile(filepath=str(rail.ROOT/"art/rail_architecture.blend"),compress=True)


if __name__=="__main__":
    main()

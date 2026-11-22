#!/usr/bin/env python3
"""Blender source builder for LuanTTD's three original civic parcels.

Run: blender -b -t 2 --python-exit-code 1 --python tools/build_town_props.py
Each exported mesh occupies one 2x2-node tile. Anchor it at the lower x/z
node at grade + 1, with bl_scenery_palette.png in its one material slot.
"""
from math import cos, pi, sin
import os
from pathlib import Path
from random import Random
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_scenery_art import (
    COLORS, MATS, ROOT, beam, box, bulbs, chimney, gable, hip, init, mesh,
    pane, tapered,
)


def plot(name, x=0, y=0, w=1.87, d=1.87, material="stone"):
    box(name, (x,y,.0175), (w,d,.035), material)


def sett_court(x=0, y=0, w=1.87, d=1.87):
    # Cut setts rather than an image on a slab, with a hand-set perimeter.
    plot("Sand and mortar bed", x, y, w, d, "soil shade")
    mx,my = 10,11
    rng=Random(474)
    for j in range(my):
        a=y+(j+.5-my/2)*d/my
        cut=mx if j%2==0 else mx+1
        for k in range(cut):
            b=x+(k+.5-cut/2)*w/cut
            shade = rng.choice(("stone","stone","pale stone","warm limestone"))
            box("Dressed granite sett",(b,a,.023),(w/cut-.011,d/my-.011,.038),shade)


def text_plate(name, letters, x,y,z, h, color):
    # Geometry, not a decal: raised front lettering faces local -Y.
    curve=bpy.data.curves.new(name,"FONT")
    curve.body=letters
    curve.align_x="CENTER"
    curve.align_y="CENTER"
    curve.size=h
    curve.extrude=.0012
    curve.resolution_u=2
    typ=bpy.data.objects.new(name,curve)
    bpy.context.collection.objects.link(typ)
    typ.location=(x,y,z)
    typ.rotation_euler.x=pi/2
    typ.data.materials.append(MATS[color])
    bpy.ops.object.select_all(action="DESELECT")
    typ.select_set(True)
    bpy.context.view_layer.objects.active=typ
    bpy.ops.object.convert(target="MESH")


def crate(x,y,z=0,w=.21,d=.18,h=.105,tone="cedar"):
    box("Crate slatted base",(x,y,z+h*.10),(w,d,h*.20),tone)
    for q in (-1,1):
        box("Crate long side",(x,y+q*d*.43,z+h*.56),(w,d*.14,h*.89),tone)
        box("Crate short side",(x+q*w*.43,y,z+h*.56),(w*.14,d,h*.89),tone)
        for j in (-1,1):
            box("Crate upright strap",(x+j*w*.32,y+q*d*.505,z+h*.56),(w*.085,d*.10,h*.87),"sapwood")


def goods(x,y,z,tag,c):
    for a in (-1,0,1):
        for b in (-1,1):
            xx,yy=x+a*.046,y+b*.032
            tapered(tag,(xx,yy,z),(xx+.008,yy,z+.033),.025,.017,6,c)


def striped_awning(name,x,back,front,w,zb,zf,colors,ribs=7,soft=False):
    """Slight roof sag and a thin closed sewn surface, with colored bands."""
    for j in range(ribs):
        a,b=x-w/2+w*j/ribs,x-w/2+w*(j+1)/ribs
        c=colors[j%len(colors)]
        mid=(back+front)*.5
        zmid=(zb+zf)*.5-(.018 if soft else .008)
        # A real fabric underside: no doubled coincident faces or z-fighting.
        shell=[(a,back,zb),(a,mid,zmid),(a,front,zf),
               (a,front,zf-.053),(a,front+.009,zf-.053),
               (a,front+.009,zf-.009),(a,mid,zmid-.009),(a,back,zb-.009)]
        side=[(b,y,z) for _,y,z in shell]
        faces=[(0,1,2,3,4,5,6,7),(15,14,13,12,11,10,9,8)]
        for t in range(8):
            q=(t+1)%8
            faces.append((q,t,t+8,q+8))
        mesh(name,shell+side,[tuple(reversed(face)) for face in faces],c)


def stall(x,y,w,display):
    yfront=y-.29
    for dx in (-w*.43,w*.43):
        for dy in (-.25,.27):
            box("Stall pine upright",(x+dx,y+dy,.39),(.049,.056,.72),"cedar")
        beam("Stall diagonal knee brace",(x+dx,y-.245,.45),(x+dx,y-.08,.66),.033,.033,"sapwood")
    for yy in (y-.27,y+.27):
        box("Canvas rail",(x,yy,.675 if yy<y else .792),(w+.035,.037,.042),"sapwood")
    colors=("terracotta","cream","cream") if display=="produce" else ("teal","cream","cream")
    striped_awning("Stall sewn canvas",x,y+.34,y-.36,w+.13,.805,.677,colors,9,True)
    box("Seller counter",(x,yfront+.085,.357),(w*.92,.27,.046),"sapwood")
    box("Seller counter front",(x,yfront+.029,.197),(w*.84,.048,.292),"cedar")
    for j in range(9):
        box("Counter board batten",(x+(j-4)*w*.086,yfront+.001,.193),(.015,.014,.267),"sapwood")
    for k, col in enumerate(("wheat","terracotta","sage") if display=="produce" else ("cream board","straw","trail")):
        cx=x+(k-1)*w*.272
        crate(cx,yfront+.091,.38,.145,.153,.059)
        goods(cx,yfront+.091,.422,"Harvest on sale" if display=="produce" else "Bakery loaf",col)
    for dx in (-w*.40,w*.40):
        box("Stall base peg",(x+dx,y-.22,.059),(.106,.113,.041),"stone")


def market():
    sett_court()
    stall(-.456,.43,.69,"produce")
    stall(.454,.43,.69,"bakery")
    box("Market wayfinding post",(-.792,-.679,.271),(.048,.047,.488),"dark metal")
    box("Market sign",(-.792,-.700,.50),(.229,.034,.117),"teal")
    text_plate("Raised market sign","MARKET",-.792,-.721,.50,.046,"cream")
    for x,y,z in ((.71,-.65,0),(.715,-.657,.106),(.433,-.735,0)):
        crate(x,y,z,.217,.19,.104)
    for x,y in ((-.55,-.64),(-.62,-.205)):
        tapered("Coopered barrel",(x,y,.041),(x,y,.113),.061,.075,10,"cedar")
        tapered("Coopered barrel",(x,y,.113),(x,y,.235),.075,.062,10,"cedar")
        for h,r in ((.069,.068),(.182,.070),(.222,.064)):
            tapered("Barrel iron hoop",(x,y,h),(x,y,h+.013),r,r,10,"metal")


def shop_display(cx,y,z,w=.405):
    box("Shopfront surround",(cx,y-.019,z),(w+.048,.045,.392),"teal")
    box("Recessed display window",(cx,y-.044,z+.010),(w,.019,.308),"glazing")
    box("Display reflection strip",(cx-.038,y-.057,z+.110),(w*.74,.008,.040),"reflection")
    for x in (cx-w*.245,cx+w*.245):
        box("Shopfront mullion",(x,y-.059,z+.006),(.017,.016,.313),"cream")
    box("Shopfront meeting rail",(cx,y-.062,z+.076),(w,.013,.014),"cream")
    for x,c in ((cx-.082,"terracotta"),(cx+.003,"cream board"),(cx+.085,"wheat")):
        box("Goods in display",(x,y-.065,z-.093),(.057,.012,.058),c)
    box("Shopfront sill",(cx,y-.058,z-.166),(w+.05,.059,.028),"pale stone")


def shop():
    plot("Grocer's stone corner forecourt",0,-.395,1.86,1.066,"warm limestone")
    for j in range(11):
        box("Pavement edging",((j-5)*.165,-.878,.031),(.157,.106,.047),"pale stone")
    w,d,x,y=1.495,1.234,0,.243
    f=y-d/2
    plot("Coursed limestone footings",x,y,w+.064,d+.062,"stone")
    box("Two-story burnt brick shop",(x,y,.493),(w,d,.914),"brick")
    box("Shop banding",(x,y,.550),(w+.069,d+.058,.062),"pale stone")
    box("Upper cornice",(x,y,.925),(w+.066,d+.068,.068),"pale stone")
    for side in (-1,1):
        for ht in (.594,.764,.883):
            box("Corner pale stone quoins",(side*w*.5,f-.013,ht),(.174,.046,.043),"pale stone")
        pane("Upper shop sash",side*.475,f,.744,.186,.241,"front","cream")
        pane("Upper side sash",side*w*.5,y-.036,.743,.238,.233,"left" if side<0 else "right","cream")
        pane("Side business sash",side*w*.5,y-.078,.327,.278,.259,"left" if side<0 else "right","cream")
    hip("Hipped raised seam roof",x,y,w,d,.972,1.248,"slate")
    chimney(-.37,y+.17,1.072,.23)
    shop_display(-.435,f,.31)
    shop_display(.438,f,.31)
    box("Open shopfront transom",(0,f-.029,.43),(.264,.047,.11),"pale stone")
    box("Deep green shop door",(0,f-.031,.232),(.210,.041,.361),"teal")
    box("Door glazing",(0,f-.057,.302),(.132,.013,.145),"glazing")
    box("Bell pull",(.072,f-.064,.212),(.019,.022,.026),"gold")
    box("Threshold",(0,f-.095,.064),(.261,.204,.048),"pale stone")
    box("Enameled grocer fascia",(0,f-.048,.545),(1.35,.054,.097),"teal")
    text_plate("Shop sign: painted raised letters","CORNER GROCER",0,f-.078,.545,.089,"cream")
    striped_awning("Shop's striped folding awning",0,f-.062,f-.336,1.39,.484,.396,("teal","cream","teal"),11)
    for xx in (-.63,.63):
        beam("Steel awning stay",(xx,f-.030,.355),(xx,f-.319,.397),.019,.017,"dark metal")
    for xx,c in ((-.65,"wheat"),(.62,"terracotta")):
        crate(xx,-.711,.045,.169,.17,.109)
        goods(xx,-.711,.135,"Shop fruit display",c)


def park_bench(x,y):
    for xx in (x-.192,x+.192):
        box("Bench end casting",(xx,y,.107),(.036,.151,.141),"dark metal")
        beam("Cast bench back support",(xx,y+.066,.139),(xx,y+.104,.311),.023,.023,"dark metal")
    for dy in (-.067,-.017,.032):
        box("Varnished bench slat",(x,y+dy,.175),(.45,.038,.027),"cedar")
    for z in (.226,.282):
        box("Varnished bench back",(x,y+.091,z),(.44,.029,.043),"sapwood")


def clipped_hedge(x,y,length):
    box("Civic planting curb",(x,y,.026),(length+.046,.228,.052),"pale stone")
    for i in range(6):
        xx=x+(i-2.5)*length/6
        tapered("Pruned hedge grouping",(xx,y,.054),(xx+.013,y,.170),.099,.077,7,"hedge")
        tapered("Lit upper hedge leaves",(xx+.010,y,.153),(xx+.014,y,.212),.080,.053,6,"mint")


def lamp(x,y):
    tapered("Cast-iron base",(x,y,.025),(x,y,.155),.043,.026,8,"dark metal")
    tapered("Slender lamp column",(x,y,.140),(x,y,.644),.019,.014,8,"dark metal")
    tapered("Lamp lantern pedestal",(x,y,.628),(x,y,.661),.028,.036,8,"dark metal")
    tapered("Lamp lantern glass",(x,y,.657),(x,y,.743),.035,.049,6,"cream")
    tapered("Lamp lantern cover",(x,y,.74),(x,y,.791),.057,.016,7,"dark metal")


def green():
    plot("Trimmed civic green",0,0,1.862,1.853,"sage")
    box("Gravel walk from street",(0,-.530,.0395),(.39,.688,.011),"trail")
    for i in range(5):
        box("Walkway granite paver",(0,-.779+i*.118,.0475),(.325,.094,.009),"pale stone")
    # True oval paving cut into the lawn, with an opening at the street walk.
    verts=[(.52*cos(2*pi*i/36),.21+.42*sin(2*pi*i/36),.047) for i in range(36)]
    mesh("Ellipse of compacted gravel",verts,[tuple(range(36))],"trail")
    for i in range(26):
        a=2*pi*i/26
        x,y=.513*cos(a),.21+.415*sin(a)
        if y<0 and abs(x)<.20:
            continue
        o=box("Circular paving edge sett",(0,0,0),(.069,.105,.029),"warm limestone")
        o.location=(x,y,.061)
        o.rotation_euler.z=a
    for h,r1,r2 in ((.078,.317,.317),(.130,.252,.239),(.193,.187,.18)):
        tapered("Dressed memorial stair",(0,.201,h),(0,.201,h+.053),r1,r2,12,"pale stone")
    box("Memorial shaft",(0,.20,.375),(.223,.214,.306),"warm limestone")
    box("Memorial plaque",(0,.086,.393),(.137,.021,.143),"dark metal")
    for row in range(3):
        box("Plaque engraving",(0,.073,.358+row*.035),(.098,.004,.012),"gold")
    box("Obelisk shoulder",(0,.20,.547),(.255,.242,.055),"pale stone")
    tapered("Limestone obelisk",(0,.20,.575),(0,.20,.898),.138,.074,4,"warm limestone")
    tapered("Obelisk apex",(0,.20,.895),(0,.20,.958),.075,.006,4,"pale stone")
    for x in (-.558,.558):
        park_bench(x,-.420)
        lamp(x*1.36,-.722)
        clipped_hedge(x*.94,.729,.65)
    for x in (-.715,.715):
        box("Narrow flower bed",(x,.173,.040),(.278,.407,.056),"soil")
        bulbs(x,.082,Random(12))
        bulbs(x,.272,Random(33))


MODELS = (("market",market),("shop",shop),("green",green))

def export(name, make):
    init()
    make()
    bpy.context.scene.name="LuanTTD / town "+name
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/f"art/town_{name}.blend"), compress=True)
    shapes=[o for o in bpy.context.scene.objects if o.type=="MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in shapes:
        o.select_set(True)
    bpy.context.view_layer.objects.active=shapes[0]
    bpy.ops.object.join()
    model=bpy.context.object
    source=model.matrix_world.copy()
    model.matrix_world.identity()
    for v in model.data.vertices:
        v.co=source@v.co+Vector((-.5,-.5,-.5))
    uv=model.data.uv_layers.active or model.data.uv_layers.new()
    for face in model.data.polygons:
        c=COLORS.index(model.data.materials[face.material_index].name)
        for loop in face.loop_indices:
            uv.data[loop].uv=((c+.5)/64,.5)
    model.data.update()
    bpy.ops.wm.obj_export(
        filepath=str(ROOT/f"mods/bayline/models/bl_town_{name}.obj"),
        export_selected_objects=True,export_materials=False,export_uv=True,
        export_normals=True,export_triangulated_mesh=True,global_scale=1,
        forward_axis="NEGATIVE_Z",up_axis="Y",
    )


def render_review(target):
    init()
    for index,(_,make) in enumerate(MODELS):
        before={o.name for o in bpy.context.scene.objects}
        make()
        for obj in bpy.context.scene.objects:
            if obj.name not in before:
                obj.location.x+=(index-1)*2.43
    bpy.ops.object.camera_add(location=(2.8,-6.7,5.6))
    camera=bpy.context.object
    camera.rotation_euler=(Vector((.0,0,.37))-camera.location).to_track_quat("-Z","Y").to_euler()
    camera.data.type="ORTHO"
    camera.data.ortho_scale=7.8
    scene=bpy.context.scene
    scene.camera=camera
    scene.render.engine="BLENDER_WORKBENCH"
    scene.render.resolution_x,scene.render.resolution_y=1450,680
    scene.render.resolution_percentage=100
    scene.world=bpy.data.worlds.new("Sky matte")
    scene.world.color=(.185,.215,.212)
    shading=scene.display.shading
    shading.light="STUDIO"
    shading.color_type="MATERIAL"
    shading.background_type="WORLD"
    shading.show_shadows=True
    shading.show_cavity=True
    shading.cavity_type="BOTH"
    scene.render.filepath=target
    bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    for kind,constructor in MODELS:
        export(kind,constructor)
    if (review_path := os.environ.get("BAYLINE_TOWN_REVIEW")):
        render_review(review_path)

#!/usr/bin/env python3
"""Build LuanTTD's original two-aspect electrical and semaphore signal meshes.

    blender -b -t 4 --python-exit-code 1 --python tools/build_rail_signal_art.py

The OBJ origin is the mast's deck-level anchor. The aspect face is local -Z,
seen by a train approaching on the protected travel direction +Z. The asset
may be rotated and instanced over existing track without a replacement node.
"""
from pathlib import Path
from math import cos, sin, pi
import os
import struct
import sys
import zlib

import bpy
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_rail_art as rail

PALETTE = {
    "Footing":"8d9286", "Footing edge":"aaa99a", "Oxidized steel":"5b6561",
    "Steel edges":"879087", "Black enamel":"282f32", "Backplate":"323938",
    "Weathered white":"ece3c4", "Bolt bronze":"b4936a", "Cable":"504640",
    "Red off":"4b2325", "Green off":"253c34", "Red rim":"ae2623",
    "Green rim":"087e4d", "Red lens":"f94936", "Green lens":"38ea7e",
    "Red brilliance":"ff6a52", "Green brilliance":"7dffa9",
    "Semaphore red":"c63130", "Semaphore cream":"f7e2ae",
    "Semaphore back":"dedcd0", "Semaphore black":"252a2c", "Gold plate":"dca956",
}
P={name:i for i,name in enumerate(PALETTE)}
rail.COLORS[:]=PALETTE.values()


def prism(mesh,name,col,shape,z0,z1,back=None):
    """Extruded convex profile in the X / height plane."""
    if rail.signed_area(shape)<0:
        shape=shape[::-1]
    front=[(x,z0,h) for x,h in shape]
    rear=[(x,z1,h) for x,h in shape]
    mesh.face(name,P[col],front)
    mesh.face(name,P[back or col],rear[::-1])
    for i in range(len(shape)):
        j=(i+1)%len(shape)
        mesh.face(name,P[col],(front[j],front[i],rear[i],rear[j]))


def panel(mesh,name,col,x,h,w,t,z0,z1,corner=.010,back=None):
    a,b=x-w/2,x+w/2
    c,d=h-t/2,h+t/2
    s=corner
    prism(mesh,name,col,((a+s,c),(b-s,c),(b,c+s),(b,d-s),
                        (b-s,d),(a+s,d),(a,d-s),(a,c+s)),z0,z1,back)


def legacy_foot(mesh,x,z,diam=.191):
    def ring(w,h):
        return [(x+w*cos(i*pi/6),z+w*sin(i*pi/6),h) for i in range(12)]
    bottom=ring(diam/2,0)
    edge=ring(diam/2,.041)
    top=ring(diam/2-.012,.062)
    mesh.face("Granite plinth",P["Footing"],bottom[::-1])
    mesh.face("Granite plinth",P["Footing edge"],top)
    for a,b,col in ((bottom,edge,"Footing"),(edge,top,"Footing edge")):
        for i in range(12):
            j=(i+1)%12
            mesh.face("Granite plinth",P[col],(a[i],a[j],b[j],b[i]))
    panel(mesh,"Bolt-down steel base","Oxidized steel",x,.073,.108,.024,z-.058,z+.058,.008)
    for bx in (-.039,.039):
        for bz in (-.038,.038):
            panel(mesh,"Anchoring bolts","Bolt bronze",x+bx,.091,.018,.017,z+bz-.010,z+bz+.010,.005)


def rod(mesh,name,color,x0,h0,x1,h1,width,z,depth):
    dx,dh=x1-x0,h1-h0
    length=(dx*dx+dh*dh)**.5
    a,b=-dh*width/(2*length),dx*width/(2*length)
    prism(mesh,name,color,((x0+a,h0+b),(x0-a,h0-b),(x1-a,h1-b),(x1+a,h1+b)),z-depth/2,z+depth/2)


def disk(mesh,name,col,x,h,r,z0,z1,n=18):
    prism(mesh,name,col,[(x+r*cos(2*pi*i/n),h+r*sin(2*pi*i/n)) for i in range(n)],z0,z1)


def light_ring(mesh,name,x,h,green,active,scale=1):
    r=.079*scale
    shade="Green " if green else "Red "
    disk(mesh,name,"Backplate",x,h,1.12*r,-.097,-.034)
    # Convex clear lens. Several distinct physical bands give a readable
    # edge from survey height, including when the center faces the driver.
    ring_specs=[(1.00,-.099,shade+"off" if not active else shade+"rim"),
                (.83,-.116,shade+"off" if not active else shade+"lens"),
                (.59,-.126,shade+"off" if not active else shade+"lens")]
    loops=[]
    for q,z,_ in ring_specs:
        loops.append([(x+r*q*cos(i*pi/9),z*scale,h+r*q*sin(i*pi/9)) for i in range(18)])
    for a,b,(_,_,color) in zip(loops,loops[1:],ring_specs):
        for i in range(18):
            j=(i+1)%18
            mesh.face(name,P[color],(a[j],a[i],b[i],b[j]))
    mesh.face(name,P[shade+"brilliance" if active else shade+"off"],loops[-1])
    # Hood only across the upper half; it ends just behind the bulged lens
    # to keep the lit color legible from a raised survey view.
    for i in range(10):
        a,b=pi*i/10,pi*(i+1)/10
        shape=[(x+rr*cos(q),h+rr*sin(q)) for rr,q in
               ((r*.99,a),(r*.99,b),(r*1.16,b),(r*1.16,a))]
        prism(mesh,name,"Black enamel",shape,-.115*scale,-.061*scale)


def electrical(green):
    m=rail.Mesh(rail.terrain_height(0))
    legacy_foot(m,0,0)
    # Tapered column has two abutting steel coats before the dark backplate.
    prism(m,"Tapered steel mast","Oxidized steel",
          ((-.035,.078),(.035,.078),(.024,1.29),(-.024,1.29)),-.026,.027)
    prism(m,"Formed steel flange","Steel edges",
          ((.023,.095),(.035,.095),(.023,1.26),(.014,1.26)),-.029,-.025)
    for h in (.245,.397,.550,.703,.856):
        panel(m,"Service ladder steps","Steel edges",.001,h,.123,.018,.023,.061,.006)
    panel(m,"Signal control box","Oxidized steel",.048,.343,.095,.171,.012,.086,.012)
    panel(m,"Signal control inspection plate","Steel edges",.049,.343,.064,.129,.085,.091,.010)
    disk(m,"Cable entry","Cable",.050,.324,.013,.089,.094,10)
    # Driver-facing two-aspect head and two distinct louvers.
    panel(m,"Cast double-aperture head","Black enamel",0,1.335,.289,.562,-.051,.089,.055)
    panel(m,"Rounded rear service cover","Oxidized steel",0,1.337,.249,.501,.092,.103,.049)
    for h,which,active in ((1.470,False,not green),(1.204,True,green)):
        light_ring(m,"Green aperture" if which else "Red aperture",0,h,which,active)
    panel(m,"Number board on mast","Weathered white",0,.916,.143,.085,-.053,-.021,.013)
    for x in (-.043,-.014,.014,.043):
        panel(m,"Number board enamel marks","Backplate",x,.915,.015,.043,-.056,-.052,.004)
    return m


def sema(green):
    m=rail.Mesh(rail.terrain_height(0))
    legacy_foot(m,0,0)
    # Era-appropriate steel lattice post with four visible diagonal links.
    for x in (-.041,.041):
        rod(m,"Riveted lattice stiles","Oxidized steel",x,.071,x*.65,1.396,.025,-.007,.055)
    for i in range(9):
        y=.115+i*.138
        rod(m,"Riveted lattice braces","Steel edges",-.039+.0015*i,y,
            .037-.0012*i,min(1.36,y+.118),.016,-.038,.018)
        rod(m,"Riveted lattice cross members","Oxidized steel",-.040+.0015*i,y,
            .040-.0015*i,y,.017,.014,.049)
    panel(m,"Weatherproof semaphore lamp","Backplate",.026,1.305,.095,.183,
          -.012,.096,.022)
    panel(m,"Semaphore lamp chimney","Oxidized steel",.026,1.419,.054,.066,
          .005,.062,.010)
    panel(m,"Semaphore post number","Weathered white",0,.936,.146,.092,-.060,-.028,.013)
    for x in (-.045,-.014,.016,.047):
        panel(m,"Semaphore number plate markers","Backplate",x,.936,.014,.035,
              -.064,-.057,.003)
    # A single upper-quadrant stop arm. Red stays red on both models; the
    # raised arm, like a real semaphore, is how daytime clear is indicated.
    theta=(-45*pi/180 if green else 0)
    def turn(x,y):
        return x*cos(theta)-y*sin(theta),1.416+x*sin(theta)+y*cos(theta)
    def piece(name,color,coords,z0,z1,back=None):
        prism(m,name,color,[turn(x,h) for x,h in coords],z0,z1,back)
    arm=((- .460,-.045),(-.443,-.065),(-.030,-.065),(.029,-.035),
         (.029,.037),(-.035,.057),(-.454,.057),(-.468,.043))
    piece("Moving upper-quadrant blade","Semaphore red",arm,-.087,-.043,"Semaphore back")
    stripe=((- .365,-.063),(-.300,-.063),(-.300,.055),(-.365,.055))
    piece("Blade face ivory visibility bar","Semaphore cream",stripe,-.091,-.086)
    piece("Black rear semaphore visibility bar","Semaphore black",stripe,-.042,-.037)
    for x in (-.42,-.10):
        next_x,h=turn(x,-.029)
        disk(m,"Blade vane rivets","Bolt bronze",next_x,h,.011,-.094,-.085,8)
    disk(m,"Operating pivot and collar","Backplate",0,1.416,.043,-.096,-.030,14)
    disk(m,"Operating pivot bronze peg","Bolt bronze",0,1.416,.022,-.103,-.093,12)
    # Active spectacle lens color is indicated at the same fixed lamp
    # location; the metal arm and spectacle carrier visibly change pose.
    left,right=turn(.039,-.055),turn(.060,-.159)
    rod(m,"Rotating spectacle bracket","Oxidized steel",*left,*right,.036,-.033,.027)
    disk(m,"Out-of-aspect spectacle glass","Red off" if green else "Green off",
         *right,.028,-.071,-.043,12)
    disk(m,"Active spectacle lens","Green lens" if green else "Red lens",
         .057,1.320,.034,-.084,-.050,14)
    disk(m,"Active spectacle lens inner ring","Green brilliance" if green else "Red brilliance",
         .057,1.320,.020,-.087,-.082,14)
    # Link geometry in a different position for either aspect.
    x,y=turn(-.022,-.047)
    rod(m,"Counterweighted operating rod","Cable",.033,.202,x+.056,y,.017,.044,.015)
    panel(m,"Cast balance weight","Backplate",
          .046,.261 if green else .222,.065,.126,.038,.077,.010)
    return m


def png_atlas():
    def chunk(tag,payload):
        return struct.pack(">I",len(payload))+tag+payload+struct.pack(">I",zlib.crc32(tag+payload))
    colors=b"".join(bytes.fromhex(c)*8 for c in PALETTE.values())
    png=b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",len(PALETTE)*8,8,8,2,0,0,0))
    png+=chunk(b"IDAT",zlib.compress((b"\0"+colors)*8))+chunk(b"IEND",b"")
    (rail.TEXTURES/"bl_rail_signal_atlas.png").write_bytes(png)


def local_obj(mesh):
    # Shared rail exporter is for a two-node mesh overlay 0.5 above deck;
    # here put the physical mast anchor at the entity's own coordinate origin.
    # Luanti entity meshes use internal block-scale units (10 per native node)
    # unlike terrain node OBJ. Keep authoring in real native geometry units.
    out=rail.Mesh(rail.terrain_height(0))
    for group,faces in mesh.parts.items():
        for refs,mat in faces:
            out.face(group,mat,[(10*x-.5,10*z-.5,10*h+.5) for x,z,h
                                in (mesh.vertices[group][i] for i in refs)])
    return out


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene
    scene.name="LuanTTD / original light and upper-quadrant signals"
    scene.view_settings.view_transform="Standard"
    mats=rail.materials()
    for i,n in enumerate(PALETTE):
        mat=mats[i]
        mat.name=n
        node=mat.node_tree.nodes.get("Principled BSDF")
        node.inputs["Metallic"].default_value=.50 if n in ("Oxidized steel","Steel edges","Bolt bronze") else .04
        node.inputs["Roughness"].default_value=.21 if "lens" in n or "brilliance" in n else .81
        if "brilliance" in n or "lens" in n:
            node.inputs["Emission Color"].default_value=mat.diffuse_color
            node.inputs["Emission Strength"].default_value=.22
    for i,(name,make) in enumerate((("light",electrical),("semaphore",sema))):
        for j,green in enumerate((False,True)):
            mesh=make(green)
            aspect="green" if green else "red"
            basename=f"rail_signal_{name}_{aspect}"
            collection=rail.stash(mesh,mats,basename)
            rail.instance(scene,collection,(2*i+j-1.5)*.90,0)
            rail.export_obj(rail.MODELS/f"bl_{basename}.obj",local_obj(mesh))
    png_atlas()
    bpy.ops.wm.save_as_mainfile(filepath=str(rail.ROOT/"art/rail_signals.blend"),compress=True)
    render_path=os.getenv("RAIL_SIGNAL_RENDER")
    if render_path:
        bpy.ops.mesh.primitive_plane_add(size=20,location=(0,0,-.007))
        ob=bpy.context.object
        base=bpy.data.materials.new("Weathered yard")
        base.diffuse_color=(.14,.21,.166,1)
        ob.data.materials.append(base)
        world=bpy.data.worlds.new("Sky")
        world.color=(.40,.46,.52)
        scene.world=world
        bpy.ops.object.light_add(type="AREA",location=(-2.3,-3.5,5))
        key=bpy.context.object
        key.data.energy=560
        key.data.shape="DISK"
        key.data.size=5
        key.rotation_euler=(Vector((0,0,1))-key.location).to_track_quat("-Z","Y").to_euler()
        bpy.ops.object.camera_add(location=(.65,-7,3.05))
        camera=bpy.context.object
        camera.rotation_euler=(Vector((-.11,0,.89))-camera.location).to_track_quat("-Z","Y").to_euler()
        camera.data.type="ORTHO"
        camera.data.ortho_scale=4.25
        scene.camera=camera
        scene.render.engine="BLENDER_EEVEE_NEXT"
        scene.render.resolution_x=1440
        scene.render.resolution_y=930
        scene.render.resolution_percentage=100
        scene.eevee.taa_render_samples=24
        scene.render.filepath=render_path
        bpy.ops.render.render(write_still=True)


if __name__=="__main__":
    main()

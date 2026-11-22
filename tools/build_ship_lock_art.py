#!/usr/bin/env python3
"""Model the original three-tile stepped ship lock and real miter gates.

blender -b -t 4 --python-exit-code 1 --python tools/build_ship_lock_art.py
SHIP_LOCK_RENDER=/tmp/ship-lock.png blender -b -t 4 --python tools/build_ship_lock_art.py
"""
from pathlib import Path
from math import floor
import os
import struct
import sys
import zlib

import bpy
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_ship_facility_art as H

R=H.rail
COLORS=dict(H.PALETTE,**{
    "Lock water":"2a617e", "Lock cut stone":"9faaa3", "Lock pale cap":"b4b6a2",
    "Lock dark submerged stone":"626d66", "Lock climbing brick":"8c7869",
    "Lock mortar":"77766d", "Lock shutter timber":"746251",
    "Lock green iron":"40665a", "Lock painted trim":"72887a",
    "Lock warning color":"c4975c", "Gate black strike":"374b48",
})
H.PALETTE=COLORS
H.P={n:k for k,n in enumerate(COLORS)}
R.COLORS[:]=COLORS.values()
P=H.P
B,Htube=H.box,H.tube
ATLAS="bl_ship_lock_atlas.png"
WIDTH,HEIGHT=512,64
GRASS,WATER=(4,4,32),(44,4,32)
WALL=.602
CHAMBER_HALF=.604
HINGE=.631
UPPER_GATE=1.115
LOWER_GATE=-UPPER_GATE
END_CUT=2-UPPER_GATE
LOWER_CAP=.228
WALL_CAP=1.318
WALL_BOTTOM=-.610


def topo(m,name,c,x0,x1,z0,z1,height):
    m.face(name,P[c],[(x0,z0,height(x0,z0)),(x1,z0,height(x1,z0)),
                     (x1,z1,height(x1,z1)),(x0,z1,height(x0,z1))])


def pool(m,name,x0,x1,z0,z1):
    # One repeat per native node, matching the ordinary canal cube texture.
    def cuts(lo,hi):
        return [lo,*(a for a in (-1,0,1) if lo<a<hi),hi]
    xx,zz=cuts(x0,x1),cuts(z0,z1)
    for a,b in zip(xx,xx[1:]):
        for c,d in zip(zz,zz[1:]):
            topo(m,name,"Lock water",a,b,c,d,lambda x,z:0.)


def water_sheet():
    m=R.Mesh(R.terrain_height(0))
    pool(m,"Moving chamber water",-CHAMBER_HALF,CHAMBER_HALF,LOWER_GATE,UPPER_GATE)
    return m


def lower_wall_height(x,z):
    if z<-.680:return LOWER_CAP
    return LOWER_CAP+(WALL_CAP-LOWER_CAP)*min(1,max(0,(z+.680)/1.500))


def retaining(m,part):
    # Native heights relative each static tile's own top-of-water datum.
    # All profiles share the same world centerline and bank height at joins.
    if part=="lower":
        pieces=[(-1,-.680),(-.680,.820),(.820,1)]
        height=lower_wall_height
        h_offset=0
        caps=(-.680,.820,1)
    else:
        pieces=[(-1,1)]
        h_offset=(1 if part=="upper" else 0)
        caps=(-1,) if part=="upper" else (-1,1)
        height=lambda x,z:WALL_CAP-h_offset
    for s in (-1,1):
        for a,b in pieces:
            z=(a+b)/2
            B(m,"Deep structural retaining walls","Lock dark submerged stone",s*.767,z,.330,b-a,
              WALL_BOTTOM-h_offset,lambda x,z:height(x,z)-.110,top="Stone foundation",no_endcaps=caps)
            B(m,"Dressed retaining masonry quoin","Lock cut stone",s*.768,z,.332,b-a,
              lambda x,z:height(x,z)-.112,lambda x,z:height(x,z)-.037,no_endcaps=caps)
            B(m,"Quarried coping slab","Lock pale cap",s*.771,z,.339,b-a,
              lambda x,z:height(x,z)-.040,height,no_endcaps=caps)

        # Surface-level individualized block faces, with joints offset each
        # course; the plate height is evaluated against the sloping approach.
        for row,h in enumerate((-.466,-.329,-.193,-.056,.081,.218,.355,.492,.629,.766,.903,1.040,1.177)):
            for a in range(9):
                low=h-h_offset
                z=-.935+a*.212+.075*(row%2)
                width=.181 if z<.83 else .125
                if z+width/2>1 or low+.12>min(height(0,z-width/2),height(0,z+width/2))-.047:
                    continue
                mat=("Lock climbing brick" if (a*13+row*47)%7<2 else
                     "Lock cut stone" if (a+row)%3==0 else "Stone foundation")
                B(m,"Staggered lock face masonry blocks",mat,s*.602,z,.008,width,
                  low,low+.119,.005)
        # The exposed back of the chamber is banked up beside the exact
        # inclined track. Narrow strips meet adjoining ordinary terrain.
        if part=="middle":
            terrain=lambda x,z:(z+1)/2
            x0,x1=sorted((s*.936,s*1.0))
            topo(m,"Exact graded outer grass banks","Grassy grade",x0,x1,-1,1,terrain)
            B(m,"Wall access channel ladder hoop","Lock green iron",s*.624,.286,.032,.018,1.269,1.476)
            for z in (.252,.325):
                Htube(m,"Lock deck access ladder stringers","Lock green iron",
                      (s*.628,z,-.327),(s*.628,z,1.467),.010,.010,8)
            for j in range(14):
                h=-.285+.118*j
                Htube(m,"Lock deck access ladder iron treads","Cast steel",
                      (s*.630,.251,h),(s*.630,.327,h),.008,.008,8)

        # Continuous narrow ladderway and iron pedestrian protection.
        zs=(-.91,-.64,-.352,-.065,.228,.538,.833)
        for z in zs:
            base=height(0,z)
            Htube(m,"Safety railing cast sockets","Cast steel",
                  (s*.857,z,base-.012),(s*.857,z,base+.262),.014,.011,9)
        for a,b in pieces:
            for rail_h in (.131,.252):
                B(m,"Joined quay rails","Lock green iron",s*.856,(a+b)/2,.023,b-a,
                  lambda x,z:height(x,z)+rail_h-.008,lambda x,z:height(x,z)+rail_h+.008,
                  no_endcaps=caps)
        for z in (-.831,.016,.831):
            h=height(0,z)
            Htube(m,"Workman's bollard stone plinth","Cut harbour granite",
                  (s*.714,z,h-.008),(s*.714,z,h+.022),.034,.029,10)
            Htube(m,"Cast mooring bollards","Blackened marine hardware",
                  (s*.714,z,h+.016),(s*.714,z,h+.102),.020,.017,12)
            Htube(m,"Cast mooring bollards","Blackened marine hardware",
                  (s*.742,z,h+.092),(s*.686,z,h+.092),.016,.014,12)


def hinge_seats(m,part):
    hi=(1 if part=="upper" else 0)
    z=(END_CUT if part=="lower" else -END_CUT)
    drum_z=z+(-.096 if part=="lower" else .096)
    for s in (-1,1):
        # Hinge footprint bolts develop into the static canal wall. Visible
        # steel sleeve cannot narrow the >1.19-node clear passage.
        x=s*(HINGE+.022)
        B(m,"Cast mitre gate foundation block","Lock pale cap",x,z,.146,.223,-.356-hi,1.280-hi,.012)
        Htube(m,"Greased gate coaxial socket","Lock green iron",
              (s*HINGE,z,-.278-hi),(s*HINGE,z,1.314-hi),.018,.016,12)
        for h in (-.091,.438,.947,1.192):
            Htube(m,"Cast gate pintle mounts","Blackened marine hardware",
                  (s*HINGE,z,h-hi),(s*HINGE,z,h+.033-hi),.022,.021,12)
        # Raised hand-operated geared drum and the fixed small platform.
        x=s*.791
        B(m,"Side capstan platform","Dressed granite edge",x,drum_z,.206,.156,1.294-hi,1.326-hi,.012)
        Htube(m,"Cast manual gearbox drum","Lock green iron",
              (x,drum_z,1.314-hi),(x,drum_z,1.443-hi),.039,.030,12)
        for i in (-1,1):
            Htube(m,"Manual valve and crank handles","Dull brass",
                  (x,drum_z,1.448-hi),(x+i*.091,drum_z,1.448-hi),.011,.009,8)
            Htube(m,"Handle grip","Weathered timber",
                  (x+i*.091,drum_z,1.444-hi),(x+i*.091,drum_z,1.484-hi),.012,.010,9)
    if part=="upper":
        x,z=.797,-.312
        B(m,"Wet well instrument standard","Lock green iron",x,z,.045,.042,.299,.651,.008)
        B(m,"Upper pool level gauge dial case","Blackened marine hardware",x,z,.084,.114,.622,.727,.016)
        B(m,"Upper pool level gauge porcelain face","White enamel",x-.047,z,.013,.085,.638,.709,.011)
        for t in (-.030,-.015,0,.015,.030):
            B(m,"Upper pool level marks","Sign dark",x-.052,z+t,.007,.005,.644,.666,.002)
        for z in (.196,.722):
            B(m,"Platform wet work rail step","Wet inspection deck",
              .788,z,.281,.068,.308,.329,.004)


def shell(part):
    m=R.Mesh(R.terrain_height(0))
    retaining(m,part)
    if part=="lower":
        # True negative-side ordinary pool. A narrow throat remains
        # deliberately empty, filled by the floating chamber water entity.
        pool(m,"Fixed lower reach water",-1,1,-1,END_CUT)
        # Short stone access stair climbs beside the lower lock approach
        # and never intrudes into the actual ship channel.
        for j in range(14):
            z=-.627+j*.097
            h=lower_wall_height(0,z-.048)+.13
            B(m,"Individual limestone staircase treads","Dressed granite edge",-.751,z,
              .210,.088,h-.046,h,.010)
        hinge_seats(m,part)
    elif part=="upper":
        pool(m,"Fixed upper reach water",-1,1,-END_CUT,1)
        hinge_seats(m,part)
    return m


def gate(gate_part,opened):
    m=R.Mesh(R.terrain_height(0))
    sig=-1 if gate_part=="lower" else 1
    for side in (-1,1):
        px,pz=side*HINGE,0.
        qx,qz=(side*.662,sig*.652) if opened else (side*.004,.117)
        dx,dz=qx-px,qz-pz
        length=(dx*dx+dz*dz)**.5
        nx,nz=-dz/length,dx/length
        def profile(a,b,w,off=0):
            return [(px+t*dx+(off+u*w)*nx,pz+t*dz+(off+u*w)*nz)
                    for t,u in ((a,-1),(b,-1),(b,1),(a,1))]
        def plank(n,col,a,b,w,low,high,off=0):
            H.prism(m,n,col,profile(a,b,w,off),low,high)
        # Real timber slats, banded iron hinge and join blocks, reflected
        # into the opposite leaf with the same mechanical linkage.
        plank("Main watertight gate leaf hardwood","Lock shutter timber",.018,.998,.024,-.293,1.196)
        for row in range(15):
            h=-.292+.100*row
            color=("Warm plank","Grey plank","Wet timber","Weathered timber")[(row*7)%4]
            for direction in (-1,1):
                plank("Vertically shuttered plank courses",color,.040,.975,.004,
                      h,h+.094,direction*.025)
        plank("Green iron upper gate cap","Lock green iron",.008,1.005,.035,1.174,1.229)
        plank("Wet timber lower guard beam","Blackened marine hardware",.020,1.003,.039,-.291,-.189)
        for h in (-.069,.351,.831,1.108):
            plank("Gated cross ties","Lock painted trim",.030,.989,.034,h,h+.053)
        for t in (.100,.304,.603,.905):
            cx,cz=px+dx*t,pz+dz*t
            Htube(m,"Gate internal framing brass piers","Dull brass",
                  (cx,cz,-.202),(cx,cz,1.215),.008,.008,8)
        plank("Gate sacrificial guard jamb","Blackened marine hardware",.937,1.009,.033,-.22,1.176)
        for h in (-.061,.419,.951,1.147):
            Htube(m,"Wooden gate forge pivot","Cast steel",
                  (px,pz,h),(px,pz,h+.069),.023,.020,12)
        a=(px+.079*dx,pz+.079*dz,.992)
        b=(px+.859*dx,pz+.859*dz,.156)
        Htube(m,"Diagonal wrought gate brace","Lock green iron",a,b,.014,.014,8)
        # Cap footbridge lowers visual mass and stays beyond the hull when
        # opened; its planar profile is part of the moving entity.
        plank("Tread across top of gate leaf","Wet inspection deck",.050,.973,.049,1.223,1.246)
        for t in (.22,.56,.83):
            x,z=px+dx*t,pz+dz*t
            B(m,"Raised gate footway anti-slip treads","Lock pale cap",x,z,.030,.060,1.246,1.254,.003)
    if not opened:
        B(m,"Closed central rail striker","Gate black strike",0,.117,.020,.036,-.251,1.210,.004)
    return m


def atlas():
    def chunk(tag,payload):
        return struct.pack(">I",len(payload))+tag+payload+struct.pack(">I",zlib.crc32(tag+payload))
    sources=[(GRASS,H.read_source_rgba(R.TEXTURES/"bl_grass0.png")),
             (WATER,H.read_source_rgba(R.TEXTURES/"bl_water3.png"))]
    palette=[bytes.fromhex(p) for p in COLORS.values()]
    rows=[]
    for y in range(HEIGHT):
        buf=bytearray()
        for x in range(WIDTH):
            if y>=44:
                px=palette[min(x//8,len(palette)-1)]
            else:
                px=b"\x2a\x61\x7e"
                for (ax,ay,n),data in sources:
                    if ax-3<=x<ax+n+3 and ay-3<=y<ay+n+3:
                        px=bytes(data[max(0,min(n-1,y-ay))][max(0,min(n-1,x-ax))])
                        break
            buf.extend(px)
        rows.append(b"\0"+bytes(buf))
    png=b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",WIDTH,HEIGHT,8,2,0,0,0))
    png+=chunk(b"IDAT",zlib.compress(b"".join(rows)))+chunk(b"IEND",b"")
    (R.TEXTURES/ATLAS).write_bytes(png)


def uv_tile(x,z,rect):
    u,v,n=rect
    a=max(0,min(1,(1+x)/2))
    b=max(0,min(1,(1+z)/2))
    return ((u+.5+(n-1)*a)/WIDTH,1-(v+.5+(n-1)*b)/HEIGHT)


def export(m,path,entity=False):
    refs=[((i*8+4)/WIDTH,.125) for i in range(len(COLORS))]
    uv_lookup={v:n+1 for n,v in enumerate(refs)}
    append=[]
    normal_off=1
    vert_off=1
    for name,faces in m.parts.items():
        append.append("o "+name.replace(" ","_"))
        world=m.vertices[name]
        verts=[(-10*x,10*h,10*z) if entity else (-x-.5,h-.5,z+.5) for x,z,h in world]
        append.extend("v %.6f %.6f %.6f"%v for v in verts)
        normals=[];ni={};entries=[]
        for ids,col in faces:
            a,b,c=(Vector(verts[i]) for i in ids)
            normal=(b-a).cross(c-a)
            if normal.length_squared<1e-16:continue
            q=tuple(round(i,6) for i in normal.normalized())
            if q not in ni:
                ni[q]=len(normals)
                normals.append(q)
            corners=[]
            for i in ids:
                if col in (P["Lock water"],P["Grassy grade"]):
                    x,z,_=world[i]
                    if col==P["Lock water"]:
                        bx=floor(sum(world[k][0] for k in ids)/len(ids))
                        bz=floor(sum(world[k][1] for k in ids)/len(ids))
                        v=uv_tile(2*(x-bx)-1,2*(z-bz)-1,WATER)
                    else:v=uv_tile(x,z,GRASS)
                    if v not in uv_lookup: refs.append(v);uv_lookup[v]=len(refs)
                    uv=uv_lookup[v]
                else:uv=col+1
                corners.append(f"{vert_off+i}/{uv}/{normal_off+ni[q]}")
            entries.append("f "+" ".join(corners))
        append.extend("vn %.6f %.6f %.6f"%v for v in normals)
        append+=entries
        normal_off+=len(normals);vert_off+=len(verts)
    lines=["# Original three-tile LuanTTD harbour infrastructure"]
    lines.extend("vt %.7f %.7f"%v for v in refs);lines+=append
    path.write_text("\n".join(lines)+"\n")


def configure_materials():
    mats=R.materials()
    for name,i in P.items():
        mat=mats[i];mat.name=name
        node=mat.node_tree.nodes.get("Principled BSDF")
        node.inputs["Roughness"].default_value=.26 if name=="Lock water" else .82
        node.inputs["Metallic"].default_value=.42 if name in ("Lock green iron","Cast steel","Dull brass") else .02
    for name,path in (("Lock water","bl_water3.png"),("Grassy grade","bl_grass0.png")):
        mat=mats[P[name]]
        img=bpy.data.images.load(str(R.TEXTURES/path),check_existing=True);img.pack()
        node=mat.node_tree.nodes.get("Principled BSDF")
        texture=mat.node_tree.nodes.new("ShaderNodeTexImage")
        texture.image=img;texture.interpolation="Closest"
        mat.node_tree.links.new(texture.outputs["Color"],node.inputs["Base Color"])
    return mats


def grade_uv(c):
    for o in c.objects:
        if not ("water" in o.name.lower() or "grass banks" in o.name.lower()):
            continue
        if not o.data.uv_layers:
            layer=o.data.uv_layers.new(name="Original lock water / grade UV")
        else:layer=o.data.uv_layers.active
        for loop in o.data.loops:
            p=o.data.vertices[loop.vertex_index].co
            layer.data[loop.index].uv=((p.x+1)/2,(1-p.y)/2)


def model_instance(scene,c,x,z,h=0):
    ob=R.instance(scene,c,x,z)
    ob.location.z=h
    return ob


def showroom(scene,path):
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.18))
    bed=bpy.data.materials.new("Open lock ambient")
    bed.diffuse_color=(.12,.20,.23,1);bpy.context.object.data.materials.append(bed)
    sky=bpy.data.worlds.new("Coastal open sky");sky.color=(.37,.45,.55);scene.world=sky
    bpy.ops.object.light_add(type="AREA",location=(-4,-5.9,10))
    l=bpy.context.object;l.data.energy=1600;l.data.size=6.4
    l.rotation_euler=(Vector((0,0,0))-l.location).to_track_quat("-Z","Y").to_euler()
    bpy.ops.object.camera_add(location=(11.2,-8.0,11.8))
    c=bpy.context.object
    c.rotation_euler=(Vector((0,0,.53))-c.location).to_track_quat("-Z","Y").to_euler()
    c.data.type="ORTHO";c.data.ortho_scale=10.3;scene.camera=c
    scene.render.engine="BLENDER_EEVEE_NEXT";scene.eevee.taa_render_samples=22
    scene.render.resolution_x=1600;scene.render.resolution_y=1040
    scene.render.resolution_percentage=100;scene.render.filepath=path
    bpy.ops.render.render(write_still=True)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene;scene.name="LuanTTD / graded ship lock with physical open and closed mitre gates"
    scene.view_settings.view_transform="Standard"
    materials=configure_materials()
    atlas()
    parts={}
    for p in ("lower","middle","upper"):
        model=shell(p)
        for d,q in enumerate((1,0,3,2)):
            mesh=H.turn(model,q)
            name=f"ship_lock_{p}_{d}"
            c=R.stash(mesh,materials,name);grade_uv(c)
            export(mesh,R.MODELS/f"bl_{name}.obj")
            if d==1:parts[p]=c
    for k,p in enumerate(("lower","middle","upper")):
        for x in (-1.7,1.7):model_instance(scene,parts[p],x,2*(k-1),1 if k==2 else 0)
    model=water_sheet()
    name="ship_lock_chamber_water"
    data=R.stash(model,materials,name);grade_uv(data)
    for x,h in ((-1.7,0),(1.7,1)):
        model_instance(scene,data,x,0,h)
    export(model,R.MODELS/f"bl_{name}.obj",True)
    for name in ("lower","upper"):
        for opened in (False,True):
            model=gate(name,opened)
            state="open" if opened else "closed"
            file=f"ship_lock_gate_{name}_{state}"
            data=R.stash(model,materials,file)
            show_x=-1.7 if (name=="lower")==opened else 1.7
            model_instance(scene,data,show_x,LOWER_GATE if name=="lower" else UPPER_GATE)
            export(model,R.MODELS/f"bl_{file}.obj",True)
    bpy.ops.wm.save_as_mainfile(filepath=str(R.ROOT/"art/ship_lock.blend"),compress=True)
    if os.getenv("SHIP_LOCK_RENDER"):showroom(scene,os.environ["SHIP_LOCK_RENDER"])


if __name__=="__main__":
    main()

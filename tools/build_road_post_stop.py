#!/usr/bin/env python3
"""Author LuanTTD's original roadside post and light-freight stop.

blender -b -t 3 --python-exit-code 1 --python tools/build_road_post_stop.py
Optional ROAD_POST_STOP_RENDER=/tmp/post-stop.png renders the editable scene.
"""
from collections import defaultdict
from math import cos, pi, sin, sqrt
from pathlib import Path
import os
import struct
import zlib

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
PREFIX = "bl_road_post_stop"
COLORS = {
    "Sandstone": "c5bba0", "Concrete": "a09989", "Paving shade": "938d7e",
    "Fired brick": "a94f3a", "Fired brick light": "bb6146", "Fired brick dark": "963f2f",
    "Mortar": "ce9b72", "Brick recess": "674136",
    "Slated teal": "3a524f", "Slate shadow": "2d3f3e", "Standing seams": "526e65",
    "Signal ivory": "f9e5b8", "Enamel red": "973e29", "Red ironwork": "713f35",
    "Loading bay green": "2d6256", "Siding green": "578373",
    "Counter timber": "775133", "Crate timber": "a57541", "Crate cut wood": "c4995e",
    "Jute": "d1aa65", "Jute side": "b98952", "Canvas": "8c8573", "Twine": "e6d5a7",
    "Metal fasteners": "a7b1aa", "Roof gutter": "52615d", "Mullion shadow": "342c24",
    "Window greenblue": "6c9696", "Window glint": "b1c8c1",
    "Bollard brass": "da9b2a", "Grass": "758449", "Asphalt": "4f5353",
    "Road shoulder": "a59576",
}
assert len(COLORS) == 32


class Mesh:
    """Coordinates local right-handed (longitudinal X, curb Z, elevation)."""
    def __init__(self):
        self.parts = defaultdict(list)

    def face(self, part, color, points):
        for i in range(1,len(points)-1):
            self.parts[part].append((color,(points[0],points[i],points[i+1])))

    def ring(self, part, color, lower, upper, face_color=None, cap_color=None):
        fc=face_color or (lambda i:color)
        self.face(part,color,lower[::-1])
        self.face(part,cap_color or color,upper)
        for i in range(len(lower)):
            j=(i+1)%len(lower)
            self.face(part,fc(i),(lower[i],lower[j],upper[j],upper[i]))

    def box(self, part, color, x0,x1,z0,z1,h0,h1, chamfer=0, cap=None):
        a=chamfer
        coords=[(x0,z0),(x1,z0),(x1,z1),(x0,z1)] if not a else [
            (x0+a,z0),(x1-a,z0),(x1,z0+a),(x1,z1-a),
            (x1-a,z1),(x0+a,z1),(x0,z1-a),(x0,z0+a)]
        f=lambda h,z:h(z) if callable(h) else h
        self.ring(part,color,[(x,z,f(h0,z)) for x,z in coords],
                  [(x,z,f(h1,z)) for x,z in coords],cap_color=cap)

    def post(self,part,color,x,z,bottom,top,r0,r1,n=8,cap=None):
        def ring(h,r):
            return [(x+r*cos(i*2*pi/n),z+r*sin(i*2*pi/n),h) for i in range(n)]
        self.ring(part,color,ring(bottom,r0),ring(top,r1),cap_color=cap)

    def transformed(self, quarter=0):
        out=Mesh()
        for part, faces in self.parts.items():
            for color, poly in faces:
                out.parts[part].append((color,tuple(
                    ((x,z,h),(-z,x,h),(-x,-z,h),(z,-x,h))[quarter] for x,z,h in poly)))
        return out


GLYPHS={
    "P":("1110","1001","1001","1110","1000","1000","1000"),
    "O":("0110","1001","1001","1001","1001","1001","0110"),
    "S":("0111","1000","1000","0110","0001","0001","1110"),
    "T":("1111","0110","0110","0110","0110","0110","0110"),
}


def author_stop(compact=False):
    m=Mesh()
    scale=.71 if compact else 1.
    shift=.19 if compact else 0.
    def box(part,c,x0,x1,z0,z1,h0,h1,ch=0,cap=None):
        m.box(part,c,x0*scale+shift,x1*scale+shift,z0,z1,h0,h1,ch,cap)
    # Ground is local Y=-.50, and asphalt shoulders end at .375 from the center.
    # Dock stays outside .43, leaving the full lane+shoulder unobstructed.
    box("Paved loading platform","Concrete",-.94,.94,.432,.970,-.506,-.420,.028)
    for col in range(10):
        x=-.904+col*.181
        box("Loading-edge kerbstone blocks","Sandstone",x,x+.177,.432,.494,-.488,-.404,.006)
        for j in range(2):
            px=x+(j%2)*.008
            box("Weathered platform flags",("Concrete","Paving shade","Concrete")[(col+2*j)%3],
                px,px+.167,.504+j*.12,.615+j*.12,-.422,-.414,.006)
    for x in (-.86,.86):
        box("Protective wheel bollard base","Brick recess",x-.050,x+.050,.48,.57,-.418,-.391,.009)
        q=x*scale+shift
        m.post("Ribbed loading bollards","Red ironwork",q,.525,-.404,-.234,.030,.024)
        m.post("Bollard visibility collars","Bollard brass",q,.525,-.305,-.278,.030,.030)
        m.post("Bollard cast caps","Red ironwork",q,.525,-.235,-.222,.028,.018)
    # Rear brick room with two genuine ~.47-wide open loading apertures.
    box("Back-wall mortar bed","Mortar",-.695,.695,.849,.910,-.414,.062,.002)
    brick=("Fired brick","Fired brick light","Fired brick","Fired brick dark")
    for row in range(8):
        h=-.410+row*.057
        for j in range(9):
            x0=max(-.694,-.784+(row%2)*.087+j*.176)
            x1=min(.694,-.784+(row%2)*.087+j*.176+.169)
            if x1-x0>.015:
                box("Glazed rear brick courses",brick[(4*row+j+row%3)%4],x0,x1,.842,.914,h,h+.052)
    for j,x in enumerate((-.625,0,.625)):
        box("Brick loading-bay piers","Mortar",x-.066,x+.066,.597,.870,-.413,.082,.007)
        for row in range(8):
            h=-.408+row*.057
            tone=brick[(j+row+row//3)%4]
            box("Exposed pier brick faces",tone,x-.070,x+.070,.590+(row%2)*.011,.873,h,h+.051,.004)
        box("Dressed pier capital","Sandstone",x-.079,x+.079,.581,.883,.050,.092,.009)
    box("Continuous post-office sill beam","Counter timber",-.751,.751,.572,.868,.069,.151,.008)
    # Recessed shutter tracks and slatted valance sit inside true open bays.
    for c in (-.310,.310):
        for x in (c-.219,c+.219):
            box("Steel shutter guides","Red ironwork",x-.016,x+.016,.628,.664,-.371,.061,.003)
        box("Partially rolled shutters","Loading bay green",c-.214,c+.214,.650,.700,-.019,.076,.006)
        for j in range(3):
            h=-.013+j*.029
            box("Shutter slat beads","Siding green",c-.210,c+.210,.644,.652,h,h+.006)
        box("Parcel counter","Counter timber",c-.215,c+.215,.706,.850,-.291,-.256,.006,"Crate cut wood")
        box("Service ledge foot rail","Metal fasteners",c-.190,c+.190,.741,.763,-.387,-.372)
    # Overhanging low pitched canopy, slate folds, distinct ridge and gutters.
    def roof(z):
        return .235-.58*abs(z-.772)
    for z0,z1 in ((.540,.770),(.772,.966)):
        box("Slate pitched loading canopy","Slated teal",-.77,.77,z0,z1,
            lambda z:roof(z)-.036,roof,.0)
    for i in range(12):
        cx=-.728+i*.132
        for z0,z1 in ((.544,.771),(.773,.962)):
            box("Standing seam canopy ribs","Standing seams",cx-.006,cx+.006,z0,z1,
                lambda z:roof(z)-.004,lambda z:roof(z)+.008)
    box("Folded ridge flashing","Standing seams",-.780,.780,.761,.781,.223,.246,.005)
    for z in (.547,.958):
        box("Gutters and dark roof drip","Roof gutter",-.785,.785,z-.011,z+.012,roof(z)-.034,roof(z)+.007,.004)
    box("Rainwater downspout","Roof gutter",.707,.732,.908,.940,-.390,.141,.006)
    # High contrast porcelain fascia with dimensional raised POST and envelope.
    box("Porcelain post-office fascia","Signal ivory",-.444,.444,.506,.562,.070,.150,.012)
    box("Fired-red sign field","Enamel red",-.430,.430,.502,.514,.080,.140,.007)
    for i,c in enumerate("POST"):
        start=-.280+i*.139
        for r,row in enumerate(GLYPHS[c]):
            for col,b in enumerate(row):
                if b=="1":
                    x=start+.021*col; h=.128-.0068*r
                    box("Raised porcelain POST lettering","Signal ivory",x,x+.021,.500,.503,h-.0068,h)
    box("Letter symbol porcelain plate","Signal ivory",.268,.371,.497,.506,.088,.131,.006)
    def stamp(points):
        m.face("Envelope emblem folds","Enamel red",[(x*scale+shift,.495,h) for x,h in points])
    stamp(((.275,.121),(.319,.104),(.319,.111),(.275,.125)))
    stamp(((.319,.104),(.363,.121),(.363,.125),(.319,.111)))
    # Parcel batches stay in their actual loading bays, never in a traffic lane.
    def parcel(x,z,h,w,depth,height,c):
        box("Parcels awaiting collection",c,x-w/2,x+w/2,z-depth/2,z+depth/2,h,h+height,.010,"Crate cut wood")
        # Both twine straps turn down the boxes' curb faces.
        for a in (-.21,.19):
            sx=x+w*a
            box("Parcel twine and shipping labels","Twine",sx-.006,sx+.006,z-depth/2-.004,z+depth/2,h+height-.001,h+height+.004)
            box("Parcel twine and shipping labels","Twine",sx-.006,sx+.006,z-depth/2-.004,z-depth/2+.001,h+.009,h+height)
        box("Parcel twine and shipping labels","Signal ivory",x-.018,x+.020,z-.030,z+.013,h+height-.001,h+height+.005,.002)
    parcel(-.399,.705,-.416,.27,.154,.118,"Crate timber")
    parcel(-.370,.699,-.298,.16,.112,.095,"Jute side")
    parcel(-.198,.757,-.415,.133,.136,.101,"Crate timber")
    for i,x in enumerate((.203,.363,.481)):
        c=x*scale+shift
        h=(-.261,-.205,-.244)[i]
        for b,t,r0,r1 in ((-.416,-.402,.045,.057),(-.402,h-.045,.057,.062),
                         (h-.045,h-.014,.062,.026),(h-.014,h+.004,.026,.033)):
            m.post("Tied canvas mail sacks","Jute" if i!=1 else "Canvas",c,.720+i%2*.032,b,t,r0,r1,n=8,cap="Jute side")
        m.post("Mail sack tied collars","Twine",c,.720+i%2*.032,h-.015,h-.010,.029,.028)
    # Post collection box and its actual shadowed letter slot.
    x=.746
    box("Pedestal collection box","Red ironwork",x-.048,x+.048,.811,.896,-.417,-.243,.009)
    box("Enamel post box housing","Enamel red",x-.072,x+.072,.771,.906,-.260,-.120,.018)
    box("Curved cap of post box","Enamel red",x-.062,x+.062,.779,.897,-.123,-.092,.014)
    box("Post box mouth","Brick recess",x-.043,x+.043,.766,.775,-.179,-.165,.003)
    box("Post box collection plate","Signal ivory",x-.042,x+.042,.766,.773,-.208,-.188,.003)
    return m


def payload(mesh, variant):
    indices={c:i+1 for i,c in enumerate(COLORS)}
    lines=["# LuanTTD original post stop; Y-up node-space OBJ",
           *(f"vt {(i+.5)/len(COLORS):.6f} 0.5" for i in range(len(COLORS)))]
    v_count,n_count=1,1
    for part, polygons in mesh.parts.items():
        lines.append("o "+part.replace(" ","_"))
        vertices,normals,faces={},{},[]
        for color, points in polygons:
            # Same upper-node anchor and engine OBJ X reflection as bridge/depot art.
            points=[tuple(round(q,6) for q in (-x-.5,h,z+.5)) for x,z,h in points]
            a,b,c=points
            ab=[q-p for p,q in zip(a,b)];ac=[q-p for p,q in zip(a,c)]
            n=[ab[(i+1)%3]*ac[(i+2)%3]-ab[(i+2)%3]*ac[(i+1)%3] for i in range(3)]
            area=sqrt(sum(k*k for k in n))
            if area<1e-7:
                raise RuntimeError(f"Degenerate {variant}/{part}: {points}")
            u=tuple(round(q/area,6) for q in n)
            nid=normals.setdefault(u,n_count+len(normals))
            refs=[vertices.setdefault(p,v_count+len(vertices)) for p in points]
            faces.append((refs,indices[color],nid))
        lines.extend("v %.6f %.6f %.6f"%p for p in vertices)
        lines.extend("vn %.6f %.6f %.6f"%n for n in normals)
        lines.extend("f "+" ".join(f"{i}/{c}/{n}" for i in refs) for refs,c,n in faces)
        v_count+=len(vertices);n_count+=len(normals)
    return "\n".join(lines)+"\n"


def atlas():
    def chunk(tag,data):
        return struct.pack(">I",len(data))+tag+data+struct.pack(">I",zlib.crc32(tag+data))
    row=b"".join(bytes.fromhex(c)*8 for c in COLORS.values())
    return (b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",256,8,8,2,0,0,0))
            +chunk(b"IDAT",zlib.compress((b"\0"+row)*8))+chunk(b"IEND",b""))


def make_materials():
    mats={}
    for name,color in COLORS.items():
        mat=bpy.data.materials.new(name)
        rgb=[int(color[i:i+2],16)/255 for i in (0,2,4)]
        mat.diffuse_color=(*[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in rgb],1)
        mats[name]=mat
    return mats


def author(mesh,name,mats,scene):
    collection=bpy.data.collections.new(name)
    scene.collection.children.link(collection)
    for part,faces in mesh.parts.items():
        # Keep named parts independently editable in the saved file.
        geom=bpy.data.meshes.new(part)
        vertices={}
        rings=[list(vertices.setdefault(v,len(vertices)) for v in poly) for _,poly in faces]
        geom.from_pydata(list(vertices),[],rings)
        colors=list(dict.fromkeys(c for c,_ in faces))
        for c in colors:
            geom.materials.append(mats[c])
        for polygon,(color,_) in zip(geom.polygons,faces):
            polygon.material_index=colors.index(color)
        geom.update()
        ob=bpy.data.objects.new(part,geom)
        collection.objects.link(ob)
    return collection


def setup_camera(scene, label):
    loc=(1.85,-2.68,1.56) if label=="Straight stop" else (1.49,-2.42,1.51)
    # Camera faces canopy from the asphalt; Blender authoring +Y is curbward.
    bpy.ops.object.camera_add(location=loc)
    c=bpy.context.object
    c.name="Stop overview"
    c.rotation_euler=(Vector((.01,.56,-.14))-c.location).to_track_quat("-Z","Y").to_euler()
    c.data.type="ORTHO"
    c.data.ortho_scale=2.55
    scene.camera=c
    scene.render.engine="BLENDER_WORKBENCH"
    scene.render.resolution_x,scene.render.resolution_y=1280,760
    scene.render.resolution_percentage=100
    scene.display.shading.light="STUDIO"
    scene.display.shading.color_type="MATERIAL"
    scene.display.shading.show_shadows=True
    scene.display.shading.show_cavity=True
    scene.display.shading.cavity_type="BOTH"
    scene.display.shading.background_type="WORLD"
    scene.world=bpy.data.worlds.new("Soft blue sky")
    scene.world.color=(.11,.16,.22)
    scene.view_settings.view_transform="Standard"


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene
    scene.name="Straight stop"
    mats=make_materials()
    full,bay=author_stop(),author_stop(True)
    for suffix, mesh in [("straight_0", full),("straight_1",full.transformed(1)),
                         *((f"bay_{d}",bay.transformed((-d)%4)) for d in range(4))]:
        (ROOT/"mods/luanttd_core/models"/f"{PREFIX}_{suffix}.obj").write_text(payload(mesh,suffix))
    (ROOT/"mods/luanttd_core/textures"/f"{PREFIX}.png").write_bytes(atlas())
    for label,model in (("Straight stop",full),("Compact bay stop",bay)):
        if label!=scene.name:
            scene=bpy.data.scenes.new(label)
        bpy.context.window.scene=scene
        author(model,label+" — editable architecture",mats,scene)
        stage=Mesh()
        stage.box("Grass lot","Grass",-5,5,-3.5,3.5,-.60,-.508)
        stage.box("Gravel road shoulders","Road shoulder",-4,4,-.380,.380,-.511,-.500)
        stage.box("Road asphalt","Asphalt",-4,4,-.3125,.3125,-.505,-.495)
        for q in range(-10,11):
            stage.box("Centre dashes","Signal ivory",q*.35-.066,q*.35+.066,-.014,.014,-.495,-.494)
        author(stage,"Presentation — not exported",mats,scene)
        setup_camera(scene,label)
    bpy.context.window.scene=bpy.data.scenes["Straight stop"]
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art/road_post_stop.blend"),compress=True)
    if target:=os.environ.get("ROAD_POST_STOP_RENDER"):
        bpy.context.scene.render.filepath=target
        bpy.ops.render.render(write_still=True)


if __name__=="__main__":
    main()

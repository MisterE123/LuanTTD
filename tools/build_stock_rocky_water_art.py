#!/usr/bin/env python3
"""Original RC1 rocky-water overlays and separate native rapids decoration.

python3 tools/build_stock_rocky_water_art.py [--check]
blender -b --python-exit-code 1 --python tools/build_stock_rocky_water_art.py -- --blend

Blender is optional for rebuilding the deterministic runtime OBJ/palette.
"""
from argparse import ArgumentParser
from dataclasses import dataclass, field
from io import BytesIO
from math import cos, hypot, pi, sin, sqrt, tau
from pathlib import Path
from random import Random
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_coastal_sheet import APRON, MASKS, SEA, SHINGLE, bank, source

REPO = Path(__file__).resolve().parents[1]
MOD = REPO / "mods" / "luanttd_core"
RAPIDS = (3, 6, 9, 12)
SWATCHES = (
    ("Submerged basalt", "374849"),
    ("Wet olive slate", "475753"),
    ("Split gray stone", "5e655e"),
    ("Dry silicate", "74776b"),
    ("Pale weathered cap", "8d8c7b"),
    ("Bedded light seam", "aaa38c"),
    ("Broken wake green", "abc5b6"),
    ("Foam highlight", "d4e5d5"),
)


@dataclass
class Part:
    name: str
    points: list = field(default_factory=list)
    faces: list = field(default_factory=list)  # winding, swatch
    uv: list | None = None


def height_field(mask):
    facets = source(mask)

    def height(x,z):
        for a,b,c in facets:
            ax,ay,az = a
            ux,uz = b[0]-ax,b[2]-az
            vx,vz = c[0]-ax,c[2]-az
            d = ux*vz-uz*vx
            f,g = ((x-ax)*vz-(z-az)*vx)/d, (ux*(z-az)-uz*(x-ax))/d
            if f >= -1e-8 and g >= -1e-8 and f+g <= 1+1e-8:
                return ay+f*(b[1]-ay)+g*(c[1]-ay)
        raise AssertionError((mask,x,z,"sample outside its own tile"))
    return height


def cross(a,b,c):
    ux,uy,uz = (b[i]-a[i] for i in range(3))
    vx,vy,vz = (c[i]-a[i] for i in range(3))
    return uy*vz-uz*vy,uz*vx-ux*vz,ux*vy-uy*vx


def stone(name, x,z,rx,rz,rise, angle, support, rng, mode):
    """Closed hand-faceted stone form. Roots remain attached to bed/shore."""
    def footing(floor):
        if mode=="lake" or mode=="shore" and floor<=SEA+.008:
            return SEA-APRON-.08 # no detached skerries at maximum native wave dip
        return floor-(.20 if mode=="shore" else .105)

    p = Part(name)
    count = 7
    angles = [tau*i/count+rng.uniform(-.095,.095) for i in range(count)]
    radial = [rng.uniform(.88,1.11) for _ in angles]
    crest = [rng.uniform(.78,1.08) for _ in angles]
    # The contact ring follows the exact slope (or flat water level).
    # Upper rings narrow unequally to give the split stone real planes.
    for layer,(size,lift,shift_x,shift_z) in enumerate((
        (.73,None,0,0),(.97,.045,0,0),(1.00,.43,-.04,.04),(.58,.91,.08,-.07)
    )):
        for i,a in enumerate(angles):
            u=rx*(radial[i]*size*cos(a)+shift_x)
            v=rz*(radial[i]*size*sin(a)+shift_z)
            xx,zz = x+u*cos(angle)-v*sin(angle),z+u*sin(angle)+v*cos(angle)
            floor=support(xx,zz)
            yy=footing(floor) if layer==0 else floor+rise*lift*(crest[i] if layer>=2 else 1)
            p.points.append((xx,yy,zz))
    p.points += [(x,footing(support(x,z)),z),(x,support(x,z)+rise*1.03,z)]
    for k in range(3):
        for i in range(count):
            j=(i+1)%count
            a,b,c,d = i+k*count,j+k*count,i+(k+1)*count,j+(k+1)*count
            shade = 0 if k==0 else rng.choice((1,1,2,2,3)) if k==1 else rng.choice((2,3,3,4,4))
            p.faces.append(((a,c,b),shade))
            p.faces.append(((b,c,d), min(4,shade+rng.choice((0,0,1))) if k>0 else 0))
    for i in range(count):
        j=(i+1)%count
        p.faces.append(((i,j,4*count),0))
        p.faces.append(((i+3*count, 4*count+1, j+3*count),rng.choice((3,4,4,4,5))))
    return p


def old_bank(mask):
    p = Part("Original exact shingle and land bank", uv=[])
    for line in bank(mask).splitlines():
        kind,*s=line.split()
        if kind=="v": p.points.append(tuple(map(float,s)))
        elif kind=="vt": p.uv.append(tuple(map(float,s)))
        elif kind=="f": p.faces.append((tuple(int(x.split('/')[0])-1 for x in s),None))
    assert len(p.points)==len(p.uv)
    return p


def shoreline(mask):
    ground=height_field(mask)
    rng=Random(0xC0A5+149*mask)
    parts=[old_bank(mask)]
    centers=[]

    for i,(rx,rz,rise) in enumerate((
        (.27,.229,.335),(.205,.168,.266),(.195,.125,.21),
        (.115,.085,.15),(.098,.071,.106),(.074,.058,.095),
    )):
        room=max(rx,rz)*1.17+.018
        candidates=[]
        for _ in range(550):
            x,z=rng.uniform(-1.5+room,.5-room),rng.uniform(-.5+room,1.5-room)
            at=ground(x,z)
            lower=min(ground(x+rx*.66*cos(a),z+rx*.66*sin(a))
                      for a in (0,pi/2,pi,3*pi/2))
            # Keep stone along the shore, not on top of the grass crest or on
            # the distant flat part of a tile with one raised corner.
            if at==SEA and max(ground(x+rx*.65*cos(a),z+rx*.65*sin(a))
                               for a in (0,pi/2,pi,3*pi/2))==SEA:
                continue
            if any(hypot(x-a,z-b)<.71*(rx+c) for a,b,c in centers): continue
            if at>SEA+.75: continue
            near=abs(at-(SEA+.22))+.19*max(0,lower-SEA-.20)
            # Space the big blocks somewhat evenly, with small loose toes.
            crowd=sum(max(0,.63-hypot(x-a,z-b)) for a,b,_ in centers)*(.5 if i<3 else .10)
            candidates.append((near+crowd+rng.uniform(0,.19),x,z))
        if not candidates: continue
        _,x,z=min(candidates)
        centers.append((x,z,rx))
        parts.append(stone(f"Shore split rock {i+1}",x,z,rx,rz,rise,rng.uniform(0,tau),ground,rng,"shore"))
    assert len(parts)>=4, mask
    return parts


def open_water():
    rng=Random(0xC1EA)
    return [stone(f"Open-sea skerry block {i+1}",x,z,rx,rz,h,a,lambda x,z:SEA,rng,"lake")
            for i,(x,z,rx,rz,h,a) in enumerate((
                (-.91,.62,.383,.26,.415,.32),(-.51,.53,.258,.21,.285,.85),
                (-1.14,.92,.19,.16,.236,.78),(-.17,.26,.18,.124,.169,-.15),
                (.18,.93,.145,.13,.186,-.54),(-.68,1.25,.114,.087,.125,.55),
            ))]


def wake(name,x,z,forward,length,width,height,rng):
    """Flat painted froth in the outgoing water plane, not buoy geometry."""
    fx,fz=forward
    sx,sz=-fz,fx
    vertices=[]
    for t,w in ((0,.19),(.22,1),(.63,.74),(1,0)):
        cx=x+fx*length*t + sx*sin(pi*t)*width*.8
        cz=z+fz*length*t + sz*sin(pi*t)*width*.8
        for sign in (-1,1):
            xx,zz=cx+sx*width*w*sign,cz+sz*width*w*sign
            if not (-1.475 < xx < .475 and -.475 < zz < 1.475): return
            vertices.append((xx,height(xx,zz)+.0135,zz))
    p=Part(name,vertices)
    for k in range(3):
        for inds in ((2*k,2*k+1,2*k+2),(2*k+1,2*k+3,2*k+2)):
            a,b,c=[vertices[i] for i in inds]
            normal=cross(a,b,c)[1]
            if abs(normal)>1e-9:
                p.faces.append((inds if normal>0 else inds[::-1], rng.choice((6,6,7))))
    return p


def waterfall(mask):
    height=height_field(mask)
    rng=Random(0xFAA1+177*mask)
    gx=(height(-.35,.5)-height(-.65,.5))/.3
    gz=(height(-.5,.65)-height(-.5,.35))/.3
    norm=hypot(gx,gz)
    fx,fz=-gx/norm,-gz/norm
    sx,sz=-fz,fx
    parts=[]
    for i,(side,along,rx,rz,h) in enumerate((
        (-.68,-.19,.225,.16,.23),(-.75,-.44,.133,.118,.131),
        (.69,.15,.22,.176,.22),(.73,-.09,.11,.102,.14),
    )):
        x,z=-.5+sx*side+fx*along,.5+sz*side+fz*along
        parts.append(stone(f"Rapid side stone {i+1}",x,z,rx,rz,h,rng.uniform(0,tau),height,rng,"rapid"))
        for j,(off,down,l,w) in enumerate(((-.075,.14,.32,.014),(.057,.24,.28,.020),(.093,.32,.19,.015))):
            p=wake(f"Downstream foam {i+1}-{j+1}",x+sx*off+fx*down,z+sz*off+fz*down,
                   (fx,fz),l,w,height,rng)
            if p:parts.append(p)
    crest=-.28
    for j,(side,along) in enumerate(((-.25,.15),(.045,.20),(.25,.19),(-.33,.54),(.09,.50),(.32,.46))):
        p=wake(f"Froth sheen {j+1}",-.5+sx*side+fx*(along+crest),.5+sz*side+fz*(along+crest),
               (fx,fz),rng.uniform(.20,.37),rng.uniform(.012,.025),height,rng)
        if p:parts.append(p)
    return parts


def batch():
    for mask in MASKS:
        yield f"rocky_coastal_bank_{mask}", shoreline(mask), 0
    yield "rocky_water_flat",open_water(),0
    for mask in RAPIDS:
        # Adjacent +X anchor frees the actual sloping-water node. Native
        # OBJ flips X, so moving the anchor east adds one to authored X.
        yield f"river_rapid_rocks_{mask}",waterfall(mask),1


def encode_obj(parts, shift):
    lines=["# Original LuanTTD rock-water art; tools/build_stock_rocky_water_art.py", "o RockyWater"]
    composite=parts[0].uv is not None
    vo,uo,no=1,1,1
    for p in parts:
        lines.append("# "+p.name)
        lines.extend(f"v {x+shift:.6f} {y:.6f} {z:.6f}" for x,y,z in p.points)
        if p.uv is not None:
            lines.extend(f"vt {u*.75:.8f} {v:.8f}" for u,v in p.uv)
        else:
            lines.extend(f"vt {((96 if composite else 0)+4*j+2)/(128 if composite else 32):.8f} .5"
                         for j in range(len(SWATCHES)))
        normals=[]
        faces=[]
        for inds,k in p.faces:
            a,b,c=[p.points[j] for j in inds]
            n=cross(a,b,c)
            d=sqrt(sum(v*v for v in n))
            assert d>1e-9,(p.name,inds,d)
            normals.append("vn "+" ".join(f"{v/d:.7f}" for v in n))
            faces.append("f "+" ".join(f"{j+vo}/{uo+(j if k is None else k)}/{no+len(normals)-1}"
                                        for j in inds))
        lines.extend(normals)
        lines.extend(faces)
        vo+=len(p.points)
        uo+=len(p.points) if p.uv is not None else len(SWATCHES)
        no+=len(normals)
    return ("\n".join(lines)+"\n").encode()


def atlases():
    from PIL import Image
    def png(image):
        with BytesIO() as out:
            image.save(out,format="PNG",optimize=True)
            return out.getvalue()
    palette=Image.new("RGB",(32,32))
    for i,(_,rgb) in enumerate(SWATCHES):
        palette.paste(tuple(bytes.fromhex(rgb)),(i*4,0,i*4+4,32))
    yield "bl_stock_water_rocks_atlas.png",png(palette)
    for v in range(4):
        original=Image.open(MOD/"textures"/f"bl_original_coast_{v}.png").convert("RGB")
        assert original.size==(96,32)
        texture=Image.new("RGB",(128,32))
        texture.paste(original,(0,0))
        texture.paste(palette,(96,0))
        yield f"bl_rocky_coast_{v}.png",png(texture)


def asset_files():
    for name,parts,shift in batch():
        yield MOD/"models"/f"bl_{name}.obj",encode_obj(parts,shift)
    for name,data in atlases():
        yield MOD/"textures"/name,data


def create_blend():
    import bpy
    from mathutils import Vector

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene
    scene.name="LuanTTD | rocky coast, sea and rapids"
    scene["Floor"]="Existing OpenTTD-derived LuanTTD planar shore. Level sea stays independent and waved."
    scene["Provenance"]="Original rock facets and foam accents; OpenTTD 16.0-RC1 rocky-water drawing state, no sprite reused."

    def mat(name,hex):
        m=bpy.data.materials.new(name)
        rgb=tuple(int(hex[i:i+2],16)/255 for i in (0,2,4))
        linear=lambda x:x/12.92 if x<=.04045 else ((x+.055)/1.055)**2.4
        m.diffuse_color=(*map(linear,rgb),1)
        return m

    material_list=[mat(n,c) for n,c in SWATCHES]
    grass=mat("Native original grass (review color)","617650")
    shingle=mat("Native original shingle (review color)","a09777")
    sea=mat("Level water datum (review only)","405c65")
    river=mat("Projected flowing water datum (review only)","557973")
    review= bpy.data.collections.new("Sheet | original source collections and review water")
    scene.collection.children.link(review)

    def create(label, points, faces, mats, cols, dest):
        data=bpy.data.meshes.new(label)
        data.from_pydata([(x,z,y) for x,y,z in points],[],[f[::-1] for f in faces])
        for m in mats: data.materials.append(m)
        for polygon,i in zip(data.polygons,cols): polygon.material_index=i
        data.update()
        obj=bpy.data.objects.new(label,data);dest.objects.link(obj)
        return obj

    for i,(name,parts,shift) in enumerate(batch()):
        group=bpy.data.collections.new(name)
        group.use_fake_user=True
        ox,oz=(i%6)*2.7,-(i//6)*2.8
        for p in parts:
            if p.uv is None:
                create(p.name,p.points,[f for f,k in p.faces],material_list,[k for f,k in p.faces],group)
            else:
                create(p.name,p.points,[f for f,k in p.faces],[grass,shingle],
                       [int(p.uv[f[0]][0]>1/3) for f,k in p.faces],group)
        instance=bpy.data.objects.new(name,None)
        instance.instance_type="COLLECTION";instance.instance_collection=group
        instance.location=(ox,oz,0)
        review.objects.link(instance)
        name_only=name.startswith("river")
        geometry=source(int(name.rsplit("_",1)[1])) if name_only else [[(-1.5,SEA,-.5),(.5,SEA,-.5),(.5,SEA,1.5),(-1.5,SEA,1.5)]]
        for tri in geometry:
            create("Presentation datum (not exported)", [(x+ox,y-.003,z+oz) for x,y,z in tri],
                   [tuple(range(len(tri)))],[river if name_only else sea],[0],review)
    cam=bpy.data.objects.new("Survey review",bpy.data.cameras.new("Survey review"))
    scene.collection.objects.link(cam)
    cam.location=(12.2,-12.9,28)
    cam.rotation_euler=(Vector((6.3,-3.7,-.25))-cam.location).to_track_quat("-Z","Y").to_euler()
    cam.data.type="ORTHO"
    cam.data.ortho_scale=21.0
    scene.camera=cam
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":
                area.spaces.active.region_3d.view_distance=21
                area.spaces.active.region_3d.view_location=(6.3,-3.7,0)
                area.spaces.active.region_3d.view_rotation=cam.rotation_euler.to_quaternion()
                area.spaces.active.shading.color_type="MATERIAL"
    scene.render.engine="BLENDER_WORKBENCH"
    scene.display.shading.color_type="MATERIAL"
    scene.display.shading.light="STUDIO"
    scene.display.shading.show_cavity=True
    scene.display.shading.cavity_type="BOTH"
    scene.render.resolution_x,scene.render.resolution_y=1470,1100
    bpy.ops.wm.save_as_mainfile(filepath=str(REPO/"art"/"stock_rocky_water.blend"),compress=True)
    import os
    if r:=os.getenv("LUANTTD_ROCKY_WATER_REVIEW"):
        scene.render.filepath=r
        bpy.ops.render.render(write_still=True)


def main():
    p=ArgumentParser(description=__doc__)
    p.add_argument("--check",action="store_true")
    p.add_argument("--blend",action="store_true")
    opts=p.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else None)
    if opts.blend:
        create_blend()
        return
    for path,data in asset_files():
        if opts.check:
            assert path.read_bytes()==data, f"{path.name} differs from its original source"
        else:
            tmp=path.with_suffix(".tmp")
            tmp.write_bytes(data)
            tmp.replace(path)


if __name__=="__main__":main()

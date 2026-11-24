#!/usr/bin/env python3
"""Original RC1 rocky-water overlays and separate native rapids decoration.

python3 tools/build_stock_rocky_water_art.py [--check]
blender -b --python-exit-code 1 --python tools/build_stock_rocky_water_art.py -- --blend

Blender is optional for rebuilding the deterministic runtime OBJ/palette.
"""
from argparse import ArgumentParser
from dataclasses import dataclass, field
from io import BytesIO
from math import atan2, cos, hypot, pi, sin, sqrt, tau
from pathlib import Path
from random import Random
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_coastal_sheet import MASKS, SEA, bank, source

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


def stone(name, x,z,rx,rz,rise, angle, support, rng, mode, depth=None, emerge=0):
    """Closed hand-faceted stone form. Roots remain attached to bed/shore."""
    depths={"lake":.35, "shore":.19, "bed":.38, "rapid":.31}
    thickness=depth if depth is not None else depths[mode]
    def footing(floor):
        return floor-thickness

    p = Part(name)
    count = 5 if mode=="bed" else 7
    angles = [tau*i/count+rng.uniform(-.095,.095) for i in range(count)]
    radial = [rng.uniform(.88,1.11) for _ in angles]
    crest = [rng.uniform(.78,1.08) for _ in angles]
    # The contact ring follows the exact slope (or flat water level).
    # Upper rings narrow unequally to give the split stone real planes.
    for layer,(size,lift,shift_x,shift_z) in enumerate((
        (.53,None,-.03,.04),(.94,emerge,0,0),(1.00,emerge+.43,-.04,.04),(.56,emerge+.91,.08,-.07)
    )):
        for i,a in enumerate(angles):
            u=rx*(radial[i]*size*cos(a)+shift_x)
            v=rz*(radial[i]*size*sin(a)+shift_z)
            xx,zz = x+u*cos(angle)-v*sin(angle),z+u*sin(angle)+v*cos(angle)
            floor=support(xx,zz)
            yy=footing(floor) if layer==0 else floor+rise*lift*(crest[i] if layer>=2 else 1)
            p.points.append((xx,yy,zz))
    p.points += [(x,footing(support(x,z)),z),(x,support(x,z)+rise*(emerge+1.03),z)]
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


# Low standalone slabs: widest part is close to half-height, and the foot
# narrows back in. Nothing grows a straight shaft to meet a falling wave.
def slab(name, x,z,rx,rz,top,thickness,angle,rng,wet=False):
    p=Part(name)
    n=6
    angular=[tau*i/n+rng.uniform(-.12,.12) for i in range(n)]
    edges=[rng.uniform(.82,1.09) for _ in range(n)]
    for layer,(size,frac,sx,sz) in enumerate(((.53,0,-.08,.03),(1,.41,0,0),(.67,.83,.09,-.07))):
        for i,a in enumerate(angular):
            u=rx*(edges[i]*size*cos(a)+sx)
            v=rz*(edges[i]*size*sin(a)+sz)
            y=top-thickness+thickness*(frac+(rng.uniform(-.08,.08) if layer else 0))
            p.points.append((x+u*cos(angle)-v*sin(angle),y,z+u*sin(angle)+v*cos(angle)))
    p.points += [(x,top-thickness,z),(x+rx*.05,top,z)]
    for j in range(n):
        k=(j+1)%n
        p.faces.append(((j,k,3*n),0))
        for layer in range(2):
            a,b,c,d=j+layer*n,k+layer*n,j+(layer+1)*n,k+(layer+1)*n
            shades=(0,0,1) if wet else (1,2,2) if layer==0 else (2,3,3,4)
            p.faces+= [((a,c,b),rng.choice(shades)),((b,c,d),rng.choice(shades))]
        p.faces.append(((j+2*n,3*n+1,k+2*n),rng.choice((0,1,1) if wet else (3,4,4,5))))
    return p


def rotated(part, quarter):
    # Actual parcel center in authored coordinates. The native even/even
    # node anchor is offset by half a node, so facedir alone would drift.
    points=[]
    for x,y,z in part.points:
        u,v=x+.5,z-.5
        for _ in range(quarter): u,v=-v,u
        points.append((u-.5,y,v+.5))
    return Part(part.name,points,part.faces.copy(),part.uv)



def shoreline(mask, variant):
    ground=height_field(mask)
    rng=Random(0xC0A5+149*mask+859*variant)
    parts=[old_bank(mask)]
    centers=[]
    # Candidate support is local, rather than rotating the bank. Forms lean
    # toward the waterline, rather than borrowing the land's vertical scale.
    designs=(
        ((.244,.183,.130),(.217,.151,.114),(.160,.11,.088),(.138,.091,.076),(.101,.080,.058),(.074,.063,.045)),
        ((.292,.169,.135),(.163,.107,.079),(.185,.118,.085),(.127,.097,.066),(.093,.072,.056),(.087,.057,.045)),
    )
    for i,(rx,rz,rise) in enumerate(designs[variant]):
        room=max(rx,rz)*1.15+.008
        candidates=[]
        for _ in range(650):
            x,z=rng.uniform(-1.5+room,.5-room),rng.uniform(-.5+room,1.5-room)
            at=ground(x,z)
            edge=[ground(x+rx*.82*cos(a),z+rx*.82*sin(a)) for a in (0,pi/2,pi,3*pi/2)]
            lower,upper=min(edge),max(edge)
            if upper<=SEA+1e-6 or at>SEA+.41:
                continue
            if any(hypot(x-a,z-b)<.60*(rx+c) for a,b,c in centers): continue
            desired=SEA+(.061 if i<3 else .085)
            near=abs(at-desired)+.90*max(0,lower-SEA-.070)
            crowd=sum(max(0,.57-hypot(x-a,z-b)) for a,b,_ in centers)*(.34 if variant==0 else -.11)
            candidates.append((near+crowd+rng.uniform(0,.07),x,z,lower))
        if not candidates: continue
        _,x,z,lower=min(candidates)
        centers.append((x,z,rx))
        ceiling=max(SEA+.050,min(ground(x,z)+rise,SEA+max(.071,rx*.72)))
        thickness=min(1.06*max(rx,rz),max(rise+.040,ceiling-lower+.068))
        parts.append(slab(f"Shore slab {i+1}",x,z,rx,rz,ceiling,thickness,rng.uniform(0,tau),rng))
    # Scatter real water-side toes into the two halves of the actual
    # shoreline contour. These low boulders straddle the existing bank
    # instead of revealing a blank vertical skirt under their crests.
    edges=[]
    for tri in source(mask):
        if max(q[1] for q in tri)<=SEA:
            continue
        for a,b in zip(tri,tri[1:]+tri[:1]):
            if a[1]==b[1]==SEA:
                edges.append((a,b))
    for i,(a,b) in enumerate(edges):
        dx,dz=b[0]-a[0],b[2]-a[2]
        angle=atan2(dz,dx)
        for j,f in enumerate((.33,.66) if variant==0 else (.42,.71)):
            u=f+rng.uniform(-.048,.048)
            x,z=a[0]+u*dx,a[2]+u*dz
            rx,rz=(.212,.129) if (variant+j)%2==0 else (.162,.118)
            parts.append(slab(f"Shingle toe {i+1}.{j+1}", x,z,rx,rz,
                              SEA+(.072 if j==0 else .034),.147,angle+rng.uniform(-.21,.21),rng))
    assert len(parts)>=4, (mask,variant)
    return parts


# Distinct ledge, rounded stack, twin islets and scattered shoal profiles.
# Tuples: offset from parcel center, ellipse radii, crest height, long axis.
OPEN_SHAPES=(
    ((-.24,.09,.39,.22,.177,.04),(.34,.16,.28,.19,.124,-.34),(-.45,-.28,.21,.14,.115,.12)),
    ((-.33,-.18,.29,.28,.194,-.18),(-.06,.19,.29,.24,.118,.81),(.28,.38,.18,.15,.082,.12),( .26,-.32,.17,.14,.068,.42)),
    ((-.38,.18,.33,.22,.126,.44),(.38,-.22,.32,.24,.180,-.20),(.53,.17,.15,.12,.078,.63),(-.56,-.14,.15,.13,.07,.26)),
    ((-.49,-.06,.21,.17,.076,-1.11),(-.13,.38,.22,.17,.137,-.45),(.24,.17,.21,.17,.08,.58),(.48,-.24,.25,.17,.138,-1.10),(-.12,-.37,.20,.16,.064,.90)),
)
def open_water(form):
    rng=Random(0xC1EA+7577*form)
    parts=[]
    for i,(u,v,rx,rz,h,angle) in enumerate(OPEN_SHAPES[form]):
        x,z=u-.5,v+.5
        parts.append(slab(f"Exposed skerry {i+1}",x,z,max(rx,.181),max(rz,.142),SEA+h,h+.101,angle,rng))
        # Three shorter separate stones overlap and underlap the exposed
        # body. Offset every successive shelf; no extruded silhouette.
        for j,(top,thick,expand) in enumerate(((-.087,.210,1.07),(-.244,.239,1.18),(-.402,.302,1.11))):
            dx=(j+1)*rng.uniform(-.055,.055)
            dz=(j+1)*rng.uniform(-.059,.059)
            parts.append(slab(f"Submerged shelf {i+1}.{j+1}",x+dx,z+dz,
                              min(max(rx*expand,thick*.92),.40),min(max(rz*expand,thick*.86),.33),SEA+top,thick,
                              angle+rng.uniform(-.49,.49),rng,True))
    # Other lower rocks are secondary outcrops, not foundation feet.
    for i,(u,v) in enumerate(((-.28,.59),(.06,-.54),(.46,.45))):
        a=form*pi/8
        x=u*cos(a)-v*sin(a)-.5
        z=u*sin(a)+v*cos(a)+.5
        parts.append(slab(f"Submerged spill {i+1}",x,z,.19,.15,SEA-(.11+i*.08),.15,.16+i*.9,rng,True))
    return parts


def waterfall(mask):
    height=height_field(mask)
    rng=Random(0xFAA1+177*mask)
    gx=(height(-.35,.5)-height(-.65,.5))/.3
    gz=(height(-.5,.65)-height(-.5,.35))/.3
    norm=hypot(gx,gz)
    fx,fz=-gx/norm,-gz/norm
    sx,sz=-fz,fx
    parts=[]
    for i,(side,along,rx,rz,h,dip) in enumerate((
        (-.68,-.19,.23,.18,.26,.46),(-.74,-.44,.16,.15,.12,.33),
        (.69,.15,.24,.19,.22,.41),(.72,-.085,.15,.12,.10,.33),
        (-.16,.18,.21,.18,.16,.47),(.24,-.40,.155,.15,.105,.32),
    )):
        x,z=-.5+sx*side+fx*along,.5+sz*side+fz*along
        # Embed solid, closed stones in the riverbed. The flowing sheet
        # intersects them partway up their flanks on all viewing sides.
        level=height(x,z)-.035
        parts.append(stone(f"Riverbed block {i+1}",x,z,rx,rz,h,rng.uniform(0,tau),
                           lambda _x,_z:level,rng,"rapid",dip))
    return parts


def batch(include_rotations=True):
    for mask in MASKS:
        for variant in range(2):
            suffix="_1" if variant else ""
            yield f"rocky_coastal_bank_{mask}{suffix}", shoreline(mask,variant), 0
    for form in range(len(OPEN_SHAPES)):
        rocks=open_water(form)
        for quarter in range(4):
            if quarter and not include_rotations:
                continue
            suffix=f"_{form}_{quarter}" if form or quarter else ""
            yield f"rocky_water_flat{suffix}", [rotated(p,quarter) for p in rocks], 0
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
    foam=Image.new("RGBA",(16,16))
    for y in range(16):
        for x in range(16):
            d=hypot((x-7.5)/7.5,(y-7.5)/6.5)
            alpha=round(220*max(0,1-d)**1.28)
            foam.putpixel((x,y),(223,239,233,alpha))
    yield "bl_river_foam.png",png(foam)
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
    scene["Provenance"]="Original closed rock volumes and riverbed blocks; OpenTTD 16.0-RC1 rocky-water drawing state, no sprite reused."

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

    for i,(name,parts,shift) in enumerate(batch(include_rotations=False)):
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
    cam.location=(11.2,-15.2,30)
    cam.rotation_euler=(Vector((6.3,-8.4,-.25))-cam.location).to_track_quat("-Z","Y").to_euler()
    cam.data.type="ORTHO"
    cam.data.ortho_scale=27.0
    scene.camera=cam
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":
                area.spaces.active.region_3d.view_distance=27
                area.spaces.active.region_3d.view_location=(6.3,-8.4,0)
                area.spaces.active.region_3d.view_rotation=cam.rotation_euler.to_quaternion()
                area.spaces.active.shading.color_type="MATERIAL"
    scene.render.engine="BLENDER_WORKBENCH"
    scene.display.shading.color_type="MATERIAL"
    scene.display.shading.light="STUDIO"
    scene.display.shading.show_cavity=True
    scene.display.shading.cavity_type="BOTH"
    scene.render.resolution_x,scene.render.resolution_y=1470,1100
    dest=REPO/"art"/"stock_rocky_water.blend"
    temporary=dest.with_name("stock_rocky_water.tmp.blend")
    bpy.ops.wm.save_as_mainfile(filepath=str(temporary),compress=True)
    temporary.replace(dest)
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

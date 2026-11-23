#!/usr/bin/env python3
"""Author LuanTTD's original 3D rail meshes in Blender (GEOS >= 3.10).

    blender -b -t 4 --python tools/build_rail_art.py
    RAIL_ART_RENDER=/tmp/luanttd-track.png blender -b -t 4 --python tools/build_rail_art.py

No assets or meshes are copied from OpenTTD. The six track bit indexes are
its topology; the rail profiles, timberwork, ballast and presentation are ours.
Runtime needs only OBJ and the embedded atlas texture, not GEOS or Blender.
"""
from ctypes import CDLL, POINTER, byref, c_byte, c_char_p, c_double, c_int, c_uint, c_void_p
from ctypes.util import find_library
from math import atan2, ceil, cos, hypot, pi, sin
from pathlib import Path
from random import Random
import os
import struct
import zlib

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / "mods/luanttd_core/models"
TEXTURES = ROOT / "mods/luanttd_core/textures"
GEOMETRY_PRECISION = 1e-6
# Railhead centres fit the two wheel-tread centres of the editable train art.
GAUGE = .424
HEAD = .030    # half-width of the worn running surface
FOOT = .043    # half-width of flared rail foot
SLEEPER = .300
TRACK_TOP = .114
BED_EDGE = .358
BED_CROWN = .284
BALLAST = ["6b6457", "71695a", "776d5c", "776f63", "82786a", "696257"]
TIES = ["725440", "654737", "77503a", "60483a", "735641"]
COLORS = BALLAST + TIES + [
    "5d4b40",   # tie bevel in shadow
    "49403b",   # creosoted end grain
    "544d47",   # dark chairs and flange guards
    "5d4840",   # oxidized rail foot
    "756156",   # weathered rail web
    "8b8277",   # railhead sides
    "b9bfc0",   # worn steel top
    "a3aeb0",   # less polished turnout hardware
]
BALLAST_N = len(BALLAST)
BEVEL, END, CHAIR, FOOT_MAT, WEB, HEAD_SIDE, STEEL, POINTS = range(11, 19)

# Engine-world axes. Stock NE=-X, SE=+Z, SW=+X, NW=-Z.
SIDE = ((-1.,0.), (0.,1.), (1.,0.), (0.,-1.))
# In stock order X, Y, UPPER, LOWER, LEFT, RIGHT (Track bits 1, 2, 4, 8, 16, 32).
TRACKS = ((0,2), (3,1), (0,3), (2,1), (2,3), (0,1))
NAMES = ("X", "Y", "Upper", "Lower", "Left", "Right")


class Geos:
    """Small C-API wrapper. No Python package installs needed for regeneration."""
    def __init__(self):
        name = find_library("geos_c")
        if not name:
            raise RuntimeError("Rail mesh authoring requires GEOS >=3.10 (libgeos_c).")
        lib = self.lib = CDLL(name)
        for sig in (
            ("initGEOS", None, c_void_p, c_void_p),
            ("GEOSGeomFromWKT", c_void_p, c_char_p),
            ("GEOSBufferWithStyle", c_void_p, c_void_p, c_double, c_int, c_int, c_int, c_double),
            ("GEOSUnaryUnionPrec", c_void_p, c_void_p, c_double),
            ("GEOSDifferencePrec", c_void_p, c_void_p, c_void_p, c_double),
            ("GEOSIntersectionPrec", c_void_p, c_void_p, c_void_p, c_double),
            ("GEOSConstrainedDelaunayTriangulation", c_void_p, c_void_p),
            ("GEOSGeom_destroy", None, c_void_p),
            ("GEOSGeomTypeId", c_int, c_void_p),
            ("GEOSGetNumGeometries", c_int, c_void_p),
            ("GEOSGetGeometryN", c_void_p, c_void_p, c_int),
            ("GEOSGetExteriorRing", c_void_p, c_void_p),
            ("GEOSGetNumInteriorRings", c_int, c_void_p),
            ("GEOSGetInteriorRingN", c_void_p, c_void_p, c_int),
            ("GEOSGeom_getCoordSeq", c_void_p, c_void_p),
            ("GEOSCoordSeq_getSize", c_int, c_void_p, POINTER(c_uint)),
            ("GEOSCoordSeq_getX", c_int, c_void_p, c_uint, POINTER(c_double)),
            ("GEOSCoordSeq_getY", c_int, c_void_p, c_uint, POINTER(c_double)),
            ("GEOSisEmpty", c_byte, c_void_p),
        ):
            n, ret, *args = sig
            f = getattr(lib, n)
            f.argtypes = args
            f.restype = ret
        lib.initGEOS(None, None)

    def free(self, *geoms):
        for g in geoms:
            if g:
                self.lib.GEOSGeom_destroy(g)

    def union(self, rings):
        def ring(points):
            return "((" + ",".join(f"{x:.7f} {z:.7f}" for x,z in (*points, points[0])) + "))"
        poly = self.lib.GEOSGeomFromWKT(("MULTIPOLYGON(" + ",".join(map(ring,rings)) + ")").encode())
        assert poly
        result = self.lib.GEOSUnaryUnionPrec(poly, GEOMETRY_PRECISION)
        self.free(poly)
        assert result
        return result

    def difference(self, a, b):
        g = self.lib.GEOSDifferencePrec(a,b,GEOMETRY_PRECISION)
        assert g
        return g

    def ribbon(self, points, half_width):
        line = self.lib.GEOSGeomFromWKT(("LINESTRING(" + ",".join(f"{x:.7f} {z:.7f}" for x,z in points) + ")").encode())
        assert line
        out = self.lib.GEOSBufferWithStyle(line, half_width, 4, 2, 1, 1.)
        self.free(line)
        assert out
        return out

    def members(self,g):
        if self.lib.GEOSisEmpty(g):
            return
        if self.lib.GEOSGeomTypeId(g)==3:
            yield g
        else:
            for i in range(self.lib.GEOSGetNumGeometries(g)):
                p=self.lib.GEOSGetGeometryN(g,i)
                if p and p!=g:
                    yield from self.members(p)

    def ring(self, r):
        seq = self.lib.GEOSGeom_getCoordSeq(r)
        n = c_uint()
        self.lib.GEOSCoordSeq_getSize(seq,byref(n))
        pairs=[]
        x,y=c_double(),c_double()
        for i in range(n.value-1):
            self.lib.GEOSCoordSeq_getX(seq,i,byref(x))
            self.lib.GEOSCoordSeq_getY(seq,i,byref(y))
            pairs.append((x.value,y.value))
        return pairs

    def rings(self,g):
        for p in self.members(g):
            exterior=self.ring(self.lib.GEOSGetExteriorRing(p))
            yield exterior if signed_area(exterior)>0 else exterior[::-1]
            for i in range(self.lib.GEOSGetNumInteriorRings(p)):
                inner=self.ring(self.lib.GEOSGetInteriorRingN(p,i))
                yield inner if signed_area(inner)<0 else inner[::-1]

    def triangles(self,g):
        for p in self.members(g):
            t = self.lib.GEOSConstrainedDelaunayTriangulation(p)
            assert t
            for child in self.members(t):
                points=self.ring(self.lib.GEOSGetExteriorRing(child))
                assert len(points)==3
                if abs(signed_area(points))>1e-10:
                    yield points if signed_area(points)>0 else points[::-1]
            self.free(t)


def signed_area(points):
    return sum(x*z2-z*x2 for (x,z),(x2,z2) in zip(points,points[1:]+points[:1]))/2


class TrackPath:
    def __init__(self, i):
        a,b=self.a,self.b=tuple(SIDE[d] for d in TRACKS[i])
        self.is_straight= i<2
        self.length=2 if self.is_straight else pi/2
        if not self.is_straight:
            self.cx,self.cz=a[0]+b[0], a[1]+b[1]
            self.angle=atan2(a[1]-self.cz,a[0]-self.cx)
            end=atan2(b[1]-self.cz,b[0]-self.cx)
            self.turn=(1 if (end-self.angle)%(2*pi)<pi else -1)*pi/2

    def sample(self,t):
        if self.is_straight:
            ax,az=self.a
            return ax*(1-2*t),az*(1-2*t),-ax,-az
        a=self.angle+self.turn*t
        s,c=sin(a),cos(a)
        sg=1 if self.turn>0 else -1
        return self.cx+c,self.cz+s,-s*sg,c*sg

    def offset(self,t,offset):
        x,z,dx,dz=self.sample(t)
        return x-dz*offset,z+dx*offset

    def sweep(self,low,high,begin=0.,end=1.):
        n=1 if self.is_straight else max(1,ceil((end-begin)*22))
        ts=[begin+(end-begin)*i/n for i in range(n+1)]
        return [self.offset(t,low) for t in ts]+[self.offset(t,high) for t in reversed(ts)]

    def distance(self,x,z):
        if self.is_straight:
            return abs(z if self.a[0] else x)
        angle=atan2(z-self.cz,x-self.cx)
        f=((angle-self.angle)* (1 if self.turn>0 else -1))%(2*pi)
        if f<=pi/2+1e-7:
            return abs(hypot(x-self.cx,z-self.cz)-1)
        return min(hypot(x-ax,z-az) for ax,az in (self.a,self.b))


def edge(a,b):
    return ((abs(a[0]-b[0])<1e-6 and abs(abs(a[0])-1)<1e-6)
         or (abs(a[1]-b[1])<1e-6 and abs(abs(a[1])-1)<1e-6))


def terrain_height(axis):
    if axis==0: return lambda x,z:0
    if axis==1: return lambda x,z:(x+1)/2
    if axis==2: return lambda x,z:(1-x)/2
    if axis==3: return lambda x,z:(z+1)/2
    if axis==4: return lambda x,z:(1-z)/2
    raise ValueError(axis)


class Mesh:
    def __init__(self,grade):
        self.grade=grade
        self.parts={}
        self.vertices={}
        self.lookup={}
    def tri(self,group,color,points):
        # Internal coordinates: X, Z, elevation (the latter is Blender +Z).
        inds=[]
        vertices=self.vertices.setdefault(group,[])
        lookup=self.lookup.setdefault(group,{})
        for x,z,h in points:
            co=(round(x,6),round(z,6),round(h+self.grade(x,z),6))
            if co not in lookup:
                lookup[co]=len(vertices)
                vertices.append(co)
            inds.append(lookup[co])
        if len(set(inds))==3:
            self.parts.setdefault(group,[]).append((tuple(inds),color))
    def face(self,group,col,pts):
        for i in range(1,len(pts)-1):
            self.tri(group,col,(pts[0],pts[i],pts[i+1]))
    def skin(self,g,group,col,height,geos):
        for t in geos.triangles(g):
            x=sum(p[0] for p in t)/3
            z=sum(p[1] for p in t)/3
            color=col(x,z) if callable(col) else col
            self.tri(group,color,[(a,b,height(a,b)) for a,b in t])
    def side(self,g,group,col,h0,h1,geos):
        for ring in geos.rings(g):
            for a,b in zip(ring,ring[1:]+ring[:1]):
                if not edge(a,b):   # true shared edges, not coincident end faces
                    self.face(group,col,((*a,h1),(*a,h0),(*b,h0),(*b,h1)))
    def prune(self):
        for group in list(self.parts):
            if not self.parts[group]:
                del self.parts[group]


def reprofile(mesh,profile):
    """Rebuild a shaped native mesh; authored boundaries keep shared vertices."""
    out=Mesh(terrain_height(0))
    for group,faces in mesh.parts.items():
        verts=mesh.vertices[group]
        for indices,col in faces:
            out.face(group,col,[profile(group,*verts[i]) for i in indices])
    return out


def rect(path,t,length,width,side=0,bevel=.012):
    x,z,tx,tz=path.sample(t)
    nx,nz=-tz,tx
    x,z=x+nx*side,z+nz*side
    a,b=length/2,width/2
    pts=((-a+bevel,-b),(a-bevel,-b),(a,-b+bevel),(a,b-bevel),
         (a-bevel,b),(-a+bevel,b),(-a,b-bevel),(-a,-b+bevel))
    return [(x+tx*s+nx*n,z+tz*s+nz*n) for s,n in pts]


def top_color(x,z,seed=0):
    return (int((x+4)*229)*1500450271 ^ int((z+4)*330)*1246379293 ^ seed) % BALLAST_N


def tie_color(x,z):
    return BALLAST_N+(int((x+2)*17)*269 ^ int((z+2)*17)*151) % len(TIES)


def rail_geometry(mask,grade,geos,detail=True,paths=None):
    mesh=Mesh(terrain_height(grade))
    pp=paths or [TrackPath(i) for i in range(6) if mask&(1<<i)]
    # Presentation-only diagonal paths have oblique seam tangents. Extend
    # their sweeps through the ports, then trim precisely on the tile edge.
    tile=geos.union([[(-1,-1),(1,-1),(1,1),(-1,1)]]) if paths else None
    def clip(g):
        if tile is not None:
            trimmed=geos.lib.GEOSIntersectionPrec(g,tile,GEOMETRY_PRECISION)
            geos.free(g)
            assert trimmed
            return trimmed
        return g
    def union(rings):
        return clip(geos.union(rings))
    def sweep(w):
        if paths and len(pp)==1 and hasattr(pp[0],"ribbon_points"):
            # Buffer the centerline instead of ever folding a broad
            # shoulder's inner offsets over themselves at a tight easing.
            return clip(geos.ribbon(pp[0].ribbon_points(),w))
        return union([p.sweep(-w,w) for p in pp])
    def terrain_bed(x,z):
        d=min(p.distance(x,z) for p in pp)
        return .006+max(0,min(1,(BED_EDGE-d)/(BED_EDGE-BED_CROWN)))*.030

    # Union outlines before generating ballast, so switches use a single bed.
    shoulder=sweep(BED_EDGE)
    crown=sweep(BED_CROWN)
    bank=geos.difference(shoulder,crown)
    mesh.skin(bank,"Ballast shoulder",lambda x,z: top_color(x,z),terrain_bed,geos)
    mesh.skin(crown,"Compacted ballast",lambda x,z:2+(top_color(x,z)%2),lambda x,z:.036,geos)
    mesh.side(shoulder,"Ballast shoulder",0,0,.006,geos)
    geos.free(bank,shoulder,crown)

    sleeper_base=[]
    sleeper_top=[]
    chairs=[]
    for p in pp:
        count=max(1,round(p.length/.199))
        ts=p.sleeper_points(count) if paths else ((i+.5)/count for i in range(count))
        for t in ts:
            sleeper_base.append(rect(p,t,.084,SLEEPER*2))
            sleeper_top.append(rect(p,t,.067,(SLEEPER-.015)*2,bevel=.009))
            for sign in (-1,1):
                chairs.append(rect(p,t,.089,.117,sign*GAUGE/2, .010))
    lower,upper=union(sleeper_base),union(sleeper_top)
    bevel=geos.difference(lower,upper)
    mesh.side(lower,"Creosoted sleepers",END,.031,.062,geos)
    mesh.skin(bevel,"Creosoted sleepers",BEVEL,lambda x,z:.062,geos)
    mesh.side(upper,"Creosoted sleepers",BEVEL,.062,.071,geos)
    mesh.skin(upper,"Creosoted sleepers",tie_color,lambda x,z:.071,geos)
    geos.free(lower,upper,bevel)
    chair=union(chairs)
    mesh.side(chair,"Cast iron chairs",CHAIR,.071,.078,geos)
    mesh.skin(chair,"Cast iron chairs",CHAIR,lambda x,z:.078,geos)
    geos.free(chair)

    # Every rail is an I-profile with a real flange, web and railhead.
    # A union per section merges switch throats and diamond intersections,
    # eliminating overlapping coplanar faces and doubled rail ends.
    rail_centers=(-GAUGE/2,GAUGE/2)
    def railway(w):
        return union([p.sweep(o-w,o+w) for p in pp for o in rail_centers])
    foot,web,head=map(railway,(FOOT,.016,HEAD))
    un_web=geos.difference(foot,web)
    mesh.side(foot,"Rail foot",FOOT_MAT,.068,.082,geos)
    mesh.skin(un_web,"Rail foot",FOOT_MAT,lambda x,z:.082,geos)
    mesh.side(web,"Rail web",WEB,.082,.099,geos)
    if mask&3==3:
        # A diamond has a flange channel on the gauge side of each
        # intersecting running rail. The steel web forms the frog below it.
        # Cut the head only, preserving a real recessed channel and a clean
        # wheel-tread ledge rather than placing black stripes over the rail.
        def box2(x,z,ax,az):
            return [(x-ax,z-az),(x+ax,z-az),(x+ax,z+az),(x-ax,z+az)]
        cuts=[]
        for dx in (-1,1):
            for dz in (-1,1):
                x,z=dx*GAUGE/2,dz*GAUGE/2
                cuts.append(box2(x-dx*.047,z,.0105,HEAD+.0005))
                cuts.append(box2(x,z-dz*.047,HEAD+.0005,.0105))
        cut=geos.union(cuts)
        grooved=geos.difference(head,cut)
        geos.free(head,cut)
        head=grooved
    mesh.side(head,"Polished railhead",HEAD_SIDE,.099,TRACK_TOP,geos)
    mesh.skin(head,"Polished railhead",STEEL,lambda x,z:TRACK_TOP,geos)
    geos.free(foot,web,head,un_web)

    # Stock single-turnout approaches get a low steel throw linkage and
    # switch chair. The linkage intentionally stays below the rail heads.
    controls=[]
    if len(pp)==2 and mask&3!=3:
        tracks=[i for i in range(6) if mask&(1<<i)]
        a,b=(set(TRACKS[i]) for i in tracks)
        for side in a&b:
            inferred=TrackPath(0 if side%2==0 else 1)
            t=.13 if SIDE[side]==inferred.a else .87
            controls.append(rect(inferred,t,.036,.56,.0,.008))
    if mask==3:
        # Forged check rails run along the inside of each approach to guide
        # wheel flanges toward the frog without narrowing the running gauge.
        for p in pp:
            for ct in (.285,.715):
                for o in (-.130,.130):
                    controls.append(rect(p,ct,.24,.034,o,.014))
    if controls:
        g=geos.union(controls)
        mesh.side(g,"Forged switch and crossing hardware",CHAIR,.071,.092,geos)
        mesh.skin(g,"Forged switch and crossing hardware",POINTS,lambda x,z:.092,geos)
        geos.free(g)

    # Low-profile angular aggregate is real geometry, between the timber
    # spaces and at the verge. Stable in both palette and random pattern.
    if detail:
        rng=Random(0x36A7D+mask)
        for _ in range(226):
            x,z=(rng.uniform(-.965,.965) for _ in range(2))
            d=min(p.distance(x,z) for p in pp)
            if not (BED_EDGE-.066<d<BED_EDGE-.014 or .06<d<.24 and rng.random()<.42):
                continue
            s=rng.uniform(.013,.033)
            h=terrain_bed(x,z)
            col=rng.randrange(BALLAST_N)
            angle=rng.random()*2*pi
            pts=[(x+cos(k*pi/2+angle)*s,z+sin(k*pi/2+angle)*s,h-.005) for k in range(4)]
            tip=(x+.003,z+.002,h+rng.uniform(.009,.020))
            for k in range(4):
                mesh.tri("Loose aggregate",col,(pts[k],pts[(k+1)%4],tip))
    if tile is not None: geos.free(tile)
    mesh.prune()
    return mesh


def materials():
    mats=[]
    for idx,c in enumerate(COLORS):
        name=("Ballast " if idx<BALLAST_N else "Sleeper " if idx<BEVEL else "Track ")+c
        mat=bpy.data.materials.new(name)
        rgb=[int(c[i:i+2],16)/255 for i in (0,2,4)]
        mat.diffuse_color=(*[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in rgb],1)
        mat.use_nodes=True
        node=mat.node_tree.nodes.get("Principled BSDF")
        node.inputs["Base Color"].default_value=mat.diffuse_color
        node.inputs["Roughness"].default_value=.32 if idx>=HEAD_SIDE else .87
        node.inputs["Metallic"].default_value=.62 if idx>=WEB else .10 if idx>=CHAIR else 0.
        mats.append(mat)
    return mats


def to_blender(mesh,coll,mats):
    for group,faces in mesh.parts.items():
        vs=mesh.vertices[group]
        data=bpy.data.meshes.new(group)
        # Blender positions (X,Y,elevation) are authoring-world X,Z,height.
        data.from_pydata(vs,[],[inds for inds,_ in faces])
        color_list=sorted({c for _,c in faces})
        for i in color_list:
            data.materials.append(mats[i])
        for p,(_,c) in zip(data.polygons,faces):
            p.material_index=color_list.index(c)
        data.update()
        ob=bpy.data.objects.new(group,data)
        coll.objects.link(ob)


def export_obj(filename,mesh,vertical_origin=.5):
    v_off=1
    content=["# LuanTTD original track art; regenerate with tools/build_rail_art.py",
             *(f"vt {(i+.5)/len(COLORS):.6f} .5" for i in range(len(COLORS)))]
    for name,faces in mesh.parts.items():
        content.append("o "+name.replace(" ","_"))
        vs=mesh.vertices[name]
        # Luanti OBJ import reflects X. OBJ positions are local to the +Y
        # overlay node on the north-west tile cell; flat ground top is local -.5.
        # Grade overlays start one node up to clear the terrain slope mesh.
        points=[(-x-.5,h-vertical_origin,z+.5) for x,z,h in vs]
        content.extend(f"v {x:.6f} {h:.6f} {z:.6f}" for x,h,z in points)
        normals=[]
        n_index={}
        fs=[]
        for inds,col in faces:
            a,b,c=[Vector(points[i]) for i in inds]
            v=(b-a).cross(c-a)
            if v.length_squared<1e-17:
                continue
            n=tuple(round(p,5) for p in v.normalized())
            if n not in n_index:
                n_index[n]=len(normals)
                normals.append(n)
            fs.append((inds,col,n_index[n]))
        n_base=sum(l.startswith("vn ") for l in content)+1
        content.extend("vn %.5f %.5f %.5f"%n for n in normals)
        for inds,col,n in fs:
            content.append("f "+" ".join(f"{v_off+i}/{col+1}/{n_base+n}" for i in inds))
        v_off+=len(vs)
    filename.write_text("\n".join(content)+"\n")


def atlas():
    def chunk(tag,payload):
        return struct.pack(">I",len(payload))+tag+payload+struct.pack(">I",zlib.crc32(tag+payload))
    colors=b"".join(bytes.fromhex(c)*8 for c in COLORS)
    png=b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",len(COLORS)*8,8,8,2,0,0,0))
    png+=chunk(b"IDAT",zlib.compress((b"\0"+colors)*8))+chunk(b"IEND",b"")
    (TEXTURES/"bl_rail_atlas.png").write_bytes(png)


def stash(mesh,mats,name):
    c=bpy.data.collections.new(name)
    to_blender(mesh,c,mats)
    c.use_fake_user=True
    return c


def instance(scene,collection,x,y):
    ob=bpy.data.objects.new(collection.name,None)
    ob.instance_type="COLLECTION"
    ob.instance_collection=collection
    ob.location=(x,y,0)
    scene.collection.objects.link(ob)
    return ob


def showcase(collections,render_path):
    scene=bpy.context.scene
    for mask,x,z in ((1,-4,2),(2,0,2),(4,4,2),(32,8,2),
                     (16,-4,-2),(8,0,-2),(3,4,-2),(37,8,-2)):
        instance(scene,collections[mask],x,z)
    # A chicane with connected rails across four separate tile meshes.
    for mask,x,z in ((1,-4,-6),(32,-2,-6),(4,-2,-4),(1,-4,-4)):
        instance(scene,collections[mask],x,z)
    if not render_path:
        return
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.003))
    ob=bpy.context.object
    mat=bpy.data.materials.new("Muted meadow")
    mat.diffuse_color=(.139,.225,.085,1)
    ob.data.materials.append(mat)
    world=bpy.data.worlds.new("Open sky")
    world.color=(.29,.30,.34)
    scene.world=world
    bpy.ops.object.light_add(type="SUN",location=(0,0,9))
    bpy.context.object.rotation_euler=(.49,-.52,-.42)
    bpy.context.object.data.energy=2.6
    bpy.context.object.data.angle=.15
    bpy.ops.object.camera_add(location=(7,-12,22))
    camera=bpy.context.object
    camera.rotation_euler=(Vector((2,-1.5,0))-camera.location).to_track_quat("-Z","Y").to_euler()
    camera.data.type="ORTHO"
    camera.data.ortho_scale=17
    scene.camera=camera
    scene.render.engine="BLENDER_EEVEE_NEXT"
    scene.render.resolution_x=1620
    scene.render.resolution_y=1190
    scene.render.resolution_percentage=100
    scene.render.filepath=render_path
    bpy.ops.render.render(write_still=True)


def main():
    geos=Geos()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    bpy.context.scene.name="LuanTTD / original 3D rail assembly library"
    bpy.context.scene.view_settings.view_transform="Standard"
    mats=materials()
    atlas()
    collections={}
    for mask in range(1,64):
        mesh=rail_geometry(mask,0,geos)
        label=" / ".join(NAMES[i] for i in range(6) if mask&(1<<i))
        collections[mask]=stash(mesh,mats,f"{mask:02d}  {label}")
        export_obj(MODELS/f"bl_rail_track_{mask}.obj",mesh)
    # Stock sloping axes use the same profile pitched over a one-unit rise.
    # Higher masks/foundations are separate future terrain integration.
    for grade,mask,label in ((1,1,"X rise toward SW"),(2,1,"X rise toward NE"),
                             (3,2,"Y rise toward SE"),(4,2,"Y rise toward NW")):
        mesh=rail_geometry(mask,grade,geos)
        stash(mesh,mats,label)
        export_obj(MODELS/f"bl_rail_grade_{grade}.obj",mesh,vertical_origin=1.5)
    showcase(collections,None)
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art/rail_tracks.blend"),compress=True)
    render=os.getenv("RAIL_ART_RENDER")
    if render:
        # Fresh scene layout was already staged, no duplicate tile instances.
        for ob in list(bpy.context.scene.objects):
            bpy.data.objects.remove(ob,do_unlink=True)
        showcase(collections,render)


if __name__=="__main__":
    main()

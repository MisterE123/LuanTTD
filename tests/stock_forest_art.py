#!/usr/bin/env python3
"""Validate reproducible elevation meshes and unchanged original tree art."""
from io import BytesIO
from math import isclose
from pathlib import Path
import struct
import subprocess
import sys
from zipfile import ZIP_DEFLATED, ZipFile


ROOT=Path(__file__).resolve().parents[1]
MOD=ROOT/"mods/luanttd_core"
MODELS=MOD/"models"


def parse(path):
    lines=path.read_text(encoding="utf-8").splitlines()
    points=[]
    unchanged=[]
    for line in lines:
        if line.startswith("v "):
            # Luanti’s OBJ reader flips X but uses Y as the up axis.
            x,y,z=(float(v) for v in line.split()[1:])
            points.append((-x,y,z))
        elif not line.startswith("#"):
            unchanged.append(line)
    return points,unchanged


def verify():
    subprocess.run([sys.executable,str(ROOT/"tools/build_stock_forest_art.py"),"--check"],
                   check=True,cwd=ROOT)
    atlas=(MOD/"textures/bl_scenery_palette.png").read_bytes()
    assert atlas.startswith(b"\x89PNG\r\n\x1a\n")
    assert struct.unpack_from(">II",atlas,16)==(256,8)
    out=BytesIO()
    n=0
    with ZipFile(out,"w",ZIP_DEFLATED,compresslevel=9) as archive:
        for style in range(4):
            blender=ROOT/"art"/f"scenery_tree_{style}.blend"
            assert blender.stat().st_size>20000
            a,topology=parse(MODELS/f"bl_scenery_tree_{style}.obj")
            assert len(a)>225 and sum(line.startswith("f ") for line in topology)>400
            for level in range(5):
                f=MODELS/f"bl_stock_forest_{style}_{level}.obj"
                assert f"scenery_tree_{style}.blend" in f.read_text(encoding="utf-8").splitlines()[0]
                got,rest=parse(f)
                assert rest==topology and len(got)==len(a), (style,level,"normals/UVs/topology")
                assert max(max(abs(x),abs(z)) for x,y,z in got)<.37
                assert .89<max(y for x,y,z in got)-min(y for x,y,z in got)<1.07
                sample=level/2
                for (x,y,z),(u,v,w) in zip(a,got):
                    assert isclose(u,.72*x,abs_tol=1.e-6)
                    assert isclose(w,.72*z,abs_tol=1.e-6)
                    # Confirm the local node mounting contract in absolute
                    # elevation, including below / above the anchor itself.
                    for b in (0,4,15):
                        floor=b+.5+sample
                        world=v+b+2
                        assert isclose(world,floor+.72*(y+.5),abs_tol=1.e-6),(b,level,y,v)
                    n+=1
                contact=[v for (x,y,z),(u,v,w) in zip(a,got) if y==-.5]
                assert contact and all(y==-1.5+sample for y in contact)
                archive.write(f,f.name)
    print(f"STOCK_FOREST_ART_PASS: four original silhouettes × five anchored sample heights, "+
          f"{n:,} native vertices with unchanged palette/normals/topology; {out.tell():,} ZIP bytes.")


if __name__=="__main__":
    verify()

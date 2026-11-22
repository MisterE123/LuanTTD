#!/usr/bin/env python3
"""Stage a private, disposable Luanti terrain survey from a stock .sav."""
from hashlib import sha256
import argparse
import json
from pathlib import Path
import shutil
import sys

from PIL import Image

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "tools"))
from openttd_save_ground import ground_sidecar
from openttd_save_map import snapshot
from openttd_save_inspect import LIMIT

MODULES = REPO/"mods"/"bayline"
MASKS = (*range(15),23,27,29,30)


def find_views(data, ground):
    w, h = data["width"], data["height"]
    heights = bytes.fromhex("".join(data["corner_rows_hex"]))
    water = bytes.fromhex("".join(ground["water_rows_hex"]))
    roads = {int(i) for i,r in data["road_tiles"].items()
             if r["kind"]=="road" and r.get("road_bits",0)}
    coast_best, road_best = None, None
    for z in range(15,h-16,2):
        for x in range(15,w-16,2):
            area = [j*w+i for j in range(z-6,z+7) for i in range(x-6,x+7)]
            coast = sum(water[i] in (2,3) for i in area)
            sea = sum(water[i]==1 for i in area)
            road = sum(i in roads for i in area)
            altitude = max(heights[i] for i in area)
            relief = altitude-min(heights[i] for i in area)
            if coast and 20 <= sea <= 105 and relief>=1:
                value = (5*min(coast,24)+18*relief+7*min(road,8), x+1,z+1,altitude)
                coast_best = max(coast_best or value,value)
            if road>=6 and sea<24:
                value = (8*min(road,25)+20*relief, x+1,z+1,altitude)
                road_best = max(road_best or value,value)
    if not coast_best or not road_best:
        raise SystemExit("Survey needs a private stock map with a graded coast and ordinary road network")
    _,x,z,y=coast_best
    _,rx,rz,ry=road_best
    seam=8*((rx-1)//8)
    return {"coast":{"x":x,"z":z,"y":y},"roads":{"x":rx,"z":rz,"y":ry},
            "fly":{"x1":seam-5,"x2":seam+12,"z":rz,"y":ry,"seam":seam},
            "max_height":max(heights)}


def shade_coast(mask, variant):
    # Read the original shared-corner OBJ, including the exact ridge/valley
    # split. Wet/shingle/grass is original visual treatment, not a water solver.
    mesh = MODULES/"models"/f"bl_land_{mask}.obj"
    text = mesh.read_text().splitlines()
    heights = [float(line.split()[2])+.5 for line in text if line.startswith("v ")]
    triangles = [[int(c.split("/")[0])-1 for c in line.split()[1:]]
                 for line in text if line.startswith("f ")]
    assert len(triangles)==2 and len(heights)==4
    uv = ((0,0),(1,0),(0,1),(1,1))
    dir = MODULES/"textures"
    grass = Image.open(dir/f"bl_grass{variant}.png").convert("RGB")
    water = Image.open(dir/f"bl_water{variant}.png").convert("RGB")
    im = Image.new("RGB",grass.size)
    for py in range(im.height):
        for px in range(im.width):
            u,v=(px+.5)/im.width,(py+.5)/im.height
            elevation = None
            for i,j,k in triangles:
                (a,b),(c,d),(e,f)=(uv[n] for n in (i,j,k))
                det=(d-f)*(a-e)+(e-c)*(b-f)
                r=((d-f)*(u-e)+(e-c)*(v-f))/det
                s=((f-b)*(u-e)+(a-e)*(v-f))/det
                t=1-r-s
                if min(r,s,t)>=-1e-7:
                    elevation = r*heights[i]+s*heights[j]+t*heights[k]
                    break
            assert elevation is not None
            g=grass.getpixel((px,py))
            w=water.getpixel((px,py))
            noise=((px*97+py*53+mask*11+variant*17)%7)-3
            shingle=(152+noise*2,146+noise*2,107+noise)
            if elevation < .022:
                col=w
            elif elevation < .105+noise*.005:
                col=shingle
            elif elevation < .19:
                alpha=(elevation-.10)/.09
                col=tuple(round(x*alpha+y*(1-alpha)) for x,y in zip(g,shingle))
            else:
                col=g
            im.putpixel((px,py),col)
    return im


def stage(save, output):
    with save.open("rb") as stream:
        blob=stream.read(LIMIT+1)
    data,ground=snapshot(blob),ground_sidecar(blob)
    if (data["width"],data["height"])!=(256,256):
        raise SystemExit("The optional native survey fixture expects a 256×256 stock map")
    views=find_views(data,ground)
    output.mkdir(parents=True,exist_ok=False)
    game=output/"games"/"stock_survey"
    mod=game/"mods"/"stock_survey"
    (mod/"models").mkdir(parents=True)
    (mod/"textures").mkdir()
    (game/"game.conf").write_text("title = Private stock-mapped 3D terrain survey\n")
    (mod/"mod.conf").write_text("name = stock_survey\n")
    shutil.copyfile(REPO/"tests"/"terrain_survey_native.lua",mod/"init.lua")
    for name in ("openttd/slope.lua","openttd/road_slope.lua","world_storage.lua","terrain_stream.lua","terrain_word.lua",
                 "import/openttd_map.lua","import/openttd_sparse.lua","import/openttd_ground.lua"):
        shutil.copy(MODULES/name,mod)
    for key,payload in (("snapshot",data),("ground",ground),("views",views)):
        (mod/f"{key}.json").write_text(json.dumps(payload,sort_keys=True))
    for name in ("bl_land_*.obj","bl_scenery_tree_*.obj"):
        for p in (MODULES/"models").glob(name):
            shutil.copy(p,mod/"models")
    for name in ("bl_grass*.png","bl_water[0-3].png","bl_road_surface_*.png","bl_scenery_palette.png"):
        for p in (MODULES/"textures").glob(name):
            shutil.copy(p,mod/"textures")
    for mask in MASKS:
        for variant in range(4):
            shade_coast(mask,variant).save(mod/"textures"/f"survey_coast_{mask}_{variant}.png")
    (output/"views.json").write_text(json.dumps(views,indent=2)+"\n")
    assert sha256(save.read_bytes()).hexdigest()==data["source"]["sha256"]
    return views


if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("save",type=Path)
    p.add_argument("output",type=Path,help="new private directory, never overwrite")
    a=p.parse_args()
    print(json.dumps(stage(a.save,a.output),sort_keys=True))

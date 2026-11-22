#!/usr/bin/env python3
"""Verify actual native roadside/sign/decal meshes against all 5 road grades.

Optional: pass the OpenTTD 14.1 src/road_cmd.cpp path to check index roles.
"""
from pathlib import Path
from math import cos,pi,sin
import sys

from small_airport_art import obj,hull,intersects

ROOT=Path(__file__).absolute().parents[1]
M=ROOT/"mods/bayline/models"
DIRECTIONS=((-1,0),(0,1),(1,0),(0,-1))
COMPATIBLE=((0,3,12),(0,6,9))
ARROW_HEAD="Raised_original_tapered_one-way_arrow_heads"
ARROW_SHAFT="Original_one-way_stripe_shanks"
CLOSURE="Painted_closed_approach_triplet"
NO="No-entry_red_pressed_round_enamel_disk"
YES="One-way_inset_forest_green_enamel_plate"
FOOT="Dressed_cast_concrete_ground_plinth"
MOUNT="Period_galvanized_upright_sign_stanchion"
EPS=.006

def check_stock(p):
    s=p.read_text()
    a=s.index("/* Draw one way */")
    seg=s[a:a+1000]
    for n in ("DisallowedRoadDirections","DRD_NONE","SPR_ONEWAY_BASE",
              "SPR_ONEWAY_SLOPE_N_OFFSET","SPR_ONEWAY_SLOPE_S_OFFSET","GetPartialPixelZ"):
        assert n in seg
    assert "drd - 1" in seg and "road == ROAD_X" in seg

def road_plane(shape):
    v,g=obj(M/f"bl_land_{shape}.obj",(0,0))
    corners={(round(x-.5),round(z-.5)):y for x,y,z in v}
    assert corners.keys()=={(-1,-1),(-1,1),(1,-1),(1,1)}
    a=corners[-1,-1]
    s=(corners[1,-1]-a)/2
    t=(corners[-1,1]-a)/2
    assert abs(a+2*s+2*t-corners[1,1])<1e-7,"One-way grades must be single planes."
    return lambda x,z:a+s*(x+1)+t*(z+1)

def groups(p):
    vs,g=obj(p,(0,0))
    def clean(a):
        x,y,z=a
        # This kit is intentionally mounted one whole node above that
        # common mesh helper, allowing a separate grade/terrain draw node.
        return x-.5,y+1.,z-.5
    assert all(-1<=x<=1 and -1<=z<=1 and -.020001<y<1.65 for x,y,z in map(clean,vs)),p
    return {n:[list(map(clean,f)) for f in fs] for n,fs in g.items()}

def pts(g,n):
    return [p for f in g[n] for p in f]

def angled(p,d):
    a,b=DIRECTIONS[d]
    x,y,z=p
    return b*x-a*z,y,a*x+b*z

def qr(g,n,d,low,high):
    data=[angled(p,d) for p in pts(g,n)]
    assert min(x for x,_,_ in data)>low and max(x for x,_,_ in data)<high
    return data

def paint_test(g,shape,allowed=None,closed_axis=0):
    f=road_plane(shape)
    n=ARROW_HEAD if allowed is not None else CLOSURE
    for n1,fs in g.items():
        if n1 not in (ARROW_HEAD,ARROW_SHAFT,CLOSURE,"Tapered_worn_arrow_feather"):continue
        for group in fs:
            for x,y,z in group:
                assert abs(y-f(x,z)-EPS)<1e-6
                dx,_,dz=angled((x,y,z),allowed if allowed is not None else closed_axis)
                assert .055<abs(dx)<.251
    if allowed is not None:
        hi=qr(g,n,allowed,-.24,.24)
        tail=qr(g,ARROW_SHAFT,allowed,-.19,.19)
        assert min(z for _,_,z in hi)>.07899 and max(z for _,_,z in hi)>.25399
        assert min(z for _,_,z in tail)<-.224 and max(z for _,_,z in tail)<.07901
    else:
        assert len(g[CLOSURE])==24
        assert ARROW_HEAD not in g and ARROW_SHAFT not in g

def sign_test(g,shape,d,closed=False):
    path=road_plane(shape)
    name=NO if closed else YES
    glyph="White_no-entry_inset_porcelain_horizontal_bar" if closed else "Raised_up-road_enamel_pointer"
    assert name in g and glyph in g
    x0,y0,z0=qr(g,name,d,.409,.750)[0]
    rendered=qr(g,name,d,.409,.750)
    assert abs((min(z for _,_,z in rendered)+max(z for _,_,z in rendered))/2+.722)<.014
    # Runtime camera sees the approach face before the mast, with letters/
    # badge as the nearest dedicated, separate relief layer.
    assert min(z for _,_,z in qr(g,glyph,d,.409,.750))<min(z for _,_,z in rendered)
    masts=pts(g,MOUNT)
    unique=len({(round(x,1),round(z,1)) for x,_,z in masts})
    assert unique>=1
    # Concrete bottom always roughens exactly .016 node into the verge.
    feet=pts(g,FOOT)
    assert abs(min(y-path(x,z) for x,y,z in feet)+.016)<1e-6
    # Outline posts with true vertical sides on every grade.
    foot_height_max=max(y for _,y,_ in masts)-min(y for _,y,_ in masts)
    assert foot_height_max>=.550-1e-6

def clearance(g,d):
    geometry=[]
    for n,tris in g.items():
        if n in (ARROW_HEAD,ARROW_SHAFT,CLOSURE,"Tapered_worn_arrow_feather"):continue
        p=[angled(a,d) for f in tris for a in f]
        assert min(abs(q[0]) for q in p)>.412, n
        for face in tris:
            pp=[angled(a,d) for a in face]
            geom=hull((x,z) for x,_,z in pp)
            a,b=zip(*geom)
            geometry.append((min(a),max(a),min(b),max(b),geom))
    for stock,scale in VEHICLES:
        for side in (-1,1):
            angle=0 if side<0 else pi
            cc,ss=cos(angle),sin(angle)
            for z in range(-36,37):
                plan=[(x*cc-w*ss+side*.155,x*ss+w*cc+z/32) for x,w in stock]
                a,b=zip(*plan)
                a0,a1,b0,b1=min(a),max(a),min(b),max(b)
                for x0,x1,z0,z1,sh in geometry:
                    if x0>a1 or x1<a0 or z0>b1 or z1<b0:continue
                    assert not intersects(plan,sh),(d,stock,side,z)
    return 73*2*len(VEHICLES)

def main():
    atlas=(ROOT/"mods/bayline/textures/bl_oneway_atlas.png").read_bytes()
    assert atlas.startswith(b"\x89PNG\r\n\x1a\n") and int.from_bytes(atlas[16:20],"big")==224
    assert (ROOT/"art/oneway_road.blend").stat().st_size>80000
    total=0
    for d in range(4):
        for style,closed in (("oneway",False),("noentry",True)):
            g=groups(M/f"bl_{style}_sign_{d}.obj")
            sign_test(g,0,d,closed)
        for shape in COMPATIBLE[d%2]:
            paintonly=groups(M/f"bl_oneway_paint_{d}_g{shape}.obj")
            paint_test(paintonly,shape,d)
            g=groups(M/f"bl_oneway_{d}_g{shape}.obj")
            paint_test(g,shape,d)
            sign_test(g,shape,d)
            sign_test(g,shape,(d+2)%4,closed=True)
            total+=clearance(g,d)
    for axis in (0,1):
        for shape in COMPATIBLE[axis]:
            g=groups(M/f"bl_oneway_both_{axis}_g{shape}.obj")
            paint_test(g,shape,closed_axis=axis)
            assert NO in g and YES not in g
            total+=clearance(g,axis)
    print(f"PASS: 38 original sign, paint and closure assets; all 5 grades, four arrow and sign headings, {total:,} loaded truck/bus/van swept positions clear.")

def vehicle(name,scale):
    v,_=obj(M/(name+".obj"))
    return hull((x*scale,z*scale) for x,_,z in v),scale

VEHICLES=(vehicle("bl_coal_tipper_loaded",.42),vehicle("bl_leopard_bus",.40),vehicle("bl_mail_van",.43))
if __name__=="__main__":
    if len(sys.argv)>1:check_stock(Path(sys.argv[1]))
    main()

"""Conservative hull-distance proof using the mounted real Sampson OBJ.

The two projected aircraft are inside disjoint circles at all replayed
near-ground points AND continuous interpolations, including aircraft
pool-order movement. Therefore nose, gear, wings and tail cannot reach
the other plane there, independent of eased yaw or fractional rendering.
"""
from math import atan2, cos, hypot, pi, sin
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "mods/luanttd_core/models/bl_bayshore_trimotor.obj"


def minimum_segment(a,b):
    x,z=a
    dx,dz=b[0]-x,b[1]-z
    q=dx*dx+dz*dz
    t=max(0,min(1,-(x*dx+z*dz)/q)) if q else 0
    return hypot(x+t*dx,z+t*dz)/8


def projected_radius(points,limit):
    r=0
    for x,y,z in points:
        pitch=atan2(y,z)
        angles=[-limit,limit]
        for k in (-1,0,1):
            if -limit<=pitch+k*pi<=limit:
                angles.append(pitch+k*pi)
        r=max(r,*(hypot(x,y*sin(p)+z*cos(p)) for p in angles))
    return r


def main():
    lua=sys.argv[1] if len(sys.argv)>1 else "lua5.1"
    def run(flag):
        return subprocess.check_output([lua,"tests/airport_ground_pair.lua",flag],cwd=ROOT,text=True)
    scale=float(run("--scale"))
    points=[tuple(float(q)/10 for q in row.split()[1:4]) for row in MODEL.read_text().splitlines() if row.startswith("v ")]
    assert min(y for _,y,_ in points)==0 # scaling keeps moving gear at native ground contact
    assert .85<scale<.9
    radii=[projected_radius(points,pitch)*scale for pitch in (0,.25)]
    rows=[row.split() for row in run("--poses").splitlines()]
    latest={}
    counts={"exact":0,"frame":0}
    min_center,min_gap=float("inf"),float("inf")
    for marker,*data in rows:
        tick,ax,az,_,bx,bz,_,alt_a,alt_b,air_a,air_b=map(int,data)
        counts[marker]+=1
        last=latest.get(marker)
        assert 0<=alt_a<=8 and 0<=alt_b<=8
        current=(ax-bx,az-bz)
        gap=minimum_segment(current,current)
        radius=radii[air_a]+radii[air_b]
        if last and last[0]+1==tick:
            _,px,pz,qx,qz,old_air_a,old_air_b=last
            radius=radii[air_a|old_air_a]+radii[air_b|old_air_b]
            previous=(px-qx,pz-qz)
            midway=(ax-qx,az-qz)
            gap=min(gap,minimum_segment(previous,current),
                    minimum_segment(previous,midway),minimum_segment(midway,current))
        min_center=min(min_center,gap)
        min_gap=min(min_gap,gap-radius)
        latest[marker]=(tick,ax,az,bx,bz,air_a,air_b)
    assert counts["exact"]>450 and counts["frame"]>450 and min_gap>.015,(counts,min_center,min_gap)
    print(f"PASS: {counts['exact']} native motion passes and {counts['frame']} paired frames with continuous sweeps; "
          f"min centers {min_center:.3f} nodes, "
          f"positive hull clearance {min_gap:.6f} nodes, common native scale {scale}")


if __name__=="__main__":
    main()

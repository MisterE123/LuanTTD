#!/usr/bin/env python3
"""Compare the six authored meshes and quantify real split shoe travel."""
from collections import defaultdict
from hashlib import sha256
from io import BytesIO
from math import atan, cos, sin
from zipfile import ZipFile, ZIP_DEFLATED

from rail_span_art import along_ray, load, MODELS, ROOT, basis
from ship_facility_art import read

PIVOT_Y=.580
PIVOT_Z=.053
RIGID_RISE=.784
STEM="rail_sh_collector"
SHOE="Transverse_working_contact_shoe,_level_at_the_specified_wire"
FULL={
    30:"206e377103e5f1675d16220c6cc62771b12ace631820834fe4eade8cae1feb71",
    40:"958f3f8471056a60397974520e78f0e8acabafa628ae3c1ff6f3dda3b21d7124",
}


def read_faces(name):
    mesh=defaultdict(list)
    for kind,data in read(name,True).items():
        mesh[kind]=[(tuple(p),j) for p,j in data]
    return mesh


def main():
    raised=read_faces(STEM)
    names={f"rail_sh_{i}_body" for i in FULL}
    assert len(raised)==8
    for i,digest in FULL.items():
        stem=f"rail_sh_{i}"
        assert sha256((MODELS/f"bl_{stem}.obj").read_bytes()).hexdigest()==digest
        orig=read_faces(stem);shell=read_faces(stem+"_body")
        assert not set(shell)&set(raised) and set(shell)|set(raised)==set(orig)
        assert all(orig[k]==v for k,v in shell.items())
        for k,batch in raised.items():
            restored=[(tuple((round(x,6),round(z+PIVOT_Z,6),round(y+PIVOT_Y,6))
                              for x,z,y in nodes),j) for nodes,j in batch]
            pristine=[(tuple(tuple(round(p,6) for p in node) for node in nodes),j)
                      for nodes,j in orig[k]]
            assert restored==pristine,k
        assert "Painted_rectangular_scissor_heel_foot_attached_to_roof" in shell
        assert "Genuine_turned_stacked_roof_ceramic_standoffs" in shell
    top=max(y for tri,_ in raised[SHOE] for _,_,y in tri)
    assert abs(top-.204)<1e-7
    # Test actual shared shoe top vertices, both approaches of both
    # axes and both directions on their straight graded ramp centers.
    vertices={p for tri,_ in raised[SHOE] for p in tri if abs(p[2]-top)<1e-7}
    total=0
    for direction in range(4):
        trans=[tuple(basis(direction,p) for p in face) for name,face in
               load("bl_rail_bridge_catenary_head_ramp_"+str(direction))
               if name.startswith("Continuous_shaped_contact_wire")]
        for orientation in (-1,1):
            s=.5*orientation
            pitch=atan(s)
            scale=(RIGID_RISE*cos(pitch)-PIVOT_Y)/top
            assert .594<scale<.597
            # Shoe X width centered with actual wire; top plane orientation
            # has no clearance error anywhere along rail motion.
            z_center=sorted({round(v[1],6) for v in vertices})
            for x in (-.004,.001,.005):
                for z in z_center:
                    for f in (-.30,0.,.29):
                        high=PIVOT_Y+scale*top
                        along=PIVOT_Z+z
                        pz=cos(pitch)*along-sin(pitch)*high
                        py=sin(pitch)*along+cos(pitch)*high
                        world_z=f+orientation*pz
                        world_y=f*.5+.114+py
                        assert abs(min(along_ray(trans,2,x,world_z))+1-world_y)<3e-6
                        total+=1
    z=BytesIO()
    with ZipFile(z,"w",ZIP_DEFLATED,compresslevel=9) as archive:
        for n in sorted(names|{STEM}):
            archive.write(MODELS/f"bl_{n}.obj",f"bl_{n}.obj")
    assert z.tell()<265_000
    assert (ROOT/"art/rail_sh_sprung_collector.blend").is_file()
    print(f"SH_SPLIT_ART_PASS exact reassembly of #23 and #24, {total} full-grade contact rays, scale .594–.597, {z.tell():,} ZIP bytes")


if __name__=="__main__":
    main()

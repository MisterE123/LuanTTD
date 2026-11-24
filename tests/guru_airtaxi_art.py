#!/usr/bin/env python3
"""Check editable models, real nacelle apertures, and separately grounded gear."""
from collections import Counter
from hashlib import sha256
import struct

from darwin_100_art import CORE, ROOT, bore_test, mesh

DATA={
    "guru_galaxy": (1.846, .350, .158, .206, .106, [(0,.570,-.581,.085)]),
    "airtaxi_a21": (1.778, .293, .168, .263, .114, []),
    "airtaxi_a31": (1.786, .321, .155, .208, .122, []),
    "airtaxi_a32": (1.636, .291, .135, .213, .096, []),
    "dinger_100": (1.378, .155, .247, -.368, .060, []),
    "yate_yae46": (1.612, .248, .258, .169, .061,
                  [(-.477,.272,.092,.055*.87),(.477,.272,.092,.055*.87)]),
}
signatures=set()
for name,(width,x,y,z,r,extra) in DATA.items():
    obj=CORE/"models"/f"bl_stock_{name}.obj"
    ground,faces=mesh(obj)
    air,flight=mesh(CORE/"models"/f"bl_stock_{name}_flight.obj")
    assert (ROOT/"art"/f"stock_{name}.blend").stat().st_size>140000
    texture=CORE/"textures"/f"bl_stock_{name}_atlas.png"
    assert struct.unpack(">IIBBBBB",texture.read_bytes()[16:29])==(256,8,8,2,0,0,0)
    signatures.add(sha256(texture.read_bytes()).hexdigest())
    lo,hi=[tuple(op(c) for c in zip(*ground)) for op in (min,max)]
    assert abs(hi[0]-lo[0]-width)<.034 and lo[1]==0
    medium=name in ("yate_yae46","dinger_100","airtaxi_a32")
    assert lo[2]<(-.74 if medium else -.92) and hi[2]>(.70 if medium else .89)
    if name=="yate_yae46":
        fin_band=[y for a,y,c in ground if abs(a)<.041 and .39<c<.69]
        assert all(any(lo<y<lo+.07 for y in fin_band) for lo in (.25,.33,.40,.47,.54)), "detached T-tail"
    assert min(v[1] for v in air)>.025 and max(v[1] for v in air)==hi[1]
    contacts={(a,c) for a,b,c in ground if b==0}
    tires={(a,c) for ps,tag in faces if tag in (25,26) for a,b,c in ps if b==0}
    assert contacts==tires and len(tires)==(12 if name=="dinger_100" else 20), (name,len(tires))
    assert not any(tag in (25,26) for _,tag in flight)
    # A shoulder-wing regional jet retracts its gear much higher.
    above_gear=.335 if name=="yate_yae46" else .217
    exterior=lambda rows:Counter((tuple(sorted(poly)),tag) for poly,tag in rows if min(v[1] for v in poly)>above_gear)
    shell=exterior(faces)
    assert sum((exterior(flight)&shell).values())>.995*sum(shell.values())
    bore_test(faces,[(-x,y,z,r*.84),(x,y,z,r*.84)]+extra)
    print(f"PASS {name}: {2+len(extra)} open turbine recesses, separate exact tire contact and clear flight mesh")
assert len(signatures)==len(DATA)

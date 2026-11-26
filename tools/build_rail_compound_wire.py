#!/usr/bin/env python3
"""Original wire and compatible portal for flat RC1 compound junctions.

The source chooses actual live contact pieces separately. The native
steel portal is a shared visual fallback, not OpenTTD's PCP/PPP selection.
"""
from copy import deepcopy
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_rail_catenary_art as W

R=W.R
# These cover the outside corners of the true two-node railway tile.
LEGS=((-0.86,-0.86),(.86,.86))
TOP=1.29
P=(0,0,TOP-.015)
PLAIN=(1,2,4,8,16,32)

def ribbon(mesh,path,name,low,w,h,c,edge=None,sections=None):
    # Flat contact wire needs no artificial subdivisions on a straight.
    # Ten curve chords miss the continuous rail centerline by <=.0031
    # node at the one-node radius, less than the contact half-width.
    if sections is None:
        n=6 if path.is_straight else 10
        sections=([j/n for j in range(n+1)],)
    def ring(t):
        a,b=path.offset(t,-w/2),path.offset(t,w/2)
        y=low(t)
        return [(*a,y),(*b,y),(*b,y+h),(*a,y+h)]
    for section in sections:
        rows=[ring(t) for t in section]
        for a,b in zip(rows,rows[1:]):
            for i in range(4):
                j=(i+1)%4
                W.face(mesh,name,edge if edge and i in (1,3) else c,(a[i],a[j],b[j],b[i]))

def wire(mask,eased=None):
    m=R.Mesh(R.terrain_height(0))
    for bit in range(6):
        if not mask & (1<<bit): continue
        path=(eased or {}).get(bit) or R.TrackPath(bit)
        crossing=bit==1 and mask&3==3
        sections=(([0,.497],[.503,1]) if crossing else ([0,1],)) if path.is_straight else None
        ribbon(m,path,f"Track {bit} contact wire",W.contact,.012,.009,
               "Weathered copper contact underside","Glancing contact edge",sections)
        low=lambda t: W.messenger(t)+(.016*max(0,1-abs(t-.5)*6) if crossing else 0)
        ribbon(m,path,f"Track {bit} messenger",low,.009,.008,"Messenger cable charcoal")
        for t in (.24,.50,.76):
            x,z,*_=path.sample(t)
            W.bar(m,f"Track {bit} independent droppers","Dropper link tempered steel",
                  (x,z,W.WIRE+.006),(x,z,low(t)+.004),.0049)
        x,z,*_=path.sample(.5)
        # The wire-only scene includes the hangers, not extra feet.
        # Endpoint control remains on the canonical half-tile geometry.
        W.bar(m,f"Track {bit} overhead registration","Braced period blue-grey steel mast",
              P,(x,z,1.066),.013,.017)
        W.D(m,f"Track {bit} porcelain registration","Porcelain warm bleached insulator",
            (x,z,0),.014,"h",1.025,1.073,8)
        W.bar(m,f"Track {bit} clip to messenger","Raised copper end clamps",
              (x,z,1.025),(x,z,low(.5)),.006)
    return m

def portal():
    m=R.Mesh(R.terrain_height(0))
    for x,z in LEGS:
        for dx in (-.081,.081):
            for dz in (-.081,.081):
                assert min(R.TrackPath(i).distance(x+dx,z+dz) for i in range(6))>.56
        W.B(m,"Cast granite portal foundation","Foundation dark mortar edge",x,z,.160,.160,0,.071,.016,
            "Foundation rough granite")
        W.B(m,"Original rolled steel portal upright","Braced period blue-grey steel mast",x,z,.064,.060,.066,TOP,.009)
        for u in (-.025,.025):
            W.B(m,"Rigid weathered steel flange","Satin warm galvanized beam edge",x+u,z,.011,.072,.083,TOP-.01,.002)
        W.bar(m,"Riveted outward diagonal stiffener","Mast steel shadow tension flange",
              (x,z,.91),(.56*x,.56*z,TOP-.037),.025,.018)
        W.bar(m,"Separate lower gantry tension strap","Mast steel shadow tension flange",
              (x,z,1.175),(.73*x,.73*z,TOP+.023),.014)
    a,b=LEGS
    W.bar(m,"Independent compound roof girder","Braced period blue-grey steel mast",
          (*a,TOP),(*b,TOP),.052,.044,"Satin warm galvanized beam edge")
    W.bar(m,"Lower rolled lip along main girder","Mast steel shadow tension flange",
          (*a,TOP-.037),(*b,TOP-.037),.033,.012)
    W.B(m,"Shared bolted registration plate","Satin warm galvanized beam edge",0,0,.14,.11,TOP-.066,TOP-.013,.013)
    return m

def join(*meshes):
    m=R.Mesh(R.terrain_height(0))
    for q in meshes:
        for name,faces in q.parts.items():
            for ids,color in faces:
                m.face(name,color,[q.vertices[name][i] for i in ids])
    return m

def export_contact(path,mesh,generator):
    R.export_obj(path,mesh,vertical_origin=1.5,generator=generator)
    raw=path.read_text().splitlines()
    path.write_text("\n".join([raw[0],"g CompoundContact",*(("# "+l) if l.startswith("o ") else l for l in raw[1:])])+"\n")

def main():
    for mask in range(1,64):
        name=f"bl_rail_compound_contact_{mask}"
        export_contact(R.MODELS/(name+".obj"),wire(mask),"build_rail_compound_wire.py")
    p=portal()
    export=deepcopy(p)
    for key,row in export.vertices.items():
        export.vertices[key]=[(x-1,z-1,y) for x,z,y in row]
    R.export_obj(R.MODELS/"bl_rail_compound_portal.obj",export,vertical_origin=1.5,generator="build_rail_compound_wire.py")
    W.author([(f"Compound source pieces {m}",join(p,wire(m))) for m in (7,25,42,63)],"rail_compound_wire.blend")

if __name__=="__main__":
    main()

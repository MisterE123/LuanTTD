#!/usr/bin/env python3
"""Check exported timber brackets, bridge shoe datum and exact profiles."""
from io import BytesIO
from math import sqrt
from zipfile import ZIP_DEFLATED, ZipFile
from rail_span_art import EPS, MODELS, ROOT, along_ray, basis, load, physical, profile, vehicle

ART="bl_rail_bridge_catenary"
DECK="bl_rail_bridge_wood"
WIRE="Continuous_shaped_contact_wire_underside_aligned_to_SH30_shoe"
MESSENGER="Independently_suspended_messenger_catenary_cable"
BEARER="Transverse_switch-timber_bearers"
SADDLE="Channel_shoe_sockets_over_end_of_actual_wooden_bridge_bearer"
CHEEKS="Two_bolted_side_cheek_straps_wrapping_actual_bridge_bearer"
BOLT="Zinc_plated_clamp_nuts_seated_on_bridge_bracket"
PEDESTAL="Bolted_overhang_pedestal_isolated_from_guardrail"
MAST="Upright_bracketed_bridge_mast_central_H_web"
FLANGE="Pair_of_real_hot_rolled_outer_mast_flange_plates"
FENCE="Bridge_inspection_fence"
CROWN="Polished_railhead"


def local(mesh,d,group,shift=0):
    return [tuple((u,v,y+shift) for u,v,y in (basis(d,p) for p in tri))
            for name,tri in mesh if name==group]


def bounds(tris,d):
    a=[p[d] for tri in tris for p in tri]
    return min(a),max(a)


def volume_samples(tris,range1,range2,axis):
    for a in range1:
        for b in range2:
            y=list(along_ray(tris,axis,a,b))
            if y and max(y)>min(y)+EPS:
                yield a,b,min(y),max(y)


def near(s,v=0): return abs(s-v)<EPS


def overlap(a,b,c,d):
    return min(b,d)-max(a,c)


def test():
    count=samples=0
    exported=[]
    for d in range(4):
        axis=d%2
        direction=1 if axis else 2
        ordinary=load(f"bl_rail_catenary_{axis+1}_0")
        span=load(f"{ART}_span_{axis}_1")
        bare_span=load(f"{ART}_span_{axis}_0")
        for name in (f"{ART}_span_{axis}_1",f"{ART}_span_{axis}_0"):
            if name not in exported:exported.append(name)
        assert not physical(bare_span,SADDLE,MAST)
        for w in (WIRE,MESSENGER,"Five_actual_thin_separate_vertical_droppers"):
            assert physical(span,w)==physical(bare_span,w)
        for name in ("flat","ramp"):
            prefix=f"{ART}_head_{name}_{d}"
            head=load(prefix)
            opposite=load(f"{ART}_head_{name}_{(d+2)%4}")
            exported.append(prefix)
            timber=load(f"{DECK}_head_{name}_{d}")
            # Match all edge sections at world heights on the genuine
            # Harbor Valley level difference and alternate absolute decks;
            # also join a zero-middle head pair.
            for part in (WIRE,MESSENGER):
                for deck in (1,2,9):
                    low=deck-1 if name=="ramp" else deck
                    a=profile(head,d,1,part,deck+1)
                    b=profile(span,d,-1,part,deck+1)
                    c=profile(span,d,1,part,deck+1)
                    other=profile(opposite,d,-1,part,deck+1)
                    assert a and a==b==c==other,(a,b,c,other)
                    assert (profile(head,d,-1,part,deck+1)
                            ==profile(ordinary,d,1,part,low+2))
                    count+=5
            for setup,wood,heading,is_grading in (
                (head,timber,d,name=="ramp"),
                (span,load(f"{DECK}_span_{axis}"),direction,False),
            ):
                side=1 if heading in (1,2) else -1
                inner=lambda x:side*x
                shoe=local(setup,heading,SADDLE,1)
                cheek=local(setup,heading,CHEEKS,1)
                bearer=local(wood,heading,BEARER)
                ybase=.135 if is_grading else .5
                assert near(bounds(shoe,2)[0],ybase-.137)
                assert near(bounds(shoe,2)[1],ybase-.068)
                # Actual exported shoe overlaps the load-bearing crossbeam
                # at several underlying rays; side cheeks straddle the edges.
                points=list(volume_samples(shoe,sorted(map(inner,(.535,.541,.544))),(.245,.27,.293),2))
                assert len(points)==9
                for x,z,lo,hi in points:
                    tim=list(along_ray(bearer,2,x,z))
                    assert overlap(lo,hi,min(tim),max(tim))>.052
                    samples+=1
                brace=local(setup,heading,PEDESTAL,1)
                cap=local(setup,heading,MAST,1)
                guard=local(wood,heading,FENCE)
                plates=local(setup,heading,FLANGE,1)
                innermost=min(side*p[0] for surf in (cap,plates,brace) for tri in surf for p in tri)
                assert .572<innermost<.580
                assert innermost>max(side*p[0] for tri in guard for p in tri)+.05
                assert abs(bounds(cheek,1)[0]-.229)<EPS and abs(bounds(cheek,1)[1]-.311)<EPS
                # Clip/standing members stay above the bearer bottom and
                # far above the pier and river. Never occupy the rail bed.
                assert min(p[2] for _,tri in setup for p in tri)+1>ybase-.15
                rail=local(wood,heading,CROWN)
                assert max(abs(p[0]) for tri in rail for p in tri)<.25
                assert min(side*p[0] for surf in (shoe,cheek,cap) for tri in surf for p in tri)>.48
                assert physical(setup,BOLT)
                for along in (-.89,-.5,0,.23,.27,.29,.81,.98):
                    railz=(along/2 if is_grading else .5)+.114
                    line=local(setup,heading,WIRE,1)
                    assert near(min(along_ray(line,2,0,along))-railz,.784)
        # Flat bridge section retains exact electric shoes and sight clearance.
        shoe=local(span,d,WIRE,1)
        for kind in ("bl_rail_sh_30","bl_rail_sh_40"):
            vr=list(vehicle(kind))
            for new in (.031,-.031):
                for z in (-.7,0,.68):
                    assert near(min(along_ray(shoe,2,0,z+new)),.614+max(p[2] for p in vr))
        # A fixed rigid collector TEST FAILING ON RAMPS is documented, not
        # masked by moving the contact cable; a slope-following shoe is needed.
        assert .092<.784*(sqrt(1+.5**2)-1)<.094
    b=BytesIO()
    with ZipFile(b,"w",ZIP_DEFLATED,compresslevel=9) as z:
        for name in exported:
            z.write((MODELS/(name+".obj")),name+".obj")
    assert (ROOT/"art/rail_bridge_catenary.blend").stat().st_size>40_000
    assert len(exported)==12 and b.tell()<110_000
    print(f"WOOD_BRIDGE_CATENARY_PASS {len(exported)} models, {count:,} exact edge profiles, {samples} genuine bracket bearing rays; "
          f"SH30/40 qualified for flats only; {b.tell():,} ZIP bytes.")


if __name__=="__main__":
    test()

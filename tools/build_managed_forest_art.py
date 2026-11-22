#!/usr/bin/env python3
"""Original native conifer plantation, stock OpenTTD 14.1 layouts 0 and 1."""
from math import cos, pi, sin, tau
from pathlib import Path
from random import Random
import os
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_sawmill_art as s

R=s.R
B,T=s.B,s.T
Vector=s.Vector
bpy=s.bpy
PREFIX="bl_forest"
PAL=s.PAL | {
    "pine_bark":"765a44","pine_deep":"59493b","pine_high":"916548",
    "pine_weather":"8b755b","needle_deep":"2d4f49","needle_shade":"325950",
    "needle_blue":"40665c","needle_light":"557b65","needle_fresh":"64866a",
    "pine_tip":"52755d","evergreen_shadow":"375447","forest_floor":"675c46",
    "forest_soil":"786349","wood_moss":"64704c","new_ground":"8c6f50","fern":"628357",
    "fern_light":"76905e","dead_needle":"957d53","lichen_speck":"97936b",
}
s.PAL=PAL
s.P=s.w.P={k:i for i,k in enumerate(PAL)}
R.COLORS[:]=PAL.values()
LAYOUTS={
  0:tuple((x,z) for x in range(4) for z in range(4))+((1,4),(2,4)),
  1:tuple((x,z) for z in range(4) for x in range(5))+((1,4),(2,4),(3,4)),
}


def stump(m,x,z,d,a,tall,t=0,prefix="Cut planted conifer"):
    rng=Random(t*11+179)
    pn=12
    rings=[]
    for j,(rad,h) in enumerate(((d*1.31,.004),(d*1.07,.115*tall),(d*.94,tall))):
        ring=[]
        for i in range(pn):
            phase=a+tau*i/pn
            rr=rad*(1+rng.uniform(-.11,.095))
            ring.append((x+rr*cos(phase),z+rr*sin(phase),h+(rng.uniform(-.012,.008) if j==2 else 0)))
        rings.append(ring)
    for a,b in zip(rings,rings[1:]):
        for j in range(pn):
            i=(j+1)%pn
            s.f(m,prefix+" broken bark profile",rng.choice(("pine_bark","pine_deep","pine_high","pine_bark")),
                (a[j],a[i],b[i],b[j]))
    origin=(x,z,tall-.001)
    hi=rings[-1]
    for zf,mat in ((.85,"end_wood"),(.70,"growth_ring"),(.61,"fresh_split"),(.47,"growth_light"),(.35,"end_wood")):
        v=[tuple(b+(a-b)*zf for a,b in zip(q,origin)) for q in rings[-1]]
        for j in range(pn):
            i=(j+1)%pn
            s.f(m,prefix+" concentric fresh crosscut",mat,(hi[j],hi[i],v[i],v[j]))
        hi=v
    s.f(m,prefix+" pale exposed heartwood","heartwood",hi)


def conifer(m,x,z,h,r,seed):
    rng=Random(seed)
    ang=rng.uniform(0,tau)
    n=11
    branches=("needle_deep","needle_shade","needle_blue","needle_shade","needle_light")
    trunk_bottom=(x,z,.014)
    trunk_center=(x-rng.uniform(-.02,.02),z-rng.uniform(-.023,.023),h*.74)
    trunk_top=(x+rng.uniform(-.049,.052),z+rng.uniform(-.048,.049),h*.99)
    s.tube(m,"Genuinely tapered evergreen trunks","pine_bark",trunk_bottom,trunk_center,r*.154,r*.061,11)
    s.tube(m,"Upright tapered central leader","pine_high",trunk_center,trunk_top,r*.061,r*.026,9)
    for j in range(4):
        q=ang+j*tau/4
        xx,zz=x+cos(q)*r*.27,z+sin(q)*r*.27
        s.tube(m,"Conifer root ridges anchored in earth","pine_deep",(x,z,.065),(xx,zz,.007),r*.072,r*.015,7)
    # Five overlapping bough whorls. Each has independent asymmetry and
    # bent skirt silhouettes with increasing crown taper and decreasing
    # conifer radius; they are full geometries, not double-face leaf boards.
    rows=((.265,1.01),(.413,.938),(.555,.754),(.686,.589),(.784,.417))
    for j,(at,fac) in enumerate(rows):
        az=ang+j*.853
        rr=r*fac
        lean_x=trunk_top[0]-x
        lean_z=trunk_top[1]-z
        tx=x+lean_x*at;tz=z+lean_z*at
        collar=[]
        middle=[]
        tips=[]
        roots=[]
        for i in range(n):
            q=az+tau*i/n
            bump=rng.uniform(.88,1.112)*(1 if i%2 else .947)
            u,v=cos(q),sin(q)
            lead=rr*bump
            sag=h*(.023+.052*rng.random())
            edge=lead*(.92 if i%3 else 1.045)
            collar.append((tx+u*lead*.239,tz+v*lead*.259,h*(at+.204)+(sag*.35)))
            middle.append((tx+u*lead*.689,tz+v*lead*.691,h*(at+.137)-(sag*.40)))
            tips.append((tx+u*edge,tz+v*edge,h*(at+.042)-sag))
            roots.append((tx+u*lead*.303,tz+v*lead*.301,h*(at+.052)-sag*.42))
        for i in range(n):
            k=(i+1)%n
            for a,b,tones in (
                (collar,middle,("needle_light","needle_shade","needle_fresh","needle_blue")),
                (middle,tips,branches),(tips,roots,("evergreen_shadow","needle_deep","needle_shade"))):
                tint=rng.choice(tones)
                s.f(m,"Bent side sprays of evergreen branches",tint,(a[i],b[i],b[k],a[k]))
        # Additional individual lateral sprays break up the stacked outline,
        # so a walking view shows a ragged conifer silhouette at each skirt.
        for k in ((1,4,6,9) if j<3 else (3,8)):
            q=az+tau*k/n
            dx,dz=cos(q),sin(q)
            u,v,y=tips[k]
            l=r*.087*(1.0-j*.10)
            a=(u-dx*l*.36+dz*l*.57,v-dz*l*.36-dx*l*.57,y+h*.026)
            b=(u-dx*l*.36-dz*l*.57,v-dz*l*.36+dx*l*.57,y+h*.020)
            c=(u+dx*l*.56,v+dz*l*.56,y-.020-h*.012)
            d=(u-dx*l*.47,v-dz*l*.47,y-h*.032)
            s.f(m,"Individual tapered pine needle tip clusters",rng.choice(branches),(a,b,c))
            s.f(m,"Individual tapered pine needle tip clusters","evergreen_shadow",(c,b,d))
            s.f(m,"Individual tapered pine needle tip clusters","needle_shade",(d,a,c))
        # Exposed deadwood between the lower boughs.
        if j<2:
            for i in (2,6):
                s.tube(m,"Tangible bare undersides of pine branches","pine_deep",(tx,tz,h*(at+.071)),
                        (tips[i][0]*.74+tx*.26,tips[i][1]*.74+tz*.26,tips[i][2]+.039),
                        r*.017,r*.006,7)
    last=(trunk_top[0],trunk_top[1],h)
    for i in range(n):
        j=(i+1)%n
        a,b=tau*i/n+ang,tau*j/n+ang
        def pt(u):
            return (trunk_top[0]+r*.192*cos(u),trunk_top[1]+r*.193*sin(u),h*.858+r*.028*sin(7*u))
        s.f(m,"Pointed tightly spaced upper pine shoots","pine_tip" if i%3 else "needle_fresh",(pt(a),pt(b),last))


def moss_and_litter(m,seed,lighter=False):
    rng=Random(seed)
    for k in range(20):
        x,z=rng.uniform(-.885,.885),rng.uniform(-.885,.885)
        shade=rng.choice(("wood_moss","forest_floor","forest_soil","dead_needle","wood_moss","pine_weather"))
        s.disk(m,"Sparse irregular plantation litter on grass",shade,x,z,.0031,
               rng.uniform(.015,.096),rng.choice((5,6,7)))
    for k in range(5 if lighter else 8):
        x,z=rng.uniform(-.869,.870),rng.uniform(-.87,.869)
        if lighter and x>-.6 and z>.1:continue
        height=rng.uniform(.061,.104)
        for j in range(4):
            ang=rng.uniform(0,tau)
            d=cos(ang);e=sin(ang)
            dx,dz=d*rng.uniform(.062,.089),e*rng.uniform(.065,.086)
            a=(x,z,.005);edge=(x+dx*.48-dz*.20,z+dz*.48+dx*.20,height*.68)
            b=(x+dx,z+dz,height)
            edge2=(edge[0]+dz*.4,edge[1]-dx*.4,height*.55)
            s.f(m,"Small understory fern leaflets","fern" if k%2 else "fern_light",(a,edge,b,edge2))


def landing(m,key):
    # One lightly thinned stock harvest landing at the tip of each block.
    # Surroundings are still maturing plantation; do not fill a stock hole.
    s.patch(m,"Exposed logging landing pad","forest_soil",-.916,.908,-.648,1,.002)
    for x in (-.62,-.26):
        s.patch(m,"Twin wheel ruts along log approach","wheel_rut",x-.05,x+.05,.04,1,.007)
    stump(m,-.73,-.45,.053,1.4,.153,key,"Recently dressed landing stump")
    stump(m,.716,-.436,.071,2.0,.152,key+3,"Recently dressed landing stump")
    s.log_stack(m,.407,.222,1.073,1,key+37,"gold",rows=(4,3,2),radius=.081)
    for z in (-.498,.862):
        B(m,"Short log guide and skid post","oak_weather",.816,z,.062,.068,.002,.322,.006)
        B(m,"Fresh tops of skid post","cut_pine",.816,z,.060,.065,.318,.327,.005)
    s.spar(m,"One skid support used at forest edge","oak_shade",(-.168,-.427,.059),(-.697,.396,.105),.079,.043)
    for x,z,d,r in ((-.81,-.81,.070,.082),(.86,-.834,.057,.095)):
        s.disk(m,"Debarking chips at the landing","fresh_split",x,z,.005,r,8)


def forest_tile(i,x,z):
    m=s.art_mesh()
    seed=i*10823+x*79+z*149
    rng=Random(seed)
    active=z==1 and x==3+i
    moss_and_litter(m,seed,active)
    if active:
        court=s.art_mesh()
        landing(court,seed)
        conifer(court,-.33,-.619,1.712,.275,seed+95)
        conifer(court,.37,-.697,1.508,.210,seed+269)
        # Canonical positive-Z ruts exit east along positive X to the
        # real proven Forest stop. Rotate the hand-modelled trees too.
        s.shift(m,court,0,0,0,3)
    else:
        coords=((-0.47,-0.47),(.47,-.47),(-.47,.47),(.47,.47))
        for n,(a,b) in enumerate(coords):
            u=a+rng.uniform(-.069,.072);v=b+rng.uniform(-.070,.071)
            variation=.10*sin(x*1.77+z*.51+n)
            h=1.775+variation+rng.uniform(-.305,.396)
            r=min(.391,.186+.081*h+rng.uniform(-.041,.039),(1-max(abs(u),abs(v))-.027)/1.235)
            if (n+x*3+z*7)%19==8:
                h*=.704;r*=.825
            conifer(m,u,v,h,r,seed+n*331+15)
        if z==4:
            s.spar(m,"End of aging planted fence line","oak_weather",(-.88,.944,.077),(.857,.947,.061),.029,.028)
    return m


def harvested():
    m=s.art_mesh()
    rng=Random(3812)
    moss_and_litter(m,3812,True)
    s.patch(m,"Exposed harvested stock tile ground","new_ground",-.916,.941,-.821,.878,.004)
    for i,(x,z) in enumerate(((-.518,-.451),(.452,-.373),(-.461,.435),(.500,.487))):
        stump(m,x,z,rng.uniform(.055,.101),rng.uniform(0,tau),rng.uniform(.121,.218),i*49+71)
    s.log_stack(m,.038,-.053,1.272,0,3812,"gold",rows=(4,3),radius=.091)
    for i in range(25):
        x,z=rng.uniform(-.92,.92),rng.uniform(-.91,.91)
        s.disk(m,"Real chips of the harvest cycle","chip",x,z,.006,rng.uniform(.008,.035),5)
    return m


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    mats=R.materials()
    for i,mat in enumerate(mats):mat.name=list(PAL)[i]
    scene=bpy.context.scene
    scene.name="LuanTTD | Eastern plantation | Forest stock 0 and 1"
    for i,coords in LAYOUTS.items():
        for x,z in coords:
            part=forest_tile(i,x,z)
            coll=R.stash(part,mats,f"Forest {i}: stock ({x},{z}), gfx16")
            if i==0:R.instance(scene,coll,2*x+.5,2*z+.5)
            R.export_obj(R.MODELS/(f"{PREFIX}_{i}_{x}_{z}.obj"),part)
    part=harvested()
    coll=R.stash(part,mats,"Stock temporary harvest gfx17")
    R.instance(scene,coll,8.68,7.71)
    R.export_obj(R.MODELS/(PREFIX+"_harvested.obj"),part)
    s.atlas(PREFIX,PAL)
    s.review_scene(scene,(4.07,4.1,.85),13.5)
    bpy.ops.wm.save_as_mainfile(filepath=str(R.ROOT/"art"/"managed_forest.blend"),compress=True)
    if path:=os.getenv("FOREST_ART_RENDER"):
        scene.render.filepath=path;bpy.ops.render.render(write_still=True)

if __name__=="__main__":
    main()

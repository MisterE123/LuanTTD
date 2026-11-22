#!/usr/bin/env python3
"""Build an original OpenTTD 14.1 12-cell temperate factory mesh kit."""
from math import cos, pi, sin
from pathlib import Path
from random import Random
import os
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_stock_farm_art as S

A,R=S.A,S.R
B,T,F,Q=S.B,S.T,S.F,S.Q
PAL=dict(S.PAL, **{
    "buff":"d3bd9a","ochrebrick":"a65e45","sienna":"a8674c","firebrick":"a87156",
    "flue_edge":"895943","flue_shadow":"653e34","brick_seam":"b28e73",
    "steelwork":"49636b","factory_blue":"426577","factory_blue_lit":"517988",
    "factory_blue_dark":"38535f","factory_blue_seam":"567583","paint_offwhite":"d8d4b1",
    "goods_crate":"a2794a","goods_crate_pale":"c39b61","canopy_dark":"4e5757",
    "factory_glass":"4c686b","factory_glass_lit":"779694","window_iron":"4c554f",
    "warm_asphalt":"7b8178","service_concrete":"9b9d8a","concrete_join":"757b73",
    "hi_vis":"cd9e4e","boxcar_red":"87564d","water_green":"476b68",
})
A.PAL=PAL;A.P=A.H.P={k:i for i,k in enumerate(PAL)}
R.COLORS[:]=PAL.values()
LAYOUT={(0,0):39,(0,1):40,(1,0):41,(1,1):42,
        (0,2):39,(0,3):40,(1,2):41,(1,3):42,
        (2,1):39,(2,2):40,(3,1):41,(3,2):42}
NAME="industry_factory"


def base(m):
    # Key the three neighboring four-cell blocks separately without adding
    # grass or padding to absent cells in the 4x4 bounding rectangle.
    for x,z in ((0,0),(0,2),(2,1)):
        x0,z0=2*x-.5,2*z-.5
        Q(m,"Joined stock asphalt plant blocks","warm_asphalt",x0,x0+4,z0,z0+4,.005)
        Q(m,"Concrete wagon loading court","service_concrete",x0+2.02,x0+3.97,z0+2.05,z0+3.94,.011)
        for i in range(3):
            a=x0+2.075+i*.598
            Q(m,"Poured loading apron expansion joints","concrete_join",a,a+.008,z0+2.11,z0+3.88,.013)
        for j in range(3):
            a=z0+2.10+j*.60
            Q(m,"Poured loading apron expansion joints","concrete_join",x0+2.07,x0+3.93,a,a+.008,.014)
        for i in range(4):
            a=z0+2.21+i*.45
            Q(m,"Visible dashed receive and dispatch edge stripe","hi_vis",x0+3.39,x0+3.427,a,a+.20,.017)
        for zz in (z0+2.325,z0+3.175):
            Q(m,"Painted trailer berth guide","paint_offwhite",x0+2.12,x0+3.37,zz,zz+.018,.018)
        for i in range(4):
            a=x0+2.17+i*.11
            Q(m,"Staff crossing white bars","paint_offwhite",a,a+.056,z0+3.52,z0+3.77,.019)
        rng=Random(1224+x*83+z*91)
        for i in range(41):
            xx=rng.uniform(x0+.07,x0+3.91);zz=rng.uniform(z0+.05,z0+3.91)
            if xx>x0+2.0 and zz>z0+2.0:continue
            Q(m,"Spalled asphalt aggregate flecks",rng.choice(("gravel","concrete_join","warm_asphalt")),
              xx-.01,xx+.034,zz-.015,zz+.013,.009)
        # Flush weighbridge at the east road approach. No truss, posts, or
        # fake track segment on the final .77 nodes of the stock platform.
        Q(m,"Flush outbound truck weighbridge","factory_blue_dark",x0+3.43,x0+3.94,z0+2.55,z0+3.00,.015)
        for i in range(7):
            a=x0+3.44+i*.071
            Q(m,"Weighbridge raised stippled steel bars","steel",a,a+.021,z0+2.57,z0+2.978,.018)


def slice_wall(m,n,side,x,z,w,l,low,high,body="ochrebrick"):
    if side in ("north","south"):
        s=1 if side=="south" else -1
        B(m,n+" recessed fired brick load-bearing wall",body,x,z+s*l/2,w,.062,low,high)
        for j in range(1,round((high-low)/.088)):
            yy=low+j*.088
            B(m,n+" thin bed joint","brick_seam",x,z+s*(l/2+.033),w-.016,.002,yy,yy+.005)
    else:
        s=1 if side=="east" else -1
        B(m,n+" recessed fired brick load-bearing wall",body,x+s*w/2,z,.059,l,low,high)
        for j in range(1,round((high-low)/.093)):
            yy=low+j*.093
            B(m,n+" thin side bed joint","brick_seam",x+s*(w/2+.031),z,.003,l-.015,yy,yy+.005)


def window(m,n,x,z,h,w=.209,l=.298):
    B(m,n+" limestone slip sill","buff",x,z,w+.06,.054,h-.047,h-.019,.004)
    B(m,n+" iron sash margin","window_iron",x,z+.008,w+.032,.047,h-.018,h+l+.032,.009)
    B(m,n+" glazed window pane","factory_glass",x,z+.035,w,.020,h,h+l,.007)
    B(m,n+" highlighted shop glazing","factory_glass_lit",x-w*.12,z+.047,w*.72,.003,h+.122,h+l-.028,.004)
    for i in (0,1,2):
        a=h+.061+i*(l-.075)/3
        B(m,n+" horizontal glazing bars","window_iron",x,z+.052,w-.009,.006,a,a+.012)
    for s in (-1,1):
        B(m,n+" glazed vertical mullion","window_iron",x+s*w*.16,z+.052,.011,.009,h,h+l,.002)


def blue_roof(m,n,x,z,w,l,h,r):
    A.gable(m,n+" folded standing seam blue steel weather canopy",x,z,w,l,h,r,"factory_blue","z")
    for s in (-1,1):
        S.gable_panel(m,n+" closed blue roof end flashing",x,z+s*l/2,w,h,r,"factory_blue_dark",s>0)
        for i in range(1,6):
            v=i/6
            a=(x+s*w/2*v,z-l/2-.006,r+(h-r)*v+.011)
            T(m,n+" rolled steel roof panel seam","factory_blue_seam",a,(a[0],z+l/2+.008,a[2]),.009,.009,6)
        T(m,n+" zinc gutter and rim","steel",(x+s*w/2,z-l/2,h),(x+s*w/2,z+l/2,h),.021,.021,7)
        for zz in (z-l/2,z+l/2):
            T(m,n+" cut blue rake edge","factory_blue_lit",(x,zz,r),(x+s*w/2,zz,h),.019,.015,7)
    T(m,n+" rolled crest ridge cap","factory_blue_lit",(x,z-l/2-.015,r+.008),(x,z+l/2+.015,r+.008),.023,.023,8)


def hall(m,n,x,z,w,l,h,tower=False):
    y0=.104
    B(m,n+" stone beveled load-bearing plinth","foundation",x,z,w+.10,l+.10,.006,y0,.024)
    for side in ("west","east","north"):
        slice_wall(m,n,side,x,z,w,l,y0,h)
    zz=z+l/2
    # Ground-floor portals are real voids through the front facade.
    slice_wall(m,n,"south",x,z,w,l,.614,h,"sienna")
    for xx in (x-w*.407,x,x+w*.407):
        B(m,n+" brick door jamb pilaster","ochrebrick",xx,zz,.181,.077,.11,.637,.009)
    for s in (-1,1):
        xx=x+s*w*.244
        B(m,n+" open door jamb lintel","buff",xx,zz+.011,w*.362,.100,.575,.639,.012)
        B(m,n+" overhead door track","window_iron",xx,zz+.043,w*.317,.024,.521,.577,.006)
        B(m,n+" shadowed internal factory loading floor","concrete_d",xx,zz-.267,w*.355,.690,.101,.119,.006)
        for s2 in (-1,1):
            B(m,n+" loading entrance vertical track","window_iron",xx+s2*.237,zz+.043,.025,.035,.120,.555,.005)
    for ii in range(4):
        xx=x-w*.36+ii*w*.24
        window(m,n,xx,zz+.039,h-.429,l=.228)
    B(m,n+" second-floor recessed band","factory_blue_dark",x,z+l/2+.027,w+.057,.085,h-.102,h-.058,.006)
    blue_roof(m,n,x,z,w+.154,l+.128,h+.013,h+.331)
    for j in range(3):
        a=z-.38+j*.36
        B(m,n+" ridge daylight curb","factory_blue_dark",x,a,.249,.238,h+.244,h+.311,.017)
        B(m,n+" ridge glazed daylight vent","factory_glass",x,a,.186,.197,h+.317,h+.409,.003)
        B(m,n+" broad rain hood","factory_blue_lit",x,a,.287,.265,h+.409,h+.447,.014)
    if tower:
        tx=x-w*.276;tz=z-l*.208
        B(m,n+" masonry freight elevator tower","sienna",tx,tz,.468,.486,.114,h+.717,.016)
        B(m,n+" tower base lintel","ochrebrick",tx,tz,.510,.522,h+.533,h+.588,.012)
        B(m,n+" cut-stone elevator parapet","buff",tx,tz,.528,.546,h+.695,h+.741,.014)
        B(m,n+" cast lift rooftop machinery","factory_blue_dark",tx,tz,.351,.368,h+.732,h+.823,.014)
        for y in (h+.110,h+.376):
            window(m,n+" hoist inspection",tx,tz+.249,y,.247,.158)


def chimney(m,x,z,height):
    n="Factory pair of tapering brick chimneys"
    B(m,n+" rough basalt foot","foundation",x,z,.52,.52,.006,.119,.044)
    T(m,n+" footbrick collar","sienna",(x,z,.105),(x,z,.271),.267,.237,8)
    levels=[(.266,.213),(.50,.199),(.94,.177),(height-.35,.138),
            (height-.24,.139),(height-.19,.175),(height-.047,.179),(height,.167)]
    def ring(h,r):
        return [(x+r*cos(i*pi/8),z+r*sin(i*pi/8),h) for i in range(16)]
    cols=("sienna","firebrick","ochrebrick","flue_edge")
    q=[]
    for i,((a,ra),(b,rb)) in enumerate(zip(levels,levels[1:])):
        count=max(1,round((b-a)/.122))
        for j in range(count):
            t=j/count
            q.append((a+t*(b-a),ra+t*(rb-ra)))
            q.append((a+t*(b-a)+.006,ra+t*(rb-ra)))
    q.append(levels[-1])
    for j,((a,ra),(b,rb)) in enumerate(zip(q,q[1:])):
        p,v=ring(a,ra),ring(b,rb)
        for i in range(16):
            k=(i+1)%16
            c="brick_seam" if j%2==0 else cols[(i*7+j*2)%len(cols)]
            if a>height-.26:c="flue_edge" if j%3 else "flue_shadow"
            F(m,n+" staggered masonry faces",c,(p[i],p[k],v[k],v[i]))
    outer=ring(height,.167);mouth=ring(height,.111);inside=ring(height-.185,.103)
    for i in range(16):
        k=(i+1)%16
        F(m,n+" visibly open chimney crown","flue_edge",(outer[i],outer[k],mouth[k],mouth[i]))
        F(m,n+" dark recessed interior flue","flue_shadow",(mouth[i],mouth[k],inside[k],inside[i]))
    F(m,n+" deep carbon floor of bore","dark_slate",inside)


def enclosure(m):
    for k,(x0,z0) in enumerate(((0,0),(0,4),(4,2))):
        h=(.978,.855,1.113)[k]
        hall(m,"Main production workshop" if k==0 else ("Dispatch packing hall" if k==1 else "Food handling annex"),
             x0+.48,z0+.472,1.539,1.465,h,True)
        hall(m,"Side goods warehouse",x0+.48,z0+1.969,1.375,1.332,.80+(k%2)*.073)
        # Roof-line crossing is linked to the powerhouse, not a new
        # footprint tile. Warehouse stays lower than the control tower.
        B(m,"Guttered covered transfer connector","factory_blue_dark",x0+1.36,z0+.448,.40,.693,.58,.948,.012)
        B(m,"Recessed conveyor access frame","window_iron",x0+1.35,z0+.822,.267,.098,.702,.885,.013)
        B(m,"Transfer conveyor protection hood","factory_blue_lit",x0+1.358,z0+.447,.423,.754,.944,.991,.024)
        hall(m,"Boiler and wash powerhouse",x0+2.30,z0+.630,1.38,1.19,.707+(.045*k))
        for x,z,t in ((x0+2.04,z0+.137,1.855),(x0+2.76,z0+.245,2.109)):
            chimney(m,x,z,t+.122*k)
        if k==1:
            B(m,"Shipping hall enamel blue fascia","factory_blue_dark",x0+.474,z0+2.664,.842,.054,.658,.756,.013)
            A.lettering(m,"Independent WESTFIELD marks","WESTFIELD",(x0+.474,z0+2.693,.703),.012,"south","bone")
        # An uncluttered truck swing is left at +X across the apron.
        B(m,"Dispatch loading platform stone wall","foundation",x0+2.248,z0+1.486,1.13,.452,.007,.15,.025)
        B(m,"Dispatch loading platform timber coping","creamslats",x0+2.248,z0+1.497,1.063,.43,.143,.171,.015)
        for a in (x0+1.75,x0+2.735):
            B(m,"Triangulated loading canopy support stanchion","steelwork",a,z0+1.657,.041,.048,.16,.697,.007)
            T(m,"Braced dispatch canopy knee","steelwork",(a,z0+1.653,.46),(a,z0+1.37,.658),.014,.014,7)
        F(m,"Recessed steel loading canopy roof","factory_blue",[(x0+1.72,z0+1.21,.733),(x0+2.81,z0+1.21,.733),
          (x0+2.81,z0+1.785,.651),(x0+1.72,z0+1.785,.651)])
        T(m,"Canopy rolled edge gutter","steel",(x0+1.709,z0+1.786,.650),(x0+2.815,z0+1.786,.650),.014,.014,7)
        for x in (x0+1.88,x0+2.18):
            A.lantern(m,x,z0+1.28,.52,"Loading bulkhead warmed milk-glass lamp")
        if k!=1:
            A.lantern(m,x0+2.856,z0+1.285,.539,"Powerhouse service lamp")


def consign(m):
    rng=Random(6234)
    for x0,z0 in ((0,0),(0,4),(4,2)):
        for xx,zz,y in ((x0+1.87,z0+1.48,.174),(x0+2.33,z0+1.45,.174),
                        (x0+2.04,z0+2.91,.026),(x0+2.49,z0+3.39,.027)):
            h=rng.uniform(.135,.205)
            color=rng.choice(("goods_crate","goods_crate_pale","timber"))
            for i in range(3):
                zc=zz-.112+i*.111
                B(m,"Split packing pallet bottom oak boards","warmclay",xx,zc,.307,.045,y,y+.022,.004)
            B(m,"Goods packing crates and ingredient boxes",color,xx,zz,.272,.247,y+.027,y+.027+h,.012)
            for dx in (-.083,.081):
                B(m,"Crate front reinforcing ribs","creamsun",xx+dx,zz+.126,.025,.014,y+.032,y+.024+h,.004)
                B(m,"Crate top transverse oak straps","creamsun",xx+dx,zz,.026,.238,y+.025+h,y+.036+h,.005)
        for xx,zz in ((x0+2.97,z0+1.97),(x0+2.69,z0+2.13)):
            T(m,"Removable canvas-covered steel drums","water_green",(xx,zz,.014),(xx,zz,.201),.079,.078,12)
            for h in (.035,.166):
                T(m,"Drum coaming glints","steel",(xx,zz,h),(xx,zz,h+.013),.081,.081,12)
        for zz in (z0+2.078,z0+3.391):
            B(m,"Protective concrete truck-edge bollard","foundation",x0+3.321,zz,.063,.064,.019,.070,.010)
            B(m,"Factory yellow painted steel top bollard","hi_vis",x0+3.321,zz,.039,.039,.065,.207,.006)
            B(m,"Cast bollard stripe","dark_slate",x0+3.321,zz,.041,.040,.133,.155,.004)


if __name__=="__main__":
    S.build(NAME,LAYOUT,(("Asphalt foundations and working truck aprons",base),
      ("Factory and powerhouse buildings, masonry stacks",enclosure),
      ("Export goods pallets, drums and dispatch bollards",consign)),
      "Westfield Factory","stock_temperate_factory.blend",(3.0,3.52,.70),
      (11.55,12.14,8.30),10.30,PAL,os.getenv("STOCK_FACTORY_RENDER"))

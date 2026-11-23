#!/usr/bin/env python3
"""Original conventional RC1 #34 Wood Truck: open timber bunk and removable log load."""
from pathlib import Path
from math import sin,cos,tau
from random import Random
import sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_stock_rail_metals_art as M
from build_stock_rail_farm_art import build
from build_stock_rail_metals_art import B,T,bar,r,w
STOCKWOOD={
  "Log bark brown":"755235","Log bark dark seam":"513e2c","Log bark highlight":"866344",
  "Log freshly cut head":"b28a53","Log growth ring amber":"9b7549","Log narrow sapwood":"bc995f",
  "Log split old brown":"6c5139","Log straps gunmetal blue":"486774",
}
def palette(_):
    p=M.setup(35)
    for old,(n,v) in zip(("Iron oxidized upper","Iron heat glint","Iron density dark","Iron ochre facet",
                           "Iron wet seam","Iron raw terracotta","Iron recess dust","Polished steel pack circumferential lines"),STOCKWOOD.items()):
        items=list(p.items());items[list(p).index(old)]=(n,v);p=dict(items)
    p|={"Mineral enamel navy":"416c87","Mineral weathered highlight":"527f94",
        "Mineral top milled rim blue":"7096a1","Flatcar hardwood brown":"786247",
        "Flatcar hardwood sunward":"927750","Flatcar hardwood dark wet":"634d39",
        "Warm bauxite buffer beam":"515957","Guide iron":"5a6664"}
    M.P=w.P={n:i for i,n in enumerate(p)}
    r.COLORS[:]=p.values()
    return p

def stake_rack(o):
    # Permanent and load-independent; open flat wooden deck, four
    # distinct fitted stake pairs and a low safety blocker at each end.
    w.faces_xz(o,"Closed chamfered timber flatbed base","Mineral enamel navy",
        w.rect(0,0,.437,.834,.022),.188,.230,"Flatcar hardwood dark wet")
    for i in range(12):
        x=(i-5.5)*.034
        B(o,"Individual exposed solid wooden load-floor planks",
          ("Flatcar hardwood brown","Flatcar hardwood sunward","Flatcar hardwood dark wet")[i%3],
          x,0,.033,.791,.226,.244,.003)
    for side in (-1,1):
        for z in (-.345,-.115,.115,.345):
            B(o,"Separate transverse wooden bolsters under the carried logs","Flatcar hardwood dark wet",
              0,z,.431,.044,.243,.265,.004)
            B(o,"Closed armoured stake bed pockets with reverse shoe","Mineral enamel navy",
                side*.209,z,.037,.049,.205,.278,.005)
            bar(o,"Four paired outward-raked steel load restraint stakes","Mineral weathered highlight",
                (side*.192,z,.258),(side*.225,z,.459),.028,.026)
            bar(o,"Forged thin tip guards and smooth painted stake faces","Mineral top milled rim blue",
                (side*.225,z,.435),(side*.226,z,.461),.020,.026)
            for h in (.230,.269):
                T(o,"Outer removable bunk lock pins","Cold rolled coil edge",
                  (side*.236,z,h),.006,"x",-.005,.005,8)
            T(o,"Permanently visible strap guides for each bunk","Log straps gunmetal blue",
              (side*.229,z,.283),.009,"x",-.002,.005,8,False)
        B(o,"Original small leaf marker on blue timber carrier chassis","Original wagon stencil background",
           side*.228,0,.010,.100,.201,.226,.003)
        bar(o,"Thin original leaf stem marking","Original wagon stencil straw",
           (side*.235,-.020,.204),(side*.235,.018,.223),.003,.004)
        for z in (-.011,0,.014):
            B(o,"Three subtle cut leaves on marker","Original wagon stencil straw",side*.235,z,.003,.018,.215,.223,.001)
        B(o,"Inboard permanent narrow timber end beams","Flatcar hardwood brown",0,side*.389,.367,.030,.237,.285,.006)
        for x in (-.164,.164):
            B(o,"Steel end beam brackets beneath logs","Mineral enamel navy",x,side*.389,.031,.038,.237,.290,.004)

def logs(o):
    # Three independent full-length trunks in the lower row and two
    # in the upper row. Actual log geometry has an uneven bark envelope
    # and physically incised cap growth lines with no photo texture.
    rng=Random(340164)
    N=18
    specs=((- .125,.321,.062,-.369,.363),(.001,.325,.064,-.365,.374),(.125,.318,.059,-.372,.369),
           (-.062,.424,.054,-.354,.353),(.063,.429,.052,-.346,.361))
    for no,(cx,cy,rad,z0,z1) in enumerate(specs,1):
        name=f"Independent closed longitudinal pine log {no}"
        jitter=[rng.uniform(.90,1.08) for _ in range(N)]
        angle=rng.uniform(0,tau)
        angles=[angle+tau*i/N for i in range(N)]
        zz=((z0,.91),(z0+.011,1.02),(z0+.070,1.04),(z0+(z1-z0)*.37,1.01),
            (z0+(z1-z0)*.65,.98),(z1-.080,.96),(z1-.012,.95),(z1,.88))
        rows=[]
        for k,(z,f) in enumerate(zz):
            dx=.003*sin(k*.7+no);dy=.002*cos(k*.8+no)
            rows.append([(cx+dx+rad*f*q*cos(a),z+.0025*sin(a*2+no),cy+dy+rad*f*q*sin(a))
                         for q,a in zip(jitter,angles)])
        faces=("Log bark brown","Log bark dark seam","Log bark highlight","Log split old brown","Log bark brown")
        for a,b in zip(rows,rows[1:]):
            for i in range(N):
                j=(i+1)%N
                M.f(o,name,faces[(i*3+no)%5],(a[i],b[i],b[j],a[j]))
        # Caps share actual irregular end vertices. The radii form
        # concentric stepped sapwood and amber seams in the cut face.
        for s,outer in ((-1,rows[0]),(1,rows[-1])):
            z=z0 if s<0 else z1
            hub=(cx+rad*.12,z+s*.0001,cy-rad*.10)
            targets=(.92,.84,.79,.68,.63,.52,.47,.36,.31,.19,.14)
            tones=("Log narrow sapwood","Log freshly cut head","Log growth ring amber","Log freshly cut head")
            A=outer
            for k,v in enumerate(targets):
                y=z+s*(.003+(.0009 if k%2==0 else 0))
                Q=[(hub[0]+(x-hub[0])*v,y,hub[2]+(h-hub[2])*v) for x,_,h in outer]
                for i in range(N):
                    j=(i+1)%N
                    M.f(o,name,tones[k%4],(A[i],A[j],Q[j],Q[i])[::s])
                A=Q
            for i in range(N):
                j=(i+1)%N
                M.f(o,name,"Log growth ring amber",(A[i],A[j],hub)[::s])
    # Two packed-load bands wrap around the silhouette, folded foot
    # ends and blue cargo webbing are visibly distinct from the rack.
    outline=((- .178,.323),(-.153,.373),(-.108,.458),(-.065,.475),(.065,.478),
             (.108,.465),(.155,.380),(.181,.330),(.179,.277),(-.177,.277))
    for j,z in enumerate((-.210,.210),1):
        bands=[]
        for p,d in ((-.010,0),(.010,0),(.010,.004),(-.010,.004)):
            bands.append([(x*(1+d*2),z+p,h+d*(h-.267)*4) for x,h in outline])
        for i,a in enumerate(bands):
            b=bands[(i+1)%len(bands)]
            for k in range(len(a)):
                l=(k+1)%len(a)
                M.f(o,f"Closed crosswise packed log strap {j}","Log straps gunmetal blue",(a[k],a[l],b[l],b[k]))
        B(o,"Short pressed steel strap tensioners","Mineral top milled rim blue",.151,z,
           .021,.029,.368,.398,.004)

if __name__=="__main__":
    build(34,"rail_wood_truck","Wood Truck",stake_rack,logs,palette,
          source=Path(__file__).name,load_name="packed logs and bands")

#!/usr/bin/env python3
"""Original Tidewater Sawmill, exact OpenTTD 14.1 temperate footprint 0."""
from math import cos, pi, sin, tau
from pathlib import Path
from random import Random
import os
import struct
import sys
import zlib

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_rail_wagon_art as w

R=w.rail
bpy=w.bpy
Vector=w.Vector
LAYOUT=((1,0,14),(1,1,12),(1,2,11),(2,0,14),(2,1,13),(0,0,15),(0,1,15),(0,2,12))
PAL={
    "yard_dark":"6d5b48","yard_warm":"826d52","yard_light":"8c755b","packed_clay":"917b5e",
    "wheel_rut":"786552","wheel_sand":"9b8366","chip":"b8a174","fine_sawdust":"ae9060",
    "foundation":"888278","concrete_bright":"a2a092","concrete_cold":"7c8178","mortar":"766b5d",
    "oak_dark":"6a4e37","oak_shade":"775642","oak_warm":"936744","oak_weather":"88735f",
    "oak_high":"a67a50","oak_trim":"c1a079","cut_pine":"c2985b","fresh_split":"d3ab6f",
    "end_wood":"e2bd85","growth_ring":"9f8154","growth_light":"bb985f","heartwood":"ba9666",
    "bark_1":"674833","bark_2":"805a39","bark_3":"9a683d","bark_4":"9b7852",
    "bark_5":"504435","bark_wet":"5a5447","bark_shade":"6b5c46","sap":"a98952",
    "slate":"596364","slate_dark":"48565a","slate_light":"6a7270","slate_grey":"616d6c","roof_flash":"85908a",
    "cinder":"4a4c45","iron_dark":"455352","iron":"63706b","bright_steel":"98a09a",
    "iron_ochre":"ad8652","brick":"a57358","brick_dark":"875344","brick_bright":"b58161",
    "foreman":"405c55","enamel":"cbba92","glazing":"526f75","glass_light":"8ea8a8",
    "drum_rubber":"454a44","electric":"58675b","sawdust_dark":"987c50","strap":"6f7368",
}
P={k:i for i,k in enumerate(PAL)}
w.P=P
R.COLORS[:]=PAL.values()
B,T=w.slab,w.circular
Q=w.rect
RFX="bl_sawmill"


def art_mesh():
    return R.Mesh(R.terrain_height(0))


def f(m,g,c,pts):
    m.face(g,P[c],pts)


def patch(m,g,c,x0,x1,z0,z1,h):
    f(m,g,c,((x0,z0,h),(x1,z0,h),(x1,z1,h),(x0,z1,h)))


def disk(m,g,c,x,z,h,rad,num=12):
    ring=[(x+rad*cos(tau*i/num),z+rad*sin(tau*i/num),h) for i in range(num)]
    f(m,g,c,ring)


def tube(m,g,c,a,b,r0,r1=None,n=12,caps=True):
    a,b=Vector(a),Vector(b)
    d=(b-a).normalized()
    u=d.cross(Vector((0,0,1) if abs(d.z)<.86 else (0,1,0))).normalized()
    v=d.cross(u).normalized()
    rr=lambda p,rad:[tuple(p+rad*(u*cos(tau*i/n)+v*sin(tau*i/n))) for i in range(n)]
    lo,hi=rr(a,r0),rr(b,r0 if r1 is None else r1)
    if caps:f(m,g,c,lo[::-1]);f(m,g,c,hi)
    for i in range(n):
        j=(i+1)%n
        f(m,g,c,(lo[i],lo[j],hi[j],hi[i]))


def spar(m,g,c,a,b,width,thick):
    a,b=Vector(a),Vector(b)
    d=(b-a).normalized()
    u=d.cross(Vector((0,0,1) if abs(d.z)<.83 else (0,1,0))).normalized()*width/2
    v=d.cross(u).normalized()*thick/2
    ps=(u+v,-u+v,-u-v,u-v)
    a,b=([tuple(q+p) for p in ps] for q in (a,b))
    f(m,g,c,a[::-1]);f(m,g,c,b)
    for i in range(4):
        j=(i+1)%4
        f(m,g,c,(a[i],a[j],b[j],b[i]))


def shift(m,group,x,z,h,turn=0):
    for name,faces in group.parts.items():
        vs=group.vertices[name]
        for ids,c in faces:
            pts=[]
            for i in ids:
                u,v,b=vs[i]
                a,d=((u,v),(-v,u),(-u,-v),(v,-u))[turn]
                pts.append((a+x,d+z,b+h))
            f(m,name,list(PAL)[c],pts)


def base(m):
    for i,(x,z,g) in enumerate(LAYOUT):
        a,b=2*x,2*z
        cols=("yard_dark","yard_warm","yard_light","yard_warm","packed_clay")
        patch(m,"Exact unpaved sawmill footprint",cols[(g*3+x+z)%len(cols)],a-.5,a+1.5,b-.5,b+1.5,.002)
        rng=Random(996+17*i)
        for j in range(73):
            cx,cz=a+rng.uniform(-.468,1.467),b+rng.uniform(-.469,1.467)
            dx,dz=rng.uniform(.007,.029),rng.uniform(.006,.031)
            patch(m,"Dispersed bark and sawdust on hard yard",rng.choice(cols+("chip","fine_sawdust","yard_warm")),
                  cx-dx,cx+dx,cz-dz,cz+dz,.0037)
    # A flush courtyard reads as a sibling to the actual road approach.
    patch(m,"Full east timber intake approach","packed_clay",4.604,5.5,1.636,3.348,.005)
    for z in (2.110,2.533):
        patch(m,"Warm wheel lanes in sorted-log approach","wheel_sand",4.64,5.5,z-.064,z+.064,.007)
    patch(m,"Unobstructed south dry-lumber dispatch apron","packed_clay",.05,2.85,4.949,5.5,.005)
    for x in (.518,1.007,1.947,2.425):
        patch(m,"Truck dock shallow flush tire paths","wheel_rut",x-.055,x+.055,4.962,5.5,.007)
    # A little triangle of authentic gravel under a bridge between yards.
    patch(m,"Below conveyors gravel under runners","foundation",1.927,2.639,1.296,4.009,.0055)


def log(m,x,z,y,length,radius,axis=0,var=0,style="mixed",group="Rough logs"):
    """Bark with separate individually ringed cut ends, slight taper, splits."""
    rng=Random(var)
    n=10 if radius<.105 else 13
    rings=[]
    rr=(.940,1.01,.96,.86)
    for j,t in enumerate((-.5,-.34,.30,.5)):
        # Small curvature and asymmetric radial offsets prevent cloned timber.
        zz=t*length
        seed=[]
        for k in range(n):
            a=tau*k/n
            r=radius*rr[j]*(1+rng.uniform(-.071,.071))
            u=r*cos(a)+radius*.11*sin(j*2+var)
            h=r*sin(a)
            seed.append((x+u,z+zz,y+h) if axis else (x+zz,z-u,y+h))
        rings.append(seed)
    tones=("bark_1","bark_2","bark_3","bark_3","bark_4","bark_5") if style=="mixed" else (
           ("bark_wet","bark_5","bark_shade","bark_shade","bark_5") if style=="dark" else ("bark_3","bark_4","oak_high","bark_2"))
    for i,(a,b) in enumerate(zip(rings,rings[1:])):
        for k in range(n):
            j=(k+1)%n
            f(m,group+" tapered bark","bark_5" if k>n*.78 else rng.choice(tones),(a[k],b[k],b[j],a[j]))
    for j in (-1,1):
        rim=rings[0 if j<0 else -1]
        cx,cz,ch=(sum(v[i] for v in rim)/n for i in range(3))
        rr=[rim]
        for a in (.78,.69,.39,.32,.17):
            rr.append([(cx+(x-cx)*a+(j*.002 if axis==0 else 0),
                        cz+(z-cz)*a+(j*.002 if axis else 0),ch+(v-ch)*a) for x,z,v in rim])
        for idx,(a,b) in enumerate(zip(rr,rr[1:])):
            col=("cut_pine","growth_ring","end_wood","growth_light","heartwood")[idx]
            for k in range(n):
                u=(k+1)%n
                pts=(a[k],a[u],b[u],b[k])
                f(m,group+" exposed concentric end-grain measures",col,pts[::-1] if j>0 else pts)
        f(m,group+" original cut heartwood","cut_pine",rr[-1][::-1] if j>0 else rr[-1])
        # Tight checking along narrow end-grain seams.
        for idx in (2,6 if n>6 else 5):
            l=rr[0][idx];a=rr[1][idx];b=rr[2][idx]
            q=(b[0]+(j*.003 if axis==0 else .012),b[1]+(j*.003 if axis else .008),b[2]+.006)
            f(m,group+" exposed checking fissures","bark_5",(l,a,q) if j>0 else (q,a,l))


def log_stack(m,x,z,length,axis,seed,style,rows=(5,4,3,2,1),radius=.106):
    for j,num in enumerate(rows):
        for i in range(num):
            u=(i-(num-1)/2)*radius*1.79
            h=.056+radius*(.91+1.62*j)
            a=x+u if axis else x+(.022*sin(i+j))
            b=z+u if not axis else z+(.029*sin(i+j))
            rng=Random(seed+31*j+i)
            dx,dz=a+rng.uniform(-.018,.018),b+rng.uniform(-.016,.016)
            log(m,dx,dz,h,length*rng.uniform(.891,1.024),radius*rng.uniform(.91,1.053),
                axis,seed+j*101+i*71,style,"Roundwood deck")
    for offset in (-.41,.41):
        x0,z0=(x,z+offset) if axis else (x+offset,z)
        w0,h0=(radius*(rows[0]+1)*1.89,.068) if axis else (.068,radius*(rows[0]+1)*1.89)
        B(m,"Raw log stacking chocks","oak_dark",x0,z0,w0,h0,.015,.072,.007)


def bundle(m,x,z,width,length,layers,seed,turn=0):
    rng=Random(seed)
    for j in range(layers):
        for i in range(4):
            across=(i-1.5)*width/4
            zz=rng.uniform(-.012,.012)
            col=rng.choice(("cut_pine","fresh_split","end_wood","fresh_split","growth_light"))
            if turn:
                xp,zp=x+zz,z+across
                B(m,"Individual sawn timber board","end_wood",xp,zp,length,width/4-.005,.120+j*.039,.145+j*.039,.004,col)
            else:
                xp,zp=x+across,z+zz
                B(m,"Individual sawn timber board","end_wood",xp,zp,width/4-.005,length,.120+j*.039,.145+j*.039,.004,col)
        if j!=layers-1:
            for d in (-.29,.29):
                a,b=(x+d*length,z) if turn else (x,z+d*length)
                ww,ll=(.026,width-.008) if turn else (width-.008,.026)
                B(m,"Spacer stickers between sawn boards","oak_shade",a,b,ww,ll,.145+j*.039,.158+j*.039,.001)
    for side in (-1,1):
        l=.272*length*side
        xp,zp=(x+l,z) if turn else (x,z+l)
        B(m,"Rack below finished lumber","oak_shade",xp,zp,(.105 if turn else width+.045),
            (width+.045 if turn else .105),.028,.117,.007,"oak_warm")
        B(m,"Inset flat ties on finished lumber","strap",xp,zp,
            (.024 if turn else width-.002),(width-.002 if turn else .024),
            .145+(layers-1)*.039,.148+(layers-1)*.039)


LETTERS={
    "S":("0111","1000","0110","0001","1110"),"A":("0110","1001","1111","1001","1001"),
    "W":("10001","10001","10101","10101","01010"),"M":("10001","11011","10101","10001","10001"),
    "I":("111","010","010","010","111"),"L":("100","100","100","100","111"),
    "T":("111","010","010","010","010"),"O":("0110","1001","1001","1001","0110"),
    "G":("0111","1000","1011","1001","0111"),"D":("1110","1001","1001","1001","1110"),
}
def sign(m,x,z,h,word,sg=1):
    k=.012
    width=(sum(len(LETTERS[c][0])+1 for c in word)+3)*k
    B(m,"Sawmill shop painted enamel board","foreman",x,z,width,.022,h,h+.085,.008)
    B(m,"Original cream timber site signs","enamel",x,z+sg*.013,width-.020,.008,h+.010,h+.074,.003)
    count=sum(len(LETTERS[c][0])+1 for c in word)-1
    i=0
    for c in word:
        glyph=LETTERS[c]
        for j,row in enumerate(glyph):
            for a,on in enumerate(row):
                if on=="1":
                    z0=z+sg*.018
                    x0=x-sg*(i+a+.5-count/2)*k
                    y=h+.017+(4-j)*.010
                    pts=((x0-.45*k,z0,y),(x0+.45*k,z0,y),(x0+.45*k,z0,y+.0095),(x0-.45*k,z0,y+.0095))
                    f(m,"Raised working yard sign lettering","foreman",pts[::-1] if sg>0 else pts)
        i+=len(glyph[0])+1


def roof(m,x,z,width,length,eave,rise=.250,ridge=0):
    # Folded slate running seams and real roof thickness, over open doors.
    holder=art_mesh()
    w=width/2+.063;l=length/2+.064
    for sign in (-1,1):
        a,b=sorted((0,sign*w))
        for j in range(11):
            q=-l+2*l*j/11
            nz=-l+2*l*(j+1)/11-.002
            h=lambda u:eave+rise*(1-abs(u)/w)
            pts=((a,q,h(a)),(b,q,h(b)),(b,nz,h(b)),(a,nz,h(a)))
            low=[(u,v,y-.029) for u,v,y in pts]
            f(holder,"Pressed grey slate roof panels",("slate","slate_grey","slate_dark","slate","slate_light")[(j*3+sign)%5],pts)
            f(holder,"Exposed wooden roof lining","oak_dark",low[::-1])
            for i in range(4):
                n=(i+1)%4
                f(holder,"Slate folded eave overhang","slate_dark",(low[i],low[n],pts[n],pts[i]))
            spar(holder,"Long standing seams along folded slate","roof_flash",(a,q+.001,h(a)+.005),
                (b,q+.001,h(b)+.005),.013,.009)
        for nz in (-l-.008,l+.004):
            spar(holder,"Raking-bar edge to weatherboard eave","oak_trim",(a,nz,h(a)-.032),
                (b,nz,h(b)-.032),.041,.027)
        tube(holder,"Cylindrical iron eave gutter","iron_dark",(sign*(w+.008),-l,eave-.021),
            (sign*(w+.008),l,eave-.021),.021,n=9)
    tube(holder,"Pressed round slate ridge flashing","roof_flash",(0,-l-.011,eave+rise),
         (0,l+.011,eave+rise),.023,n=12)
    shift(m,holder,x,z,0,ridge)


def boards(m,x,z,width,length,open_front,eave,lean=False,office=False,rise=.25):
    # Actual interior volume: floor, individual timber siding, sill and
    # lintel only, with a full-size aperture left in machine/drying sheds.
    B(m,"Dressed footing around mill workshop","foundation",x,z,width+.075,length+.069,.004,.101,.018)
    B(m,"Mill individually clamped working floor","oak_weather",x,z,width-.038,length-.033,.099,.126,.008)
    for s in (-1,1):
        xx=x+s*(width/2-.027)
        B(m,"Structural workshop timber side sill","oak_dark",xx,z,.077,length,.106,.155,.007)
        for i in range(max(8,round(length/.083))):
            n=round(length/.083)
            b=z-length/2+(i+.51)*length/n
            col=("oak_shade","oak_warm","oak_dark","oak_warm","oak_weather")[(i*17+s)%5]
            # Service group gets three actual separated side window slots.
            if lean and s>0 and abs(b-z+.092)<.280:
                B(m,"Mill side lapped weatherboards below windows",col,xx,b,.065,length/n-.003,
                  .143,eave*.53,.004)
                B(m,"Mill side lapped weatherboards above windows",col,xx,b,.065,length/n-.003,
                  eave*.80,eave-.025,.004)
            else:
                B(m,"Mill side lapped weatherboards",col,xx,b,.064,length/n-.003,.145,eave-.030,.004)
        if lean and s>0:
            win_h=(eave*.53+eave*.80)/2
            B(m,"Sunlit painted workshop window casing","oak_trim",xx+.029,z-.092,.026,.545,eave*.53-.014,eave*.80+.013,.008)
            for dz in (-.174,0,.174):
                B(m,"Darkened workshop glass pane","glazing",xx+.049,z-.092+dz,.010,.159,
                    eave*.53+.006,eave*.80-.013,.004)
                B(m,"Glint from western mill window","glass_light",xx+.055,z-.088+dz,.005,.108,
                    win_h+.025,eave*.80-.027,.003)
        B(m,"Exposed timber wall eave plate","oak_dark",xx,z,.086,length,eave-.049,eave+.003,.007)
    for s in (-1,1):
        zz=z+s*(length/2-.019)
        aw=width/2
        front=s>0
        opening=open_front if front else (.55 if lean else 0)
        if office and front:opening=.240
        for i in range(max(7,round(width/.080))):
            n=round(width/.080)
            a=-aw+(i+.5)*width/n
            l=width/n-.005
            color=("oak_warm","oak_high","oak_weather","oak_shade")[(i*13+s)%4]
            lo=.150 if abs(a)-l*.375>opening*.5 else (.677 if front else .533)
            top=eave+rise*(1-abs(a)/aw)
            if lo>top-.024:continue
            B(m,"Vertical timbers of gabled mill end",color,x+a,zz,l,.054,lo,top-.021,.004)
        for p in (-1,1):
            B(m,"Workshop split timber upright","oak_dark",x+p*(aw-.030),zz,.084,.092,.101,eave-.004,.006)
            if opening:
                xpos=x+p*(opening*.5+.002)
                h=.690 if front else .553
                # Pediment over air; side posts define a real door.
                B(m,"Frame post at working bay width","oak_trim",xpos,zz+s*.015,.060,.071,.116,h,.006)
        if opening:
            bottom=.668 if front and not office else .535
            if office and front:
                B(m,"Part open foreman office split door","foreman",x+.063,zz-s*.016,.097,.053,.125,.545,.007)
                B(m,"Glazing in small foreman side door","glazing",x+.063,zz+s*.014,.060,.008,.395,.506,.003)
            B(m,"Wide rustic oak door lintel","oak_trim",x,zz+s*.026,opening+.112,.080,bottom,bottom+.041,.007)
        # Actual relief peg heads and gear tie backs on the end.
        for dz in (-.116,.116):
            tube(m,"Bar stock roof-wall peg","bright_steel",(x+dz,zz,eave+.014),
                 (x+dz,zz+s*.043,eave+.014),.010,n=8)
    roof(m,x,z,width,length,eave,rise)
    if office:sign(m,x,z+length/2+.029,eave+.048,"MILL")


def rollers(m,x,z,a,b,toward="z",name="Green infeed"):
    # Roller bed continuous through snow-free flat cells. Longitudinal
    # steel webs and emergency stops are physically visible at each end.
    length=b-a
    def pt(u,v,h):
        return (x+u,z+v,h) if toward=="z" else (x+v,z+u,h)
    for u in (-.180,.180):
        spar(m,name+" continuous side angle rails","iron_dark",pt(u,a,.365),pt(u,b,.365),.052,.078)
        spar(m,name+" brushed running flange","bright_steel",pt(u,a,.411),pt(u,b,.411),.035,.025)
    for j in range(round(length/.145)):
        t=a+(j+.5)*length/round(length/.145)
        tube(m,name+" individually spaced idler drums","iron",pt(-.160,t,.382),
             pt(.160,t,.382),.027,n=9)
        if j%3==1:
            for u in (-.195,.195):
                p=pt(u,t,.050)
                B(m,"Cross deck roller support plate","concrete_cold",p[0],p[1],.104,.115,.012,.091,.010)
                spar(m,"Fixed conveyor stanchions","iron_ochre",p,pt(u,t,.346),.041,.053)
    for t in (a+.032,b-.035):
        tube(m,"Roller conveyor transverse end stop","iron_ochre",pt(-.173,t,.423),pt(.173,t,.423),.018,n=8)


def saw_bay(m,x,z):
    B(m,"Sawn timber cast saw bed","iron_dark",x,z,.588,.717,.108,.244,.015)
    for i in range(6):
        B(m,"Sculpted stiffening ribs on saw stand","iron",x-.263,z+(i-2.5)*.104,.056,.030,.171,.271,.005)
    B(m,"Rip-table fence and gauge frame","iron",x,z,.560,.610,.248,.275,.006)
    for s in (-1,1):
        B(m,"Steel slit in inspected feed table","bright_steel",x+s*.162,z,.243,.607,.274,.291,.002)
    # Upper visible sector; the rest is below the slotted safety bed.
    blade=.166
    cy=.267
    n=34
    for i in range(n):
        a=i*pi/n;b=(i+1)*pi/n
        center=(x,z,cy)
        l=(x,z+blade*cos(a),cy+blade*sin(a))
        rr=(x,z+blade*cos(b),cy+blade*sin(b))
        for s in (-1,1):
            tr=[(q+s*.006,w,h) for q,w,h in (center,l,rr)]
            f(m,"Actual installed circular mill saw rim","bright_steel" if i%5 else "iron",tr if s>0 else tr[::-1])
        q=(x+.007,z+(blade+.011)*cos(a+(b-a)*.33),cy+(blade+.011)*sin(a+(b-a)*.33))
        f(m,"Individual upper sawtooth edges","iron",(l,q,rr))
    B(m,"Protective partially raised saw guard bracket","iron_ochre",x-.156,z-.175,.075,.088,.273,.525,.006)
    for dz in (-.10,.11):
        spar(m,"Curved guard supports above fixed saw","iron_ochre",(x-.147,z+dz,.541),(x+.086,z+dz,.466),.025,.037)
    B(m,"Raised belt cover half shell","iron_dark",x+.259,z-.038,.141,.381,.261,.427,.021)
    tube(m,"Motor bearing inspection round flange","iron", (x+.266,z+.195,.298),(x+.266,z+.244,.299),.072,n=15)
    tube(m,"Motor lower shaft","bright_steel",(x+.266,z+.241,.298),(x+.266,z+.287,.298),.024,n=11)
    for zz in (-.113,.04,.12):
        guards=(x+.348,z+zz,.066)
        B(m,"Motor foundation metal plate foot","iron_ochre",guards[0],guards[1],.091,.118,.018,.067,.004)


def crane(m,x,z):
    # Small grey yard grip gantry. Amber hall of raw logs remains dominant.
    for zz in (z-.472,z+.465):
        for xx in (x-.494,x+.495):
            B(m,"Bogies under raw log handling gantry","concrete_cold",xx,zz,.143,.146,.017,.106,.012)
            B(m,"Structural timber sorting gantry posts","iron_dark",xx,zz,.071,.074,.104,.992,.007)
            spar(m,"Gantry braces on below rail structure","iron",(xx,zz,.737),(xx,zz+(.219 if zz<z else -.219),.970),.033,.038)
        B(m,"Transverse overhead log sorting bridge beam","iron_ochre",x,zz,1.118,.098,.948,1.064,.009)
    for xx in (x-.492,x+.495):
        B(m,"Gantry overhead travel rail support","iron",xx,z,.081,1.080,.925,1.034,.008)
    for xx in (x-.170,x+.172):
        B(m,"Greased longitudinal trolley wheels","iron_dark",xx,z,.064,.990,1.021,1.068,.007)
    x0=x+.081; z0=z+.138
    B(m,"Hoist trolley machine case","iron_ochre",x0,z0,.274,.159,1.057,1.174,.013)
    for q in (-.049,.053):
        tube(m,"Lowering winch steel cable","iron_dark",(x0+q,z0,1.063),(x0+q,z0,.746),.007,n=8)
        spar(m,"Hook for pick up logs","bright_steel",(x0+q,z0,.722),(x0+q,z0+(q*.61),.682),.019,.023)
    B(m,"Gantry empty stock ticket sign","foreman",x,z+.527,.297,.030,.960,1.022,.004)


def structures(m):
    # Gfx15: the two back workshops and open drying loft. Main roof group
    # keeps the collapsed grey-and-brown visual mass of the base-game mill.
    boards(m,.473,.421,1.404,1.490,.51,.783,lean=True,office=True,rise=.231)
    boards(m,.476,2.491,1.450,1.568,.714,.796,lean=False,rise=.200)
    for x,z in ((.101,.866),(.202,3.01),(.716,2.871)):
        B(m,"Clamp racks inside split piled wall bay","iron_dark",x,z,.271,.422,.135,.198,.012)
        B(m,"Tidy lane bundles in storage shed","cut_pine",x,z,.251,.385,.199,.299,.006,"fresh_split")
    # Gfx12: street-level working hall, tangible saw and apron.
    boards(m,2.490,2.533,1.486,1.546,.969,.834,lean=True,rise=.249)
    saw_bay(m,2.494,2.554)
    sign(m,2.49,3.356,.735,"SAWMILL")
    # Gfx11 and repeated Gfx12: lumber dressing and finished goods frontage.
    boards(m,2.490,4.284,1.433,1.170,.786,.720,lean=True,rise=.208)
    boards(m,.480,4.188,1.462,1.149,.901,.746,lean=False,rise=.195)
    sign(m,.480,4.819,.696,"LOAD")
    bundle(m,.210,5.146,.352,.540,5,741,turn=1)
    bundle(m,.901,5.125,.369,.640,4,721,turn=1)
    bundle(m,2.054,5.031,.392,.533,4,348,turn=1)
    # Rear of dressing shed leaves the transfer line visible from survey.
    bundle(m,2.947,4.445,.321,.359,3,742,turn=0)
    for x,z in ((1.087,4.921),(1.569,4.973)):
        B(m,"Tinted lane buffer bin","oak_warm",x,z,.172,.150,.016,.121,.013)
        B(m,"Iron workyard crossing bollard","iron_ochre",x,z,.044,.048,.120,.315,.003)
    # Distinct intake Sorting deck on gfx13 (wood accepted here).
    log_stack(m,4.183,2.816,1.020,1,500,"dark",rows=(4,3,2,1),radius=.092)
    crane(m,4.141,2.493)
    rollers(m,0,1.905,3.692,4.806,"x","East raw roundwood transfer")
    # Paired amber log mass on the two stock gfx14 cells.
    log_stack(m,2.457,.572,1.151,0,133,"gold",rows=(7,6,5,4,3,2),radius=.109)
    log_stack(m,4.548,.537,1.168,0,422,"gold",rows=(7,6,5,4,3,2),radius=.107)
    # Bilateral receiving and outing physically share the two tile seams.
    rollers(m,2.45,0,.964,2.266,"z","North feed bridge")
    rollers(m,2.45,0,2.854,4.105,"z","South transfer bridge")


def clip(pts,axis,at,sg):
    out=[]
    for i,n in enumerate(pts):
        p=pts[i-1]
        a=(p[axis]-at)*sg>=-1e-7
        b=(n[axis]-at)*sg>=-1e-7
        if a!=b:
            f=(at-p[axis])/(n[axis]-p[axis])
            out.append(tuple(v+(u-v)*f if j!=axis else at for j,(v,u) in enumerate(zip(p,n))))
        if b:out.append(n)
    return out


def split(m,x,z):
    out=art_mesh()
    xx,zz=2*x-.5,2*z-.5
    for name,faces in m.parts.items():
        verts=m.vertices[name]
        for inds,c in faces:
            pts=[verts[i] for i in inds]
            if max(p[0] for p in pts)<xx-1e-6 or min(p[0] for p in pts)>xx+2+1e-6:continue
            if max(p[1] for p in pts)<zz-1e-6 or min(p[1] for p in pts)>zz+2+1e-6:continue
            for axis,at,side in ((0,xx,1),(0,xx+2,-1),(1,zz,1),(1,zz+2,-1)):
                pts=clip(pts,axis,at,side)
                if not pts:break
            # Rounded faces just crossing a boundary preserve physical joins.
            out.face(name,c,[(a-xx-1,b-zz-1,h) for a,b,h in pts])
    return out


def atlas(prefix,pal):
    def chunk(tag,payload):
        return struct.pack(">I",len(payload))+tag+payload+struct.pack(">I",zlib.crc32(tag+payload))
    row=b"".join(bytes.fromhex(c)*8 for c in pal.values())
    png=b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",len(pal)*8,8,8,2,0,0,0))
    png+=chunk(b"IDAT",zlib.compress((b"\0"+row)*8))+chunk(b"IEND",b"")
    (R.TEXTURES/(prefix+"_atlas.png")).write_bytes(png)


def review_scene(scene,aim,scale):
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.006))
    mat=bpy.data.materials.new("Muted temperate terrain surrounding sawmill")
    mat.diffuse_color=(.134,.206,.131,1)
    bpy.context.object.data.materials.append(mat)
    bpy.ops.object.camera_add(location=(10.23,12.68,8.52))
    cam=bpy.context.object
    cam.rotation_euler=(Vector(aim)-cam.location).to_track_quat("-Z","Y").to_euler()
    cam.data.type="ORTHO";cam.data.ortho_scale=scale;scene.camera=cam
    scene.render.engine="BLENDER_WORKBENCH"
    scene.render.resolution_x=1540;scene.render.resolution_y=1070
    scene.display.shading.light="STUDIO"
    scene.display.shading.color_type="MATERIAL"
    scene.display.shading.show_shadows=True
    scene.display.shading.show_cavity=True
    scene.display.shading.cavity_type="BOTH"
    scene.display.shading.cavity_ridge_factor=1.22
    scene.display.shading.background_type="WORLD"
    scene.world=bpy.data.worlds.new("Delicate Atlantic grey daylight")
    scene.world.color=(.154,.190,.231)
    scene.view_settings.view_transform="Standard"


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    m=art_mesh();base(m);structures(m)
    mats=R.materials()
    for i,mat in enumerate(mats):mat.name=list(PAL)[i]
    scene=bpy.context.scene
    scene.name="LuanTTD | Tidewater Sawmill stock 0"
    for x,z,gfx in LAYOUT:
        tile=split(m,x,z)
        coll=R.stash(tile,mats,f"Stock Sawmill ({x},{z}) gfx {gfx}")
        R.instance(scene,coll,2*x+.5,2*z+.5)
        R.export_obj(R.MODELS/(f"{RFX}_0_{x}_{z}.obj"),tile)
    atlas(RFX,PAL)
    review_scene(scene,(2.35,2.44,.38),8.1)
    bpy.ops.wm.save_as_mainfile(filepath=str(R.ROOT/"art"/"tidewater_sawmill.blend"),compress=True)
    if out:=os.getenv("SAWMILL_ART_RENDER"):
        scene.render.filepath=out;bpy.ops.render.render(write_still=True)


if __name__=="__main__":
    main()

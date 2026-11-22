#!/usr/bin/env python3
"""Original Cedar Coal; exact OpenTTD 14.1 temperate Coal Mine layout 0.

blender -b -t 4 --python-exit-code 1 --python tools/build_coal_mine_art.py
COAL_MINE_RENDER=/tmp/coal-mine.png blender -b -t 4 --python tools/build_coal_mine_art.py
"""
from math import cos, hypot, pi, sin
from pathlib import Path
from random import Random
import os
import struct
import sys
import zlib

import bpy
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_small_airport_art as A

R,H=A.RAIL,A.H
PAL=dict(A.PAL,**{
    "soot":"3c4443","dressed":"a9a898","gravel_brown":"918270",
    "mine_teal":"415957","iron":"748280","iron_edge":"8e9a91",
    "rail_rust":"8a6652","cage":"4a615b","cadmium":"d1a56b","iron_dark":"3b4644",
    "hoist_timber":"987453","dark_lagging":"684e42","coke":"282d2e",
    "anthracite":"34393b","shale":"494b48","gray_coal":"44484a","pale_coal":"5b5c56",
    "brick_c":"9b624d","brick_deep":"85513f","brick_bright":"b27558",
    "window_mill":"6f8989","window_muted":"465d62","rubber_coal":"333b3a",
    "whitesmoke":"ffffdb","oxide":"9d7457",
})
A.PAL=PAL
A.P=H.P={k:i for i,k in enumerate(PAL)}
P=A.P
R.COLORS[:]=PAL.values()
B,T,F,Q=A.B,A.T,A.face,A.rect
LAYOUT=((1,1,0),(1,2,2),(0,0,5),(1,0,6),(2,0,3),(2,2,3))
WIND_X,WIND_Z,WIND_H=2.50,2.42,2.395
RIM=.262
A.DIGITS["C"]=("01111","11000","11000","11000","11000","11000","01111")
A.DIGITS["M"]=("11011","11111","10101","10101","10001","10001","10001")
A.DIGITS["S"]=("01111","11000","11000","01110","00011","00011","11110")
COAL=("coke","anthracite","gray_coal","shale","pale_coal")


def layer(m,n,color,x0,x1,z0,z1,y):
    Q(m,n,color,x0,x1,z0,z1,y)


def section(m,n,dom,color):
    # Drawing layout coordinates place the native tile (0,0) center at .5,.5.
    x,z=dom
    layer(m,n,color,x-.5,x+1.5,z-.5,z+1.5,.0017)


def ground(m):
    rng=Random(829)
    for x,z,gfx in LAYOUT:
        a,b=2*x,2*z
        section(m,"Individual stock coal mine yard ground",(a,b),
                "gravel_brown" if gfx in (0,3) else "gravel")
        for j in range(113):
            px,pz=a+rng.uniform(-.467,1.47),b+rng.uniform(-.466,1.47)
            w,l=rng.uniform(.006,.034),rng.uniform(.005,.031)
            col=rng.choice(("gravel_d","gravel_brown","gravel_l","asphalt_joint"))
            layer(m,"Sparse gritty spoil in the roadway",col,px-w,px+w,pz-l,pz+l,.0030)
    # West truck pad and distinct southern rail receiving/loading frontage.
    layer(m,"West truck stop approach concrete","concrete_d",-.5,1.487,.139,1.212,.005)
    layer(m,"West ramp brick apron at main scale","concrete",-.5,.871,.315,.990,.006)
    layer(m,"Open rail-side platform apron","concrete_d",3.502,5.5,4.246,5.5,.004)
    layer(m,"East loading frontage open wheel clearance","concrete_l",4.950,5.5,3.501,5.5,.006)
    for i in range(8):
        z=3.58+.239*i
        layer(m,"Rail apron contraction joints","concrete_seal",4.971,5.48,z,z+.007,.009)
    for x in (-.43,-.19,.052,.294,.535,.78,1.03,1.276):
        layer(m,"West apron low worn lane markings","paint_shadow",x-.063,x+.063,.231,.249,.008)
    for z in (.174,1.158):
        layer(m,"Safety paint west weighing curb","yellow",-.483,1.465,z,z+.014,.008)
    for t in range(5):
        x=5.16+t*.061
        layer(m,"Vehicle guidance yellow loading marks","yellow",x-.012,x+.012,4.97,5.194,.010)


def block(m,n,x0,x1,z0,z1,h0,h1,material="brick_c",walls=("x","z")):
    B(m,n+" load-bearing brickwork",material,(x0+x1)/2,(z0+z1)/2,x1-x0,z1-z0,h0,h1)
    rng=Random(int(abs(x0*41+z0*239+h1*32)))
    levels=range(max(1,int((h1-h0)/.081)))
    for row in levels:
        h=h0+row*.081+.004
        for key in walls:
            for sd in (-1,1):
                a,b=(z0,z1) if key=="x" else (x0,x1)
                p=a-.081*(row%2)
                while p<b:
                    c,d=max(a,p+.005),min(b,p+.154)
                    if d-c>.004:
                        mat=rng.choices(("brick_c","brick_deep","brick_bright"),(7,2,2))[0]
                        if key=="x":
                            x=(x0 if sd<0 else x1)
                            F(m,n+" stepped individual bricks",mat,
                              [(x+sd*.003,c,h),(x+sd*.003,d,h),(x+sd*.003,d,h+.070),
                               (x+sd*.003,c,h+.070)][::sd])
                        else:
                            z=(z0 if sd<0 else z1)
                            F(m,n+" stepped individual bricks",mat,
                              [(c,z+sd*.003,h),(d,z+sd*.003,h),(d,z+sd*.003,h+.070),
                               (c,z+sd*.003,h+.070)][::-sd])
                    p+=.159


def roof(m,n,x,z,w,l,h,pitch=.32):
    def y(x1,z1):return h+(w*.5-abs(x1-x))*pitch
    for a,b in ((x-w*.5,x),(x,x+w*.5)):
        B(m,n+" weathered roof","slate",(a+b)/2,z,b-a,l,lambda x,z:y(x,z)-.03,y)
        for k in range(max(3,int(l/.129))):
            seam=z-l*.45+k*l*.9/max(3,int(l/.129))
            B(m,n+" standing seam iron ribs","slate_rib",(a+b)/2,seam,b-a,.011,
                y,lambda x,z:y(x,z)+.010)
    B(m,n+" crown flashing","slate_rib",x,z,.036,l+.006,y(x,z)-.006,y(x,z)+.023,.004)


def window(m,n,x,z,h,axis,size=.180):
    if axis=="x":
        B(m,n+" masonry sill","dressed",x,z,.039,size+.040,h-.023,h+.006,.004)
        B(m,n+" cast iron window frame","dark_green",x,z,.025,size,h,h+.181,.006)
        for k in [-.037,.037]:
            B(m,n+" actual individual panes","window_mill",x+.015,z+k,.011,size*.41,h+.019,h+.149,.004)
        B(m,n+" upper horizontal cross sash","iron_edge",x+.021,z,.013,size*.88,h+.077,h+.092)
    else:
        B(m,n+" masonry sill","dressed",x,z,size+.033,.038,h-.025,h+.005,.003)
        B(m,n+" cast iron window frame","dark_green",x,z,size,.021,h,h+.190,.004)
        for k in [-.040,.040]:
            B(m,n+" actual individual panes","window_muted",x+k,z+.014,size*.40,.013,h+.020,h+.166,.005)
            B(m,n+" narrow sky reflection","glass_light",x+k-.017,z+.023,.010,.005,h+.036,h+.154,.001)
        B(m,n+" upper horizontal cross sash","iron_edge",x,z+.026,size*.90,.010,h+.080,h+.095)


def sign_south(m,n,text,x,z,h,scale=.020):
    B(m,n+" raised metal enclosure","dark_green",x,z,.03+len(text)*scale*6,.037,
      h-scale*.8,h+scale*7.7,.009)
    A.lettering(m,n+" enamel lettering",text,(x,z+.022,h),scale,"south","bone")


def post(m,n,x,z,h=.265):
    B(m,n+" concrete toe","foundation",x,z,.083,.079,.005,.047,.007)
    T(m,n+" enamel iron post","mine_teal",(x,z,.04),(x,z,h),.018,.013,10)
    T(m,n+" ochre safety band","cadmium",(x,z,h-.076),(x,z,h-.048),.019,.017,10)


def weigh(m):
    x0,x1=.046,1.142
    z0,z1=-.409,.102
    B(m,"Weigh office footings","dressed",.596,-.156,1.161,.555,.006,.087,.012)
    block(m,"Weigh office",x0,x1,z0,z1,.075,.590)
    roof(m,"Weigh office",.594,-.155,1.151,.582,.605,.21)
    for x in (.267,.533,.971):window(m,"Weigh office roadside",x,.109,.325,"z",.154)
    B(m,"Freight scale operation hatch","dark_green",.734,.119,.158,.030,.091,.429,.006)
    B(m,"Door top glazing","window_mill",.734,.138,.121,.012,.303,.404,.004)
    B(m,"Weigh house door handle","ochre",.782,.142,.021,.008,.250,.270,.003)
    sign_south(m,"Cedar coal works plaque","CEDAR COAL",.585,.125,.509,.016)
    # Flush weighing tray is genuinely flat; the adjacent public road is
    # not replaced. Both vehicle and station may approach from west.
    B(m,"Flattened iron mine truck weighbridge","iron_dark",.409,.650,1.012,.603,.004,.013,.014)
    for z in (.407,.893):
        B(m,"Flush drainage rib on truck scale","iron",.408,z,.971,.024,.013,.017,.003)
    for x in (-.011,.092,.194,.297,.400,.503,.606,.709,.812):
        B(m,"Mine scale textured nonslip rollers","iron",x,.652,.014,.523,.013,.015)
    for z in (.147,1.169):
        for x in (-.335,.996,1.425):post(m,"Truck entrance bollards",x,z)
    for x in (1.209,1.468):
        B(m,"Roadside gate tripod bases","foundation",x,1.375,.083,.082,.007,.105,.009)
    T(m,"Opened road gate iron arm","mine_teal",(1.245,1.376,.163),
      (1.474,1.376,.497),.016,.014)
    for s in (-1,1):
        z=.644+s*.411
        B(m,"Tall gate approach direction placards","mine_teal",-.366,z,.041,.090,.242,.340,.006)
        B(m,"Gold grit truck-path marks","cadmium",-.390,z,.009,.055,.265,.325,.003)


def belt(m,n,a,b,width=.296):
    ax,az,ah=a
    bx,bz,bh=b
    dx,dz=bx-ax,bz-az
    length=hypot(dx,dz)
    nx,nz=-dz/length,dx/length
    def pin(t,d,y=0):return (ax+dx*t+nx*d,az+dz*t+nz*d,ah+(bh-ah)*t+y)
    for s in (-1,1):
        T(m,n+" continuous steel truss","mine_teal",pin(0,s*width/2,-.036),pin(1,s*width/2,-.036),.022,.022,8)
        T(m,n+" upper belt strakes","iron",pin(0,s*width/2,.035),pin(1,s*width/2,.035),.011,.011,8)
        T(m,n+" lower belt stringer","iron_dark",pin(0,s*width/2,-.111),pin(1,s*width/2,-.111),.016,.016,8)
    F(m,n+" open moving conveyor belt","rubber_coal",[pin(0,-.131),pin(1,-.131),pin(1,.131),pin(0,.131)])
    nbar=max(12,int(length/.055))
    for j in range(nbar+1):
        t=j/nbar
        T(m,n+" belt rib transverse bars","iron_dark",pin(t,-.131,.006),pin(t,.131,.006),.005,.005,6)
    for j in range(max(4,int(length/.18))):
        t=j/max(4,int(length/.18));u=min(1,t+.13)
        for s in (-1,1):
            T(m,n+" visible side diagonals","mine_teal",pin(t,s*width/2,-.110),pin(u,s*width/2,.037),.010,.010,7)
    for t in (.09,.46,.81):
        for s in (-1,1):
            x,z,h=pin(t,s*width*.54,-.109)
            # Place supports only inside the industrial tile being serviced.
            B(m,n+" cast support footing","foundation",x,z,.100,.102,.004,.049,.010)
            T(m,n+" braced trestle legs","mine_teal",(x,z,.041),(x,z,h),.017,.016,9)
    for t in (0,1):
        T(m,n+" end drive roller","iron",pin(t,-width*.63,-.012),pin(t,width*.63,-.012),.045,.045,14)


def mound(m,n,x,z,rx,rz,height,seed):
    rng=Random(seed)
    angles=[2*pi*i/24 for i in range(24)]
    loops=[]
    for step,base in ((1.0,.012),(.77,height*.42),(.46,height*.78),(.19,height*.94)):
        loop=[]
        for i,a in enumerate(angles):
            r=rng.uniform(.79,1.08)
            loop.append((x+rx*cos(a)*step*r,z+rz*sin(a)*step*r,base+rng.uniform(-.008,.020)))
        loops.append(loop)
    for step,(a,b) in enumerate(zip(loops,loops[1:])):
        for i in range(len(a)):
            j=(i+1)%len(a)
            color=COAL[(i*7+step*13)%len(COAL)]
            F(m,n+" jagged layered surfaces",color,[a[i],a[j],b[j],b[i]])
    tip=(x+rx*.07,z+rz*.11,height+.009)
    for i in range(len(angles)):
        j=(i+1)%len(angles)
        F(m,n+" peaked top coal facets",COAL[(i*11)%len(COAL)],[loops[-1][i],loops[-1][j],tip])
    for k in range(130):
        a=rng.random()*2*pi
        r=rng.uniform(.42,1.20)
        px,pz=x+rx*cos(a)*r,z+rz*sin(a)*r
        py=.030+rng.uniform(0,.025)+height*max(0,1-r)*.69
        q=rng.uniform(.009,.045)
        near=[(px+q*cos(i*2*pi/5),pz+q*sin(i*2*pi/5),py-rng.uniform(.005,.013)) for i in range(5)]
        for i in range(5):
            F(m,n+" broken coal lumps",COAL[(i*3+k*7)%len(COAL)],
              [near[i],near[(i+1)%5],(px+.005,pz-.006,py+q*.60)])


def pockets(m):
    # Thin real hopper walls: hold coal in open-topped volumes instead of
    # painting a black patch over a solid lid.
    for x,z in ((2.122,.384),(2.967,.393)):
        for xx in (x-.31,x+.31):
            for zz in (z-.27,z+.27):
                B(m,"Screening bunker cubic pad","foundation",xx,zz,.116,.111,.006,.080,.012)
                T(m,"Screening bin carrying legs","mine_teal",(xx,zz,.07),(xx,zz,1.147),.022,.020,8)
        a=[(x-.220,z-.172,.659),(x+.220,z-.172,.659),(x+.220,z+.172,.659),(x-.220,z+.172,.659)]
        b=[(x-.345,z-.260,1.178),(x+.345,z-.260,1.178),(x+.345,z+.260,1.178),(x-.345,z+.260,1.178)]
        c=[(x+(xx-x)*.91,z+(zz-z)*.91,h-.007) for xx,zz,h in b]
        d=[(x+(xx-x)*.875,z+(zz-z)*.875,h+.032) for xx,zz,h in a]
        for j in range(4):
            k=(j+1)%4
            F(m,"Actual tapered coal bunker external sides","mine_teal",[a[j],a[k],b[k],b[j]])
            F(m,"Actual tapered coal bunker internal sides","iron_dark",[d[j],c[j],c[k],d[k]])
            F(m,"Actual open bunker rim thickness","iron_edge",[b[j],b[k],c[k],c[j]])
            T(m,"Bunker rolled top caps","iron",b[j],b[k],.015,.015,10)
        F(m,"Actual bottoms deep inside open coal bins","rubber_coal",d)
        # Real irregular small coal chunks inside the bins at fill height.
        rng=Random(42+int(10*x))
        for _ in range(136):
            px,pz=x+rng.uniform(-.242,.242),z+rng.uniform(-.166,.166)
            h=rng.uniform(.900,.971)-.061*abs(px-x)
            q=rng.uniform(.009,.034)
            F(m,"Semi-full in-bin coal inventory",rng.choice(COAL),
              [(px-q,pz-q,h),(px+q,pz-q,h+.007),(px+q*.31,pz+q,h+.041),(px-q,pz+q,h+.001)])
        B(m,"Riveted bunker rotary slide gate","iron_dark",x,z,.320,.243,.596,.697,.010)
        B(m,"Bunker slide gate handle","cadmium",x+.173,z,.196,.027,.629,.664,.004)
        T(m,"Bunker discharge chute vertical","mine_teal",(x,z,.429),(x,z,.599),.123,.137,10)
    # Coal sorting/loader assemblies connect physically to the raised skip
    # and open pile. These two belt seams are clipped at stock tile edges.
    belt(m,"Shaft to screen", (2.50,2.041,.973),(2.50,.612,1.298))
    belt(m,"Screen to spoil yard", (2.994,.374,1.283),(4.658,.369,.839))
    belt(m,"Truck charging chute", (1.950,.829,.943),(1.106,.829,.664),.273)
    B(m,"Lower coal chute outlet","rubber_coal",1.084,.830,.236,.300,.574,.682,.014)
    sign_south(m,"Mine loader caution plate","LOAD",1.824,1.295,.154,.017)


def headframe(m):
    # Excavated shaft appearance and cage line. Machinery is genuine depth,
    # with unoccupied space visible between the four tapered steel legs.
    B(m,"Reinforced open shaft corner curb","foundation",2.50,2.49,.719,.689,.005,.064,.014)
    layer(m,"Dark shaft throat interior","soot",2.221,2.778,2.222,2.760,.068)
    for x in (2.20,2.80):
        B(m,"Shaft guard high curb","dressed",x,2.482,.051,.645,.064,.112,.004)
    for z in (2.197,2.776):
        B(m,"Shaft guard high sill","dressed",2.497,z,.573,.042,.064,.112,.004)
    q={}
    for sx in (-1,1):
        for sz in (-1,1):
            marks=[(WIND_X+sx*.477,WIND_Z+sz*.504,.058),
                   (WIND_X+sx*.353,WIND_Z+sz*.369,.775),
                   (WIND_X+sx*.275,WIND_Z+sz*.257,1.325),
                   (WIND_X+sx*.227,WIND_Z+sz*.167,1.923),
                   (WIND_X+sx*.218,WIND_Z+sz*.125,2.326)]
            q[(sx,sz)]=marks
            x,z,_=marks[0]
            B(m,"Heavy octagonal concrete shoe","foundation",x,z,.223,.228,.006,.145,.021)
            B(m,"Raised wrought bolt base","iron",x,z,.142,.150,.135,.182,.013)
            for a,b in zip(marks,marks[1:]):
                T(m,"Tapered mine winding headframe legs","mine_teal",a,b,.046,.034,8)
                T(m,"Lighter headframe leg flange","iron_edge",(a[0]+sx*.035,a[1],a[2]),
                  (b[0]+sx*.030,b[1],b[2]),.012,.010,8)
    c=[(1,1),(-1,1),(-1,-1),(1,-1)]
    for i,a in enumerate(c):
        b=c[(i+1)%4]
        for j,h in enumerate((.77,1.32,1.92)):
            T(m,"Platform perimeter steel beams","iron_dark",q[a][j+1],q[b][j+1],.027,.026,8)
        for j in range(1,4):
            T(m,"Open steel cross-braced X lattice","mine_teal",q[a][j],q[b][j+1],.018,.016,8)
            T(m,"Open steel cross-braced X lattice","mine_teal",q[b][j],q[a][j+1],.017,.016,8)
    for sx in (-1,1):
        B(m,"High split sheave maintenance platform","iron_dark",WIND_X+sx*.333,WIND_Z,
          .214,.438,2.014,2.062,.009)
        x=WIND_X+sx*.423
        for z in (WIND_Z-.179,WIND_Z+.179):
            T(m,"Headgear service railing uprights","iron",(x,z,2.033),(x,z,2.275),.014,.014,8)
        T(m,"Headgear service railing bar","mine_teal",(x,WIND_Z-.213,2.271),
          (x,WIND_Z+.213,2.271),.013,.013,8)
        # Bearing housings don't also rotate. Bearings surround exact X-axis.
        x=WIND_X+sx*.251
        B(m,"Split upper bearing pads","iron_dark",x,WIND_Z,.105,.177,2.272,2.419,.010)
        T(m,"Bearing collar pinned headframe support","iron",(x-.047,WIND_Z,WIND_H),
          (x+.047,WIND_Z,WIND_H),.060,.055,14)
    B(m,"Winding steel headframe crown beam","iron_dark",WIND_X,WIND_Z+.006,.658,.103,2.129,2.205,.007)
    for sx in (-1,1):
        x=2.50+sx*.157
        T(m,"Vertical wire down inside cage shaft","soot",(x,WIND_Z-.252,2.356),(x,2.301,.216),.009,.009,8)
        T(m,"Taut diagonal winding cable across tile join","soot",(x,WIND_Z+.164,2.225),
          (x,4.118,.396),.009,.009,8)
        T(m,"Cage guiding flat steel bar","iron",(x,2.463,.128),(x,2.463,1.046),.015,.015,8)
    B(m,"Carriage cage grating floor","iron_dark",2.50,2.341,.351,.261,.164,.192,.008)
    for x in (2.342,2.661):
        for z in (2.228,2.455):
            T(m,"Suspended steel skip cage bars","cage",(x,z,.178),(x,z,.532),.016,.015,8)
    T(m,"Suspended steel skip cage header","cage",(2.34,2.228,.520),(2.66,2.228,.520),.017,.016,8)
    for j in range(12):
        h=.222+j*.147
        T(m,"Headgear fixed metal ladder rungs","iron_edge",(2.021,2.850,h),
          (2.205,2.850,h),.011,.011,8)
    for x in (2.018,2.210):
        T(m,"Headgear fixed metal ladder legs","iron_dark",(x,2.847,.112),(x,2.847,2.027),.015,.015,8)
    # Decorative safety lantern is fixed outside the highest sheave so
    # clicks or rotation cannot send it through the model.
    B(m,"Winding tower red safety beacon","red",2.749,2.612,.064,.059,2.345,2.411,.010)


def sheaves(m,local=False):
    # The center is the shared visual rotation axle. Geometry of both large
    # circumferences, rims, visible spokes and axle stays mechanically rigid.
    def e(x,z,h):return (x,z,h) if local else (x+WIND_X,z+WIND_Z,h+WIND_H)
    def rod(name,c,a,b,r,s=None,n=10):
        T(m,name,c,e(*a),e(*b),r,s,n)
    rod("Common winding sheave spindle","iron",(-.305,0,0),(.305,0,0),.043,.043,14)
    for x in (-.157,.157):
        rod("Winding wheel inner bearing hubs","oxide",(x-.049,0,0),(x+.050,0,0),.071,.071,18)
        for j in range(28):
            a,b=2*pi*j/28,2*pi*(j+1)/28
            rod("Forged winding wheel outer rims","iron",(x,RIM*cos(a),RIM*sin(a)),
                (x,RIM*cos(b),RIM*sin(b)),.020,.020,7)
            for s in (-1,1):
                rod("Forged wheel rim outer flange","iron_edge",(x+s*.019,(RIM+.006)*cos(a),(RIM+.006)*sin(a)),
                    (x+s*.019,(RIM+.006)*cos(b),(RIM+.006)*sin(b)),.008,.008,6)
        for j in range(7):
            a=2*pi*j/7
            rod("Exposed seven-armed winding spokes","oxide",(x,.066*cos(a),.066*sin(a)),
                (x,.249*cos(a+.053),.249*sin(a+.053)),.022,.016,8)
        rod("Winding wheel axle locking plate","iron_edge",(x-.044,0,0),(x+.048,0,0),.028,.028,14)


def winch_house(m):
    # Holds the line shaft in a roofed but genuinely open rear-to-front bay.
    B(m,"Mine hoist machine-room stone floor","dressed",2.512,4.471,1.432,1.534,.005,.071,.028)
    for x0,x1 in ((1.800,1.987),(3.019,3.205)):
        block(m,"Winding house side",x0,x1,3.759,5.186,.065,.858)
    block(m,"Winding house rear",1.802,3.205,5.043,5.189,.065,.864)
    for x0,x1 in ((1.802,2.100),(2.928,3.202)):
        block(m,"Open-front brick machine-room jamb",x0,x1,3.772,3.905,.066,.858)
    B(m,"Wide open hoist service bay lintel","dressed",2.488,3.818,1.384,.139,.744,.856,.009)
    B(m,"Rolled-up corrugated service bay door","mine_teal",2.497,3.799,.829,.058,.752,.822,.007)
    roof(m,"Winding house engine room",2.497,4.504,1.498,1.536,.864,.303)
    # The worker sees two real drum hoists and reduction gear inside.
    for x in (2.266,2.718):
        B(m,"Raised winch drum foundation","foundation",x,4.288,.383,.457,.072,.204,.015)
        for z in (4.17,4.447):
            T(m,"Rope winch steel cable drum","iron_dark",(x-.167,z,.373),(x+.167,z,.373),.130,.130,24)
            for s in (-1,1):
                T(m,"Rope drum back-fitted flywheel flanges","rail_rust",(x+s*.164,z,.373),
                  (x+s*.180,z,.373),.142,.142,18)
            for j in range(6):
                q=x-.135+j*.051
                T(m,"Wound steel cable drum separators","iron",(q,z,.373),(q+.013,z,.373),.132,.132,16)
        B(m,"Electrical starter enclosure","mine_teal",x,4.766,.193,.249,.078,.472,.015)
        for i in range(4):
            B(m,"Starter enclosure cooling slots","soot",x,4.630,.152,.009,.320+i*.028,.330+i*.028,.004)
    for z in (4.061,4.430,4.792):window(m,"Winding house workshop",3.207,z,.505,"x",.208)
    B(m,"Tall machine-house electric hot vent","mine_teal",2.776,4.718,.072,.081,.958,1.243,.007)
    T(m,"Hot vent peaked cap","iron",(2.776,4.718,1.221),(2.776,4.718,1.248),.067,.050,12)
    sign_south(m,"Open service bay safety plaque","MINE",2.49,5.199,.705,.017)


def rail_loading(m):
    # Separate low rail loading service apron on the *occupied* south-east
    # stock yard tile. Station ownership and player-built track remain
    # outside this footprint. No decorative fake tracks.
    B(m,"Rail freighter loading base","foundation",4.447,4.425,1.011,1.195,.004,.091,.021)
    for x in (3.989,4.855):
        for z in (4.009,4.827):
            T(m,"Rail coal loader structural support legs","mine_teal",(x,z,.078),(x,z,.684),.027,.026,8)
            B(m,"Loading hopper foot cast plate","dressed",x,z,.139,.129,.071,.133,.010)
    box=[(3.908,4.003,.521),(4.923,4.003,.521),(4.923,4.831,.521),(3.908,4.831,.521)]
    ring=[(3.843,3.924,.843),(4.986,3.924,.843),(4.986,4.910,.843),(3.843,4.910,.843)]
    for j in range(4):
        k=(j+1)%4
        F(m,"Rail-side loading bunker panels","iron_dark",[box[j],box[k],ring[k],ring[j]])
        F(m,"Visible interior rail bunker walls","soot",[box[j],ring[j],ring[k],box[k]])
        T(m,"Rail-site load bin top edge","iron",ring[j],ring[k],.022,.022,9)
    layer(m,"Rail bunker interior cargo bed","rubber_coal",3.94,4.88,4.035,4.815,.526)
    B(m,"Rail loading sleeve empty chute","mine_teal",5.122,4.437,.521,.302,.607,.757,.010)
    B(m,"Rail extended chute gate plate","iron_dark",5.351,4.437,.183,.340,.552,.661,.013)
    for z in (3.749,4.004,4.940,5.148):
        post(m,"Open rail apron protective bollards",4.823,z,.251)
    B(m,"Rail scale operating locker","mine_teal",4.027,5.142,.291,.201,.007,.427,.021)
    B(m,"Rail scale warm marker lamp","ochre",4.027,5.142,
      .085,.080,.426,.493,.009)


def yard(m):
    mound(m,"Coal stockpile main tapered body",4.507,.521,.727,.644,.487,1054)
    for z in (-.337,1.404):
        B(m,"Coal yard rear open angular bin restraints","foundation",4.512,z,1.755,.090,.007,.181,.009)
        for x in (3.735,4.116,4.508,4.896,5.281):
            B(m,"Yard spoil block gussets","dressed",x,z,.094,.154,.013,.159,.008)
    B(m,"Yard geared spillage gate","mine_teal",5.313,1.147,.266,.345,.009,.339,.017)
    T(m,"Piling conveyor gearbox shaft","rail_rust",(5.24,1.15,.324),(5.430,1.15,.324),.036,.036,14)


def split(m,x,z,skip=None):
    out=A.mesh();lx,lz=2*x-.5,2*z-.5
    for name,faces in m.parts.items():
        if skip is not None and skip(name):continue
        p=m.vertices[name]
        for ids,col in faces:
            poly=[p[i] for i in ids]
            for axis,at,sign in ((0,lx,1),(0,lx+2,-1),(1,lz,1),(1,lz+2,-1)):
                poly=A.clip(poly,axis,at,sign)
                if not poly:break
            out.face(name,col,[(xx-(lx+1),zz-(lz+1),h) for xx,zz,h in poly])
    return out


def local_entity(m):
    out=A.mesh()
    for n,faces in m.parts.items():
        for ids,c in faces:
            out.face(n,c,[(10*x-.5,10*z-.5,10*h+.5) for x,z,h in (m.vertices[n][i] for i in ids)])
    return out


def atlas():
    def ch(tag,data):
        return struct.pack(">I",len(data))+tag+data+struct.pack(">I",zlib.crc32(tag+data))
    colors=b"".join(bytes.fromhex(v)*8 for v in PAL.values())
    blob=b"\x89PNG\r\n\x1a\n"+ch(b"IHDR",struct.pack(">IIBBBBB",len(PAL)*8,8,8,2,0,0,0))
    blob+=ch(b"IDAT",zlib.compress((b"\0"+colors)*8))+ch(b"IEND",b"")
    (R.TEXTURES/"bl_coal_mine_atlas.png").write_bytes(blob)


def render(scene,path):
    bpy.ops.mesh.primitive_plane_add(size=100,location=(0,0,-.005))
    mat=bpy.data.materials.new("Pasture ash and grass")
    mat.diffuse_color=(.147,.220,.108,1);bpy.context.object.data.materials.append(mat)
    w=bpy.data.worlds.new("Coastal ironworks daylight");w.color=(.40,.47,.55);scene.world=w
    bpy.ops.object.light_add(type="AREA",location=(-5.,-1.1,8.2))
    li=bpy.context.object;li.data.energy=1140;li.data.size=6.6
    li.rotation_euler=(Vector((2.5,2.5,0))-li.location).to_track_quat("-Z","Y").to_euler()
    bpy.ops.object.camera_add(location=(8.58,11.49,9.23))
    cam=bpy.context.object;cam.rotation_euler=(Vector((2.55,2.44,.570))-cam.location).to_track_quat("-Z","Y").to_euler()
    cam.data.type="ORTHO";cam.data.ortho_scale=9.5;scene.camera=cam
    scene.render.engine="BLENDER_EEVEE_NEXT";scene.eevee.taa_render_samples=20
    scene.render.resolution_x=1630;scene.render.resolution_y=1200
    scene.render.resolution_percentage=100;scene.render.filepath=path
    bpy.ops.render.render(write_still=True)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene;scene.name="LuanTTD / Cedar Coal on the exact stock six-tile layout"
    scene.view_settings.view_transform="Standard"
    scene["source_layout"]="OpenTTD 14.1, src/table/build_industry.h, _tile_table_coal_mine_0"
    scene["headgear_axle"]="At stock (1,1) tile center X, Z-.080, +2.395 above deck"
    mats=R.materials()
    for c,i in P.items():
        mat=mats[i];mat.name=c
        node=mat.node_tree.nodes.get("Principled BSDF")
        node.inputs["Roughness"].default_value=.29 if "window" in c or "glazing" in c else .82
        node.inputs["Metallic"].default_value=.45 if c in ("iron","mine_teal","oxide") else .01
    groups=[("Cedar native stock footprint and vehicle frontage",ground),
            ("Scale cabin and real road weighbridge",weigh),("Coal hoist steel headframe and fixed cable",headframe),
            ("Open tipping bins and connected conveyors",pockets),("Coal store and spoil ground",yard),
            ("Actual open machine bay and rope hoists",winch_house),("Rail apron and transfer loader",rail_loading)]
    static=A.mesh()
    for name,fn in groups:
        fn(static)
        g=A.mesh();fn(g)
        col=bpy.data.collections.new(name);scene.collection.children.link(col)
        R.to_blender(g,col,mats)
    sheave=A.mesh();sheaves(sheave,True)
    c=R.stash(sheave,mats,"Open working sheave pair (rotate X)")
    motor=R.instance(scene,c,WIND_X,WIND_Z);motor.location.z=WIND_H
    for x,z,gfx in LAYOUT:
        tile=split(static,x,z)
        if (x,z)==(1,1):
            R.export_obj(R.MODELS/"bl_coal_mine_0_1_1_nosheaves.obj",tile)
            combo=A.mesh()
            for name,fn in groups:fn(combo)
            sheaves(combo,False)
            tile=split(combo,x,z)
        R.export_obj(R.MODELS/f"bl_coal_mine_0_{x}_{z}.obj",tile)
    R.export_obj(R.MODELS/"bl_coal_mine_0_sheaves.obj",local_entity(sheave))
    atlas()
    bpy.ops.wm.save_as_mainfile(filepath=str(R.ROOT/"art/cedar_coal_mine.blend"),compress=True)
    if os.environ.get("COAL_MINE_RENDER"):render(scene,os.environ["COAL_MINE_RENDER"])


if __name__=="__main__":main()

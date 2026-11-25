"""Build original editable Temperate town landmarks; no upstream sprite pixels.

blender -b -t 2 --python-exit-code 1 --python tools/build_stock_town_art.py
STOCK_TOWN_REVIEW=output.png renders an orthographic contact sheet after export.
"""
import os
import sys
from math import ceil, cos, sin, pi, sqrt
from pathlib import Path
from random import Random
import bpy
import bmesh
from mathutils import Matrix, Vector
sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_scenery_art import COLORS, ROOT, beam, box, bulbs, chimney, frontdoor, gable, hip, init, mesh, pane, tapered
from build_town_props import text_plate, striped_awning


def plot(color="stone"):
    box("Parcel and retaining edge", (0,0,.018), (1.88,1.88,.036), color)


def walk(x,y,w,d):
    for i in range(max(1,round(d/.12))):
        n=max(1,round(d/.12))
        box("Setts in contrasting courses",(x,y+(i+.5)*d/n-d/2,.041),(w,d/n-.006,.013),
            "pale stone" if i%3==0 else "warm limestone")


def tree(x,y,h, tones=("foliage dark","foliage","foliage sun")):
    tapered("Tree trunk",(x,y,.03),(x+.013,y,h*.68),h*.052,h*.028,7,"cedar")
    for i in range(7):
        a=i*2.4
        dx,dy=.15*h*cos(a),.15*h*sin(a)
        z=h*(.56+.065*i)
        if i<4:
            tapered("Tree fork",(x,y,h*.37),(x+dx,y+dy,z),h*.018,h*.009,5,"cedar")
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=1,location=(x+dx,y+dy,z))
        o=bpy.context.object
        from build_scenery_art import MATS
        o.name="Individually shaped foliage crown"
        o.scale=(h*(.23+.022*(i%3)),h*.21,h*.24)
        o.data.materials.append(MATS[tones[i%len(tones)]])


def bench(x,y):
    for a in (-.105,.105):
        box("Cast iron bench leg",(x+a,y,.09),(.027,.11,.123),"dark metal")
        beam("Bench back standard",(x+a,y+.041,.08),(x+a,y+.074,.235),.016,.018,"dark metal")
    for a in (-1,0,1):
        box("Bench seat slat",(x,y+a*.032,.149),(.29,.025,.019),"sapwood")
    for a in (0,1):
        box("Bench backrest slat",(x,y+.072,.190+.039*a),(.29,.021,.025),"cedar")


def lamp(x,y):
    tapered("Cast iron street lamp shaft",(x,y,.044),(x,y,.46),.023,.012,8,"dark metal")
    tapered("Lantern foot",(x,y,.448),(x,y,.474),.022,.035,6,"black")
    tapered("Lantern glazing",(x,y,.474),(x,y,.531),.035,.026,6,"cream")
    tapered("Lantern crown",(x,y,.53),(x,y,.57),.042,.003,6,"dark metal")


def arch_window(x,y,z,w,h):
    # Radial masonry voussoirs surround a Gothic pointed glazed opening.
    box("Window stone apron",(x,y-.016,z-h*.52),(w+.07,.048,.037),"warm limestone")
    box("Window glass below arch",(x,y-.022,z-h*.12),(w,.036,h*.76),"glazing")
    for sign in (-1,1):
        box("Window jamb",(x+sign*(w/2+.014),y-.026,z-h*.09),(.027,.043,h*.86),"pale stone")
        last=(x+sign*w*.54,y-.026,z+h*.32)
        for i in range(1,5):
            f=i/4
            p=(x+sign*w*.54*(1-f),y-.026,z+h*(.32+.44*sin(f*pi*.5)))
            beam("Pointed arch limestone block",last,p,.030,.038,"pale stone" if i%2 else "warm limestone")
            last=p
    box("Lancet lead came",(x,y-.046,z-.05),(.010,.012,h*.90),"light metal")


def church():
    plot("sage"); walk(0,-.78,.34,.24)
    box("Historic sandstone nave",(0,.20,.39),(1.21,1.20,.70),"warm limestone")
    gable("Slate nave",0,.20,1.21,1.20,.74,1.08,"warm limestone","slate","pale stone",7)
    box("Bell tower stone shaft",(0,-.48,.67),(.50,.47,1.29),"stone")
    for i in (.31,.79,1.23):
        box("Tower dressed limestone stringcourse",(0,-.48,i),(.55,.52,.038),"pale stone")
    for x in (-.25,.25):
        box("Tower edge quoins",(x,-.70,.67),(.073,.069,1.18),"warm limestone")
    for q in (-1,1):
        arch_window(q*.44,-.421,.38,.139,.23)
        for y in (.11,.49):
            box("Side buttress foundation",(q*.623,y,.073),(.18,.15,.13),"stone")
            box("Tapering nave buttress",(q*.622,y,.31),(.112,.11,.48),"pale stone")
            pane("Nave stained glass",q*.606,y+.06,.53,.131,.267,"left" if q<0 else "right","warm limestone")
    arch_window(0,-.716,1.04,.17,.19)
    frontdoor(0,-.718,.37,"stone")
    tapered("Octagonal belfry roof",(0,-.48,1.32),(0,-.48,1.90),.344,.008,8,"slate")
    beam("Cast iron finial upright",(0,-.48,1.86),(0,-.48,2.03),.024,.023,"dark metal")
    beam("Cast iron finial crossbar",(-.059,-.48,1.975),(.059,-.48,1.975),.022,.024,"dark metal")
    for x in (-.76,.76):
        box("Boundary hedge",(x,.06,.11),(.17,1.42,.20),"hedge")
    tree(-.71,.7,.48); tree(.70,.64,.45)


def flats():
    plot("sage"); walk(0,-.79,.27,.25)
    box("Interwar apartment massing",(0,.104,.765),(1.39,1.31,1.47),"brick")
    box("Centre rendered stair bay",(0,-.566,.786),(.344,.115,1.52),"plaster")
    box("Projecting brick utility wing",(.48,.717,.56),(.53,.24,1.05),"brick bright")
    for z in (.12,.53,.91,1.30,1.485):
        box("Front masonry stringcourse",(0,-.567,z),(1.43,.063,.034),"warm limestone")
    for x in (-.496,-.250,.250,.496):
        for z in (.34,.725,1.102,1.38):
            pane("Apartment casement",x,-.55,z,.139,.163,f="warm limestone")
    for q in (-1,1):
        for y in (-.25,.19,.57):
            for z in (.33,.72,1.11,1.38):
                pane("End elevation casement",q*.695,y,z,.149,.16,"left" if q<0 else "right","cream")
    for z in (.63,.96,1.29):
        pane("Common stair landing window",0,-.63,z,.160,.215,f="teal",divisions=3)
    for x in (-.40,.40):
        box("Balcony garden retaining wall",(x,-.717,.113),(.32,.196,.16),"warm limestone")
        box("Balcony garden plantings",(x,-.717,.198),(.28,.15,.07),"foliage sun")
    frontdoor(0,-.633,.30,"plaster")
    hip("Plain tile apartment roof",0,.105,1.41,1.34,1.52,1.79,"terracotta")
    chimney(.37,.42,1.66,.13)


def theater():
    plot();walk(0,-.832,1.42,.159)
    box("Theater auditorium volume",(0,.28,.54),(1.47,1.11,1.022),"brick")
    gable("Theater auditorium",0,.28,1.47,1.11,1.052,1.22,"brick","slate","slate",4)
    box("Beaux arts entrance",(0,-.443,.541),(1.32,.403,1.03),"plaster")
    box("Central upper stone cornice",(0,-.443,1.089),(1.38,.476,.064),"warm limestone")
    box("Center parapet behind sign",(0,-.46,1.165),(.94,.35,.13),"warm limestone")
    for x in (-.544,-.28,.28,.544):
        box("Fluted facade pilaster",(x,-.673,.61),(.066,.085,.89),"pale stone")
        for dx in (-.018,0,.018):
            box("Front pilaster flute",(x+dx,-.720,.62),(.008,.013,.802),"warm limestone")
        box("Pilaster capital",(x,-.67,1.041),(.106,.102,.059),"cream")
    for x in (-.411,0,.411):
        arch_window(x,-.652,.789,.16,.21)
    for x in (-.224,0,.224):
        frontdoor(x,-.655,.305,"plaster")
    box("Maroon canopy hidden structure",(0,-.752,.405),(1.16,.286,.061),"burgundy")
    box("Reflective canopy trim",(0,-.903,.401),(1.159,.023,.043),"gold")
    box("Theater engraved lettering backing",(0,-.651,1.18),(.74,.034,.094),"burgundy")
    text_plate("Raised theater name","THEATRE",0,-.674,1.173,.104,"cream")
    for x in (-.86,.86):
        lamp(x,-.72)


def cinema():
    plot();walk(0,-.825,1.42,.19)
    box("Plain brick screen hall",(.06,.28,.68),(1.49,1.20,1.30),"brick bright")
    box("Asymmetric curved-era entrance massing",(0,-.44,.53),(1.45,.45,1.0),"warm limestone")
    box("Stepped upper fin",(-.47,-.46,1.02),(.35,.56,1.98),"cream board")
    box("Sculpted top step",(-.64,-.44,1.06),(.14,.51,1.60),"plaster")
    box("Box-office bay",(.25,-.666,.244),(.33,.111,.40),"teal")
    pane("Box office counter",.25,-.732,.303,.218,.157,f="cream")
    for x in (-.20,.013,.556):
        frontdoor(x,-.675,.296,"plaster")
    box("Blue art deco marquee",(.14,-.794,.467),(1.18,.25,.079),"teal")
    for z in (.438,.47,.50,.69,.79,.90):
        box("Stepped horizontal stainless strip",(.137,-.686 if z>.51 else -.927,z),(1.175,.028,.014),"light metal")
    box("Blue neon letter support",(-.47,-.766,1.17),(.137,.033,.81),"teal")
    for i,c in enumerate("CINEMA"):
        text_plate("Porcelain enamel letter "+c,c,-.47,-.787,1.51-i*.127,.118,"cream")
    box("Flat roof weather coping",(.16,.28,1.339),(1.29,1.24,.039),"plaster")
    box("Roof ventilation tower",(.36,.39,1.41),(.30,.21,.147),"metal")


def park_square():
    plot("soil shade")
    for i in (-1,1):
        for j in (-1,1):
            box("Raised square grass parterre",(i*.471,j*.471,.049),(.64,.64,.05),"mint")
            for k in (-1,1):
                box("Clipped formal hedge",(i*.471+k*.291,j*.471,.16),(.11,.652,.18),"hedge")
                box("Clipped formal hedge",(i*.471,j*.471+k*.29,.16),(.652,.11,.18),"foliage")
            bulbs(i*.49,j*.48,Random(i*j))
    walk(0,0,.23,1.84)
    for x in (-.62,-.32,.32,.62):
        box("Central crosswalk setts",(x,0,.044),(.275,.238,.018),"warm limestone")
    for x in (-.52,.52):
        bench(x,.15);lamp(x,.83)
    tree(-.49,.49,.63);tree(.49,-.49,.65)


def park_grove():
    plot("sage")
    for i in range(13):
        y=-.88+(i+.5)*.135
        x=.34*sin(y*2.1)
        a=box("Winding gravel walkway",(x,y,.047),(.253,.161,.021),"trail")
        a.rotation_euler.z=-.5*cos(y*2.1)
    for x,y,h in ((-.53,.56,.88),(.52,-.47,.8),(-.56,-.15,.71),(.63,.25,.58),(.3,.67,.52)):
        tree(x,y,h)
    for x,y in ((-.38,-.60),(.48,.52),(.67,-.1),(-.63,.1)):
        bulbs(x,y,Random(abs(x)))
    bench(.37,-.03);bench(-.43,.52)
    lamp(-.60,-.78);lamp(.62,.76)

def façade_side(x,y,w,d,z,height,tw=3,cols=4,trim="pale stone"):
    for i in range(tw):
        yy=y+(i+.5-tw/2)*d/tw
        for j in range(cols):
            zz=z+(j+.5)*height/cols
            pane("Side facade casement",x,yy,zz,min(.20,d/tw*.65),min(.22,height/cols*.65),
                 "left" if x<0 else "right",trim,divisions=1)


def office(*,tone,trim,style,floors,width,depth,wings=False):
    plot(); walk(0,-.817,.39,.217)
    front=-depth/2+.093
    cy=.093
    base=.221
    ft=.241 if floors>6 else .29
    top=base+ft*floors
    box("Office podium",(0,cy,.127),(min(width+.18,1.72),depth+.135,.195),tone)
    if style=="pavilion":
        for x in (-.72,.72):
            box("Raised glazed side lobby",(x,-.04,.337),(.25,1.38,.61),"blue board")
            for y in (-.47,-.16,.17,.47):
                pane("Lobby wing glass",x+(.125 if x>0 else -.125),y,.345,.165,.333,
                     "left" if x<0 else "right","teal",divisions=2)
    box("Office primary volume",(0,cy,(base+top)*.5),(width,depth,top-base),tone)
    bays=5 if floors>5 else 4
    for j in range(floors):
        zz=base+ft*(j+.5)
        if style in ("bands","pavilion","terrace"):
            box("Projecting floor slab",(0,cy,zz-ft*.406),(width+.067,depth+.075,.039),trim)
        if style=="bands":
            box("Continuous ribbon facade glazing",(0,front-.019,zz),(width*.93,.053,.13),"glazing")
            for i in range(bays+1):
                x=(i-bays*.5)*width*.92/bays
                box("Ribbon window aluminium mullion",(x,front-.050,zz),(.014,.018,.127),trim)
                if i<bays:
                    box("Glazing sky band",(x+width*.46/bays,front-.047,zz+.041),(width*.86/bays,.013,.026),"reflection")
        else:
            for i in range(bays):
                x=(i+.5-bays/2)*width*.91/bays
                pane("Office glazing",x,front,zz,.148 if bays==5 else .177,.135,f=trim,divisions=1 if j%3 else 2)
    for x in (-width/2,width/2):
        façade_side(x,cy,width,depth,base,top-base,3,min(6,floors),trim)
    if style=="pilasters":
        for i in range(bays+1):
            x=(i-bays/2)*width*.89/bays
            box("Vertical decorative facade rib",(x,front-.045,(top+base)*.5),(.032,.048,top-base),trim)
        box("Setback capital",(0,cy,top+.105),(width*.77,depth*.74,.19),tone)
        box("Inset penthouse roof cap",(0,cy,top+.214),(width*.83,depth*.79,.045),trim)
    elif style=="terrace":
        box("Recessed penthouse mass",(width*.19,.15,top+.117),(width*.45,depth*.74,.224),trim)
        for x in (-.41,-.24,-.07):
            box("Roof terrace planted trough",(x,-.19,top+.043),(.122,.247,.08),"terracotta")
            box("Roof terrace shrubs",(x,-.19,top+.112),(.103,.211,.076),"hedge")
        for y in (-.34,.49):
            box("Roof terrace safety glass",(-width*.26,y,top+.093),(width*.42,.026,.13),"reflection")
    elif style=="bands":
        box("Tall glazed crown inset",(0,cy+.18,top+.116),(width*.59,depth*.62,.213),"glazing")
        for x in (-.208,0,.208):
            box("Crown mullion",(x,cy-depth*.31+.166,top+.13),(.019,.025,.197),"light metal")
    else:
        box("Roof plant room",(.31,cy+.16,top+.105),(.32,.33,.193),"slate")
    box("Perimeter roof coping",(0,cy,top+.021),(width+.107,depth+.103,.047),trim)
    box("Strip of entrance plinth",(0,front-.045,.055),(.72,.235,.061),trim)
    for x in (-.10,.10):
        box("Entrance bronze framing",(x,front-.095,.165),(.17,.036,.23),"gold")
        box("Entrance glazing",(x,front-.119,.17),(.151,.021,.18),"glazing")
    box("Street canopy",(0,front-.204,.292),(.63,.328,.058),trim)
    if wings:
        for x in (-.60,.60):
            box("Street-level landscaped planter",(x,-.69,.087),(.32,.29,.101),"stone")
            box("Street-level clipped shrubs",(x,-.69,.168),(.284,.26,.092),"foliage")
    lamp(.811,-.765)


def lift_office():
    # OpenGFX's gateway is a visual reference only. Build an original
    # brushed steel exterior lift on the right-hand side of a period office.
    office(tone="reflection",trim="light metal",style="bands",floors=6,width=1.54,depth=1.37,wings=False)
    x,y=.54,-.780
    box("Indigo enamel lift shaft backing",(x,y+.080,1.085),(.302,.047,1.927),"slate")
    for dx in (-.158,.158):
        box("Full-height shaft exterior column",(x+dx,y+.002,1.089),(.039,.154,1.949),"light metal")
        box("Continuous lift guide rail",(x+dx*.72,y-.035,1.087),(.014,.017,1.912),"metal")
        box("Concrete lift footing",(x+dx,y,.083),(.088,.184,.119),"warm limestone")
    for floor in (0,2,3,4,5,6):
        zz=.104+floor*6*.0475
        box("Floor sill", (x,y-.058,zz),(.306,.035,.017),"light metal")
        box("Landing call lamp", (x+.134,y-.078,zz+.101),(.014,.009,.024),"gold")
    box("Lift crown frame",(x,y,2.112),(.382,.231,.103),"slate")
    box("Lift motor enclosure",(x,y+.020,2.180),(.270,.172,.083),"metal")
    box("Polished crown flashing",(x,y-.008,2.174),(.391,.239,.019),"light metal")
    box("Elevator approach paving",(x,y-.124,.045),(.390,.188,.033),"warm limestone")


def lift_cab():
    # Translated vertically as a separate original mesh on the same native
    # anchor as the supporting office. Nothing else is animated.
    x,y,z=.54,-.781,.225
    box("Cabinet chassis", (x,y,z-.083),(.220,.104,.027),"metal")
    box("Warm cabin", (x,y,z),(.212,.088,.155),"pale stone")
    box("Sliding doors", (x,y-.049,z-.006),(.177,.018,.132),"light metal")
    box("Door joint", (x,y-.059,z-.006),(.008,.003,.131),"metal")
    for dx in (-.055,.055):
        box("Blue cab viewing glass", (x+dx,y-.060,z+.025),(.062,.005,.044),"glazing")
        box("Cab viewing glass reflection", (x+dx,y-.064,z+.034),(.058,.003,.011),"reflection")
    box("Cab top clamp", (x,y,z+.086),(.233,.104,.020),"metal")
    box("Amber car lamp", (x,y-.063,z+.078),(.070,.008,.011),"gold")


def apartments(*,width,body,roof,balconies):
    plot("sage"); walk(0,-.777,.34,.23)
    depth=1.10;front=-depth/2+.11
    h=.99 if not balconies else 1.17
    box("Three-storey flatted residences",(0,.11,h*.5+.037),(width,depth,h),body)
    for j in range(3):
        z=(j+.53)*h/3+.062
        for x in (-.40,0,.40):
            pane("Domestic double sash",x,front,z,.18,.166,f="cream",divisions=2)
            if balconies and x!=0 and j>0:
                box("Concrete balcony deck",(x,front-.12,z-.11),(.345,.266,.043),"warm limestone")
                for dx in (-.135,-.045,.045,.135):
                    box("Balcony iron stanchion",(x+dx,front-.242,z-.045),(.013,.015,.093),"dark metal")
                box("Balcony top rail",(x,front-.241,z+.011),(.334,.026,.023),"dark metal")
                box("Window flower box",(x,front-.24,z-.09),(.143,.06,.044),"terracotta")
                box("Flowering geraniums",(x,front-.24,z-.054),(.12,.045,.042),"foliage sun")
        box("Masonry floor moulding",(0,front-.012,z-.125),(width+.04,.054,.032),"warm limestone")
    for q in (-1,1):
        façade_side(q*width/2,.11,width,depth,.03,h,3,3)
    hip("Domestic hipped tile roof",0,.11,width,depth,h+.035,h+.28,roof)
    chimney(-.25,.32,h+.20,.115,tone_for_chimney(body))
    frontdoor(0,front-.018,.235,body)
    tree(.66,-.67,.39)


def tone_for_chimney(tone):
    return "brick" if tone in ("terracotta","brick","brick bright") else "warm limestone"


def main_street(*,tone,roof,sign,narrow=False,tall=False,awning=("burgundy","cream")):
    plot(); walk(0,-.825,1.77,.17)
    front=-.605
    height=1.43 if tall else (1.03 if narrow else 1.20)
    rows=4 if tall else 3
    for n,(x,w) in enumerate(((-.46,.59),(.295,.9))):
        body=tone if n else "plaster" if tone!="plaster" else "brick"
        box(("Left" if n==0 else "Right")+" mixed-use frontage",(x,.078,height*.5),(w,1.35,height),body)
        if narrow or n==0:
            gable("Street gabled attic",x,.078,w,1.35,height,height+.23,body,roof,"pale stone",4)
        else:
            box("Deep shop parapet",(x,.078,height+.052),(w+.071,1.425,.13),"warm limestone")
        for j in range(1,rows):
            z=.24+j*(height-.28)/rows
            box("Commercial upper facade molding",(x,front-.022,z-.136),(w+.034,.043,.024),"warm limestone")
            for dx in (-.17,.139) if w<.7 else (-.27,0,.27):
                pane("Upper occupied casement",x+dx,front,z,.12,.131,f="cream",divisions=2)
        frontdoor(x-w*.30,front-.012,.263,body)
        center=x+w*.15
        pane("Street shop display",center,front-.028,.222,w*.49,.199,f="teal",divisions=3)
        striped_awning("Canvas shop blind",center,front-.047,front-.270,w*.65,.401,.348,awning,7,True)
        for q in (-1,1):
            box("Shop iron sign bracket",(x+q*w*.33,front-.043,.469),(.019,.093,.085),"dark metal")
        box("Shop fascia plaque",(x,front-.045,.463),(w*.71,.04,.066),"slate")
        text_plate("Raised shop name",sign[n],x,front-.067,.459,.069,"cream")
        chimney(x+.122,.50,height+.03,.205,"brick")
    façade_side(.746,.075,.90,1.35,.19,height-.21,4,rows-1)
    façade_side(-.755,.075,.59,1.35,.19,height-.21,4,rows-1)
    lamp(.851,-.74)


def warehouse():
    plot("stone")
    box("Masonry industrial shell",(.095,.19,.451),(1.49,1.30,.825),"brick")
    gable("Warehouse zinc roof",.095,.19,1.49,1.30,.86,1.13,"brick","slate","slate",8)
    box("Low loading platform",(.065,-.591,.093),(1.453,.299,.117),"stone")
    box("Truck bump strip",(.065,-.751,.09),(1.39,.071,.052),"black")
    for x in (-.409,.072,.553):
        box("Loading door jamb",(x,-.478,.326),(.391,.073,.438),"warm limestone")
        box("Roll-up loading door",(x,-.526,.326),(.333,.052,.362),"blue board")
        for j in range(9):
            box("Loading door rolled seam",(x,-.553,.151+j*.041),(.331,.013,.010),"metal")
        pane("Upper workshop glass",x,-.47,.673,.252,.151,f="plaster",divisions=3)
        for t in (-1,1):
            box("Dock bumper",(x+t*.183,-.762,.127),(.062,.043,.049),"dark metal")
    for y in (-.25,.07,.39,.68):
        pane("Side factory light",.839,y,.633,.20,.163,"right","plaster",divisions=3)
    box("Electric service meter and conduit",(-.701,-.414,.362),(.12,.111,.215),"teal")
    lamp(-.806,-.76)


def statue():
    plot("stone");walk(0,-.596,.54,.541)
    for z,w in ((.058,1.21),(.119,.95),(.179,.72)):
        box("Monument stepped pedestal",(0,.065,z),(w,w,.057),"pale stone" if z!=.119 else "warm limestone")
    box("Carved monument die",(0,.065,.362),(.522,.529,.365),"stone")
    box("Stone capital ledge",(0,.065,.554),(.608,.612,.056),"warm limestone")
    box("Engraved dedication back",(0,-.210,.386),(.317,.023,.181),"dark metal")
    text_plate("Dedication inscription","1918",0,-.226,.38,.142,"gold")
    bronze="teal"
    for x in (-.064,.058):
        tapered("Bronze boot to coat hem",(x,.061,.58),(x,.069,.816),.041,.048,8,bronze)
    tapered("Bronze coat",(0,.083,.765),(0,.083,1.019),.073,.102,8,bronze)
    tapered("Bronze collar",(0,.083,.994),(0,.083,1.062),.08,.042,8,"pine dark")
    tapered("Bronze neck",(0,.074,1.036),(0,.070,1.101),.035,.038,8,bronze)
    tapered("Bronze bust head",(0,.06,1.078),(0,.06,1.199),.052,.052,10,bronze)
    tapered("Broad-brim hat",(0,.06,1.181),(0,.06,1.212),.086,.044,10,"pine dark")
    for sign in (-1,1):
        tapered("Bronze upper sleeve",(sign*.078,.082,1),(sign*.133,.026,.914),.042,.041,8,bronze)
        tapered("Bronze forearm",(sign*.133,.026,.914),(sign*.096,-.057,.901+sign*.047),.038,.023,8,bronze)
        for y in (-.55,.58):
            bulbs(sign*.715,y,Random(9))
        bench(sign*.58,.69)


def fountain():
    plot("stone")
    tapered("Outer basin foot",(0,0,.025),(0,0,.105),.692,.65,16,"warm limestone")
    tapered("Turquoise water surface",(0,0,.115),(0,0,.130),.59,.59,32,"water")
    for i in range(24):
        a,b=i*2*pi/24,(i+1)*2*pi/24
        p=lambda t:(.633*cos(t),.633*sin(t),.165)
        beam("Individually dressed basin coping",p(a+.007),p(b-.007),.11,.138,"pale stone")
    for z,a,b,h,s in ((.124,.208,.150,.083,10),(.20,.107,.079,.155,8),(.345,.248,.331,.089,16),
                      (.43,.105,.063,.238,10),(.65,.158,.199,.077,14),(.72,.067,.034,.14,8)):
        tapered("Carved fountain tiers",(0,0,z),(0,0,z+h),a,b,s,"stone" if s<12 else "pale stone")
    for i in range(5):
        a=i*2*pi/5+.24
        last=(0,0,.829)
        for j in range(1,9):
            f=j/8
            p=(.367*f*cos(a),.367*f*sin(a),.834+.226*f-.79*f*f)
            beam("Fine arcing jet",last,p,.012,.012,"reflection")
            last=p
    for x in (-.73,.73):
        for y in (-.76,.76):
            box("Flowers in square urn",(x,y,.104),(.231,.216,.149),"terracotta")
            bulbs(x,y,Random(8))


FIRST={0x03:("church",church),0x0B:("grove_park",park_grove),0x0C:("formal_park",park_square),
       0x1B:("flats",flats),0x1F:("theater",theater),0x27:("cinema",cinema)}
SECOND={
    0x00:("tall_office_block",lambda:office(tone="plaster",trim="warm limestone",style="pilasters",floors=9,width=1.35,depth=1.25,wings=True)),
    0x01:("office_block",lambda:office(tone="brick bright",trim="pale stone",style="terrace",floors=4,width=1.48,depth=1.27)),
    0x02:("small_block_of_flats",lambda:apartments(width=1.39,body="plaster",roof="terracotta",balconies=True)),
    0x04:("large_office_block",lift_office),
    0x09:("statue",statue),0x0A:("fountain",fountain),
    0x0D:("office_block_stone",lambda:office(tone="warm limestone",trim="cream",style="pilasters",floors=5,width=1.50,depth=1.38)),
    0x0F:("shop_pastry",lambda:main_street(tone="burgundy",roof="slate",sign=("FLORIST","BAKERY"),narrow=True,awning=("teal","cream"))),
    0x10:("shop_books",lambda:main_street(tone="cream board",roof="shingle",sign=("BOOKS","TEA ROOM"),awning=("terracotta","cream","cream"))),
    0x11:("modern_office",lambda:office(tone="warm limestone",trim="teal",style="pavilion",floors=6,width=1.12,depth=1.40)),
    0x12:("warehouse",warehouse),
    0x13:("office_block_ceramic",lambda:office(tone="blue board",trim="cream board",style="terrace",floors=5,width=1.54,depth=1.18,wings=True)),
    0x1C:("tall_office_glazed",lambda:office(tone="blue board",trim="slate",style="bands",floors=8,width=1.30,depth=1.38)),
    0x1D:("shop_outfitters",lambda:main_street(tone="brick",roof="slate",sign=("TAILOR","OUTFITTERS"),narrow=True,tall=True)),
    0x1E:("shop_broadway",lambda:main_street(tone="blue board",roof="terracotta",sign=("PHOTO","RECORDS"),tall=True,awning=("teal","cream","teal"))),
    0x24:("offices",lambda:office(tone="plaster",trim="light metal",style="terrace",floors=7,width=1.55,depth=1.34)),
}

MULTI_SIZE={0x07:(1,2),0x14:(2,2),0x20:(2,2),0x28:(2,2)}


def big_plot(w,d,color):
    box("Full landmark foundation",(w-1,-(d-1),.019),(w*2-.083,d*2-.083,.038),color)


def hotel():
    big_plot(1,2,"sage")
    walk(0,-2.72,.64,.41)
    box("Two-tile hotel masonry base",(0,-.99,.147),(1.60,2.92,.241),"stone")
    box("Guest room wing",(0,-.94,1.065),(1.32,2.61,1.75),"plaster")
    for q in (-1,1):
        for j in range(5):
            y=-1.99+j*.50
            for n in range(5):
                pane("Guest window",q*.66,y,.453+n*.305,.22,.172,"left" if q<0 else "right","pale stone",divisions=2)
        box("Hotel facade stringcourse",(q*.67,-.94,.289),(.068,2.61,.051),"pale stone")
    cy=-2.25
    for i in (-1,1):
        box("Street entrance stone column",(i*.47,-2.47,.295),(.11,.11,.437),"stone")
        box("Entrance stone capital",(i*.47,-2.47,.501),(.137,.147,.049),"warm limestone")
    box("Hotel canopy",(0,-2.415,.564),(1.165,.583,.08),"slate")
    box("Brass fascia",(0,-2.713,.574),(1.067,.027,.071),"burgundy")
    text_plate("Hotel lettering","HOTEL",0,-2.731,.57,.082,"cream")
    for x in (-.202,0,.202):
        pane("Hotel main entrance",x,cy,.306,.16,.331,f="cream")
    for i in (1,2,3,4):
        for x in (-.424,0,.424):
            pane("End facade bedroom",x,cy,.54+i*.3,.20,.182,f="warm limestone")
    hip("Long patinated roof",0,-.945,1.32,2.61,1.94,2.22,"slate")
    chimney(.333,-.42,2.045,.175)
    lamp(-.81,-2.52);lamp(.81,-2.52)
    for x in (-.816,.816):
        box("Hotel entrance planted border",(x,-1.83,.13),(.194,1.04,.17),"foliage")


def rectangular_stadium():
    big_plot(2,2,"stone")
    cx,cy=1,-1
    box("Football pitch grass",(cx,cy,.06),(2.76,1.62,.047),"mint")
    for i in range(10):
        box("Alternating cut pitch grass",(cx-1.20+i*.267,cy,.084),(.266,1.60,.007),"foliage sun" if i%2 else "mint")
    for q in (-1,1):
        box("White touchline",(cx,cy+q*.764,.093),(2.56,.022,.008),"white")
        box("White goal line",(cx+q*1.267,cy,.093),(.022,1.53,.008),"white")
        for d in (-1,1):
            box("Penalty area horizontal line",(cx+q*1.114,cy+d*.407,.093),(.319,.017,.007),"white")
        box("Penalty area vertical line",(cx+q*.956,cy,.093),(.015,.813,.007),"white")
        for d in (-1,1):
            xx,yy=cx+q*1.28,cy+d*.234
            tapered("Goal upright",(xx,yy,.086),(xx,yy,.20),.013,.013,6,"white")
            beam("Net back stay",(xx,yy,.189),(xx+q*.095,yy,.095),.013,.013,"light metal")
        box("Goal crossbar",(cx+q*1.28,cy,.20),(.022,.491,.022),"white")
    box("Halfway line",(cx,cy,.093),(.022,1.53,.008),"white")
    torus_mark("Centre circle",cx,cy,.321,.019,.094)
    for q in (-1,1):
        for n in range(4):
            z=.103+n*.107;y=cy+q*(.95+n*.153)
            box("Concrete grandstand riser",(cx,y,z),(3.65,.169,.153),"stone")
            box("Continuous color seating",(cx,y,z+.082),(3.55,.091,.035),"teal" if q<0 else "burgundy")
            for x in (-.35,.31,1.69,2.35):
                box("Seat aisle stepped profile",(x,y,z+.085),(.088,.173,.038),"pale stone")
        y=cy+q*1.45
        for x in (-.58,.42,1.58,2.58):
            box("Canopy stanchion",(x,y,.364),(.039,.053,.68),"dark metal")
        canopy=box("Grandstand shade canopy",(cx,y,.731),(3.65,.72,.083),"slate")
        canopy.rotation_euler.x=q*.13
    for x in (-.68,2.68):
        for y in (-2.55,.55):
            lamp(x,y)
    station_entry("FOOTBALL",cx,-2.893)


def torus_mark(name,x,y,r,width,z,sy=1):
    for i in range(32):
        a,b=i*pi/16,(i+1)*pi/16
        begin=(x+r*cos(a),y+r*sy*sin(a),z)
        end=(x+r*cos(b),y+r*sy*sin(b),z)
        beam(name,begin,end,width,.008,"white")


def station_entry(name,x,y):
    box("Street ticket entrance blocks",(x,y+.117,.216),(.71,.221,.364),"plaster")
    for q in (-1,1):
        pane("Entry ticket windows",x+q*.176,y+.013,.194,.215,.177,f="metal",divisions=2)
    box("Entry roof coping",(x,y+.113,.421),(.84,.254,.049),"slate")
    box("Enamel name board",(x,y-.015,.371),(.594,.028,.09),"teal")
    sign=text_plate("Raised venue name",name,x,y-.033,.367,.077,"cream")
    sign["luanti_front_text"]=name


def oval_stadium():
    big_plot(2,2,"stone")
    x,y=1,-1
    def ring(name,r1,r2,z,height,material,ellipse=1.10):
        for i in range(32):
            a,b=i*pi/16,(i+1)*pi/16
            vs=[(x+r*cos(t),y+r*ellipse*sin(t),top)
                for top in (z,z+height) for r,t in [(r1,a),(r2,a),(r2,b),(r1,b)]]
            mesh(name,vs,((3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)),material)
    ring("Terracotta running track",.975,1.375,.045,.044,"terracotta")
    tapered("Oval central infield",(x,y,.05),(x,y,.091),1.08,1.08,32,"mint")
    for r in (1.02,1.10,1.18,1.26,1.34): torus_mark("Full athletics line",x,y,r,.009,.102,1.10)
    for n in range(5):
        r=1.382+n*.074
        ring("Oval athletic seating",r,r+.077,.110+n*.096,.095,"blue board" if n%2 else "slate",1.066)
    for i in range(16):
        a=i*pi/8
        px,py=x+1.74*cos(a),y+1.832*sin(a)
        tapered("Perimeter railing post",(px,py,.41),(px,py,.64),.017,.017,7,"metal")
        b=(i+1)*pi/8
        beam("Stadium fencing circular handrail",(px,py,.62),
             (x+1.74*cos(b),y+1.832*sin(b),.62),.019,.018,"light metal")
    for px in (-.57,2.57):
        for py in (-2.67,.65):
            tapered("Athletics floodlight pole",(px,py,.04),(px,py,1.28),.031,.023,8,"metal")
            box("Floodlight glass bank",(px,py,1.27),(.21,.13,.122),"cream")
    station_entry("ATHLETICS",x,-2.895)


def mall():
    big_plot(2,2,"stone")
    walk(1,-2.786,3.55,.271)
    for i in range(2):
        for j in range(2):
            x,y=.055+i*1.883,-1.925+j*1.883
            box("Mall age-appropriate retail block",(x,y,.493),(1.79,1.73,.91),"plaster" if (i+j)%2 else "brick bright")
            box("Weathered rooftop coping",(x,y,.997),(1.838,1.79,.115),"warm limestone")
            for z in (.604,.806):
                box("Facade precast cladding strip",(x,y-.867,z),(1.767,.024,.038),"pale stone")
            for w in (-.536,0,.536):
                pane("Retail show window",x+w,y-.868,.291,.333,.305,f="teal",divisions=3)
            façade_side(x+(-.897 if i==0 else .897),y,1.79,1.74,.176,.71,4,2,"cream board")
            box("Roof HVAC louver housing",(x+.22,y+.31,1.093),(.42,.358,.144),"metal")
            for k in range(5):
                box("Rooftop equipment grilles",(x+.22,y+.129,1.045+k*.024),(.383,.014,.011),"dark metal")
    box("Cross-tile glazed central atrium",(1,-1,.896),(1.069,2.893,1.72),"reflection")
    gable("Glass atrium roof",1,-1,1.06,2.87,1.755,2.095,"reflection","slate","metal",8)
    for z in (.384,.718,1.097,1.478):
        pane("Atrium structural glazing",1,-2.467,z,.924,.299,f="light metal",divisions=5)
    box("Cantilevered red entry canopy",(1,-2.672,.499),(1.10,.49,.055),"burgundy")
    box("Enamel lettering strip",(1,-2.922,.501),(1.03,.022,.058),"teal")
    text_plate("Mall entry raised sign","SHOPPING CENTRE",1,-2.94,.495,.059,"cream")
    for x in (-.607,2.516):
        box("Street planter",(x,-2.478,.09),(.44,.32,.134),"stone")
        box("Street planter foliage",(x,-2.478,.175),(.40,.27,.064),"foliage")
        lamp(x,-2.70)


def construction(w,d,stage):
    big_plot(w,d,"soil")
    for i in range(w):
        for j in range(d):
            x,y=i*2,-j*2
            box("Excavation spoil",(x-.44,y+.42,.07),(.46,.45,.099),"soil shade")
            for side in (-1,1):
                for k in range(5):
                    px=x+(k-2)*.30
                    yy=y+side*.82
                    box("Temporary hoarding post",(px,yy,.15),(.037,.044,.237),"dark metal")
                box("Temporary timber perimeter",(x,y+side*.82,.191),(1.387,.044,.119),"sapwood")
            for side in (-1,1):
                box("Rebar rack",(x+side*.33,y-.41,.093),(.018,.41,.027),"metal")
            if stage>=1:
                box("Fresh structural footing",(x,y,.129),(1.60,1.35,.178),"stone")
                for a in (-1,1):
                    for b in (-1,1):
                        box("Structural frame upright",(x+a*.63,y+b*.52,.296+stage*.058),
                            (.102,.102,.301+stage*.109),"rust")
            if stage>=2:
                box("Unfinished poured deck",(x,y,.655),(1.43,1.23,.083),"pale stone")
                for side in (-1,1):
                    box("Partial unfinished infill partition",(x+side*.395,y+.204,.363),(.151,.77,.311),"brick")
                    beam("Temporary structural X bracing",(x+side*.63,y-.51,.24),(x+side*.63,y+.51,.65),
                         .033,.034,"sapwood")


MULTI_ASSETS={0x07:("hotel",hotel),0x14:("football_ground",rectangular_stadium),
              0x20:("athletics_stadium",oval_stadium),0x28:("shopping_mall",mall)}


ASSETS={**FIRST,**SECOND,**MULTI_ASSETS}


def join_into_native():
    # In the multipart OBJ export, Blender front -Y becomes Luanti +Z.
    # X then runs screen-left as viewed from that facade. Reverse the
    # relief in its own coordinates before clipping, not the parcel or
    # the editable Blender letters. Fix winding after the reflection.
    for sign in bpy.context.scene.objects:
        if sign.get("luanti_front_text"):
            sign.data.transform(Matrix.Diagonal((-1.0,1.0,1.0,1.0)))
            sign.data.flip_normals()
    first=next(iter(bpy.context.scene.objects))
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active=first
    bpy.ops.object.join()
    o=bpy.context.object
    matrix=o.matrix_world.copy()
    o.matrix_world.identity()
    for v in o.data.vertices:
        v.co=matrix@v.co+Vector((-.5,-.5,-.5))
    return o


def export_obj(o,stem):
    uv=o.data.uv_layers.active or o.data.uv_layers.new()
    for p in o.data.polygons:
        index=COLORS.index(o.data.materials[p.material_index].name)
        for i in p.loop_indices:
            uv.data[i].uv=((index+.5)/64,.5)
    bpy.ops.wm.obj_export(filepath=str(ROOT/"mods/luanttd_core/models"/f"bl_{stem}.obj"),
        export_selected_objects=True,export_materials=False,export_uv=True,export_normals=True,
        export_triangulated_mesh=True,global_scale=1,forward_axis="NEGATIVE_Z",up_axis="Y")


def export_parts(o,stem,w,d):
    # The single-node export stores -X in OBJ space. Partition the
    # unmirrored layout first, centered at Luanti's .5 local footprint,
    # then mirror each output piece for the engine OBJ import convention.
    for v in o.data.vertices:
        v.co.x+=1
    # Split faces without capping the boundary. Each piece streams on its own.
    for i in range(w):
        for j in range(d):
            m=bmesh.new()
            m.from_mesh(o.data)
            for axis,bound,begin in ((0,2*i-.5,True),(0,2*i+1.5,False),
                                     (1,-(2*j+1.5),True),(1,-(2*j-.5),False)):
                mask=[0.,0.,0.]; mask[axis]=1.
                p=[0.,0.,0.]; p[axis]=bound
                bmesh.ops.bisect_plane(m,geom=list(m.verts)+list(m.edges)+list(m.faces),dist=.000001,
                    plane_co=p,plane_no=mask,clear_outer=not begin,clear_inner=begin)
            # Blender bisect preserves faces exactly on a seam in both
            # halves. Keep each such face on the side it bounds, otherwise
            # stadium segments at cardinal directions get duplicate faces.
            m.normal_update()
            seams=((0,2*i-.5,i>0,1),(0,2*i+1.5,i<w-1,-1),
                   (1,-(2*j+1.5),j<d-1,1),(1,-(2*j-.5),j>0,-1))
            duplicate=[]
            for f in m.faces:
                if any(valid and sign*f.normal[axis]>0 and
                    all(abs(v.co[axis]-bound)<.000001 for v in f.verts)
                    for axis,bound,valid,sign in seams):
                    duplicate.append(f)
            if duplicate:
                bmesh.ops.delete(m,geom=duplicate,context="FACES_ONLY")
            for v in m.verts:
                v.co.x=2*i-v.co.x  # Luanti OBJ import reverses handedness.
                v.co.y+=2*j
            bmesh.ops.reverse_faces(m,faces=list(m.faces))
            m.normal_update()
            data=bpy.data.meshes.new(f"{stem} x{i} z{j}")
            for mat in o.data.materials:
                data.materials.append(mat)
            m.to_mesh(data)
            m.free()
            chunk=bpy.data.objects.new(data.name,data)
            bpy.context.collection.objects.link(chunk)
            o.select_set(False)
            chunk.select_set(True)
            bpy.context.view_layer.objects.active=chunk
            export_obj(chunk,f"{stem}_{j+2*i}")
            bpy.data.objects.remove(chunk,do_unlink=True)
            bpy.data.meshes.remove(data)


def export(id,name,geometry):
    init()
    geometry()
    bpy.context.scene.name="LuanTTD / stock temperate "+name.replace("_"," ")
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/f"art/town_stock_{id:02x}_{name}.blend"),compress=True)
    o=join_into_native()
    if id in MULTI_SIZE:
        w,d=MULTI_SIZE[id]
        export_parts(o,f"town_stock_{id:02x}",w,d)
    else:
        export_obj(o,f"town_stock_{id:02x}")


def export_construction():
    for w,d in sorted(set(MULTI_SIZE.values())):
        for stage in range(3):
            init()
            construction(w,d,stage)
            export_parts(join_into_native(),f"town_stock_stage_{w}{d}_{stage}",w,d)


def review(path):
    init()
    active = dict(FIRST) if not os.getenv("STOCK_TOWN_IDS") else {
        id:spec for id,spec in ASSETS.items() if id in {int(x,16) for x in os.environ["STOCK_TOWN_IDS"].split()}}
    columns=min(5,ceil(sqrt(len(active))))
    rows=ceil(len(active)/columns)
    stride=4.6 if set(active).intersection(MULTI_SIZE) else 2.7
    for n,(id,(_,fn)) in enumerate(active.items()):
        before=set(bpy.context.scene.objects)
        fn()
        w,d=MULTI_SIZE.get(id,(1,1))
        for o in set(bpy.context.scene.objects)-before:
            o.location.x+=(n%columns-(columns-1)*.5)*stride-(w-1)
            o.location.y+=((rows-1)*.5-n//columns)*stride+(d-1)
    box("Matte background",(0,0,-.12),(100,100,.15),"blue board")
    scene=bpy.context.scene
    bpy.ops.object.camera_add(location=(8,-13,11))
    scene.camera=bpy.context.object
    scene.camera.rotation_euler=(Vector((0,0,.55))-scene.camera.location).to_track_quat("-Z","Y").to_euler()
    scene.camera.data.type="ORTHO"
    scene.camera.data.ortho_scale=max(columns,rows)*stride*1.30
    scene.render.engine="BLENDER_WORKBENCH"
    scene.display.shading.color_type="MATERIAL"
    scene.display.shading.show_cavity=True
    scene.display.shading.cavity_type="BOTH"
    scene.display.shading.show_shadows=True
    scene.render.resolution_x=1280;scene.render.resolution_y=900;scene.render.resolution_percentage=100
    scene.render.filepath=path
    bpy.ops.render.render(write_still=True)


if __name__=="__main__":
    requested={int(x,16) for x in os.getenv("STOCK_TOWN_IDS","").split() if x}
    if not os.getenv("STOCK_TOWN_RENDER_ONLY"):
        for id,(name,geometry) in ASSETS.items():
            if not requested or id in requested:
                export(id,name,geometry)
        if not requested or 0x04 in requested:
            init()
            lift_cab()
            bpy.context.scene.name="LuanTTD / exterior office lift car"
            bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art/town_lift_04.blend"),compress=True)
            export_obj(join_into_native(),"town_stock_04_lift")
        if not requested or requested.intersection(MULTI_SIZE):
            export_construction()
    if os.getenv("STOCK_TOWN_REVIEW"):
        review(os.environ["STOCK_TOWN_REVIEW"])

#!/usr/bin/env python3
"""Original early-mid-century cottage staging for stock 1x1 house growth."""
from pathlib import Path
from random import Random
from math import cos, pi, sin
import os
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_sawmill_art as s

R=s.R
B,T=s.B,s.T
bpy=s.bpy
PAL=s.PAL | {
   "lawn_loam":"837257","dark_foundation_bed":"615447","rusty_nail":"92765c",
   "frost_stone":"a9a393","lime_mortar":"aba08d","warm_block":"a18e77",
   "lath_bright":"d5b27c","lath_shade":"a68154","warm_lath":"b68b58",
   "orange_cord":"b88552","pine_under":"96856a","roof_felt":"5c5a52",
   "tile_warm":"b16852","tile_shade":"985a49","tile_sun":"bb7760",
   "putty":"cfbaa1","linen":"e4d0ab","paper":"d1bd94",
   "store_grey":"687774","steel_dark":"505951","wood_oil":"775f4b",
   "rounded_slate":"6b706a","crated_white":"d3cdb1",
}
s.PAL=PAL
s.P=s.w.P={k:i for i,k in enumerate(PAL)}
R.COLORS[:]=PAL.values()
PREFIX="bl_house_build"
W=.578
Z0,Z1=-.475,.627
EAVE=.653
PEAK=.977
ASSEMBLY=(("Foundation",0),("Framing",1),("Partly roofed",2))


def pad(m,i):
    rng=Random(901)
    # The normal ground remains beneath the art; slight bias prevents
    # its patch of exposed soil from fighting the native turf plane.
    outline=[(-.835,-.682),(-.681,-.806),(.568,-.824),(.731,-.721),(.804,-.433),
             (.823,.500),(.705,.775),(.557,.825),(-.632,.846),(-.807,.719)]
    s.f(m,"Exposed cottage building site",("lawn_loam","yard_warm","packed_clay")[i],[(x,z,.002) for x,z in outline])
    for j in range(63):
        x,z=rng.uniform(-.691,.698),rng.uniform(-.672,.719)
        u,v=rng.uniform(.005,.021),rng.uniform(.006,.022)
        hue=("yard_dark","yard_light","chip","fine_sawdust","yard_warm")
        s.patch(m,"Small knapped stones and grit in site yard",rng.choice(hue),x-u,x+u,z-v,z+v,.004)
    for x in (-.126,.186):
        s.patch(m,"Temporary footpath lime grit","wheel_sand",x-.025,x+.025,-.872,-.485,.0055)
    for j in range(5):
        x=.665-.104*j
        z=-.694+.033*sin(j*2)
        B(m,"Exposed packed drain trench rim stones","concrete_cold" if j%3 else "warm_block",
          x,z,.069,.059,.005,.025,.005)


def foundations(m):
    # Four actual excavated strips. A recessed dark strip models the
    # footing void above, without cutting into a neighbor's terrain node.
    for x in (-W,W):
        B(m,"Dark lower strip beneath limestone footing","dark_foundation_bed",x,.076,.171,1.166,.004,.022,.006)
        B(m,"Mortared deep cottage foundation wall","lime_mortar",x,.076,.110,1.123,.012,.085,.005)
        for i in range(8):
            for k in range(2):
                z=Z0+(i+.5)*.138+(.032 if k else .0)
                if z+.064>Z1+.014: z=Z1-.047
                B(m,"Individually dressed exposed foundation stones",
                  ("warm_block","frost_stone","foundation")[(i+2*k)%3],
                  x,z,.118,.132,.020+.032*k,.049+.032*k,.004)
    for z in (Z0,Z1):
        B(m,"Mortared deep cottage foundation wall","lime_mortar",0,z,1.072,.110,.013,.084,.005)
        B(m,"Dark lower strip beneath limestone footing","dark_foundation_bed",0,z,1.070,.165,.006,.020,.005)
        for i in range(8):
            B(m,"Individually dressed exposed foundation stones",
              ("foundation","warm_block","frost_stone","concrete_bright")[i%4],(i-3.5)*.133,z,.128,.118,.021,.079,.004)
    for j in range(7):
        x=(j-3)*.143
        B(m,"Rough interior underfloor concrete service ribs","concrete_cold",x,.071,.026,.828,.009,.018,.003)
    s.tube(m,"Rising future service stub copper","iron_ochre",(.414,.471,.026),(.414,.472,.120),.012,n=8)


def stakeout(m):
    coords=((-W-.143,Z0-.137),(W+.142,Z0-.134),(W+.137,Z1+.125),(-W-.149,Z1+.121))
    for i,(x,z) in enumerate(coords):
        B(m,"Tapered survey peg and chalk stripe","lath_shade",x,z,.040,.039,.011,.213-(i%2)*.026,.003)
        B(m,"White survey nail head paint","linen",x,z,.042,.041,.153,.171,.001)
        s.tube(m,"Visible site building line strings","orange_cord",(x,z,.113),
              (coords[(i+1)%4][0],coords[(i+1)%4][1],.113),.004,n=6)
        b=.052
        B(m,"Tripod width board stake brace","warm_lath",x,z+.013,.093,.030,.121,.138,.002)
    for i in range(3):
        for j in range(2):
            B(m,"Dry stacked hand-hewn bricks ready for footing","brick_bright" if i%2 else "brick",
                .303+i*.101,-.679-j*.053,.092,.046,.023,.091+(j%2)*.034,.003)


def supplies(m,i):
    # Cropped inside the ordinary tile. Supplies visually step down as
    # the same building uses up its materials and gains new components.
    if i<=1:
        q=((-.461,-.700),(-.451,-.608),(-.434,-.525))
        for j in range(2):
            for k,(x,z) in enumerate(q):
                B(m,"Piled stock cottage construction timber","lath_bright" if j%2 else "warm_lath",x,z,.317,.053,
                  .052+j*.031,.077+j*.031,.002)
        for z in (-.706,-.525):
            B(m,"Timber bundle transport skids","oak_shade",-.441,z,.354,.025,.012,.049,.003)
    # A-frame bench is assembled from real angled posts rather than a filled box.
    x,z=(.706,.343) if i<2 else (.702,-.681)
    for dz in (-.088,.085):
        for d in (-1,1):
            s.spar(m,"Small working saw horse legs","oak_warm",(x+d*.060,z+dz,.014),
                   (x+d*.032,z+dz,.184),.027,.026)
        B(m,"Splayed sawhorse spreader","oak_dark",x,z+dz,.121,.025,.075,.094,.002)
    B(m,"Saw horse slender top lumber rail","warm_lath",x,z,.101,.229,.179,.209,.003)
    for j in range(3):
        dx=(j-1)*.029
        B(m,"Loose narrow boards across joiner's horse","lath_bright",x+dx,z,.024,.268,.208,.223,.002)
    if i==2:
        for j in range(4):
            for k in range(3):
                B(m,"Small stacks of waiting red roof tiles","tile_shade" if k%2 else "tile_warm",-.626+(k-1)*.056,
                  -.672+j*.028,.052,.046,.031+j*.013,.043+j*.013,.004)
    else:
        x,z=.470,.781
        B(m,"Iron-bound store chest under canvas","store_grey",x,z,.237,.122,.018,.101,.009)
        B(m,"Exposed chest green lid panel","electric",x,z,.242,.125,.099,.121,.008)
        for d in (-.064,.064):
            B(m,"Chest band wrought iron","steel_dark",x+d,z,.022,.126,.067,.124,.002)


def floor(m,i):
    for x in (-W,W):
        B(m,"Oak bearing plates in unchanged sill line","oak_dark",x,.076,.082,1.109,.075,.119,.007)
    for z in (Z0,Z1):
        B(m,"Oak bearing plates in unchanged sill line","oak_dark",0,z,1.118,.078,.075,.119,.007)
    for j in range(7):
        x=(j-3)*.163
        B(m,"Visible subfloor joists at regular pitch","warm_lath",x,.076,.057,1.077,.092,.147,.005)
    for j in range(7 if i==1 else 13):
        z=.586-j*.081
        B(m,"Individual floor sheathing planks","lath_bright" if j%3!=1 else "lath_shade",
          0,z,1.038,.077,.145,.166,.002)
        for x in (-.475,-.163,.163,.475):
            B(m,"Shallow iron nail heads in decking","rusty_nail",x,z,.008,.008,.166,.169,.001)


def studs(m,i):
    for x in (-W,W):
        B(m,"Continuous wall top wall plate","warm_lath",x,.076,.070,1.153,EAVE-.039,EAVE,.004)
        B(m,"Wall base chalked timber line","oak_dark",x,.076,.068,1.116,.118,.162,.003)
        for j,z in enumerate((Z0,-.352,-.204,-.027,.069,.248,.407,.533,Z1)):
            if -.028<=z<=.069:
                B(m,"Cut cripple studs below side sash openings","lath_bright",x,z,.040,.036,.149,.365,.003)
                B(m,"Cut cripple studs above side sash openings","warm_lath",x,z,.040,.036,.527,.629,.003)
            else:
                B(m,"Side wall vertically framed timber studs","lath_bright" if j%3 else "warm_lath",x,z,.049,.049,.127,.631,.003)
        for h in (.347,.518):
            B(m,"Side sash oak lintel and mid-storey sill","lath_shade",x,-.026,.064,.334,h,h+.031,.006)
        if i==1:
            s.spar(m,"Diagonal staging braces at empty wall","oak_warm",(x+.007,Z0+.018,.170),
                   (x-.004,Z1-.112,.564),.030,.034)
    for z in (Z0,Z1):
        B(m,"Continuous gable end top wall plate","warm_lath",0,z,1.105,.074,EAVE-.040,EAVE,.004)
        is_front=z<0
        opening=(.117,.368) if is_front else (-.166,.160)
        bay=(-.423,-.173) if is_front else (.271,.476)
        for k,x in enumerate((-.536,-.466,-.371,-.242,-.131,-.019,.097,.211,.336,.442,.534)):
            if opening[0]<x<opening[1]:
                B(m,"Header cripple studs over future door","warm_lath",x,z,.043,.038,.520,.620,.003)
                if not is_front:B(m,"Back sash sill cripples","lath_shade",x,z,.044,.042,.155,.321,.003)
            elif bay[0]<x<bay[1]:
                B(m,"Lower sash cripple studs below gap","lath_bright",x,z,.044,.039,.148,.333,.003)
                B(m,"Weak gable top sash cripples framing","lath_bright",x,z,.044,.039,.500,.619,.003)
            else:
                B(m,"Existing end-wall vertical studs","warm_lath" if k%3 else "lath_bright",
                  x,z,.044,.041,.133,.634,.003)
        for a,b,h,j in ((opening[0],opening[1],.510,.038),(bay[0],bay[1],.319,.031),(bay[0],bay[1],.494,.029)):
            B(m,"Fabricated doorway lintel and sash small sill","lath_shade",(a+b)/2,z,b-a+.007,.052,h,h+j,.005)
        for a in (opening[0],opening[1],bay[0],bay[1]):
            B(m,"Long framed edge around doorway and sash","oak_high",a,z,.025,.044,.149,.541,.003)
        B(m,"Window opening base blocking","lath_shade",-.306,z,.213,.045,.208,.228,.003)
    if i==1:
        for x,side in ((-.530,-1),(.553,1)):
            s.spar(m,"Temporary raking frame supports to ground peg","oak_warm",(x,Z0-.267,.021),
                   (x-side*.126,Z0-.025,.418),.038,.027)


def upper(m):
    """Stage 2: physically install some slate/terracotta and leave rafters exposed."""
    for z in (-.503,-.366,-.227,-.088,.048,.183,.318,.450,.586,.650):
        for d in (-1,1):
            s.spar(m,"Actual paired gable roof rafters","oak_high",(d*.648,z,EAVE-.009),
                   (0,z,PEAK),.036,.049)
        B(m,"Cross-ties bracing exposed roof planes","warm_lath",0,z,.743,.039,.691,.723,.004)
    B(m,"Long standing roof ridge board","oak_dark",0,.075,.049,1.315,PEAK-.025,PEAK+.028,.004)
    # Completed left/back roof slope; opposite broad gap visibly exposes ribs.
    def sheet(m,name,color,a,b,z0,z1,h,th=.016):
        top=((a,z0,h(a)),(b,z0,h(b)),(b,z1,h(b)),(a,z1,h(a)))
        low=[(x,z,y-th) for x,z,y in top]
        s.f(m,name,color,top);s.f(m,"Exposed stage-two roof battens from below","pine_under",low[::-1])
        for j in range(4):
            k=(j+1)%4
            s.f(m,name+" raised lap edge","tile_shade",(low[j],low[k],top[k],top[j]))
    h=lambda x:PEAK+.039-abs(x)/(W+.065)*(.344)
    for sec in (-1,1):
        n=7
        w=.659
        for j in range(n):
            a,b=sorted((sec*(w*j/n),sec*(w*(j+1)/n+.009)))
            a*=1.0
            for k in range(9):
                # A small right-rear patch is already weathered in. Leave
                # the front three quarters of that side visibly unroofed.
                if sec>0 and (k<6 or j<2):continue
                u=-.558+k*.139
                c=("tile_warm","tile_sun","tile_warm","tile_shade")[(j+7*k)%4]
                sheet(m,"Course of physically fitted terracotta roof tiles",c,a,b,u,u+.138,
                      lambda x:h(x)+(j%2)*.002)
    for j in range(3):
        z=.255+j*.137
        s.tube(m,"Partially installed cylinder ridge row","tile_shade",(0,z,PEAK+.044),(0,z+.135,PEAK+.044),
             .028,.024,10)
    # Two boarded walls with real opening trim; open framing remains visible at front/right.
    for z in (Z1,Z0):
        n=11
        for q in range(n):
            x=(q-(n-1)/2)*.101
            if z<0 and x>-.086:continue
            # Pale left lower sash and open door live in the native fabric.
            cut=(-.414<x<-.181) if z<0 else (-.165<x<.163)
            for a,b in (((.169,.319),(.516,EAVE-.011)) if cut else ((.170,EAVE-.011),)):
                B(m,"Pale vertical boards installed beside bare frames","linen" if q%2 else "putty",
                    x,z+(.032 if z>0 else -.032),.096,.022,a,b,.003)
    for i in range(12):
        z=Z0+(i+.5)*.091
        low=((.180,.338),(.550,EAVE)) if -.208<z<.179 else ((.179,EAVE-.006),)
        for a,b in low:
            B(m,"Installed shiplap on first finished side","linen" if i%3 else "putty",-.608,z,.023,.086,a,b,.002)
    # Actual outer glaze is deliberately present in just one fitted sash.
    a=-.294;z=Z0-.046
    for x in (a-.122,a+.122):
        B(m,"Completed left front casing cut and trued","crated_white",x,z,.028,.028,.303,.519,.003)
    for y in (.300,.512):
        B(m,"Completed left front sash sill","crated_white",a,z,.243,.027,y,y+.024,.003)
    for sx in (-1,1):
        B(m,"First stand-alone window blank glass pane","glazing",a+sx*.050,z-.006,.093,.012,.333,.505,.006)
        B(m,"Sunlit upper reflection on one completed sash","glass_light",a+sx*.049,z-.016,.080,.006,.460,.493,.002)
    B(m,"A partly decked brick chimney plinth","brick_dark",-.311,.467,.144,.129,.552,.755,.002)
    for j in range(8):
        c=("brick","brick_bright","brick","brick_dark")[j%4]
        B(m,"Legitimate individual brick chimney courses",c,-.311,.467,.139,.124,.620+j*.045,.659+j*.045,.003)
    B(m,"Chimney top warm stone corbel","warm_block",-.311,.467,.181,.158,.946,.986,.006)
    # Leaning timber ladder outside open right half.
    for z in (-.214,.014):
        s.spar(m,"Period wooden ladder posts on eave side","oak_weather",(.806,z,.037),(.590,z,.750),.024,.027)
    for j in range(7):
        f=(j+1)/8
        s.spar(m,"Individual ladder rungs","lath_bright",(.806-.216*f,-.213,.037+.713*f),
               (.806-.216*f,.014,.037+.713*f),.021,.025)


def build(i):
    m=s.art_mesh()
    pad(m,i);foundations(m);supplies(m,i)
    if i==0:stakeout(m)
    if i>=1:floor(m,i);studs(m,i)
    if i==2:upper(m)
    return m


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    mats=R.materials()
    for i,mat in enumerate(mats):mat.name=list(PAL)[i]
    scene=bpy.context.scene
    scene.name="LuanTTD | Ordinary temperate cottage construction stages"
    for label,i in ASSEMBLY:
        m=build(i)
        coll=R.stash(m,mats,f"Stock stage {i} | {label}")
        R.instance(scene,coll,2.36*(2-i),0)
        R.export_obj(R.MODELS/(f"{PREFIX}_stage_{i}.obj"),m)
    s.atlas(PREFIX,PAL)
    s.review_scene(scene,(2.34,0,.38),7.85)
    bpy.ops.wm.save_as_mainfile(filepath=str(R.ROOT/"art"/"house_construction.blend"),compress=True)
    if p:=os.getenv("HOUSE_STAGES_RENDER"):
        scene.render.filepath=p;bpy.ops.render.render(write_still=True)


if __name__=="__main__":
    main()

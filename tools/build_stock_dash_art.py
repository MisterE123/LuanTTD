#!/usr/bin/env python3
"""Build an original late-diesel twin multiple-unit half for OpenTTD stock #12."""
from math import cos, sin, tau
import os
import sys
from pathlib import Path
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_stock_rail_f_art as F

M, R, W, J, G = F.M, F.R, F.W, F.J, F.G
B, D, Pipe = F.B, F.D, F.Pipe
NAME = "rail_dash"
AXLES = (-.264, -.194, .189, .256)
PALETTE = {
    **F.PAL,
    "Dash lower indigo":"2c455e",
    "Dash cobalt skirt":"486783",
    "Dash shell ivory":"c4ccc8",
    "Dash shell sunlit":"dce2d9",
    "Dash window belt":"344a58",
    "Dash cab surround":"263541",
    "Dash door vermilion":"ad4836",
    "Dash door edge":"7d3c35",
    "Dash lamp ivory":"f6ecbd",
    "Dash cab amber":"e9b34c",
    "Dash dark amber":"bb863b",
    "Dash rubber bevel":"454c4f",
    "Dash warm window reflection":"a5b7be",
}
P = {material:i for i,material in enumerate(PALETTE)}
# The outward end has a distinct square-shouldered cab with a slight taper and
# recessed under-bumper. The inboard corridor mates to an independently placed
# opposing car. All dimensions are in the game's conventional vehicle envelope.
SECTIONS = (
    (-.421,.183,.497,.182,.437),(-.406,.198,.522,.173,.453),
    (-.368,.212,.539,.172,.464),(-.312,.216,.547,.173,.472),
    (-.242,.216,.548,.174,.475),(.312,.216,.548,.174,.475),
    (.394,.211,.541,.174,.465),(.425,.190,.517,.177,.451),
)

def setup():
    F.P = M.P = J.P = W.P = G.P = P
    R.COLORS[:] = PALETTE.values()

def hull(m):
    for (a,*one),(b,*two) in zip(SECTIONS,SECTIONS[1:]):
        q,r=F.body_contour(*one),F.body_contour(*two)
        for t in range(len(q)):
            u=(t+1)%len(q)
            if t in (0,1,18):
                c="Dash lower indigo"
            elif t in (2,17):
                c="Dash cobalt skirt"
            elif t in (3,4,15,16):
                c="Dash shell ivory"
            else:
                c="Dash shell sunlit" if 8<=t<=11 else "Dash shell ivory"
            p=((q[t][0],a,q[t][1]),(r[t][0],b,r[t][1]),
               (r[u][0],b,r[u][1]),(q[u][0],a,q[u][1]))
            F.face(m,"Separate rolled roof and fluted shell faces",c,p)
    for i in (0,-1):
        z,*section=SECTIONS[i]
        p=[(w,z,h) for w,h in F.body_contour(*section)]
        F.face(m,"Outward pilot cast face and corridor bulkhead",
               "Dash cab amber" if i==0 else "Dash shell ivory",p if i==0 else p[::-1])

def cab(m):
    B(m,"Moulded low outward anti-climber","Dash lower indigo",0,-.426,.335,.031,.172,.219,.010)
    B(m,"Distinct low protective amber cab skirt","Dash dark amber",0,-.424,.342,.013,.222,.269,.005)
    B(m,"Wide cab glazed fascia with rubber isolation","Dash cab surround",0,-.425,.340,.011,.319,.448,.012)
    for i,(x0,x1) in enumerate(((-.154,-.033),(-.024,.027),(.037,.154))):
        width=x1-x0
        x=(x0+x1)/2
        B(m,"Separate cab panes with narrow centre mullions","Deep glass blue",x,-.432,width,.004,.333,.431,.004)
        B(m,"Cab panes: soft pale upper sky","Dash warm window reflection",x,-.435,width-.010,.003,.401,.422,.0015)
        B(m,"Cab panes: dashboard reflection","Window shadow",x,-.435,width-.010,.003,.339,.353,.0015)
        if i!=1:
            Pipe(m,"Seated outward driver window wiper","Dash rubber bevel",
                 (x-.026,-.438,.350),(x+.013,-.438,.380),.0026,8)
    B(m,"Cab LED destination recess","Dash cab surround",0,-.424,.113,.010,.453,.480,.003)
    for x in (-.12,.12):
        B(m,"Outward paired marker and headlamp sockets","Dash cab surround",x,-.430,.064,.009,.260,.291,.004)
        D(m,"Warm running lamp","Dash lamp ivory",(x,-.437,.277),.0085,"z",-.002,.004,16)
        D(m,"Inboard rear ruby marker","Warm rear ruby",(x*.85,-.437,.277),.006,"z",-.002,.004,12)
    for x in (-.032,-.015,0,.015,.032):
        B(m,"Destination display separated amber segments","Dash cab amber",x,-.431,.010,.003,.461,.472,.001)

def sides(m):
    for s in (-1,1):
        def panel(name,c,a,b,h0,h1,lift):
            F.skin_panels(m,name,c,SECTIONS,s,a,b,h0,h1,lift)
        for a,b in ((-.368,-.173),(-.090,.152),(.236,.400)):
            panel("Indigo lining interrupted by passenger doors","Dash lower indigo",a,b,.247,.268,.0018)
        panel("Upper sealed black glazing belt","Dash window belt",-.375,.389,.338,.438,.0020)
        for a,b in ((-.346,-.284),(-.230,-.179),(-.078,-.013),(.000,.061),(.076,.146),(.240,.297),(.311,.370)):
            panel("Individual bonded saloon windscreen","Dash cab surround",a,b,.346,.433,.0036)
            panel("Glass recessed by stepped rubber and side waist","Mid glass blue",a+.003,b-.003,.355,.424,.0048)
            panel("Cool upper sky reflection in each window","Dash warm window reflection",a+.005,b-.005,.399,.423,.0054)
            panel("Lower passenger-seat reflection stripe","Deep glass blue",a+.006,b-.006,.359,.381,.0056)
        for a,b in ((-.172,-.091),(.153,.235)):
            panel("Distinct double sliding passenger door recess","Dash door edge",a,b,.218,.447,.003)
            for lo,hi in ((a+.004,(a+b)/2-.001),((a+b)/2+.001,b-.004)):
                # Split at the curved lower sill, so the door skin does not cut into its own shell.
                for base,top in ((.226,.238),(.238,.265),(.265,.442)):
                    panel("Pressed warm-red sliding door leaves","Dash door vermilion",lo,hi,base,top,.0047)
                panel("Window on each individual slider leaf","Dash cab surround",lo+.005,hi-.005,.336,.424,.0068)
                panel("Small side door panes","Mid glass blue",lo+.008,hi-.008,.343,.418,.0076)
                panel("Low step-side open button","Dash lamp ivory",lo+.006,lo+.012,.307,.314,.008)
            B(m,"External bus-style folding step below valance","Dash rubber bevel",
              s*.205,(a+b)/2,.045,b-a-.015,.156,.179,.004)
        for z in (-.245,-.221,.265,.287):
            B(m,"Underfloor accessible battery/service inspection ribs","Dash cobalt skirt",
              s*.165,z,.015,.011,.102,.142,.0012)
        Pipe(m,"Exterior rail at corridor threshold","Dash window belt",
             (s*.174,.401,.231),(s*.174,.406,.337),.0038,9)
    for z in (-.211,-.124,.130,.228):
        B(m,"Shallow HVAC cowls above saloon","Roof lead blue",0,z,.161,.054,.537,.560,.011)
        for x in (-.044,-.022,0,.022,.044):
            B(m,"Formed upper HVAC outlet slots","Dash window belt",x,z,.009,.036,.555,.561,.002)


def wheel(m,z):
    rad=M.RAD
    D(m,"Full width native steel axle","Dry tire iron",(0,z,rad),.012,"x",-.221,.221,16)
    for s,side in ((-1,"L"),(1,"R")):
        x=s*.212
        lo,hi=sorted((-s*.027,s*.028))
        J.Lathe(m,"Rolling tread Dash "+side,[(lo,.62*rad),(lo,rad),(hi,rad),
                (hi,.62*rad),(lo,.62*rad)],"x",(x,z,rad),("Dash rubber bevel","Dry tire iron",
                "Steel wheel flange","Dry tire iron"),28,False,False)
        lo,hi=sorted((-s*.037,-s*.029))
        J.Lathe(m,"Inboard Dash railhead flange",[(lo,.65*rad),(lo,rad+.009),
                (hi,rad+.009),(hi,.65*rad),(lo,.65*rad)],"x",(x,z,rad),
                ("Steel wheel flange",),28,False,False)
        D(m,"Spoked dish wheel face","Dry tire iron",(x+s*.013,z,rad),.036,"x",-.009,.009,20)
        D(m,"Separate axlebox cap","Wheel center grease",(x+s*.024,z,rad),.015,"x",-.005,.005,14)
        for j in range(5):
            rot=tau*j/5
            D(m,"Array of visible ring bolts","Fresh nickel pin",
              (x+s*.024,z+.025*cos(rot),rad+.025*sin(rot)),.0023,"x",-.003,.003,7)

def build():
    setup()
    parts = (
        ("01 • Formed ivory pressure shell",hull),
        ("02 • Live faces: glazing, lowered skirt and cab optics",cab),
        ("03 • Separate double doors, side glazing and HVAC",sides),
        ("04 • Corridor bellows and chassis",lambda m:(F.vestibule(m,True,1),F.underframe(m,False,AXLES))),
    )
    full=F.make_mesh()
    for _,fn in parts:fn(full)
    for z in AXLES:wheel(full,z)
    colors=tuple(PALETTE.values())
    active=sorted({c for fs in full.parts.values() for _,c in fs})
    idx={p:i for i,p in enumerate(active)}
    packed=F.make_mesh()
    for group,fs in full.parts.items():
        for poly,col in fs:
            packed.face(group,idx[col],[full.vertices[group][i] for i in poly])
    R.COLORS[:]=[colors[c] for c in active]
    target=F.ROOT/"mods/luanttd_core/models"/f"bl_{NAME}.obj"
    R.export_obj(target,W.local_obj(packed))
    _,*rest=target.read_text().splitlines()
    target.write_text("# Original native Dash railcar authored in Blender; nose neutral -Z\n"+"\n".join(rest)+"\n")
    F.atlas(NAME,R.COLORS)

    setup()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene
    scene.name="LuanTTD stock Dash DMU #12"
    scene["Upstream"]="OpenTTD 16.0-RC1 table/engines.h, #12; original artwork."
    scene["Envelope"]="Conventional one-tile wheelbase, 0.424 gauge, neutral nose -Z."
    scene["Partner"]="The same native model faces the opposite direction on the second powered half."
    # The shared palette builder reads M.PAL, so supply this body's own complete palette.
    M.PAL=PALETTE
    mats=M.colors()
    for name,fn in parts:
        mesh=F.make_mesh();fn(mesh);J.geometry(scene,name,mesh,mats)
    for i,z in enumerate(AXLES,1):
        mesh=F.make_mesh();wheel(mesh,z)
        col=J.geometry(scene,f"{i+4:02} • Independently editable axle {i}",mesh,mats)
        pivot=bpy.data.objects.new(f"Dash axle {i} pivot",None)
        pivot.location=(0,z,M.RAD);pivot.empty_display_type="CIRCLE";pivot.empty_display_size=.045
        col.objects.link(pivot)
        for ob in tuple(col.objects):
            if ob!=pivot:
                ob.parent=pivot;ob.location=(0,-z,-M.RAD)
    F.render(scene,NAME,os.getenv("DASH_REVIEW"))

if __name__=="__main__":
    build()

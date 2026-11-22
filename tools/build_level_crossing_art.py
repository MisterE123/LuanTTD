#!/usr/bin/env python3
"""Original conventional road/rail crossing kit, both stock axis combinations.

blender -b -t 4 --python-exit-code 1 --python tools/build_level_crossing_art.py
LEVEL_CROSSING_RENDER=/tmp/level.png blender -b -t 4 --python tools/build_level_crossing_art.py

OpenTTD 14.1 road_cmd.cpp DrawTile_Road, road_map.h, rail_cmd.cpp: perpendicular
straight rail and road, flat/leveled foundation and an open/barred state.
No OpenTTD art is imported. Shared production rail profiles and palette are
retained through the site. Camera scenes and separate gate pivots are editable.
"""
from math import cos, pi, sin
from pathlib import Path
import os
import struct
import sys
import zlib

import bpy
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_rail_art as R
TRACK=R.COLORS.copy()  # Exact stock neighboring-track atlas, captured before helper import.
import build_ship_facility_art as H
ROOT=R.ROOT
EXTRA={
    "Road asphalt":"4f5255","Road warm gravel":"9a937e","Paint stripe":"efe3b6",
    "Inlaid crossing deck dark":"655c51","Inlaid crossing deck faded":"766e60",
    "Plate wear line":"544f49","Road edge timber":"836b54","Edge steel":"827f73",
    "Pavement seat":"655e50","Dressed footing":"a19a86","Footing shadow":"706e61",
    "Green galvanized":"526e67","Base casting":"3b5351","Galvanized steel":"8f9a92",
    "Dark gear case":"424648","Cast cap":"666c63","Lamp hoods":"363b3d",
    "Lamp red ring":"963f35","Ruby unlit":"612e2d","Ruby lit":"f44c32",
    "Ruby lens center":"fa7652","Pale ceramic":"e5d6b3","Worn cream":"ece1c6",
    "Gate enamel red":"b5493f","Gate enamel ivory":"f3dfad","Gate lever":"586964",
    "Black lettering":"444638","Brass bolt":"aa9867","Sign dark fascia":"4e5a51",
    "Bed backdrop":"57814c","Reflector":"e8bc74"
}
P={k:i+len(TRACK) for i,k in enumerate(EXTRA)}
H.P=P
R.COLORS[:]=TRACK+list(EXTRA.values())
B,T=H.box,H.tube
ROAD_EDGE=.3125
ROUGH_EDGE=.375
INNER=.147
RAIL_IN=R.GAUGE/2-R.HEAD # .182; inside flangeway must contain wheel flange at .168-.176.
RAIL_OUT=R.GAUGE/2+R.HEAD # .242
PLATE=.108
PIVOT=(.487,.704,.290)
ARM=.903
UP=82*pi/180

def mesh():
    return R.Mesh(R.terrain_height(0))

def f(m,n,c, pts):
    m.face(n,P[c],pts)

def r(m,n,c,x0,x1,z0,z1,h):
    h=h if callable(h) else lambda x,z,v=h:v
    f(m,n,c,[(x0,z0,h(x0,z0)),(x1,z0,h(x1,z0)),(x1,z1,h(x1,z1)),(x0,z1,h(x0,z1))])

def move(m,tr):
    out=mesh()
    for n,fs in m.parts.items():
        v=m.vertices[n]
        for ids,p in fs:out.face(n,p,[tr(*v[i]) for i in ids])
    return out

def merge(*pieces):
    out=mesh()
    for m in pieces:
        for n,fs in m.parts.items():
            v=m.vertices[n]
            for ids,p in fs:out.face(n,p,[v[i] for i in ids])
    return out

def turn(m,q):
    return move(m,lambda x,z,h:((x,z,h),(-z,x,h),(-x,-z,h),(z,-x,h))[q%4])

def street_height(z):
    t=min(1,max(0,(.94-abs(z))/.57))
    return .002+(PLATE-.002)*t*t*(3-2*t)

def grades(z0,z1):
    lo,hi=sorted((z0,z1))
    # The stations include profile breakpoints plus enough intermediate
    # samples that interpolation differs by under 1 millinode.
    k=[lo,*[p for i in range(23) if lo<(p:=-.94+i*.085)<hi],hi]
    return list(zip(k,k[1:]))

def street(m):
    # Road axis native Z and rail X in seed. Existing rail itself is
    # generated as a full-depth continuous section, not hidden by paint.
    # The asphalt stops clear of both outward rail faces at the joint.
    for s in (-1,1):
        a,b=sorted((s*(RAIL_OUT+.003),s))
        for z0,z1 in grades(a,b):
            h=lambda x,z:street_height(z)
            r(m,"Joined two-lane asphalt approaches","Road asphalt",-ROAD_EDGE,ROAD_EDGE,z0,z1,h)
            for side in (-1,1):
                u,v=sorted((side*ROAD_EDGE,side*ROUGH_EDGE))
                r(m,"Joined native warm gravel shoulders","Road warm gravel",u,v,z0,z1,
                  lambda x,z:street_height(z)-.0015*(abs(x)-ROAD_EDGE)/(ROUGH_EDGE-ROAD_EDGE))
                f(m,"Sloped gravel approach retaining edge","Pavement seat",[(side*ROUGH_EDGE,z0,0),
                    (side*ROUGH_EDGE,z1,0),(side*ROUGH_EDGE,z1,street_height(z1)-.0015),
                    (side*ROUGH_EDGE,z0,street_height(z0)-.0015)][::-1] if side<0 else
                    [(side*ROUGH_EDGE,z0,0),(side*ROUGH_EDGE,z1,0),(side*ROUGH_EDGE,z1,street_height(z1)-.0015),
                    (side*ROUGH_EDGE,z0,street_height(z0)-.0015)])
        # Broken lane markings near the tile edge and side-specific
        # stop-line, no paint crossing an entire external seam.
        lo,hi=sorted((s*.912,s*.825))
        r(m,"Approach centerline paint","Paint stripe",-.018,.018,lo,hi,lambda x,z:street_height(z)+.0016)
        lo,hi=sorted((s*.782,s*.811))
        x0,x1=(-.272,-.047) if s<0 else (.047,.272)
        r(m,"Inset per-lane railway stop bar","Paint stripe",x0,x1,lo,hi,lambda x,z:street_height(z)+.0018)
        for i in range(3):
            p0,p1=sorted((s*(.272+.034*i),s*(.299+.034*i)))
            r(m,"Near-rail composite rubber panels","Inlaid crossing deck dark",-ROUGH_EDGE,ROUGH_EDGE,p0,p1,
              lambda x,z:street_height(z)+.0007)
        # Recessed stone bed in outer check seams, not overlapping railhead.
        z0,z1=sorted((s*(RAIL_OUT+.001),s*(RAIL_OUT+.019)))
        r(m,"Outside running-rail grooved shoulder seal","Pavement seat",-ROUGH_EDGE,ROUGH_EDGE,z0,z1,.089)
        # Deep flangeway trough floor under the wheel flange, no blocking edge.
        z0,z1=sorted((s*INNER,s*(RAIL_IN+.001)))
        r(m,"Continuous open railway flangeway floor","Lamp hoods",-ROUGH_EDGE,ROUGH_EDGE,z0,z1,.0825)
        f(m,"Visible inner deck flange groove edge","Edge steel",
          [(-ROUGH_EDGE,s*INNER,.0825),(ROUGH_EDGE,s*INNER,.0825),
           (ROUGH_EDGE,s*INNER,PLATE),(-ROUGH_EDGE,s*INNER,PLATE)][::s])
    # Three boards exactly cover the common drivable width. Every raised
    # edge is lowered below a normal vehicle's bottom. Real slots preserve
    # both rail wheel flange paths and each rail head remains visible.
    for z0,z1,mat in ((-INNER,-.051,"Inlaid crossing deck faded"),(-.050,.050,"Inlaid crossing deck dark"),
                      (.051,INNER,"Inlaid crossing deck faded")):
        r(m,"Seated rail crossing surface panels",mat,-ROAD_EDGE,ROAD_EDGE,z0,z1,PLATE)
    for z in (-.0505,.0505):
        r(m,"Recessed individual crossing deck joints","Plate wear line",-ROAD_EDGE,ROAD_EDGE,z-.0005,z+.0005,.104)
    for side in (-1,1):
        x0,x1=sorted((side*ROAD_EDGE,side*ROUGH_EDGE))
        B(m,"Outside timber mat apron","Road edge timber",(x0+x1)/2,0,x1-x0,2*INNER,.037,PLATE-.004)
        for j in range(4):
            x=side*(.335+(j%2)*.013)
            z=-.112+j*.073
            T(m,"Plate outer flush brass fasteners","Brass bolt",
               (x,z,.104),(x,z,.1085),.009,.008,8)
    # Surface aggregates are subtle and inside the approaches only.
    for z in (-.917,-.882,-.759,-.689,-.611,-.450,.414,.573,.695,.812,.877):
        for i in range(7):
            x=-.275+.083*i+(.012 if i%2 else -.006)
            r(m,"Inset shallow road skin aggregate","Inlaid crossing deck dark",x-.006,x+.007,z-.004,z+.004,
              lambda x,z:street_height(z)+.0007)

def lx_panel(m,n,c,pts,z0,z1):
    if R.signed_area(pts)<0:pts=pts[::-1]
    a=[(x,z0,h) for x,h in pts]
    b=[(x,z1,h) for x,h in pts]
    f(m,n,c,a);f(m,n,c,b[::-1])
    for i in range(len(a)):
        j=(i+1)%len(a)
        f(m,n,c,[a[j],a[i],b[i],b[j]])

def rotated_bar(x,y,length,width,angle):
    dx,dy=cos(angle),sin(angle)
    return [(x+u*dx-v*dy,y+u*dy+v*dx)
            for u,v in ((-length/2,-width/2),(length/2,-width/2),(length/2,width/2),(-length/2,width/2))]

def sign_base(m):
    x,z,hinge=PIVOT
    B(m,"Crossing dressed cast-concrete barrier footing","Dressed footing",x+.005,z,.158,.142,.006,.068,.013)
    B(m,"Green cast hinge standard","Base casting",x+.015,z,.082,.098,.063,hinge-.010,.010)
    B(m,"Hinge weathered mast crown","Cast cap",x+.018,z,.089,.102,hinge-.046,hinge+.030,.012)
    T(m,"Gate protruding axle bearing journal","Galvanized steel",(x,z-.063,hinge),(x,z+.067,hinge),.032,.027,16)
    T(m,"Gate radial bolt collar","Brass bolt",(x,z+.071,hinge),(x,z+.084,hinge),.025,.022,12)
    B(m,"Electric gear motor cabinet support leg","Dark gear case",x+.097,z-.038,.089,.106,.066,.136,.011)
    B(m,"Cast electric gate motor housing","Green galvanized",x+.096,z-.036,.135,.125,.131,.253,.014)
    B(m,"Motor inspection hatch side notch","Dark gear case",x+.102,z+.030,.097,.012,.161,.223,.006)
    for i in range(4):
        w=.143+i*.018
        B(m,"Motor convective housing louvers","Cast cap",x+.100,z+.039,.065,.014,w,w+.005,.002)
    for zz in (z-.050,z+.050):
        T(m,"Barrier foundation exposed hold-down bolts","Brass bolt",
          (x+.058,zz,.067),(x+.058,zz,.081),.008,.008,8)

    # Cantilevered highway warning sign stands outboard and looks toward
    # its incoming road. The other quadrant is the exact inverted standard.
    X,Z=x+.095,z+.120
    B(m,"Flashers and crossbuck cast foot pad","Dressed footing",X,Z,.140,.134,.000,.083,.012)
    T(m,"Galvanized crossbuck mast","Green galvanized",(X,Z,.084),(X,Z,.753),.020,.016,10)
    for y in (.181,.457):
        T(m,"Mast compression collar","Galvanized steel",(X,Z,y-.014),(X,Z,y+.010),.024,.025,12)
    for theta in (pi/5,-pi/5):
        lx_panel(m,"Raised X railway-crossing sign timber core","Worn cream",
            rotated_bar(X,.748,.318,.057,theta),Z+.020,Z+.037)
        lx_panel(m,"Raised crossbuck inset narrow reflective line","Reflector",
            rotated_bar(X,.748,.253,.013,theta),Z+.0375,Z+.041)
    T(m,"Central crossbuck face bolt","Brass bolt",(X,Z+.039,.749),(X,Z+.047,.749),.011,.011,8)
    T(m,"Road warning lamp mounted horizontal pipe crossbar","Dark gear case",
      (X-.125,Z,.537),(X+.125,Z,.537),.017,.014,10)
    for side in (-1,1):
        cx=X+side*.081
        T(m,"Circular black flasher rear backing","Dark gear case",
          (cx,Z-.011,.538),(cx,Z+.027,.538),.054,.057,20)
        T(m,"Narrow ruby flashing lens socket outer collar","Lamp red ring",
          (cx,Z+.027,.538),(cx,Z+.032,.538),.051,.050,20)
        # Actual overhanging black metal half hoods leave sight lines open.
        a,b=[],[]
        for j in range(13):
            q=j*pi/12
            a.append((cx+.051*cos(q),Z+.031,.538+.051*sin(q)))
            b.append((cx+.053*cos(q),Z+.072-.009*abs(cos(q)),.538+.050*sin(q)))
        for j in range(12):
            pts=(a[j],a[j+1],b[j+1],b[j])
            f(m,"Open pressed steel lamp hoods","Lamp hoods",pts)
            f(m,"Open pressed steel lamp hood interiors","Lamp hoods",
              [(i,j,k-.001) for i,j,k in pts[::-1]])
    lx_panel(m,"Black signal backplate with cream edge","Dark gear case",
      [(X-.055,.418),(X+.054,.418),(X+.061,.457),(X+.053,.475),(X-.049,.475)],Z+.015,Z+.029)
    lx_panel(m,"Stamped advisory highway sign face","Pale ceramic",
      [(X-.048,.424),(X+.048,.424),(X+.048,.465),(X-.048,.465)],Z+.030,Z+.034)
    for x1 in (X-.023,X+.011):
        lx_panel(m,"Cast sign text bars","Black lettering",[(x1,.438),(x1+.013,.438),(x1+.013,.450),(x1,.450)],Z+.034,Z+.036)

def arm():
    m=mesh()
    # A physically independent galvanized shaft with a tapered drive arm;
    # the narrow head remains articulated at its axle, not the tile origin.
    for j in range(9):
        a=ARM*j/9
        b=ARM*(j+1)/9
        # Cone of tapered rectangles along rail X, cutting an assembled
        # bright panel on every other span.
        def ring(r):
            z=.018-.008*r/ARM
            h=.026-.010*r/ARM
            return [(-r,-z,-h),(-r,-z,h),(-r,z,h),(-r,z,-h)]
        lo,hi=ring(a),ring(b)
        c="Gate enamel red" if j%2==0 else "Gate enamel ivory"
        for i in range(4):
            q=(i+1)%4
            f(m,"Tapered striped movable crossing barrier",c,(lo[i],lo[q],hi[q],hi[i]))
        if j==8:f(m,"Gate tip metal strike cap","Gate enamel red",hi[::-1])
    B(m,"Galvanized gate drive lever","Gate lever",.022,0,.110,.046,-.032,.029,.005)
    B(m,"Gate hinge counterweight shaped iron casting","Dark gear case",.101,0,.104,.058,-.055,.030,.010)
    B(m,"Bright counterweight yellow scale calibration edge","Brass bolt",.107,0,.064,.060,-.056,-.044,.004)
    T(m,"Gate tail spindle independently rotating cap","Galvanized steel",(0,-.035,0),(0,.038,0),.034,.029,16)
    for a in (-.27,-.63,-.844):
        T(m,"Barrier raised warm LED reflectors","Reflector",(a,.017,.004),(a,.020,.004),.020,.018,12)
    return m

def gate_pose(m,opened):
    a=UP if opened else 0
    c,s=cos(a),sin(a)
    x,z,y=PIVOT
    return move(m,lambda u,v,w:(x+u*c+w*s,z+v,y-u*s+w*c))

def lens(opened):
    m=mesh()
    X,Z=PIVOT[0]+.095,PIVOT[1]+.120
    for dx in (-.081,.081):
        x=X+dx
        T(m,"Ruby standby lenses" if opened else "Active bright red approach lenses",
          "Ruby unlit" if opened else "Ruby lit",(x,Z+.0325,.538),(x,Z+.041,.538),.048,.044,24)
        T(m,"Biconvex red center glass glint","Lamp red ring" if opened else "Ruby lens center",
          (x,Z+.0405,.538),(x,Z+.045,.538),.038,.025,20)
    return m

def render_atlas():
    def chunk(t,p):
        return struct.pack(">I",len(p))+t+p+struct.pack(">I",zlib.crc32(t+p))
    p=R.TEXTURES/"bl_level_crossing_atlas.png"
    span=bytes.fromhex("".join(v*8 for v in R.COLORS))
    p.write_bytes(b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",len(R.COLORS)*8,8,8,2,0,0,0))
                   +chunk(b"IDAT",zlib.compress((b"\0"+span)*8,9))+chunk(b"IEND",b""))

def stamp(filename,art,entity=False):
    p=R.MODELS/(filename+".obj")
    R.export_obj(p,art)
    vals=p.read_text().splitlines()
    vals[0]="# Original LuanTTD road/rail crossing art; tools/build_level_crossing_art.py"
    if entity:
        vals=[line if not line.startswith("v ") else "v "+" ".join(f"{float(k)*10:.6f}" for k in line.split()[1:])
              for line in vals]
    p.write_text("\n".join(vals)+"\n")

def install_scene(scene,base,seed,lights,mats,axis):
    b=bpy.data.collections.new("Road, rails, footings and signal apparatus")
    scene.collection.children.link(b)
    R.to_blender(base,b,mats)
    c=bpy.data.collections.new("Two animated independent gate hinges")
    scene.collection.children.link(c)
    for idx in range(2):
        q=(axis+idx*2)%4
        x,z,h=PIVOT
        x,z,h=((x,z,h),(-z,x,h),(-x,-z,h),(z,-x,h))[q]
        pivot=bpy.data.objects.new(f"Gate {idx+1}: direction fixture",None)
        c.objects.link(pivot)
        pivot.location=(x,z,h)
        pivot.rotation_euler.z=q*pi/2
        moving=bpy.data.objects.new(f"Gate {idx+1}: hinge angle (animated around local Y)",None)
        moving.empty_display_type="ARROWS";moving.empty_display_size=.096
        c.objects.link(moving);moving.parent=pivot
        armcoll=bpy.data.collections.new(f"Gate {idx+1} editable movable steel and stripes")
        c.children.link(armcoll)
        R.to_blender(seed,armcoll,mats)
        for ob in armcoll.objects:ob.parent=moving
        for tick,val in ((1,UP),(14,UP),(36,0),(53,0),(79,UP)):
            moving.rotation_euler.y=val
            moving.keyframe_insert(data_path="rotation_euler",index=1,frame=tick)
    visual=bpy.data.collections.new("Static neutral ruby lens preview")
    scene.collection.children.link(visual)
    R.to_blender(lights,visual,mats)
    scene["native deck"]="Standard rail tread +.114, gap .147..183; road approaches +.002 to +.108 above the terrain"
    scene["native arm FK"]="Rail X / road Z (axis 0), centered pivot (x,z,h)=(.487,.704,.290), companion point = yaw180. Open 82 degrees."
    scene.frame_start=1;scene.frame_end=79
    scene.frame_set(1)

def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    street_seed=mesh();street(street_seed)
    post=mesh();sign_base(post)
    post_pair=merge(post,turn(post,2))
    seed=arm()
    base={}
    geos=R.Geos()
    mats=R.materials()
    for i,name in enumerate(EXTRA,start=len(TRACK)):mats[i].name=name
    for axis in (0,1):
        rail=R.rail_geometry(1<<axis,0,geos,detail=True)
        base[axis]=merge(rail,turn(street_seed,axis),turn(post_pair,axis))
        stamp(f"bl_level_crossing_{axis}",base[axis])
        for opened in (True,False):
            a=gate_pose(seed,opened)
            pair=merge(a,turn(a,2))
            l=lens(opened)
            overlays=turn(merge(pair,l,turn(l,2)),axis)
            state="open" if opened else "closed"
            stamp(f"bl_level_crossing_gate_{axis}_{state}",overlays)
            stamp(f"bl_level_crossing_{axis}_{state}",merge(base[axis],overlays))
    stamp("bl_level_crossing_arm",move(seed,lambda x,z,h:(x-.5,z-.5,h+.5)),entity=True)
    render_atlas()
    scenes=(bpy.context.scene,bpy.data.scenes.new("Rail Z, road X"))
    scenes[0].name="Rail X, road Z"
    for axis,scene in enumerate(scenes):
        preview=lens(True)
        install_scene(scene,base[axis],seed,turn(merge(preview,turn(preview,2)),axis),mats,axis)
    bpy.context.window.scene=scenes[0]
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":
                a=area.spaces.active
                a.shading.color_type="MATERIAL"
                a.region_3d.view_location=(0,0,.25)
                a.region_3d.view_distance=3.6
                a.region_3d.view_rotation=(Vector((0,0,.1))-Vector((2.0,3.2,2.7))).to_track_quat("-Z","Y")
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art/level_crossing.blend"),compress=True)
    if destination:=os.environ.get("LEVEL_CROSSING_RENDER"):
        review(scenes[0],Path(destination),mats)

def review(scene,path,mats):
    g=mesh()
    r(g,"Artist reference grass","Bed backdrop",-4,4,-4,4,-.002)
    c=bpy.data.collections.new("Grass and neighboring approaches, render only")
    scene.collection.children.link(c)
    for s in (-1,1):
        x0,x1=sorted((s,s*4))
        r(g,"Outside approaching asphalt road","Road asphalt",-ROAD_EDGE,ROAD_EDGE,x0,x1,0)
        r(g,"Outside flat gravel shoulder","Road warm gravel",-ROUGH_EDGE,-ROAD_EDGE,x0,x1,0)
        r(g,"Outside flat gravel shoulder","Road warm gravel",ROAD_EDGE,ROUGH_EDGE,x0,x1,0)
        for i in range(7):
            p,q=sorted((s*(1.08+.43*i),s*(1.23+.43*i)))
            r(g,"Adjacent paint center dashes","Paint stripe",-.020,.020,p,q,.0015)
    R.to_blender(g,c,mats)
    rail=R.rail_geometry(1,0,R.Geos())
    for a in (-4,-2,2,4):
        R.to_blender(move(rail,lambda x,z,h:(x+a,z,h)),c,mats)
    cam=bpy.data.cameras.new("Crossing leading view")
    co=bpy.data.objects.new("Crossing leading view",cam)
    scene.collection.objects.link(co)
    scene.camera=co
    cam.type="ORTHO";cam.ortho_scale=3.28
    co.location=(1.97,3.12,1.79)
    co.rotation_euler=(Vector((-.054,.008,.29))-co.location).to_track_quat("-Z","Y").to_euler()
    scene.render.engine="BLENDER_WORKBENCH"
    scene.render.resolution_x=1264;scene.render.resolution_y=830
    scene.render.resolution_percentage=100
    scene.display.shading.light="STUDIO"
    scene.display.shading.color_type="MATERIAL"
    scene.display.shading.show_shadows=True
    scene.display.shading.show_cavity=True
    scene.display.shading.cavity_type="BOTH"
    scene.display.shading.background_type="WORLD"
    scene.world=bpy.data.worlds.new("Light country sky")
    scene.world.color=(.135,.20,.25)
    scene.view_settings.view_transform="Standard"
    for frame,s in ((1,"open"),(42,"closed")):
        if frame>1:
            scene.collection.children["Static neutral ruby lens preview"].hide_render=True
            m=lens(False)
            R.to_blender(merge(m,turn(m,2)),c,mats)
        scene.frame_set(frame)
        scene.render.filepath=str(path.with_name(path.stem+"-"+s+".png"))
        bpy.ops.render.render(write_still=True)

if __name__=="__main__":main()

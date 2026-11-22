#!/usr/bin/env python3
"""Original timber-mounted overhead for the exact native wooden rail bridge."""
from pathlib import Path
import sys
import bpy
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_rail_catenary_art as C
import build_road_bridge_art as bridge
R=C.R
STEM="bl_rail_bridge_catenary"
# Existing timber bearers in tools/build_rail_span_art.py reach ±.545
# transversely, are centered at along=.27 and run from deck-.145 to -.059.
V=.27


class Path:
    is_straight=True

    def sample(self,t):
        return 0,2*t-1,0,1

    def offset(self,t,offset):
        return -offset,2*t-1


def support(m,side,h):
    """Bolted steel saddle on the actual transverse timber, not a dirt pylon."""
    B,D,bar=C.B,C.D,C.bar
    S=lambda u:side*u
    dark="Mast steel shadow tension flange"
    steel="Braced period blue-grey steel mast"
    edge="Satin warm galvanized beam edge"
    hardware="Raised copper end clamps"
    insulation="Porcelain warm bleached insulator"
    # Shoe surrounds the outside end of the 0.086-wide load-bearing cross
    # timber; bolts feed into that beam. 0.065 exterior stand-off clears both
    # the existing fence and its local upright hardware.
    B(m,"Channel shoe sockets over end of actual wooden bridge bearer",dark,
      S(.553),V,.056,.071,h-.137,h-.068,.005,edge)
    for delta in (-.036,.036):
        B(m,"Two bolted side cheek straps wrapping actual bridge bearer",steel,
          S(.527),V+delta,.085,.010,h-.144,h-.057,.003,edge)
        B(m,"Zinc plated clamp nuts seated on bridge bracket",hardware,
          S(.514),V+delta*1.14,.021,.012,h-.107,h-.092,.003)
    B(m,"Load transfer shelf from clamp to exterior mast shoe",steel,
      S(.580),V,.107,.075,h-.079,h-.057,.006,edge)
    bar(m,"Two paired steel console diagonals to bridge bearer",dark,
        (S(.539),V-.029,h-.133),(S(.606),V-.029,h-.060),.012,.012,edge)
    bar(m,"Two paired steel console diagonals to bridge bearer",dark,
        (S(.539),V+.029,h-.133),(S(.606),V+.029,h-.060),.012,.012,edge)
    B(m,"Bolted overhang pedestal isolated from guardrail",steel,
      S(.614),V,.078,.069,h-.059,h+.021,.008)
    for z in (V-.024,V+.024):
        D(m,"Visible exterior sleeve anchor nuts",hardware,(S(.640),z,0),
          .007,"h",h+.017,h+.030,7)
    B(m,"Upright bracketed bridge mast central H web",steel,
      S(.614),V,.027,.050,h+.016,h+1.185,.004)
    for u in (.592,.636):
        B(m,"Pair of real hot rolled outer mast flange plates",edge,
          S(u),V,.012,.064,h+.024,h+1.185,.004)
    B(m,"Capped steel bridge mast with shoulder overhang",steel,
      S(.614),V,.059,.066,h+1.182,h+1.209,.005)
    bar(m,"Main cantilever across bridge contact and messenger",steel,
        (S(.613),V,h+1.114),(0,V,h+1.068),.023,.021,edge)
    bar(m,"Triangular clear-running cantilever support",dark,
        (S(.614),V,h+.759),(S(.365),V,h+1.095),.014,.014,steel)
    for lo,r in ((1.016,.012),(1.031,.016),(1.047,.012)):
        D(m,"Three cast porcelain eaves on bridge suspension",insulation,
          (0,V,0),r,"h",h+lo,h+lo+.008,10)
    plate=C.messenger((V+1)/2)
    D(m,"Working hanging eye bears on messenger cable",dark,
      (0,V,0),.007,"h",h+plate+.004,h+1.067,8)
    bar(m,"Short insulated drop arm secures real contact at existing wire height",hardware,
        (S(.056),V,h+1.069),(0,V,h+C.WIRE+.012),.008,.009)
    bar(m,"Contact wire registration clip",edge,
        (-.019,V,h+C.WIRE+.010),(.019,V,h+C.WIRE+.010),.006,.007)


def variant(direction,ramp,pole):
    h=(lambda v:v/2) if ramp else (lambda v:.5)
    m=R.Mesh(lambda u,v:h(v))
    C.wire(m,Path())
    m.grade=lambda u,v:0
    if pole:
        # Keep support on the same geographical side through opposing heads.
        support(m,1 if direction in (1,2) else -1,h(V))
    dx,dz=bridge.DIRECTIONS[direction]
    out=R.Mesh(lambda u,v:0)
    for name,faces in m.parts.items():
        for indices,col in faces:
            pts=[m.vertices[name][i] for i in indices]
            out.tri(name,col,[(dz*u+dx*v,-dx*u+dz*v,y) for u,v,y in pts])
    return out


def configurations():
    for axis,direction in enumerate((2,1)):
        for pole in (0,1):
            yield f"span_{axis}_{pole}",direction,False,pole
    for head in ("flat","ramp"):
        for direction in range(4):
            yield f"head_{head}_{direction}",direction,head=="ramp",1


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    scene=bpy.context.scene
    scene.name="LuanTTD · timber railway bridge overhead and channel clamps"
    scene.view_settings.view_transform="Standard"
    scene["Mount"]="Both heads and the span mount at stock deck+1, even x/z; flat wire lower edge y=deck+1.398."
    scene["Contact"]="Ramps join physically; pitched rigid-pantograph contact not implied."
    scene["Mounting steel"]="Saddle mates existing timber bearer at v=.27, full beam u=±.545, under the guardrail."
    pal=C.mats()
    for i,(part,direction,ramp,pole) in enumerate(configurations()):
        name=f"{STEM}_{part}"
        m=variant(direction,ramp,pole)
        p=R.MODELS/f"{name}.obj"
        R.export_obj(p,m,vertical_origin=1)
        p.write_text("# Original timber bridge wire art · tools/build_rail_bridge_wire_art.py\n"+
                     p.read_text().split("\n",1)[1])
        col=bpy.data.collections.new(part)
        scene.collection.children.link(col)
        R.to_blender(m,col,pal)
        for ob in col.objects:
            ob.location=((i%4-1.5)*2.36,(i//4-1)*2.36,0)
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=="VIEW_3D":
                v=area.spaces.active
                v.shading.color_type="MATERIAL"
                v.region_3d.view_location=(0,0,.76)
                v.region_3d.view_rotation=Vector((5.4,-7.12,5.1)).to_track_quat("Z","Y")
                v.region_3d.view_distance=13
    bpy.ops.wm.save_as_mainfile(filepath=str(R.ROOT/"art/rail_bridge_catenary.blend"),compress=True)


if __name__=="__main__":
    main()

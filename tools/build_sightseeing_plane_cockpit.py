#!/usr/bin/env python3
"""Build the original windowed Sampson sightseeing cockpit; OBJ -Z is forward."""
from pathlib import Path
from math import sin, cos, pi
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1] / "mods" / "luanttd_core"
im = Image.new("RGB", (256, 256), "#292923")
d = ImageDraw.Draw(im)
col = {
    "outer": "#424f4b", "inside": "#808a78", "rubber": "#2a3430", "tan": "#a49c81",
    "shadow": "#393a36", "metal": "#304047", "leather": "#673f2d",
    "edge": "#a28d6e", "mahogany": "#49332a", "dialrim": "#1b2525", "brass": "#b49a61",
}
uv = {}
for i, (k, value) in enumerate(col.items()):
    x, y = (i % 8) * 16, (i // 8) * 16
    d.rectangle((x, y, x + 15, y + 15), fill=value)
    uv[k] = ((x + 8) / 256, 1 - (y + 8) / 256)

# Painted mahogany panel with physical black dial bezel, off-white division
# marks and mechanical needles; the separate in-game HUD shows actual flight data.
atlas = (3, 43, 252, 125)
d.rounded_rectangle(atlas, radius=6, fill="#51413a", outline="#baab82", width=2)
for y in range(49, 120, 3):
    d.line((7, y, 249, y), fill=("#55443a" if y % 2 == 0 else "#4b3c33"))
d.rectangle((82, 79, 169, 105), fill="#2f372f", outline="#b39b75", width=2)
d.text((104, 88), "SAMPSON", fill="#efe0ac")

def gauge(cx, cy, r, label, needle):
    d.ellipse((cx-r-3, cy-r-3, cx+r+3, cy+r+3), fill="#141c1b", outline="#bcab7a", width=2)
    d.ellipse((cx-r, cy-r, cx+r, cy+r), fill="#252f2c", outline="#837d66")
    for i in range(12):
        a=(i*260/11+140)*pi/180
        v=r-2
        d.line((cx+cos(a)*v,cy+sin(a)*v,cx+cos(a)*(v-3),cy+sin(a)*(v-3)),fill="#ddd8ae")
    a=needle*pi/180
    d.line((cx,cy,cx+cos(a)*(r-5),cy+sin(a)*(r-5)), fill="#d29763", width=2)
    d.ellipse((cx-2,cy-2,cx+2,cy+2), fill="#e9d6ab")
    d.text((cx-3*len(label), cy+r+4), label, fill="#e8dfad")

gauge(30,73,16,"AIR",302)
gauge(68,67,13,"RPM",313)
gauge(89,64,10,"PWR",320)
gauge(127,62,13,"HDG",252)
gauge(163,64,10,"PWR",295)
gauge(184,67,13,"ALT",312)
gauge(221,73,16,"VSI",258)
for x in (20,40,68,187,216,235):
    d.rectangle((x-2,111,x+3,118), fill="#202b25", outline="#8f876c")
    d.rectangle((x-1,112,x+2,114), fill="#a8a37f")

lines=["# Original sightseeing cockpit; local -Z forward.","o Sightseeing_Sampson_Cockpit"]
i=0
# Luanti 5.10's first-person camera follows the parent's real origin,
# not its attach offset. Export the cabin from the measured eye anchor.
SEAT = (0, 4.30, -2.45)

def poly(v, color=None, coords=None):
    global i
    n=len(v)
    lines.extend("v %.4f %.4f %.4f" % tuple(p-a for p,a in zip(t,SEAT)) for t in v)
    if coords is None: coords=[uv[color]]*n
    lines.extend("vt %.6f %.6f" % t for t in coords)
    lines.append("f "+" ".join(f"{i+j}/{i+j}" for j in range(1,n+1)))
    i+=n

def box(x0,y0,z0,x1,y1,z1,key):
    corners=[(x,y,z) for x in (x0,x1) for y in (y0,y1) for z in (z0,z1)]
    for indices in ((0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)):
        poly([corners[j] for j in indices],key)

def bar(p,q,width,key):
    # Square extrusion in the plane of each window panel; the closed shell
    # catches both diagonal structural geometry and reflected sky edges.
    dx,dy,dz=(q[j]-p[j] for j in range(3))
    length=(dx*dx+dy*dy+dz*dz)**.5
    axis=(dx/length,dy/length,dz/length)
    a=(axis[1],-axis[0],0)
    n=(a[0]**2+a[1]**2)**.5
    if n<1e-6: a,n=(1,0,0),1
    a=tuple(v/n for v in a)
    b=(axis[1]*a[2]-axis[2]*a[1],axis[2]*a[0]-axis[0]*a[2],axis[0]*a[1]-axis[1]*a[0])
    t=width*.5
    points=[]
    for c in (p,q):
        points.extend(tuple(c[i]+t*(m*a[i]+n*b[i]) for i in range(3))
                      for m,n in ((-1,-1),(1,-1),(1,1),(-1,1)))
    for js in ((0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)):
        poly([points[j] for j in js],key)

# A structural windshield frame with genuine openings (nothing obscures the
# world). Side glazing openings continue past the eye point on both sides.
for sign in (-1,1):
    x=2.49*sign
    top=(x,6.37,-6.79)
    bottom=(x,4.02,-7.29)
    pillar=(2.81*sign,6.48,-3.97)
    sill=(2.81*sign,3.91,-3.85)
    far=(2.87*sign,6.49,-.40)
    far_sill=(2.89*sign,3.83,-.40)
    for a,b,w,key in ((top,bottom,.23,"inside"),(top,pillar,.20,"inside"),(bottom,sill,.21,"edge"),
                      (pillar,sill,.18,"inside"),(pillar,far,.21,"inside"),(sill,far_sill,.21,"edge"),
                      (far,far_sill,.28,"inside")):
        bar(a,b,w,key)
    poly([bottom,sill,far_sill,(2.90*sign,2.46,1.5),(x,2.65,-7.0)],"leather")
    bar((2.75*sign,4.02,-5.80),(2.80*sign,4.00,-4.64),.14,"rubber")
bar((-2.49,6.37,-6.79),(2.49,6.37,-6.79),.25,"outer")
bar((-2.49,4.02,-7.29),(2.49,4.02,-7.29),.18,"outer")
bar((0,4.03,-7.28),(0,6.36,-6.80),.16,"inside")
poly([(-2.52,6.46,-6.79),(2.52,6.46,-6.79),(2.92,6.54,1.2),(-2.92,6.54,1.2)],"tan")
bar((-2.50,6.39,-6.83),(2.50,6.39,-6.83),.10,"rubber")
# Full-width upper bench and angled front panel; camera is in the cabin,
# not in front of this mesh. Instruments are close but below eyeline.
poly([(-2.51,3.99,-7.19),(2.51,3.99,-7.19),(2.61,3.99,-5.56),(-2.61,3.99,-5.56)],"shadow")
poly([(-2.61,3.97,-5.55),(2.61,3.97,-5.55),(2.55,2.40,-5.17),(-2.55,2.40,-5.17)],
     coords=[(3/256,1-43/256),(252/256,1-43/256),(252/256,1-125/256),(3/256,1-125/256)])
bar((-2.62,4.02,-5.54),(2.62,4.02,-5.54),.10,"edge")
# Visible yoke and throttle quadrant give the seat a cockpit silhouette.
bar((0,2.67,-4.34),(0,3.47,-4.93),.19,"metal")
bar((-.76,3.48,-4.89),(.76,3.48,-4.89),.14,"metal")
for s in (-1,1):
    bar((s*.76,3.39,-4.90),(s*.76,3.83,-4.91),.20,"rubber")
box(.89,2.96,-4.75,1.64,3.17,-4.21,"mahogany")
for x in (1.04,1.27,1.48):
    bar((x,3.13,-4.44),(x,3.55,-4.58),.09,"brass")
    box(x-.08,3.52,-4.66,x+.08,3.62,-4.50,"rubber")

(root/"models"/"bl_sightseeing_plane_cockpit.obj").write_text("\n".join(lines)+"\n")
im.save(root/"textures"/"bl_sightseeing_plane_cockpit_atlas.png", optimize=True)

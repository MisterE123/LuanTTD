"""Reusable geometry from LuanTTD's early-stock Blender road producer.

COORDINATES: local -Y nose, +Z elevation in Blender; Luanti exporter -Z nose.
This recovered primitive module does not write any in-game files itself.
"""
from math import cos, sin, tau
import build_rail_wagon_art as w

r,bpy,Vector=w.rail,w.bpy,w.Vector
B,C=w.slab,w.circular
P={}


def f(m,g,c,pts):m.face(g,P[c],pts)


def section_hull(m,name,rows,paint,finish=None):
    """Each row lists z and a CCW x/height contour; fixed open road axis."""
    sections=[[(x,z,y) for x,y in points] for z,points in rows]
    n=len(sections[0])
    assert all(len(a)==n for a in sections)
    f(m,name,finish or paint,sections[0]);f(m,name,finish or paint,sections[-1][::-1])
    for a,b in zip(sections,sections[1:]):
        for j in range(n):
            q=(j+1)%n
            col=paint if isinstance(paint,str) else paint[j]
            f(m,name,col,(a[j],b[j],b[q],a[q]))


def rod(m,name,c,a,b,t=.006):
    a,b=Vector(a),Vector(b)
    direction=(b-a).normalized()
    u=direction.cross(Vector((1,0,0) if abs(direction.z)>.85 else (0,0,1))).normalized()*t
    v=direction.cross(u)
    q,r0=(tuple(tuple(p+u*cos(tau*k/5)+v*sin(tau*k/5)) for k in range(5)) for p in (a,b))
    f(m,name,c,q[::-1]);f(m,name,c,r0)
    for i in range(5):
        j=(i+1)%5
        f(m,name,c,(q[i],q[j],r0[j],r0[i]))


def wheels(m,yf,yr,width,rad,trim,twin=False,extra_rear=()):
    for z,rear in ((yf,False),(yr,True))+tuple((z,True) for z in extra_rear):
        C(m,"Heavy straight axles","Axle grey",(0,z,rad),rad*.24,"x",-width,width,10)
        for s in (-1,1):
            x=s*width
            C(m,"Bulged rubber casings","Rubber",(x,z,rad),rad*.96,"x",-.035,.035,16)
            C(m,"Tread contact, no hover","Tyre scuff",(x,z,rad),rad,"x",-.023,.023,16)
            C(m,"Painted pressed steel wheel discs",trim,(x+s*.035,z,rad),rad*.59,"x",-.007,.007,14)
            C(m,"Greased center wheel hubs","Hub",(x+s*.041,z,rad),rad*.29,"x",-.007,.007,10)
            if twin and rear:
                C(m,"Twin rear inner tyre","Rubber",(x-s*.053,z,rad),rad*.94,"x",-.023,.023,16)
            for j in range(5):
                a=tau*j/5
                at=(x+s*.042,z+rad*.46*cos(a),rad+rad*.46*sin(a))
                C(m,"Individual wheel nuts","Rim",at,rad*.04,"x",-.002,.002,6)


def fender(m,label,x,z,y,outer,dx,c,start=.06,end=3.08):
    s=(1 if x>0 else -1)
    bands=[]
    for rr in (outer-.024,outer):
        bands.append([[(x+d,z+rr*cos(start+(end-start)*j/12),y+rr*sin(start+(end-start)*j/12)) for j in range(13)]
                       for d in (-s*dx/2,s*dx/2)])
    inner,outer=bands
    for i in range(12):
        j=i+1
        f(m,label,c,(outer[0][i],outer[0][j],outer[1][j],outer[1][i])[::s])
        f(m,label,"Roof dark",(inner[0][i],inner[1][i],inner[1][j],inner[0][j])[::s])
        for k in (0,1):
            f(m,label,c,(inner[k][i],outer[k][i],outer[k][j],inner[k][j])[::(s if k==0 else -s)])


def panes(m,g,x,z,width,bottom,top,frame,c="Glass"):
    s=1 if x>0 else -1
    B(m,g+" picture frame",frame,x,z,.013,width,bottom,top,.010)
    B(m,g+" blue glass",c,x+s*.009,z,.008,width-.023,bottom+.012,top-.013,.006)
    B(m,g+" bright top reflection","Glass glint",x+s*.014,z,.004,width-.033,top-.029,top-.019,.002)


def bus_frame(m,first,last,wide=.47):
    B(m,"Independent pressed steel chassis","Frame",0,(first+last)/2,wide,last-first,.131,.213,.034)
    B(m,"Packed gearbox casings","Axle grey",0,-.12,.183,.204,.085,.175,.026)
    B(m,"Underside fuel tank","Nurled iron",0,.204,.257,.208,.097,.166,.028)


def studio(scene):
    # Studio only: the recovered original production geometry routines above
    # are unchanged. No background lights/geometry can enter the mesh export.
    bpy.ops.mesh.primitive_plane_add(size=6,location=(0,0,-.003))
    material=bpy.data.materials.new("Aggregate grey studio pavement")
    material.diffuse_color=(.092,.105,.108,1)
    bpy.context.object.data.materials.append(material)
    bpy.ops.object.camera_add(location=(2.1,-2.5,1.65))
    scene.camera=bpy.context.object
    scene.camera.data.type="ORTHO"
    scene.camera.data.ortho_scale=1.98
    scene.render.engine="BLENDER_WORKBENCH"
    scene.world=bpy.data.worlds.new("Grey slate studio")
    scene.world.color=(.137,.159,.183)
    s=scene.display.shading
    s.light="STUDIO";s.color_type="MATERIAL";s.background_type="WORLD"
    s.show_shadows=True;s.show_cavity=True;s.cavity_type="BOTH"
    scene.view_settings.view_transform="Standard"

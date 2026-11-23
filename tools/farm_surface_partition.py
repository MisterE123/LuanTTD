"""Keep one owner for every farm surface, including same-height paint inlays.

A strip, pane or board can meet another piece, but two same-facing polygons
on one plane may never cover the same area. Subtract the detail from the
underlying polygon before exporting. Work on original convex pieces, not
individual rendered triangles, and retain their names and materials.
"""
from collections import defaultdict
from math import sqrt

EPS=1e-8


def sub(a,b):
    return tuple(x-y for x,y in zip(a,b))


def cross3(a,b):
    return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])


def plane(poly):
    for a,b in zip(poly[1:],poly[2:]):
        n=cross3(sub(a,poly[0]),sub(b,poly[0]))
        scale=sqrt(sum(c*c for c in n))
        if scale>EPS:
            n=tuple(c/scale for c in n)
            axis=max(range(3),key=lambda j:abs(n[j]))
            d=sum(a*b for a,b in zip(n,poly[0]))
            return axis,tuple(round(c,5) for c in (*n,d))
    return None,None


def project(p,axis):
    return (p[(axis+1)%3],p[(axis+2)%3])


def area(poly,axis):
    pts=[project(p,axis) for p in poly]
    return sum(a*d-b*c for (a,b),(c,d) in zip(pts,pts[1:]+pts[:1]))*.5


def bounds(poly,axis):
    x,y=zip(*(project(p,axis) for p in poly))
    return min(x),min(y),max(x),max(y)


def overlaps(a,b):
    return a[0]+EPS<b[2] and b[0]+EPS<a[2] and a[1]+EPS<b[3] and b[1]+EPS<a[3]


def split(poly,axis,a,b):
    ab=b[0]-a[0],b[1]-a[1]
    def dist(p):
        x,y=project(p,axis)
        return ab[0]*(y-a[1])-ab[1]*(x-a[0])
    ds=[dist(p) for p in poly]
    inside,outside=[],[]
    for i,(u,v) in enumerate(zip(poly,poly[1:]+poly[:1])):
        c,d=ds[i],ds[(i+1)%len(ds)]
        if c>=-EPS:inside.append(u)
        if c<=EPS:outside.append(u)
        if (c>EPS and d<-EPS) or (c<-EPS and d>EPS):
            t=c/(c-d)
            p=tuple(x+(y-x)*t for x,y in zip(u,v))
            inside.append(p)
            outside.append(p)
    return inside,outside


def subtract(poly,cover,axis):
    """Subtract a convex cover; straight cuts return zero or more convex pieces."""
    if area(cover,axis)<0:
        cover=cover[::-1]
    pts=[project(p,axis) for p in cover]
    inside,pieces=poly,[]
    for a,b in zip(pts,pts[1:]+pts[:1]):
        if abs(a[0]-b[0])+abs(a[1]-b[1])<EPS:
            continue
        inside,outside=split(inside,axis,a,b)
        if len(inside)<3 or abs(area(inside,axis))<EPS:
            return [poly] # no positive-area intersection
        if len(outside)>=3 and abs(area(outside,axis))>=EPS:
            pieces.append(outside)
    return pieces


def partition(faces):
    """Keep layers in order: later finish detail owns any equal plane overlap."""
    planes=defaultdict(list)
    buckets={}
    # Traverse frontmost paint/trim first. Original triangles/polys can
    # cover earlier layers even when they are themselves divided later.
    for order,name,material,poly in reversed(faces):
        axis,k=plane(poly)
        if k is None:
            continue
        box=bounds(poly,axis)
        fragments=[poly]
        for prior_box,prior in planes[k]:
            if overlaps(box,prior_box):
                fragments=[p for f in fragments for p in subtract(f,prior,axis)]
                if not fragments:break
        if fragments:
            buckets[order]=[(name,material,p) for p in fragments]
        planes[k].append((box,poly))
    for order in sorted(buckets):
        yield from buckets[order]

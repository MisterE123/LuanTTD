#!/usr/bin/env python3
"""Original dual-ended Millennium Z1 power/saloon cab, stock RC1 #55."""
# SPDX-License-Identifier: GPL-2.0-only
import sys
from pathlib import Path
import bpy
sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_stock_rail_f_art as F
import build_stock_x2001_art as Mono

B,D,Pipe=F.B,F.D,F.Pipe
M,R,W,J,G=F.M,F.R,F.W,F.J,F.G
PAL=Mono.PALETTE | {
 "Crimson plate":"a34548","Claret sill":"622c43","Pink mica satin":"c47574",
 "White ceramic roof":"cfdbd8","Gold handrail":"f1c065","Copper exhaust fin":"785a60",
}
P={name:i for i,name in enumerate(PAL)}
PATH=(
 (-.454,.127,.262,.106,.212),(-.441,.145,.278,.110,.232),
 (-.417,.166,.322,.115,.278),(-.386,.182,.371,.117,.325),
 (-.347,.195,.420,.122,.377),(-.284,.207,.458,.128,.414),
 (-.216,.213,.483,.129,.436),(-.112,.213,.486,.130,.440),
 (.260,.213,.486,.130,.440),(.375,.203,.478,.132,.421),(.427,.185,.457,.135,.391),
)

def body(mesh):
    for (z,*x),(w,*y) in zip(PATH,PATH[1:]):
        a,b=F.body_contour(*x),F.body_contour(*y)
        for i in range(len(a)):
            j=(i+1)%len(a)
            color=("Claret sill" if i in (0,1,17,18) else "White ceramic roof" if i in (7,8,9,10,11)
                   else "Pink mica satin" if i in (6,12) else "Crimson plate")
            F.face(mesh,"Closed continuously lofted cab and passenger saloon",color,
              ((a[i][0],z,a[i][1]),(b[i][0],w,b[i][1]),(b[j][0],w,b[j][1]),(a[j][0],z,a[j][1])))
    for i in (0,-1):
        z,*dims=PATH[i]
        points=[(x,z,y) for x,y in F.body_contour(*dims)]
        F.face(mesh,"Real closed end pressure bulkheads","Claret sill" if i<0 else "Crimson plate",
          points if i==0 else points[::-1])
    for side in (-1,1):
        def panel(n,c,z0,z1,h0,h1,offset=.004):
            F.skin_panels(mesh,n,c,PATH,side,z0,z1,h0,h1,offset)
        # Unlike X2001's smaller power-only body, this is a working cab
        # and a 25-seat saloon with two doors and five windows on each side.
        for z0,z1,h0,h1 in ((-.382,-.350,.296,.346),(-.347,-.294,.315,.394),(-.290,-.231,.321,.407)):
            panel("Driver wraparound window seal","Windshield rim",z0,z1,h0,h1)
            panel("Illuminated pilot panoramic panes","Cab glass",z0+.003,z1-.003,h0+.006,h1-.007,.006)
            panel("Light reflected by swept pilot panes","Cab reflected sky",z0+.007,z1-.008,h1-.021,h1-.007,.0075)
        for z in (-.142,-.058,.026,.110,.200):
            panel("Individual saloon pressure window frames","Windshield rim",z,z+.062,.320,.409)
            panel("Sunlit indigo passenger glass","Cab glass",z+.003,z+.059,.327,.401,.006)
            panel("Narrow horizontal upper reflection","Cab reflected sky",z+.006,z+.057,.382,.399,.0075)
        for z0,z1 in ((-.225,-.155),(.270,.362)):
            panel("Accessible side-entry pressure doors","Claret sill",z0,z1,.188,.415)
            for lo,hi in ((z0+.003,(z0+z1)/2-.002),((z0+z1)/2+.002,z1-.003)):
                panel("Independent powered door leaves","Pink mica satin",lo,hi,.194,.409,.006)
                panel("Clear door inserts","Cab glass",lo+.004,hi-.004,.327,.392,.007)
                panel("Yellow push-to-open buttons","Gold handrail",lo+.004,lo+.009,.250,.263,.010)
        panel("Continuous slim marker band","Gold handrail",-.220,.359,.281,.288,.004)
        for z in (-.200,.038,.210):
            B(mesh,"Marshalled train roof cooling slots","Copper exhaust fin",side*.035,z,.012,.047,.485,.496,.002)
        for z0,z1 in ((-.447,-.424),(.400,.422)):
            B(mesh,"Recessed tail and cab portal lights","Gold handrail",side*.095,(z0+z1)/2,.042,z1-z0,.190,.212,.003)
    B(mesh,"Belly suspension and pressurization cassette","Armature iron",0,.003,.276,.642,.086,.145,.009)
    B(mesh,"Reinforced reciprocal headstock","Suspension steel",0,.426,.158,.032,.111,.195,.004)
    B(mesh,"Stock guideway rear draw eye","Suspension steel",0,.454,.100,.038,.075,.113,.004)
    B(mesh,"Closed rear crew vestibule","Claret sill",0,.431,.148,.026,.197,.385,.006)
    B(mesh,"Independent rear gangway lamp","Amber tail",0,.442,.045,.012,.314,.337,.003)

def main():
    F.P=M.P=J.P=W.P=G.P=P
    M.PAL=PAL
    R.COLORS[:]=PAL.values()
    shell=F.make_mesh();full=F.make_mesh();gear=F.make_mesh()
    body(shell);body(full)
    for z in Mono.LOCKS:
        Mono.bogie(gear,54,z);Mono.bogie(full,54,z)
    stem="rail_millennium_z1"
    for suffix,geom in (("",full),("_body",shell)):
        R.export_obj(R.MODELS/f"bl_{stem}{suffix}.obj",W.local_obj(geom),generator=Path(__file__).name)
    F.atlas(stem,list(PAL.values()))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    sc=bpy.context.scene;sc.name="LuanTTD | RC1 Millennium Z1 #55"
    sc["Provenance"]="OpenTTD 16.0-RC1 stock row #55; original editable mesh and materials."
    sc["Physical consist"]="Fit this power/saloon head at both outer ends; the physical rear head faces the opposite direction."
    mats=M.colors()
    J.geometry(sc,"01 Closed power/saloon cab and actual door leaves",shell,mats)
    J.geometry(sc,"02 Native straddle carriers and guidance",gear,mats)
    F.render(sc,stem,None,center=.245)

if __name__=="__main__":main()

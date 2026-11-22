"""Original later-era compact FFP passenger ferry. Builds editable and native assets."""
from pathlib import Path
import os
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_harbor_ferry_art as H

bpy, V, B, M, Vector = H.bpy, H.V, H.B, H.M, H.Vector
NAME = "bl_ffp_passenger_ferry"
# −Y is stern; +Y is the bow before Blender's Luanti axis conversion.
FRAMES = [(-.93,.08),(-.89,.28),(-.72,.35),(-.41,.373),(-.06,.381),
          (.26,.364),(.51,.315),(.71,.244),(.89,.125),(1.02,.009)]


def vessel():
    V.profile_hull("Welded V-section passenger hull, ten frames",
        [(y,[(-w,.118),(-w*.97,.032),(-w*.91,-.004),(-w*.48,-.100),
             (-w*.12,-.145),(w*.12,-.145),(w*.48,-.100),(w*.91,-.004),(w*.97,.032),(w,.118)])
         for y,w in FRAMES],"sea green",
         ["sea green","boot white","red oxide","red oxide","red keel","red oxide",
          "red oxide","boot white","sea green","deck shade"])
    for i,(y,w) in enumerate(FRAMES[1:-1]):
        B("Welded deck plates",(0,y,.121),(w*1.87,.17,.013),"deck shade",.002)
    # Wide low enclosed saloon, no tall riveted superstructure or period mast.
    B("Main aluminium saloon",(0,-.160,.258),(.601,1.14,.267),"offwhite",.025)
    B("Low swept saloon roof",(0,-.163,.413),(.635,1.229,.062),"silver",.028)
    B("Raised wheelhouse",(0,.275,.454),(.359,.369,.186),"offwhite",.022)
    B("Bridge sun visor",(0,.286,.558),(.407,.405,.039),"deep green",.019)
    B("Bridge panoramic forward glass",(0,.466,.473),(.305,.012,.092),"dark glass",.006)
    B("Central forward windshield divider",(0,.474,.474),(.013,.011,.096),"silver",.002)
    B("Stern passenger entry door",(0,-.734,.259),(.167,.014,.236),"light glass",.007)
    for side in (-1,1):
        B("Waterline passenger rubbing rail",(side*.357,-.17,.101),(.025,1.19,.023),"rubber",.007)
        B("Continuous lower green trim band",(side*.301,-.151,.191),(.015,1.101,.044),"deep green",.003)
        B("Bridge wrap-around glass",(side*.183,.303,.475),(.013,.253,.083),"light glass",.003)
        for i in range(6):
            y=-.596+i*.170
            B("Individual dark saloon glazing",(side*.306,y,.300),(.012,.133,.091),"dark glass",.003)
            B("Brushed silver window sill",(side*.312,y,.250),(.009,.139,.012),"silver",.002)
            B("Window reflected sky ribbon",(side*.313,y,.328),(.007,.114,.011),"light glass",.002)
        for a,b in ((.42,.65),(.65,.83),(-.73,-.88)):
            wa=(.32 if a<.5 else .246) if a>0 else .242
            wb=(.244 if b<=.65 else .153) if b>0 else .156
            for y,w in ((a,wa),(b,wb)):
                H.rod("Bow and stern handrail vertical",(side*w,y,.128),(side*w,y,.222),.005,"silver",6)
            H.rod("Low open-deck handrail",(side*wa,a,.221),(side*wb,b,.221),.006,"silver",6)
        B("Wing navigation lamp",(side*.204,.289,.518),(.038,.036,.020),
          "tail" if side<0 else "green light",.005)
        B("Stacked enclosed liferaft pods",(side*.235,-.476,.463),(.111,.223,.069),"enamel",.026)
        H.rod("Separate steel propeller shaft",(side*.137,-.755,-.094),(side*.137,-.911,-.088),.014,"red keel",8)
    B("Rear exhaust and deck machinery",(0,-.57,.470),(.09,.112,.090),"steel",.010)
    H.rod("Short VHF aerial",(0,.317,.565),(0,.281,.674),.006,"silver",8)
    B("Forward radar sweep bar",(0,.285,.645),(.162,.035,.025),"offwhite",.009)
    B("Foredeck anchor capstan",(0,.804,.147),(.073,.070,.049),"chassis",.015)


def main():
    V.begin()
    bpy.context.preferences.filepaths.save_version=0
    vessel()
    s=bpy.context.scene
    s.name="LuanTTD / FFP Passenger Ferry, original enclosed motor vessel"
    bpy.ops.wm.save_as_mainfile(filepath=str(H.ROOT/"art/ffp_passenger_ferry.blend"),compress=True)
    ob=H.merge([o for o in s.objects if o.type=="MESH"])
    uv=ob.data.uv_layers.active or ob.data.uv_layers.new()
    for face in ob.data.polygons:
        idx=V.KEYS.index(ob.data.materials[face.material_index].name)
        for loop in face.loop_indices: uv.data[loop].uv=((idx+.5)/32,.5)
    bpy.ops.wm.obj_export(filepath=str(H.ROOT/"mods/luanttd_core/models"/(NAME+".obj")),
        export_selected_objects=True,export_materials=False,export_uv=True,export_normals=True,
        export_triangulated_mesh=True,global_scale=10,forward_axis="NEGATIVE_Z",up_axis="Y")
    if target:=os.getenv("LUANTTD_FFP_RENDER"):
        bpy.ops.object.camera_add(location=(2.9,4.1,3.2))
        cam=bpy.context.object
        cam.rotation_euler=(Vector((0,0,.18))-cam.location).to_track_quat("-Z","Y").to_euler()
        cam.data.type="ORTHO";cam.data.ortho_scale=2.6;s.camera=cam
        s.render.engine="BLENDER_WORKBENCH"
        s.render.resolution_x,s.render.resolution_y=860,600
        s.display.shading.color_type="MATERIAL";s.display.shading.show_cavity=True
        s.render.filepath=target;bpy.ops.render.render(write_still=True)


if __name__=="__main__":
    main()

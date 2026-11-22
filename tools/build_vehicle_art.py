"""Blender 4.3+; run blender -b -t 2 --python tools/build_vehicle_art.py."""
import math
import bpy
from pathlib import Path
root=Path(__file__).resolve().parents[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
palette={
    "Deep teal":"22656a", "Sun cream":"e7d29f", "Glass":"283b48",
    "Tires":"282d35", "Navy":"1c3540", "Chrome":"a7b3ae",
    "Lamp":"ffe4ab", "Brake":"9e352f", "Seat":"aa6947",
}
mats={}
for name,hexcolor in palette.items():
    srgb=[int(hexcolor[i:i+2],16)/255 for i in (0,2,4)]
    lin=[c/12.92 if c<.04045 else ((c+.055)/1.055)**2.4 for c in srgb]
    m=bpy.data.materials.new(name);m.diffuse_color=(*lin,1)
    mats[name]=m
def finish(obj,name,mat):
    obj.name=name
    obj.data.materials.append(mats[mat])
    return obj
def box(name,p,d,mat,bevel=0.):
    bpy.ops.mesh.primitive_cube_add(size=1,location=p)
    obj=finish(bpy.context.object,name,mat)
    obj.scale=d
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        m=obj.modifiers.new("Rounded corners","BEVEL");m.width=bevel;m.segments=2
        bpy.ops.object.modifier_apply(modifier=m.name)
    return obj
def wheel(name,p,radius,depth,mat):
    bpy.ops.mesh.primitive_cylinder_add(vertices=16,radius=radius,depth=depth,location=p,rotation=(0,math.pi/2,0))
    return finish(bpy.context.object,name,mat)
# Original fictional mid-century single-deck bus. Local +Y is the nose;
# floor z=0 in Luanti. No third-party sprites, models or textures are imported.
box("Hull",(0,0,.245),(.55,1.56,.23),"Deep teal",.035)
box("Window band",(0,0,.418),(.532,1.54,.23),"Sun cream",.06)
box("Roof",(0,-.012,.545),(.535,1.47,.13),"Sun cream",.055)
box("Front windscreen",(0,.766,.439),(.418,.022,.165),"Glass",.027)
box("Windscreen mullion",(0,.784,.436),(.012,.014,.157),"Chrome")
box("Rear glass",(0,-.768,.448),(.366,.025,.12),"Glass",.023)
for side in (-1,1):
    a=side*.266
    for i,pos in enumerate((-.60,-.37,-.14,.09,.32,.55)):
        box(f"Side {side} window {i+1}",(a,pos,.439),(.015,.175,.131),"Glass",.012)
    for pos in (-.445,.483):
        wheel("Rubber tyre",(side*.26,pos,.116),.121,.092,"Tires")
        wheel("Steel hub",(side*.31,pos,.116),.060,.018,"Chrome")
    box("Striping",(side*.279,.0,.327),(.014,1.43,.030),"Sun cream")
    box("Headlight",(side*.152,.783,.233),(.079,.021,.051),"Lamp",.01)
    box("Rear light",(side*.19,-.782,.224),(.058,.022,.035),"Brake",.009)
for y in (-.787,.787):
    box("Bumper",(0,y,.165),(.48,.057,.048),"Chrome",.015)
box("Radiator trim",(0,.779,.258),(.24,.022,.061),"Navy",.006)
for j in range(3):
    box("Radiator grille",(0,.793,.239+j*.016),(.201,.012,.005),"Chrome")
box("Door seam",(.277,.602,.338),(.011,.013,.252),"Navy")
box("Destination blind",(0,.776,.517),(.232,.015,.029),"Navy",.005)
box("Destination plate",(0,.784,.519),(.15,.010,.011),"Lamp")
bpy.context.scene.view_settings.view_transform="Standard"
bpy.context.scene.name="Bayline / Town Flyer bus"
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(root/"art/town_flyer.blend"),compress=True)
# OBJ gets a single texture. Map each face to its swatch, so it loads in
# Luanti without Blender-specific materials or a per-face material shader.
objects=[o for o in bpy.context.scene.objects if o.type=="MESH"]
bpy.ops.object.select_all(action="DESELECT")
for o in objects:o.select_set(True)
bpy.context.view_layer.objects.active=objects[0]
bpy.ops.object.join()
obj=bpy.context.object
uv=obj.data.uv_layers.active or obj.data.uv_layers.new()
if bpy.app.version>=(4,0,0):
    uv=obj.data.uv_layers.active
colors=list(palette)
for poly in obj.data.polygons:
    mat=obj.data.materials[poly.material_index].name
    sw=colors.index(mat)
    u=(sw+.5)/16
    for idx in poly.loop_indices:
        uv.data[idx].uv=(u,.5)
bpy.ops.wm.obj_export(filepath=str(root/"mods/bayline/models/bl_town_flyer.obj"),export_materials=False,
    export_selected_objects=True,export_uv=True,export_normals=True,export_triangulated_mesh=True,global_scale=10,forward_axis="NEGATIVE_Z",up_axis="Y")
def asset(key,fn):
    bpy.ops.object.select_all(action="SELECT");bpy.ops.object.delete(use_global=False)
    fn()
    objects=[o for o in bpy.context.scene.objects if o.type=="MESH"]
    bpy.context.scene.name="Bayline / "+key
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(root/f"art/{key}.blend"),compress=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.object.join()
    obj=bpy.context.object
    uv=obj.data.uv_layers.active or obj.data.uv_layers.new()
    for poly in obj.data.polygons:
        sw=colors.index(obj.data.materials[poly.material_index].name)
        for idx in poly.loop_indices: uv.data[idx].uv=((sw+.5)/16,.5)
    bpy.ops.wm.obj_export(filepath=str(root/f"mods/bayline/models/bl_{key}.obj"),export_materials=False,
        export_selected_objects=True,export_uv=True,export_normals=True,export_triangulated_mesh=True,global_scale=10,
        forward_axis="NEGATIVE_Z",up_axis="Y")
def cylinder(name,p,radius,count,depth,axis,mat,top=None):
    rotation={"x":(0,math.pi/2,0),"y":(math.pi/2,0,0),"z":(0,0,0)}[axis]
    if top is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=count,radius=radius,depth=depth,location=p,rotation=rotation)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=count,radius1=radius,radius2=top,depth=depth,location=p,rotation=rotation)
    return finish(bpy.context.object,name,mat)
def trucks(ys,rail=False):
    for y in ys:
        for side in (-1,1):
            x=side*(.212 if rail else .26)
            wheel("Wheel",(x,y,.115),.113,.094,"Tires")
            wheel("Hub",(x+side*.044,y,.115),.065,.021,"Chrome")
def lorry():
    box("Chassis",(0,0,.20),(.44,1.52,.09),"Navy")
    box("Steel cab",(0,.46,.39),(.51,.60,.345),"Brake",.055)
    box("Windscreen",(0,.766,.44),(.375,.016,.12),"Glass",.015)
    box("Cargo box",(0,-.351,.40),(.60,.82,.43),"Sun cream",.025)
    for side in (-1,1):
        box("Cab glass",(side*.252,.49,.44),(.014,.285,.10),"Glass",.014)
        box("Side trim",(side*.302,-.351,.32),(.009,.80,.055),"Brake")
        box("Headlight",(side*.167,.775,.266),(.079,.015,.043),"Lamp")
    trucks((-.45,.51))
def coach():
    box("Bottom skirt",(0,0,.23),(.54,1.70,.29),"Deep teal",.04)
    box("Coach cabin",(0,0,.47),(.525,1.69,.285),"Sun cream",.065)
    box("Panoramic screen",(0,.841,.46),(.417,.017,.17),"Glass",.033)
    for x in (-1,1):
        for y in (-.643,-.381,-.119,.143,.405,.646):
            box("Window",(x*.262,y,.459),(.015,.201,.139),"Glass",.012)
        box("Livery stripe",(x*.273,0,.328),(.013,1.55,.052),"Chrome")
    trucks((-.525,.525))
def steam():
    box("Locomotive frame",(0,0,.192),(.44,1.69,.13),"Navy",.018)
    cylinder("Boiler",(0,.153,.395),.163,20,.96,"y","Deep teal")
    cylinder("Smokebox",(0,.647,.395),.151,20,.125,"y","Navy")
    cylinder("Chimney",(0,.52,.622),.067,16,.205,"z","Navy",.047)
    cylinder("Dome",(0,.09,.564),.089,16,.14,"z","Chrome",.068)
    box("Cab",(0,-.48,.42),(.45,.41,.37),"Deep teal",.018)
    box("Cab roof",(0,-.48,.618),(.501,.457,.068),"Navy",.023)
    for x in (-1,1):
        box("Side cab window",(x*.226,-.465,.5),(.014,.19,.142),"Glass",.016)
    box("Buffer beam",(0,.803,.22),(.434,.084,.08),"Brake")
    cylinder("Lamp",(0,.743,.44),.036,16,.08,"y","Lamp")
    trucks((-.46,-.183,.08,.56),True)
def diesel(electric=False):
    box("Frame",(0,0,.184),(.444,1.76,.105),"Navy",.018)
    box("Body",(0,0,.352),(.465,1.689,.286),"Deep teal" if electric else "Brake",.065)
    box("Cab + roof",(0,.30 if not electric else 0,.546),(.46,1.48 if electric else .564,.19),"Sun cream",.034)
    box("Front glass",(0,.755 if electric else .579,.539),(.365,.016,.099),"Glass",.017)
    for x in (-1,1):
        for y in (-.51,.166,.40):
            box("Side window/louver",(x*.234,y,.52),(.014,.175,.078),"Glass",.01)
        box("Stripe",(x*.234,0,.298),(.015,1.49,.038),"Sun cream")
    if electric:
        box("Roof electrical box",(0,-.27,.663),(.277,.265,.066),"Navy")
        obj=box("Pantograph arm",(0,-.28,.746),(.026,.27,.024),"Chrome"); obj.rotation_euler[0]=.35
        box("Pantograph contact",(0,-.153,.793),(.171,.038,.024),"Chrome")
    trucks((-.61,-.34,.34,.61),True)
def hull(name,length,beam):
    verts=[]
    for scale,z in ((.78,.03),(1,.18)):
        for x,y in ((0,.54),(-.43,.31),(-.5,-.33),(-.28,-.48),(.28,-.48),(.5,-.33),(.43,.31)):
            verts.append((x*beam*scale,y*length,z))
    faces=[tuple(range(6,-1,-1)),tuple(range(7,14))]
    for i in range(7):faces.append((i,(i+1)%7,(i+1)%7+7,i+7))
    me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update()
    ob=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(ob);finish(ob,name,"Deep teal")
def boat(cargo=False):
    hull("Hull",1.82,.66)
    if cargo:
        box("Aft wheelhouse",(0,-.43,.32),(.365,.38,.28),"Sun cream",.023)
        box("Containers",(0,.174,.264),(.367,.60,.155),"Brake",.009)
        for y in (-.098,.08,.251,.423):
            box("Container divisions",(0,y,.342),(.372,.018,.019),"Chrome")
    else:
        box("Passenger deck",(0,-.11,.297),(.466,1.05,.238),"Sun cream",.038)
        for x in (-1,1):
            for j in range(5):box("Passenger window",(x*.232,-.48+j*.18,.327),(.013,.13,.082),"Glass",.008)
        box("Bridge",(0,.272,.451),(.361,.283,.124),"Sun cream",.024)
    cylinder("Funnel",(0,-.39,.517),.069,16,.219,"z","Navy",.053)
def plane(jet=False):
    fus=cylinder("Fuselage",(0,0,.204),.118,20,1.52,"y","Sun cream")
    fus.scale[0]=1.1
    obj=cylinder("Nose",(0,.837,.204),.116,20,.253,"y","Sun cream",.032);obj.rotation_euler[0]=-math.pi/2
    box("Cockpit windows",(0,.731,.30),(.153,.130,.043),"Glass",.015)
    for sign in (-1,1):
        wing=box("Wing",(sign*.43,-.064,.198),(.836,.265,.030),"Chrome",.012)
        wing.rotation_euler[2]=-sign*(.315 if jet else .09)
        tail=box("Tailplane",(sign*.203,-.604,.216),(.387,.173,.028),"Deep teal",.009)
        tail.rotation_euler[2]=-sign*.2
        cylinder("Engine",(sign*.345,-.02,.155),.073,16,.278,"y","Deep teal")
        if not jet:
            prop=box("Propeller",(sign*.345,.126,.154),(.025,.028,.238),"Navy",.006)
            prop.rotation_euler[1]=sign*.56
    box("Fin",(0,-.61,.339),(.043,.231,.243),"Deep teal",.020)
for key,fn in (("truck",lorry),("coach",coach),("steam",steam),("diesel",diesel),
    ("electric",lambda:diesel(True)),("ferry",boat),("freighter",lambda:boat(True)),
    ("prop",plane),("jet",lambda:plane(True))):
    asset(key,fn)

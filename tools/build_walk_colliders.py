#!/usr/bin/env python3
"""Export bounded Walk hulls from original game OBJ assets (no engine-time parsing).

Building hulls are face-connected mesh components. Keep a bounded number
of structural volumes and leave foliage and openings clear. Rail fences
follow authored steel posts, not a diagonal rectangle. Forest meshes reuse
the same narrow stem hulls across lifts. All data is fixed-point 1/128 node.
"""
import argparse
import re
from collections import defaultdict
from math import floor, ceil, dist, prod
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "mods/luanttd_core"
OUT = ROOT / "walk_collision_art.lua"
MIN_DIM = (.069, .165, .069)
SKIP = {0x09,0x0a,0x0b,0x0c,0x14,0x20}


def components(path, section=None):
    """Union faces sharing a position, including OBJ duplicates across UV seams."""
    coords, seen, groups, parents = [], {}, defaultdict(list), []
    active = section is None

    def root(a):
        while parents[a] != a:
            parents[a] = parents[parents[a]]
            a = parents[a]
        return a

    for line in path.read_text().splitlines():
        if section and line.startswith("# "):
            active = section.lower() in line.lower()
        if line.startswith("v "):
            x, y, z = map(float, line.split()[1:4])
            p = (-round(x, 5), round(y, 5), round(z, 5))
            coords.append(seen.setdefault(p, len(seen)))
            if len(parents) < len(seen):
                parents.append(len(parents))
        elif active and line.startswith("f "):
            ix = [coords[int(v.split("/")[0])-1] for v in line.split()[1:]]
            a = root(ix[0])
            for b in ix[1:]:
                parents[root(b)] = a
            for i in ix:
                groups[i].append(True)
    result = defaultdict(list)
    for p, i in seen.items():
        if i in groups:
            result[root(i)].append(p)
    return result.values()


def bounds(points):
    axes = list(zip(*points))
    return tuple(min(q) for q in axes) + tuple(max(q) for q in axes)


def dims(b):
    return tuple(b[i+3] - b[i] for i in range(3))


def fixed(b):
    return tuple(floor(b[i]*128+1e-6) if i<3 else ceil(b[i]*128-1e-6) for i in range(6))


WALL_CLEARANCE = .04


def wall_padding(b, axis=None):
    # Walker eye stays just outside the actual facade under lag or camera
    # bob. Expand collision half-width horizontally only.
    out=list(b)
    for i in ((0,2) if axis is None else (axis,)):
        out[i]-=WALL_CLEARANCE
        out[i+3]+=WALL_CLEARANCE
    return out


def buildings(path):
    ranked = []
    for points in components(path):
        b = bounds(points)
        size = dims(b)
        if all(a >= low for a, low in zip(size, MIN_DIM)) and prod(size) > .013:
            ranked.append((prod(size), b))
    selected = []
    for _, b in sorted(ranked, reverse=True):
        if not any(all(a[i]<=b[i] and a[i+3]>=b[i+3] for i in range(3)) for a in selected):
            selected.append(b)
        if len(selected) == 6:
            break
    return tuple(fixed(wall_padding(b) if b[1]<-.37 and dims(b)[1]>.24 else b)
                 for b in selected)


def railway(path):
    # Authored comments delimit geometry, including 5 individual closed posts
    # per boundary. Order each line by its coordinates relative to the anchor.
    posts=[bounds(p) for p in components(path, "steel posts")]
    points=[((b[0]+b[3])/2,(b[2]+b[5])/2,b[1],b[4]) for b in posts]
    todo=set(points)
    lines=[]
    while todo:
        queue=[min(todo)]
        todo.remove(queue[0])
        for p in queue:
            nearby=sorted(q for q in todo if dist(p[:2],q[:2]) <= .73)
            for q in nearby:
                todo.remove(q)
                queue.append(q)
        lines.append(sorted(queue))
    assert lines and all(len(line)==5 for line in lines), (path, lines)
    boxes=[]
    for line in lines:
        diagonal=line[0][0]!=line[-1][0] and line[0][1]!=line[-1][1]
        for a,b in zip(line,line[1:]):
            segs=2 if diagonal else 1
            for i in range(segs):
                p,q=[tuple(a[j]+(b[j]-a[j])*u for j in range(4)) for u in (i/segs,(i+1)/segs)]
                boxes.append(fixed((min(p[0],q[0])-.017,min(p[2],q[2]),min(p[1],q[1])-.017,
                               max(p[0],q[0])+.017,min(p[3],q[3]),max(p[1],q[1])+.017)))
    assert len(boxes)<=8
    return tuple(boxes)


def named_groups(path, names):
    vertices, groups = [], []
    selected = False
    for line in path.read_text().splitlines():
        if line.startswith("o "):
            selected = any(t in line[2:].lower() for t in names)
            if selected:
                groups.append([])
        elif line.startswith("v "):
            x,y,z=map(float,line.split()[1:4])
            vertices.append((-x,y,z))
        elif selected and line.startswith("f "):
            groups[-1].extend(vertices[int(v.split("/")[0])-1] for v in line.split()[1:])
    return groups


def parcel_fences(path):
    # Blender's old parcel exporter did not assign these rails object names.
    # Find independent low continuous strips joined to a repeating row of
    # actual upright posts; do not bridge doorways between separate strips.
    boxes=[bounds(q) for q in components(path)]
    out=[]
    for b in boxes:
        x,y,z=dims(b)
        if not (b[1]<-.24 and b[4]<-.19 and .27<max(x,z)<1.60 and min(x,z)<.065 and y<.09):
            continue
        align=0 if x>z else 2
        cross=2-align
        posts=[]
        for q in boxes:
            qx,qy,qz=dims(q)
            if (q[1]<-.455 and .18<qy<.33 and max(qx,qz)<.073 and
                    q[align]>=b[align]-.04 and q[align+3]<=b[align+3]+.04 and
                    q[cross]<b[cross+3]+.045 and q[cross+3]>b[cross]-.045 and
                    q[4]>b[4]-.008):
                posts.append(q)
        if len(posts)<3:
            continue
        hull=list(b)
        hull[1]=min(q[1] for q in posts)
        hull[4]=max(q[4] for q in posts)
        hull[cross]=min(hull[cross],*(q[cross] for q in posts))
        hull[cross+3]=max(hull[cross+3],*(q[cross+3] for q in posts))
        r=fixed(hull)
        if not any(abs(r[cross]-v[cross])<=4 and abs(r[align]-v[align])<=6 and
                   abs(r[align+3]-v[align+3])<=6 for v in out):
            out.append(r)
    return tuple(out[:4])


def farm_buildings(path):
    names=("longitudinal_boarded_frame","north_boarded_frame","narrow_front_pier",
           "front_clapboard_elevation","shell","pitched_dressed",
           "boundary_hewn_rail","paddock_hewn_rail","corral_hewn_rail","boundary_board")
    out=[]
    for points in named_groups(path,names):
        if not points: continue
        b=list(bounds(points)); x,y,z=dims(b)
        if min(x,z)<.005 or max(x,z)<.07: continue
        if y<.10 and not (b[4]>-.29 and max(x,z)>.29):continue
        if .02<y<.10: b[1]=-.50
        if b[1]<-.35 and y>.32:
            # Only deepen the facade normal of narrow wall strips;
            # never shrink a loading doorway along its width.
            axis=(0 if x<z else 2) if min(x,z)<max(x,z)*.32 else None
            b=wall_padding(b,axis)
        out.append((prod(dims(b)),fixed(b)))
    # Closed silo shells keep their footprint collision. Dedicated wall
    # pieces leave a cart shed's loading doors and paths open.
    return tuple(b for _,b in sorted(out,reverse=True)[:12])


# Original industry builders name the load-bearing components and export each
# finished/construction stage as a separate mesh. Select actual structure,
# never a footprint/roof envelope. The order is significant: a solid deck
# supports Walk, but roof canopies, ladders, rails and gauges are not walls.
INDUSTRIES = ("industry_factory_", "industry_layout_gfx_", "industry_iron_mine_",
              "industry_steel_mill_", "industry_oil_rig_", "industry_oil_refinery_",
              "industry_oil_well_", "industry_temperate_bank_", "coal_mine_",
              "power_station_", "sawmill_", "forest_")
DECK = re.compile(r"(working_deck.*spill_tray|boat_transfer_landing$|load-bearing_helideck|"
                  r"shadowed_internal_factory_loading_floor|dispatch_loading_platform_stone_wall|"
                  r"individually_clamped_working_floor|open_worker_gallery_decking|"
                  r"open_grippy_maintenance_bridge|mine_hoist_machine-room_stone_floor|covered_service_catwalk)")
WALL = re.compile(r"(walls?$|endwall$|masonry_(?:front|rear|side)_elevation|"
                  r"brick_(?:rear|side)_elevation|weatherboards(?:_below_windows)?$|"
                  r"wall$|wall_waist|deep_masonry_edge_to_working_bay|solid_ashlar_volume|load-bearing_brickwork|_red_brick$|"
                  r"structural_outer_pier_on_either_side_of_open_drive|wall_mass|long_side_masonry|city.*terminal.*volume)")
BODY = re.compile(r"(closed_.*(?:body|volume)|solid_.*volume|machine-room|"
                  r"cylindrical_shell|rounded_wet_receiving_tank|"
                  r"wrought_blast_furnace_process_shell|riveted_transformer_tank|"
                  r"transformer_tank$|brick_chimney|masonry_freight_elevator_tower|"
                  r"gearbox$|calibrated_pump_body|engine_block|"
                  r"stack_of|stacked_|_stacks?$|stockpile_(?:underside|apex)|"
                  r"_terraced_strata|contained_material_bay|"
                  r"living_module_base|_shed_main_body|_log_bundle|"
                  r"braced_hopper_frame|wide_ore_storage_bin|broad_steel_shrouds|"
                  r"covered_exchange_core|low-pressure_condenser_vessel|polished_production_casing|"
                  r"masonry_smoke_shaft|tapered_body_jagged_layered_surfaces|coal_stockpile_faces|surge_bin$|tapered_coal_bunker_external_sides|"
                  r"drums_with_closed_rims|tapered_bark$|tapered_evergreen_trunks|cooling_tower.*housing|horizontal_finned_exchanger_barrel|"
                  r"lighthouse_masonry_shafts|ashlar_quarters_with|control_tower.*masonry|panoramic_windows|closed_terminal_envelope|"
                  r"stack_bluestone_foundation|dressed_flue_foot_plinth|chimney_foot_sandstone_set-off)")
COLUMN = re.compile(r"(legs?$|uprights?$|stanchion$|pier$|column$|bolted_cast_footing|"
                    r"tubular_deck_support|landing_hoist_shoe|"
                    r"structural_.*(?:timber|concrete)_post$|load-bearing_plinth|"
                    r"pedestal_and_crank|submerged_battered_steel_piles|working_bay_width|articulated_grade_stand|cast_support_footing|gantry_post$|"
                    r"_piers?$|stone_jambs|supporting_stone_legs|concourse.*structural_plinth)")
TRIM = re.compile(r"(window|glazing|paint|letter|bolt(?!ed_cast_footing)|gear_teeth|ladder|"
                  r"roof|railing|guardbar|handrail|fence|lattice|cross-brac|"
                  r"pallet|curb|tire_track|gutters?|buffer_|perimeter_marker|"
                  r"platform_[a-z]*stanchion|truss|plaster|decal|grit|fleck|"
                  r"underside|fine-grain|sill$|_cames?|panel_stile|"
                  r"strip|lobed_shale|rung|recessed_band|_access_floor)")


def industry_role(name):
    if DECK.search(name):
        return "deck"
    if TRIM.search(name):
        return None
    if WALL.search(name):
        return "wall"
    if BODY.search(name):
        return "body"
    if COLUMN.search(name):
        return "column"


def industry_parts(path):
    # Keep objects distinct, and union faces only within that object. This
    # preserves e.g. separate loading-door piers defined in the same group.
    vertices, ids, keys, parents = [], {}, [], []
    role = None

    def root(a):
        while parents[a] != a:
            parents[a] = parents[parents[a]]
            a = parents[a]
        return a

    def finish():
        groups = defaultdict(list)
        for j,p in enumerate(keys):
            groups[root(j)].append(p)
        return [bounds(points) for points in groups.values()]

    for ln in path.read_text().splitlines():
        if ln.startswith("v "):
            x,y,z=map(float,ln.split()[1:4])
            vertices.append((-round(x,5),round(y,5),round(z,5)))
        elif ln.startswith("o "):
            if role:
                for b in finish():
                    yield role,b
            role=industry_role(ln[2:].lower())
            ids,keys,parents={},[],[]
        elif role and ln.startswith("f "):
            indices=[]
            for v in ln.split()[1:]:
                k=vertices[int(v.split("/")[0])-1]
                if k not in ids:
                    ids[k]=len(keys); keys.append(k); parents.append(len(parents))
                indices.append(ids[k])
            a=root(indices[0])
            for j in indices[1:]:
                parents[root(j)]=a
    if role:
        for b in finish():
            yield role,b


def industry_buildings(path):
    ranks={"deck":4,"wall":3,"body":2,"column":1}
    selected=[]
    for role,b in industry_parts(path):
        # Avoid deep underwater parts increasing the native map-wide
        # collision-search extent; swimmers still meet exposed piles.
        if b[1]<-.5: b=(*b[:1],-.5,*b[2:])
        x,y,z=dims(b)
        if min(x,z)<.030 or y<.022 or max(x,z)<.066 or b[4]<=-.426:
            continue
        if role=="deck":
            if x<.15 or z<.12:
                continue
        elif y<(.060 if role=="column" else .10) or min(x,z)<.042:
            continue
        # A named deck can be traversed from its top. Ordinary roofs and
        # overhead conveyor decoration are not bridged across their columns.
        if role=="wall" and y>.23 and min(x,z)<max(x,z)*.38:
            b=wall_padding(b,0 if x<z else 2)
        elif role=="wall" and y>.29 and b[1]<-.31:
            b=wall_padding(b)
        selected.append((ranks[role],prod((x,min(y,.65),z)),fixed(b)))

    # Adjacent masonry/weatherboards that already share their other four
    # coordinate planes may be merged without changing the occupied volume.
    # Never bridge even a one-quantum gap (could be a split doorway).
    merged=[]
    for rank,size,box in sorted(selected,reverse=True):
        changed=True
        while changed:
            changed=False
            for i,(prior,_,a) in enumerate(merged):
                if prior!=rank: continue
                for axis in (0,1,2):
                    k=[j for j in range(6) if j%3 != axis]
                    if all(a[j]==box[j] for j in k) and max(a[axis],box[axis])<=min(a[axis+3],box[axis+3]):
                        b=list(box)
                        b[axis],b[axis+3]=min(a[axis],box[axis]),max(a[axis+3],box[axis+3])
                        box=tuple(b)
                        merged.pop(i)
                        changed=True
                        break
                if changed: break
        merged.append((rank,prod(n/128 for n in dims(box)),box))
    out=[]
    for _,__,b in sorted(merged,reverse=True):
        if all(b[i]<b[i+3] for i in range(3)) and not any(
            all(k[i]<=b[i] and k[i+3]>=b[i+3] for i in range(3)) for k in out):
            out.append(b)
        if len(out)==10:
            break
    return tuple(out)


FACILITIES = ("rail_depot_", "tram_depot_", "ship_depot_", "small_airport_", "city_airport_",
              "heliport_", "helidepot_", "stock_lighthouse", "stock_transmitter")
SOLID_SCENERY = ("scenery_town", "scenery_mine", "scenery_farm", "scenery_mill", "scenery_factory",
                 "stock_company_hq_", "town_site_shell_", "town_stock_stage_", "house_build_stage_",
                 "road_depot_", "guideway_maglev_depot_", "guideway_mono_depot_",
                 "commuter_tower", "hub_low_building", "metro_radar_fence_ne")
# These four intentionally keep the separately authored portal side boxes
# in sightseeing_hangar.lua; a new architectural hull must not mask them.
HANGAR_PORTALS={"small_airport_2_0","small_airport_3_0","city_airport_4_0","city_airport_5_0"}
TREE_EXACT=re.compile(r"^(stock_tree_[0-9a-f]+)_([0-4])_([0-6])$")
TREE_OLD=re.compile(r"^(stock_forest_[0-3])_([0-4])(_g[0-6])?$")


def stem_parts(path):
    # Current tree OBJs have the three authored stem sections divided by
    # comments. Older Blender meshes put leaves and trunk in one object;
    # their vertex-welded components still isolate the rooted stem.
    if TREE_EXACT.fullmatch(path.stem[3:]):
        points=components(path,"# trunk")
        return [bounds(part) for part in points]
    lines=path.read_text()
    if "# Rooted tapered trunk" in lines:
        return [bounds(part) for label in ("# rooted tapered trunk", "# central trunk bend",
                "# upper trunk leader") for part in components(path,label)]
    return [bounds(part) for part in components(path)]


def tree_trunks(path):
    name=path.stem[3:]
    ground=-.5 if name.startswith("scenery") else -1.5
    boxes=stem_parts(path)
    kept=[]
    for b in boxes:
        dx,dy,dz=dims(b)
        if (dy>=.105 and min(dx,dz)>.011 and max(dx,dz)<.24 and
                b[3]>-.13 and b[0]<.13 and b[5]>-.12 and b[2]<.12):
            kept.append(b)
    if name.startswith("scenery") or ("stock_forest" in name and "_g" not in name):
        # Older Blender assets did not name their component boundaries:
        # retain only the rooted object, not upper twigs near the axis.
        kept=[b for b in kept if b[1]<=ground+.04]
    return tuple(fixed(b) for b in sorted(kept,key=lambda b:(b[1],b[0],b[2]))[:3])

BRIDGE_PART=re.compile(r"(?:_(span)_(\d)|_(head_flat|head_ramp)_(\d))")
RAIL_SECTIONS=("continuous_railings","low_precast_safety_railing","bridge_angle_guardbar",
    "continuous_steel_handrails","solid_cast_parapet_webs","continuous_parapet_coping",
    "continuous_guarded_walkway_barrier","bridge_inspection_fence","deck_edge_stringer")


def bridge_rails(path,name):
    m=BRIDGE_PART.search(name)
    if not m:return ()
    kind=m[1] or m[3];direction=int(m[2] or m[4])
    axis=0 if direction%2==0 else 2
    cross=2-axis
    # Keep the visible mesh side(s), not ballast rails, high cables, or piers.
    points=[v for group in named_groups(path,RAIL_SECTIONS) for v in group]
    out=[]
    for side in (False,True):
        side_points=[v for v in points if (v[cross]>.5)==side]
        if not side_points:continue
        b=list(bounds(side_points))
        if b[axis+3]-b[axis]<.24 or b[cross+3]-b[cross]>.25:continue
        out.append(fixed(b))
    return tuple(out)


def stadium(path):
    out=[]
    for points in components(path):
        b=bounds(points); x,y,z=dims(b)
        # The low playing surface and the physical stand treads are
        # independent in the authored assembly. Truss canopy, field
        # paint, posts and terrace decoration are deliberately excluded.
        lane=min(x,z);length=max(x,z)
        if ((lane>=.62 and length>=.82 and -.47<b[4]<-.38 and .028<y<.07)
                or (lane>=.075 and length>=.48 and -.41<b[4]<.095 and .05<y<.18)):
            if lane>1.40 and b[4]>-.38:
                # Athletics terraces wrap two edges in these corner
                # quadrants. A single AABB would cover the whole infield
                # at stand height. Fit the two long arms independently.
                for axis in (0,2):
                    q=2-axis
                    first=[v for v in points if v[axis]<b[axis]+.018]
                    last=[v for v in points if v[axis]>b[axis+3]-.018]
                    for side in (first,last):
                        if not side: continue
                        lo,hi=min(v[q] for v in side),max(v[q] for v in side)
                        if not .048<hi-lo<.64: continue
                        along=[v[axis] for v in points if lo-.016<=v[q]<=hi+.016]
                        part=list(b);part[axis],part[axis+3]=min(along),max(along)
                        part[q],part[q+3]=lo,hi
                        out.append((b[4],fixed(part)))
            else:
                out.append((b[4],fixed(b)))
    # Include the supporting floor first, then bounded stepped terraces.
    return tuple(b for _,b in sorted(out)[:14])


def write():
    lookup, templates, bridge, lifted = {}, {}, {}, {}
    for p in sorted((ROOT/"models").glob("bl_*.obj")):
        name = p.stem[3:]

        tree=TREE_EXACT.fullmatch(name) or TREE_OLD.fullmatch(name)
        if tree:
            # Every native model is an exact 0.5-node Y translation of
            # its lift-0 model. Store the form once for all five slopes.
            if tree[2]=="0":
                rows=tree_trunks(p)
                assert rows,(name,stem_parts(p))
                lifted[tree[1]+"_"+(tree[3] or "")]=templates.setdefault(rows,len(templates)+1)
            continue
        if name.startswith("scenery_tree_"):
            rows=tree_trunks(p)
            assert rows,name
        elif name.startswith(("road_bridge_", "rail_bridge_")):
            rows=bridge_rails(p,name)
            if rows: bridge[name]=templates.setdefault(rows,len(templates)+1)
            continue
        elif re.match(r"town_stock_(14|20)_\d$",name):
            rows=stadium(p)
        elif name.startswith("industry_farm_"):
            rows=farm_buildings(p)
        elif name.startswith(FACILITIES):
            rows=() if name in HANGAR_PORTALS else industry_buildings(p)
        elif name.startswith(SOLID_SCENERY):
            rows=buildings(p)
        elif name.startswith(INDUSTRIES) and not name.startswith(("industry_oil_well_motor_", "industry_oil_well_pose_")):
            rows=industry_buildings(p)
        elif name.startswith(("rail_ground_fence_", "rail_split_fence_")):
            rows = railway(p)
        elif name.startswith("scenery_house_") or name.startswith("town_stock_") and (
            name[11:13] not in {f"{i:02x}" for i in SKIP} and name[11:13].isalnum()
        ):
            rows = buildings(p)
            if name.startswith("scenery_house_"): rows += parcel_fences(p)
        else:
            continue
        if rows:
            lookup[name] = templates.setdefault(rows,len(templates)+1)
    # Original farm fence y is entity units (one tenth of a node).
    heights=[]
    for i in range(1,7):
        path=ROOT/"models"/f"bl_farm_fence_{i}_0.obj"
        height=max(float(line.split()[2]) for line in path.read_text().splitlines() if line.startswith("v "))
        heights.append(ceil(height/10*128))
    result = ["-- Generated by tools/build_walk_colliders.py from original OBJ; fixed point 1/128 node.",
              "local T={"]
    for rows in templates:
        result.append("{" + ",".join("{"+",".join(map(str,b))+"}" for b in rows)+"},")
    result += ["}","local I={"]
    for name, ix in lookup.items():
        result.append(f'  {name}={ix},')
    result += ["}","local R={"]
    for name,ix in bridge.items(): result.append(f"  {name}={ix},")
    result += ["}","local L={"]
    for name,ix in lifted.items(): result.append(f"  {name}={ix},")
    result += ["}","local C={farm={"+",".join(map(str,heights))+"}}",
               "for i,h in ipairs(C.farm) do C.farm[i]=h/128 end",
               "for _,row in ipairs(T) do for _,b in ipairs(row) do",
               "  for i,n in ipairs(b) do b[i]=n/128 end", "end end",

               "local lifted_cache={}",
               "function C.box(mesh)",
               "  if I[mesh] then return T[I[mesh]] end",
               '  if mesh:sub(1,10)~="stock_tree" and mesh:sub(1,12)~="stock_forest" then return end',
               "  if lifted_cache[mesh] then return lifted_cache[mesh] end",
               '  local key,e,phase=mesh:match("^(stock_tree_%x%x%x)_([0-4])_([0-6])$")',
               '  if not key then key,e,phase=mesh:match("^(stock_forest_[0-3])_([0-4])(_g[0-6])$") end',
               '  if not key then key,e=mesh:match("^(stock_forest_[0-3])_([0-4])$") end',
               '  local rows=key and T[L[key.."_"..(phase or "")]]',
               "  if not rows then return end",
               "  local lift=tonumber(e)*.5",
               "  if lift==0 then return rows end",
               "  local boxes={}",
               "  for i,b in ipairs(rows) do boxes[i]={b[1],b[2]+lift,b[3],b[4],b[5]+lift,b[6]} end",
               "  lifted_cache[mesh]=boxes;return boxes",
               "end",
               "function C.bridge(mesh) return T[R[mesh]] end",
               "return C", ""]
    out = "\n".join(result).encode()
    assert len(out)<79*1024,"collision asset exceeds its 79 KiB total budget"
    return out,len(lookup),len(templates)


if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--check", action="store_true")
    options=p.parse_args()
    data,assets,rows=write()
    if options.check:
        assert OUT.read_bytes()==data
    else:
        t=OUT.with_suffix(".tmp");t.write_bytes(data);t.replace(OUT)
    print(f"{assets} collision assets, {rows} shared hulls, {len(data)} bytes")

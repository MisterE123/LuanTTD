-- LuanTTD road presentation: keep models scaled to one lane and shift their
-- pose to the right. No pathfinding occupancy, speed or routing changes.
local M = {}

M.road_width = .625      -- ten asphalt texels across a two-node tile
M.lane_width = .3125
M.right_offset = .155
M.corner_radius = .18    -- index-space radius in road_motion.lua

-- Existing editable meshes use ten OBJ units per Luanti entity node.
-- Bus width .638, truck .629, coach .629 at native unit visual_size.
local scales = { bus=.42, truck=.40, coach=.42, leopard_bus=.40, foster_bus=.40, mail_van=.43, coal_tipper=.42,
  wood_truck=.42,goods_truck=.42,grain_truck=.42,livestock_van=.42,oil_tanker=.42 }

function M.visual_size(engine)
  local scale = scales[engine] or 1
  return {x=scale,y=scale,z=scale}
end

local function clamp01(f)
  return math.max(0,math.min(1,f))
end

-- Non-nil outer_phase is the progress through a compact left turn from 0..1.
-- Nominal right offset is tapered only on the outside of this bend; without
-- the taper, the long body would overrun the outside asphalt by ~.067 nodes.
-- This does not grant vehicle passing clearance on an exceptionally tight turn.
function M.offset(dx,dz,outer_phase,blend)
  local mag = math.sqrt(dx*dx+dz*dz)
  if mag < 1e-9 then return 0,0 end
  local by = M.right_offset
  if outer_phase then
    by = by - .10 * math.sin(math.pi*clamp01(outer_phase))^1.4
  end
  by = by * clamp01(blend or 1)
  -- Luanti X is right when looking in world +Z.
  return by*dz/mag,-by*dx/mag
end

function M.position(x,z,dx,dz,outer_phase,blend)
  local ox,oz = M.offset(dx,dz,outer_phase,blend)
  return x+ox,z+oz
end

function M.outside_phase(route,at,xy,radius)
  radius = radius or M.corner_radius
  local k = math.floor(at+.5)
  if k<=1 or k>=#route or math.abs(at-k)>=radius then return end
  local ax,az = xy(route[k-1])
  local bx,bz = xy(route[k])
  local cx,cz = xy(route[k+1])
  local ux,uz,vx,vz = bx-ax,bz-az,cx-bx,cz-bz
  if math.abs(ux)+math.abs(uz)~=1 or math.abs(vx)+math.abs(vz)~=1
      or uz*vx-ux*vz~=-1 then return end
  return clamp01((at-(k-radius))/(2*radius))
end

-- Vehicles park on depot centerlines, not in a lane. Ease off that
-- centerline before the first adjoining tile, and vice versa on return.
function M.depot_blend(f,leaving,arriving)
  local function smooth(t)
    t=clamp01(t)
    return t*t*(3-2*t)
  end
  return (leaving and smooth(f*2) or 1) *
         (arriving and smooth((1-f)*2) or 1)
end

return M

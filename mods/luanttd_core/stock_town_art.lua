-- OpenTTD 16.0-RC1 stock Temperate root IDs; native meshes are original.
-- Gameplay metadata (age, zone, population, etc.) stays in the stock table.
local Art={
  [0x00]={name="Tall office block",asset=true,solid={-0.175,-.50,-0.218,1.175,2.150,1.032}},
  [0x01]={name="Office block",asset=true,solid={-0.240,-.50,-0.228,1.240,1.140,1.042}},
  [0x02]={name="Small block of flats",asset=true,solid={-0.195,-.50,-0.143,1.195,1.020,0.957}},
  [0x03]={name="Church",asset=true,solid={-.11,-.50,-.21,1.11,.27,.90}},
  [0x04]={name="Large office block",asset=true,solid={-0.270,-.50,-0.278,1.270,2.380,1.092}},
  [0x06]={name="Town houses",asset=true,looks={0,0,2,2},solid={-.07,-.50,-.02,1.12,.22,1.02}},
  [0x07]={name="Hotel",asset=true,width=1,depth=2,solid={-.16,-.50,-.28,1.16,1.44,1.32}},
  [0x09]={name="Statue",asset=true},
  [0x0A]={name="Fountain",asset=true},
  [0x0B]={name="Grove park",asset=true},
  [0x0C]={name="Formal park",asset=true},
  [0x0D]={name="Stone office block",asset=true,solid={-0.250,-.50,-0.283,1.250,1.420,1.097}},
  [0x0E]={name="Shops and offices",asset=true,solid={-.26,-.50,-.26,1.22,1.21,1.03}},
  [0x0F]={name="Shops and offices",asset=true,solid={-0.280,-.50,-0.268,1.280,0.810,1.082}},
  [0x10]={name="Shops and offices",asset=true,solid={-0.280,-.50,-0.268,1.280,0.950,1.082}},
  [0x11]={name="Modern office building",asset=true,solid={-0.060,-.50,-0.293,1.060,1.600,1.107}},
  [0x12]={name="Warehouse",asset=true,solid={-0.145,-.50,-0.203,1.145,0.550,1.017}},
  [0x13]={name="Office block",asset=true,solid={-0.270,-.50,-0.183,1.270,1.350,0.997}},
  [0x14]={name="Football ground",asset=true,width=2,depth=2},
  [0x18]={name="Old houses",asset=true,looks={0,1,2,3},solid={-.03,-.50,.04,1.04,.24,.97}},
  [0x19]={name="Cottages",asset=true,solid={-.01,-.50,.03,1.01,.27,.98}},
  [0x1A]={name="Houses",asset=true,looks={0,1,2,3},solid={-.10,-.50,.02,1.08,.18,1.02}},
  [0x1B]={name="Flats",asset=true,solid={-.19,-.50,-.22,1.19,1.04,1.04}},
  [0x1C]={name="Tall office block",asset=true,solid={-0.150,-.50,-0.283,1.150,1.900,1.097}},
  [0x1D]={name="Shops and offices",asset=true,solid={-0.280,-.50,-0.268,1.280,1.180,1.082}},
  [0x1E]={name="Shops and offices",asset=true,solid={-0.280,-.50,-0.268,1.280,1.180,1.082}},
  [0x1F]={name="Theater",asset=true,solid={-.17,-.50,-.17,1.17,.55,1.15}},
  [0x20]={name="Athletics stadium",asset=true,width=2,depth=2},
  [0x24]={name="Offices",asset=true,solid={-0.275,-.50,-0.263,1.275,1.620,1.077}},
  [0x27]={name="Cinema",asset=true,solid={-.20,-.50,-.24,1.11,.79,1.17}},
  [0x28]={name="Shopping mall",asset=true,width=2,depth=2,solid={-.19,-.50,-.23,1.31,.55,1.32}},
}
-- RC1 DrawTile_Town uses TileHash2Bit(pixel_x, pixel_y) to choose a
-- sprite/layout slot. Our x/z are one-based tiles, not pixel coordinates.
-- Only the two low bits matter for the stock table. This is visual only
-- and draws nothing from the town generator's random stream.
local function xor2(a,b)
  return ((a+b)%2)+2*((math.floor(a/2)+math.floor(b/2))%2)
end
function Art.tile_hash(x,z)
  x,z=x-1,z-1
  return (xor2(xor2(x%4,math.floor(x/4)%4),z%4)-math.floor(z/4))%4
end
function Art.look(id,x,z)
  local style=Art[id]
  return style and style.looks and style.looks[1+Art.tile_hash(x,z)] or 0
end
function Art.asset_name(id,look)
  local name=("town_stock_%02x"):format(id)
  return look and look~=0 and (name.."_"..look) or name
end

-- Source BuildTownHouse part order: N, W, E, S in OpenTTD isometric
-- terminology, mapped to (x,z), (x,z+1), (x+1,z), (x+1,z+1).
function Art.inspect(Sim,p,clear_base)
  local style=Art[p.id]
  if not style or type(p.parts)~="table" then return end
  local w,d=style.width or 1,style.depth or 1
  if #p.parts~=w*d then return end
  local parts,level={},nil
  for dx=0,w-1 do
    for dz=0,d-1 do
      local index=dx*d+dz
      local h=p.parts[index+1]
      local x,z=p.x+dx,p.z+dz
      local id=Sim.id(x,z)
      if not id or h.x~=x or h.z~=z or h.root_x~=p.x or h.root_z~=p.z or
         h.id~=p.id+index or h.town~=p.town or (not not h.root)~=(index==0) then return end
      local height=clear_base(id)
      if height==nil or level~=nil and height~=level then return end
      level=height
      parts[#parts+1]={id=id,record=h,index=2*dx+dz}
    end
  end
  return parts,level
end

function Art.stamp(h,p,style,part,tick)
  h.town_growth,h.built_tick,h.random_bits=true,tick,p.random_bits
  h.render_variant,h.render_parcel=style.variant,style.parcel
  if style.width then h.asset_root,h.asset_part=p.id,part end
end

function Art.footprint(Sim,s,h)
  if not h or not h.asset_root then return end
  local style=Art[h.asset_root]
  if not style or not style.width then return end
  local result={}
  for dx=0,style.width-1 do
    for dz=0,style.depth-1 do
      local id=Sim.id(h.root_x+dx,h.root_z+dz)
      local tile=id and s.tiles[id]
      local q=tile and tile.house and tile.source_house
      if not q or q.asset_root~=h.asset_root or q.town~=h.town or q.asset_part~=2*dx+dz or
          q.root_x~=h.root_x or q.root_z~=h.root_z then return end
      result[#result+1]={id=id,record=q}
    end
  end
  return result
end

return Art

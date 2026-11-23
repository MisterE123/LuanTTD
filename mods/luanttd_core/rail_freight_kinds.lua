-- Freight services use exclusive, explicit loading/unloading platform
-- roles and the common paid Train pool.
local M={}
M.all={"coal","oil","goods","iron_ore","steel","valuables","livestock","grain","wood"}
M.industry={"oil","goods","iron_ore","steel","valuables","livestock","grain","wood"}
M.wagons={[29]="coal",[30]="oil",[31]="livestock",[32]="goods",[33]="grain",[34]="wood",[35]="iron_ore",[36]="steel",[37]="valuables"}
M.profile_order={"iron_ore","steel","valuables","livestock","grain","wood"}
M.profiles={
  iron_ore={wagon=35,stem="iron_ore_hopper",name="Iron Ore",source="Iron Ore Mine",sink="Steel Mill",
    capacity_name="30-ton Iron Ore Hopper",short="Iron Ore Hopper",system="heavy"},
  steel={wagon=36,stem="steel_truck",name="Steel",source="Steel Mill",sink="Factory",
    capacity_name="20-ton Steel Truck",short="Steel Truck",system="heavy"},
  valuables={wagon=37,stem="armoured_van",name="Valuables",source="Bank",sink="other Bank",
    capacity_name="20-bag Armoured Van",short="Armoured Van",system="bank",fixed_visual=true,distinct_industries=true,unit="bags"},
  livestock={wagon=31,stem="livestock_van",name="Livestock",source="Farm",sink="Factory",
    capacity_name="25-animal Livestock Van",short="Livestock Van",system="farm",fixed_visual=true,unit="animals",menu="Farm trains"},
  grain={wagon=33,stem="grain_hopper",name="Grain",source="Farm",sink="Factory",
    capacity_name="30-ton Grain Hopper",short="Grain Hopper",system="farm",menu="Farm trains"},
  wood={wagon=34,stem="wood_truck",name="Wood",source="Forest",sink="Sawmill",
    capacity_name="30-ton Wood Truck",short="Wood Truck",system="timber",menu="Timber & Goods trains"},
}
function M.art_ready(p,assets)
  if p.fixed_visual then return not not assets[p.stem] end
  return not not (assets[p.stem.."_empty"] and assets[p.stem.."_loaded"])
end
function M.role(st,except)
  if st then
    for _,cargo in ipairs(M.all) do
      if cargo~=except and st[cargo.."_role"] then return cargo end
    end
  end
end
function M.known(cargo)
  return cargo=="coal" or cargo=="oil" or cargo=="goods" or M.profiles[cargo]~=nil
end
return M

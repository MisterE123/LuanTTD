-- Cross-check the source layer ordering, resource selection and no
-- persistence changes. No engine nodes or host projection are mocked.
local p="mods/luanttd_core/"
local Draw=dofile(p.."openttd/stock_town_draw_rows.lua")
local Art=dofile(p.."stock_town_art.lua")
local C=dofile(p.."stock_town_construction_art.lua")(Draw,Art)
local roots=dofile(p.."openttd/town_growth_houses.lua")
local cases,count,stages,files={},0,0,C.files()
local function name(id,slot,phase)
  local k,ground,sprite,look=C.resolve(id,slot,phase)
  return k,ground,sprite,look
end
for _,spec in ipairs(roots) do
  if spec[6]==1 and spec[7]==1 then
    local id=spec[1]
    assert(Draw[id] and not cases[id])
    cases[id]=true
    count=count+1
    for slot=0,3 do
      local seq=Draw[id][Draw[id].slots[slot+1]]
      for stage=0,3 do
        local k,ground,sprite=name(id,slot,stage)
        assert(ground==seq[stage+1][1] and sprite==seq[stage+1][2])
        if stage==3 then
          assert(k=="complete")
        elseif k=="complete" then
          assert(sprite==seq[4][2] and ground==seq[4][1])
        else
          assert(files[k] and io.open(p.."models/bl_"..k..".obj","rb"):close())
        end
        stages=stages+1
      end
    end
  else
    assert(not C.resolve(spec[1],0,2),"Multipart sites use their existing native renderer")
  end
end
assert(count==27 and stages==432)
assert(name(0x06,0,0)=="town_site_bare_1444")
assert(name(0x06,1,1)=="town_site_bare_1445")
assert(name(0x06,1,2)=="town_site_shell_06")
assert(name(0x06,2,0)=="town_site_1501_1502")
assert(name(0x06,3,1)=="town_site_1503_1504")
assert(name(0x06,3,2)=="complete")
assert(name(0x0A,0,0)=="town_site_bare")
assert(name(0x0A,0,1)=="town_site_paved")
assert(name(0x0A,0,2)=="complete")
assert(name(0x0B,0,1)=="complete")
for i=0,3 do
  assert(name(0x18,i,0)=="town_site_shell_18"..(i==0 and "" or "_"..i))
  assert(name(0x18,i,1)=="complete")
end
assert(name(0x19,0,0)=="town_site_bare" and name(0x19,0,1)=="complete")
local key,g,u=name(0x1A,0,1)
assert(key=="town_site_1498_0" and g==1498 and u==0)
for i=1,3 do assert(name(0x1A,i,2)=="complete") end
assert(name(0x24,0,1)=="town_site_1562_1563" and name(0x24,0,2)=="town_site_1562_1563")
assert(name(0x24,0,3)=="complete")
local n=0
for k in pairs(files) do n=n+1 end
assert(n==66)
print(("PASS %d stock house families, %d exact RC1 phase/slot selections, %d editable native stage keys")
  :format(count,stages,n))

-- Some deterministic freight scenarios deliberately constrain the native
-- catalogue. The immutable RC1 rows still include their excluded roots.
local restrict=dofile("tests/fixed_parcel_footprint.lua")
local limited={}
for k,v in pairs(Art) do limited[k]=v end
local subset=dofile(p.."stock_town_construction_art.lua")(Draw,restrict(limited))
assert(Draw[0x00] and not subset.resolve(0x00,0,0))
assert(Draw[0x03] and not subset.selection(0x03,1,1,0))
assert(subset.resolve(0x06,2,1)=="town_site_1503_1504")
local remaining=subset.files()
assert(remaining.town_site_1503_1504 and remaining.town_site_shell_18_3)
assert(not remaining.town_site_bare_1421 and not remaining.town_site_shell_03)
for _,phase in pairs(remaining) do assert(limited[phase.id] and limited[phase.id].asset) end
print("PASS native construction registration with the deterministic fixed-parcel freight catalogue")

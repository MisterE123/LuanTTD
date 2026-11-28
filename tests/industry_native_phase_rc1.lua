-- Native choices and real stock footprint geometry. Placement draws
-- are measured in the source and replayed here, not computed by the
-- unfinished climate geography adapter.
local p="mods/luanttd_core/openttd/"
local I=dofile(p.."industry_generation_schedule_rc1.lua")
local Layout=dofile(p.."stock_industry_layouts_rc1.lua")
local Specs=dofile(p.."industry_spec_rc1.lua")
local TG=dofile(p.."terragenesis.lua")(dofile(p.."slope.lua"))
local cases=dofile("tests/fixtures/rc1-native-industry-phase.lua")
assert(Specs.cargo("temperate","CT_OIL").definition[6]==4437 and Specs.cargo("tropic","CT_OIL").definition[6]==4892)
assert(Specs.cargo("temperate","CT_WOOD").definition[6]==5005 and Specs.cargo("tropic","CT_WOOD").definition[6]==7964)
local floor=math.floor
local firms,tiles,draws,attempts=0,0,0,0
local function hash(rows)
  table.sort(rows,function(a,b)return a[1]<b[1] end)
  local h=1
  for _,row in ipairs(rows) do
    h=(65599*h+row[1])%2147483647
    h=(65599*h+row[2])%2147483647
  end
  return h
end
for _,case in ipairs(cases) do
  local climate,seed,w,h,n,rng,final,choices,placed=unpack(case)
  local state={rng[1],rng[2]}
  local function random()return TG.next_random(state) end
  local index,total=0,0
  I.generate({width=w,height=h,initial_land_count=n},{landscape=climate,density=4},random,
    function(id,water,force)
      index=index+1
      local c=assert(choices[index])
      assert(c[1]==id and (c[2]==1)==water and (c[3]==1)==force,
        ("%s seed %d choice %d"):format(climate,seed,index))
      assert(c[4]==state[1] and c[5]==state[2],"Source ordered selection RNG")
      local firm=assert(placed[index])
      local used,found=0,false
      while used+4<=c[6] do
        local x,z,_,bits,layout=I.candidate(w,h,#Layout[id]+1,random)
        local at,variant=x+z*w,layout+1
        used=used+4
        if at==firm[2] and variant==firm[5] and bits==firm[8] then found=true;break end
      end
      assert(found and used<c[6],
        ("Native %s seed %d: no exact successful draw for type %d"):format(climate,seed,id))
      attempts=attempts+used/4
      -- Site clearing/leveling and industry/tile initialization still
      -- consume a source-measured tail. Do not claim predicate parity.
      for _=used+1,c[6] do random() end
      draws=draws+c[6]
    end,function(_,count) total=total+count end)
  assert(total==index and index==#choices and index==#placed and state[1]==final[1] and state[2]==final[2])
  for _,record in ipairs(placed) do
    local id,t,fw,fh,variant,count,expected,_,produced,accepted=unpack(record)
    local spec=assert(Specs.get(id,climate))
    for _,set in ipairs{{spec.produce,produced},{spec.accept,accepted}} do
      local seen=0
      for _,slot in ipairs(set[1]) do
        if slot.cargo then seen=seen+1;assert(slot.cargo.id==set[2][seen],climate.."/"..spec.kind) end
      end
      assert(seen==#set[2])
    end
    local plan=assert(Layout[id][variant-1])
    local dx,dz=t%w,floor(t/w)
    local physical,pw,ph={},0,0
    for _,part in ipairs(plan) do
      local x,z,gfx=unpack(part)
      if gfx~=65535 then
        local u,v=x+dx,z+dz
        assert(u>=0 and u<w and v>=0 and v<h)
        physical[#physical+1]={u+v*w,gfx}
        pw,ph=math.max(pw,x+1),math.max(ph,z+1)
      end
    end
    assert(pw==fw and ph==fh and #physical==count and hash(physical)==expected,
      ("Native %s stock footprint type %d layout %d at %d,%d"):format(climate,id,variant,dx,dz))
    firms,tiles=firms+1,tiles+#physical
  end
end
assert(firms==206 and tiles==1826 and attempts==4824 and draws==35922)
print(("PASS six native RC1 starts: %d actual industry selections and footprints, %d physical tiles, %d candidate draws, %d total placement RNG words"):
  format(firms,tiles,attempts,draws))

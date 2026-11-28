-- Controlled entry at the source industry initialization boundary
-- after any worldgen platform edits and before field planting.
local p="mods/luanttd_core/openttd/"
local R=dofile(p.."industry_initial_record_rc1.lua")
local Specs=dofile(p.."industry_spec_rc1.lua")
local Layout=dofile(p.."stock_industry_layouts_rc1.lua")
local TG=dofile(p.."terragenesis.lua")(dofile(p.."slope.lua"))
local cases=dofile("tests/fixtures/rc1-native-industry-init.lua")
local count,physical,rates,originals=0,0,0,0
local function hash(rows)
  table.sort(rows,function(a,b)return a[1]<b[1] end)
  local h=1
  for _,row in ipairs(rows) do
    for _,v in ipairs(row) do h=(65599*h+v)%2147483647 end
  end
  return h
end
for _,r in ipairs(cases) do
  local climate,seed,w,h,firms=unpack(r)
  for j,row in ipairs(firms) do
    local kind,t,variant,original,col,counter,before,after,expected,source_rates=unpack(row)
    local id=("%s-%d industry %d (kind %d) field "):format(climate,seed,j-1,kind)
    local spec=assert(Specs.get(kind,climate))
    local state={before[1],before[2]}
    local cells={}
    for _,c in ipairs(assert(Layout[kind][variant-1])) do
      if c[3]~=65535 then cells[#cells+1]={at=t+c[1]+w*c[2],gfx=c[3]} end
    end
    local plan=R.draw({layout=variant-1,cells=cells},spec,function()return TG.next_random(state)end,original==1,true)
    assert(plan.random_colour==col,id.."color")
    assert(plan.counter==counter,id.."counter")
    assert(state[1]==after[1] and state[2]==after[2],id.."post-tile RNG")
    local raw={}
    for _,c in ipairs(cells) do
      raw[#raw+1]={c.at,c.gfx,c.random_bits,c.stage,c.construction_counter}
    end
    assert(hash(raw)==expected,id.."tile random/stage")
    local n=0
    for i,slot in ipairs(spec.produce) do
      if slot.cargo then
        n=n+1
        local want=assert(source_rates[n],id.."output")
        local rate=R.rate(slot.value,plan.production_raw[i])
        assert(want[1]==slot.cargo.id and want[2]==rate and want[3]==rate*8,id.."rate and pregame material history")
        rates=rates+1
      end
    end
    assert(n==#source_rates,id.."output count")
    count,physical=count+1,physical+#cells
    originals=originals+original
  end
end
assert(count==261 and physical==2406 and originals==42 and rates>0)
print(("PASS exact stock initialization on ten native RC1 worlds: %d firms, %d tile states and %d production records"):
  format(count,physical,rates))

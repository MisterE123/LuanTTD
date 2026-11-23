-- SPDX-License-Identifier: GPL-2.0-only
-- Run a real generated campaign through the gameplay builder; the test
-- chooses an already valid target quota to skip years of waiting, not the
-- terrain site, per-candidate RNG, amount, neutral ID or construction.
local mod="mods/luanttd_core"
local function m(n) return dofile(mod.."/"..n..".lua") end
local initcore={settings={get=function()return nil end}}
local media=assert(arg[1],"Pass the directory of actual models/textures listing files.")
function initcore.get_dir_list(path)
  local list={}
  local file=path:match("([^/]+)$")
  for f in io.lines(media.."/"..file) do list[#list+1]=f end
  return list
end
local Sim=m("sim")
local Gen=m("campaign_generation")(initcore,mod,Sim,m("world_setup"))
local s=Gen.run({seed=1751,width=128,depth=128,relief=1,sea=0,coast=15,rivers=0,year=1965,towns=2,industries=4})
local seen=0
for _,i in pairs(s.stock_oil_industries or {}) do assert(i.kind~="oil_rig") end
for _,k in ipairs({"coal","timber","farm","oil","heavy"}) do
  s["road_"..k]=next(s["stock_"..k.."_industries"] or {})~=nil
end
local cap={road={start_year=1965,foster=true,breakdowns=0,service_interval=0},oil_tanker=true,heavy_industry=true,air={},ferry={}}
local compose=m("campaign_authority_runtime")
local rt=compose(Sim,mod,s,cap)
local b=assert(s.stock_industry_builder)
local rows={coal_mine=0,power_station=1,sawmill=2,forest=3,oil_refinery=4,oil_rig=5,factory=6,
  steel_mill=8,farm=9,oil_well=11,iron_mine=18}
for _,chain in ipairs({"coal","timber","oil","farm","heavy"}) do
  for _,i in pairs(s["stock_"..chain.."_industries"] or {}) do
    local key=assert(rows[i.kind])
    b.builddata[key].target_count=b.builddata[key].target_count+1
    seen=seen+1
  end
end
for id,p in pairs({[0]=2,[1]=2,[2]=2,[3]=3,[4]=2,[5]=6,[6]=2,[8]=2,[9]=2,[18]=2}) do b.builddata[id].probability=p end
b.builddata[5].target_count=3
b.wanted_inds=(seen+3)*65536
local attempts
for k=1,100 do
  b.daily_counter=65535 -- skip otherwise idle days; all source candidate draws are real
  rt.day()
  for id,o in pairs(s.stock_oil_industries or {}) do
    if o.kind=="oil_rig" then
      attempts=k
      assert(o.construction_type=="gameplay" and not o.neutral_station and not o.tiles[1].completed)
      local presses=s.stock_news_journal.items
      local news=false
      for _,n in ipairs(presses) do if n.kind=="open" and n.headline:find("Oil Rig",1,true) then news=true end end
      assert(news,"Natural opening not in Gazette")
      print("Auto-opening accepted stock RNG site",id,o.x,o.z,attempts,"days",#o.tiles)
      for d=1,150 do
        if d==6 then
          local function clone(t)
            if type(t)~="table" then return t end
            local row={};for k,v in pairs(t) do row[k]=clone(v) end;return row
          end
          s=clone(s);rt=compose(Sim,mod,s,cap);o=assert(s.stock_oil_industries[id])
          assert(not o.neutral_station and o.construction_type=="gameplay")
        end
        rt.day()
        if o.neutral_station then
          print("PASS generated authority lifecycle completed one restored neutral Oil Rig terminal",o.neutral_station,d)
          return
        end
      end
      error("failed to complete created neutral platform")
    end
  end
end
error("Generation seed or calendar could not qualify a real oil rig")

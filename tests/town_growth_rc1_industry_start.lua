-- Native OpenTTD 16.0-RC1 (07b339c) observations from a regular 1950
-- 128-square map, seed 1751, stock Normal industry/rivers and Smooth
-- production. Only numeric evidence, not an imported source game.
local root="mods/luanttd_core/"
local function m(n) return dofile(root..n..".lua") end
local Sim,T=m("sim"),m("openttd/terrain")
local core={settings={get=function()return nil end},get_dir_list=function(path)
 local files={}
 local p=assert(io.popen("ls -1 "..path))
 for n in p:lines() do files[#files+1]=n end
 p:close();return files
end}
local s=m("campaign_generation")(core,root:sub(1,-2),Sim,m("world_setup")).run({
 width=128,depth=128,year=1950,seed=1751,relief=1,sea=0,coast=16,rivers=2,
 trees=2,towns=4,custom_towns=4,larger_towns=3,industries=4,variety=0,smooth=1,layout="original",growth_rate=2,
})
local ht,cls=1,1
for id,t in ipairs(s.tiles) do
 local x,z=Sim.xy(id)
 local v=t.stock_void and 7 or t.stock_industry and 8 or t.stock_landmark and 10 or t.wood and 4 or t.terrain=="water" and 6 or t.build=="road" and 2 or t.source_house and 3 or 0
 ht=(ht*65599+T.corner(s.corner_grid,x,z))%2147483647
 cls=(cls*65599+v)%2147483647
end
assert(ht==815929123 and cls==1755659935,"Ground and industry/wood/town map differ from RC1")
assert(s.passenger_house_clock.counter==1280)
assert(s.passenger_rating_rng[1]==1492574293 and s.passenger_rating_rng[2]==255261184,
  "RC1 pregame landscape consumed a different random stream")
local profile=s.stock_generated_profile
assert(profile.industry_rng[1]==2180298511 and profile.industry_rng[2]==3128084668)
assert(profile.object_rng[1]==3155780971 and profile.object_rng[2]==1022975992)
assert(profile.forest[1]==1251450299 and profile.forest[2]==3204912898)
-- Types, tile, nearest TownID, one-based layout, starting counter,
-- source initial color, and initial output-rate/last-month pairs.
-- Reference industry DATE is Jan 1 tick 1281, after OnTick_Industry
-- decremented each counter once. The rows below restore that one tick.
local ref={
 {"coal_mine",13214,4,3,3881,6,"14:112"},
 {"power_station",6094,1,1,3083,15,""},
 {"sawmill",11287,2,2,1549,4,"0:0"},
 {"forest",7600,1,2,1303,8,"7:56"},
 {"oil_refinery",4843,3,2,863,0,"0:0"},
 {"factory",13362,2,2,487,0,"0:0"},
 {"steel_mill",13937,2,1,1002,13,"0:0"},
 {"farm",7443,1,2,2087,3,"6:48,6:48"},
 {"oil_well",12968,2,2,2144,7,"15:120"},
 {"iron_mine",12382,2,1,4078,5,"10:80"},
 {"farm",9036,2,1,157,7,"7:56,5:40"},
}
assert(#profile.industries==#ref)
for i,t in ipairs(profile.industries) do
  local row=s["stock_"..t.chain.."_industries"][t.industry]
  local r=row.produced
  if r and r.rate then r={r} end
  local values={}
  for _,q in ipairs(r or {}) do
    if q.cargo or #r==1 then values[#values+1]=tostring(q.rate)..":"..tostring(q.last.production) end
  end
  local actual={t.kind,t.tile-1,t.near,row.selected_layout,row.counter,row.random_colour,table.concat(values,",")}
  for j,v in ipairs(ref[i]) do
    assert(actual[j]==v,("Industry %d field %d: got %s; RC1 %s"):format(i,j,tostring(actual[j]),tostring(v)))
  end
end
print("PASS fresh RC1 Normal-industry region: eleven real factories/mines/farms, exact startup map, initial production and shared RNG")

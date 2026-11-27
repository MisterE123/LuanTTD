-- The real Gazette panel stays navigable using normal button fields,
-- and an offered route's endpoint opens the correct world location.
local core,player,client={},{},{}
local form,requests,position
requests={}
local function push(q) requests[#requests+1]=q end
function core.formspec_escape(s) return s:gsub("([%[%];])","\\%1") end
function core.colorize(_,t) return t end
function core.show_formspec(n,id,body) assert(n=="QA" and id=="luanttd_core:newspaper");form=body end
function core.close_formspec() form=nil end
function player:get_player_name() return "QA" end
function player:get_meta() return {get_string=function()return "" end,get_int=function()return 0 end} end
function player:set_pos(p) position=p end
function client.query(q,cb)
  push(q)
  if q.kind=="news" and q.action=="subsidies" then
    local items
    if q.page==1 then items={{cargo="Mail",src="Cross; Bay",dst="Larch",months=7,source_tile=30,destination_tile=31}}
    else items={{cargo="Oil",src="Oil Rig",dst="Refinery",months=11,owner="Freight",source_tile=41,destination_tile=42}} end
    cb({ok=true,value={items=items,count=7}})
  elseif q.kind=="jump_tile" then
    cb({ok=true,value={x=14,y=8,z=30}})
  else
    cb({ok=true,value={items={},count=0}})
  end
  return true
end
local u=dofile("mods/luanttd_core/campaign_news_ui.lua")(core,"mods/luanttd_core",client,tostring)
u.open(player)
assert(form:find("Active subsidies",1,true))
u.fields(player,{subsidies=true})
assert(form:find("ACTIVE SUBSIDIES",1,true) and form:find("Mail: Cross\\; Bay",1,true))
assert(form:find("Unclaimed",1,true) and form:find("7 months left",1,true))
u.fields(player,{next=true})
assert(requests[#requests].page==2 and form:find("Awarded to Freight",1,true))
u.fields(player,{dst_1=true})
assert(requests[#requests].kind=="jump_tile" and requests[#requests].tile==42 and position.z==30 and not form)
u.open(player)
u.fields(player,{subsidies=true})
u.fields(player,{quit=true})
print("PASS live-subsidy Gazette button, paging, ownership status and destination jump")

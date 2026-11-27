-- Read-only pricing under the normal generated campaign's autosave.
-- Loaded only in an isolated copy of the game.
local owner="Road Hover QA"
local function start()
  if not (authority and authority.status()=="owned") then core.after(.1,start);return end
  local view=assert(OwnerCheckpoint.read())
  assert(view.speed>0 and view.corner_grid.width>=512)
  local w,h=view.corner_grid.width,view.corner_grid.depth
  local T=dofile(mod.."/openttd/terrain.lua")
  local first,last,bend
  for z=20,h-10 do
    for x=20,w-60 do
      local clean=true
      local _,height=T.tile(view.corner_grid,x,z)
      for dz=0,3 do for dx=0,12 do
        local id=(z+dz-1)*w+x+dx
        local p=view.tiles[id]
        local slope,base=T.tile(view.corner_grid,x+dx,z+dz)
        if slope~=0 or base~=height or p.terrain=="water" or p.stock_void or p.build or p.site or p.house
            or p.wood or p.owner or p.stock_industry or p.rail_tracks or p.tram or p.ship or p.airfield
            or view.stock_farm_fields and view.stock_farm_fields[id] then clean=false;break end
      end;if not clean then break end end
      if clean then first=(z-1)*w+x;last=first+10;bend=first+2*w+9;break end
    end
    if first then break end
  end
  assert(first,"No empty flat road quote field")
  view=nil
  local function ask(q,cb)
    q.player=owner
    local function send()
      if not authority.query(q,function(r)assert(r.ok,r.why);cb(r)end) then core.after(.05,send) end
    end
    send()
  end
  local specs={
    {tool="drag",first=first,last=last,axis=0,start_half=false,end_half=true},
    {tool="bend",first=first,last=bend},
  }
  ask({kind="command",command={kind="company_open"}},function(opened)
    local stage,from,round="running",core.get_us_time(),0
    local quoted,paused_cash={},nil
    local function loop()
      round=round+1
      local i=1+round%2
      local sent=core.get_us_time()
      ask({kind="road_quote",peek=true,request=specs[i]},function(r)
        local received=core.get_us_time()
        local q=assert(r.value)
        assert(q.ticket and q.cost>0 and #q.tiles>=10 and r.actor_us==nil)
        if quoted[i] then assert(q.ticket==quoted[i].ticket and q.cost==quoted[i].cost)
        else quoted[i]=q end
        core.log("action",("PROBE_HOVER %d %s send=%d receive=%d day=%d cost=%d tiles=%d"):format(
          r.seq,stage,sent,received,r.day,q.cost,#q.tiles))
        if stage=="running" and received-from>=19000000 then
          ask({kind="command",command={kind="speed",speed=0,revision=r.revision}},function()
            ask({kind="company"},function(company)
              paused_cash=company.value.cash
              ask({kind="checkpoint"},function()
                stage,from="paused",core.get_us_time()
                core.log("action","PROBE_HOVER_PAUSED us="..from)
                core.after(.075,loop)
              end)
            end)
          end)
        elseif stage=="paused" and received-from>=10500000 then
          core.log("action","PROBE_HOVER_END us="..received)
          ask({kind="company"},function(company)
            assert(company.value.cash==paused_cash,"road hovers charged the paused company")
            core.log("action","PROBE_HOVER_FINISH day="..company.day)
            core.request_shutdown("Road autosave hover benchmark complete",false,0)
          end)
        else core.after(.075,loop) end
      end)
    end
    loop()
  end)
end
core.register_on_mods_loaded(function() core.after(.1,start) end)

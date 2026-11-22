-- SPDX-License-Identifier: GPL-2.0-only
-- Detached typed, owner-thread receipts for the native TownTick 1x1
-- house writer. Source RNG selection stays on the real native call.
return function(Authority)
  local M={}
  local substrate={terrain=true,h=true,variant=true,stock_clear_ground=true}
  local permitted_town={house_counts=true,num_houses=true,radii=true,growth_rate=true,grow_counter=true,last_build=true}
  local layers={"level_crossing_tiles","bridge_above","aqueduct_above","tunnel_below",
    "rail_bridge_above","rail_tunnel_below","stock_farm_fields"}
  local function exact(n,a,b)
    return type(n)=="number" and n>=a and n<=b and n==math.floor(n)
  end
  local function plain(v) return type(v)=="table" and getmetatable(v)==nil end
  local function copy(t)
    local o={}
    for k,v in pairs(t) do o[k]=v end
    return o
  end
  local function same(a,b)
    for k,v in pairs(a) do if b[k]~=v then return false end end
    for k,v in pairs(b) do if a[k]~=v then return false end end
    return true
  end
  local function rng(s)
    local r=s.passenger_rating_rng
    return r and r[1],r and r[2],r
  end

  function M.bind(s,world,owner,side_guard)
    assert(plain(s) and type(world)=="string" and plain(owner) and plain(s.corner_grid))
    assert(side_guard==nil or type(side_guard)=="function")
    local width,depth=s.corner_grid.width,s.corner_grid.depth
    assert(exact(width,1,4096) and exact(depth,1,4096))
    local function unknown(id)
      for _,k in ipairs(layers) do
        local map=s[k]
        if map~=nil and (not plain(map) or map[id]~=nil) then return true end
      end
      return side_guard and side_guard(id)
    end
    return function(state,f,write)
      assert(state==s and plain(f) and type(write)=="function","Bad native town writer receipt")
      local id,clock=f.tile,s.passenger_house_clock
      assert(exact(f.x,1,width) and exact(f.z,1,depth) and id==(f.z-1)*width+f.x and clock and
        clock.counter==f.tick and width==s.corner_grid.width and depth==s.corner_grid.depth,
        "Native town writer must run after its owning completed landscape tick")
      local ground=s.tiles[id]
      assert(plain(ground) and not unknown(id),"Unreviewed native growth substrate")
      for k in pairs(ground) do assert(substrate[k],"Unreviewed town-house tile field: "..tostring(k)) end
      local t=s.stock_town_growth and s.stock_town_growth.towns[f.town]
      local site=s.sites[f.town]
      assert(t and site and (ground.terrain=="grass" or ground.terrain=="hill"),"Unknown town or house site")
      local planned={{kind="tile",host=id}}
      -- "slot" here includes the native after-landscape TownTick
      -- callback. Its source RNG and prior phases have already run.
      local token,err=owner.preflight({schema=Authority.SCHEMA,world=world,revision=owner.revision(),
        changes=planned},"slot")
      assert(token,err)
      local applied,reason=owner.run(token,"slot",function()
        assert(ground==s.tiles[id] and not unknown(id))
        local before=copy(ground)
        local old_town,old_site=copy(t),copy(site)
        local expected_counts=copy(t.house_counts or {})
        expected_counts[f.house]=(expected_counts[f.house] or 0)+1
        local level,topology=s.corner_grid.revision,s.topology
        local a,b,seed=rng(s)
        local n,p,q=t.num_houses,t.population,site.population
        local count=t.house_counts and t.house_counts[f.house] or 0
        assert(write()==true,"Native house occupancy failed at commit")
        local after=s.tiles[id]
        local h=after.source_house
        assert(after==ground and after.house==true and h and h.id==f.house and
          h.town==f.town and h.x==f.x and h.z==f.z and h.built_tick==f.tick and
          h.town_growth and h.root and h.random_bits==f.random_bits and not h.completed and
          h.stage==0 and h.counter==0 and t.last_build and t.last_build.tile==id and t.last_build.tick==f.tick)
        local ea,eb,es=rng(s)
        assert(s.corner_grid.revision==level and s.topology==topology and not unknown(id) and
          ea==a and eb==b and es==seed and t.population==p and site.population==q and
          t.num_houses==n+1 and t.house_counts[f.house]==count+1)
        before.house,before.source_house,before.h=true,h,f.level
        for k in pairs(permitted_town) do old_town[k]=t[k] end
        assert(same(before,after),"Native house writer touched an unattested tile field")
        assert(same(old_town,t) and same(old_site,site) and same(expected_counts,t.house_counts),
          "Native house writer touched an unattested town ledger field")
        -- Derived from the actual one ground record storing the house,
        -- not the visual append and not the caller's planning array.
        return {{kind="tile",host=(h.z-1)*width+h.x}}
      end)
      assert(applied,reason)
      return true
    end
  end
  return M
end

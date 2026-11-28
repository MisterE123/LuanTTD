-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 contributors: town_cmd.cpp CmdFoundTown,
-- TownCanBePlacedHere and IsUniqueTownName; table/pricebase.h.
-- Ordinary player command branch. Editor and GameScript authority
-- are not implied by the caller's player or server privileges.
return function(Worldgen)
  local F={}
  F.BASE_PRICE=750000 -- Default 3/4 construction-price multiplier applied to RC1 base 1,000,000.
  F.MAX_NAME_CHARS=32 -- includes the terminator
  local size_id={small=0,medium=1,large=2,random=3}
  local layouts={original=true,better=true,grid2=true,grid3=true,random=true}
  local normal={[0]=15,25,40,25}
  local cities={[0]=20,35,55,35}
  local function integer(n,lo,hi)
    return type(n)=="number" and n%1==0 and n>=lo and n<=hi
  end
  local function valid_name(s)
    if type(s)~="string" or #s>4*(F.MAX_NAME_CHARS-1) or s:find("[%z\1-\31\127]") then return false end
    local _,characters=s:gsub("[^\128-\191]","")
    return characters<F.MAX_NAME_CHARS
  end
  function F.quote(board,args)
    if type(args)~="table" or type(board)~="table" or not integer(board.policy or 0,1,2) then
      return nil,"TOWN_FOUNDING_FORBIDDEN"
    end
    local size=type(args.size)=="string" and size_id[args.size]
    if not size or size==2 or type(args.city)~="boolean" or args.random_location then
      return nil,"INVALID_TOWN_SIZE_OR_LOCATION"
    end
    local layout=args.layout or board.default_layout
    if not layouts[layout] or (board.policy~=2 and layout~=board.default_layout) then
      return nil,"INVALID_TOWN_LAYOUT"
    end
    local text=args.name or ""
    local parts=args.nameparts
    if not valid_name(text) or not integer(parts,0,4294967295) then return nil,"INVALID_TOWN_NAME" end
    local name=text~="" and text or board.name(parts)
    if not valid_name(name) or #name==0 then return nil,"INVALID_TOWN_NAME" end
    for _,t in ipairs(board.towns) do
      -- For custom text OpenTTD only compares other custom names.
      -- VerifyTownName checks any displayed name when automatic.
      if t.name==name and (text=="" or t.custom_name) then return nil,"NAME_MUST_BE_UNIQUE" end
    end
    if board.capacity and #board.towns>=board.capacity then return nil,"TOO_MANY_TOWNS" end
    if not integer(args.x,0,board.width-1) or not integer(args.z,0,board.height-1) then
      return nil,"INVALID_TOWN_LOCATION"
    end
    local ok,why=Worldgen.can_place(board,board.towns,args.x,args.z,false,board.separation)
    if not ok then return nil,why end
    return {
      x=args.x,z=args.z,size=args.size,city=args.city,layout=layout,name=name,
      custom_name=text~="" and text or nil,nameparts=parts,
      cost=(board.base_price or F.BASE_PRICE)*(args.city and cities[size] or normal[size]),
    }
  end
  -- CommandCost is a quote independent of the balance. On execute RC1
  -- returns the amount of additional cash needed without touching RNG.
  function F.can_execute(plan,cash)
    if cash<plan.cost then return nil,"NOT_ENOUGH_MONEY",plan.cost end
    return true
  end
  return F
end

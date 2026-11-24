-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 contributors: src/town_cmd.cpp, TownActionBuildStatue,
-- GetTownActionCost and CmdDoTownAction; src/table/object_land.h.
return function(Spiral)
  local M={inner=25,diameter=9}
  function M.price(base)
    return math.floor((base or 1000000)*48/256)
  end
  function M.site(board,center)
    local best,count=nil,0
    for id in Spiral.centered(board.width,board.depth,center,M.diameter) do
      count=count+1
      local tile=assert(board.tile(id))
      -- Source continue skips even the 25th-position early-exit branch.
      if tile.slope<16 and not tile.bridge_above then
        if (tile.class=="clear" or tile.class=="trees") and board.can_clear(id,tile) then
          return id
        end
        local house=tile.class=="house"
        if count<=M.inner then
          if house and best==nil and board.can_clear(id,tile) then best=id end
          if count==M.inner and best~=nil then break end
        end
        if house and board.can_clear(id,tile) then best=id;break end
      end
    end
    if best==nil then return nil,"STATUE_NO_SUITABLE_PLACE" end
    return best
  end
  function M.quote(board,town,company,view)
    if not company or not town or view and view.unwanted then return nil,"STATUE_UNAVAILABLE" end
    if view and view.existing then return nil,"STATUE_ALREADY_BUILT" end
    local id,why=M.site(board,town.center)
    if id==nil then return nil,why end
    return {id=id,cost=M.price(),affordable=company.cash>=M.price()}
  end
  return M
end

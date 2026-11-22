-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 14.1 src/rail_cmd.cpp, CmdRailTrackHelper (build branch).
-- The callback quotes one piece: true on success, false for ALREADY_BUILT,
-- or nil and the command error. Keep OpenTTD's ordered stop/skip behavior.
return function(list,quote_piece,fail_on_obstacle)
  local had_success,last_error,stopped,skipped=false,nil,nil,0
  for _,piece in ipairs(list) do
    local result,why=quote_piece(piece)
    if result==true then
      had_success=true
    elseif result==false then
      last_error=why
    else
      last_error=why
      if fail_on_obstacle then return nil,last_error end
      if had_success then stopped=piece.id;break end
      skipped=skipped+1
    end
  end
  if had_success then return true,last_error,stopped,skipped end
  return nil,last_error
end

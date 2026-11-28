-- SPDX-License-Identifier: GPL-2.0-only
-- Direct port of Order::ShouldStopAtStation, OpenTTD 16.0-RC1,
-- src/order_cmd.cpp. Flags are the original OrderNonStopFlags bitset.
local O={NON_STOP=1,GO_VIA=2}

function O.should_stop(kind,destination,nonstop,part_of_orders,last_station,station)
  local is_destination=kind=="goto_station" and destination==station
  local flag=is_destination and O.GO_VIA or O.NON_STOP
  return (kind~="goto_depot" or not not part_of_orders) and last_station~=station
      and math.floor((nonstop or 0)/flag)%2==0
end

return O

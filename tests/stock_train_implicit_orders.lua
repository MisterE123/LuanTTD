-- SPDX-License-Identifier: GPL-2.0-only
local O=dofile("mods/luanttd_core/openttd/rail_order_list.lua")
local function order(id) return {kind="station",station=id,nonstop=0} end
local a,b=order(1),order(5)
local rows,index={a,b},{real=0,implicit=0}
-- Native first pass goes through the later ordered platform before the
-- current real destination: do not advance/replace that real order.
assert(O.observe_stop(rows,index,5)=="consecutive")
-- Use an unlisted mid-line platform to exercise insertion.
assert(O.observe_stop(rows,index,13)=="inserted")
assert(#rows==3 and rows[1].kind=="implicit" and rows[1].station==13)
assert(index.real==1 and index.implicit==0 and rows[index.real+1]==a)
assert(O.complete_stop(rows,index,13) and index.implicit==index.real and rows[index.real+1]==a)
O.prune_unreached(rows,index)
assert(O.complete_stop(rows,index,1) and rows[index.real+1]==b)
assert(O.complete_stop(rows,index,5) and rows[index.real+1]==a and index.implicit==0)
assert(O.observe_stop(rows,index,13)=="current")
-- A changed approach skips abandoned implicit stops.
index.suppress_implicit=true
assert(O.observe_stop(rows,index,9)=="unrecorded")
assert(not O.complete_stop(rows,index,9))
O.prune_unreached(rows,index)
assert(index.implicit==index.real and not index.suppress_implicit and #rows==3)
index.implicit=0
O.prune_unreached(rows,index)
assert(#rows==2 and rows[1]==a and index.real==0 and index.implicit==0)
print("PASS stock rail implicit-stop cursor preserves and advances only the real matching platform")

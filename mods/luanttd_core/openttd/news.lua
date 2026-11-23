-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1: news_gui.cpp, news_type.h, news_display_settings.ini.
-- Source ordering, duration, display classes and expiry, independent
-- of Luanti's modal formspec and asynchronous campaign owner.
local N={OFF=0,SUMMARY=1,FULL=2,DURATION=16.650,MIN_KEEP=30,MAX_KEEP=1024,TIMEOUT=2}
local kinds={
  {"arrival_player",60,2,"Your first arrivals"},
  {"arrival_other",60,1,"Other first arrivals"},
  {"accident",90,2,"Your accidents"},
  {"accident_other",90,2,"Other accidents"},
  {"company_info",60,2,"Company information"},
  {"open",90,1,"Industry opens"},
  {"close",90,1,"Industry closes"},
  {"economy",30,2,"Economy"},
  {"production_player",30,1,"Production you serve"},
  {"production_other",30,0,"Production others serve"},
  {"production_nobody",30,0,"Unserved production"},
  {"advice",150,2,"Vehicle advice"},
  {"new_vehicles",30,2,"New vehicles"},
  {"acceptance",90,2,"Cargo acceptance"},
  {"subsidies",180,1,"Subsidies"},
  {"general",60,2,"General news"},
}
N.categories=kinds
local indexed={}
for _,row in ipairs(kinds) do indexed[row[1]]=row end
function N.category(k) return indexed[k] end
function N.mode(prefs,k)
  local custom=prefs and prefs[k]
  if custom==0 or custom==1 or custom==2 then return custom end
  return assert(indexed[k],k)[3]
end
function N.fresh(row,day)
  return day-row.economy<=indexed[row.kind][2]
end
function N.new()
  return {version=1,head=0,items={}}
end
-- The head of this array is the most recent item, as with _news.emplace_front.
function N.push(book,row)
  assert(indexed[row.kind] and type(row.economy)=="number")
  book.head=book.head+1
  row.seq=book.head
  table.insert(book.items,1,row)
  if #book.items>N.MAX_KEEP then table.remove(book.items) end
  return row
end
-- DeleteNews visits oldest first; it can remove scattered old items
-- (different expiry ages) until only MIN_NEWS_AMOUNT items remain.
function N.remove(book,predicate,minimum)
  local rows=book.items
  for i=#rows,1,-1 do
    if #rows<=(minimum or 0) then break end
    if predicate(rows[i]) then table.remove(rows,i) end
  end
end
function N.cleanup(book,economy,month,timeout)
  if #book.items==0 or book.month==month then return end
  book.month=month
  N.remove(book,function(row)
    return economy-indexed[row.kind][2]*(timeout or N.TIMEOUT)>row.economy
  end,N.MIN_KEEP)
end
function N.view(row,viewer)
  if row.private and row.owner~=viewer then return end
  local kind=row.kind
  if row.owner and row.owner~=viewer then
    kind=({arrival_player="arrival_other",accident="accident_other",production_player="production_other"})[kind] or kind
  end
  -- Never send the stored owner or actor internals in a public newspaper.
  return {seq=row.seq,kind=kind,style=row.style,headline=row.headline,body=row.body,
    year=row.year,month=row.month,day=row.day,economy=row.economy,tile=row.tile,icon=row.icon}
end
-- Newest-first history includes Off and expired-for-auto items. It does not
-- expose the existence of any other viewer's private entries in its counts.
function N.history(book,viewer,page,limit)
  local first=(page-1)*limit+1
  local out,count={},0
  for _,row in ipairs(book.items) do
    local visible=N.view(row,viewer)
    if visible then
      count=count+1
      if count>=first and #out<limit then out[#out+1]=visible end
    end
  end
  return out,count
end
-- Independent, oldest-first ticker and newspaper cursors. Summary and Off
-- share the status-bar lane; a Full item never occupies that lane.
function N.next_auto(rows,cursor,lane,economy,prefs)
  for _,row in ipairs(rows) do
    if row.seq>cursor then
      cursor=row.seq
      if N.fresh(row,economy) then
        local mode=N.mode(prefs,row.kind)
        if (lane=="paper")==(mode==N.FULL) then return row,cursor,mode end
      end
    end
  end
  return nil,cursor
end
-- A status-bar "last message" starts at latest if it has not shown one,
-- otherwise moves toward older entries with wrap, skipping Status-only/Off.
function N.last(rows,forced,current,shown,prefs)
  local index={}
  for i,r in ipairs(rows) do index[r.seq]=i end
  local i=forced and ((index[forced] or #rows)%math.max(1,#rows)+1) or index[current] or 1
  if not forced and shown and index[current] and i<#rows then i=i+1 end
  for _=1,#rows do
    local row=rows[i]
    if N.mode(prefs,row.kind)~=N.OFF then return row end
    i=i%#rows+1
  end
end
return N

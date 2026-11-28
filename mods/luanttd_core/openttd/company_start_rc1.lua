-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 company_cmd.cpp, company_manager_face.h,
-- table/company_face.h, and strings.cpp. These draws use the same RNG
-- as house, landscape, industry and vehicle ticks.
local C={}
local floor=math.floor
local function bits(word,at,n)
  return floor(word/2^at)%2^n
end
local weights={2,2,3,2,3,2,3,2,3,2,2,2,3,1,1,1}
local similar={{8,5},{6,7},{},{12},{},{0,8},{1,7},{1,6},{0,5},{13,12},{11},{10},{3,9},{9},{15},{14}}
local function remove(t,n)
  for i,v in ipairs(t) do
    if v==n then return table.remove(t,i) end
  end
end
function C.colour(random,existing)
  local shuffle,list={},{}
  for i=1,16 do shuffle[i]=i-1 end
  for _=1,100 do
    local word=random()
    local a,b=bits(word,0,4)+1,bits(word,4,4)+1
    shuffle[a],shuffle[b]=shuffle[b],shuffle[a]
  end
  for w=3,1,-1 do
    for _,v in ipairs(shuffle) do
      if weights[v+1]==w then list[#list+1]=v end
    end
  end
  for _,p in ipairs(existing) do
    remove(list,p.colour)
    for _,v in ipairs(similar[p.colour+1]) do
      if remove(list,v)~=nil then list[#list+1]=v end
    end
  end
  return assert(list[1])
end
-- {offset, bit width, valid values, inactive when off, inactive when on}.
-- The last two columns contain one-based variable indices.
local styles={
  {{3,1,2,{7},{8,9}},{4,1,2,{14}},{5,2,3},{0,0,1},{7,2,4},{9,4,12},
   {13,2,3},{13,4,12},{17,3,8},{20,4,9},{26,2,4},{24,2,3},{28,3,6},{31,1,2}},
  {{3,1,2,{12}},{4,1,2,{13}},{5,2,3},{0,0,1},{0,0,1},{9,4,16},
   {13,4,10},{17,3,4},{20,4,5},{26,2,4},{24,2,3},{28,3,3},{31,1,2}},
  {{3,1,2,{6},{7,8}},{4,1,2,{13}},{0,0,1},{7,2,2},{9,4,11},{13,2,3},
   {13,4,9},{17,3,4},{20,4,5},{26,2,4},{24,2,3},{28,3,6},{31,1,2}},
  {{3,1,2,{11}},{4,1,2,{12}},{0,0,1},{7,2,2},{9,4,16},{13,4,9},
   {17,3,5},{20,4,5},{26,2,4},{24,2,3},{28,3,3},{31,1,2}},
}
local function face(random)
  local style=floor(random()*#styles/4294967296)
  local word,vars,inactive=random(),styles[style+1],{}
  for _,v in ipairs(vars) do
    if v[4] then
      local hidden=bits(word,v[1],1)==0 and v[4] or v[5]
      for _,i in ipairs(hidden or {}) do inactive[i]=true end
    end
  end
  for i,v in ipairs(vars) do
    if not inactive[i] then
      local n=bits(word,v[1],v[2])
      word=word+(n%v[3]-n)*2^v[1]
    end
  end
  return style,word
end
local initials="ABCDEFGHIJKLMNPRSTW"
local surnames={"Adams","Allan","Baker","Bigwig","Black","Bloggs","Brown","Campbell","Gordon","Hamilton",
  "Hawthorn","Higgins","Green","Gribble","Jones","McAlpine","MacDonald","McIntosh","Muir","Murphy","Nelson",
  "O'Donnell","Parker","Phillips","Pilkington","Quigley","Sharkey","Thomson","Watkins"}
function C.surname(word)
  return surnames[floor(#surnames*bits(word,16,8)/256)+1]
end
function C.president(word)
  local a=floor(#initials*bits(word,0,8)/256)+1
  local b=floor((#initials+35)*bits(word,8,8)/256)+1
  return initials:sub(a,a)..". "..(b<=#initials and initials:sub(b,b)..". " or "")..C.surname(word)
end
function C.open(random,existing)
  local used_id,used_name={},{}
  for _,p in ipairs(existing) do
    used_id[p.id],used_name[p.president]=true,true
  end
  local id=0
  while used_id[id] do id=id+1 end
  if id>=15 then return nil end
  local colour=C.colour(random,existing)
  local style,face_bits=face(random)
  local seed,president
  repeat
    seed=random()
    president=C.president(seed)
  until #president<32 and not used_name[president]
  return {id=id,colour=colour,face_style=style,face_bits=face_bits,president_seed=seed,president=president}
end
return C

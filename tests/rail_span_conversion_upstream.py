#!/usr/bin/env python3
"""Differential for stock 14.1 CmdConvertRail on the two mouths of one span.

Use a real command, price/compatibility helpers, span-length calculation
and direction-to-track mapping. Supply an axial rectangle's tile iteration,
map/ownership facts and outcome of the PBS holder search at the host boundary.
"""
from itertools import product
from pathlib import Path
import subprocess
import sys
import tempfile

from rail_types_upstream import ROOT, DIGEST, MAIN, block, cpp, src

DIGEST.update({
    "tunnelbridge.h": "4de7d8cfef5e8d16141bcc6f58bbc8451d1297106f8fcb7238e37403e4e37009",
    "tunnelbridge_map.h": "b67714f412328782a20561d582baef8460fb8947ac3b120bb3a2e5c77017fa7f",
})

DRIVER = r"""
int main() {
  int kind,axis,span_size,selection_mode,from,to,owner,left_res,right_res,under,disabled,occupied;
  while(std::cin>>kind>>axis>>span_size>>selection_mode>>from>>to>>owner>>left_res>>right_res
                >>under>>disabled>>occupied) {
    selection.clear();free_log.clear();retry_log.clear();query_log.clear();power_log.clear();
    notification_log.clear();bridge_dirty.clear();tile_dirty.clear();write_log.clear();compat_checks=0;
    int step=axis?16:1;
    TileIndex a=17,b=a+(span_size-1)*step,g=a+(span_size/2)*step;
    auto *company=Company::Get(1);company->avail_railtypes=3;
    std::fill(company->infrastructure.rail,company->infrastructure.rail+4,0);
    _settings_game.vehicle.disable_elrails=disabled;
    _current_company=1;
    for(TileIndex i=0;i<Map::Size();++i) {
      map[i]=TileRecord{};
      map[i].res=-1;map[i].m8=192;map[i].owner=1;
    }
    std::vector<TileIndex> pts;
    for(TileIndex x=a; x<=b; x+=step) pts.push_back(x);
    for(auto p:{a,b}) {
      auto &r=map[p];r.owner=owner;r.kind=kind;r.other=p==a?b:a;r.m8=192|from;
      r.res=p==a?left_res:right_res;r.reserved={r.res,static_cast<int>(p)};
      r.m5=(p==a?axis+2:axis)|(r.res!=-1?16:0)|(TRANSPORT_RAIL<<2);
      r.occupied=occupied;
    }
    // An ordinary ground rail tile beneath a bridge, or on the surface above
    // a tunnel, not a third record belonging to the span.
    if(under) { map[g].kind=1;map[g].m8=192|from;map[g].bits=axis?1:2; }
    if(selection_mode==0) selection={a};
    if(selection_mode==1) selection={b};
    if(selection_mode==2 || selection_mode==3) selection=pts;
    if(selection_mode==3) std::reverse(selection.begin(),selection.end());
    if(selection_mode==4) selection={g};
    auto quote=CmdConvertRail(0,selection.back(),selection.front(),to,axis!=0);
    assert(free_log.empty()&&retry_log.empty()&&query_log.empty()&&power_log.empty()&&
           notification_log.empty()&&bridge_dirty.empty()&&tile_dirty.empty()&&write_log.empty());
    auto exec=CmdConvertRail(DC_EXEC,selection.back(),selection.front(),to,axis!=0);
    assert(quote.error==exec.error&&quote.value==exec.value&&compat_checks==0);
    assert(free_log==retry_log);  // retry precisely the disempowered resolved holder
    auto out=[&](const auto &log) {
      if(log.empty()) std::cout<<"-";
      else for(auto i:log) std::cout<<i<<",";
      std::cout<<" ";
    };
    if(quote.Failed()) std::cout<<quote.error;
    else std::cout<<quote.value;
    std::cout<<" "<<company->infrastructure.rail[0]<<" "<<company->infrastructure.rail[1]<<" ";
    for(auto i:{a,b,g}) {
      assert((map[i].m8&192)==192);
      std::cout<<GetRailType(Tile{i})<<" ";
    }
    out(write_log);out(query_log);out(free_log);
    out(power_log);out(notification_log);out(bridge_dirty);out(tile_dirty);
    std::cout<<"\n";
  }
}
"""

LUA = r"""
local R=dofile("mods/luanttd_core/openttd/rail_types.lua")
local function format(a)
  if #a==0 then return "-" end
  return table.concat(a,",")..","
end
for line in io.lines() do
  local args={}
  for v in line:gmatch("%-?%d+") do args[#args+1]=tonumber(v) end
  local kind,axis,n,sm,from,to,owner,left,right,under,disable=unpack(args)
  local a,step=17,axis==1 and 16 or 1
  local b,g=a+(n-1)*step,a+math.floor(n/2)*step
  local isbridge=kind==6
  local k=isbridge and "bridge" or "tunnel"
  local m={
    [a]={kind=k,other=b,track=axis,length=n-2,owner=owner,railtype=from,res=left},
    [b]={kind=k,other=a,track=axis,length=n-2,owner=owner,railtype=from,res=right},
    [g]=under==1 and {kind="rail",trackbits=axis==1 and 1 or 2,owner=1,railtype=from,res=-1} or nil
  }
  local tiles={}
  if sm==0 then tiles={a}
  elseif sm==1 then tiles={b}
  elseif sm==2 then for i=a,b,step do tiles[#tiles+1]=i end
  elseif sm==3 then for i=b,a,-step do tiles[#tiles+1]=i end
  else tiles={g} end
  local board={size=256,tile=function(id) return m[id] end}
  local write,query,free,power,notify,bridge_dirty,tile_dirty={},{},{},{},{},{},{}
  function board.reservations(id)
    local t=m[id]
    if t.res==-1 then return {} end
    local track=t.track or 0
    query[#query+1]=id*8+track
    if t.res==-2 then return {} end -- marked portal with no reachable holder
    return {{train=id,railtype=t.res,track=track}}
  end
  local q,why=R.quote_convert(board,tiles,to,{available=3,owner=1,disable_elrails=disable==1})
  local types={[a]=from,[b]=from,[g]=under==1 and from or 0}
  if q then
    for _,u in ipairs(q.updates) do
      types[u.id]=u.to
      write[#write+1]=u.id
    end
    for _,r in ipairs(q.free_reservations) do
      free[#free+1]=r.train
    end
    -- Oracle for the host-side actions implied by the detached plan's
    -- ordered charges.  This does not claim that a Lua world executes them.
    for _,c in ipairs(q.charged) do
      local t=m[c.id]
      power[#power+1]=c.id
      if t.other then
        power[#power+1]=t.other
        notify[#notify+1]=c.id*8+axis
        notify[#notify+1]=t.other*8+axis
        if isbridge then bridge_dirty[#bridge_dirty+1]=c.id
        else
          tile_dirty[#tile_dirty+1]=c.id
          tile_dirty[#tile_dirty+1]=t.other
        end
      else
        tile_dirty[#tile_dirty+1]=c.id
        notify[#notify+1]=c.id*8+(axis==1 and 0 or 1)
      end
    end
  end
  print(table.concat({q and q.cost or why,q and q.infra[0] or 0,q and q.infra[1] or 0,
     types[a],types[b],types[g],format(write),format(query),format(free),format(power),
     format(notify),format(bridge_dirty),format(tile_dirty)}," "))
end
"""


def replace(s, old, new):
    assert s.count(old) == 1, old
    return s.replace(old, new)


def source_code(source):
    text = cpp(source)
    assert text.endswith(MAIN)
    text = text[:-len(MAIN)]
    text = replace(text, "TileIndex Size(){return 16;}", "TileIndex Size(){return 256;}")
    text = replace(text, "TileRecord map[16];", "TileRecord map[256];")
    text = replace(text, "int length,res;", "int length,res,occupied;")
    text = replace(text, "unsigned char m8; Train reserved;", "unsigned char m8,m5; Train reserved;")
    text = replace(text, "&m8() const {return map[id].m8;}",
                   "&m8() const {return map[id].m8;} unsigned char m5() const {return map[id].m5;}")
    text = replace(text, "std::vector<int> free_log;",
                   "std::vector<int> free_log,retry_log,query_log,power_log,notification_log,bridge_dirty,tile_dirty,write_log;"
                   "\nint compat_checks;")
    text = replace(text, "SB(t.m8(), 0, 6, r);", "write_log.push_back(t.id);\n\tSB(t.m8(), 0, 6, r);")
    text = replace(text, 'CommandCost TunnelBridgeIsFree(TileIndex,TileIndex){assert(false);return CMD_ERROR;}',
                   'CommandCost TunnelBridgeIsFree(TileIndex t,TileIndex b){'
                   '++compat_checks;return map[t].occupied||map[b].occupied?CommandCost("OCCUPIED"):CommandCost(0);}')
    text = replace(text, "Train *GetTrainForReservation(TileIndex t, Track){return map[t].res>=0?&map[t].reserved:nullptr;}",
                   "Train *GetTrainForReservation(TileIndex t, Track track){query_log.push_back(t*8+track);"
                   "return map[t].res>=0?&map[t].reserved:nullptr;}")
    text = replace(text, "void TryPathReserve(Train *,bool){}", "void TryPathReserve(Train *t,bool){retry_log.push_back(t->id);}")
    text = replace(text, "void MarkTileDirtyByTile(TileIndex){}", "void MarkTileDirtyByTile(TileIndex t){tile_dirty.push_back(t);}")
    text = replace(text, "void MarkBridgeDirty(TileIndex){}", "void MarkBridgeDirty(TileIndex t){bridge_dirty.push_back(t);}")
    text = replace(text, "void FindVehicleOnPos(TileIndex,TrainList *,void(*)()){}",
                   "void FindVehicleOnPos(TileIndex t,TrainList *,void(*)()){power_log.push_back(t);}")
    text = replace(text, "void YapfNotifyTrackLayoutChange(TileIndex,Track){}",
                   "void YapfNotifyTrackLayoutChange(TileIndex t,Track track){notification_log.push_back(t*8+track);}")
    tunnel_map = src(source,"tunnelbridge_map.h")
    text = replace(text, "int GetTunnelBridgeTransportType(TileIndex){return TRANSPORT_RAIL;}",
                   "bool IsTileType(Tile t,TileType kind){return GetTileType(t.id)==kind;}\nusing TransportType=int;\n"
                   + block(tunnel_map, r"^inline TransportType GetTunnelBridgeTransportType\("))
    text = replace(text, "bool HasTunnelBridgeReservation(TileIndex t){return map[t].res>=0;}",
                   block(tunnel_map, r"^inline bool HasTunnelBridgeReservation\("))
    text = replace(text, "unsigned GetTunnelBridgeLength(TileIndex t, TileIndex){return map[t].length;}",
                   "int TileX(TileIndex t){return t%16;}\nint TileY(TileIndex t){return t/16;}\n"
                   + block(src(source,"tunnelbridge.h"),r"^inline uint GetTunnelBridgeLength\("))
    text = replace(text, "int GetTunnelBridgeDirection(TileIndex){return 0;}",
                   "using DiagDirection=int;\nbool IsValidDiagDirection(int d){return d>=0&&d<4;}\n"
                   + block(tunnel_map, r"^inline DiagDirection GetTunnelBridgeDirection\("))
    text = replace(text, "Track DiagDirToDiagTrack(int d){return d;}",
                   block(src(source,"track_func.h"),r"^inline Track DiagDirToDiagTrack\("))
    return text + DRIVER


def cases():
    fixtures = [
        (6,0,7,0,0,1,1,-1,-1,1,0,1), # north ramp only; ordinary lower-layer rail untouched
        (7,0,7,1,1,0,1,-1, 1,1,0,1), # south portal only; unpowered electric PBS holder
        (6,0,7,2,0,1,1,-1,-1,0,0,1), # both ends, exactly one span charge
        (7,0,7,2,1,0,1,-1, 1,0,0,1), # inspect only initiating portal, not second bit
        (6,0,7,2,0,1,1,-1,-1,1,0,1), # real area equals span + separately selected lower rail
        (6,0,7,4,0,1,1,-1,-1,1,0,1), # convert only the lower rail, not the bridge
    ]
    return fixtures + list(product([6,7], [0,1], [3,7], range(5),
                    [0,1], [0,1], [1,2], [-2,-1,0,1], [-2,-1,0,1], [0,1], [0,1], [0,1]))


def main():
    source=Path(sys.argv[1])
    lua=sys.argv[2] if len(sys.argv)>2 else "lua5.1"
    inputs=cases()
    exchange="\n".join(" ".join(map(str,case)) for case in inputs)+"\n"
    with tempfile.TemporaryDirectory() as tmp:
        tmp=Path(tmp)
        (tmp/"oracle.cpp").write_text(source_code(source))
        (tmp/"code.lua").write_text(LUA)
        subprocess.run(["g++","-std=c++17","-O2",str(tmp/"oracle.cpp"),"-o",str(tmp/"oracle")],check=True)
        ref=subprocess.check_output([str(tmp/"oracle")],input=exchange,text=True).splitlines()
        got=subprocess.check_output([lua,str(tmp/"code.lua")],cwd=ROOT,input=exchange,text=True).splitlines()
    assert len(ref)==len(got)==len(inputs)
    for case,a,b in zip(inputs,ref,got):
        assert a.rstrip()==b,(case,a,b)
    assert ref[0].split()[:6]==["476","-28","28","1","1","0"]
    assert ref[1].split()[:9]==["84","28","-28","0","0","1","23,17,","184,","23,"]
    assert ref[2].split()[:9]==["476","-28","28","1","1","0","17,23,","-","-"]
    assert ref[3].split()[7:9]==["-","-"]
    assert ref[4].split()[:6]==["544","-29","29","1","1","1"]
    assert ref[5].split()[:6]==["68","-1","1","0","0","1"]
    print(f"PASS {len(inputs):,} stock rail span conversions: costs, layer separation, portal reservation/power actions")


if __name__=="__main__":
    main()

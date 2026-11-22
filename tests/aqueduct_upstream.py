#!/usr/bin/env python3
"""Compare the new aqueduct planner with official OpenTTD 14.1 command runs.

python tests/aqueduct_upstream.py /path/openttd /path/share/openttd --lua lua5.1
Uses unmodified stock executable, isolated HOME, loopback-only port, and a
locally installed compatible OpenGFX set. No fixture asset is distributed.
"""
import argparse
import os
from pathlib import Path
import queue
import re
import shutil
import subprocess
import tempfile
import threading
import time

ROOT=Path(__file__).resolve().parents[1]
SCRIPT=r"""
local A=dofile('mods/luanttd_core/openttd/aqueduct.lua')(
  dofile('mods/luanttd_core/openttd/road_bridge.lua')(dofile('mods/luanttd_core/openttd/slope.lua')))
for line in io.lines() do
  local n={}
  for i in line:gmatch("%d+") do n[#n+1]=tonumber(i) end
  local a,len,h,m1,m2,site=n[1],n[2],n[3],n[4],n[5],n[6]
  local grid={}
  for i=1,len+1 do grid[i]={kind="clear",slope=0,base=h,max_z=h} end
  grid[1].slope=m1;grid[len+1].slope=m2
  grid[1].max_z=h+1;grid[len+1].max_z=h+1
  local board={
    tile=function(id) return grid[id] end,
    xy=function(id) return a==0 and id or 1,a==1 and id or 1 end,
    id=function(x,z) return a==0 and x or z end,
    clear_quote=function(id)
      return id==1 and site or 0
    end,
  }
  local p=assert(A.plan(board,len+1,1))
  print(table.concat({p.price,A.clear_cost(p),A.head_record(p,1).bridge_type}," "))
end
"""


def run(binary,share,port):
    with tempfile.TemporaryDirectory(prefix="openttd-aqueduct-") as directory:
        home=Path(directory)
        profile=home/".openttd"
        (profile/"ai").mkdir(parents=True)
        for name in ("lang","baseset","game"):
            (profile/name).symlink_to(share/name,target_is_directory=True)
        for file in (share/"ai").glob("*.nut"):
            (profile/"ai"/file.name).symlink_to(file)
        shutil.copytree(Path(__file__).with_name("aqueduct_ai"),profile/"ai"/"AqueductProbe")
        cfg=home/"openttd.cfg"
        cfg.write_text("[network]\nserver_game_type = local\n[difficulty]\nconstruction_cost = 1\n")
        args=[binary,"-s","null","-m","null","-I","OpenGFX","-D",f"127.0.0.1:{port}",
              "-G","1751","-d","script=5","-c",cfg]
        env={**os.environ,"HOME":str(home),"XDG_CONFIG_HOME":str(home/"config"),
             "XDG_DATA_HOME":str(home/"share")}
        with subprocess.Popen(args,cwd=share,env=env,text=True,stdin=subprocess.PIPE,
                              stdout=subprocess.PIPE,stderr=subprocess.STDOUT,bufsize=1) as game:
            lines=queue.Queue()

            def read():
                for line in game.stdout:
                    lines.put(line)
                lines.put(None)

            threading.Thread(target=read,daemon=True).start()
            deadline=time.monotonic()+45
            version_ok=False
            results=[]
            seen=[]
            try:
                while time.monotonic()<deadline:
                    try:
                        line=lines.get(timeout=.25)
                    except queue.Empty:
                        continue
                    if line is None:
                        break
                    seen.append(line.rstrip())
                    if "Network revision name: 14.1" in line:
                        version_ok=True
                    if "Map generated, starting game" in line:
                        assert version_ok, "Oracle must run the official 14.1 revision"
                        game.stdin.write("start_ai AqueductProbe\nunpause\n")
                        game.stdin.flush()
                    m=re.search(r"AQUEDUCT_RESULT ([\d ]+)",line)
                    if m:
                        results.append(tuple(map(int,m[1].split())))
                    if "AQUEDUCT_DONE" in line:
                        assert len(results)==2
                        return results
                    if "script died" in line.lower():
                        break
                raise AssertionError("Stock probe did not complete:\n"+"\n".join(seen[-35:]))
            finally:
                game.terminate()
                try:
                    game.wait(5)
                except subprocess.TimeoutExpired:
                    game.kill()


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("binary",type=Path)
    p.add_argument("share",type=Path)
    p.add_argument("--lua",default="lua5.1")
    p.add_argument("--port",type=int,default=39743)
    args=p.parse_args()
    results=run(args.binary.resolve(),args.share.resolve(),args.port)
    dataset="\n".join(" ".join(map(str,r[:6])) for r in results)+"\n"
    with tempfile.TemporaryDirectory() as d:
        lua=Path(d)/"aqueduct_cases.lua"
        lua.write_text(SCRIPT)
        code=subprocess.check_output([args.lua,str(lua)],input=dataset,text=True,cwd=ROOT)
    observed=[tuple(map(int,row.split())) for row in code.splitlines()]
    expected=[t[6:] for t in results]
    assert observed==expected,(results,observed)
    for case in results:
        print("stock axis,length,base,head,tail,clear-land,built,demolished,stored-ID",*case)
    print("PASS: two live stock axes; exact build and demolition prices, storage ID 0, unsuitable heads and duplicate refusal.")


if __name__=="__main__":
    main()

#!/usr/bin/env python3
"""Compare OpenTTD 14.1 stock #211 ship data, refit, price and loading to Lua."""
import argparse
import hashlib
from pathlib import Path
import random
import re
import subprocess
import tempfile

from road_loading_upstream import ROOT, SHIM, DRIVER, LUA, extract

DIGEST = {
    "newgrf.cpp": "9de1d16e53976da153d6318843aba244d6c0b27e23ee1f68711c7e5fb8002359",
    "engines.h": "7fa1a77466a4f1aba963eea9147fbe2e7e4c20f85f26a1aad9d8fb8092998182",
    "pricebase.h": "17375cb1dda0c9917f47b3415ca62e795532b97d48acfa12186e895445fd1356",
    "engine.cpp": "b2bbfc2fb77e4b9695730b5e7623f0311e8f7d4d75dbc4fcd166d4ac08691db9",
    "economy.cpp": "073022978e8177f4d542bc83fe5a0e62de4b01b2b290d8fb03aa1bfca4059efb",
    "ship_cmd.cpp": "f664841259821ee557109c15f2f2e6497b7416030a78e0275875f47f1fb8851a",
    "vehicle_cmd.cpp": "0d474c78652fe4c5593ffcb4b6e352fe4293ad869a9c7ff7dacde2bff598d587",
    "timer_game_tick.h": "be45ea7873d9f61e2da80d824de3dede265de76d9178e8afa3dc685c2a95e7e1",
    "timer_game_common.h": "99cd3d7f24d8539d9de72cea942b566911ce7e5cebc1e19e22eddfa368b988cf",
    "cargo_const.h": "3b9344026c8e7b2c9169d531b418aa89858f0cc419585cab5675e8bd16f25c45",
    "vehicle.cpp": "1415664b1b45546544a038176125ecab23d0f702119a712b5fc76375339dd387",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--lua", default="lua5.1")
    ns = parser.parse_args()
    def read(name):
        for d in (".", "src", "src/table", "src/timer"):
            p = ns.source / d / name
            if p.is_file():
                data = p.read_bytes()
                assert hashlib.sha256(data).hexdigest() == DIGEST[name], p
                return data.decode()
        raise FileNotFoundError(name)
    files = {name: read(name) for name in DIGEST}
    eng, eco, ship, prices, command, timer, calendar, refits, cargos, engine, veh = (
        files[k] for k in ("engines.h", "economy.cpp", "ship_cmd.cpp", "pricebase.h", "vehicle_cmd.cpp",
                           "timer_game_tick.h", "timer_game_common.h", "newgrf.cpp", "cargo_const.h", "engine.cpp", "vehicle.cpp")
    )
    def int_at(pattern, body):
        return int(re.search(pattern, body)[1])
    def args_at(pattern, body):
        return re.search(pattern, body)[1].replace(" ", "").split(",")
    def row(macro, body):
        m = re.search(rf"\b{macro}\((.*)\), //\s+(\d+) Yate Cargo ship\b", body)
        return int(m[2]), m[1].replace(" ", "").split(",")
    sid, ship_row = row("MS", eng)
    local_id, prop = row("SVI", eng)
    baseyear = int_at(r"ORIGINAL_BASE_YEAR = (\d+)", calendar)
    yeardays = int_at(r"DAYS_IN_YEAR = (\d+)", calendar)
    day = int_at(r"\bDAY_TICKS = (\d+)", timer)
    age = int_at(r"\bCARGO_AGING_TICKS = (\d+)", timer)
    purchase_base = int_at(r"{\s*(\d+),\s*PCAT_.*///< PR_BUILD_VEHICLE_SHIP\b", prices)
    running_base = int_at(r"{\s*(\d+),\s*PCAT_.*///< PR_RUNNING_SHIP\b", prices)
    assert prop[-1] == "1"
    assert re.search(r"#define SVI\(.*?\).*?VE_DEFAULT, 0, 0 }",eng)
    # Evaluate the exact stock ship allow/disallow class selection, using
    # the active original temperate CargoIDs, not every climate's slots.
    stock = refits[refits.index("/* Cargo ships */"):].split("e->u.ship.old_refittable",1)[0]
    masks = re.search(r"} else {\s*_gted\[engine\]\.cargo_allowed = (.*?);\s*_gted\[engine\]\.cargo_disallowed = (.*?);",stock)
    masks = [set(re.findall(r"CC_\w+", masks[i])) for i in (1,2)]
    classes = {}
    for m in re.finditer(r"^\s*MK\(\s*(\d+),\s*(CT_\w+),([^\n]*)\),",cargos,re.M):
        classes.setdefault(m[2],(int(m[1]),set(re.findall(r"CC_\w+",m[3]))))
    climate = re.search(r"{ CT_PASSENGERS, CT_COAL,.*CT_VALUABLES.*}",cargos)[0]
    active = [classes[k] for k in re.findall(r"CT_\w+",climate)]
    assert sorted(i for i,_ in active)==list(range(11))
    mask = [i for i,cl in active if cl&masks[0] and not cl&masks[1]]
    defm = args_at(r"#define MS\(.*?\) \{ (.*?) \}",eng)
    vals = [sid, local_id,*[int(prop[i]) for i in (0,2,3,4,1,5)], int(ship_row[0]), baseyear, *map(int,ship_row[1:4]),
            classes[ship_row[4]][0], classes["CT_COAL"][0], int(defm[9]), int(defm[4]), day, yeardays, age,
            purchase_base,running_base]
    assert "this->type != VEH_SHIP && default_cargo != cargo_type" in engine
    buyshift = int_at(r"GetPrice\(base_price, cost_factor, this->GetGRF\(\), -(\d+)\)",extract(engine,"Money Engine::GetCost()"))
    refitshift = int_at(r"GetPrice\(base_price, cost_factor, e->GetGRF\(\), -(\d+)\)",extract(command,"static CommandCost GetRefitCost("))
    cost = extract(eco,"Money GetPrice(")
    cost_prelude = r"""
using Price=int;
const Price PR_END=2;
struct GRFFile { int price_base_multipliers[2]; };
Money _price[2];
"""
    per_day = re.search(r"CommandCost cost\(EXPENSES_SHIP_RUN, (.*?)\);",ship)[1].replace(
        "this->GetRunningCost()", "GetPrice(1,factor,nullptr,0)").replace(
        "this->running_ticks","ticks").replace("CalendarTime::DAYS_IN_YEAR",str(yeardays)).replace("Ticks::DAY_TICKS",str(day))
    block=extract(eco,"static void LoadUnloadVehicle(Vehicle *front)")
    rules=block[block.index("ClrBit(front->vehicle_flags, VF_STOP_LOADING)"):block.index("/* Calculate the loading indicator")]
    prelude=r"""
void RoadPulse(Vehicle *front,int loaded,int unloaded,bool retry,bool sliced,int reserved,bool not_full) {
  Station *st=nullptr;
  int new_load_unload_ticks=loaded+unloaded;
  bool anything_loaded=loaded>0,anything_unloaded=unloaded>0 || retry;
  CargoTypes full_load_amount=sliced,reservation_left=reserved,cargo_not_full=not_full,cargo_full=!not_full;
"""
    defs=cost_prelude+cost+rf"""
void Prices() {{
  int requested,current,price,factor,ticks,running_base;
  std::cin>>requested>>current>>price>>factor>>ticks>>running_base;
  _price[0]=price;
  _price[1]=running_base;
  if (!(({sum(1<<i for i in mask)}u>>requested)&1)) {{ std::cout<<"X\n";return; }}
  std::cout<<GetPrice(0,{int(prop[1])},nullptr,-{buyshift})<<","<<
    GetPrice(0,requested==current?0:{int(defm[9])},nullptr,-{refitshift})<<","<<{per_day}<<"\n";
}}
"""+extract(eco,"static void UpdateLoadUnloadTicks(")+"\n"+prelude+rules+"\n}\n"+extract(veh,"void Vehicle::HandleLoading(bool mode)")
    driver=DRIVER[:DRIVER.index("else if(kind=='S')")]+"else if(kind=='P') { Prices(); } else std::abort();\n  }\n}\n"
    driver=driver.replace("Vehicle u;","Vehicle u; u.type=2 /* VEH_SHIP */;")
    lua=LUA[:LUA.index("    local v={id=3")]+"""
    local q=R.quote(a[2],a[4],a[3])
    if not q then print("X") else print(table.concat({q.purchase,q.refit,R.running_fixed(a[6],a[7])},",")) end
  end
end
"""
    lua=lua.replace('local T=dofile(base.."openttd/loading_timing.lua")',
                    'local R=dofile(base.."openttd/ship_roster.lua")\nlocal T=R.timing(dofile(base.."openttd/loading_timing.lua"))')
    # Input first emits the extracted table identity separately; compare
    # all constants that determine build, refit, motion and service.
    data_keys="id local_id image acceleration max_speed capacity purchase_factor running_factor intro base_year decay life base_life default_cargo coal refit_factor load_amount day_ticks year_days cargo_age_ticks purchase_base running_base"
    lua=lua.replace("for line in io.lines() do",
        'local table_identity={}\nfor k in ("'+data_keys+'"):gmatch("%S+") do table_identity[#table_identity+1]=assert(R[k]) end\nprint(table.concat(table_identity,","))\nfor line in io.lines() do')
    rng=random.Random(211)
    cases=[]
    for _ in range(6000):
        args=(rng.randrange(11),rng.randrange(11),rng.randrange(2),rng.randrange(2),
              rng.randrange(4),rng.randrange(2),rng.randrange(2),rng.randrange(2),
              rng.choice((0,2,3,4)),rng.randrange(400),rng.randrange(-150,150),
              rng.randrange(600),rng.randrange(2))
        cases.append("T "+" ".join(map(str,args)))
        args=(rng.randrange(11),rng.randrange(11),rng.randrange(1000000),int(prop[5]),
              rng.randrange(75),rng.randrange(50000))
        cases.append("P "+" ".join(map(str,args)))
    data=("\n".join(cases)+"\n").encode()
    with tempfile.TemporaryDirectory() as d:
        p=Path(d)
        (p/"stock.cpp").write_text(SHIM+defs+driver)
        (p/"ship.lua").write_text(lua)
        subprocess.run(["c++","-std=c++20","-O2",str(p/"stock.cpp"),"-o",str(p/"stock")],check=True)
        stock=subprocess.check_output([str(p/"stock")],input=data).splitlines()
        port=subprocess.check_output([ns.lua,str(p/"ship.lua")],input=data,cwd=ROOT).splitlines()
    assert port[0].decode()==",".join(map(str,vals)), (port[0],vals)
    for inp,want,got in zip(cases,stock,port[1:],strict=True):
        assert want==got, (inp,want,got)
    print("PASS: pinned OpenTTD 14.1 #211 Yate stock table + 6,000 compiled loading/leave and 6,000 price/refit/running comparisons")


if __name__=="__main__":
    main()

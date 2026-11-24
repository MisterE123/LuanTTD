#!/usr/bin/env python3
"""Drive Lua-backed gameplay through the actual Linux Luanti UI.

The observer is read-only except for camera aim, and never submits GUI fields.
Its checkpoints attribute construction, operation and revenue to GUI input.
"""
import json
import math
import os
from pathlib import Path
import signal
import subprocess as sp
import sys
import time

from PIL import Image, ImageChops

out, port, server, client = Path(sys.argv[1]), *sys.argv[2:]
trace = out / "world" / "native.json"
user = "NativeQA"
fresh_profile = os.environ.get('BAYLINE_NATIVE_FRESH') == '1'
turns = os.environ.get('BAYLINE_NATIVE_TURNS') == '1'
yapf = os.environ.get('BAYLINE_NATIVE_YAPF')
assert yapf in (None,"plain","stop")
sensitivity = None
processes = []
phase = "initial startup"
server_process = None
client_process = None
grade = os.getenv("BAYLINE_NATIVE_GRADE") == "1"


def state():
    try:
        return json.loads(trace.read_text())
    except FileNotFoundError:
        return {}


def await_state(description, matches, seconds=10):
    until = time.monotonic() + seconds
    while time.monotonic() < until:
        s = state()
        if s and matches(s):
            return s
        if server_process and server_process.poll() is not None:
            raise RuntimeError(f"Server exited ({server_process.returncode}); inspect server log")
        time.sleep(.12)
    raise AssertionError(f"Timed out waiting for {description}: {state()}")


def start(which, args, filename):
    with (out / filename).open("w") as log:
        verbose = ["--verbose"] if filename=="server-camera.log" else []
        p = sp.Popen([which, *args, *verbose, "--logfile", ""], stdout=log, stderr=sp.STDOUT)
    processes.append(p)
    return p


def join(name):
    global server_process, client_process
    trace.unlink(missing_ok=True)
    server_process = start(server, ["--world", str(out / "world"),
                                   "--config", str(out / "server.conf"), "--gameid", "luanttd"], f"server-{name}.log")
    await_state("server to update the test observer", lambda s: not s["present"])
    client_process = start(client, ["--config", str(out / "client.conf"), "--go", "--address",
                                   "127.0.0.1", "--port", port, "--name", user,
                                   "--password", "test-world-only"], f"client-{name}.log")
    s = await_state("native client to join", lambda s: s["present"], 105)
    win = sp.check_output(["xdotool", "search", "--sync", "--onlyvisible", "--pid",
                          str(client_process.pid)], timeout=12).decode().splitlines()[-1]
    xdo("windowfocus", "--sync", win)
    xdo("mousemove", "750", "462")
    # The telemetry sees the server-side join before the world textures load.
    time.sleep(2)
    return s


def xdo(*args):
    sp.run(["xdotool", *map(str, args)], check=True, timeout=10)


def screenshot(name):
    path = out / (name+".png")
    sp.run(["import", "-window", "root", str(path)], check=True, timeout=10)
    return path


def chat(command):
    xdo("key", "t")
    time.sleep(.22)
    xdo("type", "--clearmodifiers", command)
    xdo("key", "Return")


def angle_delta(a, b):
    return (a-b+math.pi)%(2*math.pi)-math.pi


def native_aim(x, z, target_height=.5, framing=False):
    """Normal relative mouse motion from spawn; no teleport or aim command."""
    global sensitivity
    wanted=f"{x},{z}"
    def pose():
        return state()["camera"]
    if sensitivity is None:
        first=pose()
        xdo("mousemove_relative", "--", 30, 20)
        time.sleep(.6)
        after=pose()
        sy=angle_delta(after["yaw"],first["yaw"])/30
        sp=(after["pitch"]-first["pitch"])/20
        if not (abs(sy)>1e-4 and abs(sp)>1e-4):
            raise AssertionError(f"No mouse-look response: {first!r} → {after!r}")
        sensitivity=sy,sp
    for _ in range(7):
        if not framing and state()["target"]==wanted:
            return
        cur=pose()
        pos=cur["pos"]
        dx,dz=2*x+.5-pos["x"],2*z+.5-pos["z"]
        yaw=math.atan2(-dx,dz)
        pitch=math.atan2(pos["y"]+cur["eye"]-target_height,math.hypot(dx,dz))
        if framing and abs(angle_delta(yaw,cur["yaw"]))<.02 and abs(pitch-cur["pitch"])<.02:
            return
        dy=round(angle_delta(yaw,cur["yaw"])/sensitivity[0])
        dp=round((pitch-cur["pitch"])/sensitivity[1])
        dy,dp=(max(-260,min(260,n)) for n in (dy,dp))
        xdo("mousemove_relative","--",dy,dp)
        time.sleep(.5)
    if framing: raise AssertionError("Mouse did not reach desired showcase view")
    await_state("native mouse targeted "+wanted,lambda s:s["target"]==wanted,2)


def aim(x, z):
    if fresh_profile:
        native_aim(x,z)
        return
    pos = f"{x},{z}"
    chat(f"/qa_aim {x} {z}")
    await_state("camera pointing at tile "+pos, lambda s: s.get("aim") == pos and s["target"] == pos)
    time.sleep(.35)


inspect_via_teleport = False


def click(n=1):
    if n == 1 and inspect_via_teleport:
        n = 3
    # Keep the ordinary physical press visible for at least two server ticks.
    xdo("mousedown", n)
    time.sleep(.23)
    xdo("mouseup", n)
    time.sleep(.16)


def hold_to_build(point_at, start, end):
    point_at(*start)
    xdo("mousedown",1)
    time.sleep(.24)
    try:
        point_at(*end)
        time.sleep(.18)
    finally:
        xdo("mouseup",1)
    time.sleep(.22)


def slot(n):
    global inspect_via_teleport
    # Fixture contracts use the logical action; send the physical key on
    # the compact row. A full toolbar exposes Inspect as Teleport's
    # secondary action, and its authored slot is then absent.
    def resolved(s):
        layout = s.get("hotbar_layout") or list(range(1,11))
        return n if n in layout else 11 if n==1 and 11 in layout else None
    snapshot=await_state(f"hotbar action {n} is mounted", lambda s:resolved(s) is not None)
    wanted=resolved(snapshot)
    inspect_via_teleport=n==1 and wanted==11
    layout=snapshot.get("hotbar_layout") or list(range(1,11))
    physical = layout.index(wanted) + 1
    if wanted==9 and snapshot.get("hotbar")==physical and snapshot.get("wield_item")=="luanttd_core:menu_clear":
        # Selecting an already-highlighted inherited slot isn't an
        # engine selection event. Explicitly reselect it for build tests.
        alternate=1 if physical!=1 else 2
        xdo("key",alternate)
        await_state("moved off inherited Bulldoze",lambda s:s.get("hotbar")==alternate)
        time.sleep(.18)
    xdo("key", 0 if physical == 10 else physical)
    await_state(f"hotbar action {n} (physical {physical})", lambda s:
        s["hotbar"] == physical and (not s.get("hotbar_layout") or
                                     s["hotbar_layout"][physical-1] == wanted))


def rail_engineering():
    slot(7);click()
    await_state("Rail Tools & Operations",lambda s:s.get("menu")=="railops")
    slot(1);click()
    await_state("Rail Engineering",lambda s:s.get("menu")=="railengineering")


def leave_rail_engineering():
    slot(8);click()
    await_state("Back to Rail Tools & Operations",lambda s:s.get("menu")=="railops")
    slot(8);click()
    await_state("Back to Rail Construction",lambda s:s.get("menu")=="railworks")


def choose_bridge_type(style=0):
    state_now=await_state("bridge type picker",lambda s:s.get("form")=="luanttd_core:bridge_picker")
    candidates=[f for f in state_now["buttons"] if f.startswith("bridge_") and f.endswith(f"_{style}")]
    assert len(candidates)==1,state_now["buttons"]
    choose("luanttd_core:bridge_picker",candidates[0],"choose-mode-specific-bridge-type")


def rotate_rail_fitting(times):
    rail_engineering()
    slot(6)
    for _ in range(times):
        click()
    leave_rail_engineering()


def tile(s, p):
    return (s.get("builds") or {}).get(f"{p[0]},{p[1]}", {}).get("name")


def choose(form, control, name):
    s = await_state(form+" with "+control, lambda s: s.get("form") == form and control in (s.get("buttons") or {}))
    # Find the real rendered panel using its background color then translate
    # the read-only formspec layout to screen coordinates. Never submit fields.
    im = Image.open(screenshot(name)).convert("RGB")
    w, h, bg = s["panel"]
    rgb = tuple(bytes.fromhex(bg))
    diff = ImageChops.difference(im, Image.new("RGB", im.size, rgb))
    r,g,b = diff.split()
    eq = ImageChops.lighter(ImageChops.lighter(r,g),b).point(
        lambda p: 255 if p == 0 else 0)
    bounds = eq.getbbox()
    if not bounds:
        raise AssertionError(f"The active {form} was not visible on the screen")
    left,top,right,bottom = bounds
    assert abs((right-left)/w - (bottom-top)/h) < 1.0, (s["panel"], bounds)
    x,y,bw,bh = s["buttons"][control]
    px = x+bw/2
    # If another button overlaps (known on the legacy palette), physically
    # click only the largest exposed vertical portion. Log this UI defect.
    viable = []
    for i in range(3,98):
        py = y+i*bh/100
        if not any(ox <= px <= ox+ow and oy <= py <= oy+oh
                   for key,(ox,oy,ow,oh) in s["buttons"].items() if key!=control):
            viable.append(py)
    if len(viable) < 80:
        print(f"UI FRICTION: {control} overlaps another control "
              f"(only {len(viable)}% of button centerline exposed)", flush=True)
    if not viable:
        raise AssertionError(f"{control} is fully obscured")
    py=viable[len(viable)//2]
    xdo("mousemove", round(left+(right-left)*px/w), round(top+(bottom-top)*py/h))
    click()


def ramp_shapes(s):
    g = s.get("grade_tiles") or {}
    if not g:
        return False
    want = {"12":(0,0,0), "13":(3,0,1), "14":(0,1,1),
            "16":(0,1,1), "17":(12,0,1), "18":(0,0,0)}
    return all(tuple(g[x][k] for k in ("shape", "base", "top")) == vals
               for x, vals in want.items())


def ramp_nodes(s):
    if not ramp_shapes(s):
        return False
    g=s["grade_tiles"]
    return (g["13"].get("node") == "luanttd_core:road_grade_3"
            and g["17"].get("node") == "luanttd_core:road_grade_12"
            and all(v.get("road") == v["shape"] and v.get("road_base") == v["base"] for v in g.values()))


def ramp_traversal(s):
    samples=s.get("grade_samples") or {}
    return samples.get("ascending",0)>0 and samples.get("descending",0)>0


def assert_clearance(s):
    assert ramp_traversal(s), s.get("grade_samples")
    assert s["grade_samples"]["height_error"] < .012, s["grade_samples"]
    # Physics observer allows modest pitch blending between ramp and apron.
    assert s["grade_samples"]["pitch_error"] < .10, s["grade_samples"]


def stop_server(client_first=False):
    if client_first and client_process.poll() is None:
        # Match a player leaving an active world before stopping the host.
        # Complete the leave-save before requesting the shutdown save.
        client_process.send_signal(signal.SIGINT)
        client_process.wait(timeout=12)
        await_state("client left before save and shutdown",lambda s:not s["present"],35)
    server_process.send_signal(signal.SIGINT)
    code = server_process.wait(timeout=15)
    if code:
        raise AssertionError(f"Server did not save and exit cleanly ({code})")
    if client_process.poll() is None:
        client_process.terminate()
        try:
            client_process.wait(timeout=6)
        except sp.TimeoutExpired:
            # A software-rendered client sometimes remains in its
            # disconnected UI. Server shutdown/save above is mandatory.
            client_process.kill()
            client_process.wait(timeout=5)


def camera_regression():
    phase_name = "camera flight"
    def sweep(key=None, count=18):
        samples=[]
        if key: xdo("keydown",key)
        try:
            samples.append(state()["camera"])
            for _ in range(count):
                xdo("mousemove_relative","--",12,2)
                time.sleep(.12)
                samples.append(state()["camera"])
        finally:
            if key: xdo("keyup",key)
        angles=[angle_delta(b["yaw"],a["yaw"]) for a,b in zip(samples,samples[1:])]
        pitch=[b["pitch"]-a["pitch"] for a,b in zip(samples,samples[1:])]
        distance=math.dist(tuple(samples[0]["pos"].values()),tuple(samples[-1]["pos"].values()))
        return {"yaw":sum(angles),"pitch":sum(pitch),"distance":distance,
                "minimum_y":min(s["pos"]["y"] for s in samples),
                "maximum_y":max(s["pos"]["y"] for s in samples), "samples":samples}

    join("camera")
    # Compare identical horizontal and vertical mouse updates with and
    # without flight input. Initial spawn is outside the measurement.
    xdo("mousemove_relative","--",0,-100)
    time.sleep(.6)
    still=sweep()
    moving=sweep("w")
    climbing=sweep("space")
    time.sleep(.7)
    descending=sweep("Shift_L")
    time.sleep(.7)
    settled=state()["camera"]["pos"]["y"]
    time.sleep(.9)
    stable=state()["camera"]["pos"]["y"]
    screenshot("camera-moving-and-looking")
    if server_process: stop_server()
    log=(out/"server-camera.log").read_text()
    packets=log.count("Server: Sending TOCLIENT_MOVE_PLAYER pos=")
    (out/"camera-result.json").write_text(json.dumps(
        {"stationary":still,"moving":moving,"climb":climbing,"descend":descending,
         "vertical_drift":stable-settled,"absolute_camera_packets":packets},indent=2))
    print(f'{phase_name} | yaw stationary {still["yaw"]:.3f}, moving {moving["yaw"]:.3f}, rising {climbing["yaw"]:.3f}; '
          f'world translation {moving["distance"]:.2f}; vertical drift {stable-settled:.3f}; absolute packets {packets}')
    if os.environ.get("BAYLINE_NATIVE_CAMERA_BASELINE")!="1":
        assert 0.7 < moving["yaw"]/still["yaw"] < 1.3
        assert 0.7 < climbing["yaw"]/still["yaw"] < 1.3
        assert 0.6 < moving["pitch"]/still["pitch"] < 1.4
        assert moving["distance"]>5
        assert climbing["maximum_y"]-climbing["minimum_y"]>4
        assert abs(stable-settled)<.4
        assert 0.7 < descending["yaw"]/still["yaw"] < 1.3
        assert descending["maximum_y"]-descending["minimum_y"]>4
        assert 1<=packets<9,"expected spawn packets, not ongoing absolute view resets"


try:
    if os.environ.get("BAYLINE_NATIVE_CAMERA")=="1":
        camera_regression()
        sys.exit(0)
    fresh = join("build")
    assert fresh["fleets"] == 0 and fresh["revenue"] == 0
    if os.environ.get("BAYLINE_NATIVE_AQUEDUCT")!="1":
        assert not fresh["builds"]
    if os.environ.get("BAYLINE_NATIVE_HOTBAR_POLISH")=="1":
        phase="new hotbar routes and readable native player HUD"
        assert all((fresh.get("stock_workbenches") or {}).get(k) for k in
                   ("rail","ship","air","tram","freight","oneway","bays"))
        def opened(key,menu):
            slot(key);click()
            return await_state(menu,lambda s:s.get("menu")==menu)
        def verify(key,item,shot=None):
            slot(key)
            record=await_state(item,lambda s:s.get("wield_item")=="luanttd_core:menu_"+item)
            if shot:
                time.sleep(.4);screenshot(shot)
            return record.get("cash")
        opened(4,"company");slot(5);click()
        # Pause the economy so monthly loan interest cannot be mistaken for
        # an accidental construction debit.
        baseline=opened(8,"home")["cash"]
        verify(10,"section_portair","00-polished-home")
        opened(10,"portair")
        opened(2,"harbor");verify(9,"clear","01-polished-harbors")
        opened(8,"portair")
        opened(3,"airfields");verify(2,"airfield_build")
        opened(8,"portair");opened(8,"home")
        opened(2,"roads");verify(9,"clear","02-polished-roads")
        opened(5,"freight");verify(3,"truck_stop_tool","03-polished-road-freight")
        opened(8,"roads")
        opened(7,"road_direction")
        opened(4,"tramway");verify(9,"clear","04-polished-tramways")
        opened(8,"road_direction");opened(8,"roads");opened(8,"home")
        opened(8,"railworks")
        opened(5,"railsignals");verify(2,"rail_signal_pbs","05-polished-path-signals")
        opened(8,"railworks");opened(8,"home")
        opened(7,"terrain")
        verify(4,"landscape_level")
        await_state("terrain target",lambda s:s.get("target") not in (None,"-"))
        click()
        await_state("level area first corner selected",lambda s:s.get("road_gesture"))
        click(3)
        await_state("right click cancels level area without opening a sheet",lambda s:
            not s.get("road_gesture") and not s.get("form") and s["cash"]==baseline)
        opened(8,"home")
        opened(5,"navigation");verify(5,"jump","06-polished-navigation")
        final=opened(8,"home")
        assert not final.get("builds") and final["cash"]==baseline
        (out/"native-hotbar-polish.json").write_text(json.dumps({
            "home":"transport and construction","sea_air":True,"freight":True,
            "tramway":True,"rail_signals":True,"jump":True,"cash":final["cash"]},indent=2))
        stop_server(client_first=True)
        print(f"PASS: actual polished toolbar, all pictured routes and Back; no accidental building: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_WATER_EFFECTS")=="1":
        phase="verify coast, moving river and actual native water shader"
        def survey_water(x,z):
            chat(f"/survey {x} {z}")
            await_state("survey is correctly framed",lambda s:
                abs(s["camera"]["pos"]["x"]-(x*2+.5))<.1 and
                abs(s["camera"]["pos"]["z"]-(z*2-8))<.1)
        survey_water(15,18)
        proof=await_state("flat and inclined river render through native water nodes",lambda s:
            (s.get("water_fx") or {}).get("plain","").startswith("luanttd_core:ocean_top_") and
            s["water_fx"].get("river","").startswith("luanttd_core:stock_river_flat") and
            s["water_fx"].get("slope","").startswith("luanttd_core:stock_river_3"))["water_fx"]
        assert proof["waving"]==3 and abs(proof["fog"]["fog_start"]-.65)<.02,proof
        time.sleep(.8)
        screenshot("01-river-animated-with-haze")
        crop=(350,500,620,630)
        def coast_frame(label):
            chat("/qa_water_coast")
            await_state("fixed low ocean viewpoint",lambda s:
                abs(s["camera"]["pos"]["x"]-7)<.1 and abs(s["camera"]["pos"]["z"]-18)<.1)
            # Confirm that the client has actually emerged water, not the
            # uniform gray scene drawn before the mapblocks arrive.
            for _ in range(12):
                time.sleep(.50)
                path=screenshot(label)
                im=Image.open(path).convert("RGB").crop(crop)
                px=list(im.getdata())
                if sum(b>r+14 and b>g+5 for r,g,b in px)>.75*len(px):
                    return im
            raise AssertionError("Ocean crop did not draw colored water")
        a=coast_frame("02-coast-reflections-on")
        time.sleep(.85)
        b=Image.open(screenshot("03-coast-next-wave-frame")).convert("RGB").crop(crop)
        diff=ImageChops.difference(a,b)
        motion=sum(1 for px in diff.getdata() if sum(px)>5)
        assert motion>250,motion
        stop_server(client_first=True)
        conf=out/"client.conf"
        conf.write_text(conf.read_text().replace("enable_water_reflections = true","enable_water_reflections = false"))
        join("water-reflections-off")
        off=coast_frame("04-coast-reflections-off")
        difference=ImageChops.difference(a,off)
        shader=sum(1 for px in difference.getdata() if sum(px)>15)
        from PIL import ImageStat
        luminance=lambda im:sum(ImageStat.Stat(im).mean)/3
        delta=abs(luminance(a)-luminance(off))
        assert shader>3000 and delta>4,(shader,delta)
        (out/"native-water-effects.json").write_text(json.dumps(
            {"nodes":proof,"moving_pixels":motion,"reflection_ab_pixels":shader,"mean_luminance_delta":delta},indent=2))
        stop_server(client_first=True)
        print(f"PASS: native Luanti reflected water A/B, animated frames, flowing river nodes, haze: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_JUMP_MAP")=="1":
        phase="open dense Jump Map from the normal hotbar"
        chat("/tools")
        slot(5);click()
        await_state("Navigation menu",lambda s:s.get("menu")=="navigation")
        slot(5);click()
        opened=await_state("the detailed native overview has a compact area grid and place labels",lambda s:
            s.get("form") in ("luanttd_core:dispatch","luanttd_core:worker_jump") and
            150 <= (s.get("jump_map") or {}).get("count",0) <= 576 and s["jump_map"]["labels"]>=1)
        # The server's form record precedes the client raster/GUI build.
        time.sleep(.75)
        snap=screenshot("dense-native-jump-map")
        im=Image.open(snap).convert("RGB")
        def mask_exact(rgb):
            diff=ImageChops.difference(im,Image.new("RGB",im.size,rgb))
            r,g,b=diff.point(lambda p:255 if p==0 else 0).split()
            return ImageChops.darker(ImageChops.darker(r,g),b)
        bounds=ImageChops.lighter(mask_exact((45,105,133)),mask_exact((23,42,54))).getbbox()
        assert bounds and bounds[2]-bounds[0]>400 and bounds[3]-bounds[1]>400,bounds
        left,top,right,bottom=bounds
        width=opened["generated"]["width"]
        if width==128:
            def toggle_zoom():
                xdo("mousemove",round(left+(17.48-1.95)*(right-left)/10.38),
                    round(top+(3.25-2.46)*(bottom-top)/10.38))
                click()
            toggle_zoom()
            await_state("128x128 switches to individual world tiles",lambda s:
                (s.get("jump_map") or {}).get("detail"))
            time.sleep(.7)
            screenshot("dense-native-local-detail")
            toggle_zoom()
            await_state("returns to full region",lambda s:s.get("jump_map") and not s["jump_map"]["detail"])
            time.sleep(.7)
        stride=(width+23)//24
        areas=(width+stride-1)//stride
        cell_col,cell_row=19,15
        xdo("mousemove",round(left+(cell_col+.5)*(right-left)/areas),
            round(top+(cell_row+.5)*(bottom-top)/areas))
        click()
        xs=range(cell_col*width//areas+1,(cell_col+1)*width//areas+1)
        zs=range(cell_row*width//areas+1,(cell_row+1)*width//areas+1)
        landed=await_state("clicked far-away dense map cell and returned to the 3D world",lambda s:
            not s.get("form") and
            any(abs(s["camera"]["pos"]["x"]-(2*x+.5))<.08 for x in xs) and
            any(abs(s["camera"]["pos"]["z"]-(2*z+.5))<.08 for z in zs))
        screenshot("dense-native-jump-destination")
        (out/"native-jump-map.json").write_text(json.dumps({"tile_count":opened["jump_map"]["count"],
            "width":width,"destination":landed["camera"]["pos"]},indent=2))
        stop_server(client_first=True)
        print(f"PASS: native dense {width}x{width} overview, physical click to a distant 3D destination: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_SLOPE_RENDER")=="1":
        phase="observe the original one-corner slope in the live renderer"
        assert fresh["generated"]["width"]==64 and not fresh.get("starter_map")
        chat("/survey 16 8")
        await_state("at the sampled generated corner",lambda s:
            abs(s["camera"]["pos"]["x"]-32.5)<.2 and
            abs(s["camera"]["pos"]["z"]-8)<.2 and s["camera"]["pos"]["y"]>=19.9)
        native_aim(16,8,1.7,framing=True)
        screenshot("01-one-corner-slope-survey")
        xdo("keydown","Shift_L")
        try:
            time.sleep(1)
        finally:
            xdo("keyup","Shift_L")
        native_aim(16,8,1.7,framing=True)
        screenshot("02-one-corner-slope-lower-view")
        stop_server(client_first=True)
        print(f"PASS: ordinary generated one-corner slope viewed from two native client elevations: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_CLEAR_AREA")=="1":
        phase="start the native Bulldozer without changing the selected tile on mouse-down"
        chat("/qa_demolition_fixture");chat("/survey 35 14")
        before=await_state("priced demolition cells",lambda s:(s.get("demolition") or {}).get("on")==[True]*8)
        h=before["demolition"]["height"]
        slot(2);click()
        await_state("Road Construction menu opened",lambda s:s.get("menu")=="roads")
        slot(9);native_aim(33,15,h[0])
        xdo("mousedown",1)
        await_state("a held single click is only a proposal",lambda s:
            s["demolition"].get("anchor") and s["demolition"]["on"][0] and s["cash"]==250)
        xdo("mouseup",1)
        single=await_state("single click released exactly one ordinary piece",lambda s:
            s["demolition"]["on"]==[False]+[True]*7 and s["cash"]==170)

        phase="hold across an ordered rectangle; skip protected tile and stop at unaffordable tile"
        native_aim(37,14,h[5]);xdo("mousedown",1)
        await_state("rectangle press recorded with no charge",lambda s:s["demolition"]["anchor"] and s["cash"]==170)
        native_aim(33,14,h[1])
        assert state()["demolition"]["on"]==single["demolition"]["on"]
        screenshot("01-stock-demolition-affordable-preview")
        xdo("mouseup",1)
        rectangle=await_state("the row-major affordable prefix removes 33 and 35 but not others",lambda s:
            s["demolition"]["on"]==[False,False,True,False,True,True,True,True] and s["cash"]==10)
        assert rectangle["demolition"]["owner"][2]=="OtherCompany"
        assert "Next costs $80" in rectangle["demolition"]["status"]
        assert rectangle["demolition"]["limit"]==before["demolition"]["limit"]-65536*3

        phase="right-click cancels a held drag without letting its later release clear"
        native_aim(36,14,h[4]);xdo("mousedown",1)
        await_state("gesture active before cancel",lambda s:s["demolition"]["anchor"])
        click(3)
        await_state("press canceled",lambda s:not s["demolition"]["anchor"])
        xdo("mouseup",1)
        assert state()["cash"]==10 and state()["demolition"]["on"]==rectangle["demolition"]["on"]

        phase="hold Aux1 on release; use stock release-first diagonal order with one clear left"
        chat("/qa_demolition_fixture diag")
        await_state("one remaining clearing unit",lambda s:s["demolition"]["limit"]==65537)
        native_aim(38,14,h[6]);xdo("mousedown",1)
        await_state("first corner anchored",lambda s:s["demolition"]["anchor"])
        native_aim(40,15,h[7]);xdo("keydown","e")
        await_state("Aux1 is active before release",lambda s:s["demolition"].get("aux"))
        xdo("mouseup",1)
        diagonal=await_state("diagonal begins at release rather than first corner",lambda s:
            s["demolition"]["on"][-2:]==[True,False] and s["demolition"]["limit"]==1)
        xdo("keyup","e")
        assert diagonal["cash"]==920 and "Clearing limit reached" in diagonal["demolition"]["status"]
        screenshot("02-stock-demolition-diagonal-done")
        (out/"stock-area-demolition.json").write_text(json.dumps(
            {"before":before["demolition"],"single":single["demolition"],"rectangle":rectangle["demolition"],
             "diagonal":diagonal["demolition"]},indent=2))
        stop_server(client_first=True)
        print(f"PASS: native click and held drag, protected skip, progressive money, cancel, Aux1 diagonal and quota: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_STOCK_WATER_GUI")=="1":
        phase="use shared Bulldoze on real sea in the generated default world"
        assert fresh["generated"]["width"]==64 and not fresh.get("starter_map")
        chat("/qa_freeze_coast");chat("/survey 2 2")
        before=await_state("ordinary default sea in the selected view",
            lambda s:s["clear_water"]["terrain"]=="water" and s["clear_water"]["paused"])
        slot(2);click()
        await_state("Road Construction",lambda s:s.get("menu")=="roads")
        slot(9);native_aim(2,2,.5)
        screenshot("01-real-sea-clear-preview")
        click()
        after=await_state("the cleared sea tile is now exposed land",
            lambda s:s["clear_water"]["terrain"]=="grass")
        assert before["cash"]-after["cash"]==10000
        screenshot("02-ordinary-bulldozer-cleared-sea")
        (out/"stock-water-gui.json").write_text(json.dumps({
            "before":before["clear_water"],"after":after["clear_water"],"cost":10000},indent=2))
        stop_server(client_first=True)
        print(f"PASS: ordinary sea is not protected from the real Bulldozer hotbar; $10,000 stock clear price: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_CROSSING_CONNECT_GUI")=="1":
        phase="connect the existing railway crossing with the ordinary Road hotbar"
        chat("/qa_existing_crossing");chat("/survey 13 12")
        before=await_state("existing crossing and unconnected west half-road",lambda s:
            (s.get("existing_crossing") or {}).get("road")==8 and
            (s.get("existing_crossing") or {}).get("mesh")=="luanttd_core:level_crossing_1_open")
        assert not before["existing_crossing"].get("connected")
        screenshot("01-crossing-missing-approach")
        slot(2);click()
        await_state("Road Construction",lambda s:s.get("menu")=="roads")
        # The existing crossing lies outside the selected run. It must
        # supply only the reciprocal endpoint bit, not be rebuilt.
        slot(2);native_aim(11,12,1.5)
        xdo("mousedown",1)
        await_state("held Road input has an anchor",lambda s:s["existing_crossing"].get("anchor"))
        native_aim(13,12,1.5)
        assert state()["existing_crossing"]["road"]==8 and state()["cash"]==before["cash"]
        screenshot("02-autoroad-held-before-release")
        xdo("mouseup",1)
        after=await_state("the half-road now meets the open crossing",lambda s:
            (s.get("existing_crossing") or {}).get("road")==10 and s["existing_crossing"].get("connected"))
        assert after["existing_crossing"].get("same")
        assert before["cash"]-after["cash"]==63
        screenshot("03-ordinary-road-connects-the-crossing")
        (out/"ordinary-crossing-native.json").write_text(json.dumps({
            "before":before["existing_crossing"],"after":after["existing_crossing"],"cost":63},indent=2))
        stop_server(client_first=True)
        print(f"PASS: actual mouse with ordinary Road connects existing crossing; only missing half charged $63: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_ELECTRIC_BRIDGE_GUI")=="1":
        assert fresh["electric"]["available"] and fresh["electric"]["year"]==1978
        assert fresh["starter_map"]["name"]=="coastal test circuit"
        phase="mouse-build the true timber bridge across the coastal test circuit channel"
        chat("/survey 24 15")
        def rail_at(x): native_aim(x,15,1.5);click()
        slot(8);click()
        await_state("Railworks",lambda s:s.get("menu")=="railworks")
        slot(10);rail_at(21);rail_at(27)
        if state().get("form")=="luanttd_core:bridge_picker":
            choose_bridge_type()
        plain=await_state("seven real wooden bridge cells",lambda s:
            (s["electric"].get("bridges") or {}).get("21,15",{}).get("length")==7)
        assert plain["electric"]["bridges"]["21,15"]["type"]==0
        slot(4);rail_at(15)
        await_state("enclosed depot",lambda s:(s.get("track_nodes") or {}).get("15,15",{}).get("depot")==2)
        slot(2);hold_to_build(lambda x:native_aim(x,15,1.5),(16,),(20,))
        hold_to_build(lambda x:native_aim(x,15,1.5),(28,),(36,))
        await_state("linked plain approaches",lambda s:len(s.get("track_nodes") or {})==15)
        slot(3);rail_at(18);rail_at(19);rail_at(35);rail_at(36)
        await_state("two long platforms",lambda s:
            all((s.get("track_nodes") or {}).get(f"{x},15",{}).get("station") for x in (18,19,35,36)))
        slot(5);click()
        await_state("Rail Signals",lambda s:s.get("menu")=="railsignals")
        slot(6);click();click()
        slot(2);rail_at(17)
        await_state("near path signal facing west",lambda s:(s.get("rail_work") or {}).get("signals")==1)
        slot(8);click()
        await_state("Back to Railworks",lambda s:s.get("menu")=="railworks")
        phase="convert the whole bridge from one occupied-free portal"
        rail_engineering()
        slot(1);click()
        await_state("Rail Types",lambda s:s.get("menu")=="railtypes")
        cash_before=state()["cash"]
        slot(2);rail_at(21);rail_at(21)
        def wired(s):
            span=(s["electric"].get("bridges") or {}).get("21,15",{})
            return span.get("type")==1 and "rail_bridge_catenary" in span.get("level","")
        single=await_state("the center gained original bridge wire from one selection",wired)
        assert single["electric"]["bridges"]["21,15"]["deck"]==2 and cash_before-single["cash"]==476
        slot(3);rail_at(27);rail_at(27)
        unwired=await_state("a single opposite portal reverted the bridge",lambda s:
            (s["electric"].get("bridges") or {}).get("21,15",{}).get("type")==0)
        assert single["cash"]-unwired["cash"]==84
        slot(2);rail_at(15);rail_at(36)
        await_state("all powered approaches",lambda s:
            len(s.get("track_nodes") or {})==15 and
            all(v.get("railtype")==1 for v in s["track_nodes"].values()))
        native_aim(24,15,3.4,framing=True)
        screenshot("01-native-wired-Coastal-Circuit-bridge")
        phase="buy the stock SH 40 and drive the actual route through the span"
        slot(1);rail_at(15)
        choose("luanttd_core:rail_fleet","purchase_sh_40","02-buy-the-bridge-electric")
        choose("luanttd_core:rail_fleet","unit_1","03-order-the-bridge-electric")
        rail_at(35);rail_at(18);slot(8);click()
        native_aim(24,15,3.4,framing=True)
        def over(s):
            rail=s.get("electric") or {}
            c=rail.get("collector") or {}
            return rail.get("sprung") and 42.2<c.get("x",0)<54.8 and abs(c.get("z",0)-30.5)<1
        on=await_state("visible native roof collector on either ramp or across the deck",over,90)
        screenshot("04-native-collector-over-Coastal-Circuit")
        assert on["electric"]["traction"] and "bl_rail_sh_collector.obj" in on["electric"]["meshes"]
        stop_server(client_first=True)
        after=join("bridge-electric-restored")
        assert after["electric"]["sprung"] and after["electric"]["engine"]==24
        chat("/survey 24 15")
        after=await_state("far native deck emerges wired after reopening",wired)
        assert wired(after) and after["electric"]["sprung"] and after["electric"]["engine"]==24
        (out/"electric-bridge-native.json").write_text(json.dumps({"wire":single["electric"],
            "running":on["electric"],"reopened":after["electric"]},indent=2))
        stop_server(client_first=True)
        print(f"PASS: normal GUI wooden bridge construction, conversion from either end, sprung SH40 across the channel and SQLite: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_ELECTRIC_GUI")=="1":
        phase="build an owned flat railway in the default coastal test circuit start"
        market_year=int(os.environ.get("BAYLINE_NATIVE_ELECTRIC_YEAR","1970"))
        newer=os.environ.get("BAYLINE_NATIVE_SH_40_GUI")=="1"
        electric_engine,electric_model=(24,"sh_40") if newer else (23,"sh_30")
        assert fresh["electric"]["available"] and fresh["electric"]["year"]==market_year
        assert fresh["starter_map"]["name"]=="coastal test circuit"
        slot(8);click()
        await_state("native Railworks",lambda s:s.get("menu")=="railworks")
        chat("/survey 33 14")
        def rail_at(x): native_aim(x,14,.5);click()
        slot(4);rail_at(28)
        await_state("own the enclosed depot",lambda s:(s.get("track_nodes") or {}).get("28,14",{}).get("depot")==2)
        slot(2);hold_to_build(lambda x:native_aim(x,14,.5),(29,),(37,))
        await_state("own the flat ten-tile rail route",lambda s:len(s.get("track_nodes") or {})==10)
        slot(3);rail_at(31);rail_at(32);rail_at(36);rail_at(37)
        await_state("two complete owned platforms",lambda s:
            all((s.get("track_nodes") or {}).get(f"{x},14",{}).get("station") for x in (31,32,36,37)))
        slot(5);click()
        await_state("Rail Signals tools",lambda s:s.get("menu")=="railsignals")
        slot(6);click();click()
        slot(2);rail_at(30)
        await_state("one native path signal",lambda s:(s.get("rail_work") or {}).get("signals")==1)
        slot(8);click()
        await_state("Back to Railworks",lambda s:s.get("menu")=="railworks")
        phase="convert the whole corridor using ordinary Rail Types tools"
        rail_engineering()
        slot(1);click()
        await_state("Rail Types",lambda s:s.get("menu")=="railtypes")
        slot(2);rail_at(28);rail_at(37)
        wired=await_state("ten electrically typed pieces with original wire over two platforms",lambda s:
            sum(v.get("railtype")==1 for v in (s.get("track_nodes") or {}).values())==10 and
            (s.get("track_nodes") or {}).get("31,14",{}).get("wire")=="luanttd_core:rail_catenary_1_0")
        screenshot("01-native-electrified-corridor")
        phase=f"buy and dispatch the actual {electric_model} from the electrified depot"
        slot(1);rail_at(28)
        choose("luanttd_core:rail_fleet",f"purchase_{electric_model}","02-buy-the-electric")
        choose("luanttd_core:rail_fleet","unit_1","03-order-the-electric")
        rail_at(36);rail_at(31);slot(8);click()
        rolling=await_state(f"native {electric_model} and coach running on powered rails",lambda s:
            (s.get("electric") or {}).get("steps",0)>24 and
            f"bl_rail_{electric_model}.obj" in (s["electric"].get("meshes") or []),75)
        assert rolling["electric"]["traction"]
        screenshot("04-native-electric-under-wire")
        stop_server(client_first=True)
        restored=join("electric-restored")
        assert all(v["railtype"]==1 for v in restored["track_nodes"].values())
        assert restored["electric"]["engine"]==electric_engine and restored["electric"]["traction"]
        (out/"electric-native.json").write_text(json.dumps({"wire":wired["track_nodes"],"run":rolling["electric"],
            "reopened":restored["electric"]},indent=2))
        stop_server(client_first=True)
        print(f"PASS: ordinary hotbars, real electrified track and owned {electric_model} motion across SQLite: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_GENERATED_SCALE")=="1":
        phase="survey the far side of an actual 128×128 stock generated region"
        gen=fresh["generated"]
        assert gen["width"]==gen["depth"]==128 and len(gen["towns"])==8
        assert gen["scale"]["industry"]==13 and gen["scale"]["head"]==6090
        assert gen["scale"]["log_x"]==gen["scale"]["log_y"]==7
        chat("/survey 106 70")
        await_state("far eastern survey past the old 64×64 limit",lambda s:
            abs(s["camera"]["pos"]["x"]-212.5)<.1 and abs(s["camera"]["pos"]["z"]-132)<.1)
        time.sleep(.65);screenshot("01-128-stock-town-and-terrain")
        phase="build a paid road and bus stops past the old map boundary"
        slot(2);click()
        await_state("Roadworks from the normal menu",lambda s:s.get("menu")=="roads")
        def tile_aim(x):
            native_aim(x,70,gen["scale"]["heights"][str(x)]+.5)
        def tile_click(x):
            tile_aim(x);click()
        slot(2);hold_to_build(tile_aim,(102,),(111,))
        await_state("far road construction",lambda s:all(tile(s,(x,70))=="road" for x in range(102,112)))
        slot(3);click()
        await_state("ordinary Bus Stops",lambda s:s.get("menu")=="road_stops")
        slot(2);tile_click(103);tile_click(110)
        built=await_state("two actual bus stops on high tile IDs",lambda s:
            all(tile(s,(x,70))=="road_station" for x in (103,110)))
        assert built["cash"]==fresh["cash"]-2226
        slot(1);time.sleep(.4);screenshot("02-native-construction-on-wide-map")
        stop_server(client_first=True)
        loaded=join("128-region-restored")
        assert all(tile(loaded,(x,70))=="road_station" for x in (103,110))
        assert loaded["generated"]["width"]==128 and loaded["generated"]["scale"]["head"]==6090
        assert loaded["generated"]["scale"]["tick"]>=built["generated"]["scale"]["tick"]
        assert loaded["cash"]==built["cash"]
        (out/"generated-scale-native.json").write_text(json.dumps(
            {"map":{"width":128,"depth":128,"towns":gen["towns"],**gen["scale"]},
             "spent":fresh["cash"]-built["cash"],"restored":loaded["generated"]["scale"]},indent=2))
        stop_server(client_first=True)
        print(f"PASS: real 128×128 generated region, far paid native construction and SQLite reload: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_GENERATED_RIVER")=="1":
        phase="survey an actual TerraGenesis river"
        chat("/survey 25 20")
        flow=await_state("native mapgen river and slope meshes exposed",lambda s:
            (s.get("generated") or {}).get("river",{}).get("middle","").startswith("luanttd_core:stock_river_3") and
            s["generated"]["river"].get("flat","").startswith("luanttd_core:stock_river_flat"))["generated"]["river"]
        assert flow["stats"]["rivers"]==2 and flow["stats"]["terraform_committed"]==2 and flow["cursor"]==2899
        assert flow["typed"]=="river" and not flow.get("lock")
        time.sleep(.6);screenshot("01-stock-terragenesis-native-river")
        phase="place a real working lock on the generated incline"
        slot(10);click()
        await_state("Sea & Air from Home",lambda s:s.get("menu")=="portair")
        slot(2);click()
        await_state("ordinary Harbor Construction",lambda s:s.get("menu")=="harbor")
        slot(4);click()
        await_state("Waterworks tools",lambda s:s.get("menu")=="waterworks")
        slot(3)
        native_aim(25,20,2.0);click()
        made=await_state("a paid three-tile lock replaces only the incline mesh",lambda s:
            (s["generated"]["river"].get("lock") or {}).get("tiles")==3 and
            s["generated"]["river"].get("middle","").startswith("luanttd_core:ship_lock_middle_"))
        assert made["cash"]==fresh["cash"]-17500
        assert made["generated"]["river"]["typed"]=="river"
        slot(1);time.sleep(.35)
        screenshot("02-lock-on-generated-river")
        stop_server()
        resumed=join("river-restored")
        assert resumed["cash"]==made["cash"]
        assert resumed["generated"]["river"]["lock"]==made["generated"]["river"]["lock"]
        (out/"generated-river-native.json").write_text(json.dumps(
            {"before":flow,"built":made["generated"]["river"],"after":resumed["generated"]["river"],
             "cost":fresh["cash"]-made["cash"]},indent=2))
        stop_server()
        print(f"PASS: stock-generated TerraGenesis river, actual paid lock and native SQLite restore: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_GENERATED_WORLD")=="1":
        phase="inspect an actual 64×64 native campaign with source-generated settlements"
        gen=await_state("visible modeled houses on the generated map",lambda s:
            (s.get("generated") or {}).get("visible_house",0)>5 and len(s["generated"].get("towns") or [])>=2)
        gen=gen["generated"]
        assert gen["width"]==gen["depth"]==64 and gen["style"]=="terragenesis-14.1" and gen["void"]==252
        assert gen["road"]>20 and gen["house"]>10
        assert gen["forest_tiles"]>100 and gen["forest_stems"]>gen["forest_tiles"] and gen["forest_shore"]>0
        city=gen["towns"][0]
        if os.environ.get("BAYLINE_NATIVE_GENERATED_DEFAULT")=="1":
            phase="start above a generated town without any map setting or teleport"
            camera=fresh["camera"]["pos"]
            assert abs(camera["x"]-(2*city["x"]+.5))<.5
            assert abs(camera["z"]-(2*city["z"]-7))<.5
            assert abs(camera["y"]-(city["h"]+15))<.5
            assert fresh.get("starter_map") is None
            assert all(fresh["stock_workbenches"].get(k) for k in
                       ("bridges","rail","rail_owned","rail_goods","rail_coal","rail_spans","crossings",
                        "ship","air","tram","freight","oneway","bays","mail","paid_air","paid_ship","paid_rail"))
            assert gen["mixed"] and gen["timber_ready"]
            assert {(q["kind"],q["x"],q["z"]) for q in gen["industries"]}=={
                ("coal_mine",47,41),("power_station",30,28),("sawmill",23,42),("forest",48,44)}
            screenshot("00-no-config-generated-spawn")
        chat(f"/survey {int(city['x'])} {int(city['z'])}")
        await_state("actual native trees loaded in the visible town region",lambda s:s["generated"]["visible_tree"]>25)
        screenshot("01-source-town-with-real-homes-and-streets")
        phase="build a roadside stop on an actual generated public street"
        stop=gen["stop"]
        slot(2);click()
        await_state("ordinary Roadworks",lambda s:s.get("menu")=="roads")
        slot(3);click()
        await_state("Bus Stops",lambda s:s.get("menu")=="road_stops")
        slot(2)
        x,z=int(stop["x"]),int(stop["z"])
        native_aim(x,z,stop["h"]+.5);click()
        built=await_state("paid stop on the generated street",lambda s:tile(s,(x,z))=="road_station")
        screenshot("02-stock-bus-stop-on-generated-street")
        mixed=gen.get("mixed")
        cargo="wood" if mixed else "coal"
        phase=f"inspect generated {cargo} freight in real Luanti"
        assert gen["freight_ready"] and len(gen["industries"])==(4 if mixed else 3)
        if mixed: assert gen["timber_ready"]
        origin=(23,42) if mixed else (24,43)
        chat(f"/survey {origin[0]} {origin[1]}")
        await_state("camera actually reached the production area",lambda s:
            abs(s["camera"]["pos"]["x"]-(origin[0]*2+.5))<.1 and abs(s["camera"]["pos"]["z"]-(origin[1]*2-8))<.1)
        await_state("native generated stock industry scenery",lambda s:s["generated"]["visible_industry"]>=6)
        time.sleep(.5)
        screenshot("03-stock-generated-sawmill" if mixed else "03-stock-generated-coal-mine")
        delivery=None
        if os.environ.get("BAYLINE_NATIVE_GENERATED_FREIGHT")=="1":
            phase=f"build the generated {cargo} route through ordinary hotbar tools"
            chat("/tools")
            slot(2);click()
            await_state("Road Construction",lambda s:s.get("menu")=="roads")
            slot(5);click()
            await_state("Freight Roadworks hotbar",lambda s:s.get("menu")=="freight")
            def field(pt):
                q,r=pt
                chat(f"/survey {q} {r}")
                native_aim(q,r,gen["route_heights"][f"{q},{r}"]+.5)
                click()
            slot(2)
            lines=([
                ((25,44),(47,44)),((25,44),(25,45)),((25,45),(30,45)),((30,45),(30,44)),
                ((47,44),(47,46)),((47,46),(46,46)),((46,46),(46,44))
            ] if mixed else [
                ((29,26),(29,45)),((29,26),(28,26)),((28,26),(28,30)),((28,30),(29,30)),
                ((29,45),(28,45)),((28,45),(28,41)),((28,41),(29,41))
            ])
            def terrain_aim(x,z):
                native_aim(x,z,gen["route_heights"][f"{x},{z}"]+.5,framing=True)
                await_state(f"ground hit at {x},{z}",lambda s:s["target"]==f"{x},{z}")
            for a,b in lines:
                mid=((a[0]+b[0])//2,(a[1]+b[1])//2)
                chat(f"/survey {mid[0]} {mid[1]}")
                await_state("survey camera settled",lambda s:
                    abs(s["camera"]["pos"]["x"]-(2*mid[0]+.5))<.1 and
                    abs(s["camera"]["pos"]["z"]-(2*mid[1]-8))<.1)
                terrain_aim(*a);xdo("mousedown",1)
                try:
                    anchor=(a[1]-1)*gen["width"]+a[0]
                    await_state("holding the correct AutoRoad tile",lambda s:s.get("road_gesture")==anchor)
                    terrain_aim(*b)
                finally:
                    xdo("mouseup",1)
                await_state(f"real road at {b}",lambda s:tile(s,b)=="road" and not s.get("road_gesture"))
                time.sleep(.24)
            load,unload,depot=((45,44),(26,44),(32,43)) if mixed else ((29,43),(29,28),(30,35))
            slot(3);field(load);field(unload)
            await_state("actual generated industry stops",lambda s:all(tile(s,pt)=="road_station" for pt in (load,unload)))
            slot(4);field(depot)
            await_state("actual generated route depot",lambda s:tile(s,depot)=="road_depot")
            phase="purchase, order, and earn real freight income on the generated world"
            slot(1);field(depot)
            choose("luanttd_core:service","depot_buy_wood" if mixed else "depot_buy_coal",f"Buy the {cargo} truck")
            await_state("stock freight truck in the player fleet",
                lambda s:s.get("engine")==("wood_truck" if mixed else "coal_tipper"))
            choose("luanttd_core:service","service_pick","Add stops")
            field(load);field(unload);click(3)
            await_state("two orders for generated freight",lambda s:len(s.get("orders") or [])==2)
            choose("luanttd_core:service","service_cycle_load","First stop: full load")
            choose("luanttd_core:service","service_toggle",f"Start the loaded {cargo} truck")
            delivery=await_state("cash and receipts for 20 tons at the generated stock industry",lambda s:
                s["generated"][cargo+"_received"]>=20 and s.get("revenue",0)>0,110)
            chat(f"/survey {unload[0]} {unload[1]}")
            time.sleep(.5)
            screenshot(f"04-stock-generated-{cargo}-delivery")
        stop_server()
        resumed=join("generated-world-restored")
        assert resumed["generated"]["towns"][0]["name"]==city["name"] and tile(resumed,(x,z))=="road_station"
        assert resumed["generated"]["industries"]==gen["industries"]
        assert resumed["generated"].get("mixed")==gen.get("mixed")
        assert resumed["generated"]["forest_stems"]==(delivery["generated"] if delivery else gen)["forest_stems"]
        if delivery:
            assert resumed["generated"][cargo+"_received"]>=delivery["generated"][cargo+"_received"]
        if gen.get("landmarks"):
            phase="inspect a protected stock lighthouse on the generated coast"
            assert len(gen["landmarks"])==2 and all(q["kind"]=="lighthouse" for q in gen["landmarks"])
            spot=gen["landmarks"][0]
            q,r=int(spot["x"]),int(spot["z"])
            chat("/survey "+f"{q} {r}")
            await_state("native anchor of a generated lighthouse",lambda s:
                any(o["x"]==q and o["z"]==r and o["visible"] for o in s["generated"]["landmarks"]))
            native_aim(q,r,spot["h"]+1.2,framing=True)
            time.sleep(.5)
            screenshot("05-stock-generated-lighthouse")
        (out/"generated-world-native.json").write_text(json.dumps({"generated":gen,"stop":built["builds"][f"{x},{z}"],
            cargo:delivery and {"received":delivery["generated"][cargo+"_received"],"revenue":delivery.get("revenue")}},indent=2))
        stop_server()
        print(f"PASS: real generated 64×64 region and towns, paid bus-stop construction, native SQLite restore: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_ROAD_BEND")=="1":
        phase="hold the actual AutoRoad tool across both axes"
        assert fresh["starter_map"]["name"]=="coastal test circuit"
        slot(2);click();await_state("Roadworks",lambda s:s.get("menu")=="roads")
        fixture=await_state("the dry, level test plaza",lambda s:s.get("road_bend",{}).get("link")==0)
        a,b=([int(v) for v in fixture["road_bend"][k]] for k in ["a","b"])
        chat(f"/survey {a[0]+2} {a[1]+1}");time.sleep(.85)
        slot(2);native_aim(*a,1.5)
        before=state()
        xdo("mousedown",1)
        await_state("road drag started",lambda s:s["road_bend"]["anchor"])
        native_aim(*b,1.5)
        straight=await_state("the normal drag remains stock",lambda s:
            "AutoRoad" in (s["road_bend"].get("hint") or ""))
        assert straight["cash"]==before["cash"] and straight["road_bend"]["link"]==0
        xdo("keydown","e")
        quote=await_state("E displays one priced two-leg preview",lambda s:
            "Road bend" in (s["road_bend"].get("hint") or "") and s["road_bend"]["valid"])
        assert quote["road_bend"]["link"]==0 and quote["cash"]==before["cash"]
        screenshot("01-priced-bend-before-release")
        xdo("mouseup",1)
        built=await_state("both approaches meet through the real rendered elbow",lambda s:
            s["road_bend"]["link"]==7 and s["road_bend"]["elbow"].startswith("luanttd_core:road_12_"))
        xdo("keyup","e");time.sleep(1.2)
        assert built["road_bend"]["masks"][4]==12 and built["road_bend"]["stock"]==0
        assert before["cash"]-built["cash"]==876 and not built["road_bend"]["anchor"]
        screenshot("02-connected-road-bend")
        phase="direct tile teleport from the compact Roadworks tools"
        slot(11)
        await_state("the shared teleport tool is selected",lambda s:
            s["wield_item"]=="luanttd_core:menu_teleport_tile")
        native_aim(*b,1.5)
        angle=state()["camera"]
        click()
        moved=await_state("the player jumped to the exact tile center without opening a map",lambda s:
            abs(s["camera"]["pos"]["x"]-(b[0]*2+.5))<.1 and
            abs(s["camera"]["pos"]["z"]-(b[1]*2+.5))<.1 and
            9<=s["camera"]["pos"]["y"]<=10 and not s.get("form"))
        assert moved["cash"]==built["cash"] and moved["road_bend"]["masks"]==built["road_bend"]["masks"]
        assert abs(angle_delta(moved["camera"]["yaw"],angle["yaw"]))<.008
        assert abs(moved["camera"]["pitch"]-angle["pitch"])<.008
        assert moved["hotbar_layout"][:3]==[8,9,11]
        screenshot("03-teleport-above-selected-road-tile")
        slot(8);click();await_state("Back returns to Home",lambda s:s.get("menu")=="home")
        slot(5);click()
        nav=await_state("Navigation uses a shorter dense bar",lambda s:s.get("menu")=="navigation")
        assert len(nav["hotbar_layout"])==4 and nav["hotbar_layout"][:2]==[8,11]
        screenshot("04-compact-navigation-hotbar")
        (out/"autoroad-bend-native.json").write_text(json.dumps(
            {"before":before["road_bend"],"stock_preview":straight["road_bend"]["hint"],
             "bend_preview":quote["road_bend"]["hint"],"after":built["road_bend"],"spent":before["cash"]-built["cash"],
             "teleport":moved["camera"],"road_slots":moved["hotbar_layout"],"navigation_slots":nav["hotbar_layout"]},indent=2))
        stop_server(client_first=True)
        print(f"PASS: physical E + AutoRoad lays both priced and connected legs: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_AUTORAIL")=="1":
        phase="open Railworks directly and preview the original six-piece selection"
        assert (fresh["starter_map"] or {}).get("name")=="coastal test circuit"
        slot(8);click()
        await_state("direct Railworks",lambda s:s.get("menu")=="railworks")
        chat("/survey 32 16");time.sleep(.75)
        slot(2);native_aim(30,15);xdo("mousedown",1);time.sleep(.3)
        native_aim(33,18)
        def rail_ghost(s,count):
            return len((s.get("starter") or {}).get("ghost") or [])==count
        preview=await_state("seven native ghost pieces on an actual stock diagonal",lambda s:rail_ghost(s,7))
        before=preview["cash"]
        assert not preview["track_nodes"]
        screenshot("01-autorail-priced-diagonal-preview")
        click(3)
        canceled=await_state("right-click cancels without building",lambda s:rail_ghost(s,1))
        assert not canceled["track_nodes"] and canceled["cash"]==before
        xdo("mouseup",1);time.sleep(.3)
        assert not state()["track_nodes"] and state()["cash"]==before
        native_aim(30,15);xdo("mousedown",1);time.sleep(.3);native_aim(33,18)
        await_state("diagonal comes back on next selection",lambda s:rail_ghost(s,7))
        xdo("mouseup",1)
        done=await_state("exact alternating pieces really built",lambda s:len(s.get("track_nodes") or {})==7)
        masks=done["track_nodes"]
        assert {m["mask"] for m in masks.values()}=={16,32},masks
        assert masks["30,15"]["mask"]==masks["33,18"]["mask"]
        west=[(30,15),(30,16),(31,16),(31,17),(32,17),(32,18),(33,18)]
        east=[(30,15),(31,15),(31,16),(32,16),(32,17),(33,17),(33,18)]
        assert set(masks)=={f"{x},{z}" for x,z in west} or set(masks)=={f"{x},{z}" for x,z in east}
        assert done["cash"]<before
        screenshot("02-autorail-stock-diagonal-built")
        phase="second placement follows a straight without another submenu"
        native_aim(28,14);xdo("mousedown",1);time.sleep(.3);native_aim(36,14)
        await_state("nine stock straight ghost pieces",lambda s:rail_ghost(s,9))
        slot(1);time.sleep(.35);slot(2);xdo("mouseup",1);time.sleep(.35)
        assert state()["track_nodes"]==masks and state()["cash"]==done["cash"]
        hold_to_build(native_aim,(28,14),(36,14))
        second=await_state("nine actual straight rail tiles",lambda s:len(s.get("track_nodes") or {})==16)
        assert all(second["track_nodes"][f"{x},14"]["mask"]==1 for x in range(28,37))
        phase="click to lay one piece at the cursor without an anchor"
        native_aim(37,14);click()
        single=await_state("a single-tile click builds only one piece",lambda s:len(s.get("track_nodes") or {})==17)
        piece=single["track_nodes"]["37,14"]
        assert piece["mask"] in (1,2,4,8,16,32),piece
        phase="drag toward a real river obstruction"
        chat("/survey 24 15");time.sleep(.8)
        native_aim(20,15);xdo("mousedown",1);time.sleep(.3);native_aim(28,15)
        blocked=await_state("real ghost draws just the payable prefix before water",lambda s:
            2<=len((s.get("starter") or {}).get("ghost") or [])<9)
        assert len(blocked["track_nodes"])==17
        screenshot("03-autorail-stops-at-water-preview")
        xdo("mouseup",1)
        prefix=await_state("the prefix is constructed without placing the far bank tile",lambda s:
            (s.get("track_nodes") or {}).get("21,15"))
        assert "20,15" in prefix["track_nodes"] and "28,15" not in prefix["track_nodes"]
        assert len(prefix["track_nodes"])-17==len(blocked["starter"]["ghost"])
        phase="manual pieces remain accessible and Back follows the active hierarchy"
        rail_engineering()
        slot(7);click()
        await_state("manual stock pieces",lambda s:s.get("menu")=="railpieces")
        screenshot("04-manual-six-stock-pieces")
        for menu in ("railengineering","railops","railworks","home"):
            slot(8);click();await_state(menu,lambda s:s.get("menu")==menu)
        (out/"autorail-native.json").write_text(json.dumps({"diagonal":masks,"straight":second["track_nodes"],
          "ghost_pieces":preview["starter"]["ghost"], "cost":before-done["cash"],
          "single_piece":piece, "obstructed_prefix":blocked["starter"]["ghost"], "no_build_before_release":True, "right_click_and_slot_change_cancel":True},indent=2))
        stop_server()
        print(f"PASS: direct AutoRail, genuine 3D snapped ghost, clean cancel, stock diagonal and straight construction, manual pieces and Back: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_COASTAL_CIRCUIT")=="1":
        phase="start the explicit coastal test circuit scenario with no feature overrides"
        cfg=(out/"server.conf").read_text()
        overrides=[line for line in cfg.splitlines() if line.startswith("bayline_") and
                   not line.startswith("bayline_seconds_per_day =") and line!="luanttd_qa_coastal_layout = true"]
        assert overrides==[], overrides
        profile=await_state("coastal test circuit map with every compatible workbench available",lambda s:
            (s.get("starter_map") or {}).get("name")=="coastal test circuit" and
            all((s.get("stock_workbenches") or {}).get(k) for k in
                ("bridges","rail","rail_owned","rail_spans","crossings","rail_coal","ship","air","tram","freight",
                 "oneway","bays","mail","paid_air","paid_ship","paid_rail")) and
            len((s["stock_workbenches"].get("ordinary") or {}))==9 and
            all(s["stock_workbenches"]["ordinary"].values()))
        assert profile["starter_map"]["peak"]>=5 and profile["starter_map"]["shore"]>=60
        screenshot("00-coastal-circuit-new-campaign")
        phase="use the native workbenches index, not a config file, to examine the available systems"
        slot(6);click()
        await_state("Controls hotbar",lambda s:s.get("menu")=="options")
        slot(2);click()
        choose("luanttd_core:workbenches","wb_tab_scenarios","01-workbenches-and-scenarios")
        screenshot("02-native-world-scenarios")
        choose("luanttd_core:workbenches","wb_back","03-return-from-scenarios")
        slot(8);click()
        await_state("Home with a direct Railworks entry",lambda s:s.get("menu")=="home")
        phase="build the actual paid timber bridge from the Road Construction toolbar"
        slot(2);click()
        await_state("Road Construction mounted automatically",lambda s:s.get("menu")=="roads")
        chat("/survey 24 13");time.sleep(.75)
        slot(10)
        if state()["wield_item"]=="luanttd_core:menu_road_bridge_picker":
            cash=state()["cash"]
            aim(21,13);click();aim(27,13);click()
            await_state("span selected before style, with no purchase",
                        lambda s:s.get("form")=="luanttd_core:bridge_picker" and cash-s["cash"]<2447
                        and not s["starter"].get("bridge"))
            choose_bridge_type()
        else:
            # Older fixtures can explicitly exercise a world without a picker.
            click()
            await_state("legacy road bridge styles",lambda s:s.get("menu")=="structures")
            slot(2);aim(21,13);click();aim(27,13);click()
            slot(8);click()
            await_state("Back to Road Construction",lambda s:s.get("menu")=="roads")
        bridge_state=await_state("the new timber bridge is actually built and paid",lambda s:(s["starter"] or {}).get("bridge"))
        assert bridge_state["starter"]["bridge"]["cost"]>0 and bridge_state["starter"]["bridge"]["span"]==7
        screenshot("04-timber-bridge-crosses-new-valley")
        phase="demolish the paid road bridge without leaving Rail Construction"
        slot(8);click()
        await_state("Back returns to Home",lambda s:s.get("menu")=="home")
        slot(8);click()
        await_state("Rail Construction mounted automatically",lambda s:s.get("menu")=="railworks")
        slot(9)
        assert state()["wield_item"]=="luanttd_core:menu_clear"
        aim(21,13);click()
        await_state("paired bridge removal cleared the bridge and only its heads",
                    lambda s:not (s.get("starter") or {}).get("bridge"))
        screenshot("04a-bulldoze-from-rail-toolbar")
        phase="build a rail depot and buy an original train"
        chat("/survey 30 14");time.sleep(.65)
        slot(4);aim(28,14);click()
        await_state("actual stock rail depot placed",lambda s:
            (s.get("track_nodes") or {}).get("28,14",{}).get("depot") is not None)
        slot(1);aim(28,14);click()
        await_state("sawmill-coach Goods Van offer on the real default depot panel",lambda s:
            s.get("form")=="luanttd_core:rail_fleet" and "purchase_goods" in (s.get("buttons") or {}))
        choose("luanttd_core:rail_fleet","purchase","05-buy-an-original-kirby-from-new-map")
        bought=await_state("stock Kirby and passenger carriage persisted",lambda s:bool((s["starter"] or {}).get("units")))
        assert bought["starter"]["units"][0]["stock_ids"]==[0,27] and bought["starter"]["units"][0]["price"]==12866
        (out/"coastal-circuit-native.json").write_text(json.dumps(dict(
            defaults=profile["stock_workbenches"],map=profile["starter_map"],
            bridge=bridge_state["starter"]["bridge"],purchased=bought["starter"]["units"][0]),indent=2))
        stop_server()
        print(f"PASS: default coastal test circuit, in-game scenario index, paid timber bridge and stock train purchase, zero configuration overrides: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_COAST")=="1":
        phase="dig a real dry inland trench with the native stock Lower area tool"
        chat("/qa_coast trench");time.sleep(.65)
        slot(7);click()
        await_state("Landscaping",lambda s:s.get("menu")=="terrain")
        slot(6);aim(8,17);click();aim(10,19);click()
        await_state("the game lowered the whole inland trench to sea level",lambda s:
            s["coast"]["trench"]["base"]==0 and s["coast"]["trench"]["top"]==0 and not s["coast"]["trench"]["water"])
        screenshot("01-dry-inland-trench")
        phase="level a bay from sea level into shore with the ordinary hotbar"
        chat("/qa_coast bay");time.sleep(.65)
        slot(4);aim(11,33);click();aim(13,28);click()
        before=await_state("a real sea-level cut before any tile-loop floods it",lambda s:
            s["coast"]["bay"]["base"]==0 and s["coast"]["bay"]["top"]==0 and not s["coast"]["bay"]["water"])["coast"]
        assert before["day"]==0
        screenshot("02-bay-cut-before-flood")
        chat("/qa_coast go")
        after=await_state("the connected cut fills, the separated trench stays dry",lambda s:
            s["coast"]["bay"]["water"] and s["coast"]["day"]>=12 and not s["coast"]["trench"]["water"],40)["coast"]
        chat("/qa_coast beach");time.sleep(.8);screenshot("03-new-bay-connected-to-sea")
        stop_server()
        after_save=join("coast-restored")["coast"]
        assert after_save["bay"]["water"] and not after_save["trench"]["water"]
        (out/"native-coast.json").write_text(json.dumps(dict(before=before,after=after,reloaded=after_save),indent=2))
        stop_server()
        print(f"PASS: stock native area tools cut a bay, let the sea flood it, keep a separate trench dry and reload: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_ALL_WORKBENCHES")=="1":
        phase="one setting opens the native workbenches without the developer sandbox"
        modes=await_state("all live workbenches are mounted",lambda s:
            len(s.get("stock_workbenches") or {})==16 and all(s["stock_workbenches"].values()))["stock_workbenches"]
        for chain in (
            ((2,"roads"),(7,"road_direction"),(4,"tramway")),
            ((8,"railworks"),(7,"railops"),(1,"railengineering"),(7,"railpieces")),
            ((2,"roads"),(3,"road_stops")),
            ((2,"roads"),(7,"road_direction")),
            ((10,"portair"),(2,"harbor"),(4,"waterworks")),
            ((10,"portair"),(3,"airfields")),
            ((8,"railworks"),(7,"railops"),(1,"railengineering")),
            ((8,"railworks"),(7,"railops"),(5,"railfreight")),
            ((2,"roads"),(5,"freight")),
            ((5,"navigation"),),
        ):
            for digit,menu in chain:
                slot(digit);click()
                await_state(menu,lambda s:s.get("menu")==menu)
            parents=["home"]+[menu for _,menu in chain[:-1]]
            for menu in reversed(parents):
                slot(8);click()
                await_state(menu,lambda s:s.get("menu")==menu)
        (out/"stock-workbench-menu.json").write_text(json.dumps(modes,indent=2))
        if os.environ.get("BAYLINE_NATIVE_ROAD_BAY")!="1":
            stop_server()
            print("PASS: native one-setting stock workbenches, all sections and Back.")
            sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_ROAD_BAY")=="1":
        phase="mouse-build a two-bay passenger terminal and three scheduled bus routes"
        implicit_bay=os.environ.get("BAYLINE_NATIVE_ROAD_BAY_DEFAULT")=="1"
        if implicit_bay:
            config=(out/"server.conf").read_text()
            assert "bayline_road_bay_preview" not in config
            assert "bayline_stock_workbenches" not in config
            assert "bayline_preview_stock_road_loading" not in config
        A,B,D=(11,12),(17,12),(12,13)
        slot(2);click()
        await_state("Roadworks",lambda s:s.get("menu")=="roads")
        slot(2);hold_to_build(native_aim,A,B)
        await_state("road from town to town",lambda s:all(tile(s,(x,12))=="road" for x in range(11,18)))
        slot(3);click()
        await_state("Bus Stops menu",lambda s:s.get("menu")=="road_stops")
        slot(3)
        for target in (A,B):
            aim(*target);click()
            await_state("own stock bay terminus",lambda s:tile(s,target)=="road_station")
        slot(8);click()
        await_state("roadworks after Return",lambda s:s.get("menu")=="roads")
        slot(4);aim(*D);click()
        await_state("depot",lambda s:tile(s,D)=="road_depot")
        for i in range(1,4):
            slot(1);aim(*D);click()
            choose("luanttd_core:service","depot_buy",f"buy-bay-bus-{i}")
            if os.environ.get("BAYLINE_NATIVE_ORDER_MODAL")=="1":
                from bus_order_modal_native import exercise
                exercise(globals(),A,B,D)
                sys.exit(0)
            choose("luanttd_core:service","service_pick",f"two-bay-orders-{i}")
            await_state("world selects orders",lambda s:not s.get("form"))
            for target in (A,B):
                aim(*target);click()
            click(3)
            choose("luanttd_core:service","service_cycle_load",f"full-load-bay-bus-{i}")
            await_state("stock full-load order edited",lambda s:
                s["bus_bay"]["fleet"].get(str(i),{}).get("first_order")=="full")
            choose("luanttd_core:service","service_back",f"leave-bay-bus-{i}")
            await_state("back to depot",lambda s:not s.get("form"))
        slot(8);click()
        await_state("home from roadworks",lambda s:s.get("menu")=="home")
        slot(3);click()
        await_state("Fleet",lambda s:s.get("menu")=="fleet")
        for i in range(1,4):
            slot(3);click()
            choose("luanttd_core:service",f"vehicle_{i}",f"fleet-bay-bus-{i}")
            choose("luanttd_core:service","service_toggle",f"start-bay-bus-{i}")
            await_state("vehicle running",lambda s:not s.get("form"))
        def both_parked(s):
            bay=s["bus_bay"];f=bay["fleet"];a=bay.get("status") or {}
            c=[f.get(str(i),{}).get("claim") or {} for i in (1,2)]
            return (a.get("first") and a.get("second") and not a.get("entrance")
              and all(x.get("tile")==bay["id"] and x.get("phase")=="parked" and x.get("bay")==i
                      for i,x in enumerate(c))
              and f.get("3",{}).get("wait")=="bay" and len(bay.get("meshes",[]))==2)
        native_aim(*A,.59,framing=True)
        phase="two actual bus models park concurrently while a third queues outside"
        before=await_state("both stock models parked",both_parked,45)["bus_bay"]
        m,n=before["meshes"]
        assert abs(math.dist((m["x"],m["z"]),(n["x"],n["z"]))-.5)<.018,before
        assert before["node"]=="luanttd_core:road_bus_bay_pair_2",before
        assert before["fleet"]["3"]["position"]!=before["id"],before
        chat("/qa_bay_photo");time.sleep(.5)
        screenshot("01f-mouse-built-stock-bay-pair")
        stop_server()
        cfg=out/"server.conf"
        cfg.write_text("\n".join(line for line in cfg.read_text().splitlines()
                                 if not line.startswith("bayline_road_bay_preview ="))
                       +"\nbayline_road_bay_preview = false\n")
        reload=join("road-bay-reloaded")
        chat("/qa_bay_photo")
        recovered=await_state("both physical claims recovered",both_parked,15)["bus_bay"]
        assert recovered["fleet"]["1"]["arrived"]==before["fleet"]["1"]["arrived"]
        assert recovered["fleet"]["2"]["arrived"]==before["fleet"]["2"]["arrived"]
        phase="third real bus enters and passenger fare posts after the shared exit opens"
        final=await_state("third bus enters after one bay clears",lambda s:
            s["bus_bay"]["fleet"]["3"].get("arrived",0)>before["fleet"]["2"]["arrived"]
            and s["paid_units"]>0,75)
        screenshot("02f-stock-bay-queue-released")
        (out/"road-bay-desktop.json").write_text(json.dumps({"default_menu_without_settings":implicit_bay,"before":before,"reload":recovered,
          "after":final["bus_bay"],"paid_units":final["paid_units"],"revenue":final["revenue"]},indent=2))
        stop_server()
        print(f"PASS: Mouse-built two stock bays, two visible parked buses, third waits across SQLite reload then enters; {final['paid_units']} paid riders.")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_JUNCTION_CLEARANCE")=="1":
        phase="buy and order two stock buses through a real three-arm merge"
        chat("/qa_junction prepare")
        await_state("visible T-junction and two actual road depots",lambda s:
            (s.get("guarded_junction") or {}).get("ready"))
        slot(2);click()
        await_state("Roadworks",lambda s:s.get("menu")=="roads")
        for index,(depot,origin) in enumerate((((9,13),(8,12)),((16,16),(15,20))),1):
            slot(1);aim(*depot);click()
            choose("luanttd_core:service","depot_buy",f"buy-merge-bus-{index}")
            choose("luanttd_core:service","service_pick",f"order-merge-bus-{index}")
            aim(23,12);click();aim(*origin);click();click(3)
            choose("luanttd_core:service","service_back",f"return-merge-bus-{index}")
        slot(8);click();slot(3);click()
        await_state("Fleet",lambda s:s.get("menu")=="fleet")
        for index in (1,2):
            slot(3);click()
            choose("luanttd_core:service",f"vehicle_{index}",f"choose-merge-bus-{index}")
            choose("luanttd_core:service","service_toggle",f"dispatch-merge-bus-{index}")
            await_state("back in the world",lambda s:not s.get("form"))
            if index==1:
                chat("/qa_junction one")
                await_state("advance exactly one shared stock day",lambda s:s["guarded_junction"].get("one")==1)
        chat("/qa_junction go")
        phase="models separated at the actual shared merge"
        first=await_state("a real movement attempt yielded in the 3D junction",lambda s:
            (s.get("guarded_junction") or {}).get("hold"),90)["guarded_junction"]
        a,b=first["hold"]["positions"]
        assert math.dist((a["x"],a["z"]),(b["x"],b["z"]))>.72
        chat("/qa_junction photo");time.sleep(.6);screenshot("01w-native-junction-physical-clearance")
        stop_server()
        restored=join("junction-clearance-restarted")["guarded_junction"]
        assert restored["hold"]==first["hold"] and restored["enabled"] and first["enabled"]
        chat("/qa_junction go")
        phase="both real buses proceed after restoring their physical approach state"
        end=await_state("both actual buses subsequently arrived",lambda s:
            all((s["guarded_junction"]["drivers"].get(str(i)) or {}).get("arrival") for i in (1,2)),125)["guarded_junction"]
        (out/"junction-clearance-desktop.json").write_text(json.dumps({"first":first,"restored":restored,"after":end},indent=2))
        stop_server()
        print("PASS: native two-bus T-junction clearance, actual models separated, both complete after SQLite restart.")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_RAIL_BLOCK")=="1":
        phase="mouse-build two independent stock rail lines and their conventional interlocking"
        chat("/survey 39 7")
        slot(8);click();await_state("Railworks",lambda s:s.get("menu")=="railworks")
        slot(2);hold_to_build(aim,(34,7),(46,7))
        hold_to_build(aim,(39,3),(39,14))
        slot(4);aim(33,7);click()
        await_state("east-facing real depot",lambda s:(s.get("rail_work") or {}).get("depot")==1)
        slot(3);aim(44,7);click();aim(46,7);click()
        slot(5);click();await_state("rail signals menu",lambda s:s.get("menu")=="railsignals")
        slot(4)
        for p in ((37,7),(41,7)):
            aim(*p);click()
        slot(8);click();await_state("back to Railworks",lambda s:s.get("menu")=="railworks")
        rotate_rail_fitting(3)
        slot(4);aim(39,2);click()
        await_state("south-facing real depot",lambda s:(s.get("rail_work") or {}).get("depot")==2)
        slot(3);aim(39,12);click();aim(39,14);click()
        slot(5);click();await_state("rail signals menu",lambda s:s.get("menu")=="railsignals")
        slot(4)
        for p in ((39,6),(39,9)):
            aim(*p);click()
        ready=await_state("native rails form a diamond with four true block signal heads",lambda s:
            (s.get("block_rail") or {}).get("diamond")==3 and
            len(s["block_rail"].get("aspects") or {})==4)["block_rail"]
        assert all(x=="green" for x in ready["aspects"].values()),ready
        slot(7)
        for depot,platform in (((33,7),(44,7)),((39,2),(39,12))):
            aim(*depot);click();aim(*platform);click()
        await_state("two real empty consists ordered through the native block layout",lambda s:
            s["block_rail"]["ready"]==2)
        chat("/qa_block_rail go")
        phase="a red approach persists while only the other train's wagon occupies the diamond"
        hold=await_state("the tail actually blocks the approach",lambda s:
            (s["block_rail"].get("hold") or {}).get("tick"))["block_rail"]
        assert hold["no_reservations"] and hold["hold"]["parts"][1]["phase"]=="waiting"
        assert hold["hold"]["aspects"]["39,6"]=="red"
        chat("/qa_block_rail photo");time.sleep(.9);screenshot("01ac-native-block-holds-trailing-wagon")
        stop_server()
        restored=join("conventional-block-wagon-reloaded")["block_rail"]
        assert restored["hold"]==hold["hold"] and restored["parts"]==hold["hold"]["parts"]
        assert restored["aspects"]["39,6"]=="red" and restored["no_reservations"]
        chat("/qa_block_rail go")
        phase="watch the block release only after the last wagon leaves its protection"
        final=await_state("both true consists arrive with no route reservations",lambda s:
            all(p["phase"]=="arrived" for p in s["block_rail"].get("parts") or []) and
            len(s["block_rail"].get("parts") or [])==2,80)["block_rail"]
        assert final["no_reservations"] and not final.get("failure")
        did=lambda p:(p[1]-1)*48+p[0]
        ev=final["events"]
        tail_cross=next(e["tick"] for e in ev if e["kind"]=="tail_left" and e["train"]==1 and e["tile"]==did((39,7)))
        tail_protect=next(e["tick"] for e in ev if e["kind"]=="tail_left" and e["train"]==1 and e["tile"]==did((41,7)))
        north_green=next(e["tick"] for e in ev if e["kind"]=="block_aspect" and e["tile"]==did((39,6))
                         and e["green"] and e["tick"]>=tail_cross)
        assert hold["hold"]["tick"]<tail_cross<tail_protect==north_green,(tail_cross,tail_protect,north_green)
        screenshot("02ac-native-block-cleared")
        (out/"rail-block-desktop.json").write_text(json.dumps(dict(placed=ready,hold=hold,reopened=restored,
            after=final,tail_cross=tail_cross,tail_protect=tail_protect,north_green=north_green),indent=2))
        stop_server()
        print(f"PASS: native mouse-built conventional block interlocking holds the last wagon across SQLite and clears at its real boundary: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_OIL")=="1":
        phase="survey five modeled wells and exact real refinery receiving blocks"
        chat("/qa_oil wells")
        start_oil=await_state("native oil wells and refinery, with stock footprint hole",lambda s:
            s.get("oil") and s["oil"].get("framed")=="wells"
            and s["oil"]["stores"].get("wells")=="luanttd_core:industry_oil_well_0_0"
            and s["oil"]["stores"].get("refinery")=="luanttd_core:industry_oil_refinery_0_0"
            and s["oil"]["stores"].get("refinery_gate")=="luanttd_core:industry_oil_refinery_1_0"
            and not (s["oil"]["stores"].get("refinery_hole") or "").startswith("luanttd_core:industry"),45)["oil"]
        time.sleep(.68);screenshot("00pe-native-oil-wells-survey")
        phase="mouse-build the real oil and finished Goods route"
        chat("/survey 14 9");time.sleep(.45)
        slot(2);click();slot(5);click();await_state("Road Freight",lambda s:s.get("menu")=="freight")
        slot(2)
        paths=[
          ((12,4),(16,4),(16,7),(15,7),(15,8),(12,8),(12,14),(14,14),(14,16),(18,16)),
          ((12,4),(12,5),(16,5)),
          ((15,8),(15,12),(12,12)),
          ((18,16),(18,15),(14,15)),
        ]
        for pair in paths:
            for a,b in zip(pair,pair[1:]):
                aim(*a);time.sleep(.28);click();aim(*b);time.sleep(.28);click()
                await_state("built actual street "+str(b),lambda s:s["oil"]["roads"].get(f"{b[0]},{b[1]}")=="road")
        D,F,R,T=(11,12),(13,4),(16,16),(14,8)
        slot(3)
        for site in (F,R,T):
            aim(*site);click()
            await_state("owned dedicated loading stop "+str(site),lambda s:
              s["oil"]["roads"].get(f"{site[0]},{site[1]}")=="road_station")
        slot(4);aim(*D);click()
        await_state("oil route has a real depot",lambda s:tile(s,D)=="road_depot")
        phase="buy original tanker and Goods truck, choose live 3D station orders"
        trucks=(("oil_tanker","depot_buy_oil",F,R),("goods_truck","depot_buy_goods",R,T))
        for engine,offer,a,b in trucks:
            slot(1);aim(*D);click()
            choose("luanttd_core:service",offer,"native-buy-"+engine)
            choose("luanttd_core:service","service_pick","native-orders-"+engine)
            for p in (a,b): aim(*p);click()
            click(3)
            await_state("actual orders for "+engine,lambda s:s["oil"]["working"][engine]["orders"]==2)
            choose("luanttd_core:service","service_back","oil-depot-return-"+engine)
            await_state("world restored",lambda s:not s.get("form"))
            time.sleep(.60)
        slot(8);click();await_state("Road Construction",lambda s:s.get("menu")=="roads")
        slot(8);click();await_state("Home",lambda s:s.get("menu")=="home")
        slot(3);click();await_state("Fleet operations",lambda s:s.get("menu")=="fleet")
        for n,(engine,*_) in enumerate(trucks,1):
            slot(3);click()
            choose("luanttd_core:service","vehicle_"+str(n),"oil-fleet-"+str(n))
            choose("luanttd_core:service","service_toggle","oil-dispatch-"+str(n))
            await_state("vehicle is dispatched and menu closed",lambda s:
              not s.get("form") and s["oil"]["working"][engine]["active"])
            time.sleep(.60)
        chat("/qa_oil go")
        phase="inspect true loaded tanker and save in native SQLite"
        loaded=await_state("the real original closed tanker is hauling stock crude",lambda s:
            s.get("oil") and s["oil"].get("loaded"),120)["oil"]
        assert loaded["crude"]==0 and loaded["loaded"]["units"]>=5
        chat("/qa_oil loaded")
        await_state("nearby view frames the real loaded tanker",lambda s:s["oil"].get("framed")=="loaded")
        time.sleep(.61);screenshot("01pe-native-witcombe-tanker-loaded")
        stop_server()
        phase="reload the actual loaded road vehicle and pay both refinery chain fares"
        restored=join("stock-oil-loaded-restart")["oil"]
        assert restored["loaded"]==loaded["loaded"] and restored["crude"]==0
        assert restored["working"]["oil_tanker"]["units"]==loaded["working"]["oil_tanker"]["units"]
        chat("/qa_oil go")
        def delivered_oil(s):
            o=s["oil"];w=o["working"]
            return o["crude"]>=21 and w["goods_truck"]["paid"]>0 and all(v["expense"]>0 for v in w.values())
        final=await_state("oil paid at the refinery; later the same stop sends paid Goods into houses",delivered_oil,250)["oil"]
        assert final["tick"]==final["house"] and final["working"]["oil_tanker"]["paid"]==final["crude"]
        assert sum(v["paid"] for v in final["working"].values())==final["paid"]
        assert sum(v["cash"] for v in final["working"].values())==final["money"]
        chat("/qa_oil refinery")
        await_state("real refinery receiving scene in view",lambda s:s["oil"].get("framed")=="refinery")
        time.sleep(.62);screenshot("02pe-native-oil-refinery-paid-goods")
        (out/"oil-workbench-desktop.json").write_text(json.dumps(dict(
            before=start_oil,loaded=loaded,restored=restored,paid=final),indent=2))
        stop_server()
        print(f"PASS: native mouse-built oil-to-refinery-to-Goods company, real loaded stock tanker and paid SQLite replay: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_FARM")=="1":
        phase="review original farm buildings, growing field geometry and boundary fences"
        chat("/qa_farm farm")
        first=await_state("stock farm, stock factory and actual planted fields render",lambda s:
            (s.get("farm") or {}).get("fields",0)>=100 and s["farm"]["fences"]>0 and
            s["farm"]["mesh"].get("farm")=="luanttd_core:industry_farm_0_0" and
            s["farm"]["mesh"].get("factory")=="luanttd_core:industry_factory_0_0" and
            s["farm"].get("framed")=="farm",45)["farm"]
        time.sleep(.65)
        screenshot("00ad-native-highfield-farm-survey")
        phase="mouse-build real routes, turn loops, depot and three freight stops on the untouched seed"
        chat("/survey 14 9")
        slot(2);click();await_state("Road Construction",lambda s:s.get("menu")=="roads")
        slot(5);click()
        await_state("freight roadworks",lambda s:s.get("menu")=="freight")
        slot(2)
        paths=[
            ((11,4),(16,4),(16,7),(15,7),(15,8),(12,8),(12,14),(13,14),(13,15),(19,15),(19,20)),
            ((11,4),(11,5),(16,5)),
            ((15,8),(15,12),(12,12)),
            ((19,15),(20,15),(20,20),(19,20)),
        ]
        for path in paths:
            for begin_tile,end_tile in zip(path,path[1:]):
                aim(*begin_tile);time.sleep(.30);click()
                aim(*end_tile);time.sleep(.30);click()
                await_state("built freight street to "+str(end_tile),lambda s:
                    s["farm"]["streets"].get(f"{end_tile[0]},{end_tile[1]}")=="road")
        D,F,P,T=(11,12),(13,4),(19,17),(14,8)
        slot(3)
        for at in (F,P,T):
            aim(*at);click()
            await_state("placed stock freight loading stop "+str(at),lambda s:
                        s["farm"]["streets"].get(f"{at[0]},{at[1]}")=="road_station")
        slot(4);aim(*D);click()
        await_state("owned depot",lambda s:tile(s,D)=="road_depot")
        phase="buy original grain, livestock and Goods trucks and pick their actual stop orders"
        roster=[
          ("grain_truck","depot_buy_grain",F,P),
          ("livestock_van","depot_buy_livestock",F,P),
          ("goods_truck","depot_buy_goods",P,T),
        ]
        for engine,button,a,b in roster:
            slot(1);aim(*D);click()
            choose("luanttd_core:service",button,"buy-"+engine+"-native")
            choose("luanttd_core:service","service_pick","first-order-"+engine)
            for p in (a,b):
                aim(*p);click()
            click(3)
            await_state("both actual stop picks committed",lambda s:
                s["farm"]["vehicles"][engine]["orders"]==2)
            if engine!="goods_truck":
                choose("luanttd_core:service","service_back","return-"+engine)
            else:
                choose("luanttd_core:service","service_back","return-farm-goods")
        for _ in range(3):
            if state().get("menu")=="home": break
            before_menu=state().get("menu")
            slot(8);click()
            await_state("back from "+str(before_menu),lambda s:s.get("menu")!=before_menu)
        slot(3);click();await_state("fleet operations",lambda s:s.get("menu")=="fleet")
        for idx in range(1,4):
            slot(3);click()
            choose("luanttd_core:service",f"vehicle_{idx}",f"farm-select-vehicle-{idx}")
            choose("luanttd_core:service","service_toggle",f"farm-start-vehicle-{idx}")
            engine=roster[idx-1][0]
            await_state("dispatch complete and world input restored", lambda s:
                not s.get("form") and s["farm"]["vehicles"][engine]["active"])
            time.sleep(.60)
        chat("/qa_farm go")
        phase="observe actual grain payload, ventilated livestock body and all three paid routes"
        grain=await_state("grain is really visible inside the travelling truck",lambda s:
            (s["farm"].get("loaded") or {}).get("units",0)>=10,115)["farm"]
        chat("/qa_farm grain")
        await_state("native camera has framed the frozen loaded truck",lambda s:s["farm"].get("framed")=="grain")
        time.sleep(.65)
        screenshot("01ad-native-grain-loaded-visible")
        chat("/qa_farm go")
        def paid_farm(s,earlier=None):
            f=s["farm"]
            for key,_,_,_ in roster:
                v=f["vehicles"][key]
                if v["paid"]<=(earlier and earlier["vehicles"][key]["paid"] or 0) or v["expense"]<=0:
                    return False
            return f["tick"]==f["house"] and bool(f.get("van"))
        paid=await_state("factory takes both inputs and town earns the converted Goods fare",paid_farm,250)["farm"]
        assert paid["receipts"]["grain"]==paid["vehicles"]["grain_truck"]["paid"]
        assert paid["receipts"]["livestock"]==paid["vehicles"]["livestock_van"]["paid"]
        assert sum(v["paid"] for v in paid["vehicles"].values())==paid["company_paid"]
        assert sum(v["cash"] for v in paid["vehicles"].values())==paid["company_money"]
        chat("/qa_farm factory")
        await_state("factory cash and actual building framed",lambda s:s["farm"].get("framed")=="factory")
        time.sleep(.65)
        screenshot("02ad-native-factory-after-stock-goods-output")
        stop_server()
        phase="restore all farm trucks, field state and real farm/industry ledgers"
        opened=join("stock-farm-restarted")["farm"]
        assert opened["loaded"]==grain["loaded"] and opened["company_paid"]>=paid["company_paid"]
        later=await_state("new settled deliveries for every actual carrier after restore",
             lambda s:paid_farm(s,opened),250)["farm"]
        assert later["receipts"]["grain"]==later["vehicles"]["grain_truck"]["paid"]
        assert later["receipts"]["livestock"]==later["vehicles"]["livestock_van"]["paid"]
        assert sum(v["paid"] for v in later["vehicles"].values())==later["company_paid"]
        (out/"farm-workbench-desktop.json").write_text(json.dumps(dict(before=first,loaded=grain,
            paid=paid,reopened=opened,after=later),indent=2))
        stop_server()
        print(f"PASS: full mouse-built original farm, factory and town Goods logistics with native art and repeat paid saves: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_TIMBER")=="1":
        phase="fresh timber map has real forest and sawmill artwork on actual stock footprints"
        forest,wood_in,goods_out,town,depot=(16,2),(15,17),(12,15),(14,8),(11,12)
        base=await_state("stock industry meshes on the persistent map",lambda s:
            s["timber"]["enabled"] and
            s["timber"]["ind"].get("forest",{}).get("mesh")=="luanttd_core:forest_0_0_0" and
            s["timber"]["ind"].get("sawmill",{}).get("mesh")=="luanttd_core:sawmill_0_0_0")
        assert base["timber"]["ind"]["forest"]["n"]==18 and base["timber"]["ind"]["sawmill"]["n"]==8
        slot(2);click();slot(5);click()
        await_state("Freight Roadworks",lambda s:s.get("menu")=="freight")
        slot(2)
        paths=[
            ((16,2),(16,7),(15,7),(15,8),(12,8),(12,14),(13,14),(13,15),(15,15),(15,17)),
            ((15,8),(15,12),(12,12)),
            ((12,14),(12,15)),
        ]
        phase="mouse-build the wood trunk, town return and separate sawmill Goods spur"
        chat("/qa_timber north")
        await_state("new camera position settled before calibrating native mouse look",lambda s:
            (s.get("camera") or {}).get("pos",{}).get("x")==35)
        time.sleep(.7)
        for path in paths:
            for a,b in zip(path,path[1:]):
                aim(*a);click();aim(*b);click()
                await_state(f"road segment ending {b}",lambda s:
                    s["timber"]["road_tiles"].get(f"{b[0]},{b[1]}")=="road")
        slot(3)
        for pos in (forest,wood_in,goods_out,town):
            aim(*pos);click()
            await_state(f"stock truck stop at {pos}",lambda s:tile(s,pos)=="road_station")
        slot(4);aim(*depot);click()
        await_state("actual yard depot",lambda s:tile(s,depot)=="road_depot")
        phase="buy and order two exact cargo trucks at the actual depot"
        for engine,control,order in (
            ("wood_truck","depot_buy_wood",(forest,wood_in)),
            ("goods_truck","depot_buy_goods",(goods_out,town)),
        ):
            slot(1);aim(*depot);click()
            choose("luanttd_core:service",control,engine+"-purchase")
            choose("luanttd_core:service","service_pick",engine+"-pick")
            for pos in order: aim(*pos);click()
            click(3)
            choose("luanttd_core:service","service_cycle_load",engine+"-full")
            await_state("real full-load order",lambda s:
                s["timber"]["vehicles"][engine]["orders"]==2 and s["timber"]["vehicles"][engine]["order"]=="full")
            choose("luanttd_core:service","service_toggle",engine+"-dispatch")
        chat("/qa_timber go")
        phase="loaded logging model visibly changes at ten tons and survives SQLite reload"
        first=await_state("actual original truck's loaded OBJ",lambda s:s["timber"].get("loaded"),105)["timber"]
        assert first["loaded"]["units"]>=10 and first["ind"]["sawmill"]["received"]==0
        chat("/qa_timber photo");time.sleep(.55)
        screenshot("01t-real-stock-loaded-witcombe")
        stop_server()
        resume=join("timber-loaded-restart")["timber"]
        assert resume["loaded"]==first["loaded"] and resume["vehicles"]["wood_truck"]["units"]==first["loaded"]["units"]
        chat("/qa_timber go")
        phase="witness the sawmill's physical wood payment and separate paid town Goods delivery"
        final=await_state("second real processed goods delivery",lambda s:
            s["timber"].get("town_goods",0)>=28 and
            s["timber"]["vehicles"]["goods_truck"]["delivered"]>=28,150)["timber"]
        assert final["ind"]["sawmill"]["received"]>=40
        assert all(v["revenue"]>0 and v["expense"]>0 for v in final["vehicles"].values())
        assert final["mesh"]["luanttd_core:vehicle_goods_truck"]["obj"]=="bl_balogh_goods_truck.obj"
        chat("/qa_timber sawmill");time.sleep(.55);screenshot("02t-tidewater-sawmill-and-two-road-approaches")
        (out/"timber-desktop-native.json").write_text(json.dumps({"loaded":first,"reload":resume,"after":final},indent=2))
        stop_server()
        print(f"PASS: untouched native timber countryside, mouse-established logistics, persisted loaded Witcombe, {final['town_goods']} crates paid.")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_RAIL_PAIR")=="1":
        mixed=os.environ.get("BAYLINE_NATIVE_RAIL_MIXED")=="1"
        phase="purchase two real stock steam locomotives on a prepared signed railway"
        chat("/qa_pair prepare")
        await_state("stock three-platform rail network",lambda s:(s.get("rail_pair") or {}).get("ready"))
        slot(8);click()
        await_state("Railworks",lambda s:s.get("menu")=="railworks")
        for i,dep in enumerate(((2,14),(8,9)),1):
            slot(1);aim(*dep);click()
            choose("luanttd_core:rail_fleet","purchase_a4" if i==2 and mixed else "purchase",f"buy-paired-engine-{i}")
            await_state(f"owned train {i}",lambda s:f"unit_{i}" in (s.get("buttons") or {}))
            choose("luanttd_core:rail_fleet","back",f"close-rail-depot-{i}")
        slot(7);click()
        await_state("Rail Operations",lambda s:s.get("menu")=="railops")
        slot(6);click()
        phase="choose depot and station orders for each train by physical world click"
        for x,z in ((2,14),(17,14),(33,14),(8,9),(17,14),(28,5)):
            if (x,z)==(28,5): chat("/qa_pair north")
            aim(x,z);click()
            print(f"Pair click {x},{z}: {(state().get('rail_pair') or {}).get('guide')}",flush=True)
        slot(8);click()
        staged=await_state("both were dispatched by one order transaction",lambda s:
            (s.get("rail_pair") or {}).get("first") and s["rail_pair"].get("second"))
        assert staged["rail_pair"]["first"]["delivered"]==0 and staged["rail_pair"]["second"]["delivered"]==0
        assert staged["rail_pair"]["stock"]==[0,9 if mixed else 0]
        assert staged["rail_pair"]["max_speed"]==[64,128 if mixed else 64]
        assert staged["rail_pair"]["annual_fp"]==[280000,784000 if mixed else 280000]
        chat("/qa_pair survey")
        slot(8);click()
        await_state("Railworks",lambda s:s.get("menu")=="railworks")
        slot(1);aim(8,9);click()
        choose("luanttd_core:rail_fleet","unit_2","01ra-hold-the-second-purchased-train")
        choose("luanttd_core:rail_fleet","back","01ra-leave-the-held-train-depot")
        chat("/qa_pair one")
        await_state("one ordinary shared economy day advanced",lambda s:s["rail_pair"].get("manual_day"))
        aim(8,9);click()
        choose("luanttd_core:rail_fleet","unit_2","01rb-resume-the-second-purchased-train")
        choose("luanttd_core:rail_fleet","back","01rc-return-to-railway")
        chat("/qa_pair go")
        phase="two original stock coaches visible; the second waits while only the first wagon holds the merge"
        def held(s):
            p=s.get("rail_pair") or {}
            return ((p.get("phase_hold") or {}).get("red")
                    and len(p.get("trains") or [])==len(p.get("wagons") or [])==2)
        before=await_state("two real locomotive meshes and both wagons at the occupied merge",held,55)["rail_pair"]
        assert before["phase_hold"]["rail"][0]!=before["phase_hold"]["rail"][1]
        meshes=sorted(x["mesh"] for x in before["trains"])
        assert meshes==sorted(["bl_rail_kirby_paul_tank.obj",
                               "bl_rail_ginzu_a4.obj" if mixed else "bl_rail_kirby_paul_tank.obj"])
        chat("/qa_pair photo");time.sleep(.65)
        screenshot("01r-purchased-trains-stock-pbs-hold")
        stop_server()
        join("rail-pair-reloaded")
        after=await_state("same reservation and four independent native models after SQLite restore",held,30)["rail_pair"]
        assert after["phase_hold"]==before["phase_hold"]
        chat("/qa_pair go")
        phase="both trains unload independently, then park on separate occupied terminals"
        final=await_state("both sustained services posted actual passenger fares",lambda s:
            (s["rail_pair"].get("first") or {}).get("finished") and
            (s["rail_pair"].get("second") or {}).get("finished"),125)
        end=final["rail_pair"]
        assert end["first"]["delivered"]==end["second"]["delivered"]==40
        assert final["revenue"]==end["first"]["fare"]+end["second"]["fare"] and min(end["finance"])>0
        assert len(end["trains"])==len(end["wagons"])==2
        if mixed: assert end["wait_event"]
        chat("/qa_pair finish");time.sleep(.55);screenshot("02r-both-owned-trains-at-separate-platforms")
        (out/"rail-pair-desktop.json").write_text(json.dumps({"before":before,"reload":after,"after":end},indent=2))
        stop_server()
        print("PASS: native depot purchase and paired world orders, rear holds PBS across restart; each train delivered 40 passengers.")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_RAIL_OIL")=="1":
        phase="designate wells and refinery using the actual Rail Freight hotbar"
        chat("/qa_railoil layout")
        await_state("paid test layout with original seed kept intact",lambda s:s.get("rail_oil",{}).get("ready"))
        slot(8);click();slot(7);click()
        await_state("Rail Operations hotbar",lambda s:s.get("menu")=="railops")
        slot(5);click()
        await_state("Rail Freight hotbar",lambda s:s.get("menu")=="railfreight")
        slot(4);aim(11,5);click()
        await_state("real well loading role visible",lambda s:(s.get("rail_oil") or {}).get("wells")=="load")
        screenshot("01-oil-well-platform")
        chat("/qa_railoil refinery")
        slot(5);aim(12,17);click()
        await_state("real refinery unloading role visible",lambda s:(s.get("rail_oil") or {}).get("refinery")=="unload")
        screenshot("02-oil-refinery-platform")
        phase="pay for Kirby and tanker, then pick both physical platforms"
        chat("/qa_railoil layout")
        slot(1);aim(14,5);click()
        choose("luanttd_core:rail_fleet","purchase_oil","03-buy-kirby-and-oil-tanker")
        buy=await_state("the purchased Oil Tanker is not a substitute",lambda s:
            ((s.get("rail_oil") or {}).get("unit") or {}).get("stock_ids")==[0,30])
        choose("luanttd_core:rail_fleet","unit_1","04-order-oil-train")
        aim(11,5);click()
        await_state("the first picked platform sets the refinery order prompt",lambda s:
            "Refinery unloading platform" in (s["rail_oil"].get("toast") or ""))
        chat("/qa_railoil refinery")
        aim(12,17);click();slot(8);click()
        await_state("native world orders created a real purchased train in the depot",lambda s:
            ((s.get("rail_oil") or {}).get("train") or {}).get("phase")=="depot")
        chat("/qa_railoil go")
        first=await_state("a physically rendered stock tanker loads actual oil",lambda s:
            (s.get("rail_oil") or {}).get("partial"),100)["rail_oil"]
        assert first["partial"]["kind"]=="luanttd_core:dispatch_oil_tanker"
        assert 0<first["partial"]["oil"]<30 and first["oil"]==0
        chat("/qa_railoil photo");time.sleep(.8);screenshot("05-real-oil-tanker-loading")
        phase="restore loading and physically deliver to the refinery and town"
        stop_server()
        restored=join("oil-train-restored")["rail_oil"]
        assert restored["partial"]==first["partial"] and restored["train"]["onboard"]==first["train"]["onboard"]
        chat("/qa_railoil resume")
        latest=await_state("rail oil pays and the paid truck delivers the refinery's output",lambda s:
            ((s.get("rail_oil") or {}).get("train") or {}).get("delivered",0)>=30 and s["rail_oil"].get("goods",0)>0,150)["rail_oil"]
        assert latest["train"]["fare"]>0 and latest["goods_fare"]>0
        assert latest["oil"]==latest["train"]["delivered"] and latest["train"]["tick"]==latest["house_tick"]
        chat("/qa_railoil refinery");time.sleep(.8);screenshot("06-refinery-goods-delivered")
        (out/"rail-oil-native.json").write_text(json.dumps(dict(purchased=buy["rail_oil"]["unit"],loaded=first,
            restored=restored,paid=latest),indent=2))
        stop_server()
        print(f"PASS: native tanker purchased and ordered by mouse, loading restored, refinery and Goods truck paid: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_RAIL_COAL")=="1":
        phase="build authentic owned track from the untouched power station to the mine"
        chat("/qa_railcoal ready")
        await_state("rail-only coal industry seeded",lambda s:s.get("rail_coal",{}).get("ready"))
        slot(8);click()
        await_state("Railworks",lambda s:s.get("menu")=="railworks")
        rotate_rail_fitting(2)
        slot(4);aim(44,15);click()
        await_state("west-facing dedicated rail depot",lambda s:
            (s.get("track_nodes") or {}).get("44,15",{}).get("depot")==0)
        slot(2);hold_to_build(aim,(30,15),(43,15))
        await_state("the fourteen standard tracks are paid and placed",lambda s:s.get("rail_work",{}).get("track")==15)
        slot(3);aim(30,15);click();aim(32,15);click();aim(39,15);click();aim(41,15);click()
        await_state("actual owned platforms in both coal catchments",lambda s:s.get("rail_work",{}).get("platforms")==2)
        slot(5);click()
        await_state("Path Signals",lambda s:s.get("menu")=="railsignals")
        slot(6);click();click()
        slot(2);aim(42,15);click()
        await_state("correct return signal follows stock direction",lambda s:s.get("rail_work",{}).get("signals")==1)
        slot(8);click();slot(7);click()
        await_state("Rail Operations",lambda s:s.get("menu")=="railops")
        slot(5);click()
        await_state("only opt-in workbench shows Rail Freight",lambda s:s.get("menu")=="railfreight")
        slot(2);aim(30,15);click()
        slot(3);aim(41,15);click()
        stages=await_state("loader and receiver assets are different real native meshes",lambda s:
            (s["rail_coal"].get("stages") or {}).get("load",{}).get("model")=="luanttd_core:rail_coal_stage_load_0_mirror" and
            s["rail_coal"]["stages"].get("unload",{}).get("model")=="luanttd_core:rail_coal_stage_unload_0_mirror")
        initial=stages["cash"]
        slot(1);aim(44,15);click()
        await_state("the owner can buy the actual coal wagon from the depot",lambda s:
            s.get("form")=="luanttd_core:rail_fleet" and "purchase_coal" in (s.get("buttons") or {}))
        choose("luanttd_core:rail_fleet","purchase_coal","00q-real-coal-train-purchase")
        buy=await_state("stock #0 locomotive and stock #29 coal wagon bought together",lambda s:
            (s["rail_coal"].get("unit") or {}).get("stock_ids")==[0,29] and "unit_1" in (s.get("buttons") or {}))
        assert buy["rail_coal"]["unit"]["price"]==12312 and buy["cash"]==initial-12312
        choose("luanttd_core:rail_fleet","unit_1","Set rail-coal orders")
        aim(30,15);click();aim(41,15);click();slot(8);click()
        await_state("ordered true owned coal on exact designated stages and no passenger alias",lambda s:
            (s["rail_coal"].get("coal") or {}).get("phase")=="depot" and not s.get("form"))
        chat("/qa_railcoal go")
        first=await_state("real model fills with stock coal and saves in the native scene",lambda s:
            s["rail_coal"].get("loaded") and s["rail_coal"].get("wagon_mesh")=="luanttd_core:dispatch_coal_loaded",85)["rail_coal"]
        assert first["loaded"]["units"]>0 and abs(first["loaded"]["wagon"]["y"]-.614)<.025
        chat("/qa_railcoal photo");time.sleep(.8);screenshot("01q-coal-wagon-filled-in-native-game")
        phase="restore the same real coal wagon, reverse and deliver at the power plant"
        stop_server()
        restored=join("coal-train-reloaded")["rail_coal"]
        assert restored["loaded"]==first["loaded"] and restored["coal"]["onboard"]==first["coal"]["onboard"]
        chat("/qa_railcoal resume")
        again=await_state("fresh second load after a completed first delivery and physical empty return",lambda s:
            s["rail_coal"].get("second_load") and s["rail_coal"]["coal"].get("cycles")==1,105)["rail_coal"]
        assert again["second_load"]["delivered"]==30==again["received"]
        assert again["second_load"]["units"]>0 and again["second_load"]["clock"]>first["loaded"]["clock"]
        # Inspection and order change use the live depot formspec; the QA
        # pause only freezes the world while images and form state settle.
        slot(8);click()
        phase="schedule an actual parking order from the depot panel"
        # The reconnect resets the nested menu to Home.
        if state().get("menu")=="home":
            slot(8);click()
        await_state("Railworks visible on reconnect",lambda s:s.get("menu")=="railworks")
        slot(1);aim(44,15);click()
        choose("luanttd_core:rail_fleet","park_coal","01qb-park-coal-after-second-delivery")
        await_state("park option now saved",lambda s:s["rail_coal"]["coal"].get("parking"))
        choose("luanttd_core:rail_fleet","back","01qc-return-to-coal-world")
        chat("/qa_railcoal resume")
        end=await_state("rail coal pays for exactly what the actual power plant received",lambda s:
            (s["rail_coal"].get("coal") or {}).get("finished") and s["rail_coal"].get("wagon_mesh")=="luanttd_core:dispatch_coal_empty",105)["rail_coal"]
        assert end["coal"]["cycles"]==2 and end["coal"]["delivered"]==60==end["received"]
        assert end["coal"]["fare"]>again["coal"]["fare"]>0 and end["coal"]["running_expense"]>0
        assert end["coal"]["tick"]==end["house_tick"]
        chat("/qa_railcoal plant");time.sleep(.7);screenshot("02q-coal-wagon-empty-at-power-plant")
        (out/"rail-coal-desktop-native.json").write_text(json.dumps(dict(
          purchase=buy["rail_coal"]["unit"],first=first,restored=restored,second=again,after=end),indent=2))
        stop_server()
        print(f"PASS: genuine wagon built & ordered by mouse, restored, two paid 30-ton deliveries, then parked by mouse: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_RAIL_OWNED")=="1":
        phase="buy the source temperate steam locomotive in a real rail depot"
        chat("/qa_owned_train prepare")
        await_state("real source town terrain",lambda s:s.get("owned_rail",{}).get("ready"))
        default_steam=os.environ.get("BAYLINE_NATIVE_OWNED_DEFAULT")=="1"
        jubilee=os.environ.get("BAYLINE_NATIVE_JUBILEE")=="1"
        ginzu=os.environ.get("BAYLINE_NATIVE_GINZU")=="1"
        floss=os.environ.get("BAYLINE_NATIVE_FLOSS")=="1"
        assert sum([jubilee,ginzu,floss])<=1
        cases={
            "kirby": (0,64,12866,"purchase",72,"kirby_paul_tank","01p-kirby-pays-native",280000),
            "jubilee": (8,112,22241,"purchase_jubilee",156,"chaney_jubilee","01pa-jubilee-boards-native",672000),
            "ginzu": (9,128,31616,"purchase_a4",187,"ginzu_a4","01pb-ginzu-a4-boards-native",784000),
            "floss": (15,160,30054,"purchase_floss",137,"floss_47","01pf-floss-47-paid-native",728000),
        }
        stock,speed,price,buy_button,expected_mass,loco_name,photo_name,annual_fp=cases[
            "floss" if floss else "ginzu" if ginzu else "jubilee" if jubilee else "kirby"]
        rail_z=5 if default_steam else 10
        west,east=(5,21) if default_steam else (11,22)
        if default_steam:
            slot(2);click()
            await_state("Roadworks for clearing three trees",lambda s:s.get("menu")=="roads")
            slot(9)
            for x in (2,3,4):
                aim(x,rail_z);click()
            slot(8);click()
            await_state("Back to the main menu after clearing",lambda s:s.get("menu")=="home")
        slot(8);click()
        await_state("Railworks enabled with purchased train profile",lambda s:s.get("menu")=="railworks")
        if default_steam:
            phase="build the entire default-seed steam route by mouse, without prepared track"
            slot(4);aim(2,rail_z);click()
            await_state("stock depot built before connecting rail",lambda s:(s.get("rail_work") or {}).get("depot")==1)
            slot(2);hold_to_build(aim,(3,rail_z),(23,rail_z))
            await_state("twenty-two real rails placed",lambda s:(s.get("rail_work") or {}).get("track")==22,25)
            slot(3);aim(5,rail_z);click();aim(6,rail_z);click();aim(21,rail_z);click();aim(23,rail_z);click()
            await_state("two real passenger platforms",lambda s:(s.get("rail_work") or {}).get("platforms")==2)
            slot(5);click()
            await_state("Path Signals",lambda s:s.get("menu")=="railsignals")
            slot(6);click();click()  # face west to protect the arriving return leg
            slot(2);aim(4,rail_z);click()
            await_state("source-facing path signal before the west platform",lambda s:(s.get("rail_work") or {}).get("signals")==1)
            slot(8);click()
            await_state("Back in Railworks",lambda s:s.get("menu")=="railworks")
        waypoint=os.environ.get("BAYLINE_NATIVE_RAIL_WAYPOINT")=="1"
        via_v=16
        if waypoint:
            phase="build and remove an actual rail waypoint from the compact world hotbar"
            slot(7);click();await_state("Rail Operations",lambda s:s.get("menu")=="railops")
            slot(9);click();await_state("Rail Waypoints",lambda s:s.get("menu")=="railwaypoints")
            slot(2);aim(via_v,rail_z)
            before_wp=state()["cash"]
            click()
            def painted(s):
                q=(s.get("owned_rail") or {}).get("waypoint") or {}
                return q.get("node")=="luanttd_core:rail_waypoint_0" and q.get("track")==1 and q.get("id")
            made=await_state("real waypoint node, two-sided model, and unchanged underlying track",painted)
            assert made["cash"]==before_wp-600
            time.sleep(.8);screenshot("01-rail-waypoint-built")
            slot(3);click()
            erased=await_state("removal restores plain rail without removing its pieces",lambda s:
                not (s["owned_rail"].get("waypoint") or {}).get("id") and
                (s["owned_rail"].get("waypoint") or {}).get("track")==1)
            assert erased["cash"]==made["cash"]-150
            slot(2);aim(via_v,rail_z);click();await_state("waypoint rebuilt for passenger train",painted)
            for m in ("railops","railworks"):
                slot(8);click();await_state(m,lambda s:s.get("menu")==m)
        initial=state()["cash"]
        slot(1);aim(2,rail_z);click()
        await_state("actual depot offers a priced train",lambda s:
            s.get("form")=="luanttd_core:rail_fleet" and buy_button in (s.get("buttons") or {}))
        choose("luanttd_core:rail_fleet",buy_button,"00p-purchased-stock-train")
        bought=await_state("owned stock train and coach persist with exact price",
            lambda s:(s.get("owned_rail") or {}).get("count")==1 and "unit_1" in (s.get("buttons") or {}))
        record=bought["owned_rail"]["unit"]
        assert record["stock_ids"]==[stock,27] and record["price"]==price and bought["cash"]==initial-price
        choose("luanttd_core:rail_fleet","unit_1","Start owned steam orders")
        await_state("pick real platforms from the 3D world",lambda s:not s.get("form"))
        aim(east,rail_z);click()
        if waypoint:
            aim(via_v,rail_z);click();time.sleep(.35)
            screenshot("02-real-passenger-order-picks-waypoint")
        aim(west,rail_z);click();slot(8);click()
        await_state("paid orders use the purchased locomotive",lambda s:
            s["owned_rail"].get("phase")=="depot" and s["owned_rail"].get("stock")==stock and
            s["owned_rail"].get("max")==speed and not s.get("form"))
        if waypoint:
            assert state()["owned_rail"]["via"]["id"]==state()["owned_rail"]["waypoint"]["id"]
            assert state()["owned_rail"]["via"]["passes"]==0
        chat("/qa_owned_train go")
        first=await_state("the actual original steam and carriage board on the source clock",
            lambda s:s["owned_rail"].get("boarded"),65)["owned_rail"]
        assert abs(first["boarded"]["engine"]["y"]-.614)<.025 and first["boarded"]["units"]>0
        assert first["boarded"]["mass"]>=expected_mass and first["paid"]["tick"]==first["house_tick"]
        assert first["boarded"]["model"]=="bl_rail_"+loco_name+".obj"
        assert first["moving"]["running_year_fp"]==annual_fp
        assert first["moving"]["future_daily_rate_fp"]==annual_fp//365
        chat("/qa_owned_train photo")
        time.sleep(1.15);screenshot(photo_name)
        phase="restore the same purchased train with passengers and observe payment"
        stop_server()
        resumed=join("owned-rail-reloaded")["owned_rail"]
        assert resumed["boarded"]==first["boarded"] and resumed["unit"]["id"]==record["id"]
        assert resumed["paid"]["onboard"]==first["paid"]["onboard"]
        if waypoint: assert resumed["via"]==first["via"]
        chat("/qa_owned_train resume")
        final=await_state("purchased steam reverses and earns real stock fares",lambda s:
            (s["owned_rail"].get("paid") or {}).get("fare",0)>0 and
            s["owned_rail"].get("reversals",0)>=2 and
            (not waypoint or s["owned_rail"].get("via",{}).get("passes",0)>=2),90)["owned_rail"]
        if waypoint:
            assert final["waypoint"]["id"]==final["via"]["id"] and final["first_pass_speed"]>0
            screenshot("03-waypoint-train-earned-passenger-fares")
        assert final["paid"]["delivered"]>0 and final["count"]==1 and final["paid"]["tick"]==final["house_tick"]
        if jubilee or ginzu or floss: assert final["moving"]["running_expense"]>0
        (out/"owned-steam-native.json").write_text(json.dumps(dict(purchase=record,first=first,restored=resumed,after=final),indent=2))
        stop_server()
        print(f"PASS: buy exact stock steam set by mouse, order, board, restore and earn fares: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_ONEWAY")=="1":
        phase="mark a one-way road by dragging in the actual travel direction"
        chat("/qa_oneway prepare")
        await_state("a flat, reversible road fixture",lambda s:
            (s.get("oneway") or {}).get("ready") and s["oneway"]["route_east"] and s["oneway"]["route_west"])
        def open_direction():
            slot(2);click()
            await_state("Roadworks",lambda s:s.get("menu")=="roads")
            slot(7);click()
            await_state("Road Direction",lambda s:s.get("menu")=="road_direction")
        def mark():
            slot(2);hold_to_build(native_aim,(12,12),(17,12))
        open_direction();mark()
        east=await_state("real sign pair, arrows and east-only source route",lambda s:
            s["oneway"].get("dir")==2 and s["oneway"]["route_east"] and not s["oneway"]["route_west"] and
            s["oneway"].get("surface")=="luanttd_core:oneway_paint_2_g0")["oneway"]
        assert east["entry"]=="luanttd_core:oneway_2_g0"
        chat("/qa_oneway street");time.sleep(.7);screenshot("01o-oneway-signed-road")
        chat("/qa_oneway overview");mark()
        await_state("same drag removes the sign and restores both directions",lambda s:
            s["oneway"].get("drd")==0 and s["oneway"]["route_west"] and s["oneway"]["route_east"])
        chat("/qa_oneway arrange");mark()
        await_state("a stale westbound order faces a new east-only section",lambda s:
            s["oneway"].get("dir")==2 and not s["oneway"]["route_west"] and s["oneway"].get("road_tile"))
        chat("/qa_oneway go")
        held=await_state("physical frame holds at closed direction",lambda s:
            s["oneway"].get("held"),30)["oneway"]
        assert held["held"]["tile"]==held["road_tile"]
        stop_server()
        restored=join("oneway-reloaded")["oneway"]
        assert restored["held"]==held["held"] and restored["road_tile"]==held["road_tile"]
        assert not restored["route_west"] and restored["dir"]==2
        chat("/qa_oneway overview");open_direction();mark();chat("/qa_oneway resume")
        final=await_state("reopening the road lets the held bus reach its stop",lambda s:
            s["oneway"].get("last_stop")==s["oneway"].get("target") and s["oneway"]["route_west"],35)["oneway"]
        (out/"oneway-native.json").write_text(json.dumps(dict(east=east,held=held,restored=restored,after=final),indent=2))
        stop_server()
        print(f"PASS: native one-way markings, directed route, saved physical hold and resumed bus: {out}")
        sys.exit(0)
    native_pass=os.environ.get("BAYLINE_NATIVE_OVERTAKE")
    if native_pass:
        phase="view actual vehicles paused in a stock overtaking phase"
        chat("/qa_overtake prepare")
        def displaced(s):
            snap=s.get("overtake") or {}
            a,b=snap.get("lead"),snap.get("follow")
            return a and b and abs(a["z"]-b["z"])>.29 and snap.get("active") and "road" in (snap.get("road") or "")
        before=await_state("two actual meshes visibly in different lanes",displaced,25)["overtake"]
        assert before["kind"]==native_pass and before["simulation_passes"]==1 and before["timeline"]
        assert before["frame"]["z"]%16==9 and abs(before["follow"]["z"]-24.655)<.025
        assert abs(abs(before["lead"]["z"]-before["follow"]["z"])-.31)<.025
        time.sleep(1.5)  # the client mesh arrives after server-side telemetry
        screenshot("08-stock-overtake-"+native_pass)
        phase="restart while the overtaking actor is on the opposite lane"
        stop_server()
        join("overtake-reloaded")
        chat("/qa_overtake frame")
        restored=await_state("same road mesh still on its saved alternate lane",displaced,25)["overtake"]
        assert not restored["timeline"] and restored["frame"]==before["frame"]
        assert restored["ctr"]==before["ctr"] and abs(restored["follow"]["z"]-before["follow"]["z"])<.035
        chat("/qa_overtake resume")
        after=await_state("actual source actor returns safely to its lane",
            lambda s:(s.get("overtake") or {}).get("completed",0)>0 and
            abs((s["overtake"].get("follow") or {}).get("z",0)-24.345)<.03,20)["overtake"]
        assert after["simulation_passes"]==1 and not after["active"]
        chat("/qa_overtake capture_after")
        time.sleep(1.0);screenshot("09-stock-overtake-merged-"+native_pass)
        (out/("road-overtake-native-"+native_pass+".json")).write_text(
            json.dumps(dict(before=before,restored=restored,after=after),indent=2))
        stop_server()
        print(f"PASS: stock {native_pass} leader overtake rendered in real Luanti, retained lane after restart, returned: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_COAL")=="1":
        phase="actual paid source coal loading route between stock industries"
        chat("/qa_coal_view")
        slot(2);click();slot(5);click()
        await_state("Freight Roadworks hotbar",lambda s:s.get("menu")=="freight")
        slot(2);hold_to_build(native_aim,(31,14),(41,14))
        await_state("own the road between the industries",
            lambda s:"31,14" in s.get("builds",{}) and "41,14" in s.get("builds",{}))
        slot(4);aim(32,15);click()
        await_state("build the actual freight depot",lambda s:"32,15" in s.get("builds",{}))
        slot(3);aim(31,14);click();aim(41,14);click()
        freight=await_state("two loading stops with a real mine and power-station catchment",
           lambda s:len((s.get("coal_view") or {}).get("stops") or [])==2,25)["coal_view"]
        assert not freight["stops"][0]["accepts"] and freight["stops"][1]["accepts"],freight
        assert freight["mine"]==15 and freight["meshes"]["mine"].startswith("luanttd_core:coal_mine_0_")
        assert freight["meshes"]["plant"].startswith("luanttd_core:power_station_")
        slot(1);native_aim(30,11,target_height=1.5);click()
        await_state("inspect the true source mine",lambda s:s.get("form")=="luanttd_core:service" and "Mine" in (s.get("service_title") or ""))
        screenshot("01l-coal-mine-inspector")
        xdo("key","Escape")
        aim(32,15);click()
        await_state("coal tipper in the real road depot",lambda s: "depot_buy_coal" in (s.get("buttons") or {}))
        choose("luanttd_core:service","depot_buy_coal","Buy Coal Tipper")
        await_state("buy the original coal tipper",lambda s:s.get("engine")=="coal_tipper")
        choose("luanttd_core:service","service_pick","Go to…")
        await_state("vehicle ordering returned to world",lambda s:s.get("form") is None or s.get("form")=="")
        aim(31,14);click();aim(41,14);click()
        click(3)
        await_state("actual coal truck has both stock freight stops",lambda s:len(s.get("orders") or [])==2)
        choose("luanttd_core:service","service_toggle","Start service")
        chat("/qa_coal_view freight")
        first=await_state("original loaded mesh moves and real coal income posts",lambda s:
            (s.get("coal_view") or {}).get("revenue",0)>0 and s["coal_view"].get("loaded"),95)["coal_view"]
        assert first["plant"]==first["delivered"] and first["delivered"]>0 and first.get("winding")
        assert abs(first["loaded"]["y"]-.52)<.03
        screenshot("01l-paying-coal-tipper")
        phase="resume the same real industrial chain after SQLite restart"
        stop_server()
        restored=join("coal-reloaded")["coal_view"]
        assert restored["revenue"]>=first["revenue"]
        chat("/qa_coal_view freight")
        final=await_state("next stock coal payment and matching power-plant tons",
            lambda s:(s.get("coal_view") or {}).get("revenue",0)>restored["revenue"],90)["coal_view"]
        assert final["plant"]==final["delivered"] and final["delivered"]>restored["delivered"]
        (out/"coal-native.json").write_text(json.dumps(dict(first=first,restored=restored,after=final),indent=2))
        stop_server()
        print(f"PASS: native coal truck purchase, physical coal cargo mesh, source industry, fares and restart: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_MAIL")=="1":
        phase="postal service: place real terminals and order a van"
        chat("/qa_postal_route")
        chat("/truckstop 11 12")
        chat("/truckstop 17 12")
        def stops_ok(s):
            stops=s.get("postal_stops") or {}
            return all(stops.get(k,{}).get("accept") and
                stops[k].get("node","").startswith("luanttd_core:stock_road_post_stop_")
                for k in ["11,12","17,12"])
        await_state("two modeled accepting loading stops",stops_ok)
        slot(2);click()
        await_state("road tools opened",lambda s:s.get("menu")=="roads")
        slot(1);aim(12,13)
        click()
        choose("luanttd_core:service","depot_buy_mail","postal-van-purchase")
        await_state("bought the actual van",lambda s:s.get("engine")=="mail_van")
        choose("luanttd_core:service","service_pick","postal-orders")
        for x in (11,17):
            aim(x,12);click()
        click(3)
        choose("luanttd_core:service","service_toggle","postal-dispatch")
        p=await_state("mail has a mesh, boards and pays",lambda s:s.get("postal_mesh") and s.get("paid_units",0)>0,50)
        screenshot("postal-service")
        stop_server()
        join("mail-reload")
        q=await_state("loaded mail route pays after restart",lambda s:s.get("paid_units",0)>p["paid_units"],45)
        (out/"postal-service.json").write_text(json.dumps({"before":p["paid_units"],"after":q["paid_units"],
          "mesh":p["postal_mesh"],"stops":p["postal_stops"],
          "stock_loading":q.get("road_stock_loading"),"shared_tick":q.get("stock_loading_tick"),
          "arrival_tick":q.get("last_road_arrival_tick"),"departure_tick":q.get("last_road_departure_tick"),
          "fare":q.get("fare")},indent=2))
        if os.environ.get("BAYLINE_NATIVE_STOCK_LOADING")=="1":
            assert p.get("road_stock_loading") and q.get("road_stock_loading")
            assert q["stock_loading_tick"]==q["house_tick"]>p["stock_loading_tick"]
            assert q["fare"]["tick"]>0 and q["fare"]["units"]>0
        stop_server()
        print(f"PASS: native stock-priced mail route and van resumed in {out}.")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_PAID_RAIL")=="1":
        phase="build stock rail and ferry connections sharing source town households"
        chat("/qa_dispatch_layout")
        chat("/pathsignal 3 5 west")
        chat("/shipyard dock 18 8")
        chat("/shipyard dock 18 16")
        chat("/shipyard depot 22 10 x")
        chat("/ferrypilot 22 10 18 8 18 16")
        chat("/railshuttle 2 5 13 5 5 5")
        chat("/qa_dispatch_photo")
        chat("/qa_dispatch_go")
        def earned(s):
            r=(s.get("dispatch_view") or {}).get("paid") or {}
            f=(s.get("ship_view") or {}).get("paid") or {}
            return r.get("fare",0)>0 and f.get("fare",0)>0
        first=await_state("both paid stock modes settle live without duplicating houses",earned,105)
        rail=first["dispatch_view"]["paid"]
        ferry=first["ship_view"]["paid"]
        assert rail["tick"]==ferry["tick"]==first["ship_view"]["house_tick"]==first["ship_view"]["stock_tick"]
        assert rail["fare"]+ferry["fare"]==first["ship_view"]["revenue"]
        assert rail["delivered"]+ferry["delivered"]==first["ship_view"]["paid_units"]
        assert rail["capacity"]==40 and first["dispatch_view"]["drawing"]==2,first["dispatch_view"]
        screenshot("01j-paid-coupled-train")
        phase="continued revenue after shared paid vehicle world restart"
        stop_server()
        restored=join("paid-rail-reloaded")
        rv=restored["dispatch_view"]["paid"];fv=restored["ship_view"]["paid"]
        assert rv["fare"]>=rail["fare"] and fv["fare"]>=ferry["fare"]
        after=await_state("rail and ferry both settle more passengers after restart",lambda s:
            (((s.get("dispatch_view") or {}).get("paid") or {}).get("fare",0)>rv["fare"] and
             ((s.get("ship_view") or {}).get("paid") or {}).get("fare",0)>fv["fare"]),95)
        a=after["dispatch_view"]["paid"];b=after["ship_view"]["paid"]
        assert a["fare"]+b["fare"]==after["ship_view"]["revenue"] and a["tick"]==b["tick"]
        (out/"rail-paid-native.json").write_text(json.dumps(dict(first=first,restored=restored,after=after),indent=2))
        stop_server()
        print(f"PASS: native paid coupled shuttle and ferry earn fares on one stock clock through restart: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_BUOY")=="1":
        phase="place native public buoy using the real Harbor toolbar"
        marker=(19,12)
        dock1,dock2,depot=(8,9),(8,16),(12,10)
        chat("/qa_ship_photo buoy_order")
        for command in ("/shipyard dock 8 9","/shipyard dock 8 16","/shipyard depot 12 10 x"):
            chat(command)
        await_state("two docks and a ship depot",lambda s:
            (s.get("ship_view") or {}).get("docks")==2 and s["ship_view"]["depots"]==1)
        slot(10);click();await_state("Sea & Air",lambda s:s.get("menu")=="portair")
        slot(2);click();await_state("Harbors",lambda s:s.get("menu")=="harbor")
        slot(4);click();await_state("Waterworks",lambda s:s.get("menu")=="waterworks")
        slot(6);aim(*marker);baseline=state()["cash"];click()
        planted=await_state("original buoy mesh with a public navigation record",lambda s:
            s["ship_view"].get("buoy") and s["ship_view"]["buoy_mesh"]=="luanttd_core:ship_buoy")
        assert baseline-planted["cash"]==350
        slot(7);click()
        cleared=await_state("standalone buoy removed without changing water",lambda s:not s["ship_view"].get("buoy"))
        assert planted["cash"]-cleared["cash"]==50
        slot(6);aim(*marker);click()
        buoy=await_state("buoy ready again",lambda s:s["ship_view"].get("buoy"))["ship_view"]["buoy"]
        chat("/qa_ship_photo buoy");time.sleep(1)
        screenshot("01-public-buoy-original-mesh")
        chat("/qa_ship_photo buoy_order")
        slot(8);click();await_state("Back to Harbors",lambda s:s.get("menu")=="harbor")
        slot(7);click();await_state("Ferry Operations",lambda s:s.get("menu")=="harbor_ops")
        slot(2);click();slot(1)
        for pos in (depot,dock1,marker,dock2):
            aim(*pos);click()
        slot(8);click()
        ordered=await_state("buoy is a saved ferry route waypoint",lambda s:
            s["ship_view"].get("via",{}).get("id")==buoy and s["ship_view"]["phase"]=="depot")
        slot(8);click();await_state("Back to Harbors",lambda s:s.get("menu")=="harbor")
        slot(4);click();await_state("Back to Waterworks",lambda s:s.get("menu")=="waterworks")
        slot(7);aim(*marker);click()
        assert state()["ship_view"]["buoy"]==buoy and state()["cash"]==ordered["cash"]
        phase="save paid sailing at distance four, before the stock waypoint advance"
        chat("/qa_ship_photo go")
        stopped=await_state("ferry arrives at the four-tile reload checkpoint",lambda s:
            s["ship_view"].get("buoy_stop"),100)["ship_view"]
        assert stopped["buoy_stop"]["distance"]==4 and stopped["via"]["passes"]==0
        assert not stopped.get("pass") and (stopped["order"] or {}).get("kind")=="waypoint"
        stop_server()
        restored=join("buoy-paid-reloaded")["ship_view"]
        assert restored["buoy_stop"]==stopped["buoy_stop"] and restored["via"]==stopped["via"]
        chat("/qa_ship_photo go")
        final=await_state("the boat passes the marker and earns a real dock fare after reload",lambda s:
            (s["ship_view"].get("paid") or {}).get("fare",0)>0 and s["ship_view"].get("via",{}).get("passes",0)>=1,100)["ship_view"]
        assert final["pass"]["distance"]==3 and final["pass"]["speed"]>0
        assert final["paid"]["delivered"]>0 and final["paid"]["fare"]==final["revenue"]
        chat("/qa_ship_photo ferry");time.sleep(.8);screenshot("02-ferry-paid-after-buoy-route-reload")
        (out/"buoy-paid-native.json").write_text(json.dumps(
            {"pre_threshold":stopped,"restored":restored,"paid":final},indent=2))
        stop_server()
        print(f"PASS: native buoy placement/removal, referenced protection, saved stock three-tile passage and paid ferry: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_PAID_FERRY")=="1":
        phase="build and dispatch a paid ferry between two real source house catchments"
        chat("/qa_ship_photo pay")
        chat("/shipyard dock 8 9")
        chat("/shipyard dock 8 16")
        chat("/shipyard depot 12 10 x")
        chat("/ferrypilot 12 10 8 9 8 16")
        first=await_state("actual ferry boards through source station service and earns revenue",
            lambda s:(((s.get("ship_view") or {}).get("paid") or {}).get("fare",0)>0),85)["ship_view"]
        assert first["paid"]["boarded"]>0 and first["paid"]["delivered"]==first["paid_units"]
        assert first["paid"]["fare"]==first["revenue"]
        assert first["paid"]["tick"]==first["house_tick"]==first["stock_tick"]
        waiting=first["paid"]["waiting"]
        assert waiting and all(w["accepts"] for w in (waiting.values() if isinstance(waiting,dict) else waiting))
        if first.get("ferry"): assert abs(first["ferry"]["y"]-.5)<.02
        screenshot("01h-paid-passenger-ferry")
        phase="reopen the paid ferry and resolve its next cargo transactions"
        stop_server()
        reopened=join("paid-ferry-reloaded")["ship_view"]
        assert reopened["paid"]["fare"]>=first["paid"]["fare"] and reopened["fleet_tick"]>=first["fleet_tick"]
        chat("/qa_ship_photo ferry")
        after=await_state("next actual paid trip after SQLite restart",lambda s:
           (((s.get("ship_view") or {}).get("paid") or {}).get("fare",0)>reopened["paid"]["fare"]),75)["ship_view"]
        assert after["paid"]["delivered"]>reopened["paid"]["delivered"] and after["paid"]["fare"]==after["revenue"]
        assert after["paid"]["tick"]==after["house_tick"]==after["stock_tick"]
        (out/"ferry-paid-native.json").write_text(json.dumps(dict(first=first,reopened=reopened,after=after),indent=2))
        stop_server()
        print(f"PASS: source paid ferry board, unload, settle and continue after native restart: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_AIR_FLEET")=="1":
        phase="build three ordinary country airports by mouse and buy two distinct aircraft"
        a,hub,b=(7,12),(20,12),(30,11)
        slot(10);click();slot(3);click()
        await_state("real Airfields tools",lambda s:s.get("menu")=="airfields")
        slot(2)
        for i,at in enumerate((a,hub,b),1):
            aim(*at);click()
            await_state(f"built ordinary twelve-tile airfield {i}",lambda s:s["air_fleet"]["airports"]==i)
        for i,point in enumerate(((10,12),(33,11)),1):
            slot(1);aim(*point);click()
            choose("luanttd_core:service","buy_aircraft_215",f"air-fleet-{i}-native-hangar")
            receipt=await_state(f"owned aircraft {i} purchased into its distinct hangar",
                 lambda s:len(s["air_fleet"]["owned"] or [])==i)["air_fleet"]
            assert receipt["expense"]==3*7200+i*38281
            assert receipt["owned"][-1]["hangar"]==(1 if i==1 else 3)
            xdo("key","Escape")
        phase="order real origins to a shared stock field with both aircraft idle"
        for o in (b,a):
            slot(3);click();slot(1)
            aim(*o);click();aim(*hub);click();slot(8);click()
        ready=await_state("two exact routes filed against the same country field",lambda s:
           len(s["air_fleet"]["runs"] or [])==2)["air_fleet"]
        assert [p["first"] for p in ready["runs"]]==[1,3]
        assert all(p["second"]==2 and p["phase"]=="hangar" for p in ready["runs"])
        chat("/qa_air_fleet go")
        phase="stock holding and runway movement"
        holding=await_state("one plane has waited for original shared runway blocks",lambda s:
           (s["air_fleet"].get("timed") or {}).get("tick"),75)["air_fleet"]
        assert any(p["holds"]>0 for p in holding["runs"])
        chat("/qa_air_fleet photo");time.sleep(.7)
        screenshot("01aa-two-owned-aircraft-runway")
        stop_server()
        opened=join("owned-air-fleet-restarted")["air_fleet"]
        assert opened["timed"]==holding["timed"]
        for i in range(2):
            for k in ("x","y","z","tick","phase"):
                assert opened["runs"][i][k]==holding["timed"]["runs"][i][k]
        chat("/qa_air_fleet go")
        phase="both real paying aircraft share cargo clocks and continue"
        def both_paid(s):
            d=s["air_fleet"]
            runs=d.get("runs") or []
            return len(runs)==2 and all(p.get("stats",{}).get("fare",0)>0 for p in runs)
        paid=await_state("both distinct real aircraft earned a fare",both_paid,190)["air_fleet"]
        assert sum(p["stats"]["delivered"] for p in paid["runs"])==paid["paid"]
        assert sum(p["stats"]["fare"] for p in paid["runs"])==paid["money"]
        assert all(p["stats"]["tick"]==paid["world_tick"] and p["stats"]["running_expense"]>0 for p in paid["runs"])
        slot(10);click();slot(3);click()
        await_state("Airfields re-opened after restart",lambda s:s.get("menu")=="airfields")
        slot(1);aim(22,13);click()
        await_state("shared inspector lists both quoted flights",lambda s:s.get("form")=="luanttd_core:service")
        screenshot("02aa-two-owned-aircraft-shared-fares")
        (out/"air-owned-fleet-desktop.json").write_text(json.dumps(dict(bought=receipt,ready=ready,
          waiting=holding,reopened=opened,paid=paid),indent=2))
        stop_server()
        print(f"PASS: two native purchased Sampsons, world routes, stock runway conflict, exact saved poses and paid service: {out}")
        sys.exit(0)

    air_paid=os.environ.get("BAYLINE_NATIVE_PAID_AIR")=="1"
    air_owned=air_paid and os.environ.get("BAYLINE_NATIVE_OWNED_AIR")=="1"
    bakewell=air_owned and os.environ.get("BAYLINE_NATIVE_BAKEWELL")=="1"
    plane_id,plane_seats,plane_art=(219,30,"bakewell_cotswald") if bakewell else (216,65,"coleman_count")
    if air_paid or os.environ.get("BAYLINE_NATIVE_AIRFIELD")=="1":
        one,two=((7,12),(20,12)) if air_paid else ((7,16),(30,16))
        if air_paid:
            chat("/qa_airfield_photo depart")
        phase="use native mouse and paid twelve-tile airport footprint on the regular map"
        slot(10);click();slot(3);click()
        await_state("Airfields opened",lambda s:s.get("menu")=="airfields")
        slot(2);aim(*one)
        await_state("all twelve stock airfield tiles are outlined before placement",lambda s:s.get("air_view",{}).get("outlines")==12)
        screenshot("00g-country-airfield-footprint")
        click()
        await_state("built first twelve-tile country airfield",lambda s:
            (s.get("air_view") or {}).get("fields")==1)
        aim(*two);click()
        both=await_state("purpose-built hangar and both runway ends",lambda s:
            (s.get("air_view") or {}).get("fields")==2 and
            (s["air_view"].get("academy") or {}).get("runway_east")=="luanttd_core:small_airport_3_2",15)["air_view"]
        assert both["academy"]["hangar"]=="luanttd_core:small_airport_3_0" and both["academy"]["runway_west"]=="luanttd_core:small_airport_0_2"
        if air_owned:
            phase="buy a stock aircraft directly from its purchased country hangar"
            slot(1);aim(10,12);click()
            choose("luanttd_core:service",f"buy_aircraft_{plane_id}",f"00h-{plane_art}-priced-hangar")
            purchase=await_state("bought the stock aircraft into this hangar",lambda s:
              ((s.get("air_view") or {}).get("owned") or {}).get("stock_id")==plane_id)["air_view"]
            assert purchase["owned"]["status"]=="hangar" and purchase["owned"]["hangar"]==1
            assert purchase["owned"]["price"]==41015 and both["cash"]-purchase["cash"]==41015
            assert purchase["expense"]-both["expense"]==41015
            xdo("key","Escape")
        slot(3);click();slot(1);aim(*one);click();aim(*two);click();slot(8);click()
        if bakewell:
            chat("/qa_air_fleet go") # fixture pauses the clock, real controls filed the route
        mid=await_state("actual original aircraft in source-controlled flight",lambda s:
            (s.get("air_view") or {}).get("mid"),35)["air_view"]["mid"]
        assert mid["mesh"]["y"]>6 and mid["vehicle"]["target"]==2
        chat("/qa_airfield_photo flight")
        time.sleep(.6)
        screenshot("01g-trimotor-in-flight")
        phase="preserve airborne state through restart, land, taxi and fly back"
        stop_server()
        reload=join("airfield-reloaded")["air_view"]
        assert reload["mid"]==mid and reload["state"]==mid["vehicle"]
        if air_owned:
            # Reload spawns the camera near the town, not in the high-air
            # mapblock containing the frozen aircraft. Load its live view.
            chat("/qa_airfield_photo flight")
            flight=await_state("original aircraft mesh changes gear on source climb",lambda s:
              (s.get("air_view") or {}).get("model")==f"bl_{plane_art}_flight.obj")["air_view"]
            assert flight["engine"]==plane_id and flight["paid"]["running_expense"]>0
        chat("/qa_airfield_photo runway")
        chat("/qa_airfield_resume")
        first=await_state("actual aircraft taxis into its destination passenger stand",
            lambda s:(s.get("air_view") or {}).get("arrivals")==1 and s["air_view"].get("aircraft"),55)["air_view"]
        assert first["last"]==2 and abs(first["aircraft"]["y"]-.5)<.035,first
        if air_owned:
            assert first["engine"]==plane_id and first["model"]==f"bl_{plane_art}.obj",first
            assert first["paid"]["capacity"]==plane_seats and first["owned"]["status"]=="dispatched"
        screenshot("02g-country-airfield-arrival")
        final=await_state("aircraft returns to the other field and lands",
            lambda s:(s.get("air_view") or {}).get("arrivals",0)>=2,55)["air_view"]
        assert final["last"]==1 and final["departures"]>=2
        if air_paid:
            phase="observe source terminal passenger delivery and finances"
            fares=await_state("paid true air terminal and shared town economy",
                lambda s: (((s.get("air_view") or {}).get("paid") or {}).get("fare",0)>0),100)["air_view"]
            assert fares["terminal_valid"] and fares["paid"]["tick"]==fares["house_tick"]
            assert fares["paid"]["fare"]==fares["revenue"] and fares["paid"]["delivered"]==fares["paid_units"]
            assert fares["paid"]["boarded"]>0
            screenshot("03g-paid-air-service")
            stop_server()
            paid_restored=join("paid-airfield-reloaded")["air_view"]
            assert paid_restored["paid"]["fare"]>=fares["paid"]["fare"]
            eventually=await_state("a further paying trip after SQLite restart",lambda s:
                (((s.get("air_view") or {}).get("paid") or {}).get("fare",0)>paid_restored["paid"]["fare"]),
                105)["air_view"]
            assert eventually["paid"]["delivered"]>paid_restored["paid"]["delivered"]
            assert eventually["paid"]["fare"]==eventually["revenue"] and eventually["terminal_valid"]
            if air_owned:
                assert eventually["paid"]["capacity"]==plane_seats
                assert eventually["paid"]["charged_running_ticks"]>paid_restored["paid"]["charged_running_ticks"]
                assert eventually["paid"]["running_expense"]>paid_restored["paid"]["running_expense"]
                assert eventually["owned"]==paid_restored["owned"]
            (out/("air-owned-desktop.json" if air_owned else "air-paid-native.json")).write_text(json.dumps(dict(
                mid=mid,loaded=reload,first=fares,paid_restored=paid_restored,after=eventually,
                purchased=purchase if air_owned else None,gear_up=flight if air_owned else None),indent=2))
            stop_server()
            print(f"PASS: order by native mouse, real air service clock and passenger fares across saves: {out}")
            sys.exit(0)
        names=[e["kind"] for e in final["events"]]
        assert names.count("takeoff")>=2 and names.count("touchdown")>=2
        (out/"airfield-native.json").write_text(json.dumps(dict(mid=mid,loaded=reload,first=first,final=final),indent=2))
        stop_server()
        print(f"PASS: actual airfield construction and runway blocks; native takeoff, airborne reload, landing and return: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_LOCK")=="1":
        phase="place a stock three-tile lock between two water levels"
        chat("/qa_ship_photo lock")
        slot(10);click();slot(2);click()
        await_state("Harbor hotbar",lambda s:s.get("menu")=="harbor")
        slot(4);click()
        await_state("Waterworks submenu",lambda s:s.get("menu")=="waterworks")
        slot(3);aim(22,20);click()
        await_state("built native middle lock tile at the true incline",
           lambda s:(s.get("ship_view") or {}).get("lock_mesh")=="luanttd_core:ship_lock_middle_2",25)
        chat("/shipyard dock 17 18")
        chat("/shipyard dock 28 18")
        chat("/shipyard depot 15 21 x")
        chat("/ferrypilot 15 21 17 18 28 18")
        mid=await_state("ferry and separate water mesh lift inside both closed gates",
            lambda s:(s.get("ship_view") or {}).get("midwater"),65)["ship_view"]["midwater"]
        assert mid["gates"]==2 and 0<mid["phase"]<1 and 0<mid["stock"]<8,mid
        assert abs(mid["pool"]["y"]-mid["ferry"]["y"])<.02,mid
        chat("/qa_ship_photo lock")
        screenshot("01f-native-ferry-rising-in-lock")
        phase="restart while the ferry is inside the raised lock"
        stop_server()
        loaded=join("lock-reloaded")["ship_view"]
        assert loaded["midwater"]==mid and loaded["lock"]["phase"]==mid["phase"]
        chat("/qa_ship_photo lock")
        chat("/qa_lock_resume")
        finished=await_state("ferry completes upward and downward traversals after restart",
            lambda s:(s.get("ship_view") or {}).get("arrivals",0)>=3,75)["ship_view"]
        assert finished["last_dock"]==1
        assert any(p["dir"]==1 for p in finished["levels"].values()) and any(
            p["dir"]==5 for p in finished["levels"].values())
        (out/"lock-native.json").write_text(json.dumps(dict(mid=mid,loaded=loaded,finished=finished),indent=2))
        stop_server()
        print(f"PASS: 3D lock built with the hotbar, actual ferry and water lift, restart, downhill return: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_AQUEDUCT")=="1":
        phase="build paired aqueduct over independent river and road"
        chat("/qa_ship_photo aqueduct")
        chat("/shipyard aqueduct 20 20 24 20")
        made=await_state("span mesh with the unmodified river and road underneath",
            lambda s:(s.get("ship_view") or {}).get("span")=="luanttd_core:aqueduct_span_0",20)["ship_view"]
        assert made["aqueduct"]==1 and "water" in made["river"] and "road" in made["road"],made
        chat("/shipyard canal 19 20 19 20")
        await_state("stock-built canal connects the dry west head",
            lambda s:(s.get("ship_view") or {}).get("canal")=="canal",15)
        chat("/shipyard dock 17 18")
        chat("/shipyard dock 28 18")
        chat("/shipyard depot 15 21 x")
        chat("/ferrypilot 15 21 17 18 28 18")
        first=await_state("native ferry crosses the aqueduct waterline rather than the low river",
            lambda s:(s.get("ship_view") or {}).get("crossed"),55)["ship_view"]
        assert abs(first["crossed"]["position"]["y"]-1.5)<.02 and first["crossed"]["level"]==8,first
        screenshot("01e-ferry-in-elevated-aqueduct")
        reached=await_state("ferry reaches the second dock on the far bank",
            lambda s:(s.get("ship_view") or {}).get("arrivals",0)>=2,35)["ship_view"]
        assert reached["last_dock"]==2
        (out/"aqueduct-native.json").write_text(json.dumps(dict(constructed=made,crossed=first["crossed"],reached=reached),indent=2))
        stop_server()
        print(f"PASS: native ferry uses stock paired aqueduct heads above a separate river and road: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_SHIP_COAL")=="1":
        phase="mouse-build genuine facilities on the default seed South Coast"
        dock_mine,dock_plant,depot=(8,32),(5,32),(12,34)
        await_state("South Coast coal scenario mounted",lambda s:
            (s.get("yate") or {}).get("enabled") and s["yate"].get("coast")=="south_coast_1751")
        chat("/qa_yate survey")
        await_state("coastal camera moved",lambda s:(s["camera"]["pos"] or {}).get("x")==17)
        time.sleep(.65)
        slot(10);click();slot(2);click()
        await_state("Harbor hotbar",lambda s:s.get("menu")=="harbor")
        slot(2);aim(*dock_mine);click()
        await_state("mine dock physically built",lambda s:(s.get("ship_view") or {}).get("docks")==1)
        aim(*dock_plant);click()
        slot(3);aim(*depot);click()
        await_state("both docks and working depot",lambda s:
            (s.get("ship_view") or {}).get("docks")==2 and s["ship_view"]["depots"]==1)
        initial=state()["cash"]
        slot(1);aim(*depot);click()
        choose("luanttd_core:service","buy_yate","00v-native-yate-purchase")
        quote=await_state("stock cargo vessel receipt charges purchase once",lambda s:
            (s["yate"].get("vessel") or {}).get("cargo")==5 and "refit_yate" in (s.get("buttons") or {}))
        assert quote["yate"]["vessel"]["engine"]==211 and quote["cash"]==initial-32500
        choose("luanttd_core:service","refit_yate","01v-refit-owned-yate")
        refitted=await_state("same owned ship now carries stock coal",lambda s:s["yate"]["vessel"].get("cargo")==1)
        assert refitted["cash"]==quote["cash"]-507
        choose("luanttd_core:service","service_back","01v-leave-yate-depot")
        slot(7);click()
        await_state("Vessel Operations",lambda s:s.get("menu")=="harbor_ops")
        slot(3);click();slot(1);aim(*dock_mine);click();aim(*dock_plant);click();slot(8);click()
        launch=await_state("two physical coal docks in its timetable",lambda s:
            (s["yate"].get("vessel") or {}).get("mine")==1 and s["yate"]["vessel"].get("power")==2)
        assert launch["yate"]["vessel"]["capacity"]==160
        chat("/qa_yate go")
        phase="genuine 3D Yate loads in a parallel berth and saves loaded"
        first=await_state("coal loaded on the ship at a genuine wet berth",lambda s:
            s["yate"].get("loaded") and s["yate"].get("model")=="bl_yate_cargo_ship.obj",125)["yate"]
        assert 10<=first["loaded"]["units"]<160 and abs(first["loaded"]["mesh"]["y"]-.5)<.018
        assert first["received"]==0 and first["loaded"]["berth"]
        chat("/qa_yate loaded");time.sleep(.7);screenshot("02v-real-yate-waterline-loading")
        stop_server()
        after=join("stock-yate-reloaded")["yate"]
        assert after["loaded"]==first["loaded"] and after["vessel"]["onboard"]==first["vessel"]["onboard"]
        chat("/qa_yate go")
        phase="ship completes full cargo and plant processes a real paid 160-ton shipment"
        end=await_state("real power receiver has the first full cargo and genuine fare",lambda s:
            s["yate"]["received"]>=160 and s["yate"]["vessel"]["delivered"]>=160 and
            s["yate"]["vessel"]["fare"]>0 and s["yate"].get("model")=="bl_yate_cargo_ship.obj",180)["yate"]
        assert end["vessel"]["delivered"]==160==end["received"] and end["vessel"]["running_expense"]>0
        assert end["vessel"]["tick"]==end["tick"]
        chat("/qa_yate plant");time.sleep(.65);screenshot("03v-coal-delivered-to-south-coast")
        (out/"yate-coal-desktop.json").write_text(json.dumps({"initial":first,"restored":after,"after":end},indent=2))
        stop_server()
        print("PASS: genuine South Coast yard, two docks, bought/refitted stock #211, SQLite restore and paid 160-ton delivery.")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_SHIP")=="1":
        phase="complete stock docks and depot on the default seeded coastline"
        chat("/qa_ship_photo east")
        slot(10);click();slot(2);click()
        await_state("Harbor hotbar opened",lambda s:s.get("menu")=="harbor")
        slot(2);aim(5,32);click()
        await_state("first pair built from the world view",lambda s:(s.get("ship_view") or {}).get("docks")==1)
        aim(8,32);click()
        slot(3);aim(11,35);click()
        facilities=await_state("two docks and both halves of the ship depot",
            lambda s:(s.get("ship_view") or {}).get("docks")==2 and
                      s["ship_view"]["depots"]==1 and s["ship_view"].get("nodes",{}).get("shed"),20)["ship_view"]
        assert facilities["nodes"]["shore"]=="luanttd_core:ship_dock_ramp_1",facilities
        assert facilities["nodes"]["pier"]=="luanttd_core:ship_dock_pier_1",facilities
        assert facilities["nodes"]["shed"]=="luanttd_core:ship_depot_0_0",facilities
        slot(7);click()
        await_state("Ferry Operations hotbar",lambda s:s.get("menu")=="harbor_ops")
        slot(2);click();slot(1);aim(11,35);click();aim(5,32);click();aim(8,32);click();slot(8);click()
        sail=await_state("deck and hull move on the water datum from the depot",
            lambda s:(s.get("ship_view") or {}).get("phase")=="sailing" and s["ship_view"].get("ferry"),35)["ship_view"]
        assert abs(sail["ferry"]["y"]-.5)<.012,sail
        first=await_state("ferry uses a navigable adjacent berth rather than the pier tile",
            lambda s:(s.get("ship_view") or {}).get("arrivals",0)>=1 and s["ship_view"].get("ferry"),30)["ship_view"]
        assert first["last_dock"]==1 and first["steps"]>20,first
        chat("/qa_ship_photo ferry")
        time.sleep(.40)
        screenshot("01c-native-ferry-waterline")
        phase="restart the charted ferry"
        stop_server()
        reload=join("ferry-reloaded")["ship_view"]
        assert reload["arrivals"]>=first["arrivals"] and reload["docks"]==2
        chat("/qa_ship_photo east")
        after=await_state("native ferry reaches the far dock after reload and keeps running",
            lambda s:(s.get("ship_view") or {}).get("arrivals",0)>=4 and s["ship_view"].get("ferry"),55)["ship_view"]
        assert after["steps"]>reload["steps"] and after["last_dock"]==2
        screenshot("02c-native-ferry-reload")
        (out/"ferry-pilot.json").write_text(json.dumps(dict(facilities=facilities,first=first,reloaded=reload,after=after),indent=2))
        stop_server()
        print(f"PASS: seed coastline facilities, real ferry waterline and arrival at both docks after restart: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_CROSSING")=="1":
        phase="install a real native crossing across the existing road by mouse"
        chat("/qa_crossing prepare")
        await_state("disconnected railway and active road geometry",
            lambda s:s.get("crossing_view",{}).get("ready"))
        slot(8);click()
        await_state("Railworks",lambda s:s.get("menu")=="railworks")
        rail_engineering()
        initial=state()["cash"]
        slot(4);aim(14,12);click()
        opened=await_state("actual open arms and ordinary source cost",lambda s:
            (s.get("crossing_view") or {}).get("mesh")=="luanttd_core:level_crossing_1_open")
        assert opened["cash"]==initial-100
        time.sleep(.7);screenshot("00n-level-crossing-open")
        chat("/qa_crossing arrange")
        road=await_state("one real bus has a committed frame on the crossing",lambda s:
            s["crossing_view"].get("checked_road_tile")==s["crossing_view"]["cross_tile"])["crossing_view"]
        leave_rail_engineering()
        slot(7);click()
        await_state("Rail Operations",lambda s:s.get("menu")=="railops")
        slot(2);click();slot(1);aim(14,4);click();aim(14,18);click();slot(8);click()
        await_state("a real two-part train assigned to the far platform",lambda s:
            s["crossing_view"].get("train")=="depot")
        chat("/qa_crossing go")
        phase="watch the real train yield to a road vehicle already inside"
        def physical_gap(bus,rail,width,length):
            # Exact half-bounds of the released cardinal mesh envelopes,
            # mapped to node units by the actual visual scales.
            return max(abs(bus["x"]-rail["x"])-.342511-width,
                       abs(bus["z"]-rail["z"])-.13398-length)
        held=await_state("train waits and red arms are lowered",lambda s:
            s["crossing_view"].get("held") and s["crossing_view"].get("gate")=="road_draining" and
            s["crossing_view"].get("mesh")=="luanttd_core:level_crossing_1_closed" and
            s["crossing_view"].get("road_mesh") and s["crossing_view"].get("engine_mesh"),45)["crossing_view"]
        assert held["checked_road_tile"]==held["cross_tile"]
        assert physical_gap(held["road_mesh"],held["engine_mesh"],.2665,.4752)>.04,held
        time.sleep(.7);screenshot("01n-level-crossing-train-yields")
        stop_server()
        resumed=join("crossing-reloaded")["crossing_view"]
        assert resumed["held"]==held["held"] and resumed["clock"]==held["clock"]
        chat("/qa_crossing queue")
        queued=await_state("second road bus refuses the red gate while first drains",lambda s:
            s["crossing_view"].get("denied"))["crossing_view"]
        assert queued["opposite"]!=queued["cross_tile"] and queued["barred"]
        chat("/qa_crossing release")
        tail=await_state("gate still closed for the rear carriage after the engine left",lambda s:
            s["crossing_view"].get("tail") and s["crossing_view"].get("gate")=="rail_occupied" and
            s["crossing_view"].get("mesh")=="luanttd_core:level_crossing_1_closed" and
            s["crossing_view"].get("road_mesh") and s["crossing_view"].get("wagon_mesh"),45)["crossing_view"]
        assert physical_gap(tail["road_mesh"],tail["wagon_mesh"],.261,.499)>.04,tail
        time.sleep(.7);screenshot("02n-level-crossing-tail-holds")
        chat("/qa_crossing finish")
        end=await_state("both modes proceed after the wagon clears and gate reopens",lambda s:
            s["crossing_view"].get("arrived") and s["crossing_view"].get("target_station")==s["crossing_view"]["destination"] and
            s["crossing_view"].get("gate")=="open",50)["crossing_view"]
        (out/"level-crossing-native.json").write_text(json.dumps(dict(
            opened=opened["crossing_view"],held=held,resumed=resumed,queued=queued,tail=tail,after=end),indent=2))
        stop_server()
        print(f"PASS: mouse-built actual crossing, saved road yield, red tail hold, reopened for road and rail: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_RAIL_SPAN")=="1":
        phase="build actual railway bridge and tunnel from the three-dimensional hotbar"
        chat("/qa_rail_span prepare")
        await_state("prepared real depots, railhead and opposite hill slopes",
            lambda s:s.get("rail_span_view",{}).get("ready"))
        slot(8);click()
        await_state("Railworks",lambda s:s.get("menu")=="railworks")
        slot(10);native_aim(5,10,4.5);click();native_aim(9,10,4.5);click()
        if state().get("form")=="luanttd_core:bridge_picker":
            choose_bridge_type()
        bridge=await_state("stock timber trestle terraced and drawn",lambda s:
            (s.get("rail_span_view",{}).get("routes") or {}).get("bridge") and
            (s["rail_span_view"].get("meshes") or {}).get("deck")=="luanttd_core:stock_rail_bridge_wood_span_0")
        assert bridge["rail_span_view"]["routes"]["bridge"]["level"]==5
        assert bridge["rail_span_view"]["meshes"]["pier"]=="luanttd_core:stock_rail_bridge_wood_pier_0"
        chat("/qa_rail_span rail")
        slot(6);native_aim(13,10,5.0);click()
        tunnel=await_state("true masonry portals at both ends",lambda s:
            (s.get("rail_span_view",{}).get("routes") or {}).get("tunnel") and
            (s["rail_span_view"].get("meshes") or {}).get("exit")=="luanttd_core:stock_rail_tunnel_portal_0")
        assert tunnel["rail_span_view"]["routes"]["tunnel"]["level"]==4
        slot(7);click()
        await_state("Rail Operations",lambda s:s.get("menu")=="railops")
        slot(4);click();slot(1);native_aim(2,10,4.5);click();native_aim(22,10,4.5);click();slot(8);click()
        await_state("real consist ordered through both spans",lambda s:s["rail_span_view"]["phase"]=="depot")
        chat("/qa_rail_span go")
        first=await_state("loaded rail span carries both actual train assets",lambda s:s["rail_span_view"].get("mid"),35)["rail_span_view"]
        assert abs(first["mid"]["head"]["y"]-5.612)<.035
        chat("/qa_rail_span deck")
        time.sleep(.55);screenshot("01m-rail-wood-span-live")
        phase="restore stock bridge motion and continue through a real rail tunnel"
        stop_server()
        reopened=join("rail-span-reloaded")["rail_span_view"]
        assert reopened["mid"]==first["mid"] and reopened["clock"]==first["mid"]["clock"]
        chat("/qa_rail_span tunnel")
        await_state("both train meshes visible at exit portal",lambda s:
            s["rail_span_view"].get("exit_visible") and s["rail_span_view"].get("head") and s["rail_span_view"].get("tail"),40)
        screenshot("02m-rail-tunnel-mouth-live")
        chat("/qa_rail_span final")
        end=await_state("real train emerges from the tunnel and reaches the platform",
            lambda s:s["rail_span_view"]["phase"]=="arrived",50)["rail_span_view"]
        tags={e["kind"] for e in end["events"]}
        assert {"span_exited","span_released","tunnel_hidden","tunnel_revealed","arrived"}<=tags and not end.get("failure"),end
        (out/"rail-span-native.json").write_text(json.dumps(dict(first=first,reopened=reopened,after=end),indent=2))
        stop_server()
        print(f"PASS: native mouse-built rail spans, real rolling stock on bridge, saved, hidden/revealed and arrived: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_RAIL_BUILD")=="1":
        phase="build all railway pieces from native hotbars"
        slot(8);click()
        await_state("Railworks",lambda s:s.get("menu")=="railworks")
        slot(4);aim(3,9);click()
        depot=await_state("stock depot on bare grass before connecting track",
            lambda s:(s.get("rail_work") or {}).get("depot")==1)
        assert depot["rail_work"]["track"]==1 and depot["cash"]==100000-720,depot
        slot(2);hold_to_build(aim,(4,9),(16,9))
        track=await_state("a paid thirteen-tile straight drag",
            lambda s:(s.get("rail_work") or {}).get("track")==14)
        assert track["cash"]==depot["cash"]-1560,track
        slot(3);aim(14,9);click();aim(16,9);click()
        station=await_state("platform overlays three compatible owned track tiles",
            lambda s:(s.get("rail_work") or {}).get("platforms")==1)
        assert station["cash"]==track["cash"]-1050
        slot(5);click()
        await_state("Path Signals submenu",lambda s:s.get("menu")=="railsignals")
        slot(2);aim(6,9);click()
        signal_state=await_state("real directional path lamp placed from the view",
            lambda s:(s.get("rail_work") or {}).get("signals")==1)
        assert signal_state["cash"]==station["cash"]-65,signal_state
        screenshot("01k-railworks-paid-layout")
        slot(8);click()
        await_state("Back to Railworks",lambda s:s.get("menu")=="railworks")
        slot(7);click()
        await_state("Rail Operations submenu",lambda s:s.get("menu")=="railops")
        slot(2);click();slot(1);aim(3,9);click();aim(15,9);click();slot(8);click()
        await_state("Native depot-to-platform order",lambda s:(s.get("dispatch_view") or {}).get("waiting")=="depot")
        chat("/tools")
        slot(4);click()
        await_state("Company hotbar opened",lambda s:s.get("menu")=="company")
        slot(6);click()
        arrived=await_state("real coupled train uses wholly mouse-built track and facilities",lambda s:
            (s.get("dispatch_view") or {}).get("waiting")=="arrived",35)["dispatch_view"]
        (out/"rail-construction-native.json").write_text(json.dumps(dict(
            cash={"depot":depot["cash"],"track":track["cash"],"platform":station["cash"],"signal":signal_state["cash"]},
            footage=signal_state["rail_work"],arrived=arrived),indent=2))
        stop_server()
        print(f"PASS: placed and paid for complete railway, depot, platform and path signal by native hotbars: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_RAIL_GRADE")=="1":
        phase="native coupled locomotive climbs and descends shared-corner rail grades"
        chat("/qa_dispatch_layout")
        chat("/raildispatch 3 9 15 9")
        chat("/qa_dispatch_photo")
        chat("/qa_dispatch_go")
        up=await_state("native locomotive physically pitched and climbing fixed stock grade",
            lambda s:((s.get("dispatch_view") or {}).get("grade") or {}).get("up"),35)["dispatch_view"]
        assert .62<up["grade"]["up"]["p"]["y"]<1.62 and 0<=up["grade"]["up"]["stock"]<=8
        assert abs(up["grade"]["up"]["pitch"]+math.atan(.5))<.018
        screenshot("01i-coupled-train-ascending")
        stop_server()
        reload=join("rail-grade-reloaded")["dispatch_view"]
        assert reload["grade"]["up"]==up["grade"]["up"] and reload["frozen"]==up["frozen"]
        chat("/qa_dispatch_go")
        done=await_state("locomotive descends and finishes on normal platform after reload",
            lambda s:(s.get("dispatch_view") or {}).get("waiting")=="arrived",40)["dispatch_view"]
        assert done["grade"].get("down") and abs(done["grade"]["down"]["pitch"]-math.atan(.5))<.018
        (out/"rail-grade-native.json").write_text(json.dumps(dict(before=up,loaded=reload,after=done),indent=2))
        stop_server()
        print(f"PASS: source rail height, native coupled climb and descent, and saved route completion: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_RAIL_SHUTTLE")=="1":
        phase="order one coupled train to shuttle between two platforms"
        chat("/qa_dispatch_layout")
        chat("/pathsignal 3 5 west")
        chat("/railshuttle 2 5 13 5 5 5")
        chat("/qa_dispatch_photo")
        chat("/qa_dispatch_go")
        flipped=await_state("first source locomotive-and-wagon reversal",
            lambda s:(s.get("dispatch_view") or {}).get("frozen"),35)["dispatch_view"]
        assert flipped["reversed"] and flipped["drawing"]==2,flipped
        screenshot("01d-native-stock-train-reversal")
        stop_server()
        reload=join("shuttle-reloaded")["dispatch_view"]
        assert reload["reversed"] and reload["stock_steps"]==flipped["stock_steps"]
        chat("/qa_dispatch_go")
        after=await_state("coupled shuttle alternates east, west, east after reload",lambda s:
            len([e for e in ((s.get("dispatch_view") or {}).get("events") or [])
                 if e["kind"]=="arrived"])>=3,45)["dispatch_view"]
        assert [e["station"] for e in after["events"] if e["kind"]=="arrived"][:3]==[2,1,2]
        assert len([e for e in after["events"] if e["kind"]=="reversed"])>=2
        (out/"rail-shuttle-native.json").write_text(json.dumps(dict(first=flipped,reloaded=reload,after=after),indent=2))
        stop_server()
        print(f"PASS: native coupled platform shuttle, both reversals and continuation from a reversed save: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_RAIL_DISPATCH")=="1":
        phase="place real path signals and dispatch two coupled trains"
        chat("/qa_dispatch_layout")
        time.sleep(.5)
        chat("/pathsignal 8 9 east oneway")
        chat("/pathsignal 9 8 south")
        chat("/raildispatch 3 9 15 9")
        chat("/raildispatch 9 4 9 15")
        chat("/qa_dispatch_photo")
        chat("/qa_dispatch_go")
        blocking=await_state("real locomotive and wagon objects, red PBS, tail-only crossing claim",
            lambda s:(s.get("dispatch_view") or {}).get("frozen"),40)["dispatch_view"]
        assert blocking["waiting"]=="waiting" and blocking["other"]=="running" and not blocking["head_on_crossing"],blocking
        assert blocking["wagon_on_crossing"] and blocking["signal"]=="red" and blocking["claim"]==2,blocking
        assert len(blocking["signs"])==2 and blocking["drawing"]==4,blocking
        screenshot("01b-last-wagon-holds-crossing")
        phase="restart with the crossing still locked by the rear wagon"
        stop_server()
        reload=join("dispatch-reloaded")["dispatch_view"]
        assert reload["frozen"]==blocking["frozen"] and reload["clock"]==blocking["clock"]
        assert reload["waiting"]=="waiting" and reload["wagon_on_crossing"] and reload["claim"]==2
        chat("/qa_dispatch_photo")
        chat("/qa_dispatch_go")
        finished=await_state("tail releases and both consists reach their own platforms",lambda s:
            (s.get("dispatch_view") or {}).get("waiting")=="arrived" and
            s["dispatch_view"].get("other")=="arrived",45)["dispatch_view"]
        crossing_events=finished["events"]
        tail=next(e for e in crossing_events if e["kind"]=="tail_released" and e["train"]==2)
        admitted=next(e for e in crossing_events if e["kind"]=="proceeded" and e["train"]==1)
        crossed=next(e for e in crossing_events if e["kind"]=="front_entered" and e["train"]==1)
        assert blocking["clock"]<tail["tick"]<=admitted["tick"]<crossed["tick"],crossing_events
        assert len([e for e in crossing_events if e["kind"]=="arrived"])==2
        (out/"rail-dispatch-native.json").write_text(json.dumps(dict(blocking=blocking,reloaded=reload,finished=finished),indent=2))
        stop_server()
        print(f"PASS: native coupled trains wait at a real path signal, preserve the rear wagon lock across restart, and both arrive: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_TRAM")=="1":
        phase="construct dedicated tramway from the native chat"
        slot(2);click();slot(7);click();slot(4);click()
        await_state("opened Tramways from the main hotbar",lambda s:s.get("menu")=="tramway")
        slot(4);aim(5,10);click()
        await_state("built directional depot in the 3D view",lambda s:s.get("tram",{}).get("count")==1)
        slot(2);hold_to_build(aim,(6,10),(8,10))
        await_state("laid priced track from the 3D view",lambda s:s.get("tram",{}).get("count")==4)
        for cmd,count in [("/tramway bit 6 10 8",4),("/tramway 8 7 8 14",11)]:
            chat(cmd)
            await_state(cmd,lambda s:s.get("tram",{}).get("count")==count,10)
        slot(6);click()  # rotate X to Z
        slot(3);aim(8,8);click();aim(8,13);click()
        artwork=await_state("complete atlas-backed depot, junction and platform nodes",
            lambda s: (s.get("tram",{}).get("nodes") or {}).get("8,13")=="luanttd_core:tram_stop_1",15)["tram"]["nodes"]
        assert artwork["5,10"]=="luanttd_core:tram_depot_2"
        assert artwork["8,10"]=="luanttd_core:tramway_13"
        screenshot("01a-dedicated-tramway")
        chat("/trampilot 5 10 8 8 8 13")
        first=await_state("streetcar arrives at north platform after a stock turn",lambda s:
            s.get("tram",{}).get("arrivals")==1 and s["tram"].get("vehicle"),25)["tram"]
        assert first["steps"]>25 and abs(first["vehicle"]["y"]-.512)<.02,first
        chat("/qa_tram_photo north")
        time.sleep(.45)
        screenshot("02a-streetcar-first-platform")
        second=await_state("streetcar turns at the stub and reaches south platform",lambda s:
            s.get("tram",{}).get("arrivals")==2 and s["tram"].get("vehicle"),25)["tram"]
        assert second["steps"]>first["steps"] and second["vehicle"]["z"]>first["vehicle"]["z"]+8,second
        chat("/qa_tram_photo south")
        time.sleep(.45)
        screenshot("03a-streetcar-second-platform")
        phase="resume moving streetcar after a real server/world restart"
        stop_server()
        reload=join("tram-reloaded")
        assert reload.get("tram",{}).get("count")==11 and reload["tram"]["arrivals"]>=second["arrivals"]
        native_aim(8,10,.58,framing=True)
        after=await_state("reloaded pilot continues alternating stops",
            lambda s:s.get("tram",{}).get("arrivals",0)>=4 and s["tram"].get("vehicle"),30)["tram"]
        screenshot("04a-streetcar-after-reload")
        (out/"tram-pilot.json").write_text(json.dumps(dict(first=first,second=second,after=after),indent=2))
        stop_server()
        print(f"PASS: Native tram depot/track/platform construction, exact turning route, live vehicle mesh, and continued arrivals after reload: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_TUNNEL_RUN")=="1":
        phase="dispatch a bus through a road tunnel"
        chat("/qa_bridge_service")
        chat("/survey 25 12")
        first=await_state("bus hides inside and emerges on opposing portal floor",
          lambda s:s.get("tunnel_hidden") and s.get("tunnel_exit") and s.get("paid_units",0)>0,55)
        screenshot("through-the-hill")
        stop_server()
        join("tunnel-service-reload")
        second=await_state("tunnel service resumes and pays after restart",
          lambda s:s.get("paid_units",0)>first["paid_units"] and s.get("tunnel_hidden") and s.get("tunnel_exit"),45)
        (out/"tunnel-service.json").write_text(json.dumps({"before":first["paid_units"],"after":second["paid_units"],
          "hidden":second["tunnel_hidden"],"exit":second["tunnel_exit"]},indent=2))
        stop_server()
        print(f"PASS: graphical bus entered, disappeared, resurfaced and paid across reload: {out}")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_BRIDGE_RUN")=="1":
        phase="dispatch a bus across a real bridge"
        chat("/qa_bridge_service")
        chat("/survey 25 12")
        bridge_style="concrete" if os.environ.get("BAYLINE_NATIVE_CONCRETE")=="1" else (
            "girder" if os.environ.get("BAYLINE_NATIVE_STEEL")=="1" else "timber")
        crossed=await_state("actual bus on elevated "+bridge_style+" deck",lambda s:s.get("bridge_pass"),45)
        assert abs(crossed["bridge_pass"]["y"]-1.52)<.012
        screenshot("bus-crosses-"+bridge_style+"-bridge")
        paid=await_state("first fare across span",lambda s:s.get("paid_units",0)>0,30)
        stop_server()
        join("bridge-service-reload")
        resumed=await_state("bridge crossing and fares resume after restart",
            lambda s:s.get("paid_units",0)>paid["paid_units"] and s.get("bridge_pass"),45)
        (out/"bridge-service.json").write_text(json.dumps({"before":paid["paid_units"],
            "after":resumed["paid_units"],"style":bridge_style,"bridge":resumed["bridge_pass"]},indent=2))
        stop_server()
        print(f"PASS: real buses crossed {bridge_style} road deck before and after reload in {out}.")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_LANDSCAPE_BRIDGE")=="1":
        phase="edit terrain and build a paid timber bridge"
        slot(7);click()
        await_state("Landscape submenu opened",lambda s:s.get("menu")=="terrain")
        slot(2);aim(6,15);click()
        await_state("terrain corner raised",lambda s:(s.get("terrain_construction") or {}).get("corner")==1)
        slot(8);click()
        await_state("returned to main hotbar",lambda s:s.get("menu")=="home")
        slot(2);click();await_state("Road Construction",lambda s:s.get("menu")=="roads")
        slot(10)
        if state()["wield_item"]=="luanttd_core:menu_road_bridge_picker":
            slot(7);click();await_state("Road Options",lambda s:s.get("menu")=="road_direction")
            slot(3);click()
        else:
            click()
        await_state("Bridge Types",lambda s:s.get("menu")=="structures")
        chat("/survey 23 3")
        slot(2);aim(17,3);click()
        aim(29,3)
        screenshot("wood-bridge-price-preview")
        click()
        def built(s):
            t=s.get("terrain_construction") or {}
            b=t.get("bridge") or {}
            nodes=t.get("meshes") or {}
            return (t.get("corner")==1 and b.get("length")==13 and b.get("price")>0 and
                nodes.get("17")=="luanttd_core:stock_road_bridge_wood_head_ramp_2" and
                nodes.get("29")=="luanttd_core:stock_road_bridge_wood_head_flat_0" and
                all(nodes.get(str(x))=="luanttd_core:stock_road_bridge_wood_span_0" for x in range(18,29)))
        result=await_state("all wooden heads and 11 continuous mesh spans",built,20)
        assert result["cash"]<100000-result["terrain_construction"]["bridge"]["price"]
        screenshot("wood-bridge-built")
        stop_server()
        join("landscape-reload")
        chat("/survey 23 3")
        result=await_state("native bridge and corner persist",built,20)
        (out/"bridge-construction.json").write_text(json.dumps(result["terrain_construction"],indent=2))
        stop_server()
        print(f"PASS: native landscaping and constructed bridge persisted in {out}.")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_TRACKWORKS")=="1":
        phase="place stock tracks"
        pieces=[(14,16,"x",1),(15,16,"x",1),(16,16,"right",32),
                (16,17,"y",2),(16,18,"upper",4),(15,18,"x",1),(14,18,"x",1),
                (17,16,"upper",4),(17,16,"lower",12)]
        rail_grades={(13,12):1,(17,12):2} if grade else {}
        if grade:
            pieces += [(x,12,"x",1) for x in range(12,19)]
        for x,z,name,bits in pieces:
            chat(f"/trackworks {x} {z} {name}")
            await_state("stock track built",lambda s: (s.get("track_nodes") or {}).get(f"{x},{z}",{}).get("mask")==bits)
        native_aim(16,17,1,framing=True)
        expected={}
        for x,z,_,bits in pieces:
            suffix=f"grade_{rail_grades[(x,z)]}" if (x,z) in rail_grades else str(bits)
            expected[f"{x},{z}"]={"mask":bits,"node":f"luanttd_core:stock_rail_{suffix}"}
        def expected_nodes(s):
            return s.get("track_nodes")==expected
        result=await_state("mesh node for each rail piece",expected_nodes)
        chat("/trackroute 14 16 14 18")
        route=await_state("stock path through two curves",
            lambda s: (s.get("track_route") or {}).get("tiles")==["14,16","15,16","16,16","16,17","16,18","15,18","14,18"])["track_route"]
        assert route["cost"]>0
        (out/"trackworks-route.json").write_text(json.dumps(route,indent=2))
        screenshot("trackworks-native")
        chat("/trackrun 14 16 14 18")
        turn=await_state("actual locomotive follows the first modeled curve",
            lambda s:(s.get("rail_locomotive") or {}).get("turning"),12)["rail_locomotive"]
        assert turn["arc_error"]<.001 and abs(turn["y"]-.612)<.001 and 1.6<turn["yaw"]<3.13,turn
        screenshot("trackworks-moving-locomotive")
        arrived=await_state("test locomotive reaches the endpoint",
            lambda s: (s.get("rail_locomotive") or {}).get("x",99)<28.30
            and abs(s["rail_locomotive"]["z"]-36.5)<.015,12)["rail_locomotive"]
        (out/"trackworks-locomotive.json").write_text(json.dumps({"curve":turn,"arrival":arrived},indent=2))
        if grade:
            native_aim(15,12,1.6,framing=True)
            screenshot("trackworks-grade")
        if os.environ.get("BAYLINE_NATIVE_RAIL_FACILITIES")=="1":
            phase="build a real depot and two-tile platform"
            chat("/trackrun clear")
            chat("/trackfacility 14 16 depot east")
            chat("/trackfacility 14 18 platform 15 18")
            expected["14,16"]={"mask":1,"node":"luanttd_core:stock_rail_depot_2","depot":2}
            for coord in ["14,18","15,18"]:
                expected[coord]={"mask":1,"node":"luanttd_core:stock_rail_platform_1","station":1}
            result=await_state("built complete rail facility meshes",expected_nodes)
            actual=await_state("source route reaches the real platform",
                lambda s:(s.get("facility_route") or {}).get("tiles")==route["tiles"])["facility_route"]
            (out/"rail-facility-route.json").write_text(json.dumps(actual,indent=2))
            native_aim(15,17,1.3,framing=True)
            screenshot("trackworks-real-facilities")
            chat("/railtrial 14 16 14 18")
            pilot=await_state("stock locomotive leaves the real depot",
                lambda s:(s.get("rail_pilot") or {}).get("phase")=="running"
                and (s.get("rail_pilot") or {}).get("mesh"),18)["rail_pilot"]
            assert pilot["tick"]>=19 or pilot["steps"]>0, pilot
        stop_server()
        join("track-reload")
        if os.environ.get("BAYLINE_NATIVE_RAIL_FACILITIES")=="1":
            arrived=await_state("stock locomotive resumed and stopped at the actual platform",
                lambda s:(s.get("rail_pilot") or {}).get("phase")=="arrived"
                and (s.get("rail_pilot") or {}).get("mesh"),25)["rail_pilot"]
            assert arrived["steps"]>pilot["steps"] and arrived["arrival"]["station"]==1,arrived
            assert arrived["arrival"]["pose"]["x"] % 16==3 and arrived["arrival"]["pose"]["y"] % 16==8,arrived
            assert abs(arrived["mesh"]["z"]-36.5)<.01,arrived
            (out/"rail-pilot-after-reload.json").write_text(json.dumps(arrived,indent=2))
            native_aim(14,18,.8,framing=True)
            screenshot("rail-pilot-at-platform")
        native_aim(16,17,1,framing=True)
        await_state("stock meshes persisted",expected_nodes)
        (out/"trackworks.json").write_text(json.dumps(result["track_nodes"],indent=2))
        stop_server()
        print(f"PASS: Native Luanti loaded and persisted {len(expected)} stock rail topology meshes in {out}.")
        sys.exit(0)
    if grade:
        assert ramp_shapes(fresh), fresh.get("grade_tiles")
    if fresh_profile:
        screenshot("00-fresh-start")
        phase="open and return from roadworks"
        assert fresh["menu"]=="home",fresh
        slot(2);click()
        await_state("Roadworks section",lambda s:s.get("menu")=="roads")
        screenshot("00b-roadworks-section")
        slot(8);click()
        await_state("Back to Sections",lambda s:s.get("menu")=="home")
        slot(2);click()
        await_state("Roadworks reordered icons",lambda s:s.get("wield_item")=="luanttd_core:menu_road" and s.get("menu")=="roads")
        phase="build and bulldoze a temporary spur"
        aim(8,12);click();click()
        await_state("temporary player road",lambda s:tile(s,(8,12))=="road")
        slot(9);click()
        await_state("bulldozer removed temporary road",lambda s:tile(s,(8,12)) is None)
    phase = "build road"
    slot(2)
    A, B, D = (9,12), (18,13 if turns else 12), ((16,13) if yapf else (10,13))
    if os.environ.get("BAYLINE_NATIVE_TOWN_GROWTH")=="1":
        A,B,D=(11,12),(17,12),(12,13)
    if fresh_profile:
        if turns:
            hold_to_build(native_aim,A,(B[0],A[1]))
            # Start with a long run, then choose the adjoining half of the
            # corner and the opposite half of the new tile separately.
            hold_to_build(native_aim,(B[0],A[1]),B)
        else:
            hold_to_build(native_aim,A,B)
    else:
        aim(*A)
        click()
        assert not state()["builds"], "legacy palette first click marks the endpoint"
        aim(*B)
        click()
    await_state("road connection", lambda s: all(tile(s,(x,12)) == "road" for x in range(A[0],B[0]+1)) and tile(s,B)=="road")
    screenshot("01-road-built")
    if yapf:
        assert fresh_profile and not grade and not turns
        phase = "build an OpenTTD-style matched junction and alternate road"
        for road_start,road_end in [((10,12),(10,13)),((10,13),(14,13)),((14,13),(14,12))]:
            hold_to_build(native_aim,road_start,road_end)
        await_state("complete detour",lambda s:all(tile(s,(x,13))=="road" for x in range(10,15)))
    if grade:
        await_state("both built slopes in actual map mesh nodes", ramp_nodes)
        chat("/qa_gradeview")
        await_state("grade camera",lambda s:s.get("aim")=="gradeview")
        time.sleep(.5)
        screenshot("01b-road-ramp-seams")
    phase = "build two stops"
    slot(3 if fresh_profile else 4)
    for placement in ((A,B,(11,12)) if yapf=="stop" else (A,B)):
        aim(*placement)
        click()
        await_state("road stop", lambda s: tile(s,placement) == "road_station")
    if fresh_profile and state().get("road_economy"):
        stops=state()["stop_state"]
        assert len(stops)==(3 if yapf=="stop" else 2) and all(x["waiting"]==0 and x.get("service_day") is None
                                    for x in stops.values()), stops
    phase = "choose and build depot"
    if fresh_profile:
        slot(4)
        aim(*D)
        screenshot("02-depot-preview")
    else:
        aim(*D)
        click(3)
        choose("luanttd_core:context","tool_road_depot","02-build-palette")
        await_state("palette closed after choosing depot", lambda s: not s.get("form"))
        slot(6)
        aim(*D)
    click()
    await_state("road depot", lambda s: tile(s,D) == "road_depot")
    if os.environ.get("BAYLINE_NATIVE_ROAD_SERVICE")=="1":
        E=(17,13)
        aim(*E);click()
        await_state("second reachable owned depot on the same road",lambda s:tile(s,E)=="road_depot")
        aim(*D)
    phase = "buy bus through depot UI"
    native_regal=os.environ.get("BAYLINE_NATIVE_STOCK_REGAL")=="1"
    native_foster=os.environ.get("BAYLINE_NATIVE_STOCK_FOSTER")=="1"
    pre_buy=state()
    slot(1)
    click()
    model="foster_bus" if native_foster else "leopard_bus" if os.environ.get("BAYLINE_NATIVE_LEOPARD")=="1" else "bus"
    choose("luanttd_core:service",{"leopard_bus":"depot_buy_leopard","foster_bus":"depot_buy_foster"}.get(model,"depot_buy"),"03-depot-buy")
    bought=await_state("purchased bus", lambda s: s["fleets"] == 1 and s.get("engine")==model and not s["operating"])
    if native_regal:
        r=bought["regal"]
        assert r["stock_id"]==116 and r["buy"]==6562 and bought["regal_capacity"]==31
        assert bought["cash"]==pre_buy["cash"]-6562 and bought["company_expense"]==pre_buy["company_expense"]+6562
        assert r["annual_fp"]==145600 and r["ticks"]==0 and bought["vehicle_expense"]==0
    if native_foster:
        w=bought["bus_market"]
        assert w["year"]==1995 and w["seats"]==37 and w["finance"]["stock_id"]==118
        assert w["offers"]["foster_bus"]=="available" and w["offers"]["bus"]=="retired"
        assert bought["cash"]==pre_buy["cash"]-8203 and w["finance"]["annual_fp"]==284800
    phase = "add two orders in the world"
    choose("luanttd_core:service","service_pick","04-select-orders")
    await_state("world selection",lambda s: not s.get("form"))
    for count, placement in enumerate((A, B),1):
        aim(*placement)
        click()
        await_state(f"{count} world-picked order(s)", lambda s: len(s["orders"] or []) == count)
    click(3)
    if os.environ.get("BAYLINE_NATIVE_SHARED_ORDERS")=="1":
        assert fresh_profile
        phase="buy two extra vehicles, link one order list and copy the other"
        def so(s):
            return s.get("shared_orders") or {}
        def acts(s,count,wanted):
            return all((so(s).get("v"+str(i),{}).get("orders") or [{}])[0].get("action")==a
                       for i,a in zip(range(1,count+1),wanted))
        def close_vehicle():
            choose("luanttd_core:service","service_back","shared-orders-close-vehicle")
            await_state("returned to the world",lambda s:not s.get("form"))
            time.sleep(.70)
        def inspect_depot():
            slot(1);aim(*D);time.sleep(.24);click()
        for i,op in ((2,"share"),(3,"copy")):
            close_vehicle();inspect_depot()
            choose("luanttd_core:service","depot_buy",f"shared-orders-buy-bus-{i}")
            choose("luanttd_core:service","order_list_open",f"open-copy-share-bus-{i}")
            choose("luanttd_core:service","order_list_"+op,f"apply-{op}-from-first-bus")
            await_state(f"list applied to bus {i}",lambda s:
               len(so(s).get("v"+str(i),{}).get("orders") or [])==2)
            if i==2:
                linked=state()
                assert so(linked)["v1"]["same"] and so(linked)["v2"]["group"]==so(linked)["v1"]["group"]
                choose("luanttd_core:service","service_cycle_load","edit-shared-full-load-on-second")
                await_state("both linked vehicles use Full load",lambda s:acts(s,2,["full","full"]))
        before=await_state("copy of the shared list is independent",lambda s:
            acts(s,3,["full","full","full"]) and not so(s)["v3"].get("group"))
        close_vehicle();inspect_depot()
        choose("luanttd_core:service","vehicle_2","select-second-shared-bus")
        choose("luanttd_core:service","service_cycle_load","edit-linked-list-before-declone")
        diverged=await_state("two linked orders changed but the third stayed Full load",lambda s:
            acts(s,3,["normal","normal","full"]))
        choose("luanttd_core:service","order_list_open","open-list-for-declone")
        choose("luanttd_core:service","order_list_unshare","declone-clears-only-second-bus")
        cleared=await_state("only the decloned vehicle has an empty list",lambda s:
            not (so(s)["v2"].get("orders") or []) and not so(s)["v1"].get("group")
            and len(so(s)["v1"]["orders"])==len(so(s)["v3"]["orders"])==2)
        choose("luanttd_core:service","order_list_open","reopen-list-for-reshare")
        choose("luanttd_core:service","order_list_share","reshare-before-native-save")
        await_state("linked group restored before save",lambda s:
            bool(so(s)["v2"].get("group")))
        stop_server()
        phase="reopen native shared and copied orders, then pay a real bus fare"
        reopened=join("stock-shared-orders-restarted")
        assert acts(reopened,3,["normal","normal","full"])
        assert so(reopened)["v1"]["same"] and so(reopened)["v2"]["same"]
        assert so(reopened)["v1"]["group"]==so(reopened)["v2"]["group"] and not so(reopened)["v3"].get("group")
        if state()["menu"]=="home":
            slot(2);click();await_state("Roadworks again",lambda s:s.get("menu")=="roads")
        inspect_depot()
        choose("luanttd_core:service","vehicle_1","open-reopened-shared-bus")
        choose("luanttd_core:service","service_toggle","start-shared-orders-after-save")
        paid=await_state("the first linked vehicle earns an actual fare while second remains stopped",lambda s:
            so(s).get("v1",{}).get("paid",0)>0 and not so(s).get("v2",{}).get("active"),100)
        (out/"road-shared-orders-desktop.json").write_text(json.dumps(
            {key:so(value) for key,value in dict(shared=before,diverged=diverged,cleared=cleared,reopened=reopened,paid=paid).items()},indent=2))
        stop_server()
        print("PASS: copied and linked source orders through native UI; declone, reload and actual fare.")
        sys.exit(0)
    phase = "dispatch and first fare"
    choose("luanttd_core:service","service_toggle","05-dispatch-orders")
    await_state("dispatched bus",lambda s: s["operating"])
    if os.environ.get("BAYLINE_NATIVE_ROAD_SERVICE")=="1":
        assert native_foster
        phase="real stock road controller orders a nearby service depot with passengers on board"
        outbound=await_state("travelling toward its actual second scheduled stop with riders",lambda s:
            (s.get("auto_service") or {}).get("ready"),100)["auto_service"]
        chat("/qa_road_service age")
        diverted=await_state("selected the second depot from its true road frame and retained passengers",lambda s:
            (s.get("auto_service") or {}).get("detour"),90)["auto_service"]
        q=diverted["detour"]
        assert diverted["active"] and q["dispatch"]["tile"]==12*48+17 and q["dispatch"]["station"]==2
        assert diverted["orders"]==outbound["orders"] and q["units"]==q["requested"]["units"]
        slot(8);click();await_state("home to inspect",lambda s:s.get("menu")=="home")
        slot(3);click();await_state("Fleet while automatic depot order is active",lambda s:s.get("menu")=="fleet")
        slot(3);click();choose("luanttd_core:service","vehicle_1","automatic-depot-selected-foster")
        time.sleep(.7);screenshot("01pd-native-automatic-depot-in-service")
        stop_server()
        phase="resume exact saved service diversion and then complete the interrupted passenger order"
        restored=join("automatic-service-restarted")["auto_service"]
        assert restored["detour"]==q and restored["active"] and restored["pose"]==diverted["pose"]
        chat("/qa_road_service go")
        final=await_state("actual depot entry, safe release and fare at the interrupted destination",lambda s:
            (s.get("auto_service") or {}).get("fare",0)>q["fare"],100)["auto_service"]
        assert final["orders"]==restored["orders"] and final["last"]["tile"]==11*48+18
        assert final["last"]["units"]==q["units"] and final["depot_entry"]>q["tick"]
        assert final["service"]>=final["depot_entry"] and final["last_departure"]>=final["depot_entry"]
        (out/"road-auto-service-desktop.json").write_text(json.dumps(
            dict(outbound=outbound,diverted=diverted,restored=restored,paid=final),indent=2))
        stop_server()
        print("PASS: live stock depot service chose nearby depot without changing schedule; saved boarding remained and paid.")
        sys.exit(0)
    if os.environ.get("BAYLINE_NATIVE_ROAD_FAULTS")=="1":
        assert native_foster
        phase="stock breakdown rolls after actual live road motion"
        start_fault=await_state("a meaningfully moving Foster with serviced depot history",lambda s:
            s.get("fault") and (s["fault"].get("raw_speed") or 0)>=5 and s["fault"].get("last_service_tick"),45)["fault"]
        chat("/qa_road_fault age")
        failed=await_state("accelerated wear triggered the actual stock repair hold",lambda s:
            s.get("fault") and s["fault"].get("first"),95)["fault"]
        first=failed["first"]
        assert failed["running"] and failed["active"] and failed["raw_speed"]==0 and failed["status"]=="Broken down"
        assert first["service"]>=1 and failed["charged"]>=first["billed"]>start_fault["charged"]
        assert (failed["x"],failed["z"],failed["index"])==(first["x"],first["z"],first["index"])
        if state()["menu"]=="roads":
            slot(8);click();await_state("Home to check the broken bus",lambda s:s.get("menu")=="home")
        slot(3);click();await_state("Fleet status while broken",lambda s:s.get("menu")=="fleet")
        slot(3);click()
        choose("luanttd_core:service","vehicle_1","road-fault-fleet-select")
        await_state("actual inspector of broken bus",lambda s:"service_back" in (s.get("buttons") or {}))
        time.sleep(.75);screenshot("01pc-native-foster-broken-inspector")
        phase="reopen the exact repair pose and survive the real recovery tick"
        stop_server()
        reopened=join("stock-road-fault-restarted")["fault"]
        assert reopened["first"]==first and reopened["delay"]==failed["delay"]
        assert reopened["orders"]==failed["orders"] and reopened["running"] and reopened["active"]
        assert (reopened["x"],reopened["z"],reopened["index"])==(first["x"],first["z"],first["index"])
        fx=os.environ.get("BAYLINE_NATIVE_FAULT_FX")=="1"
        if fx:
            chat("/qa_road_fault smoke")
            await_state("actual bus in view for localized repair smoke", lambda s:s["fault"].get("smoke_framed"))
            assert state()["fault"]["smoke"]==reopened["smoke"]
        chat("/qa_road_fault resume")
        if fx:
            await_state("live failure sends actual visible local smoke",lambda s:
                s["fault"].get("active") and s["fault"]["smoke"]>reopened["smoke"],10)
            time.sleep(.36);screenshot("02pc-native-repair-smoke")
        final=await_state("same vehicle recovered, moved and actually earned another fare",lambda s:
            s.get("fault") and s["fault"].get("recovered") and s["fault"]["paid"]>first["paid"],100)["fault"]
        assert final["orders"]==reopened["orders"] and final["charged"]>reopened["charged"]
        assert final["recovered"]>first["started"] and final["revenue"]>0
        assert final["first_recovery"]==first["tick"]+2*first["delay"]-int(first["phase_counter"]%2)
        (out/"road-breakdown-native.json").write_text(json.dumps(
            dict(driving=start_fault,broken=failed,reopened=reopened,after=final),indent=2))
        stop_server()
        print("PASS: real stock bus tested at accelerated wear; controlled stock breakdown, exact SQLite repair, continued fare.")
        sys.exit(0)
    if fresh_profile and state().get("road_economy"):
        arrival=await_state("first scheduled bus visit",lambda s: (s.get("arrival") or {}).get("first"),20)
        assert arrival["paid_units"]==0, arrival
        screenshot("05a-first-scheduled-arrival")
    if grade:
        if fresh_profile:
            native_aim(13,12,1.0)
            screenshot("01a-grade-tile-selected")
        chat("/qa_gradeview")
        await_state("grade camera",lambda s:s.get("aim")=="gradeview")
        for motion, name in [("ascending","05b-bus-ascending"),("descending","05c-bus-descending")]:
            await_state("actual bus mesh is "+motion,
                        lambda s: (s.get("grade_samples") or {}).get("current")==motion,20)
            screenshot(name)
        await_state("actual mesh objects travel uphill and downhill",ramp_traversal,20)
    if fresh_profile and state().get("road_economy"):
        await_state("passengers actually boarded",lambda s: (s.get("boarded") or {}).get("units",0)>0,30)
    if native_regal:
        loading=await_state("genuine 31-seat Regal stock loading pulse",lambda s:
           s.get("regal_load_capacity")==31 and s.get("regal_units",0)>0)
    if native_foster:
        foster=await_state("native original Foster bus model loaded real riders on its 37-seat stock body",lambda s:
           s["bus_market"].get("model")=="bl_foster_bus.obj" and
           s["bus_market"].get("load")==37 and s["bus_market"].get("units",0)>0)
        screenshot("05aa-foster-stock-lane-and-stop")
    fare = await_state("first positive fare",lambda s: s["vehicle_revenue"]>0 and s["paid_units"]>0,45)
    if grade:
        assert_clearance(fare)
    assert fare["delivered"] == fare["paid_units"] and fare["fare"]["amount"]>0
    if yapf:
        expected="detour" if yapf=="stop" else "straight"
        trace_yapf=await_state("bus mesh moving through the expected "+expected+" branch",
            lambda s: (s.get("yapf") or {}).get(expected) and
            (s.get("yapf") or {}).get("route_cost",0)>0, 12)["yapf"]
        assert not trace_yapf.get("straight" if yapf=="stop" else "detour"),trace_yapf
        (out/"yapf-route.json").write_text(json.dumps(trace_yapf,indent=2))
    if turns:
        turn=await_state("the real bus visibly rotates between cardinal axes near the native bend",
                         lambda s:s.get("observed_turn"),35)["observed_turn"]
        (out/"native-stock-turn-pose.json").write_text(json.dumps(turn,indent=2))
    if fresh_profile:
        assert fare.get("source_motion"), "No active stock motion stream in the default world"
        if os.environ.get("BAYLINE_NATIVE_STOCK_CLOCK")!="0":
            assert fare.get("road_stock_clock")
        if os.environ.get("BAYLINE_NATIVE_STOCK_HOUSES")!="0":
            assert fare.get("road_stock_house_supply") and fare.get("house_tick",0)>0
        crowd=await_state("waiting and boarding-fade platform figures",
                          lambda s:(s.get("crowd") or {}).get("count",0)>0 and
                                   (s.get("crowd") or {}).get("fades",0)>0, 12)["crowd"]
        assert .4<crowd["min_life"]<=crowd["max_life"]<.57 and 1.7<crowd["min_size"]<=crowd["max_size"]<2.2,crowd
        assert crowd["moving"]==0,crowd
        lane=fare.get("lane")
        assert lane and abs(abs(lane["offset"])-.155)<.01 and lane["visual_width"]<.3125 and lane["offset"]*lane["nose_x"]<0, lane
    if os.environ.get("BAYLINE_NATIVE_STOCK_LOADING")=="1":
        assert fare.get("road_stock_loading") and fare["stock_loading_tick"]==fare["house_tick"]
        assert fare["fare"]["tick"]>0 and fare["boarded"]["tick"]>0
    screenshot("06-served-corridor")
    (out / "first-fare.json").write_text(json.dumps(fare, indent=2))
    if fresh_profile:
        phase = "street-height view"
        xdo("keydown", "Shift_L")
        try:
            await_state("normal camera descent", lambda s: s.get("camera", {}).get("pos", {}).get("y", 99)<4.8, 8)
        finally:
            xdo("keyup", "Shift_L")
        native_aim(9,12,.67,framing=True)
        screenshot("06b-platform-street-height")
        native_aim(9,9,1.35,framing=True)
        screenshot("06c-town-street-height")
    if os.environ.get("BAYLINE_NATIVE_TOWN_GROWTH")=="1":
        phase="paid bus route enables a visible stock house construction"
        original=await_state("source ordered construction, stage 0",lambda s:
            (s.get("growth") or {}).get("node")=="luanttd_core:house_build_stage_0",105)["growth"]
        assert original["reason"]=="serviced" and not original.get("first_cargo")
        chat("/qa_growth photo");time.sleep(.6);screenshot("01u-served-town-foundation")
        saved=await_state("timber framing with population unchanged",lambda s:
            (s.get("growth") or {}).get("node")=="luanttd_core:house_build_stage_1" and s["growth"].get("paused"),75)["growth"]
        assert saved["population"]==original["population"] and not saved.get("first_cargo")
        screenshot("02u-stock-house-frame")
        stop_server()
        cfg=out/"server.conf"
        cfg.write_text(cfg.read_text().replace("bayline_stock_town_growth = true","bayline_stock_town_growth = false"))
        join("grown-town-restarted")
        retained=await_state("the saved framing survives when new growth is disabled",lambda s:
            (s.get("growth") or {}).get("node")=="luanttd_core:house_build_stage_1",45)["growth"]
        assert retained["built"]==saved["built"] and retained["population"]==saved["population"]
        chat("/qa_growth photo");chat("/qa_growth go")
        phase="same house gains roof and inhabitants before eventual real cargo"
        roof=await_state("partly roofed stage after restart",lambda s:
            (s.get("growth") or {}).get("node")=="luanttd_core:house_build_stage_2",65)["growth"]
        assert roof["population"]==saved["population"] and not roof.get("first_cargo")
        screenshot("03u-house-roof-after-restart")
        mature=await_state("completed mature real house",lambda s:
            (s.get("growth") or {}).get("completed") and "house_build_stage_" not in s["growth"].get("node",""),70)["growth"]
        assert mature["population"]>original["population"]
        screenshot("04u-occupied-mature-stock-house")
        final=await_state("first actual stock cargo from new home",lambda s:
            (s.get("growth") or {}).get("first_cargo"),105)["growth"]
        assert final["first_cargo"]>final["completion"]>final["built"]
        (out/"town-growth-desktop.json").write_text(json.dumps({"original":original,"saved":saved,"restored":retained,
          "roofed":roof,"occupied":mature,"cargo":final},indent=2))
        stop_server()
        print("PASS: native paid road service creates a house; saved framing resumed with roof, occupancy, and real later cargo.")
        sys.exit(0)
    phase = "restart and verify fare and orders persisted"
    stop_server()
    if grade:
        # The grade must come from the persisted campaign, not from running
        # the test preset again. Starting without the flag tests that path.
        cfg=out/"server.conf"
        cfg.write_text(cfg.read_text().replace("bayline_preview_terrain = true",
                                               "bayline_preview_terrain = false"))
    if native_regal:
        cfg=out/"server.conf"
        cfg.write_text(cfg.read_text().replace("bayline_stock_regal_preview = true","bayline_stock_regal_preview = false"))
    reload = join("reload")
    if grade:
        assert ramp_shapes(reload), reload.get("grade_tiles")
    assert reload["fleets"] == 1 and reload["engine"]==model and reload["operating"]
    assert reload["orders"] == fare["orders"] and reload["builds"] == fare["builds"]
    assert reload["revenue"] >= fare["revenue"] and reload["paid_units"] >= fare["paid_units"]
    phase = "receive fare after restart"
    final = await_state("next positive fare with persisted service",
                        lambda s: s["paid_units"]>reload["paid_units"] and s["revenue"]>reload["revenue"],40)
    if grade:
        final=await_state("actual mesh objects traverse persisted slopes",ramp_traversal,20)
        assert_clearance(final)
    screenshot("07-reloaded-service")
    if os.environ.get("BAYLINE_NATIVE_PASSING")=="1":
        phase = "two live stock-motion buses pass on a straight"
        native_aim(13,12,.64,framing=True)
        chat("/qa_passing")
        passed=await_state("two actual bus meshes passing",lambda s:s.get("passing"),40)["passing"]
        assert .03<passed["gap"]<.06,passed
        assert passed["forward"]["z"]<24.5<passed["back"]["z"],passed
        (out/"passing.json").write_text(json.dumps(passed,indent=2))
        screenshot("08-bus-passing")
    if os.environ.get("BAYLINE_NATIVE_QUEUE")=="1":
        phase = "traffic queues behind an occupied terminal and then resumes"
        chat("/qa_roadqueue")
        blocking=await_state("follower yields while leader is parked",
            lambda s: (s.get("road_queue") or {}).get("stage")=="blocked",40)["road_queue"]
        assert blocking["wait"]["leader_xy"]!=blocking["wait"]["follower_xy"],blocking
        screenshot("08-queued-road-vehicles")
        resumed=await_state("follower reaches stop after leader leaves",
            lambda s:(s.get("road_queue") or {}).get("stage")=="resumed",50)["road_queue"]
        assert resumed["arrival_day"]>resumed["wait"]["day"]
        if os.environ.get("BAYLINE_NATIVE_STOCK_LOADING")=="1":
            assert resumed["arrival_tick"]>0
        (out/"road-queue.json").write_text(json.dumps(resumed,indent=2))
    if native_regal:
        for s in (fare,reload,final):
            r=s["regal"]
            assert s["regal_capacity"]==31 and r["annual_fp"]==145600 and s["vehicle_expense"]>0
            # Ten road/stop tiles plus a two-dollar depot and 200 loan
            # interest per month, independent of vehicle costs.
            months=int(s["day"])//30-int(bought["day"])//30
            assert s["company_expense"]==bought["company_expense"]+s["vehicle_expense"]+212*months
            assert s["vehicle_expense"]==(r["running_fp"]+255)//256
            assert s["company_fraction"]==(-r["running_fp"])%256
            assert r["buy"]==6562 and r["value"]<=6562 and r["ticks"]>=r["charged_ticks"]>0
        assert final["regal"]["charged_ticks"]>reload["regal"]["charged_ticks"]
        assert final["regal"]["value"]<bought["regal"]["value"]
        (out/"regal-desktop.json").write_text(json.dumps(dict(before=pre_buy,bought=bought,loading=loading,
           first=fare,reopened=reload,after=final),indent=2))
    if native_foster:
        a,b=reload["bus_market"]["finance"],final["bus_market"]["finance"]
        assert b["charged_ticks"]>a["charged_ticks"] and b["running_fp"]>a["running_fp"]
        assert final["vehicle_expense"]==(b["running_fp"]+255)//256
        assert final["company_fraction"]==(-b["running_fp"])%256
        assert final["bus_market"]["seats"]==37 and final["bus_market"]["year"]==reload["bus_market"]["year"]
        (out/"foster-desktop.json").write_text(json.dumps(dict(bought=bought,loaded=foster,first=fare,reloaded=reload,
           after=final),indent=2))
    if os.environ.get("BAYLINE_NATIVE_DEPOT_RETURN")=="1":
        phase="mouse-build a nearer owned depot and stop a paid live bus at its station"
        E=(17,13)
        slot(2);click();await_state("Roadworks ready",lambda s:s.get("menu")=="roads")
        slot(4);aim(*E);click()
        await_state("nearer second depot built",lambda s:tile(s,E)=="road_depot")
        chat("/qa_depot_return latch")
        await_state("actual bus carries passengers towards its next accepting stop",lambda s:
            (s.get("depot_return") or {}).get("latch"),45)
        slot(8);click();slot(3);click()
        await_state("Fleet menu",lambda s:s.get("menu")=="fleet")
        slot(3);click();choose("luanttd_core:service","vehicle_1","depot-return-select-bus")
        choose("luanttd_core:service","service_toggle","depot-return-stop-after-paid-trip")
        chat("/qa_depot_return go")
        at_stop=await_state("bus stopped after really unloading",lambda s:
            (s.get("depot_return") or {}).get("park"),45)
        assert at_stop["depot_return"]["station"]==2 and at_stop["vehicle_revenue"]>=final["vehicle_revenue"]
        slot(3);click();choose("luanttd_core:service","vehicle_1","depot-return-select-parked")
        choose("luanttd_core:service","service_park","depot-return-choose-nearest")
        numbered=(E[1]-1)*48+E[0]
        arriving=await_state("bus enters nearer depot and vanishes at the original door frame",lambda s:
            s["depot_return"].get("depot")==numbered and not s["depot_return"].get("mesh"),35)
        assert arriving["depot_return"]["road_tick"]>at_stop["depot_return"]["visited"]
        assert arriving["orders"]==at_stop["orders"] and arriving["vehicle_revenue"]==at_stop["vehicle_revenue"]
        phase="restore the parked hidden bus and restart its preserved schedule"
        stop_server()
        again=join("native-depot-parked-restart")
        assert again["depot_return"]["road_tick"]==arriving["depot_return"]["road_tick"]
        assert again["depot_return"]["depot"]==numbered and not again["depot_return"].get("pose")
        slot(2);click();await_state("Roadworks ready",lambda s:s.get("menu")=="roads")
        slot(1);aim(*E);click()
        choose("luanttd_core:service","vehicle_1","depot-return-hidden-bus-in-its-depot")
        choose("luanttd_core:service","service_toggle","depot-return-resume-previous-orders")
        later=await_state("restored bus earns money again",lambda s:
            s["vehicle_revenue"]>again["vehicle_revenue"],70)
        assert later["orders"]==again["orders"] and later["depot_return"]["road_tick"]==again["depot_return"]["road_tick"]
        (out/"depot-return-desktop.json").write_text(json.dumps(dict(stopped=at_stop,in_depot=arriving,
            reopened=again,after=later),indent=2))
        stop_server()
        print(f"PASS: actual paid bus parks in the nearest source depot, hides, saves, starts and earns again: {out}")
        sys.exit(0)
    (out / "after-reload.json").write_text(json.dumps(final, indent=2))
    stop_server()
    print(f"PASS: Native UI built a road network, {fare['stops']:g} stops and a depot; dispatched 1 bus; "
          f"{fare['paid_units']:g} paid riders before restart, {final['paid_units']:g} after; evidence in {out}.")
    if yapf:
        print(f"PASS: source pathfinder chose the {expected} branch, and the bus mesh traversed it.")
    if grade:
        print(f"PASS: native bus traversed uphill and downhill before and after reload; "
              f"max model-origin height error {max(fare['grade_samples']['height_error'],final['grade_samples']['height_error']):.5f} node.")
except Exception:
    print(f"FAIL during {phase}; evidence in {out}", file=sys.stderr)
    try:
        screenshot("failure")
    except Exception:
        pass
    raise
finally:
    for p in reversed(processes):
        if p.poll() is None:
            p.terminate()
            try:
                p.wait(timeout=5)
            except sp.TimeoutExpired:
                p.kill()

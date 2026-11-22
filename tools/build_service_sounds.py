#!/usr/bin/env python3
"""Synthesize LuanTTD's original, short service sounds (requires ffmpeg)."""
from math import exp, pi, sin
from pathlib import Path
import struct
import subprocess
import tempfile
import wave

RATE = 24000
SOUNDS = Path(__file__).resolve().parents[1] / "mods/luanttd_core/sounds"
scores = {
    "first_arrival": (0.38, [(0.0, 392, .19, 8), (.14, 523.25, .15, 10)]),
    "fare": (.25, [(0.0, 659.25, .14, 14), (.063, 880, .13, 16)]),
}
SOUNDS.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory() as d:
    for name, (duration, notes) in scores.items():
        samples=[]
        for i in range(round(duration*RATE)):
            t=i/RATE
            sound=0
            for onset,hz,amp,decay in notes:
                age=t-onset
                if age<0:
                    continue
                env=min(1, age/.011) * exp(-age*decay)
                sound+=amp*env*(sin(2*pi*hz*age)+.22*sin(2*pi*hz*2.004*age))
            samples.append(round(32767*sound*min(1,(duration-t)/.022)))
        p=Path(d)/"cue.wav"
        with wave.open(str(p),"wb") as f:
            f.setparams((1,2,RATE,0,"NONE","not compressed"))
            f.writeframes(struct.pack("<"+"h"*len(samples),*samples))
        subprocess.run(["ffmpeg","-nostdin","-hide_banner","-loglevel","error","-y",
                        "-i",str(p),"-map_metadata","-1","-c:a","libvorbis","-q:a","4",
                        SOUNDS/f"bayline_{name}.ogg"],check=True)
print("Wrote two original monophonic service cues")

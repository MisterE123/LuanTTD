#!/usr/bin/env python3
"""Synthesize the simulator's mono propeller, slipstream and gear cues."""
import math
import random
import subprocess
import tempfile
import wave
from array import array
from pathlib import Path

DIR = Path(__file__).resolve().parents[1] / "mods/luanttd_core/sounds"
RATE = 24000
TAU = math.tau

def synth(name, duration, fn):
    with tempfile.TemporaryDirectory() as tmp:
        raw = Path(tmp) / "cue.wav"
        amplitude = array("h")
        for i in range(int(RATE * duration)):
            v = max(-1.0, min(1.0, fn(i/RATE, i)))
            amplitude.append(int(v * 32766))
        with wave.open(str(raw), "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(RATE)
            wav.writeframes(amplitude.tobytes())
        subprocess.run(["ffmpeg","-hide_banner","-loglevel","error","-y","-i",str(raw),
                        "-c:a","libvorbis","-q:a","3",str(DIR / (name+".ogg"))], check=True)

def rotors(base):
    # Three close tonal bands and an asymmetric blade pulse, inheriting
    # flutter from independent rotor phases. Integers loop at 3 seconds.
    variants = [(base-2,.2,1.21),(base,.4,0),(base+3,.16,2.4)]
    coefficients=[.63,.34,.24,.15,.12,.075]
    def sample(t, _):
        mix=0
        for f,volume,phase in variants:
            mod=math.sin(TAU*3*t+phase)*.11 + math.sin(TAU*t+2*phase)*.16
            for j,amp in enumerate(coefficients,1):
                mix += amp * volume * math.sin(TAU*f*j*t+phase*j+mod*j) * (.9+.10*math.cos(TAU*7*t+phase))
        return .69*mix
    return sample

rng=random.Random(215)
noise=[rng.uniform(-1,1) for _ in range(3*RATE)]
def wind(t, i):
    def mean(n):
        return sum(noise[(i-a)%len(noise)] for a in range(n))/n
    pressure = .91*mean(11) + .38*mean(47)
    fizz = .08*noise[i]
    swell = .72 + math.sin(TAU*t)*.11 + math.sin(TAU*2*t+2.9)*.12
    return swell*(pressure+fizz)

def touchdown(t, i):
    n=noise[i]
    thump=.74*math.sin(TAU*(68-29*t)*t)*math.exp(-34*t)
    skid=.25*n*math.exp(-13*t)*(.64+.36*math.cos(TAU*24*t))
    return (thump+skid)*min(1,t/.006)

synth("bl_plane_prop_idle", 3, rotors(42))
synth("bl_plane_prop_power", 3, rotors(66))
synth("bl_plane_wind", 3, wind)
synth("bl_plane_touchdown", .43, touchdown)

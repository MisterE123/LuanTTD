#!/usr/bin/env python3
"""Import official OpenSFX 1.0.3 and OpenMSX 0.4.2 into Luanti.

Audio packs (.tar, .tar.gz, .tar.xz, .zip or unpacked directories) must
come from the OpenTTD distribution. Neither proprietary Transport Tycoon
audio nor a no_sound/no_music descriptor is accepted. Requires ffmpeg and the FluidSynth shared library. See docs/STOCK_AUDIO.md for source and redistribution.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import configparser
import hashlib
from pathlib import Path, PurePosixPath
import struct
import subprocess
import tarfile
import tempfile
from render_stock_midi import render
import zipfile
import wave

ROOT = Path(__file__).resolve().parents[1]
COUNT = 73


def bank(data):
    """Decode OpenTTD 16.0-RC1 sound.cpp and soundloader.cpp CAT directory."""
    if len(data) < COUNT * 8 or struct.unpack_from("<I", data)[0] != (0x80000000 | COUNT*8):
        raise ValueError("Not a new-format 73-sample OpenSFX bank")
    entries = [struct.unpack_from("<II", data, i*8) for i in range(COUNT)]
    for i, (start, size) in enumerate(entries):
        start &= 0x7fffffff
        if not size or not COUNT*8 <= start < len(data):
            raise ValueError(f"Missing OpenSFX entry {i}")
        skip = data[start] + 1
        end = entries[i+1][0] & 0x7fffffff if i+1 < len(entries) else len(data)
        clip = data[start+skip:end]
        if not clip or not clip.startswith((b"RIFF", b"fLaC", b"OggS")):
            raise ValueError(f"Unrecognized OpenSFX entry {i} codec")
        yield clip


def pack(path):
    if path.is_dir():
        return {p.name: p.read_bytes() for p in path.rglob("*") if p.is_file()}
    if zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as z:
            return {PurePosixPath(i.filename).name: z.read(i) for i in z.infolist() if not i.is_dir()}
    with tarfile.open(path, "r:*") as tar:
        return {PurePosixPath(m.name).name: tar.extractfile(m).read() for m in tar if m.isfile()}


def parse_ini(blob):
    ini = configparser.ConfigParser(interpolation=None)
    ini.optionxform = str
    ini.read_string(blob.decode("utf-8-sig"))
    return ini


def material(items, ext, name, ver):
    matches = [(key, data) for key, data in items.items() if key.lower().endswith(ext)]
    if len(matches) != 1:
        raise ValueError(f"Expected one {ext} descriptor for {name}")
    key, data = matches[0]
    ini = parse_ini(data)
    version = ini.get("metadata", "version")
    if ini.get("metadata", "name").lower() != name.lower() or version not in ver:
        raise ValueError(f"Expected {name} version {ver}; found {version}")
    return key, ini


def verified(items, ini, name):
    data = items[name]
    md5 = ini["md5s"][name].strip()
    if hashlib.md5(data).hexdigest() != md5:
        raise ValueError(f"Incorrect MD5 for source asset {name}")
    return data


def convert(source, dest, *, rate, channels, q, metadata=None):
    args = ["ffmpeg", "-nostdin", "-loglevel", "error", "-y", "-i", str(source), "-map_metadata", "-1",
            "-af", "aresample=" + str(rate), "-ac", str(channels), "-c:a", "libvorbis",
            "-q:a", str(q)]
    for k, v in (metadata or {}).items():
        args += ["-metadata", f"{k}={v}"]
    tmp = dest.with_suffix(".tmp.ogg")
    dest.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(args + [str(tmp)], check=True)
    tmp.replace(dest)


def import_sfx(args, work):
    items = pack(args.sfx)
    if "opensfx.psfo" in items:
        expected = {f"osfx_{n:02}.wav" for n in range(COUNT)}
        if not expected <= items.keys():
            raise ValueError("Incomplete official WAV source")
        clips = [(n,items[f"osfx_{n:02}.wav"]) for n in range(COUNT)]
    else:
        _, ini = material(items, ".obs", "OpenSFX", {"103","1.0.3","20211031"})
        banks = list(ini["files"].values())
        if len(banks) != 1:
            raise ValueError("Expected one official OpenSFX CAT")
        clips = list(enumerate(bank(verified(items, ini, banks[0]))))
    def build(entry):
        n,clip=entry
        src = work / f"clip-{n}"
        src.write_bytes(clip)
        if n in (0x22,0x32) and clip.startswith(b"RIFF"):
            with wave.open(str(src),"rb") as original:
                empty=original.getnframes()==0
            if empty:
                # OpenSFX distributes two reserved slots as zero-frame WAVs.
                # Vorbis requires at least one packet, so preserve silence.
                with wave.open(str(src),"wb") as sample:
                    sample.setparams((1,2,22050,0,"NONE","not compressed"))
                    sample.writeframes(bytes(2206))
        convert(src, args.sounds / f"stock_sfx_{n:02x}.ogg", rate=22050, channels=1, q=3,
                metadata={"license": "CC BY-SA 3.0", "organization": "OpenSFX"})
    with ThreadPoolExecutor(max_workers=4) as jobs:
        list(jobs.map(build,clips))


def lua(value):
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def import_music(args, work):
    items = pack(args.music)
    if "themes.list" in items:
        songs = []
        for line in items["themes.list"].decode("utf-8").splitlines():
            if line.lstrip().startswith("#") or not line.strip():
                continue
            slot,name,author,title=(field.strip() for field in line.split(";",3))
            songs.append((slot,name,author,title,items[name]))
    else:
        key, ini = material(items, ".obm", "OpenMSX", {"4","5","42","0.4.2"})
        songs = [(slot,name,ini.get("authors", name,fallback="OpenMSX authors"),
                  ini.get("names",name,fallback=name),verified(items,ini,name))
                 for slot,name in ini["files"].items()]
    if len(songs)!=31 or sum(slot=="theme" for slot,*_ in songs)!=1:
        raise ValueError("OpenMSX must contain one title theme and 30 gameplay tracks")
    font = args.soundfont.resolve(strict=True)

    def build(item):
        i,(slot,name,author,title,song)=item
        if PurePosixPath(name).name != name or not song.startswith(b"MThd"):
            raise ValueError("Not a valid local MIDI filename and MIDI source")
        is_title=slot=="theme"
        rate=32000 if is_title else 22050
        sound = work / f"track-{i}.wav"
        src = work / f"track-{i}.mid"
        src.write_bytes(song)
        seconds=render(src,sound,font,rate)
        asset=f"openmsx_{i:02d}"
        metadata={"title": title, "artist":author, "album":"OpenMSX 0.4.2", "license":"GPL-2.0-only"}
        dest = args.output / "menu" / "theme.ogg" if is_title else args.sounds / (asset + ".ogg")
        convert(sound, dest, rate=rate, channels=2, q=0 if is_title else -.35, metadata=metadata)
        sound.unlink()
        src.unlink()
        return f"  {{slot={lua(slot)}, title={lua(title)}, author={lua(author)}, name={lua(asset)}, duration={seconds:.3f}}},"
    with ThreadPoolExecutor(max_workers=3) as jobs:
        made=list(jobs.map(build,enumerate(songs)))
    target = args.sounds.parent / "stock_audio_music.lua"
    target.with_suffix(".tmp").write_text("-- Generated from official OpenMSX source. See docs/STOCK_AUDIO.md.\nreturn {\n"+"\n".join(made)+"\n}\n")
    target.with_suffix(".tmp").replace(target)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sfx", type=Path)
    parser.add_argument("--music", type=Path)
    parser.add_argument("--soundfont", type=Path, default=Path("/usr/share/sounds/sf2/TimGM6mb.sf2"))
    parser.add_argument("--output", type=Path, default=ROOT)
    args = parser.parse_args()
    if not (args.sfx or args.music):
        parser.error("Supply at least one official audio release archive")
    args.sounds = args.output / "mods" / "luanttd_core" / "sounds"
    with tempfile.TemporaryDirectory(prefix="luanttd-audio-") as d:
        path = Path(d)
        if args.sfx:
            import_sfx(args, path)
        if args.music:
            import_music(args, path)


if __name__ == "__main__":
    main()

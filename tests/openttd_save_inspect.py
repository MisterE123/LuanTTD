"""Preflight regression, optionally with a genuine OpenTTD 14.1 fixture."""
from pathlib import Path
import lzma
import sys
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/"tools"))
from openttd_save_inspect import inspect, SaveError

size=64*64
schema=b"\x06\x05dim_x\x06\x05dim_y\0"
content=b"MAPS\3"+bytes([len(schema)+1])+schema+b"\x09"+b"\0\0\0\x40"*2+b"\0"
content+=b"MAPT"+size.to_bytes(4,"big")+bytes(size)
content+=b"MAPH"+size.to_bytes(4,"big")+bytes(range(256))*16+b"\0"*4
for magic,codec in ((b"OTTX",lzma.compress),(b"OTTZ",zlib.compress),(b"OTTN",lambda raw: raw)):
    data=magic+b"\x01\x4e\0\0"+codec(content)
    info=inspect(data)
    assert info["width"]==64 and info["height"]==64
    assert info["max_corner"]==255 and not info["can_resume_in_luanti"]
    try:
        inspect(data[:-1])
    except (SaveError,lzma.LZMAError,zlib.error):
        pass
    else:
        raise AssertionError("accepted truncated data")
for garbage in (b"NOPE",b"OTTN\xff\xff\0\0"+content,b"OTTN\x01\x4e\0\0"+content+b"JUNK"):
    try:
        inspect(garbage)
    except SaveError:
        pass
    else:
        raise AssertionError("accepted invalid or unknown format")
for filename in sys.argv[1:]:
    info=inspect(Path(filename).read_bytes())
    assert info["save_version"] in (333,334) and "VEHS" in info["chunk_records_or_bytes"]
    assert not info["can_resume_in_luanti"]
print(f"PASS: 3 encodings, rejection cases and {len(sys.argv)-1} real save(s)")

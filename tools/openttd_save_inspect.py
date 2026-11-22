#!/usr/bin/env python3
"""Read-only preflight for OpenTTD 14.1-era saves; NOT a world importer.

Save-layout sources: OpenTTD 14.1 src/saveload/{saveload.cpp,map_sl.cpp}
(GPL-2.0-only, copyright OpenTTD contributors; see COPYING.OpenTTD.md).
Only map fields are interpreted. Other chunks are indexed without reading
their objects, following the upstream record lengths rather than searching
for four-byte strings in compressed or decoded data.
"""
from collections import Counter
from hashlib import sha256
from pathlib import Path
import argparse
import json
import lzma
import struct
import sys
import zlib

LIMIT = 256 * 1024 * 1024
VERSIONS = {333, 334}
DEMOS = {b"OTTX":"xz",b"OTTZ":"zlib",b"OTTN":"uncompressed"}

class SaveError(ValueError):
    pass

class Reader:
    def __init__(self, data):
        self.data = memoryview(data)
        self.at = 0

    def take(self, size):
        end = self.at + size
        if end > len(self.data):
            raise SaveError("Truncated save record")
        result = self.data[self.at:end]
        self.at = end
        return result

    def byte(self):
        return self.take(1)[0]

    def gamma(self):
        first = self.byte()
        if first < 128:
            return first
        for width, base in enumerate((0xC0,0xE0,0xF0), 1):
            if first < base:
                prefix = first & ((1<<(7-width))-1)
                return (prefix << (width*8)) | int.from_bytes(self.take(width),"big")
        if first < 0xF8:
            return int.from_bytes(self.take(4),"big")
        raise SaveError("Invalid length prefix")

    def record(self):
        size = self.gamma()
        return None if size == 0 else self.take(size-1)

def unpack_payload(blob):
    if len(blob)<8:
        raise SaveError("Save header missing")
    magic=blob[:4]
    if magic not in DEMOS:
        raise SaveError("Unsupported compression or save signature")
    version=int.from_bytes(blob[4:6],"big")
    if version not in VERSIONS or blob[6:8]!=b"\0\0":
        raise SaveError(f"Save version {version} needs a version-specific reader")
    body=blob[8:]
    if magic==b"OTTX":
        dec=lzma.LZMADecompressor(format=lzma.FORMAT_XZ,memlimit=128*1024*1024)
        result=dec.decompress(body,max_length=LIMIT+1)
    elif magic==b"OTTZ":
        dec=zlib.decompressobj()
        result=dec.decompress(body,max_length=LIMIT+1)
    else:
        return version,DEMOS[magic],body
    if len(result)>LIMIT or not dec.eof or dec.unused_data:
        raise SaveError("Decoded save exceeds budget or is incomplete")
    return version,DEMOS[magic],result

def chunks(data):
    reader=Reader(data)
    seen=set()
    while True:
        tag=bytes(reader.take(4))
        if tag==b"\0\0\0\0":
            if reader.at!=len(reader.data):
                raise SaveError("Unexpected data after the final chunk")
            break
        if any(not (48<=b<=57 or 65<=b<=90 or 97<=b<=122 or b==95) for b in tag):
            raise SaveError("Invalid chunk identifier")
        if tag in seen:
            raise SaveError(f"Duplicate chunk {tag!r}")
        seen.add(tag)
        m=reader.byte()
        mode=m&15
        if mode==0:
            n=((m>>4)<<24)|int.from_bytes(reader.take(3),"big")
            yield tag,mode,None,reader.take(n)
        elif mode in (1,2,3,4) and m==mode:
            count=0
            schema=reader.record() if mode in (3,4) else None
            if mode in (3,4) and schema is None:
                raise SaveError("Table without a schema")
            row=None
            while (record:=reader.record()) is not None:
                if count==0 and tag==b"MAPS":
                    row=record
                count+=1
            yield tag,mode,schema,(count,row)
        else:
            raise SaveError(f"Unsupported chunk mode {m} in {tag!r}")

def inspect(blob):
    version,compression,body=unpack_payload(blob)
    result={
        "save_version":version,"compression":compression,
        "source_sha256":sha256(blob).hexdigest(),"can_resume_in_luanti":False,
    }
    dims=None
    planes={}
    indexed={}
    for tag,mode,schema,data in chunks(body):
        if tag==b"MAPS":
            # Save/Load can reorder fields in a new version. Deliberately
            # admit only the exact known table here; never guess its meaning.
            count,row=data if mode==3 else (0,None)
            if schema!=b"\x06\x05dim_x\x06\x05dim_y\0" or count!=1 or len(row)!=8:
                raise SaveError("Unsupported MAPS schema")
            dims=struct.unpack(">II",row)
            if any(n<64 or n>4096 or n&(n-1) for n in dims):
                raise SaveError("Invalid or unsupported map dimensions")
        if tag in (b"MAPT",b"MAPH") and mode==0:
            planes[tag]=data
        indexed[tag.decode()]=len(data) if mode==0 else data[0]
    if not dims or not all(len(planes.get(t,()))==dims[0]*dims[1] for t in (b"MAPT",b"MAPH")):
        raise SaveError("Missing or inconsistent map planes")
    heights=planes[b"MAPH"]
    tile_types=Counter(x>>4 for x in planes[b"MAPT"])
    result.update(width=dims[0],height=dims[1],min_corner=min(heights),max_corner=max(heights),
        corner_plane_sha256=sha256(heights).hexdigest(),
        tile_type_counts=dict(sorted(tile_types.items())),chunk_records_or_bytes=indexed)
    return result

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("save",type=Path)
    args=parser.parse_args()
    try:
        with args.save.open("rb") as stream:
            blob=stream.read(LIMIT+1)
        if len(blob)>LIMIT:
            raise SaveError("Input exceeds the preflight budget")
        print(json.dumps(inspect(blob),indent=2,sort_keys=True))
    except (SaveError,OSError,lzma.LZMAError,zlib.error) as exc:
        parser.exit(1,f"Save not inspected: {exc}\n")

if __name__=="__main__":
    main()

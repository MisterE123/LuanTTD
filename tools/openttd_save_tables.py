"""Read selected stock OpenTTD 14.1 CH_TABLE / CH_SPARSE_TABLE pools.

Returns raw field values and actual pool indices. The file schema encodes
integer width, not whether a field is a direct index, a pointer or a flag;
normalize references only with source-specific field knowledge.
"""
# SPDX-License-Identifier: GPL-2.0-only
# Translated from OpenTTD 14.1 src/saveload/{saveload.h,saveload.cpp}.
# Copyright OpenTTD contributors; see COPYING.OpenTTD.md.
from openttd_save_inspect import LIMIT, Reader, SaveError, unpack_payload

SIZE = (0,1,1,2,2,4,4,8,8,2)
SIGNED = {1,3,5,7}
MAX_FIELDS = 8192
MAX_ARRAY = 65_536
MAX_POOL = 100_000


def read_schema(r, depth=0, budget=None):
    if depth > 16:
        raise SaveError("OpenTTD table schema nests too deeply")
    if budget is None:
        budget = [MAX_FIELDS]
    fields = {}
    while (tag := r.byte()) != 0:
        type_id = tag & 15
        listed = bool(tag & 16)
        if not (1 <= type_id <= 11) or tag > 31 or (type_id in (10,11) and not listed):
            raise SaveError(f"Unsupported OpenTTD table field type {tag}")
        n = r.gamma()
        if not 1 <= n <= 1024:
            raise SaveError("Invalid table field name size")
        try:
            key = bytes(r.take(n)).decode("ascii")
        except UnicodeDecodeError as exc:
            raise SaveError("Invalid table field name") from exc
        if key in fields or budget[0] <= 0 or not key.isprintable():
            raise SaveError("Duplicate, invalid or excessive OpenTTD fields")
        budget[0] -= 1
        fields[key] = (type_id, listed)
    return [(k, i, a, read_schema(r,depth+1,budget) if i==11 else None)
            for k,(i,a) in fields.items()]


def read_row(r, desc, budget):
    row = {}
    for field, type_id, listed, nested in desc:
        n = r.gamma() if listed else 1
        if n > MAX_ARRAY or budget[0] < n+1:
            raise SaveError("OpenTTD field length exceeds the table decode budget")
        budget[0] -= n+1
        if type_id==11:
            row[field] = [read_row(r,nested,budget) for _ in range(n)]
        elif type_id==10:
            # Raw text bytes preserve engine control codes and avoid silently
            # changing otherwise valid names. Normalization chooses policy.
            row[field] = bytes(r.take(n))
        else:
            width = SIZE[type_id]
            raw = r.take(n*width)
            values = [int.from_bytes(raw[off:off+width],"big",signed=type_id in SIGNED)
                      for off in range(0,len(raw),width)]
            row[field] = values if listed else values[0]
    return row


def decode_tables(blob, selected):
    """Return {chunk_name: {pool_id: fields}}, retaining dense gaps."""
    if len(blob) > LIMIT:
        raise SaveError("Input exceeds the table decoder budget")
    _, _, body = unpack_payload(blob)
    r = Reader(body)
    seen, output = set(), {}
    while (tag := bytes(r.take(4))) != bytes(4):
        if tag in seen:
            raise SaveError(f"Duplicate OpenTTD pool {tag!r}")
        seen.add(tag)
        mode = r.byte()
        if mode&15==0:
            n = ((mode >> 4) << 24) | int.from_bytes(r.take(3),"big")
            if tag in selected:
                raise SaveError(f"Expected table pool for {tag!r}")
            r.take(n)
            continue
        if mode not in (1,2,3,4):
            raise SaveError(f"Invalid OpenTTD pool mode {mode}")
        header = r.record() if mode in (3,4) else None
        if mode in (3,4) and header is None:
            raise SaveError("Missing OpenTTD table header")
        decode = tag in selected
        if decode:
            if mode not in (3,4):
                raise SaveError(f"Expected OpenTTD table for {tag!r}")
            hr = Reader(header)
            desc = read_schema(hr)
            if hr.at != len(hr.data):
                raise SaveError("Unexpected OpenTTD schema bytes")
            rows, budget = {}, [2_000_000]
        i = 0
        while (record := r.record()) is not None:
            if decode and (record or mode==4):
                rr = Reader(record)
                index = rr.gamma() if mode==4 else i
                if index in rows or index>=2**31 or len(rows)>=MAX_POOL:
                    raise SaveError(f"Duplicate, invalid or excessive pool index in {tag!r}")
                rows[index] = read_row(rr,desc,budget)
                if rr.at != len(rr.data):
                    raise SaveError(f"Incorrect OpenTTD row length in {tag!r} at {index}")
            i += 1
        if decode:
            output[tag] = rows
    if r.at!=len(r.data) or set(output)!=set(selected):
        raise SaveError("Extra save bytes or missing requested OpenTTD table")
    return output


def reference(value, pool, what):
    """Resolve a known SlRef field (0=null, 1=object with index zero)."""
    if not isinstance(value,int) or value < 0:
        raise SaveError(f"Invalid pointer encoding for {what}")
    if value == 0:
        return None
    index = value-1
    if index not in pool:
        raise SaveError(f"Dangling {what} pointer to pool index {index}")
    return index

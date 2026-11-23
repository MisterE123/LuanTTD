#!/usr/bin/env python3
"""Prepare a local content-addressed client cache for graphical game fixtures."""
# SPDX-License-Identifier: GPL-2.0-only
from hashlib import sha1
from pathlib import Path
from tempfile import NamedTemporaryFile
import os
import sys

game = Path(sys.argv[1])
output = Path(sys.argv[2]) / "minetest" / "media"
assert (game / "game.conf").is_file() and (game / "mods").is_dir()
output.mkdir(parents=True, exist_ok=True)
for media in (game / "mods").rglob("*"):
    if not media.is_file() or not {"models", "textures", "sounds"}.intersection(media.relative_to(game).parts[:-1]):
        continue
    body = media.read_bytes()
    key = output / sha1(body).hexdigest()
    if key.is_file():
        continue
    with NamedTemporaryFile(dir=output, prefix=".stage-", delete=False) as stream:
        stream.write(body)
        temp = stream.name
    os.replace(temp, key)

#!/usr/bin/env python3
"""Prepare a local content-addressed client cache for graphical game fixtures."""
# SPDX-License-Identifier: GPL-2.0-only
from hashlib import sha1
from pathlib import Path
from tempfile import NamedTemporaryFile
import errno
import os
import sys

hardlink = len(sys.argv) == 4 and sys.argv[3] == "--hardlink"
assert len(sys.argv) == 3 or hardlink
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
    if hardlink:  # Same-mount disposable tests; game assets stay immutable.
        try:
            os.link(media, key)
            continue
        except FileExistsError:
            continue
        except OSError as error:
            if error.errno not in (errno.EXDEV, errno.EPERM, errno.EOPNOTSUPP):
                raise
    with NamedTemporaryFile(dir=output, prefix=".stage-", delete=False) as stream:
        stream.write(body)
        temp = stream.name
    os.replace(temp, key)

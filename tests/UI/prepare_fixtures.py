#!/usr/bin/env python3
"""Prepare only synthetic UI fixture files in the installed simulator app."""
import plistlib
import sqlite3
import subprocess
import sys
import struct
import zlib
from pathlib import Path

udid = sys.argv[1] if len(sys.argv) > 1 else 'booted'
container = subprocess.check_output(['xcrun', 'simctl', 'get_app_container', udid, 'mumu.pduola.WQManager', 'data'], text=True).strip()
root = Path(container) / 'tmp/WQMContainerFixture/Documents'
root.mkdir(parents=True, exist_ok=True)
# Reuse a fixture rather than touching any app-managed or imported user data.
path = root / 'inspection.sqlite'
if not path.exists():
    with sqlite3.connect(path) as database:
        database.execute('CREATE TABLE messages (id INTEGER PRIMARY KEY, text TEXT, attachment BLOB)')
        database.executemany('INSERT INTO messages VALUES (?, ?, ?)', [(index, f'Fixture row {index} · 中文', b'fixture') for index in range(1, 206)])
with (root / 'inspection.plist').open('wb') as file:
    plistlib.dump({'nested': {'theme': 'dark', 'enabled': True}, 'items': ['one', 'two']}, file, fmt=plistlib.FMT_BINARY)
(root / 'large.txt').write_text(('Synthetic preview line\n' * 100000), encoding='utf-8')
export_root = root / 'Export Fixture'
export_root.mkdir(parents=True, exist_ok=True)
for name, size in (('voice.m4a', 1024 * 1024), ('report.pdf', 1024 * 1024), ('archive.zip', 1024 * 1024)):
    path = export_root / name
    if not path.exists():
        path.write_bytes(b'\0' * size)
duplicate = b'duplicate-fixture-content' * 80000
for name in ('duplicate-a.jpg', 'duplicate-b.jpg'):
    path = export_root / name
    if not path.exists():
        path.write_bytes(duplicate)
print('Prepared synthetic plist, SQLite and large-text UI fixtures')

# Stream a high-resolution PNG without retaining an uncompressed image in RAM.
def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
compressor = zlib.compressobj()
row = b'\x00' + b'\x24\x80\xa0' * 8000
encoded = bytearray()
for index in range(4000):
    encoded.extend(compressor.compress(row))
encoded.extend(compressor.flush())
(root / 'large.png').write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 8000, 4000, 8, 2, 0, 0, 0)) + chunk(b'IDAT', bytes(encoded)) + chunk(b'IEND', b''))

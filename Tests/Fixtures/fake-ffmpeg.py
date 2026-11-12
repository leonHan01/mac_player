#!/usr/bin/env python3
"""Exercise clip export process handling without opening or decoding media."""
import json
from pathlib import Path
import sys
import time

args = sys.argv[1:]
source = Path(args[args.index('-i') + 1])
output = Path(args[-1])
source.with_suffix('.started').touch()
if source.stem == 'slow':
    output.write_bytes(b'partial clip')
    time.sleep(30)
if source.stem == 'fail':
    output.write_bytes(b'partial clip')
    print('fixture export failure', file=sys.stderr)
    sys.exit(23)
if source.stem == 'empty':
    output.touch()
    sys.exit(0)
assert args[args.index('-c:v') + 1] == 'libx264'
assert args[args.index('-c:a') + 1] == 'aac'
assert args[args.index('-f') + 1] == 'mp4'
assert '0:v:0' in args and '0:a:0?' in args
output.write_text(json.dumps({
    'source': str(source),
    'start': float(args[args.index('-ss') + 1]),
    'duration': float(args[args.index('-t') + 1]),
}))

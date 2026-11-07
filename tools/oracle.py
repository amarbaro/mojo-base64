#!/usr/bin/env python3
"""Live CPython output for the cases replayed by the Mojo runner."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_vectors import evaluate
sys.stdout.reconfigure(line_buffering=True)
if sys.argv[1] == '--list':
    print('golden')
else:
    for row in Path('tests/golden/basic.txt').read_text().splitlines():
        index, op, data, flag, extra, _, _ = row.split('\t')
        status, result = evaluate(op, bytes.fromhex(data), flag == '1', bytes.fromhex(extra))
        print('\t'.join((index, status, result)))

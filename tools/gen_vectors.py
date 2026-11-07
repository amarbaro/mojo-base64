#!/usr/bin/env python3
"""Deterministic CPython 3.14 vectors; tab-separated, byte fields hex."""
import base64
import itertools
from itertools import chain
import random
from pathlib import Path

OPS = ('b64encode', 'b64decode', 'standard_b64encode', 'standard_b64decode',
       'urlsafe_b64encode', 'urlsafe_b64decode', 'b32encode', 'b32decode',
       'b32hexencode', 'b32hexdecode', 'b16encode', 'b16decode')


def evaluate(op, data, flag=False, extra=b''):
    call = getattr(base64, op)
    kwargs = {}
    if op == 'b64decode':
        kwargs = dict(validate=flag, altchars=extra or None)
    elif op == 'standard_b64decode':
        call, kwargs = base64.b64decode, dict(validate=flag)
    elif op == 'urlsafe_b64decode' and flag:
        call, kwargs = base64.b64decode, dict(validate=True, altchars=b'-_')
    elif op == 'b32decode':
        kwargs = dict(casefold=flag, map01=extra or None)
    elif op in ('b32hexdecode', 'b16decode'):
        kwargs = dict(casefold=flag)
    try:
        return 'ok', call(data, **kwargs).hex()
    except (ValueError, AssertionError) as error:
        return 'err', str(error)


def vectors():
    for n in range(65):
        data = bytes((i * 73 + n) % 256 for i in range(n))
        for enc, dec in zip(OPS[::2], OPS[1::2]):
            yield enc, data, False, b''
            yield dec, getattr(base64, enc)(data), False, b''
    for n in range(5):
        for chars in itertools.product(b'A=!\xff', repeat=n):
            for strict in (False, True):
                yield 'b64decode', bytes(chars), strict, b''
    for data in (b'AAAA=', b'YQ==A', b'YQ=Q', b'YQ===', b'A!A!A!AA', b'=!',
                 b'YQ==!', b'AA=!', b'AA==!', b'AA==A', b'A=!A', b'!AAA='):
        for strict in (False, True):
            yield 'b64decode', data, strict, b''
    for extra in (b'!', b'abc', b'\x00\xff\n', b"'", b'"', b'-_', b'==', b'AA',
                  b'\\', b'\t', b'\r', b'\'"', b'\'"\\', b'\'"\t\r\\', b':,'):
        for data in (b'', b'-w==', b'__8=', b'AAAA'):
            for strict in (False, True):
                yield 'b64decode', data, strict, extra
    # altchars are validated and applied before the leading '=' check (fuzz 2026-11-07)
    for extra in (b'=_', b'_=', b'-=', b'!', b'abc', b'=='):
        for data in (b'=QUJD', b'QUJD', b'=', b'==AA'):
            for strict in (False, True):
                yield 'b64decode', data, strict, extra
    for op in ('b32decode', 'b32hexdecode'):
        for pad in range(17):
            for char in (b'A', b'!', b'a'):
                for fold in (False, True):
                    yield op, char * (16-pad) + b'=' * pad, fold, b''
        for data in (b'A', b'=AAAAAAA', b'aa======', b'\xffAAAAAAA', b'', b'!======='):
            for fold in (False, True):
                yield op, data, fold, b''
    for data in (b'01AAAAAA', b'01======', b'A', b'', b'!!!!!!!!'):
        for extra in (b'I', b'L', b'i', b'!', b'IL', b'\x00\xff', b"'", b'"',
                      b'\\\\', b'\t\t', b'\r\r', b'\'"', b'\'"\\', b'\'"\t\r\\'):
            for fold in (False, True):
                yield 'b32decode', data, fold, extra
    for data in (b'A', b'Z', b'AA!', b'aa', b'\xff0', b'A A', b'', b'0123456789ABCDEF', b'GG', b'AG'):
        for fold in (False, True):
            yield 'b16decode', data, fold, b''
    rng = random.Random(42)
    for _ in range(500):
        yield rng.choice(OPS[1::2]), rng.randbytes(rng.randrange(65)), bool(rng.randrange(2)), b''


JUNK = (b'=', b'\n', b' ', b'-', b'_', b'+', b'/', b'\xff', b'\x00', b'!', b'a', b'0', b'1', b'A', b'Z')


def mutate(rng, data):
    """Valid encoding with random insertions, replacements, deletions and truncation."""
    data = bytearray(data)
    for _ in range(rng.choice((0, 0, 1, 1, 2, 5))):
        pos = rng.randrange(len(data) + 1)
        kind = rng.randrange(4)
        if kind == 0:
            data[pos:pos] = rng.choice(JUNK) * rng.randrange(1, 4)
        elif kind == 1 and pos < len(data):
            data[pos] = rng.choice(JUNK)[0]
        elif kind == 2 and pos < len(data):
            del data[pos]
        elif kind == 3:
            del data[pos:]
    return bytes(data)


def random_vectors(seed, count):
    """Long, alphabet-biased rows: the fast path, the slow path and every hand-off between them."""
    rng = random.Random(seed)
    for _ in range(count):
        raw = rng.randbytes(rng.choice((0, 1, 2, 3, 5, 17, 64, 65, 129, 300, 1000)) + rng.randrange(3))
        op = rng.choice(OPS)
        if op.endswith('encode'):
            yield op, raw, False, b''
            continue
        flag = bool(rng.randrange(2))
        extra = b''
        if op == 'b64decode':
            extra = rng.choice((b'', b'', b'-_', b'+/', b'_-', b'!?', b'=_'))
            enc = base64.b64encode(raw) if extra == b'' else base64.b64encode(raw, extra if len(extra) == 2 else None)
        elif op == 'b32decode':
            extra = rng.choice((b'', b'', b'I', b'L'))
            enc = base64.b32encode(raw)
        else:
            enc = getattr(base64, op.replace('decode', 'encode'))(raw)
        yield op, mutate(rng, enc), flag, extra


def main():
    import sys
    if len(sys.argv) == 4:  # tools/gen_vectors.py SEED COUNT OUT: scratch fuzz file, not committed
        rows = [(i, *v) for i, v in enumerate(random_vectors(int(sys.argv[1]), int(sys.argv[2])))]
        Path(sys.argv[3]).write_text(''.join('\t'.join((str(i), op, d.hex(), str(int(f)), e.hex(), *evaluate(op, d, f, e))) + '\n' for i, op, d, f, e in rows))
        print(f'fuzz: {len(rows)} rows -> {sys.argv[3]}')
        return
    rows = []
    for index, (op, data, flag, extra) in enumerate(chain(vectors(), random_vectors(7, 1500))):
        status, result = evaluate(op, data, flag, extra)
        rows.append('\t'.join((str(index), op, data.hex(), str(int(flag)), extra.hex(), status, result)))
    Path('tests/golden/basic.txt').write_text('\n'.join(rows) + '\n')
    print(f'goldens: {len(rows)} CPython vectors')


if __name__ == '__main__':
    main()

# Design

Inputs are non-owning Span[UInt8] views; outputs own List[Byte] buffers.
The byte codecs use scalar integer grouping and comptime alphabet strings.
No runtime Python dependency. The reference is CPython 3.14.8/3.14.9.

Base64 validation follows current binascii branch order, including invalid
alphabet before post-padding errors and valid-data counts in length errors.
Duplicate altchars use the last mapping, matching bytes.maketrans.
Base32 checks input length, map01 length, alphabet, then padding count.
The tests compare output bytes and full error messages, not Python error types.
Mojo errors use Error; empty optional byte lists represent Python None.

Memory: every codec writes through one pointer into spare capacity of the
caller's List: one `reserve` (exact, so capacity == length, no slack), one
uninitialized `resize`, no per-byte capacity check, no scratch buffer, no
String. Decode grows the list only on success, so an error leaves the caller's
prefix untouched. Alphabets live in static memory (`global_constant`, 64 B and
256 B tables, no per-call build); altchars and casefold patch a 256 B stack
copy. URL-safe encode picks its table at compile time; no second pass.
Base32 is still append-based (checked against CPython, not tuned).

Performance, real calls, 64 MiB x3 and 1 KiB x10000, core 2, three alternating
rounds, medians, GB/s. before = 269509f (b16: 875f25f), CPython 3.14.8:

| call | size | before | after | CPython |
|---|---|---|---|---|
| b64encode | 64 MiB | 0.550 | 1.227 | 0.774 |
| b64encode | 1 KiB | 0.683 | 2.015 | 1.133 |
| b64decode | 64 MiB | 0.668 | 1.280 | 0.644 |
| b64decode | 1 KiB | 0.613 | 1.189 | 0.798 |
| b16encode | 64 MiB | 0.659 | 1.212 | 0.283 |
| b16encode | 1 KiB | 0.649 | 1.698 | 0.535 |
| b16decode | 64 MiB | 0.239 | 1.300 | 0.469 |
| b16decode | 1 KiB | 0.238 | 1.432 | 0.491 |

Summary: b64encode 64 MiB 1.227 GB/s (was 0.550, CPython 0.774 GB/s).

Peak RSS, b64 only: 270152 KB before and 270144 KB after, CPython 250828 KB
(+7.7%). The result owns exactly its bytes; the gap is allocator retention
of freed 64-87 MiB blocks, the same with a bare `List` fill/drop. The bench
with b16 rows: 432700 KB, CPython 556764 KB. Bench numbers move 2x with host
load: pin one idle core, alternate, compare medians.
Base32 and sizes other than 1 KiB and 64 MiB were not benchmarked.

Build: scripts/capped.sh .venv/bin/mojo build -O3 -I src tests/bench.mojo -o .work/bench.
Compare: scripts/bench.sh BASELINE_BINARY .work/bench (three alternating rounds).
Reference: scripts/capped.sh python3 -I tools/bench_ref.py.

Verification: committed CPython vectors, a bit-at-a-time Mojo encoder oracle
on 10000 seeded random inputs (0..4096 bytes), append replay, and compiling
behavioral mutants. scripts/ci.sh runs the full stable gate; scripts/nightly.sh
precompiles the package and runs the same golden/brute/API/example entry points.
The CPython 3.14.0 strict pad order changed in maintenance versions; docs and
goldens name the tested maintenance versions rather than claiming all 3.14.

#!/usr/bin/env python3
import base64
import time
for n in (1024, 67108864):
    data = b'a' * n
    encoded = base64.b64encode(data)
    iterations = 10000 if n == 1024 else 3
    for label, call, value in (('encode', base64.b64encode, data), ('decode', base64.b64decode, encoded), ('b16encode', base64.b16encode, data), ('b16decode', base64.b16decode, base64.b16encode(data))):
        start = time.perf_counter_ns()
        checksum = sum(len(call(value)) for _ in range(iterations))
        elapsed = time.perf_counter_ns() - start
        print(label, 'bytes', n, 'iterations', iterations, 'GB/s', n * iterations / elapsed, 'checksum', checksum)

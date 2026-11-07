from std.collections import List, Array
from std.builtin.globals import global_constant

# 64 B alphabet tables, one cache line each, in static memory (no per-call build or copy).
def _enc_table(plus: UInt8, slash: UInt8) -> SIMD[DType.uint8, 64]:
    var t = SIMD[DType.uint8, 64](0)
    for i in range(26):
        t[i] = UInt8(65 + i)
        t[26 + i] = UInt8(97 + i)
    for i in range(10):
        t[52 + i] = UInt8(48 + i)
    t[62] = plus
    t[63] = slash
    return t

# 256 B decode table: value 0..63, 254 for '=', 255 for any other byte.
def _dec_table() -> SIMD[DType.uint8, 256]:
    var t = SIMD[DType.uint8, 256](255)
    var enc = _enc_table(43, 47)
    for i in range(64):
        t[Int(enc[i])] = UInt8(i)
    t[61] = 254
    return t

comptime _ENC_STD = _enc_table(43, 47)
comptime _ENC_URL = _enc_table(45, 95)
comptime _DEC_STD = _dec_table()

@always_inline
def _enc_ptr[url: Bool]() -> Pointer[UInt8, ImmStaticOrigin]:
    comptime if url:
        return Pointer(to=global_constant[_ENC_URL]()).unsafe_bitcast[UInt8]()
    else:
        return Pointer(to=global_constant[_ENC_STD]()).unsafe_bitcast[UInt8]()

@always_inline
def _dec_ptr() -> Pointer[UInt8, ImmStaticOrigin]:
    return Pointer(to=global_constant[_DEC_STD]()).unsafe_bitcast[UInt8]()

def _b64decode_into_kernel(s: Span[UInt8, _], mut out: List[Byte], altchars: Span[UInt8, _], strict: Bool) raises:
    var n = len(s)
    var has_alt = len(altchars) != 0
    if has_alt and len(altchars) != 2:
        raise Error(_bytes_repr(List[Byte](altchars)))

    # Alt chars patch a stack copy of the table (last mapping wins, as bytes.maketrans).
    var local = _DEC_STD
    if has_alt:
        local[Int(altchars[0])] = 62
        local[Int(altchars[1])] = 63
    var t = Pointer(to=local).unsafe_bitcast[UInt8]()
    var p = s.unsafe_ptr()
    # CPython translates altchars first, so a leading alt char that maps to '+' is not padding.
    if strict and n > 0 and t.unsafe_offset(Int(p.unsafe_offset(0)[]))[] == 254:
        raise Error("Leading padding not allowed")

    # The output is written through a raw pointer; `out` only grows on success, so an error
    # leaves the caller's list untouched.
    var orig_len = len(out)
    out.reserve(orig_len + ((n + 3) // 4) * 3)
    var o = out.unsafe_ptr().unsafe_offset(orig_len)
    var w = 0
    var quad_pos = 0
    var leftchar: Int = 0
    var pads = 0
    var i = 0

    # Fast path: clean 4-character groups
    while i + 4 <= n:
        var v0 = t.unsafe_offset(Int(p.unsafe_offset(i)[]))[]
        var v1 = t.unsafe_offset(Int(p.unsafe_offset(i + 1)[]))[]
        var v2 = t.unsafe_offset(Int(p.unsafe_offset(i + 2)[]))[]
        var v3 = t.unsafe_offset(Int(p.unsafe_offset(i + 3)[]))[]
        if ((v0 | v1 | v2 | v3) & 0xC0) != 0:
            break
        var trip = (Int(v0) << 18) | (Int(v1) << 12) | (Int(v2) << 6) | Int(v3)
        o.unsafe_offset(w)[] = UInt8(trip >> 16)
        o.unsafe_offset(w + 1)[] = UInt8((trip >> 8) & 255)
        o.unsafe_offset(w + 2)[] = UInt8(trip & 255)
        w += 3
        i += 4

    while i < n:
        var tv = t.unsafe_offset(Int(p.unsafe_offset(i)[]))[]
        if tv == 254:
            pads += 1
            if quad_pos >= 2 and quad_pos + pads <= 4:
                i += 1
                continue
            if strict:
                if quad_pos == 1:
                    break
                raise Error("Excess padding not allowed")
            i += 1
            continue
        if tv == 255:
            if strict:
                raise Error("Only base64 data is allowed")
            i += 1
            continue
        var v = Int(tv)
        if strict and pads != 0:
            if quad_pos + pads == 4:
                raise Error("Excess data after padding")
            raise Error("Discontinuous padding not allowed")
        pads = 0
        if quad_pos == 0:
            quad_pos = 1
            leftchar = v
        elif quad_pos == 1:
            quad_pos = 2
            o.unsafe_offset(w)[] = UInt8((leftchar << 2) | (v >> 4))
            w += 1
            leftchar = v & 15
        elif quad_pos == 2:
            quad_pos = 3
            o.unsafe_offset(w)[] = UInt8((leftchar << 4) | (v >> 2))
            w += 1
            leftchar = v & 3
        else:
            quad_pos = 0
            o.unsafe_offset(w)[] = UInt8((leftchar << 6) | v)
            w += 1
            leftchar = 0
        i += 1

    if quad_pos == 1:
        raise Error("Invalid base64-encoded string: number of data characters (" + String((w // 3) * 4 + 1) + ") cannot be 1 more than a multiple of 4")
    if quad_pos != 0 and quad_pos + pads < 4:
        raise Error("Incorrect padding")
    out.resize(unsafe_uninit_length=orig_len + w)

def b64encode(s: Span[UInt8, _]) -> List[Byte]:
    var out = List[Byte]()
    b64encode_into(s, out)
    return out^

def _b64encode_kernel[url: Bool](s: Span[UInt8, _], mut out: List[Byte]):
    var n = len(s)
    var base = len(out)
    out.reserve(base + ((n + 2) // 3) * 4)
    out.resize(unsafe_uninit_length=base + ((n + 2) // 3) * 4)
    var o = out.unsafe_ptr().unsafe_offset(base)
    var p = s.unsafe_ptr()
    var t = _enc_ptr[url]()
    var full = n // 3
    var i = 0
    var j = 0
    for _ in range(full):
        var b0 = Int(p.unsafe_offset(i)[])
        var b1 = Int(p.unsafe_offset(i + 1)[])
        var b2 = Int(p.unsafe_offset(i + 2)[])
        o.unsafe_offset(j)[] = t.unsafe_offset(b0 >> 2)[]
        o.unsafe_offset(j + 1)[] = t.unsafe_offset(((b0 & 3) << 4) | (b1 >> 4))[]
        o.unsafe_offset(j + 2)[] = t.unsafe_offset(((b1 & 15) << 2) | (b2 >> 6))[]
        o.unsafe_offset(j + 3)[] = t.unsafe_offset(b2 & 63)[]
        i += 3
        j += 4
    var rem = n - i
    if rem == 1:
        var b0 = Int(p.unsafe_offset(i)[])
        o.unsafe_offset(j)[] = t.unsafe_offset(b0 >> 2)[]
        o.unsafe_offset(j + 1)[] = t.unsafe_offset((b0 & 3) << 4)[]
        o.unsafe_offset(j + 2)[] = UInt8(ord('='))
        o.unsafe_offset(j + 3)[] = UInt8(ord('='))
    elif rem == 2:
        var b0 = Int(p.unsafe_offset(i)[])
        var b1 = Int(p.unsafe_offset(i + 1)[])
        o.unsafe_offset(j)[] = t.unsafe_offset(b0 >> 2)[]
        o.unsafe_offset(j + 1)[] = t.unsafe_offset(((b0 & 3) << 4) | (b1 >> 4))[]
        o.unsafe_offset(j + 2)[] = t.unsafe_offset((b1 & 15) << 2)[]
        o.unsafe_offset(j + 3)[] = UInt8(ord('='))

def b64encode_into(s: Span[UInt8, _], mut out: List[Byte]):
    _b64encode_kernel[False](s, out)

def _bytes_repr(data: List[Byte]) -> String:
    var single = False
    var double = False
    for i in range(len(data)):
        single = single or data[i] == 39
        double = double or data[i] == 34
    var quote = 34 if single and not double else 39
    var result = String("b") + chr(quote)
    comptime hexchars = "0123456789abcdef"
    for i in range(len(data)):
        var c = Int(data[i])
        if c == quote or c == 92:
            result += String("\\") + chr(c)
        elif c == 9: result += "\\t"
        elif c == 10: result += "\\n"
        elif c == 13: result += "\\r"
        elif c < 32 or c >= 127:
            result += String("\\x") + String(hexchars[byte=c >> 4]) + String(hexchars[byte=c & 15])
        else:
            result += chr(c)
    return result + chr(quote)

def b64decode(s: Span[UInt8, _], altchars: List[Byte] = List[Byte](), validate: Bool = False) raises -> List[Byte]:
    var out = List[Byte]()
    _b64decode_into_kernel(s, out, Span(altchars), validate)
    return out^

def b64decode_into(s: Span[UInt8, _], mut out: List[Byte], altchars: List[Byte] = List[Byte](), validate: Bool = False) raises:
    _b64decode_into_kernel(s, out, Span(altchars), validate)

# standard
def standard_b64encode(s: Span[UInt8, _]) -> List[Byte]:
    return b64encode(s)

def standard_b64encode_into(s: Span[UInt8, _], mut out: List[Byte]):
    b64encode_into(s, out)

def standard_b64decode(s: Span[UInt8, _], validate: Bool = False) raises -> List[Byte]:
    return b64decode(s, List[Byte](), validate)

def standard_b64decode_into(s: Span[UInt8, _], mut out: List[Byte], validate: Bool = False) raises:
    b64decode_into(s, out, List[Byte](), validate)

# urlsafe
def urlsafe_b64encode(s: Span[UInt8, _]) -> List[Byte]:
    var out = List[Byte]()
    urlsafe_b64encode_into(s, out)
    return out^

def urlsafe_b64encode_into(s: Span[UInt8, _], mut out: List[Byte]):
    _b64encode_kernel[True](s, out)

def urlsafe_b64decode(s: Span[UInt8, _], validate: Bool = False) raises -> List[Byte]:
    var out = List[Byte]()
    urlsafe_b64decode_into(s, out, validate)
    return out^

def urlsafe_b64decode_into(s: Span[UInt8, _], mut out: List[Byte], validate: Bool = False) raises:
    var alt = Array[UInt8, 2](fill=0)
    alt[0] = UInt8(ord('-'))
    alt[1] = UInt8(ord('_'))
    _b64decode_into_kernel(s, out, Span(alt), validate)

# b32
comptime _B32ALPHA = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
comptime _B32HEX = "0123456789ABCDEFGHIJKLMNOPQRSTUV"

@always_inline
def _make_b32_table(alphabet: String) -> Array[Int8, 256]:
    var t = Array[Int8, 256](fill=-1)
    for k in range(32):
        t[Int(ord(alphabet[byte=k]))] = Int8(k)
    return t^

def _b32encode_into_with(alphabet: String, s: Span[UInt8, _], mut out: List[Byte]):
    var n = len(s)
    var leftover = n % 5
    var i = 0
    while i + 5 <= n:
        var c = (Int(s[i]) << 32) | (Int(s[i+1]) << 24) | (Int(s[i+2]) << 16) | (Int(s[i+3]) << 8) | Int(s[i+4])
        out.append(UInt8(ord(alphabet[byte=(c >> 35) & 31])))
        out.append(UInt8(ord(alphabet[byte=(c >> 30) & 31])))
        out.append(UInt8(ord(alphabet[byte=(c >> 25) & 31])))
        out.append(UInt8(ord(alphabet[byte=(c >> 20) & 31])))
        out.append(UInt8(ord(alphabet[byte=(c >> 15) & 31])))
        out.append(UInt8(ord(alphabet[byte=(c >> 10) & 31])))
        out.append(UInt8(ord(alphabet[byte=(c >> 5) & 31])))
        out.append(UInt8(ord(alphabet[byte=c & 31])))
        i += 5
    if leftover != 0:
        var tail = Array[UInt8, 5](fill=0)
        for k in range(leftover):
            tail[k] = s[i + k]
        var c = (Int(tail[0]) << 32) | (Int(tail[1]) << 24) | (Int(tail[2]) << 16) | (Int(tail[3]) << 8) | Int(tail[4])
        out.append(UInt8(ord(alphabet[byte=(c >> 35) & 31])))
        out.append(UInt8(ord(alphabet[byte=(c >> 30) & 31])))
        out.append(UInt8(ord(alphabet[byte=(c >> 25) & 31])))
        out.append(UInt8(ord(alphabet[byte=(c >> 20) & 31])))
        out.append(UInt8(ord(alphabet[byte=(c >> 15) & 31])))
        out.append(UInt8(ord(alphabet[byte=(c >> 10) & 31])))
        out.append(UInt8(ord(alphabet[byte=(c >> 5) & 31])))
        out.append(UInt8(ord(alphabet[byte=c & 31])))
        var L = len(out)
        if leftover == 1:
            for j in range(L-6, L):
                out[j] = UInt8(ord('='))
        elif leftover == 2:
            for j in range(L-4, L):
                out[j] = UInt8(ord('='))
        elif leftover == 3:
            for j in range(L-3, L):
                out[j] = UInt8(ord('='))
        elif leftover == 4:
            out[L-1] = UInt8(ord('='))

def b32encode(s: Span[UInt8, _]) -> List[Byte]:
    var out = List[Byte]()
    out.reserve(((len(s) + 4) // 5) * 8)
    b32encode_into(s, out)
    return out^

def b32encode_into(s: Span[UInt8, _], mut out: List[Byte]):
    _b32encode_into_with(_B32ALPHA, s, out)

def _b32decode_into_with(alphabet: String, s: Span[UInt8, _], mut out: List[Byte], casefold: Bool, map01: Span[UInt8, _]) raises:
    var l = len(s)
    if l % 8 != 0:
        raise Error("Incorrect padding")
    var has_map01 = len(map01) != 0
    if has_map01:
        if len(map01) != 1:
            raise Error(_bytes_repr(List[Byte](map01)))

    var end = l
    while end > 0 and s[end - 1] == UInt8(ord('=')):
        end -= 1
    var padchars = l - end

    var t = _make_b32_table(alphabet)
    var idx = 0
    var acc_last: Int = 0
    while idx + 8 <= end:
        var acc: Int = 0
        for k in range(8):
            var c = s[idx + k]
            if has_map01:
                if c == UInt8(ord('0')):
                    c = UInt8(ord('O'))
                elif c == UInt8(ord('1')):
                    c = map01[0]
            if casefold and c >= 97 and c <= 122:
                c -= 32
            var v = Int(t[Int(c)])
            if v < 0:
                raise Error("Non-base32 digit found")
            acc = (acc << 5) + v
        out.append(UInt8((acc >> 32) & 255))
        out.append(UInt8((acc >> 24) & 255))
        out.append(UInt8((acc >> 16) & 255))
        out.append(UInt8((acc >> 8) & 255))
        out.append(UInt8(acc & 255))
        acc_last = acc
        idx += 8

    if idx < end:
        var acc: Int = 0
        var cnt = end - idx
        for k in range(cnt):
            var c = s[idx + k]
            if has_map01:
                if c == UInt8(ord('0')):
                    c = UInt8(ord('O'))
                elif c == UInt8(ord('1')):
                    c = map01[0]
            if casefold and c >= 97 and c <= 122:
                c -= 32
            var v = Int(t[Int(c)])
            if v < 0:
                raise Error("Non-base32 digit found")
            acc = (acc << 5) + v
        out.append(UInt8((acc >> 32) & 255))
        out.append(UInt8((acc >> 24) & 255))
        out.append(UInt8((acc >> 16) & 255))
        out.append(UInt8((acc >> 8) & 255))
        out.append(UInt8(acc & 255))
        acc_last = acc

    if padchars not in (0, 1, 3, 4, 6):
        raise Error("Incorrect padding")

    if padchars != 0 and len(out) > 0:
        acc_last <<= 5 * padchars
        var b0 = UInt8((acc_last >> 32) & 255)
        var b1 = UInt8((acc_last >> 24) & 255)
        var b2 = UInt8((acc_last >> 16) & 255)
        var b3 = UInt8((acc_last >> 8) & 255)
        var b4 = UInt8(acc_last & 255)
        var lastbytes = Array[UInt8, 5](fill=0)
        lastbytes[0] = b0
        lastbytes[1] = b1
        lastbytes[2] = b2
        lastbytes[3] = b3
        lastbytes[4] = b4
        var leftover = (43 - 5 * padchars) // 8
        var newlen = len(out) - (5 - leftover)
        while len(out) > newlen:
            _ = out.pop()
        var base2 = len(out) - leftover
        if base2 < 0:
            base2 = 0
        for k in range(leftover):
            if base2 + k < len(out):
                out[base2 + k] = lastbytes[k]
            else:
                out.append(lastbytes[k])

def b32decode(s: Span[UInt8, _], casefold: Bool = False, map01: List[Byte] = List[Byte]()) raises -> List[Byte]:
    var out = List[Byte]()
    out.reserve((len(s) * 5) // 8 + 5)
    b32decode_into(s, out, casefold, map01)
    return out^

def b32decode_into(s: Span[UInt8, _], mut out: List[Byte], casefold: Bool = False, map01: List[Byte] = List[Byte]()) raises:
    var orig_len = len(out)
    try:
        _b32decode_into_with(_B32ALPHA, s, out, casefold, Span(map01))
    except e:
        while len(out) > orig_len:
            _ = out.pop()
        raise e

def b32hexdecode(s: Span[UInt8, _], casefold: Bool = False) raises -> List[Byte]:
    var out = List[Byte]()
    out.reserve((len(s) * 5) // 8 + 5)
    b32hexdecode_into(s, out, casefold)
    return out^

def b32hexdecode_into(s: Span[UInt8, _], mut out: List[Byte], casefold: Bool = False) raises:
    var empty = List[Byte]()
    var orig_len = len(out)
    try:
        _b32decode_into_with(_B32HEX, s, out, casefold, Span(empty))
    except e:
        while len(out) > orig_len:
            _ = out.pop()
        raise e

def b32hexencode(s: Span[UInt8, _]) -> List[Byte]:
    var out = List[Byte]()
    out.reserve(((len(s) + 4) // 5) * 8)
    b32hexencode_into(s, out)
    return out^

def b32hexencode_into(s: Span[UInt8, _], mut out: List[Byte]):
    _b32encode_into_with(_B32HEX, s, out)

# b16
def _hex_table() -> SIMD[DType.uint8, 16]:
    var t = SIMD[DType.uint8, 16](0)
    for i in range(10):
        t[i] = UInt8(48 + i)
    for i in range(6):
        t[10 + i] = UInt8(65 + i)
    return t

# value 0..15, 255 for anything that is not an uppercase hex digit
def _hexdec_table() -> SIMD[DType.uint8, 256]:
    var t = SIMD[DType.uint8, 256](255)
    var h = _hex_table()
    for i in range(16):
        t[Int(h[i])] = UInt8(i)
    return t

comptime _HEX = _hex_table()
comptime _HEXDEC = _hexdec_table()

def b16encode(s: Span[UInt8, _]) -> List[Byte]:
    var out = List[Byte]()
    b16encode_into(s, out)
    return out^

def b16encode_into(s: Span[UInt8, _], mut out: List[Byte]):
    var n = len(s)
    var base = len(out)
    out.reserve(base + n * 2)
    out.resize(unsafe_uninit_length=base + n * 2)
    var o = out.unsafe_ptr().unsafe_offset(base)
    var p = s.unsafe_ptr()
    var t = Pointer(to=global_constant[_HEX]()).unsafe_bitcast[UInt8]()
    for j in range(n):
        var b = Int(p.unsafe_offset(j)[])
        o.unsafe_offset(2 * j)[] = t.unsafe_offset(b >> 4)[]
        o.unsafe_offset(2 * j + 1)[] = t.unsafe_offset(b & 15)[]

def _b16decode_into_kernel(s: Span[UInt8, _], mut out: List[Byte], casefold: Bool) raises:
    var n = len(s)
    var local = _HEXDEC
    if casefold:
        for i in range(6):
            local[97 + i] = UInt8(10 + i)
    var t = Pointer(to=local).unsafe_bitcast[UInt8]()
    var p = s.unsafe_ptr()
    var orig_len = len(out)
    out.reserve(orig_len + n // 2)
    var o = out.unsafe_ptr().unsafe_offset(orig_len)
    var bad: UInt8 = 0
    var j = 0
    while j + 1 < n:
        var hi = t.unsafe_offset(Int(p.unsafe_offset(j)[]))[]
        var lo = t.unsafe_offset(Int(p.unsafe_offset(j + 1)[]))[]
        bad |= hi | lo
        o.unsafe_offset(j // 2)[] = (hi << 4) | (lo & 15)
        j += 2
    if j < n:
        bad |= t.unsafe_offset(Int(p.unsafe_offset(j)[]))[]
    # CPython checks every digit (regex) before the length (unhexlify)
    if bad > 15:
        raise Error("Non-base16 digit found")
    if n % 2 != 0:
        raise Error("Odd-length string")
    out.resize(unsafe_uninit_length=orig_len + n // 2)

def b16decode(s: Span[UInt8, _], casefold: Bool = False) raises -> List[Byte]:
    var out = List[Byte]()
    _b16decode_into_kernel(s, out, casefold)
    return out^

def b16decode_into(s: Span[UInt8, _], mut out: List[Byte], casefold: Bool = False) raises:
    _b16decode_into_kernel(s, out, casefold)

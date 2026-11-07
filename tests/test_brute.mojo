from base64 import *
from std.testing import assert_equal

def reference(data: Span[UInt8, _], alphabet: String, width: Int, quantum: Int) -> List[Byte]:
    # Independent bit-at-a-time oracle, no production grouping or reverse table.
    var result = List[Byte]()
    var value = 0
    var bits = 0
    for i in range(len(data)):
        for bit in range(7, -1, -1):
            value = value * 2 + (Int(data[i]) // (1 << bit)) % 2
            bits += 1
            if bits == width:
                result.append(UInt8(ord(alphabet[byte=value])))
                value = 0
                bits = 0
    if bits:
        value *= 1 << (width - bits)
        result.append(UInt8(ord(alphabet[byte=value])))
    while len(result) % quantum:
        result.append(61)
    return result^

def main() raises:
    var state = UInt64(42)
    for trial in range(10000):
        state = state * 6364136223846793005 + 1
        var data = List[Byte]()
        var n = Int((state >> 32) % 4097)
        for i in range(n):
            state = state * 6364136223846793005 + 1
            data.append(UInt8(state >> 32))
        var sp = Span(data)
        var encoded = b64encode(sp)
        assert_equal(encoded, reference(sp, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/", 6, 4))
        assert_equal(b64decode(encoded), data)
        var encoded32 = b32encode(sp)
        assert_equal(encoded32, reference(sp, "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567", 5, 8))
        assert_equal(b32decode(encoded32), data)
        var encodedhex = b32hexencode(sp)
        assert_equal(encodedhex, reference(sp, "0123456789ABCDEFGHIJKLMNOPQRSTUV", 5, 8))
        assert_equal(b32hexdecode(encodedhex), data)
        var encoded16 = b16encode(sp)
        assert_equal(encoded16, reference(sp, "0123456789ABCDEF", 4, 1))
        assert_equal(b16decode(encoded16), data)
        var url = urlsafe_b64encode(sp)
        assert_equal(urlsafe_b64decode(url), data)
    print("PASS brute: 10000 random inputs, lengths 0..4096, five codecs")

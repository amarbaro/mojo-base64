from base64 import b64encode
from std.collections import List
from std.testing import assert_equal

def main() raises:
    var s = List[Byte]()
    s.append(UInt8(ord('a')))
    var sp = Span[UInt8, _](list=s)
    var e = b64encode(sp)
    assert_equal(len(e), 4)
    print("PASS")

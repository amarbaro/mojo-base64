from base64 import b64encode, b64decode
from std.testing import assert_equal

def main() raises:
    var data = List[Byte]()
    data.append(97)
    var encoded = b64encode(data)
    var text = String("")
    for i in range(len(encoded)):
        text += chr(Int(encoded[i]))
    assert_equal(text, "YQ==")
    assert_equal(b64decode(encoded), data)
    print(text)

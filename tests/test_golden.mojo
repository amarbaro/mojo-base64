from std.testing import assert_equal, assert_true
from std.sys import argv
from support import replay

def main() raises:
    var text = String("")
    var path = String("tests/golden/basic.txt")
    if len(argv()) > 1:
        path = String(argv()[1])
    with open(path, "r") as source:
        text = source.read()
    var rows = 0
    var errors = 0
    var successes = 0
    for line in text.split("\n"):
        if line.byte_length() == 0:
            continue
        var fields = line.split("\t")
        assert_equal(len(fields), 7)
        var expected = String(fields[0]) + "\t" + String(fields[5]) + "\t" + String(fields[6])
        var actual = replay(String(line), False)
        if actual != expected:
            print("FAIL vector", line)
            print("got", actual)
        assert_equal(actual, expected)
        # Replay each operation through append APIs, preserving a caller prefix.
        assert_equal(replay(String(line), True), expected)
        rows += 1
        if fields[5] == "err":
            errors += 1
        else:
            successes += 1
    assert_true(rows > 1000)
    assert_true(errors > 100)
    assert_true(successes > 100)
    print("PASS goldens", rows, "errors", errors, "successes", successes)

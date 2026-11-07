from support import replay

def main() raises:
    var text = String("")
    with open("tests/golden/basic.txt", "r") as source:
        text = source.read()
    for line in text.split("\n"):
        if line.byte_length() > 0:
            print(replay(String(line), False))

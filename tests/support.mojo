from base64 import *

def unhex(text: String) -> List[Byte]:
    var result = List[Byte]()
    for i in range(0, text.byte_length(), 2):
        var a = Int(text.as_bytes()[i])
        var b = Int(text.as_bytes()[i+1])
        result.append(UInt8((a - 48 if a <= 57 else a - 87) * 16 + (b - 48 if b <= 57 else b - 87)))
    return result^

def hexbytes(data: List[Byte]) -> String:
    var result = String("")
    comptime digits = "0123456789abcdef"
    for i in range(len(data)):
        result += String(digits[byte=Int(data[i]) >> 4])
        result += String(digits[byte=Int(data[i]) & 15])
    return result

def invoke(op: String, data: Span[UInt8, _], flag: Bool, extra: List[Byte], into: Bool) raises -> List[Byte]:
    var result = List[Byte]()
    if into:
        result.append(173)
        if op == "b64encode": b64encode_into(data, result)
        elif op == "b64decode": b64decode_into(data, result, extra, flag)
        elif op == "standard_b64encode": standard_b64encode_into(data, result)
        elif op == "standard_b64decode": standard_b64decode_into(data, result, flag)
        elif op == "urlsafe_b64encode": urlsafe_b64encode_into(data, result)
        elif op == "urlsafe_b64decode": urlsafe_b64decode_into(data, result, flag)
        elif op == "b32encode": b32encode_into(data, result)
        elif op == "b32decode": b32decode_into(data, result, flag, extra)
        elif op == "b32hexencode": b32hexencode_into(data, result)
        elif op == "b32hexdecode": b32hexdecode_into(data, result, flag)
        elif op == "b16encode": b16encode_into(data, result)
        elif op == "b16decode": b16decode_into(data, result, flag)
        else: raise Error("unknown operation")
        if result[0] != 173: raise Error("append prefix overwritten")
        return List[Byte](Span(result)[1:])
    if op == "b64encode": return b64encode(data)
    if op == "b64decode": return b64decode(data, extra, flag)
    if op == "standard_b64encode": return standard_b64encode(data)
    if op == "standard_b64decode": return standard_b64decode(data, flag)
    if op == "urlsafe_b64encode": return urlsafe_b64encode(data)
    if op == "urlsafe_b64decode": return urlsafe_b64decode(data, flag)
    if op == "b32encode": return b32encode(data)
    if op == "b32decode": return b32decode(data, flag, extra)
    if op == "b32hexencode": return b32hexencode(data)
    if op == "b32hexdecode": return b32hexdecode(data, flag)
    if op == "b16encode": return b16encode(data)
    if op == "b16decode": return b16decode(data, flag)
    raise Error("unknown operation")

def replay(row: String, into: Bool) raises -> String:
    var fields = row.split("\t")
    var data = unhex(String(fields[2]))
    var extra = unhex(String(fields[4]))
    var status = String("ok")
    var value = String("")
    try:
        var result = invoke(String(fields[1]), data, fields[3] == "1", extra, into)
        value = hexbytes(result)
    except error:
        status = "err"
        value = String(error)
    return String(fields[0]) + "\t" + status + "\t" + value

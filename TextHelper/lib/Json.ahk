#Requires AutoHotkey v2.0

; Минимальный JSON для TextHelper.
; JsonLoad: объекты -> Map, массивы -> Array, true/false -> 1/0, null -> "".
; JsonDump: Map/Array/объекты/числа/строки -> JSON-текст.

JsonLoad(src) {
    pos := 1
    value := _JsonValue(src, &pos)
    _JsonSkipWs(src, &pos)
    if pos <= StrLen(src)
        throw ValueError("JSON: лишние символы в позиции " pos)
    return value
}

JsonDump(value) {
    if value is Map {
        out := ""
        for key, item in value
            out .= (A_Index = 1 ? "" : ",") JsonQuote(String(key)) ":" JsonDump(item)
        return "{" out "}"
    }
    if value is Array {
        out := ""
        for item in value
            out .= (A_Index = 1 ? "" : ",") JsonDump(item)
        return "[" out "]"
    }
    if value is Integer || value is Float
        return String(value)
    if IsObject(value) {
        out := ""
        for key, item in value.OwnProps()
            out .= (A_Index = 1 ? "" : ",") JsonQuote(key) ":" JsonDump(item)
        return "{" out "}"
    }
    return JsonQuote(value)
}

JsonQuote(str) {
    str := StrReplace(str, "\", "\\")
    str := StrReplace(str, '"', '\"')
    str := StrReplace(str, "`n", "\n")
    str := StrReplace(str, "`r", "\r")
    str := StrReplace(str, "`t", "\t")
    while RegExMatch(str, "[\x01-\x1F]", &m)
        str := StrReplace(str, m[0], Format("\u{:04X}", Ord(m[0])))
    return '"' str '"'
}

_JsonSkipWs(src, &pos) {
    while pos <= StrLen(src) && InStr(" `t`r`n", SubStr(src, pos, 1))
        pos++
}

_JsonValue(src, &pos) {
    _JsonSkipWs(src, &pos)
    c := SubStr(src, pos, 1)
    switch c {
        case "{":
            obj := Map()
            pos++
            _JsonSkipWs(src, &pos)
            if SubStr(src, pos, 1) = "}" {
                pos++
                return obj
            }
            loop {
                _JsonSkipWs(src, &pos)
                if SubStr(src, pos, 1) != '"'
                    throw ValueError("JSON: ожидался ключ в позиции " pos)
                key := _JsonString(src, &pos)
                _JsonSkipWs(src, &pos)
                if SubStr(src, pos, 1) != ":"
                    throw ValueError("JSON: ожидалось ':' в позиции " pos)
                pos++
                obj[key] := _JsonValue(src, &pos)
                _JsonSkipWs(src, &pos)
                c := SubStr(src, pos++, 1)
                if c = "}"
                    return obj
                if c != ","
                    throw ValueError("JSON: ожидалось ',' или '}' в позиции " pos - 1)
            }
        case "[":
            arr := []
            pos++
            _JsonSkipWs(src, &pos)
            if SubStr(src, pos, 1) = "]" {
                pos++
                return arr
            }
            loop {
                arr.Push(_JsonValue(src, &pos))
                _JsonSkipWs(src, &pos)
                c := SubStr(src, pos++, 1)
                if c = "]"
                    return arr
                if c != ","
                    throw ValueError("JSON: ожидалось ',' или ']' в позиции " pos - 1)
            }
        case '"':
            return _JsonString(src, &pos)
        default:
            for word, result in Map("true", 1, "false", 0, "null", "") {
                if SubStr(src, pos, StrLen(word)) == word {
                    pos += StrLen(word)
                    return result
                }
            }
            start := pos
            while pos <= StrLen(src) && InStr("+-0123456789.eE", SubStr(src, pos, 1), true)
                pos++
            num := SubStr(src, start, pos - start)
            if num = ""
                throw ValueError("JSON: неожиданный символ в позиции " start)
            return IsNumber(num) ? num + 0 : num
    }
}

; pos указывает на открывающую кавычку; после вызова — на символ за закрывающей.
_JsonString(src, &pos) {
    pos++
    out := ""
    slash := 0
    loop {
        quote := InStr(src, '"', true, pos)
        if !quote
            throw ValueError("JSON: незакрытая строка")
        if slash < pos
            slash := InStr(src, "\", true, pos) || StrLen(src) + 1
        if quote < slash {
            out .= SubStr(src, pos, quote - pos)
            pos := quote + 1
            return out
        }
        out .= SubStr(src, pos, slash - pos)
        esc := SubStr(src, slash + 1, 1)
        pos := slash + 2
        switch esc, true {
            case '"', "\", "/": out .= esc
            case "n": out .= "`n"
            case "r": out .= "`r"
            case "t": out .= "`t"
            case "b": out .= "`b"
            case "f": out .= "`f"
            case "u":
                code := Integer("0x" SubStr(src, pos, 4))
                pos += 4
                ; Суррогатная пара 😀 -> один символ.
                if code >= 0xD800 && code <= 0xDBFF && SubStr(src, pos, 2) == "\u" {
                    low := Integer("0x" SubStr(src, pos + 2, 4))
                    if low >= 0xDC00 && low <= 0xDFFF {
                        code := 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                        pos += 6
                    }
                }
                out .= Chr(code)
            default:
                throw ValueError("JSON: неизвестная escape-последовательность \" esc)
        }
    }
}

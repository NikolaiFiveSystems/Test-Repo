#Requires AutoHotkey v2.0

; HTTP-запрос через WinHTTP. Тело отправляется и читается как UTF-8.
; headers — Map("Имя", "значение"). Возвращает {status, body}.
HttpPost(url, body, headers, proxy := "") {
    req := ComObject("WinHttp.WinHttpRequest.5.1")
    req.Open("POST", url, false)
    ; DNS, соединение, отправка, ожидание ответа (мс)
    req.SetTimeouts(15000, 15000, 30000, 120000)
    if proxy != ""
        req.SetProxy(2, proxy, "<local>")
    for name, value in headers
        req.SetRequestHeader(name, value)
    try {
        req.Send(Utf8Bytes(body))
    } catch as e {
        host := RegExReplace(url, "^\w+://([^/]+).*$", "$1")
        msg := "Не удалось связаться с " host "."
        if InStr(e.Message, "80072F8F") || InStr(e.Message, "80072F0D") || InStr(e.Message, "80072F06")
            msg .= "`nСервер использует сертификат, которому Windows не доверяет."
                . "`nДля GigaChat установите сертификат «Russian Trusted Root CA» (см. README)."
        else if InStr(e.Message, "80072EE2")
            msg .= "`nПревышено время ожидания."
        else if InStr(e.Message, "80072EFD") && RegExMatch(host, "i)^(localhost|127\.0\.0\.1)(:|$)")
            msg .= "`nЛокальная модель не отвечает — запущена ли Ollama?"
        throw Error(msg "`n`n" e.Message)
    }
    return {status: req.Status, body: Utf8FromBytes(req.ResponseBody)}
}

; Строка -> массив байтов UTF-8 (SAFEARRAY VT_UI1), как требует WinHttpRequest.Send.
Utf8Bytes(str) {
    size := StrPut(str, "UTF-8") - 1
    buf := Buffer(size + 1)
    StrPut(str, buf, "UTF-8")
    arr := ComObjArray(0x11, size)
    if size {
        DllCall("OleAut32\SafeArrayAccessData", "Ptr", ComObjValue(arr), "Ptr*", &data := 0)
        DllCall("RtlMoveMemory", "Ptr", data, "Ptr", buf, "UPtr", size)
        DllCall("OleAut32\SafeArrayUnaccessData", "Ptr", ComObjValue(arr))
    }
    return arr
}

Utf8FromBytes(arr) {
    if !(ComObjType(arr) & 0x2000)
        return ""
    size := arr.MaxIndex() + 1
    if size <= 0
        return ""
    DllCall("OleAut32\SafeArrayAccessData", "Ptr", ComObjValue(arr), "Ptr*", &data := 0)
    text := StrGet(data, size, "UTF-8")
    DllCall("OleAut32\SafeArrayUnaccessData", "Ptr", ComObjValue(arr))
    return text
}

; Кодирование для application/x-www-form-urlencoded (UTF-8).
UrlEncode(str) {
    buf := Buffer(StrPut(str, "UTF-8"))
    size := StrPut(str, buf, "UTF-8") - 1
    out := ""
    loop size {
        b := NumGet(buf, A_Index - 1, "UChar")
        if (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
            || b = 0x2D || b = 0x2E || b = 0x5F || b = 0x7E
            out .= Chr(b)
        else
            out .= Format("%{:02X}", b)
    }
    return out
}

NewUuid() {
    guid := Buffer(16)
    DllCall("ole32\CoCreateGuid", "Ptr", guid)
    buf := Buffer(39 * 2)
    DllCall("ole32\StringFromGUID2", "Ptr", guid, "Ptr", buf, "Int", 39)
    return StrLower(Trim(StrGet(buf), "{}"))
}

UnixTimeMs() {
    return DateDiff(A_NowUTC, "19700101000000", "Seconds") * 1000
}

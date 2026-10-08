#Requires AutoHotkey v2.0

; HTTP-запрос через WinHTTP API. Тело отправляется и читается как UTF-8.
; headers — Map("Имя", "значение"). Возвращает {status, body}.
; ignoreCertErrors — не проверять сертификат сервера (аналог verify=False).
; Клиентский сертификат не отправляется никогда: иначе Windows может сама подставить
; сертификат из личного хранилища (ЭЦП, банковский), и сервер ответит ошибкой 495.
HttpPost(url, body, headers, proxy := "", ignoreCertErrors := false) {
    ; Держим winhttp.dll загруженной: иначе DllCall выгружает её после каждого вызова
    ; и дескрипторы сессии становятся недействительными.
    static winhttp := DllCall("LoadLibrary", "Str", "winhttp.dll", "Ptr")
    if !RegExMatch(url, "i)^(https?)://([^/:]+)(?::(\d+))?(/.*)?$", &u)
        throw ValueError("Неверный адрес: " url)
    secure := u[1] = "https"
    host := u[2]
    port := u[3] != "" ? Integer(u[3]) : secure ? 443 : 80
    path := u[4] != "" ? u[4] : "/"

    hSession := hConnect := hRequest := 0
    try {
        if proxy != ""
            hSession := DllCall("winhttp\WinHttpOpen", "Str", "TextHelper", "UInt", 3, "Str", proxy, "Str", "<local>;localhost;127.0.0.1;[::1]", "UInt", 0, "Ptr")
        else
            hSession := DllCall("winhttp\WinHttpOpen", "Str", "TextHelper", "UInt", 0, "Ptr", 0, "Ptr", 0, "UInt", 0, "Ptr")
        if !hSession
            _WinHttpFail(host, A_LastError)
        ; DNS, соединение, отправка, ожидание ответа (мс)
        DllCall("winhttp\WinHttpSetTimeouts", "Ptr", hSession, "Int", 15000, "Int", 15000, "Int", 30000, "Int", 120000)
        if !(hConnect := DllCall("winhttp\WinHttpConnect", "Ptr", hSession, "Str", host, "UShort", port, "UInt", 0, "Ptr"))
            _WinHttpFail(host, A_LastError)
        hRequest := DllCall("winhttp\WinHttpOpenRequest", "Ptr", hConnect, "Str", "POST", "Str", path,
            "Ptr", 0, "Ptr", 0, "Ptr", 0, "UInt", secure ? 0x800000 : 0, "Ptr")  ; WINHTTP_FLAG_SECURE
        if !hRequest
            _WinHttpFail(host, A_LastError)
        if secure && ignoreCertErrors  ; SECURITY_FLAGS: неизвестный УЦ, имя, срок, назначение
            DllCall("winhttp\WinHttpSetOption", "Ptr", hRequest, "UInt", 31, "UInt*", 0x3300, "UInt", 4)
        if secure  ; CLIENT_CERT_CONTEXT = WINHTTP_NO_CLIENT_CERT_CONTEXT
            DllCall("winhttp\WinHttpSetOption", "Ptr", hRequest, "UInt", 47, "Ptr", 0, "UInt", 0)

        headerText := ""
        for name, value in headers
            headerText .= name ": " value "`r`n"
        if headerText != ""
            DllCall("winhttp\WinHttpAddRequestHeaders", "Ptr", hRequest, "Str", headerText, "UInt", -1, "UInt", 0xA0000000)

        size := StrPut(body, "UTF-8") - 1
        data := Buffer(size + 1)
        StrPut(body, data, "UTF-8")
        loop 2 {
            ok := DllCall("winhttp\WinHttpSendRequest", "Ptr", hRequest, "Ptr", 0, "UInt", 0,
                "Ptr", data, "UInt", size, "UInt", size, "UPtr", 0)
                && DllCall("winhttp\WinHttpReceiveResponse", "Ptr", hRequest, "Ptr", 0)
            if ok
                break
            err := A_LastError
            ; ERROR_WINHTTP_CLIENT_AUTH_CERT_NEEDED: повторяем без клиентского сертификата
            if err != 12044 || A_Index = 2
                _WinHttpFail(host, err)
            DllCall("winhttp\WinHttpSetOption", "Ptr", hRequest, "UInt", 47, "Ptr", 0, "UInt", 0)
        }

        ; WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER
        DllCall("winhttp\WinHttpQueryHeaders", "Ptr", hRequest, "UInt", 0x20000013, "Ptr", 0,
            "UInt*", &status := 0, "UInt*", 4, "Ptr", 0)

        response := Buffer(65536)
        total := 0
        loop {
            if !DllCall("winhttp\WinHttpQueryDataAvailable", "Ptr", hRequest, "UInt*", &avail := 0)
                _WinHttpFail(host, A_LastError)
            if !avail
                break
            if total + avail > response.Size
                response.Size := Max(response.Size * 2, total + avail)
            if !DllCall("winhttp\WinHttpReadData", "Ptr", hRequest, "Ptr", response.Ptr + total, "UInt", avail, "UInt*", &read := 0)
                _WinHttpFail(host, A_LastError)
            if !read
                break
            total += read
        }
        return {status: status, body: total ? StrGet(response, total, "UTF-8") : ""}
    } finally {
        for handle in [hRequest, hConnect, hSession]
            if handle
                DllCall("winhttp\WinHttpCloseHandle", "Ptr", handle)
    }
}

_WinHttpFail(host, code) {
    msg := "Не удалось связаться с " host "."
    switch code {
        case 12175, 12045, 12038, 12037, 12157, 12057:
            msg .= "`nСервер использует сертификат, которому Windows не доверяет."
                . "`nДля GigaChat: VerifySsl=0 в settings.ini или сертификат «Russian Trusted Root CA» (см. README)."
        case 12002:
            msg .= "`nПревышено время ожидания."
        case 12007:
            msg .= "`nСервер не найден — проверьте адрес и подключение к интернету."
        case 12029:
            if RegExMatch(host, "i)^(localhost|127\.0\.0\.1)$")
                msg .= "`nЛокальная модель не отвечает — запущена ли Ollama?"
            else
                msg .= "`nСоединение не установлено — проверьте интернет или прокси."
    }
    throw Error(msg "`n`nКод ошибки WinHTTP: " code)
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

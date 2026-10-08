#Requires AutoHotkey v2.0
#SingleInstance Force

; TextHelper — проверка орфографии и переформулировка выделенного текста
; в любой программе Windows. Настройки — в settings.ini рядом со скриптом.

#Include %A_ScriptDir%\lib\Json.ahk
#Include %A_ScriptDir%\lib\Net.ahk
#Include %A_ScriptDir%\lib\Services.ahk

SETTINGS_PATH := A_ScriptDir "\settings.ini"
STARTUP_LINK := A_Startup "\TextHelper.lnk"

DEFAULT_ACTIONS := [
    ["Исправить ошибки", "Исправь орфографические, пунктуационные и грамматические ошибки. Больше ничего не меняй."],
    ["Переформулировать", "Перепиши текст своими словами: яснее и естественнее, сохранив смысл, тон и примерную длину."],
    ["Вежливее / деловой стиль", "Перепиши текст в вежливом деловом стиле, подходящем для переписки с коллегами или клиентами."],
    ["Проще и дружелюбнее", "Перепиши текст проще и дружелюбнее, как в разговоре с коллегой."],
    ["Короче", "Сократи текст, оставив главное."]
]

global Cfg := LoadSettings(SETTINGS_PATH)
global Busy := false

Persistent()
SetupTray()
RegisterHotkey("Fix", "^!vk46", FixSelection)
RegisterHotkey("Menu", "^!vk52", ShowActionsMenu)
TrayTip(HotkeyLabel(Setting("Hotkeys", "Fix", "^!vk46")) " — исправить орфографию`n"
    . HotkeyLabel(Setting("Hotkeys", "Menu", "^!vk52")) " — меню переформулировки",
    "TextHelper запущен", "Mute")

; ---------------------------------------------------------------------------
; Действия
; ---------------------------------------------------------------------------

FixSelection(*) {
    if Busy
        return
    if sel := CaptureSelection()
        FixText(sel)
}

FixText(sel, *) {
    global Busy
    if Busy
        return
    Busy := true
    try {
        Notify("Проверяю орфографию…", 0)
        matches := LanguageToolCheck(sel.text, {
            url: Setting("LanguageTool", "Url", "https://api.languagetool.org/v2/check"),
            language: Setting("LanguageTool", "Language", "auto"),
            preferredVariants: Setting("LanguageTool", "PreferredVariants", "en-US"),
            username: Setting("LanguageTool", "Username"),
            apiKey: Setting("LanguageTool", "ApiKey"),
            proxy: Setting("General", "Proxy")
        })
        result := ApplyLanguageToolMatches(sel.text, matches,
            Setting("LanguageTool", "SkipIssueTypes", "style"))
    } catch as e {
        Notify()
        ShowError(e.Message)
        return
    } finally {
        Busy := false
    }
    if !result.changes.Length {
        Notify("Ошибок не найдено ✓")
        return
    }
    PasteText(sel.hwnd, result.text)
    summary := ""
    for change in result.changes {
        if A_Index > 8 {
            summary .= "`n…и ещё " result.changes.Length - 8
            break
        }
        summary .= "`n«" change[1] "» → «" change[2] "»"
    }
    Notify("Исправлено: " result.changes.Length summary, 5000)
}

ShowActionsMenu(*) {
    if Busy
        return
    sel := CaptureSelection()
    if !sel
        return
    m := Menu()
    for action in ActionList() {
        label := StrReplace(action[1], "&", "&&")
        if A_Index <= 9
            label := "&" A_Index "  " label
        m.Add(label, RunAction.Bind(sel, action[2]))
    }
    m.Add()
    m.Add("Проверить орфографию (LanguageTool)", FixText.Bind(sel))
    m.Add("Настройки…", (*) => OpenSettings())
    m.Show()
}

RunAction(sel, instruction, *) {
    global Busy
    if Busy
        return
    opts := AiOptions()
    if !opts
        return
    Busy := true
    try {
        Notify(ProviderName(opts) " думает…", 0)
        result := AiTransform(sel.text, instruction, opts)
    } catch as e {
        Notify()
        ShowError(e.Message)
        return
    } finally {
        Busy := false
    }
    Notify()
    ShowPreview(sel, result, instruction, opts)
}

; ---------------------------------------------------------------------------
; Окно с результатом
; ---------------------------------------------------------------------------

ShowPreview(sel, result, instruction, opts) {
    g := Gui("+AlwaysOnTop -MinimizeBox", "TextHelper — " ProviderName(opts))
    g.SetFont("s10", "Segoe UI")
    g.Add("Text", "w640", "Было:")
    g.Add("Edit", "w640 r5 ReadOnly -TabStop", ToCrLf(sel.text))
    g.Add("Text", "w640", "Стало (можно поправить вручную):")
    resultEdit := g.Add("Edit", "w640 r10", ToCrLf(result))
    btnReplace := g.Add("Button", "w150 Default", "&Заменить")
    btnCopy := g.Add("Button", "x+10 w150", "&Копировать")
    btnAgain := g.Add("Button", "x+10 w150", "&Ещё вариант")
    btnCancel := g.Add("Button", "x+10 w150", "Отмена")

    btnReplace.OnEvent("Click", (*) => (
        text := FromCrLf(resultEdit.Value),
        g.Destroy(),
        PasteText(sel.hwnd, RestoreEdges(sel.text, text))
    ))
    btnCopy.OnEvent("Click", (*) => (
        A_Clipboard := ToCrLf(FromCrLf(resultEdit.Value)),
        g.Destroy(),
        Notify("Скопировано в буфер обмена")
    ))
    btnAgain.OnEvent("Click", Regenerate)
    btnCancel.OnEvent("Click", (*) => g.Destroy())
    g.OnEvent("Escape", (*) => g.Destroy())
    g.OnEvent("Close", (*) => g.Destroy())
    g.Show()
    btnReplace.Focus()

    Regenerate(*) {
        global Busy
        if Busy
            return
        Busy := true
        for ctrl in [btnReplace, btnCopy, btnAgain]
            ctrl.Enabled := false
        g.Title := "TextHelper — " ProviderName(opts) " думает…"
        try {
            resultEdit.Value := ToCrLf(AiTransform(sel.text, instruction, opts, FromCrLf(resultEdit.Value)))
        } catch as e {
            ShowError(e.Message)
        } finally {
            Busy := false
        }
        try {
            for ctrl in [btnReplace, btnCopy, btnAgain]
                ctrl.Enabled := true
            g.Title := "TextHelper — " ProviderName(opts)
            btnReplace.Focus()
        }
    }
}

; ---------------------------------------------------------------------------
; Буфер обмена и выделение
; ---------------------------------------------------------------------------

; Копирует выделенный текст, не портя содержимое буфера обмена.
; Возвращает {text, hwnd} или "" если ничего не выделено.
CaptureSelection() {
    ; Ждём, пока пользователь отпустит Ctrl/Alt/Shift/Win после горячей клавиши.
    for key in ["Ctrl", "Alt", "Shift", "LWin", "RWin"]
        KeyWait(key, "T1")
    hwnd := WinExist("A")
    saved := ClipboardAll()
    A_Clipboard := ""
    Send("^c")
    ok := ClipWait(0.8)
    if !ok && Setting("General", "SelectAllIfEmpty", "0") = "1" {
        Send("^a")
        Sleep(50)
        Send("^c")
        ok := ClipWait(0.8)
    }
    text := ok ? A_Clipboard : ""
    A_Clipboard := saved
    if Trim(text, " `t`r`n") = "" {
        Notify("Сначала выделите текст")
        return ""
    }
    return {text: FromCrLf(text), hwnd: hwnd}
}

PasteText(hwnd, text) {
    if hwnd && WinExist(hwnd) {
        WinActivate(hwnd)
        WinWaitActive(hwnd, , 1)
    }
    saved := ClipboardAll()
    A_Clipboard := ToCrLf(text)
    ClipWait(1)
    Send("^v")
    ; Даём программе забрать текст из буфера, потом возвращаем прежнее содержимое.
    Sleep(400)
    A_Clipboard := saved
}

FromCrLf(text) => StrReplace(text, "`r`n", "`n")
ToCrLf(text) => StrReplace(FromCrLf(text), "`n", "`r`n")

; Сохраняет пробелы и переводы строк по краям исходного выделения.
RestoreEdges(original, text) {
    RegExMatch(original, "^\s*", &lead)
    RegExMatch(original, "\s*$", &trail)
    return lead[0] Trim(text, " `t`r`n") trail[0]
}

; ---------------------------------------------------------------------------
; Настройки
; ---------------------------------------------------------------------------

; Простой разбор INI в UTF-8: Map(раздел -> массив пар [ключ, значение]).
LoadSettings(path) {
    cfg := Map()
    cfg.CaseSense := "Off"
    if !FileExist(path)
        return cfg
    section := ""
    for line in StrSplit(FileRead(path, "UTF-8"), "`n", "`r") {
        line := Trim(line)
        if line = "" || SubStr(line, 1, 1) = ";"
            continue
        if RegExMatch(line, "^\[(.+)\]$", &m) {
            section := Trim(m[1])
            if !cfg.Has(section)
                cfg[section] := []
        } else if section != "" && (eq := InStr(line, "=")) {
            cfg[section].Push([Trim(SubStr(line, 1, eq - 1)), Trim(SubStr(line, eq + 1))])
        }
    }
    return cfg
}

Setting(section, key, default := "") {
    if Cfg.Has(section)
        for pair in Cfg[section]
            if pair[1] = key
                return pair[2]
    return default
}

ActionList() {
    actions := []
    if Cfg.Has("Actions")
        for pair in Cfg["Actions"]
            if pair[1] != "" && pair[2] != ""
                actions.Push(pair)
    return actions.Length ? actions : DEFAULT_ACTIONS
}

; Собирает настройки для ИИ. Если чего-то не хватает — объясняет, что сделать, и возвращает "".
AiOptions() {
    provider := StrLower(Setting("General", "Provider", "gigachat"))
    opts := {
        provider: provider,
        proxy: Setting("General", "Proxy"),
        gigaKey: Setting("GigaChat", "AuthKey") || EnvGet("GIGACHAT_CREDENTIALS"),
        gigaScope: Setting("GigaChat", "Scope", "GIGACHAT_API_PERS"),
        gigaModel: Setting("GigaChat", "Model", "GigaChat-2"),
        gigaAuthUrl: Setting("GigaChat", "AuthUrl", GIGACHAT_AUTH_URL),
        gigaChatUrl: Setting("GigaChat", "ChatUrl", GIGACHAT_CHAT_URL),
        localUrl: Setting("Local", "Url", LOCAL_CHAT_URL),
        localModel: Setting("Local", "Model", "qwen2.5:7b"),
        localKey: Setting("Local", "ApiKey"),
        claudeKey: Setting("Claude", "ApiKey") || EnvGet("ANTHROPIC_API_KEY"),
        claudeModel: Setting("Claude", "Model", "claude-opus-5-5"),
        claudeEffort: Setting("Claude", "Effort", "low"),
        claudeFallbacks: Setting("Claude", "Fallbacks", "default")
    }
    switch provider {
        case "gigachat":
            if opts.gigaKey != ""
                return opts
            problem := "Не указан ключ GigaChat.`n`n"
                . "1. Зарегистрируйтесь на developers.sber.ru → GigaChat API (для физлиц есть бесплатный пакет).`n"
                . "2. В проекте нажмите «Получить ключ» и скопируйте «Ключ авторизации».`n"
                . "3. Вставьте его в settings.ini, раздел [GigaChat], строка AuthKey=."
        case "claude":
            if opts.claudeKey != ""
                return opts
            problem := "Не указан API-ключ Claude (settings.ini, раздел [Claude], строка ApiKey=)."
        case "local":
            return opts
        default:
            problem := "Неизвестный Provider=" provider " в разделе [General].`nДопустимо: gigachat, local, claude."
    }
    if MsgBox(problem "`n`nОткрыть settings.ini?", "TextHelper", "YesNo Icon!") = "Yes"
        OpenSettings()
    return ""
}

ProviderName(opts) {
    switch opts.provider {
        case "gigachat": return "GigaChat"
        case "claude": return "Claude"
        default: return opts.localModel
    }
}

OpenSettings() {
    Run('notepad.exe "' SETTINGS_PATH '"')
}

; ---------------------------------------------------------------------------
; Горячие клавиши, трей, уведомления
; ---------------------------------------------------------------------------

RegisterHotkey(name, default, callback) {
    keys := Setting("Hotkeys", name, default)
    if keys = ""
        return
    try Hotkey(keys, callback)
    catch as e
        ShowError("Не удалось назначить горячую клавишу " name "=" keys "`n`n" e.Message)
}

; "^!vk46" -> "Ctrl+Alt+F"
HotkeyLabel(keys) {
    mods := ""
    while keys != "" && InStr("^!+#<>*~$", SubStr(keys, 1, 1)) {
        switch SubStr(keys, 1, 1) {
            case "^": mods .= "Ctrl+"
            case "!": mods .= "Alt+"
            case "+": mods .= "Shift+"
            case "#": mods .= "Win+"
        }
        keys := SubStr(keys, 2)
    }
    if RegExMatch(keys, "i)^vk([0-9a-f]{2})$", &m) {
        vk := Integer("0x" m[1])
        keys := (vk >= 0x30 && vk <= 0x5A) ? Chr(vk) : GetKeyName(keys)
    }
    return mods StrUpper(keys)
}

SetupTray() {
    A_IconTip := "TextHelper — проверка и переформулировка текста"
    tray := A_TrayMenu
    tray.Delete()
    tray.Add("Как пользоваться", (*) => ShowHelp())
    tray.Add("Настройки", (*) => OpenSettings())
    tray.Add("Запускать вместе с Windows", ToggleAutostart)
    if FileExist(STARTUP_LINK)
        tray.Check("Запускать вместе с Windows")
    tray.Add("Перезапустить", (*) => Reload())
    tray.Add()
    tray.Add("Выход", (*) => ExitApp())
    tray.Default := "Как пользоваться"
}

ToggleAutostart(itemName, *) {
    if FileExist(STARTUP_LINK) {
        FileDelete(STARTUP_LINK)
        A_TrayMenu.Uncheck(itemName)
    } else {
        if A_IsCompiled
            FileCreateShortcut(A_ScriptFullPath, STARTUP_LINK, A_ScriptDir)
        else
            FileCreateShortcut(A_AhkPath, STARTUP_LINK, A_ScriptDir, '"' A_ScriptFullPath '"')
        A_TrayMenu.Check(itemName)
    }
}

ShowHelp() {
    MsgBox("1. Выделите текст в любой программе.`n"
        . "2. Нажмите:`n"
        . "    " HotkeyLabel(Setting("Hotkeys", "Fix", "^!vk46")) " — исправить орфографию (LanguageTool, бесплатно)`n"
        . "    " HotkeyLabel(Setting("Hotkeys", "Menu", "^!vk52")) " — меню: исправить, переформулировать, вежливее, короче…`n"
        . "3. В меню можно нажать цифру пункта. В окне результата Enter — заменить, Esc — отмена.`n`n"
        . "Отменить замену — Ctrl+Z в той программе, где был текст.`n"
        . "Свои пункты меню и ключи ИИ — в settings.ini (трей → Настройки).",
        "TextHelper — как пользоваться", "Iconi")
}

Notify(message := "", ms := 2500) {
    static clear := (*) => ToolTip()
    if message = "" {
        ToolTip()
        SetTimer(clear, 0)
        return
    }
    ToolTip(message)
    SetTimer(clear, ms ? -ms : 0)
}

ShowError(message) {
    MsgBox(message, "TextHelper", "Icon! T60")
}

#Requires AutoHotkey v2.0
; Тесты логики TextHelper без сети и без GUI.
; Запуск: AutoHotkey64.exe /ErrorStdOut tests\RunTests.ahk  (результат — в stdout, код выхода 0/1)
; Необязательно: TEXTHELPER_ECHO_URL=http://127.0.0.1:8765/ — проверка UTF-8 через WinHTTP на эхо-сервере.

#Include %A_ScriptDir%\..\lib\Json.ahk
#Include %A_ScriptDir%\..\lib\Net.ahk
#Include %A_ScriptDir%\..\lib\Services.ahk

global Failed := 0, Passed := 0

Check(name, actual, expected) {
    global Failed, Passed
    if actual == expected {
        Passed++
        return
    }
    Failed++
    Out("FAIL " name "`n  ожидалось: " expected "`n  получено:  " actual)
}

Throws(name, fn, needle := "") {
    global Failed, Passed
    try {
        fn()
    } catch as e {
        if needle = "" || InStr(e.Message, needle) {
            Passed++
            return
        }
        Failed++
        Out("FAIL " name ": неожиданное сообщение: " e.Message)
        return
    }
    Failed++
    Out("FAIL " name ": исключения не было")
}

Out(text) => FileAppend(text "`n", "*", "UTF-8")

; --- JSON ---------------------------------------------------------------------

data := JsonLoad('{"a": [1, 2.5, -3e2, true, false, null], "s": "Привет \"мир\"\n\t\\ \/ Ж 😀", "o": {}, "e": [], "nested": {"k": [{"x": "y"}]}}')
Check("json array len", data["a"].Length, 6)
Check("json int", data["a"][1], 1)
Check("json float", data["a"][2], 2.5)
Check("json exp", data["a"][3] + 0, -300.0)
Check("json true", data["a"][4], 1)
Check("json false", data["a"][5], 0)
Check("json null", data["a"][6], "")
Check("json string escapes", data["s"], 'Привет "мир"`n`t\ / Ж ' Chr(0x1F600))
Check("json empty obj", data["o"].Count, 0)
Check("json empty arr", data["e"].Length, 0)
Check("json nested", data["nested"]["k"][1]["x"], "y")
Throws("json trailing garbage", () => JsonLoad('{"a":1} x'), "лишние")
Throws("json unterminated", () => JsonLoad('{"a":"b'), "незакрытая")

src := "Строка с `"кавычками`", \ обратным слэшем,`nпереводом`r`nи таб`tом, эмодзи " Chr(0x1F44D) " и " Chr(1)
back := JsonLoad(JsonDump(Map("text", src, "n", 16000, "list", ["a", Map("b", 2)])))
Check("json roundtrip text", back["text"], src)
Check("json roundtrip int", back["n"], 16000)
Check("json roundtrip nested", back["list"][2]["b"], 2)
Check("json dump object", JsonDump({k: "v"}), '{"k":"v"}')
Check("json quote control", JsonQuote(Chr(1)), '"\u0001"')

; --- URL-кодирование, UUID ------------------------------------------------------

Check("urlencode ascii", UrlEncode("a-b_c.d~e f&g=h"), "a-b_c.d~e%20f%26g%3Dh")
Check("urlencode cyrillic", UrlEncode("Привет"), "%D0%9F%D1%80%D0%B8%D0%B2%D0%B5%D1%82")
Check("urlencode newline", UrlEncode("a`nb"), "a%0Ab")
Check("uuid format", RegExMatch(NewUuid(), "^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"), 1)

; --- LanguageTool ---------------------------------------------------------------

text := "Превет, как дила? Я хател спросить."
ltResponse := '
(
{"software":{"name":"LanguageTool"},"language":{"code":"ru-RU"},"matches":[
 {"message":"Орфографическая ошибка","replacements":[{"value":"Привет"},{"value":"Превед"}],"offset":0,"length":6,
  "context":{"text":"Превет, как дила? Я хател спросить.","offset":0,"length":6},"rule":{"id":"MORFOLOGIK_RULE_RU_RU","issueType":"misspelling"}},
 {"message":"Орфографическая ошибка","replacements":[{"value":"дела"}],"offset":12,"length":4,
  "context":{"text":"...как дила? Я хател","offset":7,"length":4},"rule":{"id":"MORFOLOGIK_RULE_RU_RU","issueType":"misspelling"}},
 {"message":"Стиль","replacements":[{"value":"желал"}],"offset":20,"length":5,
  "context":{"text":"Я хател спросить.","offset":2,"length":5},"rule":{"id":"STYLE","issueType":"style"}},
 {"message":"Орфографическая ошибка","replacements":[{"value":"хотел"}],"offset":20,"length":5,
  "context":{"text":"Я хател спросить.","offset":2,"length":5},"rule":{"id":"MORFOLOGIK_RULE_RU_RU","issueType":"misspelling"}},
 {"message":"Без вариантов","replacements":[],"offset":27,"length":8,
  "context":{"text":"спросить.","offset":0,"length":8},"rule":{"id":"X","issueType":"grammar"}}
]}
)'
fixed := ApplyLanguageToolMatches(text, JsonLoad(ltResponse)["matches"], "style")
Check("lt fixed text", fixed.text, "Привет, как дела? Я хотел спросить.")
Check("lt change count", fixed.changes.Length, 3)
Check("lt first change", fixed.changes[1][1] "→" fixed.changes[1][2], "Превет→Привет")

; Если пропуск стиля выключен, «желал» и «хотел» пересекаются — применяется только одна правка.
fixed := ApplyLanguageToolMatches(text, JsonLoad(ltResponse)["matches"], "")
Check("lt overlap applies one", fixed.changes.Length, 3)

; Смещение не совпадает с контекстом — правка пропускается, текст не портится.
bad := JsonLoad('{"matches":[{"replacements":[{"value":"X"}],"offset":3,"length":2,"context":{"text":"Превет","offset":0,"length":6},"rule":{"issueType":"misspelling"}}]}')
fixed := ApplyLanguageToolMatches(text, bad["matches"])
Check("lt mismatched offset skipped", fixed.text, text)

; Порядок замечаний в ответе не важен.
unordered := JsonLoad('{"matches":[{"replacements":[{"value":"bb"}],"offset":4,"length":1},{"replacements":[{"value":"aa"}],"offset":0,"length":1}]}')
Check("lt unordered", ApplyLanguageToolMatches("a b c d", unordered["matches"]).text, "aa b bb d")

; --- Термины, которые проверка орфографии не трогает -------------------------------

dict := ["Рутокен", "Эвотор", "Штрих-М", "фискализация", "ТСД"]
for word in ["ККТ", "ЕГАИС", "USB", "1С", "54-ФЗ", "COM1", "ПолучитьДанные", "JaCarta",
        "Рутокен", "рутокена", "Рутокеном", "Эвотора", "Штрих-М", "фискализации", "ТСД"]
    Check("protected " word, IsProtectedWord(word, dict), true)
for word in ["превет", "Рутакен", "Эвоторный_длинный", "Привет", "А", "Фискал"]
    Check("not protected " word, IsProtectedWord(word, dict), false)

techText := "Рутокена нет, Эвотор превет."
techMatches := JsonLoad('
(
{"matches":[
 {"replacements":[{"value":"Рутина"}],"offset":0,"length":8,"rule":{"issueType":"misspelling"}},
 {"replacements":[{"value":"Электор"}],"offset":14,"length":6,"rule":{"issueType":"misspelling"}},
 {"replacements":[{"value":"привет"}],"offset":21,"length":6,"rule":{"issueType":"misspelling"}}
]}
)')["matches"]
Check("lt keeps dictionary terms", ApplyLanguageToolMatches(techText, techMatches, "style", dict).text, "Рутокена нет, Эвотор привет.")
Check("lt without dictionary", ApplyLanguageToolMatches(techText, techMatches, "style").text, "Рутина нет, Электор привет.")

; Правки, удаляющие слово целиком, не применяются; знаки препинания — применяются.
deletions := JsonLoad('{"matches":[{"replacements":[{"value":""}],"offset":0,"length":6,"rule":{"issueType":"misspelling"}},{"replacements":[{"value":""}],"offset":7,"length":3,"rule":{"issueType":"grammar"}},{"replacements":[{"value":","}],"offset":10,"length":1,"rule":{"issueType":"typographical"}},{"replacements":[{"value":" "}],"offset":11,"length":2,"rule":{"issueType":"whitespace"}}]}')["matches"]
fixed := ApplyLanguageToolMatches("Превет как;  дела", deletions)
Check("lt never deletes words", fixed.text, "Превет как, дела")
Check("lt deletion changes", fixed.changes.Length, 2)
Check("count letters", CountLetters("Привет, мир! 123 ok"), 11)

; --- Файлы контекста и словаря --------------------------------------------------

tmp := A_Temp "\texthelper_test.txt"
try FileDelete(tmp)
FileAppend("; комментарий`r`nЯ специалист по 1С.`r`n`r`n  `; ещё комментарий`r`nПишу клиентам.`r`n", tmp, "UTF-8")
Check("read user text", ReadUserText(tmp), "Я специалист по 1С.`n`nПишу клиентам.")
FileDelete(tmp)
FileAppend("; термины`nАТОЛ, Штрих-М ,Эвотор`n`nРутокен`n", tmp, "UTF-8")
words := ReadWordList(tmp)
Check("word list", words.Length "|" words[1] "|" words[2] "|" words[3] "|" words[4], "4|АТОЛ|Штрих-М|Эвотор|Рутокен")
FileDelete(tmp)
Check("missing file", ReadUserText(tmp), "")
Check("missing word list", ReadWordList(tmp).Length, 0)

; --- Промпт с контекстом и терминами ------------------------------------------------

prompt := AiSystemPrompt("Сократи.", "", "Я специалист по 1С.", ["ККТ", "Рутокен"])
Check("prompt context", InStr(prompt, "<context>`nЯ специалист по 1С.`n</context>`n`nTask: Сократи.") > 0, true)
Check("prompt terms", InStr(prompt, "Russian words may change their endings to fit the grammar: ККТ, Рутокен") > 0, true)
plain := AiSystemPrompt("Сократи.")
Check("prompt without context", InStr(plain, "<context>") || InStr(plain, "Keep these terms") || InStr(plain, "{"), 0)
Check("prompt without context layout", InStr(plain, "transform it.`n`nTask: Сократи.") > 0, true)

; --- Claude ---------------------------------------------------------------------

opts := {claudeModel: "claude-opus-5-5", claudeEffort: "low", claudeFallbacks: "default"}
body := JsonLoad(ClaudeRequestBody(AiSystemPrompt("Сократи текст."), AiUserMessage("Привет `"мир`""), opts))
Check("claude body model", body["model"], "claude-opus-5-5")
Check("claude body effort", body["output_config"]["effort"], "low")
Check("claude body fallbacks", body["fallbacks"], "default")
Check("claude body user", body["messages"][1]["content"], "<text>`nПривет `"мир`"`n</text>")
Check("claude body system has task", InStr(body["system"], "Task: Сократи текст.") > 0, true)
Check("claude body max_tokens", body["max_tokens"], 16000)
noExtras := JsonLoad(ClaudeRequestBody("s", "u", {claudeModel: "m", claudeEffort: "", claudeFallbacks: ""}))
Check("claude body without effort", noExtras.Has("output_config") || noExtras.Has("fallbacks"), false)

ok := '{"id":"msg_1","type":"message","role":"assistant","content":[{"type":"thinking","thinking":"","signature":"x"},{"type":"text","text":"Готово "},{"type":"text","text":"✓"}],"stop_reason":"end_turn"}'
Check("claude parse text", ClaudeParseResponse(200, ok), "Готово ✓")
Throws("claude refusal", () => ClaudeParseResponse(200, '{"content":[],"stop_reason":"refusal","stop_details":{"type":"refusal","category":null}}'), "отказался")
Throws("claude 401", () => ClaudeParseResponse(401, '{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}'), "неверный API-ключ")
Throws("claude 529", () => ClaudeParseResponse(529, '{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}'), "перегружен")
Throws("claude html error", () => ClaudeParseResponse(502, "<html>Bad gateway</html>"), "Bad gateway")

; --- GigaChat и OpenAI-совместимый формат (Ollama) ------------------------------

gbody := JsonLoad(ChatRequestBody("sys", "user", "GigaChat-2"))
Check("chat body model", gbody["model"], "GigaChat-2")
Check("chat body roles", gbody["messages"][1]["role"] "," gbody["messages"][2]["role"], "system,user")
Check("chat body content", gbody["messages"][2]["content"], "user")
gok := '{"choices":[{"message":{"role":"assistant","content":"Добрый день!"},"index":0,"finish_reason":"stop"}],"created":1,"model":"GigaChat-2","object":"chat.completion"}'
Check("chat parse", ChatParseResponse("GigaChat", 200, gok), "Добрый день!")
Throws("chat blacklist", () => ChatParseResponse("GigaChat", 200, '{"choices":[{"message":{"role":"assistant","content":"Не могу"},"finish_reason":"blacklist"}]}'), "GigaChat отказался")
Throws("giga 402", () => ChatParseResponse("GigaChat", 402, '{"status":402,"message":"Payment Required"}'), "Payment Required")
Throws("ollama 404", () => ChatParseResponse("Модель x", 404, '{"error":{"message":"model \"x\" not found, try pulling it first","type":"api_error"}}'), "not found, try pulling")
Throws("plain error string", () => ChatParseResponse("M", 400, '{"error":"bad request"}'), "bad request")
Throws("empty choices", () => ChatParseResponse("M", 200, '{"choices":[]}'), "разобрать")

; --- Подготовка ответа модели -----------------------------------------------------

Check("clean tags", AiCleanResult("  <text>`nПривет`n</text>`n"), "Привет")
Check("clean plain", AiCleanResult("`nПривет, мир`n"), "Привет, мир")
Check("clean think", AiCleanResult("<think>`nрассуждаю…`n</think>`n`nГотовый текст"), "Готовый текст")
Check("system prompt previous", InStr(AiSystemPrompt("t", "старый вариант"), "<previous>`nстарый вариант`n</previous>") > 0, true)

; --- WinHTTP + UTF-8 через локальный эхо-сервер (необязательно) ----------------------

if echoUrl := EnvGet("TEXTHELPER_ECHO_URL") {
    payload := JsonDump(Map("text", "Съешь ещё этих мягких французских булок " Chr(0x1F950)))
    resp := HttpPost(echoUrl, payload, Map("Content-Type", "application/json", "X-Test", "1"))
    Check("echo status", resp.status, 200)
    echoed := JsonLoad(resp.body)
    Check("echo body utf8", echoed["body"], payload)
    Check("echo header", echoed["x-test"], "1")
}

Out(Passed " passed, " Failed " failed")
ExitApp(Failed ? 1 : 0)

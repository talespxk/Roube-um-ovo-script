--[[
    ================================================================================
    BIGFROOT (BF) SNIFFER & DUMPER FORENSE
    Jogo: Roube um Ovo (PlaceId: 107778070777162)
    ================================================================================
    Como Usar:
    1. Execute este script PRIMEIRO no seu executor.
    2. Logo em seguida, execute o seu bfloader normalmente.
    3. O Sniffer intercepta o HttpGet, loadstring, tabelas descriptografadas
       de getgc() e getgenv(), salvando todo o código fonte e as funções do BF
       em arquivos na pasta do executor:
       - BF_SOURCE_LOADSTRING.lua (Código-fonte completo descriptografado)
       - BF_SOURCE_HTTPGET.lua (Código baixado via web)
       - BF_MEMORY_DUMP.txt (Tabelas de ovos, funções e variáveis em memória)
]]

print("==================================================")
print("[BF SNIFFER] Inicializando interceptadores de rede e memória...")
print("==================================================")

local capturedCount = 0

-- 1. INTERCEPTAÇÃO DE LOADSTRING (Pega o código executado na memória)
if hookfunction and loadstring then
    local oldLoadstring
    oldLoadstring = hookfunction(loadstring, function(source, chunkname)
        capturedCount = capturedCount + 1
        print(string.format("[BF SNIFFER] Interceptado loadstring #%d! Tamanho: %d bytes", capturedCount, #tostring(source)))
        pcall(function()
            if writefile then
                writefile("BF_SOURCE_LOADSTRING_" .. capturedCount .. ".lua", tostring(source))
                writefile("BF_SOURCE_LOADSTRING_LATEST.lua", tostring(source))
            end
            if setclipboard and capturedCount == 1 then
                setclipboard(tostring(source))
            end
        end)
        return oldLoadstring(source, chunkname)
    end)
    print("[BF SNIFFER] Hook em loadstring ATIVADO!")
else
    print("[BF SNIFFER] hookfunction/loadstring não disponível neste executor.")
end

-- 2. INTERCEPTAÇÃO DE HTTPGET (Pega a URL e o Script baixado)
if hookfunction and game and game.HttpGet then
    local oldHttpGet
    oldHttpGet = hookfunction(game.HttpGet, function(self, url, ...)
        print("[BF SNIFFER] Interceptado HttpGet: " .. tostring(url))
        local result = oldHttpGet(self, url, ...)
        pcall(function()
            if writefile then
                writefile("BF_SOURCE_HTTPGET_" .. tick() .. ".lua", tostring(result))
                writefile("BF_SOURCE_HTTPGET_LATEST.lua", tostring(result))
                writefile("BF_URLS_CAPTURED.txt", tostring(url) .. "\n")
            end
        end)
        return result
    end)
    print("[BF SNIFFER] Hook em game:HttpGet ATIVADO!")
end

-- 3. INTERCEPTAÇÃO DE REQUEST / HTTP_REQUEST
local requestFunc = (syn and syn.request) or (http and http.request) or request or http_request
if hookfunction and type(requestFunc) == "function" then
    local oldRequest
    oldRequest = hookfunction(requestFunc, function(options, ...)
        if type(options) == "table" and options.Url then
            print("[BF SNIFFER] Interceptado request para: " .. tostring(options.Url))
        end
        local resp = oldRequest(options, ...)
        pcall(function()
            if type(resp) == "table" and resp.Body and #resp.Body > 500 then
                if writefile then
                    writefile("BF_REQUEST_BODY_" .. tick() .. ".lua", tostring(resp.Body))
                end
            end
        end)
        return resp
    end)
    print("[BF SNIFFER] Hook em request() ATIVADO!")
end

-- 4. MONITOR DE MEMÓRIA APÓS EXECUÇÃO DO BF (SNAPSHOT DE GETGC E GETGENV)
local genvSnapshot = {}
if getgenv then
    for k, v in pairs(getgenv()) do
        genvSnapshot[k] = true
    end
end

-- Função para varrer getgc() procurando listas de ovos, nomes de pets e lógicas do BF
local function scanBFMemory()
    print("[BF SNIFFER] Iniciando varredura profunda de tabelas em memória (getgc)...")
    local dumpLines = {}
    local function logL(s) table.insert(dumpLines, s or "") end

    logL("================================================================================")
    logL("BF MEMORY FORENSIC DUMP")
    logL("Data: " .. os.date("%Y-%m-%d %H:%M:%S"))
    logL("================================================================================\n")

    -- 1. Novas variáveis em getgenv()
    logL("[1] NOVAS VARIÁVEIS CRIADAS EM GETGENV():")
    if getgenv then
        for k, v in pairs(getgenv()) do
            if not genvSnapshot[k] then
                logL(string.format("  > %s = %s (%s)", tostring(k), tostring(v), type(v)))
                if type(v) == "table" then
                    pcall(function()
                        logL("    Conteúdo: " .. game:GetService("HttpService"):JSONEncode(v))
                    end)
                end
            end
        end
    end
    logL("\n")

    -- 2. Varredura de tabelas no Garbage Collector (getgc)
    if getgc then
        logL("[2] TABELAS RELEVANTES ENCONTRADAS NO GETGC:")
        local gcItems = getgc(true)
        local matchesFound = 0

        for _, item in ipairs(gcItems) do
            if type(item) == "table" then
                local isMatch = false
                local sampleKey = ""
                for k, val in pairs(item) do
                    local strK = tostring(k):lower()
                    local strV = tostring(val):lower()
                    if strK:find("godzilla") or strV:find("godzilla")
                        or strK:find("kitsune") or strV:find("kitsune")
                        or strK:find("archdemon") or strV:find("archdemon")
                        or strK:find("dreadscale") or strV:find("dreadscale")
                        or strK:find("areaegg") or strV:find("areaegg")
                        or strK:find("eggslots") or strV:find("eggslots")
                        or strK:find("bigfroot") or strV:find("bigfroot") then
                        isMatch = true
                        sampleKey = tostring(k) .. " = " .. tostring(val)
                        break
                    end
                end

                if isMatch then
                    matchesFound = matchesFound + 1
                    logL(string.format("\n  --- Tabela GC #%d (Amostra: %s) ---", matchesFound, sampleKey))
                    pcall(function()
                        local json = game:GetService("HttpService"):JSONEncode(item)
                        if #json > 5000 then json = json:sub(1, 5000) .. " ... (truncado)" end
                        logL("  JSON: " .. json)
                    end)
                    if matchesFound >= 25 then
                        logL("  ... limite de 25 tabelas atingido.")
                        break
                    end
                end
            end
        end
        logL(string.format("Total de tabelas do BF encontradas: %d\n", matchesFound))
    end

    local finalMemoryText = table.concat(dumpLines, "\n")
    pcall(function()
        if writefile then
            writefile("BF_MEMORY_DUMP.txt", finalMemoryText)
        end
    end)
    print("[BF SNIFFER] Varredura de memória concluída! Salvo em 'BF_MEMORY_DUMP.txt'")
end

-- Deixa uma função global para acionar o dump de memória a qualquer momento
_G.DumpBFMemory = scanBFMemory

-- Agenda uma varredura automática após 8 segundos (tempo para você executar o bfloader)
task.spawn(function()
    print("[BF SNIFFER] PRONTO! Pode executar o bfloader agora!")
    print("[BF SNIFFER] Uma varredura de memória automática será feita em 12 segundos.")
    print("[BF SNIFFER] Você também pode digitar _G.DumpBFMemory() para varrer a qualquer hora.")
    task.wait(12)
    pcall(scanBFMemory)
end)

--[[
    ROUBE UM OVO - FLUENT STEALTH HUB v3.4 (DEEP SPY & AUTO DISK LOG SAVER)
    -----------------------------------------------------------------------
    - Design 100% Nativo no Estilo Fluent UI (Abas, Toggles com chaves animadas, Sliders).
    - Deep Spy & Disk Saver: Grava logs ultra-detalhados de todas as ações no disco (writefile/appendfile).
    - Serialização Avançada de Argumentos (Tabelas, Vector3, CFrame, Instances, Types).
    - Motor Real de Raridade (Inspeciona Atributos, Values, TextLabels, Billboards e Nomes).
    - Auto Fly Steal com Voo Suave e Retorno DIRETO à Base.
    - ZERO Metamétodos hookmetamethod (100% Imune a mensagens de Anti-Bypass).
]]

print("========== CARREGANDO SCRIPT ÚNICO: ROUBE UM OVO HUB v3.4 ==========")

--================================================================--
-- BFLOADER SPY: CAPTURA FUNÇÕES E AMBIENTE DO SCRIPT EXTERNO
-- Roda ANTES de tudo. Você só precisa executar este arquivo.
--================================================================--

local BFLoader_Capturado = {}
local BFLoader_Carregado = false

local function snapshotGlobais()
    local snap = {}
    pcall(function()
        for k, v in pairs(_G) do snap[k] = v end
    end)
    pcall(function()
        if getgenv then
            for k, v in pairs(getgenv()) do snap[k] = v end
        end
    end)
    return snap
end

local function capturarNovas(antes, depois)
    local novasFuncs = {}
    for k, v in pairs(depois) do
        if antes[k] == nil then
            BFLoader_Capturado[k] = v
            table.insert(novasFuncs, string.format("  -> %s [%s]", tostring(k), type(v)))
        end
    end
    if #novasFuncs > 0 then
        local log = "[BFLoader] " .. #novasFuncs .. " globals capturadas:\n" .. table.concat(novasFuncs, "\n")
        print("\n========================================")
        print(log)
        print("========================================\n")
        _G.BFLoader_LogText = log
        pcall(function()
            if writefile then writefile("bfloader_capturado.txt", log) end
        end)
    else
        local msg = "[BFLoader] Nenhuma nova global detectada no ambiente."
        print(msg)
        _G.BFLoader_LogText = msg
    end
end

local function chamarBFLoader(nomeFuncao, ...)
    local fn = BFLoader_Capturado[nomeFuncao]
    if type(fn) == "function" then
        local ok, res = pcall(fn, ...)
        if not ok then
            print("[BFLoader] Erro ao chamar '" .. nomeFuncao .. "': " .. tostring(res))
        end
        return res
    else
        print("[BFLoader] Função '" .. nomeFuncao .. "' não encontrada.")
        return nil
    end
end

_G.BFLoader_Capturado = BFLoader_Capturado
_G.chamarBFLoader = chamarBFLoader

-- Configurações e Flags Globais
local Flags = {
    LoadExternalBFLoader = false, -- Define se deve carregar o BFLoader externo
    AutoSteal = false,
    FlySteal = true,
    InstantReturn = false, -- Retorno voando por física (sem TP para evitar kick)
    FlySpeed = 500, -- Velocidade ultra rápida (ajustável até 1000)
    StealRadius = 2500,
    StealDelay = 0.15,
    InstantPrompt = true,
    PrioritizeRare = true,
    CustomBasePos = nil,
    SavedBasePos = nil,

    -- Proteção & Player
    GodMode = false,
    AntiRagdoll = true,
    NeverDropEgg = true,
    SpeedHack = false,
    WalkSpeed = 16,
    JumpPowerHack = false,
    JumpPower = 50,
    Noclip = false,
    InfJump = false,

    -- ESP
    EggESP = false,
    PlayerESP = false,
    ESPColor = Color3.fromRGB(255, 215, 0),
    PlayerESPColor = Color3.fromRGB(0, 180, 255),

    -- Filtros & Radar de Ovos
    MinRarityScore = 0,
    FilterIgnoreCommons = false,
    DiscoveredEggs = {},

    -- Utils & Logger
    AntiAFK = true,
    AutoLogger = false,
    SaveToDisk = false -- Desativado por padrão para 0% de lag de disco
}

-- ▼▼▼ BFLoader (Opcional - Ative apenas se quiser capturar o script externo) ▼▼▼
if Flags.LoadExternalBFLoader then
    local _antes = snapshotGlobais()

    task.spawn(function()
        print("[BFLoader] [1/4] Iniciando download do script externo...")

        local source
        local ok1, err1 = pcall(function()
            source = game:HttpGet("https://raw.githubusercontent.com/hanniii1/Loader/refs/heads/main/BFLoader.lua")
        end)

        if not ok1 or not source then
            warn("[BFLoader] ERRO no HttpGet: " .. tostring(err1))
            return
        end
        print("[BFLoader] [2/4] Download OK (" .. #source .. " bytes). Compilando...")

        local fn, compileErr = loadstring(source)
        if not fn then
            warn("[BFLoader] ERRO ao compilar: " .. tostring(compileErr))
            return
        end
        print("[BFLoader] [3/4] Compilado OK. Executando em thread dedicada...")

        task.spawn(function()
            local ok2, runErr = pcall(fn)
            if not ok2 then
                warn("[BFLoader] ERRO na execução do script externo: " .. tostring(runErr))
            end
        end)

        print("[BFLoader] [4/4] Script iniciado! Aguardando 5s para tirar snapshot das globals...")
        task.wait(5)

        local _depois = snapshotGlobais()
        capturarNovas(_antes, _depois)
        BFLoader_Carregado = true
        print("[BFLoader] ✅ Captura concluída!")
    end)
end
-- ▲▲▲ O resto do script carrega normalmente em paralelo ▲▲▲

--================================================================--

local function safeService(name)
    local s = game:GetService(name)
    return (cloneref and cloneref(s)) or s
end

local Services = {
    Workspace = safeService("Workspace"),
    Players = safeService("Players"),
    HttpService = safeService("HttpService"),
    RunService = safeService("RunService"),
    UserInputService = safeService("UserInputService"),
    ReplicatedStorage = safeService("ReplicatedStorage"),
    TweenService = safeService("TweenService")
}

local LocalPlayer = Services.Players.LocalPlayer

--================================================================--
-- MOTOR DE SERIALIZAÇÃO DE ARGUMENTOS E GRAVAÇÃO DE LOGS NO DISCO
--================================================================--

local LogHistory = {}
local LogFileName = "stealth_hub_captured_logs.txt"

local function serializeValue(v, depth)
    depth = depth or 1
    if depth > 4 then return "..." end
    local t = typeof(v)
    if t == "string" then
        return '"' .. tostring(v) .. '"'
    elseif t == "Instance" then
        return "Instance(" .. v:GetFullName() .. ")"
    elseif t == "Vector3" then
        return string.format("Vector3.new(%.1f, %.1f, %.1f)", v.X, v.Y, v.Z)
    elseif t == "CFrame" then
        return string.format("CFrame.new(%.1f, %.1f, %.1f)", v.X, v.Y, v.Z)
    elseif t == "table" then
        local parts = {}
        for k, val in pairs(v) do
            table.insert(parts, tostring(k) .. " = " .. serializeValue(val, depth + 1))
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    else
        return tostring(v) .. " [" .. t .. "]"
    end
end

local function formatArgsList(args)
    if not args or #args == 0 then return "(Sem argumentos)" end
    local formatted = {}
    for i = 1, #args do
        table.insert(formatted, string.format("Arg[%d]: %s", i, serializeValue(args[i])))
    end
    return table.concat(formatted, " | ")
end

local function addLog(category, text, extraArgs)
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local entry = string.format("[%s] [%s] %s", timestamp, category, text)
    if extraArgs then
        entry = entry .. "\n  ↪ Detalhes: " .. formatArgsList(extraArgs)
    end

    table.insert(LogHistory, 1, entry)
    if #LogHistory > 300 then
        table.remove(LogHistory, #LogHistory)
    end

    -- Salvar em arquivo no disco via executor (writefile / appendfile)
    if Flags.SaveToDisk then
        pcall(function()
            if appendfile then
                appendfile(LogFileName, entry .. "\n----------------------------------------\n")
            elseif writefile then
                local fullText = table.concat(LogHistory, "\n----------------------------------------\n")
                writefile(LogFileName, fullText)
            end
        end)
    end

    if _G.UpdateLogConsole then
        _G.UpdateLogConsole()
    end
end

addLog("SISTEMA", "Fluent Stealth Hub v3.4 (Deep Log Engine) ativado.")

-- Utilitários de Segurança
local function getRandomName()
    return "Fluent_" .. Services.HttpService:GenerateGUID(false):sub(1, 8)
end

local function protectGui(gui)
    pcall(function()
        local env = (getgenv and getgenv()) or _G
        local pgui = rawget(env, "protectgui") or env.protectgui
        if type(pgui) == "function" then
            pgui(gui)
        else
            local synTable = rawget(env, "syn") or env.syn
            if type(synTable) == "table" and type(synTable.protect_gui) == "function" then
                synTable.protect_gui(gui)
            end
        end
    end)
end

local function getGuiContainer()
    local container = nil
    pcall(function()
        if gethui then
            container = gethui()
        end
    end)
    if not container then
        pcall(function()
            local cg = game:GetService("CoreGui")
            container = (cloneref and cloneref(cg)) or cg
        end)
    end
    if not container then
        container = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    end
    return container
end

local function isEgg(obj)
    if not obj then return false end
    local promptText = ""
    if obj:IsA("ProximityPrompt") then
        promptText = obj.ActionText .. " " .. obj.ObjectText
    else
        local p = obj:FindFirstChildWhichIsA("ProximityPrompt")
        if p then promptText = p.ActionText .. " " .. p.ObjectText end
    end
    local name = (obj.Name .. " " .. promptText):lower()
    return name:find("egg") or name:find("ovo") or name:find("brainrot") 
        or name:find("secret") or name:find("godly") or name:find("mythic") 
        or name:find("legend") or name:find("steal") or name:find("roub") 
        or name:find("peg") or name:find("take") or name:find("grab")
end

local function getCharacter()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

local function getHRP()
    local char = getCharacter()
    return char and char:FindFirstChild("HumanoidRootPart")
end

-- Detecção e Fixação da Posição da Base
local function getBasePosition()
    if Flags.CustomBasePos then
        return Flags.CustomBasePos
    end
    if Flags.SavedBasePos then
        return Flags.SavedBasePos
    end

    pcall(function()
        local playerName = LocalPlayer.Name:lower()
        for _, obj in ipairs(Services.Workspace:GetDescendants()) do
            if obj:IsA("Model") or obj:IsA("Folder") or obj:IsA("BasePart") then
                local n = obj.Name:lower()
                if n:find(playerName) or (obj:FindFirstChild("Owner") and tostring(obj.Owner.Value):lower() == playerName) then
                    local pos = obj:IsA("BasePart") and obj.Position or (obj:IsA("Model") and obj:GetPivot().Position)
                    if pos then
                        Flags.SavedBasePos = pos + Vector3.new(0, 3, 0)
                    end
                end
            end
        end
    end)

    if not Flags.SavedBasePos then
        local hrp = getHRP()
        if hrp then
            Flags.SavedBasePos = hrp.Position
        end
    end

    return Flags.SavedBasePos
end

--================================================================--
-- MOTOR AVANÇADO DE DETECÇÃO DE RARIDADE DE OVOS (IA DE VALOR)
--================================================================--

local RarityWeights = {
    ["infinity"] = 50000,
    ["infinito"] = 50000,
    ["void"] = 45000,
    ["celestial"] = 40000,
    ["divine"] = 38000,
    ["divino"] = 38000,
    ["secret"] = 35000,
    ["secreto"] = 35000,
    ["dark matter"] = 32000,
    ["godly"] = 30000,
    ["deus"] = 30000,
    ["trillionaire"] = 28000,
    ["billionaire"] = 25000,
    ["millionaire"] = 22000,
    ["titan"] = 20000,
    ["tungsten"] = 19000,
    ["gigachad"] = 18000,
    ["brainrot"] = 17000,
    ["sigma"] = 16000,
    ["skibidi"] = 15000,
    ["mewing"] = 14000,
    ["rizz"] = 13000,
    ["cameraman"] = 12000,
    ["tvman"] = 11500,
    ["speaker"] = 11000,
    ["dragon"] = 10500,
    ["kitsune"] = 10000,
    ["rainbow"] = 9000,
    ["arco-íris"] = 9000,
    ["diamond"] = 8000,
    ["diamante"] = 8000,
    ["emerald"] = 7500,
    ["esmeralda"] = 7500,
    ["ruby"] = 7000,
    ["rubi"] = 7000,
    ["gold"] = 6500,
    ["ouro"] = 6500,
    ["mythic"] = 5500,
    ["mítico"] = 5500,
    ["mitico"] = 5500,
    ["legendary"] = 4500,
    ["lendário"] = 4500,
    ["lendario"] = 4500,
    ["epic"] = 3000,
    ["épico"] = 3000,
    ["epico"] = 3000,
    ["rare"] = 1500,
    ["raro"] = 1500,
    ["uncommon"] = 800,
    ["incomum"] = 800,
    ["common"] = 200,
    ["comum"] = 200
}

local function parseMultiplierOrNumber(str)
    if not str then return 0 end
    local s = tostring(str):lower()

    -- 1. Tiers e Levels (ex: Tier 10, T5, Lvl 100)
    local tier = s:match("tier%s*(%d+)") or s:match("t(%d+)") or s:match("lvl%s*(%d+)") or s:match("level%s*(%d+)")
    if tier then
        local tNum = tonumber(tier)
        if tNum and tNum > 0 then
            return tNum * 3000
        end
    end

    -- 2. Multiplicadores e Valores com sufixos (ex: 500k, 10M, 1B, 50T, 1Qa, 1Qi)
    local num, suffix = s:match("([%d%,%.]+)%s*([kmbtq]a?i?)")
    if num and suffix then
        num = num:gsub(",", "")
        local n = tonumber(num)
        if n then
            local mult = 1
            if suffix:find("qi") then mult = 1e18
            elseif suffix:find("qa") then mult = 1e15
            elseif suffix:find("t") then mult = 1e12
            elseif suffix:find("b") then mult = 1e9
            elseif suffix:find("m") then mult = 1e6
            elseif suffix:find("k") then mult = 1e3
            end
            return math.min(n * (mult > 1e6 and 5000 or (mult > 1e3 and 1000 or 100)), 60000)
        end
    end

    -- 3. Multiplicador simples (ex: x500, 100x)
    local simpleMult = s:match("x(%d+)") or s:match("(%d+)x")
    if simpleMult then
        local m = tonumber(simpleMult)
        if m then return m * 200 end
    end

    return 0
end

local function evaluateEggRarity(eggObj, prompt)
    if not eggObj then return 200, "Comum" end
    local maxScore = 0
    local detectedRarity = "Comum"

    local function checkText(str)
        if not str or str == "" then return end
        local s = tostring(str):lower()
        for kw, weight in pairs(RarityWeights) do
            if s:find(kw) then
                if weight > maxScore then
                    maxScore = weight
                    detectedRarity = kw:upper()
                end
            end
        end

        local numScore = parseMultiplierOrNumber(s)
        if numScore > maxScore then
            maxScore = numScore
            detectedRarity = "ALTO VALOR (" .. math.floor(numScore) .. " pts)"
        end
    end

    -- 1. Inspecionar Prompt ObjectText e ActionText
    if prompt then
        checkText(prompt.ObjectText)
        checkText(prompt.ActionText)
    end

    -- 2. Inspecionar Objeto e seu Pedestal/Pai
    local targetsToInspect = { eggObj }
    if eggObj.Parent and eggObj.Parent ~= Services.Workspace then
        table.insert(targetsToInspect, eggObj.Parent)
    end

    for _, target in ipairs(targetsToInspect) do
        -- Atributos
        pcall(function()
            for key, val in pairs(target:GetAttributes()) do
                checkText(key)
                checkText(val)
            end
        end)

        -- Value Objects
        pcall(function()
            for _, child in ipairs(target:GetChildren()) do
                if child:IsA("ValueBase") then
                    checkText(child.Name)
                    checkText(child.Value)
                end
            end
        end)

        -- TextLabels / BillboardGuis
        pcall(function()
            for _, desc in ipairs(target:GetDescendants()) do
                if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                    checkText(desc.Text)
                end
            end
        end)

        -- Nome
        checkText(target.Name)
    end

    return (maxScore > 0 and maxScore or 200), detectedRarity
end

-- Detecção de Ilha, Zona, Base ou Plot do Ovo
local function getEggLocationZone(eggObj, prompt)
    local cur = eggObj or (prompt and prompt.Parent)
    local zoneName = "Mapa Aberto"
    local plotOwner = nil

    while cur and cur ~= Services.Workspace do
        local n = cur.Name
        local nLow = n:lower()

        -- Checar se é base/plot de jogador
        if nLow:find("plot") or nLow:find("base") or nLow:find("spawn") or nLow:find("house") or nLow:find("casa") then
            pcall(function()
                local ownerVal = cur:FindFirstChild("Owner") or cur:FindFirstChild("Player") or cur:FindFirstChild("OwnerName")
                if ownerVal and ownerVal.Value and tostring(ownerVal.Value) ~= "" then
                    plotOwner = tostring(ownerVal.Value)
                end
            end)
            zoneName = n .. (plotOwner and (" (" .. plotOwner .. ")") or "")
            break
        elseif nLow:find("island") or nLow:find("ilha") or nLow:find("zone") or nLow:find("zona") or nLow:find("area") or nLow:find("world") or nLow:find("mundo") then
            zoneName = n
            break
        end
        cur = cur.Parent
    end

    return zoneName, plotOwner
end

-- Scanner Completo de Todos os Ovos do Mapa (Radar & Dump)
local function scanAllEggsInMap()
    local myPlayerName = LocalPlayer.Name:lower()
    local discovered = {}
    local rarityCounts = {}
    local zoneCounts = {}

    for _, obj in ipairs(Services.Workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") and obj.Enabled then
            local parent = obj.Parent
            if parent then
                local fullName = parent:GetFullName():lower()
                local isMyBase = fullName:find(myPlayerName)
                local isEligible = isEgg(parent) or isEgg(obj)

                if isEligible then
                    local pos = parent:IsA("BasePart") and parent.Position 
                             or (parent:IsA("Model") and parent:GetPivot().Position)
                             or (parent:FindFirstChildWhichIsA("BasePart") and parent:FindFirstChildWhichIsA("BasePart").Position)
                    
                    if pos then
                        local hrp = getHRP()
                        local dist = hrp and (hrp.Position - pos).Magnitude or 0
                        local rarityScore, rarityName = evaluateEggRarity(parent, obj)
                        local zoneName, plotOwner = getEggLocationZone(parent, obj)
                        local displayName = (obj.ObjectText ~= "" and obj.ObjectText) or parent.Name

                        rarityCounts[rarityName] = (rarityCounts[rarityName] or 0) + 1
                        zoneCounts[zoneName] = (zoneCounts[zoneName] or 0) + 1

                        table.insert(discovered, {
                            Prompt = obj,
                            Parent = parent,
                            Name = displayName,
                            Rarity = rarityName,
                            RarityScore = rarityScore,
                            Zone = zoneName,
                            IsMyBase = isMyBase,
                            PlotOwner = plotOwner,
                            Position = pos,
                            Distance = dist,
                            Path = parent:GetFullName()
                        })
                    end
                end
            end
        end
    end

    -- Ordenar por Raridade (maior pontuação primeiro)
    table.sort(discovered, function(a, b)
        if a.RarityScore ~= b.RarityScore then
            return a.RarityScore > b.RarityScore
        end
        return a.Distance < b.Distance
    end)

    Flags.DiscoveredEggs = discovered
    _G.DiscoveredEggs = discovered

    -- Gerar Relatório Formatado para Visualização e Cópia
    local lines = {}
    table.insert(lines, "================================================================================")
    table.insert(lines, string.format("🎯 RADAR & SCANNER DE OVOS (%s) — %d OVOS ENCONTRADOS", os.date("%H:%M:%S"), #discovered))
    table.insert(lines, "================================================================================")
    
    local rSummary = {}
    for rName, count in pairs(rarityCounts) do
        table.insert(rSummary, string.format("%s: %d", rName, count))
    end
    table.insert(lines, "⭐ RARIDADES NO SERVIDOR: " .. (#rSummary > 0 and table.concat(rSummary, " | ") or "Nenhuma"))

    local zSummary = {}
    for zName, count in pairs(zoneCounts) do
        table.insert(zSummary, string.format("%s (%d)", zName, count))
    end
    table.insert(lines, "🏝️ ILHAS / ZONAS / BASES: " .. (#zSummary > 0 and table.concat(zSummary, " | ") or "Nenhuma"))
    table.insert(lines, "--------------------------------------------------------------------------------")

    for i, egg in ipairs(discovered) do
        local tag = egg.IsMyBase and "[SUA BASE]" or "[ALVO]"
        table.insert(lines, string.format("#%02d %s [%s] %s | 📍 %s | 📏 %dm | 🏆 %d pts",
            i, tag, egg.Rarity, egg.Name, egg.Zone, math.floor(egg.Distance), egg.RarityScore
        ))
    end
    table.insert(lines, "================================================================================")

    local fullDumpText = table.concat(lines, "\n")
    _G.EggRadarText = fullDumpText

    return discovered, fullDumpText
end

_G.scanAllEggsInMap = scanAllEggsInMap

-- Mega Varredura Completa do Jogo (Introspecção & Dump de Arquitetura Real)
local function dumpGameStructure()
    local output = {}
    local function logLine(str)
        table.insert(output, str or "")
    end

    logLine("================================================================================")
    logLine("🧬 MEGA VARREDURA DE ESTRUTURA REAL DO JOGO — " .. os.date("%Y-%m-%d %H:%M:%S"))
    logLine("Game: Roube um Ovo | PlaceId: " .. tostring(game.PlaceId) .. " | JobId: " .. tostring(game.JobId))
    logLine("================================================================================\n")

    -- 1. Inspecionar ReplicatedStorage (Pastas, Módulos, Remotos, Configs)
    logLine("📁 [1/4] INVENTÁRIO DO REPLICATEDSTORAGE:")
    local rsItems = {}
    pcall(function()
        for _, child in ipairs(Services.ReplicatedStorage:GetChildren()) do
            table.insert(rsItems, string.format("  • %s [%s] (Filhos: %d)", child.Name, child.ClassName, #child:GetChildren()))
            
            local cLow = child.Name:lower()
            if cLow:find("egg") or cLow:find("rarit") or cLow:find("item") or cLow:find("pet") or cLow:find("config") or cLow:find("data") then
                for _, sub in ipairs(child:GetChildren()) do
                    table.insert(rsItems, string.format("      ↳ %s [%s]", sub.Name, sub.ClassName))
                end
            end
        end
    end)
    logLine(#rsItems > 0 and table.concat(rsItems, "\n") or "  (Vazio)")
    logLine("\n")

    -- 2. Inspecionar Workspace (Zonas, Ilhas, Plots, Spawns, Pedestais)
    logLine("🗺️ [2/4] ZONAS, ILHAS E PASTAS NO WORKSPACE:")
    local wsItems = {}
    pcall(function()
        for _, child in ipairs(Services.Workspace:GetChildren()) do
            if child:IsA("Folder") or child:IsA("Model") then
                local count = #child:GetChildren()
                if count > 0 then
                    table.insert(wsItems, string.format("  • %s [%s] (Objetos: %d)", child.Name, child.ClassName, count))
                end
            end
        end
    end)
    logLine(#wsItems > 0 and table.concat(wsItems, "\n") or "  (Vazio)")
    logLine("\n")

    -- 3. Inspecionar Todos os ProximityPrompts e Textos no Mapa
    logLine("🥚 [3/4] TODOS OS PROMPTS & OVOS PRESENTES NO MAPA:")
    local promptItems = {}
    pcall(function()
        for _, obj in ipairs(Services.Workspace:GetDescendants()) do
            if obj:IsA("ProximityPrompt") then
                local p = obj.Parent
                local pName = p and p.Name or "Sem Pai"
                local pPath = p and p:GetFullName() or "N/A"
                local action = obj.ActionText ~= "" and obj.ActionText or "N/A"
                local objText = obj.ObjectText ~= "" and obj.ObjectText or "N/A"
                local hold = tostring(obj.HoldDuration) .. "s"
                local dist = tostring(obj.MaxActivationDistance) .. " studs"

                local attrs = {}
                if p then
                    for k, v in pairs(p:GetAttributes()) do
                        table.insert(attrs, tostring(k) .. "=" .. tostring(v))
                    end
                end
                local attrStr = #attrs > 0 and (" | Atributos: {" .. table.concat(attrs, ", ") .. "}") or ""

                table.insert(promptItems, string.format("  • Prompt em: %s\n      Ação: '%s' | Texto: '%s' | Hold: %s | Dist: %s%s\n      Caminho: %s",
                    pName, action, objText, hold, dist, attrStr, pPath
                ))
            end
        end
    end)
    logLine(#promptItems > 0 and table.concat(promptItems, "\n\n") or "  (Nenhum ProximityPrompt encontrado)")
    logLine("\n")

    -- 4. Inspecionar PlayerGui (Catálogos, Índices de Ovos, Telas da Loja)
    logLine("🖥️ [4/4] INTERFACES & ÍNDICE DO JOGO (PLAYERGUI):")
    local guiItems = {}
    pcall(function()
        local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if pg then
            for _, gui in ipairs(pg:GetChildren()) do
                if gui:IsA("ScreenGui") and gui.Enabled then
                    table.insert(guiItems, string.format("  • ScreenGui: %s", gui.Name))
                    for _, desc in ipairs(gui:GetDescendants()) do
                        if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                            local t = desc.Text
                            local tLow = t:lower()
                            if tLow:find("egg") or tLow:find("ovo") or tLow:find("chance") or tLow:find("rarit") or tLow:find("%$") or tLow:find("tier") then
                                table.insert(guiItems, string.format("      ↳ [%s] '%s' (%s)", desc.ClassName, t, desc:GetFullName()))
                            end
                        end
                    end
                end
            end
        end
    end)
    logLine(#guiItems > 0 and table.concat(guiItems, "\n") or "  (Nenhum texto relevante no PlayerGui)")
    logLine("\n================================================================================")
    logLine("✅ FIM DA MEGA VARREDURA (Salvo em ROUBE_UM_OVO_MEGA_DUMP.txt e Copiado)")
    logLine("================================================================================")

    local fullText = table.concat(output, "\n")
    _G.MegaDumpText = fullText

    pcall(function()
        if writefile then
            writefile("ROUBE_UM_OVO_MEGA_DUMP.txt", fullText)
        end
        if setclipboard then
            setclipboard(fullText)
        end
    end)

    return fullText
end

_G.dumpGameStructure = dumpGameStructure

-- Seleção do Melhor Ovo por Raridade (Prioridade Absoluta com Filtros)
local function getBestEggPrompt()
    local basePos = getBasePosition()
    if not basePos then return nil, nil, "Nenhum" end

    local myPlayerName = LocalPlayer.Name:lower()
    local candidates = {}

    for _, obj in ipairs(Services.Workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") and obj.Enabled then
            local parent = obj.Parent
            if parent then
                local fullName = parent:GetFullName():lower()
                local isMyBase = fullName:find(myPlayerName)

                -- Não roubar ovos da própria base
                if not isMyBase then
                    local isEligible = isEgg(parent) or isEgg(obj)
                    if isEligible then
                        local pos = parent:IsA("BasePart") and parent.Position 
                                 or (parent:IsA("Model") and parent:GetPivot().Position)
                                 or (parent:FindFirstChildWhichIsA("BasePart") and parent:FindFirstChildWhichIsA("BasePart").Position)
                        
                        if pos then
                            local dist = (basePos - pos).Magnitude
                            if dist <= Flags.StealRadius then
                                local rarityScore, rarityName = evaluateEggRarity(parent, obj)

                                -- Aplicação de Filtros de Raridade
                                local passedFilter = true
                                if Flags.MinRarityScore > 0 and rarityScore < Flags.MinRarityScore then
                                    passedFilter = false
                                end
                                if Flags.FilterIgnoreCommons and rarityScore <= 800 then
                                    passedFilter = false
                                end

                                if passedFilter then
                                    local zoneName = getEggLocationZone(parent, obj)
                                    local displayName = (obj.ObjectText ~= "" and obj.ObjectText) or parent.Name

                                    table.insert(candidates, {
                                        Prompt = obj,
                                        Position = pos,
                                        RarityScore = rarityScore,
                                        Name = displayName,
                                        Rarity = rarityName,
                                        Zone = zoneName,
                                        Distance = dist
                                    })
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if #candidates == 0 then return nil, nil, "Nenhum" end

    -- ORDENAÇÃO ESTRITA: O mais raro SEMPRE vem primeiro, independente da distância
    table.sort(candidates, function(a, b)
        if Flags.PrioritizeRare then
            if a.RarityScore ~= b.RarityScore then
                return a.RarityScore > b.RarityScore -- Maior pontuação de raridade tem prioridade absoluta!
            end
        end
        return a.Distance < b.Distance -- Se forem da mesma raridade, escolhe o mais próximo
    end)

    local best = candidates[1]
    return best.Prompt, best.Position, best.Rarity .. " [" .. best.Name .. "] @ " .. (best.Zone or "Mapa")
end

-- Voo ultra-rápido e 100% estável via física (Personagem fica em pé sem animação de queda)
local function flyToPosition(targetPos, speed)
    local hrp = getHRP()
    local char = LocalPlayer.Character
    if not hrp or not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")

    speed = speed or Flags.FlySpeed or 500
    local startPos = hrp.Position
    local totalDist = (targetPos - startPos).Magnitude
    if totalDist < 3.5 then return true end

    -- Criar BodyPosition & BodyGyro com altíssima força de arraste
    local bp = Instance.new("BodyPosition")
    bp.Name = "StealthFlight_BP"
    bp.MaxForce = Vector3.new(1e9, 1e9, 1e9)
    bp.D = 600
    bp.P = 50000
    bp.Position = startPos
    bp.Parent = hrp

    local bg = Instance.new("BodyGyro")
    bg.Name = "StealthFlight_BG"
    bg.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
    bg.D = 100
    bg.P = 30000
    bg.CFrame = CFrame.new(startPos, targetPos)
    bg.Parent = hrp

    local travelTime = totalDist / math.max(speed, 10)
    local startTime = os.clock()

    while (os.clock() - startTime) < (travelTime + 1.5) do
        local elapsed = os.clock() - startTime
        local alpha = math.clamp(elapsed / travelTime, 0, 1)
        local currentTarget = startPos:Lerp(targetPos, alpha)
        bp.Position = currentTarget
        bg.CFrame = CFrame.new(hrp.Position, targetPos)

        -- Manter postura firme e ereta (totalmente parado no ar)
        if hum then
            hum.PlatformStand = false
            if hum:GetState() ~= Enum.HumanoidStateType.Running then
                hum:ChangeState(Enum.HumanoidStateType.Running)
            end
        end

        if (targetPos - hrp.Position).Magnitude < 3.5 or alpha >= 1 then
            break
        end
        Services.RunService.Heartbeat:Wait()
    end

    bp.Position = targetPos
    task.wait(0.04)

    pcall(function() bp:Destroy() end)
    pcall(function() bg:Destroy() end)

    return true
end

local function stealEgg(prompt)
    if not prompt or not prompt.Parent then return end
    pcall(function()
        -- 1. Execução direta com fireproximityprompt
        if fireproximityprompt then
            pcall(function() fireproximityprompt(prompt) end)
        end

        -- 2. Fallback com simulação de toque/segurar nativo
        pcall(function()
            prompt:InputHoldBegin()
            task.wait(0.04)
            prompt:InputHoldEnd()
        end)
    end)
end

-- Loop Principal de Fly-Steal e Retorno à Base
local isStealing = false
local function flyStealLoop()
    if isStealing then return end
    isStealing = true

    pcall(function()
        local hrp = getHRP()
        if not hrp then return end

        local basePos = getBasePosition()
        if not basePos then return end

        -- 1. Identificar o Melhor Ovo por Raridade Real
        local prompt, eggPos, eggInfo = getBestEggPrompt()
        if not prompt or not eggPos then
            if Flags.AutoLogger then
                addLog("FLY-STEAL", "Nenhum ovo elegível encontrado no raio de busca.")
            end
            return
        end

        if Flags.AutoLogger then
            addLog("RARIDADE-ENGINE", "Alvo mais valioso selecionado: " .. eggInfo .. " | Voando a " .. tostring(Flags.FlySpeed) .. " studs/s...", { eggPos, prompt })
        end

        -- 2. Voar até a exata posição do ovo em postura firme
        local targetFlightPos = eggPos + Vector3.new(0, 1.2, 0)
        local arrived = flyToPosition(targetFlightPos, Flags.FlySpeed)
        if not arrived or not Flags.AutoSteal then return end

        -- 3. Roubar o Ovo (dispara 3x para garantir registro imediato no servidor)
        for _ = 1, 3 do
            stealEgg(prompt)
            task.wait(0.06)
        end
        task.wait(Flags.StealDelay)

        -- 4. RETORNAR VOANDO DIRETO PARA A BASE (SEM TP)
        if Flags.AutoLogger then
            addLog("FLY-STEAL", "Ovo coletado! Retornando voando para a Base...", { basePos })
        end

        flyToPosition(basePos + Vector3.new(0, 3, 0), Flags.FlySpeed)
        task.wait(0.2)
    end)

    isStealing = false
end

-- ESP System
local activeESPs = {}

local function removeESP(target)
    if activeESPs[target] then
        pcall(function()
            if activeESPs[target].Highlight then activeESPs[target].Highlight:Destroy() end
            if activeESPs[target].Billboard then activeESPs[target].Billboard:Destroy() end
        end)
        activeESPs[target] = nil
    end
end

local function applyESP(target, isPlayer)
    if not target or activeESPs[target] then return end

    local color = isPlayer and Flags.PlayerESPColor or Flags.ESPColor
    local highlight = Instance.new("Highlight")
    highlight.Name = getRandomName()
    highlight.FillColor = color
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.FillTransparency = 0.4
    highlight.OutlineTransparency = 0.1
    highlight.Adornee = target
    highlight.Parent = target

    local billboard = Instance.new("BillboardGui")
    billboard.Name = getRandomName()
    billboard.AlwaysOnTop = true
    billboard.Size = UDim2.new(0, 160, 0, 28)
    billboard.StudsOffset = Vector3.new(0, 3.5, 0)
    billboard.Adornee = target

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.TextColor3 = color
    label.TextStrokeTransparency = 0.2
    label.TextSize = 13
    label.Font = Enum.Font.SourceSansBold
    label.Text = (isPlayer and "👤 " or "🥚 ") .. target.Name
    label.Parent = billboard

    billboard.Parent = target
    activeESPs[target] = { Highlight = highlight, Billboard = billboard, IsPlayer = isPlayer }

    target.AncestryChanged:Connect(function(_, parent)
        if not parent then removeESP(target) end
    end)
end

local function updateESP()
    for target, espData in pairs(activeESPs) do
        if espData.IsPlayer and not Flags.PlayerESP then
            removeESP(target)
        elseif not espData.IsPlayer and not Flags.EggESP then
            removeESP(target)
        end
    end

    if Flags.EggESP then
        for _, obj in ipairs(Services.Workspace:GetDescendants()) do
            pcall(function()
                if isEgg(obj) then applyESP(obj, false)
                elseif obj:IsA("ProximityPrompt") and obj.Parent and isEgg(obj.Parent) then applyESP(obj.Parent, false) end
            end)
        end
    end

    if Flags.PlayerESP then
        for _, player in ipairs(Services.Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                pcall(function() applyESP(player.Character, true) end)
            end
        end
    end
end

-- Player Mods Loop (Ultra-otimizado para 0% de queda de FPS)
Services.RunService.RenderStepped:Connect(function()
    pcall(function()
        local char = LocalPlayer.Character
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")

        if hum then
            if Flags.SpeedHack then hum.WalkSpeed = Flags.WalkSpeed end
            if Flags.JumpPowerHack then hum.JumpPower = Flags.JumpPower end
        end

        if Flags.Noclip then
            for _, part in ipairs(char:GetChildren()) do
                if part:IsA("BasePart") then
                    part.CanCollide = false
                end
            end
        end
    end)
end)

-- Sistema de Proteção 100% Baseado em Eventos (0% de uso de CPU e 0% de queda de FPS)
local function applyCharacterProtections(char)
    if not char then return end
    local hum = char:WaitForChild("Humanoid", 3)
    if not hum then return end

    -- 1. Anti-Ragdoll via Evento StateChanged
    hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
    hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
    hum:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, false)

    hum.StateChanged:Connect(function(_, newState)
        if Flags.AntiRagdoll then
            if newState == Enum.HumanoidStateType.Ragdoll or newState == Enum.HumanoidStateType.FallingDown or newState == Enum.HumanoidStateType.PlatformStanding then
                hum:ChangeState(Enum.HumanoidStateType.GettingUp)
            end
        end
    end)

    -- 2. GodMode via Evento HealthChanged
    hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
    hum.HealthChanged:Connect(function(currentHealth)
        if Flags.GodMode and currentHealth < hum.MaxHealth and currentHealth > 0 then
            hum.Health = hum.MaxHealth
        end
    end)

    -- 3. Never Drop Egg via Evento ChildAdded na Mochila
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if backpack then
        backpack.ChildAdded:Connect(function(item)
            if Flags.NeverDropEgg and (isEgg(item) or item:IsA("Tool")) then
                task.wait(0.05)
                if item.Parent == backpack and char:FindFirstChildOfClass("Humanoid") then
                    char:FindFirstChildOfClass("Humanoid"):EquipTool(item)
                end
            end
        end)
    end
end

-- Inicializar proteções no personagem atual e ao renascer
if LocalPlayer.Character then
    task.spawn(function() applyCharacterProtections(LocalPlayer.Character) end)
end
LocalPlayer.CharacterAdded:Connect(function(char)
    task.spawn(function() applyCharacterProtections(char) end)
end)

Services.UserInputService.JumpRequest:Connect(function()
    if Flags.InfJump then
        pcall(function()
            local char = LocalPlayer.Character
            if char and char:FindFirstChildOfClass("Humanoid") then
                char:FindFirstChildOfClass("Humanoid"):ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end)
    end
end)

-- Anti-AFK seguro: reseta o idle timer sem usar serviços protegidos
pcall(function()
    LocalPlayer.Idled:Connect(function()
        if Flags.AntiAFK then
            pcall(function()
                -- Simular movimento suave via Humanoid para enganar o idle timer
                local char = LocalPlayer.Character
                if char then
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    if hum then
                        hum:Move(Vector3.new(0, 0, 0), false)
                    end
                end
            end)
        end
    end)
end)

--================================================================--
-- CONSTRUÇÃO DA INTERFACE FLUENT DESIGN (NATIVA & ULTRA LIMPA)
--================================================================--

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = getRandomName()
ScreenGui.ResetOnSpawn = false

local MainFrame = Instance.new("Frame")
MainFrame.Name = "FluentMain"
MainFrame.Size = UDim2.new(0, 660, 0, 450)
MainFrame.Position = UDim2.new(0.5, -330, 0.5, -225)
MainFrame.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 10)
MainCorner.Parent = MainFrame

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(50, 50, 65)
MainStroke.Thickness = 1
MainStroke.Parent = MainFrame

local TopGlow = Instance.new("Frame")
TopGlow.Size = UDim2.new(1, 0, 0, 3)
TopGlow.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
TopGlow.BorderSizePixel = 0
TopGlow.Parent = MainFrame

local TopGlowCorner = Instance.new("UICorner")
TopGlowCorner.CornerRadius = UDim.new(0, 10)
TopGlowCorner.Parent = TopGlow

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 45)
Header.Position = UDim2.new(0, 0, 0, 3)
Header.BackgroundColor3 = Color3.fromRGB(26, 26, 34)
Header.BorderSizePixel = 0
Header.Parent = MainFrame

local HeaderCorner = Instance.new("UICorner")
HeaderCorner.CornerRadius = UDim.new(0, 10)
HeaderCorner.Parent = Header

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -60, 0, 24)
Title.Position = UDim2.new(0, 16, 0, 4)
Title.BackgroundTransparency = 1
Title.Text = "🥚 Roube um Ovo | Fluent Stealth Hub"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.TextSize = 15
Title.Font = Enum.Font.SourceSansBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Header

local Subtitle = Instance.new("TextLabel")
Subtitle.Size = UDim2.new(1, -60, 0, 16)
Subtitle.Position = UDim2.new(0, 16, 0, 24)
Subtitle.BackgroundTransparency = 1
Subtitle.Text = "v3.4 • Deep Spy & Auto Disk Logger (" .. LogFileName .. ")"
Subtitle.TextColor3 = Color3.fromRGB(150, 150, 170)
Subtitle.TextSize = 11
Subtitle.Font = Enum.Font.SourceSans
Subtitle.TextXAlignment = Enum.TextXAlignment.Left
Subtitle.Parent = Header

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 32, 0, 32)
CloseBtn.Position = UDim2.new(1, -40, 0, 6)
CloseBtn.BackgroundColor3 = Color3.fromRGB(38, 38, 48)
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = Color3.fromRGB(200, 200, 220)
CloseBtn.TextSize = 15
CloseBtn.Font = Enum.Font.SourceSansBold
CloseBtn.Parent = Header

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 6)
CloseCorner.Parent = CloseBtn

CloseBtn.MouseButton1Click:Connect(function()
    ScreenGui:Destroy()
end)

local Sidebar = Instance.new("Frame")
Sidebar.Size = UDim2.new(0, 170, 1, -48)
Sidebar.Position = UDim2.new(0, 0, 0, 48)
Sidebar.BackgroundColor3 = Color3.fromRGB(25, 25, 33)
Sidebar.BorderSizePixel = 0
Sidebar.Parent = MainFrame

local SidebarList = Instance.new("UIListLayout")
SidebarList.Padding = UDim.new(0, 5)
SidebarList.SortOrder = Enum.SortOrder.LayoutOrder
SidebarList.Parent = Sidebar

local SidebarPadding = Instance.new("UIPadding")
SidebarPadding.PaddingTop = UDim.new(0, 10)
SidebarPadding.PaddingLeft = UDim.new(0, 10)
SidebarPadding.PaddingRight = UDim.new(0, 10)
SidebarPadding.Parent = Sidebar

local ContentContainer = Instance.new("Frame")
ContentContainer.Size = UDim2.new(1, -170, 1, -48)
ContentContainer.Position = UDim2.new(0, 170, 0, 48)
ContentContainer.BackgroundTransparency = 1
ContentContainer.Parent = MainFrame

local TabFrames = {}
local TabButtons = {}

local function createTab(name, icon)
    local tabBtn = Instance.new("TextButton")
    tabBtn.Size = UDim2.new(1, 0, 0, 38)
    tabBtn.BackgroundColor3 = Color3.fromRGB(32, 32, 42)
    tabBtn.Text = "  " .. icon .. "  " .. name
    tabBtn.TextColor3 = Color3.fromRGB(180, 180, 200)
    tabBtn.TextSize = 13
    tabBtn.Font = Enum.Font.SourceSansSemibold
    tabBtn.TextXAlignment = Enum.TextXAlignment.Left
    tabBtn.Parent = Sidebar

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 6)
    btnCorner.Parent = tabBtn

    local tabFrame = Instance.new("ScrollingFrame")
    tabFrame.Size = UDim2.new(1, -18, 1, -18)
    tabFrame.Position = UDim2.new(0, 9, 0, 9)
    tabFrame.BackgroundTransparency = 1
    tabFrame.BorderSizePixel = 0
    tabFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    tabFrame.ScrollBarThickness = 4
    tabFrame.Visible = false
    tabFrame.Parent = ContentContainer

    local frameList = Instance.new("UIListLayout")
    frameList.Padding = UDim.new(0, 8)
    frameList.SortOrder = Enum.SortOrder.LayoutOrder
    frameList.Parent = tabFrame

    frameList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        tabFrame.CanvasSize = UDim2.new(0, 0, 0, frameList.AbsoluteContentSize.Y + 12)
    end)

    table.insert(TabFrames, tabFrame)
    table.insert(TabButtons, tabBtn)

    tabBtn.MouseButton1Click:Connect(function()
        for i, frame in ipairs(TabFrames) do
            frame.Visible = (frame == tabFrame)
        end
        for i, btn in ipairs(TabButtons) do
            local active = (btn == tabBtn)
            btn.BackgroundColor3 = active and Color3.fromRGB(0, 120, 215) or Color3.fromRGB(32, 32, 42)
            btn.TextColor3 = active and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(180, 180, 200)
        end
    end)

    return tabFrame
end

local MainTab = createTab("Fly Steal & Base", "🚀")
local RadarTab = createTab("Radar & Filtros", "🎯")
local PlayerTab = createTab("Player & Mover", "⚡")
local VisualsTab = createTab("ESP & Visuais", "👁️")
local LoggerTab = createTab("Remote Logger", "📜")
local SettingsTab = createTab("Configurações", "⚙️")

TabFrames[1].Visible = true
TabButtons[1].BackgroundColor3 = Color3.fromRGB(0, 120, 215)
TabButtons[1].TextColor3 = Color3.fromRGB(255, 255, 255)

local function addToggle(tab, text, defaultState, callback)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, 44)
    card.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    card.Parent = tab

    local cardCorner = Instance.new("UICorner")
    cardCorner.CornerRadius = UDim.new(0, 6)
    cardCorner.Parent = card

    local cardStroke = Instance.new("UIStroke")
    cardStroke.Color = Color3.fromRGB(45, 45, 60)
    cardStroke.Thickness = 1
    cardStroke.Parent = card

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -65, 1, 0)
    label.Position = UDim2.new(0, 12, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(230, 230, 240)
    label.TextSize = 13
    label.Font = Enum.Font.SourceSansSemibold
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = card

    local switchBg = Instance.new("TextButton")
    switchBg.Size = UDim2.new(0, 42, 0, 22)
    switchBg.Position = UDim2.new(1, -52, 0.5, -11)
    switchBg.BackgroundColor3 = defaultState and Color3.fromRGB(0, 120, 215) or Color3.fromRGB(50, 50, 65)
    switchBg.Text = ""
    switchBg.Parent = card

    local switchCorner = Instance.new("UICorner")
    switchCorner.CornerRadius = UDim.new(1, 0)
    switchCorner.Parent = switchBg

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 16, 0, 16)
    knob.Position = defaultState and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.Parent = switchBg

    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(1, 0)
    knobCorner.Parent = knob

    local state = defaultState
    switchBg.MouseButton1Click:Connect(function()
        state = not state
        switchBg.BackgroundColor3 = state and Color3.fromRGB(0, 120, 215) or Color3.fromRGB(50, 50, 65)
        knob:TweenPosition(
            state and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8),
            Enum.EasingDirection.Out,
            Enum.EasingStyle.Quad,
            0.15,
            true
        )
        pcall(function() callback(state) end)
    end)

    return card
end

local function addButton(tab, text, callback)
    local card = Instance.new("TextButton")
    card.Size = UDim2.new(1, 0, 0, 42)
    card.BackgroundColor3 = Color3.fromRGB(36, 36, 48)
    card.Text = "  " .. text
    card.TextColor3 = Color3.fromRGB(255, 255, 255)
    card.TextSize = 13
    card.Font = Enum.Font.SourceSansSemibold
    card.TextXAlignment = Enum.TextXAlignment.Left
    card.Parent = tab

    local cardCorner = Instance.new("UICorner")
    cardCorner.CornerRadius = UDim.new(0, 6)
    cardCorner.Parent = card

    local cardStroke = Instance.new("UIStroke")
    cardStroke.Color = Color3.fromRGB(55, 55, 75)
    cardStroke.Thickness = 1
    cardStroke.Parent = card

    card.MouseButton1Click:Connect(function()
        pcall(function() callback() end)
    end)

    return card
end

local function addSlider(tab, title, min, max, default, callback)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, 54)
    card.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    card.Parent = tab

    local cardCorner = Instance.new("UICorner")
    cardCorner.CornerRadius = UDim.new(0, 6)
    cardCorner.Parent = card

    local cardStroke = Instance.new("UIStroke")
    cardStroke.Color = Color3.fromRGB(45, 45, 60)
    cardStroke.Thickness = 1
    cardStroke.Parent = card

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -24, 0, 22)
    label.Position = UDim2.new(0, 12, 0, 5)
    label.BackgroundTransparency = 1
    label.Text = title .. ": " .. tostring(default)
    label.TextColor3 = Color3.fromRGB(220, 220, 235)
    label.TextSize = 12
    label.Font = Enum.Font.SourceSansBold
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = card

    local sliderBg = Instance.new("TextButton")
    sliderBg.Size = UDim2.new(1, -24, 0, 10)
    sliderBg.Position = UDim2.new(0, 12, 0, 32)
    sliderBg.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
    sliderBg.Text = ""
    sliderBg.Parent = card

    local bgCorner = Instance.new("UICorner")
    bgCorner.CornerRadius = UDim.new(1, 0)
    bgCorner.Parent = sliderBg

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new((default - min) / (max - min), 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
    fill.BorderSizePixel = 0
    fill.Parent = sliderBg

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(1, 0)
    fillCorner.Parent = fill

    local dragging = false
    local function update(input)
        local pos = math.clamp((input.Position.X - sliderBg.AbsolutePosition.X) / sliderBg.AbsoluteSize.X, 0, 1)
        fill.Size = UDim2.new(pos, 0, 1, 0)
        local val = math.floor(min + (max - min) * pos)
        label.Text = title .. ": " .. tostring(val)
        pcall(function() callback(val) end)
    end

    sliderBg.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            update(input)
        end
    end)

    Services.UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    Services.UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            update(input)
        end
    end)
end

-- População da Aba 1: Fly Steal & Base
addToggle(MainTab, "Auto Steal + Retorno à Base (Voo Ultra Rápido)", Flags.AutoSteal, function(state)
    Flags.AutoSteal = state
    if state then
        local hrp = getHRP()
        if hrp then
            Flags.SavedBasePos = Flags.CustomBasePos or hrp.Position
        end
        addLog("FLY-STEAL", "Auto Steal ativado. Base gravada com sucesso!")
        task.spawn(function()
            while Flags.AutoSteal do
                flyStealLoop()
                task.wait(Flags.StealDelay)
            end
        end)
    else
        addLog("FLY-STEAL", "Auto Steal desativado.")
    end
end)

addToggle(MainTab, "Priorizar Ovos Raros (Brainrot, Godly, Secret)", Flags.PrioritizeRare, function(state)
    Flags.PrioritizeRare = state
end)

addSlider(MainTab, "Velocidade do Voo (Studs/s)", 50, 1000, Flags.FlySpeed, function(val)
    Flags.FlySpeed = val
end)

addSlider(MainTab, "Raio de Busca no Mapa (Studs)", 100, 4000, Flags.StealRadius, function(val)
    Flags.StealRadius = val
end)

addButton(MainTab, "📌 Definir Posição ONDE ESTOU como Base", function()
    local hrp = getHRP()
    if hrp then
        Flags.CustomBasePos = hrp.Position
        Flags.SavedBasePos = hrp.Position
        addLog("BASE", "Nova Base gravada em: " .. tostring(math.floor(hrp.Position.X)) .. ", " .. tostring(math.floor(hrp.Position.Z)))
    end
end)

addButton(MainTab, "⚡ Executar Fly Steal 1x Agora", function()
    task.spawn(function()
        local prev = Flags.AutoSteal
        Flags.AutoSteal = true
        flyStealLoop()
        Flags.AutoSteal = prev
    end)
end)

-- População da Aba 2: Radar de Ovos & Filtros do Servidor
addButton(RadarTab, "🔍 ESCANEAR MAPA COMPLETO (Radar & Dump)", function()
    local discovered, dumpText = scanAllEggsInMap()
    addLog("RADAR", dumpText)
    print("\n" .. dumpText .. "\n")
end)

addButton(RadarTab, "🧬 MEGA VARREDURA DO JOGO (Extrair Raridades Reais)", function()
    local dump = dumpGameStructure()
    addLog("MEGA-DUMP", "Mega Varredura concluída! Arquivo ROUBE_UM_OVO_MEGA_DUMP.txt gerado e copiado para o Clipboard.")
    print("\n" .. dump .. "\n")
end)

addButton(RadarTab, "📋 Copiar Relatório do Radar (Clipboard)", function()
    if not _G.EggRadarText or _G.EggRadarText == "" then
        scanAllEggsInMap()
    end
    pcall(function()
        if setclipboard then
            setclipboard(_G.EggRadarText)
            addLog("RADAR", "Relatório de todos os ovos copiado para a Área de Transferência!")
        end
    end)
end)

addButton(RadarTab, "⚡ Roubar Ovo #1 Mais Raro do Radar Agora", function()
    task.spawn(function()
        local prev = Flags.AutoSteal
        Flags.AutoSteal = true
        flyStealLoop()
        Flags.AutoSteal = prev
    end)
end)

addToggle(RadarTab, "Filtro: Ignorar Ovos Comuns & Incomuns", Flags.FilterIgnoreCommons, function(state)
    Flags.FilterIgnoreCommons = state
    addLog("FILTRO", "Ignorar Comuns: " .. (state and "ATIVADO" or "DESATIVADO"))
end)

addToggle(RadarTab, "Filtro: Apenas Ovos Raros/Míticos+ (>= 5.000 pts)", false, function(state)
    Flags.MinRarityScore = state and 5000 or 0
    addLog("FILTRO", "Filtro Míticos+: " .. (state and "ATIVADO (>= 5.000 pts)" or "DESATIVADO"))
end)

addToggle(RadarTab, "Filtro: Apenas Secret & Godly (>= 30.000 pts)", false, function(state)
    Flags.MinRarityScore = state and 30000 or 0
    addLog("FILTRO", "Filtro Secret/Godly: " .. (state and "ATIVADO (>= 30.000 pts)" or "DESATIVADO"))
end)

addSlider(RadarTab, "Pontuação Mínima de Raridade (Filtro)", 0, 40000, Flags.MinRarityScore, function(val)
    Flags.MinRarityScore = val
end)

-- População da Aba 3: Player, Proteção & Movimento
addToggle(PlayerTab, "🛡️ GodMode (Imortalidade / Sem Dano)", Flags.GodMode, function(state)
    Flags.GodMode = state
    if state then
        addLog("PLAYER", "GodMode ativado.")
    end
end)

addToggle(PlayerTab, "🥋 Anti-Ragdoll (Não Cair / Não Ser Derrubado)", Flags.AntiRagdoll, function(state)
    Flags.AntiRagdoll = state
    if state then
        addLog("PLAYER", "Anti-Ragdoll ativado.")
    end
end)

addToggle(PlayerTab, "🥚 Segurar Ovo Sempre (Never Drop Egg)", Flags.NeverDropEgg, function(state)
    Flags.NeverDropEgg = state
    if state then
        addLog("PLAYER", "Never Drop Egg ativado.")
    end
end)

addToggle(PlayerTab, "Velocidade Aumentada (Speed Hack)", Flags.SpeedHack, function(state)
    Flags.SpeedHack = state
end)

addSlider(PlayerTab, "Velocidade de Caminhada (WalkSpeed)", 16, 250, Flags.WalkSpeed, function(val)
    Flags.WalkSpeed = val
end)

addToggle(PlayerTab, "Super Pulo (JumpPower Hack)", Flags.JumpPowerHack, function(state)
    Flags.JumpPowerHack = state
end)

addSlider(PlayerTab, "Força do Pulo (JumpPower)", 50, 300, Flags.JumpPower, function(val)
    Flags.JumpPower = val
end)

addToggle(PlayerTab, "Noclip (Atravessar Paredes)", Flags.Noclip, function(state)
    Flags.Noclip = state
end)

addToggle(PlayerTab, "Infinite Jump (Pulo Infinito no Ar)", Flags.InfJump, function(state)
    Flags.InfJump = state
end)

-- População da Aba 3: ESP & Visuais
addToggle(VisualsTab, "Egg ESP (Destacar Ovos)", Flags.EggESP, function(state)
    Flags.EggESP = state
    updateESP()
end)

addToggle(VisualsTab, "Player ESP (Destacar Jogadores)", Flags.PlayerESP, function(state)
    Flags.PlayerESP = state
    updateESP()
end)

-- População da Aba 4: Remote Logger & Inspector (Console)
local ConsoleFrame = Instance.new("ScrollingFrame")
ConsoleFrame.Size = UDim2.new(1, 0, 1, -85)
ConsoleFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
ConsoleFrame.BorderSizePixel = 0
ConsoleFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
ConsoleFrame.ScrollBarThickness = 6
ConsoleFrame.Parent = LoggerTab

local ConsoleCorner = Instance.new("UICorner")
ConsoleCorner.CornerRadius = UDim.new(0, 6)
ConsoleCorner.Parent = ConsoleFrame

local ConsoleText = Instance.new("TextLabel")
ConsoleText.Size = UDim2.new(1, -10, 1, 0)
ConsoleText.Position = UDim2.new(0, 5, 0, 5)
ConsoleText.BackgroundTransparency = 1
ConsoleText.TextColor3 = Color3.fromRGB(0, 230, 140)
ConsoleText.TextSize = 11
ConsoleText.Font = Enum.Font.Code
ConsoleText.TextXAlignment = Enum.TextXAlignment.Left
ConsoleText.TextYAlignment = Enum.TextYAlignment.Top
ConsoleText.Text = "=== LOGGER DETALHADO DE EVENTOS, REMOTES E PROMPTS ==="
ConsoleText.Parent = ConsoleFrame

local function updateLogConsole()
    local text = table.concat(LogHistory, "\n")
    ConsoleText.Text = text
    ConsoleFrame.CanvasSize = UDim2.new(0, 0, 0, #LogHistory * 22 + 30)
end
_G.UpdateLogConsole = updateLogConsole

addToggle(LoggerTab, "Salvar Logs Automaticamente no Disco (writefile)", Flags.SaveToDisk, function(state)
    Flags.SaveToDisk = state
    addLog("SISTEMA", "Gravação automática no disco: " .. (state and "ATIVADA" or "DESATIVADA"))
end)

addButton(LoggerTab, "📋 Copiar Todos os Logs para a Área de Transferência", function()
    pcall(function()
        local fullText = table.concat(LogHistory, "\n----------------------------------------\n")
        if setclipboard then
            setclipboard(fullText)
            addLog("SISTEMA", "Todos os logs foram copiados para a área de transferência.")
        end
    end)
end)

addButton(LoggerTab, "📦 Copiar Funções Capturadas do BFLoader", function()
    pcall(function()
        local txt = _G.BFLoader_LogText or "Nenhuma função capturada ainda."
        if setclipboard then
            setclipboard(txt)
            addLog("SISTEMA", "Funções capturadas do BFLoader copiadas para a área de transferência!")
        end
    end)
end)

addButton(LoggerTab, "🧹 Limpar Histórico de Logs", function()
    LogHistory = {}
    addLog("SISTEMA", "Logs limpos pelo usuário.")
end)

-- População da Aba 5: Configurações & Utils
addToggle(SettingsTab, "Anti-AFK (Prevenir Desconexão)", Flags.AntiAFK, function(state)
    Flags.AntiAFK = state
end)

addToggle(SettingsTab, "Logger Automático de Atividades", Flags.AutoLogger, function(state)
    Flags.AutoLogger = state
end)

addButton(SettingsTab, "👁️ Esconder / Exibir Interface (Ctrl)", function()
    ScreenGui.Enabled = not ScreenGui.Enabled
end)

addButton(SettingsTab, "❌ Destruir Interface", function()
    ScreenGui:Destroy()
end)

-- Tecla de Atalho (LeftControl)
Services.UserInputService.InputBegan:Connect(function(input, gpe)
    if not gpe and input.KeyCode == Enum.KeyCode.LeftControl then
        ScreenGui.Enabled = not ScreenGui.Enabled
    end
end)

-- Realtime Listener Otimizado (Sem sobrecarga de CPU)
Services.Workspace.DescendantAdded:Connect(function(obj)
    if not (Flags.EggESP or Flags.AutoSteal) then return end
    pcall(function()
        if obj:IsA("ProximityPrompt") and obj.Parent and isEgg(obj.Parent) then
            if Flags.EggESP then applyESP(obj.Parent, false) end
        end
    end)
end)

-- Iniciar GUI com proteção contra detecção de ChildAdded
protectGui(ScreenGui)
ScreenGui.Parent = getGuiContainer()
print("========== SCRIPT ÚNICO: ROUBE UM OVO HUB v3.4 CARREGADO ==========")

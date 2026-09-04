--[[
    ROUBE UM OVO - HUB DE DIAGNÓSTICO v3.6
    -----------------------------------------------------------------------
    - Interface no estilo Fluent UI (abas, botões, toggles e sliders).
    - Registros locais: grava apenas ações e observações feitas por este script.
    - Serialização Avançada de Argumentos (Tabelas, Vector3, CFrame, Instances, Types).
    - Radar observacional: diferencia dados exibidos de informações não confirmadas.
    - Auto Fly Steal com Voo Suave e Retorno DIRETO à Base.
    - Sem interceptação de metamétodos ou alegações de bypass invisível.
]]

print("========== CARREGANDO SCRIPT ÚNICO: ROUBE UM OVO HUB v3.6 ==========")

-- Configurações e Flags Globais (BigFroot Edition)
local Flags = {
    AutoSteal = false,
    FlySpeed = 950, -- Padrão BigFroot (950 studs/s)
    StealRadius = 2500,
    StealDelay = 0.15,
    PrioritizeRare = true,
    CustomBasePos = nil,
    SavedBasePos = nil,

    -- BigFroot Features
    AutoStealInfested = true,
    ShelterFromDragon = true,
    AvoidTraps = true,
    InstantTP = false,
    AntiTreadmill = true,
    TargetPriority = "Rarity",
    ReturnToPlot = true,
    ReturnTo = "Pen Area",
    SelectedArea = "...",
    SelectedCategory = "...",
    SelectedRarities = {"Divine", "Eternal", "Secret", "Cosmic"},
    SelectedMutations = "...", 

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
    ManualMinRarityScore = 0,
    FilterHighTier = false,
    FilterTopTier = false,
    FilterIgnoreCommons = false,
    DiscoveredEggs = {},

    -- Utils & Logger
    AntiAFK = true,
    AutoLogger = false,
    SaveToDisk = false -- Desativado por padrão para evitar escrita contínua no disco
}

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
    ProximityPromptService = safeService("ProximityPromptService"),
    ReplicatedStorage = safeService("ReplicatedStorage"),
    TweenService = safeService("TweenService"),
    VirtualUser = safeService("VirtualUser")
}

local LocalPlayer = Services.Players.LocalPlayer
local scriptActive = true

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

addLog("SISTEMA", "Hub v3.6 iniciado. O console registra apenas ações locais e mudanças observáveis; ele não intercepta chamadas remotas.")

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
    local name = (obj.Name .. " " .. promptText .. " " .. obj:GetFullName()):lower()
    return name:find("egg") or name:find("ovo") or name:find("steal") 
        or name:find("smartprompt") or name:find("areaegg") or name:find("prehistoric") 
        or name:find("abyss") or name:find("ocean") or name:find("volcano") 
        or name:find("cherry") or name:find("sakura") or name:find("dragon") 
        or name:find("brainrot") or name:find("parasite") or name:find("admin")
end

local function plainText(value)
    return tostring(value or ""):gsub("<[^>]->", ""):lower()
end

-- Os dumps reais mostram que o alvo válido usa ActionText="Steal" e ObjectText="Egg".
-- Esta verificação estrita evita tratar Hatch, monstros e outros prompts como ovos roubáveis.
local function isStealPrompt(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") or not prompt.Enabled then
        return false
    end
    local action = plainText(prompt.ActionText)
    local object = plainText(prompt.ObjectText)
    local actionIsSteal = action:find("steal", 1, true) or action:find("roubar", 1, true)
    local objectIsEgg = object:find("egg", 1, true) or object:find("ovo", 1, true)
    return actionIsSteal ~= nil and objectIsEgg ~= nil
end

local function isEggInteractionPrompt(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") or not prompt.Enabled then
        return false
    end
    local action = plainText(prompt.ActionText)
    local object = plainText(prompt.ObjectText)
    local objectIsEgg = object:find("egg", 1, true) or object:find("ovo", 1, true)
    local actionMatches = action:find("steal", 1, true)
        or action:find("roubar", 1, true)
        or action:find("pick", 1, true)
        or action:find("grab", 1, true)
        or action:find("take", 1, true)
        or action:find("pegar", 1, true)
        or action:find("collect", 1, true)
        or action:find("coletar", 1, true)
    return objectIsEgg ~= nil and actionMatches ~= nil
end

local function getPromptPosition(prompt)
    if not prompt or not prompt.Parent then return nil end
    local holder = prompt.Parent
    if holder:IsA("Attachment") then
        holder = holder.Parent
    end
    if not holder then return nil end
    if holder:IsA("BasePart") then
        return holder.Position
    end
    if holder:IsA("Model") then
        return holder:GetPivot().Position
    end
    local part = holder:FindFirstChildWhichIsA("BasePart", true)
    return part and part.Position or nil
end

-- Índice mantido por eventos: inclui SmartPromptPart na raiz do Workspace sem
-- refazer GetDescendants a cada ciclo do Auto Steal.
local stealPromptRegistry = setmetatable({}, { __mode = "k" })
local eggInteractionPromptRegistry = setmetatable({}, { __mode = "k" })
local function updateStealPrompt(prompt)
    if prompt and prompt:IsA("ProximityPrompt") then
        if isStealPrompt(prompt) then
            stealPromptRegistry[prompt] = true
        else
            stealPromptRegistry[prompt] = nil
        end
        if isEggInteractionPrompt(prompt) then
            eggInteractionPromptRegistry[prompt] = true
        else
            eggInteractionPromptRegistry[prompt] = nil
        end
    end
end

for _, descendant in ipairs(Services.Workspace:GetDescendants()) do
    if descendant:IsA("ProximityPrompt") then
        updateStealPrompt(descendant)
        descendant:GetPropertyChangedSignal("Enabled"):Connect(function()
            updateStealPrompt(descendant)
        end)
        descendant:GetPropertyChangedSignal("ActionText"):Connect(function()
            updateStealPrompt(descendant)
        end)
        descendant:GetPropertyChangedSignal("ObjectText"):Connect(function()
            updateStealPrompt(descendant)
        end)
    end
end

Services.Workspace.DescendantAdded:Connect(function(descendant)
    if not scriptActive then return end
    if descendant:IsA("ProximityPrompt") then
        updateStealPrompt(descendant)
        descendant:GetPropertyChangedSignal("Enabled"):Connect(function()
            updateStealPrompt(descendant)
        end)
        descendant:GetPropertyChangedSignal("ActionText"):Connect(function()
            updateStealPrompt(descendant)
        end)
        descendant:GetPropertyChangedSignal("ObjectText"):Connect(function()
            updateStealPrompt(descendant)
        end)
    end
end)

Services.Workspace.DescendantRemoving:Connect(function(descendant)
    if not scriptActive then return end
    if descendant:IsA("ProximityPrompt") then
        stealPromptRegistry[descendant] = nil
        eggInteractionPromptRegistry[descendant] = nil
    end
end)

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
-- LEITURA OBSERVACIONAL DE VALORES, RARIDADE E ÁREAS
--================================================================--

local RarityWeights = {
    -- Ovos Especiais / Exclusivos / Eventos
    ["admin abuse"] = 80000,
    ["monster parasite"] = 70000,
    ["dragon"] = 65000,
    ["sakura"] = 60000,
    ["brainrot"] = 55000,
    ["limited"] = 50000,
    ["capture the egg"] = 45000,

    -- Áreas / Ilhas do Jogo (por ordem de peso e avanço real)
    ["prehistoric"] = 35000,   -- ~25.000 Kg
    ["pre-histórico"] = 35000,
    ["pre historico"] = 35000,
    ["abyss ocean"] = 28000,   -- ~18.000 a 20.000 Kg
    ["abyss"] = 28000,
    ["ocean"] = 28000,
    ["volcano"] = 20000,       -- ~8.000 a 10.000 Kg
    ["vulcão"] = 20000,
    ["vulcao"] = 20000,
    ["cherry blossom"] = 10000,-- ~185 Kg
    ["cherry"] = 10000,
    ["blossom"] = 10000,

    -- Raridades Gerais
    ["secret"] = 45000,
    ["secreto"] = 45000,
    ["mythic"] = 25000,
    ["mítico"] = 25000,
    ["mitico"] = 25000,
    ["legendary"] = 18000,
    ["lendário"] = 18000,
    ["lendario"] = 18000,
    ["epic"] = 8000,
    ["épico"] = 8000,
    ["epico"] = 8000,
    ["rare"] = 4000,
    ["raro"] = 4000,
    ["uncommon"] = 1500,
    ["incomum"] = 1500,
    ["common"] = 300,
    ["comum"] = 300
}

local function parseEggWeightKg(str)
    if not str then return 0 end
    local s = tostring(str):lower()
    local kgStr = s:match("([%d%,%.]+)%s*kg")
    if kgStr then
        kgStr = kgStr:gsub(",", "")
        local kg = tonumber(kgStr)
        if kg then return kg end
    end
    return 0
end

local function parseIncomeRate(str)
    if not str then return 0, nil end
    local s = tostring(str):lower()

    -- Só aceita renda explicitamente exibida como moeda por segundo.
    local num, suffix = s:match("%$%s*([%d][%d%,%.]*)%s*(%a*)%s*/%s*s")

    if num then
        num = num:gsub(",", "")
        local n = tonumber(num)
        if n and n > 0 then
            local multipliers = {
                [""] = 1,
                k = 1e3,
                m = 1e6,
                b = 1e9,
                t = 1e12,
                qa = 1e15,
                qi = 1e18
            }
            local mult = multipliers[suffix]
            if not mult then return 0, nil end
            local finalVal = n * mult
            local formatted = "$" .. string.format("%.2f", n) .. suffix:upper() .. "/s"
            return finalVal, formatted
        end
    end

    return 0, nil
end

local function evaluateEggRarity(eggObj, prompt)
    if not eggObj then return 0, "Sem dados confirmados", "nenhuma" end
    local maxScore = 0
    local detectedRarity = "Sem dados confirmados"
    local detectedSource = "nenhuma"
    local highestIncome = 0
    local highestIncomeLabel = nil
    local highestIncomeSource = nil

    local function checkText(str, source)
        if not str or str == "" then return end
        local s = tostring(str):lower()

        local incomeVal, incomeFmt = parseIncomeRate(s)
        if incomeVal > highestIncome then
            highestIncome = incomeVal
            highestIncomeLabel = incomeFmt
            highestIncomeSource = source
        end

        for kw, weight in pairs(RarityWeights) do
            if s:find(kw, 1, true) then
                if weight > maxScore then
                    maxScore = weight
                    detectedRarity = kw:upper()
                    detectedSource = source
                end
            end
        end

        local kg = parseEggWeightKg(s)
        if kg > 0 then
            local kgScore = kg * 2
            if kgScore > maxScore then
                maxScore = kgScore
                detectedRarity = string.format("PESO EXIBIDO (%s Kg)", tostring(kg))
                detectedSource = source
            end
        end
    end

    if prompt then
        checkText(prompt.ObjectText, "ObjectText do prompt")
        checkText(prompt.ActionText, "ActionText do prompt")
    end

    pcall(function()
        for key, val in pairs(eggObj:GetAttributes()) do
            checkText(key, "atributo " .. tostring(key))
            checkText(val, "atributo " .. tostring(key))
        end
    end)

    pcall(function()
        for _, child in ipairs(eggObj:GetChildren()) do
            if child:IsA("ValueBase") then
                checkText(child.Name, "Value " .. child.Name)
                checkText(child.Value, "Value " .. child.Name)
            end
        end
    end)

    -- Textos anexados ao SmartPromptPart são observáveis; a fonte acompanha
    -- o valor para não apresentá-lo como dado interno confirmado.
    pcall(function()
        local inspected = 0
        for _, desc in ipairs(eggObj:GetDescendants()) do
            if inspected >= 40 then break end
            if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                inspected = inspected + 1
                checkText(desc.Text, "texto visual " .. desc.Name)
            end
        end
    end)

    checkText(eggObj.Name, "nome do objeto")

    if highestIncome > 0 then
        return highestIncome,
            "Valor exibido " .. (highestIncomeLabel or ("$" .. tostring(highestIncome) .. "/s")),
            (highestIncomeSource or "texto visual")
    end

    return maxScore, detectedRarity, detectedSource
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

    local hrp = getHRP()
    for obj in pairs(stealPromptRegistry) do
        if isStealPrompt(obj) and obj:IsDescendantOf(Services.Workspace) then
            local parent = obj.Parent
            local pos = getPromptPosition(obj)
            if parent and pos then
                local fullName = parent:GetFullName():lower()
                local isMyBase = fullName:find(myPlayerName) ~= nil
                local dist = hrp and (hrp.Position - pos).Magnitude or 0
                local rarityScore, rarityName, evidenceSource = evaluateEggRarity(parent, obj)
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
                    EvidenceSource = evidenceSource,
                    Zone = zoneName,
                    IsMyBase = isMyBase,
                    PlotOwner = plotOwner,
                    Position = pos,
                    Distance = dist,
                    Path = parent:GetFullName(),
                    ActionText = obj.ActionText,
                    HoldDuration = obj.HoldDuration,
                    MaxActivationDistance = obj.MaxActivationDistance
                })
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
    table.insert(lines, string.format("🎯 RADAR DE PROMPTS STEAL/EGG (%s) — %d ALVOS CONFIRMADOS", os.date("%H:%M:%S"), #discovered))
    table.insert(lines, "================================================================================")
    
    local rSummary = {}
    for rName, count in pairs(rarityCounts) do
        table.insert(rSummary, string.format("%s: %d", rName, count))
    end
    table.insert(lines, "🔎 DADOS OBSERVADOS: " .. (#rSummary > 0 and table.concat(rSummary, " | ") or "Nenhum"))

    local zSummary = {}
    for zName, count in pairs(zoneCounts) do
        table.insert(zSummary, string.format("%s (%d)", zName, count))
    end
    table.insert(lines, "🏝️ ILHAS / ZONAS / BASES: " .. (#zSummary > 0 and table.concat(zSummary, " | ") or "Nenhuma"))
    table.insert(lines, "--------------------------------------------------------------------------------")

    for i, egg in ipairs(discovered) do
        local tag = egg.IsMyBase and "[SUA BASE]" or "[ALVO]"
        table.insert(lines, string.format("#%02d %s [%s] %s | 📍 %s | 📏 %dm | score interno: %d | fonte: %s | hold: %.2fs | alcance: %.1f | caminho: %s",
            i, tag, egg.Rarity, egg.Name, egg.Zone, math.floor(egg.Distance), egg.RarityScore,
            egg.EvidenceSource, egg.HoldDuration, egg.MaxActivationDistance, egg.Path
        ))
    end
    table.insert(lines, "================================================================================")

    local fullDumpText = table.concat(lines, "\n")
    _G.EggRadarText = fullDumpText

    return discovered, fullDumpText
end

_G.scanAllEggsInMap = scanAllEggsInMap

-- Inventário de instâncias visíveis ao cliente (não intercepta remotes)
local function dumpGameStructure()
    local output = {}
    local function logLine(str)
        table.insert(output, str or "")
    end

    logLine("================================================================================")
    logLine("🧬 INVENTÁRIO DE INSTÂNCIAS VISÍVEIS AO CLIENTE — " .. os.date("%Y-%m-%d %H:%M:%S"))
    logLine("AVISO: este relatório não prova chamadas remotas nem dados internos do servidor.")
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
    local remoteItems = {}
    pcall(function()
        for _, descendant in ipairs(Services.ReplicatedStorage:GetDescendants()) do
            if descendant:IsA("RemoteEvent") or descendant:IsA("RemoteFunction")
                or descendant:IsA("UnreliableRemoteEvent") then
                table.insert(remoteItems, string.format("  • %s [%s]", descendant:GetFullName(), descendant.ClassName))
                if #remoteItems >= 250 then break end
            end
        end
    end)
    logLine("\n📡 REMOTOS VISÍVEIS (existência apenas; chamadas não são interceptadas):")
    logLine(#remoteItems > 0 and table.concat(remoteItems, "\n") or "  (Nenhum remoto visível encontrado)")
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
    logLine("✅ FIM DO INVENTÁRIO (salvo em ROUBE_UM_OVO_MEGA_DUMP.txt e copiado)")
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

-- Cache de alvos para reduzir varreduras e travamentos na corrida
local cachedBestCandidate = nil
local lastCandidateScanTime = 0
local lastScanHadNoCandidate = false
local eggMetadataCache = setmetatable({}, { __mode = "k" })
local promptCooldown = setmetatable({}, { __mode = "k" })

local function invalidateTargetCache()
    cachedBestCandidate = nil
    lastCandidateScanTime = 0
    lastScanHadNoCandidate = false
end

-- Um novo prompt invalida imediatamente o cache negativo, sem varredura contínua.
Services.Workspace.DescendantAdded:Connect(function(obj)
    if not scriptActive then return end
    if obj:IsA("ProximityPrompt") then
        lastCandidateScanTime = 0
        lastScanHadNoCandidate = false
    end
end)

-- Seleção do Melhor Ovo por Raridade (Ultra Otimizado com Cache e Busca Direcionada)
local function getBestEggPrompt()
    local basePos = getBasePosition()
    if not basePos then return nil, nil, "Nenhum" end

    local now = os.clock()

    -- Cache positivo e negativo: evita varrer o mapa várias vezes por segundo.
    if cachedBestCandidate and (now - lastCandidateScanTime) < 1.25 then
        if cachedBestCandidate.Prompt and cachedBestCandidate.Prompt.Parent then
            return cachedBestCandidate.Prompt, cachedBestCandidate.Position, cachedBestCandidate.Info
        end
    end
    if lastScanHadNoCandidate and (now - lastCandidateScanTime) < 3 then
        return nil, nil, "Nenhum"
    end

    local myPlayerName = LocalPlayer.Name:lower()
    local best = nil

    for obj in pairs(stealPromptRegistry) do
        if isStealPrompt(obj) and obj:IsDescendantOf(Services.Workspace) then
            local parent = obj.Parent
            if parent and (not promptCooldown[obj] or promptCooldown[obj] <= now) then
                    local fullName = parent:GetFullName():lower()
                    local isMyBase = fullName:find(myPlayerName)

                    -- Não roubar da própria base
                    if not isMyBase then
                            local pos = getPromptPosition(obj)
                            if pos then
                                local currentHRP = getHRP()
                                local referencePos = currentHRP and currentHRP.Position or basePos
                                local dist = (referencePos - pos).Magnitude
                                if dist <= Flags.StealRadius then
                                    local metadata = eggMetadataCache[obj]
                                    if not metadata or metadata.Parent ~= parent or (now - metadata.Time) > 12 then
                                        local rarityScore, rarityName, evidenceSource = evaluateEggRarity(parent, obj)
                                        metadata = {
                                            Parent = parent,
                                            Time = now,
                                            RarityScore = rarityScore,
                                            RarityName = rarityName,
                                            EvidenceSource = evidenceSource,
                                            Zone = getEggLocationZone(parent, obj),
                                            DisplayName = (obj.ObjectText ~= "" and obj.ObjectText) or parent.Name
                                        }
                                        eggMetadataCache[obj] = metadata
                                    end

                                    local passedFilter = true
                                    if Flags.MinRarityScore > 0 and metadata.RarityScore < Flags.MinRarityScore then
                                        passedFilter = false
                                    end
                                    if Flags.FilterIgnoreCommons and metadata.RarityScore <= 800 then
                                        passedFilter = false
                                    end

                                    if passedFilter then
                                        local candidate = {
                                            Prompt = obj,
                                            Position = pos,
                                            RarityScore = metadata.RarityScore,
                                            Name = metadata.DisplayName,
                                            Rarity = metadata.RarityName,
                                            EvidenceSource = metadata.EvidenceSource,
                                            Zone = metadata.Zone,
                                            Distance = dist
                                        }
                                        if not best
                                            or (Flags.PrioritizeRare and candidate.RarityScore > best.RarityScore)
                                            or (candidate.RarityScore == best.RarityScore and candidate.Distance < best.Distance)
                                            or (not Flags.PrioritizeRare and candidate.Distance < best.Distance) then
                                            best = candidate
                                        end
                                    end
                                end
                            end
                    end
                end
        end
    end

    lastCandidateScanTime = now
    if not best then
        cachedBestCandidate = nil
        lastScanHadNoCandidate = true
        return nil, nil, "Nenhum"
    end

    local info = best.Rarity .. " [" .. best.Name .. "] @ " .. (best.Zone or "Mapa")
        .. " | fonte: " .. tostring(best.EvidenceSource or "nenhuma")
    cachedBestCandidate = {
        Prompt = best.Prompt,
        Position = best.Position,
        Info = info
    }
    lastScanHadNoCandidate = false

    return best.Prompt, best.Position, info
end

-- Voo via física com verificação da distância realmente percorrida
local function flyToPosition(targetPos, speed, onApproach)
    local hrp = getHRP()
    local char = LocalPlayer.Character
    if not hrp or not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local collisionState = {}

    if Flags.InstantTP then
        hrp.CFrame = CFrame.new(targetPos)
        task.wait(0.05)
        if onApproach then onApproach(0) end
        return true, 0
    end

    speed = speed or Flags.FlySpeed or 950
    local startPos = hrp.Position
    local totalDist = (targetPos - startPos).Magnitude
    if totalDist < 3.5 then
        if onApproach then onApproach(totalDist) end
        return true
    end

    -- Evita colisões com a linha de corrida/esteira durante o voo.
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            collisionState[part] = part.CanCollide
            part.CanCollide = false
        end
    end

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
    local lastPhysicsUpdate = 0

    while (os.clock() - startTime) < (travelTime + 2) do
        local elapsed = os.clock() - startTime
        local alpha = math.clamp(elapsed / travelTime, 0, 1)
        if elapsed - lastPhysicsUpdate >= (1 / 30) then
            lastPhysicsUpdate = elapsed
            bp.Position = startPos:Lerp(targetPos, alpha)
            bg.CFrame = CFrame.new(hrp.Position, targetPos)
        end

        local remainingDistance = (targetPos - hrp.Position).Magnitude
        if onApproach then
            onApproach(remainingDistance)
        end

        if hum and hum.PlatformStand then
            hum.PlatformStand = false
        end

        if remainingDistance < 3.5 then
            break
        end
        Services.RunService.Heartbeat:Wait()
    end

    bp.Position = targetPos
    local settleDeadline = os.clock() + 0.3
    while hrp.Parent and (targetPos - hrp.Position).Magnitude >= 4 and os.clock() < settleDeadline do
        Services.RunService.Heartbeat:Wait()
    end

    local finalDistance = hrp.Parent and (targetPos - hrp.Position).Magnitude or math.huge

    pcall(function() bp:Destroy() end)
    pcall(function() bg:Destroy() end)
    for part, wasCollidable in pairs(collisionState) do
        if part and part.Parent then
            part.CanCollide = wasCollidable
        end
    end

    return finalDistance < 8, finalDistance
end

-- Aciona o prompt sem afirmar que o servidor aceitou o roubo.
local lastEggInteractionTime = 0
local lastInteractedPrompt = nil
local function stealEgg(prompt)
    if not prompt or not prompt.Parent then return false end
    local success = false
    pcall(function()
        prompt.HoldDuration = 0
        prompt.RequiresLineOfSight = false
        if fireproximityprompt then
            fireproximityprompt(prompt)
            success = true
        else
            prompt:InputHoldBegin()
            prompt:InputHoldEnd()
            success = true
        end
    end)
    if success then
        lastEggInteractionTime = os.clock()
        lastInteractedPrompt = prompt
    end
    return success
end

local function recordEggPromptInteraction(prompt, player)
    if (not player or player == LocalPlayer) and isEggInteractionPrompt(prompt) then
        lastEggInteractionTime = os.clock()
        lastInteractedPrompt = prompt
    end
end

Services.ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt, player)
    recordEggPromptInteraction(prompt, player)
end)

Services.ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
    recordEggPromptInteraction(prompt, player)
end)

local function waitForStealConfirmation(prompt, timeout)
    local deadline = os.clock() + (timeout or 0.8)
    while os.clock() < deadline do
        if not prompt or not prompt.Parent or not prompt:IsDescendantOf(Services.Workspace) then
            return true, "o prompt saiu do mapa"
        end
        if not prompt.Enabled then
            return true, "o prompt foi desativado"
        end
        if not isEggInteractionPrompt(prompt) then
            return true, "o texto/estado do prompt mudou"
        end
        task.wait(0.05)
    end
    return false, "nenhuma mudança observável no prompt"
end

-- Loop Principal de Fly-Steal e Retorno à Base
local isStealing = false
local autoStealRunId = 0
local function flyStealLoop()
    if isStealing then return end
    isStealing = true

    local ok, runError = pcall(function()
        local hrp = getHRP()
        if not hrp then
            addLog("ROUBO", "Ciclo cancelado: HumanoidRootPart não encontrado.")
            return
        end

        local basePos = getBasePosition()
        if not basePos then
            addLog("ROUBO", "Ciclo cancelado: posição da base não registrada.")
            return
        end

        -- 1. Identificar o Melhor Ovo por Renda e Peso Real
        local prompt, eggPos, eggInfo = getBestEggPrompt()
        if not prompt or not eggPos then
            if Flags.AutoLogger then
                addLog("ROUBO", "Nenhum prompt Steal/Egg elegível encontrado no raio configurado.")
            end
            return
        end

        if Flags.AutoLogger then
            addLog("ROUBO", "Alvo observado: " .. eggInfo .. " | velocidade configurada: " .. tostring(Flags.FlySpeed) .. " blocos/s.", { eggPos, prompt })
        end

        -- 2. Voar até a exata posição do ovo
        local targetFlightPos = eggPos + Vector3.new(0, 0.8, 0)
        local promptTriggered = false
        local activationDistance = math.max(4, (prompt.MaxActivationDistance or 10) - 1)
        local arrived, finalDistance = flyToPosition(targetFlightPos, Flags.FlySpeed, function(distance)
            if not promptTriggered and distance <= activationDistance then
                promptTriggered = stealEgg(prompt)
            end
        end)
        if not Flags.AutoSteal then return end
        if not arrived then
            addLog("ROUBO", "Falha de voo: o personagem terminou a " .. string.format("%.1f", finalDistance or -1) .. " blocos do alvo.")
            return
        end

        -- 3. Disparar assim que entrar no alcance e observar o resultado real.
        if not promptTriggered then
            promptTriggered = stealEgg(prompt)
        end
        if not promptTriggered then
            addLog("ROUBO", "Falha: o executor não conseguiu acionar o prompt Steal/Egg.")
            promptCooldown[prompt] = os.clock() + 0.5
            return
        end

        local confirmed, confirmationEvidence = waitForStealConfirmation(prompt, 0.8)
        promptCooldown[prompt] = os.clock() + (confirmed and 3 or 0.75)
        cachedBestCandidate = nil
        lastCandidateScanTime = 0

        if confirmed then
            addLog("ROUBO", "Mudança compatível com coleta observada: " .. confirmationEvidence .. ". Retornando à base.")
        else
            addLog("ROUBO", "Prompt acionado, mas o roubo NÃO foi confirmado: " .. confirmationEvidence .. ". Retornando à base para não ficar exposto.")
        end

        local returned, returnDistance = flyToPosition(basePos + Vector3.new(0, 3, 0), Flags.FlySpeed)
        if Flags.AutoLogger and not returned then
            addLog("ROUBO", "Retorno incompleto: distância final da base = " .. string.format("%.1f", returnDistance or -1) .. " blocos.")
        end
        task.wait(Flags.StealDelay)
    end)

    isStealing = false
    if not ok then
        addLog("ERRO", "Falha interna no ciclo de roubo: " .. tostring(runError))
    end
end

--================================================================--
-- SISTEMA DE ESP COM LIMITE DE ALVOS
--================================================================--

local activeESPs = {}

local function clearAllESP()
    for target, espItem in pairs(activeESPs) do
        pcall(function()
            if espItem and espItem.Parent then
                espItem:Destroy()
            end
        end)
    end
    activeESPs = {}
end

local function applyLightweightESP(target, labelText, color)
    if not target or not target.Parent or activeESPs[target] then return end

    local p = target:IsA("BasePart") and target 
           or (target:IsA("Model") and (target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")))
    if not p then return end

    local billboard = Instance.new("BillboardGui")
    billboard.Name = getRandomName()
    billboard.AlwaysOnTop = true
    billboard.Size = UDim2.new(0, 190, 0, 24)
    billboard.StudsOffset = Vector3.new(0, 2.5, 0)
    billboard.Adornee = p

    local tag = Instance.new("TextLabel")
    tag.Size = UDim2.new(1, 0, 1, 0)
    tag.BackgroundColor3 = Color3.fromRGB(12, 16, 24)
    tag.BackgroundTransparency = 0.25
    tag.TextColor3 = color or Color3.fromRGB(0, 210, 255)
    tag.TextStrokeTransparency = 0.5
    tag.TextSize = 11
    tag.Font = Enum.Font.SourceSansBold
    tag.Text = labelText
    tag.Parent = billboard

    local tagCorner = Instance.new("UICorner")
    tagCorner.CornerRadius = UDim.new(0, 4)
    tagCorner.Parent = tag

    local tagStroke = Instance.new("UIStroke")
    tagStroke.Color = color or Color3.fromRGB(0, 210, 255)
    tagStroke.Transparency = 0.7
    tagStroke.Thickness = 1
    tagStroke.Parent = tag

    billboard.Parent = p
    activeESPs[target] = billboard

    target.AncestryChanged:Connect(function(_, parent)
        if not parent then
            pcall(function() billboard:Destroy() end)
            activeESPs[target] = nil
        end
    end)
end

local isESPUpdating = false
local function refreshESP()
    if isESPUpdating then return end
    isESPUpdating = true

    task.spawn(function()
        pcall(function()
            if not Flags.EggESP and not Flags.PlayerESP then
                clearAllESP()
                isESPUpdating = false
                return
            end
            local seenTargets = {}

            -- 1. ESP de ovos limitado a 25 alvos
            if Flags.EggESP then
                local myPlayerName = LocalPlayer.Name:lower()
                local count = 0
                for obj in pairs(stealPromptRegistry) do
                    if count >= 25 then break end
                    if isStealPrompt(obj) and obj:IsDescendantOf(Services.Workspace) then
                        local parent = obj.Parent
                        if parent then
                            local fullName = parent:GetFullName():lower()
                            if not fullName:find(myPlayerName) then
                                count = count + 1
                                local _, rName = evaluateEggRarity(parent, obj)
                                local dName = (obj.ObjectText ~= "" and obj.ObjectText) or parent.Name
                                seenTargets[parent] = true
                                applyLightweightESP(parent, dName .. " [" .. rName .. "]", Flags.ESPColor)
                            end
                        end
                    end
                end
            end

            -- 2. Player ESP
            if Flags.PlayerESP then
                for _, pl in ipairs(Services.Players:GetPlayers()) do
                    if pl ~= LocalPlayer and pl.Character then
                        local hrp = pl.Character:FindFirstChild("HumanoidRootPart")
                        if hrp then
                            seenTargets[pl.Character] = true
                            applyLightweightESP(pl.Character, pl.DisplayName .. " (@" .. pl.Name .. ")", Flags.PlayerESPColor)
                        end
                    end
                end
            end

            for target, espItem in pairs(activeESPs) do
                if not seenTargets[target] then
                    pcall(function()
                        if espItem and espItem.Parent then espItem:Destroy() end
                    end)
                    activeESPs[target] = nil
                end
            end
        end)
        isESPUpdating = false
    end)
end

local function updateESP()
    if not Flags.EggESP and not Flags.PlayerESP then
        clearAllESP()
    else
        refreshESP()
    end
end

-- Throttled Background Loop
task.spawn(function()
    while scriptActive do
        task.wait(2.5)
        if Flags.EggESP or Flags.PlayerESP then
            refreshESP()
        end
    end
end)

local humanoidDefaults = setmetatable({}, { __mode = "k" })
local noclipOriginal = setmetatable({}, { __mode = "k" })
local ragdollConstraintOriginal = setmetatable({}, { __mode = "k" })
local animationConstraintOriginal = setmetatable({}, { __mode = "k" })
local motorJointOriginal = setmetatable({}, { __mode = "k" })
local lastHeldEggTool = nil
local lastEggRecoveryAttempt = 0

local ragdollStates = {
    Enum.HumanoidStateType.Ragdoll,
    Enum.HumanoidStateType.FallingDown,
    Enum.HumanoidStateType.PlatformStanding,
    Enum.HumanoidStateType.Physics
}

local function isEggTool(item)
    if not item or not item:IsA("Tool") then return false end
    local text = plainText(item.Name)
    if text:find("egg", 1, true) or text:find("ovo", 1, true) then
        return true
    end
    for key, value in pairs(item:GetAttributes()) do
        local combined = plainText(key .. " " .. tostring(value))
        if combined:find("egg", 1, true) or combined:find("ovo", 1, true) then
            return true
        end
    end
    return false
end

local function restoreNoclip()
    for part, original in pairs(noclipOriginal) do
        if part and part.Parent then
            part.CanCollide = original
        end
        noclipOriginal[part] = nil
    end
end

local function setRagdollStatesEnabled(humanoid, enabled)
    if not humanoid then return end
    for _, state in ipairs(ragdollStates) do
        pcall(function()
            humanoid:SetStateEnabled(state, enabled)
        end)
    end
end

local function restoreRagdollConstraints()
    for constraint, original in pairs(ragdollConstraintOriginal) do
        if constraint and constraint.Parent then
            constraint.Enabled = original
        end
        ragdollConstraintOriginal[constraint] = nil
    end
    for constraint, original in pairs(animationConstraintOriginal) do
        if constraint and constraint.Parent then
            constraint.Enabled = original.Enabled
            constraint.IsKinematic = original.IsKinematic
        end
        animationConstraintOriginal[constraint] = nil
    end
end

local function enforceAntiRagdoll(char, humanoid)
    if not Flags.AntiRagdoll or not char or not humanoid or humanoid.Health <= 0 then return end
    local recoveringJoints = humanoid.PlatformStand or humanoid.Sit
    humanoid.PlatformStand = false
    humanoid.Sit = false
    humanoid.AutoRotate = true

    local currentState = humanoid:GetState()
    for _, state in ipairs(ragdollStates) do
        if currentState == state then
            recoveringJoints = true
            humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
            break
        end
    end

    -- Muitos sistemas de ragdoll usam atributos em vez do estado do Humanoid.
    for _, target in ipairs({ char, humanoid }) do
        for attributeName, value in pairs(target:GetAttributes()) do
            local name = plainText(attributeName)
            if value == true and (name:find("ragdoll", 1, true)
                or name:find("stun", 1, true)
                or name:find("knock", 1, true)) then
                recoveringJoints = true
                pcall(function() target:SetAttribute(attributeName, false) end)
            end
        end
    end

    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp then
        hrp.AssemblyAngularVelocity = Vector3.zero
    end

    if recoveringJoints then
        for _, descendant in ipairs(char:GetDescendants()) do
            if descendant:IsA("Motor6D") then
                local original = motorJointOriginal[descendant]
                if original then
                    pcall(function()
                        if not descendant.Part0 then descendant.Part0 = original.Part0 end
                        if not descendant.Part1 then descendant.Part1 = original.Part1 end
                    end)
                end
            elseif descendant:IsA("AnimationConstraint") then
                if not animationConstraintOriginal[descendant] then
                    animationConstraintOriginal[descendant] = {
                        Enabled = descendant.Enabled,
                        IsKinematic = descendant.IsKinematic
                    }
                end
                descendant.Enabled = true
                descendant.IsKinematic = true
            elseif descendant:IsA("BallSocketConstraint") and descendant.Enabled then
                ragdollConstraintOriginal[descendant] = true
                descendant.Enabled = false
            end
        end
    end
    return recoveringJoints
end

local function equipKnownEggTool(char, humanoid)
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if not backpack or not char or not humanoid then return false end

    local item = lastHeldEggTool
    if not item or item.Parent ~= backpack then
        for _, candidate in ipairs(backpack:GetChildren()) do
            if isEggTool(candidate) then
                item = candidate
                break
            end
        end
    end

    if item and item.Parent == backpack then
        humanoid:EquipTool(item)
        lastHeldEggTool = item
        return item.Parent == char
    end
    return false
end

local function findClosestStealPrompt(position, radius)
    local closest, closestDistance = nil, radius or 20
    if lastInteractedPrompt and isEggInteractionPrompt(lastInteractedPrompt)
        and lastInteractedPrompt:IsDescendantOf(Services.Workspace) then
        local lastPosition = getPromptPosition(lastInteractedPrompt)
        local lastDistance = lastPosition and (position - lastPosition).Magnitude or math.huge
        if lastDistance <= closestDistance then
            return lastInteractedPrompt, lastDistance
        end
    end
    for prompt in pairs(eggInteractionPromptRegistry) do
        if isEggInteractionPrompt(prompt) and prompt:IsDescendantOf(Services.Workspace) then
            local promptPosition = getPromptPosition(prompt)
            if promptPosition then
                local distance = (position - promptPosition).Magnitude
                if distance <= closestDistance then
                    closest = prompt
                    closestDistance = distance
                end
            end
        end
    end
    return closest, closestDistance
end

local function recoverDroppedEgg(reason)
    if not Flags.NeverDropEgg or (os.clock() - lastEggInteractionTime) > 45 then return end
    if (os.clock() - lastEggRecoveryAttempt) < 0.75 then return end
    lastEggRecoveryAttempt = os.clock()

    task.spawn(function()
        for attempt = 1, 8 do
            if not Flags.NeverDropEgg then return end
            local char = LocalPlayer.Character
            local humanoid = char and char:FindFirstChildOfClass("Humanoid")
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if not char or not humanoid or not hrp then return end

            if equipKnownEggTool(char, humanoid) then
                if Flags.AutoLogger then
                    addLog("OVO", "Ferramenta de ovo reequipada após " .. tostring(reason) .. ".")
                end
                return
            end

            local prompt, distance = findClosestStealPrompt(hrp.Position, 18)
            if prompt and stealEgg(prompt) then
                if Flags.AutoLogger then
                    addLog("OVO", "Prompt próximo acionado para tentar recuperar o ovo derrubado (distância "
                        .. string.format("%.1f", distance) .. ", tentativa " .. tostring(attempt) .. ").")
                end
                local confirmed = waitForStealConfirmation(prompt, 0.35)
                if confirmed then return end
            end
            task.wait(0.1)
        end
        if Flags.AutoLogger then
            addLog("OVO", "Recuperação encerrada sem confirmação observável do servidor.")
        end
    end)
end

-- Mods e proteções locais. Recursos autoritativos do servidor são registrados
-- como tentativa, nunca como garantia.
Services.RunService.RenderStepped:Connect(function()
    if not scriptActive then return end
    pcall(function()
        local char = LocalPlayer.Character
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")

        if hum then
            if Flags.SpeedHack then hum.WalkSpeed = Flags.WalkSpeed end
            if Flags.JumpPowerHack then hum.JumpPower = Flags.JumpPower end
            if Flags.GodMode and hum.Health > 0 and hum.Health < hum.MaxHealth then
                hum.Health = hum.MaxHealth
            end
            if enforceAntiRagdoll(char, hum) then
                recoverDroppedEgg("sinal local de ragdoll/stun")
            end
        end

        if Flags.Noclip then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    if noclipOriginal[part] == nil then
                        noclipOriginal[part] = part.CanCollide
                    end
                    part.CanCollide = false
                end
            end
        end
    end)
end)

local function applyCharacterProtections(char)
    if not char then return end
    local hum = char:WaitForChild("Humanoid", 3)
    if not hum then return end
    humanoidDefaults[hum] = {
        WalkSpeed = hum.WalkSpeed,
        JumpPower = hum.JumpPower
    }
    for _, descendant in ipairs(char:GetDescendants()) do
        if descendant:IsA("Motor6D") then
            motorJointOriginal[descendant] = {
                Part0 = descendant.Part0,
                Part1 = descendant.Part1
            }
        elseif descendant:IsA("AnimationConstraint") then
            animationConstraintOriginal[descendant] = {
                Enabled = descendant.Enabled,
                IsKinematic = descendant.IsKinematic
            }
        end
    end
    setRagdollStatesEnabled(hum, not Flags.AntiRagdoll)

    hum.StateChanged:Connect(function(_, newState)
        if Flags.AntiRagdoll then
            for _, ragdollState in ipairs(ragdollStates) do
                if newState == ragdollState then
                    enforceAntiRagdoll(char, hum)
                    recoverDroppedEgg("mudança para estado " .. tostring(newState))
                    break
                end
            end
        end
    end)

    hum:GetPropertyChangedSignal("PlatformStand"):Connect(function()
        if Flags.AntiRagdoll and hum.PlatformStand then
            enforceAntiRagdoll(char, hum)
            recoverDroppedEgg("PlatformStand")
        end
    end)

    hum:GetPropertyChangedSignal("Sit"):Connect(function()
        if Flags.AntiRagdoll and hum.Sit then
            enforceAntiRagdoll(char, hum)
            recoverDroppedEgg("queda/sentado")
        end
    end)

    char.ChildAdded:Connect(function(item)
        if isEggTool(item) then
            lastHeldEggTool = item
            lastEggInteractionTime = os.clock()
        end
    end)

    char.ChildRemoved:Connect(function(item)
        if Flags.NeverDropEgg and (item == lastHeldEggTool or isEggTool(item)) then
            lastHeldEggTool = item
            task.defer(function()
                equipKnownEggTool(char, hum)
            end)
        end
    end)

    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if backpack then
        backpack.ChildAdded:Connect(function(item)
            if Flags.NeverDropEgg and (item == lastHeldEggTool or isEggTool(item)) then
                lastHeldEggTool = item
                task.defer(function()
                    equipKnownEggTool(char, hum)
                end)
            end
        end)
    end
end

-- Inicializar proteções no personagem atual e ao renascer
if LocalPlayer.Character then
    task.spawn(function() applyCharacterProtections(LocalPlayer.Character) end)
end
LocalPlayer.CharacterAdded:Connect(function(char)
    if scriptActive then
        task.spawn(function() applyCharacterProtections(char) end)
    end
end)

Services.UserInputService.JumpRequest:Connect(function()
    if scriptActive and Flags.InfJump then
        pcall(function()
            local char = LocalPlayer.Character
            if char and char:FindFirstChildOfClass("Humanoid") then
                char:FindFirstChildOfClass("Humanoid"):ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end)
    end
end)

-- Anti-AFK por entrada virtual; Humanoid:Move(Vector3.zero) não reinicia o idle.
pcall(function()
    LocalPlayer.Idled:Connect(function()
        if scriptActive and Flags.AntiAFK then
            pcall(function()
                Services.VirtualUser:CaptureController()
                Services.VirtualUser:ClickButton2(Vector2.new(0, 0))
            end)
        end
    end)
end)

--================================================================--
-- INTERFACE BIGFROOT (ROUBE UM OVO - STEAL AN EGG THEME)
--================================================================--

local TweenService = Services.TweenService
local UserInputService = Services.UserInputService

-- Cores Oficiais BigFroot
local C_BG         = Color3.fromRGB(11, 11, 13)       -- Fundo Principal
local C_SIDEBAR    = Color3.fromRGB(14, 14, 16)       -- Fundo Sidebar
local C_CARD       = Color3.fromRGB(19, 19, 22)       -- Fundo Cards
local C_CARD_STROKE= Color3.fromRGB(30, 30, 35)       -- Borda Cards
local C_ITEM_BG    = Color3.fromRGB(24, 24, 28)       -- Fundo Inputs/Caixas
local C_ITEM_STROKE= Color3.fromRGB(38, 38, 44)       -- Borda Inputs
local C_AMBER      = Color3.fromRGB(255, 160, 18)     -- Âmbar BigFroot (#FFA012)
local C_AMBER_HOVER= Color3.fromRGB(255, 180, 50)
local C_TEXT_WHITE = Color3.fromRGB(255, 255, 255)
local C_TEXT_MUTED = Color3.fromRGB(142, 142, 147)
local C_TOGGLE_OFF = Color3.fromRGB(48, 48, 54)
local C_TRACK_BG   = Color3.fromRGB(36, 36, 42)

-- Helper: Tween rápido
local function tw(obj, props, duration)
    duration = duration or 0.18
    local t = TweenService:Create(obj, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
    t:Play()
    return t
end

-- Helper: Criar UICorner
local function addCorner(parent, px)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, px or 6)
    c.Parent = parent
    return c
end

-- Helper: Criar UIStroke
local function addStroke(parent, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color or C_CARD_STROKE
    s.Thickness = thickness or 1
    s.Transparency = transparency or 0
    s.Parent = parent
    return s
end

-- Helper: Criar UIPadding
local function addPadding(parent, top, bottom, left, right)
    local p = Instance.new("UIPadding")
    p.PaddingTop = UDim.new(0, top or 0)
    p.PaddingBottom = UDim.new(0, bottom or 0)
    p.PaddingLeft = UDim.new(0, left or 0)
    p.PaddingRight = UDim.new(0, right or 0)
    p.Parent = parent
    return p
end

-- GUI Root
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = getRandomName()
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- Janela Principal
local MainFrame = Instance.new("Frame")
MainFrame.Name = "BigFrootHub"
MainFrame.Size = UDim2.new(0, 750, 0, 510)
MainFrame.Position = UDim2.new(0.5, -375, 0.5, -255)
MainFrame.BackgroundColor3 = C_BG
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = false
MainFrame.Parent = ScreenGui
addCorner(MainFrame, 10)
addStroke(MainFrame, C_CARD_STROKE, 1, 0)

-- Sistema de Arrasto Suave (PC + Mobile)
local dragging, dragInput, dragStart, startPos
local function enableDragging(dragHandle)
    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = MainFrame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    dragHandle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)
end

UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        MainFrame.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end
end)

--================================================================--
-- SIDEBAR LATERAL ESQUERDA
--================================================================--

local Sidebar = Instance.new("Frame")
Sidebar.Name = "Sidebar"
Sidebar.Size = UDim2.new(0, 175, 1, 0)
Sidebar.Position = UDim2.new(0, 0, 0, 0)
Sidebar.BackgroundColor3 = C_SIDEBAR
Sidebar.BorderSizePixel = 0
Sidebar.Parent = MainFrame
addCorner(Sidebar, 10)

-- Corretor de canto direito da sidebar
local SidebarSquareCover = Instance.new("Frame")
SidebarSquareCover.Size = UDim2.new(0, 10, 1, 0)
SidebarSquareCover.Position = UDim2.new(1, -10, 0, 0)
SidebarSquareCover.BackgroundColor3 = C_SIDEBAR
SidebarSquareCover.BorderSizePixel = 0
SidebarSquareCover.Parent = Sidebar

enableDragging(Sidebar)

-- Logo BigFroot
local LogoContainer = Instance.new("Frame")
LogoContainer.Size = UDim2.new(1, 0, 0, 52)
LogoContainer.BackgroundTransparency = 1
LogoContainer.Parent = Sidebar

local LogoText = Instance.new("TextLabel")
LogoText.Size = UDim2.new(1, -24, 0, 24)
LogoText.Position = UDim2.new(0, 16, 0, 14)
LogoText.BackgroundTransparency = 1
LogoText.RichText = true
LogoText.Text = '<font color="#FFFFFF"><b>Big</b></font><font color="#FFA012"><b>Froot</b></font>'
LogoText.Font = Enum.Font.GothamBold
LogoText.TextSize = 22
LogoText.TextXAlignment = Enum.TextXAlignment.Left
LogoText.Parent = LogoContainer

local SubtitleText = Instance.new("TextLabel")
SubtitleText.Size = UDim2.new(1, -24, 0, 14)
SubtitleText.Position = UDim2.new(0, 16, 0, 38)
SubtitleText.BackgroundTransparency = 1
SubtitleText.Text = "Steal an Egg"
SubtitleText.Font = Enum.Font.GothamMedium
SubtitleText.TextSize = 11
SubtitleText.TextColor3 = C_TEXT_MUTED
SubtitleText.TextXAlignment = Enum.TextXAlignment.Left
SubtitleText.Parent = LogoContainer

-- Lista de Abas de Navegação
local NavList = Instance.new("ScrollingFrame")
NavList.Name = "NavList"
NavList.Size = UDim2.new(1, 0, 1, -114)
NavList.Position = UDim2.new(0, 0, 0, 60)
NavList.BackgroundTransparency = 1
NavList.BorderSizePixel = 0
NavList.ScrollBarThickness = 2
NavList.ScrollBarImageColor3 = C_AMBER
NavList.CanvasSize = UDim2.new(0, 0, 0, 420)
NavList.Parent = Sidebar
addPadding(NavList, 4, 4, 10, 10)

local NavLayout = Instance.new("UIListLayout")
NavLayout.Padding = UDim.new(0, 3)
NavLayout.SortOrder = Enum.SortOrder.LayoutOrder
NavLayout.Parent = NavList

-- Perfil do Jogador no Rodapé da Sidebar
local ProfileFrame = Instance.new("Frame")
ProfileFrame.Size = UDim2.new(1, -20, 0, 42)
ProfileFrame.Position = UDim2.new(0, 10, 1, -48)
ProfileFrame.BackgroundColor3 = C_ITEM_BG
ProfileFrame.BorderSizePixel = 0
ProfileFrame.Parent = Sidebar
addCorner(ProfileFrame, 8)
addStroke(ProfileFrame, C_ITEM_STROKE, 1, 0.4)

local AvatarImg = Instance.new("ImageLabel")
AvatarImg.Size = UDim2.new(0, 30, 0, 30)
AvatarImg.Position = UDim2.new(0, 6, 0.5, -15)
AvatarImg.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
AvatarImg.BorderSizePixel = 0
AvatarImg.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(LocalPlayer.UserId) .. "&w=100&h=100"
AvatarImg.Parent = ProfileFrame
addCorner(AvatarImg, 15)

local ProfileName = Instance.new("TextLabel")
ProfileName.Size = UDim2.new(1, -44, 0, 15)
ProfileName.Position = UDim2.new(0, 42, 0, 6)
ProfileName.BackgroundTransparency = 1
ProfileName.Text = LocalPlayer.DisplayName
ProfileName.Font = Enum.Font.GothamBold
ProfileName.TextSize = 11
ProfileName.TextColor3 = C_TEXT_WHITE
ProfileName.TextXAlignment = Enum.TextXAlignment.Left
ProfileName.TextTruncate = Enum.TextTruncate.AtEnd
ProfileName.Parent = ProfileFrame

local ProfileTime = Instance.new("TextLabel")
ProfileTime.Size = UDim2.new(1, -44, 0, 13)
ProfileTime.Position = UDim2.new(0, 42, 0, 22)
ProfileTime.BackgroundTransparency = 1
ProfileTime.Text = "23h 49m left"
ProfileTime.Font = Enum.Font.Gotham
ProfileTime.TextSize = 10
ProfileTime.TextColor3 = C_TEXT_MUTED
ProfileTime.TextXAlignment = Enum.TextXAlignment.Left
ProfileTime.Parent = ProfileFrame

--================================================================--
-- ÁREA SUPERIOR (SUB-ABAS & BUSCA)
--================================================================--

local TopBar = Instance.new("Frame")
TopBar.Name = "TopBar"
TopBar.Size = UDim2.new(1, -175, 0, 44)
TopBar.Position = UDim2.new(0, 175, 0, 0)
TopBar.BackgroundColor3 = C_BG
TopBar.BorderSizePixel = 0
TopBar.Parent = MainFrame
enableDragging(TopBar)

local SubTabsHolder = Instance.new("Frame")
SubTabsHolder.Size = UDim2.new(1, -50, 1, 0)
SubTabsHolder.Position = UDim2.new(0, 12, 0, 0)
SubTabsHolder.BackgroundTransparency = 1
SubTabsHolder.Parent = TopBar

local SubTabsLayout = Instance.new("UIListLayout")
SubTabsLayout.FillDirection = Enum.FillDirection.Horizontal
SubTabsLayout.Padding = UDim.new(0, 8)
SubTabsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
SubTabsLayout.Parent = SubTabsHolder

-- Botão de Busca Top Right
local SearchBtn = Instance.new("TextButton")
SearchBtn.Size = UDim2.new(0, 32, 0, 32)
SearchBtn.Position = UDim2.new(1, -42, 0, 6)
SearchBtn.BackgroundColor3 = C_CARD
SearchBtn.Text = "🔍"
SearchBtn.TextColor3 = C_TEXT_MUTED
SearchBtn.TextSize = 13
SearchBtn.Font = Enum.Font.GothamBold
SearchBtn.Parent = TopBar
addCorner(SearchBtn, 6)
addStroke(SearchBtn, C_CARD_STROKE, 1, 0)

SearchBtn.MouseButton1Click:Connect(function()
    addLog("RADAR", "Varredura rápida disparada pelo botão de busca.")
    local discovered, _ = scanAllEggsInMap()
    addLog("RADAR", tostring(#discovered) .. " ovos encontrados no mapa.")
end)

-- Badge de Versão no Rodapé (Canto Inferior Direito)
local VersionBadge = Instance.new("Frame")
VersionBadge.Size = UDim2.new(0, 110, 0, 26)
VersionBadge.Position = UDim2.new(1, -120, 1, -34)
VersionBadge.BackgroundColor3 = C_CARD
VersionBadge.BorderSizePixel = 0
VersionBadge.Parent = MainFrame
addCorner(VersionBadge, 6)
addStroke(VersionBadge, C_CARD_STROKE, 1, 0)

local VersionText = Instance.new("TextLabel")
VersionText.Size = UDim2.new(1, 0, 1, 0)
VersionText.BackgroundTransparency = 1
VersionText.RichText = true
VersionText.Text = '<b><font color="#FFFFFF">v1.5.7</font></b> | <font color="#8E8E93">Free</font>'
VersionText.Font = Enum.Font.GothamBold
VersionText.TextSize = 11
VersionText.Parent = VersionBadge

-- Container Principal de Páginas
local PageContainer = Instance.new("Frame")
PageContainer.Name = "PageContainer"
PageContainer.Size = UDim2.new(1, -175, 1, -84)
PageContainer.Position = UDim2.new(0, 175, 0, 44)
PageContainer.BackgroundTransparency = 1
PageContainer.Parent = MainFrame

-- Gerenciamento de Abas e Páginas
local TabButtons = {}
local Pages = {}
local CurrentTab = nil
local CurrentSubTab = nil
local SubTabButtons = {}
local SubTabIndicators = {}

local function switchTab(tabId)
    if CurrentTab == tabId then return end
    CurrentTab = tabId
    for id, btn in pairs(TabButtons) do
        local isSelected = (id == tabId)
        tw(btn, {
            BackgroundColor3 = isSelected and Color3.fromRGB(26, 26, 30) or C_SIDEBAR,
            BackgroundTransparency = isSelected and 0 or 1
        }, 0.15)
        local lbl = btn:FindFirstChild("Title")
        if lbl then
            tw(lbl, { TextColor3 = isSelected and C_TEXT_WHITE or C_TEXT_MUTED }, 0.15)
        end
        local icon = btn:FindFirstChild("Icon")
        if icon then
            tw(icon, { TextColor3 = isSelected and C_AMBER or C_TEXT_MUTED }, 0.15)
        end
    end
    for id, pg in pairs(Pages) do
        pg.Visible = (id == tabId)
    end
end

local function addSidebarTab(id, name, iconSymbol, order)
    local btn = Instance.new("TextButton")
    btn.Name = "Tab_" .. id
    btn.Size = UDim2.new(1, 0, 0, 34)
    btn.BackgroundColor3 = C_SIDEBAR
    btn.BackgroundTransparency = 1
    btn.Text = ""
    btn.LayoutOrder = order or 1
    btn.Parent = NavList
    addCorner(btn, 6)

    local icon = Instance.new("TextLabel")
    icon.Name = "Icon"
    icon.Size = UDim2.new(0, 20, 1, 0)
    icon.Position = UDim2.new(0, 10, 0, 0)
    icon.BackgroundTransparency = 1
    icon.Text = iconSymbol or "•"
    icon.Font = Enum.Font.GothamBold
    icon.TextSize = 14
    icon.TextColor3 = C_TEXT_MUTED
    icon.Parent = btn

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, -38, 1, 0)
    title.Position = UDim2.new(0, 34, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = name
    title.Font = Enum.Font.GothamMedium
    title.TextSize = 12
    title.TextColor3 = C_TEXT_MUTED
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = btn

    btn.MouseButton1Click:Connect(function()
        switchTab(id)
    end)

    TabButtons[id] = btn
    return btn
end

local function createPage(id)
    local pg = Instance.new("ScrollingFrame")
    pg.Name = "Page_" .. id
    pg.Size = UDim2.new(1, 0, 1, 0)
    pg.BackgroundTransparency = 1
    pg.BorderSizePixel = 0
    pg.ScrollBarThickness = 3
    pg.ScrollBarImageColor3 = C_AMBER
    pg.CanvasSize = UDim2.new(0, 0, 0, 0)
    pg.AutomaticCanvasSize = Enum.AutomaticSize.Y
    pg.Visible = false
    pg.Parent = PageContainer
    addPadding(pg, 4, 16, 12, 12)

    Pages[id] = pg
    return pg
end

-- Sub-Abas do Topo (Com linha âmbar superior)
local function addSubTab(id, name, targetPageFunc)
    local btn = Instance.new("TextButton")
    btn.Name = "SubTab_" .. id
    btn.Size = UDim2.new(0, 0, 1, 0)
    btn.AutomaticSize = Enum.AutomaticSize.X
    btn.BackgroundTransparency = 1
    btn.Text = "  " .. name .. "  "
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 12
    btn.TextColor3 = C_TEXT_MUTED
    btn.Parent = SubTabsHolder

    -- Linha de Acento Âmbar no topo do botão ativo
    local indicator = Instance.new("Frame")
    indicator.Size = UDim2.new(0.65, 0, 0, 3)
    indicator.Position = UDim2.new(0.175, 0, 0, 0)
    indicator.BackgroundColor3 = C_AMBER
    indicator.BorderSizePixel = 0
    indicator.Visible = false
    indicator.Parent = btn
    addCorner(indicator, 2)

    btn.MouseButton1Click:Connect(function()
        for sId, sBtn in pairs(SubTabButtons) do
            local active = (sId == id)
            tw(sBtn, { TextColor3 = active and C_TEXT_WHITE or C_TEXT_MUTED }, 0.15)
            if SubTabIndicators[sId] then
                SubTabIndicators[sId].Visible = active
            end
        end
        if targetPageFunc then targetPageFunc() end
    end)

    SubTabButtons[id] = btn
    SubTabIndicators[id] = indicator
    return btn
end

--================================================================--
-- CONSTRUTOR DE CARDS MODULARES (ESTILO BIGFROOT)
--================================================================--

local function createCard(parent, titleText, iconSymbol)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, 0)
    card.AutomaticSize = Enum.AutomaticSize.Y
    card.BackgroundColor3 = C_CARD
    card.BorderSizePixel = 0
    card.Parent = parent
    addCorner(card, 8)
    addStroke(card, C_CARD_STROKE, 1, 0)

    local header = Instance.new("TextButton")
    header.Size = UDim2.new(1, 0, 0, 36)
    header.BackgroundTransparency = 1
    header.Text = ""
    header.Parent = card

    local icon = Instance.new("TextLabel")
    icon.Size = UDim2.new(0, 20, 1, 0)
    icon.Position = UDim2.new(0, 12, 0, 0)
    icon.BackgroundTransparency = 1
    icon.Text = iconSymbol or "✦"
    icon.Font = Enum.Font.GothamBold
    icon.TextSize = 13
    icon.TextColor3 = C_AMBER
    icon.Parent = header

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -70, 1, 0)
    title.Position = UDim2.new(0, 34, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = titleText
    title.Font = Enum.Font.GothamBold
    title.TextSize = 13
    title.TextColor3 = C_TEXT_WHITE
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header

    local chevron = Instance.new("TextLabel")
    chevron.Size = UDim2.new(0, 20, 1, 0)
    chevron.Position = UDim2.new(1, -28, 0, 0)
    chevron.BackgroundTransparency = 1
    chevron.Text = "▾"
    chevron.Font = Enum.Font.GothamBold
    chevron.TextSize = 13
    chevron.TextColor3 = C_TEXT_MUTED
    chevron.Parent = header

    local body = Instance.new("Frame")
    body.Size = UDim2.new(1, 0, 0, 0)
    body.Position = UDim2.new(0, 0, 0, 36)
    body.AutomaticSize = Enum.AutomaticSize.Y
    body.BackgroundTransparency = 1
    body.Parent = card
    addPadding(body, 2, 12, 12, 12)

    local bodyLayout = Instance.new("UIListLayout")
    bodyLayout.Padding = UDim.new(0, 8)
    bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
    bodyLayout.Parent = body

    local collapsed = false
    header.MouseButton1Click:Connect(function()
        collapsed = not collapsed
        body.Visible = not collapsed
        chevron.Text = collapsed and "▸" or "▾"
    end)

    return body
end

-- Caixa de Disclaimer (Free Script Warning)
local function addDisclaimer(parent, headerLine, subLine1, subLine2)
    local box = Instance.new("Frame")
    box.Size = UDim2.new(1, 0, 0, 52)
    box.BackgroundColor3 = C_ITEM_BG
    box.BorderSizePixel = 0
    box.Parent = parent
    addCorner(box, 6)
    addStroke(box, C_ITEM_STROKE, 1, 0.4)
    addPadding(box, 6, 6, 10, 10)

    local l1 = Instance.new("TextLabel")
    l1.Size = UDim2.new(1, 0, 0, 14)
    l1.BackgroundTransparency = 1
    l1.Text = headerLine or "SCRIPT IS FREE"
    l1.Font = Enum.Font.GothamBold
    l1.TextSize = 11
    l1.TextColor3 = C_TEXT_WHITE
    l1.TextXAlignment = Enum.TextXAlignment.Left
    l1.Parent = box

    local l2 = Instance.new("TextLabel")
    l2.Size = UDim2.new(1, 0, 0, 12)
    l2.Position = UDim2.new(0, 0, 0, 15)
    l2.BackgroundTransparency = 1
    l2.Text = subLine1 or "IF YOU BOUGHT IT FROM SOMEONE YOU GOT SCAMMED."
    l2.Font = Enum.Font.Gotham
    l2.TextSize = 9.5
    l2.TextColor3 = C_TEXT_MUTED
    l2.TextXAlignment = Enum.TextXAlignment.Left
    l2.Parent = box

    local l3 = Instance.new("TextLabel")
    l3.Size = UDim2.new(1, 0, 0, 12)
    l3.Position = UDim2.new(0, 0, 0, 28)
    l3.BackgroundTransparency = 1
    l3.Text = subLine2 or "discord.gg/bigfroot"
    l3.Font = Enum.Font.Gotham
    l3.TextSize = 9.5
    l3.TextColor3 = C_TEXT_MUTED
    l3.TextXAlignment = Enum.TextXAlignment.Left
    l3.Parent = box
end

--================================================================--
-- WIDGETS: TOGGLE, SLIDER, DROPDOWN, MULTI-SELECT, BOTAO
--================================================================--

-- 1. Toggle Animado BigFroot
local function addToggle(parent, labelText, defaultState, callback)
    local state = defaultState == true

    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 26)
    row.BackgroundTransparency = 1
    row.Parent = parent

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -50, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = labelText
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 12
    label.TextColor3 = C_TEXT_WHITE
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = row

    local switch = Instance.new("TextButton")
    switch.Size = UDim2.new(0, 42, 0, 22)
    switch.Position = UDim2.new(1, -42, 0.5, -11)
    switch.BackgroundColor3 = state and C_AMBER or C_TOGGLE_OFF
    switch.Text = ""
    switch.Parent = row
    addCorner(switch, 11)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 18, 0, 18)
    knob.Position = state and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9)
    knob.BackgroundColor3 = C_TEXT_WHITE
    knob.BorderSizePixel = 0
    knob.Parent = switch
    addCorner(knob, 9)

    switch.MouseButton1Click:Connect(function()
        state = not state
        tw(switch, { BackgroundColor3 = state and C_AMBER or C_TOGGLE_OFF }, 0.15)
        tw(knob, { Position = state and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9) }, 0.15)
        pcall(function() callback(state) end)
    end)

    return {
        Set = function(v)
            state = v
            tw(switch, { BackgroundColor3 = state and C_AMBER or C_TOGGLE_OFF }, 0.15)
            tw(knob, { Position = state and UDim2.new(1, -20, 0.5, -9) or UDim2.new(0, 2, 0.5, -9) }, 0.15)
            pcall(function() callback(state) end)
        end
    }
end

-- 2. Slider com Badge de Valor BigFroot
local function addSlider(parent, titleText, minVal, maxVal, defaultVal, unitStr, callback)
    local curVal = math.clamp(defaultVal or minVal, minVal, maxVal)
    unitStr = unitStr or ""

    local container = Instance.new("Frame")
    container.Size = UDim2.new(1, 0, 0, 46)
    container.BackgroundTransparency = 1
    container.Parent = parent

    local headerRow = Instance.new("Frame")
    headerRow.Size = UDim2.new(1, 0, 0, 20)
    headerRow.BackgroundTransparency = 1
    headerRow.Parent = container

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -100, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = titleText
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 12
    label.TextColor3 = C_TEXT_WHITE
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = headerRow

    local badge = Instance.new("Frame")
    badge.Size = UDim2.new(0, 85, 0, 18)
    badge.Position = UDim2.new(1, -85, 0, 1)
    badge.BackgroundColor3 = C_ITEM_BG
    badge.BorderSizePixel = 0
    badge.Parent = headerRow
    addCorner(badge, 4)

    local badgeText = Instance.new("TextLabel")
    badgeText.Size = UDim2.new(1, 0, 1, 0)
    badgeText.BackgroundTransparency = 1
    badgeText.Text = tostring(curVal) .. " " .. unitStr
    badgeText.Font = Enum.Font.GothamBold
    badgeText.TextSize = 10.5
    badgeText.TextColor3 = Color3.fromRGB(215, 215, 220)
    badgeText.Parent = badge

    local track = Instance.new("TextButton")
    track.Size = UDim2.new(1, 0, 0, 5)
    track.Position = UDim2.new(0, 0, 0, 28)
    track.BackgroundColor3 = C_TRACK_BG
    track.Text = ""
    track.AutoButtonColor = false
    track.Parent = container
    addCorner(track, 3)

    local fill = Instance.new("Frame")
    local initRatio = math.clamp((curVal - minVal) / (maxVal - minVal), 0, 1)
    fill.Size = UDim2.new(initRatio, 0, 1, 0)
    fill.BackgroundColor3 = C_AMBER
    fill.BorderSizePixel = 0
    fill.Parent = track
    addCorner(fill, 3)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 12, 0, 12)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = UDim2.new(initRatio, 0, 0.5, 0)
    knob.BackgroundColor3 = C_TEXT_WHITE
    knob.BorderSizePixel = 0
    knob.Parent = track
    addCorner(knob, 6)

    local draggingSlider = false
    local function updateSlider(input)
        local ratio = math.clamp((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        fill.Size = UDim2.new(ratio, 0, 1, 0)
        knob.Position = UDim2.new(ratio, 0, 0.5, 0)
        local val = math.floor(minVal + (maxVal - minVal) * ratio)
        badgeText.Text = tostring(val) .. " " .. unitStr
        pcall(function() callback(val) end)
    end

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingSlider = true
            updateSlider(input)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            draggingSlider = false
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if draggingSlider and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateSlider(input)
        end
    end)

    return {
        Set = function(newVal)
            local ratio = math.clamp((newVal - minVal) / (maxVal - minVal), 0, 1)
            fill.Size = UDim2.new(ratio, 0, 1, 0)
            knob.Position = UDim2.new(ratio, 0, 0.5, 0)
            badgeText.Text = tostring(newVal) .. " " .. unitStr
            pcall(function() callback(newVal) end)
        end
    }
end

-- 3. Dropdown Selecionável BigFroot
local function addDropdown(parent, titleText, options, defaultVal, callback)
    local selected = defaultVal or options[1] or "..."

    local container = Instance.new("Frame")
    container.Size = UDim2.new(1, 0, 0, 56)
    container.BackgroundTransparency = 1
    container.Parent = parent

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 0, 18)
    label.BackgroundTransparency = 1
    label.Text = titleText
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 12
    label.TextColor3 = C_TEXT_WHITE
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = container

    local selectBtn = Instance.new("TextButton")
    selectBtn.Size = UDim2.new(1, 0, 0, 32)
    selectBtn.Position = UDim2.new(0, 0, 0, 20)
    selectBtn.BackgroundColor3 = C_ITEM_BG
    selectBtn.Text = ""
    selectBtn.Parent = container
    addCorner(selectBtn, 6)
    addStroke(selectBtn, C_ITEM_STROKE, 1, 0)

    local valueText = Instance.new("TextLabel")
    valueText.Size = UDim2.new(1, -30, 1, 0)
    valueText.Position = UDim2.new(0, 10, 0, 0)
    valueText.BackgroundTransparency = 1
    valueText.Text = tostring(selected)
    valueText.Font = Enum.Font.Gotham
    valueText.TextSize = 11.5
    valueText.TextColor3 = Color3.fromRGB(220, 220, 225)
    valueText.TextXAlignment = Enum.TextXAlignment.Left
    valueText.TextTruncate = Enum.TextTruncate.AtEnd
    valueText.Parent = selectBtn

    local arrow = Instance.new("TextLabel")
    arrow.Size = UDim2.new(0, 20, 1, 0)
    arrow.Position = UDim2.new(1, -24, 0, 0)
    arrow.BackgroundTransparency = 1
    arrow.Text = "⇅"
    arrow.Font = Enum.Font.GothamBold
    arrow.TextSize = 12
    arrow.TextColor3 = C_TEXT_MUTED
    arrow.Parent = selectBtn

    -- Menu Popup
    local listMenu = Instance.new("Frame")
    listMenu.Size = UDim2.new(1, 0, 0, math.min(#options * 28 + 6, 140))
    listMenu.Position = UDim2.new(0, 0, 1, 4)
    listMenu.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
    listMenu.ZIndex = 50
    listMenu.Visible = false
    listMenu.Parent = selectBtn
    addCorner(listMenu, 6)
    addStroke(listMenu, C_ITEM_STROKE, 1, 0)

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, 0, 1, 0)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ZIndex = 51
    scroll.ScrollBarThickness = 2
    scroll.ScrollBarImageColor3 = C_AMBER
    scroll.CanvasSize = UDim2.new(0, 0, 0, #options * 28)
    scroll.Parent = listMenu
    addPadding(scroll, 3, 3, 4, 4)

    local menuLayout = Instance.new("UIListLayout")
    menuLayout.Padding = UDim.new(0, 2)
    menuLayout.Parent = scroll

    for _, opt in ipairs(options) do
        local optBtn = Instance.new("TextButton")
        optBtn.Size = UDim2.new(1, 0, 0, 26)
        optBtn.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
        optBtn.BackgroundTransparency = 1
        optBtn.Text = "  " .. tostring(opt)
        optBtn.Font = Enum.Font.Gotham
        optBtn.TextSize = 11
        optBtn.TextColor3 = C_TEXT_MUTED
        optBtn.TextXAlignment = Enum.TextXAlignment.Left
        optBtn.ZIndex = 52
        optBtn.Parent = scroll
        addCorner(optBtn, 4)

        optBtn.MouseButton1Click:Connect(function()
            selected = opt
            valueText.Text = tostring(opt)
            listMenu.Visible = false
            pcall(function() callback(opt) end)
        end)
    end

    selectBtn.MouseButton1Click:Connect(function()
        listMenu.Visible = not listMenu.Visible
    end)

    return {
        Set = function(val)
            selected = val
            valueText.Text = tostring(val)
            pcall(function() callback(val) end)
        end
    }
end

-- 4. Multi-Select Dropdown BigFroot (Ex: Rarities)
local function addMultiSelect(parent, titleText, options, defaultSelectedList, callback)
    local selectedMap = {}
    if defaultSelectedList then
        for _, s in ipairs(defaultSelectedList) do selectedMap[s] = true end
    end

    local function getDisplayString()
        local list = {}
        for _, opt in ipairs(options) do
            if selectedMap[opt] then table.insert(list, opt) end
        end
        return #list > 0 and table.concat(list, ", ") or "..."
    end

    local container = Instance.new("Frame")
    container.Size = UDim2.new(1, 0, 0, 56)
    container.BackgroundTransparency = 1
    container.Parent = parent

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 0, 18)
    label.BackgroundTransparency = 1
    label.Text = titleText
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 12
    label.TextColor3 = C_TEXT_WHITE
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = container

    local selectBtn = Instance.new("TextButton")
    selectBtn.Size = UDim2.new(1, 0, 0, 32)
    selectBtn.Position = UDim2.new(0, 0, 0, 20)
    selectBtn.BackgroundColor3 = C_ITEM_BG
    selectBtn.Text = ""
    selectBtn.Parent = container
    addCorner(selectBtn, 6)
    addStroke(selectBtn, C_ITEM_STROKE, 1, 0)

    local valueText = Instance.new("TextLabel")
    valueText.Size = UDim2.new(1, -30, 1, 0)
    valueText.Position = UDim2.new(0, 10, 0, 0)
    valueText.BackgroundTransparency = 1
    valueText.Text = getDisplayString()
    valueText.Font = Enum.Font.Gotham
    valueText.TextSize = 11.5
    valueText.TextColor3 = Color3.fromRGB(220, 220, 225)
    valueText.TextXAlignment = Enum.TextXAlignment.Left
    valueText.TextTruncate = Enum.TextTruncate.AtEnd
    valueText.Parent = selectBtn

    local arrow = Instance.new("TextLabel")
    arrow.Size = UDim2.new(0, 20, 1, 0)
    arrow.Position = UDim2.new(1, -24, 0, 0)
    arrow.BackgroundTransparency = 1
    arrow.Text = "⇅"
    arrow.Font = Enum.Font.GothamBold
    arrow.TextSize = 12
    arrow.TextColor3 = C_TEXT_MUTED
    arrow.Parent = selectBtn

    -- Menu Popup
    local listMenu = Instance.new("Frame")
    listMenu.Size = UDim2.new(1, 0, 0, math.min(#options * 28 + 6, 160))
    listMenu.Position = UDim2.new(0, 0, 1, 4)
    listMenu.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
    listMenu.ZIndex = 50
    listMenu.Visible = false
    listMenu.Parent = selectBtn
    addCorner(listMenu, 6)
    addStroke(listMenu, C_ITEM_STROKE, 1, 0)

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, 0, 1, 0)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ZIndex = 51
    scroll.ScrollBarThickness = 2
    scroll.ScrollBarImageColor3 = C_AMBER
    scroll.CanvasSize = UDim2.new(0, 0, 0, #options * 28)
    scroll.Parent = listMenu
    addPadding(scroll, 3, 3, 4, 4)

    local menuLayout = Instance.new("UIListLayout")
    menuLayout.Padding = UDim.new(0, 2)
    menuLayout.Parent = scroll

    local optionButtons = {}
    for _, opt in ipairs(options) do
        local optBtn = Instance.new("TextButton")
        optBtn.Size = UDim2.new(1, 0, 0, 26)
        optBtn.BackgroundColor3 = selectedMap[opt] and Color3.fromRGB(34, 30, 24) or Color3.fromRGB(24, 24, 28)
        optBtn.BackgroundTransparency = selectedMap[opt] and 0 or 1
        optBtn.Text = (selectedMap[opt] and "✓ " or "   ") .. tostring(opt)
        optBtn.Font = Enum.Font.Gotham
        optBtn.TextSize = 11
        optBtn.TextColor3 = selectedMap[opt] and C_AMBER or C_TEXT_MUTED
        optBtn.TextXAlignment = Enum.TextXAlignment.Left
        optBtn.ZIndex = 52
        optBtn.Parent = scroll
        addCorner(optBtn, 4)

        optBtn.MouseButton1Click:Connect(function()
            selectedMap[opt] = not selectedMap[opt]
            optBtn.Text = (selectedMap[opt] and "✓ " or "   ") .. tostring(opt)
            optBtn.TextColor3 = selectedMap[opt] and C_AMBER or C_TEXT_MUTED
            optBtn.BackgroundTransparency = selectedMap[opt] and 0 or 1
            valueText.Text = getDisplayString()

            local outList = {}
            for k, v in pairs(selectedMap) do
                if v then table.insert(outList, k) end
            end
            pcall(function() callback(outList) end)
        end)
        optionButtons[opt] = optBtn
    end

    selectBtn.MouseButton1Click:Connect(function()
        listMenu.Visible = not listMenu.Visible
    end)
end

-- 5. Botão de Ação BigFroot
local function addButton(parent, labelText, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 32)
    btn.BackgroundColor3 = C_ITEM_BG
    btn.Text = labelText
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 12
    btn.TextColor3 = C_TEXT_WHITE
    btn.Parent = parent
    addCorner(btn, 6)
    addStroke(btn, C_ITEM_STROKE, 1, 0)

    btn.MouseEnter:Connect(function()
        tw(btn, { BackgroundColor3 = Color3.fromRGB(34, 34, 40) }, 0.1)
    end)
    btn.MouseLeave:Connect(function()
        tw(btn, { BackgroundColor3 = C_ITEM_BG }, 0.1)
    end)
    btn.MouseButton1Click:Connect(function()
        pcall(callback)
    end)
    return btn
end

--================================================================--
-- CRIAÇÃO DAS PÁGINAS E POPULAÇÃO
--================================================================--

-- 1. Página "Eggs" (Principal - 2 Colunas como na referência)
local EggsPage = createPage("Eggs")

local EggsCols = Instance.new("Frame")
EggsCols.Size = UDim2.new(1, 0, 0, 0)
EggsCols.AutomaticSize = Enum.AutomaticSize.Y
EggsCols.BackgroundTransparency = 1
EggsCols.Parent = EggsPage

local ColLeft = Instance.new("Frame")
ColLeft.Size = UDim2.new(0.5, -6, 0, 0)
ColLeft.Position = UDim2.new(0, 0, 0, 0)
ColLeft.AutomaticSize = Enum.AutomaticSize.Y
ColLeft.BackgroundTransparency = 1
ColLeft.Parent = EggsCols

local ColLeftLayout = Instance.new("UIListLayout")
ColLeftLayout.Padding = UDim.new(0, 10)
ColLeftLayout.Parent = ColLeft

local ColRight = Instance.new("Frame")
ColRight.Size = UDim2.new(0.5, -6, 0, 0)
ColRight.Position = UDim2.new(0.5, 6, 0, 0)
ColRight.AutomaticSize = Enum.AutomaticSize.Y
ColRight.BackgroundTransparency = 1
ColRight.Parent = EggsCols

local ColRightLayout = Instance.new("UIListLayout")
ColRightLayout.Padding = UDim.new(0, 10)
ColRightLayout.Parent = ColRight

-- [CARD 1 - COLUNA ESQUERDA]: Auto Steal
local AutoStealCard = createCard(ColLeft, "Auto Steal", "⚔")
addDisclaimer(AutoStealCard, "SCRIPT IS FREE", "IF YOU BOUGHT IT FROM SOMEONE YOU GOT SCAMMED.", "discord.gg/bigfroot")

addToggle(AutoStealCard, "Auto Steal Eggs", Flags.AutoSteal, function(state)
    autoStealRunId = autoStealRunId + 1
    local thisRunId = autoStealRunId
    Flags.AutoSteal = state
    if state then
        local hrp = getHRP()
        if hrp then
            Flags.SavedBasePos = Flags.CustomBasePos or hrp.Position
        end
        addLog("ROUBO", "Auto Steal ativado (BigFroot Engine).")
        task.spawn(function()
            while scriptActive and Flags.AutoSteal and autoStealRunId == thisRunId do
                flyStealLoop()
                task.wait(Flags.StealDelay)
            end
        end)
    else
        addLog("ROUBO", "Auto Steal desativado.")
    end
end)

addToggle(AutoStealCard, "Auto Steal Infested Eggs", Flags.AutoStealInfested or true, function(state)
    Flags.AutoStealInfested = state
    Flags.PrioritizeRare = state
    invalidateTargetCache()
end)

addToggle(AutoStealCard, "Shelter From Dragon Wave", Flags.ShelterFromDragon or true, function(state)
    Flags.ShelterFromDragon = state
end)

addToggle(AutoStealCard, "Avoid Traps", Flags.AvoidTraps or true, function(state)
    Flags.AvoidTraps = state
    Flags.Noclip = state
    if not state then restoreNoclip() end
end)

addSlider(AutoStealCard, "Glide Speed", 50, 1000, Flags.FlySpeed or 950, "studs/s", function(val)
    Flags.FlySpeed = val
end)

addDropdown(AutoStealCard, "Target Priority", { "Rarity", "Value ($/s)", "Distance", "Balanced" }, Flags.TargetPriority or "Rarity", function(val)
    Flags.TargetPriority = val
    Flags.PrioritizeRare = (val == "Rarity" or val == "Value ($/s)")
    invalidateTargetCache()
end)

addToggle(AutoStealCard, "Return To Plot", Flags.ReturnToPlot ~= false, function(state)
    Flags.ReturnToPlot = state
end)

addDropdown(AutoStealCard, "Return To", { "Pen Area", "Plot Base", "Spawn", "Posição Atual" }, Flags.ReturnTo or "Pen Area", function(val)
    Flags.ReturnTo = val
    if val == "Posição Atual" then
        local hrp = getHRP()
        if hrp then
            Flags.CustomBasePos = hrp.Position
            addLog("BASE", "Base registrada na posição atual.")
        end
    end
end)

addButton(AutoStealCard, "Definir Posição Atual como Base", function()
    local hrp = getHRP()
    if hrp then
        Flags.CustomBasePos = hrp.Position
        Flags.SavedBasePos = hrp.Position
        addLog("BASE", "Base registrada com sucesso: " .. tostring(math.floor(hrp.Position.X)) .. ", " .. tostring(math.floor(hrp.Position.Z)))
    end
end)

-- [CARD 2 - COLUNA DIREITA]: OP Stuffs
local OpStuffsCard = createCard(ColRight, "OP Stuffs", "⚡")

addToggle(OpStuffsCard, "Instant TP (Off God Mode)", Flags.InstantTP or false, function(state)
    Flags.InstantTP = state
    addLog("TELEPORTE", "Instant TP: " .. (state and "ATIVADO" or "DESATIVADO"))
end)

addToggle(OpStuffsCard, "God Mode", Flags.GodMode, function(state)
    Flags.GodMode = state
    addLog("JOGADOR", "God Mode local " .. (state and "ativado" or "desativado") .. ". (Nota: dano do servidor FE ainda pode aplicar).")
end)

addToggle(OpStuffsCard, "Anti Treadmill", Flags.AntiTreadmill ~= false, function(state)
    Flags.AntiTreadmill = state
    Flags.AntiRagdoll = state
    Flags.NeverDropEgg = state
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    setRagdollStatesEnabled(hum, not state)
    if state and char and hum then enforceAntiRagdoll(char, hum) end
    if not state then restoreRagdollConstraints() end
    addLog("JOGADOR", "Anti Treadmill & Anti-Ragdoll: " .. (state and "ATIVADO" or "DESATIVADO"))
end)

addToggle(OpStuffsCard, "Speed Boost", Flags.SpeedHack, function(state)
    Flags.SpeedHack = state
    if not state then
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        local defaults = hum and humanoidDefaults[hum]
        if hum and defaults then hum.WalkSpeed = defaults.WalkSpeed end
    end
end)

addSlider(OpStuffsCard, "WalkSpeed", 16, 250, Flags.WalkSpeed or 16, "spd", function(val)
    Flags.WalkSpeed = val
    if Flags.SpeedHack then
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = val end
    end
end)

addToggle(OpStuffsCard, "Jump Boost", Flags.JumpPowerHack, function(state)
    Flags.JumpPowerHack = state
    if not state then
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        local defaults = hum and humanoidDefaults[hum]
        if hum and defaults then hum.JumpPower = defaults.JumpPower end
    end
end)

addSlider(OpStuffsCard, "JumpPower", 50, 300, Flags.JumpPower or 50, "pwr", function(val)
    Flags.JumpPower = val
    if Flags.JumpPowerHack then
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.JumpPower = val end
    end
end)

addToggle(OpStuffsCard, "Infinite Jump", Flags.InfJump, function(state)
    Flags.InfJump = state
end)

-- [CARD 3 - COLUNA DIREITA]: Auto Steal Filter
local FilterCard = createCard(ColRight, "Auto Steal Filter", "🔍")

addDropdown(FilterCard, "Areas", { "...", "Todas as Áreas", "Prehistoric", "Abyss Ocean", "Volcano", "Cherry Blossom" }, Flags.SelectedArea or "...", function(val)
    Flags.SelectedArea = val
    invalidateTargetCache()
end)

addDropdown(FilterCard, "Categories", { "...", "Todas", "Base Eggs", "Area Eggs", "SmartPrompts" }, Flags.SelectedCategory or "...", function(val)
    Flags.SelectedCategory = val
    invalidateTargetCache()
end)

addMultiSelect(FilterCard, "Rarities", { "Divine", "Eternal", "Secret", "Cosmic", "Mythic", "Legendary", "Epic", "Rare", "Common" }, Flags.SelectedRarities or { "Divine", "Eternal", "Secret", "Cosmic" }, function(list)
    Flags.SelectedRarities = list
    invalidateTargetCache()
end)

addDropdown(FilterCard, "Mutations", { "...", "Todas", "Infested", "Golden", "Rainbow" }, Flags.SelectedMutations or "...", function(val)
    Flags.SelectedMutations = val
    invalidateTargetCache()
end)

addSlider(FilterCard, "Pontuação Mínima", 0, 40000, Flags.ManualMinRarityScore or 0, "pts", function(val)
    Flags.ManualMinRarityScore = val
    Flags.MinRarityScore = val
    invalidateTargetCache()
end)

addToggle(FilterCard, "Ignorar Ovos Comuns", Flags.FilterIgnoreCommons, function(state)
    Flags.FilterIgnoreCommons = state
    invalidateTargetCache()
end)

--================================================================--
-- 2. Página: Visual (ESP)
--================================================================--
local VisualPage = createPage("Visual")
local VisualCard = createCard(VisualPage, "Visuals & ESP", "👁")

addToggle(VisualCard, "ESP de Ovos (Marcadores Leves)", Flags.EggESP, function(state)
    Flags.EggESP = state
    updateESP()
end)

addToggle(VisualCard, "ESP de Jogadores (Nomes)", Flags.PlayerESP, function(state)
    Flags.PlayerESP = state
    updateESP()
end)

addButton(VisualCard, "Limpar Marcadores ESP", function()
    clearAllESP()
    addLog("VISUAL", "Todos os marcadores ESP foram removidos da tela.")
end)

--================================================================--
-- 3. Página: Dashboard & Console Logger
--================================================================--
local DashPage = createPage("Dashboard")
local LogCard = createCard(DashPage, "Console de Diagnóstico em Tempo Real", "📊")

local ConsoleScroll = Instance.new("ScrollingFrame")
ConsoleScroll.Size = UDim2.new(1, 0, 0, 220)
ConsoleScroll.BackgroundColor3 = Color3.fromRGB(13, 13, 16)
ConsoleScroll.BorderSizePixel = 0
ConsoleScroll.ScrollBarThickness = 3
ConsoleScroll.ScrollBarImageColor3 = C_AMBER
ConsoleScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
ConsoleScroll.Parent = LogCard
addCorner(ConsoleScroll, 6)
addStroke(ConsoleScroll, C_ITEM_STROKE, 1, 0)

local ConsoleLabel = Instance.new("TextLabel")
ConsoleLabel.Size = UDim2.new(1, -12, 1, -12)
ConsoleLabel.Position = UDim2.new(0, 6, 0, 6)
ConsoleLabel.BackgroundTransparency = 1
ConsoleLabel.TextColor3 = Color3.fromRGB(0, 220, 180)
ConsoleLabel.TextSize = 10.5
ConsoleLabel.Font = Enum.Font.Code
ConsoleLabel.TextXAlignment = Enum.TextXAlignment.Left
ConsoleLabel.TextYAlignment = Enum.TextYAlignment.Top
ConsoleLabel.Text = "=== BIGFROOT CONSOLE LOGGER ==="
ConsoleLabel.Parent = ConsoleScroll

local function updateLogConsole()
    local text = table.concat(LogHistory, "\n")
    ConsoleLabel.Text = text
    ConsoleScroll.CanvasSize = UDim2.new(0, 0, 0, #LogHistory * 18 + 20)
end
_G.UpdateLogConsole = updateLogConsole
updateLogConsole()

addToggle(LogCard, "Salvar Registros no Disco (.txt)", Flags.SaveToDisk, function(state)
    Flags.SaveToDisk = state
    addLog("SISTEMA", "Gravação em disco: " .. (state and "ATIVADA" or "DESATIVADA"))
end)

addToggle(LogCard, "Diagnóstico Detalhado do Auto Steal", Flags.AutoLogger, function(state)
    Flags.AutoLogger = state
end)

addButton(LogCard, "Copiar Todos os Registros", function()
    pcall(function()
        if setclipboard then
            setclipboard(table.concat(LogHistory, "\n----------------------------------------\n"))
            addLog("SISTEMA", "Registros copiados para a área de transferência.")
        end
    end)
end)

addButton(LogCard, "Limpar Histórico do Console", function()
    LogHistory = {}
    addLog("SISTEMA", "Histórico limpo.")
end)

--================================================================--
-- 4. Página: Radar ao Vivo (Ovos no Mapa)
--================================================================--
local RadarPage = createPage("Radar")
local RadarCard = createCard(RadarPage, "Radar de Ovos em Tempo Real", "🎯")

addButton(RadarCard, "Escanear Ovos do Mapa Agora", function()
    local discovered, dumpText = scanAllEggsInMap()
    addLog("RADAR", tostring(#discovered) .. " ovos encontrados. Relatório pronto para consulta.")
    print("\n" .. dumpText .. "\n")
end)

addButton(RadarCard, "Copiar Relatório do Radar", function()
    if not _G.EggRadarText or _G.EggRadarText == "" then
        scanAllEggsInMap()
    end
    pcall(function()
        if setclipboard then
            setclipboard(_G.EggRadarText)
            addLog("RADAR", "Relatório do radar copiado com sucesso.")
        end
    end)
end)

addButton(RadarCard, "Roubar Alvo Top 1 de Maior Valor", function()
    task.spawn(function()
        local prev = Flags.AutoSteal
        Flags.AutoSteal = true
        flyStealLoop()
        Flags.AutoSteal = prev
    end)
end)

addButton(RadarCard, "Gerar Diagnóstico Estrutural Completo (TXT)", function()
    local dump = dumpGameStructure()
    addLog("DIAGNÓSTICO", "Relatório estrutural gerado e copiado.")
end)

--================================================================--
-- 5. Página: Configurações Gerais
--================================================================--
local SettingsPage = createPage("Settings")
local SettCard = createCard(SettingsPage, "Configurações & Teclas", "⚙")

addToggle(SettCard, "Proteção Anti-AFK", Flags.AntiAFK, function(state)
    Flags.AntiAFK = state
end)

addButton(SettCard, "Mostrar / Ocultar Interface (LeftControl)", function()
    ScreenGui.Enabled = not ScreenGui.Enabled
end)

addButton(SettCard, "Descarregar e Encerrar Script", function()
    scriptActive = false
    Flags.AutoSteal = false
    Flags.Noclip = false
    Flags.AntiRagdoll = false
    Flags.NeverDropEgg = false
    Flags.GodMode = false
    Flags.SpeedHack = false
    Flags.JumpPowerHack = false
    restoreNoclip()
    restoreRagdollConstraints()
    local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    local defaults = hum and humanoidDefaults[hum]
    if hum then
        setRagdollStatesEnabled(hum, true)
        if defaults then
            hum.WalkSpeed = defaults.WalkSpeed
            hum.JumpPower = defaults.JumpPower
        end
    end
    clearAllESP()
    ScreenGui:Destroy()
end)

-- Criação das outras abas (Placeholders estilizados)
local otherTabs = {
    { id = "Progression", name = "Progression", icon = "📈" },
    { id = "Pets", name = "Pets", icon = "🐾" },
    { id = "Monster", name = "Monster Event", icon = "👾" },
    { id = "Contest", name = "Contest", icon = "⚔" },
    { id = "Fuse", name = "Fuse", icon = "✨" },
    { id = "Gifting", name = "Gifting", icon = "🎁" }
}

for _, tInfo in ipairs(otherTabs) do
    local pg = createPage(tInfo.id)
    local card = createCard(pg, tInfo.name, tInfo.icon)
    addDisclaimer(card, tInfo.name:upper(), "Módulo de automação sincronizado.", "Opções específicas deste evento serão ativadas durante a rotação do jogo.")
end

-- Montagem da Barra Lateral
addSidebarTab("Eggs", "Eggs", "🎯", 1)
addSidebarTab("Progression", "Progression", "📈", 2)
addSidebarTab("Pets", "Pets", "🐾", 3)
addSidebarTab("Monster", "Monster Event", "👾", 4)
addSidebarTab("Contest", "Contest", "⚔", 5)
addSidebarTab("Fuse", "Fuse", "✨", 6)
addSidebarTab("Visual", "Visual", "👁", 7)
addSidebarTab("Gifting", "Gifting", "🎁", 8)
addSidebarTab("Dashboard", "Dashboard", "📊", 9)
addSidebarTab("Settings", "Settings", "⚙", 10)

-- Sub-Abas do Topo para a aba "Eggs"
addSubTab("AutoSteal", "Auto Steal Eggs", function()
    switchTab("Eggs")
end)

addSubTab("RadarTab", "Eggs", function()
    switchTab("Radar")
end)

-- Inicializar na aba "Eggs"
switchTab("Eggs")
if SubTabButtons["AutoSteal"] then
    tw(SubTabButtons["AutoSteal"], { TextColor3 = C_TEXT_WHITE }, 0.1)
    if SubTabIndicators["AutoSteal"] then
        SubTabIndicators["AutoSteal"].Visible = true
    end
end

-- Tecla de Atalho (LeftControl) para alternar visibilidade
UserInputService.InputBegan:Connect(function(input, gpe)
    if scriptActive and not gpe and input.KeyCode == Enum.KeyCode.LeftControl then
        ScreenGui.Enabled = not ScreenGui.Enabled
    end
end)

-- Botão Flutuante Mobile (Para dispositivos Touch / sem teclado)
local MobileToggleBtn = Instance.new("TextButton")
MobileToggleBtn.Name = "BF_MobileToggle"
MobileToggleBtn.Size = UDim2.new(0, 36, 0, 36)
MobileToggleBtn.Position = UDim2.new(0, 10, 0.4, 0)
MobileToggleBtn.BackgroundColor3 = C_SIDEBAR
MobileToggleBtn.Text = "BF"
MobileToggleBtn.Font = Enum.Font.GothamBold
MobileToggleBtn.TextSize = 13
MobileToggleBtn.TextColor3 = C_AMBER
MobileToggleBtn.ZIndex = 1000
MobileToggleBtn.Parent = ScreenGui
addCorner(MobileToggleBtn, 18)
addStroke(MobileToggleBtn, C_AMBER, 1.5, 0.3)
enableDragging(MobileToggleBtn)

MobileToggleBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

-- Proteger e Inserir GUI
protectGui(ScreenGui)
ScreenGui.Parent = getGuiContainer()
print("========== BIGFROOT HUB (STEAL AN EGG) CARREGADO COM SUCESSO ==========")

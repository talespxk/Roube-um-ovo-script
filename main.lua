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

-- Configurações e Flags Globais
local Flags = {
    AutoSteal = false,
    FlySpeed = 500, -- Velocidade ultra rápida (ajustável até 1000)
    StealRadius = 2500,
    StealDelay = 0.15,
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

    speed = speed or Flags.FlySpeed or 500
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
-- INTERFACE GLASSMORPHISM (FROSTED GLASS DARK AESTHETICS - v3.5)
--================================================================--

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = getRandomName()
ScreenGui.ResetOnSpawn = false

-- Janela Principal com Vidro Fumê Translúcido
local MainFrame = Instance.new("Frame")
MainFrame.Name = "GlassMain"
MainFrame.Size = UDim2.new(0, 680, 0, 460)
MainFrame.Position = UDim2.new(0.5, -340, 0.5, -230)
MainFrame.BackgroundColor3 = Color3.fromRGB(13, 16, 24)
MainFrame.BackgroundTransparency = 0.12
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 12)
MainCorner.Parent = MainFrame

-- Contorno / Reflexo de Vidro
local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(255, 255, 255)
MainStroke.Transparency = 0.86
MainStroke.Thickness = 1
MainStroke.Parent = MainFrame

-- Linha Superior de Brilho Ciano Suave
local TopGlow = Instance.new("Frame")
TopGlow.Size = UDim2.new(1, 0, 0, 2)
TopGlow.BackgroundColor3 = Color3.fromRGB(0, 175, 255)
TopGlow.BackgroundTransparency = 0.2
TopGlow.BorderSizePixel = 0
TopGlow.Parent = MainFrame

local TopGlowCorner = Instance.new("UICorner")
TopGlowCorner.CornerRadius = UDim.new(0, 12)
TopGlowCorner.Parent = TopGlow

-- Cabeçalho Glass
local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 46)
Header.Position = UDim2.new(0, 0, 0, 2)
Header.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
Header.BackgroundTransparency = 0.25
Header.BorderSizePixel = 0
Header.Parent = MainFrame

local HeaderCorner = Instance.new("UICorner")
HeaderCorner.CornerRadius = UDim.new(0, 12)
HeaderCorner.Parent = Header

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -70, 0, 22)
Title.Position = UDim2.new(0, 16, 0, 5)
Title.BackgroundTransparency = 1
Title.Text = "ROUBE UM OVO  /  PRO"
Title.TextColor3 = Color3.fromRGB(240, 245, 255)
Title.TextSize = 14
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Header

local Subtitle = Instance.new("TextLabel")
Subtitle.Size = UDim2.new(1, -70, 0, 16)
Subtitle.Position = UDim2.new(0, 16, 0, 25)
Subtitle.BackgroundTransparency = 1
Subtitle.Text = "Edição Furtiva em Vidro • v3.5"
Subtitle.TextColor3 = Color3.fromRGB(120, 140, 170)
Subtitle.TextSize = 11
Subtitle.Font = Enum.Font.Gotham
Subtitle.TextXAlignment = Enum.TextXAlignment.Left
Subtitle.Parent = Header

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 28, 0, 28)
CloseBtn.Position = UDim2.new(1, -38, 0, 9)
CloseBtn.BackgroundColor3 = Color3.fromRGB(25, 30, 44)
CloseBtn.BackgroundTransparency = 0.3
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = Color3.fromRGB(180, 195, 220)
CloseBtn.TextSize = 13
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.Parent = Header

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 6)
CloseCorner.Parent = CloseBtn

local CloseStroke = Instance.new("UIStroke")
CloseStroke.Color = Color3.fromRGB(255, 255, 255)
CloseStroke.Transparency = 0.9
CloseStroke.Thickness = 1
CloseStroke.Parent = CloseBtn

CloseBtn.MouseButton1Click:Connect(function()
    ScreenGui.Enabled = false
end)

-- Sidebar Vertical
local Sidebar = Instance.new("Frame")
Sidebar.Size = UDim2.new(0, 165, 1, -48)
Sidebar.Position = UDim2.new(0, 0, 0, 48)
Sidebar.BackgroundColor3 = Color3.fromRGB(10, 13, 19)
Sidebar.BackgroundTransparency = 0.35
Sidebar.BorderSizePixel = 0
Sidebar.Parent = MainFrame

local SidebarList = Instance.new("UIListLayout")
SidebarList.Padding = UDim.new(0, 4)
SidebarList.SortOrder = Enum.SortOrder.LayoutOrder
SidebarList.Parent = Sidebar

local SidebarPadding = Instance.new("UIPadding")
SidebarPadding.PaddingTop = UDim.new(0, 8)
SidebarPadding.PaddingLeft = UDim.new(0, 8)
SidebarPadding.PaddingRight = UDim.new(0, 8)
SidebarPadding.Parent = Sidebar

local ContentContainer = Instance.new("Frame")
ContentContainer.Size = UDim2.new(1, -165, 1, -48)
ContentContainer.Position = UDim2.new(0, 165, 0, 48)
ContentContainer.BackgroundTransparency = 1
ContentContainer.Parent = MainFrame

local TabFrames = {}
local TabButtons = {}

local function createTab(name)
    local tabBtn = Instance.new("TextButton")
    tabBtn.Size = UDim2.new(1, 0, 0, 36)
    tabBtn.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
    tabBtn.BackgroundTransparency = 0.5
    tabBtn.Text = "  " .. name
    tabBtn.TextColor3 = Color3.fromRGB(150, 165, 185)
    tabBtn.TextSize = 12
    tabBtn.Font = Enum.Font.GothamMedium
    tabBtn.TextXAlignment = Enum.TextXAlignment.Left
    tabBtn.Parent = Sidebar

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 6)
    btnCorner.Parent = tabBtn

    local btnStroke = Instance.new("UIStroke")
    btnStroke.Color = Color3.fromRGB(255, 255, 255)
    btnStroke.Transparency = 0.94
    btnStroke.Thickness = 1
    btnStroke.Parent = tabBtn

    local tabFrame = Instance.new("ScrollingFrame")
    tabFrame.Size = UDim2.new(1, -16, 1, -16)
    tabFrame.Position = UDim2.new(0, 8, 0, 8)
    tabFrame.BackgroundTransparency = 1
    tabFrame.BorderSizePixel = 0
    tabFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    tabFrame.ScrollBarThickness = 3
    tabFrame.ScrollBarImageColor3 = Color3.fromRGB(0, 175, 255)
    tabFrame.Visible = false
    tabFrame.Parent = ContentContainer

    local frameList = Instance.new("UIListLayout")
    frameList.Padding = UDim.new(0, 6)
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
            btn.BackgroundColor3 = active and Color3.fromRGB(0, 135, 230) or Color3.fromRGB(20, 24, 34)
            btn.BackgroundTransparency = active and 0.15 or 0.5
            btn.TextColor3 = active and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 165, 185)
        end
    end)

    return tabFrame
end

local MainTab = createTab("Roubo e Base")
local RadarTab = createTab("Radar e Filtros")
local PlayerTab = createTab("Modificações")
local VisualsTab = createTab("Visuais (ESP)")
local LoggerTab = createTab("Diagnóstico")
local SettingsTab = createTab("Configurações")

TabFrames[1].Visible = true
TabButtons[1].BackgroundColor3 = Color3.fromRGB(0, 135, 230)
TabButtons[1].BackgroundTransparency = 0.15
TabButtons[1].TextColor3 = Color3.fromRGB(255, 255, 255)

local function addToggle(tab, text, defaultState, callback)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, 42)
    card.BackgroundColor3 = Color3.fromRGB(20, 26, 38)
    card.BackgroundTransparency = 0.35
    card.Parent = tab

    local cardCorner = Instance.new("UICorner")
    cardCorner.CornerRadius = UDim.new(0, 6)
    cardCorner.Parent = card

    local cardStroke = Instance.new("UIStroke")
    cardStroke.Color = Color3.fromRGB(255, 255, 255)
    cardStroke.Transparency = 0.92
    cardStroke.Thickness = 1
    cardStroke.Parent = card

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -65, 1, 0)
    label.Position = UDim2.new(0, 12, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(225, 235, 245)
    label.TextSize = 12
    label.Font = Enum.Font.GothamMedium
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = card

    local switchBg = Instance.new("TextButton")
    switchBg.Size = UDim2.new(0, 40, 0, 20)
    switchBg.Position = UDim2.new(1, -50, 0.5, -10)
    switchBg.BackgroundColor3 = defaultState and Color3.fromRGB(0, 160, 255) or Color3.fromRGB(38, 46, 62)
    switchBg.Text = ""
    switchBg.Parent = card

    local switchCorner = Instance.new("UICorner")
    switchCorner.CornerRadius = UDim.new(1, 0)
    switchCorner.Parent = switchBg

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 14, 0, 14)
    knob.Position = defaultState and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.Parent = switchBg

    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(1, 0)
    knobCorner.Parent = knob

    local state = defaultState
    switchBg.MouseButton1Click:Connect(function()
        state = not state
        switchBg.BackgroundColor3 = state and Color3.fromRGB(0, 160, 255) or Color3.fromRGB(38, 46, 62)
        knob:TweenPosition(
            state and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7),
            Enum.EasingDirection.Out,
            Enum.EasingStyle.Quad,
            0.12,
            true
        )
        pcall(function() callback(state) end)
    end)

    return card
end

local function addButton(tab, text, callback)
    local card = Instance.new("TextButton")
    card.Size = UDim2.new(1, 0, 0, 38)
    card.BackgroundColor3 = Color3.fromRGB(24, 31, 46)
    card.BackgroundTransparency = 0.35
    card.Text = "  " .. text
    card.TextColor3 = Color3.fromRGB(235, 245, 255)
    card.TextSize = 12
    card.Font = Enum.Font.GothamMedium
    card.TextXAlignment = Enum.TextXAlignment.Left
    card.Parent = tab

    local cardCorner = Instance.new("UICorner")
    cardCorner.CornerRadius = UDim.new(0, 6)
    cardCorner.Parent = card

    local cardStroke = Instance.new("UIStroke")
    cardStroke.Color = Color3.fromRGB(0, 175, 255)
    cardStroke.Transparency = 0.85
    cardStroke.Thickness = 1
    cardStroke.Parent = card

    card.MouseButton1Click:Connect(function()
        pcall(function() callback() end)
    end)

    return card
end

local function addSlider(tab, title, min, max, default, callback)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, 50)
    card.BackgroundColor3 = Color3.fromRGB(20, 26, 38)
    card.BackgroundTransparency = 0.35
    card.Parent = tab

    local cardCorner = Instance.new("UICorner")
    cardCorner.CornerRadius = UDim.new(0, 6)
    cardCorner.Parent = card

    local cardStroke = Instance.new("UIStroke")
    cardStroke.Color = Color3.fromRGB(255, 255, 255)
    cardStroke.Transparency = 0.92
    cardStroke.Thickness = 1
    cardStroke.Parent = card

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -24, 0, 20)
    label.Position = UDim2.new(0, 12, 0, 4)
    label.BackgroundTransparency = 1
    label.Text = title .. ": " .. tostring(default)
    label.TextColor3 = Color3.fromRGB(210, 225, 240)
    label.TextSize = 11
    label.Font = Enum.Font.GothamMedium
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = card

    local sliderBg = Instance.new("TextButton")
    sliderBg.Size = UDim2.new(1, -24, 0, 8)
    sliderBg.Position = UDim2.new(0, 12, 0, 28)
    sliderBg.BackgroundColor3 = Color3.fromRGB(34, 42, 58)
    sliderBg.Text = ""
    sliderBg.Parent = card

    local bgCorner = Instance.new("UICorner")
    bgCorner.CornerRadius = UDim.new(1, 0)
    bgCorner.Parent = sliderBg

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new((default - min) / (max - min), 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(0, 160, 255)
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

-- População da Aba 1: Roubo e Base
addToggle(MainTab, "Roubo automático e retorno à base", Flags.AutoSteal, function(state)
    autoStealRunId = autoStealRunId + 1
    local thisRunId = autoStealRunId
    Flags.AutoSteal = state
    if state then
        local hrp = getHRP()
        if hrp then
            Flags.SavedBasePos = Flags.CustomBasePos or hrp.Position
        end
        addLog("ROUBO", "Roubo automático ativado. Posição da base registrada.")
        task.spawn(function()
            while scriptActive and Flags.AutoSteal and autoStealRunId == thisRunId do
                flyStealLoop()
                task.wait(Flags.StealDelay)
            end
        end)
    else
        addLog("ROUBO", "Roubo automático desativado.")
    end
end)

addToggle(MainTab, "Priorizar maior valor ($/s e raridade)", Flags.PrioritizeRare, function(state)
    Flags.PrioritizeRare = state
    invalidateTargetCache()
end)

addSlider(MainTab, "Velocidade de voo (blocos/s)", 50, 1000, Flags.FlySpeed, function(val)
    Flags.FlySpeed = val
end)

addSlider(MainTab, "Raio de busca (blocos)", 100, 4000, Flags.StealRadius, function(val)
    Flags.StealRadius = val
    invalidateTargetCache()
end)

addButton(MainTab, "Registrar posição atual como base", function()
    local hrp = getHRP()
    if hrp then
        Flags.CustomBasePos = hrp.Position
        Flags.SavedBasePos = hrp.Position
        addLog("BASE", "Posição da base atualizada: " .. tostring(math.floor(hrp.Position.X)) .. ", " .. tostring(math.floor(hrp.Position.Z)))
    end
end)

addButton(MainTab, "Executar um ciclo de roubo agora", function()
    task.spawn(function()
        local prev = Flags.AutoSteal
        Flags.AutoSteal = true
        flyStealLoop()
        Flags.AutoSteal = prev
    end)
end)

-- População da Aba 2: Radar & Filters
addButton(RadarTab, "Escanear ovos do mapa (radar ao vivo)", function()
    local discovered, dumpText = scanAllEggsInMap()
    addLog("RADAR", tostring(#discovered) .. " prompts compatíveis com Steal/Egg encontrados. O relatório completo foi enviado ao console do executor.")
    print("\n" .. dumpText .. "\n")
end)

addButton(RadarTab, "Gerar relatório completo do jogo (TXT)", function()
    local dump = dumpGameStructure()
    addLog("DIAGNÓSTICO", "Inventário estrutural gerado. Ele mostra objetos presentes, não chamadas remotas nem dados internos do servidor.")
    print("\n" .. dump .. "\n")
end)

addButton(RadarTab, "Copiar relatório do radar", function()
    if not _G.EggRadarText or _G.EggRadarText == "" then
        scanAllEggsInMap()
    end
    pcall(function()
        if setclipboard then
            setclipboard(_G.EggRadarText)
            addLog("RADAR", "Relatório do radar copiado.")
        end
    end)
end)

addButton(RadarTab, "Roubar agora o alvo de maior valor", function()
    task.spawn(function()
        local prev = Flags.AutoSteal
        Flags.AutoSteal = true
        flyStealLoop()
        Flags.AutoSteal = prev
    end)
end)

addToggle(RadarTab, "Filtro: ignorar comuns e baixo nível", Flags.FilterIgnoreCommons, function(state)
    Flags.FilterIgnoreCommons = state
    invalidateTargetCache()
    addLog("FILTROS", "Ignorar comuns: " .. (state and "ATIVADO" or "DESATIVADO"))
end)

local function updateMinimumRarityFilter()
    Flags.MinRarityScore = math.max(
        Flags.ManualMinRarityScore,
        Flags.FilterHighTier and 5000 or 0,
        Flags.FilterTopTier and 30000 or 0
    )
    invalidateTargetCache()
end

addToggle(RadarTab, "Filtro: nível alto (>= 5.000 pts)", false, function(state)
    Flags.FilterHighTier = state
    updateMinimumRarityFilter()
    addLog("FILTROS", "Filtro de nível alto: " .. (state and "ATIVADO (>= 5.000 pts)" or "DESATIVADO"))
end)

addToggle(RadarTab, "Filtro: somente nível máximo (>= 30.000 pts)", false, function(state)
    Flags.FilterTopTier = state
    updateMinimumRarityFilter()
    addLog("FILTROS", "Filtro de nível máximo: " .. (state and "ATIVADO (>= 30.000 pts)" or "DESATIVADO"))
end)

addSlider(RadarTab, "Pontuação mínima", 0, 40000, Flags.MinRarityScore, function(val)
    Flags.ManualMinRarityScore = val
    updateMinimumRarityFilter()
end)

-- População da Aba 3: Player Mods
addToggle(PlayerTab, "Recuperar vida local (experimental)", Flags.GodMode, function(state)
    Flags.GodMode = state
    addLog("JOGADOR", "Recuperação local de vida " .. (state and "ativada" or "desativada")
        .. ". O servidor pode sobrescrever esse efeito.")
end)

addToggle(PlayerTab, "Bloqueio local de ragdoll", Flags.AntiRagdoll, function(state)
    Flags.AntiRagdoll = state
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if state and char then
        for _, descendant in ipairs(char:GetDescendants()) do
            if descendant:IsA("AnimationConstraint") and not animationConstraintOriginal[descendant] then
                animationConstraintOriginal[descendant] = {
                    Enabled = descendant.Enabled,
                    IsKinematic = descendant.IsKinematic
                }
            end
        end
    end
    setRagdollStatesEnabled(hum, not state)
    if state and char and hum then enforceAntiRagdoll(char, hum) end
    if not state then restoreRagdollConstraints() end
    addLog("JOGADOR", "Bloqueio local de ragdoll " .. (state and "ativado" or "desativado")
        .. ". A recuperação do ovo será tentada após impactos detectados.")
end)

addToggle(PlayerTab, "Recuperar ovo derrubado", Flags.NeverDropEgg, function(state)
    Flags.NeverDropEgg = state
    addLog("JOGADOR", "Recuperação de ovo derrubado " .. (state and "ativada" or "desativada")
        .. ". O script tentará reequipar ou reacionar um prompt próximo.")
end)

addToggle(PlayerTab, "Aumento de velocidade", Flags.SpeedHack, function(state)
    Flags.SpeedHack = state
    if not state then
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        local defaults = hum and humanoidDefaults[hum]
        if hum and defaults then hum.WalkSpeed = defaults.WalkSpeed end
    end
end)

addSlider(PlayerTab, "Velocidade de caminhada", 16, 250, Flags.WalkSpeed, function(val)
    Flags.WalkSpeed = val
end)

addToggle(PlayerTab, "Aumento de força do pulo", Flags.JumpPowerHack, function(state)
    Flags.JumpPowerHack = state
    if not state then
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        local defaults = hum and humanoidDefaults[hum]
        if hum and defaults then hum.JumpPower = defaults.JumpPower end
    end
end)

addSlider(PlayerTab, "Força do pulo", 50, 300, Flags.JumpPower, function(val)
    Flags.JumpPower = val
end)

addToggle(PlayerTab, "Atravessar paredes", Flags.Noclip, function(state)
    Flags.Noclip = state
    if not state then restoreNoclip() end
end)

addToggle(PlayerTab, "Pulo infinito", Flags.InfJump, function(state)
    Flags.InfJump = state
end)

-- População da Aba 4: Visuals (ESP)
addToggle(VisualsTab, "ESP de ovos (marcadores leves)", Flags.EggESP, function(state)
    Flags.EggESP = state
    updateESP()
end)

addToggle(VisualsTab, "ESP de jogadores (nomes)", Flags.PlayerESP, function(state)
    Flags.PlayerESP = state
    updateESP()
end)

-- População da Aba 5: Console Logger
local ConsoleFrame = Instance.new("ScrollingFrame")
ConsoleFrame.Size = UDim2.new(1, 0, 1, -85)
ConsoleFrame.BackgroundColor3 = Color3.fromRGB(11, 14, 20)
ConsoleFrame.BackgroundTransparency = 0.3
ConsoleFrame.BorderSizePixel = 0
ConsoleFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
ConsoleFrame.ScrollBarThickness = 4
ConsoleFrame.ScrollBarImageColor3 = Color3.fromRGB(0, 175, 255)
ConsoleFrame.Parent = LoggerTab

local ConsoleCorner = Instance.new("UICorner")
ConsoleCorner.CornerRadius = UDim.new(0, 6)
ConsoleCorner.Parent = ConsoleFrame

local ConsoleStroke = Instance.new("UIStroke")
ConsoleStroke.Color = Color3.fromRGB(255, 255, 255)
ConsoleStroke.Transparency = 0.94
ConsoleStroke.Thickness = 1
ConsoleStroke.Parent = ConsoleFrame

local ConsoleText = Instance.new("TextLabel")
ConsoleText.Size = UDim2.new(1, -10, 1, 0)
ConsoleText.Position = UDim2.new(0, 5, 0, 5)
ConsoleText.BackgroundTransparency = 1
ConsoleText.TextColor3 = Color3.fromRGB(0, 220, 180)
ConsoleText.TextSize = 11
ConsoleText.Font = Enum.Font.Code
ConsoleText.TextXAlignment = Enum.TextXAlignment.Left
ConsoleText.TextYAlignment = Enum.TextYAlignment.Top
ConsoleText.Text = "=== CONSOLE DE DIAGNÓSTICO LOCAL ==="
ConsoleText.Parent = ConsoleFrame

local function updateLogConsole()
    local text = table.concat(LogHistory, "\n")
    ConsoleText.Text = text
    ConsoleFrame.CanvasSize = UDim2.new(0, 0, 0, #LogHistory * 20 + 30)
end
_G.UpdateLogConsole = updateLogConsole
updateLogConsole()

addToggle(LoggerTab, "Salvar registros automaticamente no disco", Flags.SaveToDisk, function(state)
    Flags.SaveToDisk = state
    addLog("SISTEMA", "Salvamento automático no disco: " .. (state and "ATIVADO" or "DESATIVADO"))
end)

addButton(LoggerTab, "Copiar registros do console", function()
    pcall(function()
        local fullText = table.concat(LogHistory, "\n----------------------------------------\n")
        if setclipboard then
            setclipboard(fullText)
            addLog("SISTEMA", "Todos os registros foram copiados.")
        end
    end)
end)

addButton(LoggerTab, "Limpar histórico do console", function()
    LogHistory = {}
    addLog("SISTEMA", "Histórico do console limpo.")
end)

-- População da Aba 6: Settings
addToggle(SettingsTab, "Proteção anti-inatividade", Flags.AntiAFK, function(state)
    Flags.AntiAFK = state
end)

addToggle(SettingsTab, "Diagnóstico detalhado do Auto Steal", Flags.AutoLogger, function(state)
    Flags.AutoLogger = state
end)

addButton(SettingsTab, "Mostrar/ocultar interface (Control esquerdo)", function()
    ScreenGui.Enabled = not ScreenGui.Enabled
end)

addButton(SettingsTab, "Descarregar e encerrar script", function()
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

-- Tecla de Atalho (LeftControl)
Services.UserInputService.InputBegan:Connect(function(input, gpe)
    if scriptActive and not gpe and input.KeyCode == Enum.KeyCode.LeftControl then
        ScreenGui.Enabled = not ScreenGui.Enabled
    end
end)

-- Iniciar GUI com proteção contra detecção de ChildAdded
protectGui(ScreenGui)
ScreenGui.Parent = getGuiContainer()
print("========== ROUBE UM OVO PRO v3.6 CARREGADO ==========")

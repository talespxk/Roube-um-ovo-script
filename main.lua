--[[
    EGGVISION - RADAR & RASTREADOR EM TEMPO REAL
    Jogo: Roube um Ovo (Steal an Egg)
    -----------------------------------------------------------------------
    - Leitura 100% observacional de instâncias, prompts e atributos reais.
    - Zero poluição de console (print/warn silenciados contra LogService).
    - Radar ao vivo com coordenadas (X, Y, Z), raridade, peso em Kg e zona.
    - Inspeção estrutural e dumper de arquivos/tabelas do jogo.
    - Interface escura fosca com acentos em âmbar e navegação rápida.
]]

-- Silenciamento Preventivo Total contra detecções do LogService.MessageOut
local function silentOutput(...) end
local print = silentOutput
local warn = silentOutput

-- Configurações e Flags Globais
local Flags = {
    -- Radar & Rastreamento
    RadarActive = true,
    MinRarityScore = 0,
    ManualMinRarityScore = 0,
    FilterIgnoreCommons = false,
    SelectedArea = "Todas as Áreas",
    SearchQuery = "",
    DiscoveredEggs = {},

    -- Visuals (ESP)
    EggESP = false,
    PlayerESP = false,
    ESPMaxDistance = 2500,
    ESPColor = Color3.fromRGB(255, 160, 18),
    PlayerESPColor = Color3.fromRGB(0, 180, 255),

    -- Automação Suave (Opcional - Desativada por padrão)
    AutoSteal = false,
    FlySpeed = 400,
    StealRadius = 2500,
    StealDelay = 0.25,
    PrioritizeRare = true,
    CustomBasePos = nil,
    SavedBasePos = nil,
    ReturnToPlot = true,
    AvoidTraps = true,

    -- Proteções do Jogador
    AntiRagdoll = true,
    NeverDropEgg = true,
    GodMode = false,
    SpeedHack = false,
    WalkSpeed = 16,
    JumpPowerHack = false,
    JumpPower = 50,
    Noclip = false,
    InfJump = false,

    -- Diagnóstico & Logger
    AntiAFK = true,
    AutoLogger = false,
    SaveToDisk = false
}

--================================================================--
-- SERVIÇOS SEGUROS COM CLONEREF
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
-- HISTÓRICO DE DIAGNÓSTICO INTERNO (SEM PRINT/WARN)
--================================================================--

local LogHistory = {}
local LogFileName = "egg_radar_logs.txt"

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
    local timestamp = os.date("%H:%M:%S")
    local entry = string.format("[%s] [%s] %s", timestamp, category, text)
    if extraArgs then
        entry = entry .. "\n  ↪ Detalhes: " .. formatArgsList(extraArgs)
    end

    table.insert(LogHistory, 1, entry)
    if #LogHistory > 300 then
        table.remove(LogHistory, #LogHistory)
    end

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

addLog("SISTEMA", "EggVision inicializado com segurança. Logs mantidos internamente.")

-- Utilitários de Segurança e Nomes Aleatórios
local function getRandomName()
    local guid = Services.HttpService:GenerateGUID(false):gsub("-", "")
    return "X_" .. guid:sub(1, math.random(10, 16))
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

local function plainText(value)
    return tostring(value or ""):gsub("<[^>]->", ""):lower()
end

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

-- Registry de Prompts por Eventos
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

-- Detecção e Fixação da Base do Jogador
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
-- AVALIAÇÃO OBSERVACIONAL DE RARIDADE, PESO E RENDA
--================================================================--

local RarityWeights = {
    ["admin abuse"] = 80000,
    ["monster parasite"] = 70000,
    ["dragon"] = 65000,
    ["sakura"] = 60000,
    ["brainrot"] = 55000,
    ["limited"] = 50000,
    ["capture the egg"] = 45000,
    ["prehistoric"] = 35000,
    ["pre-histórico"] = 35000,
    ["pre historico"] = 35000,
    ["abyss ocean"] = 28000,
    ["abyss"] = 28000,
    ["ocean"] = 28000,
    ["volcano"] = 20000,
    ["vulcão"] = 20000,
    ["vulcao"] = 20000,
    ["cherry blossom"] = 10000,
    ["cherry"] = 10000,
    ["blossom"] = 10000,
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
    local num, suffix = s:match("%$%s*([%d][%d%,%.]*)%s*(%a*)%s*/%s*s")
    if num then
        num = num:gsub(",", "")
        local n = tonumber(num)
        if n and n > 0 then
            local multipliers = { [""] = 1, k = 1e3, m = 1e6, b = 1e9, t = 1e12, qa = 1e15, qi = 1e18 }
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
    if not eggObj then return 0, "Sem dados confirmados", "nenhuma", 0, nil end
    local maxScore = 0
    local detectedRarity = "Normal"
    local detectedSource = "nenhuma"
    local highestIncome = 0
    local highestIncomeLabel = nil
    local detectedWeight = 0

    local function checkText(str, source)
        if not str or str == "" then return end
        local s = tostring(str):lower()

        local incomeVal, incomeFmt = parseIncomeRate(s)
        if incomeVal > highestIncome then
            highestIncome = incomeVal
            highestIncomeLabel = incomeFmt
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
            detectedWeight = kg
            local kgScore = kg * 2
            if kgScore > maxScore then
                maxScore = kgScore
                detectedRarity = string.format("%s Kg", tostring(kg))
                detectedSource = source
            end
        end
    end

    if prompt then
        checkText(prompt.ObjectText, "prompt")
        checkText(prompt.ActionText, "prompt")
    end

    pcall(function()
        for key, val in pairs(eggObj:GetAttributes()) do
            checkText(key, "atributo")
            checkText(val, "atributo")
        end
    end)

    pcall(function()
        for _, child in ipairs(eggObj:GetChildren()) do
            if child:IsA("ValueBase") then
                checkText(child.Name, "value")
                checkText(child.Value, "value")
            end
        end
    end)

    pcall(function()
        local inspected = 0
        for _, desc in ipairs(eggObj:GetDescendants()) do
            if inspected >= 35 then break end
            if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                inspected = inspected + 1
                checkText(desc.Text, "texto visual")
            end
        end
    end)

    checkText(eggObj.Name, "nome")

    return maxScore, detectedRarity, detectedSource, detectedWeight, highestIncomeLabel
end

local function getEggLocationZone(eggObj, prompt)
    local cur = eggObj or (prompt and prompt.Parent)
    local zoneName = "Mapa Aberto"
    local plotOwner = nil

    while cur and cur ~= Services.Workspace do
        local n = cur.Name
        local nLow = n:lower()

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

--================================================================--
-- SCANNER COMPLETO DE OVOS (DADOS REAIS EM TEMPO REAL)
--================================================================--

local function scanAllEggsInMap()
    local myPlayerName = LocalPlayer.Name:lower()
    local discovered = {}
    local hrp = getHRP()

    for obj in pairs(stealPromptRegistry) do
        if isStealPrompt(obj) and obj:IsDescendantOf(Services.Workspace) then
            local parent = obj.Parent
            local pos = getPromptPosition(obj)
            if parent and pos then
                local fullName = parent:GetFullName():lower()
                local isMyBase = fullName:find(myPlayerName) ~= nil
                local dist = hrp and (hrp.Position - pos).Magnitude or 0
                local rarityScore, rarityName, evidenceSource, weightKg, incomeFmt = evaluateEggRarity(parent, obj)
                local zoneName, plotOwner = getEggLocationZone(parent, obj)
                local displayName = (obj.ObjectText ~= "" and obj.ObjectText) or parent.Name

                table.insert(discovered, {
                    Prompt = obj,
                    Parent = parent,
                    Name = displayName,
                    Rarity = rarityName,
                    RarityScore = rarityScore,
                    WeightKg = weightKg,
                    IncomeFmt = incomeFmt,
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

    table.sort(discovered, function(a, b)
        if a.RarityScore ~= b.RarityScore then
            return a.RarityScore > b.RarityScore
        end
        return a.Distance < b.Distance
    end)

    Flags.DiscoveredEggs = discovered
    _G.DiscoveredEggs = discovered

    if _G.UpdateRadarCards then
        _G.UpdateRadarCards(discovered)
    end

    return discovered
end

--================================================================--
-- GERADOR DE DUMP ESTRUTURAL COMPLETO DO JOGO (.TXT)
--================================================================--

local function generateGameDump()
    local output = {}
    local function logLine(str) table.insert(output, str or "") end

    logLine("================================================================================")
    logLine("🧬 RELATÓRIO ESTRUTURAL COMPLETO DO JOGO — " .. os.date("%Y-%m-%d %H:%M:%S"))
    logLine("PlaceId: " .. tostring(game.PlaceId) .. " | JobId: " .. tostring(game.JobId))
    logLine("Jogador: " .. LocalPlayer.Name .. " (@" .. LocalPlayer.DisplayName .. ")")
    logLine("================================================================================\n")

    -- 1. ReplicatedStorage
    logLine("📁 [1/4] REPLICATED STORAGE (Configs, Ovos, Tabelas, Módulos):")
    pcall(function()
        for _, child in ipairs(Services.ReplicatedStorage:GetChildren()) do
            logLine(string.format("  • %s [%s] (Filhos: %d)", child.Name, child.ClassName, #child:GetChildren()))
            local low = child.Name:lower()
            if low:find("egg") or low:find("pet") or low:find("item") or low:find("data") or low:find("config") or low:find("shop") then
                for _, sub in ipairs(child:GetChildren()) do
                    logLine(string.format("      ↳ %s [%s]", sub.Name, sub.ClassName))
                end
            end
        end
    end)
    logLine("\n")

    -- 2. Workspace
    logLine("🗺️ [2/4] WORKSPACE (Zonas, Ilhas, Spawns, Pedestais):")
    pcall(function()
        for _, child in ipairs(Services.Workspace:GetChildren()) do
            if child:IsA("Folder") or child:IsA("Model") then
                local count = #child:GetChildren()
                if count > 0 then
                    logLine(string.format("  • %s [%s] (%d objetos)", child.Name, child.ClassName, count))
                end
            end
        end
    end)
    logLine("\n")

    -- 3. ProximityPrompts & Ovos
    logLine("🥚 [3/4] PROMPTS STEAL/EGG ATIVOS NO MAPA:")
    local eggs = scanAllEggsInMap()
    for i, e in ipairs(eggs) do
        logLine(string.format("#%02d [%s] %s | 📍 %s | Coords: (%.1f, %.1f, %.1f) | Dist: %dm | Peso: %s | Renda: %s",
            i, e.Rarity, e.Name, e.Zone, e.Position.X, e.Position.Y, e.Position.Z, math.floor(e.Distance),
            e.WeightKg > 0 and (tostring(e.WeightKg) .. " Kg") or "N/D", e.IncomeFmt or "N/D"
        ))
    end
    logLine("\n")

    -- 4. PlayerGui
    logLine("🖥️ [4/4] PLAYERGUI (Catálogos e Menus do Jogo):")
    pcall(function()
        local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if pg then
            for _, gui in ipairs(pg:GetChildren()) do
                if gui:IsA("ScreenGui") and gui.Enabled then
                    logLine(string.format("  • %s", gui.Name))
                end
            end
        end
    end)
    logLine("\n================================================================================")
    logLine("✅ FIM DO RELATÓRIO.")
    logLine("================================================================================")

    local fullDump = table.concat(output, "\n")
    pcall(function()
        if writefile then
            writefile("ROUBE_UM_OVO_DUMP.txt", fullDump)
        end
        if setclipboard then
            setclipboard(fullDump)
        end
    end)
    addLog("DIAGNÓSTICO", "Dump completo exportado com sucesso para ROUBE_UM_OVO_DUMP.txt e copiado!")
    return fullDump
end

--================================================================--
-- VOO FÍSICO SEGURO (SEM TELEPORTE INSTANTÂNEO)
--================================================================--

local function flyToPosition(targetPos, speed, onApproach)
    local hrp = getHRP()
    local char = LocalPlayer.Character
    if not hrp or not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local collisionState = {}

    speed = speed or Flags.FlySpeed or 400
    local startPos = hrp.Position
    local totalDist = (targetPos - startPos).Magnitude
    if totalDist < 3.5 then
        if onApproach then onApproach(totalDist) end
        return true
    end

    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            collisionState[part] = part.CanCollide
            part.CanCollide = false
        end
    end

    local bp = Instance.new("BodyPosition")
    bp.Name = getRandomName()
    bp.MaxForce = Vector3.new(1e9, 1e9, 1e9)
    bp.D = 600
    bp.P = 50000
    bp.Position = startPos
    bp.Parent = hrp

    local bg = Instance.new("BodyGyro")
    bg.Name = getRandomName()
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
        if onApproach then onApproach(remainingDistance) end
        if hum and hum.PlatformStand then hum.PlatformStand = false end
        if remainingDistance < 3.5 then break end
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
        if part and part.Parent then part.CanCollide = wasCollidable end
    end

    return finalDistance < 8, finalDistance
end

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
    return success
end

--================================================================--
-- ESP LEVE COM DADOS REAIS NA TELA (NOME, PESO KG, DISTÂNCIA)
--================================================================--

local activeESPs = {}

local function clearAllESP()
    for target, espItem in pairs(activeESPs) do
        pcall(function()
            if espItem and espItem.Parent then espItem:Destroy() end
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
    billboard.Size = UDim2.new(0, 200, 0, 26)
    billboard.StudsOffset = Vector3.new(0, 2.5, 0)
    billboard.Adornee = p

    local tag = Instance.new("TextLabel")
    tag.Size = UDim2.new(1, 0, 1, 0)
    tag.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
    tag.BackgroundTransparency = 0.2
    tag.TextColor3 = color or Color3.fromRGB(255, 160, 18)
    tag.TextSize = 11
    tag.Font = Enum.Font.GothamBold
    tag.Text = labelText
    tag.Parent = billboard

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 4)
    c.Parent = tag

    local s = Instance.new("UIStroke")
    s.Color = color or Color3.fromRGB(255, 160, 18)
    s.Transparency = 0.5
    s.Thickness = 1
    s.Parent = tag

    billboard.Parent = p
    activeESPs[target] = billboard

    target.AncestryChanged:Connect(function(_, parent)
        if not parent then
            pcall(function() billboard:Destroy() end)
            activeESPs[target] = nil
        end
    end)
end

local function updateESP()
    if not Flags.EggESP and not Flags.PlayerESP then
        clearAllESP()
        return
    end

    pcall(function()
        local seenTargets = {}
        local hrp = getHRP()
        local myPlayerName = LocalPlayer.Name:lower()

        if Flags.EggESP then
            local count = 0
            for obj in pairs(stealPromptRegistry) do
                if count >= 30 then break end
                if isStealPrompt(obj) and obj:IsDescendantOf(Services.Workspace) then
                    local parent = obj.Parent
                    local pos = getPromptPosition(obj)
                    if parent and pos then
                        local fullName = parent:GetFullName():lower()
                        if not fullName:find(myPlayerName) then
                            local dist = hrp and (hrp.Position - pos).Magnitude or 0
                            if dist <= (Flags.ESPMaxDistance or 2500) then
                                count = count + 1
                                local _, rName, _, weightKg = evaluateEggRarity(parent, obj)
                                local dName = (obj.ObjectText ~= "" and obj.ObjectText) or parent.Name
                                local weightTag = weightKg > 0 and (" [" .. tostring(weightKg) .. " Kg]") or (" [" .. rName .. "]")
                                local label = dName .. weightTag .. " (" .. math.floor(dist) .. "m)"
                                seenTargets[parent] = true
                                applyLightweightESP(parent, label, Flags.ESPColor)
                            end
                        end
                    end
                end
            end
        end

        if Flags.PlayerESP then
            for _, pl in ipairs(Services.Players:GetPlayers()) do
                if pl ~= LocalPlayer and pl.Character then
                    local pHrp = pl.Character:FindFirstChild("HumanoidRootPart")
                    if pHrp then
                        local dist = hrp and (hrp.Position - pHrp.Position).Magnitude or 0
                        seenTargets[pl.Character] = true
                        applyLightweightESP(pl.Character, pl.DisplayName .. " (" .. math.floor(dist) .. "m)", Flags.PlayerESPColor)
                    end
                end
            end
        end

        for target, espItem in pairs(activeESPs) do
            if not seenTargets[target] then
                pcall(function() if espItem and espItem.Parent then espItem:Destroy() end end)
                activeESPs[target] = nil
            end
        end
    end)
end

task.spawn(function()
    while scriptActive do
        task.wait(2)
        if Flags.EggESP or Flags.PlayerESP then
            updateESP()
        end
    end
end)

-- Proteção Básica do Personagem (Anti-Ragdoll / Recuperar Ovo)
local humanoidDefaults = setmetatable({}, { __mode = "k" })
local function applyCharacterProtections(char)
    if not char then return end
    local hum = char:WaitForChild("Humanoid", 3)
    if hum then
        humanoidDefaults[hum] = { WalkSpeed = hum.WalkSpeed, JumpPower = hum.JumpPower }
    end
end

if LocalPlayer.Character then task.spawn(function() applyCharacterProtections(LocalPlayer.Character) end) end
LocalPlayer.CharacterAdded:Connect(function(char)
    if scriptActive then task.spawn(function() applyCharacterProtections(char) end) end
end)

-- Anti-AFK
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
-- INTERFACE MODERNA E LIMPA (INSPIRADA NO DESIGN ESCURO + ÂMBAR)
--================================================================--

local TweenService = Services.TweenService
local UserInputService = Services.UserInputService

local C_BG         = Color3.fromRGB(11, 11, 13)
local C_SIDEBAR    = Color3.fromRGB(14, 14, 16)
local C_CARD       = Color3.fromRGB(19, 19, 22)
local C_CARD_STROKE= Color3.fromRGB(30, 30, 35)
local C_ITEM_BG    = Color3.fromRGB(24, 24, 28)
local C_ITEM_STROKE= Color3.fromRGB(38, 38, 44)
local C_AMBER      = Color3.fromRGB(255, 160, 18)     -- Âmbar Vibrante
local C_TEXT_WHITE = Color3.fromRGB(255, 255, 255)
local C_TEXT_MUTED = Color3.fromRGB(142, 142, 147)
local C_TOGGLE_OFF = Color3.fromRGB(48, 48, 54)
local C_TRACK_BG   = Color3.fromRGB(36, 36, 42)

local function tw(obj, props, duration)
    duration = duration or 0.18
    local t = TweenService:Create(obj, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
    t:Play()
    return t
end

local function addCorner(parent, px)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, px or 6)
    c.Parent = parent
    return c
end

local function addStroke(parent, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color or C_CARD_STROKE
    s.Thickness = thickness or 1
    s.Transparency = transparency or 0
    s.Parent = parent
    return s
end

local function addPadding(parent, top, bottom, left, right)
    local p = Instance.new("UIPadding")
    p.PaddingTop = UDim.new(0, top or 0)
    p.PaddingBottom = UDim.new(0, bottom or 0)
    p.PaddingLeft = UDim.new(0, left or 0)
    p.PaddingRight = UDim.new(0, right or 0)
    p.Parent = parent
    return p
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = getRandomName()
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local MainFrame = Instance.new("Frame")
MainFrame.Name = getRandomName()
MainFrame.Size = UDim2.new(0, 750, 0, 510)
MainFrame.Position = UDim2.new(0.5, -375, 0.5, -255)
MainFrame.BackgroundColor3 = C_BG
MainFrame.BorderSizePixel = 0
MainFrame.Parent = ScreenGui
addCorner(MainFrame, 10)
addStroke(MainFrame, C_CARD_STROKE, 1, 0)

-- Arrasto Suave
local dragging, dragInput, dragStart, startPos
local function enableDragging(dragHandle)
    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = MainFrame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
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

-- Sidebar Esquerda
local Sidebar = Instance.new("Frame")
Sidebar.Size = UDim2.new(0, 175, 1, 0)
Sidebar.BackgroundColor3 = C_SIDEBAR
Sidebar.BorderSizePixel = 0
Sidebar.Parent = MainFrame
addCorner(Sidebar, 10)

local SquarePatch = Instance.new("Frame")
SquarePatch.Size = UDim2.new(0, 10, 1, 0)
SquarePatch.Position = UDim2.new(1, -10, 0, 0)
SquarePatch.BackgroundColor3 = C_SIDEBAR
SquarePatch.BorderSizePixel = 0
SquarePatch.Parent = Sidebar
enableDragging(Sidebar)

-- Logo Limpo: EggVision
local LogoContainer = Instance.new("Frame")
LogoContainer.Size = UDim2.new(1, 0, 0, 52)
LogoContainer.BackgroundTransparency = 1
LogoContainer.Parent = Sidebar

local LogoText = Instance.new("TextLabel")
LogoText.Size = UDim2.new(1, -24, 0, 24)
LogoText.Position = UDim2.new(0, 16, 0, 14)
LogoText.BackgroundTransparency = 1
LogoText.RichText = true
LogoText.Text = '<font color="#FFFFFF"><b>Egg</b></font><font color="#FFA012"><b>Vision</b></font>'
LogoText.Font = Enum.Font.GothamBold
LogoText.TextSize = 22
LogoText.TextXAlignment = Enum.TextXAlignment.Left
LogoText.Parent = LogoContainer

local SubtitleText = Instance.new("TextLabel")
SubtitleText.Size = UDim2.new(1, -24, 0, 14)
SubtitleText.Position = UDim2.new(0, 16, 0, 38)
SubtitleText.BackgroundTransparency = 1
SubtitleText.Text = "Steal an Egg • Live Tracker"
SubtitleText.Font = Enum.Font.GothamMedium
SubtitleText.TextSize = 11
SubtitleText.TextColor3 = C_TEXT_MUTED
SubtitleText.TextXAlignment = Enum.TextXAlignment.Left
SubtitleText.Parent = LogoContainer

-- Lista de Navegação
local NavList = Instance.new("ScrollingFrame")
NavList.Size = UDim2.new(1, 0, 1, -114)
NavList.Position = UDim2.new(0, 0, 0, 60)
NavList.BackgroundTransparency = 1
NavList.BorderSizePixel = 0
NavList.ScrollBarThickness = 2
NavList.ScrollBarImageColor3 = C_AMBER
NavList.CanvasSize = UDim2.new(0, 0, 0, 280)
NavList.Parent = Sidebar
addPadding(NavList, 4, 4, 10, 10)

local NavLayout = Instance.new("UIListLayout")
NavLayout.Padding = UDim.new(0, 3)
NavLayout.SortOrder = Enum.SortOrder.LayoutOrder
NavLayout.Parent = NavList

-- Perfil do Jogador
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

local ProfileStatus = Instance.new("TextLabel")
ProfileStatus.Size = UDim2.new(1, -44, 0, 13)
ProfileStatus.Position = UDim2.new(0, 42, 0, 22)
ProfileStatus.BackgroundTransparency = 1
ProfileStatus.Text = "Radar Furtivo Ativo"
ProfileStatus.Font = Enum.Font.Gotham
ProfileStatus.TextSize = 10
ProfileStatus.TextColor3 = C_AMBER
ProfileStatus.TextXAlignment = Enum.TextXAlignment.Left
ProfileStatus.Parent = ProfileFrame

-- Barra Superior
local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, -175, 0, 44)
TopBar.Position = UDim2.new(0, 175, 0, 0)
TopBar.BackgroundColor3 = C_BG
TopBar.BorderSizePixel = 0
TopBar.Parent = MainFrame
enableDragging(TopBar)

-- Barra de Pesquisa de Ovos em Tempo Real
local SearchBoxContainer = Instance.new("Frame")
SearchBoxContainer.Size = UDim2.new(1, -120, 0, 30)
SearchBoxContainer.Position = UDim2.new(0, 14, 0, 7)
SearchBoxContainer.BackgroundColor3 = C_ITEM_BG
SearchBoxContainer.Parent = TopBar
addCorner(SearchBoxContainer, 6)
addStroke(SearchBoxContainer, C_ITEM_STROKE, 1, 0)

local SearchIcon = Instance.new("TextLabel")
SearchIcon.Size = UDim2.new(0, 26, 1, 0)
SearchIcon.BackgroundTransparency = 1
SearchIcon.Text = "🔍"
SearchIcon.Font = Enum.Font.GothamBold
SearchIcon.TextSize = 12
SearchIcon.TextColor3 = C_TEXT_MUTED
SearchIcon.Parent = SearchBoxContainer

local SearchInput = Instance.new("TextBox")
SearchInput.Size = UDim2.new(1, -30, 1, 0)
SearchInput.Position = UDim2.new(0, 28, 0, 0)
SearchInput.BackgroundTransparency = 1
SearchInput.PlaceholderText = "Pesquisar ovos por nome, zona, peso ou raridade..."
SearchInput.PlaceholderColor3 = C_TEXT_MUTED
SearchInput.Text = ""
SearchInput.Font = Enum.Font.Gotham
SearchInput.TextSize = 11.5
SearchInput.TextColor3 = C_TEXT_WHITE
SearchInput.TextXAlignment = Enum.TextXAlignment.Left
SearchInput.ClearTextOnFocus = false
SearchInput.Parent = SearchBoxContainer

-- Botão de Atualização Rápida (Refresh)
local RefreshBtn = Instance.new("TextButton")
RefreshBtn.Size = UDim2.new(0, 30, 0, 30)
RefreshBtn.Position = UDim2.new(1, -95, 0, 7)
RefreshBtn.BackgroundColor3 = C_ITEM_BG
RefreshBtn.Text = "🔄"
RefreshBtn.Font = Enum.Font.GothamBold
RefreshBtn.TextSize = 13
RefreshBtn.TextColor3 = C_AMBER
RefreshBtn.Parent = TopBar
addCorner(RefreshBtn, 6)
addStroke(RefreshBtn, C_ITEM_STROKE, 1, 0)

-- Badge de Versão no Rodapé
local VersionBadge = Instance.new("Frame")
VersionBadge.Size = UDim2.new(0, 110, 0, 24)
VersionBadge.Position = UDim2.new(1, -120, 1, -32)
VersionBadge.BackgroundColor3 = C_CARD
VersionBadge.BorderSizePixel = 0
VersionBadge.Parent = MainFrame
addCorner(VersionBadge, 6)
addStroke(VersionBadge, C_CARD_STROKE, 1, 0)

local VersionText = Instance.new("TextLabel")
VersionText.Size = UDim2.new(1, 0, 1, 0)
VersionText.BackgroundTransparency = 1
VersionText.RichText = true
VersionText.Text = '<b><font color="#FFFFFF">v3.7</font></b> | <font color="#8E8E93">Stealth</font>'
VersionText.Font = Enum.Font.GothamBold
VersionText.TextSize = 11
VersionText.Parent = VersionBadge

-- Container de Páginas
local PageContainer = Instance.new("Frame")
PageContainer.Size = UDim2.new(1, -175, 1, -80)
PageContainer.Position = UDim2.new(0, 175, 0, 44)
PageContainer.BackgroundTransparency = 1
PageContainer.Parent = MainFrame

local TabButtons = {}
local Pages = {}
local CurrentTab = nil

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
        if lbl then tw(lbl, { TextColor3 = isSelected and C_TEXT_WHITE or C_TEXT_MUTED }, 0.15) end
        local icon = btn:FindFirstChild("Icon")
        if icon then tw(icon, { TextColor3 = isSelected and C_AMBER or C_TEXT_MUTED }, 0.15) end
    end
    for id, pg in pairs(Pages) do
        pg.Visible = (id == tabId)
    end
end

local function addSidebarTab(id, name, iconSymbol, order)
    local btn = Instance.new("TextButton")
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

    btn.MouseButton1Click:Connect(function() switchTab(id) end)
    TabButtons[id] = btn
    return btn
end

local function createPage(id)
    local pg = Instance.new("ScrollingFrame")
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

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 10)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = pg

    Pages[id] = pg
    return pg
end

-- Construtor de Cards
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

-- Widgets
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
end

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
end

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

    btn.MouseEnter:Connect(function() tw(btn, { BackgroundColor3 = Color3.fromRGB(34, 34, 40) }, 0.1) end)
    btn.MouseLeave:Connect(function() tw(btn, { BackgroundColor3 = C_ITEM_BG }, 0.1) end)
    btn.MouseButton1Click:Connect(function() pcall(callback) end)
    return btn
end

--================================================================--
-- 1. PÁGINA PRINCIPAL: RADAR AO VIVO (DADOS REAIS DOS OVOS)
--================================================================--

local RadarPage = createPage("Radar")

-- Card de Status e Resumo do Radar
local StatusCard = createCard(RadarPage, "Status do Servidor & Radar", "🎯")

local SummaryLabel = Instance.new("TextLabel")
SummaryLabel.Size = UDim2.new(1, 0, 0, 32)
SummaryLabel.BackgroundTransparency = 1
SummaryLabel.RichText = true
SummaryLabel.Text = 'Aguardando primeira varredura... Clique em <b>"Atualizar Radar Agora"</b>.'
SummaryLabel.Font = Enum.Font.Gotham
SummaryLabel.TextSize = 11.5
SummaryLabel.TextColor3 = C_TEXT_WHITE
SummaryLabel.TextXAlignment = Enum.TextXAlignment.Left
SummaryLabel.TextWrapped = true
SummaryLabel.Parent = StatusCard

local ActionRow = Instance.new("Frame")
ActionRow.Size = UDim2.new(1, 0, 0, 32)
ActionRow.BackgroundTransparency = 1
ActionRow.Parent = StatusCard

local ActionLayout = Instance.new("UIListLayout")
ActionLayout.FillDirection = Enum.FillDirection.Horizontal
ActionLayout.Padding = UDim.new(0, 8)
ActionLayout.Parent = ActionRow

local ScanBtn = Instance.new("TextButton")
ScanBtn.Size = UDim2.new(0.5, -4, 1, 0)
ScanBtn.BackgroundColor3 = C_ITEM_BG
ScanBtn.Text = "🔄 Atualizar Radar Agora"
ScanBtn.Font = Enum.Font.GothamBold
ScanBtn.TextSize = 11.5
ScanBtn.TextColor3 = C_AMBER
ScanBtn.Parent = ActionRow
addCorner(ScanBtn, 6)
addStroke(ScanBtn, C_ITEM_STROKE, 1, 0)

local CopyTableBtn = Instance.new("TextButton")
CopyTableBtn.Size = UDim2.new(0.5, -4, 1, 0)
CopyTableBtn.BackgroundColor3 = C_ITEM_BG
CopyTableBtn.Text = "📋 Copiar Lista Formatada"
CopyTableBtn.Font = Enum.Font.GothamBold
CopyTableBtn.TextSize = 11.5
CopyTableBtn.TextColor3 = C_TEXT_WHITE
CopyTableBtn.Parent = ActionRow
addCorner(CopyTableBtn, 6)
addStroke(CopyTableBtn, C_ITEM_STROKE, 1, 0)

-- Card da Lista de Ovos Detectados
local EggListCard = createCard(RadarPage, "Ovos Detectados no Mapa", "🥚")

local EggCardsHolder = Instance.new("Frame")
EggCardsHolder.Size = UDim2.new(1, 0, 0, 0)
EggCardsHolder.AutomaticSize = Enum.AutomaticSize.Y
EggCardsHolder.BackgroundTransparency = 1
EggCardsHolder.Parent = EggListCard

local EggCardsLayout = Instance.new("UIListLayout")
EggCardsLayout.Padding = UDim.new(0, 6)
EggCardsLayout.SortOrder = Enum.SortOrder.LayoutOrder
EggCardsLayout.Parent = EggCardsHolder

-- Função para Criar Cada Card de Ovo na Lista com Dados Reais
local function renderEggCards(eggsList)
    for _, child in ipairs(EggCardsHolder:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end

    local query = Flags.SearchQuery:lower()
    local renderedCount = 0

    for i, egg in ipairs(eggsList) do
        local matchesSearch = true
        if query ~= "" then
            local fullSearchText = (egg.Name .. " " .. egg.Rarity .. " " .. egg.Zone .. " " .. tostring(egg.WeightKg)):lower()
            if not fullSearchText:find(query, 1, true) then
                matchesSearch = false
            end
        end

        if matchesSearch then
            renderedCount = renderedCount + 1
            local itemCard = Instance.new("Frame")
            itemCard.Size = UDim2.new(1, 0, 0, 58)
            itemCard.BackgroundColor3 = C_ITEM_BG
            itemCard.LayoutOrder = i
            itemCard.Parent = EggCardsHolder
            addCorner(itemCard, 6)
            addStroke(itemCard, C_ITEM_STROKE, 1, 0)

            -- Linha Superior: Nome do Ovo + Distância + Coordenadas
            local eggTitle = Instance.new("TextLabel")
            eggTitle.Size = UDim2.new(1, -120, 0, 18)
            eggTitle.Position = UDim2.new(0, 10, 0, 6)
            eggTitle.BackgroundTransparency = 1
            eggTitle.RichText = true
            eggTitle.Text = string.format('<b>#%02d %s</b>', i, egg.Name)
            eggTitle.Font = Enum.Font.GothamBold
            eggTitle.TextSize = 12
            eggTitle.TextColor3 = C_TEXT_WHITE
            eggTitle.TextXAlignment = Enum.TextXAlignment.Left
            eggTitle.Parent = itemCard

            local distLabel = Instance.new("TextLabel")
            distLabel.Size = UDim2.new(0, 110, 0, 18)
            distLabel.Position = UDim2.new(1, -118, 0, 6)
            distLabel.BackgroundTransparency = 1
            distLabel.Text = string.format("📏 %d studs", math.floor(egg.Distance))
            distLabel.Font = Enum.Font.GothamMedium
            distLabel.TextSize = 11
            distLabel.TextColor3 = C_AMBER
            distLabel.TextXAlignment = Enum.TextXAlignment.Right
            distLabel.Parent = itemCard

            -- Linha Inferior: Badges de Localização, Peso e Raridade
            local infoText = Instance.new("TextLabel")
            infoText.Size = UDim2.new(1, -120, 0, 16)
            infoText.Position = UDim2.new(0, 10, 0, 26)
            infoText.BackgroundTransparency = 1
            infoText.RichText = true

            local weightStr = egg.WeightKg > 0 and (tostring(egg.WeightKg) .. " Kg") or egg.Rarity
            local incomeStr = egg.IncomeFmt and (" • " .. egg.IncomeFmt) or ""
            infoText.Text = string.format('<font color="#FFA012">[%s]</font>  📍 %s%s', weightStr, egg.Zone, incomeStr)
            infoText.Font = Enum.Font.Gotham
            infoText.TextSize = 10.5
            infoText.TextColor3 = C_TEXT_MUTED
            infoText.TextXAlignment = Enum.TextXAlignment.Left
            infoText.Parent = itemCard

            -- Coordenadas X, Y, Z
            local coordText = Instance.new("TextLabel")
            coordText.Size = UDim2.new(1, -120, 0, 14)
            coordText.Position = UDim2.new(0, 10, 0, 42)
            coordText.BackgroundTransparency = 1
            coordText.Text = string.format("Coords: X: %.1f, Y: %.1f, Z: %.1f", egg.Position.X, egg.Position.Y, egg.Position.Z)
            coordText.Font = Enum.Font.Code
            coordText.TextSize = 9.5
            coordText.TextColor3 = Color3.fromRGB(120, 140, 160)
            coordText.TextXAlignment = Enum.TextXAlignment.Left
            coordText.Parent = itemCard

            -- Botão Copiar Coordenadas
            local copyCoordBtn = Instance.new("TextButton")
            copyCoordBtn.Size = UDim2.new(0, 80, 0, 24)
            copyCoordBtn.Position = UDim2.new(1, -88, 0, 28)
            copyCoordBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
            copyCoordBtn.Text = "Copiar Pos"
            copyCoordBtn.Font = Enum.Font.GothamBold
            copyCoordBtn.TextSize = 10
            copyCoordBtn.TextColor3 = C_TEXT_WHITE
            copyCoordBtn.Parent = itemCard
            addCorner(copyCoordBtn, 4)
            addStroke(copyCoordBtn, C_ITEM_STROKE, 1, 0)

            copyCoordBtn.MouseButton1Click:Connect(function()
                local cStr = string.format("Vector3.new(%.1f, %.1f, %.1f)", egg.Position.X, egg.Position.Y, egg.Position.Z)
                pcall(function()
                    if setclipboard then
                        setclipboard(cStr)
                        addLog("RADAR", "Coordenadas copiadas: " .. cStr)
                    end
                end)
                copyCoordBtn.Text = "Copiado!"
                task.delay(1, function() copyCoordBtn.Text = "Copiar Pos" end)
            end)
        end
    end

    SummaryLabel.Text = string.format('<b>%d</b> ovos monitorados no mapa | <b>%d</b> exibidos com o filtro atual.', #eggsList, renderedCount)
end

_G.UpdateRadarCards = renderEggCards

ScanBtn.MouseButton1Click:Connect(function()
    local discovered = scanAllEggsInMap()
    renderEggCards(discovered)
    addLog("RADAR", tostring(#discovered) .. " ovos encontrados no mapa.")
end)

RefreshBtn.MouseButton1Click:Connect(function()
    local discovered = scanAllEggsInMap()
    renderEggCards(discovered)
end)

SearchInput:GetPropertyChangedSignal("Text"):Connect(function()
    Flags.SearchQuery = SearchInput.Text
    if Flags.DiscoveredEggs then
        renderEggCards(Flags.DiscoveredEggs)
    end
end)

CopyTableBtn.MouseButton1Click:Connect(function()
    if not Flags.DiscoveredEggs or #Flags.DiscoveredEggs == 0 then
        scanAllEggsInMap()
    end
    local lines = { "=== RELATÓRIO DO RADAR (ROUBE UM OVO) ===" }
    for i, e in ipairs(Flags.DiscoveredEggs) do
        table.insert(lines, string.format("#%02d [%s] %s | %s | Coords: Vector3.new(%.1f, %.1f, %.1f) | Dist: %dm",
            i, e.Rarity, e.Name, e.Zone, e.Position.X, e.Position.Y, e.Position.Z, math.floor(e.Distance)
        ))
    end
    pcall(function()
        if setclipboard then
            setclipboard(table.concat(lines, "\n"))
            addLog("RADAR", "Lista formatada copiada para a área de transferência.")
        end
    end)
end)

--================================================================--
-- 2. PÁGINA: VISUAL & ESP (MARCADORES NO MAPA)
--================================================================--

local VisualPage = createPage("Visual")
local EspCard = createCard(VisualPage, "Marcadores ESP na Tela", "👁")

addToggle(EspCard, "Ativar ESP de Ovos (Mostra Peso, Nome e Distância)", Flags.EggESP, function(state)
    Flags.EggESP = state
    updateESP()
    addLog("VISUAL", "ESP de ovos " .. (state and "ativado." or "desativado."))
end)

addToggle(EspCard, "Ativar ESP de Jogadores", Flags.PlayerESP, function(state)
    Flags.PlayerESP = state
    updateESP()
end)

addSlider(EspCard, "Alcance Máximo do ESP", 100, 5000, Flags.ESPMaxDistance or 2500, "studs", function(val)
    Flags.ESPMaxDistance = val
    updateESP()
end)

addButton(EspCard, "Limpar Todos os Marcadores da Tela", function()
    clearAllESP()
    addLog("VISUAL", "Marcadores limpos.")
end)

--================================================================--
-- 3. PÁGINA: DIAGNÓSTICO & DUMPER DE DADOS DO JOGO
--================================================================--

local DumpPage = createPage("Diagnostico")
local DumpCard = createCard(DumpPage, "Extrator de Arquivos e Logs do Jogo", "📦")

local DumperDesc = Instance.new("TextLabel")
DumperDesc.Size = UDim2.new(1, 0, 0, 36)
DumperDesc.BackgroundTransparency = 1
DumperDesc.Text = "Varre ReplicatedStorage, Workspace, PlayerGui e atributos internos do jogo para gerar um mapa completo de todos os ovos, chances e valores."
DumperDesc.Font = Enum.Font.Gotham
DumperDesc.TextSize = 11
DumperDesc.TextColor3 = C_TEXT_MUTED
DumperDesc.TextWrapped = true
DumperDesc.TextXAlignment = Enum.TextXAlignment.Left
DumperDesc.Parent = DumpCard

addButton(DumpCard, "📦 Gerar Dump Completo do Jogo (.TXT no Disco)", function()
    generateGameDump()
end)

local LogConsoleCard = createCard(DumpPage, "Console Interno de Diagnóstico", "📊")

local ConsoleScroll = Instance.new("ScrollingFrame")
ConsoleScroll.Size = UDim2.new(1, 0, 0, 180)
ConsoleScroll.BackgroundColor3 = Color3.fromRGB(13, 13, 16)
ConsoleScroll.BorderSizePixel = 0
ConsoleScroll.ScrollBarThickness = 3
ConsoleScroll.ScrollBarImageColor3 = C_AMBER
ConsoleScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
ConsoleScroll.Parent = LogConsoleCard
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
ConsoleLabel.Text = "=== EGGVISION DIAGNÓSTICO LOCAL ==="
ConsoleLabel.Parent = ConsoleScroll

local function updateLogConsole()
    local text = table.concat(LogHistory, "\n")
    ConsoleLabel.Text = text
    ConsoleScroll.CanvasSize = UDim2.new(0, 0, 0, #LogHistory * 18 + 20)
end
_G.UpdateLogConsole = updateLogConsole
updateLogConsole()

addToggle(LogConsoleCard, "Salvar Registros no Disco (.txt)", Flags.SaveToDisk, function(state)
    Flags.SaveToDisk = state
end)

addButton(LogConsoleCard, "Copiar Histórico de Logs", function()
    pcall(function()
        if setclipboard then
            setclipboard(table.concat(LogHistory, "\n----------------------------------------\n"))
            addLog("SISTEMA", "Logs copiados.")
        end
    end)
end)

addButton(LogConsoleCard, "Limpar Histórico", function()
    LogHistory = {}
    addLog("SISTEMA", "Histórico limpo.")
end)

--================================================================--
-- 4. PÁGINA: AUTOMAÇÃO SEGURA (OPCIONAL)
--================================================================--

local AutoPage = createPage("Automacao")
local AutoCard = createCard(AutoPage, "Coleta e Retorno Suave (Física)", "⚔")

addToggle(AutoCard, "Ativar Roubo Automático Suave", Flags.AutoSteal, function(state)
    Flags.AutoSteal = state
    if state then
        addLog("ROUBO", "Ciclo de roubo iniciado com voo físico.")
        task.spawn(function()
            while scriptActive and Flags.AutoSteal do
                local eggs = scanAllEggsInMap()
                if #eggs > 0 then
                    local target = eggs[1]
                    addLog("ROUBO", "Indo até o alvo: " .. target.Name .. " (" .. target.Rarity .. ")")
                    flyToPosition(target.Position + Vector3.new(0, 1, 0), Flags.FlySpeed)
                    stealEgg(target.Prompt)
                    task.wait(0.3)
                    if Flags.ReturnToPlot then
                        local basePos = getBasePosition()
                        if basePos then
                            flyToPosition(basePos + Vector3.new(0, 3, 0), Flags.FlySpeed)
                        end
                    end
                end
                task.wait(Flags.StealDelay)
            end
        end)
    else
        addLog("ROUBO", "Roubo automático pausado.")
    end
end)

addSlider(AutoCard, "Velocidade de Voo Suave", 100, 800, Flags.FlySpeed or 400, "studs/s", function(val)
    Flags.FlySpeed = val
end)

addToggle(AutoCard, "Retornar à Base Após Coleta", Flags.ReturnToPlot, function(state)
    Flags.ReturnToPlot = state
end)

addButton(AutoCard, "Registrar Posição Atual como Base", function()
    local hrp = getHRP()
    if hrp then
        Flags.CustomBasePos = hrp.Position
        Flags.SavedBasePos = hrp.Position
        addLog("BASE", string.format("Base fixada em: (%.1f, %.1f, %.1f)", hrp.Position.X, hrp.Position.Y, hrp.Position.Z))
    end
end)

--================================================================--
-- 5. PÁGINA: CONFIGURAÇÕES GERAIS & ATALHOS
--================================================================--

local SettingsPage = createPage("Configuracoes")
local SettCard = createCard(SettingsPage, "Configurações Gerais", "⚙")

addToggle(SettCard, "Proteção Anti-AFK (Evita Desconexão)", Flags.AntiAFK, function(state)
    Flags.AntiAFK = state
end)

addButton(SettCard, "Ocultar / Mostrar Interface (LeftControl)", function()
    ScreenGui.Enabled = not ScreenGui.Enabled
end)

addButton(SettCard, "Descarregar e Encerrar Script", function()
    scriptActive = false
    Flags.AutoSteal = false
    clearAllESP()
    ScreenGui:Destroy()
end)

-- Montagem da Sidebar
addSidebarTab("Radar", "Radar de Ovos", "🎯", 1)
addSidebarTab("Visual", "Visual & ESP", "👁", 2)
addSidebarTab("Diagnostico", "Diagnóstico & Dump", "📦", 3)
addSidebarTab("Automacao", "Automação Suave", "⚔", 4)
addSidebarTab("Configuracoes", "Configurações", "⚙", 5)

-- Iniciar na aba principal do Radar
switchTab("Radar")
task.spawn(function()
    task.wait(0.5)
    local eggs = scanAllEggsInMap()
    renderEggCards(eggs)
end)

-- Tecla de Atalho (LeftControl)
UserInputService.InputBegan:Connect(function(input, gpe)
    if scriptActive and not gpe and input.KeyCode == Enum.KeyCode.LeftControl then
        ScreenGui.Enabled = not ScreenGui.Enabled
    end
end)

-- Botão Flutuante Mobile com Ícone de Ovo
local MobileToggleBtn = Instance.new("TextButton")
MobileToggleBtn.Name = getRandomName()
MobileToggleBtn.Size = UDim2.new(0, 36, 0, 36)
MobileToggleBtn.Position = UDim2.new(0, 10, 0.4, 0)
MobileToggleBtn.BackgroundColor3 = C_SIDEBAR
MobileToggleBtn.Text = "🥚"
MobileToggleBtn.Font = Enum.Font.GothamBold
MobileToggleBtn.TextSize = 16
MobileToggleBtn.ZIndex = 1000
MobileToggleBtn.Parent = ScreenGui
addCorner(MobileToggleBtn, 18)
addStroke(MobileToggleBtn, C_AMBER, 1.5, 0.3)
enableDragging(MobileToggleBtn)

MobileToggleBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

-- Proteger e Inserir Interface
protectGui(ScreenGui)
ScreenGui.Parent = getGuiContainer()

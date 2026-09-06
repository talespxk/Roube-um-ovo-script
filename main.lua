if not game:IsLoaded() then
    game.Loaded:Wait()
end

--[[
    ROUBE UM OVO - HUB DE AUTOMAÇÃO & RADAR (v13.1 STABILITY)
    -----------------------------------------------------------------------
    - Radar honesto: somente mostra pet/raridade/renda quando o cliente replica
      evidência real. Slots opacos aparecem como N/D.
    - Sistema de Unload Completo: Botão no topo e configurações para encerrar
      100% das threads, limpar conexões, remover ESP e fechar interface.
    - Catálogo Oficial dos 11 Biomas (Ilhas 1 a 11): Coordenadas exatas, nomes
      reais e raridades legítimas (Comum a Titã - Godzilla/Kitsune).
    - Navegação por Humanoid/Pathfinding sem alterar CFrame do personagem.
    - Suporte a Ovos Especiais: Demonic Egg, Dragon Egg, Limited e Brainrot.
    - Movimento conservador sem alterar ou remover scripts do jogo.
]]

-- 1. Limpeza Preventiva de Globais
pcall(function()
    _G.DiscoveredEggs = nil
    _G.UpdateRadarCards = nil
    _G.UpdateLogConsole = nil
    _G.EggRadarText = nil
    _G.MegaDumpText = nil
    _G.scanAllEggsInMap = nil
    if getgenv then
        local g = getgenv()
        g.DiscoveredEggs = nil
        g.UpdateRadarCards = nil
        g.UpdateLogConsole = nil
        g.EggRadarText = nil
        g.MegaDumpText = nil
    end
end)

-- 2. Serviços Seguros via cloneref
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
    TweenService = safeService("TweenService"),
    PathfindingService = safeService("PathfindingService"),
    ReplicatedStorage = safeService("ReplicatedStorage"),
    CoreGui = safeService("CoreGui"),
    StarterGui = safeService("StarterGui")
}

local LocalPlayer = Services.Players.LocalPlayer
while not LocalPlayer do
    task.wait(0.2)
    LocalPlayer = Services.Players.LocalPlayer
end

-- 3. Paleta de Cores e Estilos Globais (Design Moderno & Alto Contraste v12.0)
local C_BG = Color3.fromRGB(11, 15, 26)         -- Fundo ultramoderno e profundo
local C_TOPBAR = Color3.fromRGB(19, 26, 45)     -- Barra superior elegante
local C_CARD = Color3.fromRGB(22, 32, 54)       -- Cards com contraste perfeito
local C_CARD_HOVER = Color3.fromRGB(30, 44, 74) -- Hover de destaque
local C_BORDER = Color3.fromRGB(48, 64, 94)     -- Bordas nítidas
local C_CYAN = Color3.fromRGB(56, 189, 248)     -- Ciano neon Tech Blue
local C_TEXT = Color3.fromRGB(255, 255, 255)    -- Branco puro 100% nítido
local C_MUTED = Color3.fromRGB(165, 180, 205)   -- Cinza-claro muito mais legível
local C_GREEN = Color3.fromRGB(34, 197, 94)     -- Verde vibrante (Lucro / Ativo)
local C_PURPLE = Color3.fromRGB(168, 85, 247)   -- Roxo mítico
local C_RED = Color3.fromRGB(239, 68, 68)       -- Vermelho alerta
local C_YELLOW = Color3.fromRGB(234, 179, 8)    -- Amarelo ouro

-- 4. Gerenciador Mestre de Conexões e Limpeza
local ScriptConnections = {}

--================================================================--
-- 5.1. CACHE FORENSE EM TEMPO REAL DE REMOTES (PETS, RENDA & EGG SHIFT)
--================================================================--
local RealFieldEggCache = {}
local RealPetIncomeCache = {}

local function setupNetworkingListeners()
    local packages = Services.ReplicatedStorage:FindFirstChild("Packages")
    local networking = packages and packages:FindFirstChild("Networking")
    
    -- Helper para encontrar remotes de forma resiliente
    local function findRemote(name, className)
        if networking then
            local r = networking:FindFirstChild(name)
            if r and (not className or r:IsA(className)) then return r end
        end
        for _, desc in ipairs(Services.ReplicatedStorage:GetDescendants()) do
            if desc.Name == name or desc.Name:find(name, 1, true) then
                if not className or desc:IsA(className) then
                    return desc
                end
            end
        end
        return nil
    end

    -- 1. FieldEggShifted: O servidor avisa exatamente qual Pet (AssetCategory) nasceu em cada Área/Slot
    local eggShifted = findRemote("FieldEggShifted", "RemoteEvent")
    if eggShifted then
        registerConnection(eggShifted.OnClientEvent:Connect(function(data)
            if type(data) == "table" then
                local petName = data.AssetCategory or data.Name or data.Pet
                local areaId = data.AreaId or data.Area or "Desconhecida"
                if petName and areaId then
                    RealFieldEggCache[areaId] = {
                        PetName = tostring(petName),
                        AreaId = tostring(areaId),
                        Time = os.clock(),
                        Data = data
                    }
                    if data.SlotKey then
                        RealFieldEggCache[tostring(data.SlotKey)] = tostring(petName)
                    end
                    traceEvent("EGG_SHIFTED", tostring(areaId) .. " -> " .. tostring(petName), data)
                end
            end
        end))
    end

    -- 2. CoinsGathered: O servidor envia a renda exata de cada Pet em moedas/segundo
    local coinsGathered = findRemote("CoinsGathered", "RemoteEvent")
    if coinsGathered then
        registerConnection(coinsGathered.OnClientEvent:Connect(function(petsList, isTotal)
            if type(petsList) == "table" then
                for _, pEntry in ipairs(petsList) do
                    if type(pEntry) == "table" and pEntry.uid and pEntry.amount then
                        RealPetIncomeCache[tostring(pEntry.uid)] = tonumber(pEntry.amount) or 0
                    end
                end
            end
        end))
    end
end
task.spawn(setupNetworkingListeners)

-- Helper para disparar Bat Swing (auto-defesa e stun em guardas/galinhas)
local function triggerBatSwing()
    pcall(function()
        local packages = Services.ReplicatedStorage:FindFirstChild("Packages")
        local networking = packages and packages:FindFirstChild("Networking")
        local batRemote = networking and networking:FindFirstChild("RE/BatSwing/Trigger")
        if not batRemote then
            for _, desc in ipairs(Services.ReplicatedStorage:GetDescendants()) do
                if desc:IsA("RemoteEvent") and (desc.Name == "RE/BatSwing/Trigger" or desc.Name:find("BatSwing")) then
                    batRemote = desc
                    break
                end
            end
        end
        if batRemote then
            batRemote:FireServer()
        end
    end)
end

-- Helper para invocar o Roubo Instantâneo via RemoteFunction (AskFieldEggCarry)
local function tryInstantCarryRemote(target)
    if not target then return false end
    local inst = target.Instance
    local modelName = inst and inst.Name or ""
    local slotKey = modelName:match("([%a%d_]+:Slot_%d+)")
    if not slotKey and inst and inst.Parent then
        slotKey = inst.Parent.Name:match("([%a%d_]+:Slot_%d+)")
    end
    if not slotKey and target.Position then
        local isl = getIslandByPos(target.Position)
        if isl and isl.Name then
            slotKey = isl.Name .. ":Slot_001"
        end
    end
    slotKey = slotKey or "Forest:Slot_001"
    local uid = modelName:find("FirstAreaEgg_") and modelName or ("FirstAreaEgg_" .. tostring(LocalPlayer.UserId) .. "_0_" .. slotKey)

    local packages = Services.ReplicatedStorage:FindFirstChild("Packages")
    local networking = packages and packages:FindFirstChild("Networking")
    local askCarry = networking and networking:FindFirstChild("RF/EggWorld/AskFieldEggCarry")
    if not askCarry then
        for _, desc in ipairs(Services.ReplicatedStorage:GetDescendants()) do
            if desc:IsA("RemoteFunction") and (desc.Name == "RF/EggWorld/AskFieldEggCarry" or desc.Name:find("AskFieldEggCarry")) then
                askCarry = desc
                break
            end
        end
    end

    if askCarry then
        for i = 1, 4 do
            task.spawn(function()
                pcall(function()
                    askCarry:InvokeServer({
                        FirstAreaSlotKey = slotKey,
                        Uid = uid
                    })
                end)
            end)
            task.wait(0.02)
        end
        return true
    end
    return false
end


local function registerConnection(conn)
    if conn then
        table.insert(ScriptConnections, conn)
    end
    return conn
end

-- 5. Configuração e Estado Geral
local Config = {
    StealMethod = "CaminhadaSegura",
    AutoStealEnabled = false,
    AutoEsteiraEnabled = false,
    LockCurrentIsland = false, -- Padrão: busca em todo o mapa
    MaxStealDistance = 450,
    MoveSpeed = 30,
    TargetRarity = "Qualquer",
    MinRarityScore = 0,
    ESPEnabled = false,
    ShowOnlyUnowned = true,
    AutoDepositWait = 1.0,
    SearchQuery = ""
}

local State = {
    IsUnloaded = false,
    BaseCFrame = nil,
    PlotFound = false,
    IsExecutingSteal = false,
    IsOnTreadmill = false,
    CarryConfirmed = false,
    CarryEvidence = nil,
    LastCarryChange = 0,
    ExpectCarryUntil = 0,
    LastHoldingResult = false,
    LastHoldingEvidence = nil,
    PendingLearnFingerprint = nil,
    PendingLearnAt = 0,
    CurrentTargetEgg = nil,
    LastPromptTriggered = nil,
    Logs = {}
}

local LearnedEggData = {}
local LearnedVisualData = {}
local learnEggMetadataFromArgs = function() end
local getEggVisualFingerprint

-- Telemetria de sessão. O arquivo JSONL é estruturado para permitir que uma
-- sessão longa seja analisada sem depender apenas do pequeno console da UI.
local Telemetry = {
    Enabled = true,
    StartedAt = os.clock(),
    SessionId = os.date("%Y%m%d_%H%M%S"),
    FileName = "ROUBE_UM_OVO_TRACE.jsonl",
    Pending = {},
    Recent = {},
    Counts = {},
    MaxRecent = 1200,
}

local function instancePath(instance)
    if typeof(instance) ~= "Instance" then return tostring(instance) end
    local ok, result = pcall(function() return instance:GetFullName() end)
    return ok and result or (instance.ClassName .. ":" .. instance.Name)
end

local function serializeTelemetry(value, depth, seen)
    depth = depth or 0
    seen = seen or {}
    local valueType = typeof(value)
    if valueType == "Instance" then
        local attrs = {}
        pcall(function()
            for key, attrValue in pairs(value:GetAttributes()) do
                attrs[tostring(key)] = tostring(attrValue)
            end
        end)
        return { type = value.ClassName, path = instancePath(value), attributes = attrs }
    elseif valueType == "Vector3" then
        return { x = value.X, y = value.Y, z = value.Z }
    elseif valueType == "CFrame" then
        local p = value.Position
        return { x = p.X, y = p.Y, z = p.Z }
    elseif valueType == "EnumItem" then
        return tostring(value)
    end

    local luaType = type(value)
    if luaType == "string" then
        return #value > 2000 and (value:sub(1, 2000) .. "<truncated>") or value
    end
    if luaType == "nil" or luaType == "boolean" or luaType == "number" then
        return value
    end
    if luaType ~= "table" then return tostring(value) end
    if seen[value] then return "<circular>" end
    if depth >= 4 then return "<max-depth>" end

    seen[value] = true
    local result = {}
    local count = 0
    for key, child in pairs(value) do
        count = count + 1
        if count > 80 then
            result["<truncated>"] = true
            break
        end
        result[tostring(key)] = serializeTelemetry(child, depth + 1, seen)
    end
    seen[value] = nil
    return result
end

local function traceEvent(category, eventName, data)
    if not Telemetry.Enabled then return end
    local entry = {
        session = Telemetry.SessionId,
        elapsed = math.floor((os.clock() - Telemetry.StartedAt) * 1000) / 1000,
        wallTime = os.date("%Y-%m-%d %H:%M:%S"),
        category = tostring(category),
        event = tostring(eventName),
        data = serializeTelemetry(data),
    }
    local ok, encoded = pcall(function() return Services.HttpService:JSONEncode(entry) end)
    if not ok then return end
    table.insert(Telemetry.Pending, encoded)
    table.insert(Telemetry.Recent, encoded)
    if #Telemetry.Recent > Telemetry.MaxRecent then table.remove(Telemetry.Recent, 1) end
    Telemetry.Counts[entry.category] = (Telemetry.Counts[entry.category] or 0) + 1
end

local function flushTelemetry()
    if #Telemetry.Pending == 0 then return end
    local batch = table.concat(Telemetry.Pending, "\n") .. "\n"
    table.clear(Telemetry.Pending)
    pcall(function()
        if appendfile then
            appendfile(Telemetry.FileName, batch)
        elseif writefile and readfile then
            local existing = ""
            pcall(function() existing = readfile(Telemetry.FileName) end)
            writefile(Telemetry.FileName, existing .. batch)
        end
    end)
end

-- Declarações antecipadas de componentes da UI e Funções
local ScreenGui = nil
local MobileBtn = nil
local MainFrame = nil
local StatusBadge = nil
local TargetInfoLabel = nil
local BaseLabel = nil
local EsteiraStatusLabel = nil
local MainToggleBtn = nil
local EsteiraToggleBtn = nil
local unloadScript = nil
local executeDirectSteal = nil

-- Função segura de anexação da GUI ao container do executor
local function attachGui(gui)
    local attached = false
    if gethui then
        local ok, res = pcall(gethui)
        if ok and res then
            gui.Parent = res
            attached = true
        end
    end
    if not attached and Services.CoreGui then
        local ok = pcall(function()
            gui.Parent = Services.CoreGui
        end)
        if ok and gui.Parent == Services.CoreGui then
            attached = true
        end
    end
    if not attached then
        pcall(function()
            local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 5)
            if pg then
                gui.Parent = pg
                attached = true
            end
        end)
    end
    return attached
end

local function purgeAllGuis()
    local names = {
        ["RoubeUmOvoMasterHub"] = true,
        ["RoubeUmOvoHub"] = true,
        ["EggTelemetryHub"] = true,
        ["MobileToggleBtn"] = true
    }
    local containers = {
        (gethui and gethui()),
        Services.CoreGui,
        LocalPlayer:FindFirstChildOfClass("PlayerGui")
    }
    for _, container in ipairs(containers) do
        if container then
            pcall(function()
                for _, child in ipairs(container:GetChildren()) do
                    if names[child.Name] then
                        pcall(function()
                            if child:IsA("ScreenGui") then child.Enabled = false end
                            child:Destroy()
                            child.Parent = nil
                        end)
                    end
                end
            end)
        end
    end
end

-- Se uma versão anterior estava rodando, encerra completamente antes de recarregar
pcall(function()
    if _G.RoubeUmOvoUnload then
        _G.RoubeUmOvoUnload()
    end
    if getgenv and getgenv().RoubeUmOvoUnload then
        getgenv().RoubeUmOvoUnload()
    end
end)
purgeAllGuis()

pcall(function()
    if writefile then
        writefile(Telemetry.FileName, Services.HttpService:JSONEncode({
            type = "session_start",
            session = Telemetry.SessionId,
            placeId = game.PlaceId,
            jobId = game.JobId,
            player = LocalPlayer.Name,
            userId = LocalPlayer.UserId,
            version = "13.1",
        }) .. "\n")
    end
end)
task.spawn(function()
    while not State.IsUnloaded do
        task.wait(2)
        flushTelemetry()
    end
end)

-- Não desabilitar, destruir ou modificar scripts internos do personagem. Isso
-- causava dessincronização e podia acionar a recuperação/rejoin do próprio jogo.
registerConnection(LocalPlayer.CharacterAdded:Connect(function(newChar)
    if State.IsUnloaded then return end
    State.CarryConfirmed = false
    State.CarryEvidence = nil
    State.LastCarryChange = os.clock()
    traceEvent("CHARACTER", "CARRY_RESET_ON_RESPAWN", { character = newChar })
end))

local function addLog(category, msg)
    local timestamp = os.date("%H:%M:%S")
    local entry = string.format("[%s] [%s] %s", timestamp, category, msg)
    table.insert(State.Logs, 1, entry)
    if #State.Logs > 100 then table.remove(State.Logs) end
    traceEvent("UI_LOG", category, { message = msg })
    if _G.UpdateLogConsole then _G.UpdateLogConsole() end
end

local function getChar()
    return LocalPlayer.Character
end

local function getHRP()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function getHum()
    local c = LocalPlayer.Character
    return c and c:FindFirstChildWhichIsA("Humanoid")
end

-- 6. Detecção de Posse de Ovo — Estratégia de 3 Camadas (v11.0 — Sem Falso Positivo R15)
-- ============================================================================
-- NÃO verificamos mais BasePart soldadas genéricas (Motor6D, Weld, WeldConstraint)
-- porque partes do corpo R15 (Head com Neck, UpperTorso, etc.) disparam falso positivo.
-- NÃO verificamos mais PlayerGui.AssetEggData (também disparava falso positivo).
-- APENAS verificamos:
--   Camada 1: Atributos explícitos com "egg", "carry", "hold", "grab"
--   Camada 2: Tool equipada com "egg"/"ovo" no nome ou atributo IsEgg
--   Camada 3: Model soldado ao Character com "egg"/"ovo" no nome ou atributo IsEgg
-- ============================================================================
-- Sistema Oficial de Renda por Segundo ($/s) e Formatação de Valores
local function formatIncome(n)
    if not n or n <= 0 then return "$0/s" end
    local suffixes = {"", "k", "M", "B", "T", "Qa", "Qi"}
    local idx = 1
    local val = n
    while val >= 1000 and idx < #suffixes do
        val = val / 1000
        idx = idx + 1
    end
    if idx == 1 then
        return string.format("$%.0f/s", val)
    elseif val >= 100 then
        return string.format("$%.0f%s/s", val, suffixes[idx])
    else
        return string.format("$%.1f%s/s", val, suffixes[idx])
    end
end

local RarityBaseIncome = {
    ["COMMON"] = 3, ["COMUM"] = 3,
    ["UNCOMMON"] = 25, ["INCOMUM"] = 25,
    ["RARE"] = 250, ["RARO"] = 250,
    ["EPIC"] = 2500, ["ÉPICO"] = 2500,
    ["LEGENDARY"] = 25000, ["LENDÁRIO"] = 25000,
    ["MYTHIC"] = 250000, ["MÍTICO"] = 250000,
    ["COSMIC"] = 2500000, ["CÓSMICO"] = 2500000,
    ["SECRET"] = 25000000, ["SECRETO"] = 25000000,
    ["ETERNAL"] = 250000000, ["ETERNO"] = 250000000,
    ["DIVINE"] = 2500000000, ["DIVINO"] = 2500000000,
    ["TITAN"] = 25000000000, ["TITÃ"] = 25000000000
}

local PetBaseIncome = {
    ["chicken"] = 2, ["dog"] = 3, ["duckling"] = 4, ["frog"] = 4, ["jerboa"] = 5,
    ["catfish"] = 18, ["desertlark"] = 25, ["fennecfox"] = 35,
    ["burrowing owl"] = 180, ["camel"] = 220, ["chimpanzee"] = 250, ["dodo"] = 280, ["ash gecko"] = 300, ["parrotfish"] = 350, ["penguin"] = 400, ["raccoon"] = 450, ["toucan"] = 500, ["turtle"] = 550,
    ["bear"] = 1800, ["crocodile"] = 2200, ["crane"] = 2500, ["lava frog"] = 2800, ["mire fox"] = 3200, ["swordfish"] = 3600, ["tob tobi tob tob"] = 4000, ["trulimero trulicina"] = 4500, ["walrus"] = 5000, ["bananita dolphinita"] = 6000,
    ["crab"] = 18000, ["dream axolotl"] = 22000, ["flaming bull"] = 25000, ["finned thresher"] = 28000, ["galaxy gecko"] = 32000, ["gorilla"] = 35000, ["lava iguana"] = 40000, ["orangutini ananassini"] = 45000, ["polar bear"] = 50000, ["pterodactyl"] = 55000, ["rattlesnake"] = 60000, ["rift eye"] = 65000, ["salamander"] = 70000, ["void angler"] = 75000, ["brr brr patapim"] = 80000,
    ["ankylosaurus"] = 180000, ["belula beluga"] = 200000, ["blade head"] = 220000, ["chillin chilli"] = 250000, ["cyclops gorilla"] = 280000, ["deathstalkerscorpion"] = 300000, ["froggo"] = 350000, ["mammoth"] = 400000, ["orca"] = 450000, ["red panda"] = 500000, ["riftwing"] = 550000, ["sabertooth tiger"] = 600000, ["sand spider"] = 650000, ["shardling"] = 700000, ["shadow dragon"] = 750000, ["spider"] = 800000, ["tiger"] = 850000, ["voidmaw"] = 900000,
    ["alabaster whale"] = 1800000, ["basilisk"] = 2200000, ["bronto"] = 2500000, ["colossal mammoth"] = 2800000, ["crawler"] = 3200000, ["demon imp"] = 3500000, ["dreadclaw"] = 4000000, ["drill monster"] = 4500000, ["hellhound"] = 5000000, ["irihorus"] = 5500000, ["koi"] = 6000000, ["la vacca saturno saturnita"] = 6500000, ["mangolini parrochini"] = 7000000, ["mantis"] = 7500000, ["rhino"] = 8000000, ["shattered ram"] = 8500000, ["snowy owl"] = 9000000, ["triceratops"] = 9500000, ["ventinal"] = 10000000, ["whale shark"] = 12000000,
    ["abyss overlord"] = 18000000, ["alien skeleton boss"] = 22000000, ["bomboclat crocolat"] = 25000000, ["cave dragon"] = 30000000, ["cerberus"] = 35000000, ["crocodon"] = 40000000, ["ember dragon"] = 45000000, ["gargoyle"] = 50000000, ["kraken"] = 55000000, ["mawbreaker"] = 60000000, ["mecha crawler"] = 65000000, ["mecha froggo"] = 70000000, ["mecha scorpio"] = 75000000, ["minotaur"] = 80000000, ["scorcheddragon"] = 85000000, ["shardwing"] = 90000000, ["shark"] = 95000000, ["stag"] = 100000000, ["tralaledon"] = 110000000, ["tyrannosaurusrex"] = 120000000, ["warden"] = 130000000, ["wendigo"] = 140000000, ["yeti"] = 150000000,
    ["ascended vermilion phoenix"] = 180000000, ["balrog"] = 220000000, ["dragon"] = 250000000, ["el maja"] = 280000000, ["eternal lunar dragon"] = 320000000, ["ice dragon"] = 350000000, ["king kong"] = 400000000, ["krakenoid"] = 450000000, ["mecha crocodon"] = 500000000, ["mecha krakenoid"] = 550000000, ["mosasaurus"] = 600000000, ["oni tiger"] = 650000000, ["shattered drake"] = 700000000, ["strawberry elephant"] = 750000000, ["void dragon"] = 800000000, ["void serpent"] = 850000000, ["world eater"] = 900000000,
    ["archdemon dragon"] = 1800000000, ["dreadscale"] = 2200000000, ["godzilla"] = 3500000000, ["kitsune"] = 4000000000, ["mecha dreadscale"] = 5000000000, ["shattered colossus"] = 6000000000, ["unicorn"] = 8000000000,
    ["kaiju spider"] = 12000000000
}

local standardLimbNames = {
    ["head"] = true, ["uppertorso"] = true, ["lowertorso"] = true,
    ["leftupperarm"] = true, ["rightupperarm"] = true, ["leftlowerarm"] = true,
    ["rightlowerarm"] = true, ["lefthand"] = true, ["righthand"] = true,
    ["leftupperleg"] = true, ["rightupperleg"] = true, ["leftlowerleg"] = true,
    ["rightlowerleg"] = true, ["leftfoot"] = true, ["rightfoot"] = true,
    ["humanoidrootpart"] = true, ["torso"] = true,
    ["left arm"] = true, ["right arm"] = true, ["left leg"] = true, ["right leg"] = true,
    ["animate"] = true, ["humanoid"] = true, ["health"] = true
}

-- 6. Detecção de Posse de Ovo Ultra-Confiável (Multi-Camada)
local getPositionOf
local boundCarryRemotes = {}
local function bindCarryStateRemote(carryStateRemote)
    if not carryStateRemote or not carryStateRemote:IsA("RemoteEvent") or boundCarryRemotes[carryStateRemote] then return end
    boundCarryRemotes[carryStateRemote] = true
    registerConnection(carryStateRemote.OnClientEvent:Connect(function(...)
        local args = table.pack(...)
        local belongsToLocalPlayer = true
        local explicitlyScoped = false
        local carrying = nil
        local evidence = nil

        traceEvent("CARRY_REMOTE", instancePath(carryStateRemote), { args = args })

        for index = 1, args.n do
            local value = args[index]
            if typeof(value) == "Instance" and value:IsA("Player") then
                explicitlyScoped = true
                belongsToLocalPlayer = value == LocalPlayer
            elseif typeof(value) == "Instance" then
                evidence = value.Name
            elseif type(value) == "boolean" then
                carrying = value
            elseif type(value) == "number" then
                local eventPlayer = Services.Players:GetPlayerByUserId(value)
                if eventPlayer then
                    explicitlyScoped = true
                    belongsToLocalPlayer = eventPlayer == LocalPlayer
                end
            elseif type(value) == "string" and #value >= 8
                and value ~= LocalPlayer.Name and value ~= LocalPlayer.DisplayName then
                evidence = value
            elseif type(value) == "table" then
                local owner = value.Player or value.Owner or value.UserId or value.PlayerId
                if owner ~= nil then
                    explicitlyScoped = true
                    belongsToLocalPlayer = owner == LocalPlayer
                        or tostring(owner) == tostring(LocalPlayer.UserId)
                        or tostring(owner) == LocalPlayer.Name
                end
                local tableState = value.IsCarrying
                if tableState == nil then tableState = value.Carrying end
                if tableState == nil then tableState = value.Holding end
                if type(tableState) == "boolean" then carrying = tableState end
                evidence = value.EggUid or value.EggUID or value.Uid or value.UID or evidence
            end
        end

        if carrying == nil then
            if evidence ~= nil then
                carrying = true
            elseif args.n == 0 then
                carrying = false
            end
        end

        -- Alguns servidores transmitem o evento sem Player. Só aceitar um evento
        -- positivo sem dono enquanto acabamos de acionar um ovo; isso impede que
        -- a coleta de outro jogador vire um falso carry local.
        local isExpectedWindow = os.clock() <= (State.ExpectCarryUntil or 0)
        local canApply = belongsToLocalPlayer and (explicitlyScoped or isExpectedWindow)
        if canApply and carrying ~= nil then
            State.CarryConfirmed = carrying
            State.CarryEvidence = carrying and tostring(evidence or "AreaEggCarryStateChanged") or nil
            State.LastCarryChange = os.clock()
            traceEvent("CARRY_STATE", carrying and "ACQUIRED" or "RELEASED", {
                evidence = State.CarryEvidence,
                explicitlyScoped = explicitlyScoped,
                expectedWindow = isExpectedWindow,
            })
        end
    end))
end

for _, desc in ipairs(Services.ReplicatedStorage:GetDescendants()) do
    if desc.Name == "AreaEggCarryStateChanged" then bindCarryStateRemote(desc) end
end
registerConnection(Services.ReplicatedStorage.DescendantAdded:Connect(function(desc)
    if desc.Name == "AreaEggCarryStateChanged" then bindCarryStateRemote(desc) end
end))

local function isHoldingEggRaw()
    local char = LocalPlayer.Character
    if not char then return false, nil end

    local function isValidEggUid(value)
        if type(value) ~= "string" then return false end
        local uid = value:match("^%s*(.-)%s*$")
        return #uid >= 4
            and uid:match("^[%w_%-]+$") ~= nil
            and uid:match("%a") ~= nil
            and uid:match("%d") ~= nil
    end

    -- Camada 1: nomes exatos. Nunca procurar por "uid", "carry" ou "hold".
    for _, target in ipairs({char, LocalPlayer}) do
        if target:GetAttribute("CarryingEgg") == true then
            return true, target.Name .. ".CarryingEgg"
        end
        if target:GetAttribute("HoldEgg") == true then
            return true, target.Name .. ".HoldEgg"
        end
        if target:GetAttribute("IsCarrying") == true then
            return true, target.Name .. ".IsCarrying"
        end
        local eggUid = target:GetAttribute("EggUid")
        if isValidEggUid(eggUid) then
            return true, target.Name .. ".EggUid=" .. eggUid
        end
    end

    if State.CarryConfirmed == true then
        if os.clock() - (State.LastCarryChange or 0) <= 12 then
            return true, State.CarryEvidence or "AreaEggCarryStateChanged"
        end
        traceEvent("CARRY_STATE", "STALE_CLEARED", { evidence = State.CarryEvidence })
        State.CarryConfirmed = false
        State.CarryEvidence = nil
    end

    -- Backpack é inventário, não mãos. Somente Tool equipada conta.
    for _, item in ipairs(char:GetChildren()) do
        if item:IsA("Tool") then
            local toolName = item.Name:lower()
            if toolName:find("egg", 1, true) or toolName:find("ovo", 1, true)
                or item:GetAttribute("IsEgg") == true or item:GetAttribute("EggType") ~= nil then
                return true, item.Name
            end
        end
    end

    local rightHand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
    local function explicitlyLooksLikeEgg(obj)
        local current = obj
        while current and current ~= char do
            local low = current.Name:lower()
            if low:find("egg", 1, true) or low:find("ovo", 1, true)
                or current:GetAttribute("IsEgg") == true or current:GetAttribute("EggType") ~= nil then
                return true, current.Name
            end
            current = current.Parent
        end
        return false, nil
    end

    -- Camada 3: ligação específica à mão direita + identidade explícita de ovo.
    if rightHand then
        for _, joint in ipairs(char:GetDescendants()) do
            if joint:IsA("Weld") or joint:IsA("WeldConstraint") or joint:IsA("Motor6D") then
                local otherPart = nil
                if joint.Part0 == rightHand then
                    otherPart = joint.Part1
                elseif joint.Part1 == rightHand then
                    otherPart = joint.Part0
                end
                if otherPart and otherPart ~= rightHand
                    and not standardLimbNames[otherPart.Name:lower()]
                    and not otherPart:FindFirstAncestorOfClass("Accessory")
                    and not otherPart:FindFirstAncestorOfClass("Tool") then
                    local isEgg, eggName = explicitlyLooksLikeEgg(otherPart)
                    if isEgg then return true, eggName end
                end
            end
        end
    end

    return false, nil
end

local function isHoldingEgg()
    local holding, evidence = isHoldingEggRaw()
    if holding ~= State.LastHoldingResult or tostring(evidence) ~= tostring(State.LastHoldingEvidence) then
        State.LastHoldingResult = holding
        State.LastHoldingEvidence = evidence
        traceEvent("CARRY_CHECK", holding and "TRUE" or "FALSE", { evidence = evidence })
    end
    return holding, evidence
end

-- Instrumentação passiva: remotes, inventário, personagem, prompts e slots.
-- Nenhum desses listeners altera o estado do jogo.
local TRACE_REMOTE_KEYWORDS = {
    "egg", "ovo", "carry", "place", "drop", "hatch", "pet", "fuse",
    "fusion", "sell", "trade", "inventory", "treadmill", "steal", "take",
}
local function isRelevantRemote(remote, args)
    local haystack = instancePath(remote):lower()
    for _, keyword in ipairs(TRACE_REMOTE_KEYWORDS) do
        if haystack:find(keyword, 1, true) then return true end
    end
    if type(args) == "table" then
        for index = 1, math.min(args.n or #args, 4) do
            if type(args[index]) == "string" then
                local value = args[index]:lower()
                for _, keyword in ipairs(TRACE_REMOTE_KEYWORDS) do
                    if value:find(keyword, 1, true) then return true end
                end
            end
        end
    end
    return false
end

local observedRemoteEvents = {}
local function observeRemoteEvent(remote)
    if not remote:IsA("RemoteEvent") or observedRemoteEvents[remote] then return end
    observedRemoteEvents[remote] = true
    registerConnection(remote.OnClientEvent:Connect(function(...)
        local args = table.pack(...)
        if not isRelevantRemote(remote, args) then return end
        task.defer(function()
            learnEggMetadataFromArgs(instancePath(remote), args)
            traceEvent("REMOTE_IN", instancePath(remote), { args = args })
        end)
    end))
end

for _, desc in ipairs(Services.ReplicatedStorage:GetDescendants()) do
    if desc:IsA("RemoteEvent") then observeRemoteEvent(desc) end
end
registerConnection(Services.ReplicatedStorage.DescendantAdded:Connect(function(desc)
    if desc:IsA("RemoteEvent") then
        traceEvent("REMOTE_DISCOVERED", instancePath(desc), { class = desc.ClassName })
        observeRemoteEvent(desc)
    end
end))

-- Não instalar hook em __namecall. Além do custo alto, alguns clientes tratam
-- essa alteração como corrupção da sessão e acionam rejoin. As respostas dos
-- remotes relevantes continuam sendo observadas por OnClientEvent.

local function observeContainer(container, category)
    if not container then return end
    registerConnection(container.ChildAdded:Connect(function(child)
        traceEvent(category, "CHILD_ADDED", { child = child })
    end))
    registerConnection(container.ChildRemoved:Connect(function(child)
        traceEvent(category, "CHILD_REMOVED", { child = child })
    end))
end

local function observeCharacter(char)
    if not char then return end
    observeContainer(char, "CHARACTER")
    registerConnection(char.AttributeChanged:Connect(function(attribute)
        traceEvent("ATTRIBUTE", instancePath(char), {
            attribute = attribute,
            value = char:GetAttribute(attribute),
        })
    end))
end

observeCharacter(LocalPlayer.Character)
registerConnection(LocalPlayer.CharacterAdded:Connect(function(char)
    traceEvent("CHARACTER", "RESPAWN", { character = char })
    task.wait(0.2)
    observeCharacter(char)
end))
observeContainer(LocalPlayer:FindFirstChildOfClass("Backpack"), "BACKPACK")
registerConnection(LocalPlayer.AttributeChanged:Connect(function(attribute)
    traceEvent("ATTRIBUTE", instancePath(LocalPlayer), {
        attribute = attribute,
        value = LocalPlayer:GetAttribute(attribute),
    })
end))

for _, folderName in ipairs({"AreaEggSlotsClient", "PlacedEggRenders", "ClientRenderedAssets", "__ClientTreadmillRenders"}) do
    local folder = Services.Workspace:FindFirstChild(folderName)
    if folder then observeContainer(folder, "WORLD_" .. folderName:upper()) end
end

registerConnection(Services.Workspace.DescendantAdded:Connect(function(desc)
    if desc:IsA("ProximityPrompt") then
        traceEvent("PROMPT", "ADDED", {
            prompt = desc,
            actionText = desc.ActionText,
            objectText = desc.ObjectText,
            enabled = desc.Enabled,
        })
    end
end))

for eventName, signal in pairs({
    SHOWN = Services.ProximityPromptService.PromptShown,
    HIDDEN = Services.ProximityPromptService.PromptHidden,
    TRIGGERED = Services.ProximityPromptService.PromptTriggered,
    TRIGGER_ENDED = Services.ProximityPromptService.PromptTriggerEnded,
}) do
    registerConnection(signal:Connect(function(prompt)
        traceEvent("PROMPT_LIFECYCLE", eventName, {
            prompt = prompt,
            actionText = prompt and prompt.ActionText,
            objectText = prompt and prompt.ObjectText,
            position = prompt and getPositionOf(prompt),
        })
    end))
end

task.spawn(function()
    while not State.IsUnloaded do
        task.wait(10)
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local tools = {}
        if char then
            for _, child in ipairs(char:GetChildren()) do
                if child:IsA("Tool") then table.insert(tools, "equipped:" .. child.Name) end
            end
        end
        local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        if backpack then
            for _, child in ipairs(backpack:GetChildren()) do
                if child:IsA("Tool") then table.insert(tools, "backpack:" .. child.Name) end
            end
        end
        traceEvent("SNAPSHOT", "PLAYER", {
            position = hrp and hrp.Position,
            velocity = hrp and hrp.AssemblyLinearVelocity,
            health = hum and hum.Health,
            humanoidState = hum and hum:GetState(),
            tools = tools,
            carrying = State.CarryConfirmed,
            carryEvidence = State.CarryEvidence,
        })
    end
end)

local function plainText(v)
    return tostring(v or ""):gsub("<[^>]->", ""):lower()
end

getPositionOf = function(obj)
    if not obj then return nil end
    if obj:IsA("ProximityPrompt") then
        local p = obj.Parent
        if p and p:IsA("Attachment") then p = p.Parent end
        if not p then return nil end
        if p:IsA("BasePart") then return p.Position end
        if p:IsA("Model") then return p:GetPivot().Position end
        local bp = p:FindFirstChildWhichIsA("BasePart", true)
        return bp and bp.Position or nil
    end
    if obj:IsA("BasePart") then return obj.Position end
    if obj:IsA("Model") then return obj:GetPivot().Position end
    local part = obj:FindFirstChildWhichIsA("BasePart", true)
    return part and part.Position or nil
end

-- 7. BANCO DE DADOS EMBUTIDO DE 118 PETS E OVOS DO JOGO
local KnownPetsCatalog = {
    ["sand spider"] = { DisplayName = "Sand Spider", Rarity = "MYTHIC" },
    ["orangutini ananassini"] = { DisplayName = "Orangutini Ananassini", Rarity = "LEGENDARY" },
    ["tung tung sahur"] = { DisplayName = "Tung Tung Sahur", Rarity = "RARE" },
    ["gorilla"] = { DisplayName = "Gorilla", Rarity = "LEGENDARY" },
    ["yeti"] = { DisplayName = "Yeti", Rarity = "SECRET" },
    ["crawler"] = { DisplayName = "Crawler", Rarity = "COSMIC" },
    ["kraken"] = { DisplayName = "Kraken", Rarity = "SECRET" },
    ["alien skeleton boss"] = { DisplayName = "Cosmic Skeleton Boss", Rarity = "SECRET" },
    ["spider"] = { DisplayName = "Spider", Rarity = "MYTHIC" },
    ["finned thresher"] = { DisplayName = "Shark", Rarity = "LEGENDARY" },
    ["walrus"] = { DisplayName = "Walrus", Rarity = "EPIC" },
    ["warden"] = { DisplayName = "King Snake", Rarity = "SECRET" },
    ["minotaur"] = { DisplayName = "Minotaur", Rarity = "SECRET" },
    ["crane"] = { DisplayName = "Crane", Rarity = "EPIC" },
    ["raccoon"] = { DisplayName = "Raccoon", Rarity = "RARE" },
    ["jerboa"] = { DisplayName = "Jerboa", Rarity = "COMMON" },
    ["lava iguana"] = { DisplayName = "Lava Iguana", Rarity = "LEGENDARY" },
    ["frog"] = { DisplayName = "Frog", Rarity = "COMMON" },
    ["deathstalkerscorpion"] = { DisplayName = "Scorpion", Rarity = "MYTHIC" },
    ["sabertooth tiger"] = { DisplayName = "Sabertooth Tiger", Rarity = "MYTHIC" },
    ["irihorus"] = { DisplayName = "Royal Sphinx", Rarity = "COSMIC" },
    ["blade head"] = { DisplayName = "Bladehide", Rarity = "MYTHIC" },
    ["gargoyle"] = { DisplayName = "Gargoyle", Rarity = "SECRET" },
    ["eternal lunar dragon"] = { DisplayName = "Eternal Lunar Dragon", Rarity = "ETERNAL" },
    ["catfish"] = { DisplayName = "Catfish", Rarity = "UNCOMMON" },
    ["swan"] = { DisplayName = "Swan", Rarity = "EPIC" },
    ["hellhound"] = { DisplayName = "Hellhound", Rarity = "COSMIC" },
    ["bear"] = { DisplayName = "Bear", Rarity = "EPIC" },
    ["tiger"] = { DisplayName = "Tiger", Rarity = "MYTHIC" },
    ["scorcheddragon"] = { DisplayName = "Scorched Dragon", Rarity = "SECRET" },
    ["mecha scorpio"] = { DisplayName = "Mecha Scorpio", Rarity = "SECRET" },
    ["penguin"] = { DisplayName = "Penguin", Rarity = "RARE" },
    ["camel"] = { DisplayName = "Camel", Rarity = "RARE" },
    ["flaming bull"] = { DisplayName = "Flaming Bull", Rarity = "LEGENDARY" },
    ["centapede"] = { DisplayName = "Centapede", Rarity = "EPIC" },
    ["mangolini parrochini"] = { DisplayName = "Mangolini Parrochini", Rarity = "COSMIC" },
    ["shadow dragon"] = { DisplayName = "Shadow Dragon", Rarity = "MYTHIC" },
    ["colossal mammoth"] = { DisplayName = "King Mammoth", Rarity = "COSMIC" },
    ["kaiju spider"] = { DisplayName = "Spideron", Rarity = "LEGENDARY" },
    ["bomboclat crocolat"] = { DisplayName = "Bombo Croco", Rarity = "SECRET" },
    ["archdemon dragon"] = { DisplayName = "Archdemon Dragon", Rarity = "DIVINE" },
    ["mire fox"] = { DisplayName = "Fox", Rarity = "EPIC" },
    ["el maja"] = { DisplayName = "El Maja", Rarity = "ETERNAL" },
    ["cave dragon"] = { DisplayName = "Cosmic Dragon", Rarity = "SECRET" },
    ["burrowing owl"] = { DisplayName = "Burrowing Owl", Rarity = "RARE" },
    ["krakenoid"] = { DisplayName = "Krakenoid", Rarity = "ETERNAL" },
    ["shark"] = { DisplayName = "Mutant Shark", Rarity = "SECRET" },
    ["drill monster"] = { DisplayName = "Drilla", Rarity = "COSMIC" },
    ["demon imp"] = { DisplayName = "Demon Imp", Rarity = "COSMIC" },
    ["crocodile"] = { DisplayName = "Crocodile", Rarity = "EPIC" },
    ["chillin chilli"] = { DisplayName = "Chillin Chilli", Rarity = "MYTHIC" },
    ["koi"] = { DisplayName = "Koi", Rarity = "COSMIC" },
    ["trulimero trulicina"] = { DisplayName = "Trulimero Trulicina", Rarity = "EPIC" },
    ["tyrannosaurusrex"] = { DisplayName = "TRex", Rarity = "SECRET" },
    ["duckling"] = { DisplayName = "Duckling", Rarity = "COMMON" },
    ["whale shark"] = { DisplayName = "Whale Shark", Rarity = "COSMIC" },
    ["la vacca saturno saturnita"] = { DisplayName = "La Vacca Saturno Saturnita", Rarity = "COSMIC" },
    ["crocodon"] = { DisplayName = "Crocodon", Rarity = "SECRET" },
    ["galaxy gecko"] = { DisplayName = "Cosmic Gecko", Rarity = "LEGENDARY" },
    ["dreadscale"] = { DisplayName = "Dreadscale", Rarity = "DIVINE" },
    ["triceratops"] = { DisplayName = "Triceratops", Rarity = "COSMIC" },
    ["rattlesnake"] = { DisplayName = "Snake", Rarity = "LEGENDARY" },
    ["dragon"] = { DisplayName = "Lava Dragon", Rarity = "ETERNAL" },
    ["tob tobi tob tob"] = { DisplayName = "Tob Tobi Tob Tob", Rarity = "EPIC" },
    ["scorpio"] = { DisplayName = "Scorpio", Rarity = "LEGENDARY" },
    ["pterodactyl"] = { DisplayName = "Pterodactyl", Rarity = "LEGENDARY" },
    ["polar bear"] = { DisplayName = "Polar Bear", Rarity = "LEGENDARY" },
    ["ember dragon"] = { DisplayName = "Ember Dragon", Rarity = "SECRET" },
    ["parrotfish"] = { DisplayName = "Parrotfish", Rarity = "RARE" },
    ["orca"] = { DisplayName = "Orca", Rarity = "MYTHIC" },
    ["mecha dreadscale"] = { DisplayName = "Mecha Dreadscale", Rarity = "DIVINE" },
    ["ascended vermilion phoenix"] = { DisplayName = "Phoenix", Rarity = "ETERNAL" },
    ["rhino"] = { DisplayName = "Rhinotaur", Rarity = "COSMIC" },
    ["king kong"] = { DisplayName = "Gorilla King", Rarity = "ETERNAL" },
    ["void dragon"] = { DisplayName = "Void Dragon", Rarity = "ETERNAL" },
    ["mecha froggo"] = { DisplayName = "Mecha Froggo", Rarity = "SECRET" },
    ["bananita dolphinita"] = { DisplayName = "Bananita Dolphinita", Rarity = "EPIC" },
    ["dog"] = { DisplayName = "Dog", Rarity = "COMMON" },
    ["alabaster whale"] = { DisplayName = "Beluga Whale", Rarity = "COSMIC" },
    ["bronto"] = { DisplayName = "Bronto", Rarity = "COSMIC" },
    ["mecha crocodon"] = { DisplayName = "Mecha Crocodon", Rarity = "ETERNAL" },
    ["baby aurora dragon"] = { DisplayName = "Baby Aurora Dragon", Rarity = "LEGENDARY" },
    ["ash gecko"] = { DisplayName = "Lava Gecko", Rarity = "RARE" },
    ["swordfish"] = { DisplayName = "Swordfish", Rarity = "EPIC" },
    ["strawberry elephant"] = { DisplayName = "Strawberry Elephant", Rarity = "ETERNAL" },
    ["mammoth"] = { DisplayName = "Mammoth", Rarity = "MYTHIC" },
    ["cerberus"] = { DisplayName = "Cerberus", Rarity = "SECRET" },
    ["cyclops gorilla"] = { DisplayName = "Cosmic Gorilla", Rarity = "MYTHIC" },
    ["mecha krakenoid"] = { DisplayName = "Mecha Krakenoid", Rarity = "ETERNAL" },
    ["stag"] = { DisplayName = "Stag", Rarity = "SECRET" },
    ["red panda"] = { DisplayName = "Red Panda", Rarity = "MYTHIC" },
    ["salamander"] = { DisplayName = "Salamander", Rarity = "LEGENDARY" },
    ["unicorn"] = { DisplayName = "Unicorn", Rarity = "DIVINE" },
    ["chimpanzee"] = { DisplayName = "Chimpanzee", Rarity = "RARE" },
    ["oni tiger"] = { DisplayName = "Oni Tiger", Rarity = "ETERNAL" },
    ["dodo"] = { DisplayName = "Dodo", Rarity = "RARE" },
    ["mosasaurus"] = { DisplayName = "Mosasaurus", Rarity = "ETERNAL" },
    ["mecha crawler"] = { DisplayName = "Mecha Crawler", Rarity = "SECRET" },
    ["ankylosaurus"] = { DisplayName = "Ankylosaurus", Rarity = "MYTHIC" },
    ["dream axolotl"] = { DisplayName = "Axolotl", Rarity = "LEGENDARY" },
    ["belula beluga"] = { DisplayName = "Belula Beluga", Rarity = "MYTHIC" },
    ["basilisk"] = { DisplayName = "Leviathan", Rarity = "COSMIC" },
    ["godzilla"] = { DisplayName = "Nightflame", Rarity = "DIVINE" },
    ["ice dragon"] = { DisplayName = "Ice Dragon", Rarity = "ETERNAL" },
    ["fennecfox"] = { DisplayName = "Fennec", Rarity = "UNCOMMON" },
    ["mantis"] = { DisplayName = "Mantaris", Rarity = "COSMIC" },
    ["chicken"] = { DisplayName = "Chicken", Rarity = "COMMON" },
    ["snowy owl"] = { DisplayName = "Snowy Owl", Rarity = "COSMIC" },
    ["balrog"] = { DisplayName = "Balrog", Rarity = "ETERNAL" },
    ["brr brr patapim"] = { DisplayName = "Brr Brr Patapim", Rarity = "LEGENDARY" },
    ["crab"] = { DisplayName = "Crustacia", Rarity = "LEGENDARY" },
    ["lava frog"] = { DisplayName = "Lava frog", Rarity = "EPIC" },
    ["desertlark"] = { DisplayName = "Bird", Rarity = "UNCOMMON" },
    ["tralaledon"] = { DisplayName = "Tralaledon", Rarity = "SECRET" },
    ["toucan"] = { DisplayName = "Toucan", Rarity = "RARE" },
    ["turtle"] = { DisplayName = "Turtle", Rarity = "RARE" },
    ["kitsune"] = { DisplayName = "Kitsune", Rarity = "DIVINE" },
    ["froggo"] = { DisplayName = "Froggo", Rarity = "MYTHIC" },
}

-- 7.1. BANCO DE DADOS DAS 11 ILHAS OFICIAIS — 8 PETS POR ILHA (Drop Tables Oficiais v11.0)
local OfficialIslands = {
    {
        Id = "Forest",
        Name = "Floresta (Ilha 1)",
        MinX = 520, MaxX = 670,
        BaseZ = -328,
        Rarity = "COMUM",
        Score = 300,
        TopDrop = "Brr Brr Patapim",
        EggShell = "Ovo da Floresta",
        Guard = "Forest Guard",
        SlotPets = {
            [1] = { Name = "Galinha (Chicken)", Rarity = "COMUM", Score = 300 },
            [2] = { Name = "Cachorro (Dog)", Rarity = "COMUM", Score = 300 },
            [3] = { Name = "Pássaro (DesertLark)", Rarity = "INCOMUM", Score = 1500 },
            [4] = { Name = "Coruja Escavadora (Burrowing Owl)", Rarity = "RARO", Score = 3500 },
            [5] = { Name = "Guaxinim (Raccoon)", Rarity = "RARO", Score = 3500 },
            [6] = { Name = "Raposa do Pântano (Mire Fox)", Rarity = "ÉPICO", Score = 8000 },
            [7] = { Name = "Urso (Bear)", Rarity = "ÉPICO", Score = 8000 },
            [8] = { Name = "Brr Brr Patapim", Rarity = "LENDÁRIO", Score = 15000 }
        }
    },
    {
        Id = "Lake",
        Name = "Lago (Ilha 2)",
        MinX = 671, MaxX = 850,
        BaseZ = -410,
        Rarity = "INCOMUM",
        Score = 1500,
        TopDrop = "Basilisk",
        EggShell = "Ovo do Lago",
        Guard = "Lake Guard",
        SlotPets = {
            [1] = { Name = "Sapo (Frog)", Rarity = "COMUM", Score = 300 },
            [2] = { Name = "Patinho (Duckling)", Rarity = "COMUM", Score = 300 },
            [3] = { Name = "Peixe-Gato (Catfish)", Rarity = "INCOMUM", Score = 1500 },
            [4] = { Name = "Tartaruga (Turtle)", Rarity = "RARO", Score = 3500 },
            [5] = { Name = "Trulimero Trulicina", Rarity = "ÉPICO", Score = 8000 },
            [6] = { Name = "Cisne (Swan)", Rarity = "ÉPICO", Score = 8000 },
            [7] = { Name = "Axolotl (Dream Axolotl)", Rarity = "LENDÁRIO", Score = 15000 },
            [8] = { Name = "Leviatã (Basilisk)", Rarity = "COSMIC", Score = 30000 }
        }
    },
    {
        Id = "Desert",
        Name = "Deserto (Ilha 3)",
        MinX = 851, MaxX = 1080,
        BaseZ = -325,
        Rarity = "RARO",
        Score = 3500,
        TopDrop = "Irihorus",
        EggShell = "Ovo do Deserto",
        Guard = "Desert Guard",
        SlotPets = {
            [1] = { Name = "Jerboa", Rarity = "COMUM", Score = 300 },
            [2] = { Name = "Feneco (FennecFox)", Rarity = "INCOMUM", Score = 1500 },
            [3] = { Name = "Camelo (Camel)", Rarity = "RARO", Score = 3500 },
            [4] = { Name = "Tob Tobi Tob Tob", Rarity = "ÉPICO", Score = 8000 },
            [5] = { Name = "Cobra Coral (Rattlesnake)", Rarity = "LENDÁRIO", Score = 15000 },
            [6] = { Name = "Aranha da Areia (Sand Spider)", Rarity = "MÍTICO", Score = 20000 },
            [7] = { Name = "Escorpião (DeathstalkerScorpion)", Rarity = "MÍTICO", Score = 20000 },
            [8] = { Name = "Esfinge Real (Irihorus)", Rarity = "COSMIC", Score = 30000 }
        }
    },
    {
        Id = "Jungle",
        Name = "Selva (Ilha 4)",
        MinX = 1081, MaxX = 1350,
        BaseZ = -410,
        Rarity = "ÉPICO",
        Score = 8000,
        TopDrop = "Warden",
        EggShell = "Ovo da Selva",
        Guard = "Jungle Guard",
        SlotPets = {
            [1] = { Name = "Chimpanzé (Chimpanzee)", Rarity = "RARO", Score = 3500 },
            [2] = { Name = "Tucano (Toucan)", Rarity = "RARO", Score = 3500 },
            [3] = { Name = "Crocodilo (Crocodile)", Rarity = "ÉPICO", Score = 8000 },
            [4] = { Name = "Gorila (Gorilla)", Rarity = "LENDÁRIO", Score = 15000 },
            [5] = { Name = "Orangutango (Orangutini Ananassini)", Rarity = "LENDÁRIO", Score = 15000 },
            [6] = { Name = "Aranha (Spider)", Rarity = "MÍTICO", Score = 20000 },
            [7] = { Name = "Tigre Real (Tiger)", Rarity = "MÍTICO", Score = 20000 },
            [8] = { Name = "Rei Cobra (Warden)", Rarity = "SECRET", Score = 45000 }
        }
    },
    {
        Id = "Snow",
        Name = "Neve (Ilha 5)",
        MinX = 1351, MaxX = 1680,
        BaseZ = -315,
        Rarity = "LENDÁRIO",
        Score = 15000,
        TopDrop = "Ice Dragon",
        EggShell = "Ovo da Neve",
        Guard = "Snow Guard",
        SlotPets = {
            [1] = { Name = "Pinguim (Penguin)", Rarity = "RARO", Score = 3500 },
            [2] = { Name = "Morsa (Walrus)", Rarity = "ÉPICO", Score = 8000 },
            [3] = { Name = "Urso Polar (Polar Bear)", Rarity = "LENDÁRIO", Score = 15000 },
            [4] = { Name = "Tigre Dentes-de-Sabre (Sabertooth Tiger)", Rarity = "MÍTICO", Score = 20000 },
            [5] = { Name = "Mamute (Mammoth)", Rarity = "MÍTICO", Score = 20000 },
            [6] = { Name = "Mamute Colossal (Colossal Mammoth)", Rarity = "COSMIC", Score = 30000 },
            [7] = { Name = "Yeti das Neves", Rarity = "SECRET", Score = 45000 },
            [8] = { Name = "Dragão de Gelo (Ice Dragon)", Rarity = "ETERNAL", Score = 70000 }
        }
    },
    {
        Id = "Volcano",
        Name = "Vulcão (Ilha 6)",
        MinX = 1681, MaxX = 2080,
        BaseZ = -400,
        Rarity = "MÍTICO",
        Score = 20000,
        TopDrop = "Dragon",
        EggShell = "Ovo do Vulcão",
        Guard = "Volcano Guard",
        SlotPets = {
            [1] = { Name = "Geco de Cinzas (Ash Gecko)", Rarity = "RARO", Score = 3500 },
            [2] = { Name = "Sapo de Lava (Lava Frog)", Rarity = "ÉPICO", Score = 8000 },
            [3] = { Name = "Touro Flamejante (Flaming Bull)", Rarity = "LENDÁRIO", Score = 15000 },
            [4] = { Name = "Iguana de Lava (Lava Iguana)", Rarity = "LENDÁRIO", Score = 15000 },
            [5] = { Name = "Chillin Chilli", Rarity = "MÍTICO", Score = 20000 },
            [6] = { Name = "Cérbero (Cerberus)", Rarity = "SECRET", Score = 45000 },
            [7] = { Name = "Fênix Vermilhão (Ascended Vermilion Phoenix)", Rarity = "ETERNAL", Score = 70000 },
            [8] = { Name = "Dragão de Lava (Dragon)", Rarity = "ETERNAL", Score = 70000 }
        }
    },
    {
        Id = "Abyss Ocean",
        Name = "Oceano do Abismo (Ilha 7)",
        MinX = 2081, MaxX = 2550,
        BaseZ = -328,
        Rarity = "COSMIC",
        Score = 30000,
        TopDrop = "El Maja",
        EggShell = "Ovo do Abismo",
        Guard = "Abyss Ocean Guard",
        SlotPets = {
            [1] = { Name = "Peixe-Papagaio (Parrotfish)", Rarity = "RARO", Score = 3500 },
            [2] = { Name = "Peixe-Espada (Swordfish)", Rarity = "ÉPICO", Score = 8000 },
            [3] = { Name = "Tubarão (Finned Thresher)", Rarity = "LENDÁRIO", Score = 15000 },
            [4] = { Name = "Orca Assassina (Orca)", Rarity = "MÍTICO", Score = 20000 },
            [5] = { Name = "Tubarão Baleia (Whale Shark)", Rarity = "COSMIC", Score = 30000 },
            [6] = { Name = "Baleia Alabaster (Alabaster Whale)", Rarity = "COSMIC", Score = 30000 },
            [7] = { Name = "Kraken", Rarity = "SECRET", Score = 45000 },
            [8] = { Name = "El Maja", Rarity = "ETERNAL", Score = 70000 }
        }
    },
    {
        Id = "Prehistoric",
        Name = "Pré-Histórico (Ilha 8)",
        MinX = 2551, MaxX = 3100,
        BaseZ = -398,
        Rarity = "SECRET",
        Score = 45000,
        TopDrop = "Mosasaurus",
        EggShell = "Ovo Pré-Histórico",
        Guard = "Prehistoric Guard",
        SlotPets = {
            [1] = { Name = "Dodô (Dodo)", Rarity = "RARO", Score = 3500 },
            [2] = { Name = "Pterodáctilo (Pterodactyl)", Rarity = "LENDÁRIO", Score = 15000 },
            [3] = { Name = "Anquilossauro (Ankylosaurus)", Rarity = "MÍTICO", Score = 20000 },
            [4] = { Name = "Tricerátops (Triceratops)", Rarity = "COSMIC", Score = 30000 },
            [5] = { Name = "Brontossauro (Bronto)", Rarity = "COSMIC", Score = 30000 },
            [6] = { Name = "T-Rex (TyrannosaurusRex)", Rarity = "SECRET", Score = 45000 },
            [7] = { Name = "Tralaledon", Rarity = "SECRET", Score = 45000 },
            [8] = { Name = "Mosassauro (Mosasaurus)", Rarity = "ETERNAL", Score = 70000 }
        }
    },
    {
        Id = "Cosmic",
        Name = "Cósmico (Ilha 9)",
        MinX = 3101, MaxX = 3700,
        BaseZ = -325,
        Rarity = "ETERNAL",
        Score = 70000,
        TopDrop = "Unicorn",
        EggShell = "Ovo Cósmico",
        Guard = "Cosmic Guard",
        SlotPets = {
            [1] = { Name = "Centopeia (Centapede)", Rarity = "ÉPICO", Score = 8000 },
            [2] = { Name = "Geco Cósmico (Galaxy Gecko)", Rarity = "LENDÁRIO", Score = 15000 },
            [3] = { Name = "Gorila Cósmico (Cyclops Gorilla)", Rarity = "MÍTICO", Score = 20000 },
            [4] = { Name = "La Vacca Saturno Saturnita", Rarity = "COSMIC", Score = 30000 },
            [5] = { Name = "Chefe Esqueleto Cósmico (Alien Skeleton Boss)", Rarity = "SECRET", Score = 45000 },
            [6] = { Name = "Dragão Cósmico (Cave Dragon)", Rarity = "SECRET", Score = 45000 },
            [7] = { Name = "Dragão Lunar Eterno (Eternal Lunar Dragon)", Rarity = "ETERNAL", Score = 70000 },
            [8] = { Name = "Unicórnio Divino (Unicorn)", Rarity = "DIVINE", Score = 100000 }
        }
    },
    {
        Id = "Cherry Blossom",
        Name = "Flor de Cerejeira (Ilha 10)",
        MinX = 3701, MaxX = 4400,
        BaseZ = -398,
        Rarity = "DIVINE",
        Score = 100000,
        TopDrop = "Kitsune",
        EggShell = "Ovo de Cerejeira",
        Guard = "Cherry Blossom Guard",
        SlotPets = {
            [1] = { Name = "Grou (Crane)", Rarity = "ÉPICO", Score = 8000 },
            [2] = { Name = "Salamandra (Salamander)", Rarity = "LENDÁRIO", Score = 15000 },
            [3] = { Name = "Panda Vermelho (Red Panda)", Rarity = "MÍTICO", Score = 20000 },
            [4] = { Name = "Coruja das Neves (Snowy Owl)", Rarity = "COSMIC", Score = 30000 },
            [5] = { Name = "Carpa Cósmica (Koi)", Rarity = "COSMIC", Score = 30000 },
            [6] = { Name = "Cervo Sagrado (Stag)", Rarity = "SECRET", Score = 45000 },
            [7] = { Name = "Tigre Oni (Oni Tiger)", Rarity = "ETERNAL", Score = 70000 },
            [8] = { Name = "Kitsune Ancestral (Kitsune)", Rarity = "DIVINE", Score = 100000 }
        }
    },
    {
        Id = "Titan Temple",
        Name = "Templo do Titã (Ilha 11)",
        MinX = 4401, MaxX = 99999,
        BaseZ = -328,
        Rarity = "TITAN",
        Score = 150000,
        TopDrop = "Godzilla",
        EggShell = "Ovo de Titã",
        Guard = "Titan Temple Guard",
        SlotPets = {
            [1] = { Name = "Caranguejo (Crab)", Rarity = "LENDÁRIO", Score = 15000 },
            [2] = { Name = "Aranha Titânica (Kaiju Spider)", Rarity = "LENDÁRIO", Score = 15000 },
            [3] = { Name = "Lâmina Oculta (Blade Head)", Rarity = "MÍTICO", Score = 20000 },
            [4] = { Name = "Louva-a-Deus (Mantis)", Rarity = "COSMIC", Score = 30000 },
            [5] = { Name = "Rinoceronte (Rhino)", Rarity = "COSMIC", Score = 30000 },
            [6] = { Name = "Tubarão Mutante (Shark)", Rarity = "SECRET", Score = 45000 },
            [7] = { Name = "King Kong (Gorilla King)", Rarity = "ETERNAL", Score = 70000 },
            [8] = { Name = "Godzilla (Nightflame)", Rarity = "TITAN", Score = 150000 }
        }
    }
}

local function getIslandByPos(pos)
    if not pos then return OfficialIslands[1] end
    if pos.X < 510 then
        return {
            Id = "Bases",
            Name = "Bases de Jogadores",
            Rarity = "COMUM",
            Score = 300,
            EggShell = "Ovo de Base"
        }
    end
    for _, isl in ipairs(OfficialIslands) do
        if pos.X >= isl.MinX and pos.X <= isl.MaxX then
            return isl
        end
    end
    if pos.X > 4400 then return OfficialIslands[11] end
    return OfficialIslands[1]
end

local function getIslandNameByPos(pos)
    local isl = getIslandByPos(pos)
    return isl and isl.Name or "Ilha Geral"
end

local function isEggInMyIsland(eggPos)
    if not Config.LockCurrentIsland then return true end
    local myHrp = getHRP()
    if not myHrp then return true end
    local myIsl = getIslandByPos(myHrp.Position)
    local eggIsl = getIslandByPos(eggPos)
    if myIsl.Id == "Bases" then
        return eggIsl.Id == "Bases" or eggIsl.Id == "Forest"
    end
    return myIsl.Id == eggIsl.Id
end

local RarityScoreMap = {
    ["TITAN"] = 150000,
    ["DIVINE"] = 100000,
    ["ADMIN ABUSE"] = 120000,
    ["EXCLUSIVE"] = 90000,
    ["MONSTER PARASITE"] = 85000,
    ["DRAGON"] = 75000,
    ["ETERNAL"] = 70000,
    ["BRAINROT"] = 65000,
    ["LIMITED"] = 60000,
    ["SECRET"] = 45000,
    ["COSMIC"] = 30000,
    ["RAINBOW"] = 25000,
    ["VOLCANO"] = 22000,
    ["MÍTICO"] = 20000,
    ["MYTHIC"] = 20000,
    ["MYTHICAL"] = 20000,
    ["GOLDEN"] = 18000,
    ["LENDÁRIO"] = 15000,
    ["LEGENDARY"] = 15000,
    ["CHERRY"] = 12000,
    ["ÉPICO"] = 8000,
    ["EPIC"] = 8000,
    ["FOREST"] = 5000,
    ["RARO"] = 3500,
    ["RARE"] = 3500,
    ["INCOMUM"] = 1500,
    ["UNCOMMON"] = 1500,
    ["COMUM"] = 300,
    ["COMMON"] = 300
}

learnEggMetadataFromArgs = function(source, args)
    local sourceLow = tostring(source):lower()
    if not (sourceLow:find("egg", 1, true) or sourceLow:find("ovo", 1, true)
        or sourceLow:find("carry", 1, true) or sourceLow:find("hatch", 1, true)
        or sourceLow:find("place", 1, true)) then
        return
    end

    local strings = {}
    local seen = {}
    local function collect(value, depth)
        if depth > 4 then return end
        if type(value) == "string" then
            table.insert(strings, value)
        elseif typeof(value) == "Instance" then
            table.insert(strings, value.Name)
            for _, attr in pairs(value:GetAttributes()) do collect(attr, depth + 1) end
        elseif type(value) == "table" and not seen[value] then
            seen[value] = true
            for key, child in pairs(value) do
                collect(key, depth + 1)
                collect(child, depth + 1)
            end
        end
    end
    collect(args, 0)

    local foundPet = nil
    local foundUid = nil
    local petMatches = {}
    local uidMatches = {}
    for _, text in ipairs(strings) do
        local normalized = text:lower():gsub("[_%-]+", " "):gsub("%s+", " ")
        for petKey, petData in pairs(KnownPetsCatalog) do
            if normalized == petKey or normalized == petData.DisplayName:lower()
                or normalized:find(petKey, 1, true) then
                petMatches[petData.DisplayName] = petData
                break
            end
        end
        if text:match("^[%x]+%-[%x%-]+$") and #text >= 16 then
            uidMatches[text:lower()] = true
        elseif text:match("^[%w_%-]+$") and #text >= 20 and text:match("%d") then
            uidMatches[text:lower()] = true
        end
    end

    local petMatchCount = 0
    for _, petData in pairs(petMatches) do
        petMatchCount = petMatchCount + 1
        foundPet = petData
    end
    if petMatchCount ~= 1 then
        if petMatchCount > 1 then
            traceEvent("EGG_LEARNING", "AMBIGUOUS_PAYLOAD", { source = source, matches = petMatches })
        end
        foundPet = nil
    end
    local uidMatchCount = 0
    for uid in pairs(uidMatches) do
        uidMatchCount = uidMatchCount + 1
        foundUid = uid
    end
    if uidMatchCount ~= 1 then foundUid = nil end

    if foundPet and foundUid then
        LearnedEggData[foundUid] = {
            DisplayName = foundPet.DisplayName,
            Rarity = foundPet.Rarity,
            Source = source,
            LearnedAt = os.clock(),
        }
        traceEvent("EGG_LEARNING", "UID_MAPPED", {
            uid = foundUid,
            pet = foundPet.DisplayName,
            rarity = foundPet.Rarity,
            source = source,
        })
    end
    if foundPet and State.PendingLearnFingerprint
        and os.clock() - (State.PendingLearnAt or 0) <= 30 then
        local fingerprint = State.PendingLearnFingerprint
        local existing = LearnedVisualData[fingerprint]
        if not existing then
            existing = {
                DisplayName = foundPet.DisplayName,
                Rarity = foundPet.Rarity,
                Source = source,
                LearnedAt = os.clock(),
                Hits = 1,
                Conflicted = false,
            }
            LearnedVisualData[fingerprint] = existing
        elseif existing.DisplayName == foundPet.DisplayName then
            existing.Hits = (existing.Hits or 1) + 1
            existing.Source = source
        else
            existing.Conflicted = true
            existing.ConflictWith = foundPet.DisplayName
        end
        traceEvent("EGG_LEARNING", existing.Conflicted and "VISUAL_CONFLICT" or "VISUAL_OBSERVED", {
            pet = foundPet.DisplayName,
            rarity = foundPet.Rarity,
            source = source,
            fingerprint = fingerprint,
            hits = existing.Hits,
            conflicted = existing.Conflicted,
        })
    end
end

getEggVisualFingerprint = function(instance)
    if not instance then return nil end
    local tokens = {}
    local function addToken(token)
        if token and token ~= "" then table.insert(tokens, tostring(token):lower()) end
    end
    local objects = { instance }
    for _, desc in ipairs(instance:GetDescendants()) do table.insert(objects, desc) end
    for _, obj in ipairs(objects) do
        if obj:IsA("MeshPart") then
            addToken("mesh:" .. (tostring(obj.MeshId):match("%d+") or ""))
            addToken("tex:" .. (tostring(obj.TextureID):match("%d+") or ""))
            addToken(string.format("color:%d,%d,%d", math.floor(obj.Color.R * 255), math.floor(obj.Color.G * 255), math.floor(obj.Color.B * 255)))
        elseif obj:IsA("SpecialMesh") then
            addToken("mesh:" .. (tostring(obj.MeshId):match("%d+") or ""))
            addToken("tex:" .. (tostring(obj.TextureId):match("%d+") or ""))
        elseif obj:IsA("BasePart") then
            addToken(string.format("part:%s:%d,%d,%d:%.1f,%.1f,%.1f", obj.ClassName,
                math.floor(obj.Color.R * 255), math.floor(obj.Color.G * 255), math.floor(obj.Color.B * 255),
                obj.Size.X, obj.Size.Y, obj.Size.Z))
        end
    end
    table.sort(tokens)
    if #tokens == 0 then return nil end
    return table.concat(tokens, "|")
end

-- 8. MAPEAMENTO NUMÉRICO DE MESHID — LISTA SEM SOBRESCRITA
-- Cada MeshId numérico mapeia para uma LISTA de nomes possíveis.
-- Isso evita que pets com malhas genéricas compartilhadas sobrescrevam uns aos outros.
local NumericMeshToEggMap = {} -- { [numericId] = { "Pet1", "Pet2", ... } }
local AssetsDirectoryData = {}
local RarityDataMap = {}

local function registerNumericMesh(meshIdStr, eggName)
    if not meshIdStr or not eggName then return end
    local num = tostring(meshIdStr):match("(%d+)")
    if num and num ~= "" then
        if not NumericMeshToEggMap[num] then
            NumericMeshToEggMap[num] = {}
        end
        -- Evitar duplicatas na lista
        for _, existing in ipairs(NumericMeshToEggMap[num]) do
            if existing == eggName then return end
        end
        table.insert(NumericMeshToEggMap[num], eggName)
    end
end

-- Indexar todos os modelos de ReplicatedStorage
pcall(function()
    local am = Services.ReplicatedStorage:FindFirstChild("AssetModels")
    if am then
        for _, m in ipairs(am:GetChildren()) do
            for _, d in ipairs(m:GetDescendants()) do
                local mId = (d:IsA("MeshPart") and d.MeshId) or (d:IsA("SpecialMesh") and d.MeshId)
                if mId and mId ~= "" then
                    registerNumericMesh(mId, m.Name)
                end
            end
        end
    end
end)

-- Carregar ReplicatedStorage.Data.Assets se disponível
pcall(function()
    local dataFolder = Services.ReplicatedStorage:FindFirstChild("Data")
    if dataFolder then
        local assetsMod = dataFolder:FindFirstChild("Assets")
        if assetsMod and assetsMod:IsA("ModuleScript") then
            local res = require(assetsMod)
            if type(res) == "table" and res.Directory then
                for k, v in pairs(res.Directory) do
                    local rName = "COMUM"
                    if type(v.Rarity) == "table" then
                        rName = tostring(v.Rarity.DisplayName or v.Rarity._id or "COMUM"):upper()
                    elseif type(v.Rarity) == "string" then
                        rName = v.Rarity:upper()
                    end
                    local kLow = tostring(k):lower()
                    AssetsDirectoryData[kLow] = {
                        DisplayName = tostring(v.DisplayName or v.Name or k),
                        Rarity = rName,
                        Weight = tonumber(v.Weight or v.BaseWeight)
                    }
                    -- Atualizar catálogo com display name exato
                    KnownPetsCatalog[kLow] = {
                        DisplayName = tostring(v.DisplayName or v.Name or k),
                        Rarity = rName
                    }
                end
            end
        end

        local rarityMod = dataFolder:FindFirstChild("Rarity")
        if rarityMod and rarityMod:IsA("ModuleScript") then
            local rRes = require(rarityMod)
            if type(rRes) == "table" and rRes.Rarities then
                for rKey, rVal in pairs(rRes.Rarities) do
                    if type(rVal) == "table" then
                        RarityDataMap[tostring(rKey):upper()] = rVal
                    end
                end
            end
        end
    end
end)

local function isHexUUID(str)
    if not str or #str < 18 then return false end
    local clean = str:gsub("-", "")
    return clean:match("^%x+$") ~= nil
end

-- Encontra o modelo renderizado mais próximo em ClientRenderedAssets
local function findNearbyRenderedAsset(pos, maxDist)
    if not pos then return nil end
    maxDist = maxDist or 6.5
    local cra = Services.Workspace:FindFirstChild("ClientRenderedAssets")
    if not cra then return nil end
    local bestObj = nil
    local bestDist = maxDist
    for _, child in ipairs(cra:GetChildren()) do
        local cPos = getPositionOf(child)
        if cPos then
            local d = (cPos - pos).Magnitude
            if d < bestDist then
                bestDist = d
                bestObj = child
            end
        end
    end
    return bestObj
end

-- Identificação Completa de Nome Real, Raridade e Estatísticas do Ovo (v11.0 — Prioridade Corrigida)
-- PRIORIDADE: (1) Slot da Ilha → (2) ProximityPrompt → (3) Atributos → (4) MeshId → (5) Hierarquia
local function resolveEggDetails(instance, prompt)
    local pos = getPositionOf(prompt or instance)
    local foundName = nil
    local detectedRarity = nil
    local maxScore = 300
    local detectedWeight = 0
    local detectedIncome = nil
    local resolvedPet = false

    -- Determinar ilha real
    local isl = getIslandByPos(pos)
    local slotNum = nil

    -- 0. CHECAGEM PRIORITÁRIA DE CACHE FORENSE EM TEMPO REAL (RE/EggWorld/FieldEggShifted)
    if isl and isl.Name and RealFieldEggCache[isl.Name] then
        local cacheEntry = RealFieldEggCache[isl.Name]
        local pName = cacheEntry.PetName
        for pKey, pData in pairs(KnownPetsCatalog) do
            if pKey:lower() == pName:lower() or pData.DisplayName:lower() == pName:lower() then
                foundName = pData.DisplayName
                detectedRarity = pData.Rarity
                maxScore = RarityScoreMap[pData.Rarity] or 50000
                resolvedPet = true
                break
            end
        end
        if not foundName then
            foundName = pName
            detectedRarity = isl.Rarity or "LEGENDARY"
            maxScore = RarityScoreMap[detectedRarity] or 50000
            resolvedPet = true
        end
    end

    local pos = getPositionOf(prompt or instance)
    local foundName = nil
    local detectedRarity = nil
    local maxScore = 300
    local detectedWeight = 0
    local detectedIncome = nil
    local resolvedPet = false

    -- Determinar ilha real
    local isl = getIslandByPos(pos)
    local slotNum = nil

    if instance then
        local sm = instance.Name:match("[Ss]lot[_%s%-]*(%d+)")
        if sm then slotNum = tonumber(sm) end
        if not slotNum then
            pcall(function()
                local si = instance:GetAttribute("SlotIndex") or instance:GetAttribute("Slot")
                if si then slotNum = tonumber(si) end
            end)
        end
    end

    -- SlotIndex nem sempre é replicado; derive um índice estável pela posição.
    if not slotNum and instance and instance.Parent then
        local siblings = {}
        for _, sibling in ipairs(instance.Parent:GetChildren()) do
            if sibling:IsA("Model") or sibling:IsA("BasePart") or sibling:IsA("Folder") then
                local siblingPos = getPositionOf(sibling)
                if siblingPos and getIslandByPos(siblingPos).Id == isl.Id then
                    table.insert(siblings, {Object = sibling, Position = siblingPos})
                end
            end
        end
        table.sort(siblings, function(a, b)
            if math.abs(a.Position.Z - b.Position.Z) > 0.05 then
                return a.Position.Z < b.Position.Z
            end
            return a.Position.X < b.Position.X
        end)
        for index, entry in ipairs(siblings) do
            if entry.Object == instance then
                slotNum = index
                break
            end
        end
    end

    -- Associação aprendida exclusivamente de payloads reais de remotes. Isso
    -- permite que o radar deixe de ser genérico durante a própria sessão.
    if instance then
        local uidCandidates = {
            instance.Name,
            instance:GetAttribute("EggUid"),
            instance:GetAttribute("EggUID"),
            instance:GetAttribute("UID"),
        }
        for _, uid in ipairs(uidCandidates) do
            local learned = uid and LearnedEggData[tostring(uid):lower()]
            if learned then
                foundName = learned.DisplayName
                detectedRarity = learned.Rarity
                maxScore = RarityScoreMap[learned.Rarity] or 300
                resolvedPet = true
                break
            end
        end
    end
    if instance and not foundName then
        local fingerprint = getEggVisualFingerprint(instance)
        local learnedVisual = fingerprint and LearnedVisualData[fingerprint]
        if learnedVisual and (learnedVisual.Hits or 0) >= 2 and not learnedVisual.Conflicted then
            foundName = learnedVisual.DisplayName
            detectedRarity = learnedVisual.Rarity
            maxScore = RarityScoreMap[learnedVisual.Rarity] or 300
            resolvedPet = true
        end
    end

    -- Função utilitária para inspecionar strings em catálogos
    local function inspectStr(s)
        if not s or s == "" then return false end
        local low = tostring(s):lower()
        if isHexUUID(low) or low == "assets" or low == "model" or low == "part"
            or low == "meshpart" or low == "union" or low == "touchinterest"
            or low == "hitbox" or low == "part_union" then
            return false
        end

        -- Casamento direto no catálogo oficial de Pets
        for pKey, pData in pairs(KnownPetsCatalog) do
            if low == pKey or low:find(pKey, 1, true) then
                if not foundName or #pData.DisplayName > #(foundName:match("^(.-)%s*%[") or foundName) then
                    foundName = pData.DisplayName
                    detectedRarity = pData.Rarity
                    maxScore = math.max(maxScore, RarityScoreMap[pData.Rarity] or 5000)
                    resolvedPet = true
                end
                return true
            end
        end

        -- Casamento em AssetsDirectoryData
        if AssetsDirectoryData[low] then
            local entry = AssetsDirectoryData[low]
            foundName = entry.DisplayName
            detectedRarity = entry.Rarity
            maxScore = math.max(maxScore, RarityScoreMap[entry.Rarity] or 5000)
            resolvedPet = true
            if entry.Weight then detectedWeight = entry.Weight end
            return true
        end

        -- Detecção de peso e renda
        local kg = low:match("([%d%,%.]+)%s*kg")
        if kg then
            local n = tonumber((kg:gsub(",", "")))
            if n and n > detectedWeight then detectedWeight = n end
        end

        local num, suf = low:match("%$%s*([%d][%d%,%.]*)%s*(%a*)%s*/%s*s")
        if num and not detectedIncome then
            detectedIncome = "$" .. num .. (suf or ""):upper() .. "/s"
        end

        -- Detecção de Raridade
        for rKey, score in pairs(RarityScoreMap) do
            if low:find(rKey:lower(), 1, true) then
                if score > maxScore then
                    maxScore = score
                    detectedRarity = rKey
                end
            end
        end
        return false
    end

    -- MÉTODO 2: ProximityPrompt (ObjectText e ActionText)
    if not foundName and prompt then
        if prompt.ObjectText and prompt.ObjectText ~= "" then
            local cleanObj = prompt.ObjectText:gsub("^[Tt]ake%s*", ""):gsub("^[Ss]teal%s*", ""):gsub("^[Rr]oubar%s*", ""):gsub("^[Pp]egar%s*", "")
            inspectStr(cleanObj)
        end
        if not foundName and prompt.ActionText and prompt.ActionText ~= "" then
            inspectStr(prompt.ActionText)
        end
    end

    -- MÉTODO 3: Atributos do modelo e prompt
    local function checkAttrs(root)
        if not root then return end
        for k, v in pairs(root:GetAttributes()) do
            inspectStr(k)
            inspectStr(v)
        end
    end

    local renderedModel = findNearbyRenderedAsset(pos, 6.5)
    if not foundName then
        checkAttrs(renderedModel)
        checkAttrs(instance)
        if prompt then checkAttrs(prompt) end
    end

    -- MÉTODO 4: MeshId com desambiguação por ilha
    local function checkMeshes(root)
        if not root then return false end
        for _, d in ipairs(root:GetDescendants()) do
            local mId = (d:IsA("MeshPart") and d.MeshId) or (d:IsA("SpecialMesh") and d.MeshId)
            if mId and mId ~= "" then
                local numId = tostring(mId):match("(%d+)")
                if numId and NumericMeshToEggMap[numId] then
                    local candidates = NumericMeshToEggMap[numId]
                    if type(candidates) == "table" then
                        if #candidates == 1 then
                            -- Sem ambiguidade — usar diretamente
                            inspectStr(candidates[1])
                            return true
                        else
                            -- Múltiplos nomes para o mesmo MeshId — desambiguar pela ilha
                            -- Verificar qual candidato pertence à ilha atual
                            local islPets = {}
                            if isl.SlotPets then
                                for _, pet in pairs(isl.SlotPets) do
                                    islPets[pet.Name:lower()] = true
                                    -- Também verificar nome parcial
                                    local shortName = pet.Name:match("%((.-)%)") or pet.Name
                                    islPets[shortName:lower()] = true
                                end
                            end
                            for _, candName in ipairs(candidates) do
                                local candLow = candName:lower()
                                if islPets[candLow] then
                                    inspectStr(candName)
                                    return true
                                end
                                -- Verificar match parcial no catálogo
                                local catalogEntry = KnownPetsCatalog[candLow]
                                if catalogEntry then
                                    local dispLow = catalogEntry.DisplayName:lower()
                                    if islPets[dispLow] then
                                        inspectStr(candName)
                                        return true
                                    end
                                end
                            end
                            -- Mesh compartilhada sem confirmação de ilha não identifica pet.
                            return false
                        end
                    elseif type(candidates) == "string" then
                        -- Compatibilidade: formato antigo (string)
                        inspectStr(candidates)
                        return true
                    end
                end
            end
        end
        return false
    end

    if not foundName then
        checkMeshes(renderedModel)
        if not foundName then checkMeshes(instance) end
    end

    -- MÉTODO 5: Hierarquia — TextLabels e nomes de modelos
    local function checkHierarchy(root)
        if not root then return end
        for _, desc in ipairs(root:GetDescendants()) do
            if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                inspectStr(desc.Text)
            elseif desc:IsA("Model") and not isHexUUID(desc.Name) then
                inspectStr(desc.Name)
            end
        end
    end

    if not foundName then
        checkHierarchy(renderedModel)
        checkHierarchy(instance)
    end

    -- RESOLUÇÃO FINAL: Gerar nome a partir da ilha se nenhum método achou
    -- Identificar se está em base de outro jogador
    local plots = Services.Workspace:FindFirstChild("Plots")
    local plotOwnerName = nil
    if plots and pos then
        for _, pl in ipairs(plots:GetChildren()) do
            local pP = getPositionOf(pl)
            if pP and (Vector3.new(pP.X, 0, pP.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude < 48 then
                plotOwnerName = pl.Name
                break
            end
        end
    end

    if plotOwnerName then
        if resolvedPet and foundName then
            foundName = string.format("%s (Base de %s)", foundName, plotOwnerName)
        else
            foundName = string.format("Ovo não identificado (Base de %s)", plotOwnerName)
            detectedRarity = "N/D"
            maxScore = 0
            detectedIncome = nil
        end
    end

    -- MÉTODO 5: Leitura de Renda Real e Atributos de Money
    if instance then
        pcall(function()
            local mps = instance:GetAttribute("MoneyPerSecond") or instance:GetAttribute("Rate") or instance:GetAttribute("CashPerSec")
            if mps and tonumber(mps) then
                detectedIncome = formatIncome(tonumber(mps))
            end
            for _, desc in ipairs(instance:GetDescendants()) do
                if desc:IsA("TextLabel") and desc.Text and desc.Text ~= "" then
                    local num, suf = desc.Text:match("%$%s*([%d][%d%,%.]*)%s*(%a*)%s*/%s*s")
                    if num and not detectedIncome then
                        detectedIncome = "$" .. num .. (suf or ""):upper() .. "/s"
                    end
                end
            end
        end)
    end

    -- O dump comprova que slots selvagens não expõem o pet. Não inventar
    -- raridade nem renda usando os dados do guarda/ilha.
    if not foundName then
        if isl.Id ~= "Bases" then
            local slotLabel = slotNum and string.format("Slot %d", slotNum)
                or string.format("X %.0f / Z %.0f", pos.X, pos.Z)
            foundName = string.format("Ovo selvagem [%s] (%s)", slotLabel, isl.Name)
            detectedRarity = "N/D"
            maxScore = 0
            detectedIncome = nil
        else
            foundName = "Ovo não identificado"
            detectedRarity = "N/D"
            maxScore = 0
        end
    end

    if not detectedRarity then
        detectedRarity = "COMUM"
    end

    if resolvedPet and not detectedIncome then
        local pClean = foundName and foundName:lower():match("^([%a%s]+)") or ""
        pClean = pClean:gsub("%s+$", "")
        local base = PetBaseIncome[pClean] or RarityBaseIncome[detectedRarity] or 10
        local mult = math.max(1, (detectedWeight or 1) / 1.0)
        detectedIncome = formatIncome(base * mult)
    end

    return foundName, detectedRarity, maxScore, detectedWeight, detectedIncome
end

local function identifyZone(instance)
    local cur = instance
    local zone = "Mapa Geral"
    local owner = nil

    while cur and cur ~= Services.Workspace do
        local n = cur.Name
        local low = n:lower()

        if low:find("plot") or low:find("base") or low:find("spawn") then
            pcall(function()
                local o = cur:FindFirstChild("Owner") or cur:FindFirstChild("Player") or cur:FindFirstChild("OwnerName")
                if o and o.Value and tostring(o.Value) ~= "" then owner = tostring(o.Value) end
            end)
            zone = n .. (owner and (" (" .. owner .. ")") or "")
            break
        elseif low:find("placedegg") then
            zone = "Base de Jogador"
            break
        elseif low:find("slot") or low:find("area") then
            local pos = getPositionOf(instance)
            zone = getIslandNameByPos(pos)
            break
        end
        cur = cur.Parent
    end

    local isMyPlot = false
    if owner and LocalPlayer and (owner == LocalPlayer.Name or owner == LocalPlayer.DisplayName) then
        isMyPlot = true
    end

    return zone, isMyPlot, owner
end

-- Varredura Global de Ovos
local lastRadarTraceAt = 0
local function scanAllEggs()
    local rawList = {}
    local myHrp = getHRP()
    local myPos = myHrp and myHrp.Position or Vector3.zero

    local function addCandidate(instance, prompt, sourceTag)
        if not instance then return end
        local pos = getPositionOf(prompt or instance)
        if not pos then return end

        local cleanName, rarity, score, weight, income = resolveEggDetails(instance, prompt)
        local zone, isMyPlot, owner = identifyZone(instance)
        if zone == "Mapa Geral" and pos.X >= 510 then
            zone = getIslandNameByPos(pos)
        end
        local dist = (pos - myPos).Magnitude

        table.insert(rawList, {
            Instance = instance,
            Prompt = prompt,
            Name = cleanName,
            Rarity = rarity,
            RarityScore = score,
            WeightKg = weight,
            Income = income,
            Zone = zone,
            IsMyPlot = isMyPlot,
            PlotOwner = owner,
            Position = pos,
            Distance = dist,
            Source = sourceTag
        })
    end

    -- 1. PlacedEggRenders (Apenas se tiver ProximityPrompt ativo para roubo!)
    pcall(function()
        local placed = Services.Workspace:FindFirstChild("PlacedEggRenders")
        if placed then
            for _, egg in ipairs(placed:GetChildren()) do
                local p = egg:FindFirstChildWhichIsA("ProximityPrompt", true)
                if p and p.Enabled then
                    addCandidate(egg, p, "Base/Plot")
                end
            end
        end
    end)

    -- 2. AreaEggSlotsClient
    pcall(function()
        local areaSlots = Services.Workspace:FindFirstChild("AreaEggSlotsClient")
        if areaSlots then
            for _, slot in ipairs(areaSlots:GetChildren()) do
                local p = slot:FindFirstChildWhichIsA("ProximityPrompt", true)
                addCandidate(slot, p, "Ilha Selvagem")
            end
        end
    end)

    -- 3. Prompts Gerais do Workspace
    pcall(function()
        for _, desc in ipairs(Services.Workspace:GetDescendants()) do
            if desc:IsA("ProximityPrompt") then
                local act = plainText(desc.ActionText)
                local obj = plainText(desc.ObjectText)
                local isCand = act:find("steal") or act:find("roubar") or act:find("take")
                    or act:find("pick") or obj:find("egg") or obj:find("ovo") or desc.Name:lower():find("egg")
                if isCand and desc.Parent then
                    addCandidate(desc.Parent, desc, "Prompt Geral")
                end
            end
        end
    end)

    -- Deduplicação Espacial e Vinculação
    local deduplicated = {}
    for _, cand in ipairs(rawList) do
        local merged = false
        for _, existing in ipairs(deduplicated) do
            if (existing.Position - cand.Position).Magnitude <= 4.5 then
                merged = true
                if not existing.Prompt and cand.Prompt then
                    existing.Prompt = cand.Prompt
                end
                if existing.Rarity == "N/D" and cand.Rarity ~= "N/D" then
                    existing.Name = cand.Name
                    existing.Rarity = cand.Rarity
                    existing.RarityScore = cand.RarityScore
                    existing.WeightKg = cand.WeightKg
                    existing.Income = cand.Income
                end
                break
            end
        end
        if not merged then
            table.insert(deduplicated, cand)
        end
    end

    table.sort(deduplicated, function(a, b)
        if a.RarityScore ~= b.RarityScore then
            return a.RarityScore > b.RarityScore
        end
        return a.Distance < b.Distance
    end)

    if os.clock() - lastRadarTraceAt >= 3 then
        lastRadarTraceAt = os.clock()
        local summary = {}
        for index, egg in ipairs(deduplicated) do
            if index > 80 then break end
            table.insert(summary, {
                name = egg.Name,
                rarity = egg.Rarity,
                income = egg.Income,
                zone = egg.Zone,
                source = egg.Source,
                distance = math.floor(egg.Distance),
                position = egg.Position,
                instance = egg.Instance,
                prompt = egg.Prompt,
            })
        end
        traceEvent("RADAR", "SCAN", { count = #deduplicated, eggs = summary })
    end

    return deduplicated
end

-- 9. NAVEGAÇÃO SEGURA: sem escrever CFrame no personagem.
local isMoving = false

local function movePlayerSafe(targetPos, speed, onStep)
    local hrp = getHRP()
    local char = LocalPlayer.Character
    if not hrp or not char or isMoving then return false end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return false end

    isMoving = true
    local oldWalkSpeed = humanoid.WalkSpeed
    local requestedSpeed = math.clamp(tonumber(speed) or Config.MoveSpeed or 30, 16, 36)
    humanoid.WalkSpeed = requestedSpeed
    humanoid.PlatformStand = false
    traceEvent("MOVEMENT", "START", {
        from = hrp.Position,
        target = targetPos,
        speed = requestedSpeed,
    })

    local function cleanup()
        if humanoid and humanoid.Parent and humanoid.Health > 0 then
            humanoid:Move(Vector3.zero, false)
            humanoid.WalkSpeed = oldWalkSpeed
        end
        isMoving = false
    end

    local function walkTo(point, timeout)
        humanoid:MoveTo(point)
        local started = os.clock()
        local lastProgressAt = started
        local lastDistance = (hrp.Position - point).Magnitude

        while os.clock() - started < timeout do
            if State.IsUnloaded or not char.Parent or humanoid.Health <= 0 then return false end
            local distance = (hrp.Position - point).Magnitude
            local horizontal = Vector3.new(point.X - hrp.Position.X, 0, point.Z - hrp.Position.Z)
            if horizontal.Magnitude > 0.05 then
                -- Move mantém a animação de caminhada; o WalkSpeed alto produz o
                -- efeito de deslize pedido sem escrever CFrame nem aplicar impulso.
                humanoid:Move(horizontal.Unit, false)
            end
            if onStep then onStep((hrp.Position - targetPos).Magnitude) end
            if distance <= 4 then return true end
            if distance < lastDistance - 0.75 then
                lastDistance = distance
                lastProgressAt = os.clock()
            elseif os.clock() - lastProgressAt > 3.0 then
                return false
            end
            Services.RunService.Heartbeat:Wait()
        end
        return false
    end

    local reached = false
    for attempt = 1, 4 do
        if (hrp.Position - targetPos).Magnitude <= 5 then
            reached = true
            break
        end

        local path = Services.PathfindingService:CreatePath({
            AgentRadius = 2,
            AgentHeight = 5,
            AgentCanJump = true,
            AgentCanClimb = true,
            WaypointSpacing = 10,
        })
        local computed = pcall(function()
            path:ComputeAsync(hrp.Position, targetPos)
        end)
        traceEvent("MOVEMENT", "PATH", {
            attempt = attempt,
            computed = computed,
            status = tostring(path.Status),
            distance = (hrp.Position - targetPos).Magnitude,
        })

        if computed and path.Status == Enum.PathStatus.Success then
            local waypoints = path:GetWaypoints()
            local routeOk = true
            for index = 2, #waypoints do
                local waypoint = waypoints[index]
                if waypoint.Action == Enum.PathWaypointAction.Jump then
                    humanoid.Jump = true
                end
                if not walkTo(waypoint.Position, 8) then
                    routeOk = false
                    break
                end
            end
            if routeOk and (hrp.Position - targetPos).Magnitude <= 7 then
                reached = true
                break
            end
        else
            -- Para alvos próximos ainda é seguro tentar MoveTo direto.
            local distance = (hrp.Position - targetPos).Magnitude
            if distance <= 120 and walkTo(targetPos, math.max(5, distance / humanoid.WalkSpeed + 3)) then
                reached = true
                break
            end
        end
    end

    cleanup()
    traceEvent("MOVEMENT", reached and "ARRIVED" or "FAILED", {
        target = targetPos,
        finalPosition = hrp and hrp.Parent and hrp.Position or nil,
        speed = requestedSpeed,
    })
    return reached
end

local function movePlayerDirect(targetPos, speed, onStep)
    return movePlayerSafe(targetPos, speed, onStep)
end

local function movePlayerOverhead(targetPos, speed, onStep)
    return movePlayerSafe(targetPos, speed, onStep)
end

-- Acionamento Rápido de ProximityPrompt
local function triggerPrompt(prompt)
    if not prompt or not prompt.Parent or not prompt.Enabled then return false end
    traceEvent("PROMPT", "TRIGGER", {
        prompt = prompt,
        actionText = prompt.ActionText,
        objectText = prompt.ObjectText,
        enabled = prompt.Enabled,
        position = getPositionOf(prompt),
    })
    local triggered = false
    if fireproximityprompt then
        triggered = pcall(function()
            -- Uma única interação. O código anterior disparava o mesmo prompt
            -- várias vezes e alterava suas propriedades, fazendo o servidor negar.
            fireproximityprompt(prompt)
        end)
    else
        triggered = pcall(function()
            prompt:InputHoldBegin()
            task.wait(math.clamp(prompt.HoldDuration, 0.05, 2))
            prompt:InputHoldEnd()
        end)
    end
    traceEvent("PROMPT", triggered and "TRIGGER_SENT" or "TRIGGER_FAILED", { prompt = prompt })
    return triggered
end

--================================================================--
-- 9.5. MOTOR MASTER DE AUTO-ROUBO (CAMINHADA SEGURA)
--================================================================--

-- A. Identificação do Plot do Jogador e Ponto de Depósito / Esteira
local function findMyPlot()
    local plots = Services.Workspace:FindFirstChild("Plots")
    if not plots then return nil end

    local myName = LocalPlayer.Name:lower()
    local myDisplay = LocalPlayer.DisplayName:lower()
    local myId = tostring(LocalPlayer.UserId)

    for _, plot in ipairs(plots:GetChildren()) do
        -- 1. Checagem por ObjectValue ou StringValue de proprietário
        for _, tag in ipairs({"Owner", "Player", "OwnerName", "OwnerId", "UserId", "PlayerId"}) do
            local valObj = plot:FindFirstChild(tag)
            if valObj then
                if valObj:IsA("ObjectValue") and (valObj.Value == LocalPlayer or valObj.Value == LocalPlayer.Character) then
                    return plot
                elseif valObj:IsA("StringValue") then
                    local s = valObj.Value:lower()
                    if s == myName or s == myDisplay then return plot end
                elseif valObj:IsA("IntValue") or valObj:IsA("NumberValue") then
                    if tostring(valObj.Value) == myId then return plot end
                end
            end
        end

        -- 2. Checagem de Atributos do Plot
        for k, v in pairs(plot:GetAttributes()) do
            local s = tostring(v):lower()
            if s == myName or s == myDisplay or s == myId then
                return plot
            end
        end

        -- 3. Checagem de Placas e Nomes no Plot
        for _, desc in ipairs(plot:GetDescendants()) do
            if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                local txt = desc.Text:lower()
                if txt:find(myName) or txt:find(myDisplay) then
                    return plot
                end
            end
        end
    end
    return nil
end

local function getMyDepositTarget()
    local myPlot = findMyPlot()
    if myPlot then
        local bestPart = nil
        local bestPriority = -1
        for _, d in ipairs(myPlot:GetDescendants()) do
            if d:IsA("BasePart") then
                local low = d.Name:lower()
                local priority = 0
                if low:find("deposit", 1, true) or low:find("drop", 1, true) then
                    priority = 5
                elseif low:find("conveyor", 1, true) or low:find("esteira", 1, true) then
                    priority = 4
                elseif low:find("nest", 1, true) or low:find("ninho", 1, true) then
                    priority = 3
                elseif low:find("egg", 1, true) or low:find("ovo", 1, true) then
                    priority = 1
                end
                if priority > bestPriority then
                    bestPart = d
                    bestPriority = priority
                end
            end
        end
        if bestPart and bestPriority > 0 then
            return bestPart, bestPart.CFrame + Vector3.new(0, 2.5, 0)
        end
        return nil, myPlot:GetPivot() + Vector3.new(0, 2.5, 0)
    end
    return nil, State.BaseCFrame or (getHRP() and getHRP().CFrame)
end

local function getMyDepositCFrame()
    local _, depositCFrame = getMyDepositTarget()
    return depositCFrame
end

-- B. Localização do Guarda da Floresta (Ilha 1) para Ativação de Ragdoll
local function findForestGuard()
    for _, obj in ipairs(Services.Workspace:GetChildren()) do
        if obj:IsA("Model") then
            local low = obj.Name:lower()
            if (low:find("guard") or low:find("chicken") or low:find("forest") or low:find("galinha"))
                and obj ~= Services.Workspace:FindFirstChild("_Guards") then
                local p = getPositionOf(obj)
                if p and (p - Vector3.new(598, 68, -328)).Magnitude < 180 then
                    return obj, p
                end
            end
        end
    end

    local gFolder = Services.Workspace:FindFirstChild("_Guards")
    if gFolder then
        for _, g in ipairs(gFolder:GetChildren()) do
            local low = g.Name:lower()
            if low:find("forest") or low:find("chicken") or low:find("galinha") then
                local p = getPositionOf(g)
                if p then return g, p end
            end
        end
    end

    return nil, Vector3.new(598.0, 68.0, -328.0)
end

-- C. Detecção em Tempo Real de Ragdoll e Física Suspensa
local function isPlayerInRagdoll()
    local char = getChar()
    if not char then return false end
    local hum = getHum()
    if hum then
        local state = hum:GetState()
        if state == Enum.HumanoidStateType.Ragdoll or state == Enum.HumanoidStateType.PlatformStanding or hum.PlatformStand then
            return true
        end
    end
    local lpRag = LocalPlayer:GetAttribute("RagdollEndTime") or LocalPlayer:GetAttribute("IsRagdoll") or LocalPlayer:GetAttribute("Ragdoll")
    if lpRag and (type(lpRag) == "boolean" and lpRag or type(lpRag) == "number" and lpRag > 0) then
        return true
    end
    local charRag = char:GetAttribute("RagdollEndTime") or char:GetAttribute("IsRagdoll") or char:GetAttribute("Ragdoll")
    if charRag and (type(charRag) == "boolean" and charRag or type(charRag) == "number" and charRag > 0) then
        return true
    end
    if char:FindFirstChildWhichIsA("BallSocketConstraint", true) then
        return true
    end
    return false
end

-- D. Compatibilidade: qualquer método antigo usa caminhada segura.
local function executeRagdollSteal(target)
    addLog("ROUBO", "Ragdoll TP removido; usando caminhada segura.")
    return executeDirectSteal(target)
end

-- E. Execução legada redirecionada para a mesma caminhada segura.
executeDirectSteal = function(target)
    if not target or not target.Position then return false end
    local myHrp = getHRP()
    if not myHrp or State.IsUnloaded then return false end

    local baseCF = getMyDepositCFrame() or State.BaseCFrame or myHrp.CFrame
    local targetPos = target.Position

    addLog("ROUBO", string.format("Caminhando com segurança para %s [%s]...", target.Name, target.Rarity))

    local arrived = movePlayerDirect(targetPos, Config.MoveSpeed)
    if arrived then
        local pInst = target.Prompt or (target.Instance and target.Instance:FindFirstChildWhichIsA("ProximityPrompt", true))
        if pInst then
            State.ExpectCarryUntil = os.clock() + 4
            triggerPrompt(pInst)
        end
        task.wait(0.12)

        movePlayerOverhead(baseCF.Position, Config.MoveSpeed)
        task.wait(Config.AutoDepositWait or 1.0)
    end
end

--================================================================--
-- F. MÁQUINA DE ESTADOS COMPLETA DE AUTO-ROUBO (v11.0)
-- IDLE → SELECTING → MOVING_TO_EGG → INTERACTING → VERIFYING_CARRY
-- → RETURNING → DEPOSITING → CONFIRMING → IDLE
--================================================================--

-- Variáveis da Máquina de Estados
local StealSM = {
    Current = "IDLE",
    Target = nil,              -- Alvo atual (tabela do scanAllEggs)
    StateStart = 0,            -- os.clock() do início do estado atual
    CycleStart = 0,            -- os.clock() do início do ciclo completo
    ConsecutiveFails = 0,      -- Falhas consecutivas no mesmo alvo
    Blacklist = {},            -- { [posKey] = expireTime } — alvos temporariamente ignorados
    VerifyPolls = 0,           -- Contagem de polls em VERIFYING_CARRY
    DepositRetries = 0,        -- Tentativas de re-depósito em CONFIRMING
    PickupSnapshot = nil,
}

-- Timeouts por estado (em segundos)
local SM_TIMEOUTS = {
    SELECTING = 2.0,
    INTERACTING = 1.5,
    VERIFYING_CARRY = 2.5,
    CONFIRMING = 1.5,
    GLOBAL_CYCLE = 120.0,
}

-- Gera chave de posição para o blacklist (arredonda para evitar flutuações)
local function posKey(pos)
    return string.format("%.0f_%.0f_%.0f", pos.X, pos.Y, pos.Z)
end

local function capturePickupSnapshot(target)
    local char = getChar()
    local rightHand = char and (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm"))
    local descendants = {}
    local connected = {}
    if char then
        for _, desc in ipairs(char:GetDescendants()) do descendants[desc] = true end
    end
    if rightHand then
        pcall(function()
            for _, part in ipairs(rightHand:GetConnectedParts(true)) do connected[part] = true end
        end)
    end
    StealSM.PickupSnapshot = {
        Instance = target and target.Instance,
        Parent = target and target.Instance and target.Instance.Parent,
        Position = target and target.Instance and getPositionOf(target.Instance),
        CharacterDescendants = descendants,
        ConnectedParts = connected,
    }
    State.PendingLearnFingerprint = target and target.Instance and getEggVisualFingerprint(target.Instance) or nil
    State.PendingLearnAt = os.clock()
    traceEvent("PICKUP", "SNAPSHOT", {
        target = target and target.Name,
        instance = target and target.Instance,
        position = target and target.Position,
        visualFingerprint = State.PendingLearnFingerprint,
    })
end

local function detectPickupEvidence()
    local holding, heldName = isHoldingEgg()
    if holding then return true, "carry:" .. tostring(heldName) end

    local snapshot = StealSM.PickupSnapshot
    if not snapshot then return false, nil end
    local targetInstance = snapshot.Instance
    if targetInstance then
        if not targetInstance.Parent then return true, "target_destroyed" end
        local slots = Services.Workspace:FindFirstChild("AreaEggSlotsClient")
        if snapshot.Parent and targetInstance.Parent ~= snapshot.Parent
            and (not slots or not targetInstance:IsDescendantOf(slots)) then
            return true, "target_reparented:" .. instancePath(targetInstance.Parent)
        end
        local currentPosition = getPositionOf(targetInstance)
        if snapshot.Position and currentPosition and (currentPosition - snapshot.Position).Magnitude >= 6 then
            return true, string.format("target_moved_%.1f", (currentPosition - snapshot.Position).Magnitude)
        end
    end

    local char = getChar()
    local rightHand = char and (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm"))
    if rightHand then
        local ok, parts = pcall(function() return rightHand:GetConnectedParts(true) end)
        if ok then
            for _, part in ipairs(parts) do
                if not snapshot.ConnectedParts[part]
                    and not standardLimbNames[part.Name:lower()]
                    and not part:FindFirstAncestorOfClass("Accessory")
                    and not part:FindFirstAncestorOfClass("Tool") then
                    return true, "new_hand_connection:" .. instancePath(part)
                end
            end
        end
    end

    if char then
        for _, desc in ipairs(char:GetDescendants()) do
            if not snapshot.CharacterDescendants[desc]
                and (desc:IsA("Model") or desc:IsA("BasePart"))
                and not standardLimbNames[desc.Name:lower()]
                and not desc:FindFirstAncestorOfClass("Accessory")
                and not desc:FindFirstAncestorOfClass("Tool") then
                return true, "new_character_object:" .. instancePath(desc)
            end
        end
    end
    return false, nil
end

-- Limpa entradas expiradas do blacklist
local function cleanBlacklist()
    local now = os.clock()
    for k, expire in pairs(StealSM.Blacklist) do
        if now > expire then
            StealSM.Blacklist[k] = nil
        end
    end
end

-- Transição de estado com log e atualização de UI
local function setStealState(newState)
    local oldState = StealSM.Current
    StealSM.Current = newState
    StealSM.StateStart = os.clock()

    if newState == "IDLE" then
        StealSM.Target = nil
        StealSM.CycleStart = 0
        StealSM.VerifyPolls = 0
        StealSM.DepositRetries = 0
        StealSM.PickupSnapshot = nil
        State.IsExecutingSteal = false
    elseif newState == "SELECTING" then
        if StealSM.CycleStart == 0 then
            StealSM.CycleStart = os.clock()
        end
        State.IsExecutingSteal = true
    end

    traceEvent("STATE_MACHINE", oldState .. "->" .. newState, {
        target = StealSM.Target and StealSM.Target.Name,
        targetPosition = StealSM.Target and StealSM.Target.Position,
        carryConfirmed = State.CarryConfirmed,
        carryEvidence = State.CarryEvidence,
    })

    -- Atualizar badges da UI
    local uiMap = {
        IDLE = {"PARADO", C_MUTED},
        SELECTING = {"BUSCANDO", C_CYAN},
        MOVING_TO_EGG = {"INDO AO OVO", C_GREEN},
        INTERACTING = {"INTERAGINDO", C_YELLOW},
        VERIFYING_CARRY = {"VERIFICANDO", C_YELLOW},
        RETURNING = {"RETORNANDO", C_CYAN},
        DEPOSITING = {"DEPOSITANDO", C_GREEN},
        CONFIRMING = {"CONFIRMANDO", C_YELLOW},
    }
    local info = uiMap[newState]
    if info and StatusBadge then
        StatusBadge.Text = info[1]
        StatusBadge.TextColor3 = info[2]
    end
end

-- Reset completo em caso de morte ou respawn
registerConnection(LocalPlayer.CharacterAdded:Connect(function()
    if State.IsUnloaded then return end
    task.wait(0.3)
    if StealSM.Current ~= "IDLE" then
        addLog("ESTADO", "Personagem respawnou — resetando para IDLE")
        setStealState("IDLE")
    end
end))

-- Função principal: um tick da máquina de estados (chamada a cada ~0.15s pelo loop)
local function runStateMachineTick()
    if State.IsUnloaded then return end
    local myHrp = getHRP()
    local myHum = getHum()
    if not myHrp or not myHum or myHum.Health <= 0 then
        if StealSM.Current ~= "IDLE" then setStealState("IDLE") end
        return
    end

    -- Caminhada real precisa de uma janela maior que o antigo TP.
    if StealSM.CycleStart > 0 and (os.clock() - StealSM.CycleStart) > SM_TIMEOUTS.GLOBAL_CYCLE then
        addLog("TIMEOUT", "Ciclo global excedeu o limite seguro — resetando")
        setStealState("IDLE")
        return
    end

    local elapsed = os.clock() - StealSM.StateStart
    local current = StealSM.Current

    --=== IDLE ===--
    if current == "IDLE" then
        -- Detectar base se necessário
        if not State.BaseCFrame then
            local depCF = getMyDepositCFrame()
            if depCF then
                State.BaseCFrame = depCF
                if BaseLabel then
                    local myPlot = findMyPlot()
                    BaseLabel.Text = string.format("Base: (%s) em (%.0f, %.0f, %.0f)",
                        myPlot and myPlot.Name or "Detectada",
                        depCF.Position.X, depCF.Position.Y, depCF.Position.Z)
                    BaseLabel.TextColor3 = C_GREEN
                end
            end
        end

        -- Verificar se já está segurando ovo (caso raro — jogador coletou manualmente)
        local holding, heldName = isHoldingEgg()
        if holding then
            addLog("ESTADO", "Ovo detectado em mãos (" .. tostring(heldName) .. ") — indo entregar")
            setStealState("RETURNING")
            return
        end

        setStealState("SELECTING")
        return

    --=== SELECTING ===--
    elseif current == "SELECTING" then
        if elapsed > SM_TIMEOUTS.SELECTING then
            addLog("TIMEOUT", "SELECTING excedeu timeout — voltando a IDLE")
            setStealState("IDLE")
            return
        end

        cleanBlacklist()
        local eggs = scanAllEggs()
        local valid = {}
        for _, e in ipairs(eggs) do
            if not (Config.ShowOnlyUnowned and e.IsMyPlot) then
                if e.Distance <= Config.MaxStealDistance then
                    if isEggInMyIsland(e.Position) then
                        local key = posKey(e.Position)
                        if not StealSM.Blacklist[key] then
                            table.insert(valid, e)
                        end
                    end
                end
            end
        end

        if #valid == 0 then
            if TargetInfoLabel then
                TargetInfoLabel.Text = "Nenhum ovo elegível encontrado na ilha atual."
            end
            setStealState("IDLE")
            task.wait(0.8) -- Aguarda antes de re-escanear
            return
        end

        -- Selecionar o ovo de maior valor
        StealSM.Target = valid[1]
        StealSM.ConsecutiveFails = 0
        if TargetInfoLabel then
            local incStr = StealSM.Target.Income and (" • " .. StealSM.Target.Income) or ""
            TargetInfoLabel.Text = string.format("[%s] %s (%dm%s)",
                StealSM.Target.Rarity, StealSM.Target.Name, math.floor(StealSM.Target.Distance), incStr)
        end
        if TargetTitle then
            TargetTitle.Text = Config.LockCurrentIsland and "ALVO PRIORITARIO (ILHA ATUAL):" or "ALVO PRIORITARIO (TODO O MAPA):"
        end
        addLog("ALVO", string.format("Selecionado: %s [%s] %s a %d studs",
            StealSM.Target.Name, StealSM.Target.Rarity, StealSM.Target.Income or "", math.floor(StealSM.Target.Distance)))

        setStealState("MOVING_TO_EGG")
        return

    --=== MOVING_TO_EGG ===--
    elseif current == "MOVING_TO_EGG" then
        local target = StealSM.Target
        if not target or not target.Position then
            setStealState("IDLE")
            return
        end

        -- Calcular timeout dinâmico: distância / velocidade + 3s margem
        local dist = (target.Position - myHrp.Position).Magnitude
        local dynamicTimeout = (dist / math.max(Config.MoveSpeed, 8)) + 8.0

        if elapsed > dynamicTimeout then
            addLog("TIMEOUT", "MOVING_TO_EGG excedeu timeout — resetando")
            StealSM.Blacklist[posKey(target.Position)] = os.clock() + 10.0
            setStealState("IDLE")
            return
        end

        -- Bater taco durante aproximação se houver perigo
        task.spawn(function()
            for _ = 1, 3 do
                triggerBatSwing()
                task.wait(0.1)
            end
        end)
        -- Executar movimentação (bloqueia até chegar ou falhar)
        local arrived = movePlayerDirect(target.Position, Config.MoveSpeed)
        if arrived then
            setStealState("INTERACTING")
        else
            addLog("MOVER", "Falha ao chegar ao ovo — tentando próximo alvo")
            StealSM.Blacklist[posKey(target.Position)] = os.clock() + 10.0
            setStealState("SELECTING")
        end
        return

    --=== INTERACTING ===--
    elseif current == "INTERACTING" then
        local target = StealSM.Target
        if not target then
            setStealState("IDLE")
            return
        end

        -- Disparar o ProximityPrompt do ovo
        local pInst = target.Prompt or (target.Instance and target.Instance:FindFirstChildWhichIsA("ProximityPrompt", true))
        if pInst then
            capturePickupSnapshot(target)
            State.ExpectCarryUntil = os.clock() + 4
            if triggerPrompt(pInst) then
                addLog("INTERAÇÃO", "Prompt disparado para " .. target.Name)
            else
                addLog("INTERAÇÃO", "Prompt indisponível — selecionando outro alvo")
                StealSM.Blacklist[posKey(target.Position)] = os.clock() + 5.0
                setStealState("SELECTING")
                return
            end
        else
            addLog("INTERAÇÃO", "Sem ProximityPrompt — pulando alvo")
            StealSM.Blacklist[posKey(target.Position)] = os.clock() + 10.0
            setStealState("SELECTING")
            return
        end

        task.wait(0.12)

        StealSM.VerifyPolls = 0
        setStealState("VERIFYING_CARRY")
        return

    --=== VERIFYING_CARRY ===--
    elseif current == "VERIFYING_CARRY" then
        StealSM.VerifyPolls = StealSM.VerifyPolls + 1

        local holding, heldName = detectPickupEvidence()
        local targetPrompt = StealSM.Target and (StealSM.Target.Prompt or (StealSM.Target.Instance and StealSM.Target.Instance:FindFirstChildWhichIsA("ProximityPrompt", true)))
        local promptGone = not targetPrompt or not targetPrompt.Parent or not targetPrompt.Enabled

        -- Prompt desaparecer sozinho também ocorre por streaming, disputa ou
        -- rejeição do servidor. Somente carry positivo confirma a coleta.
        if holding then
            State.CarryConfirmed = true
            State.CarryEvidence = heldName
            State.LastCarryChange = os.clock()
            traceEvent("PICKUP", "CONFIRMED", { evidence = heldName, polls = StealSM.VerifyPolls })
            addLog("VERIFICAR", "Carry confirmado (" .. tostring(heldName) .. ") — retornando à base")
            setStealState("RETURNING")
            return
        end

        if elapsed > SM_TIMEOUTS.VERIFYING_CARRY then
            traceEvent("PICKUP", "NOT_CONFIRMED", {
                promptGone = promptGone,
                polls = StealSM.VerifyPolls,
                target = StealSM.Target and StealSM.Target.Instance,
            })
            addLog("VERIFICAR", promptGone
                and "Prompt sumiu sem carry confirmado — ignorando falso positivo"
                or "Coleta não confirmada — selecionando outro alvo")
            if StealSM.Target and StealSM.Target.Position then
                StealSM.Blacklist[posKey(StealSM.Target.Position)] = os.clock() + 3.0
            end
            setStealState("SELECTING")
            return
        end

        return

    --=== RETURNING ===--
    elseif current == "RETURNING" then
        local baseCF = getMyDepositCFrame() or State.BaseCFrame
        if not baseCF then
            addLog("ERRO", "Base não encontrada para depósito")
            setStealState("IDLE")
            return
        end

        local dist = (baseCF.Position - myHrp.Position).Magnitude
        local dynamicTimeout = (dist / math.max(Config.MoveSpeed, 8)) + 8.0

        if elapsed > dynamicTimeout then
            addLog("TIMEOUT", "RETURNING excedeu timeout — resetando")
            setStealState("IDLE")
            return
        end

        addLog("RETORNO", "Voltando à base com ovo...")
        if TargetInfoLabel then
            TargetInfoLabel.Text = "Ovo em mãos! Voltando à base..."
        end

        local arrived = movePlayerOverhead(baseCF.Position, Config.MoveSpeed)
        if arrived then
            setStealState("DEPOSITING")
        else
            addLog("RETORNO", "Rota segura até a base indisponível — TP não será usado")
            setStealState("IDLE")
        end
        return

    --=== DEPOSITING ===--
    elseif current == "DEPOSITING" then
        task.wait(0.5)
        State.ExpectCarryUntil = os.clock() + 3
        local depositPart = getMyDepositTarget()
        if depositPart and depositPart.Parent then
            myHum:MoveTo(depositPart.Position)
            task.wait(0.6)
            pcall(function()
                if firetouchinterest then
                    firetouchinterest(myHrp, depositPart, 0)
                    task.wait()
                    firetouchinterest(myHrp, depositPart, 1)
                end
            end)
        end
        setStealState("CONFIRMING")
        return

    --=== CONFIRMING ===--
    elseif current == "CONFIRMING" then
        local holding, _ = isHoldingEgg()
        if not holding then
            addLog("CONFIRMAR", "Ovo depositado com sucesso!")
            State.CarryConfirmed = false
            State.CarryEvidence = nil
            StealSM.Target = nil
            StealSM.ConsecutiveFails = 0
            StealSM.DepositRetries = 0
            setStealState("IDLE")
            return
        end

        -- Nunca formar CONFIRMING -> RETURNING -> DEPOSITING em loop.
        if elapsed >= 1.5 then
            addLog("CONFIRMAR", "Confirmação atrasada pelo servidor — liberando o ciclo")
            State.CarryConfirmed = false
            State.CarryEvidence = nil
            StealSM.Target = nil
            StealSM.ConsecutiveFails = 0
            StealSM.DepositRetries = 0
            setStealState("IDLE")
            return
        end
        return
    end
end


-- 10. EXPORTADOR DE TELEMETRIA E DADOS INTERNOS (OBSERVATORY v13.1)
local function dumpGameData()
    local lines = {}
    local function logL(s) table.insert(lines, s or "") end

    logL("================================================================================")
    logL("ROUBE UM OVO - DUMP E TELEMETRIA OBSERVATORY v13.1")
    logL("Data: " .. os.date("%Y-%m-%d %H:%M:%S") .. " | PlaceId: " .. tostring(game.PlaceId))
    logL("================================================================================\n")

    -- 1. Desempacotamento de ReplicatedStorage.Data.Assets (O Banco de Dados Real de Pets/Ovos)
    logL("[1] REPLICATEDSTORAGE.DATA.ASSETS (Banco Oficial do Jogo):")
    pcall(function()
        local dataF = Services.ReplicatedStorage:FindFirstChild("Data")
        if dataF then
            local aMod = dataF:FindFirstChild("Assets")
            if aMod and aMod:IsA("ModuleScript") then
                local res = require(aMod)
                if type(res) == "table" then
                    if res.Directory then
                        local total = 0
                        for k, v in pairs(res.Directory) do total = total + 1 end
                        logL("  Total de Itens em Directory: " .. tostring(total))
                        for k, v in pairs(res.Directory) do
                            local dName = tostring(v.DisplayName or v.Name or k)
                            local rName = "N/D"
                            if type(v.Rarity) == "table" then
                                rName = tostring(v.Rarity.DisplayName or v.Rarity._id or "N/D")
                            elseif type(v.Rarity) == "string" then
                                rName = v.Rarity
                            end
                            local w = tostring(v.Weight or v.BaseWeight or "N/D")
                            local drop = tostring(v.DropChance or v.Chance or "N/D")
                            logL(string.format("  - Chave: %-25s | Display: %-24s | Raridade: %-14s | Peso: %s | Drop: %s", tostring(k), dName, rName, w, drop))
                        end
                    end
                    if res.ByRarity then
                        logL("\n  Distribuição em ByRarity:")
                        for rk, rv in pairs(res.ByRarity) do
                            local count = type(rv) == "table" and #rv or 0
                            logL(string.format("    > Raridade %s: %d itens", tostring(rk), count))
                        end
                    end
                end
            else
                logL("  Módulo Data.Assets não encontrado ou inacessível!")
            end
        end
    end)
    logL("\n")

    -- 2. Desempacotamento de ReplicatedStorage.Data.Guards (Guardas, Galinhas e Dano)
    logL("[2] REPLICATEDSTORAGE.DATA.GUARDS (Configuração de Guardas e Galinhas):")
    pcall(function()
        local dataF = Services.ReplicatedStorage:FindFirstChild("Data")
        if dataF then
            local gMod = dataF:FindFirstChild("Guards")
            if gMod and gMod:IsA("ModuleScript") then
                local res = require(gMod)
                if type(res) == "table" and res.Directory then
                    for gKey, gVal in pairs(res.Directory) do
                        logL(string.format("  - Guarda: %-20s | Dados: %s", tostring(gKey), Services.HttpService:JSONEncode(serializeTelemetry(gVal))))
                    end
                end
            end
        end
    end)
    logL("\n")

    -- 3. Guardas físicos no Workspace
    logL("[3] WORKSPACE._GUARDS & SPAWNS DE GUARDAS NO MAPA:")
    pcall(function()
        local function scanGuardObj(parent, folderName)
            if not parent then return end
            for _, g in ipairs(parent:GetChildren()) do
                local pos = getPositionOf(g)
                local posStr = pos and string.format("(%.1f, %.1f, %.1f)", pos.X, pos.Y, pos.Z) or "N/D"
                local dist = (pos and getHRP()) and string.format("%d studs", math.floor((pos - getHRP().Position).Magnitude)) or "N/D"
                local attrs = {}
                for k, v in pairs(g:GetAttributes()) do table.insert(attrs, k .. "=" .. tostring(v)) end
                local attrStr = #attrs > 0 and table.concat(attrs, ", ") or "Nenhum"
                logL(string.format("  - [%s] %-25s | Pos: %s | Dist: %s | Attrs: %s", folderName, g.Name, posStr, dist, attrStr))
            end
        end
        scanGuardObj(Services.Workspace:FindFirstChild("_Guards"), "_Guards")
        scanGuardObj(Services.Workspace:FindFirstChild("MonsterParasiteMonsters"), "MonsterParasite")
        for _, obj in ipairs(Services.Workspace:GetChildren()) do
            local low = obj.Name:lower()
            if (low:find("guard") or low:find("chicken") or low:find("galinha")) and obj ~= Services.Workspace:FindFirstChild("_Guards") then
                scanGuardObj({obj}, "WorkspaceRoot")
            end
        end
    end)
    logL("\n")

    -- 4. ReplicatedStorage.Data.Areas & Reset Cycles
    logL("[4] REPLICATEDSTORAGE.DATA.AREAS & RESET CYCLES (Áreas, Ilhas e Ciclos):")
    pcall(function()
        local dataF = Services.ReplicatedStorage:FindFirstChild("Data")
        if dataF then
            local aMod = dataF:FindFirstChild("Areas")
            if aMod and aMod:IsA("ModuleScript") then
                local res = require(aMod)
                if type(res) == "table" and res.Directory then
                    for aKey, aVal in pairs(res.Directory) do
                        logL(string.format("  - Área: %-15s | Dados: %s", tostring(aKey), Services.HttpService:JSONEncode(serializeTelemetry(aVal))))
                    end
                end
            end
            local cycleMod = dataF:FindFirstChild("AreaEggResetCycle")
            if cycleMod and cycleMod:IsA("ModuleScript") then
                local cRes = require(cycleMod)
                if type(cRes) == "table" then
                    logL(string.format("  - ResetCycle Dados: %s", Services.HttpService:JSONEncode(cRes)))
                end
            end
        end
    end)
    logL("\n")

    -- 5. Módulos de Ovos Especiais / Eventos
    logL("[5] REPLICATEDSTORAGE.DATA - MÓDULOS ESPECIAIS (Admin, Dragão, Sakura, Brainrot, Parasita):")
    pcall(function()
        local dataF = Services.ReplicatedStorage:FindFirstChild("Data")
        if dataF then
            for _, modName in ipairs({"LimitedEgg", "AdminAbuseEgg", "DragonEgg", "Sakura", "MonsterParasite", "BrainrotEgg"}) do
                local m = dataF:FindFirstChild(modName)
                if m and m:IsA("ModuleScript") then
                    local ok, res = pcall(require, m)
                    if ok and type(res) == "table" then
                        logL(string.format("  - Módulo %-16s | Dados: %s", modName, Services.HttpService:JSONEncode(res)))
                    else
                        logL(string.format("  - Módulo %-16s | Presente (não exportou tabela)", modName))
                    end
                end
            end
        end
    end)
    logL("\n")

    -- 6. ReplicatedStorage.AssetModels (Mapeamento Completo de MeshId -> Nome Real)
    logL("[6] REPLICATEDSTORAGE.ASSETMODELS (117 Modelos Oficiais e seus MeshIds):")
    pcall(function()
        local am = Services.ReplicatedStorage:FindFirstChild("AssetModels")
        if am then
            for _, m in ipairs(am:GetChildren()) do
                local meshList = {}
                for _, d in ipairs(m:GetDescendants()) do
                    local mId = (d:IsA("MeshPart") and d.MeshId) or (d:IsA("SpecialMesh") and d.MeshId)
                    if mId and mId ~= "" then
                        local num = tostring(mId):match("(%d+)")
                        if num then table.insert(meshList, num) end
                    end
                end
                local meshStr = #meshList > 0 and table.concat(meshList, ", ") or "Nenhuma"
                logL(string.format("  - Pet: %-25s | Meshes: [%s]", m.Name, meshStr))
            end
        end
    end)
    logL("\n")

    -- 7. Dissecção Detalhada de Workspace.AreaEggSlotsClient (Slots de Ovos Vivos)
    logL("[7] WORKSPACE.AREAEGGSLOTSCLIENT (Dissecção Completa dos Slots Vivos):")
    pcall(function()
        local slotsFolder = Services.Workspace:FindFirstChild("AreaEggSlotsClient")
        if slotsFolder then
            local slots = slotsFolder:GetChildren()
            logL("  Total de Slots Vivos no Servidor: " .. tostring(#slots))
            for i, slot in ipairs(slots) do
                local pos = getPositionOf(slot)
                local posStr = pos and string.format("(%.1f, %.1f, %.1f)", pos.X, pos.Y, pos.Z) or "N/D"
                local attrs = {}
                for k, v in pairs(slot:GetAttributes()) do table.insert(attrs, k .. "=" .. tostring(v)) end
                local attrStr = #attrs > 0 and table.concat(attrs, "; ") or "Sem Atributos"
                local childrenSummary = {}
                for _, c in ipairs(slot:GetChildren()) do
                    local cMesh = (c:IsA("MeshPart") and c.MeshId) or (c:FindFirstChildWhichIsA("SpecialMesh", true) and c:FindFirstChildWhichIsA("SpecialMesh", true).MeshId) or ""
                    local mNum = cMesh:match("(%d+)")
                    table.insert(childrenSummary, string.format("%s[%s]%s", c.Name, c.ClassName, mNum and (":" .. mNum) or ""))
                end
                local prompt = slot:FindFirstChildWhichIsA("ProximityPrompt", true)
                local pStr = prompt and string.format("Prompt: Act='%s' Obj='%s'", prompt.ActionText, prompt.ObjectText) or "Sem Prompt"
                local childStr = #childrenSummary > 0 and table.concat(childrenSummary, ", ") or "Vazio"
                logL(string.format("  #%02d Slot: %-32s | Pos: %s | %s | Filhos: %s | %s", i, slot.Name, posStr, pStr, childStr, attrStr))
            end
        end
    end)
    logL("\n")

    -- 8. Dissecção de Workspace.ClientRenderedAssets (Modelos Renderizados)
    logL("[8] WORKSPACE.CLIENTRENDEREDASSETS (Modelos Renderizados no Cliente):")
    pcall(function()
        local cra = Services.Workspace:FindFirstChild("ClientRenderedAssets")
        if cra then
            for _, c in ipairs(cra:GetChildren()) do
                local pos = getPositionOf(c)
                local posStr = pos and string.format("(%.1f, %.1f, %.1f)", pos.X, pos.Y, pos.Z) or "N/D"
                local meshList = {}
                for _, d in ipairs(c:GetDescendants()) do
                    local mId = (d:IsA("MeshPart") and d.MeshId) or (d:IsA("SpecialMesh") and d.MeshId)
                    if mId and mId ~= "" then
                        local num = tostring(mId):match("(%d+)")
                        if num then table.insert(meshList, num) end
                    end
                end
                local meshStr = #meshList > 0 and table.concat(meshList, ", ") or "Nenhuma"
                logL(string.format("  - Render: %-32s | Pos: %s | Meshes: [%s]", c.Name, posStr, meshStr))
            end
        end
    end)
    logL("\n")

    -- 9. Estado do Jogador Local e Character
    logL("[9] ESTADO DO JOGADOR LOCAL E CHARACTER:")
    pcall(function()
        logL("  DisplayName: " .. LocalPlayer.DisplayName .. " | Name: " .. LocalPlayer.Name .. " | UserId: " .. tostring(LocalPlayer.UserId))
        logL("  Atributos do Player:")
        for k, v in pairs(LocalPlayer:GetAttributes()) do
            logL(string.format("    > %s = %s", tostring(k), tostring(v)))
        end
        local char = LocalPlayer.Character
        if char then
            logL("  Atributos do Character:")
            for k, v in pairs(char:GetAttributes()) do
                logL(string.format("    > %s = %s", tostring(k), tostring(v)))
            end
            logL("  Scripts no Character:")
            for _, c in ipairs(char:GetChildren()) do
                local attrs = Services.HttpService:JSONEncode(serializeTelemetry(c).attributes or {})
                logL(string.format("    > %s [%s] Attrs=%s", c.Name, c.ClassName, attrs))
            end
        end
        local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        logL("  Backpack:")
        if backpack then
            for _, child in ipairs(backpack:GetChildren()) do
                logL(string.format("    > %s [%s] %s", child.Name, child.ClassName,
                    Services.HttpService:JSONEncode(serializeTelemetry(child).attributes or {})))
            end
        end
        local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        logL("  PlayerGui (elementos ligados a ovo/pet/venda/fusão):")
        if playerGui then
            for _, guiObject in ipairs(playerGui:GetDescendants()) do
                local low = guiObject.Name:lower()
                if low:find("egg", 1, true) or low:find("ovo", 1, true)
                    or low:find("pet", 1, true) or low:find("sell", 1, true)
                    or low:find("fuse", 1, true) or low:find("fusion", 1, true) then
                    local text = ""
                    if guiObject:IsA("TextLabel") or guiObject:IsA("TextButton") or guiObject:IsA("TextBox") then
                        text = guiObject.Text
                    end
                    logL(string.format("    > %s [%s] Text='%s'", instancePath(guiObject), guiObject.ClassName, text))
                end
            end
        end
    end)
    logL("\n")

    -- 10. Benchmark de Identificação em Tempo Real (Teste de Nomes Reais do Radar)
    local discovered = scanAllEggs()
    logL("[10] BENCHMARK DE IDENTIFICAÇÃO EM TEMPO REAL (" .. tostring(#discovered) .. " OVOS ENCONTRADOS):")
    local namedCount = 0
    local genericCount = 0
    for i, e in ipairs(discovered) do
        local lowName = e.Name:lower()
        local isGeneric = lowName:find("ovo selvagem", 1, true) or lowName:find("não identificado", 1, true)
        if isGeneric then genericCount = genericCount + 1 else namedCount = namedCount + 1 end
        logL(string.format("#%02d [%s] %-28s | Zona: %-22s | Prompt: %s | Dist: %-4dm | Pos: (%.1f, %.1f, %.1f)",
            i, e.Rarity, e.Name, e.Zone, e.Prompt and "SIM" or "NAO", math.floor(e.Distance),
            e.Position.X, e.Position.Y, e.Position.Z
        ))
    end
    logL(string.format("\n  Estatísticas do Radar: %d com Nome Real Próprio | %d Genéricos (Fallback)", namedCount, genericCount))

    logL("\n[11] CATÁLOGO APRENDIDO DURANTE A SESSÃO:")
    local learnedCount = 0
    for uid, learned in pairs(LearnedEggData) do
        learnedCount = learnedCount + 1
        logL(string.format("  - UID: %s | Pet: %s | Raridade: %s | Fonte: %s",
            uid, learned.DisplayName, learned.Rarity, learned.Source))
    end
    if learnedCount == 0 then
        logL("  Nenhuma associação UID -> pet foi exposta pelos remotes até agora.")
    end
    local visualCount = 0
    for fingerprint, learned in pairs(LearnedVisualData) do
        visualCount = visualCount + 1
        logL(string.format("  - VISUAL #%d: %s | Pet: %s | Raridade: %s | Hits: %d | Conflito: %s (%s) | Fonte: %s",
            visualCount, fingerprint:sub(1, 240), learned.DisplayName, learned.Rarity, learned.Hits or 0,
            tostring(learned.Conflicted), tostring(learned.ConflictWith or "nenhum"), learned.Source))
    end
    if visualCount == 0 then logL("  Nenhuma aparência de ovo foi associada a pet ainda.") end

    logL("\n[12] REMOTES DISPONÍVEIS NO REPLICATEDSTORAGE:")
    pcall(function()
        for _, remote in ipairs(Services.ReplicatedStorage:GetDescendants()) do
            if remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction") then
                logL(string.format("  - [%s] %s", remote.ClassName, instancePath(remote)))
            end
        end
    end)

    logL("\n[13] PROXIMITYPROMPTS ATIVOS E CONTEXTO:")
    pcall(function()
        local promptCount = 0
        for _, prompt in ipairs(Services.Workspace:GetDescendants()) do
            if prompt:IsA("ProximityPrompt") then
                promptCount = promptCount + 1
                local p = getPositionOf(prompt)
                logL(string.format("  - #%03d %s | Action='%s' Object='%s' Enabled=%s Hold=%.2f Max=%.1f Pos=%s",
                    promptCount, instancePath(prompt), prompt.ActionText, prompt.ObjectText,
                    tostring(prompt.Enabled), prompt.HoldDuration, prompt.MaxActivationDistance,
                    p and string.format("(%.1f, %.1f, %.1f)", p.X, p.Y, p.Z) or "N/D"))
            end
        end
    end)

    logL("\n[14] ESTADO DO HUB E TELEMETRIA DA SESSÃO:")
    logL(string.format("  Sessão: %s | Trace: %s | Duração: %.1fs", Telemetry.SessionId,
        Telemetry.FileName, os.clock() - Telemetry.StartedAt))
    logL(string.format("  Máquina: %s | Carry=%s | Evidência=%s | AutoRoubo=%s | AutoEsteira=%s | NaEsteira=%s",
        StealSM.Current, tostring(State.CarryConfirmed), tostring(State.CarryEvidence),
        tostring(Config.AutoStealEnabled), tostring(Config.AutoEsteiraEnabled), tostring(State.IsOnTreadmill)))
    logL(string.format("  Velocidade=%d | Alcance=%d | Alvo=%s", Config.MoveSpeed,
        Config.MaxStealDistance, StealSM.Target and StealSM.Target.Name or "Nenhum"))
    logL("  Contagem por categoria:")
    for category, count in pairs(Telemetry.Counts) do
        logL(string.format("    > %s = %d", category, count))
    end
    logL("  Candidatos de esteira replicados:")
    local treadmillRenders = Services.Workspace:FindFirstChild("__ClientTreadmillRenders")
    if treadmillRenders then
        for _, render in ipairs(treadmillRenders:GetChildren()) do
            local renderPos = getPositionOf(render)
            local parts = {}
            for _, desc in ipairs(render:GetDescendants()) do
                if desc:IsA("BasePart") then
                    table.insert(parts, string.format("%s(%.1fx%.1fx%.1f)", desc.Name,
                        desc.Size.X, desc.Size.Y, desc.Size.Z))
                end
            end
            logL(string.format("    > %s [%s] Pos=%s Parts=%s", render.Name, render.ClassName,
                renderPos and string.format("(%.1f, %.1f, %.1f)", renderPos.X, renderPos.Y, renderPos.Z) or "N/D",
                #parts > 0 and table.concat(parts, ", ") or "nenhuma"))
        end
    else
        logL("    > Pasta __ClientTreadmillRenders não existe neste cliente.")
    end
    logL("  Últimos eventos JSONL (máximo 400):")
    local firstRecent = math.max(1, #Telemetry.Recent - 399)
    for index = firstRecent, #Telemetry.Recent do
        logL("    " .. Telemetry.Recent[index])
    end

    logL("\n================================================================================")
    logL("FIM DO INVENTARIO.")

    local fullText = table.concat(lines, "\n")
    pcall(function()
        if writefile then writefile("ROUBE_UM_OVO_DUMP.txt", fullText) end
        if setclipboard then setclipboard(fullText) end
    end)
    addLog("INSPETOR", "Dump Observatory v13 exportado! (" .. tostring(#discovered) .. " ovos) - Copiado para o Clipboard!")
    return fullText, #discovered
end

-- 11. ESP com Cores Reais por Raridade
local activeESPs = {}
local function clearAllESP()
    for target, item in pairs(activeESPs) do
        pcall(function() if item and item.Parent then item:Destroy() end end)
    end
    activeESPs = {}
end

local RarityColors = {
    ["N/D"] = Color3.fromRGB(148, 163, 184),
    ["DIVINE"] = Color3.fromRGB(244, 63, 94),
    ["TITAN"] = Color3.fromRGB(236, 72, 153),
    ["ADMIN ABUSE"] = Color3.fromRGB(239, 68, 68),
    ["EXCLUSIVE"] = Color3.fromRGB(234, 179, 8),
    ["MONSTER PARASITE"] = Color3.fromRGB(168, 85, 247),
    ["DRAGON"] = Color3.fromRGB(249, 115, 22),
    ["SAKURA"] = Color3.fromRGB(244, 114, 182),
    ["BRAINROT"] = Color3.fromRGB(34, 197, 94),
    ["LIMITED"] = Color3.fromRGB(234, 179, 8),
    ["SECRET"] = Color3.fromRGB(168, 85, 247),
    ["ETERNAL"] = Color3.fromRGB(217, 70, 239),
    ["COSMIC"] = Color3.fromRGB(99, 102, 241),
    ["MYTHIC"] = Color3.fromRGB(244, 63, 94),
    ["MYTHICAL"] = Color3.fromRGB(244, 63, 94),
    ["MÍTICO"] = Color3.fromRGB(244, 63, 94),
    ["LEGENDARY"] = Color3.fromRGB(245, 158, 11),
    ["LENDÁRIO"] = Color3.fromRGB(245, 158, 11),
    ["EPIC"] = Color3.fromRGB(168, 85, 247),
    ["ÉPICO"] = Color3.fromRGB(168, 85, 247),
    ["RARE"] = Color3.fromRGB(56, 189, 248),
    ["RARO"] = Color3.fromRGB(56, 189, 248),
    ["UNCOMMON"] = Color3.fromRGB(34, 197, 94),
    ["INCOMUM"] = Color3.fromRGB(34, 197, 94),
    ["COMMON"] = Color3.fromRGB(148, 163, 184),
    ["COMUM"] = Color3.fromRGB(148, 163, 184)
}

local function updateESP()
    clearAllESP()
    if not Config.ESPEnabled then return end

    local eggs = scanAllEggs()
    local myHrp = getHRP()
    local myPos = myHrp and myHrp.Position or Vector3.zero

    for _, egg in ipairs(eggs) do
        if not (Config.ShowOnlyUnowned and egg.IsMyPlot) then
            local dist = (egg.Position - myPos).Magnitude
            if dist <= Config.MaxStealDistance then
                local adornee = egg.Instance:IsA("BasePart") and egg.Instance
                    or egg.Instance:FindFirstChildWhichIsA("BasePart", true)

                if adornee then
                    local color = RarityColors[egg.Rarity:upper()] or Color3.fromRGB(56, 189, 248)

                    local bb = Instance.new("BillboardGui")
                    bb.Name = "ESP_EggLabel"
                    bb.Adornee = adornee
                    bb.Size = UDim2.new(0, 150, 0, 36)
                    bb.StudsOffset = Vector3.new(0, 3.2, 0)
                    bb.AlwaysOnTop = true
                    bb.Parent = adornee

                    local tag = Instance.new("TextLabel")
                    tag.Size = UDim2.new(1, 0, 1, 0)
                    tag.BackgroundTransparency = 1
                    tag.Font = Enum.Font.GothamBold
                    tag.TextSize = 10
                    tag.TextColor3 = color
                    tag.TextStrokeTransparency = 0.2
                    tag.TextStrokeColor3 = Color3.fromRGB(10, 15, 29)
                    local incStr = egg.Income and (" • " .. egg.Income) or ""
                    tag.Text = string.format("[%s] %s\n%dm%s", egg.Rarity, egg.Name, math.floor(dist), incStr)
                    tag.Parent = bb

                    activeESPs[adornee] = bb
                end
            end
        end
    end
end

task.spawn(function()
    while not State.IsUnloaded do
        if Config.ESPEnabled then
            local ok, err = pcall(updateESP)
            if not ok then
                warn("[RoubeUmOvo][ESP] " .. tostring(err))
            end
        end
        task.wait(1.5)
    end
end)



--================================================================--
-- 12. INTERFACE OBSERVATORY v13.1 (4 ÁREAS ESSENCIAIS)
--================================================================--

ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "RoubeUmOvoMasterHub"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

attachGui(ScreenGui)


local function addCorner(instance, rad)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, rad or 8)
    corner.Parent = instance
    return corner
end

local function addStroke(instance, color, thick)
    local stroke = Instance.new("UIStroke")
    stroke.Color = color or C_BORDER
    stroke.Thickness = thick or 1
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = instance
    return stroke
end

local function createCleanCard(parent, height)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, height or 60)
    card.BackgroundColor3 = C_CARD
    card.BorderSizePixel = 0
    card.Parent = parent
    addCorner(card, 8)
    addStroke(card, C_BORDER, 1)
    return card
end

-- Janela principal com mais respiro visual e somente controles funcionais.
MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 660, 0, 500)
MainFrame.Position = UDim2.new(0.5, -330, 0.5, -250)
MainFrame.BackgroundColor3 = C_BG
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui
addCorner(MainFrame, 10)
addStroke(MainFrame, C_BORDER, 1.2)

-- Topbar
local Topbar = Instance.new("Frame")
Topbar.Size = UDim2.new(1, 0, 0, 42)
Topbar.BackgroundColor3 = C_TOPBAR
Topbar.BorderSizePixel = 0
Topbar.Parent = MainFrame
addCorner(Topbar, 10)

local TopbarSquare = Instance.new("Frame")
TopbarSquare.Size = UDim2.new(1, 0, 0, 10)
TopbarSquare.Position = UDim2.new(0, 0, 1, -10)
TopbarSquare.BackgroundColor3 = C_TOPBAR
TopbarSquare.BorderSizePixel = 0
TopbarSquare.Parent = Topbar

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(0, 255, 1, 0)
Title.Position = UDim2.new(0, 14, 0, 0)
Title.BackgroundTransparency = 1
Title.Font = Enum.Font.GothamBold
Title.TextSize = 13
Title.TextColor3 = C_CYAN
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Text = "ROUBE UM OVO  •  STABILITY v13.1"
Title.Parent = Topbar

StatusBadge = Instance.new("TextLabel")
StatusBadge.Size = UDim2.new(0, 100, 0, 22)
StatusBadge.Position = UDim2.new(0, 292, 0.5, -11)
StatusBadge.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
StatusBadge.Text = "PARADO"
StatusBadge.Font = Enum.Font.GothamBold
StatusBadge.TextSize = 10
StatusBadge.TextColor3 = C_MUTED
StatusBadge.Parent = Topbar
addCorner(StatusBadge, 11)
addStroke(StatusBadge, C_BORDER, 1)

local UnloadBtn = Instance.new("TextButton")
UnloadBtn.Size = UDim2.new(0, 68, 0, 24)
UnloadBtn.Position = UDim2.new(1, -104, 0.5, -12)
UnloadBtn.BackgroundColor3 = Color3.fromRGB(153, 27, 27)
UnloadBtn.Text = "UNLOAD"
UnloadBtn.Font = Enum.Font.GothamBold
UnloadBtn.TextSize = 10
UnloadBtn.TextColor3 = C_TEXT
UnloadBtn.Parent = Topbar
addCorner(UnloadBtn, 6)

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 24, 0, 24)
CloseBtn.Position = UDim2.new(1, -30, 0.5, -12)
CloseBtn.BackgroundColor3 = Color3.fromRGB(51, 65, 85)
CloseBtn.Text = "X"
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 11
CloseBtn.TextColor3 = C_TEXT
CloseBtn.Parent = Topbar
addCorner(CloseBtn, 6)

CloseBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = false
end)

-- Navegação lateral enxuta: rotas/TP e modificadores instáveis foram removidos.
local TabBar = Instance.new("Frame")
TabBar.Size = UDim2.new(0, 124, 1, -70)
TabBar.Position = UDim2.new(0, 12, 0, 58)
TabBar.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
TabBar.BorderSizePixel = 0
TabBar.Parent = MainFrame
addCorner(TabBar, 8)

local TabButtons = {}
local TabPages = {}
local tabNames = {"Automação", "Esteira", "Radar", "Diagnóstico"}
local activeTab = "Automação"

local ContentArea = Instance.new("Frame")
ContentArea.Size = UDim2.new(1, -160, 1, -70)
ContentArea.Position = UDim2.new(0, 148, 0, 58)
ContentArea.BackgroundTransparency = 1
ContentArea.BorderSizePixel = 0
ContentArea.Parent = MainFrame

local function switchTab(name)
    activeTab = name
    for tName, btn in pairs(TabButtons) do
        local isCur = (tName == name)
        btn.BackgroundColor3 = isCur and Color3.fromRGB(30, 44, 74) or Color3.fromRGB(15, 23, 42)
        btn.TextColor3 = isCur and C_CYAN or C_MUTED
    end
    for pName, page in pairs(TabPages) do
        page.Visible = (pName == name)
    end
end

for i, tName in ipairs(tabNames) do
    local displayName = tName
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -8, 0, 40)
    btn.Position = UDim2.new(0, 4, 0, 4 + ((i - 1) * 46))
    btn.BackgroundColor3 = (tName == activeTab) and Color3.fromRGB(30, 44, 74) or Color3.fromRGB(15, 23, 42)
    btn.Text = displayName
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 10
    btn.TextColor3 = (tName == activeTab) and C_CYAN or C_MUTED
    btn.Parent = TabBar
    addCorner(btn, 6)

    btn.MouseButton1Click:Connect(function()
        switchTab(tName)
    end)
    TabButtons[tName] = btn

    local page = Instance.new("ScrollingFrame")
    page.Name = tName .. "Page"
    page.Size = UDim2.new(1, 0, 1, 0)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 3
    page.ScrollBarImageColor3 = C_CYAN
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.CanvasSize = UDim2.new(0, 0, 0, 0)
    page.Visible = (tName == activeTab)
    page.Parent = ContentArea

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 8)
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = page

    TabPages[tName] = page
end

local TraceSidebarLabel = Instance.new("TextLabel")
TraceSidebarLabel.Size = UDim2.new(1, -12, 0, 38)
TraceSidebarLabel.Position = UDim2.new(0, 6, 1, -46)
TraceSidebarLabel.BackgroundTransparency = 1
TraceSidebarLabel.Font = Enum.Font.GothamBold
TraceSidebarLabel.TextSize = 9
TraceSidebarLabel.TextColor3 = C_GREEN
TraceSidebarLabel.TextWrapped = true
TraceSidebarLabel.Text = "● TRACE ATIVO\n" .. Telemetry.SessionId
TraceSidebarLabel.Parent = TabBar

--================================================================--
-- ABA 1: AUTO-ROUBO
--================================================================--
local AutoStealPage = TabPages["Automação"]

MainToggleBtn = Instance.new("TextButton")
MainToggleBtn.Size = UDim2.new(1, 0, 0, 46)
MainToggleBtn.BackgroundColor3 = Config.AutoStealEnabled and Color3.fromRGB(22, 101, 52) or Color3.fromRGB(30, 41, 59)
MainToggleBtn.Text = Config.AutoStealEnabled and "AUTO-ROUBO ATIVADO (EM EXECUCAO)" or "ATIVAR AUTO-ROUBO"
MainToggleBtn.Font = Enum.Font.GothamBold
MainToggleBtn.TextSize = 12
MainToggleBtn.TextColor3 = C_TEXT
MainToggleBtn.Parent = AutoStealPage
addCorner(MainToggleBtn, 8)
addStroke(MainToggleBtn, Config.AutoStealEnabled and C_GREEN or C_CYAN, 1.2)

-- Card da Base (Completamente Legível)
local BaseCard = createCleanCard(AutoStealPage, 54)
BaseLabel = Instance.new("TextLabel")
BaseLabel.Size = UDim2.new(0.66, -10, 1, 0)
BaseLabel.Position = UDim2.new(0, 14, 0, 0)
BaseLabel.BackgroundTransparency = 1
BaseLabel.Font = Enum.Font.GothamBold
BaseLabel.TextSize = 11
BaseLabel.TextColor3 = C_MUTED
BaseLabel.TextXAlignment = Enum.TextXAlignment.Left
BaseLabel.Text = "Base: Identificando plot..."
BaseLabel.Parent = BaseCard

local SetBaseBtn = Instance.new("TextButton")
SetBaseBtn.Size = UDim2.new(0.34, -10, 0, 32)
SetBaseBtn.Position = UDim2.new(0.66, 0, 0.5, -16)
SetBaseBtn.BackgroundColor3 = Color3.fromRGB(30, 44, 74)
SetBaseBtn.Text = "FIXAR BASE"
SetBaseBtn.Font = Enum.Font.GothamBold
SetBaseBtn.TextSize = 11
SetBaseBtn.TextColor3 = C_CYAN
SetBaseBtn.Parent = BaseCard
addCorner(SetBaseBtn, 6)
addStroke(SetBaseBtn, C_CYAN, 1)

SetBaseBtn.MouseButton1Click:Connect(function()
    local hrp = getHRP()
    if hrp then
        State.BaseCFrame = hrp.CFrame
        BaseLabel.Text = string.format("Base: (%.0f, %.0f, %.0f) [Fixada]", hrp.Position.X, hrp.Position.Y, hrp.Position.Z)
        BaseLabel.TextColor3 = C_GREEN
        addLog("BASE", "Base fixada manualmente na posicao atual.")
    end
end)

-- Card Alvo Prioritário (Amplo, Limpo e Informativo)
local TargetCard = createCleanCard(AutoStealPage, 68)
local TargetTitle = Instance.new("TextLabel")
TargetTitle.Size = UDim2.new(1, -20, 0, 18)
TargetTitle.Position = UDim2.new(0, 14, 0, 10)
TargetTitle.BackgroundTransparency = 1
TargetTitle.Font = Enum.Font.GothamBold
TargetTitle.TextSize = 11
TargetTitle.TextColor3 = C_CYAN
TargetTitle.TextXAlignment = Enum.TextXAlignment.Left
TargetTitle.Text = Config.LockCurrentIsland and "ALVO PRIORITARIO (ILHA ATUAL):" or "ALVO PRIORITARIO (TODO O MAPA):"
TargetTitle.Parent = TargetCard

TargetInfoLabel = Instance.new("TextLabel")
TargetInfoLabel.Size = UDim2.new(1, -20, 0, 26)
TargetInfoLabel.Position = UDim2.new(0, 14, 0, 32)
TargetInfoLabel.BackgroundTransparency = 1
TargetInfoLabel.Font = Enum.Font.GothamBold
TargetInfoLabel.TextSize = 12
TargetInfoLabel.TextColor3 = C_TEXT
TargetInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
TargetInfoLabel.Text = "Buscando ovos..."
TargetInfoLabel.Parent = TargetCard

MainToggleBtn.MouseButton1Click:Connect(function()
    Config.AutoStealEnabled = not Config.AutoStealEnabled
    if Config.AutoStealEnabled then
        Config.AutoEsteiraEnabled = false
        State.IsOnTreadmill = false
        if EsteiraToggleBtn then
            EsteiraToggleBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
            EsteiraToggleBtn.Text = "ATIVAR AUTO-ESTEIRA (TREINO)"
            addStroke(EsteiraToggleBtn, C_CYAN, 1)
        end
    end
    MainToggleBtn.BackgroundColor3 = Config.AutoStealEnabled and C_GREEN or Color3.fromRGB(30, 41, 59)
    MainToggleBtn.Text = Config.AutoStealEnabled and "AUTO-ROUBO ATIVADO (EM EXECUCAO)" or "ATIVAR AUTO-ROUBO"
    addStroke(MainToggleBtn, Config.AutoStealEnabled and C_GREEN or C_CYAN, 1)
    StatusBadge.Text = Config.AutoStealEnabled and "ROUBANDO" or "PARADO"
    StatusBadge.TextColor3 = Config.AutoStealEnabled and C_GREEN or C_MUTED
    addLog("ROUBO", Config.AutoStealEnabled and "Auto-roubo iniciado." or "Auto-roubo desativado.")
end)

--================================================================--
-- ABA 2: AUTO-ESTEIRA (TREINO CONTINUO SEM TRAVAR)
--================================================================--
local AutoEsteiraPage = TabPages["Esteira"]

local EsteiraDescCard = createCleanCard(AutoEsteiraPage, 45)
local EsteiraDesc = Instance.new("TextLabel")
EsteiraDesc.Size = UDim2.new(1, -20, 1, 0)
EsteiraDesc.Position = UDim2.new(0, 10, 0, 0)
EsteiraDesc.BackgroundTransparency = 1
EsteiraDesc.Font = Enum.Font.Gotham
EsteiraDesc.TextSize = 9
EsteiraDesc.TextColor3 = C_MUTED
EsteiraDesc.TextWrapped = true
EsteiraDesc.TextXAlignment = Enum.TextXAlignment.Left
EsteiraDesc.Text = "Treina continuamente na esteira da sua propria base. Quando estiver na esteira, o personagem corre sem parar (sem entrar no estado travado/parado)."
EsteiraDesc.Parent = EsteiraDescCard

EsteiraToggleBtn = Instance.new("TextButton")
EsteiraToggleBtn.Size = UDim2.new(1, 0, 0, 42)
EsteiraToggleBtn.BackgroundColor3 = Config.AutoEsteiraEnabled and C_GREEN or Color3.fromRGB(30, 41, 59)
EsteiraToggleBtn.Text = Config.AutoEsteiraEnabled and "AUTO-ESTEIRA ATIVADA (TREINANDO)" or "ATIVAR AUTO-ESTEIRA (TREINO)"
EsteiraToggleBtn.Font = Enum.Font.GothamBold
EsteiraToggleBtn.TextSize = 11
EsteiraToggleBtn.TextColor3 = C_TEXT
EsteiraToggleBtn.Parent = AutoEsteiraPage
addCorner(EsteiraToggleBtn, 8)
addStroke(EsteiraToggleBtn, Config.AutoEsteiraEnabled and C_GREEN or C_CYAN, 1)

local GoToEsteiraBtn = Instance.new("TextButton")
GoToEsteiraBtn.Size = UDim2.new(1, 0, 0, 32)
GoToEsteiraBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
GoToEsteiraBtn.Text = "IR PARA MINHA ESTEIRA AGORA"
GoToEsteiraBtn.Font = Enum.Font.GothamBold
GoToEsteiraBtn.TextSize = 9
GoToEsteiraBtn.TextColor3 = C_CYAN
GoToEsteiraBtn.Parent = AutoEsteiraPage
addCorner(GoToEsteiraBtn, 6)
addStroke(GoToEsteiraBtn, C_BORDER, 1)

local EsteiraStatusCard = createCleanCard(AutoEsteiraPage, 50)
EsteiraStatusLabel = Instance.new("TextLabel")
EsteiraStatusLabel.Size = UDim2.new(1, -20, 1, 0)
EsteiraStatusLabel.Position = UDim2.new(0, 12, 0, 0)
EsteiraStatusLabel.BackgroundTransparency = 1
EsteiraStatusLabel.Font = Enum.Font.Gotham
EsteiraStatusLabel.TextSize = 10
EsteiraStatusLabel.TextColor3 = C_MUTED
EsteiraStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
EsteiraStatusLabel.Text = "Esteira: Detectando..."
EsteiraStatusLabel.Parent = EsteiraStatusCard

-- Funcao para achar esteira da propria base
local treadmillCache = { At = 0, Part = nil }
local function findMyTreadmill()
    if os.clock() - treadmillCache.At < 2 then
        local cachedPart = treadmillCache.Part
        if cachedPart and cachedPart.Parent then
            return cachedPart, cachedPart.Position + Vector3.new(0, 1.5, 0)
        end
        return nil, nil
    end
    treadmillCache.At = os.clock()
    treadmillCache.Part = nil

    local function cachePart(part)
        treadmillCache.Part = part
        return part, part.Position + Vector3.new(0, 1.5, 0)
    end

    local myPlot = findMyPlot()
    local plotCenter = myPlot and myPlot:GetPivot().Position
        or (State.BaseCFrame and State.BaseCFrame.Position)
    if not plotCenter then return nil, nil end

    local function getTreadmillPart(root)
        if root:IsA("BasePart") then return root end
        local fallback = nil
        local largestArea = 0
        for _, desc in ipairs(root:GetDescendants()) do
            if desc:IsA("BasePart") then
                local low = desc.Name:lower()
                if low:find("treadmill", 1, true) or low:find("esteira", 1, true)
                    or low:find("belt", 1, true) or low:find("run", 1, true) then
                    return desc
                end
                local area = desc.Size.X * desc.Size.Z
                if area > largestArea then
                    largestArea = area
                    fallback = desc
                end
            end
        end
        return fallback
    end

    -- Primeiro use uma peça real que pertença ao próprio plot.
    for _, desc in ipairs(myPlot and myPlot:GetDescendants() or {}) do
        local low = desc.Name:lower()
        if low:find("treadmill", 1, true) or low:find("esteira", 1, true)
            or low:find("conveyor", 1, true) or low:find("belt", 1, true) then
            local part = getTreadmillPart(desc)
            if part then return cachePart(part) end
        end
    end

    -- Renders do cliente podem ficar fora da hierarquia do plot. Priorize o
    -- UserId no nome e, como fallback, a menor distância horizontal.
    local ctr = Services.Workspace:FindFirstChild("__ClientTreadmillRenders")
    if ctr then
        local bestCandidate = nil
        local bestPart = nil
        local bestScore = math.huge
        local myId = tostring(LocalPlayer.UserId)
        for _, child in ipairs(ctr:GetChildren()) do
            local part = getTreadmillPart(child)
            if part then
                local delta = part.Position - plotCenter
                local horizontalDistance = Vector3.new(delta.X, 0, delta.Z).Magnitude
                local ownerMatch = child.Name:find(myId, 1, true) ~= nil
                local score = ownerMatch and (horizontalDistance - 1000) or horizontalDistance
                if (ownerMatch or horizontalDistance <= 240) and score < bestScore then
                    bestScore = score
                    bestCandidate = child
                    bestPart = part
                end
            end
        end
        if bestCandidate and bestPart then
            traceEvent("TREADMILL", "FOUND_RENDER", {
                container = bestCandidate,
                part = bestPart,
                plot = myPlot,
                distanceFromPlot = Vector3.new(bestPart.Position.X - plotCenter.X, 0, bestPart.Position.Z - plotCenter.Z).Magnitude,
            })
            return cachePart(bestPart)
        end
    end


    -- Último fallback: alguns servidores não usam __ClientTreadmillRenders.
    -- Considere apenas objetos explicitamente nomeados e próximos ao nosso plot.
    local nearestPart = nil
    local nearestDistance = math.huge
    for _, desc in ipairs(Services.Workspace:GetDescendants()) do
        local low = desc.Name:lower()
        if low:find("treadmill", 1, true) or low:find("esteira", 1, true) then
            local part = getTreadmillPart(desc)
            if part then
                local delta = part.Position - plotCenter
                local distance = Vector3.new(delta.X, 0, delta.Z).Magnitude
                if distance <= 240 and distance < nearestDistance then
                    nearestDistance = distance
                    nearestPart = part
                end
            end
        end
    end
    if nearestPart then
        traceEvent("TREADMILL", "FOUND_NAMED_FALLBACK", {
            part = nearestPart,
            plot = myPlot,
            distanceFromPlot = nearestDistance,
        })
        return cachePart(nearestPart)
    end

    return nil, nil
end

GoToEsteiraBtn.MouseButton1Click:Connect(function()
    local _, tPos = findMyTreadmill()
    if tPos then
        task.spawn(function()
            addLog("ESTEIRA", "Caminhando até a sua esteira...")
            local arrived = movePlayerSafe(tPos, Config.MoveSpeed)
            addLog("ESTEIRA", arrived and "Chegou à esteira." or "Não foi possível calcular uma rota segura.")
        end)
    else
        addLog("ESTEIRA", "Esteira real não encontrada no seu plot.")
    end
end)

-- Conexao de corrida continua no Heartbeat (resolve 100% o estado parado)
local esteiraHeartbeatConn = nil
local treadmillNavigating = false
local lastTreadmillMode = "OFF"
local function setupEsteiraRunner()
    if esteiraHeartbeatConn then esteiraHeartbeatConn:Disconnect() end
    esteiraHeartbeatConn = Services.RunService.Heartbeat:Connect(function()
        if State.IsUnloaded or not Config.AutoEsteiraEnabled then return end
        
        local holding = isHoldingEgg()
        if State.IsExecutingSteal or holding then
            State.IsOnTreadmill = false
            if lastTreadmillMode ~= "BLOCKED" then
                lastTreadmillMode = "BLOCKED"
                traceEvent("TREADMILL", "BLOCKED", { stealing = State.IsExecutingSteal, holding = holding })
            end
            return
        end

        local hrp = getHRP()
        local hum = getHum()
        if not hrp or not hum or hum.Health <= 0 then
            State.IsOnTreadmill = false
            return
        end

        local tPart, tPos = findMyTreadmill()
        if not tPos then
            State.IsOnTreadmill = false
            if lastTreadmillMode ~= "NOT_FOUND" then
                lastTreadmillMode = "NOT_FOUND"
                traceEvent("TREADMILL", "NOT_FOUND", {})
            end
            return
        end

        local hDist = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(tPos.X, 0, tPos.Z)).Magnitude

        if hDist > 4.0 then
            State.IsOnTreadmill = false
            if lastTreadmillMode ~= "RETURNING" then
                lastTreadmillMode = "RETURNING"
                traceEvent("TREADMILL", "RETURNING", { distance = hDist, target = tPos })
                addLog("ESTEIRA", "Você saiu da esteira; retornando automaticamente.")
            end
            if not treadmillNavigating and not isMoving then
                treadmillNavigating = true
                task.spawn(function()
                    movePlayerSafe(tPos, Config.MoveSpeed)
                    treadmillNavigating = false
                end)
            end
            return
        end
        State.IsOnTreadmill = true
        if lastTreadmillMode ~= "RUNNING" then
            lastTreadmillMode = "RUNNING"
            traceEvent("TREADMILL", "RUNNING", { position = hrp.Position })
        end
        if StatusBadge and StatusBadge.Text ~= "NA ESTEIRA" then
            StatusBadge.Text = "NA ESTEIRA"
            StatusBadge.TextColor3 = C_YELLOW
        end
        -- O minigame lê MoveDirection; esta é a direção usada pela esteira do
        -- mapa, independentemente da orientação visual da peça escolhida.
        hum:Move(Vector3.new(0, 0, -1), false)
    end)
    table.insert(ScriptConnections, esteiraHeartbeatConn)
end

setupEsteiraRunner()

EsteiraToggleBtn.MouseButton1Click:Connect(function()
    Config.AutoEsteiraEnabled = not Config.AutoEsteiraEnabled
    traceEvent("TREADMILL", Config.AutoEsteiraEnabled and "ENABLED" or "DISABLED", {})
    if Config.AutoEsteiraEnabled then
        Config.AutoStealEnabled = false
        setStealState("IDLE")
        MainToggleBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
        MainToggleBtn.Text = "ATIVAR AUTO-ROUBO"
        addStroke(MainToggleBtn, C_CYAN, 1)
    end
    EsteiraToggleBtn.BackgroundColor3 = Config.AutoEsteiraEnabled and C_GREEN or Color3.fromRGB(30, 41, 59)
    EsteiraToggleBtn.Text = Config.AutoEsteiraEnabled and "AUTO-ESTEIRA ATIVADA (TREINANDO)" or "ATIVAR AUTO-ESTEIRA (TREINO)"
    addStroke(EsteiraToggleBtn, Config.AutoEsteiraEnabled and C_GREEN or C_CYAN, 1)
    if not Config.AutoEsteiraEnabled then
        lastTreadmillMode = "OFF"
        State.IsOnTreadmill = false
        local hum = getHum()
        if hum then hum:Move(Vector3.zero, false) end
        StatusBadge.Text = Config.AutoStealEnabled and "ROUBANDO" or "PARADO"
        StatusBadge.TextColor3 = Config.AutoStealEnabled and C_GREEN or C_MUTED
    end
    addLog("ESTEIRA", Config.AutoEsteiraEnabled and "Auto-Esteira iniciada." or "Auto-Esteira desativada.")
end)

--================================================================--
-- ABA 3: RADAR DE OVOS & ESP 3D
--================================================================--
local RadarPage = TabPages["Radar"]

local RadarControlsCard = createCleanCard(RadarPage, 48)
local SearchInput = Instance.new("TextBox")
SearchInput.Size = UDim2.new(0.66, -10, 0, 34)
SearchInput.Position = UDim2.new(0, 10, 0.5, -17)
SearchInput.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
SearchInput.PlaceholderText = "Buscar ovo (Godzilla, Kitsune, T-Rex...)"
SearchInput.PlaceholderColor3 = C_MUTED
SearchInput.Text = ""
SearchInput.Font = Enum.Font.Gotham
SearchInput.TextSize = 11
SearchInput.TextColor3 = C_TEXT
SearchInput.Parent = RadarControlsCard
addCorner(SearchInput, 6)
addStroke(SearchInput, C_BORDER, 1)

local EspToggleBtn = Instance.new("TextButton")
EspToggleBtn.Size = UDim2.new(0.34, -10, 0, 34)
EspToggleBtn.Position = UDim2.new(0.66, 0, 0.5, -17)
EspToggleBtn.BackgroundColor3 = Config.ESPEnabled and Color3.fromRGB(22, 101, 52) or Color3.fromRGB(30, 44, 74)
EspToggleBtn.Text = Config.ESPEnabled and "[ESP: ATIVO]" or "[ESP: DESATIVADO]"
EspToggleBtn.Font = Enum.Font.GothamBold
EspToggleBtn.TextSize = 11
EspToggleBtn.TextColor3 = Config.ESPEnabled and Color3.fromRGB(74, 222, 128) or C_MUTED
EspToggleBtn.Parent = RadarControlsCard
addCorner(EspToggleBtn, 6)
addStroke(EspToggleBtn, Config.ESPEnabled and C_GREEN or C_BORDER, 1)

local EggListFrame = Instance.new("Frame")
EggListFrame.Size = UDim2.new(1, 0, 0, 0)
EggListFrame.AutomaticSize = Enum.AutomaticSize.Y
EggListFrame.BackgroundTransparency = 1
EggListFrame.Parent = RadarPage

local eggListLayout = Instance.new("UIListLayout")
eggListLayout.Padding = UDim.new(0, 6)
eggListLayout.SortOrder = Enum.SortOrder.LayoutOrder
eggListLayout.Parent = EggListFrame

local function executeCleanRadarScan()
    if State.IsUnloaded then return end
    local eggs = scanAllEggs()
    for _, child in ipairs(EggListFrame:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end

    local query = SearchInput.Text:lower()
    local count = 0

    for _, egg in ipairs(eggs) do
        if query == "" or egg.Name:lower():find(query) or egg.Rarity:lower():find(query) then
            count = count + 1
            if count > 25 then break end

            local card = Instance.new("Frame")
            card.Size = UDim2.new(1, 0, 0, 54)
            card.BackgroundColor3 = C_CARD
            card.BorderSizePixel = 0
            card.Parent = EggListFrame
            addCorner(card, 8)
            addStroke(card, C_BORDER, 1)

            local rColor = C_CYAN
            if egg.Rarity == "TITAN" then rColor = Color3.fromRGB(239, 68, 68)
            elseif egg.Rarity == "DIVINE" then rColor = Color3.fromRGB(56, 189, 248)
            elseif egg.Rarity == "ETERNAL" then rColor = Color3.fromRGB(168, 85, 247)
            elseif egg.Rarity == "SECRET" then rColor = Color3.fromRGB(236, 72, 153)
            elseif egg.Rarity == "COSMIC" then rColor = Color3.fromRGB(99, 102, 241)
            elseif egg.Rarity:find("M") then rColor = Color3.fromRGB(249, 115, 22) end

            local RarityTag = Instance.new("TextLabel")
            RarityTag.Size = UDim2.new(0, 68, 0, 22)
            RarityTag.Position = UDim2.new(0, 10, 0.5, -11)
            RarityTag.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
            RarityTag.Text = egg.Rarity
            RarityTag.Font = Enum.Font.GothamBold
            RarityTag.TextSize = 9
            RarityTag.TextColor3 = rColor
            RarityTag.Parent = card
            addCorner(RarityTag, 5)
            addStroke(RarityTag, rColor, 1.2)

            local NameLabel = Instance.new("TextLabel")
            NameLabel.Size = UDim2.new(1, -145, 0, 18)
            NameLabel.Position = UDim2.new(0, 86, 0, 8)
            NameLabel.BackgroundTransparency = 1
            NameLabel.Font = Enum.Font.GothamBold
            NameLabel.TextSize = 12
            NameLabel.TextColor3 = C_TEXT
            NameLabel.TextXAlignment = Enum.TextXAlignment.Left
            NameLabel.Text = egg.Name
            NameLabel.Parent = card

            local incBadge = egg.Income and (" • " .. egg.Income) or ""
            local InfoLabel = Instance.new("TextLabel")
            InfoLabel.Size = UDim2.new(1, -145, 0, 16)
            InfoLabel.Position = UDim2.new(0, 86, 0, 28)
            InfoLabel.BackgroundTransparency = 1
            InfoLabel.Font = Enum.Font.Gotham
            InfoLabel.TextSize = 10
            InfoLabel.TextColor3 = C_MUTED
            InfoLabel.TextXAlignment = Enum.TextXAlignment.Left
            InfoLabel.Text = string.format("Dist: %dm%s • %s", math.floor(egg.Distance), incBadge, egg.Zone or "Selvagem")
            InfoLabel.Parent = card

            local GoBtn = Instance.new("TextButton")
            GoBtn.Size = UDim2.new(0, 44, 0, 30)
            GoBtn.Position = UDim2.new(1, -54, 0.5, -15)
            GoBtn.BackgroundColor3 = Color3.fromRGB(30, 44, 74)
            GoBtn.Text = "IR"
            GoBtn.Font = Enum.Font.GothamBold
            GoBtn.TextSize = 11
            GoBtn.TextColor3 = C_CYAN
            GoBtn.Parent = card
            addCorner(GoBtn, 6)
            addStroke(GoBtn, C_CYAN, 1)

            local eggPos = egg.Position
            GoBtn.MouseButton1Click:Connect(function()
                if eggPos and not isMoving then
                    task.spawn(function()
                        addLog("ROTA", "Calculando caminho seguro para: " .. egg.Name)
                        local arrived = movePlayerSafe(eggPos, Config.MoveSpeed)
                        addLog("ROTA", arrived and "Destino alcançado." or "Não existe rota segura até esse ovo.")
                    end)
                end
            end)
        end
    end
end

SearchInput:GetPropertyChangedSignal("Text"):Connect(function()
    executeCleanRadarScan()
end)

EspToggleBtn.MouseButton1Click:Connect(function()
    Config.ESPEnabled = not Config.ESPEnabled
    EspToggleBtn.BackgroundColor3 = Config.ESPEnabled and Color3.fromRGB(22, 101, 52) or Color3.fromRGB(30, 44, 74)
    EspToggleBtn.Text = Config.ESPEnabled and "[ESP: ATIVO]" or "[ESP: DESATIVADO]"
    EspToggleBtn.TextColor3 = Config.ESPEnabled and Color3.fromRGB(74, 222, 128) or C_MUTED
    addStroke(EspToggleBtn, Config.ESPEnabled and C_GREEN or C_BORDER, 1)
    if Config.ESPEnabled then
        updateESP()
    else
        clearAllESP()
    end
    addLog("ESP", Config.ESPEnabled and "ESP Ativado." or "ESP Desativado.")
end)

--================================================================--
-- ABA 4: DIAGNÓSTICO, AJUSTES E LOGS
--================================================================--
local ConfigsPage = TabPages["Diagnóstico"]

local TelemetryCard = createCleanCard(ConfigsPage, 54)
local TelemetryLabel = Instance.new("TextLabel")
TelemetryLabel.Size = UDim2.new(1, -24, 1, -10)
TelemetryLabel.Position = UDim2.new(0, 12, 0, 5)
TelemetryLabel.BackgroundTransparency = 1
TelemetryLabel.Font = Enum.Font.Gotham
TelemetryLabel.TextSize = 10
TelemetryLabel.TextColor3 = C_MUTED
TelemetryLabel.TextWrapped = true
TelemetryLabel.TextXAlignment = Enum.TextXAlignment.Left
TelemetryLabel.Text = "● GRAVAÇÃO ATIVA  •  jogue normalmente por ~10 min\nArquivos: ROUBE_UM_OVO_DUMP.txt + ROUBE_UM_OVO_TRACE.jsonl"
TelemetryLabel.Parent = TelemetryCard

-- Somente filtros que influenciam diretamente a automação/radar.
local ModifiersCard = createCleanCard(ConfigsPage, 46)
local ModGrid = Instance.new("Frame")
ModGrid.Size = UDim2.new(1, -20, 1, -12)
ModGrid.Position = UDim2.new(0, 10, 0, 6)
ModGrid.BackgroundTransparency = 1
ModGrid.Parent = ModifiersCard

local modLayout = Instance.new("UIGridLayout")
modLayout.CellSize = UDim2.new(0.5, -4, 0, 30)
modLayout.CellPadding = UDim2.new(0, 8, 0, 6)
modLayout.Parent = ModGrid

local IslandLockBtn = Instance.new("TextButton")
IslandLockBtn.BackgroundColor3 = Color3.fromRGB(26, 36, 60)
IslandLockBtn.Text = Config.LockCurrentIsland and "TRAVAR ILHA: ON" or "TRAVAR ILHA: OFF"
IslandLockBtn.Font = Enum.Font.GothamBold
IslandLockBtn.TextSize = 10
IslandLockBtn.TextColor3 = Config.LockCurrentIsland and C_GREEN or C_MUTED
IslandLockBtn.Parent = ModGrid
addCorner(IslandLockBtn, 6)
addStroke(IslandLockBtn, C_BORDER, 1)

IslandLockBtn.MouseButton1Click:Connect(function()
    Config.LockCurrentIsland = not Config.LockCurrentIsland
    IslandLockBtn.Text = Config.LockCurrentIsland and "TRAVAR ILHA: ON" or "TRAVAR ILHA: OFF"
    IslandLockBtn.TextColor3 = Config.LockCurrentIsland and C_GREEN or C_MUTED
    if TargetTitle then
        TargetTitle.Text = Config.LockCurrentIsland and "ALVO PRIORITARIO (ILHA ATUAL):" or "ALVO PRIORITARIO (TODO O MAPA):"
    end
end)

local UnownedBtn = Instance.new("TextButton")
UnownedBtn.BackgroundColor3 = Color3.fromRGB(26, 36, 60)
UnownedBtn.Text = Config.ShowOnlyUnowned and "IGNORAR MEUS OVOS: ON" or "IGNORAR MEUS OVOS: OFF"
UnownedBtn.Font = Enum.Font.GothamBold
UnownedBtn.TextSize = 10
UnownedBtn.TextColor3 = Config.ShowOnlyUnowned and C_GREEN or C_MUTED
UnownedBtn.Parent = ModGrid
addCorner(UnownedBtn, 6)
addStroke(UnownedBtn, C_BORDER, 1)

UnownedBtn.MouseButton1Click:Connect(function()
    Config.ShowOnlyUnowned = not Config.ShowOnlyUnowned
    UnownedBtn.Text = Config.ShowOnlyUnowned and "IGNORAR MEUS OVOS: ON" or "IGNORAR MEUS OVOS: OFF"
    UnownedBtn.TextColor3 = Config.ShowOnlyUnowned and C_GREEN or C_MUTED
end)

-- Card de Sliders
local SlidersCard = createCleanCard(ConfigsPage, 88)
local SpeedLabel = Instance.new("TextLabel")
SpeedLabel.Size = UDim2.new(1, -20, 0, 18)
SpeedLabel.Position = UDim2.new(0, 10, 0, 8)
SpeedLabel.BackgroundTransparency = 1
SpeedLabel.Font = Enum.Font.GothamBold
SpeedLabel.TextSize = 11
SpeedLabel.TextColor3 = C_TEXT
SpeedLabel.TextXAlignment = Enum.TextXAlignment.Left
SpeedLabel.Text = string.format("Velocidade de deslize: %d studs/s", Config.MoveSpeed)
SpeedLabel.Parent = SlidersCard

local SpeedSliderBg = Instance.new("Frame")
SpeedSliderBg.Size = UDim2.new(1, -20, 0, 10)
SpeedSliderBg.Position = UDim2.new(0, 10, 0, 26)
SpeedSliderBg.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
SpeedSliderBg.Parent = SlidersCard
addCorner(SpeedSliderBg, 5)

local SpeedSliderFill = Instance.new("Frame")
SpeedSliderFill.Size = UDim2.new((Config.MoveSpeed - 16) / 20, 0, 1, 0)
SpeedSliderFill.BackgroundColor3 = C_CYAN
SpeedSliderFill.BorderSizePixel = 0
SpeedSliderFill.Parent = SpeedSliderBg
addCorner(SpeedSliderFill, 5)

local SpeedTrigger = Instance.new("TextButton")
SpeedTrigger.Size = UDim2.new(1, 0, 1, 0)
SpeedTrigger.BackgroundTransparency = 1
SpeedTrigger.Text = ""
SpeedTrigger.Parent = SpeedSliderBg

local isDraggingSpeed = false
SpeedTrigger.MouseButton1Down:Connect(function() isDraggingSpeed = true end)
table.insert(ScriptConnections, Services.UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        if isDraggingSpeed then
            traceEvent("CONFIG", "MOVE_SPEED", { value = Config.MoveSpeed })
            addLog("AJUSTE", "Velocidade alterada para " .. tostring(Config.MoveSpeed) .. " studs/s")
        end
        isDraggingSpeed = false
    end
end))

table.insert(ScriptConnections, Services.RunService.RenderStepped:Connect(function()
    if isDraggingSpeed then
        local mousePos = Services.UserInputService:GetMouseLocation().X
        local barPos = SpeedSliderBg.AbsolutePosition.X
        local barSize = SpeedSliderBg.AbsoluteSize.X
        local pct = math.clamp((mousePos - barPos) / barSize, 0, 1)
        SpeedSliderFill.Size = UDim2.new(pct, 0, 1, 0)
        local val = 16 + math.floor(pct * 20)
        Config.MoveSpeed = val
        SpeedLabel.Text = string.format("Velocidade de deslize: %d studs/s", val)
    end
end))

local DistLabel = Instance.new("TextLabel")
DistLabel.Size = UDim2.new(1, -20, 0, 18)
DistLabel.Position = UDim2.new(0, 10, 0, 44)
DistLabel.BackgroundTransparency = 1
DistLabel.Font = Enum.Font.GothamBold
DistLabel.TextSize = 11
DistLabel.TextColor3 = C_TEXT
DistLabel.TextXAlignment = Enum.TextXAlignment.Left
DistLabel.Text = string.format("Alcance Maximo: %d studs", Config.MaxStealDistance)
DistLabel.Parent = SlidersCard

local DistSliderBg = Instance.new("Frame")
DistSliderBg.Size = UDim2.new(1, -20, 0, 10)
DistSliderBg.Position = UDim2.new(0, 10, 0, 60)
DistSliderBg.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
DistSliderBg.Parent = SlidersCard
addCorner(DistSliderBg, 5)

local DistSliderFill = Instance.new("Frame")
DistSliderFill.Size = UDim2.new(Config.MaxStealDistance / 1500, 0, 1, 0)
DistSliderFill.BackgroundColor3 = C_CYAN
DistSliderFill.BorderSizePixel = 0
DistSliderFill.Parent = DistSliderBg
addCorner(DistSliderFill, 5)

local DistTrigger = Instance.new("TextButton")
DistTrigger.Size = UDim2.new(1, 0, 1, 0)
DistTrigger.BackgroundTransparency = 1
DistTrigger.Text = ""
DistTrigger.Parent = DistSliderBg

local isDraggingDist = false
DistTrigger.MouseButton1Down:Connect(function() isDraggingDist = true end)
table.insert(ScriptConnections, Services.UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        if isDraggingDist then
            traceEvent("CONFIG", "MAX_DISTANCE", { value = Config.MaxStealDistance })
        end
        isDraggingDist = false
    end
end))

table.insert(ScriptConnections, Services.RunService.RenderStepped:Connect(function()
    if isDraggingDist then
        local mousePos = Services.UserInputService:GetMouseLocation().X
        local barPos = DistSliderBg.AbsolutePosition.X
        local barSize = DistSliderBg.AbsoluteSize.X
        local pct = math.clamp((mousePos - barPos) / barSize, 0.05, 1)
        DistSliderFill.Size = UDim2.new(pct, 0, 1, 0)
        local val = math.floor(pct * 1500)
        Config.MaxStealDistance = val
        DistLabel.Text = string.format("Alcance Maximo: %d studs", val)
    end
end))

-- Card de Log Console
local LogCard = createCleanCard(ConfigsPage, 90)
local LogTitle = Instance.new("TextLabel")
LogTitle.Size = UDim2.new(1, -20, 0, 18)
LogTitle.Position = UDim2.new(0, 10, 0, 6)
LogTitle.BackgroundTransparency = 1
LogTitle.Font = Enum.Font.GothamBold
LogTitle.TextSize = 10
LogTitle.TextColor3 = C_MUTED
LogTitle.TextXAlignment = Enum.TextXAlignment.Left
LogTitle.Text = "REGISTROS DO SISTEMA (LOGS):"
LogTitle.Parent = LogCard

local LogScroll = Instance.new("ScrollingFrame")
LogScroll.Size = UDim2.new(1, -20, 0, 62)
LogScroll.Position = UDim2.new(0, 10, 0, 24)
LogScroll.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
LogScroll.BorderSizePixel = 0
LogScroll.ScrollBarThickness = 3
LogScroll.Parent = LogCard
addCorner(LogScroll, 6)

local LogTextLabel = Instance.new("TextLabel")
LogTextLabel.Size = UDim2.new(1, -8, 0, 0)
LogTextLabel.AutomaticSize = Enum.AutomaticSize.Y
LogTextLabel.Position = UDim2.new(0, 4, 0, 4)
LogTextLabel.BackgroundTransparency = 1
LogTextLabel.Font = Enum.Font.Code
LogTextLabel.TextSize = 10
LogTextLabel.TextColor3 = Color3.fromRGB(226, 232, 240)
LogTextLabel.TextXAlignment = Enum.TextXAlignment.Left
LogTextLabel.TextYAlignment = Enum.TextYAlignment.Top
LogTextLabel.TextWrapped = true
LogTextLabel.Text = "Pronto."
LogTextLabel.Parent = LogScroll

_G.UpdateLogConsole = function()
    pcall(function()
        LogTextLabel.Text = table.concat(State.Logs, "\n")
    end)
end

-- Botão Dump Completo
local DumpBtn = Instance.new("TextButton")
DumpBtn.Size = UDim2.new(1, 0, 0, 34)
DumpBtn.BackgroundColor3 = Color3.fromRGB(26, 36, 60)
DumpBtn.Text = "FINALIZAR COLETA E GERAR DUMP PARA ANÁLISE"
DumpBtn.Font = Enum.Font.GothamBold
DumpBtn.TextSize = 11
DumpBtn.TextColor3 = C_CYAN
DumpBtn.Parent = ConfigsPage
addCorner(DumpBtn, 6)
addStroke(DumpBtn, C_BORDER, 1)
addCorner(DumpBtn, 5)
addStroke(DumpBtn, C_BORDER, 1)

DumpBtn.MouseButton1Click:Connect(function()
    addLog("DUMP", "Iniciando dump de dados do jogo...")
    task.spawn(function()
        traceEvent("SESSION", "MANUAL_DUMP", { duration = os.clock() - Telemetry.StartedAt })
        flushTelemetry()
        local txt = dumpGameData()
        pcall(function()
            if setclipboard then setclipboard(txt) end
            if writefile then writefile("ROUBE_UM_OVO_DUMP.txt", txt) end
        end)
        addLog("DUMP", "Pronto: envie o DUMP.txt e o TRACE.jsonl para análise.")
    end)
end)

-- Card UNLOAD Definitivo
local UnloadFullCard = createCleanCard(ConfigsPage, 45)
local UnloadBtnFull = Instance.new("TextButton")
UnloadBtnFull.Size = UDim2.new(1, -20, 0, 30)
UnloadBtnFull.Position = UDim2.new(0, 10, 0.5, -15)
UnloadBtnFull.BackgroundColor3 = Color3.fromRGB(185, 28, 28)
UnloadBtnFull.Text = "DESCARREGAR SCRIPT COMPLETAMENTE (UNLOAD)"
UnloadBtnFull.Font = Enum.Font.GothamBold
UnloadBtnFull.TextSize = 9
UnloadBtnFull.TextColor3 = C_TEXT
UnloadBtnFull.Parent = UnloadFullCard
addCorner(UnloadBtnFull, 5)
addStroke(UnloadBtnFull, C_RED, 1)

--================================================================--
-- SISTEMA MASTER DE DESCARREGAMENTO DEFINITIVO (UNLOAD)
--================================================================--
unloadScript = function()
    if State.IsUnloaded then return end
    State.IsUnloaded = true

    -- 1. Desativar todas as automações e flags
    Config.AutoStealEnabled = false
    Config.AutoEsteiraEnabled = false
    Config.ESPEnabled = false
    State.IsExecutingSteal = false
    State.IsOnTreadmill = false
    traceEvent("SESSION", "UNLOAD", { duration = os.clock() - Telemetry.StartedAt })
    flushTelemetry()
    Telemetry.Enabled = false
    pcall(function()
        if getgenv and type(getgenv().RoubeUmOvoTraceHookState) == "table" then
            getgenv().RoubeUmOvoTraceHookState.Enabled = false
            getgenv().RoubeUmOvoTraceHookState.Emit = nil
            getgenv().RoubeUmOvoTraceHookState.ShouldTrace = nil
        end
    end)

    -- 2. Desconectar o runner da esteira
    if esteiraHeartbeatConn then
        pcall(function() esteiraHeartbeatConn:Disconnect() end)
        esteiraHeartbeatConn = nil
    end

    -- 3. Desconectar TODOS os eventos registrados (RunService, Inputs, GUI)
    for _, conn in ipairs(ScriptConnections) do
        pcall(function()
            if conn and conn.Connected then
                conn:Disconnect()
            end
        end)
    end
    table.clear(ScriptConnections)

    -- 4. Limpar e restaurar o estado físico do Personagem
    pcall(function()
        local char = getChar()
        if char then
            -- Restaurar colisões padrão do personagem
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = true
                end
            end

            -- Restaurar HumanoidRootPart e remover body movers
            local hrp = getHRP()
            if hrp then
                hrp.Anchored = false
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
                for _, child in ipairs(hrp:GetChildren()) do
                    if child:IsA("BodyVelocity") or child:IsA("BodyPosition") or child:IsA("BodyGyro")
                        or child:IsA("AlignPosition") or child:IsA("AlignOrientation")
                        or child.Name:find("Mover") or child.Name:find("BV") then
                        child:Destroy()
                    end
                end
            end

            -- Restaurar propriedades padrão do Humanoid
            local hum = getHum()
            if hum then
                hum:Move(Vector3.zero, false)
                hum.WalkSpeed = 16
                hum.JumpPower = 50
                hum.PlatformStand = false
            end
        end
    end)

    -- 5. Limpar 100% dos ESPs (tanto na tabela quanto no Workspace)
    clearAllESP()
    pcall(function()
        for _, desc in ipairs(Services.Workspace:GetDescendants()) do
            if desc:IsA("BillboardGui") and (desc.Name == "ESP_EggLabel" or desc.Name:find("ESP_")) then
                desc:Destroy()
            end
        end
    end)

    -- 6. Destruir COMPLETAMENTE toda a interface gráfica e o botão mobile
    purgeAllGuis()
    pcall(function()
        if ScreenGui then
            ScreenGui.Enabled = false
            ScreenGui.Parent = nil
            ScreenGui:Destroy()
        end
    end)
    pcall(function()
        if MobileBtn then
            MobileBtn.Visible = false
            MobileBtn.Parent = nil
            MobileBtn:Destroy()
        end
    end)

    -- 7. Limpar variáveis globais
    _G.RoubeUmOvoUnload = nil
    _G.UpdateLogConsole = nil
    _G.DiscoveredEggs = nil
    _G.UpdateRadarCards = nil
    _G.EggRadarText = nil
    _G.MegaDumpText = nil
    if getgenv then
        pcall(function()
            local g = getgenv()
            g.RoubeUmOvoUnload = nil
            g.DiscoveredEggs = nil
            g.UpdateRadarCards = nil
            g.UpdateLogConsole = nil
            g.EggRadarText = nil
            g.MegaDumpText = nil
        end)
    end
end

-- Exportar Unload globalmente para permitir fechamento via console / executor
_G.RoubeUmOvoUnload = unloadScript
if getgenv then
    pcall(function() getgenv().RoubeUmOvoUnload = unloadScript end)
end

UnloadBtn.MouseButton1Click:Connect(function()
    if unloadScript then unloadScript() end
end)
UnloadBtnFull.MouseButton1Click:Connect(function()
    if unloadScript then unloadScript() end
end)

-- Atalho LeftControl e Botão Mobile Minimalista
table.insert(ScriptConnections, Services.UserInputService.InputBegan:Connect(function(input, gpe)
    if not gpe and input.KeyCode == Enum.KeyCode.LeftControl then
        MainFrame.Visible = not MainFrame.Visible
    end
end))

MobileBtn = Instance.new("TextButton")
MobileBtn.Name = "MobileToggleBtn"
MobileBtn.Size = UDim2.new(0, 36, 0, 36)
MobileBtn.Position = UDim2.new(0.02, 0, 0.45, 0)
MobileBtn.BackgroundColor3 = C_TOPBAR
MobileBtn.Text = "OVO"
MobileBtn.Font = Enum.Font.GothamBold
MobileBtn.TextSize = 9
MobileBtn.TextColor3 = C_CYAN
MobileBtn.Parent = ScreenGui
addCorner(MobileBtn, 18)
addStroke(MobileBtn, C_CYAN, 1)
MobileBtn.Draggable = true

MobileBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

-- Atualização de Status da Base e da Esteira em Tempo Real
task.spawn(function()
    while true do
        task.wait(1.5)
        if State.IsUnloaded then break end
        
        -- Atualizar Base
        local myPlot = findMyPlot()
        if myPlot then
            local dep = getMyDepositCFrame()
            if dep then
                BaseLabel.Text = string.format("Base: (%s) em (%.0f, %.0f, %.0f)", myPlot.Name, dep.Position.X, dep.Position.Y, dep.Position.Z)
                BaseLabel.TextColor3 = C_GREEN
            end
        end

        -- Atualizar Esteira
        local tPart, tPos = findMyTreadmill()
        if tPos then
            local hrp = getHRP()
            local d = hrp and math.floor((tPos - hrp.Position).Magnitude) or 0
            EsteiraStatusLabel.Text = string.format("Esteira: Detectada no Plot (%d studs)", d)
            EsteiraStatusLabel.TextColor3 = C_GREEN
        else
            EsteiraStatusLabel.Text = "Esteira: Nao encontrada no plot."
            EsteiraStatusLabel.TextColor3 = C_MUTED
        end

        -- Atualizar Radar caso este aberto
        if activeTab == "Radar" then
            executeCleanRadarScan()
        end
    end
end)


-- Thread Contínua em Segundo Plano — Driver da Máquina de Estados de Roubo
task.spawn(function()
    while true do
        if State.IsUnloaded then break end
        if Config.AutoStealEnabled and not State.IsOnTreadmill then
            local ok, err = pcall(runStateMachineTick)
            if not ok and err then
                addLog("ERRO", "Falha na máquina de estados: " .. tostring(err))
                setStealState("IDLE")
            end
        elseif not Config.AutoStealEnabled and StealSM.Current ~= "IDLE" then
            setStealState("IDLE")
        end
        task.wait(0.15)
    end
end)

-- Inicialização Limpa
task.delay(0.8, function()
    if State.IsUnloaded then return end
    executeCleanRadarScan()
    addLog("SISTEMA", "Roube um Ovo Stability v13.1 carregado com sucesso!")
    addLog("TRACE", "Gravação ativa em " .. Telemetry.FileName)
    pcall(function()
        Services.StarterGui:SetCore("SendNotification", {
            Title = "Roube um Ovo Hub",
            Text = "Script carregado com sucesso! [CTRL ou botao para abrir/fechar]",
            Duration = 5
        })
    end)
end)

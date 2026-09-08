pcall(function()
    if not game:IsLoaded() then
        game.Loaded:Wait()
    end
end)

--[[
    ROUBE UM OVO - HUB DE AUTOMAÇÃO & RADAR (v14.1 DUMP ENGINE & FLUENT MASTER)
    -----------------------------------------------------------------------
    - 100% Integrado com ReplicatedStorage.Client.EggState & PlotState.
    - Coleta Legítima com Uid real via AskFieldEggCarry & EggState.CarryFieldEgg.
    - Depósito Oficial no Ninho com LocalCFrame relativo via AskPlaceEgg.
    - Auto-Hatch Automático: choca ovos nos ninhos assim que prontos (AskHatch/AskFinishHatch).
    - Auto-Esteira Anti-Travamento: desmonte oficial do servidor com AskDoff e entrada com AskWearStill.
    - Coletor 3D de Armas Secretas: 2 pedestais oficiais (TouchPart real) e 0.7s contato.
    - Gerenciador Nativo de Pets: Equipar Melhores (WearBest) e Auto-Sell de raridades.
    - Interface Fluent Design (Windows 11 Dark Acrylic, Lucide Icons e Toasts).
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
    if cloneref then
        local ok, ref = pcall(cloneref, s)
        if ok and ref then return ref end
    end
    return s
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

-- 2.1 Módulos Internos Nativos do Jogo (EggState & PlotState extraídos do dump)
-- 2.1 Modulos Internos Nativos do Jogo (EggState, PlotState, Assets, Save, etc.)
local GameModules = {
    EggState = nil,
    PlotState = nil,
    Assets = nil,
    Rarity = nil,
    Save = nil,
    AssetItems = nil
}
pcall(function()
    local client = Services.ReplicatedStorage:WaitForChild("Client", 3)
    if client then
        local es = client:FindFirstChild("EggState")
        if es then GameModules.EggState = require(es) end
        local ps = client:FindFirstChild("PlotState")
        if ps then GameModules.PlotState = require(ps) end
    end
end)
pcall(function()
    local dataFolder = Services.ReplicatedStorage:WaitForChild("Data", 3)
    if dataFolder then
        local ast = dataFolder:FindFirstChild("Assets")
        if ast then GameModules.Assets = require(ast) end
        local rar = dataFolder:FindFirstChild("Rarity")
        if rar then GameModules.Rarity = require(rar) end
    end
end)
pcall(function()
    local shared = Services.ReplicatedStorage:WaitForChild("Shared", 3)
    if shared then
        local sv = shared:FindFirstChild("Save")
        if sv then GameModules.Save = require(sv) end
        local util = shared:FindFirstChild("Util") or shared:FindFirstChild("Utils")
        if util then
            local ai = util:FindFirstChild("AssetItems")
            if ai then GameModules.AssetItems = require(ai) end
        end
    end
end)

-- Funcoes de Resolucao Oficial via Catalogo Data.Assets
local function getPetConfig(assetCategory)
    if not assetCategory or type(assetCategory) ~= "string" then return nil end
    if GameModules.Assets and GameModules.Assets.Directory then
        local cfg = GameModules.Assets.Directory[assetCategory]
        if cfg then return cfg end
    end
    if KnownPetsCatalog then
        for petKey, petData in pairs(KnownPetsCatalog) do
            if petKey:lower() == assetCategory:lower() or (petData.DisplayName and petData.DisplayName:lower() == assetCategory:lower()) then
                return petData
            end
        end
    end
    return nil
end

local function resolvePetInfo(assetCategory)
    local cfg = getPetConfig(assetCategory)
    local displayName = (cfg and cfg.DisplayName) or assetCategory or "Ovo Desconhecido"
    local rarity = "Comum"
    if cfg and cfg.Rarity then
        if type(cfg.Rarity) == "table" then
            rarity = cfg.Rarity.DisplayName or cfg.Rarity._id or tostring(cfg.Rarity)
        else
            rarity = tostring(cfg.Rarity)
        end
    elseif cfg and cfg.RarityName then
        rarity = cfg.RarityName
    end
    local income = (cfg and cfg.EarningRate) or (cfg and cfg.Income) or 0
    local weight = (cfg and cfg.Egg and cfg.Egg.WeightKg) or (cfg and cfg.ModelWeight) or (cfg and cfg.WeightKg) or 0
    local score = (RarityScoreMap and RarityScoreMap[rarity:upper()]) or 500
    return displayName, rarity, score, weight, income
end
local function getRemote(remotePath)
    local packages = Services.ReplicatedStorage:FindFirstChild("Packages")
    local networking = packages and packages:FindFirstChild("Networking")
    if networking then
        local r = networking:FindFirstChild(remotePath)
        if r then return r end
    end
    for _, desc in ipairs(Services.ReplicatedStorage:GetDescendants()) do
        if desc.Name == remotePath then
            return desc
        end
    end
    return nil
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
-- Cache Forense em Tempo Real de Remotes
local RealFieldEggCache = {}
local RealPetIncomeCache = {}


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
    AutoHatchEnabled = true,
    AutoEquipBest = true,
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
    LastHatchCheck = 0,
    LogAutoScroll = true,
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
            version = "13.2",
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

--================================================================--
-- 5.1. ESCUTA FORENSE EM TEMPO REAL (EGG SHIFT & COINS GATHERED)
--================================================================--
local function setupNetworkingListeners()
    local packages = Services.ReplicatedStorage:FindFirstChild("Packages")
    local networking = packages and packages:FindFirstChild("Networking")
    
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
    local registeredUids = {}

    -- 1. CONSULTA OFICIAL PRIORITARIA: EggState.ReadFieldEggs() (Ovos Selvagens Vivos)
    pcall(function()
        if GameModules.EggState and GameModules.EggState.ReadFieldEggs then
            local fSnapshot = GameModules.EggState.ReadFieldEggs()
            local records = fSnapshot and fSnapshot.Records
            if records and type(records) == "table" then
                for _, rec in ipairs(records) do
                    local uid = rec.Uid
                    local petCategory = rec.AssetCategory
                    local cframe = rec.BottomCFrame
                    local pos = cframe and cframe.Position or Vector3.zero
                    local state = rec.State
                    local carrier = rec.CarrierUserId

                    if uid and petCategory and not carrier and state ~= "Claimed" then
                        registeredUids[uid] = true
                        local cleanName, rarity, score, weight, income = resolvePetInfo(petCategory)
                        local zone = getIslandNameByPos(pos)
                        local dist = (pos - myPos).Magnitude

                        table.insert(rawList, {
                            Uid = uid,
                            SlotKey = rec.FirstAreaSlotKey,
                            Name = cleanName,
                            Rarity = rarity,
                            RarityScore = score,
                            WeightKg = weight,
                            Income = income,
                            Zone = zone,
                            IsMyPlot = false,
                            PlotOwner = nil,
                            Position = pos,
                            Distance = dist,
                            Source = "FieldEgg (Oficial)",
                            Instance = nil,
                            Prompt = nil
                        })
                    end
                end
            end
        end
    end)

    -- 2. CONSULTA OFICIAL DE OVOS EM BASES: EggState.ReadOwnedEggs()
    pcall(function()
        if GameModules.EggState and GameModules.EggState.ReadOwnedEggs then
            local ownedRows = GameModules.EggState.ReadOwnedEggs()
            if ownedRows and type(ownedRows) == "table" then
                for _, row in ipairs(ownedRows) do
                    local ownerId = row.OwnerUserId
                    local isMy = (LocalPlayer and ownerId == LocalPlayer.UserId)
                    if row.Records and type(row.Records) == "table" then
                        for uid, rec in pairs(row.Records) do
                            if rec.Placement ~= nil and not registeredUids[uid] then
                                registeredUids[uid] = true
                                local petCategory = rec.AssetCategory
                                local cleanName, rarity, score, weight, income = resolvePetInfo(petCategory)
                                local eggPos = nil
                                local placedRenders = Services.Workspace:FindFirstChild("PlacedEggRenders")
                                if placedRenders then
                                    local m = placedRenders:FindFirstChild(uid) or placedRenders:FindFirstChild("Egg_" .. uid)
                                    if m then eggPos = getPositionOf(m) end
                                end
                                if not eggPos then
                                    local pFolder = getPlotFolderByUserId(ownerId)
                                    if pFolder then
                                        local petArea = pFolder:FindFirstChild("PetArea", true)
                                        if petArea and petArea:IsA("BasePart") then
                                            eggPos = petArea.Position
                                        end
                                    end
                                end
                                if eggPos then
                                    local dist = (eggPos - myPos).Magnitude
                                    table.insert(rawList, {
                                        Uid = uid,
                                        Name = cleanName,
                                        Rarity = rarity,
                                        RarityScore = score,
                                        WeightKg = weight,
                                        Income = income,
                                        Zone = isMy and "Meu Ninho" or ("Base (" .. tostring(ownerId) .. ")"),
                                        IsMyPlot = isMy,
                                        PlotOwner = tostring(ownerId),
                                        Position = eggPos,
                                        Distance = dist,
                                        Source = "PlacedEgg (Base)",
                                        Instance = nil,
                                        Prompt = nil
                                    })
                                end
                            end
                        end
                    end
                end
            end
        end
    end)

    -- 3. PROMPTS FISICOS NO WORKSPACE
    local cachedPrompts = {}
    pcall(function()
        for _, desc in ipairs(Services.Workspace:GetDescendants()) do
            if desc:IsA("ProximityPrompt") and desc.Enabled then
                local act = plainText(desc.ActionText)
                local obj = plainText(desc.ObjectText)
                local isCand = act:find("steal") or act:find("roubar") or act:find("take")
                    or act:find("pick") or obj:find("egg") or obj:find("ovo") or desc.Name:lower():find("egg")
                if isCand and desc.Parent then
                    local pPos = getPositionOf(desc) or getPositionOf(desc.Parent)
                    if pPos then
                        table.insert(cachedPrompts, { Prompt = desc, Instance = desc.Parent, Position = pPos })
                    end
                end
            end
        end
    end)

    -- Vincular cada ovo da lista com o prompt fisico mais proximo
    for _, egg in ipairs(rawList) do
        local closestDist = 8
        for _, cp in ipairs(cachedPrompts) do
            local d = (cp.Position - egg.Position).Magnitude
            if d < closestDist then
                closestDist = d
                egg.Prompt = cp.Prompt
                egg.Instance = cp.Instance
            end
        end
    end

    -- 4. FALLBACK PARA ITENS DO WORKSPACE QUE NAO FORAM MAPEADOS NO EGGSTATE
    pcall(function()
        for _, cp in ipairs(cachedPrompts) do
            local alreadyMatched = false
            for _, egg in ipairs(rawList) do
                if (egg.Position - cp.Position).Magnitude <= 4.5 then
                    alreadyMatched = true
                    break
                end
            end
            if not alreadyMatched then
                local cleanName, rarity, score, weight, income = resolveEggDetails(cp.Instance, cp.Prompt)
                local zone, isMyPlot, owner = identifyZone(cp.Instance)
                if zone == "Mapa Geral" and cp.Position.X >= 510 then
                    zone = getIslandNameByPos(cp.Position)
                end
                table.insert(rawList, {
                    Instance = cp.Instance,
                    Prompt = cp.Prompt,
                    Name = cleanName,
                    Rarity = rarity,
                    RarityScore = score,
                    WeightKg = weight,
                    Income = income,
                    Zone = zone,
                    IsMyPlot = isMyPlot,
                    PlotOwner = owner,
                    Position = cp.Position,
                    Distance = (cp.Position - myPos).Magnitude,
                    Source = "Prompt Fisico"
                })
            end
        end
    end)

    -- Ordenar por maior raridade / renda e menor distancia
    table.sort(rawList, function(a, b)
        if a.RarityScore ~= b.RarityScore then
            return a.RarityScore > b.RarityScore
        end
        return a.Distance < b.Distance
    end)

    return rawList
end
    return executeDirectSteal(target)
end

-- E. Execução legada redirecionada para a mesma caminhada segura.

--================================================================--
-- HELPERS FORENSES DE ROUBO: AUTO BAT SWING & REMOTE CARRY BYPASS
--================================================================--
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

local function tryInstantCarryRemote(target)
    if not target then return false end
    local inst = target.Instance
    if not inst then return false end

    local modelName = inst.Name or ""
    local slotKey = modelName:match("([%a%d_]+:Slot_%d+)")
    if not slotKey and inst.Parent then
        slotKey = inst.Parent.Name:match("([%a%d_]+:Slot_%d+)")
    end
    if not slotKey and target.Position then
        local isl = getIslandByPos(target.Position)
        if isl and isl.Name then
            slotKey = isl.Name .. ":Slot_001"
        end
    end
    slotKey = slotKey or "Forest:Slot_001"

    local uid = inst:GetAttribute("Uid") or inst:GetAttribute("FirstAreaUid") or inst:GetAttribute("EggUid")
    if not uid and inst.Parent then
        uid = inst.Parent:GetAttribute("Uid") or inst.Parent:GetAttribute("FirstAreaUid") or inst.Parent:GetAttribute("EggUid")
    end
    if not uid then
        for _, c in ipairs(inst:GetChildren()) do
            if c.Name:find("FirstAreaEgg_") then
                uid = c.Name
                break
            end
        end
    end
    if not uid and modelName:find("FirstAreaEgg_") then
        uid = modelName
    end

    -- Se tivermos EggState oficial, buscar Uid real nos registros vivos
    if not uid and GameModules.EggState then
        pcall(function()
            local fEggs = GameModules.EggState.ReadFieldEggs()
            if fEggs and fEggs.Records then
                local myHrp = getHRP()
                local tPos = target.Position or (inst:IsA("BasePart") and inst.Position) or (inst:GetPivot().Position)
                local closestDist = 999
                for _, rec in ipairs(fEggs.Records) do
                    if rec.BottomCFrame then
                        local d = (rec.BottomCFrame.Position - tPos).Magnitude
                        if d < closestDist then
                            closestDist = d
                            uid = rec.Uid
                            if rec.FirstAreaSlotKey then slotKey = rec.FirstAreaSlotKey end
                        end
                    end
                end
            end
        end)
    end

    if not uid then
        uid = "FirstAreaEgg_" .. tostring(LocalPlayer.UserId) .. "_" .. tostring(math.random(1000000, 9999999)) .. "_" .. slotKey
    end

    target.Uid = uid
    target.SlotKey = slotKey

    -- 1. Invocacao via EggState oficial (nativa do jogo)
    local carried = false
    if GameModules.EggState and GameModules.EggState.CarryFieldEgg then
        pcall(function()
            local ok = GameModules.EggState.CarryFieldEgg(uid, slotKey)
            if ok then carried = true end
        end)
    end

    -- 2. Invocacao direta via RemoteFunction AskFieldEggCarry
    local askCarry = getRemote("RF/EggWorld/AskFieldEggCarry")
    if askCarry and askCarry:IsA("RemoteFunction") then
        for i = 1, 2 do
            task.spawn(function()
                pcall(function()
                    askCarry:InvokeServer({
                        FirstAreaSlotKey = slotKey,
                        Uid = uid
                    })
                end)
            end)
        end
        return true
    end
    return carried
end

local function getHeldEggUid()
    local char = getChar()
    if char then
        for _, item in ipairs(char:GetChildren()) do
            if item:IsA("Tool") then
                local uid = item:GetAttribute("UID") or item:GetAttribute("Uid") or item:GetAttribute("EggUid")
                if uid and typeof(uid) == "string" and uid ~= "" then
                    return uid, item
                end
            end
        end
    end
    local bp = LocalPlayer:FindFirstChild("Backpack")
    if bp then
        for _, item in ipairs(bp:GetChildren()) do
            if item:IsA("Tool") then
                local uid = item:GetAttribute("UID") or item:GetAttribute("Uid") or item:GetAttribute("EggUid")
                if uid and typeof(uid) == "string" and uid ~= "" then
                    return uid, item
                end
            end
        end
    end
    if StealSM and StealSM.Target and StealSM.Target.Uid then
        return StealSM.Target.Uid, nil
    end
    return nil, nil
end

local function depositEggAtBase()
    local heldUid, _ = getHeldEggUid()
    local myPlot = findMyPlot()
    local relativeCF = CFrame.identity

    if GameModules.PlotState then
        local ok, pResolved = pcall(function() return GameModules.PlotState.ResolvePlot() end)
        if ok and pResolved and pResolved.CenterPoint and pResolved.PetArea then
            relativeCF = pResolved.CenterPoint.CFrame:ToObjectSpace(CFrame.new(pResolved.PetArea.Position))
        end
    end
    if relativeCF == CFrame.identity and myPlot then
        local cp = myPlot:FindFirstChild("CenterPoint")
        local petArea = myPlot:FindFirstChild("PetArea", true)
        if cp and petArea and cp:IsA("BasePart") and petArea:IsA("BasePart") then
            relativeCF = cp.CFrame:ToObjectSpace(CFrame.new(petArea.Position))
        elseif cp and cp:IsA("BasePart") then
            relativeCF = CFrame.new(0, 1, 0)
        end
    end

    local planted = false
    if heldUid then
        if GameModules.EggState and GameModules.EggState.PlantEgg then
            pcall(function()
                local ok, err = GameModules.EggState.PlantEgg(heldUid, relativeCF)
                if ok then planted = true end
            end)
        end
        if not planted then
            pcall(function()
                local askPlace = getRemote("RF/EggWorld/AskPlaceEgg")
                if askPlace and askPlace:IsA("RemoteFunction") then
                    local ok, res = askPlace:InvokeServer({
                        Uid = heldUid,
                        LocalCFrame = relativeCF
                    })
                    if ok == true then planted = true end
                end
            end)
        end
    end

    -- Fallback fisico por toque
    local depositPart = getMyDepositTarget()
    local myHrp = getHRP()
    if depositPart and myHrp and firetouchinterest then
        pcall(function()
            firetouchinterest(myHrp, depositPart, 0)
            task.wait(0.05)
            firetouchinterest(myHrp, depositPart, 1)
        end)
    end

    return planted
end

local function equipBestPets()
    pcall(function()
        local wearBest = getRemote("RF/Haul/WearBest")
        if wearBest and wearBest:IsA("RemoteFunction") then
            local ok, res = wearBest:InvokeServer()
            addLog("PETS", "Melhores pets equipados com sucesso!")
            traceEvent("PETS", "WEAR_BEST", { result = tostring(ok) })
            return true
        end
    end)
    return false
end

local function configureNativeAutoSell(raritiesTable)
    raritiesTable = raritiesTable or {
        Common = true,
        Uncommon = true,
        Rare = true
    }
    pcall(function()
        local writeAutoSell = getRemote("RF/Haul/WriteAutoSell")
        if writeAutoSell and writeAutoSell:IsA("RemoteFunction") then
            local ok, res = writeAutoSell:InvokeServer(raritiesTable)
            addLog("PETS", "Auto-venda nativa configurada com sucesso!")
            return true
        end
    end)
    return false
end

local function sellCommonPetsInInventory()
    local uidsToSell = {}
    pcall(function()
        if GameModules.Save and GameModules.Save.Get and GameModules.AssetItems then
            local save = GameModules.Save.Get()
            local inventory = save and save.Inventory
            local equipped = (save and save.EquippedAssets) or {}
            if inventory and type(inventory) == "table" then
                for uid, rawItem in pairs(inventory) do
                    local okDecode, itemData = pcall(function()
                        return GameModules.AssetItems.Decode(rawItem)
                    end)
                    if okDecode and itemData then
                        local isEquipped = table.find(equipped, uid) ~= nil
                        local isFavorite = itemData.IsFavorite == true
                        local inFuse = itemData.InFuse == true
                        if not isEquipped and not isFavorite and not inFuse then
                            local cat = itemData.AssetCategory
                            local _, rarityName = resolvePetInfo(cat)
                            local rLow = rarityName:lower()
                            if rLow == "common" or rLow == "uncommon" or rLow == "comum" or rLow == "incomum" or rLow == "basic" then
                                table.insert(uidsToSell, uid)
                            end
                        end
                    end
                end
            end
        end
    end)

    if #uidsToSell > 0 then
        local sellEvery = getRemote("RE/PetSatchel/SellEveryPet")
        if sellEvery and sellEvery:IsA("RemoteEvent") then
            sellEvery:FireServer(uidsToSell)
            addLog("PETS", string.format("%d pets comuns/incomuns vendidos com sucesso!", #uidsToSell))
        end
    else
        addLog("PETS", "Nenhum pet comum/incomum elegivel encontrado no inventario.")
    end

    pcall(function()
        local writeAutoSell = getRemote("RF/Haul/WriteAutoSell")
        if writeAutoSell and writeAutoSell:IsA("RemoteFunction") then
            writeAutoSell:InvokeServer({
                Common = true,
                Uncommon = true
            })
        end
    end)
end

local function checkAndAutoHatchEggs()
    if State.IsUnloaded or not Config.AutoHatchEnabled then return end
    pcall(function()
        if GameModules.EggState then
            local ownedEggs = GameModules.EggState.ReadOwnerEggs(LocalPlayer.UserId)
            if ownedEggs and type(ownedEggs) == "table" then
                for uid, eggRecord in pairs(ownedEggs) do
                    if eggRecord.Placement ~= nil and GameModules.EggState.IsReadyToHatch(uid) then
                        addLog("HATCH", "Ovo pronto detectado: " .. tostring(uid) .. ". Chocando...")
                        traceEvent("HATCH", "START", { uid = uid })
                        GameModules.EggState.BeginHatch(uid)
                        task.wait(0.25)
                        local ok, err, petUid = GameModules.EggState.FinishHatch(uid)
                        if ok then
                            addLog("HATCH", "Ovo chocado com sucesso! Pet coletado.")
                            traceEvent("HATCH", "SUCCESS", { uid = uid, pet = petUid })
                            if Config.AutoEquipBest then
                                task.delay(0.5, function()
                                    equipBestPets()
                                end)
                            end
                        end
                    end
                end
            end
        else
            local askHatch = getRemote("RF/EggWorld/AskHatch")
            local askFinish = getRemote("RF/EggWorld/AskFinishHatch")
            local askLive = getRemote("RF/EggWorld/AskLiveSnapshot")
            if askLive and askHatch and askFinish then
                local snapshot = askLive:InvokeServer()
                if snapshot and type(snapshot) == "table" then
                    for uid, eggRecord in pairs(snapshot) do
                        if eggRecord.Placement ~= nil then
                            askHatch:InvokeServer(uid)
                            task.wait(0.25)
                            askFinish:InvokeServer(uid)
                        end
                    end
                end
            end
        end
    end)
end

local SECRET_GEAR_PEDESTALS = {
    { Name = "GearGiver_Slap", Display = "Slap Glove (Luva de Tapa)", Pos = Vector3.new(545.01, 53.39, -357.85) },
    { Name = "GearGiver", Display = "Bat / Bastao de Choque", Pos = Vector3.new(545.01, 53.39, -344.76) }
}

local function collectAllSecretWeapons()
    local char = getChar()
    local hrp = getHRP()
    local hum = getHum()
    if not hrp or not hum then
        addLog("ARMAS", "Personagem indisponivel para coletar armas.")
        return false, "Personagem indisponivel"
    end

    local originalCF = hrp.CFrame
    local collectedCount = 0
    addLog("ARMAS", "Iniciando coleta das 2 armas secretas nos pedestais...")

    for _, gear in ipairs(SECRET_GEAR_PEDESTALS) do
        local model = Services.Workspace:FindFirstChild(gear.Name, true)
        local touchPart = nil
        if model then
            touchPart = model:FindFirstChild("TouchPart") or model:FindFirstChildWhichIsA("BasePart", true)
        end
        if not touchPart then
            for _, desc in ipairs(Services.Workspace:GetDescendants()) do
                if desc:IsA("BasePart") and desc.Name == "TouchPart" and (desc.Position - gear.Pos).Magnitude < 15 then
                    touchPart = desc
                    break
                end
            end
        end

        local targetCFrame = (touchPart and touchPart.CFrame) or CFrame.new(gear.Pos)
        hrp.CFrame = targetCFrame
        hrp.AssemblyLinearVelocity = Vector3.zero
        task.wait(0.15)

        pcall(function()
            local rFoot = char:FindFirstChild("RightFoot") or char:FindFirstChild("Right Leg") or hrp
            local lFoot = char:FindFirstChild("LeftFoot") or char:FindFirstChild("Left Leg") or hrp
            if touchPart and firetouchinterest then
                for _ = 1, 3 do
                    firetouchinterest(rFoot, touchPart, 0)
                    firetouchinterest(lFoot, touchPart, 0)
                    firetouchinterest(hrp, touchPart, 0)
                    task.wait(0.06)
                    firetouchinterest(rFoot, touchPart, 1)
                    firetouchinterest(lFoot, touchPart, 1)
                    firetouchinterest(hrp, touchPart, 1)
                    task.wait(0.06)
                end
            end
        end)

        task.wait(0.7)
        collectedCount = collectedCount + 1
        addLog("ARMAS", "Pedestal acionado com sucesso: " .. gear.Display)
    end

    hrp.CFrame = originalCF
    hrp.AssemblyLinearVelocity = Vector3.zero
    addLog("ARMAS", string.format("Coleta concluida! %d armas acionadas. Verifique o Backpack.", collectedCount))
    return true
end
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

        local pInst = target.Prompt or (target.Instance and target.Instance:FindFirstChildWhichIsA("ProximityPrompt", true))
        capturePickupSnapshot(target)
        State.ExpectCarryUntil = os.clock() + 4

        addLog("INTERAÇÃO", "Executando coleta multi-canal em " .. target.Name .. "...")

        -- Canal 1: Remote Bypass Instantâneo (AskFieldEggCarry)
        pcall(function()
            tryInstantCarryRemote(target)
        end)

        -- Canal 2: ProximityPrompt com bypass de HoldDuration
        if pInst then
            pcall(function()
                triggerPrompt(pInst)
            end)
        end

        -- Canal 3: Toque físico com membros e tronco
        pcall(function()
            local eggPart = target.Instance:IsA("BasePart") and target.Instance 
                or target.Instance:FindFirstChildWhichIsA("BasePart", true)
            if eggPart and myHrp and firetouchinterest then
                firetouchinterest(myHrp, eggPart, 0)
                task.wait()
                firetouchinterest(myHrp, eggPart, 1)
            end
        end)

        task.wait(0.18)

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
        task.wait(0.3)
        State.ExpectCarryUntil = os.clock() + 3
        addLog("DEPÓSITO", "Plantando ovo no ninho oficial da base...")
        
        -- Executa depósito via AskPlaceEgg / EggState.PlantEgg
        depositEggAtBase()
        task.wait(0.4)
        
        -- Executa checagem de ovos prontos para auto-hatch
        task.spawn(checkAndAutoHatchEggs)
        
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


-- 10. EXPORTADOR DE TELEMETRIA E DADOS INTERNOS (OBSERVATORY v13.2)
local function dumpGameData()
    local lines = {}
    local function logL(s) table.insert(lines, s or "") end

    logL("================================================================================")
    logL("ROUBE UM OVO - DUMP E TELEMETRIA OBSERVATORY v13.2")
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
--================================================================--
--================================================================--
-- 12. INTERFACE MODERNA FLUENT DESIGN v14.1 (COM FALLBACK AUTOMATICO)
--================================================================--

local Fluent = nil

-- Tentativa 1: Repositorio Oficial Direto Raw GitHub (Sem Redirecionamentos 302)
pcall(function()
    local src = game:HttpGet("https://raw.githubusercontent.com/talespxk/Roube-um-ovo-script/main/fluent.lua")
    if src and #src > 1000 then
        local fn = loadstring(src)
        if fn then
            local res = fn()
            if type(res) == "table" and res.CreateWindow then
                Fluent = res
            end
        end
    end
end)

-- Tentativa 2: Release Oficial do Dawid
if not Fluent then
    pcall(function()
        local src = game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua")
        if src and #src > 1000 then
            local fn = loadstring(src)
            if fn then
                local res = fn()
                if type(res) == "table" and res.CreateWindow then
                    Fluent = res
                end
            end
        end
    end)
end

local uiCreated = false

if Fluent then
    local okWin, errWin = pcall(function()
        local Window = Fluent:CreateWindow({
            Title = "Roube um Ovo Hub",
            SubTitle = "v14.1 Dump Engine Master",
            TabWidth = 160,
            Size = UDim2.fromOffset(580, 460),
            Acrylic = false,
            Theme = "Dark",
            MinimizeKey = Enum.KeyCode.RightControl
        })

        local Tabs = {
            AutoSteal = Window:AddTab({ Title = "Auto-Steal", Icon = "egg" }),
            Esteira = Window:AddTab({ Title = "Auto-Esteira", Icon = "gauge" }),
            Radar = Window:AddTab({ Title = "Radar de Ovos", Icon = "scan" }),
            ArmasPets = Window:AddTab({ Title = "Armas & Pets", Icon = "swords" }),
            Teleports = Window:AddTab({ Title = "Teleportes", Icon = "map-pin" }),
            Logs = Window:AddTab({ Title = "Console / Logs", Icon = "terminal" })
        }

        -- 1. ABA AUTO-STEAL
        Tabs.AutoSteal:AddToggle("AutoStealToggle", {
            Title = "Ativar Auto-Steal",
            Description = "Rouba os melhores ovos do mapa e deposita no ninho",
            Default = Config.AutoStealEnabled,
            Callback = function(val)
                Config.AutoStealEnabled = val
                addLog("ROUBO", val and "Auto-Steal ativado." or "Auto-Steal pausado.")
                Fluent:Notify({
                    Title = "Auto-Steal",
                    Content = val and "Auto-Steal ATIVADO" or "Auto-Steal PAUSADO",
                    Duration = 2
                })
            end
        })

        Tabs.AutoSteal:AddToggle("AutoEquipToggle", {
            Title = "Auto-Equipar Melhores Pets",
            Description = "Equipa os melhores pets automaticamente apos cada choco",
            Default = Config.AutoEquipBest,
            Callback = function(val)
                Config.AutoEquipBest = val
                if val then equipBestPets() end
            end
        })

        Tabs.AutoSteal:AddDropdown("PriorityModeDropdown", {
            Title = "Prioridade de Alvo",
            Values = {"Mais Raro", "Maior Renda", "Mais Proximo"},
            Default = "Mais Raro",
            Callback = function(val)
                Config.PriorityMode = val
                addLog("CONFIG", "Prioridade alterada para: " .. tostring(val))
            end
        })

        Tabs.AutoSteal:AddSlider("MoveSpeedSlider", {
            Title = "Velocidade de Deslocamento",
            Description = "Velocidade de voo overhead e movimentacao segura",
            Default = Config.MoveSpeed or 45,
            Min = 16,
            Max = 100,
            Rounding = 0,
            Callback = function(val)
                Config.MoveSpeed = val
            end
        })

        Tabs.AutoSteal:AddButton({
            Title = "Esvaziar Maos (Descartar Ovo Preso)",
            Description = "Descarta qualquer ovo que tenha travado nas maos",
            Callback = function()
                local dropped = false
                pcall(function()
                    if GameModules.EggState and GameModules.EggState.DropFieldEgg then
                        GameModules.EggState.DropFieldEgg("PlayerRequest")
                        dropped = true
                    end
                end)
                pcall(function()
                    local askDrop = getRemote("RF/EggWorld/AskFieldEggDrop")
                    if askDrop and askDrop:IsA("RemoteFunction") then
                        askDrop:InvokeServer({ Reason = "PlayerRequest" })
                        dropped = true
                    end
                end)
                addLog("ROUBO", dropped and "Comando de esvaziar maos enviado ao servidor." or "Nenhum ovo para descartar.")
                Fluent:Notify({
                    Title = "Esvaziar Maos",
                    Content = "Comando de descarte enviado!",
                    Duration = 2
                })
            end
        })

        Tabs.AutoSteal:AddButton({
            Title = "Teleportar para Minha Base / Ninho",
            Description = "Retorna instantaneamente para sua base",
            Callback = function()
                local dep = getMyDepositCFrame() or State.BaseCFrame
                local hrp = getHRP()
                if dep and hrp then
                    hrp.CFrame = dep + Vector3.new(0, 3, 0)
                    hrp.AssemblyLinearVelocity = Vector3.zero
                    addLog("TELEPORTE", "Retornado para sua base com sucesso.")
                end
            end
        })

        -- 2. ABA AUTO-ESTEIRA
        local EsteiraToggle = Tabs.Esteira:AddToggle("EsteiraToggle", {
            Title = "Ativar Treino na Esteira",
            Description = "Monta na esteira oficial com AskWearStill e treina sem travar",
            Default = Config.AutoEsteiraEnabled,
            Callback = function(val)
                Config.AutoEsteiraEnabled = val
                if not val then
                    lastTreadmillMode = "OFF"
                    State.IsOnTreadmill = false
                    local hum = getHum()
                    if hum then hum:Move(Vector3.zero, false) end
                    pcall(function()
                        local askDoff = getRemote("RF/EggWorld/AskDoff")
                        if askDoff and askDoff:IsA("RemoteFunction") then
                            askDoff:InvokeServer()
                        end
                    end)
                end
                addLog("ESTEIRA", val and "Auto-Esteira iniciada." or "Auto-Esteira desativada.")
                Fluent:Notify({
                    Title = "Auto-Esteira",
                    Content = val and "Treino ATIVADO" or "Treino DESATIVADO",
                    Duration = 2
                })
            end
        })

        Tabs.Esteira:AddDropdown("EsteiraModeDropdown", {
            Title = "Modo de Treino",
            Values = {"Velocidade (Speed)", "Forca (Power)"},
            Default = "Velocidade (Speed)",
            Callback = function(val)
                Config.EsteiraMode = (val:find("Forca") and "Power") or "Speed"
                addLog("ESTEIRA", "Modo de esteira alterado para: " .. tostring(Config.EsteiraMode))
            end
        })

        Tabs.Esteira:AddButton({
            Title = "Desmontar Esteira Imediatamente (AskDoff)",
            Description = "Libera o personagem e restaura controles fisicos",
            Callback = function()
                Config.AutoEsteiraEnabled = false
                EsteiraToggle:SetValue(false)
                State.IsOnTreadmill = false
                pcall(function()
                    local askDoff = getRemote("RF/EggWorld/AskDoff")
                    if askDoff and askDoff:IsA("RemoteFunction") then
                        askDoff:InvokeServer()
                    end
                end)
                local hum = getHum()
                if hum then
                    hum:Move(Vector3.zero, false)
                    hum.PlatformStand = false
                end
                addLog("ESTEIRA", "Desmonte oficial concluido.")
                Fluent:Notify({
                    Title = "Esteira",
                    Content = "Personagem desmontado com sucesso!",
                    Duration = 2
                })
            end
        })

        -- 3. ABA RADAR DE OVOS (100% NOMES REAIS VIA DUMP ENGINE)
        local RadarSummary = Tabs.Radar:AddParagraph({
            Title = "Radar Forense Oficial",
            Content = "Clique em 'Atualizar Radar Agora' para escanear ovos com 100% de precisao."
        })

        local scannedEggsCache = {}
        local scannedEggLabels = {"(Nenhum ovo escaneado ainda)"}
        local selectedEggIndex = 1

        local SelectedEggDropdown = Tabs.Radar:AddDropdown("RadarEggsDropdown", {
            Title = "Ovos Vivos no Mapa",
            Values = scannedEggLabels,
            Default = scannedEggLabels[1],
            Callback = function(val)
                for idx, label in ipairs(scannedEggLabels) do
                    if label == val then
                        selectedEggIndex = idx
                        break
                    end
                end
            end
        })

        local function refreshRadarUI()
            local eggs = scanAllEggs()
            scannedEggsCache = eggs
            local newLabels = {}
            local secretCount = 0
            local legendaryCount = 0

            for idx, egg in ipairs(eggs) do
                local rUpper = egg.Rarity:upper()
                if rUpper:find("SECRET") then secretCount = secretCount + 1 end
                if rUpper:find("LEGEND") then legendaryCount = legendaryCount + 1 end

                local incStr = ""
                if egg.Income and egg.Income > 0 then
                    if egg.Income >= 1000000000 then
                        incStr = string.format(" • %.1fB/s", egg.Income / 1000000000)
                    elseif egg.Income >= 1000000 then
                        incStr = string.format(" • %.1fM/s", egg.Income / 1000000)
                    elseif egg.Income >= 1000 then
                        incStr = string.format(" • %.1fK/s", egg.Income / 1000)
                    else
                        incStr = string.format(" • %d/s", egg.Income)
                    end
                end
                local label = string.format("[%s] %s (%s, %dm)%s", egg.Rarity, egg.Name, egg.Zone, math.floor(egg.Distance), incStr)
                table.insert(newLabels, label)
                if idx >= 60 then break end
            end

            if #newLabels == 0 then
                newLabels = {"(Nenhum ovo disponivel no momento)"}
            end
            scannedEggLabels = newLabels
            SelectedEggDropdown:SetValues(newLabels)
            SelectedEggDropdown:SetValue(newLabels[1])
            selectedEggIndex = 1

            RadarSummary:SetTitle(string.format("Radar: %d Ovos Vivos no Mapa", #eggs))
            RadarSummary:SetDesc(string.format("Ovos Secretos: %d | Ovos Lendarios: %d\nFonte: EggState.ReadFieldEggs + Data.Assets.Directory (100%% Nomes Reais)", secretCount, legendaryCount))
        end

        Tabs.Radar:AddButton({
            Title = "Atualizar Radar Agora",
            Description = "Faz varredura imediata dos ovos vivos",
            Callback = function()
                refreshRadarUI()
                Fluent:Notify({
                    Title = "Radar Atualizado",
                    Content = string.format("%d ovos mapeados!", #scannedEggsCache),
                    Duration = 2
                })
            end
        })

        Tabs.Radar:AddButton({
            Title = "Roubar Ovo Selecionado Acima",
            Description = "Inicia rota segura para roubar o ovo selecionado",
            Callback = function()
                local targetEgg = scannedEggsCache[selectedEggIndex]
                if targetEgg then
                    addLog("ROUBO", string.format("Iniciando roubo manual de: %s [%s]", targetEgg.Name, targetEgg.Rarity))
                    task.spawn(function()
                        executeDirectSteal(targetEgg)
                    end)
                    Fluent:Notify({
                        Title = "Iniciando Roubo",
                        Content = "Indo ate: " .. targetEgg.Name,
                        Duration = 3
                    })
                else
                    Fluent:Notify({
                        Title = "Erro",
                        Content = "Nenhum ovo valido selecionado!",
                        Duration = 2
                    })
                end
            end
        })

        -- 4. ABA ARMAS SECRETAS & PETS
        Tabs.ArmasPets:AddSection("Armas Secretas (Pedestais Oficiais)")
        Tabs.ArmasPets:AddParagraph({
            Title = "Pedestais no Mapa",
            Content = "O mapa original contem 2 pedestais fisicos com TouchPart (Slap Glove e Bat). A 3a arma (Bee Launcher) e recompensa de conquista do Index."
        })

        Tabs.ArmasPets:AddButton({
            Title = "Coletar Armas Secretas (Slap Glove + Bat)",
            Description = "Aciona os 2 pedestais fisicos via TouchPart com 0.7s de contato",
            Callback = function()
                task.spawn(function()
                    collectAllSecretWeapons()
                    Fluent:Notify({
                        Title = "Armas Secretas",
                        Content = "Coleta finalizada! Verifique seu Backpack.",
                        Duration = 3
                    })
                end)
            end
        })

        Tabs.ArmasPets:AddSection("Gerenciador Nativo de Pets")
        Tabs.ArmasPets:AddButton({
            Title = "Equipar Melhores Pets (Wear Best)",
            Description = "Invoca RF/Haul/WearBest no servidor",
            Callback = function()
                local ok = equipBestPets()
                Fluent:Notify({
                    Title = "Equipar Melhores",
                    Content = ok and "Melhores pets equipados!" or "Comando enviado ao servidor.",
                    Duration = 2
                })
            end
        })

        Tabs.ArmasPets:AddButton({
            Title = "Vender Pets Comuns & Incomuns Agora",
            Description = "Filtra inventario com Save.Get() e vende via RE/PetSatchel/SellEveryPet",
            Callback = function()
                sellCommonPetsInInventory()
                Fluent:Notify({
                    Title = "Auto-Sell",
                    Content = "Pets comuns/incomuns vendidos!",
                    Duration = 3
                })
            end
        })

        Tabs.ArmasPets:AddToggle("AutoHatchToggle", {
            Title = "Auto-Hatch nos Ninhos",
            Description = "Choca ovos dos seus ninhos assim que o timer zera",
            Default = Config.AutoHatchEnabled,
            Callback = function(val)
                Config.AutoHatchEnabled = val
                addLog("HATCH", val and "Auto-Hatch ATIVADO." or "Auto-Hatch PAUSADO.")
            end
        })

        Tabs.ArmasPets:AddToggle("AutoSellToggle", {
            Title = "Auto-Sell Continuo no Servidor",
            Description = "Sincroniza venda automatica continua com RF/Haul/WriteAutoSell",
            Default = false,
            Callback = function(val)
                configureNativeAutoSell({
                    Common = val,
                    Uncommon = val
                })
                addLog("PETS", val and "Auto-Sell continuo ativado no servidor." or "Auto-Sell continuo desativado.")
            end
        })

        -- 5. ABA TELEPORTES
        local TeleportTargets = {
            ["Minha Base / Ninho"] = function() return getMyDepositCFrame() or State.BaseCFrame end,
            ["Spawn Principal"] = function() return CFrame.new(0, 10, 0) end,
            ["Ilha do Vulcao"] = function() return CFrame.new(650, 65, 0) end,
            ["Ilha do Deserto"] = function() return CFrame.new(850, 75, 0) end,
            ["Ilha de Gelo"] = function() return CFrame.new(1100, 85, 0) end,
            ["Ilha Cibernetica"] = function() return CFrame.new(1400, 95, 0) end,
            ["Pedestal Slap Glove"] = function() return CFrame.new(545.01, 55, -357.85) end,
            ["Pedestal Bat / Choque"] = function() return CFrame.new(545.01, 55, -344.76) end
        }

        local selectedTpName = "Minha Base / Ninho"
        local tpKeys = {}
        for k in pairs(TeleportTargets) do table.insert(tpKeys, k) end
        table.sort(tpKeys)

        Tabs.Teleports:AddDropdown("TeleportDropdown", {
            Title = "Destino",
            Values = tpKeys,
            Default = "Minha Base / Ninho",
            Callback = function(val)
                selectedTpName = val
            end
        })

        Tabs.Teleports:AddButton({
            Title = "Teleportar Agora",
            Description = "Move o personagem para o destino selecionado",
            Callback = function()
                local fn = TeleportTargets[selectedTpName]
                local targetCF = fn and fn()
                local hrp = getHRP()
                if targetCF and hrp then
                    hrp.CFrame = targetCF + Vector3.new(0, 3, 0)
                    hrp.AssemblyLinearVelocity = Vector3.zero
                    addLog("TELEPORTE", "Teleportado para: " .. tostring(selectedTpName))
                    Fluent:Notify({
                        Title = "Teleporte",
                        Content = "Teleportado para: " .. tostring(selectedTpName),
                        Duration = 2
                    })
                end
            end
        })

        -- 6. ABA CONSOLE / LOGS
        local LogParagraph = Tabs.Logs:AddParagraph({
            Title = "Console em Tempo Real",
            Content = "Iniciando monitoramento de logs..."
        })

        local function updateLogsView()
            local logLines = {}
            local startIdx = math.max(1, #LogHistory - 20)
            for i = startIdx, #LogHistory do
                table.insert(logLines, LogHistory[i])
            end
            if #logLines == 0 then
                logLines = {"Nenhum evento registrado ainda."}
            end
            LogParagraph:SetDesc(table.concat(logLines, "\n"))
        end

        Tabs.Logs:AddButton({
            Title = "Atualizar Logs",
            Description = "Atualiza o console com os eventos mais recentes",
            Callback = function()
                updateLogsView()
            end
        })

        Tabs.Logs:AddButton({
            Title = "Limpar Historico",
            Description = "Esvazia os registros de logs",
            Callback = function()
                LogHistory = {}
                LogParagraph:SetDesc("Historico limpo.")
            end
        })

        local oldAddLog = addLog
        addLog = function(category, message)
            oldAddLog(category, message)
            pcall(updateLogsView)
        end

        Window:SelectTab(1)
        task.spawn(function()
            task.wait(1)
            refreshRadarUI()
            updateLogsView()
        end)

        Fluent:Notify({
            Title = "Roube um Ovo Hub v14.1",
            Content = "Hub carregado com Fluent Design & Dump Engine Oficial!",
            Duration = 5
        })

        uiCreated = true
    end)
    if not okWin then
        warn("[RoubeUmOvo] Erro ao criar Fluent Window: " .. tostring(errWin))
    end
end

-- FALLBACK NATIVO: Se o Fluent falhar por qualquer motivo (executor sem suporte ou sem HTTP)
if not uiCreated then
    warn("[RoubeUmOvo] Ativando Fallback Nativo ScreenGui...")

    local FallbackGui = Instance.new("ScreenGui")
    FallbackGui.Name = "RoubeUmOvo_FallbackHub"
    FallbackGui.ResetOnSpawn = false
    attachGui(FallbackGui)

    local Main = Instance.new("Frame")
    Main.Size = UDim2.new(0, 520, 0, 380)
    Main.Position = UDim2.new(0.5, -260, 0.5, -190)
    Main.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
    Main.BorderSizePixel = 0
    Main.Active = true
    Main.Draggable = true
    Main.Parent = FallbackGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = Main

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(56, 189, 248)
    stroke.Thickness = 1.5
    stroke.Parent = Main

    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(1, -20, 0, 36)
    Title.Position = UDim2.new(0, 10, 0, 5)
    Title.BackgroundTransparency = 1
    Title.Text = "ROUBE UM OVO • HUB MASTER v14.1 (DUMP ENGINE)"
    Title.Font = Enum.Font.GothamBold
    Title.TextSize = 13
    Title.TextColor3 = Color3.fromRGB(56, 189, 248)
    Title.TextXAlignment = Enum.TextXAlignment.Left
    Title.Parent = Main

    local function createBtn(text, pos, color, onClick)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0.48, -10, 0, 36)
        btn.Position = pos
        btn.BackgroundColor3 = color or Color3.fromRGB(30, 41, 59)
        btn.Text = text
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 10
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.Parent = Main
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 6)
        c.Parent = btn
        btn.MouseButton1Click:Connect(onClick)
        return btn
    end

    local stealBtn = createBtn(Config.AutoStealEnabled and "AUTO-STEAL: [ATIVO]" or "AUTO-STEAL: [DESATIVADO]", UDim2.new(0, 10, 0, 50), Color3.fromRGB(30, 41, 59), function()
        Config.AutoStealEnabled = not Config.AutoStealEnabled
        stealBtn.BackgroundColor3 = Config.AutoStealEnabled and Color3.fromRGB(22, 101, 52) or Color3.fromRGB(30, 41, 59)
        stealBtn.Text = Config.AutoStealEnabled and "AUTO-STEAL: [ATIVO]" or "AUTO-STEAL: [DESATIVADO]"
        addLog("ROUBO", Config.AutoStealEnabled and "Auto-Steal ativado." or "Auto-Steal desativado.")
    end)

    local esteiraBtn = createBtn(Config.AutoEsteiraEnabled and "ESTEIRA: [ATIVO]" or "ESTEIRA: [DESATIVADO]", UDim2.new(0.52, 0, 0, 50), Color3.fromRGB(30, 41, 59), function()
        Config.AutoEsteiraEnabled = not Config.AutoEsteiraEnabled
        esteiraBtn.BackgroundColor3 = Config.AutoEsteiraEnabled and Color3.fromRGB(22, 101, 52) or Color3.fromRGB(30, 41, 59)
        esteiraBtn.Text = Config.AutoEsteiraEnabled and "ESTEIRA: [ATIVO]" or "ESTEIRA: [DESATIVADO]"
        addLog("ESTEIRA", Config.AutoEsteiraEnabled and "Auto-Esteira ativada." or "Auto-Esteira desativada.")
    end)

    createBtn("PEGAR ARMAS (SLAP + BAT)", UDim2.new(0, 10, 0, 95), Color3.fromRGB(217, 119, 6), function()
        task.spawn(collectAllSecretWeapons)
    end)

    createBtn("EQUIPAR MELHORES PETS", UDim2.new(0.52, 0, 0, 95), Color3.fromRGB(16, 185, 129), function()
        equipBestPets()
    end)

    createBtn("VENDER COMUNS / INCOMUNS", UDim2.new(0, 10, 0, 140), Color3.fromRGB(239, 68, 68), function()
        sellCommonPetsInInventory()
    end)

    createBtn("ESVAZIAR MAOS (DESCARTE)", UDim2.new(0.52, 0, 0, 140), Color3.fromRGB(100, 116, 139), function()
        pcall(function()
            if GameModules.EggState and GameModules.EggState.DropFieldEgg then
                GameModules.EggState.DropFieldEgg("PlayerRequest")
            end
        end)
    end)

    createBtn("TELEPORTAR PARA MINHA BASE", UDim2.new(0, 10, 0, 185), Color3.fromRGB(59, 130, 246), function()
        local dep = getMyDepositCFrame() or State.BaseCFrame
        local hrp = getHRP()
        if dep and hrp then
            hrp.CFrame = dep + Vector3.new(0, 3, 0)
            hrp.AssemblyLinearVelocity = Vector3.zero
        end
    end)

    createBtn("DESMONTAR ESTEIRA (ASKDOFF)", UDim2.new(0.52, 0, 0, 185), Color3.fromRGB(147, 51, 234), function()
        pcall(function()
            local askDoff = getRemote("RF/EggWorld/AskDoff")
            if askDoff and askDoff:IsA("RemoteFunction") then
                askDoff:InvokeServer()
            end
        end)
    end)

    local StatusLog = Instance.new("TextLabel")
    StatusLog.Size = UDim2.new(1, -20, 0, 130)
    StatusLog.Position = UDim2.new(0, 10, 0, 235)
    StatusLog.BackgroundColor3 = Color3.fromRGB(11, 15, 26)
    StatusLog.TextColor3 = Color3.fromRGB(148, 163, 184)
    StatusLog.Font = Enum.Font.Code
    StatusLog.TextSize = 9
    StatusLog.TextXAlignment = Enum.TextXAlignment.Left
    StatusLog.TextYAlignment = Enum.TextYAlignment.Top
    StatusLog.TextWrapped = true
    StatusLog.Text = "Status: Hub Master carregado com sucesso via Fallback Nativo."
    StatusLog.Parent = Main

    local oldAddLog = addLog
    addLog = function(cat, msg)
        oldAddLog(cat, msg)
        pcall(function()
            local lines = {}
            for i = math.max(1, #LogHistory - 6), #LogHistory do
                table.insert(lines, LogHistory[i])
            end
            StatusLog.Text = table.concat(lines, "\n")
        end)
    end
end

-- Telemetria de Inicializacao Concluida
addLog("INIT", "Roube um Ovo Hub v14.1 carregado com sucesso!")

--[[
    ROUBE UM OVO - HUB DE AUTOMAÇÃO & RADAR (v9.5 NOMES ÚNICOS & CLEAN UI)
    -----------------------------------------------------------------------
    - Nomes Únicos de Ovos: Cada um dos 5 slots de cada ilha possui o nome
      real do pet do drop (Godzilla, King Kong, Kitsune, Oni Tiger, etc.).
    - Sistema de Unload Completo: Botão no topo e configurações para encerrar
      100% das threads, limpar conexões, remover ESP e fechar interface.
    - Catálogo Oficial dos 11 Biomas (Ilhas 1 a 11): Coordenadas exatas, nomes
      reais e raridades legítimas (Comum a Titã - Godzilla/Kitsune).
    - Mecânica de Ragdoll TP da Galinha (Bypass Anti-Cheat):
      Provoca hit proposital da Galinha da Floresta (Biome 1) e usa a janela
      de Ragdoll da física para teleportar ao melhor ovo e à base sem tomar
      dano fatal nem rubberband do servidor.
    - Suporte a Ovos Especiais: Demonic Egg, Dragon Egg, Limited e Brainrot.
    - Neutralização Ativa Anti-Cheat e Movimento Seguro.
]]

-- 1. Silenciamento Total Preventivo contra LogService.MessageOut
local function silentOutput(...) end
local print = silentOutput
local warn = silentOutput

-- 2. Limpeza Preventiva de Globais
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

-- 3. Serviços Seguros via cloneref
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
    TweenService = safeService("TweenService"),
    ReplicatedStorage = safeService("ReplicatedStorage"),
    CoreGui = safeService("CoreGui")
}

local LocalPlayer = Services.Players.LocalPlayer
while not LocalPlayer do
    task.wait(0.2)
    LocalPlayer = Services.Players.LocalPlayer
end

-- Gerenciador Mestre de Conexões e Limpeza de Execuções Anteriores

local function registerConnection(conn)
    if conn then
        table.insert(ScriptConnections, conn)
    end
    return conn
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

-- 4. NEUTRALIZAÇÃO ATIVA DE ANTI-CHEAT LOCAL DO CHARACTER (SEM DESATIVAR RAGDOLL)
local function disableCharacterAntiCheats(char)
    if not char then return end
    pcall(function()
        for _, child in ipairs(char:GetChildren()) do
            if child:IsA("LocalScript") then
                local low = child.Name:lower()
                if low:find("anticollision") or low:find("highseed") or low:find("highspeed")
                    or low:find("pushback") or low:find("fixcollision") then
                    child.Disabled = true
                    child:Destroy()
                end
            end
        end
        -- Manter Ragdoll HABILITADO para permitir o bypass do golpe da Galinha
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
            hum:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, true)
        end
    end)
end

if LocalPlayer.Character then
    disableCharacterAntiCheats(LocalPlayer.Character)
end

registerConnection(LocalPlayer.CharacterAdded:Connect(function(newChar)
    if State.IsUnloaded then return end
    task.wait(0.1)
    disableCharacterAntiCheats(newChar)
    registerConnection(newChar.ChildAdded:Connect(function(child)
        if child:IsA("LocalScript") then
            local low = child.Name:lower()
            if low:find("anticollision") or low:find("highseed") or low:find("highspeed")
                or low:find("pushback") or low:find("fixcollision") then
                task.wait()
                child.Disabled = true
                pcall(function() child:Destroy() end)
            end
        end
    end))
end))

-- 5. Configuração e Estado Geral
local Config = {
    StealMethod = "RagdollTP", -- "RagdollTP" ou "VooDireto"
    AutoStealEnabled = false,
    AutoEsteiraEnabled = false,
    SafeFlightEnabled = true,
    LockCurrentIsland = true,
    MaxStealDistance = 450,
    MoveSpeed = 350,
    TargetRarity = "Qualquer",
    MinRarityScore = 0,
    ESPEnabled = false,
    ShowOnlyUnowned = true,
    AutoDepositWait = 1.0,
    SearchQuery = "",
    InfJumpEnabled = false,
    NoclipEnabled = false,
    WalkSpeed = 16
}


local State = {
    IsUnloaded = false,
    BaseCFrame = nil,
    PlotFound = false,
    IsExecutingSteal = false,
    IsOnTreadmill = false,
    CurrentTargetEgg = nil,
    LastPromptTriggered = nil,
    Logs = {}
}

-- Declarações antecipadas de componentes da UI para acesso global interno
local ScreenGui = nil
local MobileBtn = nil
local MainFrame = nil
local StatusBadge = nil
local TargetInfoLabel = nil
local BaseLabel = nil
local EsteiraStatusLabel = nil
local MainToggleBtn = nil
local unloadScript = nil

local function addLog(category, msg)
    local timestamp = os.date("%H:%M:%S")
    local entry = string.format("[%s] [%s] %s", timestamp, category, msg)
    table.insert(State.Logs, 1, entry)
    if #State.Logs > 100 then table.remove(State.Logs) end
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

-- 6. Detecção de Posse de Ovo Ultra-Ampla
local standardLimbNames = {
    ["head"] = true, ["uppertorso"] = true, ["lowertorso"] = true,
    ["leftupperarm"] = true, ["rightupperarm"] = true, ["leftlowerarm"] = true,
    ["rightlowerarm"] = true, ["lefthand"] = true, ["righthand"] = true,
    ["leftlowerleg"] = true, ["rightlowerleg"] = true, ["leftfoot"] = true,
    ["rightfoot"] = true, ["humanoidrootpart"] = true,
    ["leftupperleg"] = true, ["rightupperleg"] = true, ["torso"] = true,
    ["left arm"] = true, ["right arm"] = true, ["left leg"] = true,
    ["right leg"] = true, ["animate"] = true, ["humanoid"] = true
}

local function isHoldingEgg()
    local char = LocalPlayer.Character
    if not char then return false, nil end

    -- 1. Atributos no Personagem
    for k, v in pairs(char:GetAttributes()) do
        local low = k:lower()
        if low:find("egg") or low:find("carry") or low:find("hold") or low:find("uid") or low:find("grab") then
            if v ~= nil and v ~= "" and v ~= false then
                return true, k .. "=" .. tostring(v)
            end
        end
    end

    -- 2. Atributos no LocalPlayer
    for k, v in pairs(LocalPlayer:GetAttributes()) do
        local low = k:lower()
        if low:find("egg") or low:find("carry") or low:find("hold") or low:find("uid") or low:find("grab") then
            if v ~= nil and v ~= "" and v ~= false then
                return true, k .. "=" .. tostring(v)
            end
        end
    end

    -- 3. Objetos soldados ao personagem (Chicken Egg, UUID ou modelo anexado)
    for _, child in ipairs(char:GetChildren()) do
        local low = child.Name:lower()
        if not standardLimbNames[low] and not child:IsA("Accessory") and not child:IsA("Shirt")
            and not child:IsA("Pants") and not child:IsA("BodyColors") and not child:IsA("CharacterMesh") then
            if child:IsA("Tool") then
                return true, child.Name
            end
            if child:IsA("Model") or child:IsA("BasePart") then
                local hasWeld = child:FindFirstChildWhichIsA("WeldConstraint", true)
                    or child:FindFirstChildWhichIsA("Weld", true)
                    or child:FindFirstChildWhichIsA("Motor6D", true)
                if hasWeld then
                    return true, child.Name
                end
            end
        end
    end

    -- 4. Mochila (Backpack)
    local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
    if bp then
        for _, item in ipairs(bp:GetChildren()) do
            if item:IsA("Tool") then
                local n = item.Name:lower()
                if n:find("egg") or n:find("ovo") or item:GetAttribute("IsEgg") or item:GetAttribute("EggType") then
                    return true, item.Name
                end
            end
        end
    end

    -- 5. Indicador em PlayerGui
    local pgui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if pgui then
        local eggDataGui = pgui:FindFirstChild("AssetEggData")
        if eggDataGui and eggDataGui.Enabled then
            return true, "AssetEggData"
        end
    end

    return false, nil
end

local function plainText(v)
    return tostring(v or ""):gsub("<[^>]->", ""):lower()
end

local function getPositionOf(obj)
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

-- 7.1. BANCO DE DADOS DAS 11 ILHAS OFICIAIS E PETS ÚNICOS POR SLOT
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
            [1] = { Name = "Brr Brr Patapim", Rarity = "LENDÁRIO", Score = 15000 },
            [2] = { Name = "Urso (Bear)", Rarity = "ÉPICO", Score = 8000 },
            [3] = { Name = "Raposa do Pântano (Mire Fox)", Rarity = "ÉPICO", Score = 8000 },
            [4] = { Name = "Guaxinim (Raccoon)", Rarity = "RARO", Score = 3500 },
            [5] = { Name = "Galinha (Chicken)", Rarity = "COMUM", Score = 300 }
        }
    },
    {
        Id = "Lake",
        Name = "Lago (Ilha 2)",
        MinX = 671, MaxX = 850,
        BaseZ = -410,
        Rarity = "INCOMUM",
        Score = 1500,
        TopDrop = "Crocodile",
        EggShell = "Ovo do Lago",
        Guard = "Lake Guard",
        SlotPets = {
            [1] = { Name = "Crocodilo (Crocodile)", Rarity = "ÉPICO", Score = 8000 },
            [2] = { Name = "Cisne (Swan)", Rarity = "ÉPICO", Score = 8000 },
            [3] = { Name = "Peixe-Gato (Catfish)", Rarity = "INCOMUM", Score = 1500 },
            [4] = { Name = "Patinho (Duckling)", Rarity = "COMUM", Score = 300 },
            [5] = { Name = "Sapo (Frog)", Rarity = "COMUM", Score = 300 }
        }
    },
    {
        Id = "Desert",
        Name = "Deserto (Ilha 3)",
        MinX = 851, MaxX = 1080,
        BaseZ = -325,
        Rarity = "RARO",
        Score = 3500,
        TopDrop = "Scorpio",
        EggShell = "Ovo do Deserto",
        Guard = "Desert Guard",
        SlotPets = {
            [1] = { Name = "Aranha da Areia (Sand Spider)", Rarity = "MÍTICO", Score = 20000 },
            [2] = { Name = "Escorpião (Scorpio)", Rarity = "LENDÁRIO", Score = 15000 },
            [3] = { Name = "Cobra Coral (Rattlesnake)", Rarity = "LENDÁRIO", Score = 15000 },
            [4] = { Name = "Camelo (Camel)", Rarity = "RARO", Score = 3500 },
            [5] = { Name = "Jerboa", Rarity = "COMUM", Score = 300 }
        }
    },
    {
        Id = "Jungle",
        Name = "Selva (Ilha 4)",
        MinX = 1081, MaxX = 1350,
        BaseZ = -410,
        Rarity = "ÉPICO",
        Score = 8000,
        TopDrop = "Bananita Dolphinita",
        EggShell = "Ovo da Selva",
        Guard = "Jungle Guard",
        SlotPets = {
            [1] = { Name = "Tigre Real (Tiger)", Rarity = "MÍTICO", Score = 20000 },
            [2] = { Name = "Gorila (Gorilla)", Rarity = "LENDÁRIO", Score = 15000 },
            [3] = { Name = "Orangutango (Orangutini)", Rarity = "LENDÁRIO", Score = 15000 },
            [4] = { Name = "Golfinho Banana (Bananita)", Rarity = "ÉPICO", Score = 8000 },
            [5] = { Name = "Chimpanzé (Chimpanzee)", Rarity = "RARO", Score = 3500 }
        }
    },
    {
        Id = "Snow",
        Name = "Neve (Ilha 5)",
        MinX = 1351, MaxX = 1680,
        BaseZ = -315,
        Rarity = "LENDÁRIO",
        Score = 15000,
        TopDrop = "Yeti",
        EggShell = "Ovo da Neve",
        Guard = "Snow Guard",
        SlotPets = {
            [1] = { Name = "Yeti das Neves", Rarity = "SECRET", Score = 45000 },
            [2] = { Name = "Mamute Real (Mammoth)", Rarity = "MÍTICO", Score = 20000 },
            [3] = { Name = "Urso Polar (Polar Bear)", Rarity = "LENDÁRIO", Score = 15000 },
            [4] = { Name = "Morsa (Walrus)", Rarity = "ÉPICO", Score = 8000 },
            [5] = { Name = "Pinguim (Penguin)", Rarity = "RARO", Score = 3500 }
        }
    },
    {
        Id = "Volcano",
        Name = "Vulcão (Ilha 6)",
        MinX = 1681, MaxX = 2080,
        BaseZ = -400,
        Rarity = "MÍTICO",
        Score = 20000,
        TopDrop = "Shadow Dragon",
        EggShell = "Ovo do Vulcão",
        Guard = "Volcano Guard",
        SlotPets = {
            [1] = { Name = "Dragão da Sombra (Shadow Dragon)", Rarity = "MÍTICO", Score = 20000 },
            [2] = { Name = "Touro Flamejante (Flaming Bull)", Rarity = "LENDÁRIO", Score = 15000 },
            [3] = { Name = "Iguana de Lava (Lava Iguana)", Rarity = "LENDÁRIO", Score = 15000 },
            [4] = { Name = "Sapo de Lava (Lava Frog)", Rarity = "ÉPICO", Score = 8000 },
            [5] = { Name = "Geco de Cinzas (Ash Gecko)", Rarity = "RARO", Score = 3500 }
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
            [1] = { Name = "El Maja", Rarity = "ETERNAL", Score = 70000 },
            [2] = { Name = "Kraken", Rarity = "SECRET", Score = 45000 },
            [3] = { Name = "Baleia Alabaster (Beluga)", Rarity = "COSMIC", Score = 30000 },
            [4] = { Name = "Tubarão Baleia (Whale Shark)", Rarity = "COSMIC", Score = 30000 },
            [5] = { Name = "Orca Assassina", Rarity = "MÍTICO", Score = 20000 }
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
            [1] = { Name = "Mosassauro (Mosasaurus)", Rarity = "ETERNAL", Score = 70000 },
            [2] = { Name = "T-Rex (Tyrannosaurus Rex)", Rarity = "SECRET", Score = 45000 },
            [3] = { Name = "Tralaledon", Rarity = "SECRET", Score = 45000 },
            [4] = { Name = "Brontossauro (Bronto)", Rarity = "COSMIC", Score = 30000 },
            [5] = { Name = "Pterodáctilo (Pterodactyl)", Rarity = "LENDÁRIO", Score = 15000 }
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
            [1] = { Name = "Unicórnio Divino (Unicorn)", Rarity = "DIVINE", Score = 100000 },
            [2] = { Name = "Dragão Lunar Eterno", Rarity = "ETERNAL", Score = 70000 },
            [3] = { Name = "Dragão Cósmico (Cave Dragon)", Rarity = "SECRET", Score = 45000 },
            [4] = { Name = "Chefe Esqueleto Cósmico", Rarity = "SECRET", Score = 45000 },
            [5] = { Name = "Geco Cósmico (Galaxy Gecko)", Rarity = "LENDÁRIO", Score = 15000 }
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
            [1] = { Name = "Kitsune Ancestral", Rarity = "DIVINE", Score = 100000 },
            [2] = { Name = "Tigre Oni (Oni Tiger)", Rarity = "ETERNAL", Score = 70000 },
            [3] = { Name = "Cervo Sagrado (Stag)", Rarity = "SECRET", Score = 45000 },
            [4] = { Name = "Carpa Cósmica (Koi)", Rarity = "COSMIC", Score = 30000 },
            [5] = { Name = "Coruja das Neves (Snowy Owl)", Rarity = "COSMIC", Score = 30000 }
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
            [1] = { Name = "Godzilla (Titã)", Rarity = "TITAN", Score = 150000 },
            [2] = { Name = "King Kong (Gorilla King)", Rarity = "ETERNAL", Score = 70000 },
            [3] = { Name = "Lâmina Oculta (Blade Head)", Rarity = "MÍTICO", Score = 20000 },
            [4] = { Name = "Rinoceronte (Rhino)", Rarity = "COSMIC", Score = 30000 },
            [5] = { Name = "Aranha Titânica (Kaiju Spider)", Rarity = "LENDÁRIO", Score = 15000 }
        }
    }
}

local function getIslandByPos(pos)
    if not pos then return OfficialIslands[1] end
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

-- 8. MAPEAMENTO NUMÉRICO DE MESHID E BANCO DE DADOS DINÂMICO
local NumericMeshToEggMap = {}
local AssetsDirectoryData = {}
local RarityDataMap = {}

local function registerNumericMesh(meshIdStr, eggName)
    if not meshIdStr or not eggName then return end
    local num = tostring(meshIdStr):match("(%d+)")
    if num and num ~= "" then
        NumericMeshToEggMap[num] = eggName
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

-- Identificação Completa de Nome Real, Raridade e Estatísticas do Ovo
local function resolveEggDetails(instance, prompt)
    local pos = getPositionOf(prompt or instance)
    local foundName = nil
    local detectedRarity = nil
    local maxScore = 300
    local detectedWeight = 0
    local detectedIncome = nil

    local renderedModel = findNearbyRenderedAsset(pos, 6.5)

    local function inspectStr(s)
        if not s or s == "" then return false end
        local low = tostring(s):lower()
        if isHexUUID(low) or low == "assets" or low == "model" or low == "part"
            or low == "meshpart" or low == "union" or low == "touchinterest" then
            return false
        end

        -- 1. Casamento direto no catálogo de 118 Pets
        for pKey, pData in pairs(KnownPetsCatalog) do
            if low == pKey or low:find(pKey, 1, true) then
                if not foundName or #pData.DisplayName > #foundName then
                    foundName = pData.DisplayName
                    detectedRarity = pData.Rarity
                    maxScore = math.max(maxScore, RarityScoreMap[pData.Rarity] or 5000)
                end
                return true
            end
        end

        -- 2. Casamento em AssetsDirectoryData
        if AssetsDirectoryData[low] then
            local entry = AssetsDirectoryData[low]
            foundName = entry.DisplayName
            detectedRarity = entry.Rarity
            maxScore = math.max(maxScore, RarityScoreMap[entry.Rarity] or 5000)
            if entry.Weight then detectedWeight = entry.Weight end
            return true
        end

        -- 3. Detecção de peso e renda
        local kg = low:match("([%d%,%.]+)%s*kg")
        if kg then
            local n = tonumber((kg:gsub(",", "")))
            if n and n > detectedWeight then detectedWeight = n end
        end

        local num, suf = low:match("%$%s*([%d][%d%,%.]*)%s*(%a*)%s*/%s*s")
        if num and not detectedIncome then
            detectedIncome = "$" .. num .. (suf or ""):upper() .. "/s"
        end

        -- 4. Detecção de Raridade pura
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

    -- Método A: Mapeamento de MeshId Numérico no modelo renderizado e no slot
    local function checkMeshes(root)
        if not root then return false end
        for _, d in ipairs(root:GetDescendants()) do
            local mId = (d:IsA("MeshPart") and d.MeshId) or (d:IsA("SpecialMesh") and d.MeshId)
            if mId and mId ~= "" then
                local num = tostring(mId):match("(%d+)")
                if num and NumericMeshToEggMap[num] then
                    inspectStr(NumericMeshToEggMap[num])
                    return true
                end
            end
        end
        return false
    end

    checkMeshes(renderedModel)
    if not foundName then checkMeshes(instance) end

    -- Método B: Inspeção de Atributos do modelo renderizado, slot e prompt
    local function checkAttrs(root)
        if not root then return end
        for k, v in pairs(root:GetAttributes()) do
            inspectStr(k)
            inspectStr(v)
        end
    end
    checkAttrs(renderedModel)
    checkAttrs(instance)
    if prompt then checkAttrs(prompt) end

    -- Método C: Inspeção de Nomes de Filhos e TextLabels
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
    checkHierarchy(renderedModel)
    checkHierarchy(instance)

    -- Método D: Inspeção do ProximityPrompt
    if prompt then
        inspectStr(prompt.ObjectText)
        inspectStr(prompt.ActionText)
        -- Limpar prefixos comuns em prompts para extrair o nome real do ovo
        if prompt.ObjectText and prompt.ObjectText ~= "" then
            local cleanObj = prompt.ObjectText:gsub("^[Tt]ake%s*", ""):gsub("^[Ss]teal%s*", ""):gsub("^[Rr]oubar%s*", ""):gsub("^[Pp]egar%s*", "")
            inspectStr(cleanObj)
        end
    end

    -- Método D2: Inspeção dos Atributos Diretos do Slot / Instância
    if instance then
        for _, attrKey in ipairs({"AssetId", "EggId", "EggType", "PetId", "PetName", "EggName", "Rarity"}) do
            local val = instance:GetAttribute(attrKey)
            if val then inspectStr(tostring(val)) end
        end
    end

    -- Método E: Resolução Exata com Nome Único do Pet de cada Slot da Ilha
    local isl = getIslandByPos(pos)
    local slotIdx = instance and tonumber(instance.Name:match("Slot_([%d]+)"))
    if not slotIdx and instance then
        -- Se não tiver no nome, calcula pelo índice de proximidade
        local parent = instance.Parent
        if parent then
            for idx, c in ipairs(parent:GetChildren()) do
                if c == instance then slotIdx = ((idx - 1) % 5) + 1 break end
            end
        end
    end
    slotIdx = slotIdx or 1

    local petInfo = isl.SlotPets and isl.SlotPets[slotIdx]
    if not foundName or isHexUUID(foundName) or foundName:find("pcube") or foundName:find("polysurface") or foundName:find("ovo") then
        if petInfo then
            foundName = string.format("Ovo de %s (%s)", petInfo.Name, isl.Name)
            detectedRarity = petInfo.Rarity
            maxScore = petInfo.Score
        else
            foundName = string.format("Ovo de %s (%s - Slot %02d)", isl.TopDrop or isl.EggShell, isl.Name, slotIdx)
            detectedRarity = isl.Rarity
            maxScore = isl.Score
        end
    end

    if not detectedRarity then
        detectedRarity = (petInfo and petInfo.Rarity) or isl.Rarity or "COMUM"
        maxScore = math.max(maxScore, (petInfo and petInfo.Score) or isl.Score or 300)
    end

    if detectedWeight > 0 and maxScore < (detectedWeight * 2) then
        maxScore = detectedWeight * 2
        detectedRarity = string.format("%s Kg", tostring(detectedWeight))
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

    -- 1. PlacedEggRenders
    pcall(function()
        local placed = Services.Workspace:FindFirstChild("PlacedEggRenders")
        if placed then
            for _, egg in ipairs(placed:GetChildren()) do
                local p = egg:FindFirstChildWhichIsA("ProximityPrompt", true)
                addCandidate(egg, p, "Base/Plot")
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
                if (existing.Name:find("Ovo Selvagem") or existing.Name == "Assets") and not cand.Name:find("Ovo Selvagem") then
                    existing.Name = cand.Name
                    existing.Rarity = cand.Rarity
                    existing.RarityScore = cand.RarityScore
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

    return deduplicated
end

-- 9. SISTEMAS DE MOVIMENTAÇÃO: RETÃO NO SOLO (IDA) & VOO ALTO SEGURO (VOLTA)
local isMoving = false

-- A. Deslocamento Direto no Solo (Ida rápida em linha reta sem subir no céu)
local function movePlayerDirect(targetPos, speed, onStep)
    local hrp = getHRP()
    local char = LocalPlayer.Character
    if not hrp or not char or isMoving then return false end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return false end

    isMoving = true
    disableCharacterAntiCheats(char)
    speed = speed or Config.MoveSpeed or 350
    local startPos = hrp.Position
    local dist = (targetPos - startPos).Magnitude

    if dist < 3.5 then
        isMoving = false
        return true
    end

    local noclipConn = Services.RunService.Stepped:Connect(function()
        if char and char.Parent then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = false
                    part.CanTouch = false
                end
            end
        end
    end)

    pcall(function()
        humanoid.PlatformStand = true
        humanoid:ChangeState(Enum.HumanoidStateType.Physics)
    end)

    local function cleanup()
        pcall(function() if noclipConn then noclipConn:Disconnect() end end)
        if char and char.Parent then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = true
                    part.CanTouch = true
                    part.AssemblyLinearVelocity = Vector3.zero
                    part.AssemblyAngularVelocity = Vector3.zero
                end
            end
            if humanoid and humanoid.Health > 0 then
                humanoid.PlatformStand = false
                humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
            end
        end
        isMoving = false
    end

    local totalTime = dist / math.max(speed, 100)
    local startTime = os.clock()

    while (os.clock() - startTime) < (totalTime + 0.3) do
        if State.IsUnloaded or not char or not char.Parent or not humanoid or humanoid.Health <= 0 then
            cleanup()
            return false
        end

        local elapsed = os.clock() - startTime
        local alpha = math.clamp(elapsed / math.max(totalTime, 0.001), 0, 1)

        local curTarget = startPos:Lerp(targetPos + Vector3.new(0, 1.2, 0), alpha)
        local lookTarget = targetPos + Vector3.new(0, 1.2, 0)
        local lookDir = (lookTarget - curTarget)
        if lookDir.Magnitude > 0.1 then
            hrp.CFrame = CFrame.new(curTarget, curTarget + lookDir)
        else
            hrp.CFrame = CFrame.new(curTarget)
        end
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero

        local remaining = (targetPos - hrp.Position).Magnitude
        if onStep then onStep(remaining) end
        if remaining < 3.5 then break end

        Services.RunService.Heartbeat:Wait()
    end

    hrp.CFrame = CFrame.new(targetPos + Vector3.new(0, 1.2, 0))
    cleanup()
    return (targetPos - hrp.Position).Magnitude < 7
end

-- B. Voo Alto Seguro (Volta à base com ovo por cima das paredes e void)
local function movePlayerOverhead(targetPos, speed, onStep)
    local hrp = getHRP()
    local char = LocalPlayer.Character
    if not hrp or not char or isMoving then return false end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return false end

    isMoving = true
    disableCharacterAntiCheats(char)
    speed = speed or Config.MoveSpeed or 350
    local startPos = hrp.Position
    local cruiseAltitude = 92.0

    local noclipConn = Services.RunService.Stepped:Connect(function()
        if char and char.Parent then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = false
                    part.CanTouch = false
                end
            end
        end
    end)

    pcall(function()
        humanoid.PlatformStand = true
        humanoid:ChangeState(Enum.HumanoidStateType.Physics)
    end)

    local function cleanup()
        pcall(function() if noclipConn then noclipConn:Disconnect() end end)
        if char and char.Parent then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = true
                    part.CanTouch = true
                    part.AssemblyLinearVelocity = Vector3.zero
                    part.AssemblyAngularVelocity = Vector3.zero
                end
            end
            if humanoid and humanoid.Health > 0 then
                humanoid.PlatformStand = false
                humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
            end
        end
        isMoving = false
    end

    -- Ponto 1: Subida vertical para altitude de cruzeiro
    local wayUp = Vector3.new(startPos.X, math.max(startPos.Y, cruiseAltitude), startPos.Z)
    -- Ponto 2: Cruzeiro horizontal até acima da base
    local wayCruised = Vector3.new(targetPos.X, math.max(startPos.Y, cruiseAltitude), targetPos.Z)
    -- Ponto 3: Pouso suave no alvo
    local wayDown = targetPos + Vector3.new(0, 1.2, 0)

    local function lerpBetween(pA, pB, segmentSpeed)
        local sDist = (pB - pA).Magnitude
        if sDist < 1.0 then return end
        local sTime = sDist / math.max(segmentSpeed, 100)
        local sStart = os.clock()
        while (os.clock() - sStart) < (sTime + 0.1) do
            if State.IsUnloaded or not char or not char.Parent or not humanoid or humanoid.Health <= 0 then return end
            local alpha = math.clamp((os.clock() - sStart) / math.max(sTime, 0.001), 0, 1)
            local cur = pA:Lerp(pB, alpha)
            hrp.CFrame = CFrame.new(cur)
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
            if onStep then onStep((targetPos - hrp.Position).Magnitude) end
            Services.RunService.Heartbeat:Wait()
        end
        hrp.CFrame = CFrame.new(pB)
    end

    -- Executar as 3 etapas do voo seguro com checagem de interrupção
    if State.IsUnloaded then cleanup() return false end
    lerpBetween(startPos, wayUp, speed * 0.9)
    if State.IsUnloaded then cleanup() return false end
    lerpBetween(wayCruised, wayDown, speed * 0.8)

    cleanup()
    return (targetPos - hrp.Position).Magnitude < 7
end

-- Acionamento Rápido de ProximityPrompt
local function triggerPrompt(prompt)
    if not prompt or not prompt.Parent then return false end
    pcall(function()
        prompt.HoldDuration = 0
        prompt.RequiresLineOfSight = false
        prompt.MaxActivationDistance = 9999
        prompt.Enabled = true
    end)
    pcall(function()
        if fireproximityprompt then
            fireproximityprompt(prompt, 0)
            fireproximityprompt(prompt)
        end
    end)
    pcall(function()
        prompt:InputHoldBegin()
        task.wait(0.06)
        prompt:InputHoldEnd()
    end)
    return true
end

--================================================================--
-- 9.5. MOTOR MASTER DE AUTO-ROUBO (RAGDOLL TP & VOO DIRETO)
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

local function getMyDepositCFrame()
    local myPlot = findMyPlot()
    if myPlot then
        for _, d in ipairs(myPlot:GetDescendants()) do
            if d:IsA("BasePart") then
                local low = d.Name:lower()
                if low:find("deposit") or low:find("drop") or low:find("nest") or low:find("egg") or low:find("conveyor") then
                    return d.CFrame + Vector3.new(0, 2.5, 0)
                end
            end
        end
        return myPlot:GetPivot() + Vector3.new(0, 2.5, 0)
    end
    return State.BaseCFrame or (getHRP() and getHRP().CFrame)
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

-- D. Execução de Roubo via Ragdoll TP (Bypass de Anti-Cheat)
local function executeRagdollSteal(target)
    if not target or not target.Position then return false end
    local myHrp = getHRP()
    if not myHrp or State.IsUnloaded then return false end

    local baseCF = getMyDepositCFrame() or State.BaseCFrame or myHrp.CFrame
    local targetPos = target.Position

    addLog("ROUBO", string.format("Iniciando Ragdoll TP para %s [%s]...", target.Name, target.Rarity))

    -- 1. Teleporte ao Ninho da Galinha para provocar agro
    local guardObj, guardPos = findForestGuard()
    myHrp.CFrame = CFrame.new(guardPos + Vector3.new(0, 1.2, 0))
    task.wait(0.1)

    -- 2. Aguardar ativação de Ragdoll pelo golpe
    local ragdollActive = false
    local t0 = tick()
    while (tick() - t0) < 1.4 do
        if State.IsUnloaded then return false end
        if isPlayerInRagdoll() then
            ragdollActive = true
            break
        end
        if guardObj then
            local gP = getPositionOf(guardObj)
            if gP then
                myHrp.CFrame = CFrame.new(gP + Vector3.new(math.random(-1, 1) * 0.3, 0.4, math.random(-1, 1) * 0.3))
            end
        end
        task.wait(0.07)
    end

    -- 3. Teleporte instantâneo para o Ovo Alvo
    myHrp.CFrame = CFrame.new(targetPos + Vector3.new(0, 1.8, 0))
    
    -- Âncora micro-física para garantir acionamento estável (Mecânica Ouroboros)
    local oldAnchored = myHrp.Anchored
    myHrp.Anchored = true
    task.wait(0.04)

    -- 4. Disparo do Prompt
    local pInstance = target.Prompt or (target.Instance and target.Instance:FindFirstChildWhichIsA("ProximityPrompt", true))
    if pInstance then
        triggerPrompt(pInstance)
    end
    task.wait(0.06)
    myHrp.Anchored = oldAnchored

    -- 5. Teleporte instantâneo de volta à Esteira da Base
    myHrp.CFrame = baseCF
    addLog("ROUBO", "Retornou à base! Entregando ovo na esteira...")

    -- 6. Espera de depósito
    task.wait(Config.AutoDepositWait or 1.0)
    return true
end

-- E. Execução de Roubo via Voo Direto / Solo
local function executeDirectSteal(target)
    if not target or not target.Position then return false end
    local myHrp = getHRP()
    if not myHrp or State.IsUnloaded then return false end

    local baseCF = getMyDepositCFrame() or State.BaseCFrame or myHrp.CFrame
    local targetPos = target.Position

    addLog("ROUBO", string.format("Voo direto em andamento para %s [%s]...", target.Name, target.Rarity))

    local arrived = movePlayerDirect(targetPos, Config.MoveSpeed)
    if arrived then
        local oldAnchored = myHrp.Anchored
        myHrp.Anchored = true
        local pInst = target.Prompt or (target.Instance and target.Instance:FindFirstChildWhichIsA("ProximityPrompt", true))
        if pInst then triggerPrompt(pInst) end
        task.wait(0.08)
        myHrp.Anchored = oldAnchored

        movePlayerOverhead(baseCF.Position, Config.MoveSpeed)
        task.wait(Config.AutoDepositWait or 1.0)
    end
end

-- F. Ciclo Completo de Auto-Roubo
local function runStealCycle()
    local myHrp = getHRP()
    if not myHrp or State.IsUnloaded then return end

    -- 1. Se ainda não tem base fixada, detectar automaticamente
    if not State.BaseCFrame then
        local depCF = getMyDepositCFrame()
        if depCF then
            State.BaseCFrame = depCF
            if BaseLabel then
                local myPlot = findMyPlot()
                BaseLabel.Text = string.format("Base: (%s) em (%.0f, %.0f, %.0f)", myPlot and myPlot.Name or "Detectada", depCF.Position.X, depCF.Position.Y, depCF.Position.Z)
                BaseLabel.TextColor3 = C_GREEN
            end
        end
    end

    -- 2. Verificar se o jogador já está carregando um ovo
    local holding, heldName = isHoldingEgg()
    if holding then
        if StatusBadge then
            StatusBadge.Text = "ENTREGANDO"
            StatusBadge.TextColor3 = C_CYAN
        end
        if TargetInfoLabel then
            TargetInfoLabel.Text = "Ovo em mãos! Entregando na base..."
        end
        local depCF = getMyDepositCFrame() or State.BaseCFrame
        if depCF then
            if Config.StealMethod == "RagdollTP" then
                myHrp.CFrame = depCF
            else
                movePlayerOverhead(depCF.Position, Config.MoveSpeed)
            end
        end
        task.wait(Config.AutoDepositWait or 1.0)
        return
    end

    -- 3. Escanear todos os ovos do mapa
    local eggs = scanAllEggs()
    local valid = {}
    for _, e in ipairs(eggs) do
        if not (Config.ShowOnlyUnowned and e.IsMyPlot) then
            if e.Distance <= Config.MaxStealDistance then
                if isEggInMyIsland(e.Position) then
                    table.insert(valid, e)
                end
            end
        end
    end

    if #valid == 0 then
        if TargetInfoLabel then
            TargetInfoLabel.Text = "Nenhum ovo elegível encontrado na ilha atual."
        end
        if StatusBadge then
            StatusBadge.Text = "AGUARDANDO"
            StatusBadge.TextColor3 = C_MUTED
        end
        task.wait(0.8)
        return
    end

    -- 4. O primeiro ovo já é o de maior pontuação/raridade
    local target = valid[1]
    if TargetInfoLabel then
        TargetInfoLabel.Text = string.format("[%s] %s (%dm)", target.Rarity, target.Name, math.floor(target.Distance))
    end
    if StatusBadge then
        StatusBadge.Text = "ROUBANDO"
        StatusBadge.TextColor3 = C_GREEN
    end

    if Config.StealMethod == "RagdollTP" then
        executeRagdollSteal(target)
    else
        executeDirectSteal(target)
    end
end


-- 10. EXPORTADOR DE TELEMETRIA E DADOS INTERNOS (INSPETOR v7.0 COMPLETO)
local function dumpGameData()
    local lines = {}
    local function logL(s) table.insert(lines, s or "") end

    logL("================================================================================")
    logL("ROUBE UM OVO - INVENTARIO ESTRUTURAL COMPLETO (EXAUSTIVO v7.0)")
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
                        logL(string.format("  - Guarda: %-20s | Dados: %s", tostring(gKey), Services.HttpService:JSONEncode(gVal)))
                    end
                end
            end
        end
    end)
    logL("\n")

    -- 3. Guardas Físicos no Workspace (Localização Exata da Primeira Galinha no Mapa para Ragdoll TP)
    logL("[3] WORKSPACE._GUARDS & SPAWNS DE GUARDAS NO MAPA (Para Ragdoll TP):")
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
                        logL(string.format("  - Área: %-15s | Dados: %s", tostring(aKey), Services.HttpService:JSONEncode(aVal)))
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
        local char = LocalPlayer.Character
        if char then
            logL("  Atributos do Character:")
            for k, v in pairs(char:GetAttributes()) do
                logL(string.format("    > %s = %s", tostring(k), tostring(v)))
            end
            logL("  Scripts no Character:")
            for _, c in ipairs(char:GetChildren()) do
                if c:IsA("LocalScript") or c:IsA("Script") then
                    logL(string.format("    > %s [%s] Enabled=%s", c.Name, c.ClassName, tostring(c.Enabled)))
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
        local isGeneric = e.Name:find("Ovo Selvagem") or e.Name:find("Ovo da Floresta") or e.Name:find("Ovo da Deserto") or e.Name:find("Ovo da Selva")
        if isGeneric then genericCount = genericCount + 1 else namedCount = namedCount + 1 end
        logL(string.format("#%02d [%s] %-28s | Zona: %-22s | Prompt: %s | Dist: %-4dm | Pos: (%.1f, %.1f, %.1f)",
            i, e.Rarity, e.Name, e.Zone, e.Prompt and "SIM" or "NAO", math.floor(e.Distance),
            e.Position.X, e.Position.Y, e.Position.Z
        ))
    end
    logL(string.format("\n  Estatísticas do Radar: %d com Nome Real Próprio | %d Genéricos (Fallback)", namedCount, genericCount))

    logL("\n================================================================================")
    logL("FIM DO INVENTARIO.")

    local fullText = table.concat(lines, "\n")
    pcall(function()
        if writefile then writefile("ROUBE_UM_OVO_DUMP.txt", fullText) end
        if setclipboard then setclipboard(fullText) end
    end)
    addLog("INSPETOR", "Dump estrutural v7.0 exportado! (" .. tostring(#discovered) .. " ovos) - Copiado para o Clipboard!")
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
                    tag.Text = string.format("[%s]\n%s (%dm)", egg.Rarity, egg.Name, math.floor(dist))
                    tag.Parent = bb

                    activeESPs[adornee] = bb
                end
            end
        end
    end
end



--================================================================--
-- 12. INTERFACE MASTER HUB v10.0 (5 ABAS COMPLETAS & ULTRA CLEAN)
--================================================================--

ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "RoubeUmOvoMasterHub"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

pcall(function()
    if gethui then ScreenGui.Parent = gethui()
    elseif Services.CoreGui then ScreenGui.Parent = Services.CoreGui
    else ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end
end)

-- Paleta de Cores Slate Dark Moderna
local C_BG = Color3.fromRGB(15, 23, 42)
local C_TOPBAR = Color3.fromRGB(30, 41, 59)
local C_CARD = Color3.fromRGB(24, 33, 53)
local C_BORDER = Color3.fromRGB(51, 65, 85)
local C_CYAN = Color3.fromRGB(56, 189, 248)
local C_TEXT = Color3.fromRGB(248, 250, 252)
local C_MUTED = Color3.fromRGB(148, 163, 184)
local C_GREEN = Color3.fromRGB(34, 197, 94)
local C_PURPLE = Color3.fromRGB(168, 85, 247)
local C_RED = Color3.fromRGB(239, 68, 68)
local C_YELLOW = Color3.fromRGB(234, 179, 8)

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

-- Janela Principal Expandida (520x400)
MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 520, 0, 400)
MainFrame.Position = UDim2.new(0.5, -260, 0.5, -200)
MainFrame.BackgroundColor3 = C_BG
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui
addCorner(MainFrame, 10)
addStroke(MainFrame, C_BORDER, 1.2)

-- Topbar
local Topbar = Instance.new("Frame")
Topbar.Size = UDim2.new(1, 0, 0, 40)
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
Title.Size = UDim2.new(0, 190, 1, 0)
Title.Position = UDim2.new(0, 14, 0, 0)
Title.BackgroundTransparency = 1
Title.Font = Enum.Font.GothamBold
Title.TextSize = 12
Title.TextColor3 = C_CYAN
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Text = "ROUBE UM OVO  v10.0"
Title.Parent = Topbar

StatusBadge = Instance.new("TextLabel")
StatusBadge.Size = UDim2.new(0, 95, 0, 20)
StatusBadge.Position = UDim2.new(0, 195, 0.5, -10)
StatusBadge.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
StatusBadge.Text = "PARADO"
StatusBadge.Font = Enum.Font.GothamBold
StatusBadge.TextSize = 9
StatusBadge.TextColor3 = C_MUTED
StatusBadge.Parent = Topbar
addCorner(StatusBadge, 10)
addStroke(StatusBadge, C_BORDER, 1)

local UnloadBtn = Instance.new("TextButton")
UnloadBtn.Size = UDim2.new(0, 64, 0, 22)
UnloadBtn.Position = UDim2.new(1, -98, 0.5, -11)
UnloadBtn.BackgroundColor3 = Color3.fromRGB(153, 27, 27)
UnloadBtn.Text = "UNLOAD"
UnloadBtn.Font = Enum.Font.GothamBold
UnloadBtn.TextSize = 9
UnloadBtn.TextColor3 = C_TEXT
UnloadBtn.Parent = Topbar
addCorner(UnloadBtn, 5)

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 22, 0, 22)
CloseBtn.Position = UDim2.new(1, -28, 0.5, -11)
CloseBtn.BackgroundColor3 = Color3.fromRGB(51, 65, 85)
CloseBtn.Text = "X"
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 10
CloseBtn.TextColor3 = C_TEXT
CloseBtn.Parent = Topbar
addCorner(CloseBtn, 5)

CloseBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = false
end)

-- Barra de Abas Horizontal (5 Abas)
local TabBar = Instance.new("Frame")
TabBar.Size = UDim2.new(1, -24, 0, 30)
TabBar.Position = UDim2.new(0, 12, 0, 46)
TabBar.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
TabBar.BorderSizePixel = 0
TabBar.Parent = MainFrame
addCorner(TabBar, 6)

local TabButtons = {}
local TabPages = {}
local tabNames = {"Auto-Roubo", "Auto-Esteira", "Radar de Ovos", "Teleportes", "Configuracoes"}
local activeTab = "Auto-Roubo"

local ContentArea = Instance.new("Frame")
ContentArea.Size = UDim2.new(1, -24, 1, -88)
ContentArea.Position = UDim2.new(0, 12, 0, 82)
ContentArea.BackgroundTransparency = 1
ContentArea.BorderSizePixel = 0
ContentArea.Parent = MainFrame

local function switchTab(name)
    activeTab = name
    for tName, btn in pairs(TabButtons) do
        local isCur = (tName == name)
        btn.BackgroundColor3 = isCur and Color3.fromRGB(30, 41, 59) or Color3.fromRGB(15, 23, 42)
        btn.TextColor3 = isCur and C_CYAN or C_MUTED
    end
    for pName, page in pairs(TabPages) do
        page.Visible = (pName == name)
    end
end

for i, tName in ipairs(tabNames) do
    local displayName = (tName == "Configuracoes") and "Configuracoes" or tName
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1 / #tabNames, -4, 1, 0)
    btn.Position = UDim2.new((i - 1) * (1 / #tabNames), 2, 0, 0)
    btn.BackgroundColor3 = (tName == activeTab) and Color3.fromRGB(30, 41, 59) or Color3.fromRGB(15, 23, 42)
    btn.Text = displayName
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 9
    btn.TextColor3 = (tName == activeTab) and C_CYAN or C_MUTED
    btn.Parent = TabBar
    addCorner(btn, 5)

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

--================================================================--
-- ABA 1: AUTO-ROUBO
--================================================================--
local AutoStealPage = TabPages["Auto-Roubo"]

MainToggleBtn = Instance.new("TextButton")
MainToggleBtn.Size = UDim2.new(1, 0, 0, 42)
MainToggleBtn.BackgroundColor3 = Config.AutoStealEnabled and C_GREEN or Color3.fromRGB(30, 41, 59)
MainToggleBtn.Text = Config.AutoStealEnabled and "AUTO-ROUBO ATIVADO (EM EXECUCAO)" or "ATIVAR AUTO-ROUBO"
MainToggleBtn.Font = Enum.Font.GothamBold
MainToggleBtn.TextSize = 11
MainToggleBtn.TextColor3 = C_TEXT
MainToggleBtn.Parent = AutoStealPage
addCorner(MainToggleBtn, 8)
addStroke(MainToggleBtn, Config.AutoStealEnabled and C_GREEN or C_CYAN, 1)

local MethodBtn = Instance.new("TextButton")
MethodBtn.Size = UDim2.new(1, 0, 0, 32)
MethodBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
MethodBtn.Text = (Config.StealMethod == "RagdollTP") and "[METODO: SALTO POR IMPACTO (GALINHA BYPASS)]" or "[METODO: VOO DIRETO NO SOLO]"
MethodBtn.Font = Enum.Font.GothamBold
MethodBtn.TextSize = 9
MethodBtn.TextColor3 = (Config.StealMethod == "RagdollTP") and C_PURPLE or C_CYAN
MethodBtn.Parent = AutoStealPage
addCorner(MethodBtn, 6)
addStroke(MethodBtn, C_BORDER, 1)

MethodBtn.MouseButton1Click:Connect(function()
    if Config.StealMethod == "RagdollTP" then
        Config.StealMethod = "VooDireto"
        MethodBtn.Text = "[METODO: VOO DIRETO NO SOLO]"
        MethodBtn.TextColor3 = C_CYAN
    else
        Config.StealMethod = "RagdollTP"
        MethodBtn.Text = "[METODO: SALTO POR IMPACTO (GALINHA BYPASS)]"
        MethodBtn.TextColor3 = C_PURPLE
    end
end)

-- Card da Base
local BaseCard = createCleanCard(AutoStealPage, 50)
BaseLabel = Instance.new("TextLabel")
BaseLabel.Size = UDim2.new(0.68, -10, 1, 0)
BaseLabel.Position = UDim2.new(0, 12, 0, 0)
BaseLabel.BackgroundTransparency = 1
BaseLabel.Font = Enum.Font.Gotham
BaseLabel.TextSize = 10
BaseLabel.TextColor3 = C_MUTED
BaseLabel.TextXAlignment = Enum.TextXAlignment.Left
BaseLabel.Text = "Base: Identificando plot..."
BaseLabel.Parent = BaseCard

local SetBaseBtn = Instance.new("TextButton")
SetBaseBtn.Size = UDim2.new(0.32, -10, 0, 28)
SetBaseBtn.Position = UDim2.new(0.68, 0, 0.5, -14)
SetBaseBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
SetBaseBtn.Text = "FIXAR BASE"
SetBaseBtn.Font = Enum.Font.GothamBold
SetBaseBtn.TextSize = 9
SetBaseBtn.TextColor3 = C_CYAN
SetBaseBtn.Parent = BaseCard
addCorner(SetBaseBtn, 5)
addStroke(SetBaseBtn, C_BORDER, 1)

SetBaseBtn.MouseButton1Click:Connect(function()
    local hrp = getHRP()
    if hrp then
        State.BaseCFrame = hrp.CFrame
        BaseLabel.Text = string.format("Base: (%.0f, %.0f, %.0f) [Fixada]", hrp.Position.X, hrp.Position.Y, hrp.Position.Z)
        BaseLabel.TextColor3 = C_GREEN
        addLog("BASE", "Base fixada manualmente na posicao atual.")
    end
end)

-- Card Alvo Prioritário
local TargetCard = createCleanCard(AutoStealPage, 60)
local TargetTitle = Instance.new("TextLabel")
TargetTitle.Size = UDim2.new(1, -20, 0, 16)
TargetTitle.Position = UDim2.new(0, 12, 0, 8)
TargetTitle.BackgroundTransparency = 1
TargetTitle.Font = Enum.Font.GothamBold
TargetTitle.TextSize = 9
TargetTitle.TextColor3 = C_CYAN
TargetTitle.TextXAlignment = Enum.TextXAlignment.Left
TargetTitle.Text = "ALVO PRIORITARIO (MAIOR VALOR NO MAPA):"
TargetTitle.Parent = TargetCard

TargetInfoLabel = Instance.new("TextLabel")
TargetInfoLabel.Size = UDim2.new(1, -20, 0, 24)
TargetInfoLabel.Position = UDim2.new(0, 12, 0, 26)
TargetInfoLabel.BackgroundTransparency = 1
TargetInfoLabel.Font = Enum.Font.Gotham
TargetInfoLabel.TextSize = 10
TargetInfoLabel.TextColor3 = C_TEXT
TargetInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
TargetInfoLabel.Text = "Buscando ovos..."
TargetInfoLabel.Parent = TargetCard

MainToggleBtn.MouseButton1Click:Connect(function()
    Config.AutoStealEnabled = not Config.AutoStealEnabled
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
local AutoEsteiraPage = TabPages["Auto-Esteira"]

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

local EsteiraToggleBtn = Instance.new("TextButton")
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
local function findMyTreadmill()
    local myPlot = findMyPlot()
    if not myPlot then return nil, nil end
    local plotCenter = myPlot:GetPivot().Position

    -- 1. Buscar na pasta de renders de esteira proximo do plot (<= 55 studs)
    local ctr = Services.Workspace:FindFirstChild("__ClientTreadmillRenders")
    if ctr then
        local bestCandidate = nil
        local bestDist = 55
        for _, child in ipairs(ctr:GetChildren()) do
            local pos = child:IsA("Model") and child:GetPivot().Position or (child:IsA("BasePart") and child.Position)
            if pos then
                local d = (pos - plotCenter).Magnitude
                if d < bestDist then
                    bestDist = d
                    bestCandidate = child
                end
            end
        end
        if bestCandidate then
            local pos = bestCandidate:IsA("Model") and bestCandidate:GetPivot().Position or bestCandidate.Position
            return bestCandidate, pos + Vector3.new(0, 1.6, 0)
        end
    end

    -- 2. Buscar dentro do proprio plot
    for _, desc in ipairs(myPlot:GetDescendants()) do
        local low = desc.Name:lower()
        if low:find("treadmill") or low:find("esteira") or low:find("speed") or low:find("belt") then
            if desc:IsA("BasePart") then
                return desc, desc.Position + Vector3.new(0, 1.6, 0)
            elseif desc:IsA("Model") then
                return desc, desc:GetPivot().Position + Vector3.new(0, 1.6, 0)
            end
        end
    end

    return nil, plotCenter + Vector3.new(0, 2.0, 0)
end

GoToEsteiraBtn.MouseButton1Click:Connect(function()
    local hrp = getHRP()
    if not hrp then return end
    local _, tPos = findMyTreadmill()
    if tPos then
        hrp.CFrame = CFrame.new(tPos)
        addLog("ESTEIRA", "Teleportado para a sua esteira!")
    else
        addLog("ESTEIRA", "Esteira nao encontrada. Indo para a base.")
        local dep = getMyDepositCFrame()
        if dep then hrp.CFrame = dep end
    end
end)

-- Conexao de corrida continua no Heartbeat (resolve 100% o estado parado)
local esteiraHeartbeatConn = nil
local function setupEsteiraRunner()
    if esteiraHeartbeatConn then esteiraHeartbeatConn:Disconnect() end
    esteiraHeartbeatConn = Services.RunService.Heartbeat:Connect(function()
        if State.IsUnloaded or not Config.AutoEsteiraEnabled then return end
        
        local holding, _ = isHoldingEgg()
        if holding or State.IsExecutingSteal then
            State.IsOnTreadmill = false
            return
        end

        local hrp = getHRP()
        local hum = getHum()
        if not hrp or not hum or hum.Health <= 0 then return end

        local _, tPos = findMyTreadmill()
        if not tPos then return end

        local hDist = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(tPos.X, 0, tPos.Z)).Magnitude

        if hDist > 4.0 then
            -- Se afastou da esteira, move suavemente ou reposiciona
            hrp.CFrame = CFrame.new(tPos)
            task.wait(0.06)
        else
            -- Na esteira: Correr continuamente a cada frame sem parar!
            State.IsOnTreadmill = true
            StatusBadge.Text = "NA ESTEIRA"
            StatusBadge.TextColor3 = C_YELLOW
            hum:Move(Vector3.new(0, 0, -1), false)
        end
    end)
    table.insert(ScriptConnections, esteiraHeartbeatConn)
end

setupEsteiraRunner()

EsteiraToggleBtn.MouseButton1Click:Connect(function()
    Config.AutoEsteiraEnabled = not Config.AutoEsteiraEnabled
    EsteiraToggleBtn.BackgroundColor3 = Config.AutoEsteiraEnabled and C_GREEN or Color3.fromRGB(30, 41, 59)
    EsteiraToggleBtn.Text = Config.AutoEsteiraEnabled and "AUTO-ESTEIRA ATIVADA (TREINANDO)" or "ATIVAR AUTO-ESTEIRA (TREINO)"
    addStroke(EsteiraToggleBtn, Config.AutoEsteiraEnabled and C_GREEN or C_CYAN, 1)
    if not Config.AutoEsteiraEnabled then
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
local RadarPage = TabPages["Radar de Ovos"]

local RadarControlsCard = createCleanCard(RadarPage, 45)
local SearchInput = Instance.new("TextBox")
SearchInput.Size = UDim2.new(0.68, -10, 0, 28)
SearchInput.Position = UDim2.new(0, 10, 0.5, -14)
SearchInput.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
SearchInput.PlaceholderText = "Buscar ovo (Godzilla, Kitsune, T-Rex...)"
SearchInput.PlaceholderColor3 = C_MUTED
SearchInput.Text = ""
SearchInput.Font = Enum.Font.Gotham
SearchInput.TextSize = 10
SearchInput.TextColor3 = C_TEXT
SearchInput.Parent = RadarControlsCard
addCorner(SearchInput, 6)
addStroke(SearchInput, C_BORDER, 1)

local EspToggleBtn = Instance.new("TextButton")
EspToggleBtn.Size = UDim2.new(0.32, -10, 0, 28)
EspToggleBtn.Position = UDim2.new(0.68, 0, 0.5, -14)
EspToggleBtn.BackgroundColor3 = Config.ESPEnabled and C_GREEN or Color3.fromRGB(30, 41, 59)
EspToggleBtn.Text = Config.ESPEnabled and "[ESP: ON]" or "[ESP: OFF]"
EspToggleBtn.Font = Enum.Font.GothamBold
EspToggleBtn.TextSize = 9
EspToggleBtn.TextColor3 = Config.ESPEnabled and C_TEXT or C_CYAN
EspToggleBtn.Parent = RadarControlsCard
addCorner(EspToggleBtn, 6)
addStroke(EspToggleBtn, Config.ESPEnabled and C_GREEN or C_BORDER, 1)

local EggListFrame = Instance.new("Frame")
EggListFrame.Size = UDim2.new(1, 0, 0, 0)
EggListFrame.AutomaticSize = Enum.AutomaticSize.Y
EggListFrame.BackgroundTransparency = 1
EggListFrame.Parent = RadarPage

local eggListLayout = Instance.new("UIListLayout")
eggListLayout.Padding = UDim.new(0, 5)
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
            if count > 20 then break end

            local card = Instance.new("Frame")
            card.Size = UDim2.new(1, 0, 0, 44)
            card.BackgroundColor3 = C_CARD
            card.BorderSizePixel = 0
            card.Parent = EggListFrame
            addCorner(card, 6)
            addStroke(card, C_BORDER, 1)

            local rColor = C_CYAN
            if egg.Rarity == "TITAN" then rColor = Color3.fromRGB(239, 68, 68)
            elseif egg.Rarity == "DIVINE" then rColor = Color3.fromRGB(56, 189, 248)
            elseif egg.Rarity == "ETERNAL" then rColor = Color3.fromRGB(168, 85, 247)
            elseif egg.Rarity == "SECRET" then rColor = Color3.fromRGB(236, 72, 153)
            elseif egg.Rarity == "COSMIC" then rColor = Color3.fromRGB(99, 102, 241)
            elseif egg.Rarity:find("M") then rColor = Color3.fromRGB(249, 115, 22) end

            local RarityTag = Instance.new("TextLabel")
            RarityTag.Size = UDim2.new(0, 60, 0, 18)
            RarityTag.Position = UDim2.new(0, 8, 0.5, -9)
            RarityTag.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
            RarityTag.Text = egg.Rarity
            RarityTag.Font = Enum.Font.GothamBold
            RarityTag.TextSize = 8
            RarityTag.TextColor3 = rColor
            RarityTag.Parent = card
            addCorner(RarityTag, 4)
            addStroke(RarityTag, rColor, 1)

            local NameLabel = Instance.new("TextLabel")
            NameLabel.Size = UDim2.new(1, -125, 0, 16)
            NameLabel.Position = UDim2.new(0, 74, 0, 6)
            NameLabel.BackgroundTransparency = 1
            NameLabel.Font = Enum.Font.GothamBold
            NameLabel.TextSize = 9
            NameLabel.TextColor3 = C_TEXT
            NameLabel.TextXAlignment = Enum.TextXAlignment.Left
            NameLabel.Text = egg.Name
            NameLabel.Parent = card

            local InfoLabel = Instance.new("TextLabel")
            InfoLabel.Size = UDim2.new(1, -125, 0, 14)
            InfoLabel.Position = UDim2.new(0, 74, 0, 24)
            InfoLabel.BackgroundTransparency = 1
            InfoLabel.Font = Enum.Font.Gotham
            InfoLabel.TextSize = 8
            InfoLabel.TextColor3 = C_MUTED
            InfoLabel.TextXAlignment = Enum.TextXAlignment.Left
            InfoLabel.Text = string.format("Dist: %d studs | %s", math.floor(egg.Distance), egg.Zone or "Selvagem")
            InfoLabel.Parent = card

            local GoBtn = Instance.new("TextButton")
            GoBtn.Size = UDim2.new(0, 36, 0, 26)
            GoBtn.Position = UDim2.new(1, -44, 0.5, -13)
            GoBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
            GoBtn.Text = "IR"
            GoBtn.Font = Enum.Font.GothamBold
            GoBtn.TextSize = 9
            GoBtn.TextColor3 = C_CYAN
            GoBtn.Parent = card
            addCorner(GoBtn, 4)
            addStroke(GoBtn, C_BORDER, 1)

            local eggPos = egg.Position
            GoBtn.MouseButton1Click:Connect(function()
                local hrp = getHRP()
                if hrp and eggPos then
                    hrp.CFrame = CFrame.new(eggPos + Vector3.new(0, 2.0, 0))
                    addLog("TELEPORTE", "Teleportado para: " .. egg.Name)
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
    EspToggleBtn.BackgroundColor3 = Config.ESPEnabled and C_GREEN or Color3.fromRGB(30, 41, 59)
    EspToggleBtn.Text = Config.ESPEnabled and "[ESP: ON]" or "[ESP: OFF]"
    EspToggleBtn.TextColor3 = Config.ESPEnabled and C_TEXT or C_CYAN
    addStroke(EspToggleBtn, Config.ESPEnabled and C_GREEN or C_BORDER, 1)
    if not Config.ESPEnabled then clearAllESP() end
    addLog("ESP", Config.ESPEnabled and "ESP Ativado." or "ESP Desativado.")
end)

--================================================================--
-- ABA 4: TELEPORTES (BASE, ESTEIRA E TODAS AS 11 ILHAS)
--================================================================--
local TeleportsPage = TabPages["Teleportes"]

local QuickTpCard = createCleanCard(TeleportsPage, 45)
local TpBaseBtn = Instance.new("TextButton")
TpBaseBtn.Size = UDim2.new(0.5, -6, 0, 30)
TpBaseBtn.Position = UDim2.new(0, 4, 0.5, -15)
TpBaseBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
TpBaseBtn.Text = "MINHA BASE"
TpBaseBtn.Font = Enum.Font.GothamBold
TpBaseBtn.TextSize = 9
TpBaseBtn.TextColor3 = C_GREEN
TpBaseBtn.Parent = QuickTpCard
addCorner(TpBaseBtn, 5)
addStroke(TpBaseBtn, C_GREEN, 1)

TpBaseBtn.MouseButton1Click:Connect(function()
    local hrp = getHRP()
    if hrp then
        local dep = getMyDepositCFrame() or State.BaseCFrame
        if dep then hrp.CFrame = dep end
        addLog("TELEPORTE", "Teleportado para a base!")
    end
end)

local TpEsteiraBtn = Instance.new("TextButton")
TpEsteiraBtn.Size = UDim2.new(0.5, -6, 0, 30)
TpEsteiraBtn.Position = UDim2.new(0.5, 2, 0.5, -15)
TpEsteiraBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
TpEsteiraBtn.Text = "MINHA ESTEIRA"
TpEsteiraBtn.Font = Enum.Font.GothamBold
TpEsteiraBtn.TextSize = 9
TpEsteiraBtn.TextColor3 = C_YELLOW
TpEsteiraBtn.Parent = QuickTpCard
addCorner(TpEsteiraBtn, 5)
addStroke(TpEsteiraBtn, C_YELLOW, 1)

TpEsteiraBtn.MouseButton1Click:Connect(function()
    local hrp = getHRP()
    if hrp then
        local _, tPos = findMyTreadmill()
        if tPos then hrp.CFrame = CFrame.new(tPos) end
        addLog("TELEPORTE", "Teleportado para a esteira!")
    end
end)

local IslandsTitle = Instance.new("TextLabel")
IslandsTitle.Size = UDim2.new(1, 0, 0, 18)
IslandsTitle.BackgroundTransparency = 1
IslandsTitle.Font = Enum.Font.GothamBold
IslandsTitle.TextSize = 9
IslandsTitle.TextColor3 = C_CYAN
IslandsTitle.TextXAlignment = Enum.TextXAlignment.Left
IslandsTitle.Text = "ILHAS OFICIAIS DO JOGO (1 A 11):"
IslandsTitle.Parent = TeleportsPage

local IslandsGrid = Instance.new("Frame")
IslandsGrid.Size = UDim2.new(1, 0, 0, 0)
IslandsGrid.AutomaticSize = Enum.AutomaticSize.Y
IslandsGrid.BackgroundTransparency = 1
IslandsGrid.Parent = TeleportsPage

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.new(0.5, -4, 0, 32)
gridLayout.CellPadding = UDim2.new(0, 8, 0, 6)
gridLayout.Parent = IslandsGrid

for idx, isl in ipairs(OfficialIslands) do
    local islBtn = Instance.new("TextButton")
    islBtn.BackgroundColor3 = C_CARD
    islBtn.Text = string.format("%d. %s [%s]", idx, isl.Id, isl.TopDrop or isl.Rarity)
    islBtn.Font = Enum.Font.Gotham
    islBtn.TextSize = 8
    islBtn.TextColor3 = C_TEXT
    islBtn.Parent = IslandsGrid
    addCorner(islBtn, 5)
    addStroke(islBtn, C_BORDER, 1)

    local targetX = (isl.MinX + math.min(isl.MaxX, isl.MinX + 120)) / 2
    local targetZ = isl.BaseZ or -350
    islBtn.MouseButton1Click:Connect(function()
        local hrp = getHRP()
        if hrp then
            hrp.CFrame = CFrame.new(targetX, 68, targetZ)
            addLog("TELEPORTE", "Teleportado para: " .. isl.Name)
        end
    end)
end

--================================================================--
-- ABA 5: CONFIGURACOES & LOGS & UNLOAD
--================================================================--
local ConfigsPage = TabPages["Configuracoes"]

-- Card de Toggles de Proteção e Modificadores
local ModifiersCard = createCleanCard(ConfigsPage, 75)
local ModGrid = Instance.new("Frame")
ModGrid.Size = UDim2.new(1, -20, 1, -12)
ModGrid.Position = UDim2.new(0, 10, 0, 6)
ModGrid.BackgroundTransparency = 1
ModGrid.Parent = ModifiersCard

local modLayout = Instance.new("UIGridLayout")
modLayout.CellSize = UDim2.new(0.5, -4, 0, 26)
modLayout.CellPadding = UDim2.new(0, 8, 0, 6)
modLayout.Parent = ModGrid

local IslandLockBtn = Instance.new("TextButton")
IslandLockBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
IslandLockBtn.Text = Config.LockCurrentIsland and "TRAVAR ILHA: ON" or "TRAVAR ILHA: OFF"
IslandLockBtn.Font = Enum.Font.GothamBold
IslandLockBtn.TextSize = 8
IslandLockBtn.TextColor3 = Config.LockCurrentIsland and C_GREEN or C_MUTED
IslandLockBtn.Parent = ModGrid
addCorner(IslandLockBtn, 4)

IslandLockBtn.MouseButton1Click:Connect(function()
    Config.LockCurrentIsland = not Config.LockCurrentIsland
    IslandLockBtn.Text = Config.LockCurrentIsland and "TRAVAR ILHA: ON" or "TRAVAR ILHA: OFF"
    IslandLockBtn.TextColor3 = Config.LockCurrentIsland and C_GREEN or C_MUTED
end)

local NoclipBtn = Instance.new("TextButton")
NoclipBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
NoclipBtn.Text = Config.NoclipEnabled and "NOCLIP: ON" or "NOCLIP: OFF"
NoclipBtn.Font = Enum.Font.GothamBold
NoclipBtn.TextSize = 8
NoclipBtn.TextColor3 = Config.NoclipEnabled and C_GREEN or C_MUTED
NoclipBtn.Parent = ModGrid
addCorner(NoclipBtn, 4)

NoclipBtn.MouseButton1Click:Connect(function()
    Config.NoclipEnabled = not Config.NoclipEnabled
    NoclipBtn.Text = Config.NoclipEnabled and "NOCLIP: ON" or "NOCLIP: OFF"
    NoclipBtn.TextColor3 = Config.NoclipEnabled and C_GREEN or C_MUTED
end)

local InfJumpBtn = Instance.new("TextButton")
InfJumpBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
InfJumpBtn.Text = Config.InfJumpEnabled and "PULO INFINITO: ON" or "PULO INFINITO: OFF"
InfJumpBtn.Font = Enum.Font.GothamBold
InfJumpBtn.TextSize = 8
InfJumpBtn.TextColor3 = Config.InfJumpEnabled and C_GREEN or C_MUTED
InfJumpBtn.Parent = ModGrid
addCorner(InfJumpBtn, 4)

InfJumpBtn.MouseButton1Click:Connect(function()
    Config.InfJumpEnabled = not Config.InfJumpEnabled
    InfJumpBtn.Text = Config.InfJumpEnabled and "PULO INFINITO: ON" or "PULO INFINITO: OFF"
    InfJumpBtn.TextColor3 = Config.InfJumpEnabled and C_GREEN or C_MUTED
end)

local UnownedBtn = Instance.new("TextButton")
UnownedBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
UnownedBtn.Text = Config.ShowOnlyUnowned and "IGNORAR MEUS OVOS: ON" or "IGNORAR MEUS OVOS: OFF"
UnownedBtn.Font = Enum.Font.GothamBold
UnownedBtn.TextSize = 8
UnownedBtn.TextColor3 = Config.ShowOnlyUnowned and C_GREEN or C_MUTED
UnownedBtn.Parent = ModGrid
addCorner(UnownedBtn, 4)

UnownedBtn.MouseButton1Click:Connect(function()
    Config.ShowOnlyUnowned = not Config.ShowOnlyUnowned
    UnownedBtn.Text = Config.ShowOnlyUnowned and "IGNORAR MEUS OVOS: ON" or "IGNORAR MEUS OVOS: OFF"
    UnownedBtn.TextColor3 = Config.ShowOnlyUnowned and C_GREEN or C_MUTED
end)

-- Conexão de Noclip e Pulo Infinito
table.insert(ScriptConnections, Services.RunService.Stepped:Connect(function()
    if Config.NoclipEnabled then
        local char = LocalPlayer.Character
        if char then
            for _, p in ipairs(char:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = false end
            end
        end
    end
end))

table.insert(ScriptConnections, Services.UserInputService.JumpRequest:Connect(function()
    if Config.InfJumpEnabled then
        local hum = getHum()
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end))

-- Card de Sliders
local SlidersCard = createCleanCard(ConfigsPage, 80)
local SpeedLabel = Instance.new("TextLabel")
SpeedLabel.Size = UDim2.new(1, -20, 0, 16)
SpeedLabel.Position = UDim2.new(0, 10, 0, 8)
SpeedLabel.BackgroundTransparency = 1
SpeedLabel.Font = Enum.Font.Gotham
SpeedLabel.TextSize = 9
SpeedLabel.TextColor3 = C_TEXT
SpeedLabel.TextXAlignment = Enum.TextXAlignment.Left
SpeedLabel.Text = string.format("Velocidade de Deslocamento: %d studs/s", Config.MoveSpeed)
SpeedLabel.Parent = SlidersCard

local SpeedSliderBg = Instance.new("Frame")
SpeedSliderBg.Size = UDim2.new(1, -20, 0, 10)
SpeedSliderBg.Position = UDim2.new(0, 10, 0, 26)
SpeedSliderBg.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
SpeedSliderBg.Parent = SlidersCard
addCorner(SpeedSliderBg, 5)

local SpeedSliderFill = Instance.new("Frame")
SpeedSliderFill.Size = UDim2.new(Config.MoveSpeed / 600, 0, 1, 0)
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
        isDraggingSpeed = false
    end
end))

table.insert(ScriptConnections, Services.RunService.RenderStepped:Connect(function()
    if isDraggingSpeed then
        local mousePos = Services.UserInputService:GetMouseLocation().X
        local barPos = SpeedSliderBg.AbsolutePosition.X
        local barSize = SpeedSliderBg.AbsoluteSize.X
        local pct = math.clamp((mousePos - barPos) / barSize, 0.1, 1)
        SpeedSliderFill.Size = UDim2.new(pct, 0, 1, 0)
        local val = math.floor(pct * 600)
        Config.MoveSpeed = val
        SpeedLabel.Text = string.format("Velocidade de Deslocamento: %d studs/s", val)
    end
end))

local DistLabel = Instance.new("TextLabel")
DistLabel.Size = UDim2.new(1, -20, 0, 16)
DistLabel.Position = UDim2.new(0, 10, 0, 42)
DistLabel.BackgroundTransparency = 1
DistLabel.Font = Enum.Font.Gotham
DistLabel.TextSize = 9
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
LogTitle.Size = UDim2.new(1, -20, 0, 16)
LogTitle.Position = UDim2.new(0, 10, 0, 6)
LogTitle.BackgroundTransparency = 1
LogTitle.Font = Enum.Font.GothamBold
LogTitle.TextSize = 8
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
addCorner(LogScroll, 4)

local LogTextLabel = Instance.new("TextLabel")
LogTextLabel.Size = UDim2.new(1, -8, 0, 0)
LogTextLabel.AutomaticSize = Enum.AutomaticSize.Y
LogTextLabel.Position = UDim2.new(0, 4, 0, 4)
LogTextLabel.BackgroundTransparency = 1
LogTextLabel.Font = Enum.Font.Code
LogTextLabel.TextSize = 8
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
DumpBtn.Size = UDim2.new(1, 0, 0, 28)
DumpBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
DumpBtn.Text = "GERAR DUMP COMPLETO DO JOGO"
DumpBtn.Font = Enum.Font.GothamBold
DumpBtn.TextSize = 9
DumpBtn.TextColor3 = C_CYAN
DumpBtn.Parent = ConfigsPage
addCorner(DumpBtn, 5)
addStroke(DumpBtn, C_BORDER, 1)

DumpBtn.MouseButton1Click:Connect(function()
    addLog("DUMP", "Iniciando dump de dados do jogo...")
    task.spawn(function()
        local txt = dumpGameData()
        pcall(function()
            if setclipboard then setclipboard(txt) end
            if writefile then writefile("ROUBE_UM_OVO_DUMP.txt", txt) end
        end)
        addLog("DUMP", "Dump copiado para o clipboard e salvo!")
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
    Config.NoclipEnabled = false
    Config.InfJumpEnabled = false
    State.IsExecutingSteal = false
    State.IsOnTreadmill = false

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
            -- Restaurar colisões (Noclip OFF)
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
        if activeTab == "Radar de Ovos" then
            executeCleanRadarScan()
        end
    end
end)


-- Thread Contínua em Segundo Plano para o Auto-Roubo Master
task.spawn(function()
    while true do
        if State.IsUnloaded then break end
        if Config.AutoStealEnabled and not State.IsExecutingSteal and not State.IsOnTreadmill then
            State.IsExecutingSteal = true
            local ok, err = pcall(runStealCycle)
            if not ok and err then
                addLog("ERRO", "Falha no ciclo de roubo: " .. tostring(err))
            end
            State.IsExecutingSteal = false
        end
        task.wait(0.3)
    end
end)

-- Inicialização Limpa
task.delay(0.8, function()
    if State.IsUnloaded then return end
    executeCleanRadarScan()
    addLog("SISTEMA", "Roube um Ovo v10.0 carregado com sucesso!")
end)

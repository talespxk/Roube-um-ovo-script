--[[
    ROUBE UM OVO - HUB DE TELEMETRIA & AUTOMAÇÃO (v8.0 RAGDOLL TP & UNLOAD)
    -----------------------------------------------------------------------
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

LocalPlayer.CharacterAdded:Connect(function(newChar)
    task.wait(0.1)
    disableCharacterAntiCheats(newChar)
    newChar.ChildAdded:Connect(function(child)
        if child:IsA("LocalScript") then
            local low = child.Name:lower()
            if low:find("anticollision") or low:find("highseed") or low:find("highspeed")
                or low:find("pushback") or low:find("fixcollision") then
                task.wait()
                child.Disabled = true
                pcall(function() child:Destroy() end)
            end
        end
    end)
end)

-- 5. Configuração e Estado Geral
local Config = {
    StealMethod = "RagdollTP", -- "RagdollTP" (Galinha) ou "VooDireto" (Solo)
    AutoStealEnabled = false,
    SafeFlightEnabled = true,
    LockCurrentIsland = true,
    MaxStealDistance = 350,
    MoveSpeed = 350,
    TargetRarity = "Qualquer",
    MinRarityScore = 0,
    ESPEnabled = false,
    ShowOnlyUnowned = true,
    AutoDepositWait = 1.2,
    SearchQuery = ""
}

local ScriptConnections = {}

local State = {
    IsUnloaded = false,
    BaseCFrame = nil,
    IsExecutingSteal = false,
    CurrentTargetEgg = nil,
    LastPromptTriggered = nil,
    Logs = {}
}

local function addLog(category, msg)
    local timestamp = os.date("%H:%M:%S")
    local entry = string.format("[%s] [%s] %s", timestamp, category, msg)
    table.insert(State.Logs, 1, entry)
    if #State.Logs > 100 then table.remove(State.Logs) end
    if _G.UpdateLogConsole then _G.UpdateLogConsole() end
end

local function getHRP()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
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

-- 7.1. BANCO DE DADOS DAS 11 ILHAS OFICIAIS DO JOGO (REPLICATEDSTORAGE.DATA.AREAS)
local OfficialIslands = {
    {
        Id = "Forest",
        Name = "Floresta (Ilha 1)",
        MinX = 520, MaxX = 670,
        BaseZ = -328,
        Rarity = "COMUM",
        Score = 300,
        TopDrop = "Brr Brr Patapim",
        EggShell = "Ovo Comum da Floresta",
        Guard = "Forest Guard"
    },
    {
        Id = "Lake",
        Name = "Lago (Ilha 2)",
        MinX = 671, MaxX = 850,
        BaseZ = -410,
        Rarity = "INCOMUM",
        Score = 1500,
        TopDrop = "Crocodile",
        EggShell = "Ovo Incomum do Lago",
        Guard = "Lake Guard"
    },
    {
        Id = "Desert",
        Name = "Deserto (Ilha 3)",
        MinX = 851, MaxX = 1080,
        BaseZ = -325,
        Rarity = "RARO",
        Score = 3500,
        TopDrop = "Scorpio",
        EggShell = "Ovo Raro do Deserto",
        Guard = "Desert Guard"
    },
    {
        Id = "Jungle",
        Name = "Selva (Ilha 4)",
        MinX = 1081, MaxX = 1350,
        BaseZ = -410,
        Rarity = "ÉPICO",
        Score = 8000,
        TopDrop = "Bananita Dolphinita",
        EggShell = "Ovo Épico da Selva",
        Guard = "Jungle Guard"
    },
    {
        Id = "Snow",
        Name = "Neve (Ilha 5)",
        MinX = 1351, MaxX = 1680,
        BaseZ = -315,
        Rarity = "LENDÁRIO",
        Score = 15000,
        TopDrop = "Yeti",
        EggShell = "Ovo Lendário da Neve",
        Guard = "Snow Guard"
    },
    {
        Id = "Volcano",
        Name = "Vulcão (Ilha 6)",
        MinX = 1681, MaxX = 2080,
        BaseZ = -400,
        Rarity = "MÍTICO",
        Score = 20000,
        TopDrop = "Shadow Dragon",
        EggShell = "Ovo Mítico do Vulcão",
        Guard = "Volcano Guard"
    },
    {
        Id = "Abyss Ocean",
        Name = "Oceano do Abismo (Ilha 7)",
        MinX = 2081, MaxX = 2550,
        BaseZ = -328,
        Rarity = "COSMIC",
        Score = 30000,
        TopDrop = "El Maja",
        EggShell = "Ovo Cósmico do Abismo",
        Guard = "Abyss Ocean Guard"
    },
    {
        Id = "Prehistoric",
        Name = "Pré-Histórico (Ilha 8)",
        MinX = 2551, MaxX = 3100,
        BaseZ = -398,
        Rarity = "SECRET",
        Score = 45000,
        TopDrop = "Mosasaurus",
        EggShell = "Ovo Secreto Pré-Histórico",
        Guard = "Prehistoric Guard"
    },
    {
        Id = "Cosmic",
        Name = "Cósmico (Ilha 9)",
        MinX = 3101, MaxX = 3700,
        BaseZ = -325,
        Rarity = "ETERNAL",
        Score = 70000,
        TopDrop = "Unicorn",
        EggShell = "Ovo Eterno Cósmico",
        Guard = "Cosmic Guard"
    },
    {
        Id = "Cherry Blossom",
        Name = "Flor de Cerejeira (Ilha 10)",
        MinX = 3701, MaxX = 4400,
        BaseZ = -398,
        Rarity = "DIVINE",
        Score = 100000,
        TopDrop = "Kitsune",
        EggShell = "Ovo Divino de Cerejeira",
        Guard = "Cherry Blossom Guard"
    },
    {
        Id = "Titan Temple",
        Name = "Templo do Titã (Ilha 11)",
        MinX = 4401, MaxX = 99999,
        BaseZ = -328,
        Rarity = "TITAN",
        Score = 150000,
        TopDrop = "Godzilla",
        EggShell = "Ovo de Titã Ancestral",
        Guard = "Titan Temple Guard"
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

    -- Método E: Resolução com base nas 11 Ilhas Oficiais e Nomes Legítimos
    local isl = getIslandByPos(pos)
    local slotNum = instance and instance.Name:match("Slot_([%d]+)")
    local slotSuffix = slotNum and (" - Slot " .. slotNum) or ""

    if not foundName or isHexUUID(foundName) or foundName:find("pcube") or foundName:find("polysurface") or foundName:find("ovo selvagem") then
        foundName = string.format("%s (%s%s)", isl.EggShell, isl.Name, slotSuffix)
        if not detectedRarity or detectedRarity == "COMUM" then
            detectedRarity = isl.Rarity
            maxScore = math.max(maxScore, isl.Score)
        end
    end

    if not detectedRarity then
        detectedRarity = isl.Rarity or "COMUM"
        maxScore = math.max(maxScore, isl.Score or 300)
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
        if not char or not char.Parent or not humanoid or humanoid.Health <= 0 then
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
            if not char or not char.Parent or not humanoid or humanoid.Health <= 0 then return end
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

    -- Executar as 3 etapas do voo seguro
    lerpBetween(startPos, wayUp, speed * 0.9)
    lerpBetween(wayUp, wayCruised, speed)
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
-- SISTEMA DE DESCARREGAMENTO SEGURO (UNLOAD)
--================================================================--
local function unloadScript()
    if State.IsUnloaded then return end
    State.IsUnloaded = true
    Config.AutoStealEnabled = false
    Config.ESPEnabled = false
    clearAllESP()

    -- Parar qualquer deslocamento ativo
    pcall(function()
        local hrp = getHRP()
        if hrp then
            local bv = hrp:FindFirstChild("DirectMoverBV") or hrp:FindFirstChild("OverheadMoverBV")
            if bv then bv:Destroy() end
        end
    end)

    -- Desconectar todos os eventos registrados
    for _, conn in ipairs(ScriptConnections) do
        pcall(function()
            if conn and conn.Connected then
                conn:Disconnect()
            end
        end)
    end
    table.clear(ScriptConnections)

    -- Limpar referências globais
    _G.UpdateLogConsole = nil

    -- Destruir a ScreenGui
    pcall(function()
        if ScreenGui and ScreenGui.Parent then
            ScreenGui:Destroy()
        end
    end)

    addLog("SISTEMA", "Script descarregado completamente (Unload).")
end

-- 12. INTERFACE MODERNA FLUENT & MINIMALISTA (v9.0)
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "EggTelemetryHub"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

pcall(function()
    if gethui then ScreenGui.Parent = gethui()
    elseif Services.CoreGui then ScreenGui.Parent = Services.CoreGui
    else ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end
end)

-- Paleta de Cores Clean Dark / Modern Minimalist
local C_BG = Color3.fromRGB(15, 23, 42)         -- Fundo Slate Escuro #0F172A
local C_TOPBAR = Color3.fromRGB(30, 41, 59)     -- Topbar Slate Médio #1E293B
local C_CARD = Color3.fromRGB(24, 33, 53)       -- Cartão Escuro #182135
local C_BORDER = Color3.fromRGB(51, 65, 85)     -- Borda Sutil #334155
local C_CYAN = Color3.fromRGB(56, 189, 248)     -- Destaque Cyan #38BDF8
local C_TEXT = Color3.fromRGB(248, 250, 252)    -- Texto Principal #F8FAFC
local C_MUTED = Color3.fromRGB(148, 163, 184)   -- Texto Secundário #94A3B8
local C_GREEN = Color3.fromRGB(34, 197, 94)     -- Verde Sucesso #22C55E
local C_PURPLE = Color3.fromRGB(168, 85, 247)   -- Roxo Destaque #A855F7
local C_RED = Color3.fromRGB(239, 68, 68)       -- Vermelho Alerta #EF4444

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

-- Janela Principal Compacta (480x360)
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 480, 0, 360)
MainFrame.Position = UDim2.new(0.5, -240, 0.5, -180)
MainFrame.BackgroundColor3 = C_BG
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui
addCorner(MainFrame, 10)
addStroke(MainFrame, C_BORDER, 1)

-- Topbar Elegante
local Topbar = Instance.new("Frame")
Topbar.Size = UDim2.new(1, 0, 0, 38)
Topbar.BackgroundColor3 = C_TOPBAR
Topbar.BorderSizePixel = 0
Topbar.Parent = MainFrame
addCorner(Topbar, 10)

-- Ajuste para manter os cantos inferiores retos da Topbar
local TopbarSquare = Instance.new("Frame")
TopbarSquare.Size = UDim2.new(1, 0, 0, 10)
TopbarSquare.Position = UDim2.new(0, 0, 1, -10)
TopbarSquare.BackgroundColor3 = C_TOPBAR
TopbarSquare.BorderSizePixel = 0
TopbarSquare.Parent = Topbar

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(0, 180, 1, 0)
Title.Position = UDim2.new(0, 14, 0, 0)
Title.BackgroundTransparency = 1
Title.Font = Enum.Font.GothamBold
Title.TextSize = 12
Title.TextColor3 = C_CYAN
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Text = "ROUBE UM OVO  v9.0"
Title.Parent = Topbar

-- Badge de Status (IDLE / ROUBANDO)
local StatusBadge = Instance.new("TextLabel")
StatusBadge.Size = UDim2.new(0, 90, 0, 20)
StatusBadge.Position = UDim2.new(0, 185, 0.5, -10)
StatusBadge.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
StatusBadge.Text = "PARADO"
StatusBadge.Font = Enum.Font.GothamBold
StatusBadge.TextSize = 9
StatusBadge.TextColor3 = C_MUTED
StatusBadge.Parent = Topbar
addCorner(StatusBadge, 10)
addStroke(StatusBadge, C_BORDER, 1)

-- Botão UNLOAD Vermelho no Topo
local UnloadBtn = Instance.new("TextButton")
UnloadBtn.Size = UDim2.new(0, 62, 0, 22)
UnloadBtn.Position = UDim2.new(1, -96, 0.5, -11)
UnloadBtn.BackgroundColor3 = Color3.fromRGB(153, 27, 27)
UnloadBtn.Text = "UNLOAD"
UnloadBtn.Font = Enum.Font.GothamBold
UnloadBtn.TextSize = 9
UnloadBtn.TextColor3 = C_TEXT
UnloadBtn.Parent = Topbar
addCorner(UnloadBtn, 5)

UnloadBtn.MouseButton1Click:Connect(function()
    unloadScript()
end)

-- Botão Fechar / Minimizar (X)
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

-- Barra de Abas Horizontal Superior (3 Abas Limpas)
local TabBar = Instance.new("Frame")
TabBar.Size = UDim2.new(1, -24, 0, 30)
TabBar.Position = UDim2.new(0, 12, 0, 44)
TabBar.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
TabBar.BorderSizePixel = 0
TabBar.Parent = MainFrame
addCorner(TabBar, 6)

local TabButtons = {}
local TabPages = {}
local tabNames = {"Auto-Roubo", "Radar de Ovos", "Configurações"}
local activeTab = "Auto-Roubo"

-- Área de Conteúdo
local ContentArea = Instance.new("Frame")
ContentArea.Size = UDim2.new(1, -24, 1, -86)
ContentArea.Position = UDim2.new(0, 12, 0, 78)
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
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1 / #tabNames, -4, 1, 0)
    btn.Position = UDim2.new((i - 1) * (1 / #tabNames), 2, 0, 0)
    btn.BackgroundColor3 = (tName == activeTab) and Color3.fromRGB(30, 41, 59) or Color3.fromRGB(15, 23, 42)
    btn.Text = tName
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 10
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

-- Função Auxiliar para Criar Cartões Limpos
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

--================================================================--
-- 1. ABA: AUTO-ROUBO (MINIMALISTA E PODEROSA)
--================================================================--
local AutoStealPage = TabPages["Auto-Roubo"]

-- Botão Gigante de Ativação / Desativação
local MainToggleBtn = Instance.new("TextButton")
MainToggleBtn.Size = UDim2.new(1, 0, 0, 42)
MainToggleBtn.BackgroundColor3 = Config.AutoStealEnabled and C_GREEN or Color3.fromRGB(30, 41, 59)
MainToggleBtn.Text = Config.AutoStealEnabled and "AUTO-ROUBO ATIVADO (EM EXECUÇÃO)" or "ATIVAR AUTO-ROUBO"
MainToggleBtn.Font = Enum.Font.GothamBold
MainToggleBtn.TextSize = 11
MainToggleBtn.TextColor3 = C_TEXT
MainToggleBtn.Parent = AutoStealPage
addCorner(MainToggleBtn, 8)
addStroke(MainToggleBtn, Config.AutoStealEnabled and C_GREEN or C_CYAN, 1)

-- Alternador de Método: Ragdoll da Galinha vs Voo Direto
local MethodBtn = Instance.new("TextButton")
MethodBtn.Size = UDim2.new(1, 0, 0, 32)
MethodBtn.BackgroundColor3 = (Config.StealMethod == "RagdollTP") and C_PURPLE or Color3.fromRGB(30, 41, 59)
MethodBtn.Text = (Config.StealMethod == "RagdollTP") and "MÉTODO: SALTO POR IMPACTO (GALINHA BYPASS)" or "MÉTODO: VOO DIRETO NO SOLO (ORIGINAL)"
MethodBtn.Font = Enum.Font.GothamBold
MethodBtn.TextSize = 10
MethodBtn.TextColor3 = C_TEXT
MethodBtn.Parent = AutoStealPage
addCorner(MethodBtn, 8)
addStroke(MethodBtn, (Config.StealMethod == "RagdollTP") and C_PURPLE or C_BORDER, 1)

MethodBtn.MouseButton1Click:Connect(function()
    if Config.StealMethod == "RagdollTP" then
        Config.StealMethod = "VooDireto"
        MethodBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
        MethodBtn.Text = "MÉTODO: VOO DIRETO NO SOLO (ORIGINAL)"
        addStroke(MethodBtn, C_BORDER, 1)
    else
        Config.StealMethod = "RagdollTP"
        MethodBtn.BackgroundColor3 = C_PURPLE
        MethodBtn.Text = "MÉTODO: SALTO POR IMPACTO (GALINHA BYPASS)"
        addStroke(MethodBtn, C_PURPLE, 1)
    end
    addLog("CONFIG", "Método alterado: " .. Config.StealMethod)
end)

-- Card da Base Plot
local BaseCard = createCleanCard(AutoStealPage, 50)
local BaseLabel = Instance.new("TextLabel")
BaseLabel.Size = UDim2.new(1, -95, 1, 0)
BaseLabel.Position = UDim2.new(0, 12, 0, 0)
BaseLabel.BackgroundTransparency = 1
BaseLabel.Font = Enum.Font.Gotham
BaseLabel.TextSize = 10
BaseLabel.TextColor3 = C_MUTED
BaseLabel.TextXAlignment = Enum.TextXAlignment.Left
BaseLabel.Text = "Base: Automática (no spawn do seu plot)"
BaseLabel.Parent = BaseCard

local SetBaseBtn = Instance.new("TextButton")
SetBaseBtn.Size = UDim2.new(0, 80, 0, 28)
SetBaseBtn.Position = UDim2.new(1, -88, 0.5, -14)
SetBaseBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
SetBaseBtn.Text = "FIXAR BASE"
SetBaseBtn.Font = Enum.Font.GothamBold
SetBaseBtn.TextSize = 9
SetBaseBtn.TextColor3 = C_CYAN
SetBaseBtn.Parent = BaseCard
addCorner(SetBaseBtn, 6)
addStroke(SetBaseBtn, C_BORDER, 1)

SetBaseBtn.MouseButton1Click:Connect(function()
    local hrp = getHRP()
    if hrp then
        State.BaseCFrame = hrp.CFrame
        BaseLabel.Text = string.format("Base Fixada: (%.0f, %.0f, %.0f)", hrp.Position.X, hrp.Position.Y, hrp.Position.Z)
        BaseLabel.TextColor3 = C_GREEN
        addLog("BASE", "Base registrada com sucesso.")
    end
end)

-- Card de Alvo Prioritário
local TargetCard = createCleanCard(AutoStealPage, 54)
local TargetTitle = Instance.new("TextLabel")
TargetTitle.Size = UDim2.new(1, -20, 0, 16)
TargetTitle.Position = UDim2.new(0, 12, 0, 6)
TargetTitle.BackgroundTransparency = 1
TargetTitle.Font = Enum.Font.GothamBold
TargetTitle.TextSize = 9
TargetTitle.TextColor3 = C_MUTED
TargetTitle.TextXAlignment = Enum.TextXAlignment.Left
TargetTitle.Text = "ALVO PRIORITÁRIO ATUAL"
TargetTitle.Parent = TargetCard

local TargetInfoLabel = Instance.new("TextLabel")
TargetInfoLabel.Size = UDim2.new(1, -20, 0, 24)
TargetInfoLabel.Position = UDim2.new(0, 12, 0, 22)
TargetInfoLabel.BackgroundTransparency = 1
TargetInfoLabel.Font = Enum.Font.GothamBold
TargetInfoLabel.TextSize = 10
TargetInfoLabel.TextColor3 = C_TEXT
TargetInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
TargetInfoLabel.Text = "Nenhum alvo selecionado. Aguardando ativação..."
TargetInfoLabel.Parent = TargetCard

-- Ações do Botão Principal
MainToggleBtn.MouseButton1Click:Connect(function()
    Config.AutoStealEnabled = not Config.AutoStealEnabled
    MainToggleBtn.BackgroundColor3 = Config.AutoStealEnabled and C_GREEN or Color3.fromRGB(30, 41, 59)
    MainToggleBtn.Text = Config.AutoStealEnabled and "AUTO-ROUBO ATIVADO (EM EXECUÇÃO)" or "ATIVAR AUTO-ROUBO"
    addStroke(MainToggleBtn, Config.AutoStealEnabled and C_GREEN or C_CYAN, 1)
    StatusBadge.Text = Config.AutoStealEnabled and "ROUBANDO" or "PARADO"
    StatusBadge.TextColor3 = Config.AutoStealEnabled and C_GREEN or C_MUTED
    addLog("ROUBO", Config.AutoStealEnabled and "Auto-roubo iniciado." or "Auto-roubo desativado.")
end)

--================================================================--
-- 2. ABA: RADAR DE OVOS (COMPACTO E PRECISO)
--================================================================--
local RadarPage = TabPages["Radar de Ovos"]

-- Barra Superior do Radar (Busca + ESP + Refresh)
local RadarBar = Instance.new("Frame")
RadarBar.Size = UDim2.new(1, 0, 0, 32)
RadarBar.BackgroundTransparency = 1
RadarBar.Parent = RadarPage

local SearchBox = Instance.new("TextBox")
SearchBox.Size = UDim2.new(1, -150, 1, 0)
SearchBox.BackgroundColor3 = C_CARD
SearchBox.PlaceholderText = "Filtrar por nome ou ilha..."
SearchBox.PlaceholderColor3 = C_MUTED
SearchBox.Text = ""
SearchBox.Font = Enum.Font.Gotham
SearchBox.TextSize = 9
SearchBox.TextColor3 = C_TEXT
SearchBox.TextXAlignment = Enum.TextXAlignment.Left
SearchBox.Parent = RadarBar
addCorner(SearchBox, 6)
addStroke(SearchBox, C_BORDER, 1)

local BoxPadding = Instance.new("UIPadding")
BoxPadding.PaddingLeft = UDim.new(0, 10)
BoxPadding.Parent = SearchBox

local ESPToggleBtn = Instance.new("TextButton")
ESPToggleBtn.Size = UDim2.new(0, 68, 1, 0)
ESPToggleBtn.Position = UDim2.new(1, -142, 0, 0)
ESPToggleBtn.BackgroundColor3 = Config.ESPEnabled and C_GREEN or Color3.fromRGB(30, 41, 59)
ESPToggleBtn.Text = Config.ESPEnabled and "ESP: ON" or "ESP: OFF"
ESPToggleBtn.Font = Enum.Font.GothamBold
ESPToggleBtn.TextSize = 9
ESPToggleBtn.TextColor3 = C_TEXT
ESPToggleBtn.Parent = RadarBar
addCorner(ESPToggleBtn, 6)
addStroke(ESPToggleBtn, C_BORDER, 1)

local RadarRefreshBtn = Instance.new("TextButton")
RadarRefreshBtn.Size = UDim2.new(0, 68, 1, 0)
RadarRefreshBtn.Position = UDim2.new(1, -70, 0, 0)
RadarRefreshBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
RadarRefreshBtn.Text = "VARREDURA"
RadarRefreshBtn.Font = Enum.Font.GothamBold
RadarRefreshBtn.TextSize = 9
RadarRefreshBtn.TextColor3 = C_CYAN
RadarRefreshBtn.Parent = RadarBar
addCorner(RadarRefreshBtn, 6)
addStroke(RadarRefreshBtn, C_BORDER, 1)

-- Container da Lista de Ovos do Radar
local RadarListContainer = Instance.new("Frame")
RadarListContainer.Size = UDim2.new(1, 0, 0, 0)
RadarListContainer.AutomaticSize = Enum.AutomaticSize.Y
RadarListContainer.BackgroundTransparency = 1
RadarListContainer.Parent = RadarPage

local RadarListLayout = Instance.new("UIListLayout")
RadarListLayout.Padding = UDim.new(0, 4)
RadarListLayout.SortOrder = Enum.SortOrder.LayoutOrder
RadarListLayout.Parent = RadarListContainer

local currentDiscovered = {}

local function renderCleanRadar(eggsList)
    currentDiscovered = eggsList or {}
    for _, child in ipairs(RadarListContainer:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end

    local q = (SearchBox.Text or ""):lower()
    local shown = 0

    for i, egg in ipairs(currentDiscovered) do
        local matches = (q == "") or egg.Name:lower():find(q, 1, true) or egg.Rarity:lower():find(q, 1, true)
        if matches and shown < 30 then
            shown = shown + 1

            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, 0, 0, 36)
            row.BackgroundColor3 = C_CARD
            row.BorderSizePixel = 0
            row.Parent = RadarListContainer
            addCorner(row, 6)
            addStroke(row, C_BORDER, 1)

            -- Badge de Raridade Colorido
            local color = RarityColors[egg.Rarity:upper()] or C_CYAN
            local badge = Instance.new("TextLabel")
            badge.Size = UDim2.new(0, 68, 0, 20)
            badge.Position = UDim2.new(0, 8, 0.5, -10)
            badge.BackgroundColor3 = color
            badge.Text = egg.Rarity
            badge.Font = Enum.Font.GothamBold
            badge.TextSize = 8
            badge.TextColor3 = Color3.fromRGB(15, 23, 42)
            badge.Parent = row
            addCorner(badge, 4)

            -- Nome e Ilha do Ovo
            local nameLbl = Instance.new("TextLabel")
            nameLbl.Size = UDim2.new(1, -150, 1, 0)
            nameLbl.Position = UDim2.new(0, 82, 0, 0)
            nameLbl.BackgroundTransparency = 1
            nameLbl.Font = Enum.Font.GothamMedium
            nameLbl.TextSize = 9
            nameLbl.TextColor3 = C_TEXT
            nameLbl.TextXAlignment = Enum.TextXAlignment.Left
            nameLbl.Text = string.format("%s (%dm)", egg.Name, math.floor(egg.Distance))
            nameLbl.Parent = row

            -- Botão Ir
            local goBtn = Instance.new("TextButton")
            goBtn.Size = UDim2.new(0, 52, 0, 22)
            goBtn.Position = UDim2.new(1, -58, 0.5, -11)
            goBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
            goBtn.Text = "IR"
            goBtn.Font = Enum.Font.GothamBold
            goBtn.TextSize = 9
            goBtn.TextColor3 = C_CYAN
            goBtn.Parent = row
            addCorner(goBtn, 4)
            addStroke(goBtn, C_BORDER, 1)

            goBtn.MouseButton1Click:Connect(function()
                task.spawn(function()
                    addLog("MOVIMENTO", "Indo até: " .. egg.Name)
                    movePlayerDirect(egg.Position, Config.MoveSpeed)
                end)
            end)
        end
    end
end

local function executeCleanRadarScan()
    local eggs = scanAllEggs()
    renderCleanRadar(eggs)
    updateESP()
end

RadarRefreshBtn.MouseButton1Click:Connect(executeCleanRadarScan)
SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
    renderCleanRadar(currentDiscovered)
end)

ESPToggleBtn.MouseButton1Click:Connect(function()
    Config.ESPEnabled = not Config.ESPEnabled
    ESPToggleBtn.BackgroundColor3 = Config.ESPEnabled and C_GREEN or Color3.fromRGB(30, 41, 59)
    ESPToggleBtn.Text = Config.ESPEnabled and "ESP: ON" or "ESP: OFF"
    updateESP()
end)

--================================================================--
-- 3. ABA: CONFIGURAÇÕES & UNLOAD DEFINITIVO
--================================================================--
local ConfigsPage = TabPages["Configurações"]

-- Toggle Travar Ilha
local IslandLockCard = createCleanCard(ConfigsPage, 44)
local IslandLockLabel = Instance.new("TextLabel")
IslandLockLabel.Size = UDim2.new(1, -110, 1, 0)
IslandLockLabel.Position = UDim2.new(0, 12, 0, 0)
IslandLockLabel.BackgroundTransparency = 1
IslandLockLabel.Font = Enum.Font.Gotham
IslandLockLabel.TextSize = 10
IslandLockLabel.TextColor3 = C_TEXT
IslandLockLabel.TextXAlignment = Enum.TextXAlignment.Left
IslandLockLabel.Text = "Travar na Ilha Atual (Segurança)"
IslandLockLabel.Parent = IslandLockCard

local IslandLockToggleBtn = Instance.new("TextButton")
IslandLockToggleBtn.Size = UDim2.new(0, 90, 0, 26)
IslandLockToggleBtn.Position = UDim2.new(1, -98, 0.5, -13)
IslandLockToggleBtn.BackgroundColor3 = Config.LockCurrentIsland and C_GREEN or Color3.fromRGB(30, 41, 59)
IslandLockToggleBtn.Text = Config.LockCurrentIsland and "LIGADO" or "DESLIGADO"
IslandLockToggleBtn.Font = Enum.Font.GothamBold
IslandLockToggleBtn.TextSize = 9
IslandLockToggleBtn.TextColor3 = C_TEXT
IslandLockToggleBtn.Parent = IslandLockCard
addCorner(IslandLockToggleBtn, 5)

IslandLockToggleBtn.MouseButton1Click:Connect(function()
    Config.LockCurrentIsland = not Config.LockCurrentIsland
    IslandLockToggleBtn.BackgroundColor3 = Config.LockCurrentIsland and C_GREEN or Color3.fromRGB(30, 41, 59)
    IslandLockToggleBtn.Text = Config.LockCurrentIsland and "LIGADO" or "DESLIGADO"
end)

-- Slider Velocidade de Deslocamento
local SpeedCard = createCleanCard(ConfigsPage, 48)
local SpeedLabel = Instance.new("TextLabel")
SpeedLabel.Size = UDim2.new(1, -20, 0, 16)
SpeedLabel.Position = UDim2.new(0, 10, 0, 6)
SpeedLabel.BackgroundTransparency = 1
SpeedLabel.Font = Enum.Font.Gotham
SpeedLabel.TextSize = 9
SpeedLabel.TextColor3 = C_TEXT
SpeedLabel.TextXAlignment = Enum.TextXAlignment.Left
SpeedLabel.Text = string.format("Velocidade: %d studs/s", Config.MoveSpeed)
SpeedLabel.Parent = SpeedCard

local SpeedBg = Instance.new("Frame")
SpeedBg.Size = UDim2.new(1, -20, 0, 10)
SpeedBg.Position = UDim2.new(0, 10, 0, 28)
SpeedBg.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
SpeedBg.Parent = SpeedCard
addCorner(SpeedBg, 5)

local SpeedFill = Instance.new("Frame")
SpeedFill.Size = UDim2.new(Config.MoveSpeed / 600, 0, 1, 0)
SpeedFill.BackgroundColor3 = C_CYAN
SpeedFill.BorderSizePixel = 0
SpeedFill.Parent = SpeedBg
addCorner(SpeedFill, 5)

local SpeedBtn = Instance.new("TextButton")
SpeedBtn.Size = UDim2.new(1, 0, 1, 0)
SpeedBtn.BackgroundTransparency = 1
SpeedBtn.Text = ""
SpeedBtn.Parent = SpeedBg

local isDraggingSpd = false
SpeedBtn.MouseButton1Down:Connect(function() isDraggingSpd = true end)
table.insert(ScriptConnections, Services.UserInputService.InputEnded:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
        isDraggingSpd = false
    end
end))
table.insert(ScriptConnections, Services.RunService.RenderStepped:Connect(function()
    if isDraggingSpd then
        local mX = Services.UserInputService:GetMouseLocation().X
        local bX = SpeedBg.AbsolutePosition.X
        local bW = SpeedBg.AbsoluteSize.X
        local pct = math.clamp((mX - bX) / bW, 0.1, 1)
        SpeedFill.Size = UDim2.new(pct, 0, 1, 0)
        local val = math.floor(pct * 600)
        Config.MoveSpeed = val
        SpeedLabel.Text = string.format("Velocidade: %d studs/s", val)
    end
end))

-- Card de Descarregamento Definitivo (UNLOAD)
local UnloadFullCard = createCleanCard(ConfigsPage, 50)
local UnloadBtnFull = Instance.new("TextButton")
UnloadBtnFull.Size = UDim2.new(1, -20, 0, 32)
UnloadBtnFull.Position = UDim2.new(0, 10, 0.5, -16)
UnloadBtnFull.BackgroundColor3 = Color3.fromRGB(185, 28, 28)
UnloadBtnFull.Text = "DESCARREGAR SCRIPT COMPLETAMENTE (UNLOAD)"
UnloadBtnFull.Font = Enum.Font.GothamBold
UnloadBtnFull.TextSize = 10
UnloadBtnFull.TextColor3 = C_TEXT
UnloadBtnFull.Parent = UnloadFullCard
addCorner(UnloadBtnFull, 6)
addStroke(UnloadBtnFull, C_RED, 1)

UnloadBtnFull.MouseButton1Click:Connect(function()
    unloadScript()
end)

-- Atualização de Status em Tempo Real no Loop
local function updateTargetCardText(target)
    if target then
        TargetInfoLabel.Text = string.format("[%s] %s (%dm)", target.Rarity, target.Name, math.floor(target.Distance))
    else
        TargetInfoLabel.Text = "Nenhum ovo elegível encontrado."
    end
end

-- Substituir hook de status do ciclo
local old_runStealCycle = runStealCycle
runStealCycle = function()
    local myHrp = getHRP()
    if not myHrp or State.IsUnloaded then return end

    if not State.BaseCFrame then
        State.BaseCFrame = myHrp.CFrame
        BaseLabel.Text = string.format("Base: (%.0f, %.0f, %.0f)", myHrp.Position.X, myHrp.Position.Y, myHrp.Position.Z)
        BaseLabel.TextColor3 = C_GREEN
    end

    local holding, heldName = isHoldingEgg()
    if holding then
        StatusBadge.Text = "ENTREGANDO"
        StatusBadge.TextColor3 = C_CYAN
        TargetInfoLabel.Text = "Ovo em mãos! Entregando na base..."
        movePlayerOverhead(State.BaseCFrame.Position + Vector3.new(0, 2.5, 0), Config.MoveSpeed)
        task.wait(Config.AutoDepositWait)
        return
    end

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
        updateTargetCardText(nil)
        task.wait(1.2)
        return
    end

    local target = valid[1]
    updateTargetCardText(target)
    StatusBadge.Text = "ROUBANDO"
    StatusBadge.TextColor3 = C_GREEN

    if Config.StealMethod == "RagdollTP" then
        executeRagdollSteal(target)
    else
        local arrived = movePlayerDirect(target.Position, Config.MoveSpeed)
        if arrived then
            local pInst = target.Prompt or (target.Instance and target.Instance:FindFirstChildWhichIsA("ProximityPrompt", true))
            if pInst then triggerPrompt(pInst) end
            task.wait(0.3)
            movePlayerOverhead(State.BaseCFrame.Position + Vector3.new(0, 2.5, 0), Config.MoveSpeed)
            task.wait(Config.AutoDepositWait)
        end
    end
end

-- Atalho LeftControl e Botão Mobile Minimalista
table.insert(ScriptConnections, Services.UserInputService.InputBegan:Connect(function(input, gpe)
    if not gpe and input.KeyCode == Enum.KeyCode.LeftControl then
        MainFrame.Visible = not MainFrame.Visible
    end
end))

local MobileBtn = Instance.new("TextButton")
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

-- Inicialização Limpa
task.delay(0.8, function()
    if State.IsUnloaded then return end
    executeCleanRadarScan()
    addLog("SISTEMA", "Roube um Ovo v9.0 carregado!")
end)

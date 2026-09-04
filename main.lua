--[[
    ROUBE UM OVO - HUB DE TELEMETRIA & AUTOMAÇÃO (v6.0 DEFINITIVA)
    -----------------------------------------------------------------------
    - Neutralização Ativa Anti-Cheat: Desativa e remove automaticamente os scripts
      locais AntiCollisionHighSeedPushBack e FixCollisions do Character, zerando
      RagdollEndTime e eliminando todo efeito de pushback / teletransporte para trás (lag falso).
    - Trava de Ilha Atual (LockCurrentIsland): Impede o roubo de ovos em ilhas trancadas
      distantes, eliminando mortes contra as barreiras de fronteira do servidor.
    - Movimento Híbrido Perfeito:
        > IDA (até o ovo): Retão direto suave no solo (Y+2.5 studs) com noclip contínuo.
        > VOLTA (à base com o ovo): Voo aéreo seguro por cima das paredes (Y ≈ 92 studs),
          pousando suavemente no centro do plot do jogador.
    - Catálogo Completo de 118 Pets: Mapeamento embutido de todos os pets e raridades oficiais,
      resolução numérica de MeshId em ReplicatedStorage.AssetModels e inspeção espacial
      direta em Workspace.ClientRenderedAssets.
    - Detecção Real de Posse: Monitora atributos e modelos soldados ao avatar (ex: Chicken Egg)
      e aciona o retorno instantâneo à base.
    - Inspetor Aprofundado: Exporta dados de Assets, Rarity, Áreas, Guardas, Modelos e
      ClientRenderedAssets para ROUBE_UM_OVO_DUMP.txt.
    - Interface Tech Blue (#38BDF8), 100% em português, zero emojis, zero poluição global.
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

-- 4. NEUTRALIZAÇÃO ATIVA DE ANTI-CHEAT LOCAL DO CHARACTER
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
        LocalPlayer:SetAttribute("RagdollEndTime", 0)
        char:SetAttribute("RagdollEndTime", 0)
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
            hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
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

local State = {
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

local IslandZones = {
    { MaxX = 950,   Name = "Floresta (Ilha 1)" },
    { MaxX = 1650,  Name = "Deserto (Ilha 2)" },
    { MaxX = 2550,  Name = "Selva (Ilha 3)" },
    { MaxX = 3650,  Name = "Vulcão (Ilha 4)" },
    { MaxX = 99999, Name = "Abismo / Místico (Ilha 5)" }
}

local function getIslandNameByPos(pos)
    if not pos then return "Ilha Geral" end
    for _, zone in ipairs(IslandZones) do
        if pos.X <= zone.MaxX then
            return zone.Name
        end
    end
    return "Ilha Avançada"
end

local function isEggInMyIsland(eggPos)
    if not Config.LockCurrentIsland then return true end
    local myHrp = getHRP()
    if not myHrp then return true end
    local myIsland = getIslandNameByPos(myHrp.Position)
    local eggIsland = getIslandNameByPos(eggPos)
    return myIsland == eggIsland
end

local RarityScoreMap = {
    ["DIVINE"] = 120000,
    ["TITAN"] = 110000,
    ["ADMIN ABUSE"] = 100000,
    ["EXCLUSIVE"] = 90000,
    ["MONSTER PARASITE"] = 85000,
    ["DRAGON"] = 75000,
    ["SAKURA"] = 65000,
    ["BRAINROT"] = 60000,
    ["LIMITED"] = 50000,
    ["SECRET"] = 45000,
    ["ETERNAL"] = 35000,
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
    end

    -- Método E: Fallback de Slot e Ilha
    local island = getIslandNameByPos(pos)
    if not foundName or isHexUUID(foundName) or foundName:find("pcube") or foundName:find("polysurface") then
        local slotNum = instance and instance.Name:match("Slot_([%d]+)")
        if slotNum then
            foundName = "Ovo Selvagem (" .. island .. " - Slot " .. slotNum .. ")"
        else
            foundName = "Ovo Selvagem (" .. island .. ")"
        end
    end

    if not detectedRarity then
        detectedRarity = "COMUM"
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

-- 10. EXPORTADOR DE TELEMETRIA E DADOS INTERNOS (INSPETOR)
local function dumpGameData()
    local lines = {}
    local function logL(s) table.insert(lines, s or "") end

    logL("================================================================================")
    logL("ROUBE UM OVO - INVENTARIO ESTRUTURAL COMPLETO (EXAUSTIVO v6.0)")
    logL("Data: " .. os.date("%Y-%m-%d %H:%M:%S") .. " | PlaceId: " .. tostring(game.PlaceId))
    logL("================================================================================\n")

    -- 1. Catálogo Completo de 118 Pets
    logL("[1] CATALOGO DE PETS E RARIDADES REAIS (118 PETS VERIFICADOS):")
    for k, v in pairs(KnownPetsCatalog) do
        logL(string.format("  - Chave: %-25s | Display: %-22s | Raridade: %-12s", tostring(k), tostring(v.DisplayName), tostring(v.Rarity)))
    end
    logL("\n")

    -- 2. Modelos em ReplicatedStorage.AssetModels
    logL("[2] REPLICATEDSTORAGE.ASSETMODELS (Total: " .. tostring(#Services.ReplicatedStorage.AssetModels:GetChildren()) .. "):")
    pcall(function()
        local am = Services.ReplicatedStorage:FindFirstChild("AssetModels")
        if am then
            for _, m in ipairs(am:GetChildren()) do
                local mCount = 0
                for _, d in ipairs(m:GetDescendants()) do
                    if (d:IsA("MeshPart") and d.MeshId ~= "") or (d:IsA("SpecialMesh") and d.MeshId ~= "") then
                        mCount = mCount + 1
                    end
                end
                logL(string.format("  - Modelo: %-25s | Meshes: %d", m.Name, mCount))
            end
        end
    end)
    logL("\n")

    -- 3. Workspace.ClientRenderedAssets
    logL("[3] WORKSPACE.CLIENTRENDEREDASSETS (Modelos Renderizados no Cliente):")
    pcall(function()
        local cra = Services.Workspace:FindFirstChild("ClientRenderedAssets")
        if cra then
            for _, c in ipairs(cra:GetChildren()) do
                local pos = getPositionOf(c)
                local posStr = pos and string.format("(%.1f, %.1f, %.1f)", pos.X, pos.Y, pos.Z) or "N/D"
                logL(string.format("  - Rendered: %-32s | Filhos: %d | Pos: %s", c.Name, #c:GetChildren(), posStr))
            end
        end
    end)
    logL("\n")

    -- 4. ReplicatedStorage.Data.Areas.Directory
    logL("[4] REPLICATEDSTORAGE.DATA.AREAS.DIRECTORY (Áreas e Ilhas):")
    pcall(function()
        local dataF = Services.ReplicatedStorage:FindFirstChild("Data")
        if dataF then
            local aMod = dataF:FindFirstChild("Areas")
            if aMod and aMod:IsA("ModuleScript") then
                local res = require(aMod)
                if type(res) == "table" and res.Directory then
                    for aKey, aVal in pairs(res.Directory) do
                        logL(string.format("  - Área: %s | Dados: %s", tostring(aKey), Services.HttpService:JSONEncode(aVal)))
                    end
                end
            end
        end
    end)
    logL("\n")

    -- 5. Atributos do Jogador e Scripts Locais
    logL("[5] ESTADO DO JOGADOR LOCAL E CHARACTER:")
    pcall(function()
        logL("  DisplayName: " .. LocalPlayer.DisplayName .. " | Name: " .. LocalPlayer.Name)
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
        logL("  Atributos do LocalPlayer:")
        for k, v in pairs(LocalPlayer:GetAttributes()) do
            logL(string.format("    > %s = %s", tostring(k), tostring(v)))
        end
    end)
    logL("\n")

    -- 6. Ovos Detectados com Nomes Reais
    local discovered = scanAllEggs()
    logL("[6] LISTA DE OVOS DETECTADOS PELO RADAR (" .. tostring(#discovered) .. " ENCONTRADOS):")
    for i, e in ipairs(discovered) do
        logL(string.format("#%02d [%s] %s | Tem Prompt: %s | Zona: %s | Pos: (%.1f, %.1f, %.1f) | Dist: %dm",
            i, e.Rarity, e.Name, e.Prompt and "SIM" or "NAO", e.Zone,
            e.Position.X, e.Position.Y, e.Position.Z, math.floor(e.Distance)
        ))
    end
    logL("\n================================================================================")
    logL("FIM DO INVENTARIO.")

    local fullText = table.concat(lines, "\n")
    pcall(function()
        if writefile then writefile("ROUBE_UM_OVO_DUMP.txt", fullText) end
        if setclipboard then setclipboard(fullText) end
    end)
    addLog("INSPETOR", "Dump estrutural exportado para ROUBE_UM_OVO_DUMP.txt (" .. tostring(#discovered) .. " ovos)!")
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

-- 12. INTERFACE TECH BLUE MODERNA (MINIMALISTA, SEM EMOJIS)
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "EggTelemetryHub"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

pcall(function()
    if gethui then ScreenGui.Parent = gethui()
    elseif Services.CoreGui then ScreenGui.Parent = Services.CoreGui
    else ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end
end)

local C_BG = Color3.fromRGB(11, 15, 25)
local C_PANEL = Color3.fromRGB(17, 24, 39)
local C_CARD = Color3.fromRGB(24, 33, 53)
local C_BORDER = Color3.fromRGB(30, 41, 59)
local C_BLUE = Color3.fromRGB(56, 189, 248)
local C_BLUE_DARK = Color3.fromRGB(14, 116, 144)
local C_TEXT = Color3.fromRGB(241, 245, 249)
local C_MUTED = Color3.fromRGB(148, 163, 184)
local C_RED = Color3.fromRGB(239, 68, 68)
local C_GREEN = Color3.fromRGB(34, 197, 94)

local function addCorner(instance, rad)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, rad or 6)
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

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 540, 0, 400)
MainFrame.Position = UDim2.new(0.5, -270, 0.5, -200)
MainFrame.BackgroundColor3 = C_BG
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui
addCorner(MainFrame, 8)
addStroke(MainFrame, C_BLUE, 1)

-- Topbar
local Topbar = Instance.new("Frame")
Topbar.Size = UDim2.new(1, 0, 0, 36)
Topbar.BackgroundColor3 = C_PANEL
Topbar.BorderSizePixel = 0
Topbar.Parent = MainFrame
addCorner(Topbar, 8)

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -70, 1, 0)
Title.Position = UDim2.new(0, 12, 0, 0)
Title.BackgroundTransparency = 1
Title.Font = Enum.Font.GothamBold
Title.TextSize = 12
Title.TextColor3 = C_BLUE
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Text = "ROUBE UM OVO - TELEMETRIA & AUTOMAÇÃO v6.0"
Title.Parent = Topbar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 24, 0, 24)
CloseBtn.Position = UDim2.new(1, -30, 0, 6)
CloseBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
CloseBtn.Text = "X"
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 11
CloseBtn.TextColor3 = C_TEXT
CloseBtn.Parent = Topbar
addCorner(CloseBtn, 4)
CloseBtn.MouseButton1Click:Connect(function() MainFrame.Visible = false end)

-- Sidebar de Navegação
local Sidebar = Instance.new("Frame")
Sidebar.Size = UDim2.new(0, 120, 1, -36)
Sidebar.Position = UDim2.new(0, 0, 0, 36)
Sidebar.BackgroundColor3 = C_PANEL
Sidebar.BorderSizePixel = 0
Sidebar.Parent = MainFrame

local ContentArea = Instance.new("Frame")
ContentArea.Size = UDim2.new(1, -120, 1, -36)
ContentArea.Position = UDim2.new(0, 120, 0, 36)
ContentArea.BackgroundColor3 = C_BG
ContentArea.BorderSizePixel = 0
ContentArea.Parent = MainFrame

local Pages = {}
local CurrentTab = "Radar"

local function createPage(name)
    local page = Instance.new("ScrollingFrame")
    page.Name = name .. "Page"
    page.Size = UDim2.new(1, 0, 1, 0)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 3
    page.ScrollBarImageColor3 = C_BLUE
    page.CanvasSize = UDim2.new(0, 0, 0, 0)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.Visible = false
    page.Parent = ContentArea

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 8)
    layout.Parent = page

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 10)
    pad.PaddingBottom = UDim.new(0, 10)
    pad.PaddingLeft = UDim.new(0, 10)
    pad.PaddingRight = UDim.new(0, 10)
    pad.Parent = page

    Pages[name] = page
    return page
end

local TabButtons = {}
local function switchTab(name)
    CurrentTab = name
    for tabName, page in pairs(Pages) do
        page.Visible = (tabName == name)
    end
    for tabName, btn in pairs(TabButtons) do
        if tabName == name then
            btn.BackgroundColor3 = C_BLUE_DARK
            btn.TextColor3 = C_TEXT
        else
            btn.BackgroundColor3 = Color3.fromRGB(24, 33, 53)
            btn.TextColor3 = C_MUTED
        end
    end
end

local tabsList = {
    { Id = "Radar", Label = "RADAR" },
    { Id = "AutoSteal", Label = "AUTO-ROUBO" },
    { Id = "Configs", Label = "CONFIGS" },
    { Id = "Inspector", Label = "INSPETOR" },
    { Id = "Logs", Label = "REGISTROS" }
}

for i, t in ipairs(tabsList) do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -12, 0, 28)
    btn.Position = UDim2.new(0, 6, 0, 8 + (i - 1) * 34)
    btn.BackgroundColor3 = (t.Id == CurrentTab) and C_BLUE_DARK or Color3.fromRGB(24, 33, 53)
    btn.Text = t.Label
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 10
    btn.TextColor3 = (t.Id == CurrentTab) and C_TEXT or C_MUTED
    btn.Parent = Sidebar
    addCorner(btn, 4)
    TabButtons[t.Id] = btn
    btn.MouseButton1Click:Connect(function() switchTab(t.Id) end)
end

local function createCard(parent, titleText)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, 0)
    card.AutomaticSize = Enum.AutomaticSize.Y
    card.BackgroundColor3 = C_CARD
    card.BorderSizePixel = 0
    card.Parent = parent
    addCorner(card, 6)
    addStroke(card, C_BORDER, 1)

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 8)
    pad.PaddingBottom = UDim.new(0, 8)
    pad.PaddingLeft = UDim.new(0, 10)
    pad.PaddingRight = UDim.new(0, 10)
    pad.Parent = card

    local cardLayout = Instance.new("UIListLayout")
    cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
    cardLayout.Padding = UDim.new(0, 6)
    cardLayout.Parent = card

    if titleText then
        local cTitle = Instance.new("TextLabel")
        cTitle.Size = UDim2.new(1, 0, 0, 16)
        cTitle.BackgroundTransparency = 1
        cTitle.Font = Enum.Font.GothamBold
        cTitle.TextSize = 10
        cTitle.TextColor3 = C_BLUE
        cTitle.TextXAlignment = Enum.TextXAlignment.Left
        cTitle.Text = titleText
        cTitle.Parent = card
    end

    return card
end

--================================================================--
-- 1. ABA: RADAR DE OVOS
--================================================================--
local RadarPage = createPage("Radar")
local RadarHeaderCard = createCard(RadarPage, "CONTROLE DE VARREDURA")

local ControlsRow = Instance.new("Frame")
ControlsRow.Size = UDim2.new(1, 0, 0, 26)
ControlsRow.BackgroundTransparency = 1
ControlsRow.Parent = RadarHeaderCard

local SearchInput = Instance.new("TextBox")
SearchInput.Size = UDim2.new(1, -170, 1, 0)
SearchInput.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
SearchInput.PlaceholderText = "Filtrar por nome ou raridade..."
SearchInput.PlaceholderColor3 = C_MUTED
SearchInput.Text = ""
SearchInput.Font = Enum.Font.Gotham
SearchInput.TextSize = 10
SearchInput.TextColor3 = C_TEXT
SearchInput.ClearTextOnFocus = false
SearchInput.Parent = ControlsRow
addCorner(SearchInput, 4)
addStroke(SearchInput, C_BORDER, 1)

local RefreshBtn = Instance.new("TextButton")
RefreshBtn.Size = UDim2.new(0, 78, 1, 0)
RefreshBtn.Position = UDim2.new(1, -162, 0, 0)
RefreshBtn.BackgroundColor3 = C_BLUE_DARK
RefreshBtn.Text = "VARREDURA"
RefreshBtn.Font = Enum.Font.GothamBold
RefreshBtn.TextSize = 10
RefreshBtn.TextColor3 = C_TEXT
RefreshBtn.Parent = ControlsRow
addCorner(RefreshBtn, 4)

local ToggleESPBtn = Instance.new("TextButton")
ToggleESPBtn.Size = UDim2.new(0, 78, 1, 0)
ToggleESPBtn.Position = UDim2.new(1, -80, 0, 0)
ToggleESPBtn.BackgroundColor3 = Config.ESPEnabled and C_GREEN or Color3.fromRGB(30, 41, 59)
ToggleESPBtn.Text = Config.ESPEnabled and "ESP: ON" or "ESP: OFF"
ToggleESPBtn.Font = Enum.Font.GothamBold
ToggleESPBtn.TextSize = 10
ToggleESPBtn.TextColor3 = C_TEXT
ToggleESPBtn.Parent = ControlsRow
addCorner(ToggleESPBtn, 4)

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, 0, 0, 14)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextSize = 9
StatusLabel.TextColor3 = C_MUTED
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.Text = "Pronto para varredura do mapa."
StatusLabel.Parent = RadarHeaderCard

local RadarListContainer = Instance.new("Frame")
RadarListContainer.Size = UDim2.new(1, 0, 0, 0)
RadarListContainer.AutomaticSize = Enum.AutomaticSize.Y
RadarListContainer.BackgroundTransparency = 1
RadarListContainer.Parent = RadarPage

local RadarListLayout = Instance.new("UIListLayout")
RadarListLayout.SortOrder = Enum.SortOrder.LayoutOrder
RadarListLayout.Padding = UDim.new(0, 4)
RadarListLayout.Parent = RadarListContainer

local currentDiscovered = {}

local function renderRadarList(eggs)
    currentDiscovered = eggs
    for _, child in ipairs(RadarListContainer:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end

    local query = Config.SearchQuery:lower()
    local matched = 0

    for _, e in ipairs(eggs) do
        local matchesSearch = (query == "") or e.Name:lower():find(query, 1, true) or e.Rarity:lower():find(query, 1, true)
        if matchesSearch then
            matched = matched + 1
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, 0, 0, 48)
            row.BackgroundColor3 = C_CARD
            row.BorderSizePixel = 0
            row.Parent = RadarListContainer
            addCorner(row, 4)
            addStroke(row, C_BORDER, 1)

            local rColor = RarityColors[e.Rarity:upper()] or C_BLUE

            local badge = Instance.new("TextLabel")
            badge.Size = UDim2.new(0, 70, 0, 16)
            badge.Position = UDim2.new(0, 8, 0, 6)
            badge.BackgroundColor3 = rColor
            badge.Text = e.Rarity:upper()
            badge.Font = Enum.Font.GothamBold
            badge.TextSize = 8
            badge.TextColor3 = Color3.fromRGB(11, 15, 25)
            badge.Parent = row
            addCorner(badge, 3)

            local nameLbl = Instance.new("TextLabel")
            nameLbl.Size = UDim2.new(1, -250, 0, 16)
            nameLbl.Position = UDim2.new(0, 84, 0, 6)
            nameLbl.BackgroundTransparency = 1
            nameLbl.Font = Enum.Font.GothamBold
            nameLbl.TextSize = 10
            nameLbl.TextColor3 = C_TEXT
            nameLbl.TextXAlignment = Enum.TextXAlignment.Left
            nameLbl.Text = e.Name
            nameLbl.Parent = row

            local subLbl = Instance.new("TextLabel")
            subLbl.Size = UDim2.new(1, -250, 0, 14)
            subLbl.Position = UDim2.new(0, 8, 0, 26)
            subLbl.BackgroundTransparency = 1
            subLbl.Font = Enum.Font.Gotham
            subLbl.TextSize = 9
            subLbl.TextColor3 = C_MUTED
            subLbl.TextXAlignment = Enum.TextXAlignment.Left
            subLbl.Text = string.format("%dm | %s%s", math.floor(e.Distance), e.Zone, e.Prompt and " | Prompt Ativo" or "")
            subLbl.Parent = row

            -- Botão 1: Copiar Posição
            local copyBtn = Instance.new("TextButton")
            copyBtn.Size = UDim2.new(0, 68, 0, 22)
            copyBtn.Position = UDim2.new(1, -156, 0, 13)
            copyBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
            copyBtn.Text = "COPIAR POS"
            copyBtn.Font = Enum.Font.GothamBold
            copyBtn.TextSize = 8
            copyBtn.TextColor3 = C_TEXT
            copyBtn.Parent = row
            addCorner(copyBtn, 4)

            copyBtn.MouseButton1Click:Connect(function()
                local cStr = string.format("Vector3.new(%.1f, %.1f, %.1f)", e.Position.X, e.Position.Y, e.Position.Z)
                pcall(function() if setclipboard then setclipboard(cStr) end end)
                copyBtn.Text = "COPIADO!"
                task.delay(1, function() copyBtn.Text = "COPIAR POS" end)
            end)

            -- Botão 2: Ir até o Ovo (Voo Direto no Solo)
            local gotoBtn = Instance.new("TextButton")
            gotoBtn.Size = UDim2.new(0, 78, 0, 22)
            gotoBtn.Position = UDim2.new(1, -82, 0, 13)
            gotoBtn.BackgroundColor3 = C_BLUE_DARK
            gotoBtn.Text = "IR ATE OVO"
            gotoBtn.Font = Enum.Font.GothamBold
            gotoBtn.TextSize = 9
            gotoBtn.TextColor3 = C_TEXT
            gotoBtn.Parent = row
            addCorner(gotoBtn, 4)

            gotoBtn.MouseButton1Click:Connect(function()
                task.spawn(function()
                    addLog("MOVIMENTO", "Iniciando deslocamento direto até " .. e.Name .. " (" .. math.floor(e.Distance) .. " studs)...")
                    local ok = movePlayerDirect(e.Position, Config.MoveSpeed)
                    if ok then
                        addLog("MOVIMENTO", "Chegou ao ovo! Interagindo com o prompt...")
                        if e.Prompt then triggerPrompt(e.Prompt) end
                    else
                        addLog("MOVIMENTO", "Deslocamento finalizado.")
                    end
                end)
            end)
        end
    end

    StatusLabel.Text = string.format("Monitorando %d ovos no mapa (%d exibidos pelo filtro).", #currentDiscovered, matched)
end

local function executeRadarScan()
    StatusLabel.Text = "Executando varredura profunda no Workspace..."
    local eggs = scanAllEggs()
    renderRadarList(eggs)
    addLog("RADAR", string.format("Varredura concluída. %d ovos identificados.", #eggs))
    updateESP()
end

RefreshBtn.MouseButton1Click:Connect(executeRadarScan)
SearchInput:GetPropertyChangedSignal("Text"):Connect(function()
    Config.SearchQuery = SearchInput.Text
    renderRadarList(currentDiscovered)
end)

ToggleESPBtn.MouseButton1Click:Connect(function()
    Config.ESPEnabled = not Config.ESPEnabled
    ToggleESPBtn.BackgroundColor3 = Config.ESPEnabled and C_GREEN or Color3.fromRGB(30, 41, 59)
    ToggleESPBtn.Text = Config.ESPEnabled and "ESP: ON" or "ESP: OFF"
    updateESP()
    addLog("ESP", Config.ESPEnabled and "ESP ativado." or "ESP desativado.")
end)

--================================================================--
-- 2. ABA: INSPETOR E EXTRAÇÃO ESTRUTURAL
--================================================================--
local InspectorPage = createPage("Inspector")
local DumpCard = createCard(InspectorPage, "INSPETOR DE ARQUIVOS E DADOS INTERNOS")

local DumpDesc = Instance.new("TextLabel")
DumpDesc.Size = UDim2.new(1, 0, 0, 36)
DumpDesc.BackgroundTransparency = 1
DumpDesc.Font = Enum.Font.Gotham
DumpDesc.TextSize = 9
DumpDesc.TextColor3 = C_MUTED
DumpDesc.TextXAlignment = Enum.TextXAlignment.Left
DumpDesc.TextWrapped = true
DumpDesc.Text = "Exporta tabelas completas de ReplicatedStorage.Data (Assets com 118 Pets, Raridades, Áreas, Guardas), modelos em AssetModels e ClientRenderedAssets para ROUBE_UM_OVO_DUMP.txt."
DumpDesc.Parent = DumpCard

local DumpBtn = Instance.new("TextButton")
DumpBtn.Size = UDim2.new(1, 0, 0, 28)
DumpBtn.BackgroundColor3 = C_BLUE_DARK
DumpBtn.Text = "EXPORTAR DUMP ESTRUTURAL COMPLETO (TXT)"
DumpBtn.Font = Enum.Font.GothamBold
DumpBtn.TextSize = 10
DumpBtn.TextColor3 = C_TEXT
DumpBtn.Parent = DumpCard
addCorner(DumpBtn, 4)

local DumpStatus = Instance.new("TextLabel")
DumpStatus.Size = UDim2.new(1, 0, 0, 16)
DumpStatus.BackgroundTransparency = 1
DumpStatus.Font = Enum.Font.Gotham
DumpStatus.TextSize = 9
DumpStatus.TextColor3 = C_GREEN
DumpStatus.Text = ""
DumpStatus.Parent = DumpCard

DumpBtn.MouseButton1Click:Connect(function()
    DumpBtn.Text = "GERANDO DUMP ESTRUTURAL..."
    task.spawn(function()
        local txt, count = dumpGameData()
        DumpBtn.Text = "EXPORTAR DUMP ESTRUTURAL COMPLETO (TXT)"
        DumpStatus.Text = string.format("Dump exportado com sucesso! (%d ovos mapeados)", count)
        task.delay(4, function() DumpStatus.Text = "" end)
    end)
end)

--================================================================--
-- 3. ABA: AUTO-ROUBO
--================================================================--
local AutoStealPage = createPage("AutoSteal")
local StealCard = createCard(AutoStealPage, "CONTROLE DO AUTO-ROUBO")

local SetBaseBtn = Instance.new("TextButton")
SetBaseBtn.Size = UDim2.new(1, 0, 0, 26)
SetBaseBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
SetBaseBtn.Text = "FIXAR POSIÇÃO ATUAL COMO BASE (PLOT)"
SetBaseBtn.Font = Enum.Font.GothamBold
SetBaseBtn.TextSize = 9
SetBaseBtn.TextColor3 = C_TEXT
SetBaseBtn.Parent = StealCard
addCorner(SetBaseBtn, 4)

local BaseStatus = Instance.new("TextLabel")
BaseStatus.Size = UDim2.new(1, 0, 0, 16)
BaseStatus.BackgroundTransparency = 1
BaseStatus.Font = Enum.Font.Gotham
BaseStatus.TextSize = 9
BaseStatus.TextColor3 = C_MUTED
BaseStatus.TextXAlignment = Enum.TextXAlignment.Left
BaseStatus.Text = "Nenhuma base fixada (usará spawn inicial automaticamente)."
BaseStatus.Parent = StealCard

SetBaseBtn.MouseButton1Click:Connect(function()
    local hrp = getHRP()
    if hrp then
        State.BaseCFrame = hrp.CFrame
        BaseStatus.Text = string.format("Base fixada em: (%.1f, %.1f, %.1f)", hrp.Position.X, hrp.Position.Y, hrp.Position.Z)
        BaseStatus.TextColor3 = C_GREEN
        addLog("BASE", "Base registrada: " .. BaseStatus.Text)
    end
end)

local ToggleStealBtn = Instance.new("TextButton")
ToggleStealBtn.Size = UDim2.new(1, 0, 0, 32)
ToggleStealBtn.BackgroundColor3 = Config.AutoStealEnabled and C_GREEN or C_BLUE_DARK
ToggleStealBtn.Text = Config.AutoStealEnabled and "DESATIVAR AUTO-ROUBO" or "ATIVAR AUTO-ROUBO"
ToggleStealBtn.Font = Enum.Font.GothamBold
ToggleStealBtn.TextSize = 11
ToggleStealBtn.TextColor3 = C_TEXT
ToggleStealBtn.Parent = StealCard
addCorner(ToggleStealBtn, 4)

local StealInfoCard = createCard(AutoStealPage, "ESTATÍSTICAS DO CICLO ATUAL")
local StealStatusLabel = Instance.new("TextLabel")
StealStatusLabel.Size = UDim2.new(1, 0, 0, 44)
StealStatusLabel.BackgroundTransparency = 1
StealStatusLabel.Font = Enum.Font.Gotham
StealStatusLabel.TextSize = 9
StealStatusLabel.TextColor3 = C_MUTED
StealStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StealStatusLabel.TextWrapped = true
StealStatusLabel.Text = "Ciclo: Desativado\nAlvo Atual: Nenhum\nMétodo: Solo na Ida / Voo Alto na Volta à Base"
StealStatusLabel.Parent = StealInfoCard

-- Função do Ciclo de Roubo
local function runStealCycle()
    if State.IsExecutingSteal or not Config.AutoStealEnabled then return end
    State.IsExecutingSteal = true

    local myHrp = getHRP()
    if not myHrp then
        State.IsExecutingSteal = false
        return
    end

    if not State.BaseCFrame then
        State.BaseCFrame = myHrp.CFrame
        BaseStatus.Text = string.format("Base automática: (%.1f, %.1f, %.1f)", myHrp.Position.X, myHrp.Position.Y, myHrp.Position.Z)
        BaseStatus.TextColor3 = C_GREEN
    end
    local basePos = State.BaseCFrame.Position

    -- 1. Se já está com ovo na mão, voltar pelo alto à base imediatamente
    local holding, heldName = isHoldingEgg()
    if holding then
        StealStatusLabel.Text = "Ciclo: Ovo em mãos (" .. tostring(heldName) .. ")\nRetornando à base com voo alto seguro..."
        addLog("BASE", "Ovo detectado em mãos (" .. tostring(heldName) .. ")! Retornando à base...")
        movePlayerOverhead(basePos + Vector3.new(0, 2.5, 0), Config.MoveSpeed)
        addLog("BASE", "Na base! Aguardando o jogo depositar o ovo no plot...")
        task.wait(Config.AutoDepositWait)
        State.IsExecutingSteal = false
        return
    end

    -- 2. Buscar ovos e filtrar por Ilha Atual e Distância Segura
    local eggs = scanAllEggs()
    local validTargets = {}

    for _, e in ipairs(eggs) do
        if not (Config.ShowOnlyUnowned and e.IsMyPlot) then
            if e.Distance <= Config.MaxStealDistance then
                if isEggInMyIsland(e.Position) then
                    table.insert(validTargets, e)
                end
            end
        end
    end

    if #validTargets == 0 then
        StealStatusLabel.Text = "Ciclo: Aguardando ovos na ilha atual...\nAlvo Atual: Nenhum no alcance seguro (" .. tostring(Config.MaxStealDistance) .. " studs)"
        task.wait(1.5)
        State.IsExecutingSteal = false
        return
    end

    local target = validTargets[1]
    State.CurrentTargetEgg = target
    StealStatusLabel.Text = string.format("Ciclo: Roubando...\nAlvo: %s [%s] (%dm)\nIndo em linha reta no solo...", target.Name, target.Rarity, math.floor(target.Distance))
    addLog("ROUBO", "Indo até o alvo: " .. target.Name .. " (" .. math.floor(target.Distance) .. " studs)...")

    -- 3. Deslocamento direto no solo até o ovo
    local arrived = movePlayerDirect(target.Position, Config.MoveSpeed)
    if not arrived then
        State.IsExecutingSteal = false
        return
    end

    -- 4. Coletar Ovo via ProximityPrompt
    addLog("ROUBO", "Chegou ao ovo! Coletando...")
    local pInstance = target.Prompt or (target.Instance and target.Instance:FindFirstChildWhichIsA("ProximityPrompt", true))

    local pickedUp = false
    for _ = 1, 6 do
        if isHoldingEgg() then
            pickedUp = true
            break
        end
        if pInstance and pInstance.Parent then
            triggerPrompt(pInstance)
        end
        task.wait(0.12)
        if not pInstance or not pInstance.Parent or not pInstance.Enabled then
            pickedUp = true
            break
        end
    end

    -- 5. Retorno à Base pelo alto
    if pickedUp or isHoldingEgg() then
        addLog("ROUBO", "Ovo coletado com sucesso! Retornando à base com voo alto...")
        StealStatusLabel.Text = "Ciclo: Ovo coletado!\nRetornando à base pelo alto..."
        movePlayerOverhead(basePos + Vector3.new(0, 2.5, 0), Config.MoveSpeed)
        addLog("BASE", "Na base! Aguardando depósito...")
        task.wait(Config.AutoDepositWait)
    else
        addLog("ROUBO", "Ovo protegido ou em recarga. Buscando próximo alvo...")
        task.wait(0.4)
    end

    State.IsExecutingSteal = false
end

ToggleStealBtn.MouseButton1Click:Connect(function()
    Config.AutoStealEnabled = not Config.AutoStealEnabled
    ToggleStealBtn.BackgroundColor3 = Config.AutoStealEnabled and C_GREEN or C_BLUE_DARK
    ToggleStealBtn.Text = Config.AutoStealEnabled and "DESATIVAR AUTO-ROUBO" or "ATIVAR AUTO-ROUBO"
    addLog("ROUBO", Config.AutoStealEnabled and "Ciclo de auto-roubo ativado." or "Ciclo de auto-roubo desativado.")
end)

task.spawn(function()
    while true do
        if Config.AutoStealEnabled and not State.IsExecutingSteal then
            runStealCycle()
        end
        task.wait(0.2)
    end
end)

--================================================================--
-- 4. ABA: CONFIGURAÇÕES
--================================================================--
local ConfigsPage = createPage("Configs")
local LimitsCard = createCard(ConfigsPage, "LIMITES DE SEGURANÇA E MOVIMENTAÇÃO")

-- Alternador: Travar Ilha Atual (LockCurrentIsland)
local IslandLockBtn = Instance.new("TextButton")
IslandLockBtn.Size = UDim2.new(1, 0, 0, 26)
IslandLockBtn.BackgroundColor3 = Config.LockCurrentIsland and C_GREEN or Color3.fromRGB(30, 41, 59)
IslandLockBtn.Text = Config.LockCurrentIsland and "TRAVAR ILHA ATUAL: LIGADO (PROTEÇÃO ANTI-MORTE)" or "TRAVAR ILHA ATUAL: DESLIGADO"
IslandLockBtn.Font = Enum.Font.GothamBold
IslandLockBtn.TextSize = 9
IslandLockBtn.TextColor3 = C_TEXT
IslandLockBtn.Parent = LimitsCard
addCorner(IslandLockBtn, 4)

IslandLockBtn.MouseButton1Click:Connect(function()
    Config.LockCurrentIsland = not Config.LockCurrentIsland
    IslandLockBtn.BackgroundColor3 = Config.LockCurrentIsland and C_GREEN or Color3.fromRGB(30, 41, 59)
    IslandLockBtn.Text = Config.LockCurrentIsland and "TRAVAR ILHA ATUAL: LIGADO (PROTEÇÃO ANTI-MORTE)" or "TRAVAR ILHA ATUAL: DESLIGADO"
    addLog("CONFIG", "Trava de ilha atual definida para: " .. tostring(Config.LockCurrentIsland))
end)

-- Slider: Alcance Seguro
local DistSliderCard = createCard(ConfigsPage, "ALCANCE SEGURO MÁXIMO")
local DistLabel = Instance.new("TextLabel")
DistLabel.Size = UDim2.new(1, 0, 0, 16)
DistLabel.BackgroundTransparency = 1
DistLabel.Font = Enum.Font.Gotham
DistLabel.TextSize = 9
DistLabel.TextColor3 = C_TEXT
DistLabel.Text = string.format("Alcance Máximo: %d studs (Recomendado: 350)", Config.MaxStealDistance)
DistLabel.Parent = DistSliderCard

local DistSliderBg = Instance.new("Frame")
DistSliderBg.Size = UDim2.new(1, 0, 0, 12)
DistSliderBg.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
DistSliderBg.Parent = DistSliderCard
addCorner(DistSliderBg, 6)

local DistSliderFill = Instance.new("Frame")
DistSliderFill.Size = UDim2.new(Config.MaxStealDistance / 1500, 0, 1, 0)
DistSliderFill.BackgroundColor3 = C_BLUE
DistSliderFill.BorderSizePixel = 0
DistSliderFill.Parent = DistSliderBg
addCorner(DistSliderFill, 6)

local DistTrigger = Instance.new("TextButton")
DistTrigger.Size = UDim2.new(1, 0, 1, 0)
DistTrigger.BackgroundTransparency = 1
DistTrigger.Text = ""
DistTrigger.Parent = DistSliderBg

local isDraggingDist = false
DistTrigger.MouseButton1Down:Connect(function() isDraggingDist = true end)
Services.UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        isDraggingDist = false
    end
end)

Services.RunService.RenderStepped:Connect(function()
    if isDraggingDist then
        local mousePos = Services.UserInputService:GetMouseLocation().X
        local barPos = DistSliderBg.AbsolutePosition.X
        local barSize = DistSliderBg.AbsoluteSize.X
        local pct = math.clamp((mousePos - barPos) / barSize, 0.05, 1)
        DistSliderFill.Size = UDim2.new(pct, 0, 1, 0)
        local val = math.floor(pct * 1500)
        Config.MaxStealDistance = val
        DistLabel.Text = string.format("Alcance Máximo: %d studs", val)
    end
end)

-- Slider: Velocidade de Voo
local SpeedSliderCard = createCard(ConfigsPage, "VELOCIDADE DE DESLOCAMENTO")
local SpeedLabel = Instance.new("TextLabel")
SpeedLabel.Size = UDim2.new(1, 0, 0, 16)
SpeedLabel.BackgroundTransparency = 1
SpeedLabel.Font = Enum.Font.Gotham
SpeedLabel.TextSize = 9
SpeedLabel.TextColor3 = C_TEXT
SpeedLabel.Text = string.format("Velocidade: %d studs/s", Config.MoveSpeed)
SpeedLabel.Parent = SpeedSliderCard

local SpeedSliderBg = Instance.new("Frame")
SpeedSliderBg.Size = UDim2.new(1, 0, 0, 12)
SpeedSliderBg.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
SpeedSliderBg.Parent = SpeedSliderCard
addCorner(SpeedSliderBg, 6)

local SpeedSliderFill = Instance.new("Frame")
SpeedSliderFill.Size = UDim2.new(Config.MoveSpeed / 600, 0, 1, 0)
SpeedSliderFill.BackgroundColor3 = C_BLUE
SpeedSliderFill.BorderSizePixel = 0
SpeedSliderFill.Parent = SpeedSliderBg
addCorner(SpeedSliderFill, 6)

local SpeedTrigger = Instance.new("TextButton")
SpeedTrigger.Size = UDim2.new(1, 0, 1, 0)
SpeedTrigger.BackgroundTransparency = 1
SpeedTrigger.Text = ""
SpeedTrigger.Parent = SpeedSliderBg

local isDraggingSpeed = false
SpeedTrigger.MouseButton1Down:Connect(function() isDraggingSpeed = true end)
Services.UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        isDraggingSpeed = false
    end
end)

Services.RunService.RenderStepped:Connect(function()
    if isDraggingSpeed then
        local mousePos = Services.UserInputService:GetMouseLocation().X
        local barPos = SpeedSliderBg.AbsolutePosition.X
        local barSize = SpeedSliderBg.AbsoluteSize.X
        local pct = math.clamp((mousePos - barPos) / barSize, 0.1, 1)
        SpeedSliderFill.Size = UDim2.new(pct, 0, 1, 0)
        local val = math.floor(pct * 600)
        Config.MoveSpeed = val
        SpeedLabel.Text = string.format("Velocidade: %d studs/s", val)
    end
end)

--================================================================--
-- 5. ABA: REGISTROS (LOGS EM TEMPO REAL)
--================================================================--
local LogsPage = createPage("Logs")
local LogCard = createCard(LogsPage, "CONSOLE DE EVENTOS EM TEMPO REAL")

local LogTextLabel = Instance.new("TextLabel")
LogTextLabel.Size = UDim2.new(1, 0, 0, 0)
LogTextLabel.AutomaticSize = Enum.AutomaticSize.Y
LogTextLabel.BackgroundTransparency = 1
LogTextLabel.Font = Enum.Font.Code
LogTextLabel.TextSize = 8
LogTextLabel.TextColor3 = C_TEXT
LogTextLabel.TextXAlignment = Enum.TextXAlignment.Left
LogTextLabel.TextYAlignment = Enum.TextYAlignment.Top
LogTextLabel.TextWrapped = true
LogTextLabel.Text = "Registros iniciados."
LogTextLabel.Parent = LogCard

_G.UpdateLogConsole = function()
    pcall(function()
        LogTextLabel.Text = table.concat(State.Logs, "\n")
    end)
end

-- 13. Tecla de Atalho (LeftControl) e Botão Mobile (RAD)
Services.UserInputService.InputBegan:Connect(function(input, gpe)
    if not gpe and input.KeyCode == Enum.KeyCode.LeftControl then
        MainFrame.Visible = not MainFrame.Visible
    end
end)

local MobileBtn = Instance.new("TextButton")
MobileBtn.Name = "MobileToggleBtn"
MobileBtn.Size = UDim2.new(0, 38, 0, 38)
MobileBtn.Position = UDim2.new(0.02, 0, 0.45, 0)
MobileBtn.BackgroundColor3 = C_PANEL
MobileBtn.Text = "RAD"
MobileBtn.Font = Enum.Font.GothamBold
MobileBtn.TextSize = 10
MobileBtn.TextColor3 = C_BLUE
MobileBtn.Parent = ScreenGui
addCorner(MobileBtn, 19)
addStroke(MobileBtn, C_BLUE, 1)
MobileBtn.Draggable = true

MobileBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

-- Inicialização com primeira varredura após 1 segundo
task.delay(1, function()
    executeRadarScan()
    addLog("SISTEMA", "Roube um Ovo v6.0 carregado com sucesso!")
end)

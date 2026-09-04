--[[
    ROUBE UM OVO - HUB DE TELEMETRIA & AUTOMAÇÃO (v5.0)
    -----------------------------------------------------------------------
    - Deslocamento Físico Anti-Rollback (BodyVelocity + BodyGyro):
      * Movimentação por velocidade física com altitude de segurança (Y ≈ 92 na ida, Y >= 115 na volta).
      * Elimina o rollback do servidor (WallEntryRollback) e as mortes causadas por barreiras de ilha.
      * Noclip contínuo com CanTouch = false para anular qualquer kill-brick.
    - Resolução Real de Ovos por MeshId & Assets.Directory:
      * Mapeamento de todos os 117 modelos de ReplicatedStorage.AssetModels por MeshId.
      * Leitura direta de ReplicatedStorage.Data.Assets.Directory e ByRarity.
      * Identifica o nome real exato (Dragon Egg, Sakura Egg, Abyss Egg, etc.) e sua raridade real.
    - Auto-Steal Confiável:
      * Associa automaticamente o ProximityPrompt correto a cada ovo.
      * Bypass de HoldDuration = 0 e acionamento múltiplo.
      * Retorno à base com voo elevado somente após confirmação real de coleta.
    - Dumper Exaustivo de Dados e Tabelas para ROUBE_UM_OVO_DUMP.txt.
    - Interface minimalista em português, tema Tech Blue (#38BDF8), sem emojis.
]]

-- 1. Silenciamento Total Preventivo contra LogService.MessageOut
local function silentOutput(...) end
local print = silentOutput
local warn = silentOutput

-- 2. Limpeza Preventiva de Globais (_G e getgenv)
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
    ReplicatedStorage = safeService("ReplicatedStorage"),
    TweenService = safeService("TweenService")
}

local LocalPlayer = Services.Players.LocalPlayer
local scriptActive = true

-- 4. Utilitários de Nomes Aleatórios e Proteção de GUI
local function getRandomName()
    local guid = ""
    pcall(function()
        guid = Services.HttpService:GenerateGUID(false):gsub("-", ""):sub(1, 14)
    end)
    if guid == "" then
        guid = tostring(math.random(1000000000, 9999999999))
    end
    return guid
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
        if gethui then container = gethui() end
    end)
    if not container then
        pcall(function()
            local cg = game:GetService("CoreGui")
            container = (cloneref and cloneref(cg)) or cg
        end)
    end
    if not container and LocalPlayer then
        container = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 3)
    end
    return container
end

-- 5. Configurações Locais
local Config = {
    SearchQuery = "",
    MinWeightKg = 0,
    MinScore = 0,

    EggESP = false,
    PlayerESP = false,
    ESPMaxDistance = 4000,

    AutoSteal = false,
    MoveSpeed = 350,
    StealDelay = 0.4,
    ReturnToBase = true,
    CustomBasePos = nil,
    SavedBasePos = nil,

    AntiAFK = true
}

local LogHistory = {}
local _updateConsoleFunc = nil

local function addLog(categoria, texto)
    local timestamp = os.date("%H:%M:%S")
    local msg = string.format("[%s] [%s] %s", timestamp, categoria, tostring(texto))
    table.insert(LogHistory, 1, msg)
    if #LogHistory > 250 then
        table.remove(LogHistory, #LogHistory)
    end
    if _updateConsoleFunc then
        _updateConsoleFunc()
    end
end

-- 6. Utilitários do Personagem e Posse de Ovos
local function getHRP()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getBasePosition()
    if Config.CustomBasePos then return Config.CustomBasePos end
    if Config.SavedBasePos then return Config.SavedBasePos end

    pcall(function()
        local myName = LocalPlayer.Name:lower()
        local myDisplay = LocalPlayer.DisplayName:lower()
        local plots = Services.Workspace:FindFirstChild("Plots")
        if plots then
            for _, plot in ipairs(plots:GetChildren()) do
                local owner = plot:FindFirstChild("Owner") or plot:FindFirstChild("OwnerName") or plot:FindFirstChild("Player")
                local val = owner and tostring(owner.Value):lower() or ""
                if val ~= "" and (val == myName or val == myDisplay) then
                    local p = plot:IsA("BasePart") and plot.Position or (plot:IsA("Model") and plot:GetPivot().Position)
                    if p then
                        Config.SavedBasePos = p + Vector3.new(0, 3.5, 0)
                        return
                    end
                end
            end
        end
    end)

    if not Config.SavedBasePos then
        local hrp = getHRP()
        if hrp then Config.SavedBasePos = hrp.Position end
    end
    return Config.SavedBasePos
end

local function isHoldingEgg()
    local char = LocalPlayer.Character
    if not char then return false, nil end

    -- 1. Ferramenta equipada na mão
    for _, item in ipairs(char:GetChildren()) do
        if item:IsA("Tool") then
            return true, item.Name
        end
    end

    -- 2. Modelo soldado ao tronco do personagem (mecânica de carregar nas costas/mãos)
    for _, item in ipairs(char:GetChildren()) do
        if (item:IsA("Model") or item:IsA("BasePart")) and item.Name ~= "HumanoidRootPart" then
            local n = item.Name:lower()
            if n:find("egg") or n:find("ovo") or n:find("carry") or n:find("render") then
                local weld = item:FindFirstChildWhichIsA("WeldConstraint", true) or item:FindFirstChildWhichIsA("Weld", true) or item:FindFirstChildWhichIsA("Motor6D", true)
                if weld then
                    return true, item.Name
                end
            end
        end
    end

    -- 3. Mochila (Backpack)
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

    -- 4. Atributos no Personagem ou Player
    local holdingAttr = char:GetAttribute("HoldingEgg") or char:GetAttribute("CarryingEgg") or char:GetAttribute("HasEgg")
        or char:GetAttribute("EggUid") or char:GetAttribute("Carrying")
        or LocalPlayer:GetAttribute("HoldingEgg") or LocalPlayer:GetAttribute("CarryingEgg") or LocalPlayer:GetAttribute("HasEgg")
    if holdingAttr then
        return true, tostring(holdingAttr)
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

-- 7. BANCO DE DADOS COMPLETO (MESHID -> MODELO -> ASSETS.DIRECTORY)
local MeshIdToEggModel = {}
local AssetsDirectoryData = {}
local AssetsByRarityData = {}
local RarityConfigs = {}

-- 1. Mapeamento de MeshId de ReplicatedStorage.AssetModels (117 modelos de ovos)
pcall(function()
    local am = Services.ReplicatedStorage:FindFirstChild("AssetModels")
    if am then
        for _, model in ipairs(am:GetChildren()) do
            for _, desc in ipairs(model:GetDescendants()) do
                if desc:IsA("MeshPart") and desc.MeshId ~= "" then
                    MeshIdToEggModel[desc.MeshId] = model.Name
                elseif desc:IsA("SpecialMesh") and desc.MeshId ~= "" then
                    MeshIdToEggModel[desc.MeshId] = model.Name
                end
            end
        end
    end
end)

-- 2. Carregar ReplicatedStorage.Data.Assets (Directory e ByRarity)
pcall(function()
    local dataFolder = Services.ReplicatedStorage:FindFirstChild("Data")
    if dataFolder then
        local assetsMod = dataFolder:FindFirstChild("Assets")
        if assetsMod and assetsMod:IsA("ModuleScript") then
            local res = require(assetsMod)
            if type(res) == "table" then
                AssetsDirectoryData = res.Directory or res
                AssetsByRarityData = res.ByRarity or {}
            end
        end
        local rarityMod = dataFolder:FindFirstChild("Rarity")
        if rarityMod and rarityMod:IsA("ModuleScript") then
            local rRes = require(rarityMod)
            if type(rRes) == "table" then
                RarityConfigs = rRes.Rarities or rRes
            end
        end
    end
end)

local function isHexUUID(str)
    if not str or #str < 18 then return false end
    local clean = str:gsub("-", "")
    return clean:match("^%x+$") ~= nil
end

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

local RarityScoreMap = {
    ["ADMIN ABUSE"] = 100000,
    ["MONSTER PARASITE"] = 85000,
    ["DRAGON"] = 75000,
    ["SAKURA"] = 65000,
    ["BRAINROT"] = 60000,
    ["LIMITED"] = 50000,
    ["SECRET"] = 45000,
    ["PREHISTORIC"] = 40000,
    ["ABYSS"] = 30000,
    ["VOLCANO"] = 22000,
    ["MÍTICO"] = 20000,
    ["MYTHIC"] = 20000,
    ["GOLDEN"] = 18000,
    ["RAINBOW"] = 25000,
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

local KeywordTranslations = {
    ["admin abuse"] = { Name = "Ovo Admin Abuse", Rarity = "ADMIN ABUSE" },
    ["monster parasite"] = { Name = "Ovo Parasita Monstro", Rarity = "MONSTER PARASITE" },
    ["dragon"] = { Name = "Ovo do Dragão", Rarity = "DRAGON" },
    ["sakura"] = { Name = "Ovo de Sakura", Rarity = "SAKURA" },
    ["brainrot"] = { Name = "Ovo Brainrot", Rarity = "BRAINROT" },
    ["limited"] = { Name = "Ovo Limitado", Rarity = "LIMITED" },
    ["secret"] = { Name = "Ovo Secreto", Rarity = "SECRET" },
    ["prehistoric"] = { Name = "Ovo Pré-Histórico", Rarity = "PREHISTORIC" },
    ["abyss"] = { Name = "Ovo do Abismo", Rarity = "ABYSS" },
    ["volcano"] = { Name = "Ovo do Vulcão", Rarity = "VOLCANO" },
    ["rainbow"] = { Name = "Ovo Arco-Íris", Rarity = "RAINBOW" },
    ["golden"] = { Name = "Ovo Dourado", Rarity = "GOLDEN" },
    ["mythic"] = { Name = "Ovo Mítico", Rarity = "MÍTICO" },
    ["legendary"] = { Name = "Ovo Lendário", Rarity = "LENDÁRIO" },
    ["cherry"] = { Name = "Ovo de Cerejeira", Rarity = "CHERRY" },
    ["epic"] = { Name = "Ovo Épico", Rarity = "ÉPICO" },
    ["forest"] = { Name = "Ovo da Floresta", Rarity = "FOREST" },
    ["rare"] = { Name = "Ovo Raro", Rarity = "RARO" },
    ["uncommon"] = { Name = "Ovo Incomum", Rarity = "INCOMUM" },
    ["common"] = { Name = "Ovo Comum", Rarity = "COMUM" }
}

local function formatDisplayName(raw)
    if not raw or raw == "" then return nil end
    local clean = tostring(raw):gsub("Egg", " Egg"):gsub("  ", " "):gsub("^%s+", "")
    for kw, tr in pairs(KeywordTranslations) do
        if clean:lower():find(kw, 1, true) then
            return tr.Name
        end
    end
    return clean
end

local function resolveEggDetails(instance, prompt)
    local pos = getPositionOf(prompt or instance)
    local foundName = nil
    local detectedRarity = "COMUM"
    local maxScore = 300
    local detectedWeight = 0
    local detectedIncome = nil

    local function inspectStr(s)
        if not s or s == "" then return end
        local low = tostring(s):lower()

        -- Consulta direta no Directory de Assets
        if AssetsDirectoryData[s] or AssetsDirectoryData[low] then
            local entry = AssetsDirectoryData[s] or AssetsDirectoryData[low]
            if type(entry) == "table" then
                if entry.DisplayName or entry.Name then
                    foundName = formatDisplayName(entry.DisplayName or entry.Name)
                end
                if entry.Rarity then
                    detectedRarity = tostring(entry.Rarity):upper()
                end
                if entry.Weight or entry.BaseWeight then
                    detectedWeight = tonumber(entry.Weight or entry.BaseWeight) or detectedWeight
                end
            end
        end

        -- Peso em Kg
        local kg = low:match("([%d%,%.]+)%s*kg")
        if kg then
            local n = tonumber((kg:gsub(",", "")))
            if n and n > detectedWeight then detectedWeight = n end
        end

        -- Renda $/s
        local num, suf = low:match("%$%s*([%d][%d%,%.]*)%s*(%a*)%s*/%s*s")
        if num and not detectedIncome then
            detectedIncome = "$" .. num .. (suf or ""):upper() .. "/s"
        end

        -- Palavras-chave
        for kw, meta in pairs(KeywordTranslations) do
            if low:find(kw, 1, true) then
                local sc = RarityScoreMap[meta.Rarity] or 5000
                if sc > maxScore then
                    maxScore = sc
                    detectedRarity = meta.Rarity
                    if not foundName or isHexUUID(foundName) or foundName:find("Ovo") == nil then
                        foundName = meta.Name
                    end
                end
            end
        end
    end

    -- 1. INSPEÇÃO POR MESHID (Identificação 100% Precisa do Modelo 3D)
    local function inspectMeshes(obj)
        if not obj then return end
        pcall(function()
            for _, desc in ipairs(obj:GetDescendants()) do
                local mId = (desc:IsA("MeshPart") and desc.MeshId) or (desc:IsA("SpecialMesh") and desc.MeshId)
                if mId and mId ~= "" and MeshIdToEggModel[mId] then
                    local modelName = MeshIdToEggModel[mId]
                    foundName = formatDisplayName(modelName)
                    inspectStr(modelName)
                    break
                end
            end
        end)
    end

    inspectMeshes(instance)

    -- 2. Inspeção em ClientRenderedAssets (Onde o jogo renderiza os ovos no cliente)
    pcall(function()
        if pos then
            local renderedFolder = Services.Workspace:FindFirstChild("ClientRenderedAssets")
            if renderedFolder then
                for _, rItem in ipairs(renderedFolder:GetChildren()) do
                    local isMatch = false
                    if rItem.Name == instance.Name then
                        isMatch = true
                    else
                        local rPos = getPositionOf(rItem)
                        if rPos then
                            local horizDist = (Vector2.new(rPos.X, rPos.Z) - Vector2.new(pos.X, pos.Z)).Magnitude
                            if horizDist <= 8 then
                                isMatch = true
                            end
                        end
                    end

                    if isMatch then
                        inspectMeshes(rItem)
                        if not foundName or isHexUUID(foundName) then
                            if not isHexUUID(rItem.Name) and rItem.Name ~= "Model" and rItem.Name ~= "MeshPart" then
                                foundName = formatDisplayName(rItem.Name)
                            end
                        end
                        inspectStr(rItem.Name)
                        for k, v in pairs(rItem:GetAttributes()) do
                            inspectStr(k); inspectStr(v)
                        end
                        for _, d in ipairs(rItem:GetDescendants()) do
                            if d:IsA("TextLabel") or d:IsA("TextButton") then
                                inspectStr(d.Text)
                            end
                        end
                        break
                    end
                end
            end
        end
    end)

    -- 3. Inspeção do Prompt
    if prompt then
        local pObj = prompt.ObjectText
        if pObj and pObj ~= "" and pObj:lower() ~= "egg" and pObj:lower() ~= "ovo" and pObj:lower() ~= "assets" and not isHexUUID(pObj) then
            foundName = formatDisplayName(pObj)
        end
        inspectStr(prompt.ObjectText)
        inspectStr(prompt.ActionText)
        inspectStr(prompt.Name)
        pcall(function()
            for k, v in pairs(prompt:GetAttributes()) do
                inspectStr(k); inspectStr(v)
            end
        end)
    end

    -- 4. Inspeção dos Atributos da Instância
    if instance then
        inspectStr(instance.Name)

        pcall(function()
            for k, v in pairs(instance:GetAttributes()) do
                if (k == "EggName" or k == "EggType" or k == "Egg" or k == "AssetId") and tostring(v) ~= "" and not isHexUUID(tostring(v)) then
                    foundName = formatDisplayName(tostring(v))
                end
                inspectStr(k); inspectStr(v)
            end
        end)

        pcall(function()
            for _, child in ipairs(instance:GetChildren()) do
                if child:IsA("Model") and not isHexUUID(child.Name) and child.Name ~= "Model" and child.Name ~= "Assets" then
                    foundName = formatDisplayName(child.Name)
                end
            end
        end)
    end

    -- 5. Fallback limpo caso o nome ainda seja genérico
    if not foundName or isHexUUID(foundName) or foundName:lower() == "egg" or foundName:lower() == "ovo" or foundName:lower() == "assets" or foundName:find("pcube") or foundName:find("polysurface") then
        local island = getIslandNameByPos(pos)
        foundName = "Ovo da " .. island
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
        elseif low:find("areaegg") or low:find("island") or low:find("zone") then
            local p = getPositionOf(instance)
            zone = getIslandNameByPos(p)
            break
        end
        cur = cur.Parent
    end
    return zone, owner
end

-- 8. Motor de Varredura Completa com Deduplicação e Vínculo de Prompt
local function scanAllEggs()
    local rawList = {}
    local hrp = getHRP()
    local myName = LocalPlayer.Name:lower()
    local myDisplay = LocalPlayer.DisplayName:lower()

    -- Coleta de todos os prompts de ovos no Workspace
    local promptsByPos = {}
    pcall(function()
        for _, desc in ipairs(Services.Workspace:GetDescendants()) do
            if desc:IsA("ProximityPrompt") then
                local pPos = getPositionOf(desc)
                if pPos then
                    table.insert(promptsByPos, { Prompt = desc, Position = pPos })
                end
            end
        end
    end)

    local function findClosestPrompt(pos, maxDist)
        maxDist = maxDist or 8
        local bestPrompt = nil
        local bestDist = maxDist
        for _, entry in ipairs(promptsByPos) do
            local d = (entry.Position - pos).Magnitude
            if d < bestDist then
                bestDist = d
                bestPrompt = entry.Prompt
            end
        end
        return bestPrompt
    end

    local function addCandidate(instance, prompt, sourceTag)
        if not instance then return end
        local pos = getPositionOf(prompt or instance)
        if not pos then return end

        -- Se não veio prompt direto, busca o prompt mais próximo num raio de 8 studs
        if not prompt then
            prompt = findClosestPrompt(pos, 8)
        end

        local fullName = instance:GetFullName():lower()
        local isMyPlot = (fullName:find(myName) ~= nil) or (fullName:find(myDisplay) ~= nil)
        local dist = hrp and (hrp.Position - pos).Magnitude or 0
        local cleanName, rarity, score, weight, income = resolveEggDetails(instance, prompt)
        local zone, owner = identifyZone(instance)

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

    -- 3. Prompts Gerais de Roubo do Workspace
    pcall(function()
        for _, desc in ipairs(Services.Workspace:GetDescendants()) do
            if desc:IsA("ProximityPrompt") then
                local act = plainText(desc.ActionText)
                local obj = plainText(desc.ObjectText)
                local isCand = act:find("steal") or act:find("roubar") or act:find("take") or act:find("pick")
                    or obj:find("egg") or obj:find("ovo") or desc.Name:lower():find("egg")

                if isCand and desc.Parent then
                    addCandidate(desc.Parent, desc, "Prompt Geral")
                end
            end
        end
    end)

    -- 4. Deduplicação Espacial (Agrupa candidatos dentro de 4 studs e prioriza o que tem Prompt)
    local deduplicated = {}
    for _, cand in ipairs(rawList) do
        local merged = false
        for _, existing in ipairs(deduplicated) do
            if (existing.Position - cand.Position).Magnitude <= 4.5 then
                merged = true
                -- Se o existente não tinha prompt e o novo tem, atualiza
                if not existing.Prompt and cand.Prompt then
                    existing.Prompt = cand.Prompt
                end
                -- Se o nome do existente for genérico e o novo tiver nome próprio, atualiza
                if (existing.Name:find("Ilha") or existing.Name == "Assets") and (not cand.Name:find("Ilha") and cand.Name ~= "Assets") then
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

    -- Ordenação: Maior raridade/score primeiro, depois menor distância
    table.sort(deduplicated, function(a, b)
        if a.RarityScore ~= b.RarityScore then
            return a.RarityScore > b.RarityScore
        end
        return a.Distance < b.Distance
    end)

    return deduplicated
end

-- 9. SISTEMA DE DESLOCAMENTO FÍSICO ANTI-ROLLBACK (BODYVELOCITY + BODYGYRO)
local isMoving = false

local function movePlayerTo(targetPos, speed, isReturningToBase, onStep)
    local hrp = getHRP()
    local char = LocalPlayer.Character
    if not hrp or not char or isMoving then return false end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return false end

    isMoving = true
    speed = speed or Config.MoveSpeed or 350
    local startPos = hrp.Position
    local totalDist = (targetPos - startPos).Magnitude

    if totalDist < 4 then
        isMoving = false
        return true
    end

    -- 1. Ativação Contínua de Noclip & CanTouch = false
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

    -- 2. Desativar física padrão do Humanoid
    pcall(function()
        humanoid.PlatformStand = true
        humanoid:ChangeState(Enum.HumanoidStateType.Physics)
    end)

    -- 3. Criação de Força Física (BodyVelocity + BodyGyro)
    -- Isso garante que a física do Roblox replique a movimentação como VOO natural
    -- impedindo que o script do jogo (WallEntryRollback) acione rollback ou mate o jogador!
    local bv = Instance.new("BodyVelocity")
    bv.Name = getRandomName()
    bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
    bv.Velocity = Vector3.zero
    bv.Parent = hrp

    local bg = Instance.new("BodyGyro")
    bg.Name = getRandomName()
    bg.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
    bg.CFrame = hrp.CFrame
    bg.Parent = hrp

    local function cleanup()
        pcall(function() if noclipConn then noclipConn:Disconnect() end end)
        pcall(function() if bv and bv.Parent then bv:Destroy() end end)
        pcall(function() if bg and bg.Parent then bg:Destroy() end end)
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

    -- 4. Definição de Waypoints com Elevação Anti-Parede
    -- No Roube um Ovo, as paredes entre as ilhas e os void death-zones ficam entre Y=65 e Y=80.
    -- Voar a Y ≈ 92 na ida permite passar por cima das paredes sem acionar o trigger horizontal de rollback!
    -- Na volta com ovo: sobe para Y >= 115 para segurança total.
    local waypoints = {}
    if isReturningToBase and totalDist > 20 then
        local safeY = math.max(startPos.Y, targetPos.Y) + 40
        if safeY < 115 then safeY = 115 end
        table.insert(waypoints, Vector3.new(startPos.X, safeY, startPos.Z))
        table.insert(waypoints, Vector3.new(targetPos.X, safeY, targetPos.Z))
        table.insert(waypoints, targetPos + Vector3.new(0, 3.5, 0))
    else
        -- Ida direta: se for entre ilhas (dist > 60), eleva a Y=92 para passar pelas paredes com segurança
        if totalDist > 60 then
            local clearY = math.max(startPos.Y, targetPos.Y) + 24
            if clearY < 92 then clearY = 92 end
            table.insert(waypoints, Vector3.new(startPos.X, clearY, startPos.Z))
            table.insert(waypoints, Vector3.new(targetPos.X, clearY, targetPos.Z))
            table.insert(waypoints, targetPos + Vector3.new(0, 2.0, 0))
        else
            table.insert(waypoints, targetPos + Vector3.new(0, 1.8, 0))
        end
    end

    -- 5. Execução por Força Física Ponto a Ponto
    for _, wp in ipairs(waypoints) do
        local wpStart = os.clock()
        local maxWpTime = (wp - hrp.Position).Magnitude / math.max(speed, 60) + 1.2

        while (os.clock() - wpStart) < maxWpTime do
            if not char or not char.Parent or not humanoid or humanoid.Health <= 0 then
                cleanup()
                return false
            end

            local delta = (wp - hrp.Position)
            local dist = delta.Magnitude

            if dist < 4 then break end

            local dir = delta.Unit
            bv.Velocity = dir * speed
            bg.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + dir)

            local distToFinal = (targetPos - hrp.Position).Magnitude
            if onStep then onStep(distToFinal) end

            Services.RunService.Heartbeat:Wait()
        end
    end

    bv.Velocity = Vector3.zero
    hrp.CFrame = CFrame.new(targetPos + Vector3.new(0, isReturningToBase and 3.5 or 1.8, 0))
    cleanup()
    return (targetPos - hrp.Position).Magnitude < 8
end

-- Acionamento Forçado de ProximityPrompt
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

-- 10. Dumper Exaustivo de Dados e Tabelas
local function dumpGameData()
    local lines = {}
    local function logL(s) table.insert(lines, s or "") end

    logL("================================================================================")
    logL("ROUBE UM OVO - INVENTARIO ESTRUTURAL COMPLETO (DUMP EXAUSTIVO v5.0)")
    logL("Data: " .. os.date("%Y-%m-%d %H:%M:%S") .. " | PlaceId: " .. tostring(game.PlaceId))
    logL("================================================================================\n")

    -- 1. Tabela Assets.Directory
    logL("[1] REPLICATEDSTORAGE.DATA.ASSETS.DIRECTORY (Todos os Ovos do Jogo):")
    pcall(function()
        local count = 0
        for eggKey, eggData in pairs(AssetsDirectoryData) do
            count = count + 1
            if count <= 40 then
                if type(eggData) == "table" then
                    logL(string.format("  - Chave: %s | DisplayName: %s | Rarity: %s | Weight: %s",
                        tostring(eggKey), tostring(eggData.DisplayName or eggData.Name),
                        tostring(eggData.Rarity), tostring(eggData.Weight or eggData.BaseWeight or "N/D")
                    ))
                else
                    logL(string.format("  - Chave: %s = %s", tostring(eggKey), tostring(eggData)))
                end
            end
        end
        logL("  Total de entradas no Directory: " .. tostring(count))
    end)
    logL("\n")

    -- 2. Tabela Rarity.Rarities
    logL("[2] REPLICATEDSTORAGE.DATA.RARITY.RARITIES:")
    pcall(function()
        for rKey, rData in pairs(RarityConfigs) do
            if type(rData) == "table" then
                logL(string.format("  - %s: %s", tostring(rKey), Services.HttpService:JSONEncode(rData)))
            else
                logL(string.format("  - %s = %s", tostring(rKey), tostring(rData)))
            end
        end
    end)
    logL("\n")

    -- 3. Mapeamento de Modelos em AssetModels
    logL("[3] REPLICATEDSTORAGE.ASSETMODELS (Amostra de Modelos e Meshes):")
    pcall(function()
        local am = Services.ReplicatedStorage:FindFirstChild("AssetModels")
        if am then
            logL("  Total de modelos em AssetModels: " .. tostring(#am:GetChildren()))
            for idx, m in ipairs(am:GetChildren()) do
                if idx <= 20 then
                    local meshIds = {}
                    for _, d in ipairs(m:GetDescendants()) do
                        if (d:IsA("MeshPart") or d:IsA("SpecialMesh")) and d.MeshId ~= "" then
                            table.insert(meshIds, d.MeshId:sub(-14))
                        end
                    end
                    logL(string.format("  - #%02d %s | Meshes: %s", idx, m.Name, table.concat(meshIds, ", ")))
                end
            end
        end
    end)
    logL("\n")

    -- 4. Ovos Detectados no Radar com Nomes Reais
    local discovered = scanAllEggs()
    logL("[4] LISTA DE OVOS DETECTADOS PELO RADAR (" .. tostring(#discovered) .. " ENCONTRADOS):")
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
    addLog("INSPETOR", "Dump exportado para ROUBE_UM_OVO_DUMP.txt (" .. tostring(#discovered) .. " ovos)!")
    return fullText, #discovered
end

-- 11. ESP Colorizado por Raridade Real
local activeESPs = {}
local function clearAllESP()
    for target, item in pairs(activeESPs) do
        pcall(function() if item and item.Parent then item:Destroy() end end)
    end
    activeESPs = {}
end

local RarityColors = {
    ["ADMIN ABUSE"] = Color3.fromRGB(239, 68, 68),
    ["MONSTER PARASITE"] = Color3.fromRGB(168, 85, 247),
    ["DRAGON"] = Color3.fromRGB(249, 115, 22),
    ["SAKURA"] = Color3.fromRGB(244, 114, 182),
    ["BRAINROT"] = Color3.fromRGB(34, 197, 94),
    ["LIMITED"] = Color3.fromRGB(234, 179, 8),
    ["SECRET"] = Color3.fromRGB(217, 70, 239),
    ["PREHISTORIC"] = Color3.fromRGB(245, 158, 11),
    ["ABYSS"] = Color3.fromRGB(59, 130, 246),
    ["VOLCANO"] = Color3.fromRGB(239, 68, 68),
    ["MÍTICO"] = Color3.fromRGB(236, 72, 153),
    ["MYTHIC"] = Color3.fromRGB(236, 72, 153),
    ["GOLDEN"] = Color3.fromRGB(250, 204, 21),
    ["RAINBOW"] = Color3.fromRGB(56, 189, 248),
    ["LENDÁRIO"] = Color3.fromRGB(245, 158, 11),
    ["LEGENDARY"] = Color3.fromRGB(245, 158, 11),
    ["CHERRY"] = Color3.fromRGB(251, 113, 133),
    ["ÉPICO"] = Color3.fromRGB(168, 85, 247),
    ["EPIC"] = Color3.fromRGB(168, 85, 247),
    ["FOREST"] = Color3.fromRGB(74, 222, 128),
    ["RARO"] = Color3.fromRGB(56, 189, 248),
    ["RARE"] = Color3.fromRGB(56, 189, 248),
    ["INCOMUM"] = Color3.fromRGB(148, 163, 184),
    ["UNCOMMON"] = Color3.fromRGB(148, 163, 184),
    ["COMUM"] = Color3.fromRGB(203, 213, 225),
    ["COMMON"] = Color3.fromRGB(203, 213, 225)
}

local function applyESP(target, text, rarity)
    if not target or not target.Parent or activeESPs[target] then return end
    local p = target:IsA("BasePart") and target or (target:IsA("Model") and (target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")))
    if not p then return end

    local color = RarityColors[rarity] or Color3.fromRGB(56, 189, 248)

    local bill = Instance.new("BillboardGui")
    bill.Name = getRandomName()
    bill.AlwaysOnTop = true
    bill.Size = UDim2.new(0, 195, 0, 24)
    bill.StudsOffset = Vector3.new(0, 2.8, 0)
    bill.Adornee = p

    local tag = Instance.new("TextLabel")
    tag.Size = UDim2.new(1, 0, 1, 0)
    tag.BackgroundColor3 = Color3.fromRGB(10, 14, 23)
    tag.BackgroundTransparency = 0.2
    tag.TextColor3 = color
    tag.TextSize = 11
    tag.Font = Enum.Font.GothamBold
    tag.Text = text
    tag.Parent = bill

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 4)
    c.Parent = tag

    local s = Instance.new("UIStroke")
    s.Color = color
    s.Transparency = 0.5
    s.Thickness = 1
    s.Parent = tag

    bill.Parent = p
    activeESPs[target] = bill

    target.AncestryChanged:Connect(function(_, parent)
        if not parent then
            pcall(function() bill:Destroy() end)
            activeESPs[target] = nil
        end
    end)
end

local function updateESP()
    if not Config.EggESP and not Config.PlayerESP then
        clearAllESP()
        return
    end

    pcall(function()
        local seen = {}
        local hrp = getHRP()

        if Config.EggESP then
            local eggs = scanAllEggs()
            for i = 1, math.min(#eggs, 40) do
                local e = eggs[i]
                if not e.IsMyPlot and e.Distance <= Config.ESPMaxDistance then
                    seen[e.Instance] = true
                    local wText = e.WeightKg > 0 and (" [" .. tostring(e.WeightKg) .. " Kg]") or (" [" .. e.Rarity .. "]")
                    local label = e.Name .. wText .. " (" .. math.floor(e.Distance) .. "m)"
                    applyESP(e.Instance, label, e.Rarity)
                end
            end
        end

        if Config.PlayerESP then
            for _, pl in ipairs(Services.Players:GetPlayers()) do
                if pl ~= LocalPlayer and pl.Character then
                    local pHrp = pl.Character:FindFirstChild("HumanoidRootPart")
                    if pHrp then
                        local dist = hrp and (hrp.Position - pHrp.Position).Magnitude or 0
                        seen[pl.Character] = true
                        applyESP(pl.Character, pl.DisplayName .. " (" .. math.floor(dist) .. "m)", "INCOMUM")
                    end
                end
            end
        end

        for target, item in pairs(activeESPs) do
            if not seen[target] then
                pcall(function() if item and item.Parent then item:Destroy() end end)
                activeESPs[target] = nil
            end
        end
    end)
end

-- 12. Construção da Interface (Tech Blue Minimalista em Português)
local TweenService = Services.TweenService
local UserInputService = Services.UserInputService

local C_BG       = Color3.fromRGB(10, 14, 23)
local C_SIDEBAR  = Color3.fromRGB(14, 19, 31)
local C_CARD     = Color3.fromRGB(18, 25, 41)
local C_BORDER   = Color3.fromRGB(30, 41, 59)
local C_ITEM_BG  = Color3.fromRGB(22, 32, 51)
local C_BLUE     = Color3.fromRGB(56, 189, 248)
local C_BLUE_DARK= Color3.fromRGB(14, 116, 144)
local C_TEXT     = Color3.fromRGB(248, 250, 252)
local C_TEXT_DIM = Color3.fromRGB(148, 163, 184)
local C_INACTIVE = Color3.fromRGB(51, 65, 85)

local function tw(obj, props, t)
    TweenService:Create(obj, TweenInfo.new(t or 0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function addCorner(parent, px)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, px or 6)
    c.Parent = parent
    return c
end

local function addStroke(parent, color, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color or C_BORDER
    s.Thickness = thickness or 1
    s.Parent = parent
    return s
end

local function addPadding(parent, t, b, l, r)
    local p = Instance.new("UIPadding")
    p.PaddingTop = UDim.new(0, t or 0)
    p.PaddingBottom = UDim.new(0, b or 0)
    p.PaddingLeft = UDim.new(0, l or 0)
    p.PaddingRight = UDim.new(0, r or 0)
    p.Parent = parent
    return p
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = getRandomName()
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset = true
protectGui(ScreenGui)
ScreenGui.Parent = getGuiContainer()

local MainFrame = Instance.new("Frame")
MainFrame.Name = getRandomName()
MainFrame.Size = UDim2.new(0, 750, 0, 510)
MainFrame.Position = UDim2.new(0.5, -375, 0.5, -255)
MainFrame.BackgroundColor3 = C_BG
MainFrame.BorderSizePixel = 0
MainFrame.Parent = ScreenGui
addCorner(MainFrame, 8)
addStroke(MainFrame, C_BORDER, 1)

-- Arrasto Suave
local dragging, dragInput, dragStart, startPos
local function makeDraggable(handle)
    handle.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = i.Position
            startPos = MainFrame.Position
            i.Changed:Connect(function()
                if i.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    handle.InputChanged:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch then
            dragInput = i
        end
    end)
end

UserInputService.InputChanged:Connect(function(i)
    if i == dragInput and dragging then
        local delta = i.Position - dragStart
        MainFrame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end)

-- Sidebar
local Sidebar = Instance.new("Frame")
Sidebar.Size = UDim2.new(0, 165, 1, 0)
Sidebar.BackgroundColor3 = C_SIDEBAR
Sidebar.BorderSizePixel = 0
Sidebar.Parent = MainFrame
addCorner(Sidebar, 8)

local SidebarPatch = Instance.new("Frame")
SidebarPatch.Size = UDim2.new(0, 10, 1, 0)
SidebarPatch.Position = UDim2.new(1, -10, 0, 0)
SidebarPatch.BackgroundColor3 = C_SIDEBAR
SidebarPatch.BorderSizePixel = 0
SidebarPatch.Parent = Sidebar
makeDraggable(Sidebar)

local Brand = Instance.new("Frame")
Brand.Size = UDim2.new(1, 0, 0, 50)
Brand.BackgroundTransparency = 1
Brand.Parent = Sidebar

local Tag = Instance.new("TextLabel")
Tag.Size = UDim2.new(1, -24, 0, 14)
Tag.Position = UDim2.new(0, 16, 0, 12)
Tag.BackgroundTransparency = 1
Tag.Text = "ROUBE UM OVO"
Tag.Font = Enum.Font.GothamBold
Tag.TextSize = 9.5
Tag.TextColor3 = C_TEXT_DIM
Tag.TextXAlignment = Enum.TextXAlignment.Left
Tag.Parent = Brand

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -24, 0, 20)
Title.Position = UDim2.new(0, 16, 0, 26)
Title.BackgroundTransparency = 1
Title.RichText = true
Title.Text = '<b>RADAR HUB</b> <font color="#38BDF8">v5.0</font>'
Title.Font = Enum.Font.GothamBold
Title.TextSize = 15.5
Title.TextColor3 = C_TEXT
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Brand

local NavList = Instance.new("Frame")
NavList.Size = UDim2.new(1, 0, 1, -110)
NavList.Position = UDim2.new(0, 0, 0, 58)
NavList.BackgroundTransparency = 1
NavList.Parent = Sidebar
addPadding(NavList, 6, 6, 10, 10)

local NavLayout = Instance.new("UIListLayout")
NavLayout.Padding = UDim.new(0, 4)
NavLayout.Parent = NavList

-- Perfil no Rodapé
local ProfileBar = Instance.new("Frame")
ProfileBar.Size = UDim2.new(1, -20, 0, 38)
ProfileBar.Position = UDim2.new(0, 10, 1, -46)
ProfileBar.BackgroundColor3 = C_ITEM_BG
ProfileBar.BorderSizePixel = 0
ProfileBar.Parent = Sidebar
addCorner(ProfileBar, 6)
addStroke(ProfileBar, C_BORDER, 1)

local AvatarImg = Instance.new("ImageLabel")
AvatarImg.Size = UDim2.new(0, 26, 0, 26)
AvatarImg.Position = UDim2.new(0, 6, 0.5, -13)
AvatarImg.BackgroundColor3 = C_BG
AvatarImg.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(LocalPlayer.UserId) .. "&w=100&h=100"
AvatarImg.Parent = ProfileBar
addCorner(AvatarImg, 13)

local UserNameLabel = Instance.new("TextLabel")
UserNameLabel.Size = UDim2.new(1, -40, 0, 14)
UserNameLabel.Position = UDim2.new(0, 38, 0, 5)
UserNameLabel.BackgroundTransparency = 1
UserNameLabel.Text = LocalPlayer.DisplayName
UserNameLabel.Font = Enum.Font.GothamBold
UserNameLabel.TextSize = 10.5
UserNameLabel.TextColor3 = C_TEXT
UserNameLabel.TextXAlignment = Enum.TextXAlignment.Left
UserNameLabel.TextTruncate = Enum.TextTruncate.AtEnd
UserNameLabel.Parent = ProfileBar

local StatusDot = Instance.new("TextLabel")
StatusDot.Size = UDim2.new(1, -40, 0, 12)
StatusDot.Position = UDim2.new(0, 38, 0, 19)
StatusDot.BackgroundTransparency = 1
StatusDot.RichText = true
StatusDot.Text = '<font color="#10B981">●</font> Voo Físico Ativo'
StatusDot.Font = Enum.Font.Gotham
StatusDot.TextSize = 9.5
StatusDot.TextColor3 = C_TEXT_DIM
StatusDot.TextXAlignment = Enum.TextXAlignment.Left
StatusDot.Parent = ProfileBar

-- TopBar
local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, -165, 0, 44)
TopBar.Position = UDim2.new(0, 165, 0, 0)
TopBar.BackgroundColor3 = C_BG
TopBar.BorderSizePixel = 0
TopBar.Parent = MainFrame
makeDraggable(TopBar)

local SearchBox = Instance.new("Frame")
SearchBox.Size = UDim2.new(1, -130, 0, 28)
SearchBox.Position = UDim2.new(0, 14, 0, 8)
SearchBox.BackgroundColor3 = C_ITEM_BG
SearchBox.Parent = TopBar
addCorner(SearchBox, 5)
addStroke(SearchBox, C_BORDER, 1)

local SearchInput = Instance.new("TextBox")
SearchInput.Size = UDim2.new(1, -16, 1, 0)
SearchInput.Position = UDim2.new(0, 8, 0, 0)
SearchInput.BackgroundTransparency = 1
SearchInput.PlaceholderText = "Filtrar por nome do ovo, ilha, peso ou raridade..."
SearchInput.PlaceholderColor3 = C_TEXT_DIM
SearchInput.Text = ""
SearchInput.Font = Enum.Font.Gotham
SearchInput.TextSize = 11
SearchInput.TextColor3 = C_TEXT
SearchInput.TextXAlignment = Enum.TextXAlignment.Left
SearchInput.ClearTextOnFocus = false
SearchInput.Parent = SearchBox

local RefreshBtn = Instance.new("TextButton")
RefreshBtn.Size = UDim2.new(0, 95, 0, 28)
RefreshBtn.Position = UDim2.new(1, -105, 0, 8)
RefreshBtn.BackgroundColor3 = C_BLUE_DARK
RefreshBtn.Text = "ATUALIZAR"
RefreshBtn.Font = Enum.Font.GothamBold
RefreshBtn.TextSize = 10.5
RefreshBtn.TextColor3 = C_TEXT
RefreshBtn.Parent = TopBar
addCorner(RefreshBtn, 5)

-- Container de Páginas
local PageContainer = Instance.new("Frame")
PageContainer.Size = UDim2.new(1, -165, 1, -44)
PageContainer.Position = UDim2.new(0, 165, 0, 44)
PageContainer.BackgroundTransparency = 1
PageContainer.Parent = MainFrame

local TabButtons = {}
local Pages = {}
local CurrentTab = nil

local function switchTab(id)
    if CurrentTab == id then return end
    CurrentTab = id
    for tabId, btn in pairs(TabButtons) do
        local active = (tabId == id)
        tw(btn, {
            BackgroundColor3 = active and Color3.fromRGB(30, 41, 59) or C_SIDEBAR,
            BackgroundTransparency = active and 0 or 1
        }, 0.12)
        local lbl = btn:FindFirstChild("Title")
        if lbl then tw(lbl, { TextColor3 = active and C_TEXT or C_TEXT_DIM }, 0.12) end
        local dot = btn:FindFirstChild("Dot")
        if dot then dot.Visible = active end
    end
    for pageId, page in pairs(Pages) do
        page.Visible = (pageId == id)
    end
end

local function addNavTab(id, titleText)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 32)
    btn.BackgroundColor3 = C_SIDEBAR
    btn.BackgroundTransparency = 1
    btn.Text = ""
    btn.Parent = NavList
    addCorner(btn, 5)

    local dot = Instance.new("Frame")
    dot.Name = "Dot"
    dot.Size = UDim2.new(0, 3, 0, 14)
    dot.Position = UDim2.new(0, 6, 0.5, -7)
    dot.BackgroundColor3 = C_BLUE
    dot.BorderSizePixel = 0
    dot.Visible = false
    dot.Parent = btn
    addCorner(dot, 2)

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, -22, 1, 0)
    title.Position = UDim2.new(0, 16, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = titleText
    title.Font = Enum.Font.GothamMedium
    title.TextSize = 11.5
    title.TextColor3 = C_TEXT_DIM
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
    pg.ScrollBarImageColor3 = C_BLUE
    pg.CanvasSize = UDim2.new(0, 0, 0, 0)
    pg.AutomaticCanvasSize = Enum.AutomaticSize.Y
    pg.Visible = false
    pg.Parent = PageContainer
    addPadding(pg, 8, 16, 12, 12)

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 10)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = pg

    Pages[id] = pg
    return pg
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

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 32)
    header.BackgroundTransparency = 1
    header.Parent = card

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -24, 1, 0)
    title.Position = UDim2.new(0, 12, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = titleText
    title.Font = Enum.Font.GothamBold
    title.TextSize = 11.5
    title.TextColor3 = C_TEXT
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header

    local body = Instance.new("Frame")
    body.Size = UDim2.new(1, 0, 0, 0)
    body.Position = UDim2.new(0, 0, 0, 32)
    body.AutomaticSize = Enum.AutomaticSize.Y
    body.BackgroundTransparency = 1
    body.Parent = card
    addPadding(body, 2, 10, 12, 12)

    local bodyLayout = Instance.new("UIListLayout")
    bodyLayout.Padding = UDim.new(0, 8)
    bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
    bodyLayout.Parent = body

    return body
end

local function addToggle(parent, labelText, defaultVal, callback)
    local state = defaultVal == true

    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 24)
    row.BackgroundTransparency = 1
    row.Parent = parent

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -44, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = labelText
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextSize = 11.5
    lbl.TextColor3 = C_TEXT
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 38, 0, 20)
    btn.Position = UDim2.new(1, -38, 0.5, -10)
    btn.BackgroundColor3 = state and C_BLUE or C_INACTIVE
    btn.Text = ""
    btn.Parent = row
    addCorner(btn, 10)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 16, 0, 16)
    knob.Position = state and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
    knob.BackgroundColor3 = C_TEXT
    knob.BorderSizePixel = 0
    knob.Parent = btn
    addCorner(knob, 8)

    btn.MouseButton1Click:Connect(function()
        state = not state
        tw(btn, { BackgroundColor3 = state and C_BLUE or C_INACTIVE }, 0.12)
        tw(knob, { Position = state and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8) }, 0.12)
        pcall(function() callback(state) end)
    end)
end

local function addSlider(parent, labelText, minV, maxV, defV, unit, callback)
    local val = math.clamp(defV or minV, minV, maxV)
    unit = unit or ""

    local cont = Instance.new("Frame")
    cont.Size = UDim2.new(1, 0, 0, 42)
    cont.BackgroundTransparency = 1
    cont.Parent = parent

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 18)
    header.BackgroundTransparency = 1
    header.Parent = cont

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -80, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = labelText
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextSize = 11.5
    lbl.TextColor3 = C_TEXT
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = header

    local badge = Instance.new("TextLabel")
    badge.Size = UDim2.new(0, 75, 1, 0)
    badge.Position = UDim2.new(1, -75, 0, 0)
    badge.BackgroundTransparency = 1
    badge.Text = tostring(val) .. " " .. unit
    badge.Font = Enum.Font.GothamBold
    badge.TextSize = 10.5
    badge.TextColor3 = C_BLUE
    badge.TextXAlignment = Enum.TextXAlignment.Right
    badge.Parent = header

    local track = Instance.new("TextButton")
    track.Size = UDim2.new(1, 0, 0, 4)
    track.Position = UDim2.new(0, 0, 0, 26)
    track.BackgroundColor3 = C_INACTIVE
    track.Text = ""
    track.AutoButtonColor = false
    track.Parent = cont
    addCorner(track, 2)

    local initR = math.clamp((val - minV) / (maxV - minV), 0, 1)
    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(initR, 0, 1, 0)
    fill.BackgroundColor3 = C_BLUE
    fill.BorderSizePixel = 0
    fill.Parent = track
    addCorner(fill, 2)

    local draggingSlider = false
    local function update(input)
        local ratio = math.clamp((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        fill.Size = UDim2.new(ratio, 0, 1, 0)
        val = math.floor(minV + (maxV - minV) * ratio)
        badge.Text = tostring(val) .. " " .. unit
        pcall(function() callback(val) end)
    end

    track.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            draggingSlider = true
            update(i)
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            draggingSlider = false
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if draggingSlider and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            update(i)
        end
    end)
end

local function addButton(parent, labelText, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 28)
    btn.BackgroundColor3 = C_ITEM_BG
    btn.Text = labelText
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 11.5
    btn.TextColor3 = C_TEXT
    btn.Parent = parent
    addCorner(btn, 5)
    addStroke(btn, C_BORDER, 1)

    btn.MouseEnter:Connect(function() tw(btn, { BackgroundColor3 = Color3.fromRGB(30, 41, 59) }, 0.1) end)
    btn.MouseLeave:Connect(function() tw(btn, { BackgroundColor3 = C_ITEM_BG }, 0.1) end)
    btn.MouseButton1Click:Connect(function() pcall(callback) end)
    return btn
end

--================================================================--
-- 1. ABA: RADAR (MONITOR DE OVOS EM TEMPO REAL)
--================================================================--

local RadarPage = createPage("Radar")

local StatusCard = createCard(RadarPage, "STATUS DO RADAR")
local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, 0, 0, 20)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "Iniciando varredura profunda com banco de dados do jogo..."
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextSize = 11
StatusLabel.TextColor3 = C_TEXT_DIM
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.Parent = StatusCard

local EggsCard = createCard(RadarPage, "OVOS DETECTADOS NO MAPA")
local EggListHolder = Instance.new("Frame")
EggListHolder.Size = UDim2.new(1, 0, 0, 0)
EggListHolder.AutomaticSize = Enum.AutomaticSize.Y
EggListHolder.BackgroundTransparency = 1
EggListHolder.Parent = EggsCard

local EggListLayout = Instance.new("UIListLayout")
EggListLayout.Padding = UDim.new(0, 6)
EggListLayout.SortOrder = Enum.SortOrder.LayoutOrder
EggListLayout.Parent = EggListHolder

local currentDiscovered = {}

local function renderRadarList(eggs)
    currentDiscovered = eggs or {}
    for _, child in ipairs(EggListHolder:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end

    local q = Config.SearchQuery:lower()
    local matched = 0

    for idx, e in ipairs(currentDiscovered) do
        local searchStr = (e.Name .. " " .. e.Rarity .. " " .. e.Zone .. " " .. tostring(e.WeightKg) .. " " .. (e.Source or "")):lower()
        if q == "" or searchStr:find(q, 1, true) then
            matched = matched + 1

            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, 0, 0, 52)
            row.BackgroundColor3 = C_ITEM_BG
            row.LayoutOrder = idx
            row.Parent = EggListHolder
            addCorner(row, 5)
            addStroke(row, C_BORDER, 1)

            -- Linha 1: Nome do Ovo + Raridade/Peso + Distância
            local title = Instance.new("TextLabel")
            title.Size = UDim2.new(1, -165, 0, 16)
            title.Position = UDim2.new(0, 8, 0, 6)
            title.BackgroundTransparency = 1
            title.RichText = true
            local wTag = e.WeightKg > 0 and (tostring(e.WeightKg) .. " Kg") or e.Rarity
            title.Text = string.format('<b>#%02d %s</b>  <font color="#38BDF8">[%s]</font>', idx, e.Name, wTag)
            title.Font = Enum.Font.GothamBold
            title.TextSize = 11.5
            title.TextColor3 = C_TEXT
            title.TextXAlignment = Enum.TextXAlignment.Left
            title.Parent = row

            local dist = Instance.new("TextLabel")
            dist.Size = UDim2.new(0, 75, 0, 16)
            dist.Position = UDim2.new(1, -245, 0, 6)
            dist.BackgroundTransparency = 1
            dist.Text = string.format("%d studs", math.floor(e.Distance))
            dist.Font = Enum.Font.GothamBold
            dist.TextSize = 10
            dist.TextColor3 = C_BLUE
            dist.TextXAlignment = Enum.TextXAlignment.Right
            dist.Parent = row

            -- Linha 2: Zona / Coordenadas / Origem / Status do Prompt
            local sub = Instance.new("TextLabel")
            sub.Size = UDim2.new(1, -165, 0, 16)
            sub.Position = UDim2.new(0, 8, 0, 26)
            sub.BackgroundTransparency = 1
            local promptTag = e.Prompt and "Coletável" or "Sem Prompt"
            sub.Text = string.format("Local: %s | (%.0f, %.0f, %.0f) | %s", e.Zone, e.Position.X, e.Position.Y, e.Position.Z, promptTag)
            sub.Font = Enum.Font.Code
            sub.TextSize = 9.5
            sub.TextColor3 = C_TEXT_DIM
            sub.TextXAlignment = Enum.TextXAlignment.Left
            sub.Parent = row

            -- Botão 1: Copiar Posição
            local copyBtn = Instance.new("TextButton")
            copyBtn.Size = UDim2.new(0, 72, 0, 22)
            copyBtn.Position = UDim2.new(1, -160, 0, 15)
            copyBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
            copyBtn.Text = "COPIAR POS"
            copyBtn.Font = Enum.Font.GothamBold
            copyBtn.TextSize = 9
            copyBtn.TextColor3 = C_TEXT
            copyBtn.Parent = row
            addCorner(copyBtn, 4)

            copyBtn.MouseButton1Click:Connect(function()
                local cStr = string.format("Vector3.new(%.1f, %.1f, %.1f)", e.Position.X, e.Position.Y, e.Position.Z)
                pcall(function()
                    if setclipboard then setclipboard(cStr) end
                end)
                copyBtn.Text = "COPIADO!"
                task.delay(1, function() copyBtn.Text = "COPIAR POS" end)
            end)

            -- Botão 2: Ir até o Ovo (Voo Físico Anti-Rollback)
            local gotoBtn = Instance.new("TextButton")
            gotoBtn.Size = UDim2.new(0, 78, 0, 22)
            gotoBtn.Position = UDim2.new(1, -82, 0, 15)
            gotoBtn.BackgroundColor3 = C_BLUE_DARK
            gotoBtn.Text = "IR ATE OVO"
            gotoBtn.Font = Enum.Font.GothamBold
            gotoBtn.TextSize = 9
            gotoBtn.TextColor3 = C_TEXT
            gotoBtn.Parent = row
            addCorner(gotoBtn, 4)

            gotoBtn.MouseButton1Click:Connect(function()
                task.spawn(function()
                    addLog("MOVIMENTO", "Iniciando voo físico até " .. e.Name .. " (" .. math.floor(e.Distance) .. " studs)...")
                    local ok = movePlayerTo(e.Position, Config.MoveSpeed, false)
                    if ok then
                        addLog("MOVIMENTO", "Chegou ao ovo! Tentando coletar...")
                        if e.Prompt then triggerPrompt(e.Prompt) end
                    else
                        addLog("MOVIMENTO", "Deslocamento finalizado.")
                    end
                end)
            end)
        end
    end

    StatusLabel.Text = string.format("Monitorando %d ovos no mapa (%d visíveis pelo filtro).", #currentDiscovered, matched)
end

local function executeRadarScan()
    StatusLabel.Text = "Executando varredura profunda de ovos..."
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

--================================================================--
-- 2. ABA: INSPETOR (EXTRAÇÃO EXAUSTIVA DO JOGO)
--================================================================--

local InspectorPage = createPage("Inspector")
local DumpCard = createCard(InspectorPage, "INSPETOR DE ARQUIVOS E DADOS INTERNOS")

local DumpDesc = Instance.new("TextLabel")
DumpDesc.Size = UDim2.new(1, 0, 0, 34)
DumpDesc.BackgroundTransparency = 1
DumpDesc.Text = "Exporta tabelas completas de ReplicatedStorage.Data (Assets.Directory, Rarity, Areas), modelos de AssetModels e slots mapeados para ROUBE_UM_OVO_DUMP.txt."
DumpDesc.Font = Enum.Font.Gotham
DumpDesc.TextSize = 11
DumpDesc.TextColor3 = C_TEXT_DIM
DumpDesc.TextWrapped = true
DumpDesc.TextXAlignment = Enum.TextXAlignment.Left
DumpDesc.Parent = DumpCard

local DumpStatus = Instance.new("TextLabel")
DumpStatus.Size = UDim2.new(1, 0, 0, 18)
DumpStatus.BackgroundTransparency = 1
DumpStatus.Text = "Status: Pronto para exportar inventário exaustivo."
DumpStatus.Font = Enum.Font.Code
DumpStatus.TextSize = 10.5
DumpStatus.TextColor3 = C_BLUE
DumpStatus.TextXAlignment = Enum.TextXAlignment.Left
DumpStatus.Parent = DumpCard

addButton(DumpCard, "EXPORTAR DUMP ESTRUTURAL (TXT NO DISCO & CLIPBOARD)", function()
    DumpStatus.Text = "Varrendo tabelas e módulos do jogo..."
    local text, count = dumpGameData()
    DumpStatus.Text = string.format("Salvo em ROUBE_UM_OVO_DUMP.txt (%d ovos documentados)!", count)
end)

--================================================================--
-- 3. ABA: AUTOMAÇÃO (VOO FÍSICO, POSSE DE OVO & ENTREGA NA BASE)
--================================================================--

local AutoPage = createPage("Automacao")
local AutoCard = createCard(AutoPage, "AUTOMAÇÃO INTELIGENTE DE ROUBO & ENTREGA")

addToggle(AutoCard, "Ativar Roubo Automático Inteligente", Config.AutoSteal, function(state)
    Config.AutoSteal = state
    if state then
        addLog("ROUBO", "Ciclo de roubo automático iniciado (Voo Físico Anti-Rollback).")
        task.spawn(function()
            while scriptActive and Config.AutoSteal do
                -- 1. Checar se já está segurando um ovo nas mãos / costas / mochila
                local holding, heldEggName = isHoldingEgg()
                if holding then
                    addLog("BASE", "Ovo detectado em mãos (" .. tostring(heldEggName) .. ")! Voando por cima até a base...")
                    local basePos = getBasePosition()
                    if basePos then
                        movePlayerTo(basePos + Vector3.new(0, 3.5, 0), Config.MoveSpeed, true)
                        
                        -- Aguardar na base até o ovo ser depositado no pedestal do plot
                        addLog("BASE", "Na base! Aguardando o jogo depositar o ovo no plot...")
                        local waitDeposit = 0
                        while scriptActive and Config.AutoSteal and waitDeposit < 10 do
                            task.wait(0.5)
                            waitDeposit = waitDeposit + 0.5
                            if not isHoldingEgg() then
                                addLog("BASE", "Ovo armazenado no plot da base com sucesso!")
                                break
                            end
                        end
                    end
                    task.wait(Config.StealDelay)
                else
                    -- 2. Não está com ovo: buscar ovos com Prompt VÁLIDO fora do meu plot
                    local eggs = scanAllEggs()
                    local validTargets = {}
                    for _, eg in ipairs(eggs) do
                        if not eg.IsMyPlot and eg.Prompt ~= nil then
                            table.insert(validTargets, eg)
                        end
                    end

                    if #validTargets > 0 then
                        local target = validTargets[1]
                        addLog("ROUBO", "Alvo selecionado: " .. target.Name .. " (" .. target.Rarity .. ") em " .. target.Zone)
                        
                        -- Deslocamento físico até o ovo
                        local arrived = movePlayerTo(target.Position, Config.MoveSpeed, false)
                        
                        local pickedUp = false
                        if arrived and target.Prompt then
                            addLog("ROUBO", "Chegou ao ovo! Tentando coletar...")
                            -- Tentativas contínuas de prompt com verificação
                            for attempt = 1, 8 do
                                if not scriptActive or not Config.AutoSteal then break end
                                if target.Prompt and target.Prompt.Parent then
                                    triggerPrompt(target.Prompt)
                                end
                                task.wait(0.35)
                                if isHoldingEgg() then
                                    pickedUp = true
                                    addLog("ROUBO", "Ovo em mãos! Iniciando voo por cima até a base...")
                                    break
                                end
                            end
                        end

                        -- SÓ retorna à base se realmente estiver segurando o ovo!
                        if pickedUp or isHoldingEgg() then
                            local basePos = getBasePosition()
                            if basePos then
                                addLog("BASE", "Retornando à base com voo por cima de obstáculos...")
                                movePlayerTo(basePos + Vector3.new(0, 3.5, 0), Config.MoveSpeed, true)

                                -- Aguardar depósito
                                local waitDeposit = 0
                                while scriptActive and Config.AutoSteal and waitDeposit < 10 do
                                    task.wait(0.5)
                                    waitDeposit = waitDeposit + 0.5
                                    if not isHoldingEgg() then
                                        addLog("BASE", "Ovo armazenado no plot da base!")
                                        break
                                    end
                                end
                            end
                        else
                            addLog("ROUBO", "Não foi possível coletar este ovo (em recarga ou protegido). Próximo alvo...")
                            task.wait(1)
                        end
                    else
                        addLog("ROUBO", "Nenhum ovo com prompt disponível fora da sua base.")
                        task.wait(2)
                    end
                end
                task.wait(Config.StealDelay)
            end
        end)
    else
        addLog("ROUBO", "Roubo automático desativado.")
    end
end)

addSlider(AutoCard, "Velocidade de Deslocamento", 100, 600, Config.MoveSpeed, "studs/s", function(val)
    Config.MoveSpeed = val
end)

addToggle(AutoCard, "Retornar à Base Após Coleta", Config.ReturnToBase, function(state)
    Config.ReturnToBase = state
end)

addButton(AutoCard, "REGISTRAR POSIÇÃO ATUAL COMO BASE", function()
    local hrp = getHRP()
    if hrp then
        Config.CustomBasePos = hrp.Position
        Config.SavedBasePos = hrp.Position
        addLog("BASE", string.format("Base fixada em: (%.1f, %.1f, %.1f)", hrp.Position.X, hrp.Position.Y, hrp.Position.Z))
    end
end)

addButton(AutoCard, "ROUBAR ALVO TOP 1 AGORA", function()
    task.spawn(function()
        local holding, heldName = isHoldingEgg()
        if holding then
            addLog("BASE", "Já está segurando um ovo (" .. tostring(heldName) .. ")! Entregue-o primeiro.")
            local basePos = getBasePosition()
            if basePos then movePlayerTo(basePos + Vector3.new(0, 3.5, 0), Config.MoveSpeed, true) end
            return
        end

        local eggs = scanAllEggs()
        local validTargets = {}
        for _, eg in ipairs(eggs) do
            if not eg.IsMyPlot and eg.Prompt ~= nil then table.insert(validTargets, eg) end
        end

        if #validTargets > 0 then
            local target = validTargets[1]
            addLog("ROUBO", "Indo até o alvo Top 1: " .. target.Name)
            local arrived = movePlayerTo(target.Position, Config.MoveSpeed, false)
            if arrived and target.Prompt then
                for attempt = 1, 6 do
                    triggerPrompt(target.Prompt)
                    task.wait(0.35)
                    if isHoldingEgg() then break end
                end
            end
            if isHoldingEgg() then
                local basePos = getBasePosition()
                if basePos then
                    addLog("BASE", "Retornando à base com voo por cima...")
                    movePlayerTo(basePos + Vector3.new(0, 3.5, 0), Config.MoveSpeed, true)
                end
            end
        else
            addLog("ROUBO", "Nenhum alvo Top 1 com prompt disponível.")
        end
    end)
end)

--================================================================--
-- 4. ABA: VISUAIS (MARCADORES 3D / ESP)
--================================================================--

local VisualsPage = createPage("Visuals")
local VisualsCard = createCard(VisualsPage, "MARCADORES NO MUNDO (ESP)")

addToggle(VisualsCard, "Ativar ESP de Ovos (Nome Real, Raridade e Distância)", Config.EggESP, function(state)
    Config.EggESP = state
    updateESP()
    addLog("ESP", "ESP de ovos " .. (state and "ativado." or "desativado."))
end)

addToggle(VisualsCard, "Ativar ESP de Jogadores", Config.PlayerESP, function(state)
    Config.PlayerESP = state
    updateESP()
end)

addSlider(VisualsCard, "Alcance Máximo do ESP", 200, 5000, Config.ESPMaxDistance, "studs", function(val)
    Config.ESPMaxDistance = val
    updateESP()
end)

addButton(VisualsCard, "LIMPAR TODOS OS MARCADORES DA TELA", function()
    clearAllESP()
    addLog("ESP", "Todos os marcadores foram removidos.")
end)

--================================================================--
-- 5. ABA: CONSOLE (REGISTROS INTERNOS)
--================================================================--

local ConsolePage = createPage("Console")
local ConsoleCard = createCard(ConsolePage, "TERMINAL DE TELEMETRIA LOCAL")

local ConsoleScroll = Instance.new("ScrollingFrame")
ConsoleScroll.Size = UDim2.new(1, 0, 0, 210)
ConsoleScroll.BackgroundColor3 = Color3.fromRGB(12, 16, 26)
ConsoleScroll.BorderSizePixel = 0
ConsoleScroll.ScrollBarThickness = 3
ConsoleScroll.ScrollBarImageColor3 = C_BLUE
ConsoleScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
ConsoleScroll.Parent = ConsoleCard
addCorner(ConsoleScroll, 5)
addStroke(ConsoleScroll, C_BORDER, 1)

local ConsoleText = Instance.new("TextLabel")
ConsoleText.Size = UDim2.new(1, -10, 1, -10)
ConsoleText.Position = UDim2.new(0, 5, 0, 5)
ConsoleText.BackgroundTransparency = 1
ConsoleText.TextColor3 = Color3.fromRGB(148, 163, 184)
ConsoleText.TextSize = 10
ConsoleText.Font = Enum.Font.Code
ConsoleText.TextXAlignment = Enum.TextXAlignment.Left
ConsoleText.TextYAlignment = Enum.TextYAlignment.Top
ConsoleText.Text = "=== TELEMETRIA INICIADA ==="
ConsoleText.Parent = ConsoleScroll

local function updateConsole()
    ConsoleText.Text = table.concat(LogHistory, "\n")
    ConsoleScroll.CanvasSize = UDim2.new(0, 0, 0, #LogHistory * 16 + 20)
end
_updateConsoleFunc = updateConsole
updateConsole()

addButton(ConsoleCard, "COPIAR LOGS PARA A ÁREA DE TRANSFERÊNCIA", function()
    pcall(function()
        if setclipboard then setclipboard(table.concat(LogHistory, "\n")) end
        addLog("SISTEMA", "Registros copiados para a área de transferência.")
    end)
end)

addButton(ConsoleCard, "LIMPAR HISTÓRICO", function()
    LogHistory = {}
    updateConsole()
end)

--================================================================--
-- 6. ABA: CONFIGURAÇÕES
--================================================================--

local SettingsPage = createPage("Settings")
local SettCard = createCard(SettingsPage, "CONFIGURAÇÕES GERAIS")

addToggle(SettCard, "Proteção Anti-AFK", Config.AntiAFK, function(state)
    Config.AntiAFK = state
end)

local KeyInfo = Instance.new("TextLabel")
KeyInfo.Size = UDim2.new(1, 0, 0, 20)
KeyInfo.BackgroundTransparency = 1
KeyInfo.Text = "Tecla de Atalho do Menu: [LeftControl]"
KeyInfo.Font = Enum.Font.GothamMedium
KeyInfo.TextSize = 11.5
KeyInfo.TextColor3 = C_TEXT
KeyInfo.TextXAlignment = Enum.TextXAlignment.Left
KeyInfo.Parent = SettCard

addButton(SettCard, "DESCARREGAR SCRIPT", function()
    scriptActive = false
    Config.AutoSteal = false
    clearAllESP()
    ScreenGui:Destroy()
end)

-- Montagem da Barra Lateral (100% em Português)
addNavTab("Radar", "RADAR")
addNavTab("Inspector", "INSPETOR")
addNavTab("Automacao", "AUTOMAÇÃO")
addNavTab("Visuals", "VISUAIS")
addNavTab("Console", "CONSOLE")
addNavTab("Settings", "CONFIGURAÇÕES")

-- Inicialização
switchTab("Radar")
task.delay(0.2, function()
    executeRadarScan()
end)

-- Atalho LeftControl
UserInputService.InputBegan:Connect(function(i, proc)
    if not proc and i.KeyCode == Enum.KeyCode.LeftControl then
        MainFrame.Visible = not MainFrame.Visible
    end
end)

-- Botão Flutuante Mobile
local MobileBtn = Instance.new("TextButton")
MobileBtn.Name = getRandomName()
MobileBtn.Size = UDim2.new(0, 32, 0, 32)
MobileBtn.Position = UDim2.new(0, 8, 0.4, 0)
MobileBtn.BackgroundColor3 = C_SIDEBAR
MobileBtn.Text = "RAD"
MobileBtn.Font = Enum.Font.GothamBold
MobileBtn.TextSize = 10.5
MobileBtn.TextColor3 = C_BLUE
MobileBtn.ZIndex = 1000
MobileBtn.Parent = ScreenGui
addCorner(MobileBtn, 6)
addStroke(MobileBtn, C_BLUE, 1)
makeDraggable(MobileBtn)

MobileBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

--[[
    ROUBE UM OVO - HUB DE TELEMETRIA & AUTOMAÇÃO (v5.5)
    -----------------------------------------------------------------------
    - Deslocamento Direto Rápido: Voo suave em linha reta (mesmo método original
      sem flutuação alta e sem deslizamento de física), com velocidade ajustável (400 studs/s).
    - Proteção Anti-Morte: Limite de alcance inteligente (MaxStealDistance = 350 studs)
      focando nos ovos da sua ilha/área aberta sem colidir nas barreiras trancadas de ilhas distantes.
    - Detecção Real de Posse de Ovo: Monitora atributos (EggUid, Carrying, Holding, HasEgg),
      modelos/meshes soldados ao corpo e desativação do prompt pós-coleta.
    - Ciclo de Roubo Seguro: Ao roubar, voa IMEDIATAMENTE para a base e aguarda o depósito.
    - Dumper Exaustivo: Desempacota tabelas de Assets.Directory, Rarity.Rarities, Areas, Guards,
      modelos e atributos completos em ROUBE_UM_OVO_DUMP.txt.
    - Zero prints para LogService, zero poluição global, interface Tech Blue (#38BDF8) sem emojis.
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
    ESPMaxDistance = 3500,

    AutoSteal = false,
    MoveSpeed = 400,
    MaxStealDistance = 350, -- Alcance seguro para não invadir ilhas trancadas
    StealDelay = 0.35,
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

-- DETECÇÃO ULTRA-AMPLA DE POSSE DE OVO (Atributos, Welds, Modelos e Menus)
local standardLimbNames = {
    ["head"] = true, ["upper_torso"] = true, ["lowertorso"] = true, ["uppertorso"] = true,
    ["humanoidrootpart"] = true, ["lefthand"] = true, ["righthand"] = true,
    ["leftlowerarm"] = true, ["rightlowerarm"] = true, ["leftupperarm"] = true, ["rightupperarm"] = true,
    ["leftfoot"] = true, ["rightfoot"] = true, ["leftlowerleg"] = true, ["rightlowerleg"] = true,
    ["leftupperleg"] = true, ["rightupperleg"] = true, ["torso"] = true, ["left arm"] = true,
    ["right arm"] = true, ["left leg"] = true, ["right leg"] = true, ["animate"] = true,
    ["humanoid"] = true
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

    -- 3. Objetos soldados ao tronco ou membros do personagem (o ovo carregado nas mãos/costas)
    for _, child in ipairs(char:GetChildren()) do
        local low = child.Name:lower()
        if not standardLimbNames[low] and not child:IsA("Accessory") and not child:IsA("Shirt") and not child:IsA("Pants") and not child:IsA("BodyColors") and not child:IsA("CharacterMesh") then
            if child:IsA("Tool") then
                return true, child.Name
            end
            if child:IsA("Model") or child:IsA("BasePart") then
                local hasWeld = child:FindFirstChildWhichIsA("WeldConstraint", true) or child:FindFirstChildWhichIsA("Weld", true) or child:FindFirstChildWhichIsA("Motor6D", true)
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

-- 7. BANCO DE DADOS DESEMPACOTADO DE REPLICATEDSTORAGE.DATA
local AssetsDirectoryData = {}
local RarityDataMap = {}
local MeshIdToEggMap = {}

-- 1. Carregar e desempacotar Assets.Directory
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
                    AssetsDirectoryData[tostring(k):lower()] = {
                        DisplayName = tostring(v.DisplayName or v.Name or k),
                        Rarity = rName,
                        Weight = tonumber(v.Weight or v.BaseWeight)
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

-- 2. Mapeamento de MeshId de AssetModels
pcall(function()
    local am = Services.ReplicatedStorage:FindFirstChild("AssetModels")
    if am then
        for _, m in ipairs(am:GetChildren()) do
            for _, d in ipairs(m:GetDescendants()) do
                local mId = (d:IsA("MeshPart") and d.MeshId) or (d:IsA("SpecialMesh") and d.MeshId)
                if mId and mId ~= "" then
                    MeshIdToEggMap[mId] = m.Name
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
    ["PREHISTORIC"] = 40000,
    ["ABYSS"] = 30000,
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

        if AssetsDirectoryData[low] then
            local entry = AssetsDirectoryData[low]
            foundName = entry.DisplayName
            detectedRarity = entry.Rarity
            maxScore = math.max(maxScore, RarityScoreMap[entry.Rarity] or 5000)
            if entry.Weight then detectedWeight = entry.Weight end
        end

        local kg = low:match("([%d%,%.]+)%s*kg")
        if kg then
            local n = tonumber((kg:gsub(",", "")))
            if n and n > detectedWeight then detectedWeight = n end
        end

        local num, suf = low:match("%$%s*([%d][%d%,%.]*)%s*(%a*)%s*/%s*s")
        if num and not detectedIncome then
            detectedIncome = "$" .. num .. (suf or ""):upper() .. "/s"
        end

        for rKey, score in pairs(RarityScoreMap) do
            if low:find(rKey:lower(), 1, true) then
                if score > maxScore then
                    maxScore = score
                    detectedRarity = rKey
                end
            end
        end
    end

    -- 1. Inspeção por MeshId
    pcall(function()
        for _, desc in ipairs(instance:GetDescendants()) do
            local mId = (desc:IsA("MeshPart") and desc.MeshId) or (desc:IsA("SpecialMesh") and desc.MeshId)
            if mId and mId ~= "" and MeshIdToEggMap[mId] then
                local modelName = MeshIdToEggMap[mId]
                inspectStr(modelName)
                foundName = modelName
                break
            end
        end
    end)

    -- 2. Inspeção do Prompt
    if prompt then
        local pObj = prompt.ObjectText
        if pObj and pObj ~= "" and pObj:lower() ~= "egg" and pObj:lower() ~= "ovo" and pObj:lower() ~= "assets" and not isHexUUID(pObj) then
            foundName = pObj
        end
        inspectStr(prompt.ObjectText)
        inspectStr(prompt.ActionText)
        pcall(function()
            for k, v in pairs(prompt:GetAttributes()) do inspectStr(k); inspectStr(v) end
        end)
    end

    -- 3. Inspeção do Slot
    if instance then
        inspectStr(instance.Name)
        pcall(function()
            for k, v in pairs(instance:GetAttributes()) do
                if (k == "EggName" or k == "EggType" or k == "Egg" or k == "AssetId") and tostring(v) ~= "" and not isHexUUID(tostring(v)) then
                    foundName = tostring(v)
                end
                inspectStr(k); inspectStr(v)
            end
        end)

        pcall(function()
            for _, child in ipairs(instance:GetChildren()) do
                if child:IsA("Model") and not isHexUUID(child.Name) and child.Name ~= "Model" and child.Name ~= "Assets" then
                    foundName = child.Name
                end
            end
        end)
    end

    -- 4. Fallback com Número do Slot da Ilha
    if not foundName or isHexUUID(foundName) or foundName:lower() == "egg" or foundName:lower() == "ovo" or foundName:lower() == "assets" or foundName:find("pcube") or foundName:find("polysurface") then
        local slotNum = instance and instance.Name:match("Slot_([%d]+)")
        local island = getIslandNameByPos(pos)
        if slotNum then
            foundName = "Ovo da " .. island .. " (Slot " .. slotNum .. ")"
        else
            foundName = "Ovo da " .. island
        end
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

-- 8. Scanner com Deduplicação e Vínculo de Prompts
local function scanAllEggs()
    local rawList = {}
    local hrp = getHRP()
    local myName = LocalPlayer.Name:lower()
    local myDisplay = LocalPlayer.DisplayName:lower()

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

    -- 3. Prompts Gerais do Workspace
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

    -- Deduplicação Espacial
    local deduplicated = {}
    for _, cand in ipairs(rawList) do
        local merged = false
        for _, existing in ipairs(deduplicated) do
            if (existing.Position - cand.Position).Magnitude <= 4.5 then
                merged = true
                if not existing.Prompt and cand.Prompt then
                    existing.Prompt = cand.Prompt
                end
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

    table.sort(deduplicated, function(a, b)
        if a.RarityScore ~= b.RarityScore then
            return a.RarityScore > b.RarityScore
        end
        return a.Distance < b.Distance
    end)

    return deduplicated
end

-- 9. VOO DIRETO SUAVE ORIGINAL (RÁPIDO, EM LINHA RETA, SEM SUBIR NO CÉU)
local isMoving = false

local function movePlayerTo(targetPos, speed, onStep)
    local hrp = getHRP()
    local char = LocalPlayer.Character
    if not hrp or not char or isMoving then return false end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return false end

    isMoving = true
    speed = speed or Config.MoveSpeed or 400
    local startPos = hrp.Position
    local dist = (targetPos - startPos).Magnitude

    if dist < 3.5 then
        isMoving = false
        return true
    end

    -- Ativação contínua de Noclip e CanTouch=false
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

    -- Interpolação suave direta em linha reta ("retão original")
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

-- 10. DUMPER ESTRUTURAL EXAUSTIVO DE TODOS OS ARQUIVOS E TABELAS
local function dumpGameData()
    local lines = {}
    local function logL(s) table.insert(lines, s or "") end

    logL("================================================================================")
    logL("ROUBE UM OVO - INVENTARIO ESTRUTURAL COMPLETO (EXAUSTIVO v5.5)")
    logL("Data: " .. os.date("%Y-%m-%d %H:%M:%S") .. " | PlaceId: " .. tostring(game.PlaceId))
    logL("================================================================================\n")

    -- 1. ReplicatedStorage.Data.Assets.Directory Completo
    logL("[1] REPLICATEDSTORAGE.DATA.ASSETS.DIRECTORY (Todos os 118 Pets/Ovos do Jogo):")
    pcall(function()
        for k, v in pairs(AssetsDirectoryData) do
            logL(string.format("  - Chave: %-25s | Display: %-20s | Raridade: %-12s | Peso: %s",
                tostring(k), tostring(v.DisplayName), tostring(v.Rarity), tostring(v.Weight or "N/D")
            ))
        end
    end)
    logL("\n")

    -- 2. ReplicatedStorage.Data.Rarity.Rarities
    logL("[2] REPLICATEDSTORAGE.DATA.RARITY.RARITIES (Configurações de Raridade):")
    pcall(function()
        for rKey, rVal in pairs(RarityDataMap) do
            logL(string.format("  - %s: %s", tostring(rKey), Services.HttpService:JSONEncode(rVal)))
        end
    end)
    logL("\n")

    -- 3. ReplicatedStorage.Data.Areas.Directory
    logL("[3] REPLICATEDSTORAGE.DATA.AREAS.DIRECTORY (Áreas e Ilhas do Jogo):")
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

    -- 4. ReplicatedStorage.Data.Guards.Directory (Os Guardas dos Ovos!)
    logL("[4] REPLICATEDSTORAGE.DATA.GUARDS.DIRECTORY (Guardas e Velocidades):")
    pcall(function()
        local dataF = Services.ReplicatedStorage:FindFirstChild("Data")
        if dataF then
            local gMod = dataF:FindFirstChild("Guards")
            if gMod and gMod:IsA("ModuleScript") then
                local res = require(gMod)
                if type(res) == "table" and res.Directory then
                    for gKey, gVal in pairs(res.Directory) do
                        logL(string.format("  - Guarda: %s | Dados: %s", tostring(gKey), Services.HttpService:JSONEncode(gVal)))
                    end
                end
            end
        end
    end)
    logL("\n")

    -- 5. Atributos do LocalPlayer e Character
    logL("[5] ESTADO DO JOGADOR LOCAL E CHARACTER:")
    pcall(function()
        logL("  DisplayName: " .. LocalPlayer.DisplayName .. " | Name: " .. LocalPlayer.Name)
        local char = LocalPlayer.Character
        if char then
            logL("  Atributos do Character:")
            for k, v in pairs(char:GetAttributes()) do
                logL(string.format("    > %s = %s", tostring(k), tostring(v)))
            end
            logL("  Filhos do Character:")
            for _, c in ipairs(char:GetChildren()) do
                logL(string.format("    > %s [%s]", c.Name, c.ClassName))
            end
        end
        logL("  Atributos do LocalPlayer:")
        for k, v in pairs(LocalPlayer:GetAttributes()) do
            logL(string.format("    > %s = %s", tostring(k), tostring(v)))
        end
    end)
    logL("\n")

    -- 6. Ovos Detectados
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
    ["SECRET"] = Color3.fromRGB(217, 70, 239),
    ["PREHISTORIC"] = Color3.fromRGB(245, 158, 11),
    ["ABYSS"] = Color3.fromRGB(59, 130, 246),
    ["VOLCANO"] = Color3.fromRGB(239, 68, 68),
    ["MÍTICO"] = Color3.fromRGB(236, 72, 153),
    ["MYTHIC"] = Color3.fromRGB(236, 72, 153),
    ["MYTHICAL"] = Color3.fromRGB(236, 72, 153),
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
Title.Text = '<b>RADAR HUB</b> <font color="#38BDF8">v5.5</font>'
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
StatusDot.Text = '<font color="#10B981">●</font> Voo Direto Ativo'
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
StatusLabel.Text = "Iniciando varredura com banco de dados desempacotado..."
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

            -- Botão 2: Ir até o Ovo (Voo Direto Suave Original)
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
                    addLog("MOVIMENTO", "Iniciando voo direto até " .. e.Name .. " (" .. math.floor(e.Distance) .. " studs)...")
                    local ok = movePlayerTo(e.Position, Config.MoveSpeed)
                    if ok then
                        addLog("MOVIMENTO", "Chegou ao ovo! Coletando...")
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
DumpDesc.Text = "Exporta tabelas completas de ReplicatedStorage.Data (Assets.Directory desempacotado com Raridade, Rarity, Areas, Guards) para ROUBE_UM_OVO_DUMP.txt."
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
-- 3. ABA: AUTOMAÇÃO (VOO DIRETO RÁPIDO & RETORNO SEGURO À BASE)
--================================================================--

local AutoPage = createPage("Automacao")
local AutoCard = createCard(AutoPage, "AUTOMAÇÃO INTELIGENTE DE ROUBO & ENTREGA")

addToggle(AutoCard, "Ativar Roubo Automático Inteligente", Config.AutoSteal, function(state)
    Config.AutoSteal = state
    if state then
        addLog("ROUBO", "Ciclo de roubo automático iniciado (Voo Direto Original).")
        task.spawn(function()
            while scriptActive and Config.AutoSteal do
                -- 1. Checar se já está com ovo na mão
                local holding, heldName = isHoldingEgg()
                if holding then
                    addLog("BASE", "Ovo detectado em mãos (" .. tostring(heldName) .. ")! Retornando à base...")
                    local basePos = getBasePosition()
                    if basePos then
                        movePlayerTo(basePos + Vector3.new(0, 3.0, 0), Config.MoveSpeed)
                        
                        -- Aguardar na base até o ovo ser depositado
                        addLog("BASE", "Na base! Aguardando o jogo depositar o ovo no plot...")
                        local waitDeposit = 0
                        while scriptActive and Config.AutoSteal and waitDeposit < 8 do
                            task.wait(0.4)
                            waitDeposit = waitDeposit + 0.4
                            if not isHoldingEgg() then
                                addLog("BASE", "Ovo armazenado no plot com sucesso!")
                                break
                            end
                        end
                    end
                    task.wait(Config.StealDelay)
                else
                    -- 2. Buscar ovos elegíveis dentro do alcance seguro da ilha atual
                    local eggs = scanAllEggs()
                    local validTargets = {}
                    for _, eg in ipairs(eggs) do
                        if not eg.IsMyPlot and eg.Prompt ~= nil and eg.Distance <= Config.MaxStealDistance then
                            table.insert(validTargets, eg)
                        end
                    end

                    if #validTargets > 0 then
                        local target = validTargets[1]
                        addLog("ROUBO", "Alvo selecionado: " .. target.Name .. " (" .. target.Rarity .. ") a " .. math.floor(target.Distance) .. "m")
                        
                        -- Voo direto rápido até o ovo
                        local arrived = movePlayerTo(target.Position, Config.MoveSpeed)
                        
                        local pickedUp = false
                        if arrived and target.Prompt then
                            addLog("ROUBO", "Chegou ao ovo! Coletando...")
                            local pInstance = target.Prompt
                            for attempt = 1, 8 do
                                if not scriptActive or not Config.AutoSteal then break end
                                triggerPrompt(pInstance)
                                task.wait(0.25)
                                if isHoldingEgg() or not pInstance.Parent or not pInstance.Enabled then
                                    pickedUp = true
                                    addLog("ROUBO", "Ovo coletado! Retornando imediatamente à base...")
                                    break
                                end
                            end
                        end

                        -- SÓ retorna à base se realmente tiver pego o ovo!
                        if pickedUp or isHoldingEgg() then
                            local basePos = getBasePosition()
                            if basePos then
                                addLog("BASE", "Retornando à base com o ovo...")
                                movePlayerTo(basePos + Vector3.new(0, 3.0, 0), Config.MoveSpeed)

                                -- Aguardar depósito
                                local waitDeposit = 0
                                while scriptActive and Config.AutoSteal and waitDeposit < 8 do
                                    task.wait(0.4)
                                    waitDeposit = waitDeposit + 0.4
                                    if not isHoldingEgg() then
                                        addLog("BASE", "Ovo armazenado no plot!")
                                        break
                                    end
                                end
                            end
                        else
                            addLog("ROUBO", "Ovo protegido ou em recarga. Buscando próximo alvo...")
                            task.wait(0.8)
                        end
                    else
                        addLog("ROUBO", "Nenhum ovo com prompt no alcance seguro (" .. tostring(Config.MaxStealDistance) .. "m).")
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

addSlider(AutoCard, "Alcance Máximo de Roubo Seguro", 100, 1500, Config.MaxStealDistance, "studs", function(val)
    Config.MaxStealDistance = val
    addLog("CONFIG", "Alcance seguro definido em " .. tostring(val) .. " studs.")
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
            if basePos then movePlayerTo(basePos + Vector3.new(0, 3.0, 0), Config.MoveSpeed) end
            return
        end

        local eggs = scanAllEggs()
        local validTargets = {}
        for _, eg in ipairs(eggs) do
            if not eg.IsMyPlot and eg.Prompt ~= nil and eg.Distance <= Config.MaxStealDistance then
                table.insert(validTargets, eg)
            end
        end

        if #validTargets > 0 then
            local target = validTargets[1]
            addLog("ROUBO", "Indo até o alvo Top 1: " .. target.Name)
            local arrived = movePlayerTo(target.Position, Config.MoveSpeed)
            if arrived and target.Prompt then
                for attempt = 1, 6 do
                    triggerPrompt(target.Prompt)
                    task.wait(0.25)
                    if isHoldingEgg() then break end
                end
            end
            if isHoldingEgg() then
                local basePos = getBasePosition()
                if basePos then
                    addLog("BASE", "Retornando à base com o ovo...")
                    movePlayerTo(basePos + Vector3.new(0, 3.0, 0), Config.MoveSpeed)
                end
            end
        else
            addLog("ROUBO", "Nenhum alvo no alcance seguro.")
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

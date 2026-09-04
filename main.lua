--[[
    ROUBE UM OVO - HUB DE TELEMETRIA & AUTOMAÇÃO (v4.0)
    -----------------------------------------------------------------------
    - Voo Aéreo Seguro Anti-Morte: Cruzeiro em alta altitude (Y >= 115) com
      CanTouch = false e CanCollide = false contínuos (100% imune a kill-bricks,
      lasers, espinhos, esteiras e void).
    - Resolução Real de Ovos: Eliminação total de hashes UUIDs (ex: 2e05e5...).
      Inspeção em camadas de ClientRenderedAssets, ReplicatedStorage.Data,
      atributos, meshes internas e mapeamento de ilhas em português.
    - Máquina de Estados de Posse (isHoldingEgg): Ao segurar ou roubar um ovo,
      o script retorna imediatamente à base e aguarda o depósito antes de
      buscar o próximo alvo.
    - Zero poluição de console (print/warn silenciados contra LogService).
    - Zero poluição de ambiente global (_G e getgenv limpos contra BAC).
    - Interface minimalista em português, tema Tech Blue (#38BDF8), sem emojis.
]]

-- 1. Silenciamento Preventivo Total contra LogService.MessageOut
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
    ESPMaxDistance = 3000,

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

-- Detecção Precisa de Posse de Ovo (Mãos / Costas / Mochila / Atributos)
local function isHoldingEgg()
    local char = LocalPlayer.Character
    if not char then return false, nil end

    -- 1. Ferramenta ativa no Personagem
    for _, item in ipairs(char:GetChildren()) do
        if item:IsA("Tool") then
            local n = item.Name:lower()
            return true, item.Name
        end
    end

    -- 2. Modelo soldado ao tronco do personagem (Mecânica de carregar nas mãos/costas)
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

-- 7. Resolução Avançada de Nomes Reais de Ovos & Dados Internos
local GameAssetsData = {}
local GameAreasData = {}
local GameRarityData = {}

pcall(function()
    local dataFolder = Services.ReplicatedStorage:FindFirstChild("Data")
    if dataFolder then
        local assetsMod = dataFolder:FindFirstChild("Assets")
        if assetsMod and assetsMod:IsA("ModuleScript") then
            local res = require(assetsMod)
            if type(res) == "table" then GameAssetsData = res end
        end
        local areasMod = dataFolder:FindFirstChild("Areas")
        if areasMod and areasMod:IsA("ModuleScript") then
            local res = require(areasMod)
            if type(res) == "table" then GameAreasData = res end
        end
        local rarityMod = dataFolder:FindFirstChild("Rarity")
        if rarityMod and rarityMod:IsA("ModuleScript") then
            local res = require(rarityMod)
            if type(res) == "table" then GameRarityData = res end
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

local KnownEggKeywords = {
    ["admin abuse"] = { Name = "Ovo Admin Abuse", Score = 100000, Rarity = "ADMIN ABUSE" },
    ["monster parasite"] = { Name = "Ovo Parasita Monstro", Score = 85000, Rarity = "MONSTER PARASITE" },
    ["dragon"] = { Name = "Ovo do Dragão", Score = 75000, Rarity = "DRAGON" },
    ["sakura"] = { Name = "Ovo de Sakura", Score = 65000, Rarity = "SAKURA" },
    ["brainrot"] = { Name = "Ovo Brainrot", Score = 60000, Rarity = "BRAINROT" },
    ["limited"] = { Name = "Ovo Limitado", Score = 50000, Rarity = "LIMITED" },
    ["prehistoric"] = { Name = "Ovo Pré-Histórico", Score = 40000, Rarity = "PREHISTORIC" },
    ["abyss"] = { Name = "Ovo do Abismo", Score = 30000, Rarity = "ABYSS" },
    ["volcano"] = { Name = "Ovo do Vulcão", Score = 22000, Rarity = "VOLCANO" },
    ["forest"] = { Name = "Ovo da Floresta", Score = 5000, Rarity = "FOREST" },
    ["cherry"] = { Name = "Ovo de Cerejeira", Score = 12000, Rarity = "CHERRY" },
    ["golden"] = { Name = "Ovo Dourado", Score = 18000, Rarity = "GOLDEN" },
    ["rainbow"] = { Name = "Ovo Arco-Íris", Score = 25000, Rarity = "RAINBOW" },
    ["secret"] = { Name = "Ovo Secreto", Score = 45000, Rarity = "SECRET" },
    ["mythic"] = { Name = "Ovo Mítico", Score = 20000, Rarity = "MÍTICO" },
    ["legendary"] = { Name = "Ovo Lendário", Score = 15000, Rarity = "LENDÁRIO" },
    ["epic"] = { Name = "Ovo Épico", Score = 8000, Rarity = "ÉPICO" },
    ["rare"] = { Name = "Ovo Raro", Score = 3500, Rarity = "RARO" },
    ["uncommon"] = { Name = "Ovo Incomum", Score = 1500, Rarity = "INCOMUM" },
    ["common"] = { Name = "Ovo Comum", Score = 300, Rarity = "COMUM" }
}

local function resolveEggDetails(instance, prompt)
    local pos = getPositionOf(prompt or instance)
    local foundName = nil
    local detectedRarity = "Comum"
    local maxScore = 300
    local detectedWeight = 0
    local detectedIncome = nil

    local function inspectStr(s)
        if not s or s == "" then return end
        local low = tostring(s):lower()

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

        -- Identificação por palavras-chave
        for kw, meta in pairs(KnownEggKeywords) do
            if low:find(kw, 1, true) then
                if meta.Score > maxScore then
                    maxScore = meta.Score
                    detectedRarity = meta.Rarity
                    if not foundName or isHexUUID(foundName) or foundName:find("Ovo") == nil then
                        foundName = meta.Name
                    end
                end
            end
        end
    end

    -- Camada 1: Localizar visual correspondente em ClientRenderedAssets
    pcall(function()
        if pos then
            local renderedFolder = Services.Workspace:FindFirstChild("ClientRenderedAssets")
            if renderedFolder then
                for _, renderItem in ipairs(renderedFolder:GetChildren()) do
                    local rPos = getPositionOf(renderItem)
                    if rPos and (rPos - pos).Magnitude <= 3.5 then
                        if not isHexUUID(renderItem.Name) and renderItem.Name ~= "Model" and renderItem.Name ~= "MeshPart" then
                            foundName = renderItem.Name
                        end
                        inspectStr(renderItem.Name)
                        for k, v in pairs(renderItem:GetAttributes()) do
                            inspectStr(k); inspectStr(v)
                        end
                        break
                    end
                end
            end
        end
    end)

    -- Camada 2: Inspecionar Prompt
    if prompt then
        local pObj = prompt.ObjectText
        if pObj and pObj ~= "" and pObj:lower() ~= "egg" and pObj:lower() ~= "ovo" and not isHexUUID(pObj) then
            foundName = pObj
        end
        inspectStr(prompt.ObjectText)
        inspectStr(prompt.ActionText)
        inspectStr(prompt.Name)
    end

    -- Camada 3: Inspecionar Instância, Atributos e Filhos
    if instance then
        inspectStr(instance.Name)

        pcall(function()
            for k, v in pairs(instance:GetAttributes()) do
                if (k == "EggName" or k == "EggType" or k == "Egg") and tostring(v) ~= "" and not isHexUUID(tostring(v)) then
                    foundName = tostring(v)
                end
                inspectStr(k); inspectStr(v)
            end
        end)

        pcall(function()
            for _, child in ipairs(instance:GetChildren()) do
                if child:IsA("Model") and not isHexUUID(child.Name) and child.Name ~= "Model" then
                    foundName = child.Name
                elseif child:IsA("MeshPart") and not isHexUUID(child.Name) and child.Name ~= "MeshPart" and child.Name ~= "Part" then
                    if not foundName then foundName = child.Name end
                elseif child:IsA("ValueBase") then
                    inspectStr(child.Name); inspectStr(child.Value)
                    if (child.Name:find("Egg") or child.Name:find("Name")) and tostring(child.Value) ~= "" and not isHexUUID(tostring(child.Value)) then
                        foundName = tostring(child.Value)
                    end
                end
            end
        end)

        pcall(function()
            local inspectedLabels = 0
            for _, d in ipairs(instance:GetDescendants()) do
                if inspectedLabels >= 30 then break end
                if d:IsA("TextLabel") or d:IsA("TextButton") then
                    inspectedLabels = inspectedLabels + 1
                    inspectStr(d.Text)
                end
            end
        end)
    end

    -- Camada 4: Mapeamento de nome de slot (ex: FirstAreaEgg_..._Forest:Slot_004)
    if not foundName or isHexUUID(foundName) then
        local rawName = instance and instance.Name or ""
        for kw, meta in pairs(KnownEggKeywords) do
            if rawName:lower():find(kw, 1, true) then
                foundName = meta.Name
                if meta.Score > maxScore then
                    maxScore = meta.Score
                    detectedRarity = meta.Rarity
                end
                break
            end
        end
    end

    -- Camada 5: Fallback Limpo por Ilha / Coordenadas (Zero hashes UUIDs)
    if not foundName or isHexUUID(foundName) or foundName:lower() == "egg" or foundName:lower() == "ovo" then
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

-- 8. Motor de Varredura Completa de Ovos
local function scanAllEggs()
    local discovered = {}
    local seenInstances = {}
    local hrp = getHRP()
    local myName = LocalPlayer.Name:lower()
    local myDisplay = LocalPlayer.DisplayName:lower()

    local function addCandidate(instance, prompt, sourceTag)
        if not instance or seenInstances[instance] then return end
        local pos = getPositionOf(prompt or instance)
        if not pos then return end
        seenInstances[instance] = true

        local fullName = instance:GetFullName():lower()
        local isMyPlot = (fullName:find(myName) ~= nil) or (fullName:find(myDisplay) ~= nil)
        local dist = hrp and (hrp.Position - pos).Magnitude or 0
        local cleanName, rarity, score, weight, income = resolveEggDetails(instance, prompt)
        local zone, owner = identifyZone(instance)

        table.insert(discovered, {
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

    -- 1. PlacedEggRenders (Ovos colocados nos pedestais dos plots)
    pcall(function()
        local placed = Services.Workspace:FindFirstChild("PlacedEggRenders")
        if placed then
            for _, egg in ipairs(placed:GetChildren()) do
                local p = egg:FindFirstChildWhichIsA("ProximityPrompt", true)
                addCandidate(egg, p, "Base/Plot")
            end
        end
    end)

    -- 2. AreaEggSlotsClient (Ovos nas ilhas do mapa)
    pcall(function()
        local areaSlots = Services.Workspace:FindFirstChild("AreaEggSlotsClient")
        if areaSlots then
            for _, slot in ipairs(areaSlots:GetChildren()) do
                local p = slot:FindFirstChildWhichIsA("ProximityPrompt", true)
                addCandidate(slot, p, "Ilha Selvagem")
            end
        end
    end)

    -- 3. Plots dos Jogadores
    pcall(function()
        local plots = Services.Workspace:FindFirstChild("Plots")
        if plots then
            for _, plot in ipairs(plots:GetChildren()) do
                for _, obj in ipairs(plot:GetDescendants()) do
                    if obj:IsA("ProximityPrompt") then
                        addCandidate(obj.Parent, obj, "Plot Prompt")
                    end
                end
            end
        end
    end)

    -- 4. Varredura Geral de ProximityPrompts do Workspace
    pcall(function()
        for _, desc in ipairs(Services.Workspace:GetDescendants()) do
            if desc:IsA("ProximityPrompt") then
                local act = plainText(desc.ActionText)
                local obj = plainText(desc.ObjectText)
                local isCandidate = act:find("steal") or act:find("roubar") or act:find("take") or act:find("pick")
                    or obj:find("egg") or obj:find("ovo") or desc.Name:lower():find("egg")

                if isCandidate and desc.Parent then
                    addCandidate(desc.Parent, desc, "Prompt Geral")
                end
            end
        end
    end)

    -- Ordenação por raridade/score e distância
    table.sort(discovered, function(a, b)
        if a.RarityScore ~= b.RarityScore then
            return a.RarityScore > b.RarityScore
        end
        return a.Distance < b.Distance
    end)

    return discovered
end

-- 9. SISTEMA DE VOO AÉREO SEGURO (ANTI-MORTE / IMUNIDADE A KILL BRICKS)
local isMoving = false

local function movePlayerTo(targetPos, speed, onStep)
    local hrp = getHRP()
    local char = LocalPlayer.Character
    if not hrp or not char or isMoving then return false end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return false end

    isMoving = true
    speed = speed or Config.MoveSpeed or 350
    local startPos = hrp.Position
    local totalDist = (targetPos - startPos).Magnitude

    if totalDist < 5 then
        isMoving = false
        return true
    end

    -- 1. Ativação Contínua de Noclip & Imunidade a Kill Bricks (CanTouch = false)
    -- Definir CanTouch = false a cada frame impede que scripts de Touch do jogo matem o personagem!
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

    -- 2. Congelar física do Humanoid para evitar dano de queda, tombos e flings
    pcall(function()
        humanoid.PlatformStand = true
        humanoid:ChangeState(Enum.HumanoidStateType.Physics)
    end)

    local function cleanup()
        pcall(function()
            if noclipConn then noclipConn:Disconnect() end
        end)
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

    -- 3. Definição da Trajetória em Arco Aéreo Seguro
    -- No Roube um Ovo, as ilhas e esteiras ficam entre Y=65 e Y=75.
    -- Voar a Y >= 115 garante céu 100% livre de qualquer obstáculo, void ou kill-brick.
    local waypoints = {}
    if totalDist > 25 then
        local safeY = math.max(startPos.Y, targetPos.Y) + 38
        if safeY < 115 then safeY = 115 end

        table.insert(waypoints, Vector3.new(startPos.X, safeY, startPos.Z))       -- Decolagem vertical
        table.insert(waypoints, Vector3.new(targetPos.X, safeY, targetPos.Z))      -- Cruzeiro em céu aberto
        table.insert(waypoints, targetPos + Vector3.new(0, 2.5, 0))                -- Descida sobre o alvo
    else
        table.insert(waypoints, targetPos + Vector3.new(0, 2, 0))
    end

    -- 4. Execução Ponto a Ponto Suave
    local currentPos = startPos
    for _, wp in ipairs(waypoints) do
        if not char or not char.Parent or not humanoid or humanoid.Health <= 0 then
            cleanup()
            return false
        end

        local segDist = (wp - currentPos).Magnitude
        local segTime = segDist / math.max(speed, 60)
        local segStartClock = os.clock()
        local segStartPos = currentPos

        while (os.clock() - segStartClock) < (segTime + 0.35) do
            if not char or not char.Parent or not humanoid or humanoid.Health <= 0 then
                cleanup()
                return false
            end

            local elapsed = os.clock() - segStartClock
            local alpha = math.clamp(elapsed / math.max(segTime, 0.001), 0, 1)
            local targetStep = segStartPos:Lerp(wp, alpha)

            local lookDir = (wp - segStartPos)
            if lookDir.Magnitude > 0.1 then
                hrp.CFrame = CFrame.new(targetStep, targetStep + lookDir)
            else
                hrp.CFrame = CFrame.new(targetStep)
            end
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero

            local distToFinal = (targetPos - hrp.Position).Magnitude
            if onStep then onStep(distToFinal) end

            if (wp - hrp.Position).Magnitude < 3 then
                break
            end

            Services.RunService.Heartbeat:Wait()
        end

        currentPos = hrp.Position
    end

    hrp.CFrame = CFrame.new(targetPos + Vector3.new(0, 2.5, 0))
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero

    cleanup()
    return (targetPos - hrp.Position).Magnitude < 12
end

-- Acionamento Seguro de ProximityPrompt
local function triggerPrompt(prompt)
    if not prompt then return false end
    local ok = false
    pcall(function()
        if fireproximityprompt then
            fireproximityprompt(prompt)
            ok = true
        else
            prompt:InputHoldBegin()
            task.wait(prompt.HoldDuration > 0 and (prompt.HoldDuration + 0.05) or 0.1)
            prompt:InputHoldEnd()
            ok = true
        end
    end)
    return ok
end

-- 10. Dumper Estrutural Profundo
local function dumpGameData()
    local lines = {}
    local function logL(s) table.insert(lines, s or "") end

    logL("================================================================================")
    logL("ROUBE UM OVO - INVENTARIO ESTRUTURAL COMPLETO (INSPECAO PROFUNDA)")
    logL("Data: " .. os.date("%Y-%m-%d %H:%M:%S") .. " | PlaceId: " .. tostring(game.PlaceId))
    logL("================================================================================\n")

    -- 1. PlacedEggRenders
    logL("[1] WORKSPACE.PLACEDEGGRENDERS (Ovos renderizados em plots):")
    pcall(function()
        local placed = Services.Workspace:FindFirstChild("PlacedEggRenders")
        if placed then
            logL("  Total de objetos: " .. tostring(#placed:GetChildren()))
            for _, egg in ipairs(placed:GetChildren()) do
                local pos = getPositionOf(egg)
                local posStr = pos and string.format("(%.1f, %.1f, %.1f)", pos.X, pos.Y, pos.Z) or "N/D"
                logL(string.format("  - %s [%s] | Pos: %s", egg.Name, egg.ClassName, posStr))
            end
        else
            logL("  (Pasta PlacedEggRenders nao encontrada)")
        end
    end)
    logL("\n")

    -- 2. AreaEggSlotsClient
    logL("[2] WORKSPACE.AREAEGGSLOTSCLIENT (Slots de ovos de area/ilha):")
    pcall(function()
        local slots = Services.Workspace:FindFirstChild("AreaEggSlotsClient")
        if slots then
            logL("  Total de slots: " .. tostring(#slots:GetChildren()))
            for _, s in ipairs(slots:GetChildren()) do
                local pos = getPositionOf(s)
                local posStr = pos and string.format("(%.1f, %.1f, %.1f)", pos.X, pos.Y, pos.Z) or "N/D"
                local cleanName = resolveEggDetails(s, nil)
                logL(string.format("  - %s (Nome: %s) [%s] | Pos: %s", s.Name, cleanName, s.ClassName, posStr))
            end
        else
            logL("  (Pasta AreaEggSlotsClient nao encontrada)")
        end
    end)
    logL("\n")

    -- 3. Modulos de ReplicatedStorage.Data
    logL("[3] REPLICATEDSTORAGE.DATA (Módulos e Tabelas do Jogo):")
    pcall(function()
        local dataF = Services.ReplicatedStorage:FindFirstChild("Data")
        if dataF then
            for _, mod in ipairs(dataF:GetChildren()) do
                logL("  - " .. mod.Name .. " [" .. mod.ClassName .. "]")
            end
        end
    end)
    logL("\n")

    -- 4. Ovos Detectados no Radar Atual
    local discovered = scanAllEggs()
    logL("[4] LISTA DE OVOS DETECTADOS PELO RADAR (" .. tostring(#discovered) .. " ENCONTRADOS):")
    for i, e in ipairs(discovered) do
        logL(string.format("#%02d [%s] %s | Origem: %s | Zona: %s | Pos: (%.1f, %.1f, %.1f) | Dist: %dm | Peso: %s | Renda: %s",
            i, e.Rarity, e.Name, e.Source, e.Zone, e.Position.X, e.Position.Y, e.Position.Z, math.floor(e.Distance),
            e.WeightKg > 0 and (tostring(e.WeightKg) .. " Kg") or "N/D", e.Income or "N/D"
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

-- 11. ESP Leve e Discreto (Sem Emojis)
local activeESPs = {}
local function clearAllESP()
    for target, item in pairs(activeESPs) do
        pcall(function() if item and item.Parent then item:Destroy() end end)
    end
    activeESPs = {}
end

local function applyESP(target, text, color)
    if not target or not target.Parent or activeESPs[target] then return end
    local p = target:IsA("BasePart") and target or (target:IsA("Model") and (target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")))
    if not p then return end

    local bill = Instance.new("BillboardGui")
    bill.Name = getRandomName()
    bill.AlwaysOnTop = true
    bill.Size = UDim2.new(0, 190, 0, 24)
    bill.StudsOffset = Vector3.new(0, 2.5, 0)
    bill.Adornee = p

    local tag = Instance.new("TextLabel")
    tag.Size = UDim2.new(1, 0, 1, 0)
    tag.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
    tag.BackgroundTransparency = 0.25
    tag.TextColor3 = color or Color3.fromRGB(56, 189, 248)
    tag.TextSize = 11
    tag.Font = Enum.Font.GothamBold
    tag.Text = text
    tag.Parent = bill

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 4)
    c.Parent = tag

    local s = Instance.new("UIStroke")
    s.Color = color or Color3.fromRGB(56, 189, 248)
    s.Transparency = 0.6
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
            for i = 1, math.min(#eggs, 35) do
                local e = eggs[i]
                if not e.IsMyPlot and e.Distance <= Config.ESPMaxDistance then
                    seen[e.Instance] = true
                    local wText = e.WeightKg > 0 and (" [" .. tostring(e.WeightKg) .. " Kg]") or (" [" .. e.Rarity .. "]")
                    local label = e.Name .. wText .. " (" .. math.floor(e.Distance) .. "m)"
                    applyESP(e.Instance, label, Color3.fromRGB(56, 189, 248))
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
                        applyESP(pl.Character, pl.DisplayName .. " (" .. math.floor(dist) .. "m)", Color3.fromRGB(148, 163, 184))
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
Title.Text = '<b>RADAR HUB</b> <font color="#38BDF8">v4.0</font>'
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
StatusDot.Text = '<font color="#10B981">●</font> Voo Seguro Ativo'
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
StatusLabel.Text = "Iniciando varredura passiva com resolução avançada de nomes..."
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

            -- Linha 2: Zona / Coordenadas / Origem
            local sub = Instance.new("TextLabel")
            sub.Size = UDim2.new(1, -165, 0, 16)
            sub.Position = UDim2.new(0, 8, 0, 26)
            sub.BackgroundTransparency = 1
            sub.Text = string.format("Local: %s | (%.0f, %.0f, %.0f) | %s", e.Zone, e.Position.X, e.Position.Y, e.Position.Z, e.Source or "")
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

            -- Botão 2: Ir até o Ovo (Voo Aéreo Seguro Anti-Morte)
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
                    addLog("MOVIMENTO", "Iniciando voo seguro ate " .. e.Name .. " (" .. math.floor(e.Distance) .. " studs)...")
                    local ok = movePlayerTo(e.Position + Vector3.new(0, 2.5, 0), Config.MoveSpeed)
                    if ok then
                        addLog("MOVIMENTO", "Chegou ao destino! Tentando coletar...")
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
-- 2. ABA: INSPETOR (EXTRAÇÃO DE ARQUIVOS E DADOS DO JOGO)
--================================================================--

local InspectorPage = createPage("Inspector")
local DumpCard = createCard(InspectorPage, "INSPETOR DE ARQUIVOS E DADOS INTERNOS")

local DumpDesc = Instance.new("TextLabel")
DumpDesc.Size = UDim2.new(1, 0, 0, 34)
DumpDesc.BackgroundTransparency = 1
DumpDesc.Text = "Analisa ReplicatedStorage.Data, PlacedEggRenders, AreaEggSlotsClient e ClientRenderedAssets para gerar inventário completo com nomes reais."
DumpDesc.Font = Enum.Font.Gotham
DumpDesc.TextSize = 11
DumpDesc.TextColor3 = C_TEXT_DIM
DumpDesc.TextWrapped = true
DumpDesc.TextXAlignment = Enum.TextXAlignment.Left
DumpDesc.Parent = DumpCard

local DumpStatus = Instance.new("TextLabel")
DumpStatus.Size = UDim2.new(1, 0, 0, 18)
DumpStatus.BackgroundTransparency = 1
DumpStatus.Text = "Status: Pronto para exportar inventário estrutural."
DumpStatus.Font = Enum.Font.Code
DumpStatus.TextSize = 10.5
DumpStatus.TextColor3 = C_BLUE
DumpStatus.TextXAlignment = Enum.TextXAlignment.Left
DumpStatus.Parent = DumpCard

addButton(DumpCard, "EXPORTAR DUMP ESTRUTURAL (TXT NO DISCO & CLIPBOARD)", function()
    DumpStatus.Text = "Varrendo instâncias do jogo..."
    local text, count = dumpGameData()
    DumpStatus.Text = string.format("Salvo em ROUBE_UM_OVO_DUMP.txt (%d ovos documentados)!", count)
end)

--================================================================--
-- 3. ABA: AUTOMAÇÃO (VOO SEGURO, POSSE DE OVO & ENTREGA NA BASE)
--================================================================--

local AutoPage = createPage("Automacao")
local AutoCard = createCard(AutoPage, "AUTOMAÇÃO INTELIGENTE DE ROUBO & ENTREGA")

addToggle(AutoCard, "Ativar Roubo Automático Inteligente", Config.AutoSteal, function(state)
    Config.AutoSteal = state
    if state then
        addLog("ROUBO", "Ciclo de roubo automático iniciado com verificação de posse.")
        task.spawn(function()
            while scriptActive and Config.AutoSteal do
                -- 1. Checar se já está segurando um ovo nas mãos / costas / mochila
                local holding, heldEggName = isHoldingEgg()
                if holding then
                    addLog("BASE", "Ovo detectado em mãos (" .. tostring(heldEggName) .. ")! Priorizando entrega na base...")
                    local basePos = getBasePosition()
                    if basePos then
                        movePlayerTo(basePos + Vector3.new(0, 3.5, 0), Config.MoveSpeed)
                        
                        -- Aguardar na base até o ovo ser depositado no pedestal do plot
                        local waitDeposit = 0
                        while scriptActive and Config.AutoSteal and waitDeposit < 8 do
                            task.wait(0.5)
                            waitDeposit = waitDeposit + 0.5
                            if not isHoldingEgg() then
                                addLog("BASE", "Ovo depositado com sucesso no pedestal da base!")
                                break
                            end
                        end
                    end
                    task.wait(Config.StealDelay)
                else
                    -- 2. Não está com ovo: buscar alvos externos elegíveis
                    local eggs = scanAllEggs()
                    local validTargets = {}
                    for _, eg in ipairs(eggs) do
                        if not eg.IsMyPlot then
                            table.insert(validTargets, eg)
                        end
                    end

                    if #validTargets > 0 then
                        local target = validTargets[1]
                        addLog("ROUBO", "Alvo selecionado: " .. target.Name .. " (" .. target.Rarity .. ") em " .. target.Zone)
                        local arrived = movePlayerTo(target.Position + Vector3.new(0, 2.5, 0), Config.MoveSpeed)
                        
                        if arrived and target.Prompt then
                            addLog("ROUBO", "Acionando coleta do ovo...")
                            triggerPrompt(target.Prompt)

                            -- Aguardar até 2.5s para confirmação da posse do ovo
                            local waitPick = 0
                            while waitPick < 2.5 do
                                task.wait(0.2)
                                waitPick = waitPick + 0.2
                                if isHoldingEgg() then
                                    addLog("ROUBO", "Ovo em mãos! Iniciando retorno imediato à base...")
                                    break
                                end
                            end
                        end

                        -- Retornar à base se pegou o ovo ou se ReturnToBase estiver ativo
                        if isHoldingEgg() or Config.ReturnToBase then
                            local basePos = getBasePosition()
                            if basePos then
                                addLog("BASE", "Retornando à base com voo seguro...")
                                movePlayerTo(basePos + Vector3.new(0, 3.5, 0), Config.MoveSpeed)

                                -- Aguardar depósito
                                local waitDeposit = 0
                                while scriptActive and Config.AutoSteal and waitDeposit < 8 do
                                    task.wait(0.5)
                                    waitDeposit = waitDeposit + 0.5
                                    if not isHoldingEgg() then
                                        addLog("BASE", "Ovo armazenado no plot!")
                                        break
                                    end
                                end
                            end
                        end
                    else
                        addLog("ROUBO", "Nenhum ovo de outros jogadores ou ilhas disponível.")
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
            if basePos then movePlayerTo(basePos + Vector3.new(0, 3.5, 0), Config.MoveSpeed) end
            return
        end

        local eggs = scanAllEggs()
        local validTargets = {}
        for _, eg in ipairs(eggs) do
            if not eg.IsMyPlot then table.insert(validTargets, eg) end
        end

        if #validTargets > 0 then
            local target = validTargets[1]
            addLog("ROUBO", "Indo até o alvo Top 1: " .. target.Name)
            local arrived = movePlayerTo(target.Position + Vector3.new(0, 2.5, 0), Config.MoveSpeed)
            if arrived and target.Prompt then
                triggerPrompt(target.Prompt)
                task.wait(0.5)
            end
            if Config.ReturnToBase or isHoldingEgg() then
                local basePos = getBasePosition()
                if basePos then
                    addLog("BASE", "Retornando à base...")
                    movePlayerTo(basePos + Vector3.new(0, 3.5, 0), Config.MoveSpeed)
                end
            end
        else
            addLog("ROUBO", "Nenhum alvo Top 1 disponível.")
        end
    end)
end)

--================================================================--
-- 4. ABA: VISUAIS (MARCADORES 3D / ESP)
--================================================================--

local VisualsPage = createPage("Visuals")
local VisualsCard = createCard(VisualsPage, "MARCADORES NO MUNDO (ESP)")

addToggle(VisualsCard, "Ativar ESP de Ovos (Mostra Nome Real, Peso e Distância)", Config.EggESP, function(state)
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

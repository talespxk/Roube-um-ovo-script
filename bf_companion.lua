--[[
    AUTO ESTEIRA - ASSISTENTE DE VELOCIDADE (v3.5 CORRIDA COM OVO & SPRINT SEM PARAR)
    -----------------------------------------------------------------------
    - Suporte a Treino na Esteira Segurando Ovo:
      * Se o BF roubar um ovo, chegar na base e os ninhos estiverem cheios, o BF para com o ovo na mao.
      * Apos 2.0s parado com o ovo, o companion assume e conduz o jogador ate a esteira de anjo.
      * O personagem corre e treina velocidade na esteira SEGURANDO O OVO sem conflito!
      * Caso o BF retome qualquer acao (ninho liberado, andar ou voar), o script cede o controle instantaneamente.
    - Zero Falso-Positivo na Deteccao do BF:
      * Removidas travas de switches globais estaticos (AutoSteal_Active/BF_Active) que travavam o script.
      * Checagem fisica real de forca em BodyVelocity/LinearVelocity (ignora AlignOrientation de rotacao).
      * Ignora ferramentas na mochila (apenas checa ovos fisicamente equipados no corpo).
    - Movimentacao Fluida de Alta Frequencia em Heartbeat:
      * Pathfinding assincrono seguro via task.spawn (zero erros de C-call boundary).
      * Humanoid:Move continuo mantem o personagem correndo a toda velocidade sem "passinhos".
      * Na esteira, a corrida e mantida a 60 FPS ininterruptos.
    - Sensores 3D com Raycast Inteligente:
      * Sensores ignoram o proprio personagem e ferramentas/ovos nas maos.
      * Pulinho proativo em cercas e bordas; desvio suave de quinas e paredes.
    - Corredores das 11 Ilhas:
      * Se o jogador estiver em qualquer ilha distante, trajeto segmentado conduz com seguranca ate a base.
]]

-- 1. Silenciamento Total Preventivo contra LogService.MessageOut
local function silentOutput(...) end
local print = silentOutput
local warn = silentOutput

-- 2. Limpeza de Instancias Anteriores
pcall(function()
    _G.AutoEsteira_Active = nil
    if getgenv then getgenv().AutoEsteira_Active = nil end
end)

-- 3. Limpeza Preventiva de Arquivos Residuais de Auto-Execute
pcall(function()
    if isfile and delfile then
        local residualPaths = {
            "autoexec/bf_companion_auto.lua",
            "autoexec/bf_companion.lua",
            "autoexec/auto_esteira.lua",
            "autoexec/companion.lua",
            "bf_companion_auto.lua"
        }
        for _, path in ipairs(residualPaths) do
            if isfile(path) then
                delfile(path)
            end
        end
    end
end)

-- 4. Servicos Seguros via cloneref
local function safeService(name)
    local s = game:GetService(name)
    return (cloneref and cloneref(s)) or s
end

local Services = {
    Workspace = safeService("Workspace"),
    Players = safeService("Players"),
    RunService = safeService("RunService"),
    UserInputService = safeService("UserInputService"),
    HttpService = safeService("HttpService"),
    TweenService = safeService("TweenService"),
    PathfindingService = safeService("PathfindingService"),
    ReplicatedStorage = safeService("ReplicatedStorage")
}

local LocalPlayer = Services.Players.LocalPlayer
while not LocalPlayer do
    task.wait(0.2)
    LocalPlayer = Services.Players.LocalPlayer
end

-- 5. Variaveis de Ciclo de Vida e Controle
local isRunning = true
local activeConnections = {}

-- 6. Configuracoes e Estado
local Config = {
    Enabled = true,
    IdleThresholdSeconds = 2.0,
    TreadmillPosition = nil,
    TreadmillSurfaceY = 0,
    TreadmillRunDirection = Vector3.new(0, 0, -1),
    PlotPosition = nil,
    ManualTreadmillSet = false
}

local State = {
    CurrentStatus = "Iniciando...",
    PlotFound = false,
    TreadmillFound = false,
    TreadmillSource = "Buscando...",
    HoldingEgg = false,
    WasHoldingEgg = false,
    EggPickupTick = 0,
    EggHoldStillSince = 0,
    LastEggDropTick = 0,
    IsOnTreadmill = false,
    WalkingToTreadmill = false,
    LastActiveTick = os.clock(),
    LastPosition = Vector3.zero,
    LastDistToTreadmill = 999
}

-- Funcoes Auxiliares do Personagem
local function getHRP()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
    local c = LocalPlayer.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function getHorizontalDistance(posA, posB)
    return math.sqrt((posA.X - posB.X)^2 + (posA.Z - posB.Z)^2)
end

-- 6.1 Gancho de Reaparecimento do Personagem (CharacterAdded)
table.insert(activeConnections, LocalPlayer.CharacterAdded:Connect(function()
    State.IsOnTreadmill = false
    State.WalkingToTreadmill = false
    State.HoldingEgg = false
    State.WasHoldingEgg = false
    State.EggHoldStillSince = 0
    State.LastPosition = Vector3.zero
    State.LastActiveTick = os.clock() + 1.5
    State.CurrentStatus = "Carregando..."
    task.wait(1.0)
    if isRunning and Config.Enabled then
        pcall(function() updateTreadmillTarget(false) end)
    end
end))

-- 7. Deteccao Rigorosa de Posse de Ovo (Apenas Equipado/Nas Maos)
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

local function checkIsHoldingEgg()
    local char = LocalPlayer.Character
    if not char then return false end

    -- Atributos no Personagem ou Player
    for _, attr in ipairs({"EggUid", "CarryingEgg", "HoldingEgg", "HasEgg", "StolenEgg", "Carrying"}) do
        local val = char:GetAttribute(attr)
        if val ~= nil and val ~= "" and val ~= false then return true end
        local valP = LocalPlayer:GetAttribute(attr)
        if valP ~= nil and valP ~= "" and valP ~= false then return true end
    end

    -- Ferramentas ou modelos de ovo seguros nas maos (apenas no Character)
    for _, child in ipairs(char:GetChildren()) do
        local low = child.Name:lower()
        if not standardLimbNames[low] and not child:IsA("Accessory") and not child:IsA("Shirt")
            and not child:IsA("Pants") and not child:IsA("BodyColors") and not child:IsA("CharacterMesh") then
            
            if low:find("egg") or low:find("ovo") or child:GetAttribute("IsEgg") == true then
                if child:IsA("Tool") then
                    return true
                elseif child:IsA("Model") or child:IsA("BasePart") then
                    local hasWeld = child:FindFirstChildWhichIsA("WeldConstraint", true)
                        or child:FindFirstChildWhichIsA("Weld", true)
                        or child:FindFirstChildWhichIsA("Motor6D", true)
                    if hasWeld then return true end
                end
            end
        end
    end

    return false
end

-- 8. DESTAQUE 3D VISUAL DA ESTEIRA (HIGHLIGHT + BILLBOARD)
local activeHighlight = nil
local activeBillboard = nil

local function updateTreadmillVisual(targetInstance)
    pcall(function()
        if activeHighlight and activeHighlight.Parent then activeHighlight:Destroy() end
        if activeBillboard and activeBillboard.Parent then activeBillboard:Destroy() end
    end)

    if not targetInstance then return end

    pcall(function()
        local hlTarget = targetInstance:IsA("Model") and targetInstance or targetInstance.Parent
        if hlTarget and hlTarget:IsA("Model") then
            activeHighlight = Instance.new("Highlight")
            activeHighlight.Name = "CompanionTreadmillHighlight"
            activeHighlight.Adornee = hlTarget
            activeHighlight.FillColor = Color3.fromRGB(56, 189, 248)
            activeHighlight.FillTransparency = 0.45
            activeHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
            activeHighlight.OutlineTransparency = 0.1
            activeHighlight.Parent = hlTarget
        end

        local bbPart = targetInstance:IsA("BasePart") and targetInstance or (targetInstance:IsA("Model") and (targetInstance.PrimaryPart or targetInstance:FindFirstChildWhichIsA("BasePart")))
        if bbPart then
            activeBillboard = Instance.new("BillboardGui")
            activeBillboard.Name = "CompanionTreadmillBB"
            activeBillboard.Adornee = bbPart
            activeBillboard.Size = UDim2.new(0, 130, 0, 24)
            activeBillboard.StudsOffset = Vector3.new(0, 3.5, 0)
            activeBillboard.AlwaysOnTop = true
            
            local lbl = Instance.new("TextLabel")
            lbl.Size = UDim2.new(1, 0, 1, 0)
            lbl.BackgroundTransparency = 0.25
            lbl.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
            lbl.Font = Enum.Font.SourceSansBold
            lbl.TextSize = 11
            lbl.TextColor3 = Color3.fromRGB(56, 189, 248)
            lbl.Text = "ESTEIRA DETECTADA"
            lbl.Parent = activeBillboard
            
            local uic = Instance.new("UICorner")
            uic.CornerRadius = UDim.new(0, 5)
            uic.Parent = lbl

            local uis = Instance.new("UIStroke")
            uis.Color = Color3.fromRGB(56, 189, 248)
            uis.Thickness = 1
            uis.Parent = lbl
            
            activeBillboard.Parent = bbPart
        end
    end)
end

-- 9. DETECTOR MESTRE DA ESTEIRA DE ANJO / NATIVA (findBestTreadmill)
local function findBestTreadmill()
    if Config.ManualTreadmillSet and Config.TreadmillPosition then
        return Config.TreadmillPosition, Config.TreadmillSurfaceY, Config.TreadmillRunDirection, nil, "Manual"
    end

    local hrp = getHRP()
    local charPos = hrp and hrp.Position or Vector3.zero

    -- PRIORIDADE 1: Workspace.__ClientTreadmillRenders (Render Exclusivo do Cliente)
    local ctr = Services.Workspace:FindFirstChild("__ClientTreadmillRenders")
    if ctr then
        for _, child in ipairs(ctr:GetChildren()) do
            local part = nil
            if child:IsA("BasePart") then
                part = child
            elseif child:IsA("Model") then
                for _, desc in ipairs(child:GetDescendants()) do
                    if desc:IsA("BasePart") then
                        local ln = desc.Name:lower()
                        if desc:FindFirstChildWhichIsA("TouchTransmitter") or desc.Name == "TouchInterest"
                            or ln:find("belt") or ln:find("run") or ln:find("tapete") or ln:find("floor") or ln:find("pad") or ln:find("hitbox") then
                            part = desc
                            break
                        end
                    end
                end
                if not part then part = child.PrimaryPart end
                if not part then
                    local maxArea = 0
                    for _, desc in ipairs(child:GetDescendants()) do
                        if desc:IsA("BasePart") then
                            local area = desc.Size.X * desc.Size.Z
                            if area > maxArea then maxArea = area; part = desc end
                        end
                    end
                end
            end

            if part then
                local pPos = part.Position
                local sY = pPos.Y + (part.Size.Y / 2)
                local wPos = Vector3.new(pPos.X, sY, pPos.Z)
                local rDir = part.CFrame.LookVector
                if part.AssemblyLinearVelocity.Magnitude > 1 then
                    local v = part.AssemblyLinearVelocity
                    rDir = -Vector3.new(v.X, 0, v.Z).Unit
                end
                return wPos, sY, rDir, child, "ClientRenders (Anjo)"
            end
        end
    end

    -- PRIORIDADE 2: Modelos com 'angel', 'anjo', 'wing' no Workspace e Plots
    local candidates = {}
    local searchContainers = {}
    local plots = Services.Workspace:FindFirstChild("Plots")
    if plots then
        for _, p in ipairs(plots:GetChildren()) do table.insert(searchContainers, p) end
    end
    table.insert(searchContainers, Services.Workspace)

    for _, container in ipairs(searchContainers) do
        for _, desc in ipairs(container:GetChildren()) do
            if desc:IsA("Model") or desc:IsA("BasePart") then
                local low = desc.Name:lower()
                local isAngelMatch = low:find("angel") or low:find("anjo") or low:find("wing") or low:find("asa")
                local isTreadmillMatch = low:find("treadmill") or low:find("esteira") or low:find("belt") or low:find("treino") or low:find("speed")

                if isAngelMatch or isTreadmillMatch then
                    local candidatePart = nil
                    if desc:IsA("BasePart") then
                        candidatePart = desc
                    else
                        for _, p in ipairs(desc:GetDescendants()) do
                            if p:IsA("BasePart") then
                                if p:FindFirstChildWhichIsA("TouchTransmitter") or p.Name == "TouchInterest" then
                                    candidatePart = p
                                    break
                                end
                                local pName = p.Name:lower()
                                if pName:find("belt") or pName:find("run") or pName:find("tapete") or pName:find("floor") or pName:find("pad") then
                                    candidatePart = p
                                    break
                                end
                            end
                        end
                        if not candidatePart then
                            candidatePart = desc.PrimaryPart or desc:FindFirstChildWhichIsA("BasePart")
                        end
                    end

                    if candidatePart then
                        local d = hrp and (candidatePart.Position - charPos).Magnitude or 999
                        table.insert(candidates, {
                            instance = desc,
                            part = candidatePart,
                            dist = d,
                            isAngel = isAngelMatch and true or false
                        })
                    end
                end
            end
        end
    end

    table.sort(candidates, function(a, b)
        if a.isAngel and not b.isAngel then return true end
        if not a.isAngel and b.isAngel then return false end
        return a.dist < b.dist
    end)

    if #candidates > 0 then
        local best = candidates[1]
        local pPos = best.part.Position
        local sY = pPos.Y + (best.part.Size.Y / 2)
        local wPos = Vector3.new(pPos.X, sY, pPos.Z)
        local rDir = best.part.CFrame.LookVector
        local srcName = best.isAngel and "Modelo Anjo" or "Esteira"
        return wPos, sY, rDir, best.instance, srcName
    end

    -- PRIORIDADE 3: Busca por TouchTransmitter em pecas da base (raio de ate 250 studs)
    local touchCandidates = {}
    for _, desc in ipairs(Services.Workspace:GetDescendants()) do
        if desc:IsA("TouchTransmitter") or desc.Name == "TouchInterest" then
            local p = desc.Parent
            if p and p:IsA("BasePart") and hrp then
                local d = (p.Position - charPos).Magnitude
                if d < 250 and math.abs(p.Position.Y - charPos.Y) < 25 then
                    table.insert(touchCandidates, { part = p, dist = d })
                end
            end
        end
    end
    table.sort(touchCandidates, function(a, b) return a.dist < b.dist end)
    if #touchCandidates > 0 then
        local bestP = touchCandidates[1].part
        local pPos = bestP.Position
        local sY = pPos.Y + (bestP.Size.Y / 2)
        local wPos = Vector3.new(pPos.X, sY, pPos.Z)
        return wPos, sY, bestP.CFrame.LookVector, bestP, "Toque Proximo"
    end

    return nil, nil, nil, nil, "Nao Encontrada"
end

local function updateTreadmillTarget(force)
    if Config.ManualTreadmillSet and not force then return true end

    local walkPos, surfaceY, runDir, inst, source = findBestTreadmill()
    if walkPos then
        Config.TreadmillPosition = walkPos
        Config.TreadmillSurfaceY = surfaceY or walkPos.Y
        if runDir then Config.TreadmillRunDirection = runDir end
        State.TreadmillFound = true
        State.TreadmillSource = source or "OK"
        updateTreadmillVisual(inst)
        return true
    end

    State.TreadmillFound = false
    State.TreadmillSource = "Procurando..."
    return false
end

-- 10. MOTOR DE DETECCAO MULTICAMADAS DO BF (ZERO FALSO-POSITIVO)
local function checkGlobalBFBusy()
    local envs = { _G }
    if getgenv then pcall(function() table.insert(envs, getgenv()) end) end

    for _, env in ipairs(envs) do
        if type(env) == "table" then
            if rawget(env, "BF_IsBusy") == true then return true, "BF Ocupado (Global)" end
            if rawget(env, "BF_Stealing") == true then return true, "BF Roubando (Global)" end
            if rawget(env, "BF_Flying") == true then return true, "BF Voando (Global)" end
            if rawget(env, "IsStealing") == true then return true, "Roubo Ativo" end

            local sm = rawget(env, "StealSM")
            if type(sm) == "table" and sm.Current and sm.Current ~= "IDLE" then
                return true, "BF: " .. tostring(sm.Current)
            end

            local lastTick = rawget(env, "BF_LastActionTick")
            if type(lastTick) == "number" and (os.clock() - lastTick) < 2.5 then
                return true, "BF Operando Recentemente"
            end
        end
    end
    return false, nil
end

local function detectBFActivity(hrp, hum, moveDelta, currentPos)
    -- CAMADA 1: Handshake Global de Execucao Real
    local globalBusy, globalReason = checkGlobalBFBusy()
    if globalBusy then return true, globalReason end

    local now = os.clock()
    local hVel = math.sqrt(hrp.AssemblyLinearVelocity.X^2 + hrp.AssemblyLinearVelocity.Z^2)

    -- CAMADA 2: Posse de Ovo & Cooldown de Deposito / Plantio
    local isHolding = checkIsHoldingEgg()
    if isHolding then
        if not State.HoldingEgg then
            -- Momento exato em que pegou o ovo
            State.HoldingEgg = true
            State.WasHoldingEgg = true
            State.EggPickupTick = now
            State.EggHoldStillSince = 0
            return true, "BF: Pegou Ovo"
        end

        -- Se estiver se movendo ativamente ou voando alto -> BF em transporte
        local isMoving = (hVel > 2.0 or moveDelta > 0.5)
        local isHigh = (Config.TreadmillSurfaceY ~= 0 and currentPos.Y > (Config.TreadmillSurfaceY + 5.5))

        if isMoving or isHigh then
            State.EggHoldStillSince = 0
            return true, isHigh and "BF: Voando com Ovo" or "BF: Transportando Ovo"
        end

        -- Se pegou ha menos de 2.5s, dar tempo para o BF iniciar a rota
        if (now - State.EggPickupTick) < 2.5 then
            State.EggHoldStillSince = 0
            return true, "BF: Segurando Ovo (Aguardando)"
        end

        -- Se esta PARADO com o ovo na mao (ex: em frente a base com ninhos cheios)
        if State.EggHoldStillSince == 0 then
            State.EggHoldStillSince = now
        end

        local stillDuration = now - State.EggHoldStillSince
        if stillDuration < 2.0 then
            return true, string.format("BF com Ovo: Estabilizando (%.1fs)", math.max(0.1, 2.0 - stillDuration))
        end

        -- PARADO A MAIS DE 2.0s COM OVO: BF terminou o roubo e esta ocioso!
        -- O companion agora pode assumir e treinar na esteira segurando o ovo!
        State.HoldingEgg = true
        State.WasHoldingEgg = true
    else
        State.EggHoldStillSince = 0
        if State.HoldingEgg or State.WasHoldingEgg then
            State.HoldingEgg = false
            State.WasHoldingEgg = false
            State.LastEggDropTick = now
        end
    end

    -- Cooldown apos soltar/plantar o ovo (3.0s de protecao)
    if State.LastEggDropTick > 0 and (now - State.LastEggDropTick) < 3.0 then
        local rem = 3.0 - (now - State.LastEggDropTick)
        return true, string.format("BF: Plantando Ovo (%.1fs)", math.max(0.1, rem))
    end

    -- CAMADA 3: Deteccao Aerea / Voo Real com Forca Fisica Ativa
    if Config.TreadmillSurfaceY ~= 0 and currentPos.Y > (Config.TreadmillSurfaceY + 6.0) and hrp.AssemblyLinearVelocity.Magnitude > 1.5 then
        return true, string.format("BF Voando Alto (Y+%.1f)", currentPos.Y - Config.TreadmillSurfaceY)
    end

    local bv = hrp:FindFirstChildOfClass("BodyVelocity")
    if bv and bv.MaxForce.Magnitude > 0 and bv.Velocity.Magnitude > 1.5 then
        return true, "BF: Voo Ativo (BodyVelocity)"
    end

    local lv = hrp:FindFirstChildOfClass("LinearVelocity")
    if lv and lv.Enabled and lv.VectorVelocity.Magnitude > 1.5 then
        return true, "BF: Voo Ativo (LinearVelocity)"
    end

    local bp = hrp:FindFirstChildOfClass("BodyPosition")
    if bp and bp.MaxForce.Magnitude > 0 and (bp.Position - hrp.Position).Magnitude > 3.0 then
        return true, "BF: Voo Ativo (BodyPosition)"
    end

    -- CAMADA 4: Movimentacao Dinamica e Intencao de Caminhada do BF
    if State.IsOnTreadmill then
        if hum.MoveDirection.Magnitude > 0.15 then
            local dot = hum.MoveDirection:Dot(Config.TreadmillRunDirection)
            if dot < 0.25 then
                return true, "BF: Saindo da Esteira"
            end
        end

        if Config.TreadmillPosition then
            local hDistTreadmill = getHorizontalDistance(currentPos, Config.TreadmillPosition)
            if hDistTreadmill > 5.5 then
                return true, "BF: Deslocou da Esteira"
            end
        end

    elseif State.WalkingToTreadmill then
        if Config.TreadmillPosition then
            local curDist = getHorizontalDistance(currentPos, Config.TreadmillPosition)
            if curDist > (State.LastDistToTreadmill + 5.0) and curDist > 15.0 then
                return true, "BF: Andando para Outro Alvo"
            end
        end

    else
        if hVel > 2.5 and moveDelta > 0.6 then
            return true, "BF: Andando"
        end

        local uis = Services.UserInputService
        if uis:IsKeyDown(Enum.KeyCode.W) or uis:IsKeyDown(Enum.KeyCode.A)
            or uis:IsKeyDown(Enum.KeyCode.S) or uis:IsKeyDown(Enum.KeyCode.D) then
            return true, "Movimento Manual"
        end
    end

    return false, nil
end

-- 11. MAPA DE CORREDORES DAS 11 ILHAS OFICIAIS (LONGA DISTANCIA ATE A BASE)
local IslandCorridors = {
    { X = 4600, Z = -350, Y = 105, Name = "Ilha 11 (Templo do Tita)" },
    { X = 4050, Z = -410, Y = 95,  Name = "Ilha 10 (Cerejeira)" },
    { X = 3400, Z = -325, Y = 85,  Name = "Ilha 9 (Cosmico)" },
    { X = 2825, Z = -410, Y = 75,  Name = "Ilha 8 (Pre-Historico)" },
    { X = 2315, Z = -325, Y = 65,  Name = "Ilha 7 (Abismo)" },
    { X = 1880, Z = -410, Y = 55,  Name = "Ilha 6 (Vulcao)" },
    { X = 1515, Z = -325, Y = 45,  Name = "Ilha 5 (Neve)" },
    { X = 1215, Z = -410, Y = 35,  Name = "Ilha 4 (Selva)" },
    { X = 965,  Z = -325, Y = 28,  Name = "Ilha 3 (Deserto)" },
    { X = 760,  Z = -410, Y = 20,  Name = "Ilha 2 (Lago)" },
    { X = 600,  Z = -330, Y = 15,  Name = "Ilha 1 (Floresta)" }
}

-- 12. DETECTOR DE PAREDES POR RAYCAST 3D E DESVIO DINAMICO
local function detectWallAndGetDirection(hrp, moveDir)
    local char = LocalPlayer.Character
    if not char then return "CLEAR", moveDir end

    local rayParams = RaycastParams.new()
    rayParams.FilterType = RaycastFilterType.Exclude

    local ignoreList = { char }
    for _, item in ipairs(char:GetChildren()) do
        if item:IsA("Tool") or item:IsA("Model") then
            table.insert(ignoreList, item)
        end
    end
    rayParams.FilterDescendantsInstances = ignoreList

    -- Iniciar o raio ligeiramente a frente da capsula para evitar colisoes internas
    local origin = hrp.Position + (moveDir * 1.0) + Vector3.new(0, 0.4, 0)
    local checkDist = 3.8

    local frontRay = Services.Workspace:Raycast(origin, moveDir * checkDist, rayParams)
    if frontRay and frontRay.Instance and frontRay.Instance.CanCollide then
        -- Obstaculo detectado: checar se e baixo (pular)
        local highRay = Services.Workspace:Raycast(origin + Vector3.new(0, 3.0, 0), moveDir * checkDist, rayParams)
        if not highRay then
            return "JUMP", moveDir
        else
            -- Parede alta: testar diagonais (+- 45 graus)
            local leftDir = (CFrame.Angles(0, math.rad(45), 0) * Vector3.new(moveDir.X, 0, moveDir.Z)).Unit
            local rightDir = (CFrame.Angles(0, math.rad(-45), 0) * Vector3.new(moveDir.X, 0, moveDir.Z)).Unit

            local leftRay = Services.Workspace:Raycast(origin, leftDir * checkDist, rayParams)
            local rightRay = Services.Workspace:Raycast(origin, rightDir * checkDist, rayParams)

            if not leftRay then
                return "STEER", leftDir
            elseif not rightRay then
                return "STEER", rightDir
            else
                local hardLeft = (CFrame.Angles(0, math.rad(90), 0) * Vector3.new(moveDir.X, 0, moveDir.Z)).Unit
                return "STEER", hardLeft
            end
        end
    end

    return "CLEAR", moveDir
end

-- 13. MOTOR DE NAVEGACAO FLUIDA E PATHFINDING ASSINCRONO (ZERO C-CALL ERRORS)
local navWaypoints = nil
local navIndex = 1
local lastPathComputeTick = 0
local lastTargetPos = nil
local isNavigating = false
local isComputingPath = false

local function getEffectiveIntermediateTarget(currentPos, finalTarget)
    -- Se estiver alem da Ilha 1 (X > 650), guiar pelo corredor da ilha rumo a base
    if currentPos.X > 650 then
        for _, corridor in ipairs(IslandCorridors) do
            if currentPos.X > (corridor.X + 25) then
                return Vector3.new(corridor.X, corridor.Y, corridor.Z), corridor.Name
            end
        end
        return Vector3.new(550, 12, -340), "Entrada da Base"
    end

    return finalTarget, "Esteira Final"
end

local function requestPathUpdate(fromPos, toPos)
    if isComputingPath then return end
    local now = os.clock()
    if (now - lastPathComputeTick) < 1.2 then return end

    isComputingPath = true
    lastPathComputeTick = now

    task.spawn(function()
        local path = Services.PathfindingService:CreatePath({
            AgentRadius = 2.0,
            AgentHeight = 5.0,
            AgentCanJump = true,
            WaypointSpacing = 6.5
        })

        local ok, _ = pcall(function()
            path:ComputeAsync(fromPos, toPos)
        end)

        if ok and path.Status == Enum.PathStatus.Success then
            local wps = path:GetWaypoints()
            if #wps > 1 then
                navWaypoints = wps
                navIndex = 2
                lastTargetPos = toPos
            end
        end

        isComputingPath = false
    end)
end

-- RUNNER CONTINUO EM HEARTBEAT (MOVIMENTACAO FLUIDA SEM TRAVAMENTOS)
table.insert(activeConnections, Services.RunService.Heartbeat:Connect(function(dt)
    if not isRunning or not Config.Enabled then return end
    if not isNavigating and not State.IsOnTreadmill then return end

    local hrp = getHRP()
    local hum = getHumanoid()
    if not hrp or not hum or hum.Health <= 0 then return end

    local currentPos = hrp.Position

    -- CASO A: JA ESTA NA ESTEIRA -> CORRIDA CONTINUA A 60 FPS
    if State.IsOnTreadmill then
        hum:Move(Config.TreadmillRunDirection, false)
        return
    end

    -- CASO B: A CAMINHO DA ESTEIRA
    if not isNavigating or not Config.TreadmillPosition then return end

    local finalDist = getHorizontalDistance(currentPos, Config.TreadmillPosition)

    -- CHEGADA NA ESTEIRA
    if finalDist <= 2.8 then
        isNavigating = false
        navWaypoints = nil
        State.IsOnTreadmill = true
        State.WalkingToTreadmill = false
        hum:Move(Config.TreadmillRunDirection, false)
        return
    end

    -- ALVO INTERMEDIARIO (CORREDOR DE ILHAS OU ESTEIRA FINAL)
    local subTarget, subName = getEffectiveIntermediateTarget(currentPos, Config.TreadmillPosition)

    -- Se precisar de rota, solicitar calculo assincrono seguro
    if not navWaypoints or navIndex > #navWaypoints or (lastTargetPos and (subTarget - lastTargetPos).Magnitude > 25) then
        requestPathUpdate(currentPos, subTarget)
    end

    -- SELECIONAR PROXIMO PONTO DE MOVIMENTO
    local targetStepPos = subTarget
    local isJumpPoint = false

    if navWaypoints and navIndex <= #navWaypoints then
        local wp = navWaypoints[navIndex]
        targetStepPos = wp.Position
        if wp.Action == Enum.PathWaypointAction.Jump then
            isJumpPoint = true
        end

        local distToWp = getHorizontalDistance(currentPos, targetStepPos)
        local advanceThreshold = math.clamp(hum.WalkSpeed * 0.16, 3.8, 8.0)
        if distToWp < advanceThreshold and navIndex < #navWaypoints then
            navIndex = navIndex + 1
            local nextWp = navWaypoints[navIndex]
            targetStepPos = nextWp.Position
            if nextWp.Action == Enum.PathWaypointAction.Jump then isJumpPoint = true end
        end
    end

    -- VETOR DE DIRECAO CONTINUO (ZERO HESITACAO)
    local toStep = Vector3.new(targetStepPos.X - currentPos.X, 0, targetStepPos.Z - currentPos.Z)
    if toStep.Magnitude > 0.1 then
        local moveDir = toStep.Unit

        -- DETECCAO E DESVIO DE PAREDES POR RAYCAST
        local wallAction, steerDir = detectWallAndGetDirection(hrp, moveDir)
        if wallAction == "JUMP" or isJumpPoint then
            hum.Jump = true
        elseif wallAction == "STEER" then
            moveDir = steerDir
        end

        -- Pulinho na borda da esteira
        if finalDist < 4.5 and currentPos.Y < (Config.TreadmillSurfaceY + 0.5) then
            hum.Jump = true
        end

        hum:Move(moveDir, false)
    end
end))

-- 14. LOOP PRINCIPAL DE COOPERACAO E MONITORAMENTO DO BF
task.spawn(function()
    while isRunning do
        task.wait(0.25)
        if not isRunning then break end

        if not Config.Enabled then
            State.CurrentStatus = "Pausado"
            State.IsOnTreadmill = false
            State.WalkingToTreadmill = false
            isNavigating = false
        else
            local hrp = getHRP()
            local hum = getHumanoid()

            if hrp and hum and hum.Health > 0 then
                if not Config.TreadmillPosition or not State.TreadmillFound then
                    updateTreadmillTarget(false)
                end

                local currentPos = hrp.Position
                local moveDelta = 0
                if State.LastPosition ~= Vector3.zero then
                    moveDelta = (currentPos - State.LastPosition).Magnitude
                end
                State.LastPosition = currentPos

                local isBusy, busyReason = detectBFActivity(hrp, hum, moveDelta, currentPos)

                if isBusy then
                    -- BF ATIVO: Ceder controle total imediatamente
                    State.LastActiveTick = os.clock()
                    State.CurrentStatus = busyReason or "BF Operando"
                    isNavigating = false

                    if State.IsOnTreadmill or State.WalkingToTreadmill then
                        State.IsOnTreadmill = false
                        State.WalkingToTreadmill = false
                        navWaypoints = nil
                    end

                else
                    -- BF PARADO: Contar tempo de ociosidade
                    local idleTime = os.clock() - State.LastActiveTick

                    if idleTime >= Config.IdleThresholdSeconds then
                        if Config.TreadmillPosition then
                            local hDist = getHorizontalDistance(currentPos, Config.TreadmillPosition)

                            if not State.IsOnTreadmill and hDist > 2.8 then
                                State.WalkingToTreadmill = true
                                State.LastDistToTreadmill = hDist
                                isNavigating = true

                                local _, locName = getEffectiveIntermediateTarget(currentPos, Config.TreadmillPosition)
                                local eggPrefix = State.HoldingEgg and "com Ovo " or ""
                                if locName == "Esteira Final" then
                                    State.CurrentStatus = string.format("Sprint para Esteira %s(%.0fm)", eggPrefix, hDist)
                                else
                                    State.CurrentStatus = string.format("Rumo a Base: %s %s(%.0fm)", locName, eggPrefix, hDist)
                                end

                            else
                                if hDist <= 4.8 then
                                    isNavigating = false
                                    navWaypoints = nil
                                    State.WalkingToTreadmill = false
                                    State.IsOnTreadmill = true
                                    State.CurrentStatus = State.HoldingEgg and "Na Esteira com Ovo (Treinando)" or "Na Esteira (Treinando)"
                                    hum:Move(Config.TreadmillRunDirection, false)
                                else
                                    State.IsOnTreadmill = false
                                    State.WalkingToTreadmill = true
                                    isNavigating = true
                                end
                            end
                        else
                            isNavigating = false
                            State.WalkingToTreadmill = false
                            State.CurrentStatus = "Buscando Esteira de Anjo..."
                            updateTreadmillTarget(false)
                        end
                    else
                        isNavigating = false
                        State.WalkingToTreadmill = false
                        navWaypoints = nil
                        local eggStr = State.HoldingEgg and " (Ovo Seguro)" or ""
                        State.CurrentStatus = string.format("Aguardando BF (%.1fs)%s", math.max(0, Config.IdleThresholdSeconds - idleTime), eggStr)
                    end
                end
            end
        end
    end
end)

-- 15. FUNCAO UNLOAD COMPLETA
local ScreenGui = nil

local function unloadCompanion()
    isRunning = false
    isNavigating = false

    for _, conn in ipairs(activeConnections) do
        pcall(function() conn:Disconnect() end)
    end
    activeConnections = {}

    pcall(function()
        if activeHighlight and activeHighlight.Parent then activeHighlight:Destroy() end
        if activeBillboard and activeBillboard.Parent then activeBillboard:Destroy() end
    end)

    pcall(function()
        local hum = getHumanoid()
        if hum then hum:Move(Vector3.zero, false) end
    end)

    if ScreenGui and ScreenGui.Parent then
        ScreenGui:Destroy()
    end

    pcall(function()
        _G.AutoEsteira_Active = nil
        if getgenv then getgenv().AutoEsteira_Active = nil end
    end)
end

-- 16. PROTECAO ANTECIPADA DA INTERFACE GRAFICA
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
            local cg = Services.Workspace.Parent:FindFirstChild("CoreGui") or game:GetService("CoreGui")
            container = (cloneref and cloneref(cg)) or cg
        end)
    end
    if not container and LocalPlayer then
        container = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    end
    return container or Services.Workspace
end

-- 17. INTERFACE MINIMALISTA, ELEGANTE E DISCRETA (v3.5)
local randomId = Services.HttpService:GenerateGUID(false):sub(1, 8)
ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "HUD_" .. randomId
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

protectGui(ScreenGui)
ScreenGui.Parent = getGuiContainer()

local Card = Instance.new("Frame")
Card.Name = "Panel"
Card.Size = UDim2.new(0, 210, 0, 0)
Card.AutomaticSize = Enum.AutomaticSize.Y
Card.Position = UDim2.new(0.84, -10, 0.05, 0)
Card.BackgroundColor3 = Color3.fromRGB(15, 20, 28)
Card.BackgroundTransparency = 0.08
Card.BorderSizePixel = 0
Card.Active = true
Card.Draggable = true
Card.Parent = ScreenGui

local cardCorner = Instance.new("UICorner")
cardCorner.CornerRadius = UDim.new(0, 8)
cardCorner.Parent = Card

local cardStroke = Instance.new("UIStroke")
cardStroke.Color = Color3.fromRGB(40, 52, 70)
cardStroke.Thickness = 1.2
cardStroke.Parent = Card

local cardPad = Instance.new("UIPadding")
cardPad.PaddingTop = UDim.new(0, 8)
cardPad.PaddingBottom = UDim.new(0, 10)
cardPad.PaddingLeft = UDim.new(0, 10)
cardPad.PaddingRight = UDim.new(0, 10)
cardPad.Parent = Card

local cardLayout = Instance.new("UIListLayout")
cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
cardLayout.Padding = UDim.new(0, 5)
cardLayout.Parent = Card

-- Header
local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 20)
Header.BackgroundTransparency = 1
Header.LayoutOrder = 1
Header.Parent = Card

local StatusDot = Instance.new("Frame")
StatusDot.Size = UDim2.new(0, 8, 0, 8)
StatusDot.Position = UDim2.new(0, 0, 0.5, -4)
StatusDot.BackgroundColor3 = Color3.fromRGB(16, 185, 129)
StatusDot.BorderSizePixel = 0
StatusDot.Parent = Header
local dotCorner = Instance.new("UICorner")
dotCorner.CornerRadius = UDim.new(1, 0)
dotCorner.Parent = StatusDot

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -54, 1, 0)
Title.Position = UDim2.new(0, 14, 0, 0)
Title.BackgroundTransparency = 1
Title.Font = Enum.Font.SourceSansBold
Title.TextSize = 13
Title.TextColor3 = Color3.fromRGB(240, 245, 255)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Text = "Auto Esteira (BF)"
Title.Parent = Header

local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, 18, 0, 18)
MinBtn.Position = UDim2.new(1, -38, 0.5, -9)
MinBtn.BackgroundColor3 = Color3.fromRGB(26, 34, 48)
MinBtn.Text = "-"
MinBtn.Font = Enum.Font.SourceSansBold
MinBtn.TextSize = 13
MinBtn.TextColor3 = Color3.fromRGB(200, 210, 225)
MinBtn.Parent = Header
local minCorner = Instance.new("UICorner")
minCorner.CornerRadius = UDim.new(0, 4)
minCorner.Parent = MinBtn

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 18, 0, 18)
CloseBtn.Position = UDim2.new(1, -18, 0.5, -9)
CloseBtn.BackgroundColor3 = Color3.fromRGB(153, 27, 27)
CloseBtn.Text = "x"
CloseBtn.Font = Enum.Font.SourceSansBold
CloseBtn.TextSize = 12
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.Parent = Header
local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 4)
closeCorner.Parent = CloseBtn

CloseBtn.MouseButton1Click:Connect(function()
    unloadCompanion()
end)

-- Container de Conteudo
local ContentBox = Instance.new("Frame")
ContentBox.Size = UDim2.new(1, 0, 0, 0)
ContentBox.AutomaticSize = Enum.AutomaticSize.Y
ContentBox.BackgroundTransparency = 1
ContentBox.LayoutOrder = 2
ContentBox.Parent = Card

local contentLayout = Instance.new("UIListLayout")
contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
contentLayout.Padding = UDim.new(0, 4)
contentLayout.Parent = ContentBox

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, 0, 0, 18)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Font = Enum.Font.SourceSansBold
StatusLabel.TextSize = 12
StatusLabel.TextColor3 = Color3.fromRGB(16, 185, 129)
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.Text = "Status: Procurando..."
StatusLabel.Parent = ContentBox

local EsteiraLabel = Instance.new("TextLabel")
EsteiraLabel.Size = UDim2.new(1, 0, 0, 15)
EsteiraLabel.BackgroundTransparency = 1
EsteiraLabel.Font = Enum.Font.SourceSans
EsteiraLabel.TextSize = 11
EsteiraLabel.TextColor3 = Color3.fromRGB(148, 163, 184)
EsteiraLabel.TextXAlignment = Enum.TextXAlignment.Left
EsteiraLabel.Text = "Esteira: Buscando Anjo..."
EsteiraLabel.Parent = ContentBox

local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Size = UDim2.new(1, 0, 0, 24)
ToggleBtn.BackgroundColor3 = Color3.fromRGB(16, 80, 50)
ToggleBtn.Text = "ESTEIRA: LIGADA"
ToggleBtn.Font = Enum.Font.SourceSansBold
ToggleBtn.TextSize = 11
ToggleBtn.TextColor3 = Color3.fromRGB(240, 255, 245)
ToggleBtn.Parent = ContentBox
local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 5)
toggleCorner.Parent = ToggleBtn

ToggleBtn.MouseButton1Click:Connect(function()
    Config.Enabled = not Config.Enabled
    if Config.Enabled then
        ToggleBtn.Text = "ESTEIRA: LIGADA"
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(16, 80, 50)
        ToggleBtn.TextColor3 = Color3.fromRGB(240, 255, 245)
        State.LastActiveTick = os.clock()
        State.CurrentStatus = "Iniciando..."
    else
        ToggleBtn.Text = "ESTEIRA: DESLIGADA"
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(35, 42, 54)
        ToggleBtn.TextColor3 = Color3.fromRGB(160, 175, 195)
        State.IsOnTreadmill = false
        State.WalkingToTreadmill = false
        isNavigating = false
        State.CurrentStatus = "Pausado"
        local hum = getHumanoid()
        if hum then hum:Move(Vector3.zero, false) end
    end
end)

local ActionRow = Instance.new("Frame")
ActionRow.Size = UDim2.new(1, 0, 0, 20)
ActionRow.BackgroundTransparency = 1
ActionRow.Parent = ContentBox

local rowLayout = Instance.new("UIListLayout")
rowLayout.FillDirection = Enum.FillDirection.Horizontal
rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
rowLayout.Padding = UDim.new(0, 4)
rowLayout.Parent = ActionRow

local SetPosBtn = Instance.new("TextButton")
SetPosBtn.Size = UDim2.new(0.55, -2, 1, 0)
SetPosBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
SetPosBtn.Text = "Definir Minha Pos"
SetPosBtn.Font = Enum.Font.SourceSansBold
SetPosBtn.TextSize = 10
SetPosBtn.TextColor3 = Color3.fromRGB(245, 158, 11)
SetPosBtn.Parent = ActionRow
local spCorner = Instance.new("UICorner")
spCorner.CornerRadius = UDim.new(0, 4)
spCorner.Parent = SetPosBtn

SetPosBtn.MouseButton1Click:Connect(function()
    local hrp = getHRP()
    if hrp then
        Config.TreadmillPosition = hrp.Position
        Config.TreadmillSurfaceY = hrp.Position.Y - 2.5
        Config.TreadmillRunDirection = hrp.CFrame.LookVector
        Config.ManualTreadmillSet = true
        State.TreadmillFound = true
        State.TreadmillSource = "Manual"
        updateTreadmillVisual(hrp)
        SetPosBtn.Text = "Posicao Salva!"
        task.delay(1.5, function()
            SetPosBtn.Text = "Definir Minha Pos"
        end)
    end
end)

local RescanBtn = Instance.new("TextButton")
RescanBtn.Size = UDim2.new(0.45, -2, 1, 0)
RescanBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
RescanBtn.Text = "Reescanear"
RescanBtn.Font = Enum.Font.SourceSansBold
RescanBtn.TextSize = 10
RescanBtn.TextColor3 = Color3.fromRGB(56, 189, 248)
RescanBtn.Parent = ActionRow
local rcCorner = Instance.new("UICorner")
rcCorner.CornerRadius = UDim.new(0, 4)
rcCorner.Parent = RescanBtn

RescanBtn.MouseButton1Click:Connect(function()
    RescanBtn.Text = "Buscando..."
    Config.ManualTreadmillSet = false
    Config.TreadmillPosition = nil
    updateTreadmillTarget(true)
    task.delay(1.0, function()
        RescanBtn.Text = "Reescanear"
    end)
end)

local isMinimized = false
MinBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    ContentBox.Visible = not isMinimized
    MinBtn.Text = isMinimized and "+" or "-"
    if isMinimized then
        Card.Size = UDim2.new(0, 120, 0, 20)
        cardPad.PaddingBottom = UDim.new(0, 4)
        cardPad.PaddingTop = UDim.new(0, 4)
    else
        Card.Size = UDim2.new(0, 210, 0, 0)
        cardPad.PaddingBottom = UDim.new(0, 10)
        cardPad.PaddingTop = UDim.new(0, 8)
    end
end)

-- 18. ATUALIZACAO EM TEMPO REAL DO STATUS
task.spawn(function()
    while isRunning do
        if StatusLabel and StatusLabel.Parent then
            StatusLabel.Text = "Status: " .. State.CurrentStatus

            if State.IsOnTreadmill then
                StatusLabel.TextColor3 = Color3.fromRGB(16, 185, 129)
                StatusDot.BackgroundColor3 = Color3.fromRGB(16, 185, 129)
            elseif State.CurrentStatus:find("Aguardando") then
                StatusLabel.TextColor3 = Color3.fromRGB(245, 158, 11)
                StatusDot.BackgroundColor3 = Color3.fromRGB(245, 158, 11)
            elseif State.CurrentStatus:find("Pausado") then
                StatusLabel.TextColor3 = Color3.fromRGB(148, 163, 184)
                StatusDot.BackgroundColor3 = Color3.fromRGB(100, 116, 139)
            elseif State.CurrentStatus:find("Sprint") or State.CurrentStatus:find("Rumo") then
                StatusLabel.TextColor3 = Color3.fromRGB(56, 189, 248)
                StatusDot.BackgroundColor3 = Color3.fromRGB(56, 189, 248)
            else
                StatusLabel.TextColor3 = Color3.fromRGB(168, 85, 247)
                StatusDot.BackgroundColor3 = Color3.fromRGB(168, 85, 247)
            end

            local hrp = getHRP()
            local dStr = ""
            if hrp and Config.TreadmillPosition then
                local d = math.floor(getHorizontalDistance(hrp.Position, Config.TreadmillPosition))
                dStr = string.format(" (%dm)", d)
            end
            EsteiraLabel.Text = "Esteira: " .. (State.TreadmillFound and (State.TreadmillSource .. dStr) or "Buscando...")
        end
        task.wait(0.25)
    end
end)

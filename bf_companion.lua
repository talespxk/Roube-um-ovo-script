--[[
    BIGFROOT COMPANION - AUTO ESTEIRA & SPEED FARM (v1.0)
    -----------------------------------------------------------------------
    Script complementar ultra-leve desenvolvido para rodar EM CONJUNTO com o BigFroot (BF).
    
    COMO FUNCIONA:
    1. O BigFroot rouba os ovos e os planta no seu plot/base.
    2. Assim que o BF termina de plantar e fica ocioso (sem ovos nas mãos e parado na base):
       -> O Companion detecta o estado ocioso após 2 segundos.
       -> Desloca o personagem suavemente para a sua Esteira (Treadmill).
       -> Ativa a caminhada contínua na esteira para farmar velocidade infinita.
    3. Quando o BF detecta novos ovos e começa a se mover para roubar:
       -> O Companion detecta a movimentação do BF e cede o controle na hora!
    4. Anti-AFK integrado para não desconectar por inatividade.
    5. Zero interferência com o BF, zero prints para LogService, interface minimalista.
]]

-- 1. Silenciamento Preventivo
local function silentOutput(...) end
local print = silentOutput
local warn = silentOutput

-- 2. Limpeza Preventiva de Globais
pcall(function()
    _G.BFCompanion_Active = nil
    if getgenv then getgenv().BFCompanion_Active = nil end
end)

-- 3. Serviços Seguros via cloneref
local function safeService(name)
    local s = game:GetService(name)
    return (cloneref and cloneref(s)) or s
end

local Services = {
    Workspace = safeService("Workspace"),
    Players = safeService("Players"),
    RunService = safeService("RunService"),
    UserInputService = safeService("UserInputService"),
    VirtualUser = safeService("VirtualUser"),
    HttpService = safeService("HttpService")
}

local LocalPlayer = Services.Players.LocalPlayer
while not LocalPlayer do
    task.wait(0.2)
    LocalPlayer = Services.Players.LocalPlayer
end

-- 4. Configurações e Estado
local Config = {
    AutoTreadmillEnabled = true,
    IdleThresholdSeconds = 2.0,      -- Segundos parado na base sem ovo antes de ir à esteira
    WalkOnTreadmill = true,          -- Mantém o personagem caminhando para frente na esteira
    AntiAFK = true,
    TreadmillPosition = nil,         -- Posição salva da esteira Vector3
    PlotPosition = nil,              -- Posição do plot/base
    SettingsFile = "bf_companion_settings.json"
}

local State = {
    CurrentStatus = "Iniciando...",
    IsOnTreadmill = false,
    LastActiveTick = os.clock(),
    LastPosition = Vector3.zero,
    IsCompanionMoving = false
}

-- Carregar / Salvar Configurações Locais
local function saveSettings()
    pcall(function()
        if not writefile then return end
        local data = {
            AutoTreadmillEnabled = Config.AutoTreadmillEnabled,
            IdleThresholdSeconds = Config.IdleThresholdSeconds,
            WalkOnTreadmill = Config.WalkOnTreadmill,
            AntiAFK = Config.AntiAFK
        }
        if Config.TreadmillPosition then
            data.TreadmillX = Config.TreadmillPosition.X
            data.TreadmillY = Config.TreadmillPosition.Y
            data.TreadmillZ = Config.TreadmillPosition.Z
        end
        writefile(Config.SettingsFile, Services.HttpService:JSONEncode(data))
    end)
end

local function loadSettings()
    pcall(function()
        if not readfile or not isfile or not isfile(Config.SettingsFile) then return end
        local raw = readfile(Config.SettingsFile)
        local data = Services.HttpService:JSONDecode(raw)
        if data then
            if data.AutoTreadmillEnabled ~= nil then Config.AutoTreadmillEnabled = data.AutoTreadmillEnabled end
            if data.IdleThresholdSeconds ~= nil then Config.IdleThresholdSeconds = data.IdleThresholdSeconds end
            if data.WalkOnTreadmill ~= nil then Config.WalkOnTreadmill = data.WalkOnTreadmill end
            if data.AntiAFK ~= nil then Config.AntiAFK = data.AntiAFK end
            if data.TreadmillX and data.TreadmillY and data.TreadmillZ then
                Config.TreadmillPosition = Vector3.new(data.TreadmillX, data.TreadmillY, data.TreadmillZ)
            end
        end
    end)
end
loadSettings()

-- 5. Funções Auxiliares do Personagem
local function getHRP()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
    local c = LocalPlayer.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

-- Detecção se o jogador está segurando ou transportando um ovo
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
    if not char then return false end

    -- 1. Atributos do Character ou LocalPlayer
    for k, v in pairs(char:GetAttributes()) do
        local low = k:lower()
        if low:find("egg") or low:find("carry") or low:find("hold") or low:find("uid") or low:find("grab") then
            if v ~= nil and v ~= "" and v ~= false then return true end
        end
    end
    for k, v in pairs(LocalPlayer:GetAttributes()) do
        local low = k:lower()
        if low:find("egg") or low:find("carry") or low:find("hold") or low:find("uid") or low:find("grab") then
            if v ~= nil and v ~= "" and v ~= false then return true end
        end
    end

    -- 2. Modelos ou partes soldadas ao corpo (ex: Chicken Egg)
    for _, child in ipairs(char:GetChildren()) do
        local low = child.Name:lower()
        if not standardLimbNames[low] and not child:IsA("Accessory") and not child:IsA("Shirt")
            and not child:IsA("Pants") and not child:IsA("BodyColors") and not child:IsA("CharacterMesh") then
            if child:IsA("Tool") then return true end
            if child:IsA("Model") or child:IsA("BasePart") then
                local hasWeld = child:FindFirstChildWhichIsA("WeldConstraint", true)
                    or child:FindFirstChildWhichIsA("Weld", true)
                    or child:FindFirstChildWhichIsA("Motor6D", true)
                if hasWeld then return true end
            end
        end
    end

    -- 3. Mochila
    local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
    if bp then
        for _, item in ipairs(bp:GetChildren()) do
            if item:IsA("Tool") then
                local n = item.Name:lower()
                if n:find("egg") or n:find("ovo") or item:GetAttribute("IsEgg") or item:GetAttribute("EggType") then
                    return true
                end
            end
        end
    end

    -- 4. GUI de dados do ovo
    local pgui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if pgui then
        local eggDataGui = pgui:FindFirstChild("AssetEggData")
        if eggDataGui and eggDataGui.Enabled then return true end
    end

    return false
end

-- Localiza o plot da base do jogador
local function findMyPlot()
    local plots = Services.Workspace:FindFirstChild("Plots")
    if not plots then return nil end

    for _, plot in ipairs(plots:GetChildren()) do
        local o = plot:FindFirstChild("Owner") or plot:FindFirstChild("Player") or plot:FindFirstChild("OwnerName")
        if o and o.Value and (tostring(o.Value) == LocalPlayer.Name or tostring(o.Value) == LocalPlayer.DisplayName) then
            return plot
        end
        for k, v in pairs(plot:GetAttributes()) do
            if tostring(v) == LocalPlayer.Name or tostring(v) == tostring(LocalPlayer.UserId) then
                return plot
            end
        end
    end
    return nil
end

-- Busca a esteira automaticamente
local function autoDetectTreadmill()
    local myPlot = findMyPlot()
    if myPlot then
        Config.PlotPosition = myPlot:GetPivot().Position
        for _, desc in ipairs(myPlot:GetDescendants()) do
            local low = desc.Name:lower()
            if low:find("treadmill") or low:find("esteira") or low:find("belt") then
                if desc:IsA("BasePart") then
                    return desc.Position + Vector3.new(0, 2.5, 0)
                elseif desc:IsA("Model") then
                    return desc:GetPivot().Position + Vector3.new(0, 2.5, 0)
                end
            end
        end
    end

    -- Busca em __ClientTreadmillRenders
    local ctr = Services.Workspace:FindFirstChild("__ClientTreadmillRenders")
    if ctr and Config.PlotPosition then
        local best = nil
        local bestDist = 60
        for _, child in ipairs(ctr:GetChildren()) do
            local pos = child:IsA("Model") and child:GetPivot().Position or (child:IsA("BasePart") and child.Position)
            if pos then
                local d = (pos - Config.PlotPosition).Magnitude
                if d < bestDist then
                    bestDist = d
                    best = pos + Vector3.new(0, 2.5, 0)
                end
            end
        end
        if best then return best end
    end

    -- Se não achou na pasta Plots, busca no Workspace próximo ao spawn
    local hrp = getHRP()
    if hrp then
        for _, desc in ipairs(Services.Workspace:GetDescendants()) do
            local low = desc.Name:lower()
            if (low:find("treadmill") or low:find("esteira")) and desc:IsA("BasePart") then
                local d = (desc.Position - hrp.Position).Magnitude
                if d < 120 then
                    return desc.Position + Vector3.new(0, 2.5, 0)
                end
            end
        end
    end

    return nil
end

-- Deslocamento suave até a esteira
local function walkToPosition(targetPos)
    local hrp = getHRP()
    local hum = getHumanoid()
    if not hrp or not hum or hum.Health <= 0 then return false end

    State.IsCompanionMoving = true
    local startPos = hrp.Position
    local dist = (targetPos - startPos).Magnitude

    if dist < 2.5 then
        State.IsCompanionMoving = false
        return true
    end

    -- Interpolação CFrame linear suave para subir na esteira
    local dur = math.clamp(dist / 45, 0.4, 3.0)
    local startTick = os.clock()

    while (os.clock() - startTick) < (dur + 0.1) do
        if not hum or hum.Health <= 0 or isHoldingEgg() then
            State.IsCompanionMoving = false
            return false
        end

        local alpha = math.clamp((os.clock() - startTick) / dur, 0, 1)
        local cur = startPos:Lerp(targetPos, alpha)
        hrp.CFrame = CFrame.new(cur, cur + (targetPos - cur))
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero

        if (targetPos - hrp.Position).Magnitude < 2.0 then break end
        Services.RunService.Heartbeat:Wait()
    end

    hrp.CFrame = CFrame.new(targetPos)
    State.IsCompanionMoving = false
    return true
end

-- 6. LOOP PRINCIPAL DE COOPERAÇÃO COM O BIGFROOT
task.spawn(function()
    while true do
        task.wait(0.5)

        if not Config.AutoTreadmillEnabled then
            State.CurrentStatus = "Desativado"
            State.IsOnTreadmill = false
        else
            local hrp = getHRP()
            local hum = getHumanoid()

            if hrp and hum and hum.Health > 0 then
                -- Se não tiver esteira configurada, tenta auto-detectar
                if not Config.TreadmillPosition then
                    Config.TreadmillPosition = autoDetectTreadmill()
                end

                local holdingEgg = isHoldingEgg()
                local currentPos = hrp.Position
                local moveDelta = (currentPos - State.LastPosition).Magnitude
                State.LastPosition = currentPos

                -- 1. Se estiver segurando um ovo -> BigFroot está entregando/plantando!
                if holdingEgg then
                    State.LastActiveTick = os.clock()
                    State.IsOnTreadmill = false
                    State.CurrentStatus = "BF Ativo (Plantando Ovo)"

                -- 2. Se o jogador estiver se movendo rápido para fora da base -> BigFroot roubando!
                elseif moveDelta > 15 and not State.IsCompanionMoving then
                    State.LastActiveTick = os.clock()
                    State.IsOnTreadmill = false
                    State.CurrentStatus = "BF Ativo (Voando/Roubando)"

                -- 3. Se estiver a mais de 80 studs da base -> Em outra ilha!
                elseif Config.PlotPosition and (currentPos - Config.PlotPosition).Magnitude > 90 and not State.IsCompanionMoving then
                    State.LastActiveTick = os.clock()
                    State.IsOnTreadmill = false
                    State.CurrentStatus = "BF Ativo (Na Ilha)"

                -- 4. O jogador está na base e sem ovo nas mãos!
                else
                    local idleTime = os.clock() - State.LastActiveTick

                    if idleTime >= Config.IdleThresholdSeconds then
                        -- O BigFroot terminou de plantar e está parado!
                        if Config.TreadmillPosition then
                            local distToTreadmill = (currentPos - Config.TreadmillPosition).Magnitude

                            if distToTreadmill > 3.0 and not State.IsCompanionMoving then
                                State.CurrentStatus = "Indo para a Esteira..."
                                walkToPosition(Config.TreadmillPosition)
                                State.IsOnTreadmill = true
                            else
                                State.IsOnTreadmill = true
                                State.CurrentStatus = "Ocioso: Farmando Velocidade"

                                -- Mantém o personagem ativo caminhando na esteira
                                if Config.WalkOnTreadmill then
                                    pcall(function()
                                        hum:Move(Vector3.new(0, 0, -1), false)
                                    end)
                                end
                            end
                        else
                            State.CurrentStatus = "Aguardando Posição da Esteira"
                        end
                    else
                        State.CurrentStatus = string.format("Aguardando Ociosidade (%.1fs)", math.max(0, Config.IdleThresholdSeconds - idleTime))
                    end
                end
            end
        end
    end
end)

-- 7. Anti-AFK Seguro
LocalPlayer.Idled:Connect(function()
    if Config.AntiAFK then
        pcall(function()
            Services.VirtualUser:CaptureController()
            Services.VirtualUser:ClickButton2(Vector2.new(0, 0))
        end)
    end
end)

-- 8. INTERFACE COMPACTA (CARD FLUTUANTE TECH BLUE)
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "BF_Companion_HUD"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

pcall(function()
    if gethui then ScreenGui.Parent = gethui()
    elseif Services.CoreGui then ScreenGui.Parent = Services.CoreGui
    else ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end
end)

local Card = Instance.new("Frame")
Card.Name = "CompanionCard"
Card.Size = UDim2.new(0, 240, 0, 150)
Card.Position = UDim2.new(0.82, -10, 0.05, 0)
Card.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
Card.BorderSizePixel = 0
Card.Active = true
Card.Draggable = true
Card.Parent = ScreenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = Card

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(56, 189, 248)
stroke.Thickness = 1.2
stroke.Parent = Card

-- Título
local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -16, 0, 22)
Title.Position = UDim2.new(0, 8, 0, 6)
Title.BackgroundTransparency = 1
Title.Font = Enum.Font.GothamBold
Title.TextSize = 10
Title.TextColor3 = Color3.fromRGB(56, 189, 248)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Text = "BF COMPANION - AUTO ESTEIRA"
Title.Parent = Card

-- Linha de Status
local StatusRow = Instance.new("Frame")
StatusRow.Size = UDim2.new(1, -16, 0, 24)
StatusRow.Position = UDim2.new(0, 8, 0, 30)
StatusRow.BackgroundColor3 = Color3.fromRGB(24, 33, 53)
StatusRow.BorderSizePixel = 0
StatusRow.Parent = Card
local statusCorner = Instance.new("UICorner")
statusCorner.CornerRadius = UDim.new(0, 4)
statusCorner.Parent = StatusRow

local StatusText = Instance.new("TextLabel")
StatusText.Size = UDim2.new(1, -10, 1, 0)
StatusText.Position = UDim2.new(0, 5, 0, 0)
StatusText.BackgroundTransparency = 1
StatusText.Font = Enum.Font.GothamBold
StatusText.TextSize = 9
StatusText.TextColor3 = Color3.fromRGB(241, 245, 249)
StatusText.TextXAlignment = Enum.TextXAlignment.Left
StatusText.Text = "Status: Iniciando..."
StatusText.Parent = StatusRow

-- Botão 1: Ativar / Desativar Auto-Esteira
local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Size = UDim2.new(1, -16, 0, 26)
ToggleBtn.Position = UDim2.new(0, 8, 0, 60)
ToggleBtn.BackgroundColor3 = Config.AutoTreadmillEnabled and Color3.fromRGB(34, 197, 94) or Color3.fromRGB(30, 41, 59)
ToggleBtn.Text = Config.AutoTreadmillEnabled and "AUTO ESTEIRA: ATIVADO" or "AUTO ESTEIRA: DESATIVADO"
ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.TextSize = 9
ToggleBtn.TextColor3 = Color3.fromRGB(241, 245, 249)
ToggleBtn.Parent = Card
local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(0, 4)
btnCorner.Parent = ToggleBtn

ToggleBtn.MouseButton1Click:Connect(function()
    Config.AutoTreadmillEnabled = not Config.AutoTreadmillEnabled
    ToggleBtn.BackgroundColor3 = Config.AutoTreadmillEnabled and Color3.fromRGB(34, 197, 94) or Color3.fromRGB(30, 41, 59)
    ToggleBtn.Text = Config.AutoTreadmillEnabled and "AUTO ESTEIRA: ATIVADO" or "AUTO ESTEIRA: DESATIVADO"
    saveSettings()
end)

-- Botão 2: Salvar Posição Atual como Esteira
local SetTreadmillBtn = Instance.new("TextButton")
SetTreadmillBtn.Size = UDim2.new(1, -16, 0, 26)
SetTreadmillBtn.Position = UDim2.new(0, 8, 0, 92)
SetTreadmillBtn.BackgroundColor3 = Color3.fromRGB(14, 116, 144)
SetTreadmillBtn.Text = Config.TreadmillPosition and "ESTEIRA REGISTRADA (CLIQUE P/ REDEFINIR)" or "SALVAR POSICAO ATUAL NA ESTEIRA"
SetTreadmillBtn.Font = Enum.Font.GothamBold
SetTreadmillBtn.TextSize = 8
SetTreadmillBtn.TextColor3 = Color3.fromRGB(241, 245, 249)
SetTreadmillBtn.Parent = Card
local setCorner = Instance.new("UICorner")
setCorner.CornerRadius = UDim.new(0, 4)
setCorner.Parent = SetTreadmillBtn

SetTreadmillBtn.MouseButton1Click:Connect(function()
    local hrp = getHRP()
    if hrp then
        Config.TreadmillPosition = hrp.Position
        saveSettings()
        SetTreadmillBtn.Text = "ESTEIRA SALVA COM SUCESSO!"
        task.delay(1.5, function()
            SetTreadmillBtn.Text = "ESTEIRA REGISTRADA (CLIQUE P/ REDEFINIR)"
        end)
    end
end)

-- Botão Minimizar
local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, 18, 0, 18)
MinBtn.Position = UDim2.new(1, -24, 0, 6)
MinBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
MinBtn.Text = "-"
MinBtn.Font = Enum.Font.GothamBold
MinBtn.TextSize = 10
MinBtn.TextColor3 = Color3.fromRGB(241, 245, 249)
MinBtn.Parent = Card
local minCorner = Instance.new("UICorner")
minCorner.CornerRadius = UDim.new(0, 4)
minCorner.Parent = MinBtn

local isMinimized = false
MinBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        Card.Size = UDim2.new(0, 240, 0, 32)
        StatusRow.Visible = false
        ToggleBtn.Visible = false
        SetTreadmillBtn.Visible = false
        MinBtn.Text = "+"
    else
        Card.Size = UDim2.new(0, 240, 0, 150)
        StatusRow.Visible = true
        ToggleBtn.Visible = true
        SetTreadmillBtn.Visible = true
        MinBtn.Text = "-"
    end
end)

-- Atualização contínua do texto de status na UI
task.spawn(function()
    while true do
        if StatusText and StatusText.Parent then
            StatusText.Text = "Status: " .. State.CurrentStatus
            if State.IsOnTreadmill then
                StatusText.TextColor3 = Color3.fromRGB(34, 197, 94)
            elseif State.CurrentStatus:find("BF Ativo") then
                StatusText.TextColor3 = Color3.fromRGB(56, 189, 248)
            else
                StatusText.TextColor3 = Color3.fromRGB(241, 245, 249)
            end
        end
        task.wait(0.3)
    end
end)

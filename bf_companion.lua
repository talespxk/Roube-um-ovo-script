--[[
    AUTO ESTEIRA - ASSISTENTE DE VELOCIDADE (v3.0 STEALTH & MINIMALIST)
    -----------------------------------------------------------------------
    - Neutralização Preventiva: Proteção contra BAC-9519 eliminando assinaturas
      de texto, teleporte artificial por CFrame e chamadas perigosas de input.
    - Movimentação Física Nativa: Usa exclusivamente Humanoid:MoveTo, respeitando
      a física e animação padrão do jogo (indetectável por sistema de servidor).
    - Detecção Dinâmica da Própria Base: Identifica automaticamente o plot do jogador
      em qualquer servidor/troca de mapa e localiza a sua esteira exclusiva.
    - Interface Minimalista: Design limpo de vidro escuro (210px), sem poluição
      visual, com minimização em pílula compacta e botão de encerramento rápido.
]]

-- 1. Silenciamento Total Preventivo contra LogService.MessageOut
local function silentOutput(...) end
local print = silentOutput
local warn = silentOutput

-- 2. Limpeza de Instâncias Anteriores
pcall(function()
    _G.AutoEsteira_Active = nil
    if getgenv then getgenv().AutoEsteira_Active = nil end
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
    HttpService = safeService("HttpService"),
    TweenService = safeService("TweenService")
}

local LocalPlayer = Services.Players.LocalPlayer
while not LocalPlayer do
    task.wait(0.2)
    LocalPlayer = Services.Players.LocalPlayer
end

-- 4. Variáveis de Ciclo de Vida e Controle
local isRunning = true
local activeConnections = {}

-- 5. Neutralização de Scripts Locais de Colisão no Personagem
local function disableCharacterPushback(char)
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
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
            hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
        end
    end)
end

if LocalPlayer.Character then
    disableCharacterPushback(LocalPlayer.Character)
end

local charConn = LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.2)
    disableCharacterPushback(char)
end)
table.insert(activeConnections, charConn)

-- 6. Configurações e Estado
local Config = {
    Enabled = true,
    IdleThresholdSeconds = 2.0,
    TreadmillPosition = nil,
    TreadmillLookVector = Vector3.new(0, 0, -1),
    PlotPosition = nil,
    SettingsFile = "auto_esteira_config.json"
}

local State = {
    CurrentStatus = "Iniciando...",
    PlotFound = false,
    TreadmillFound = false,
    HoldingEgg = false,
    IsOnTreadmill = false,
    LastActiveTick = os.clock(),
    LastPosition = Vector3.zero
}

-- Funções Auxiliares do Personagem
local function getHRP()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
    local c = LocalPlayer.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

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

-- 7. Detecção Rigorosa de Posse de Ovo (Sem Falso-Positivo)
local function checkIsHoldingEgg()
    local char = LocalPlayer.Character
    if not char then return false end

    -- Atributos de posse
    for _, attr in ipairs({"EggUid", "CarryingEgg", "HoldingEgg", "HasEgg", "StolenEgg", "Carrying"}) do
        local val = char:GetAttribute(attr)
        if val ~= nil and val ~= "" and val ~= false then
            return true
        end
        local valP = LocalPlayer:GetAttribute(attr)
        if valP ~= nil and valP ~= "" and valP ~= false then
            return true
        end
    end

    -- Modelos ou ferramentas soldadas que não sejam partes do corpo
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
                    if hasWeld then
                        return true
                    end
                end
            end
        end
    end

    -- Mochila
    local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
    if bp then
        for _, item in ipairs(bp:GetChildren()) do
            if item:IsA("Tool") then
                local n = item.Name:lower()
                if n:find("egg") or n:find("ovo") or item:GetAttribute("IsEgg") then
                    return true
                end
            end
        end
    end

    return false
end

-- 8. ALGORITMO ROBUSTO: DETECTAR A PRÓPRIA BASE (PLOT)
local function findMyPlot()
    local plots = Services.Workspace:FindFirstChild("Plots")
    if not plots then return nil end

    local myName = LocalPlayer.Name:lower()
    local myDisplay = LocalPlayer.DisplayName:lower()
    local myId = tostring(LocalPlayer.UserId)

    -- Camada 1: Identificação direta por Objeto/Valor de Dono
    for _, plot in ipairs(plots:GetChildren()) do
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

        -- Camada 2: Atributos no Plot
        for k, v in pairs(plot:GetAttributes()) do
            local s = tostring(v):lower()
            if s == myName or s == myDisplay or s == myId then
                return plot
            end
        end

        -- Camada 3: Placas de Texto com Nome do Jogador dentro da Base
        for _, desc in ipairs(plot:GetDescendants()) do
            if desc:IsA("TextLabel") or desc:IsA("TextButton") then
                local txt = desc.Text:lower()
                if txt:find(myName) or txt:find(myDisplay) then
                    return plot
                end
            end
        end
    end

    -- Camada 4: Base mais próxima da posição atual do jogador na base
    local hrp = getHRP()
    if hrp then
        local bestPlot = nil
        local bestDist = 65
        for _, plot in ipairs(plots:GetChildren()) do
            local pPos = plot:IsA("Model") and plot:GetPivot().Position or (plot:IsA("BasePart") and plot.Position)
            if pPos then
                local d = (pPos - hrp.Position).Magnitude
                if d < bestDist then
                    bestDist = d
                    bestPlot = plot
                end
            end
        end
        if bestPlot then return bestPlot end
    end

    return nil
end

-- 9. ALGORITMO EXCLUSIVO: DETECTAR A PRÓPRIA ESTEIRA (NUNCA A DOS OUTROS)
local function findMyTreadmill(myPlot)
    if not myPlot then return nil, nil end

    local plotPivot = myPlot:GetPivot()
    local plotCenter = plotPivot.Position

    -- A. Buscar peças nomeadas dentro do próprio Plot
    for _, desc in ipairs(myPlot:GetDescendants()) do
        local low = desc.Name:lower()
        if low:find("treadmill") or low:find("esteira") or low:find("belt") or low:find("speed") or low:find("treino") then
            if desc:IsA("BasePart") then
                return desc.Position + Vector3.new(0, 2.5, 0), desc.CFrame.LookVector
            elseif desc:IsA("Model") then
                return desc:GetPivot().Position + Vector3.new(0, 2.5, 0), desc:GetPivot().LookVector
            end
        end
    end

    -- B. Buscar na pasta __ClientTreadmillRenders (estritamente dentro de 45 studs do centro da base do jogador)
    local ctr = Services.Workspace:FindFirstChild("__ClientTreadmillRenders")
    if ctr then
        local bestCandidate = nil
        local bestDist = 45 -- Limite rigoroso: só aceita se estiver dentro do raio da própria base

        for _, child in ipairs(ctr:GetChildren()) do
            local pos = child:IsA("Model") and child:GetPivot().Position or (child:IsA("BasePart") and child.Position)
            if pos then
                local distFromMyPlot = (pos - plotCenter).Magnitude
                if distFromMyPlot < bestDist then
                    bestDist = distFromMyPlot
                    bestCandidate = child
                end
            end
        end

        if bestCandidate then
            local pos = bestCandidate:IsA("Model") and bestCandidate:GetPivot().Position or bestCandidate.Position
            local look = bestCandidate:IsA("Model") and bestCandidate:GetPivot().LookVector or bestCandidate.CFrame.LookVector
            return pos + Vector3.new(0, 2.5, 0), look
        end
    end

    -- C. Buscar partes com TouchInterest próximo ao piso do próprio plot
    for _, desc in ipairs(myPlot:GetDescendants()) do
        if desc:IsA("TouchTransmitter") or desc:IsA("TouchInterest") or desc.Name == "TouchInterest" then
            local p = desc.Parent
            if p and p:IsA("BasePart") then
                local diffY = math.abs(p.Position.Y - plotCenter.Y)
                if diffY < 12 then
                    return p.Position + Vector3.new(0, 2.5, 0), p.CFrame.LookVector
                end
            end
        end
    end

    return nil, nil
end

local function updateTreadmillTarget()
    local myPlot = findMyPlot()
    if myPlot then
        State.PlotFound = true
        Config.PlotPosition = myPlot:GetPivot().Position
        local pos, look = findMyTreadmill(myPlot)
        if pos then
            Config.TreadmillPosition = pos
            if look then Config.TreadmillLookVector = look end
            State.TreadmillFound = true
            return true
        end
    end
    State.TreadmillFound = false
    return false
end

-- 10. MOVIMENTAÇÃO 100% FÍSICA E SEGURA (HUMANOID:MOVETO)
local function safeWalkTo(targetPos)
    local hum = getHumanoid()
    if not hum or hum.Health <= 0 then return end
    hum:MoveTo(targetPos)
end

-- 11. LOOP PRINCIPAL DE COOPERAÇÃO DISCRETA
task.spawn(function()
    while isRunning do
        task.wait(0.35)
        if not isRunning then break end

        if not Config.Enabled then
            State.CurrentStatus = "Pausado"
            State.IsOnTreadmill = false
        else
            local hrp = getHRP()
            local hum = getHumanoid()

            if hrp and hum and hum.Health > 0 then
                -- Atualizar esteira se ainda não encontrada
                if not Config.TreadmillPosition or not State.TreadmillFound then
                    updateTreadmillTarget()
                end

                local holding = checkIsHoldingEgg()
                State.HoldingEgg = holding

                local currentPos = hrp.Position
                local moveDelta = (currentPos - State.LastPosition).Magnitude
                State.LastPosition = currentPos

                local distFromPlot = Config.PlotPosition and (currentPos - Config.PlotPosition).Magnitude or 0

                -- 1. Segurando ovo -> Outro script está plantando!
                if holding then
                    State.LastActiveTick = os.clock()
                    State.IsOnTreadmill = false
                    State.CurrentStatus = "Plantando Ovo"

                -- 2. Movimento rápido ou fora da base -> Outro script roubando/voando!
                elseif (distFromPlot > 60 or moveDelta > 15) and Config.PlotPosition then
                    State.LastActiveTick = os.clock()
                    State.IsOnTreadmill = false
                    State.CurrentStatus = "Operando no Mapa"

                -- 3. Na base sem ovos em mãos!
                else
                    local idleTime = os.clock() - State.LastActiveTick

                    if idleTime >= Config.IdleThresholdSeconds then
                        if Config.TreadmillPosition then
                            local distToTreadmill = (currentPos - Config.TreadmillPosition).Magnitude

                            if distToTreadmill > 3.5 then
                                State.CurrentStatus = "Indo para a Esteira..."
                                safeWalkTo(Config.TreadmillPosition)
                                State.IsOnTreadmill = false
                            else
                                State.IsOnTreadmill = true
                                State.CurrentStatus = "Na Esteira (Treinando)"

                                -- Manter caminhada na esteira contra o sentido da correia
                                safeWalkTo(Config.TreadmillPosition + Config.TreadmillLookVector * 4)
                            end
                        else
                            State.CurrentStatus = "Procurando Esteira..."
                        end
                    else
                        State.CurrentStatus = string.format("Aguardando (%.1fs)", math.max(0, Config.IdleThresholdSeconds - idleTime))
                    end
                end
            end
        end
    end
end)

-- 12. FUNÇÃO UNLOAD COMPLETA
local ScreenGui = nil

local function unloadCompanion()
    isRunning = false

    for _, conn in ipairs(activeConnections) do
        pcall(function() conn:Disconnect() end)
    end
    activeConnections = {}

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

-- 13. PROTEÇÃO ANTECIPADA DA INTERFACE GRÁFICA
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

-- 14. INTERFACE MINIMALISTA, ELEGANTE E DISCRETA (v3.0)
local randomId = Services.HttpService:GenerateGUID(false):sub(1, 8)
ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "HUD_" .. randomId
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

protectGui(ScreenGui)
ScreenGui.Parent = getGuiContainer()

-- Card Principal (apenas 210px de largura, vidro escuro fosco)
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
cardLayout.Padding = UDim.new(0, 6)
cardLayout.Parent = Card

-- Header: Indicador, Título, Minimizar e Fechar
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
Title.Text = "Auto Esteira"
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

-- Container de Conteúdo Expansível
local ContentBox = Instance.new("Frame")
ContentBox.Size = UDim2.new(1, 0, 0, 0)
ContentBox.AutomaticSize = Enum.AutomaticSize.Y
ContentBox.BackgroundTransparency = 1
ContentBox.LayoutOrder = 2
ContentBox.Parent = Card

local contentLayout = Instance.new("UIListLayout")
contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
contentLayout.Padding = UDim.new(0, 5)
contentLayout.Parent = ContentBox

-- 1. Linha de Status Compacta
local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, 0, 0, 18)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Font = Enum.Font.SourceSansBold
StatusLabel.TextSize = 12
StatusLabel.TextColor3 = Color3.fromRGB(16, 185, 129)
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.Text = "Status: Procurando..."
StatusLabel.Parent = ContentBox

-- 2. Linha de Detecção da Base & Esteira
local EsteiraLabel = Instance.new("TextLabel")
EsteiraLabel.Size = UDim2.new(1, 0, 0, 15)
EsteiraLabel.BackgroundTransparency = 1
EsteiraLabel.Font = Enum.Font.SourceSans
EsteiraLabel.TextSize = 11
EsteiraLabel.TextColor3 = Color3.fromRGB(148, 163, 184)
EsteiraLabel.TextXAlignment = Enum.TextXAlignment.Left
EsteiraLabel.Text = "Base: Buscando... | Esteira: ..."
EsteiraLabel.Parent = ContentBox

-- 3. Botão Único Liga/Desliga Minimalista
local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Size = UDim2.new(1, 0, 0, 26)
ToggleBtn.BackgroundColor3 = Color3.fromRGB(16, 80, 50)
ToggleBtn.Text = "ESTEIRA: LIGADA"
ToggleBtn.Font = Enum.Font.SourceSansBold
ToggleBtn.TextSize = 12
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
    else
        ToggleBtn.Text = "ESTEIRA: DESLIGADA"
        ToggleBtn.BackgroundColor3 = Color3.fromRGB(35, 42, 54)
        ToggleBtn.TextColor3 = Color3.fromRGB(160, 175, 195)
    end
end)

-- 4. Ação Discreta de Re-escanear Base/Esteira
local RescanBtn = Instance.new("TextButton")
RescanBtn.Size = UDim2.new(1, 0, 0, 16)
RescanBtn.BackgroundTransparency = 1
RescanBtn.Text = "Reescanear Própria Base"
RescanBtn.Font = Enum.Font.SourceSans
RescanBtn.TextSize = 10
RescanBtn.TextColor3 = Color3.fromRGB(56, 189, 248)
RescanBtn.Parent = ContentBox

RescanBtn.MouseButton1Click:Connect(function()
    RescanBtn.Text = "Escaneando mapa..."
    Config.TreadmillPosition = nil
    updateTreadmillTarget()
    task.delay(1, function()
        RescanBtn.Text = "Reescanear Própria Base"
    end)
end)

-- Minimização Elegante (Pílula Compacta)
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

-- 15. Atualização Contínua e Suave do Status na Interface
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
            else
                StatusLabel.TextColor3 = Color3.fromRGB(56, 189, 248)
                StatusDot.BackgroundColor3 = Color3.fromRGB(56, 189, 248)
            end

            local baseText = State.PlotFound and "Sua Base: OK" or "Buscando Base..."
            local esteiraText = State.TreadmillFound and "Esteira: OK" or "Buscando..."
            EsteiraLabel.Text = baseText .. " | " .. esteiraText
        end
        task.wait(0.3)
    end
end)

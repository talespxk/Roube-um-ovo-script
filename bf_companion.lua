--[[
    BIGFROOT COMPANION - AUTO ESTEIRA, AUTO-EXECUTE & SPEED FARM (v2.0 DEFINITIVA)
    -----------------------------------------------------------------------
    Script complementar ultra-leve desenvolvido para rodar EM CONJUNTO com o BigFroot (BF).
    
    CORREÇÕES v2.0:
    - Correção de Detecção de Ovo: Corrigido o bug onde o status ficava preso em
      "BF Ativo (Plantando Ovo)" por conta do AssetEggData.Enabled ser sempre true.
      Agora a verificação é estrita e exata (só ativa se houver de fato um ovo sendo carregado).
    - Interface 100% Legível e Nítida: Tipografia refeita com fonte SourceSansBold / Arial,
      tamanho aumentado para 13-14px, contraste calibrado e botões alargados para 32px de altura.
    - Indicador de Telemetria ao Vivo: Exibe claramente na tela se há ovo em mãos e
      qual é o estado real de ociosidade do BigFroot.
    - Auto-Execute (queue_on_teleport) e Instalador de Autoexec mantidos e otimizados.
]]

-- 1. Silenciamento Preventivo contra LogService
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
    HttpService = safeService("HttpService"),
    TeleportService = safeService("TeleportService")
}

local LocalPlayer = Services.Players.LocalPlayer
while not LocalPlayer do
    task.wait(0.2)
    LocalPlayer = Services.Players.LocalPlayer
end

-- 4. Configurações e Estado
local Config = {
    AutoTreadmillEnabled = true,
    IdleThresholdSeconds = 2.0,
    WalkOnTreadmill = true,
    AntiAFK = true,
    AutoReloadOnTeleport = true,
    AutoLaunchBF = false,
    TreadmillPosition = nil,
    PlotPosition = nil,
    SettingsFile = "bf_companion_settings.json",
    CompanionURL = "https://raw.githubusercontent.com/talespxk/Roube-um-ovo-script/refs/heads/main/bf_companion.lua",
    BFLoaderURL = "https://raw.githubusercontent.com/hanniii1/Loader/refs/heads/main/BFLoader.lua"
}

local State = {
    CurrentStatus = "Iniciando...",
    HoldingEggDetected = false,
    HoldingEggName = nil,
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
            AntiAFK = Config.AntiAFK,
            AutoReloadOnTeleport = Config.AutoReloadOnTeleport,
            AutoLaunchBF = Config.AutoLaunchBF
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
            if data.AutoReloadOnTeleport ~= nil then Config.AutoReloadOnTeleport = data.AutoReloadOnTeleport end
            if data.AutoLaunchBF ~= nil then Config.AutoLaunchBF = data.AutoLaunchBF end
            if data.TreadmillX and data.TreadmillY and data.TreadmillZ then
                Config.TreadmillPosition = Vector3.new(data.TreadmillX, data.TreadmillY, data.TreadmillZ)
            end
        end
    end)
end
loadSettings()

-- 5. MECANISMO DE AUTO-EXECUTE (QUEUE ON TELEPORT & AUTOEXEC INSTALLER)
local function armTeleportAutoExecute()
    if not Config.AutoReloadOnTeleport then return end
    local qot = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
    if qot then
        local payload = string.format([[
            repeat task.wait() until game:IsLoaded()
            task.wait(2)
            pcall(function()
                loadstring(game:HttpGet("%s"))()
            end)
        ]], Config.CompanionURL)
        pcall(function() qot(payload) end)
    end
end

armTeleportAutoExecute()

pcall(function()
    LocalPlayer.OnTeleport:Connect(function()
        armTeleportAutoExecute()
    end)
end)

local function installToAutoexec()
    if not writefile then return false, "writefile indisponível" end
    local scriptContent = string.format([[-- Auto-Execute Oficial: BF Companion (Roube um Ovo)
if game.PlaceId == 107778070777162 or game.PlaceId == 0 then
    repeat task.wait() until game:IsLoaded()
    task.wait(2)
    pcall(function()
        loadstring(game:HttpGet("%s"))()
    end)
end
]], Config.CompanionURL)
    local ok, err = pcall(function()
        writefile("autoexec/bf_companion_auto.lua", scriptContent)
    end)
    return ok, err
end

local function executeBigFrootNow()
    task.spawn(function()
        pcall(function()
            loadstring(game:HttpGet(Config.BFLoaderURL))()
        end)
    end)
end

if Config.AutoLaunchBF then
    task.delay(2, function()
        executeBigFrootNow()
    end)
end

-- 6. Funções Auxiliares do Personagem
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

-- DETECÇÃO CORRIGIDA DE OVO EM MÃOS (SEM FALSO-POSITIVO)
local function checkIsHoldingEgg()
    local char = LocalPlayer.Character
    if not char then return false, nil end

    -- 1. Atributos ESPECÍFICOS de posse de ovo (não busca termos genéricos)
    for _, attr in ipairs({"EggUid", "CarryingEgg", "HoldingEgg", "HasEgg", "StolenEgg", "Carrying"}) do
        local val = char:GetAttribute(attr)
        if val ~= nil and val ~= "" and val ~= false then
            return true, attr .. "=" .. tostring(val)
        end
        local valP = LocalPlayer:GetAttribute(attr)
        if valP ~= nil and valP ~= "" and valP ~= false then
            return true, attr .. "=" .. tostring(valP)
        end
    end

    -- 2. Modelos ou Peças soldadas que contenham "egg" ou "ovo" (ex: Chicken Egg)
    for _, child in ipairs(char:GetChildren()) do
        local low = child.Name:lower()
        if not standardLimbNames[low] and not child:IsA("Accessory") and not child:IsA("Shirt")
            and not child:IsA("Pants") and not child:IsA("BodyColors") and not child:IsA("CharacterMesh") then
            
            local isEggName = low:find("egg") or low:find("ovo") or child:GetAttribute("IsEgg") == true
            if isEggName then
                if child:IsA("Tool") then
                    return true, child.Name
                elseif child:IsA("Model") or child:IsA("BasePart") then
                    local hasWeld = child:FindFirstChildWhichIsA("WeldConstraint", true)
                        or child:FindFirstChildWhichIsA("Weld", true)
                        or child:FindFirstChildWhichIsA("Motor6D", true)
                    if hasWeld then
                        return true, child.Name
                    end
                end
            end
        end
    end

    -- 3. Mochila
    local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
    if bp then
        for _, item in ipairs(bp:GetChildren()) do
            if item:IsA("Tool") then
                local n = item.Name:lower()
                if n:find("egg") or n:find("ovo") or item:GetAttribute("IsEgg") then
                    return true, item.Name
                end
            end
        end
    end

    -- 4. GUI de dados do ovo (APENAS se houver frame VISÍVEL ativo, nunca checar só .Enabled)
    local pgui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if pgui then
        local eggDataGui = pgui:FindFirstChild("AssetEggData")
        if eggDataGui and eggDataGui.Enabled then
            for _, child in ipairs(eggDataGui:GetChildren()) do
                if child:IsA("GuiObject") and child.Visible and child.Size.Y.Offset > 20 then
                    return true, "AssetEggData (Visível)"
                end
            end
        end
    end

    return false, nil
end

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

    local dur = math.clamp(dist / 40, 0.3, 2.5)
    local startTick = os.clock()

    while (os.clock() - startTick) < (dur + 0.1) do
        local holdingNow = checkIsHoldingEgg()
        if not hum or hum.Health <= 0 or holdingNow then
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

-- 7. LOOP DE COOPERAÇÃO COM O BIGFROOT
task.spawn(function()
    while true do
        task.wait(0.4)

        if not Config.AutoTreadmillEnabled then
            State.CurrentStatus = "Desativado pelo Usuário"
            State.IsOnTreadmill = false
        else
            local hrp = getHRP()
            local hum = getHumanoid()

            if hrp and hum and hum.Health > 0 then
                if not Config.TreadmillPosition then
                    Config.TreadmillPosition = autoDetectTreadmill()
                end

                local holdingEgg, eggName = checkIsHoldingEgg()
                State.HoldingEggDetected = holdingEgg
                State.HoldingEggName = eggName

                local currentPos = hrp.Position
                local moveDelta = (currentPos - State.LastPosition).Magnitude
                State.LastPosition = currentPos

                -- CASO 1: Segurando ovo -> BigFroot está carregando/plantando!
                if holdingEgg then
                    State.LastActiveTick = os.clock()
                    State.IsOnTreadmill = false
                    State.CurrentStatus = "BF Plantando (" .. tostring(eggName) .. ")"

                -- CASO 2: Movimento rápido para fora da esteira -> BigFroot roubando!
                elseif moveDelta > 12 and not State.IsCompanionMoving then
                    State.LastActiveTick = os.clock()
                    State.IsOnTreadmill = false
                    State.CurrentStatus = "BF Ativo (Voando/Roubando)"

                -- CASO 3: Longe da base (> 90 studs) -> Em outra ilha!
                elseif Config.PlotPosition and (currentPos - Config.PlotPosition).Magnitude > 90 and not State.IsCompanionMoving then
                    State.LastActiveTick = os.clock()
                    State.IsOnTreadmill = false
                    State.CurrentStatus = "BF Ativo (Na Ilha)"

                -- CASO 4: Na base sem ovos em mãos!
                else
                    local idleTime = os.clock() - State.LastActiveTick

                    if idleTime >= Config.IdleThresholdSeconds then
                        if Config.TreadmillPosition then
                            local distToTreadmill = (currentPos - Config.TreadmillPosition).Magnitude

                            if distToTreadmill > 3.0 and not State.IsCompanionMoving then
                                State.CurrentStatus = "Indo para a Esteira..."
                                walkToPosition(Config.TreadmillPosition)
                                State.IsOnTreadmill = true
                            else
                                State.IsOnTreadmill = true
                                State.CurrentStatus = "Ocioso: Farmando Velocidade"

                                if Config.WalkOnTreadmill then
                                    pcall(function()
                                        hum:Move(Vector3.new(0, 0, -1), false)
                                    end)
                                end
                            end
                        else
                            State.CurrentStatus = "Defina a Esteira no Botão Abaixo"
                        end
                    else
                        State.CurrentStatus = string.format("Aguardando Ociosidade (%.1fs)", math.max(0, Config.IdleThresholdSeconds - idleTime))
                    end
                end
            end
        end
    end
end)

-- 8. Anti-AFK Seguro
LocalPlayer.Idled:Connect(function()
    if Config.AntiAFK then
        pcall(function()
            Services.VirtualUser:CaptureController()
            Services.VirtualUser:ClickButton2(Vector2.new(0, 0))
        end)
    end
end)

-- 9. INTERFACE VISUAL DE ALTA LEGIBILIDADE (FONTE NÍTIDA, ALTO CONTRASTE)
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
Card.Size = UDim2.new(0, 310, 0, 0)
Card.AutomaticSize = Enum.AutomaticSize.Y
Card.Position = UDim2.new(0.78, -10, 0.05, 0)
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
stroke.Thickness = 1.5
stroke.Parent = Card

local cardPad = Instance.new("UIPadding")
cardPad.PaddingTop = UDim.new(0, 10)
cardPad.PaddingBottom = UDim.new(0, 12)
cardPad.PaddingLeft = UDim.new(0, 12)
cardPad.PaddingRight = UDim.new(0, 12)
cardPad.Parent = Card

local cardLayout = Instance.new("UIListLayout")
cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
cardLayout.Padding = UDim.new(0, 7)
cardLayout.Parent = Card

-- Header
local HeaderFrame = Instance.new("Frame")
HeaderFrame.Size = UDim2.new(1, 0, 0, 24)
HeaderFrame.BackgroundTransparency = 1
HeaderFrame.LayoutOrder = 1
HeaderFrame.Parent = Card

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -30, 1, 0)
Title.BackgroundTransparency = 1
Title.Font = Enum.Font.SourceSansBold
Title.TextSize = 15
Title.TextColor3 = Color3.fromRGB(56, 189, 248)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Text = "BF COMPANION v2.0"
Title.Parent = HeaderFrame

local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, 24, 0, 22)
MinBtn.Position = UDim2.new(1, -24, 0, 1)
MinBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
MinBtn.Text = "-"
MinBtn.Font = Enum.Font.SourceSansBold
MinBtn.TextSize = 15
MinBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
MinBtn.Parent = HeaderFrame
local minCorner = Instance.new("UICorner")
minCorner.CornerRadius = UDim.new(0, 4)
minCorner.Parent = MinBtn

-- Container de Conteúdo
local ContentBox = Instance.new("Frame")
ContentBox.Size = UDim2.new(1, 0, 0, 0)
ContentBox.AutomaticSize = Enum.AutomaticSize.Y
ContentBox.BackgroundTransparency = 1
ContentBox.LayoutOrder = 2
ContentBox.Parent = Card

local boxLayout = Instance.new("UIListLayout")
boxLayout.SortOrder = Enum.SortOrder.LayoutOrder
boxLayout.Padding = UDim.new(0, 6)
boxLayout.Parent = ContentBox

-- 1. Status Principal
local StatusRow = Instance.new("Frame")
StatusRow.Size = UDim2.new(1, 0, 0, 28)
StatusRow.BackgroundColor3 = Color3.fromRGB(24, 33, 53)
StatusRow.BorderSizePixel = 0
StatusRow.Parent = ContentBox
local statusCorner = Instance.new("UICorner")
statusCorner.CornerRadius = UDim.new(0, 5)
statusCorner.Parent = StatusRow

local StatusText = Instance.new("TextLabel")
StatusText.Size = UDim2.new(1, -12, 1, 0)
StatusText.Position = UDim2.new(0, 8, 0, 0)
StatusText.BackgroundTransparency = 1
StatusText.Font = Enum.Font.SourceSansBold
StatusText.TextSize = 13
StatusText.TextColor3 = Color3.fromRGB(255, 255, 255)
StatusText.TextXAlignment = Enum.TextXAlignment.Left
StatusText.Text = "Status: Carregando..."
StatusText.Parent = StatusRow

-- 2. Toggle Auto-Esteira (Verde Nítido)
local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Size = UDim2.new(1, 0, 0, 32)
ToggleBtn.BackgroundColor3 = Config.AutoTreadmillEnabled and Color3.fromRGB(16, 185, 129) or Color3.fromRGB(51, 65, 85)
ToggleBtn.Text = Config.AutoTreadmillEnabled and "AUTO ESTEIRA: ATIVADO" or "AUTO ESTEIRA: DESATIVADO"
ToggleBtn.Font = Enum.Font.SourceSansBold
ToggleBtn.TextSize = 13
ToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleBtn.Parent = ContentBox
local btnCorner1 = Instance.new("UICorner")
btnCorner1.CornerRadius = UDim.new(0, 5)
btnCorner1.Parent = ToggleBtn

ToggleBtn.MouseButton1Click:Connect(function()
    Config.AutoTreadmillEnabled = not Config.AutoTreadmillEnabled
    ToggleBtn.BackgroundColor3 = Config.AutoTreadmillEnabled and Color3.fromRGB(16, 185, 129) or Color3.fromRGB(51, 65, 85)
    ToggleBtn.Text = Config.AutoTreadmillEnabled and "AUTO ESTEIRA: ATIVADO" or "AUTO ESTEIRA: DESATIVADO"
    saveSettings()
end)

-- 3. Salvar Esteira (Azul Oceano Nítido)
local SetTreadmillBtn = Instance.new("TextButton")
SetTreadmillBtn.Size = UDim2.new(1, 0, 0, 32)
SetTreadmillBtn.BackgroundColor3 = Color3.fromRGB(2, 132, 199)
SetTreadmillBtn.Text = Config.TreadmillPosition and "ESTEIRA SALVA (CLIQUE P/ REDEFINIR)" or "SALVAR POSIÇÃO DA ESTEIRA AQUI"
SetTreadmillBtn.Font = Enum.Font.SourceSansBold
SetTreadmillBtn.TextSize = 13
SetTreadmillBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
SetTreadmillBtn.Parent = ContentBox
local btnCorner2 = Instance.new("UICorner")
btnCorner2.CornerRadius = UDim.new(0, 5)
btnCorner2.Parent = SetTreadmillBtn

SetTreadmillBtn.MouseButton1Click:Connect(function()
    local hrp = getHRP()
    if hrp then
        Config.TreadmillPosition = hrp.Position
        saveSettings()
        SetTreadmillBtn.Text = "ESTEIRA GRAVADA COM SUCESSO!"
        task.delay(1.5, function()
            SetTreadmillBtn.Text = "ESTEIRA SALVA (CLIQUE P/ REDEFINIR)"
        end)
    end
end)

-- 4. Botão: Executar BigFroot Agora (Azul Céu)
local RunBFBtn = Instance.new("TextButton")
RunBFBtn.Size = UDim2.new(1, 0, 0, 30)
RunBFBtn.BackgroundColor3 = Color3.fromRGB(56, 189, 248)
RunBFBtn.Text = "EXECUTAR BIGFROOT AGORA"
RunBFBtn.Font = Enum.Font.SourceSansBold
RunBFBtn.TextSize = 13
RunBFBtn.TextColor3 = Color3.fromRGB(15, 23, 42)
RunBFBtn.Parent = ContentBox
local btnCorner3 = Instance.new("UICorner")
btnCorner3.CornerRadius = UDim.new(0, 5)
btnCorner3.Parent = RunBFBtn

RunBFBtn.MouseButton1Click:Connect(function()
    RunBFBtn.Text = "CARREGANDO BIGFROOT..."
    executeBigFrootNow()
    task.delay(2, function()
        RunBFBtn.Text = "EXECUTAR BIGFROOT AGORA"
    end)
end)

-- 5. Toggle: Auto-Iniciar BigFroot Junto
local AutoLaunchBFBtn = Instance.new("TextButton")
AutoLaunchBFBtn.Size = UDim2.new(1, 0, 0, 26)
AutoLaunchBFBtn.BackgroundColor3 = Config.AutoLaunchBF and Color3.fromRGB(16, 185, 129) or Color3.fromRGB(51, 65, 85)
AutoLaunchBFBtn.Text = Config.AutoLaunchBF and "INICIAR BF JUNTO: LIGADO" or "INICIAR BF JUNTO: DESLIGADO"
AutoLaunchBFBtn.Font = Enum.Font.SourceSansBold
AutoLaunchBFBtn.TextSize = 12
AutoLaunchBFBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
AutoLaunchBFBtn.Parent = ContentBox
local btnCorner4 = Instance.new("UICorner")
btnCorner4.CornerRadius = UDim.new(0, 5)
btnCorner4.Parent = AutoLaunchBFBtn

AutoLaunchBFBtn.MouseButton1Click:Connect(function()
    Config.AutoLaunchBF = not Config.AutoLaunchBF
    AutoLaunchBFBtn.BackgroundColor3 = Config.AutoLaunchBF and Color3.fromRGB(16, 185, 129) or Color3.fromRGB(51, 65, 85)
    AutoLaunchBFBtn.Text = Config.AutoLaunchBF and "INICIAR BF JUNTO: LIGADO" or "INICIAR BF JUNTO: DESLIGADO"
    saveSettings()
end)

-- 6. Botão: Instalar no Autoexec do Executor
local InstallAutoexecBtn = Instance.new("TextButton")
InstallAutoexecBtn.Size = UDim2.new(1, 0, 0, 26)
InstallAutoexecBtn.BackgroundColor3 = Color3.fromRGB(51, 65, 85)
InstallAutoexecBtn.Text = "INSTALAR NO AUTOEXEC DO EXECUTOR"
InstallAutoexecBtn.Font = Enum.Font.SourceSansBold
InstallAutoexecBtn.TextSize = 12
InstallAutoexecBtn.TextColor3 = Color3.fromRGB(203, 213, 225)
InstallAutoexecBtn.Parent = ContentBox
local btnCorner5 = Instance.new("UICorner")
btnCorner5.CornerRadius = UDim.new(0, 5)
btnCorner5.Parent = InstallAutoexecBtn

InstallAutoexecBtn.MouseButton1Click:Connect(function()
    local ok, err = installToAutoexec()
    if ok then
        InstallAutoexecBtn.Text = "GRAVADO NO AUTOEXEC COM SUCESSO!"
        InstallAutoexecBtn.TextColor3 = Color3.fromRGB(16, 185, 129)
    else
        InstallAutoexecBtn.Text = "ERRO AO GRAVAR AUTOEXEC"
        InstallAutoexecBtn.TextColor3 = Color3.fromRGB(239, 68, 68)
    end
    task.delay(3, function()
        InstallAutoexecBtn.Text = "INSTALAR NO AUTOEXEC DO EXECUTOR"
        InstallAutoexecBtn.TextColor3 = Color3.fromRGB(203, 213, 225)
    end)
end)

-- Minimização
local isMinimized = false
MinBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    ContentBox.Visible = not isMinimized
    MinBtn.Text = isMinimized and "+" or "-"
end)

-- Atualização contínua do status na interface com cores dinâmicas
task.spawn(function()
    while true do
        if StatusText and StatusText.Parent then
            StatusText.Text = "Status: " .. State.CurrentStatus
            if State.IsOnTreadmill then
                StatusText.TextColor3 = Color3.fromRGB(16, 185, 129) -- Verde
            elseif State.CurrentStatus:find("BF") then
                StatusText.TextColor3 = Color3.fromRGB(56, 189, 248) -- Azul ciano
            elseif State.CurrentStatus:find("Aguardando") then
                StatusText.TextColor3 = Color3.fromRGB(251, 191, 36) -- Dourado
            else
                StatusText.TextColor3 = Color3.fromRGB(255, 255, 255)
            end
        end
        task.wait(0.3)
    end
end)

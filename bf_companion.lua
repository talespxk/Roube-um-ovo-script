--[[
    BIGFROOT COMPANION - AUTO ESTEIRA, AUTO-EXECUTE & SPEED FARM (v1.5)
    -----------------------------------------------------------------------
    Script complementar ultra-leve desenvolvido para rodar EM CONJUNTO com o BigFroot (BF).
    
    NOVIDADES v1.5:
    - Auto-Execute ao Reconectar / Server Hop: Usa queue_on_teleport para reexecutar
      automaticamente toda vez que trocar de servidor ou reconectar.
    - Instalador de Autoexec: Botão de 1 clique para gravar o loader no autoexec
      do seu executor (inicia sozinho mesmo se fechar o Roblox e abrir depois).
    - Integração BigFroot Opcional:
        > Botão "EXECUTAR BIGFROOT AGORA" para disparar o BF com 1 clique.
        > Alternador "AUTO-INICIAR BF JUNTO" (opcional caso você queira que este
          script inicie o BF sozinho).
    - Detecção Inteligente de Ociosidade:
        > Enquanto o BF rouba ou planta ovos: O Companion não interfere.
        > Quando o BF termina e fica parado na base: O Companion leva o personagem
          para a esteira para farmar velocidade infinita!
        > Quando novos ovos nascem e o BF começa a se mover: O Companion cede o
          controle na hora!
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

-- Armar preventivamente
armTeleportAutoExecute()

pcall(function()
    LocalPlayer.OnTeleport:Connect(function(teleportState)
        armTeleportAutoExecute()
    end)
end)

-- Gravação no Autoexec do executor (para persistir ao fechar o jogo)
local function installToAutoexec()
    if not writefile then return false, "Função writefile não suportada pelo executor." end
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

-- Execução do BigFroot sob demanda
local function executeBigFrootNow()
    task.spawn(function()
        pcall(function()
            loadstring(game:HttpGet(Config.BFLoaderURL))()
        end)
    end)
end

-- Se configurado para iniciar o BF junto, dispara após 2 segundos
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

-- Detecção de posse de ovo
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

    local pgui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if pgui then
        local eggDataGui = pgui:FindFirstChild("AssetEggData")
        if eggDataGui and eggDataGui.Enabled then return true end
    end

    return false
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

-- 7. LOOP DE COOPERAÇÃO COM O BIGFROOT
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
                if not Config.TreadmillPosition then
                    Config.TreadmillPosition = autoDetectTreadmill()
                end

                local holdingEgg = isHoldingEgg()
                local currentPos = hrp.Position
                local moveDelta = (currentPos - State.LastPosition).Magnitude
                State.LastPosition = currentPos

                if holdingEgg then
                    State.LastActiveTick = os.clock()
                    State.IsOnTreadmill = false
                    State.CurrentStatus = "BF Ativo (Plantando Ovo)"

                elseif moveDelta > 15 and not State.IsCompanionMoving then
                    State.LastActiveTick = os.clock()
                    State.IsOnTreadmill = false
                    State.CurrentStatus = "BF Ativo (Voando/Roubando)"

                elseif Config.PlotPosition and (currentPos - Config.PlotPosition).Magnitude > 90 and not State.IsCompanionMoving then
                    State.LastActiveTick = os.clock()
                    State.IsOnTreadmill = false
                    State.CurrentStatus = "BF Ativo (Na Ilha)"

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

-- 8. Anti-AFK Seguro
LocalPlayer.Idled:Connect(function()
    if Config.AntiAFK then
        pcall(function()
            Services.VirtualUser:CaptureController()
            Services.VirtualUser:ClickButton2(Vector2.new(0, 0))
        end)
    end
end)

-- 9. INTERFACE COMPACTA (CARD FLUTUANTE MODULAR)
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
Card.Size = UDim2.new(0, 260, 0, 0)
Card.AutomaticSize = Enum.AutomaticSize.Y
Card.Position = UDim2.new(0.82, -15, 0.04, 0)
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

local cardPad = Instance.new("UIPadding")
cardPad.PaddingTop = UDim.new(0, 8)
cardPad.PaddingBottom = UDim.new(0, 10)
cardPad.PaddingLeft = UDim.new(0, 8)
cardPad.PaddingRight = UDim.new(0, 8)
cardPad.Parent = Card

local cardLayout = Instance.new("UIListLayout")
cardLayout.SortOrder = Enum.SortOrder.LayoutOrder
cardLayout.Padding = UDim.new(0, 6)
cardLayout.Parent = Card

-- Header: Título e Botão Minimizar
local HeaderFrame = Instance.new("Frame")
HeaderFrame.Size = UDim2.new(1, 0, 0, 20)
HeaderFrame.BackgroundTransparency = 1
HeaderFrame.LayoutOrder = 1
HeaderFrame.Parent = Card

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -28, 1, 0)
Title.BackgroundTransparency = 1
Title.Font = Enum.Font.GothamBold
Title.TextSize = 10
Title.TextColor3 = Color3.fromRGB(56, 189, 248)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Text = "BF COMPANION v1.5"
Title.Parent = HeaderFrame

local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, 20, 0, 20)
MinBtn.Position = UDim2.new(1, -20, 0, 0)
MinBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
MinBtn.Text = "-"
MinBtn.Font = Enum.Font.GothamBold
MinBtn.TextSize = 11
MinBtn.TextColor3 = Color3.fromRGB(241, 245, 249)
MinBtn.Parent = HeaderFrame
local minCorner = Instance.new("UICorner")
minCorner.CornerRadius = UDim.new(0, 4)
minCorner.Parent = MinBtn

-- Container de Conteúdo Expansível
local ContentBox = Instance.new("Frame")
ContentBox.Size = UDim2.new(1, 0, 0, 0)
ContentBox.AutomaticSize = Enum.AutomaticSize.Y
ContentBox.BackgroundTransparency = 1
ContentBox.LayoutOrder = 2
ContentBox.Parent = Card

local boxLayout = Instance.new("UIListLayout")
boxLayout.SortOrder = Enum.SortOrder.LayoutOrder
boxLayout.Padding = UDim.new(0, 5)
boxLayout.Parent = ContentBox

-- 1. Status Row
local StatusRow = Instance.new("Frame")
StatusRow.Size = UDim2.new(1, 0, 0, 22)
StatusRow.BackgroundColor3 = Color3.fromRGB(24, 33, 53)
StatusRow.BorderSizePixel = 0
StatusRow.Parent = ContentBox
local statusCorner = Instance.new("UICorner")
statusCorner.CornerRadius = UDim.new(0, 4)
statusCorner.Parent = StatusRow

local StatusText = Instance.new("TextLabel")
StatusText.Size = UDim2.new(1, -8, 1, 0)
StatusText.Position = UDim2.new(0, 6, 0, 0)
StatusText.BackgroundTransparency = 1
StatusText.Font = Enum.Font.GothamBold
StatusText.TextSize = 9
StatusText.TextColor3 = Color3.fromRGB(241, 245, 249)
StatusText.TextXAlignment = Enum.TextXAlignment.Left
StatusText.Text = "Status: Iniciando..."
StatusText.Parent = StatusRow

-- 2. Toggle Auto-Esteira
local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Size = UDim2.new(1, 0, 0, 24)
ToggleBtn.BackgroundColor3 = Config.AutoTreadmillEnabled and Color3.fromRGB(34, 197, 94) or Color3.fromRGB(30, 41, 59)
ToggleBtn.Text = Config.AutoTreadmillEnabled and "AUTO ESTEIRA: ATIVADO" or "AUTO ESTEIRA: DESATIVADO"
ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.TextSize = 9
ToggleBtn.TextColor3 = Color3.fromRGB(241, 245, 249)
ToggleBtn.Parent = ContentBox
local btnCorner1 = Instance.new("UICorner")
btnCorner1.CornerRadius = UDim.new(0, 4)
btnCorner1.Parent = ToggleBtn

ToggleBtn.MouseButton1Click:Connect(function()
    Config.AutoTreadmillEnabled = not Config.AutoTreadmillEnabled
    ToggleBtn.BackgroundColor3 = Config.AutoTreadmillEnabled and Color3.fromRGB(34, 197, 94) or Color3.fromRGB(30, 41, 59)
    ToggleBtn.Text = Config.AutoTreadmillEnabled and "AUTO ESTEIRA: ATIVADO" or "AUTO ESTEIRA: DESATIVADO"
    saveSettings()
end)

-- 3. Salvar Esteira
local SetTreadmillBtn = Instance.new("TextButton")
SetTreadmillBtn.Size = UDim2.new(1, 0, 0, 24)
SetTreadmillBtn.BackgroundColor3 = Color3.fromRGB(14, 116, 144)
SetTreadmillBtn.Text = Config.TreadmillPosition and "ESTEIRA REGISTRADA (CLIQUE P/ REDEFINIR)" or "SALVAR POSICAO ATUAL NA ESTEIRA"
SetTreadmillBtn.Font = Enum.Font.GothamBold
SetTreadmillBtn.TextSize = 8
SetTreadmillBtn.TextColor3 = Color3.fromRGB(241, 245, 249)
SetTreadmillBtn.Parent = ContentBox
local btnCorner2 = Instance.new("UICorner")
btnCorner2.CornerRadius = UDim.new(0, 4)
btnCorner2.Parent = SetTreadmillBtn

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

-- 4. Botão: Executar BigFroot Agora
local RunBFBtn = Instance.new("TextButton")
RunBFBtn.Size = UDim2.new(1, 0, 0, 24)
RunBFBtn.BackgroundColor3 = Color3.fromRGB(56, 189, 248)
RunBFBtn.Text = "EXECUTAR BIGFROOT AGORA"
RunBFBtn.Font = Enum.Font.GothamBold
RunBFBtn.TextSize = 9
RunBFBtn.TextColor3 = Color3.fromRGB(11, 15, 25)
RunBFBtn.Parent = ContentBox
local btnCorner3 = Instance.new("UICorner")
btnCorner3.CornerRadius = UDim.new(0, 4)
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
AutoLaunchBFBtn.Size = UDim2.new(1, 0, 0, 22)
AutoLaunchBFBtn.BackgroundColor3 = Config.AutoLaunchBF and Color3.fromRGB(34, 197, 94) or Color3.fromRGB(30, 41, 59)
AutoLaunchBFBtn.Text = Config.AutoLaunchBF and "INICIAR BF JUNTO: LIGADO" or "INICIAR BF JUNTO: DESLIGADO"
AutoLaunchBFBtn.Font = Enum.Font.Gotham
AutoLaunchBFBtn.TextSize = 8
AutoLaunchBFBtn.TextColor3 = Color3.fromRGB(241, 245, 249)
AutoLaunchBFBtn.Parent = ContentBox
local btnCorner4 = Instance.new("UICorner")
btnCorner4.CornerRadius = UDim.new(0, 4)
btnCorner4.Parent = AutoLaunchBFBtn

AutoLaunchBFBtn.MouseButton1Click:Connect(function()
    Config.AutoLaunchBF = not Config.AutoLaunchBF
    AutoLaunchBFBtn.BackgroundColor3 = Config.AutoLaunchBF and Color3.fromRGB(34, 197, 94) or Color3.fromRGB(30, 41, 59)
    AutoLaunchBFBtn.Text = Config.AutoLaunchBF and "INICIAR BF JUNTO: LIGADO" or "INICIAR BF JUNTO: DESLIGADO"
    saveSettings()
end)

-- 6. Botão: Instalar no Autoexec do Executor
local InstallAutoexecBtn = Instance.new("TextButton")
InstallAutoexecBtn.Size = UDim2.new(1, 0, 0, 22)
InstallAutoexecBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
InstallAutoexecBtn.Text = "INSTALAR NO AUTOEXEC DO EXECUTOR"
InstallAutoexecBtn.Font = Enum.Font.Gotham
InstallAutoexecBtn.TextSize = 8
InstallAutoexecBtn.TextColor3 = Color3.fromRGB(148, 163, 184)
InstallAutoexecBtn.Parent = ContentBox
local btnCorner5 = Instance.new("UICorner")
btnCorner5.CornerRadius = UDim.new(0, 4)
btnCorner5.Parent = InstallAutoexecBtn

InstallAutoexecBtn.MouseButton1Click:Connect(function()
    local ok, err = installToAutoexec()
    if ok then
        InstallAutoexecBtn.Text = "INSTALADO EM AUTOEXEC COM SUCESSO!"
        InstallAutoexecBtn.TextColor3 = Color3.fromRGB(34, 197, 94)
    else
        InstallAutoexecBtn.Text = "ERRO AO GRAVAR (MANUAL NECESSARIO)"
        InstallAutoexecBtn.TextColor3 = Color3.fromRGB(239, 68, 68)
    end
    task.delay(3, function()
        InstallAutoexecBtn.Text = "INSTALAR NO AUTOEXEC DO EXECUTOR"
        InstallAutoexecBtn.TextColor3 = Color3.fromRGB(148, 163, 184)
    end)
end)

-- Minimização
local isMinimized = false
MinBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    ContentBox.Visible = not isMinimized
    MinBtn.Text = isMinimized and "+" or "-"
end)

-- Atualização contínua do status
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

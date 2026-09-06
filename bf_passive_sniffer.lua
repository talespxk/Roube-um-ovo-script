--[[
    ================================================================================
    BF PASSIVE FLIGHT RECORDER & AUTO-STEAL SNIFFER (100% INDETECTÁVEL)
    ================================================================================
    SEGURANÇA TOTAL:
    - NÃO usa hookfunction (0% risco de Luarmor Tampering).
    - NÃO altera loadstring, HttpGet ou variáveis globais.
    - Usa APENAS eventos nativos do motor Roblox (CFrame, Touched, Prompt, State).
    
    COMO USAR:
    1. Entre no jogo em uma conta que NÃO tenha o bloqueio de 24h.
    2. Execute este script PRIMEIRO.
    3. Execute o seu BigFroot (bfloader).
    4. Ative o Auto Steal do BigFroot e deixe ele roubar 1 ou 2 ovos.
    5. O Sniffer grava CADA MILISSEGUNDO do que o BigFroot faz:
       - Para onde ele teleporta e coordenadas exatas
       - Como ele toca na galinha (física ou colisão)
       - Como ele pega o ovo (Prompt, HoldDuration, atrasos)
       - Como ele entrega na base
    6. Clique no botão [COPIAR LOG COMPLETO] na tela e envie aqui!
    ================================================================================
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local LocalPlayer = Players.LocalPlayer

local flightLogs = {}
local eventCount = 0
local startTime = os.clock()

local function logEvent(category, message, details)
    eventCount = eventCount + 1
    local elapsed = os.clock() - startTime
    local timeStr = string.format("[%06.3fs]", elapsed)
    local line = string.format("%s [%-12s] %s %s", timeStr, category, message, details and ("| " .. details) or "")
    table.insert(flightLogs, line)
    if #flightLogs > 1000 then
        table.remove(flightLogs, 1)
    end
end

logEvent("SISTEMA", "Gravador de Voo Passivo iniciado!", "Aguardando carregamento do BigFroot...")

-- 1. MONITORAMENTO DE TELEPORTE, VELOCIDADE E FÍSICA DO PERSONAGEM
local lastPos = nil

local function setupCharacterTracker(char)
    if not char then return end
    local hrp = char:WaitForChild("HumanoidRootPart", 5)
    local hum = char:WaitForChild("Humanoid", 5)
    if not hrp or not hum then return end

    lastPos = hrp.Position
    logEvent("PERSONAGEM", "Personagem detectado", string.format("Pos: (%.1f, %.1f, %.1f)", lastPos.X, lastPos.Y, lastPos.Z))

    hrp:GetPropertyChangedSignal("CFrame"):Connect(function()
        local curPos = hrp.Position
        local delta = (curPos - lastPos).Magnitude
        if delta > 12.0 then
            local vel = hrp.AssemblyLinearVelocity.Magnitude
            local stateName = hum:GetState().Name
            
            local nearby = "Espaco Aberto"
            for _, obj in ipairs(Workspace:GetChildren()) do
                if obj:IsA("Model") and (obj.Name:lower():find("guard") or obj.Name:lower():find("chicken") or obj.Name:lower():find("galinha")) then
                    local p = obj:GetPivot().Position
                    if (p - curPos).Magnitude < 25 then
                        nearby = "Perto da Galinha: " .. obj.Name .. " (" .. string.format("%.1f", (p - curPos).Magnitude) .. " studs)"
                        break
                    end
                end
            end
            if nearby == "Espaco Aberto" then
                local eggSlots = Workspace:FindFirstChild("AreaEggSlotsClient")
                if eggSlots then
                    for _, slot in ipairs(eggSlots:GetChildren()) do
                        local sPos = slot:GetPivot().Position
                        if (sPos - curPos).Magnitude < 15 then
                            nearby = "Perto do Ovo: " .. slot.Name .. " (" .. string.format("%.1f", (sPos - curPos).Magnitude) .. " studs)"
                            break
                        end
                    end
                end
            end
            if nearby == "Espaco Aberto" then
                local plots = Workspace:FindFirstChild("Plots")
                if plots then
                    for _, plot in ipairs(plots:GetChildren()) do
                        local pPos = plot:GetPivot().Position
                        if (pPos - curPos).Magnitude < 35 then
                            nearby = "Perto do Plot: " .. plot.Name .. " (" .. string.format("%.1f", (pPos - curPos).Magnitude) .. " studs)"
                            break
                        end
                    end
                end
            end

            logEvent("TELEPORTE", string.format("Salto de %.1f studs! Para: (%.1f, %.1f, %.1f)", delta, curPos.X, curPos.Y, curPos.Z),
                string.format("Vel: %.1f | Estado: %s | %s", vel, stateName, nearby))
        end
        lastPos = curPos
    end)

    hum.StateChanged:Connect(function(oldState, newState)
        local vel = hrp.AssemblyLinearVelocity.Magnitude
        logEvent("ESTADO", string.format("Humanoid mudou de [%s] para [%s]", oldState.Name, newState.Name),
            string.format("Velocidade: %.1f | Pos: (%.1f, %.1f, %.1f)", vel, hrp.Position.X, hrp.Position.Y, hrp.Position.Z))
    end)

    hum:GetPropertyChangedSignal("PlatformStand"):Connect(function()
        logEvent("FISICA", "PlatformStand alterado: " .. tostring(hum.PlatformStand))
    end)

    hrp.Touched:Connect(function(otherPart)
        if otherPart and otherPart.Parent then
            local parentName = otherPart.Parent.Name:lower()
            if parentName:find("guard") or parentName:find("chicken") or parentName:find("galinha") or parentName:find("conveyor") or parentName:find("deposit") or parentName:find("esteira") then
                logEvent("TOQUE", "HRP colidiu com: " .. otherPart.Parent.Name .. "." .. otherPart.Name,
                    string.format("Pos: (%.1f, %.1f, %.1f)", otherPart.Position.X, otherPart.Position.Y, otherPart.Position.Z))
            end
        end
    end)

    char.ChildAdded:Connect(function(child)
        local low = child.Name:lower()
        if not low:find("animate") and not child:IsA("Accessory") and not child:IsA("Shirt") and not child:IsA("Pants") then
            logEvent("OVO_PEGO", "Ovo/Item acoplado: " .. child.Name .. " [" .. child.ClassName .. "]",
                string.format("Pos HRP: (%.1f, %.1f, %.1f)", hrp.Position.X, hrp.Position.Y, hrp.Position.Z))
        end
    end)

    char.ChildRemoved:Connect(function(child)
        local low = child.Name:lower()
        if not low:find("animate") and not child:IsA("Accessory") and not child:IsA("Shirt") and not child:IsA("Pants") then
            logEvent("OVO_ENTREGUE", "Ovo/Item saiu do personagem: " .. child.Name,
                string.format("Pos HRP: (%.1f, %.1f, %.1f)", hrp.Position.X, hrp.Position.Y, hrp.Position.Z))
        end
    end)
end

if LocalPlayer.Character then
    task.spawn(setupCharacterTracker, LocalPlayer.Character)
end
LocalPlayer.CharacterAdded:Connect(setupCharacterTracker)

-- 2. MONITORAMENTO DE PROXIMITY PROMPTS
ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt, player)
    if player == LocalPlayer then
        local pPos = prompt.Parent and (prompt.Parent:IsA("BasePart") and prompt.Parent.Position or prompt.Parent:GetPivot().Position) or Vector3.zero
        logEvent("PROMPT_HOLD", "Segurou prompt: " .. prompt.ActionText .. " | Obj: " .. prompt.ObjectText,
            string.format("Pai: %s | Pos: (%.1f, %.1f, %.1f) | Hold: %.2fs", prompt.Parent and prompt.Parent.Name or "N/D", pPos.X, pPos.Y, pPos.Z, prompt.HoldDuration))
    end
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
    if player == LocalPlayer then
        local pPos = prompt.Parent and (prompt.Parent:IsA("BasePart") and prompt.Parent.Position or prompt.Parent:GetPivot().Position) or Vector3.zero
        logEvent("PROMPT_TRIGGER", "PROMPT DISPARADO! " .. prompt.ActionText .. " | Obj: " .. prompt.ObjectText,
            string.format("Pai: %s | Pos: (%.1f, %.1f, %.1f) | MaxDist: %.1f", prompt.Parent and prompt.Parent.Name or "N/D", pPos.X, pPos.Y, pPos.Z, prompt.MaxActivationDistance))
    end
end)

-- 3. INTERFACE VISUAL COMPACTA
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "BF_Passive_Sniffer_GUI"
ScreenGui.ResetOnSpawn = false

pcall(function()
    if gethui then ScreenGui.Parent = gethui()
    elseif syn and syn.protect_gui then syn.protect_gui(ScreenGui); ScreenGui.Parent = game:GetService("CoreGui")
    else ScreenGui.Parent = game:GetService("CoreGui") end
end)
if not ScreenGui.Parent then ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

local Frame = Instance.new("Frame")
Frame.Size = UDim2.new(0, 380, 0, 240)
Frame.Position = UDim2.new(0.02, 0, 0.05, 0)
Frame.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
Frame.BorderSizePixel = 0
Frame.Active = true
Frame.Draggable = true
Frame.Parent = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 8)
Corner.Parent = Frame

local Stroke = Instance.new("UIStroke")
Stroke.Color = Color3.fromRGB(56, 189, 248)
Stroke.Thickness = 1.5
Stroke.Parent = Frame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -20, 0, 24)
Title.Position = UDim2.new(0, 10, 0, 6)
Title.BackgroundTransparency = 1
Title.Font = Enum.Font.GothamBold
Title.TextSize = 12
Title.TextColor3 = Color3.fromRGB(56, 189, 248)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Text = "BF SNIFFER PASSIVO (FLIGHT RECORDER)"
Title.Parent = Frame

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, -20, 0, 16)
StatusLabel.Position = UDim2.new(0, 10, 0, 30)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextSize = 10
StatusLabel.TextColor3 = Color3.fromRGB(148, 163, 184)
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.Text = "Gravando em tempo real... 0 eventos"
StatusLabel.Parent = Frame

local LogBox = Instance.new("ScrollingFrame")
LogBox.Size = UDim2.new(1, -20, 0, 140)
LogBox.Position = UDim2.new(0, 10, 0, 50)
LogBox.BackgroundColor3 = Color3.fromRGB(10, 15, 29)
LogBox.BorderSizePixel = 0
LogBox.ScrollBarThickness = 4
LogBox.Parent = Frame

local LogText = Instance.new("TextLabel")
LogText.Size = UDim2.new(1, -10, 0, 0)
LogText.AutomaticSize = Enum.AutomaticSize.Y
LogText.Position = UDim2.new(0, 5, 0, 5)
LogText.BackgroundTransparency = 1
LogText.Font = Enum.Font.Code
LogText.TextSize = 9
LogText.TextColor3 = Color3.fromRGB(226, 232, 240)
LogText.TextXAlignment = Enum.TextXAlignment.Left
LogText.TextYAlignment = Enum.TextYAlignment.Top
LogText.TextWrapped = true
LogText.Text = "Iniciando captura..."
LogText.Parent = LogBox

local CopyBtn = Instance.new("TextButton")
CopyBtn.Size = UDim2.new(1, -20, 0, 30)
CopyBtn.Position = UDim2.new(0, 10, 1, -36)
CopyBtn.BackgroundColor3 = Color3.fromRGB(16, 185, 129)
CopyBtn.Font = Enum.Font.GothamBold
CopyBtn.TextSize = 11
CopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyBtn.Text = "COPIAR LOG COMPLETO / SALVAR ARQUIVO"
CopyBtn.Parent = Frame

local BtnCorner = Instance.new("UICorner")
BtnCorner.CornerRadius = UDim.new(0, 6)
BtnCorner.Parent = CopyBtn

CopyBtn.MouseButton1Click:Connect(function()
    local fullText = table.concat(flightLogs, "\n")
    pcall(function()
        if setclipboard then
            setclipboard(fullText)
        end
        if writefile then
            writefile("BF_FLIGHT_LOG.txt", fullText)
        end
    end)
    CopyBtn.Text = "COPIADO COM SUCESSO! (" .. #flightLogs .. " linhas)"
    CopyBtn.BackgroundColor3 = Color3.fromRGB(59, 130, 246)
    task.delay(2.5, function()
        CopyBtn.Text = "COPIAR LOG COMPLETO / SALVAR ARQUIVO"
        CopyBtn.BackgroundColor3 = Color3.fromRGB(16, 185, 129)
    end)
end)

task.spawn(function()
    while true do
        task.wait(0.5)
        StatusLabel.Text = string.format("Gravando em tempo real... %d eventos capturados", eventCount)
        local recentLogs = {}
        local startIdx = math.max(1, #flightLogs - 15)
        for i = startIdx, #flightLogs do
            table.insert(recentLogs, flightLogs[i])
        end
        LogText.Text = table.concat(recentLogs, "\n")
        LogBox.CanvasPosition = Vector2.new(0, 99999)
    end
end)

logEvent("SISTEMA", "Tudo pronto! Voce ja pode executar o BigFroot!", "Ative o Auto Steal dele e veja a magica acontecer!")

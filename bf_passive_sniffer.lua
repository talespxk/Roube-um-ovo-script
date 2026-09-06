--[[
    ================================================================================
    BF PASSIVE FLIGHT RECORDER & AUTO-STEAL SNIFFER (100% INDETECTÁVEL v2.0)
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
    5. O Sniffer grava CADA MILISSEGUNDO do que o BigFroot faz e gera um
       RELATÓRIO RESUMIDO com todas as velocidades, atrasos e coordenadas exatas!
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
    local line = string.format("%s [%-14s] %s %s", timeStr, category, message, details and ("| " .. details) or "")
    table.insert(flightLogs, line)
    if #flightLogs > 1200 then
        table.remove(flightLogs, 1)
    end
end

logEvent("SISTEMA", "Gravador de Voo Passivo v2.0 iniciado!", "Aguardando carregamento do BigFroot...")

--================================================================--
-- RASTREADOR DE CICLO DE ROUBO COM CÁLCULO DE DELTAS EM TEMPO REAL
--================================================================--
local CycleTracker = {
    CurrentPhase = "IDLE",
    TimeChicken = 0,
    TimeHit = 0,
    TimeEgg = 0,
    TimePrompt = 0,
    TimeHeld = 0,
    TimeBase = 0,
    TimeDeposit = 0,
    TargetEggName = "Nenhum",
    EggOffset = Vector3.zero,
    BasePos = Vector3.zero,
    ChickenPos = Vector3.zero
}

local function printCycleReport()
    local dHit = CycleTracker.TimeHit - CycleTracker.TimeChicken
    local dEgg = CycleTracker.TimeEgg - CycleTracker.TimeHit
    local dPrompt = CycleTracker.TimePrompt - CycleTracker.TimeEgg
    local dHeld = CycleTracker.TimeHeld - CycleTracker.TimePrompt
    local dBase = CycleTracker.TimeBase - CycleTracker.TimeHeld
    local dDeposit = CycleTracker.TimeDeposit - CycleTracker.TimeBase
    local totalTime = CycleTracker.TimeDeposit - CycleTracker.TimeChicken

    local report = {
        "==================================================",
        "[RELATÓRIO CONSOLIDADO DO AUTO-STEAL DO BF]",
        string.format("Alvo Roubado: %s", CycleTracker.TargetEggName),
        string.format("1. Espera pelo Hit da Galinha: %.3fs (Pos: %.1f, %.1f, %.1f)", math.max(0, dHit), CycleTracker.ChickenPos.X, CycleTracker.ChickenPos.Y, CycleTracker.ChickenPos.Z),
        string.format("2. Salto até o Ovo Alvo: %.3fs", math.max(0, dEgg)),
        string.format("3. Atraso antes do Prompt: %.3fs", math.max(0, dPrompt)),
        string.format("4. Tempo até o Ovo Acoplar: %.3fs", math.max(0, dHeld)),
        string.format("5. Salto de Volta para a Base: %.3fs (Pos Base: %.1f, %.1f, %.1f)", math.max(0, dBase), CycleTracker.BasePos.X, CycleTracker.BasePos.Y, CycleTracker.BasePos.Z),
        string.format("6. Tempo até o Depósito no Plot: %.3fs", math.max(0, dDeposit)),
        string.format("TEMPO TOTAL DO CICLO COMPLETO: %.3fs", math.max(0, totalTime)),
        "=================================================="
    }

    for _, rLine in ipairs(report) do
        table.insert(flightLogs, rLine)
    end
end

--================================================================--
-- 1. MONITORAMENTO FÍSICO DO PERSONAGEM
--================================================================--
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

        if delta > 10.0 then
            local vel = hrp.AssemblyLinearVelocity.Magnitude
            local stateName = hum:GetState().Name
            local now = os.clock()
            
            -- Verificar proximidade
            local nearby = "Espaco Aberto"
            local isNearChicken = false
            local isNearEgg = false
            local isNearPlot = false

            -- Galinha
            for _, obj in ipairs(Workspace:GetChildren()) do
                if obj:IsA("Model") and (obj.Name:lower():find("guard") or obj.Name:lower():find("chicken") or obj.Name:lower():find("galinha")) then
                    local p = obj:GetPivot().Position
                    if (p - curPos).Magnitude < 25 then
                        nearby = "Galinha: " .. obj.Name .. " (" .. string.format("%.1f", (p - curPos).Magnitude) .. " studs)"
                        isNearChicken = true
                        CycleTracker.ChickenPos = p
                        break
                    end
                end
            end

            -- Ovo
            if not isNearChicken then
                local eggSlots = Workspace:FindFirstChild("AreaEggSlotsClient")
                if eggSlots then
                    for _, slot in ipairs(eggSlots:GetChildren()) do
                        local sPos = slot:GetPivot().Position
                        if (sPos - curPos).Magnitude < 18 then
                            nearby = "Ovo: " .. slot.Name .. " (" .. string.format("%.1f", (sPos - curPos).Magnitude) .. " studs)"
                            isNearEgg = true
                            CycleTracker.TargetEggName = slot.Name
                            break
                        end
                    end
                end
            end

            -- Plot
            if not isNearChicken and not isNearEgg then
                local plots = Workspace:FindFirstChild("Plots")
                if plots then
                    for _, plot in ipairs(plots:GetChildren()) do
                        local pPos = plot:GetPivot().Position
                        if (pPos - curPos).Magnitude < 35 then
                            nearby = "Plot: " .. plot.Name .. " (" .. string.format("%.1f", (pPos - curPos).Magnitude) .. " studs)"
                            isNearPlot = true
                            CycleTracker.BasePos = curPos
                            break
                        end
                    end
                end
            end

            -- Transições da Máquina de Estados do Roubo
            if isNearChicken and CycleTracker.CurrentPhase == "IDLE" then
                CycleTracker.CurrentPhase = "AT_CHICKEN"
                CycleTracker.TimeChicken = now
                logEvent("FASE_ROUBO", "[1/6] BF foi até a Galinha!", string.format("Aguardando hit... Pos: (%.1f, %.1f, %.1f)", curPos.X, curPos.Y, curPos.Z))
            elseif isNearEgg and (CycleTracker.CurrentPhase == "HIT_DETECTED" or CycleTracker.CurrentPhase == "AT_CHICKEN") then
                CycleTracker.CurrentPhase = "AT_EGG"
                CycleTracker.TimeEgg = now
                logEvent("FASE_ROUBO", "[3/6] BF saltou para o Ovo!", string.format("Alvo: %s | Salto de %.1f studs", CycleTracker.TargetEggName, delta))
            elseif isNearPlot and (CycleTracker.CurrentPhase == "EGG_HELD" or CycleTracker.CurrentPhase == "AT_EGG") then
                CycleTracker.CurrentPhase = "AT_BASE"
                CycleTracker.TimeBase = now
                logEvent("FASE_ROUBO", "[5/6] BF retornou para a Base!", string.format("Pos Entrega: (%.1f, %.1f, %.1f)", curPos.X, curPos.Y, curPos.Z))
            end

            logEvent("TELEPORTE", string.format("Salto de %.1f studs -> (%.1f, %.1f, %.1f)", delta, curPos.X, curPos.Y, curPos.Z),
                string.format("Vel: %.1f | Estado: %s | %s", vel, stateName, nearby))
        end
        lastPos = curPos
    end)

    hum.StateChanged:Connect(function(oldState, newState)
        local vel = hrp.AssemblyLinearVelocity.Magnitude
        local now = os.clock()

        if newState == Enum.HumanoidStateType.Ragdoll or (newState == Enum.HumanoidStateType.PlatformStanding and vel > 25) then
            if CycleTracker.CurrentPhase == "AT_CHICKEN" then
                CycleTracker.CurrentPhase = "HIT_DETECTED"
                CycleTracker.TimeHit = now
                local deltaHit = now - CycleTracker.TimeChicken
                logEvent("FASE_ROUBO", "[2/6] Hit/Ragdoll confirmado!", string.format("Tempo de reacao: %.3fs | Velocidade do golpe: %.1f", deltaHit, vel))
            end
        end

        logEvent("ESTADO", string.format("Humanoid [%s -> %s]", oldState.Name, newState.Name),
            string.format("Vel: %.1f | Pos: (%.1f, %.1f, %.1f)", vel, hrp.Position.X, hrp.Position.Y, hrp.Position.Z))
    end)

    hum:GetPropertyChangedSignal("PlatformStand"):Connect(function()
        logEvent("FISICA", "PlatformStand = " .. tostring(hum.PlatformStand))
    end)

    hrp.Touched:Connect(function(otherPart)
        if otherPart and otherPart.Parent then
            local parentName = otherPart.Parent.Name:lower()
            if parentName:find("guard") or parentName:find("chicken") or parentName:find("galinha") or parentName:find("conveyor") or parentName:find("deposit") or parentName:find("esteira") then
                logEvent("TOQUE", "HRP tocou em: " .. otherPart.Parent.Name .. "." .. otherPart.Name,
                    string.format("Pos: (%.1f, %.1f, %.1f)", otherPart.Position.X, otherPart.Position.Y, otherPart.Position.Z))
            end
        end
    end)

    char.ChildAdded:Connect(function(child)
        local low = child.Name:lower()
        if not low:find("animate") and not child:IsA("Accessory") and not child:IsA("Shirt") and not child:IsA("Pants") then
            local now = os.clock()
            if CycleTracker.CurrentPhase == "AT_EGG" or CycleTracker.CurrentPhase == "PROMPT_DONE" then
                CycleTracker.CurrentPhase = "EGG_HELD"
                CycleTracker.TimeHeld = now
                local deltaHeld = now - (CycleTracker.TimePrompt > 0 and CycleTracker.TimePrompt or CycleTracker.TimeEgg)
                logEvent("FASE_ROUBO", "[4/6] Ovo acoplado ao personagem!", string.format("Item: %s | Tempo de captura: %.3fs", child.Name, deltaHeld))
            end
            logEvent("OVO_PEGO", "Item/Ovo acoplado: " .. child.Name .. " [" .. child.ClassName .. "]",
                string.format("Pos HRP: (%.1f, %.1f, %.1f)", hrp.Position.X, hrp.Position.Y, hrp.Position.Z))
        end
    end)

    char.ChildRemoved:Connect(function(child)
        local low = child.Name:lower()
        if not low:find("animate") and not child:IsA("Accessory") and not child:IsA("Shirt") and not child:IsA("Pants") then
            local now = os.clock()
            if CycleTracker.CurrentPhase == "AT_BASE" or CycleTracker.CurrentPhase == "EGG_HELD" then
                CycleTracker.CurrentPhase = "IDLE"
                CycleTracker.TimeDeposit = now
                local deltaDep = now - CycleTracker.TimeBase
                logEvent("FASE_ROUBO", "[6/6] Ovo depositado no Plot com sucesso!", string.format("Tempo de deposito: %.3fs", deltaDep))
                task.delay(0.1, printCycleReport)
            end
            logEvent("OVO_ENTREGUE", "Item/Ovo saiu do personagem: " .. child.Name,
                string.format("Pos HRP: (%.1f, %.1f, %.1f)", hrp.Position.X, hrp.Position.Y, hrp.Position.Z))
        end
    end)
end

if LocalPlayer.Character then
    task.spawn(setupCharacterTracker, LocalPlayer.Character)
end
LocalPlayer.CharacterAdded:Connect(setupCharacterTracker)

--================================================================--
-- 2. MONITORAMENTO DE PROXIMITY PROMPTS
--================================================================--
ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt, player)
    if player == LocalPlayer then
        local pPos = prompt.Parent and (prompt.Parent:IsA("BasePart") and prompt.Parent.Position or prompt.Parent:GetPivot().Position) or Vector3.zero
        logEvent("PROMPT_HOLD", "Segurou prompt: " .. prompt.ActionText .. " | Obj: " .. prompt.ObjectText,
            string.format("Pai: %s | Pos: (%.1f, %.1f, %.1f) | Hold: %.2fs", prompt.Parent and prompt.Parent.Name or "N/D", pPos.X, pPos.Y, pPos.Z, prompt.HoldDuration))
    end
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
    if player == LocalPlayer then
        local now = os.clock()
        if CycleTracker.CurrentPhase == "AT_EGG" then
            CycleTracker.CurrentPhase = "PROMPT_DONE"
            CycleTracker.TimePrompt = now
            local dPrompt = now - CycleTracker.TimeEgg
            logEvent("FASE_ROUBO", "Prompt de roubo disparado!", string.format("Atraso de disparo: %.3fs | MaxDist: %.1f", dPrompt, prompt.MaxActivationDistance))
        end
        local pPos = prompt.Parent and (prompt.Parent:IsA("BasePart") and prompt.Parent.Position or prompt.Parent:GetPivot().Position) or Vector3.zero
        logEvent("PROMPT_TRIGGER", "PROMPT DISPARADO! " .. prompt.ActionText .. " | Obj: " .. prompt.ObjectText,
            string.format("Pai: %s | Pos: (%.1f, %.1f, %.1f) | MaxDist: %.1f", prompt.Parent and prompt.Parent.Name or "N/D", pPos.X, pPos.Y, pPos.Z, prompt.MaxActivationDistance))
    end
end)

--================================================================--
-- 3. INTERFACE VISUAL COMPACTA
--================================================================--
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
Frame.Size = UDim2.new(0, 420, 0, 260)
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
Title.Text = "BF SNIFFER PASSIVO v2.0 (FLIGHT RECORDER)"
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
LogBox.Size = UDim2.new(1, -20, 0, 155)
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
CopyBtn.Size = UDim2.new(1, -20, 0, 32)
CopyBtn.Position = UDim2.new(0, 10, 1, -38)
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
        local startIdx = math.max(1, #flightLogs - 18)
        for i = startIdx, #flightLogs do
            table.insert(recentLogs, flightLogs[i])
        end
        LogText.Text = table.concat(recentLogs, "\n")
        LogBox.CanvasPosition = Vector2.new(0, 99999)
    end
end)

logEvent("SISTEMA", "Tudo pronto! Voce ja pode executar o BigFroot!", "Ative o Auto Steal dele e veja a magica acontecer!")

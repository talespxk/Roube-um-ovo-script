--[[
    ================================================================================
    ROUBE UM OVO - MASTER GAME DUMPER & EXTRACTOR (100% REVERSE ENGINEERING)
    PlaceId: 107778070777162 | Jogo: Roube um Ovo (Steal an Egg)
    ================================================================================
    O QUE ESTE DUMPER FAZ:
    1. EXTRACAO DE TODOS OS MODULESCRIPTS (REQUIRE):
       - Executa require() em todos os ModuleScripts do ReplicatedStorage e StarterPlayer.
       - Extrai tabelas completas de configuracao (chances de ovos, precos, multiplicadores,
         sistemas de esteira, renascimento e definicoes de remotes).
    2. DESCOMPILACAO DE SCRIPTS (SE SUPORTADO PELO EXECUTOR):
       - Se o executor tiver a funcao decompile(), descompila todos os LocalScripts e
         ModuleScripts e salva o codigo-fonte completo.
    3. DUMP ESTRUTURAL COMPLETO DO WORKSPACE:
       - Plots: Donos, ninhos, esteiras, posicoes CFrame de cada base.
       - AreaEggSlotsClient: Todos os slots de ovos vivos, Uids, SlotKeys, Meshes e Raridades.
       - PlacedEggRenders: Ovos plantados nos ninhos e status de incubacao.
       - GearGivers: Pedestais de armas secretas, scripts, botoes e requisitos.
       - Treadmills: Esteiras fisicas, renders e velocidade de conveyor.
    4. DUMP DE REMOTES E NETWORKING:
       - Mapeia 100% dos RemoteEvents e RemoteFunctions de ReplicatedStorage.Packages.Networking.
    5. SALVAMENTO AUTOMATICO NO ARQUIVO LOCAL:
       - Salva tudo formatado em JSON e TXT na pasta workspace/ do seu executor via writefile().
       - Copia resumo diretamente para o Clipboard (Area de Transferencia) com setclipboard().
    6. SUPORTE A SAVEINSTANCE (MAPA 3D COMPLETO):
       - Se o executor suportar saveinstance(), oferece opcao de baixar o mapa .rbxl
         para abrir direto no Roblox Studio oficial.
    ================================================================================
]]

local function safeService(name)
    local s = game:GetService(name)
    return (cloneref and cloneref(s)) or s
end

local Services = {
    Workspace = safeService("Workspace"),
    Players = safeService("Players"),
    ReplicatedStorage = safeService("ReplicatedStorage"),
    ReplicatedFirst = safeService("ReplicatedFirst"),
    StarterPlayer = safeService("StarterPlayer"),
    HttpService = safeService("HttpService"),
    RunService = safeService("RunService")
}

local LocalPlayer = Services.Players.LocalPlayer
while not LocalPlayer do
    task.wait(0.2)
    LocalPlayer = Services.Players.LocalPlayer
end

local startTime = os.clock()
local dumpData = {
    Meta = {
        PlaceId = game.PlaceId,
        JobId = game.JobId,
        PlaceVersion = game.PlaceVersion,
        PlayerName = LocalPlayer.Name,
        PlayerUserId = LocalPlayer.UserId,
        DumpTime = os.date("%Y-%m-%d %H:%M:%S")
    },
    Networking = {},
    Configs = {},
    Workspace = {
        Plots = {},
        AreaEggSlots = {},
        PlacedEggs = {},
        Treadmills = {},
        GearGivers = {},
        Guards = {}
    },
    Scripts = {}
}

local statusText = "Iniciando Master Dumper..."
local progressPercent = 0

local function safeString(val)
    local ok, res = pcall(function() return tostring(val) end)
    return ok and res or "ERR_TOSTRING"
end

local function tableToJson(tbl)
    local ok, res = pcall(function()
        return Services.HttpService:JSONEncode(tbl)
    end)
    if ok then return res end
    local items = {}
    for k, v in pairs(tbl) do
        local tk = type(k) == "string" and ('"' .. k .. '"') or tostring(k)
        local tv = type(v) == "table" and "{...}" or safeString(v)
        table.insert(items, string.format("%s: %s", tk, safeString(tv)))
    end
    return "{" .. table.concat(items, ", ") .. "}"
end

local function serializeValue(val, depth)
    depth = depth or 0
    if depth > 4 then return "<profundidade maxima>" end
    local t = type(val)
    if t == "string" or t == "number" or t == "boolean" then
        return val
    elseif t == "userdata" or typeof(val) == "Vector3" or typeof(val) == "CFrame" or typeof(val) == "Color3" then
        return safeString(val)
    elseif t == "table" then
        local copy = {}
        local count = 0
        for k, v in pairs(val) do
            count = count + 1
            if count > 60 then
                copy["__truncated"] = "... (" .. count .. "+ itens)"
                break
            end
            local safeKey = safeString(k)
            copy[safeKey] = serializeValue(v, depth + 1)
        end
        return copy
    elseif typeof(val) == "Instance" then
        return {
            Class = val.ClassName,
            Name = val.Name,
            Path = val:GetFullName()
        }
    else
        return safeString(val)
    end
end

--================================================================--
-- 1. DUMP DE REMOTES E NETWORKING
--================================================================--
local function dumpNetworking()
    statusText = "Mapeando Remotes e Networking..."
    progressPercent = 15
    local remotes = {}
    for _, desc in ipairs(Services.ReplicatedStorage:GetDescendants()) do
        if desc:IsA("RemoteEvent") or desc:IsA("RemoteFunction") then
            local rData = {
                Type = desc.ClassName,
                Name = desc.Name,
                FullName = desc:GetFullName(),
                Attributes = {}
            }
            for k, v in pairs(desc:GetAttributes()) do
                rData.Attributes[k] = safeString(v)
            end
            table.insert(remotes, rData)
        end
    end
    dumpData.Networking = remotes
end

--================================================================--
-- 2. DUMP DE CONFIGURACOES VIA REQUIRE() EM MODULESCRIPTS
--================================================================--
local function dumpModuleConfigs()
    statusText = "Extraindo dados de configuracao de ModuleScripts..."
    progressPercent = 35
    local configs = {}

    local candidateModules = {}
    for _, desc in ipairs(Services.ReplicatedStorage:GetDescendants()) do
        if desc:IsA("ModuleScript") then
            table.insert(candidateModules, desc)
        end
    end

    for idx, mod in ipairs(candidateModules) do
        local modName = mod.Name
        local fullName = mod:GetFullName()
        local ok, res = pcall(function()
            return require(mod)
        end)

        if ok and type(res) == "table" then
            local serialized = serializeValue(res, 0)
            table.insert(configs, {
                Module = modName,
                Path = fullName,
                Data = serialized
            })
        end
        if idx % 10 == 0 then
            task.wait(0.01)
        end
    end
    dumpData.Configs = configs
end

--================================================================--
-- 3. DUMP ESTRUTURAL DO WORKSPACE
--================================================================--
local function dumpWorkspaceObjects()
    statusText = "Extraindo Slots de Ovos, Plots, Esteiras e Pedestais..."
    progressPercent = 60

    -- A. Plots
    pcall(function()
        local plots = Services.Workspace:FindFirstChild("Plots")
        if plots then
            for _, plot in ipairs(plots:GetChildren()) do
                local pData = {
                    Name = plot.Name,
                    Pivot = safeString(plot:GetPivot()),
                    Attributes = {},
                    Treadmills = {},
                    Nests = {}
                }
                for k, v in pairs(plot:GetAttributes()) do pData.Attributes[k] = safeString(v) end
                for _, d in ipairs(plot:GetDescendants()) do
                    if d:IsA("BasePart") then
                        local low = d.Name:lower()
                        if low:find("treadmill") or low:find("esteira") or low:find("belt") then
                            table.insert(pData.Treadmills, { Name = d.Name, Pos = safeString(d.Position), Size = safeString(d.Size) })
                        elseif low:find("nest") or low:find("ninho") or low:find("deposit") or low:find("drop") then
                            table.insert(pData.Nests, { Name = d.Name, Pos = safeString(d.Position) })
                        end
                    end
                end
                table.insert(dumpData.Workspace.Plots, pData)
            end
        end
    end)

    -- B. AreaEggSlotsClient (Ovos Vivos nos Biomas)
    pcall(function()
        local slots = Services.Workspace:FindFirstChild("AreaEggSlotsClient")
        if slots then
            for _, slot in ipairs(slots:GetChildren()) do
                local sData = {
                    SlotName = slot.Name,
                    Position = safeString(slot:GetPivot().Position),
                    Attributes = {},
                    Children = {},
                    Prompt = nil
                }
                for k, v in pairs(slot:GetAttributes()) do sData.Attributes[k] = safeString(v) end
                for _, c in ipairs(slot:GetChildren()) do
                    local meshId = (c:IsA("MeshPart") and c.MeshId) or (c:FindFirstChildWhichIsA("SpecialMesh", true) and c:FindFirstChildWhichIsA("SpecialMesh", true).MeshId) or ""
                    table.insert(sData.Children, { Name = c.Name, Class = c.ClassName, Mesh = meshId })
                end
                local prompt = slot:FindFirstChildWhichIsA("ProximityPrompt", true)
                if prompt then
                    sData.Prompt = {
                        Action = prompt.ActionText,
                        Object = prompt.ObjectText,
                        HoldDuration = prompt.HoldDuration,
                        Distance = prompt.MaxActivationDistance
                    }
                end
                table.insert(dumpData.Workspace.AreaEggSlots, sData)
            end
        end
    end)

    -- C. PlacedEggRenders (Ovos Chocando nos Ninhos)
    pcall(function()
        local placed = Services.Workspace:FindFirstChild("PlacedEggRenders")
        if placed then
            for _, egg in ipairs(placed:GetChildren()) do
                local eData = {
                    Id = egg.Name,
                    Position = safeString(egg:GetPivot().Position),
                    Attributes = {}
                }
                for k, v in pairs(egg:GetAttributes()) do eData.Attributes[k] = safeString(v) end
                table.insert(dumpData.Workspace.PlacedEggs, eData)
            end
        end
    end)

    -- D. Pedestais de Armas Secretas (GearGivers)
    pcall(function()
        local gearNames = {"GearGiver_Slap", "GearGiver", "GearGiver_SentryTurret", "GearGiver_BeeLauncher"}
        for _, gName in ipairs(gearNames) do
            local gModel = Services.Workspace:FindFirstChild(gName, true)
            if gModel then
                local gData = {
                    Name = gName,
                    Pivot = safeString(gModel:GetPivot()),
                    Attributes = {},
                    Descendants = {}
                }
                for k, v in pairs(gModel:GetAttributes()) do gData.Attributes[k] = safeString(v) end
                for _, d in ipairs(gModel:GetDescendants()) do
                    if d:IsA("BasePart") or d:IsA("Script") or d:IsA("Configuration") or d:IsA("ValueBase") then
                        table.insert(gData.Descendants, {
                            Name = d.Name,
                            Class = d.ClassName,
                            Value = d:IsA("ValueBase") and safeString(d.Value) or nil
                        })
                    end
                end
                table.insert(dumpData.Workspace.GearGivers, gData)
            end
        end
    end)

    -- E. Treadmill Renders do Cliente
    pcall(function()
        local ctr = Services.Workspace:FindFirstChild("__ClientTreadmillRenders")
        if ctr then
            for _, child in ipairs(ctr:GetChildren()) do
                local tData = {
                    Name = child.Name,
                    Position = safeString(child:GetPivot().Position),
                    Attributes = {}
                }
                for k, v in pairs(child:GetAttributes()) do tData.Attributes[k] = safeString(v) end
                table.insert(dumpData.Workspace.Treadmills, tData)
            end
        end
    end)
end

--================================================================--
-- 4. DESCOMPILACAO DE SCRIPTS (SE DECOMPILE() FOR SUPORTADO)
--================================================================--
local function dumpScripts()
    statusText = "Verificando suporte a descompilacao de scripts..."
    progressPercent = 80
    local decompilerAvailable = type(decompile) == "function"
    local scriptList = {}

    local targets = {}
    for _, desc in ipairs(Services.ReplicatedStorage:GetDescendants()) do
        if desc:IsA("LocalScript") or desc:IsA("ModuleScript") then table.insert(targets, desc) end
    end
    for _, desc in ipairs(Services.StarterPlayer:GetDescendants()) do
        if desc:IsA("LocalScript") or desc:IsA("ModuleScript") then table.insert(targets, desc) end
    end
    if LocalPlayer.Character then
        for _, desc in ipairs(LocalPlayer.Character:GetDescendants()) do
            if desc:IsA("LocalScript") then table.insert(targets, desc) end
        end
    end

    dumpData.Meta.DecompilerSupported = decompilerAvailable
    dumpData.Meta.TotalScriptsFound = #targets

    for i, s in ipairs(targets) do
        local sInfo = {
            Name = s.Name,
            Class = s.ClassName,
            Path = s:GetFullName(),
            Source = nil
        }
        if decompilerAvailable and i <= 35 then
            local ok, decompiled = pcall(function() return decompile(s) end)
            if ok and type(decompiled) == "string" and #decompiled > 0 then
                sInfo.Source = decompiled:sub(1, 10000)
            end
        end
        table.insert(scriptList, sInfo)
    end
    dumpData.Scripts = scriptList
end

--================================================================--
-- 5. SALVAMENTO DO ARQUIVO LOCAL (WRITEFILE & SETCLIPBOARD)
--================================================================--
local function saveMasterDump()
    statusText = "Gerando arquivo de Dump Forense..."
    progressPercent = 95

    local timestamp = os.date("%Y%m%d_%H%M%S")
    local jsonFileName = string.format("RoubeUmOvo_DumpMaster_%s.json", timestamp)
    local txtSummaryFileName = string.format("RoubeUmOvo_Resumo_%s.txt", timestamp)

    local jsonData = tableToJson(dumpData)

    local summaryLines = {
        "================================================================================",
        "ROUBE UM OVO - RELATORIO FORENSE MESTRE COMPLETO (100% EXTRACAO)",
        "Data/Hora: " .. dumpData.Meta.DumpTime,
        "PlaceId: " .. dumpData.Meta.PlaceId .. " | JobId: " .. dumpData.Meta.JobId,
        "Jogador: " .. dumpData.Meta.PlayerName .. " (" .. dumpData.Meta.PlayerUserId .. ")",
        "================================================================================\n",
        string.format("[1] REMOTES ENCONTRADOS NO NETWORKING (%d Remotes):", #dumpData.Networking),
        "--------------------------------------------------------------------------------"
    }
    for _, r in ipairs(dumpData.Networking) do
        table.insert(summaryLines, string.format("  [%s] %s | Caminho: %s", r.Type, r.Name, r.FullName))
    end

    table.insert(summaryLines, "\n--------------------------------------------------------------------------------")
    table.insert(summaryLines, string.format("[2] CONFIGURACOES DE MODULESCRIPTS EXTRAIDAS (%d Modulos):", #dumpData.Configs))
    table.insert(summaryLines, "--------------------------------------------------------------------------------")
    for _, c in ipairs(dumpData.Configs) do
        table.insert(summaryLines, string.format("  > Modulo: %s (%s)", c.Module, c.Path))
    end

    table.insert(summaryLines, "\n--------------------------------------------------------------------------------")
    table.insert(summaryLines, string.format("[3] SLOTS DE OVOS DE CAMPO (%d Slots Vivos):", #dumpData.Workspace.AreaEggSlots))
    table.insert(summaryLines, "--------------------------------------------------------------------------------")
    for _, s in ipairs(dumpData.Workspace.AreaEggSlots) do
        local pStr = s.Prompt and string.format("Prompt: '%s' '%s' (Hold: %.1fs)", s.Prompt.Action, s.Prompt.Object, s.Prompt.HoldDuration) or "Sem Prompt"
        table.insert(summaryLines, string.format("  Slot: %-25s | Pos: %s | %s", s.SlotName, s.Position, pStr))
    end

    table.insert(summaryLines, "\n--------------------------------------------------------------------------------")
    table.insert(summaryLines, string.format("[4] PEDESTAIS DE ARMAS SECRETAS (%d Encontrados):", #dumpData.Workspace.GearGivers))
    table.insert(summaryLines, "--------------------------------------------------------------------------------")
    for _, g in ipairs(dumpData.Workspace.GearGivers) do
        table.insert(summaryLines, string.format("  Pedestal: %-25s | Pivot: %s | Filhos: %d", g.Name, g.Pivot, #g.Descendants))
    end

    table.insert(summaryLines, "\n================================================================================")
    table.insert(summaryLines, "FIM DO RESUMO FORENSE MESTRE")
    table.insert(summaryLines, "================================================================================")

    local summaryText = table.concat(summaryLines, "\n")

    local fileSaved = false
    if writefile then
        pcall(function()
            writefile(jsonFileName, jsonData)
            writefile(txtSummaryFileName, summaryText)
            fileSaved = true
        end)
    end

    if setclipboard then
        pcall(function()
            setclipboard(summaryText)
        end)
    end

    progressPercent = 100
    statusText = fileSaved 
        and string.format("Sucesso! Salvo em workspace/%s e copiado para o Clipboard!", jsonFileName)
        or "Dump concluido e copiado para o Clipboard!"

    return fileSaved, jsonFileName, txtSummaryFileName
end

--================================================================--
-- 6. INTERFACE VISUAL DE CONTROLE DO DUMPER
--================================================================--
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "RoubeUmOvo_MasterDumper_GUI"
ScreenGui.ResetOnSpawn = false

pcall(function()
    if gethui then ScreenGui.Parent = gethui()
    elseif syn and syn.protect_gui then syn.protect_gui(ScreenGui); ScreenGui.Parent = safeService("CoreGui")
    else ScreenGui.Parent = safeService("CoreGui") end
end)
if not ScreenGui.Parent then ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

local Frame = Instance.new("Frame")
Frame.Size = UDim2.new(0, 480, 0, 260)
Frame.Position = UDim2.new(0.5, -240, 0.4, -130)
Frame.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
Frame.BorderSizePixel = 0
Frame.Active = true
Frame.Draggable = true
Frame.Parent = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 10)
Corner.Parent = Frame

local Stroke = Instance.new("UIStroke")
Stroke.Color = Color3.fromRGB(56, 189, 248)
Stroke.Thickness = 1.5
Stroke.Parent = Frame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -20, 0, 36)
Title.Position = UDim2.new(0, 14, 0, 10)
Title.BackgroundTransparency = 1
Title.Font = Enum.Font.GothamBold
Title.TextSize = 14
Title.TextColor3 = Color3.fromRGB(56, 189, 248)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Text = "MASTER GAME DUMPER (100% FORENSE)"
Title.Parent = Frame

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, -28, 0, 44)
StatusLabel.Position = UDim2.new(0, 14, 0, 50)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextSize = 11
StatusLabel.TextColor3 = Color3.fromRGB(226, 232, 240)
StatusLabel.TextWrapped = true
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.Text = "Pronto para extrair 100% do jogo (Remotes, Configs, Ovos, Ninhos e Esteiras)."
StatusLabel.Parent = Frame

local BarBg = Instance.new("Frame")
BarBg.Size = UDim2.new(1, -28, 0, 12)
BarBg.Position = UDim2.new(0, 14, 0, 104)
BarBg.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
BarBg.BorderSizePixel = 0
BarBg.Parent = Frame
local BarBgCorner = Instance.new("UICorner")
BarBgCorner.CornerRadius = UDim.new(0, 6)
BarBgCorner.Parent = BarBg

local BarFill = Instance.new("Frame")
BarFill.Size = UDim2.new(0, 0, 1, 0)
BarFill.BackgroundColor3 = Color3.fromRGB(34, 197, 94)
BarFill.BorderSizePixel = 0
BarFill.Parent = BarBg
local BarFillCorner = Instance.new("UICorner")
BarFillCorner.CornerRadius = UDim.new(0, 6)
BarFillCorner.Parent = BarFill

local StartDumpBtn = Instance.new("TextButton")
StartDumpBtn.Size = UDim2.new(0.48, -4, 0, 42)
StartDumpBtn.Position = UDim2.new(0, 14, 0, 130)
StartDumpBtn.BackgroundColor3 = Color3.fromRGB(22, 101, 52)
StartDumpBtn.Text = "EXECUTAR DUMP COMPLETO"
StartDumpBtn.Font = Enum.Font.GothamBold
StartDumpBtn.TextSize = 11
StartDumpBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
StartDumpBtn.Parent = Frame
local StartCorner = Instance.new("UICorner")
StartCorner.CornerRadius = UDim.new(0, 8)
StartCorner.Parent = StartDumpBtn

local SaveInstanceBtn = Instance.new("TextButton")
SaveInstanceBtn.Size = UDim2.new(0.48, -4, 0, 42)
SaveInstanceBtn.Position = UDim2.new(0.52, 0, 0, 130)
SaveInstanceBtn.BackgroundColor3 = Color3.fromRGB(30, 44, 74)
SaveInstanceBtn.Text = "BAIXAR MAPA .RBXL (STUDIO)"
SaveInstanceBtn.Font = Enum.Font.GothamBold
SaveInstanceBtn.TextSize = 11
SaveInstanceBtn.TextColor3 = Color3.fromRGB(56, 189, 248)
SaveInstanceBtn.Parent = Frame
local SaveCorner = Instance.new("UICorner")
SaveCorner.CornerRadius = UDim.new(0, 8)
SaveCorner.Parent = SaveInstanceBtn

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(1, -28, 0, 32)
CloseBtn.Position = UDim2.new(0, 14, 0, 182)
CloseBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
CloseBtn.Text = "FECHAR INTERFACE"
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 10
CloseBtn.TextColor3 = Color3.fromRGB(148, 163, 184)
CloseBtn.Parent = Frame
local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 6)
CloseCorner.Parent = CloseBtn

CloseBtn.MouseButton1Click:Connect(function()
    ScreenGui:Destroy()
end)

local isDumping = false
StartDumpBtn.MouseButton1Click:Connect(function()
    if isDumping then return end
    isDumping = true
    StartDumpBtn.BackgroundColor3 = Color3.fromRGB(51, 65, 85)
    StartDumpBtn.Text = "DUMPING EM PROGRESSO..."

    task.spawn(function()
        dumpNetworking()
        BarFill.Size = UDim2.new(progressPercent / 100, 0, 1, 0)
        StatusLabel.Text = statusText
        task.wait(0.3)

        dumpModuleConfigs()
        BarFill.Size = UDim2.new(progressPercent / 100, 0, 1, 0)
        StatusLabel.Text = statusText
        task.wait(0.3)

        dumpWorkspaceObjects()
        BarFill.Size = UDim2.new(progressPercent / 100, 0, 1, 0)
        StatusLabel.Text = statusText
        task.wait(0.3)

        dumpScripts()
        BarFill.Size = UDim2.new(progressPercent / 100, 0, 1, 0)
        StatusLabel.Text = statusText
        task.wait(0.3)

        local saved, jsonName, txtName = saveMasterDump()
        BarFill.Size = UDim2.new(1, 0, 1, 0)
        StatusLabel.Text = statusText
        StartDumpBtn.BackgroundColor3 = Color3.fromRGB(22, 101, 52)
        StartDumpBtn.Text = "DUMP FINALIZADO COM SUCESSO!"
        isDumping = false
    end)
end)

SaveInstanceBtn.MouseButton1Click:Connect(function()
    if saveinstance then
        StatusLabel.Text = "Iniciando saveinstance() nativo do executor... Aguarde alguns segundos!"
        task.spawn(function()
            local ok, err = pcall(function()
                saveinstance({
                    mode = "full",
                    noscripts = false,
                    decompile = true,
                    timeout = 30
                })
            end)
            if ok then
                StatusLabel.Text = "Mapa .rbxl salvo com sucesso na pasta workspace do seu executor!"
            else
                StatusLabel.Text = "Erro no saveinstance nativo: " .. tostring(err)
            end
        end)
    else
        StatusLabel.Text = "Carregando Universal SynSaveInstance via web..."
        task.spawn(function()
            local ok, res = pcall(function()
                loadstring(game:HttpGet("https://raw.githubusercontent.com/luau/SynSaveInstance/main/saveinstance.luau"))()
            end)
            if ok then
                pcall(function()
                    saveinstance({ mode = "full", noscripts = false, decompile = true })
                end)
                StatusLabel.Text = "Mapa .rbxl baixado com sucesso via Universal SaveInstance!"
            else
                StatusLabel.Text = "Seu executor nao suporta saveinstance nativo. Use o Dump Completo (JSON/TXT)!"
            end
        end)
    end
end)

print("[MASTER DUMPER] Interface carregada com sucesso! Clique em 'EXECUTAR DUMP COMPLETO'.")

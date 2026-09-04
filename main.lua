--[[
    STEAL AN EGG: TELEMETRY & RADAR OBSERVER (v3.8)
    -----------------------------------------------------------------------
    - Leitura puramente observacional e passiva do Workspace e ReplicatedStorage.
    - Zero poluição de console (print/warn silenciados contra LogService).
    - Zero poluição de ambiente global (_G e getgenv limpos).
    - Radar ao vivo com coordenadas exatas (X, Y, Z), peso (Kg), raridade e zona.
    - Dumper estrutural completo de instâncias do jogo para arquivo local.
    - Interface minimalista em azul técnico escuro, sem emojis ou hooks invasivos.
]]

-- 1. Silenciamento Total Preventivo contra LogService.MessageOut
local function silentLog(...) end
local print = silentLog
local warn = silentLog

-- 2. Limpeza Preventiva de Globais para evitar detecção em _G
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

-- 4. Utilitários de Stealth & GUI
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

-- 5. Configurações Locais (Privadas)
local Settings = {
    EggESP = false,
    PlayerESP = false,
    ESPMaxDistance = 2500,
    SearchQuery = "",
    SaveLogsToDisk = false
}

local LogHistory = {}
local function addLog(tag, msg)
    local timeStr = os.date("%H:%M:%S")
    local entry = string.format("[%s] [%s] %s", timeStr, tag, tostring(msg))
    table.insert(LogHistory, 1, entry)
    if #LogHistory > 200 then
        table.remove(LogHistory, #LogHistory)
    end
    if _G_InternalUpdateConsole then
        _G_InternalUpdateConsole()
    end
end

-- 6. Helper de Posição e Personagem
local function getHRP()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getPromptPosition(prompt)
    if not prompt or not prompt.Parent then return nil end
    local holder = prompt.Parent
    if holder:IsA("Attachment") then holder = holder.Parent end
    if not holder then return nil end
    if holder:IsA("BasePart") then return holder.Position end
    if holder:IsA("Model") then return holder:GetPivot().Position end
    local part = holder:FindFirstChildWhichIsA("BasePart", true)
    return part and part.Position or nil
end

local function plainText(str)
    return tostring(str or ""):gsub("<[^>]->", ""):lower()
end

local function isEggPrompt(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") or not prompt.Enabled then
        return false
    end
    local act = plainText(prompt.ActionText)
    local obj = plainText(prompt.ObjectText)
    local hasSteal = act:find("steal", 1, true) or act:find("roubar", 1, true)
    local hasEgg = obj:find("egg", 1, true) or obj:find("ovo", 1, true)
    return (hasSteal ~= nil and hasEgg ~= nil)
end

-- 7. Avaliação Observacional Real de Ovos
local RarityTiers = {
    ["admin abuse"] = 80000,
    ["monster parasite"] = 70000,
    ["dragon"] = 65000,
    ["sakura"] = 60000,
    ["brainrot"] = 55000,
    ["limited"] = 50000,
    ["prehistoric"] = 35000,
    ["abyss"] = 28000,
    ["volcano"] = 20000,
    ["cherry"] = 10000,
    ["secret"] = 45000,
    ["mythic"] = 25000,
    ["legendary"] = 18000,
    ["epic"] = 8000,
    ["rare"] = 4000,
    ["uncommon"] = 1500,
    ["common"] = 300
}

local function parseEggData(eggModel, prompt)
    local maxScore = 0
    local detectedRarity = "Normal"
    local detectedWeight = 0
    local detectedIncome = nil

    local function inspectString(s)
        if not s or s == "" then return end
        local low = tostring(s):lower()

        -- Peso em Kg
        local kgMatch = low:match("([%d%,%.]+)%s*kg")
        if kgMatch then
            local n = tonumber((kgMatch:gsub(",", "")))
            if n and n > detectedWeight then
                detectedWeight = n
            end
        end

        -- Renda $/s
        local num, suffix = low:match("%$%s*([%d][%d%,%.]*)%s*(%a*)%s*/%s*s")
        if num and not detectedIncome then
            detectedIncome = "$" .. num .. (suffix or ""):upper() .. "/s"
        end

        -- Raridade
        for kw, score in pairs(RarityTiers) do
            if low:find(kw, 1, true) then
                if score > maxScore then
                    maxScore = score
                    detectedRarity = kw:upper()
                end
            end
        end
    end

    if prompt then
        inspectString(prompt.ObjectText)
        inspectString(prompt.ActionText)
    end

    if eggModel then
        inspectString(eggModel.Name)

        pcall(function()
            for k, v in pairs(eggModel:GetAttributes()) do
                inspectString(k)
                inspectString(v)
            end
        end)

        pcall(function()
            for _, child in ipairs(eggModel:GetChildren()) do
                if child:IsA("ValueBase") then
                    inspectString(child.Name)
                    inspectString(child.Value)
                end
            end
        end)

        pcall(function()
            local count = 0
            for _, d in ipairs(eggModel:GetDescendants()) do
                if count >= 30 then break end
                if d:IsA("TextLabel") or d:IsA("TextButton") then
                    count = count + 1
                    inspectString(d.Text)
                end
            end
        end)
    end

    if detectedWeight > 0 and maxScore < (detectedWeight * 2) then
        maxScore = detectedWeight * 2
        detectedRarity = string.format("%s Kg", tostring(detectedWeight))
    end

    return maxScore, detectedRarity, detectedWeight, detectedIncome
end

local function getEggZone(eggModel, prompt)
    local cur = eggModel or (prompt and prompt.Parent)
    local zone = "Mapa Aberto"
    local owner = nil

    while cur and cur ~= Services.Workspace do
        local n = cur.Name
        local low = n:lower()

        if low:find("plot") or low:find("base") or low:find("spawn") or low:find("house") then
            pcall(function()
                local val = cur:FindFirstChild("Owner") or cur:FindFirstChild("Player") or cur:FindFirstChild("OwnerName")
                if val and val.Value and tostring(val.Value) ~= "" then
                    owner = tostring(val.Value)
                end
            end)
            zone = n .. (owner and (" (" .. owner .. ")") or "")
            break
        elseif low:find("island") or low:find("zone") or low:find("area") or low:find("world") then
            zone = n
            break
        end
        cur = cur.Parent
    end

    return zone, owner
end

-- 8. Scanner Passivo do Mapa (Sob Demanda)
local function scanEggs()
    local list = {}
    local hrp = getHRP()
    local myName = LocalPlayer.Name:lower()

    pcall(function()
        for _, desc in ipairs(Services.Workspace:GetDescendants()) do
            if desc:IsA("ProximityPrompt") and isEggPrompt(desc) then
                local parent = desc.Parent
                local pos = getPromptPosition(desc)
                if parent and pos then
                    local fullName = parent:GetFullName():lower()
                    local isMyPlot = fullName:find(myName) ~= nil
                    local dist = hrp and (hrp.Position - pos).Magnitude or 0
                    local score, rarity, weight, income = parseEggData(parent, desc)
                    local zone, owner = getEggZone(parent, desc)
                    local dName = (desc.ObjectText ~= "" and desc.ObjectText) or parent.Name

                    table.insert(list, {
                        Prompt = desc,
                        Parent = parent,
                        Name = dName,
                        Rarity = rarity,
                        RarityScore = score,
                        WeightKg = weight,
                        Income = income,
                        Zone = zone,
                        IsMyPlot = isMyPlot,
                        PlotOwner = owner,
                        Position = pos,
                        Distance = dist,
                        HoldDuration = desc.HoldDuration
                    })
                end
            end
        end
    end)

    table.sort(list, function(a, b)
        if a.RarityScore ~= b.RarityScore then
            return a.RarityScore > b.RarityScore
        end
        return a.Distance < b.Distance
    end)

    return list
end

-- 9. Dumper Estrutural Completo para Análise Local
local function exportGameDump()
    local out = {}
    local function add(s) table.insert(out, s or "") end

    add("================================================================================")
    add("ROUBE UM OVO - INVENTARIO ESTRUTURAL COMPLETO")
    add("Data: " .. os.date("%Y-%m-%d %H:%M:%S") .. " | PlaceId: " .. tostring(game.PlaceId))
    add("================================================================================\n")

    add("[1] REPLICATED STORAGE (Modulos, Tabelas, Configs):")
    pcall(function()
        for _, child in ipairs(Services.ReplicatedStorage:GetChildren()) do
            add(string.format("  - %s [%s] (Filhos: %d)", child.Name, child.ClassName, #child:GetChildren()))
            local low = child.Name:lower()
            if low:find("egg") or low:find("rarit") or low:find("data") or low:find("config") or low:find("item") then
                for _, sub in ipairs(child:GetChildren()) do
                    add(string.format("      > %s [%s]", sub.Name, sub.ClassName))
                end
            end
        end
    end)
    add("\n")

    add("[2] WORKSPACE (Zonas, Modelos e Spawns):")
    pcall(function()
        for _, child in ipairs(Services.Workspace:GetChildren()) do
            if child:IsA("Folder") or child:IsA("Model") then
                add(string.format("  - %s [%s] (%d objs)", child.Name, child.ClassName, #child:GetChildren()))
            end
        end
    end)
    add("\n")

    add("[3] OVOS E PROMPTS ATIVOS NO SERVIDOR:")
    local eggs = scanEggs()
    for i, e in ipairs(eggs) do
        add(string.format("#%02d [%s] %s | Zona: %s | Pos: (%.1f, %.1f, %.1f) | Dist: %dm | Peso: %s | Renda: %s",
            i, e.Rarity, e.Name, e.Zone, e.Position.X, e.Position.Y, e.Position.Z, math.floor(e.Distance),
            e.WeightKg > 0 and (tostring(e.WeightKg) .. " Kg") or "N/D", e.Income or "N/D"
        ))
    end
    add("\n")

    add("[4] PLAYERGUI (Menus Ativos):")
    pcall(function()
        local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if pg then
            for _, g in ipairs(pg:GetChildren()) do
                if g:IsA("ScreenGui") and g.Enabled then
                    add("  - ScreenGui: " .. g.Name)
                end
            end
        end
    end)

    add("================================================================================")
    add("FIM DO INVENTARIO.")

    local text = table.concat(out, "\n")
    pcall(function()
        if writefile then writefile("ROUBE_UM_OVO_DUMP.txt", text) end
        if setclipboard then setclipboard(text) end
    end)
    addLog("DUMP", "Dump estrutural exportado com sucesso para ROUBE_UM_OVO_DUMP.txt e copiado!")
    return text, #eggs
end

-- 10. ESP Leve e Passivo
local activeESPs = {}
local function clearESP()
    for target, item in pairs(activeESPs) do
        pcall(function() if item and item.Parent then item:Destroy() end end)
    end
    activeESPs = {}
end

local function applyESP(target, labelText, color)
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
    tag.Text = labelText
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

local function refreshESP()
    if not Settings.EggESP and not Settings.PlayerESP then
        clearESP()
        return
    end

    pcall(function()
        local seen = {}
        local hrp = getHRP()
        local myName = LocalPlayer.Name:lower()

        if Settings.EggESP then
            local eggs = scanEggs()
            for i = 1, math.min(#eggs, 25) do
                local e = eggs[i]
                if not e.IsMyPlot and e.Distance <= Settings.ESPMaxDistance then
                    seen[e.Parent] = true
                    local wText = e.WeightKg > 0 and (" [" .. tostring(e.WeightKg) .. " Kg]") or (" [" .. e.Rarity .. "]")
                    local label = e.Name .. wText .. " (" .. math.floor(e.Distance) .. "m)"
                    applyESP(e.Parent, label, Color3.fromRGB(56, 189, 248))
                end
            end
        end

        if Settings.PlayerESP then
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

-- 11. CONSTRUÇÃO DA INTERFACE (TEMA TECH BLUE MINIMALISTA - ZERO EMOJIS)
local TweenService = Services.TweenService
local UserInputService = Services.UserInputService

local C_BG       = Color3.fromRGB(10, 14, 23)       -- Obsidian Dark Slate
local C_SIDEBAR  = Color3.fromRGB(14, 19, 31)       -- Dark Navy Sidebar
local C_CARD     = Color3.fromRGB(18, 25, 41)       -- Slate Card Background
local C_BORDER   = Color3.fromRGB(30, 41, 59)       -- Border Stroke (#1E293B)
local C_ITEM_BG  = Color3.fromRGB(22, 32, 51)       -- Input / Box Background
local C_BLUE     = Color3.fromRGB(56, 189, 248)     -- Tech Blue (#38BDF8)
local C_BLUE_DARK= Color3.fromRGB(14, 116, 144)
local C_TEXT     = Color3.fromRGB(248, 250, 252)    -- Pure Clean White
local C_TEXT_DIM = Color3.fromRGB(148, 163, 184)    -- Slate Dim Text
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

-- Instanciação Antecipada e Protegida do ScreenGui
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = getRandomName()
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset = true
protectGui(ScreenGui)
ScreenGui.Parent = getGuiContainer()

local MainFrame = Instance.new("Frame")
MainFrame.Name = getRandomName()
MainFrame.Size = UDim2.new(0, 740, 0, 500)
MainFrame.Position = UDim2.new(0.5, -370, 0.5, -250)
MainFrame.BackgroundColor3 = C_BG
MainFrame.BorderSizePixel = 0
MainFrame.Parent = ScreenGui
addCorner(MainFrame, 8)
addStroke(MainFrame, C_BORDER, 1)

-- Drag Handler
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

-- Sidebar Esquerda
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

-- Header / Logo Minimalista
local BrandHeader = Instance.new("Frame")
BrandHeader.Size = UDim2.new(1, 0, 0, 50)
BrandHeader.BackgroundTransparency = 1
BrandHeader.Parent = Sidebar

local TagLabel = Instance.new("TextLabel")
TagLabel.Size = UDim2.new(1, -24, 0, 14)
TagLabel.Position = UDim2.new(0, 16, 0, 12)
TagLabel.BackgroundTransparency = 1
TagLabel.Text = "STEAL AN EGG"
TagLabel.Font = Enum.Font.GothamBold
TagLabel.TextSize = 9.5
TagLabel.TextColor3 = C_TEXT_DIM
TagLabel.TextXAlignment = Enum.TextXAlignment.Left
TagLabel.Parent = BrandHeader

local MainTitle = Instance.new("TextLabel")
MainTitle.Size = UDim2.new(1, -24, 0, 20)
MainTitle.Position = UDim2.new(0, 16, 0, 26)
MainTitle.BackgroundTransparency = 1
MainTitle.RichText = true
MainTitle.Text = '<b>OBSERVER</b> <font color="#38BDF8">v3.8</font>'
MainTitle.Font = Enum.Font.GothamBold
MainTitle.TextSize = 16
MainTitle.TextColor3 = C_TEXT
MainTitle.TextXAlignment = Enum.TextXAlignment.Left
MainTitle.Parent = BrandHeader

-- Navegação
local NavList = Instance.new("Frame")
NavList.Size = UDim2.new(1, 0, 1, -110)
NavList.Position = UDim2.new(0, 0, 0, 58)
NavList.BackgroundTransparency = 1
NavList.Parent = Sidebar
addPadding(NavList, 6, 6, 10, 10)

local NavLayout = Instance.new("UIListLayout")
NavLayout.Padding = UDim.new(0, 4)
NavLayout.Parent = NavList

-- Profile no Rodapé
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
StatusDot.Text = '<font color="#10B981">●</font> Observer Active'
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

-- Search Box
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
SearchInput.PlaceholderText = "Search eggs by name, zone, weight or rarity..."
SearchInput.PlaceholderColor3 = C_TEXT_DIM
SearchInput.Text = ""
SearchInput.Font = Enum.Font.Gotham
SearchInput.TextSize = 11
SearchInput.TextColor3 = C_TEXT
SearchInput.TextXAlignment = Enum.TextXAlignment.Left
SearchInput.ClearTextOnFocus = false
SearchInput.Parent = SearchBox

-- Refresh Button
local RefreshBtn = Instance.new("TextButton")
RefreshBtn.Size = UDim2.new(0, 95, 0, 28)
RefreshBtn.Position = UDim2.new(1, -105, 0, 8)
RefreshBtn.BackgroundColor3 = C_BLUE_DARK
RefreshBtn.Text = "REFRESH"
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
        if lbl then
            tw(lbl, { TextColor3 = active and C_TEXT or C_TEXT_DIM }, 0.12)
        end
        local dot = btn:FindFirstChild("Dot")
        if dot then
            dot.Visible = active
        end
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
-- 1. TAB: RADAR (LIVE EGG TELEMETRY)
--================================================================--

local RadarPage = createPage("Radar")

local RadarStatusCard = createCard(RadarPage, "STATUS & FILTERS")
local RadarStatusLabel = Instance.new("TextLabel")
RadarStatusLabel.Size = UDim2.new(1, 0, 0, 20)
RadarStatusLabel.BackgroundTransparency = 1
RadarStatusLabel.Text = "Scanning active Workspace prompts..."
RadarStatusLabel.Font = Enum.Font.Gotham
RadarStatusLabel.TextSize = 11
RadarStatusLabel.TextColor3 = C_TEXT_DIM
RadarStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
RadarStatusLabel.Parent = RadarStatusCard

local RadarListCard = createCard(RadarPage, "OBSERVED EGGS")
local EggListHolder = Instance.new("Frame")
EggListHolder.Size = UDim2.new(1, 0, 0, 0)
EggListHolder.AutomaticSize = Enum.AutomaticSize.Y
EggListHolder.BackgroundTransparency = 1
EggListHolder.Parent = RadarListCard

local EggListLayout = Instance.new("UIListLayout")
EggListLayout.Padding = UDim.new(0, 5)
EggListLayout.SortOrder = Enum.SortOrder.LayoutOrder
EggListLayout.Parent = EggListHolder

local currentDiscovered = {}

local function renderRadar(list)
    currentDiscovered = list or {}
    for _, child in ipairs(EggListHolder:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end

    local q = Settings.SearchQuery:lower()
    local matched = 0

    for idx, e in ipairs(currentDiscovered) do
        local fullSearch = (e.Name .. " " .. e.Rarity .. " " .. e.Zone .. " " .. tostring(e.WeightKg)):lower()
        if q == "" or fullSearch:find(q, 1, true) then
            matched = matched + 1

            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, 0, 0, 48)
            row.BackgroundColor3 = C_ITEM_BG
            row.LayoutOrder = idx
            row.Parent = EggListHolder
            addCorner(row, 5)
            addStroke(row, C_BORDER, 1)

            -- Linha 1: Nome + Raridade + Distância
            local title = Instance.new("TextLabel")
            title.Size = UDim2.new(1, -95, 0, 16)
            title.Position = UDim2.new(0, 8, 0, 6)
            title.BackgroundTransparency = 1
            title.RichText = true
            local wStr = e.WeightKg > 0 and (tostring(e.WeightKg) .. " Kg") or e.Rarity
            title.Text = string.format('<b>#%02d %s</b>  <font color="#38BDF8">[%s]</font>', idx, e.Name, wStr)
            title.Font = Enum.Font.GothamBold
            title.TextSize = 11.5
            title.TextColor3 = C_TEXT
            title.TextXAlignment = Enum.TextXAlignment.Left
            title.Parent = row

            local dist = Instance.new("TextLabel")
            dist.Size = UDim2.new(0, 85, 0, 16)
            dist.Position = UDim2.new(1, -90, 0, 6)
            dist.BackgroundTransparency = 1
            dist.Text = string.format("%d studs", math.floor(e.Distance))
            dist.Font = Enum.Font.GothamBold
            dist.TextSize = 10.5
            dist.TextColor3 = C_BLUE
            dist.TextXAlignment = Enum.TextXAlignment.Right
            dist.Parent = row

            -- Linha 2: Zona / Coordenadas / Botão Copiar
            local sub = Instance.new("TextLabel")
            sub.Size = UDim2.new(1, -95, 0, 16)
            sub.Position = UDim2.new(0, 8, 0, 26)
            sub.BackgroundTransparency = 1
            sub.Text = string.format("Zone: %s | (%.0f, %.0f, %.0f)", e.Zone, e.Position.X, e.Position.Y, e.Position.Z)
            sub.Font = Enum.Font.Code
            sub.TextSize = 9.5
            sub.TextColor3 = C_TEXT_DIM
            sub.TextXAlignment = Enum.TextXAlignment.Left
            sub.Parent = row

            local copyBtn = Instance.new("TextButton")
            copyBtn.Size = UDim2.new(0, 70, 0, 20)
            copyBtn.Position = UDim2.new(1, -78, 0, 24)
            copyBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
            copyBtn.Text = "COPY POS"
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
                copyBtn.Text = "COPIED"
                task.delay(1, function() copyBtn.Text = "COPY POS" end)
            end)
        end
    end

    RadarStatusLabel.Text = string.format("Tracking %d eggs on map (%d visible matching query).", #currentDiscovered, matched)
end

local function executeScan()
    local eggs = scanEggs()
    renderRadar(eggs)
    addLog("RADAR", string.format("Scan complete. %d active prompts detected.", #eggs))
    refreshESP()
end

RefreshBtn.MouseButton1Click:Connect(executeScan)
SearchInput:GetPropertyChangedSignal("Text"):Connect(function()
    Settings.SearchQuery = SearchInput.Text
    renderRadar(currentDiscovered)
end)

--================================================================--
-- 2. TAB: INSPECTOR (GAME DATA & STRUCTURE DUMP)
--================================================================--

local InspectorPage = createPage("Inspector")
local DumpCard = createCard(InspectorPage, "STRUCTURAL DATA EXTRACTION")

local DumpDesc = Instance.new("TextLabel")
DumpDesc.Size = UDim2.new(1, 0, 0, 32)
DumpDesc.BackgroundTransparency = 1
DumpDesc.Text = "Inspects and exports all client-accessible instances from ReplicatedStorage, Workspace, and PlayerGui to an offline document."
DumpDesc.Font = Enum.Font.Gotham
DumpDesc.TextSize = 11
DumpDesc.TextColor3 = C_TEXT_DIM
DumpDesc.TextWrapped = true
DumpDesc.TextXAlignment = Enum.TextXAlignment.Left
DumpDesc.Parent = DumpCard

local DumpStatusLabel = Instance.new("TextLabel")
DumpStatusLabel.Size = UDim2.new(1, 0, 0, 18)
DumpStatusLabel.BackgroundTransparency = 1
DumpStatusLabel.Text = "Status: Ready to export"
DumpStatusLabel.Font = Enum.Font.Code
DumpStatusLabel.TextSize = 10.5
DumpStatusLabel.TextColor3 = C_BLUE
DumpStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
DumpStatusLabel.Parent = DumpCard

addButton(DumpCard, "EXPORT STRUCTURAL DUMP (TXT & CLIPBOARD)", function()
    DumpStatusLabel.Text = "Generating dump..."
    local text, count = exportGameDump()
    DumpStatusLabel.Text = string.format("Dump saved to ROUBE_UM_OVO_DUMP.txt (%d eggs documented)", count)
end)

--================================================================--
-- 3. TAB: VISUALS (IN-GAME 3D MARKERS)
--================================================================--

local VisualsPage = createPage("Visuals")
local VisualsCard = createCard(VisualsPage, "3D BILLBOARD OVERLAYS")

addToggle(VisualsCard, "Enable Egg Overlays (Weight, Name, Distance)", Settings.EggESP, function(state)
    Settings.EggESP = state
    refreshESP()
    addLog("ESP", "Egg overlays " .. (state and "enabled" or "disabled"))
end)

addToggle(VisualsCard, "Enable Player Overlays", Settings.PlayerESP, function(state)
    Settings.PlayerESP = state
    refreshESP()
end)

addSlider(VisualsCard, "Maximum Overlay Range", 100, 5000, Settings.ESPMaxDistance, "studs", function(val)
    Settings.ESPMaxDistance = val
    refreshESP()
end)

addButton(VisualsCard, "CLEAR ALL OVERLAYS", function()
    clearESP()
    addLog("ESP", "All overlays purged from scene.")
end)

--================================================================--
-- 4. TAB: CONSOLE (INTERNAL LOG VIEWER)
--================================================================--

local ConsolePage = createPage("Console")
local ConsoleCard = createCard(ConsolePage, "TELEMETRY LOG STREAM")

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
ConsoleText.Text = "=== TELEMETRY OBSERVER READY ==="
ConsoleText.Parent = ConsoleScroll

local function updateConsole()
    ConsoleText.Text = table.concat(LogHistory, "\n")
    ConsoleScroll.CanvasSize = UDim2.new(0, 0, 0, #LogHistory * 16 + 20)
end
_G_InternalUpdateConsole = updateConsole
updateConsole()

addButton(ConsoleCard, "COPY LOG STREAM TO CLIPBOARD", function()
    pcall(function()
        if setclipboard then setclipboard(table.concat(LogHistory, "\n")) end
        addLog("SYSTEM", "Logs copied to clipboard.")
    end)
end)

addButton(ConsoleCard, "PURGE LOG HISTORY", function()
    LogHistory = {}
    updateConsole()
end)

--================================================================--
-- 5. TAB: SETTINGS
--================================================================--

local SettingsPage = createPage("Settings")
local SettCard = createCard(SettingsPage, "GENERAL SETTINGS")

local KeyInfo = Instance.new("TextLabel")
KeyInfo.Size = UDim2.new(1, 0, 0, 20)
KeyInfo.BackgroundTransparency = 1
KeyInfo.Text = "Toggle Menu Key: [LeftControl]"
KeyInfo.Font = Enum.Font.GothamMedium
KeyInfo.TextSize = 11.5
KeyInfo.TextColor3 = C_TEXT
KeyInfo.TextXAlignment = Enum.TextXAlignment.Left
KeyInfo.Parent = SettCard

addButton(SettCard, "UNLOAD OBSERVER SCRIPT", function()
    scriptActive = false
    clearESP()
    ScreenGui:Destroy()
end)

-- Montagem da Sidebar (Zero Emojis)
addNavTab("Radar", "RADAR")
addNavTab("Inspector", "INSPECTOR")
addNavTab("Visuals", "VISUALS")
addNavTab("Console", "CONSOLE")
addNavTab("Settings", "SETTINGS")

-- Inicialização
switchTab("Radar")
task.delay(0.2, function()
    executeScan()
end)

-- Atalho LeftControl
UserInputService.InputBegan:Connect(function(i, proc)
    if not proc and i.KeyCode == Enum.KeyCode.LeftControl then
        MainFrame.Visible = not MainFrame.Visible
    end
end)

-- Botão Flutuante Mobile Minimalista (Sem Emojis, Apenas Dot/Badge)
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

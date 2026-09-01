--[[
    HOP SERVER v1.0 — Roube um Ovo
    ══════════════════════════════════════════════════════════════════════
    • Busca servidores públicos via API do Roblox
    • Ordena pelo menor número de jogadores (empate → maior FPS)
    • Atualiza a lista automaticamente a cada 8 segundos
    • Faz um re-scan imediato antes de pular (dados mais frescos)
    • Tenta auto-executar este script no novo servidor via queue_on_teleport
    • Interface Fluent UI arrastável — RCtrl para mostrar/ocultar
    ══════════════════════════════════════════════════════════════════════
]]

print("========== CARREGANDO: HOP SERVER v1.0 ==========")

-- ╔══════════════════════════════════════════════╗
-- ║           SERVIÇOS & CONFIGURAÇÃO            ║
-- ╚══════════════════════════════════════════════╝

local function safeService(name)
    local s = game:GetService(name)
    return (cloneref and cloneref(s)) or s
end

local Players          = safeService("Players")
local TeleportService  = safeService("TeleportService")
local HttpService      = safeService("HttpService")
local TweenService     = safeService("TweenService")
local UserInputService = safeService("UserInputService")

local LocalPlayer = Players.LocalPlayer

local Config = {
    PlaceId         = (game.PlaceId ~= 0) and game.PlaceId or 107778070777162,
    RefreshInterval = 8,
    MaxPages        = 5,
    ToggleKey       = Enum.KeyCode.RightControl,
    SelfURL         = "https://raw.githubusercontent.com/talespxk/Roube-um-ovo-script/refs/heads/main/hop_server.lua",
}

-- ╔══════════════════════════════════════════════╗
-- ║                   ESTADO                    ║
-- ╚══════════════════════════════════════════════╝

local State = {
    servers     = {},
    isScanning  = false,
    isHopping   = false,
    uiVisible   = true,
    minimized   = false,
    lastRefresh = 0,
}

-- ╔══════════════════════════════════════════════╗
-- ║               UTILIDADES                    ║
-- ╚══════════════════════════════════════════════╝

local function safeGet(fn) local ok, v = pcall(fn); return ok and v or nil end

local function getGuiContainer()
    return safeGet(function() return gethui() end)
        or safeGet(function() return cloneref and cloneref(game:GetService("CoreGui")) or game:GetService("CoreGui") end)
        or LocalPlayer:FindFirstChildOfClass("PlayerGui")
end

local function protectGui(gui)
    pcall(function()
        local env = (getgenv and getgenv()) or _G
        local fn = rawget(env, "protectgui") or env.protectgui
        if type(fn) == "function" then fn(gui); return end
        local s = rawget(env, "syn") or env.syn
        if type(s) == "table" and type(s.protect_gui) == "function" then s.protect_gui(gui) end
    end)
end

local function tw(obj, props, t, style, dir)
    TweenService:Create(
        obj,
        TweenInfo.new(t or 0.18, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
        props
    ):Play()
end

local function make(cls, props, parent)
    local o = Instance.new(cls)
    for k, v in pairs(props) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end

-- ╔══════════════════════════════════════════════╗
-- ║          BUSCA DE SERVIDORES (API)           ║
-- ╚══════════════════════════════════════════════╝

local API_URL = "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100&cursor=%s"

local function fetchServers(onDone, onProgress)
    if State.isScanning then
        if onDone then onDone(State.servers, true) end
        return
    end
    State.isScanning = true

    task.spawn(function()
        local all    = {}
        local cursor = ""
        local page   = 0
        local ok     = true
        local jobId  = tostring(game.JobId)

        repeat
            page = page + 1
            if onProgress then
                onProgress(
                    string.format("Página %d/%d...", page, Config.MaxPages),
                    (page - 1) / Config.MaxPages
                )
            end

            local url     = string.format(API_URL, Config.PlaceId, cursor)
            local rawOk, raw = pcall(game.HttpGet, game, url)
            if not rawOk or not raw then ok = false; break end

            local decOk, data = pcall(HttpService.JSONDecode, HttpService, raw)
            if not decOk or not data or not data.data then ok = false; break end

            for _, sv in ipairs(data.data) do
                if sv.id and sv.id ~= jobId then
                    table.insert(all, {
                        jobId      = tostring(sv.id),
                        playing    = tonumber(sv.playing)    or 0,
                        maxPlayers = tonumber(sv.maxPlayers) or 20,
                        fps        = math.floor(tonumber(sv.fps)  or 0),
                        ping       = math.floor(tonumber(sv.ping) or 0),
                    })
                end
            end

            cursor = data.nextPageCursor
        until (not cursor or cursor == "") or page >= Config.MaxPages

        table.sort(all, function(a, b)
            if a.playing ~= b.playing then return a.playing < b.playing end
            if a.fps     ~= b.fps     then return a.fps     > b.fps     end
            return a.ping < b.ping
        end)

        State.servers    = all
        State.isScanning = false
        State.lastRefresh = os.clock()

        if onProgress then onProgress("Concluído", 1) end
        if onDone     then onDone(all, ok) end
    end)
end

-- ╔══════════════════════════════════════════════╗
-- ║          TELEPORTE & AUTO-RELOAD             ║
-- ╚══════════════════════════════════════════════╝

local function queueAutoReload()
    if Config.SelfURL == "" then return end
    pcall(function()
        local src = string.format([[
            task.wait(3)
            pcall(function()
                loadstring(game:HttpGet(%q, true))()
            end)
        ]], Config.SelfURL)

        local fn = nil
        pcall(function() fn = queue_on_teleport end)
        if not fn then pcall(function() fn = syn and syn.queue_on_teleport end) end
        if not fn then
            local env = (getgenv and getgenv()) or _G
            fn = rawget(env, "queue_on_teleport") or env.queue_on_teleport
        end
        if type(fn) == "function" then
            fn(src)
            print("[HopServer] Auto-reload agendado para o próximo servidor.")
        else
            print("[HopServer] queue_on_teleport não disponível — reexecute manualmente.")
        end
    end)
end

local function hopTo(jobId, onResult)
    if State.isHopping then return end
    State.isHopping = true
    queueAutoReload()

    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(Config.PlaceId, jobId, LocalPlayer)
    end)
    if not ok then
        State.isHopping = false
        if onResult then onResult(false, tostring(err)) end
    end
end

-- ╔══════════════════════════════════════════════╗
-- ║                   GUI                       ║
-- ╚══════════════════════════════════════════════╝

pcall(function()
    local prev = getGuiContainer():FindFirstChild("HopServerUI_v1")
    if prev then prev:Destroy() end
end)

local C = {
    BG        = Color3.fromRGB(13,  15,  24),
    Panel     = Color3.fromRGB(20,  23,  37),
    Card      = Color3.fromRGB(27,  31,  50),
    CardHov   = Color3.fromRGB(34,  39,  62),
    Accent    = Color3.fromRGB(108, 99,  255),
    AccentHov = Color3.fromRGB(78,  71,  200),
    GreenBr   = Color3.fromRGB(72,  210, 150),
    Green     = Color3.fromRGB(50,  160, 110),
    Yellow    = Color3.fromRGB(255, 196, 57),
    Red       = Color3.fromRGB(255, 80,  80),
    Text      = Color3.fromRGB(228, 228, 240),
    TextDim   = Color3.fromRGB(130, 135, 160),
    Border    = Color3.fromRGB(40,  44,  68),
    Gold      = Color3.fromRGB(255, 215, 0),
    Silver    = Color3.fromRGB(192, 192, 192),
    Bronze    = Color3.fromRGB(205, 127, 50),
}

local ScreenGui = make("ScreenGui", {
    Name           = "HopServerUI_v1",
    ResetOnSpawn   = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    IgnoreGuiInset = true,
}, getGuiContainer())
protectGui(ScreenGui)

local WIN_W, WIN_H = 380, 520

local MainFrame = make("Frame", {
    Name             = "MainFrame",
    Size             = UDim2.new(0, WIN_W, 0, WIN_H),
    Position         = UDim2.new(0.5, -WIN_W/2, 0.5, -WIN_H/2),
    BackgroundColor3 = C.BG,
    BorderSizePixel  = 0,
    ClipsDescendants = true,
}, ScreenGui)
make("UICorner", { CornerRadius = UDim.new(0, 14) }, MainFrame)
make("UIStroke",  { Color = C.Border, Thickness = 1 }, MainFrame)

make("ImageLabel", {
    Size              = UDim2.new(1, 40, 1, 40),
    Position          = UDim2.new(0, -20, 0, -20),
    BackgroundTransparency = 1,
    Image             = "rbxassetid://6015897843",
    ImageColor3       = Color3.fromRGB(0,0,0),
    ImageTransparency = 0.55,
    ScaleType         = Enum.ScaleType.Slice,
    SliceCenter       = Rect.new(49, 49, 450, 450),
    ZIndex            = 0,
}, MainFrame)

-- ── TitleBar ──────────────────────────────────────
local TitleBar = make("Frame", {
    Size             = UDim2.new(1, 0, 0, 48),
    BackgroundColor3 = C.Panel,
    BorderSizePixel  = 0,
    ZIndex           = 3,
}, MainFrame)
make("UICorner", { CornerRadius = UDim.new(0, 14) }, TitleBar)
make("Frame", {
    Size             = UDim2.new(1, 0, 0, 14),
    Position         = UDim2.new(0, 0, 1, -14),
    BackgroundColor3 = C.Panel,
    BorderSizePixel  = 0,
    ZIndex           = 3,
}, TitleBar)

make("TextLabel", { Text = "🔀", Size = UDim2.new(0,34,0,34), Position = UDim2.new(0,12,0.5,-17),
    BackgroundTransparency=1, TextSize=22, Font=Enum.Font.GothamBold, TextColor3=C.Text, ZIndex=4 }, TitleBar)
make("TextLabel", { Text = "HOP SERVER", Size = UDim2.new(0,160,0,20), Position = UDim2.new(0,50,0,8),
    BackgroundTransparency=1, TextSize=14, Font=Enum.Font.GothamBold, TextColor3=C.Text,
    TextXAlignment=Enum.TextXAlignment.Left, ZIndex=4 }, TitleBar)
make("TextLabel", {
    Text = "Roube um Ovo  •  PlaceId: "..tostring(Config.PlaceId),
    Size = UDim2.new(0,260,0,14), Position = UDim2.new(0,51,0,28),
    BackgroundTransparency=1, TextSize=10, Font=Enum.Font.Gotham, TextColor3=C.TextDim,
    TextXAlignment=Enum.TextXAlignment.Left, ZIndex=4 }, TitleBar)

local MinBtn = make("TextButton", { Text="–", Size=UDim2.new(0,28,0,28), Position=UDim2.new(1,-70,0.5,-14),
    BackgroundColor3=C.Card, TextColor3=C.TextDim, TextSize=18, Font=Enum.Font.GothamBold,
    BorderSizePixel=0, ZIndex=5, AutoButtonColor=false }, TitleBar)
make("UICorner", { CornerRadius=UDim.new(0,7) }, MinBtn)

local CloseBtn = make("TextButton", { Text="✕", Size=UDim2.new(0,28,0,28), Position=UDim2.new(1,-36,0.5,-14),
    BackgroundColor3=Color3.fromRGB(80,30,30), TextColor3=C.Text, TextSize=12, Font=Enum.Font.GothamBold,
    BorderSizePixel=0, ZIndex=5, AutoButtonColor=false }, TitleBar)
make("UICorner", { CornerRadius=UDim.new(0,7) }, CloseBtn)

for _, btn in ipairs({MinBtn, CloseBtn}) do
    local orig = btn.BackgroundColor3
    btn.MouseEnter:Connect(function() tw(btn, {BackgroundColor3=orig:Lerp(Color3.new(1,1,1),0.15)},0.1) end)
    btn.MouseLeave:Connect(function() tw(btn, {BackgroundColor3=orig},0.1) end)
end

-- Drag
local dragging, dragStart, startPos
TitleBar.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging=true; dragStart=i.Position; startPos=MainFrame.Position
    end
end)
TitleBar.InputChanged:Connect(function(i)
    if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
        local d = i.Position - dragStart
        MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+d.X, startPos.Y.Scale, startPos.Y.Offset+d.Y)
    end
end)
UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging=false end
end)

-- ── Body ──────────────────────────────────────────
local Body = make("Frame", {
    Name = "Body", Size=UDim2.new(1,0,1,-48), Position=UDim2.new(0,0,0,48),
    BackgroundTransparency=1, ZIndex=2,
}, MainFrame)

-- Botões de ação
local ActionsRow = make("Frame", {
    Size=UDim2.new(1,-24,0,38), Position=UDim2.new(0,12,0,10), BackgroundTransparency=1,
}, Body)
make("UIListLayout", {
    FillDirection=Enum.FillDirection.Horizontal, Padding=UDim.new(0,8),
    SortOrder=Enum.SortOrder.LayoutOrder, VerticalAlignment=Enum.VerticalAlignment.Center,
}, ActionsRow)

local function makeButton(text, bgColor, w, order, parent)
    local btn = make("TextButton", {
        Text=text, Size=UDim2.new(0,w,1,0), BackgroundColor3=bgColor, TextColor3=C.Text,
        TextSize=12, Font=Enum.Font.GothamBold, BorderSizePixel=0, LayoutOrder=order, AutoButtonColor=false,
    }, parent)
    make("UICorner", { CornerRadius=UDim.new(0,9) }, btn)
    btn.MouseEnter:Connect(function() tw(btn,{BackgroundColor3=bgColor:Lerp(Color3.new(1,1,1),0.12)},0.1) end)
    btn.MouseLeave:Connect(function() tw(btn,{BackgroundColor3=bgColor},0.1) end)
    return btn
end

local ScanBtn    = makeButton("⟳  Atualizar",    C.Card,   108, 1, ActionsRow)
local HopBestBtn = makeButton("🚀  Ir ao Menor", C.Accent, 148, 2, ActionsRow)
make("UIStroke", {Color=C.Border, Thickness=1}, ScanBtn)

-- InfoBar
local InfoBar = make("Frame", {
    Size=UDim2.new(1,-24,0,30), Position=UDim2.new(0,12,0,56),
    BackgroundColor3=C.Card, BorderSizePixel=0,
}, Body)
make("UICorner", {CornerRadius=UDim.new(0,8)}, InfoBar)

local StatusDot = make("Frame", {
    Size=UDim2.new(0,8,0,8), Position=UDim2.new(0,10,0.5,-4),
    BackgroundColor3=C.TextDim, BorderSizePixel=0,
}, InfoBar)
make("UICorner", {CornerRadius=UDim.new(0.5,0)}, StatusDot)

local InfoText = make("TextLabel", {
    Text="Aguardando...", Size=UDim2.new(1,-30,1,0), Position=UDim2.new(0,24,0,0),
    BackgroundTransparency=1, TextSize=11, Font=Enum.Font.Gotham, TextColor3=C.TextDim,
    TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd,
}, InfoBar)

-- Progress bar
local ProgBG = make("Frame", {
    Size=UDim2.new(1,-24,0,2), Position=UDim2.new(0,12,0,90),
    BackgroundColor3=C.Border, BorderSizePixel=0,
}, Body)
make("UICorner", {CornerRadius=UDim.new(0,2)}, ProgBG)
local ProgBar = make("Frame", {
    Size=UDim2.new(0,0,1,0), BackgroundColor3=C.Accent, BorderSizePixel=0,
}, ProgBG)
make("UICorner", {CornerRadius=UDim.new(0,2)}, ProgBar)

-- Cabeçalho
local HeaderRow = make("Frame", {
    Size=UDim2.new(1,-24,0,22), Position=UDim2.new(0,12,0,97), BackgroundTransparency=1,
}, Body)
local function hdr(txt, xOff, w, align)
    return make("TextLabel", {
        Text=txt, Size=UDim2.new(0,w,1,0), Position=UDim2.new(0,xOff,0,0),
        BackgroundTransparency=1, TextSize=10, Font=Enum.Font.GothamBold, TextColor3=C.TextDim,
        TextXAlignment=align or Enum.TextXAlignment.Left,
    }, HeaderRow)
end
hdr("#",       0,   22)
hdr("PLAYERS", 26,  90)
hdr("FPS",     122, 42)
hdr("PING",    170, 48)
hdr("JOB ID",  222, 90)
hdr("IR",      326, 28, Enum.TextXAlignment.Center)

make("Frame", {
    Size=UDim2.new(1,-24,0,1), Position=UDim2.new(0,12,0,122),
    BackgroundColor3=C.Border, BorderSizePixel=0,
}, Body)

-- Lista
local ListFrame = make("ScrollingFrame", {
    Name="ServerList",
    Size=UDim2.new(1,-24,1,-192), Position=UDim2.new(0,12,0,127),
    BackgroundTransparency=1,
    ScrollBarThickness=4, ScrollBarImageColor3=C.Accent, ScrollBarImageTransparency=0.3,
    BorderSizePixel=0,
    CanvasSize=UDim2.new(0,0,0,0), AutomaticCanvasSize=Enum.AutomaticSize.Y,
    ElasticBehavior=Enum.ElasticBehavior.Never,
}, Body)
make("UIListLayout", {Padding=UDim.new(0,4), SortOrder=Enum.SortOrder.LayoutOrder}, ListFrame)

-- Status bar (rodapé)
local StatusBar = make("Frame", {
    Size=UDim2.new(1,0,0,34), Position=UDim2.new(0,0,1,-34),
    BackgroundColor3=C.Panel, BorderSizePixel=0,
}, Body)
make("UICorner", {CornerRadius=UDim.new(0,14)}, StatusBar)
make("Frame", {
    Size=UDim2.new(1,0,0,14), BackgroundColor3=C.Panel, BorderSizePixel=0,
}, StatusBar)

local StatusText = make("TextLabel", {
    Text="Pronto  •  RCtrl para mostrar/ocultar",
    Size=UDim2.new(0.62,0,1,0), Position=UDim2.new(0,12,0,0),
    BackgroundTransparency=1, TextSize=10, Font=Enum.Font.Gotham, TextColor3=C.TextDim,
    TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd,
}, StatusBar)

local CountLabel = make("TextLabel", {
    Text="– servidores",
    Size=UDim2.new(0,110,1,0), Position=UDim2.new(1,-118,0,0),
    BackgroundTransparency=1, TextSize=10, Font=Enum.Font.GothamBold, TextColor3=C.Accent,
    TextXAlignment=Enum.TextXAlignment.Right,
}, StatusBar)

-- ╔══════════════════════════════════════════════╗
-- ║         RENDERIZAÇÃO DA LISTA               ║
-- ╚══════════════════════════════════════════════╝

local function pColor(playing, max)
    if playing == 0 then return C.Accent end
    if playing == 1 then return C.GreenBr end
    if playing <= 3 then return C.Green end
    local r = playing / math.max(max, 1)
    if r < 0.5 then return C.Yellow end
    return C.Red
end

local function fColor(fps)
    if fps >= 55 then return C.GreenBr end
    if fps >= 40 then return C.Green end
    if fps >= 25 then return C.Yellow end
    return C.Red
end

local function rankStr(i)
    if i==1 then return "🥇" elseif i==2 then return "🥈" elseif i==3 then return "🥉" end
    return tostring(i)
end

local function rankCol(i)
    if i==1 then return C.Gold elseif i==2 then return C.Silver elseif i==3 then return C.Bronze end
    return C.Border
end

local function renderList(servers)
    for _, ch in ipairs(ListFrame:GetChildren()) do
        if not ch:IsA("UIListLayout") then ch:Destroy() end
    end

    if #servers == 0 then
        make("TextLabel", {
            Text="Nenhum servidor encontrado.\nClique em ⟳ Atualizar.",
            Size=UDim2.new(1,0,0,64), BackgroundTransparency=1,
            TextSize=12, Font=Enum.Font.Gotham, TextColor3=C.TextDim,
            TextWrapped=true, TextXAlignment=Enum.TextXAlignment.Center, LayoutOrder=1,
        }, ListFrame)
        return
    end

    for i, sv in ipairs(servers) do
        local pc = pColor(sv.playing, sv.maxPlayers)
        local Card = make("Frame", {
            Name="Card_"..i, Size=UDim2.new(1,0,0,40),
            BackgroundColor3=i<=3 and C.CardHov or C.Card,
            BorderSizePixel=0, LayoutOrder=i,
        }, ListFrame)
        make("UICorner", {CornerRadius=UDim.new(0,9)}, Card)

        if i<=3 or sv.playing<=1 then
            local acol = i<=3 and rankCol(i) or C.GreenBr
            local bar = make("Frame", {
                Size=UDim2.new(0,3,1,-10), Position=UDim2.new(0,0,0,5),
                BackgroundColor3=acol, BorderSizePixel=0,
            }, Card)
            make("UICorner", {CornerRadius=UDim.new(0,2)}, bar)
        end

        make("TextLabel", {
            Text=rankStr(i), Size=UDim2.new(0,24,1,0), Position=UDim2.new(0,5,0,0),
            BackgroundTransparency=1, TextSize=i<=3 and 14 or 10, Font=Enum.Font.GothamBold,
            TextColor3=i<=3 and rankCol(i) or C.TextDim, TextXAlignment=Enum.TextXAlignment.Center,
        }, Card)

        make("TextLabel", {
            Text=sv.playing.."/"..sv.maxPlayers, Size=UDim2.new(0,88,1,0), Position=UDim2.new(0,30,0,0),
            BackgroundTransparency=1, TextSize=13, Font=Enum.Font.GothamBold, TextColor3=pc,
            TextXAlignment=Enum.TextXAlignment.Left,
        }, Card)

        if sv.playing == 0 then
            local badge = make("Frame", {
                Size=UDim2.new(0,44,0,18), Position=UDim2.new(0,78,0.5,-9),
                BackgroundColor3=C.Accent:Lerp(C.BG, 0.5), BorderSizePixel=0,
            }, Card)
            make("UICorner", {CornerRadius=UDim.new(0,4)}, badge)
            make("TextLabel", {
                Text="VAZIO", Size=UDim2.new(1,0,1,0), BackgroundTransparency=1,
                TextSize=9, Font=Enum.Font.GothamBold, TextColor3=C.Accent,
            }, badge)
        end

        local fc = fColor(sv.fps)
        local fpsBadge = make("Frame", {
            Size=UDim2.new(0,40,0,20), Position=UDim2.new(0,122,0.5,-10),
            BackgroundColor3=fc:Lerp(C.BG, 0.7), BorderSizePixel=0,
        }, Card)
        make("UICorner", {CornerRadius=UDim.new(0,5)}, fpsBadge)
        make("TextLabel", {
            Text=sv.fps.." fps", Size=UDim2.new(1,0,1,0), BackgroundTransparency=1,
            TextSize=10, Font=Enum.Font.GothamBold, TextColor3=fc,
        }, fpsBadge)

        local pingCol = sv.ping<80 and C.GreenBr or (sv.ping<150 and C.Yellow or C.Red)
        make("TextLabel", {
            Text=sv.ping.."ms", Size=UDim2.new(0,46,1,0), Position=UDim2.new(0,168,0,0),
            BackgroundTransparency=1, TextSize=10, Font=Enum.Font.Gotham, TextColor3=pingCol,
        }, Card)

        make("TextLabel", {
            Text=sv.jobId:sub(1,8).."…", Size=UDim2.new(0,88,1,0), Position=UDim2.new(0,218,0,0),
            BackgroundTransparency=1, TextSize=9, Font=Enum.Font.Code, TextColor3=C.TextDim,
        }, Card)

        local GoBtn = make("TextButton", {
            Text="→", Size=UDim2.new(0,28,0,26), Position=UDim2.new(1,-34,0.5,-13),
            BackgroundColor3=C.Accent, TextColor3=Color3.new(1,1,1), TextSize=14,
            Font=Enum.Font.GothamBold, BorderSizePixel=0, AutoButtonColor=false,
        }, Card)
        make("UICorner", {CornerRadius=UDim.new(0,7)}, GoBtn)
        GoBtn.MouseEnter:Connect(function() tw(GoBtn,{BackgroundColor3=C.AccentHov},0.1) end)
        GoBtn.MouseLeave:Connect(function() tw(GoBtn,{BackgroundColor3=C.Accent},0.1) end)

        Card.MouseEnter:Connect(function() tw(Card,{BackgroundColor3=C.CardHov},0.12) end)
        Card.MouseLeave:Connect(function()
            tw(Card,{BackgroundColor3=i<=3 and C.CardHov or C.Card},0.12)
        end)

        local capturedSv = sv
        GoBtn.MouseButton1Click:Connect(function()
            if State.isHopping then return end
            StatusText.Text = "⏳ Conectando a "..capturedSv.jobId:sub(1,8).."…"
            StatusText.TextColor3 = C.Yellow
            GoBtn.Text = "…"
            GoBtn.Active = false
            hopTo(capturedSv.jobId, function(hok, err)
                GoBtn.Text = "→"
                GoBtn.Active = true
                if not hok then
                    StatusText.Text = "❌ Erro: "..err
                    StatusText.TextColor3 = C.Red
                end
            end)
        end)
    end
end

-- ╔══════════════════════════════════════════════╗
-- ║          LÓGICA DE SCAN & REFRESH           ║
-- ╚══════════════════════════════════════════════╝

local function setStatus(msg, col)
    StatusText.Text = msg
    StatusText.TextColor3 = col or C.TextDim
end

local function doScan(opts)
    opts = opts or {}
    if State.isScanning then
        if opts.onDone then opts.onDone(State.servers, true) end
        return
    end

    if not opts.silent then
        tw(StatusDot, {BackgroundColor3=C.Yellow}, 0.15)
        InfoText.Text = "⏳ Buscando servidores…"
        InfoText.TextColor3 = C.TextDim
    end

    fetchServers(
        function(servers, ok)
            if ok then
                tw(StatusDot, {BackgroundColor3=C.GreenBr}, 0.2)
                local t = os.date("%H:%M:%S")
                InfoText.Text = string.format("✅  %d servidores  •  %s  •  próximo em %ds",
                    #servers, t, Config.RefreshInterval)
                InfoText.TextColor3 = C.TextDim
                CountLabel.Text = #servers.." servidores"
                renderList(servers)
                tw(ProgBar, {Size=UDim2.new(1,0,1,0)}, 0.3)
                task.delay(0.6, function()
                    if ProgBar.Parent then tw(ProgBar,{Size=UDim2.new(0,0,1,0)},0.4) end
                end)
                if not opts.silent then setStatus("✅ Lista atualizada") end
            else
                tw(StatusDot, {BackgroundColor3=C.Red}, 0.2)
                InfoText.Text = "❌ Erro ao buscar. Verifique sua conexão."
                InfoText.TextColor3 = C.Red
                if not opts.silent then setStatus("❌ Falha na conexão", C.Red) end
            end
            if opts.onDone then opts.onDone(servers, ok) end
        end,
        function(msg, pct)
            tw(ProgBar, {Size=UDim2.new(math.clamp(pct,0,1),0,1,0)}, 0.2)
            if not opts.silent then InfoText.Text = "⏳ "..msg end
        end
    )
end

ScanBtn.MouseButton1Click:Connect(function()
    if State.isScanning then return end
    doScan()
end)

HopBestBtn.MouseButton1Click:Connect(function()
    if State.isHopping or State.isScanning then return end
    HopBestBtn.Text = "⏳ Verificando…"
    HopBestBtn.Active = false
    setStatus("⏳ Re-escaneando antes de pular…", C.Yellow)

    doScan({
        onDone = function(servers, ok)
            HopBestBtn.Text = "🚀  Ir ao Menor"
            HopBestBtn.Active = true
            if not ok or #servers == 0 then
                setStatus("❌ Nenhum servidor disponível", C.Red)
                return
            end
            local best = servers[1]
            setStatus(string.format("🚀 Pulando… [%d/%d players | %d fps]",
                best.playing, best.maxPlayers, best.fps), C.GreenBr)
            hopTo(best.jobId, function(hok, err)
                if not hok then setStatus("❌ "..err, C.Red) end
            end)
        end
    })
end)

-- Auto-refresh silencioso
task.spawn(function()
    while ScreenGui.Parent do
        task.wait(Config.RefreshInterval)
        if ScreenGui.Parent and not State.isHopping then
            doScan({silent=true})
        end
    end
end)

-- Pulsar do dot enquanto escaneia
task.spawn(function()
    local pulse = false
    while ScreenGui.Parent do
        task.wait(0.6)
        if State.isScanning and StatusDot.Parent then
            pulse = not pulse
            tw(StatusDot, {BackgroundTransparency=pulse and 0.6 or 0}, 0.5)
        end
    end
end)

-- ╔══════════════════════════════════════════════╗
-- ║         MINIMIZAR / FECHAR / TOGGLE         ║
-- ╚══════════════════════════════════════════════╝

MinBtn.MouseButton1Click:Connect(function()
    State.minimized = not State.minimized
    if State.minimized then
        Body.Visible = false
        tw(MainFrame, {Size=UDim2.new(0,WIN_W,0,48)}, 0.2)
        MinBtn.Text = "+"
    else
        Body.Visible = true
        tw(MainFrame, {Size=UDim2.new(0,WIN_W,0,WIN_H)}, 0.25, Enum.EasingStyle.Back)
        MinBtn.Text = "–"
    end
end)

CloseBtn.MouseButton1Click:Connect(function()
    local cp = MainFrame.Position
    tw(MainFrame, {
        Size=UDim2.new(0,0,0,0),
        Position=UDim2.new(cp.X.Scale, cp.X.Offset+WIN_W/2, cp.Y.Scale, cp.Y.Offset+WIN_H/2)
    }, 0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In)
    task.delay(0.22, function() pcall(function() ScreenGui:Destroy() end) end)
end)

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Config.ToggleKey then
        State.uiVisible = not State.uiVisible
        MainFrame.Visible = State.uiVisible
    end
end)

-- Animação de entrada
MainFrame.Size     = UDim2.new(0, 0, 0, 0)
MainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
tw(MainFrame, {
    Size     = UDim2.new(0, WIN_W, 0, WIN_H),
    Position = UDim2.new(0.5, -WIN_W/2, 0.5, -WIN_H/2),
}, 0.4, Enum.EasingStyle.Back)

task.delay(0.15, function() doScan() end)
setStatus("🔍 Buscando servidores…")
print("========== HOP SERVER v1.0 CARREGADO ==========")
print("[HopServer] PlaceId:", Config.PlaceId)
print("[HopServer] Tecla de toggle: RightControl")

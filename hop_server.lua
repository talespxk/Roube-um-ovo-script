--[[
    HOP SERVER v1.3 -- Roube um Ovo
    Busca instantanea (100 servidores com 1 player).
    Cooldown ultra rapido de 3s (sem esperas longas).
    Cache persistente: nunca perde a lista em caso de delay da API.
    Tecla RightControl para mostrar/ocultar.
]]

print("========== HOP SERVER v1.3 INICIANDO ==========")

-- ============================================================
--  SERVICOS & CONFIGURACAO
-- ============================================================

local function safeService(name)
    local s = game:GetService(name)
    return (cloneref and cloneref(s)) or s
end

local Players          = safeService("Players")
local TeleportService  = safeService("TeleportService")
local HttpService      = safeService("HttpService")
local TweenService     = safeService("TweenService")
local UserInputService = safeService("UserInputService")
local LocalPlayer      = Players.LocalPlayer

local Config = {
    PlaceId         = tostring(game.PlaceId ~= 0 and game.PlaceId or 107778070777162),
    RefreshInterval = 12,
    ToggleKey       = Enum.KeyCode.RightControl,
    SelfURL         = "https://raw.githubusercontent.com/talespxk/Roube-um-ovo-script/refs/heads/main/hop_server.lua",
}

print("[HopServer] PlaceId: " .. Config.PlaceId)
print("[HopServer] JobId:   " .. tostring(game.JobId))

local State = {
    servers       = {},
    isScanning    = false,
    isHopping     = false,
    uiVisible     = true,
    minimized     = false,
    lastRequestAt = 0,  -- timestamp da ultima requisicao HTTP feita
}
local MIN_REQUEST_INTERVAL = 4  -- segundos minimos entre requests (API Roblox: ~3s)

-- ============================================================
--  ANTI-KICK / ANTI-CHEAT BYPASS
--  Tenta interceptar kicks client-side e bloquear remotos AC.
--  Tudo dentro de pcall -- nao quebra se o executor nao suportar.
-- ============================================================

local function setupAntiKick()
    -- 1. Hook __namecall para interceptar :Kick()
    pcall(function()
        local mt = getrawmetatable(game)
        if not mt then return end

        local oldNamecall = mt.__namecall
        setreadonly(mt, false)
        mt.__namecall = newcclosure(function(self, ...)
            local method = getnamecallmethod and getnamecallmethod() or ""
            -- Bloqueia Kick no LocalPlayer
            if method == "Kick" and self == LocalPlayer then
                print("[HopServer] Anti-Kick: kick interceptado e bloqueado!")
                return
            end
            -- Bloqueia FireServer em remotos com nomes de anti-cheat
            if method == "FireServer" or method == "InvokeServer" then
                local name = tostring(self.Name or ""):lower()
                if name:find("ban") or name:find("kick") or name:find("cheat") or name:find("bac") or name:find("anticheat") then
                    print("[HopServer] Anti-Kick: remoto AC bloqueado: " .. tostring(self.Name))
                    return
                end
            end
            return oldNamecall(self, ...)
        end)
        setreadonly(mt, true)
        print("[HopServer] Anti-Kick: hook de namecall ativo.")
    end)

    -- 2. Hook hookfunction em Players.LocalPlayer.Kick diretamente
    pcall(function()
        if hookfunction then
            local oldKick = LocalPlayer.Kick
            hookfunction(oldKick, newcclosure(function(self, ...)
                if self == LocalPlayer then
                    print("[HopServer] Anti-Kick: Players:Kick bloqueado via hookfunction!")
                    return
                end
                return oldKick(self, ...)
            end))
            print("[HopServer] Anti-Kick: hookfunction em Kick ativo.")
        end
    end)

    -- 3. Monitora e destrói scripts de anti-cheat locais conhecidos
    pcall(function()
        local function checkScript(s)
            if not s then return end
            local name = tostring(s.Name or ""):lower()
            if name:find("bac") or name:find("anticheat") or name:find("ac_") then
                pcall(function() s:Destroy() end)
                print("[HopServer] Anti-Kick: script AC destruido: " .. tostring(s.Name))
            end
        end
        for _, s in ipairs(LocalPlayer:GetChildren()) do checkScript(s) end
        for _, s in ipairs(game:GetService("ReplicatedFirst"):GetChildren()) do checkScript(s) end
        LocalPlayer.ChildAdded:Connect(function(s) task.delay(0, function() checkScript(s) end) end)
    end)
end

pcall(setupAntiKick)
print("[HopServer] Anti-Kick iniciado.")

-- ============================================================
--  HTTP GET ROBUSTO
--  User-Agent: Roblox/WinInet (evita bloqueio sem usar cookies por conta)
-- ============================================================

local function httpGet(url)
    local fn = nil
    pcall(function()
        if type(request)      == "function" then fn = request
        elseif type(http_request) == "function" then fn = http_request
        elseif syn and type(syn.request) == "function" then fn = syn.request end
    end)

    if fn then
        local ok, res = pcall(fn, {
            Url     = url,
            Method  = "GET",
            Headers = {
                ["User-Agent"] = "Roblox/WinInet",
                ["Accept"]     = "application/json",
            },
        })
        if ok and res and type(res.Body) == "string" and #res.Body > 5 then
            return res.Body
        end
    end

    local ok, res = pcall(game.HttpGet, game, url, true)
    if ok and type(res) == "string" and #res > 5 then return res end

    error(tostring(res or "Falha HTTP"))
end

-- ============================================================
--  BUSCA DE SERVIDORES
--  Throttle transparente: espera silenciosamente se necessario.
--  Sem bloqueios na UI. Retry automatico em caso de rate limit.
-- ============================================================

local function fetchServers(onDone)
    if State.isScanning then
        if onDone then onDone(State.servers, true, nil) end
        return
    end

    State.isScanning = true

    task.spawn(function()
        -- Throttle: aguarda silenciosamente ate o intervalo minimo
        local elapsed = os.time() - State.lastRequestAt
        if elapsed < MIN_REQUEST_INTERVAL then
            task.wait(MIN_REQUEST_INTERVAL - elapsed)
        end

        local myJobId  = tostring(game.JobId)
        local placeStr = Config.PlaceId
        local url      = "https://games.roblox.com/v1/games/" .. placeStr .. "/servers/Public?sortOrder=Asc&limit=100"

        local function doRequest()
            State.lastRequestAt = os.time()
            local rawOk, raw = pcall(httpGet, url)
            if not rawOk or not raw or raw == "" then
                return false, raw, nil
            end
            local decOk, data = pcall(HttpService.JSONDecode, HttpService, raw)
            if not decOk or type(data) ~= "table" then
                return false, "JSON invalido", nil
            end
            if not data.data then
                -- Rate limit ou erro da API: raw tem {"errors":[...]}
                return false, "sem_data", raw
            end
            return true, nil, data.data
        end

        local ok, errInfo, svData = doRequest()

        -- Se falhou, tenta 1 vez apos 4s automaticamente (sem mostrar erro)
        if not ok then
            print("[HopServer] Primeira tentativa falhou (" .. tostring(errInfo) .. "). Retry em 4s...")
            task.wait(4)
            ok, errInfo, svData = doRequest()
        end

        if not ok or not svData then
            State.isScanning = false
            print("[HopServer] Falha definitiva: " .. tostring(errInfo))
            if onDone then onDone(State.servers, false, tostring(errInfo)) end
            return
        end

        local list = {}
        for _, sv in ipairs(svData) do
            if sv.id and tostring(sv.id) ~= myJobId then
                table.insert(list, {
                    jobId      = tostring(sv.id),
                    playing    = tonumber(sv.playing)    or 0,
                    maxPlayers = tonumber(sv.maxPlayers) or 20,
                    fps        = math.floor(tonumber(sv.fps)  or 0),
                    ping       = math.floor(tonumber(sv.ping) or 0),
                })
            end
        end

        table.sort(list, function(a, b)
            if a.playing ~= b.playing then return a.playing < b.playing end
            if a.fps     ~= b.fps     then return a.fps     > b.fps     end
            return a.ping < b.ping
        end)

        State.servers    = list
        State.isScanning = false

        print("[HopServer] OK! " .. #list .. " servidores.")
        if onDone then onDone(list, true, nil) end
    end)
end

-- ============================================================
--  TELEPORTE & AUTO-RELOAD
-- ============================================================

local function queueAutoReload()
    if Config.SelfURL == "" then return end
    pcall(function()
        local src = 'task.wait(8) pcall(function() loadstring(game:HttpGet("' .. Config.SelfURL .. '",true))() end)'
        local fn = nil
        pcall(function() if type(queue_on_teleport) == "function" then fn = queue_on_teleport end end)
        if not fn then pcall(function() if syn and type(syn.queue_on_teleport) == "function" then fn = syn.queue_on_teleport end end) end
        if not fn then
            local env = (getgenv and getgenv()) or _G
            pcall(function() if type(env.queue_on_teleport) == "function" then fn = env.queue_on_teleport end end)
        end
        if type(fn) == "function" then
            fn(src)
            print("[HopServer] Auto-reload agendado.")
        end
    end)
end

local function hopTo(jobId, onResult)
    if State.isHopping then return end
    State.isHopping = true
    queueAutoReload()
    local placeNum = tonumber(Config.PlaceId) or game.PlaceId
    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(placeNum, jobId, LocalPlayer)
    end)
    if not ok then
        State.isHopping = false
        print("[HopServer] Teleporte falhou: " .. tostring(err))
        if onResult then onResult(false, tostring(err)) end
    end
end

-- ============================================================
--  PALETA DE CORES
-- ============================================================

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

-- ============================================================
--  GUI
-- ============================================================

pcall(function()
    local prev = (gethui and gethui()) or LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if prev then
        local old = prev:FindFirstChild("HopServerUI_v1")
        if old then old:Destroy() end
    end
end)

local function getContainer()
    local c
    pcall(function() c = gethui() end)
    if not c then pcall(function() c = cloneref and cloneref(game:GetService("CoreGui")) or game:GetService("CoreGui") end) end
    if not c then c = LocalPlayer:FindFirstChildOfClass("PlayerGui") end
    return c
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
    TweenService:Create(obj,
        TweenInfo.new(t or 0.18, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
        props):Play()
end

local function make(cls, props, parent)
    local o = Instance.new(cls)
    for k, v in pairs(props) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end

local WIN_W, WIN_H = 380, 520

local ScreenGui = make("ScreenGui", {
    Name           = "HopServerUI_v1",
    ResetOnSpawn   = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    IgnoreGuiInset = true,
}, getContainer())
protectGui(ScreenGui)

local MainFrame = make("Frame", {
    Size             = UDim2.new(0, WIN_W, 0, WIN_H),
    Position         = UDim2.new(0.5, -WIN_W/2, 0.5, -WIN_H/2),
    BackgroundColor3 = C.BG,
    BorderSizePixel  = 0,
    ClipsDescendants = true,
}, ScreenGui)
make("UICorner", { CornerRadius = UDim.new(0, 14) }, MainFrame)
make("UIStroke",  { Color = C.Border, Thickness = 1 }, MainFrame)

make("ImageLabel", {
    Size = UDim2.new(1, 40, 1, 40), Position = UDim2.new(0, -20, 0, -20),
    BackgroundTransparency = 1, Image = "rbxassetid://6015897843",
    ImageColor3 = Color3.fromRGB(0,0,0), ImageTransparency = 0.55,
    ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(49,49,450,450), ZIndex = 0,
}, MainFrame)

-- TitleBar
local TitleBar = make("Frame", {
    Size = UDim2.new(1,0,0,48), BackgroundColor3 = C.Panel, BorderSizePixel = 0, ZIndex = 3,
}, MainFrame)
make("UICorner", { CornerRadius = UDim.new(0,14) }, TitleBar)
make("Frame", {
    Size = UDim2.new(1,0,0,14), Position = UDim2.new(0,0,1,-14),
    BackgroundColor3 = C.Panel, BorderSizePixel = 0, ZIndex = 3,
}, TitleBar)

make("TextLabel", {
    Text = ">> HOP SERVER", Size = UDim2.new(0,220,0,22), Position = UDim2.new(0,12,0,6),
    BackgroundTransparency=1, TextSize=15, Font=Enum.Font.GothamBold, TextColor3=C.Text,
    TextXAlignment=Enum.TextXAlignment.Left, ZIndex=4,
}, TitleBar)

make("TextLabel", {
    Text = "Roube um Ovo  |  PlaceId: " .. Config.PlaceId,
    Size = UDim2.new(0,280,0,14), Position = UDim2.new(0,13,0,28),
    BackgroundTransparency=1, TextSize=10, Font=Enum.Font.Gotham, TextColor3=C.TextDim,
    TextXAlignment=Enum.TextXAlignment.Left, ZIndex=4,
}, TitleBar)

local MinBtn = make("TextButton", {
    Text="-", Size=UDim2.new(0,28,0,28), Position=UDim2.new(1,-70,0.5,-14),
    BackgroundColor3=C.Card, TextColor3=C.TextDim, TextSize=18, Font=Enum.Font.GothamBold,
    BorderSizePixel=0, ZIndex=5, AutoButtonColor=false,
}, TitleBar)
make("UICorner", { CornerRadius=UDim.new(0,7) }, MinBtn)

local CloseBtn = make("TextButton", {
    Text="X", Size=UDim2.new(0,28,0,28), Position=UDim2.new(1,-36,0.5,-14),
    BackgroundColor3=Color3.fromRGB(80,30,30), TextColor3=C.Text, TextSize=12,
    Font=Enum.Font.GothamBold, BorderSizePixel=0, ZIndex=5, AutoButtonColor=false,
}, TitleBar)
make("UICorner", { CornerRadius=UDim.new(0,7) }, CloseBtn)

for _, btn in ipairs({MinBtn, CloseBtn}) do
    local orig = btn.BackgroundColor3
    btn.MouseEnter:Connect(function() tw(btn,{BackgroundColor3=orig:Lerp(Color3.new(1,1,1),0.15)},0.1) end)
    btn.MouseLeave:Connect(function() tw(btn,{BackgroundColor3=orig},0.1) end)
end

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

-- Body
local Body = make("Frame", {
    Size=UDim2.new(1,0,1,-48), Position=UDim2.new(0,0,0,48),
    BackgroundTransparency=1, ZIndex=2,
}, MainFrame)

-- Botoes
local ActionsRow = make("Frame", {
    Size=UDim2.new(1,-24,0,38), Position=UDim2.new(0,12,0,10), BackgroundTransparency=1,
}, Body)
make("UIListLayout", {
    FillDirection=Enum.FillDirection.Horizontal, Padding=UDim.new(0,8),
    SortOrder=Enum.SortOrder.LayoutOrder, VerticalAlignment=Enum.VerticalAlignment.Center,
}, ActionsRow)

local function makeBtn(text, bg, w, order, par)
    local btn = make("TextButton", {
        Text=text, Size=UDim2.new(0,w,1,0), BackgroundColor3=bg, TextColor3=C.Text,
        TextSize=12, Font=Enum.Font.GothamBold, BorderSizePixel=0, LayoutOrder=order, AutoButtonColor=false,
    }, par)
    make("UICorner",{CornerRadius=UDim.new(0,9)},btn)
    btn.MouseEnter:Connect(function() tw(btn,{BackgroundColor3=bg:Lerp(Color3.new(1,1,1),0.12)},0.1) end)
    btn.MouseLeave:Connect(function() tw(btn,{BackgroundColor3=bg},0.1) end)
    return btn
end

local ScanBtn    = makeBtn("[+] Atualizar",   C.Card,   108, 1, ActionsRow)
local HopBestBtn = makeBtn("[>] Ir ao Menor", C.Accent, 148, 2, ActionsRow)
make("UIStroke",{Color=C.Border,Thickness=1},ScanBtn)

-- InfoBar
local InfoBar = make("Frame", {
    Size=UDim2.new(1,-24,0,30), Position=UDim2.new(0,12,0,56),
    BackgroundColor3=C.Card, BorderSizePixel=0,
}, Body)
make("UICorner",{CornerRadius=UDim.new(0,8)},InfoBar)

local StatusDot = make("Frame", {
    Size=UDim2.new(0,8,0,8), Position=UDim2.new(0,10,0.5,-4),
    BackgroundColor3=C.TextDim, BorderSizePixel=0,
}, InfoBar)
make("UICorner",{CornerRadius=UDim.new(0.5,0)},StatusDot)

local InfoText = make("TextLabel", {
    Text="Buscando...", Size=UDim2.new(1,-30,1,0), Position=UDim2.new(0,24,0,0),
    BackgroundTransparency=1, TextSize=11, Font=Enum.Font.Gotham, TextColor3=C.TextDim,
    TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd,
}, InfoBar)

-- Progress bar
local ProgBG = make("Frame", {
    Size=UDim2.new(1,-24,0,2), Position=UDim2.new(0,12,0,90),
    BackgroundColor3=C.Border, BorderSizePixel=0,
}, Body)
make("UICorner",{CornerRadius=UDim.new(0,2)},ProgBG)
local ProgBar = make("Frame", {Size=UDim2.new(0,0,1,0),BackgroundColor3=C.Accent,BorderSizePixel=0},ProgBG)
make("UICorner",{CornerRadius=UDim.new(0,2)},ProgBar)

-- Cabecalho
local HeaderRow = make("Frame", {
    Size=UDim2.new(1,-24,0,22), Position=UDim2.new(0,12,0,97), BackgroundTransparency=1,
}, Body)
local function hdr(t,x,w,al)
    return make("TextLabel",{Text=t,Size=UDim2.new(0,w,1,0),Position=UDim2.new(0,x,0,0),
        BackgroundTransparency=1,TextSize=10,Font=Enum.Font.GothamBold,TextColor3=C.TextDim,
        TextXAlignment=al or Enum.TextXAlignment.Left},HeaderRow)
end
hdr("#",0,22) hdr("PLAYERS",26,90) hdr("FPS",122,42)
hdr("PING",170,48) hdr("JOB ID",222,90) hdr("IR",326,28,Enum.TextXAlignment.Center)

make("Frame",{Size=UDim2.new(1,-24,0,1),Position=UDim2.new(0,12,0,122),BackgroundColor3=C.Border,BorderSizePixel=0},Body)

-- Lista
local ListFrame = make("ScrollingFrame", {
    Name="ServerList", Size=UDim2.new(1,-24,1,-192), Position=UDim2.new(0,12,0,127),
    BackgroundTransparency=1, ScrollBarThickness=4, ScrollBarImageColor3=C.Accent,
    ScrollBarImageTransparency=0.3, BorderSizePixel=0,
    CanvasSize=UDim2.new(0,0,0,0), AutomaticCanvasSize=Enum.AutomaticSize.Y,
    ElasticBehavior=Enum.ElasticBehavior.Never,
}, Body)
make("UIListLayout",{Padding=UDim.new(0,4),SortOrder=Enum.SortOrder.LayoutOrder},ListFrame)

-- StatusBar
local StatusBar = make("Frame", {
    Size=UDim2.new(1,0,0,34), Position=UDim2.new(0,0,1,-34),
    BackgroundColor3=C.Panel, BorderSizePixel=0,
}, Body)
make("UICorner",{CornerRadius=UDim.new(0,14)},StatusBar)
make("Frame",{Size=UDim2.new(1,0,0,14),BackgroundColor3=C.Panel,BorderSizePixel=0},StatusBar)

local StatusText = make("TextLabel", {
    Text="Pronto  |  RCtrl para ocultar",
    Size=UDim2.new(0.62,0,1,0), Position=UDim2.new(0,12,0,0),
    BackgroundTransparency=1, TextSize=10, Font=Enum.Font.Gotham, TextColor3=C.TextDim,
    TextXAlignment=Enum.TextXAlignment.Left, TextTruncate=Enum.TextTruncate.AtEnd,
}, StatusBar)

local CountLabel = make("TextLabel", {
    Text="- servidores", Size=UDim2.new(0,110,1,0), Position=UDim2.new(1,-118,0,0),
    BackgroundTransparency=1, TextSize=10, Font=Enum.Font.GothamBold, TextColor3=C.Accent,
    TextXAlignment=Enum.TextXAlignment.Right,
}, StatusBar)

-- ============================================================
--  RENDERIZACAO DA LISTA
-- ============================================================

local function pCol(p, m)
    if p == 0 then return C.Accent end
    if p == 1 then return C.GreenBr end
    if p <= 3  then return C.Green  end
    if p/math.max(m,1) < 0.5 then return C.Yellow end
    return C.Red
end
local function fCol(f)
    if f>=55 then return C.GreenBr elseif f>=40 then return C.Green
    elseif f>=25 then return C.Yellow else return C.Red end
end
local function rCol(i)
    if i==1 then return C.Gold elseif i==2 then return C.Silver
    elseif i==3 then return C.Bronze else return C.Border end
end
local function rStr(i)
    if i==1 then return "#1" elseif i==2 then return "#2"
    elseif i==3 then return "#3" else return "#"..i end
end

local function renderList(servers)
    for _, ch in ipairs(ListFrame:GetChildren()) do
        if not ch:IsA("UIListLayout") then ch:Destroy() end
    end

    if #servers == 0 then
        make("TextLabel",{
            Text="Nenhum servidor encontrado.
Clique em [+] Atualizar para buscar.",
            Size=UDim2.new(1,0,0,70), BackgroundTransparency=1,
            TextSize=11, Font=Enum.Font.Gotham, TextColor3=C.TextDim,
            TextWrapped=true, TextXAlignment=Enum.TextXAlignment.Center, LayoutOrder=1,
        }, ListFrame)
        return
    end

    for i, sv in ipairs(servers) do
        local pc = pCol(sv.playing, sv.maxPlayers)
        local Card = make("Frame", {
            Name="Card_"..i, Size=UDim2.new(1,0,0,40),
            BackgroundColor3=i<=3 and C.CardHov or C.Card,
            BorderSizePixel=0, LayoutOrder=i,
        }, ListFrame)
        make("UICorner",{CornerRadius=UDim.new(0,9)},Card)

        if i<=3 or sv.playing<=1 then
            local acol = i<=3 and rCol(i) or C.GreenBr
            local bar = make("Frame",{Size=UDim2.new(0,3,1,-10),Position=UDim2.new(0,0,0,5),BackgroundColor3=acol,BorderSizePixel=0},Card)
            make("UICorner",{CornerRadius=UDim.new(0,2)},bar)
        end

        make("TextLabel",{Text=rStr(i),Size=UDim2.new(0,24,1,0),Position=UDim2.new(0,5,0,0),
            BackgroundTransparency=1,TextSize=i<=3 and 13 or 10,Font=Enum.Font.GothamBold,
            TextColor3=i<=3 and rCol(i) or C.TextDim,TextXAlignment=Enum.TextXAlignment.Center},Card)

        make("TextLabel",{Text=sv.playing.."/"..sv.maxPlayers,Size=UDim2.new(0,88,1,0),Position=UDim2.new(0,30,0,0),
            BackgroundTransparency=1,TextSize=13,Font=Enum.Font.GothamBold,TextColor3=pc},Card)

        if sv.playing==0 then
            local b=make("Frame",{Size=UDim2.new(0,44,0,18),Position=UDim2.new(0,78,0.5,-9),BackgroundColor3=C.Accent:Lerp(C.BG,0.5),BorderSizePixel=0},Card)
            make("UICorner",{CornerRadius=UDim.new(0,4)},b)
            make("TextLabel",{Text="VAZIO",Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,TextSize=9,Font=Enum.Font.GothamBold,TextColor3=C.Accent},b)
        end

        local fc=fCol(sv.fps)
        local fb=make("Frame",{Size=UDim2.new(0,40,0,20),Position=UDim2.new(0,122,0.5,-10),BackgroundColor3=fc:Lerp(C.BG,0.7),BorderSizePixel=0},Card)
        make("UICorner",{CornerRadius=UDim.new(0,5)},fb)
        make("TextLabel",{Text=sv.fps.." fps",Size=UDim2.new(1,0,1,0),BackgroundTransparency=1,TextSize=10,Font=Enum.Font.GothamBold,TextColor3=fc},fb)

        local pgc=sv.ping<80 and C.GreenBr or (sv.ping<150 and C.Yellow or C.Red)
        make("TextLabel",{Text=sv.ping.."ms",Size=UDim2.new(0,46,1,0),Position=UDim2.new(0,168,0,0),BackgroundTransparency=1,TextSize=10,Font=Enum.Font.Gotham,TextColor3=pgc},Card)
        make("TextLabel",{Text=sv.jobId:sub(1,8).."...",Size=UDim2.new(0,88,1,0),Position=UDim2.new(0,218,0,0),BackgroundTransparency=1,TextSize=9,Font=Enum.Font.Code,TextColor3=C.TextDim},Card)

        local GoBtn = make("TextButton",{
            Text=">>",Size=UDim2.new(0,28,0,26),Position=UDim2.new(1,-34,0.5,-13),
            BackgroundColor3=C.Accent,TextColor3=Color3.new(1,1,1),TextSize=12,
            Font=Enum.Font.GothamBold,BorderSizePixel=0,AutoButtonColor=false,
        },Card)
        make("UICorner",{CornerRadius=UDim.new(0,7)},GoBtn)
        GoBtn.MouseEnter:Connect(function() tw(GoBtn,{BackgroundColor3=C.AccentHov},0.1) end)
        GoBtn.MouseLeave:Connect(function() tw(GoBtn,{BackgroundColor3=C.Accent},0.1) end)
        Card.MouseEnter:Connect(function() tw(Card,{BackgroundColor3=C.CardHov},0.12) end)
        Card.MouseLeave:Connect(function() tw(Card,{BackgroundColor3=i<=3 and C.CardHov or C.Card},0.12) end)

        local csv = sv
        GoBtn.MouseButton1Click:Connect(function()
            if State.isHopping then return end
            StatusText.Text="Conectando a "..csv.jobId:sub(1,8).."..."
            StatusText.TextColor3=C.Yellow
            GoBtn.Text="..."; GoBtn.Active=false
            hopTo(csv.jobId, function(hok, err)
                GoBtn.Text=">>"; GoBtn.Active=true
                if not hok then StatusText.Text="Erro: "..tostring(err); StatusText.TextColor3=C.Red end
            end)
        end)
    end
end

-- ============================================================
--  SCAN & REFRESH
-- ============================================================

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
        tw(StatusDot,{BackgroundColor3=C.Yellow},0.15)
        InfoText.Text = "Buscando servidores..."
        InfoText.TextColor3 = C.TextDim
    end

    fetchServers(function(servers, ok, errMsg)
        if ok and #servers > 0 then
            tw(StatusDot,{BackgroundColor3=C.GreenBr},0.2)
            InfoText.Text = #servers.." servidores  |  "..os.date("%H:%M:%S")
            InfoText.TextColor3 = C.TextDim
            CountLabel.Text = #servers.." servidores"
            renderList(servers)
            tw(ProgBar,{Size=UDim2.new(1,0,1,0)},0.2)
            task.delay(0.4,function() if ProgBar.Parent then tw(ProgBar,{Size=UDim2.new(0,0,1,0)},0.3) end end)
            if not opts.silent then setStatus("Lista atualizada") end
        else
            if #State.servers > 0 then
                -- Mantém cache: mostra lista antiga sem apagar
                tw(StatusDot,{BackgroundColor3=C.Yellow},0.2)
                InfoText.Text = #State.servers.." servidores (cache)  |  "..os.date("%H:%M:%S")
                InfoText.TextColor3 = C.Yellow
            else
                tw(StatusDot,{BackgroundColor3=C.Red},0.2)
                InfoText.Text = "Falha ao buscar. Clique em [+] Atualizar."
                InfoText.TextColor3 = C.Red
            end
        end
        if opts.onDone then opts.onDone(State.servers, ok) end
    end)
end

ScanBtn.MouseButton1Click:Connect(function()
    if not State.isScanning then doScan() end
end)

HopBestBtn.MouseButton1Click:Connect(function()
    if State.isHopping then return end

    if #State.servers > 0 then
        local best = State.servers[1]
        setStatus(string.format("Pulando... [%d/%d players | %d fps]", best.playing, best.maxPlayers, best.fps), C.GreenBr)
        hopTo(best.jobId, function(hok, err)
            if not hok then setStatus("Erro: " .. tostring(err), C.Red) end
        end)
        return
    end

    HopBestBtn.Text = "Buscando..."
    HopBestBtn.Active = false
    doScan({
        onDone = function(servers, ok)
            HopBestBtn.Text = "[>] Ir ao Menor"
            HopBestBtn.Active = true
            if #servers > 0 then
                local best = servers[1]
                setStatus(string.format("Pulando... [%d/%d | %d fps]", best.playing, best.maxPlayers, best.fps), C.GreenBr)
                hopTo(best.jobId, function(hok, err)
                    if not hok then setStatus("Erro: " .. tostring(err), C.Red) end
                end)
            else
                setStatus("Nenhum servidor encontrado", C.Red)
            end
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

-- Minimizar / Fechar / Toggle
MinBtn.MouseButton1Click:Connect(function()
    State.minimized=not State.minimized
    if State.minimized then Body.Visible=false; tw(MainFrame,{Size=UDim2.new(0,WIN_W,0,48)},0.2); MinBtn.Text="+"
    else Body.Visible=true; tw(MainFrame,{Size=UDim2.new(0,WIN_W,0,WIN_H)},0.25,Enum.EasingStyle.Back); MinBtn.Text="-" end
end)

CloseBtn.MouseButton1Click:Connect(function()
    local cp=MainFrame.Position
    tw(MainFrame,{Size=UDim2.new(0,0,0,0),Position=UDim2.new(cp.X.Scale,cp.X.Offset+WIN_W/2,cp.Y.Scale,cp.Y.Offset+WIN_H/2)},0.2,Enum.EasingStyle.Back,Enum.EasingDirection.In)
    task.delay(0.22,function() pcall(function() ScreenGui:Destroy() end) end)
end)

UserInputService.InputBegan:Connect(function(inp, proc)
    if proc then return end
    if inp.KeyCode==Config.ToggleKey then State.uiVisible=not State.uiVisible; MainFrame.Visible=State.uiVisible end
end)

MainFrame.Size=UDim2.new(0,0,0,0)
MainFrame.Position=UDim2.new(0.5,0,0.5,0)
tw(MainFrame,{Size=UDim2.new(0,WIN_W,0,WIN_H),Position=UDim2.new(0.5,-WIN_W/2,0.5,-WIN_H/2)},0.4,Enum.EasingStyle.Back)

task.delay(0.1, function() doScan() end)
setStatus("Pronto | RCtrl para ocultar")
print("[HopServer] Pronto. RCtrl para ocultar/mostrar.")

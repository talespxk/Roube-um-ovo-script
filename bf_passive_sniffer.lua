--[[
    ================================================================================
    ROUBE UM OVO - MEGA SNIFFER & DUMPER FORENSE DEFINITIVO (v4.0 SUPER-FORENSIC)
    PlaceId: 107778070777162 | Jogo: Roube um Ovo (Steal an Egg)
    ================================================================================
    MELHORIAS & RECURSOS FORENSES v4.0:
    1. AUTO-DEEP SPY ATIVADO AUTOMATICAMENTE:
       - Hook seguro em __namecall, FireServer e InvokeServer desde o inicio.
       - INTERCEPTA OS VALORES DE RETORNO DO InvokeServer (ex: AskFieldEggCarry)!
       - Captura script chamador (caller), argumentos completos e resposta do servidor.
    2. FILTRO INTELIGENTE ANTI-FLOOD (SEM PERDA DE BUFFER):
       - Remotes de alta frequencia (CoinsGathered, AwayEarnings, Ping) sao agregados
         em contadores e nunca inundam o buffer de logs!
       - 100% do espaco preservado para remotes criticos de roubo, esteira e combate.
    3. MONITOR FORENSE DE AUTO-ESTEIRA & TREADMILL:
       - Rastreia toques fisicos (.Touched), teleporte e velocidade nas esteiras do mapa.
       - Intercepta chamadas de exploit: hook em firetouchinterest e fireproximityprompt!
       - Rastreia alteracoes em Humanoid.MoveDirection e corrida automatica.
    4. EXTRATOR FORENSE DE ESP & RENDA DOS OVOS DO CONCORRENTE:
       - Escaneia BillboardGuis, SurfaceGuis e Drawings gerados pelo script concorrente.
       - Captura textos de ESP contendo os nomes reais e valores/renda por segundo ($/s)!
       - Inspeciona getgc() e modulos para decodificar tabelas e formulas de ganho.
    5. GRAVADOR DE VOO & WAYPOINTS MILISSEGUNDO A MILISSEGUNDO:
       - Registra trajetoria completa de CFrame, altitude Y, velocidade e estado (Ragdoll).
       - Registra o momento exato do acoplamento do ovo e da entrega na base.
    6. EXPORTACAO MODULAR EM 5 ARQUIVOS SEPARADOS (ZERO TRUNCAMENTO):
       - MEGA_SNIFFER_RELATORIO_COMPLETO.txt (Relatorio Mestre)
       - MEGA_SNIFFER_REMOTES.txt (Apenas Remotes Enviados e Retornos, limpo para Discord)
       - MEGA_SNIFFER_ESTEIRA.txt (Eventos de Esteira, Treadmill e Touched)
       - MEGA_SNIFFER_ESP_DADOS.txt (ESP do concorrente, textos, interface e tabelas de renda)
       - MEGA_SNIFFER_VOO.txt (Waypoints e telemetria de voo)
       - Botoes individuais de copia na interface para colar direto no chat!
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
    Lighting = safeService("Lighting"),
    HttpService = safeService("HttpService"),
    RunService = safeService("RunService"),
    LogService = safeService("LogService"),
    ProximityPromptService = safeService("ProximityPromptService"),
    UserInputService = safeService("UserInputService")
}

local LocalPlayer = Services.Players.LocalPlayer
local startTime = os.clock()

--================================================================--
-- BUFFERS DEDICADOS & ESTRUTURAS DE ARMAZENAMENTO
--================================================================--
local outgoingRemotes = {}     -- Apenas FireServer e InvokeServer (com retornos!)
local incomingRemotes = {}     -- Remotes recebidos (filtrados contra spam)
local treadmillEvents = {}     -- Eventos de esteira / treadmill / toques
local competitorEspLogs = {}   -- Textos de ESP, BillboardGuis e formulas do concorrente
local competitorGuiDump = {}   -- Elementos da interface do concorrente
local flightWaypoints = {}     -- Trajetoria de voo / coordenadas / CFrame
local structuralDumpLines = {} -- Dump estrutural completo do jogo
local cycleReports = {}        -- Relatorios de ciclos completos de roubo
local liveLogs = {}            -- Log de status ao vivo

local spamCounters = {}        -- Contadores de remotes de spam (CoinsGathered, etc.)
local lastSpamSummaryTime = os.clock()

-- Lista de Remotes que geram flood constante
local SPAM_FILTER = {
    ["CoinsGathered"] = true,
    ["PenRoster/CoinsGathered"] = true,
    ["RE/PenRoster/CoinsGathered"] = true,
    ["AwayEarnings"] = true,
    ["Ping"] = true,
    ["Pong"] = true,
    ["Heartbeat"] = true,
    ["KeepAlive"] = true
}

local function safeJson(val)
    local ok, res = pcall(function()
        return Services.HttpService:JSONEncode(val)
    end)
    return ok and res or tostring(val)
end

local function getHierarchyPath(inst)
    if not inst then return "nil" end
    local ok, path = pcall(function()
        local parts = {}
        local cur = inst
        while cur and cur ~= game do
            table.insert(parts, 1, cur.Name)
            cur = cur.Parent
        end
        return table.concat(parts, ".")
    end)
    return ok and path or tostring(inst)
end

local function truncateStr(str, maxLen)
    if not str then return "" end
    str = tostring(str)
    if #str > maxLen then
        return str:sub(1, maxLen) .. "... (" .. #str .. " bytes)"
    end
    return str
end

local function logLive(cat, msg, details)
    local elapsed = os.clock() - startTime
    local line = string.format("[%06.3fs] [%-12s] %s%s", elapsed, cat, msg, details and (" | " .. details) or "")
    table.insert(liveLogs, line)
    if #liveLogs > 500 then
        table.remove(liveLogs, 1)
    end
end

logLive("SISTEMA", "Mega Sniffer & Dumper v4.0 SUPER-FORENSIC Iniciado!")

--================================================================--
-- 1. DEEP REMOTE SPY AUTOMATICO COM CAPTURA DE VALORES DE RETORNO
--================================================================--
local deepSpyActive = false
local deepSpyHookMethod = "Nenhum"

local function recordOutgoingRemote(method, targetInstance, args, callerScript, returnValues)
    local elapsed = os.clock() - startTime
    local targetName = targetInstance and targetInstance.Name or "Desconhecido"
    local targetPath = getHierarchyPath(targetInstance)

    -- Verifica se e remote de spam
    local isSpam = SPAM_FILTER[targetName] or SPAM_FILTER[targetPath]
    if not isSpam then
        for pattern, _ in pairs(SPAM_FILTER) do
            if targetPath:find(pattern, 1, true) then
                isSpam = true
                break
            end
        end
    end

    if isSpam then
        spamCounters[targetName] = (spamCounters[targetName] or 0) + 1
        return
    end

    local serializedArgs = {}
    if type(args) == "table" then
        for i = 1, math.min(#args, 8) do
            local a = args[i]
            if typeof(a) == "Instance" then
                table.insert(serializedArgs, getHierarchyPath(a))
            elseif type(a) == "table" then
                table.insert(serializedArgs, truncateStr(safeJson(a), 200))
            else
                table.insert(serializedArgs, tostring(a))
            end
        end
    end
    local argsStr = #serializedArgs > 0 and table.concat(serializedArgs, ", ") or "Nenhum"

    local retStr = ""
    if returnValues ~= nil then
        local serializedRet = {}
        if type(returnValues) == "table" then
            for i = 1, math.min(#returnValues, 6) do
                local r = returnValues[i]
                if typeof(r) == "Instance" then
                    table.insert(serializedRet, getHierarchyPath(r))
                elseif type(r) == "table" then
                    table.insert(serializedRet, truncateStr(safeJson(r), 200))
                else
                    table.insert(serializedRet, tostring(r))
                end
            end
        else
            table.insert(serializedRet, tostring(returnValues))
        end
        retStr = " => RETORNO: (" .. table.concat(serializedRet, ", ") .. ")"
    end

    local entry = string.format("[%06.3fs] [%s] %s | Caller: %s | Args: (%s)%s | Caminho: %s",
        elapsed, method, targetName, callerScript or "Desconhecido", argsStr, retStr, targetPath)

    table.insert(outgoingRemotes, entry)
    if #outgoingRemotes > 1500 then
        table.remove(outgoingRemotes, 1)
    end

    logLive("REMOTE_OUT", string.format("[%s] %s%s", method, targetName, retStr), "Args: " .. argsStr)
end

local function recordIncomingRemote(remoteInstance, args)
    local elapsed = os.clock() - startTime
    local rName = remoteInstance and remoteInstance.Name or "Desconhecido"
    local rPath = getHierarchyPath(remoteInstance)

    local isSpam = SPAM_FILTER[rName] or SPAM_FILTER[rPath]
    if not isSpam then
        for pattern, _ in pairs(SPAM_FILTER) do
            if rPath:find(pattern, 1, true) then
                isSpam = true
                break
            end
        end
    end

    if isSpam then
        spamCounters[rName] = (spamCounters[rName] or 0) + 1
        return
    end

    local serializedArgs = {}
    if type(args) == "table" then
        for i = 1, math.min(#args, 6) do
            local a = args[i]
            if typeof(a) == "Instance" then
                table.insert(serializedArgs, getHierarchyPath(a))
            elseif type(a) == "table" then
                table.insert(serializedArgs, truncateStr(safeJson(a), 160))
            else
                table.insert(serializedArgs, tostring(a))
            end
        end
    end
    local argsStr = #serializedArgs > 0 and table.concat(serializedArgs, ", ") or "Nenhum"

    local entry = string.format("[%06.3fs] [RECEBIDO] %s | Caminho: %s | Args: (%s)",
        elapsed, rName, rPath, argsStr)

    table.insert(incomingRemotes, entry)
    if #incomingRemotes > 1000 then
        table.remove(incomingRemotes, 1)
    end
end

-- Ativacao do Hook em __namecall (Deep Spy Automatico)
local function initDeepRemoteSpy()
    local ok, err = pcall(function()
        if not hookmetamethod or not getnamecallmethod then
            error("Executor nao suporta hookmetamethod ou getnamecallmethod")
        end
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            if self and (method == "FireServer" or method == "InvokeServer") then
                local args = {...}
                local caller = "Desconhecido"
                pcall(function()
                    local cs = getcallingscript and getcallingscript()
                    if cs then caller = cs:GetFullName() end
                end)

                if method == "InvokeServer" then
                    local ret = { oldNamecall(self, ...) }
                    pcall(recordOutgoingRemote, method, self, args, caller, ret)
                    return table.unpack(ret)
                else
                    pcall(recordOutgoingRemote, method, self, args, caller, nil)
                    return oldNamecall(self, ...)
                end
            end
            return oldNamecall(self, ...)
        end)
    end)

    if ok then
        deepSpyActive = true
        deepSpyHookMethod = "hookmetamethod(__namecall)"
        logLive("SISTEMA", "Deep Remote Spy ATIVADO com sucesso via " .. deepSpyHookMethod)
    else
        logLive("SISTEMA", "Falha ao ativar hookmetamethod: " .. tostring(err))
        -- Tentativa via hookfunction nos metodos do RemoteEvent/RemoteFunction
        pcall(function()
            if hookfunction then
                local dummyEvent = Instance.new("RemoteEvent")
                local oldFire = hookfunction(dummyEvent.FireServer, function(self, ...)
                    local args = {...}
                    local caller = "Desconhecido"
                    pcall(function()
                        local cs = getcallingscript and getcallingscript()
                        if cs then caller = cs:GetFullName() end
                    end)
                    pcall(recordOutgoingRemote, "FireServer", self, args, caller, nil)
                    return oldFire(self, ...)
                end)
                dummyEvent:Destroy()

                local dummyFunc = Instance.new("RemoteFunction")
                local oldInvoke = hookfunction(dummyFunc.InvokeServer, function(self, ...)
                    local args = {...}
                    local caller = "Desconhecido"
                    pcall(function()
                        local cs = getcallingscript and getcallingscript()
                        if cs then caller = cs:GetFullName() end
                    end)
                    local ret = { oldInvoke(self, ...) }
                    pcall(recordOutgoingRemote, "InvokeServer", self, args, caller, ret)
                    return table.unpack(ret)
                end)
                dummyFunc:Destroy()

                deepSpyActive = true
                deepSpyHookMethod = "hookfunction(FireServer/InvokeServer)"
                logLive("SISTEMA", "Deep Remote Spy ATIVADO via " .. deepSpyHookMethod)
            end
        end)
    end
end

initDeepRemoteSpy()

-- Monitoramento Passivo de Todos os RemoteEvents do Jogo (OnClientEvent)
local hookedCount = 0
for _, desc in ipairs(game:GetDescendants()) do
    if desc:IsA("RemoteEvent") then
        hookedCount = hookedCount + 1
        pcall(function()
            desc.OnClientEvent:Connect(function(...)
                local args = {...}
                recordIncomingRemote(desc, args)
            end)
        end)
    end
end
logLive("SISTEMA", string.format("Escuta passiva ativada em %d RemoteEvents do jogo!", hookedCount))

--================================================================--
-- 2. INTERCEPTADOR DE FUNCOES DO EXPLOIT (FIRETOUCHINTEREST, PROMPTS)
--================================================================--
local function recordTreadmillEvent(category, message, details)
    local elapsed = os.clock() - startTime
    local line = string.format("[%06.3fs] [%-14s] %s%s", elapsed, category, message, details and (" | " .. details) or "")
    table.insert(treadmillEvents, line)
    if #treadmillEvents > 1000 then
        table.remove(treadmillEvents, 1)
    end
    logLive("ESTEIRA", message, details)
end

-- Hook seguro em firetouchinterest
pcall(function()
    if hookfunction and firetouchinterest then
        local oldFti
        oldFti = hookfunction(firetouchinterest, function(part1, part2, toggle)
            local p1Name = part1 and getHierarchyPath(part1) or "nil"
            local p2Name = part2 and getHierarchyPath(part2) or "nil"
            local isTreadmill = p1Name:lower():find("treadmill") or p1Name:lower():find("esteira") or
                                p2Name:lower():find("treadmill") or p2Name:lower():find("esteira") or
                                p1Name:lower():find("conveyor")  or p2Name:lower():find("conveyor")
            local tag = isTreadmill and "FTI_ESTEIRA" or "FIRETOUCH"
            recordTreadmillEvent(tag, string.format("P1: %s <-> P2: %s (Toggle: %s)", p1Name, p2Name, tostring(toggle)))
            return oldFti(part1, part2, toggle)
        end)
        logLive("SISTEMA", "Hook em firetouchinterest instalado com sucesso!")
    end
end)

-- Hook seguro em fireproximityprompt
pcall(function()
    if hookfunction and fireproximityprompt then
        local oldFpp
        oldFpp = hookfunction(fireproximityprompt, function(prompt, amount, skip)
            local pPath = prompt and getHierarchyPath(prompt) or "nil"
            local act = prompt and prompt.ActionText or ""
            local obj = prompt and prompt.ObjectText or ""
            local isTreadmill = pPath:lower():find("treadmill") or pPath:lower():find("esteira")
            local tag = isTreadmill and "FPP_ESTEIRA" or "PROMPT_HOOK"
            recordTreadmillEvent(tag, string.format("Prompt: '%s' | Acao: '%s' | Caminho: %s", obj, act, pPath))
            return oldFpp(prompt, amount, skip)
        end)
        logLive("SISTEMA", "Hook em fireproximityprompt instalado com sucesso!")
    end
end)

-- Monitoramento Fisico de Esteiras/Treadmills no Workspace (.Touched)
local monitoredTreadmillParts = {}
local function scanAndHookTreadmillParts()
    for _, desc in ipairs(Services.Workspace:GetDescendants()) do
        if desc:IsA("BasePart") and not monitoredTreadmillParts[desc] then
            local low = desc.Name:lower()
            local parentLow = desc.Parent and desc.Parent.Name:lower() or ""
            if low:find("treadmill") or low:find("esteira") or low:find("conveyor") or low:find("belt") or
               parentLow:find("treadmill") or parentLow:find("esteira") or parentLow:find("conveyor") then
                monitoredTreadmillParts[desc] = true
                desc.Touched:Connect(function(hit)
                    if LocalPlayer.Character and hit:IsDescendantOf(LocalPlayer.Character) then
                        recordTreadmillEvent("TOQUE_FISICO", "Personagem tocou na esteira: " .. getHierarchyPath(desc),
                            string.format("Parte tocada: %s | Pos: (%.1f, %.1f, %.1f)", hit.Name, desc.Position.X, desc.Position.Y, desc.Position.Z))
                    end
                end)
                desc.TouchEnded:Connect(function(hit)
                    if LocalPlayer.Character and hit:IsDescendantOf(LocalPlayer.Character) then
                        recordTreadmillEvent("SAIU_ESTEIRA", "Personagem saiu da esteira: " .. getHierarchyPath(desc))
                    end
                end)
            end
        end
    end
end

task.spawn(function()
    scanAndHookTreadmillParts()
    Services.Workspace.DescendantAdded:Connect(function(desc)
        if desc:IsA("BasePart") then
            local low = desc.Name:lower()
            if low:find("treadmill") or low:find("esteira") or low:find("conveyor") then
                scanAndHookTreadmillParts()
            end
        end
    end)
end)

--================================================================--
-- 3. EXTRATOR FORENSE DE ESP, RENDA DOS OVOS & GUI DO CONCORRENTE
--================================================================--
local knownCompetitorGuiObjects = {}

local function recordCompetitorData(category, message, details)
    local elapsed = os.clock() - startTime
    local line = string.format("[%06.3fs] [%-14s] %s%s", elapsed, category, message, details and (" | " .. details) or "")
    table.insert(competitorEspLogs, line)
    if #competitorEspLogs > 1000 then
        table.remove(competitorEspLogs, 1)
    end
    logLive("ESP_DADO", message, details)
end

-- Varredura periodica de BillboardGuis/SurfaceGuis criados por scripts concorrentes
task.spawn(function()
    while true do
        task.wait(1.5)
        pcall(function()
            -- 3.1 Busca por BillboardGuis / ESP nos Ovos e Plots
            for _, gui in ipairs(Services.Workspace:GetDescendants()) do
                if (gui:IsA("BillboardGui") or gui:IsA("SurfaceGui") or gui:IsA("Highlight")) and not knownCompetitorGuiObjects[gui] then
                    local isOurGui = gui.Name:find("BF_") or gui.Name:find("Antigravity")
                    if not isOurGui then
                        knownCompetitorGuiObjects[gui] = true
                        local texts = {}
                        for _, child in ipairs(gui:GetDescendants()) do
                            if child:IsA("TextLabel") or child:IsA("TextButton") then
                                local t = child.Text
                                if #t > 0 then
                                    table.insert(texts, string.format("'%s'", t))
                                end
                            end
                        end
                        local target = gui.Adornee and getHierarchyPath(gui.Adornee) or (gui.Parent and getHierarchyPath(gui.Parent) or "N/D")
                        if #texts > 0 then
                            recordCompetitorData("ESP_BILLBOARD", string.format("Alvo: %s | Textos: [%s]", target, table.concat(texts, " | ")),
                                "Gui: " .. gui.Name .. " [" .. gui.ClassName .. "]")
                        end
                    end
                end
            end

            -- 3.2 Busca por Telas/Janelas do Concorrente (CoreGui, PlayerGui, gethui)
            local guiContainers = { LocalPlayer:FindFirstChild("PlayerGui") }
            pcall(function()
                if gethui then table.insert(guiContainers, gethui()) end
                table.insert(guiContainers, game:GetService("CoreGui"))
            end)

            for _, container in ipairs(guiContainers) do
                if container then
                    for _, screen in ipairs(container:GetChildren()) do
                        if (screen:IsA("ScreenGui") or screen:IsA("Folder")) and not knownCompetitorGuiObjects[screen] then
                            if screen.Name ~= "BF_Mega_Sniffer_GUI" and screen.Name ~= "Freecam" and screen.Name ~= "Chat" then
                                knownCompetitorGuiObjects[screen] = true
                                local elements = {}
                                for _, d in ipairs(screen:GetDescendants()) do
                                    if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
                                        local txt = d.Text
                                        if #txt > 0 and #txt < 60 then
                                            table.insert(elements, string.format("%s:'%s'", d.Name, txt))
                                        end
                                    end
                                end
                                if #elements > 0 then
                                    table.insert(competitorGuiDump, string.format(">>> GUI Concorrente Detectada: %s [%s] em %s", screen.Name, screen.ClassName, container.Name))
                                    for _, el in ipairs(elements) do
                                        table.insert(competitorGuiDump, "    - " .. el)
                                    end
                                    recordCompetitorData("GUI_CONCORRENTE", string.format("GUI '%s' detectada com %d textos!", screen.Name, #elements), "Local: " .. container.Name)
                                end
                            end
                        end
                    end
                end
            end
        end)
    end
end)

-- Varredura de Memoria / GC (getgc) procurando formulas de renda e valores de ovos
task.spawn(function()
    task.wait(2.0)
    pcall(function()
        if getgc then
            local tablesFound = 0
            for _, obj in ipairs(getgc(true)) do
                if type(obj) == "table" then
                    local hasIncome = rawget(obj, "Income") or rawget(obj, "MoneyPerSecond") or rawget(obj, "CashPerSecond") or rawget(obj, "EggValues") or rawget(obj, "DropTable")
                    if hasIncome and tablesFound < 15 then
                        tablesFound = tablesFound + 1
                        local sample = {}
                        local count = 0
                        for k, v in pairs(obj) do
                            count = count + 1
                            if count <= 5 then
                                table.insert(sample, tostring(k) .. "=" .. truncateStr(tostring(v), 40))
                            end
                        end
                        recordCompetitorData("GC_TABELA_RENDA", string.format("Tabela GC com dados de renda encontrada (#chaves=%d)", count), table.concat(sample, ", "))
                    end
                end
            end
            if tablesFound > 0 then
                logLive("SISTEMA", string.format("Varredura de GC encontrou %d tabelas com dados de renda!", tablesFound))
            end
        end
    end)
end)

--================================================================--
-- 4. GRAVADOR DE VOO & WAYPOINTS DA TELEMETRIA DO PERSONAGEM
--================================================================--
local lastWaypointPos = nil
local lastWaypointTime = 0
local stealCycleState = "IDLE"
local currentCycleEgg = "Nenhum"
local cycleStartTime = 0

local function recordFlightWaypoint(char, hrp, hum, forcedReason)
    local curPos = hrp.Position
    local vel = hrp.AssemblyLinearVelocity
    local stateName = hum:GetState().Name
    local now = os.clock()
    local elapsed = now - startTime

    -- Verifica ferramentas equipadas ou ovos acoplados
    local equippedTools = {}
    local attachedItems = {}
    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("Tool") then
            table.insert(equippedTools, child.Name)
        elseif not child:IsA("Accessory") and not child:IsA("Shirt") and not child:IsA("Pants") and
               child.Name ~= "HumanoidRootPart" and child.Name ~= "Head" and not child.Name:find("Arm") and not child.Name:find("Leg") and not child.Name:find("Torso") then
            table.insert(attachedItems, child.Name .. "[" .. child.ClassName .. "]")
        end
    end

    -- Distancia da galinha, slot e base mais proximos
    local nearbyContext = "Livre"
    local eggSlots = Services.Workspace:FindFirstChild("AreaEggSlotsClient")
    if eggSlots then
        for _, slot in ipairs(eggSlots:GetChildren()) do
            local d = (slot:GetPivot().Position - curPos).Magnitude
            if d < 20 then
                nearbyContext = string.format("Slot: %s (%.1f studs)", slot.Name, d)
                currentCycleEgg = slot.Name
                break
            end
        end
    end

    local line = string.format("[%06.3fs] Pos:(%6.1f, %5.1f, %6.1f) | Y:%5.1f | Vel:%4.1f | Estado:%-16s | Ferramentas:[%s] | Acoplados:[%s] | Contexto: %s%s",
        elapsed, curPos.X, curPos.Y, curPos.Z, curPos.Y, vel.Magnitude, stateName,
        table.concat(equippedTools, ","), table.concat(attachedItems, ","),
        nearbyContext, forcedReason and (" | MOTIVO: " .. forcedReason) or "")

    table.insert(flightWaypoints, line)
    if #flightWaypoints > 1500 then
        table.remove(flightWaypoints, 1)
    end
end

local function setupCharacterFlightTracker(char)
    if not char then return end
    local hrp = char:WaitForChild("HumanoidRootPart", 5)
    local hum = char:WaitForChild("Humanoid", 5)
    if not hrp or not hum then return end

    lastWaypointPos = hrp.Position
    lastWaypointTime = os.clock()
    recordFlightWaypoint(char, hrp, hum, "INICIO_TRACKER")

    -- Monitoramento de Mudanca de CFrame
    hrp:GetPropertyChangedSignal("CFrame"):Connect(function()
        local curPos = hrp.Position
        local delta = (curPos - lastWaypointPos).Magnitude
        local now = os.clock()

        -- Registra se pulou mais de 3 studs ou a cada 0.2s em movimento
        if delta > 3.0 or (delta > 0.5 and (now - lastWaypointTime) > 0.2) then
            recordFlightWaypoint(char, hrp, hum, delta > 8.0 and string.format("SALTO_%.1f_STUDS", delta) or nil)
            lastWaypointPos = curPos
            lastWaypointTime = now
        end
    end)

    -- Monitoramento de Mudanca de Estado do Humanoid (Ragdoll, Hit)
    hum.StateChanged:Connect(function(oldState, newState)
        local vel = hrp.AssemblyLinearVelocity.Magnitude
        local now = os.clock()
        local line = string.format("[%06.3fs] [ESTADO_HUMANOID] %s -> %s | Vel: %.1f | Y: %.1f",
            now - startTime, oldState.Name, newState.Name, vel, hrp.Position.Y)
        table.insert(treadmillEvents, line)
        recordFlightWaypoint(char, hrp, hum, "ESTADO: " .. oldState.Name .. "->" .. newState.Name)

        if newState == Enum.HumanoidStateType.Ragdoll or (newState == Enum.HumanoidStateType.PlatformStanding and vel > 15) then
            logLive("FASE_ROUBO", "[HIT/RAGDOLL DETECTADO!]", string.format("Velocidade do golpe: %.1f studs/s", vel))
        end
    end)

    -- Monitoramento de MoveDirection (Esteira / Caminhada automatica)
    hum:GetPropertyChangedSignal("MoveDirection"):Connect(function()
        local md = hum.MoveDirection
        if md.Magnitude > 0.1 then
            local line = string.format("[%06.3fs] [MOVE_DIRECTION] Dir: (%.2f, %.2f, %.2f) | Mag: %.2f | WalkSpeed: %.1f",
                os.clock() - startTime, md.X, md.Y, md.Z, md.Magnitude, hum.WalkSpeed)
            table.insert(treadmillEvents, line)
        end
    end)

    -- Monitoramento de Ovos Acoplados ao Personagem (ChildAdded)
    char.ChildAdded:Connect(function(child)
        local low = child.Name:lower()
        if not low:find("animate") and not child:IsA("Accessory") and not child:IsA("Shirt") and not child:IsA("Pants") then
            local now = os.clock()
            local line = string.format("[%06.3fs] [ITEM_ACOPLADO] Objeto entrou no personagem: %s [%s]", now - startTime, child.Name, child.ClassName)
            table.insert(treadmillEvents, line)
            logLive("ITEM_PEGO", "Ovo/Item Acoplado: " .. child.Name, "Pos HRP: " .. tostring(hrp.Position))
            recordFlightWaypoint(char, hrp, hum, "ITEM_ACOPLADO: " .. child.Name)
        end
    end)

    char.ChildRemoved:Connect(function(child)
        local low = child.Name:lower()
        if not low:find("animate") and not child:IsA("Accessory") and not child:IsA("Shirt") and not child:IsA("Pants") then
            local now = os.clock()
            local line = string.format("[%06.3fs] [ITEM_REMOVIDO] Objeto saiu do personagem: %s [%s]", now - startTime, child.Name, child.ClassName)
            table.insert(treadmillEvents, line)
            logLive("ITEM_SOLTO", "Ovo/Item Depositado/Removido: " .. child.Name, "Pos HRP: " .. tostring(hrp.Position))
            recordFlightWaypoint(char, hrp, hum, "ITEM_REMOVIDO: " .. child.Name)
        end
    end)
end

if LocalPlayer.Character then
    task.spawn(setupCharacterFlightTracker, LocalPlayer.Character)
end
LocalPlayer.CharacterAdded:Connect(setupCharacterFlightTracker)

--================================================================--
-- 5. MONITORAMENTO DE PROXIMITY PROMPTS
--================================================================--
Services.ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt, player)
    if player == LocalPlayer then
        local pPos = prompt.Parent and prompt.Parent:GetPivot().Position or Vector3.zero
        local entry = string.format("[%06.3fs] [PROMPT_SEGURADO] Acao: '%s' | Obj: '%s' | Pai: %s | Pos: (%.1f, %.1f, %.1f) | Hold: %.2fs",
            os.clock() - startTime, prompt.ActionText, prompt.ObjectText, prompt.Parent and prompt.Parent.Name or "N/D", pPos.X, pPos.Y, pPos.Z, prompt.HoldDuration)
        table.insert(treadmillEvents, entry)
        logLive("PROMPT_HOLD", prompt.ActionText .. " - " .. prompt.ObjectText)
    end
end)

Services.ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
    if player == LocalPlayer then
        local pPos = prompt.Parent and prompt.Parent:GetPivot().Position or Vector3.zero
        local entry = string.format("[%06.3fs] [PROMPT_TRIGGERED] DISPARADO! Acao: '%s' | Obj: '%s' | Pai: %s | Pos: (%.1f, %.1f, %.1f) | MaxDist: %.1f",
            os.clock() - startTime, prompt.ActionText, prompt.ObjectText, prompt.Parent and prompt.Parent.Name or "N/D", pPos.X, pPos.Y, pPos.Z, prompt.MaxActivationDistance)
        table.insert(treadmillEvents, entry)
        logLive("PROMPT_DONE", prompt.ActionText .. " - " .. prompt.ObjectText)
    end
end)

--================================================================--
-- 6. DUMP ESTRUTURAL COMPLETO DO JOGO (SECAO 1 A 7)
--================================================================--
local isDumping = false
local dumpFinished = false

local function runFullStructuralDump()
    if isDumping then return end
    isDumping = true
    structuralDumpLines = {}

    local function addLine(str)
        table.insert(structuralDumpLines, str or "")
    end

    addLine("================================================================================")
    addLine("ROUBE UM OVO - DUMP ESTRUTURAL COMPLETO (v4.0 FORENSE)")
    addLine("Data/Hora: " .. os.date("%Y-%m-%d %H:%M:%S") .. " | Sessao: " .. string.format("%.2fs", os.clock() - startTime))
    addLine("PlaceId: " .. tostring(game.PlaceId) .. " | JobId: " .. tostring(game.JobId))
    addLine("Jogador: " .. (LocalPlayer and LocalPlayer.Name or "N/D") .. " (" .. (LocalPlayer and tostring(LocalPlayer.UserId) or "N/D") .. ")")
    addLine("================================================================================\n")

    -- 6.1 CATALOGO DE REMOTES
    addLine("--------------------------------------------------------------------------------")
    addLine("[SECAO 1] TODOS OS REMOTES DO JOGO (COMUNICACAO CLIENTE <-> SERVIDOR)")
    addLine("--------------------------------------------------------------------------------")
    local remotes = {}
    for _, inst in ipairs(game:GetDescendants()) do
        if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") or inst:IsA("BindableEvent") or inst:IsA("BindableFunction") then
            table.insert(remotes, string.format("  [%s] %s", inst.ClassName, getHierarchyPath(inst)))
        end
    end
    addLine(string.format("Total de Remotes catalogados no jogo: %d", #remotes))
    for _, r in ipairs(remotes) do addLine(r) end
    addLine("\n")

    -- 6.2 ASSETS, PETS E ILHAS
    addLine("--------------------------------------------------------------------------------")
    addLine("[SECAO 2] REPLICATEDSTORAGE: ASSETS, PETS, ILHAS E GUARDAS")
    addLine("--------------------------------------------------------------------------------")
    local dataFolder = Services.ReplicatedStorage:FindFirstChild("Data")
    local assetsFolder = dataFolder and dataFolder:FindFirstChild("Assets")
    local directoryMod = assetsFolder and assetsFolder:FindFirstChild("Directory")
    if directoryMod and directoryMod:IsA("ModuleScript") then
        local ok, dirData = pcall(function() return require(directoryMod) end)
        if ok and type(dirData) == "table" then
            local count = 0
            for k, _ in pairs(dirData) do count = count + 1 end
            addLine(string.format(">>> Modulo Data.Assets.Directory! Total de Pets cadastrados: %d\n", count))
            for petKey, petInfo in pairs(dirData) do
                if type(petInfo) == "table" then
                    local dName = petInfo.DisplayName or petInfo.Name or petKey
                    local rarity = petInfo.Rarity or "COMMON"
                    local income = petInfo.Income or petInfo.MoneyPerSecond or petInfo.CashPerSecond or petInfo.Value or "N/D"
                    local weight = petInfo.Weight or petInfo.Chance or "N/D"
                    local mesh = petInfo.MeshId or petInfo.Model or "N/D"
                    addLine(string.format("  - Chave: %-26s | Display: %-24s | Raridade: %-11s | Renda: %-10s | Peso: %-6s | Mesh: %s",
                        tostring(petKey), tostring(dName), tostring(rarity), tostring(income), tostring(weight), tostring(mesh)))
                end
            end
        end
    end

    -- 6.3 SLOTS VIVOS
    addLine("--------------------------------------------------------------------------------")
    addLine("[SECAO 3] SLOTS VIVOS DE OVOS (WORKSPACE.AREAEGGSLOTSCLIENT)")
    addLine("--------------------------------------------------------------------------------")
    local areaSlots = Services.Workspace:FindFirstChild("AreaEggSlotsClient")
    if areaSlots then
        local slots = areaSlots:GetChildren()
        addLine(string.format("Total de Slots Vivos no momento: %d", #slots))
        for i, slot in ipairs(slots) do
            local posStr = "N/D"
            pcall(function()
                local p = slot:GetPivot().Position
                posStr = string.format("(%.1f, %.1f, %.1f)", p.X, p.Y, p.Z)
            end)
            local childrenDesc = {}
            for _, c in ipairs(slot:GetChildren()) do
                local mId = (c:IsA("MeshPart") and c.MeshId) or (c:FindFirstChildWhichIsA("SpecialMesh") and c:FindFirstChildWhichIsA("SpecialMesh").MeshId) or ""
                local num = mId:match("(%d+)")
                table.insert(childrenDesc, string.format("%s[%s]%s", c.Name, c.ClassName, num and (":" .. num) or ""))
            end
            local attrs = {}
            for k, v in pairs(slot:GetAttributes()) do table.insert(attrs, k .. "=" .. tostring(v)) end
            addLine(string.format("  #%02d Slot: %-32s | Pos: %s | Filhos: %s | Attrs: %s",
                i, slot.Name, posStr, #childrenDesc > 0 and table.concat(childrenDesc, ", ") or "Nenhum",
                #attrs > 0 and table.concat(attrs, ", ") or "Nenhum"))
        end
    end
    addLine("\n")

    -- 6.4 PLOTS E BASES
    addLine("--------------------------------------------------------------------------------")
    addLine("[SECAO 4] BASES DE JOGADORES (WORKSPACE.PLOTS)")
    addLine("--------------------------------------------------------------------------------")
    local plotsFolder = Services.Workspace:FindFirstChild("Plots")
    if plotsFolder then
        local plots = plotsFolder:GetChildren()
        addLine(string.format("Total de Plots no servidor: %d", #plots))
        for _, plot in ipairs(plots) do
            local owner = "N/D"
            pcall(function()
                local o = plot:FindFirstChild("Owner") or plot:FindFirstChild("Player") or plot:FindFirstChild("OwnerName")
                if o then owner = tostring(o.Value) end
            end)
            local pPos = "N/D"
            pcall(function()
                local p = plot:GetPivot().Position
                pPos = string.format("(%.1f, %.1f, %.1f)", p.X, p.Y, p.Z)
            end)
            local isMyPlot = (LocalPlayer and (owner == LocalPlayer.Name or plot.Name == LocalPlayer.Name)) and " [SUA BASE]" or ""
            addLine(string.format("  - Plot: %-15s | Dono: %-22s%s | Pos: %s", plot.Name, owner, isMyPlot, pPos))
        end
    end
    addLine("\n")

    dumpFinished = true
    isDumping = false
    logLive("DUMP", "Dump estrutural finalizado!", string.format("Total de linhas: %d", #structuralDumpLines))
end

task.spawn(runFullStructuralDump)

--================================================================--
-- 7. GERADORES DE RELATORIOS ESPECIALIZADOS (ZERO TRUNCAMENTO)
--================================================================--

-- 7.1 Relatorio de Remotes (Apenas Remotes Enviados e Retornos!)
local function generateRemotesReport()
    local lines = {}
    table.insert(lines, "================================================================================")
    table.insert(lines, "ROUBE UM OVO - RELATORIO DE REMOTES INTERCEPTADOS (v4.0 FORENSE)")
    table.insert(lines, "Data/Hora: " .. os.date("%Y-%m-%d %H:%M:%S") .. " | Sessao: " .. string.format("%.2fs", os.clock() - startTime))
    table.insert(lines, "Deep Spy Ativo: " .. tostring(deepSpyActive) .. " (" .. deepSpyHookMethod .. ")")
    table.insert(lines, "================================================================================\n")

    table.insert(lines, "--------------------------------------------------------------------------------")
    table.insert(lines, string.format("[SECAO A] REMOTES ENVIADOS PELO CLIENTE (FireServer / InvokeServer) - %d Chamadas", #outgoingRemotes))
    table.insert(lines, "--------------------------------------------------------------------------------")
    if #outgoingRemotes > 0 then
        for _, r in ipairs(outgoingRemotes) do table.insert(lines, r) end
    else
        table.insert(lines, "Nenhum remote enviado interceptado ainda.")
    end
    table.insert(lines, "\n")

    table.insert(lines, "--------------------------------------------------------------------------------")
    table.insert(lines, "[SECAO B] RESUMO DE REMOTES COM FILTRO ANTI-FLOOD (CONTADORES DE SPAM)")
    table.insert(lines, "--------------------------------------------------------------------------------")
    local spamCount = 0
    for name, cnt in pairs(spamCounters) do
        spamCount = spamCount + 1
        table.insert(lines, string.format("  - %-36s : %d ocorrencias suprimidas do log", name, cnt))
    end
    if spamCount == 0 then table.insert(lines, "Nenhum spam registrado.") end
    table.insert(lines, "\n")

    table.insert(lines, "--------------------------------------------------------------------------------")
    table.insert(lines, string.format("[SECAO C] REMOTES RECEBIDOS RELEVANTES (OnClientEvent) - %d Eventos", #incomingRemotes))
    table.insert(lines, "--------------------------------------------------------------------------------")
    if #incomingRemotes > 0 then
        for _, r in ipairs(incomingRemotes) do table.insert(lines, r) end
    else
        table.insert(lines, "Nenhum remote recebido relevante registrado.")
    end

    return table.concat(lines, "\n")
end

-- 7.2 Relatorio de Esteira / Treadmill
local function generateTreadmillReport()
    local lines = {}
    table.insert(lines, "================================================================================")
    table.insert(lines, "ROUBE UM OVO - RELATORIO FORENSE DE ESTEIRA & TREADMILL (v4.0)")
    table.insert(lines, "Data/Hora: " .. os.date("%Y-%m-%d %H:%M:%S") .. " | Sessao: " .. string.format("%.2fs", os.clock() - startTime))
    table.insert(lines, "================================================================================\n")

    table.insert(lines, string.format("Total de Eventos de Esteira / Toques Gravados: %d", #treadmillEvents))
    table.insert(lines, "--------------------------------------------------------------------------------")
    if #treadmillEvents > 0 then
        for _, ev in ipairs(treadmillEvents) do table.insert(lines, ev) end
    else
        table.insert(lines, "Nenhum evento de esteira gravado. Suba na esteira ou ative o auto-esteira do concorrente!")
    end

    return table.concat(lines, "\n")
end

-- 7.3 Relatorio de ESP, Renda e Interface do Concorrente
local function generateEspAndGuiReport()
    local lines = {}
    table.insert(lines, "================================================================================")
    table.insert(lines, "ROUBE UM OVO - RELATORIO FORENSE DE ESP, RENDA & CONCORRENTE (v4.0)")
    table.insert(lines, "Data/Hora: " .. os.date("%Y-%m-%d %H:%M:%S") .. " | Sessao: " .. string.format("%.2fs", os.clock() - startTime))
    table.insert(lines, "================================================================================\n")

    table.insert(lines, "--------------------------------------------------------------------------------")
    table.insert(lines, string.format("[PARTE 1] ESP E TEXTOS DE OVOS/RENDA GERADOS PELO CONCORRENTE (%d Itens)", #competitorEspLogs))
    table.insert(lines, "--------------------------------------------------------------------------------")
    if #competitorEspLogs > 0 then
        for _, item in ipairs(competitorEspLogs) do table.insert(lines, item) end
    else
        table.insert(lines, "Nenhum ESP do concorrente detectado no Workspace ainda.")
    end
    table.insert(lines, "\n")

    table.insert(lines, "--------------------------------------------------------------------------------")
    table.insert(lines, string.format("[PARTE 2] ESTRUTURA DE GUI E MENUS DO CONCORRENTE (%d Linhas)", #competitorGuiDump))
    table.insert(lines, "--------------------------------------------------------------------------------")
    if #competitorGuiDump > 0 then
        for _, g in ipairs(competitorGuiDump) do table.insert(lines, g) end
    else
        table.insert(lines, "Nenhuma GUI externa detectada em CoreGui ou PlayerGui.")
    end

    return table.concat(lines, "\n")
end

-- 7.4 Relatorio de Voo / Waypoints
local function generateFlightReport()
    local lines = {}
    table.insert(lines, "================================================================================")
    table.insert(lines, "ROUBE UM OVO - TELEMETRIA & WAYPOINTS DE VOO FORENSE (v4.0)")
    table.insert(lines, "Data/Hora: " .. os.date("%Y-%m-%d %H:%M:%S") .. " | Total de Pontos: " .. #flightWaypoints)
    table.insert(lines, "================================================================================\n")

    for _, wp in ipairs(flightWaypoints) do table.insert(lines, wp) end
    return table.concat(lines, "\n")
end

-- 7.5 Relatorio Mestre Consolidado
local function generateMasterReport()
    local master = {
        "================================================================================",
        "ROUBE UM OVO - RELATORIO FORENSE MESTRE DEFINITIVO (v4.0 SUPER-FORENSIC)",
        "Data/Hora: " .. os.date("%Y-%m-%d %H:%M:%S") .. " | Tempo: " .. string.format("%.2fs", os.clock() - startTime),
        "PlaceId: " .. tostring(game.PlaceId) .. " | JobId: " .. tostring(game.JobId),
        "Jogador: " .. (LocalPlayer and LocalPlayer.Name or "N/D") .. " (" .. (LocalPlayer and tostring(LocalPlayer.UserId) or "N/D") .. ")",
        "Deep Spy: " .. tostring(deepSpyActive) .. " [" .. deepSpyHookMethod .. "]",
        "================================================================================\n",
        generateRemotesReport(),
        "\n\n",
        generateTreadmillReport(),
        "\n\n",
        generateEspAndGuiReport(),
        "\n\n",
        generateFlightReport(),
        "\n\n",
        "================================================================================",
        string.format("[DUMP ESTRUTURAL DO JOGO] (%d Linhas)", #structuralDumpLines),
        "================================================================================",
        table.concat(structuralDumpLines, "\n"),
        "\n================================================================================",
        "FIM DO RELATORIO FORENSE MESTRE v4.0",
        "================================================================================"
    }
    return table.concat(master, "\n")
end

--================================================================--
-- 8. INTERFACE GRAFICA COM ABAS & MULTIPLOS BOTOES DE COPIA
--================================================================--
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "BF_Mega_Sniffer_GUI_v4"
ScreenGui.ResetOnSpawn = false

pcall(function()
    if gethui then ScreenGui.Parent = gethui()
    elseif syn and syn.protect_gui then syn.protect_gui(ScreenGui); ScreenGui.Parent = game:GetService("CoreGui")
    else ScreenGui.Parent = game:GetService("CoreGui") end
end)
if not ScreenGui.Parent then ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 560, 0, 410)
MainFrame.Position = UDim2.new(0.02, 0, 0.05, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(13, 17, 23)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 8)
Corner.Parent = MainFrame

local Stroke = Instance.new("UIStroke")
Stroke.Color = Color3.fromRGB(56, 189, 248)
Stroke.Thickness = 1.5
Stroke.Parent = MainFrame

-- TopBar
local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 34)
TopBar.BackgroundColor3 = Color3.fromRGB(22, 27, 34)
TopBar.BorderSizePixel = 0
TopBar.Parent = MainFrame

local TopCorner = Instance.new("UICorner")
TopCorner.CornerRadius = UDim.new(0, 8)
TopCorner.Parent = TopBar

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -90, 1, 0)
Title.Position = UDim2.new(0, 12, 0, 0)
Title.BackgroundTransparency = 1
Title.Font = Enum.Font.GothamBold
Title.TextSize = 11
Title.TextColor3 = Color3.fromRGB(56, 189, 248)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Text = "MEGA SNIFFER FORENSE v4.0 | DEEP SPY: " .. (deepSpyActive and "ATIVO" or "PASSIVO")
Title.Parent = TopBar

local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, 24, 0, 24)
MinBtn.Position = UDim2.new(1, -60, 0, 5)
MinBtn.BackgroundColor3 = Color3.fromRGB(33, 38, 45)
MinBtn.Font = Enum.Font.GothamBold
MinBtn.TextSize = 12
MinBtn.TextColor3 = Color3.fromRGB(201, 209, 217)
MinBtn.Text = "-"
MinBtn.Parent = TopBar

local MinCorner = Instance.new("UICorner")
MinCorner.CornerRadius = UDim.new(0, 4)
MinCorner.Parent = MinBtn

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 24, 0, 24)
CloseBtn.Position = UDim2.new(1, -30, 0, 5)
CloseBtn.BackgroundColor3 = Color3.fromRGB(239, 68, 68)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 11
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.Text = "X"
CloseBtn.Parent = TopBar

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 4)
CloseCorner.Parent = CloseBtn

-- Barra de Abas
local TabBar = Instance.new("Frame")
TabBar.Size = UDim2.new(1, -20, 0, 26)
TabBar.Position = UDim2.new(0, 10, 0, 38)
TabBar.BackgroundTransparency = 1
TabBar.Parent = MainFrame

local currentTab = "REMOTES"

local function createTabBtn(name, text, posX, sizeX)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(sizeX, -4, 1, 0)
    btn.Position = UDim2.new(posX, 0, 0, 0)
    btn.BackgroundColor3 = Color3.fromRGB(33, 38, 45)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 9
    btn.TextColor3 = Color3.fromRGB(139, 148, 158)
    btn.Text = text
    btn.Parent = TabBar

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 4)
    c.Parent = btn
    return btn
end

local TabLive = createTabBtn("AO_VIVO", "STATUS", 0, 0.20)
local TabRemotes = createTabBtn("REMOTES", "REMOTES", 0.20, 0.20)
local TabEsteira = createTabBtn("ESTEIRA", "ESTEIRA", 0.40, 0.20)
local TabEsp = createTabBtn("ESP", "ESP & RENDA", 0.60, 0.20)
local TabDump = createTabBtn("DUMP", "DUMP JOGO", 0.80, 0.20)

local allTabs = {
    AO_VIVO = TabLive,
    REMOTES = TabRemotes,
    ESTEIRA = TabEsteira,
    ESP = TabEsp,
    DUMP = TabDump
}

local function updateTabStyles()
    for tabKey, tabBtn in pairs(allTabs) do
        if tabKey == currentTab then
            tabBtn.BackgroundColor3 = Color3.fromRGB(56, 189, 248)
            tabBtn.TextColor3 = Color3.fromRGB(13, 17, 23)
        else
            tabBtn.BackgroundColor3 = Color3.fromRGB(33, 38, 45)
            tabBtn.TextColor3 = Color3.fromRGB(139, 148, 158)
        end
    end
end

TabLive.MouseButton1Click:Connect(function() currentTab = "AO_VIVO"; updateTabStyles() end)
TabRemotes.MouseButton1Click:Connect(function() currentTab = "REMOTES"; updateTabStyles() end)
TabEsteira.MouseButton1Click:Connect(function() currentTab = "ESTEIRA"; updateTabStyles() end)
TabEsp.MouseButton1Click:Connect(function() currentTab = "ESP"; updateTabStyles() end)
TabDump.MouseButton1Click:Connect(function() currentTab = "DUMP"; updateTabStyles() end)
updateTabStyles()

-- Caixa de Log Central
local LogBox = Instance.new("ScrollingFrame")
LogBox.Size = UDim2.new(1, -20, 0, 210)
LogBox.Position = UDim2.new(0, 10, 0, 68)
LogBox.BackgroundColor3 = Color3.fromRGB(1, 4, 9)
LogBox.BorderSizePixel = 0
LogBox.ScrollBarThickness = 5
LogBox.Parent = MainFrame

local LogBoxCorner = Instance.new("UICorner")
LogBoxCorner.CornerRadius = UDim.new(0, 6)
LogBoxCorner.Parent = LogBox

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
LogText.Text = "Aguardando eventos..."
LogText.Parent = LogBox

-- Barra Superior de Acoes Rapidas (Copias Seletivas para Discord)
local QuickCopyBar = Instance.new("Frame")
QuickCopyBar.Size = UDim2.new(1, -20, 0, 30)
QuickCopyBar.Position = UDim2.new(0, 10, 0, 284)
QuickCopyBar.BackgroundTransparency = 1
QuickCopyBar.Parent = MainFrame

local function createActionBtn(text, posX, sizeX, bgColor, fgColor)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(sizeX, -4, 1, 0)
    btn.Position = UDim2.new(posX, 0, 0, 0)
    btn.BackgroundColor3 = bgColor
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 9
    btn.TextColor3 = fgColor or Color3.fromRGB(255, 255, 255)
    btn.Text = text
    btn.Parent = QuickCopyBar

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 4)
    c.Parent = btn
    return btn
end

local CopyRemotesBtn = createActionBtn("COPIAR REMOTES", 0, 0.33, Color3.fromRGB(147, 51, 234))
local CopyEsteiraBtn = createActionBtn("COPIAR ESTEIRA", 0.33, 0.33, Color3.fromRGB(234, 88, 12))
local CopyEspBtn = createActionBtn("COPIAR ESP/RENDA", 0.66, 0.34, Color3.fromRGB(59, 130, 246))

-- Barra Principal de Botoes (Salvar 5 Arquivos & Copiar Mestre)
local ButtonBar = Instance.new("Frame")
ButtonBar.Size = UDim2.new(1, -20, 0, 42)
ButtonBar.Position = UDim2.new(0, 10, 1, -50)
ButtonBar.BackgroundTransparency = 1
ButtonBar.Parent = MainFrame

local SaveFilesBtn = Instance.new("TextButton")
SaveFilesBtn.Size = UDim2.new(0.50, -4, 1, 0)
SaveFilesBtn.Position = UDim2.new(0, 0, 0, 0)
SaveFilesBtn.BackgroundColor3 = Color3.fromRGB(16, 185, 129)
SaveFilesBtn.Font = Enum.Font.GothamBold
SaveFilesBtn.TextSize = 10
SaveFilesBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
SaveFilesBtn.Text = "SALVAR 5 ARQUIVOS TXT (NO DISCO)"
SaveFilesBtn.Parent = ButtonBar

local SaveFilesCorner = Instance.new("UICorner")
SaveFilesCorner.CornerRadius = UDim.new(0, 6)
SaveFilesCorner.Parent = SaveFilesBtn

local CopyMasterBtn = Instance.new("TextButton")
CopyMasterBtn.Size = UDim2.new(0.35, -4, 1, 0)
CopyMasterBtn.Position = UDim2.new(0.50, 4, 0, 0)
CopyMasterBtn.BackgroundColor3 = Color3.fromRGB(14, 165, 233)
CopyMasterBtn.Font = Enum.Font.GothamBold
CopyMasterBtn.TextSize = 10
CopyMasterBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyMasterBtn.Text = "COPIAR MESTRE (TUDO)"
CopyMasterBtn.Parent = ButtonBar

local CopyMasterCorner = Instance.new("UICorner")
CopyMasterCorner.CornerRadius = UDim.new(0, 6)
CopyMasterCorner.Parent = CopyMasterBtn

local ClearBtn = Instance.new("TextButton")
ClearBtn.Size = UDim2.new(0.15, 0, 1, 0)
ClearBtn.Position = UDim2.new(0.85, 4, 0, 0)
ClearBtn.BackgroundColor3 = Color3.fromRGB(239, 68, 68)
ClearBtn.Font = Enum.Font.GothamBold
ClearBtn.TextSize = 10
ClearBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ClearBtn.Text = "LIMPAR"
ClearBtn.Parent = ButtonBar

local ClearCorner = Instance.new("UICorner")
ClearCorner.CornerRadius = UDim.new(0, 6)
ClearCorner.Parent = ClearBtn

-- Handlers dos Botoes
local function notifyBtn(btn, tempText, origText, origColor)
    btn.Text = tempText
    task.delay(2.0, function()
        btn.Text = origText
        btn.BackgroundColor3 = origColor
    end)
end

CopyRemotesBtn.MouseButton1Click:Connect(function()
    local text = generateRemotesReport()
    pcall(function() if setclipboard then setclipboard(text) end end)
    notifyBtn(CopyRemotesBtn, "REMOTES COPIADOS!", "COPIAR REMOTES", Color3.fromRGB(147, 51, 234))
end)

CopyEsteiraBtn.MouseButton1Click:Connect(function()
    local text = generateTreadmillReport()
    pcall(function() if setclipboard then setclipboard(text) end end)
    notifyBtn(CopyEsteiraBtn, "ESTEIRA COPIADA!", "COPIAR ESTEIRA", Color3.fromRGB(234, 88, 12))
end)

CopyEspBtn.MouseButton1Click:Connect(function()
    local text = generateEspAndGuiReport()
    pcall(function() if setclipboard then setclipboard(text) end end)
    notifyBtn(CopyEspBtn, "ESP/RENDA COPIADA!", "COPIAR ESP/RENDA", Color3.fromRGB(59, 130, 246))
end)

SaveFilesBtn.MouseButton1Click:Connect(function()
    SaveFilesBtn.Text = "SALVANDO..."
    local ok, count = pcall(function()
        local saved = 0
        if writefile then
            writefile("MEGA_SNIFFER_RELATORIO_MESTRE.txt", generateMasterReport())
            saved = saved + 1
            writefile("MEGA_SNIFFER_REMOTES.txt", generateRemotesReport())
            saved = saved + 1
            writefile("MEGA_SNIFFER_ESTEIRA.txt", generateTreadmillReport())
            saved = saved + 1
            writefile("MEGA_SNIFFER_ESP_DADOS.txt", generateEspAndGuiReport())
            saved = saved + 1
            writefile("MEGA_SNIFFER_VOO.txt", generateFlightReport())
            saved = saved + 1
        end
        return saved
    end)

    if ok and count > 0 then
        SaveFilesBtn.BackgroundColor3 = Color3.fromRGB(5, 150, 105)
        notifyBtn(SaveFilesBtn, "5 ARQUIVOS GRAVADOS NO DISCO!", "SALVAR 5 ARQUIVOS TXT (NO DISCO)", Color3.fromRGB(16, 185, 129))
    else
        SaveFilesBtn.BackgroundColor3 = Color3.fromRGB(239, 68, 68)
        notifyBtn(SaveFilesBtn, "writefile NAO SUPORTADO!", "SALVAR 5 ARQUIVOS TXT (NO DISCO)", Color3.fromRGB(16, 185, 129))
    end
end)

CopyMasterBtn.MouseButton1Click:Connect(function()
    local master = generateMasterReport()
    pcall(function()
        if setclipboard then setclipboard(master) end
        if writefile then writefile("MEGA_SNIFFER_RELATORIO_MESTRE.txt", master) end
    end)
    notifyBtn(CopyMasterBtn, "COPIADO COMPLETO!", "COPIAR MESTRE (TUDO)", Color3.fromRGB(14, 165, 233))
end)

ClearBtn.MouseButton1Click:Connect(function()
    outgoingRemotes = {}
    incomingRemotes = {}
    treadmillEvents = {}
    competitorEspLogs = {}
    flightWaypoints = {}
    spamCounters = {}
    liveLogs = {}
    LogText.Text = "Logs limpos com sucesso!"
    notifyBtn(ClearBtn, "LIMPO!", "LIMPAR", Color3.fromRGB(239, 68, 68))
end)

local isMinimized = false
MinBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        MainFrame.Size = UDim2.new(0, 560, 0, 34)
        LogBox.Visible = false
        TabBar.Visible = false
        QuickCopyBar.Visible = false
        ButtonBar.Visible = false
        MinBtn.Text = "+"
    else
        MainFrame.Size = UDim2.new(0, 560, 0, 410)
        LogBox.Visible = true
        TabBar.Visible = true
        QuickCopyBar.Visible = true
        ButtonBar.Visible = true
        MinBtn.Text = "-"
    end
end)

CloseBtn.MouseButton1Click:Connect(function()
    ScreenGui:Destroy()
end)

-- Loop de Atualizacao da Interface
task.spawn(function()
    while true do
        task.wait(0.5)
        if not isMinimized then
            local lines = {}
            if currentTab == "AO_VIVO" then
                local sIdx = math.max(1, #liveLogs - 18)
                for i = sIdx, #liveLogs do table.insert(lines, liveLogs[i]) end
            elseif currentTab == "REMOTES" then
                table.insert(lines, string.format("--- REMOTES ENVIADOS (Total: %d) ---", #outgoingRemotes))
                local sIdx = math.max(1, #outgoingRemotes - 15)
                for i = sIdx, #outgoingRemotes do table.insert(lines, outgoingRemotes[i]) end
                table.insert(lines, "\n--- RESUMO DE SPAM SUPRIMIDO ---")
                for k, v in pairs(spamCounters) do
                    table.insert(lines, string.format("  * %s : %d ocorrencias", k, v))
                end
            elseif currentTab == "ESTEIRA" then
                local sIdx = math.max(1, #treadmillEvents - 18)
                for i = sIdx, #treadmillEvents do table.insert(lines, treadmillEvents[i]) end
                if #lines == 0 then table.insert(lines, "Aguardando eventos de esteira / treadmill / toques...") end
            elseif currentTab == "ESP" then
                local sIdx = math.max(1, #competitorEspLogs - 18)
                for i = sIdx, #competitorEspLogs do table.insert(lines, competitorEspLogs[i]) end
                if #lines == 0 then table.insert(lines, "Aguardando detecção de ESP ou textos de ovos do concorrente...") end
            elseif currentTab == "DUMP" then
                local endIdx = math.min(#structuralDumpLines, 25)
                for i = 1, endIdx do table.insert(lines, structuralDumpLines[i]) end
                if #structuralDumpLines > 25 then
                    table.insert(lines, string.format("\n... e mais %d linhas. Clique em 'COPIAR MESTRE' para ler tudo!", #structuralDumpLines - 25))
                end
            end

            LogText.Text = #lines > 0 and table.concat(lines, "\n") or "Sem eventos no momento."
            LogBox.CanvasPosition = Vector2.new(0, 99999)

            -- Atualiza Contadores no Titulo
            Title.Text = string.format("MEGA SNIFFER v4.0 | Remotes:%d | Esteira:%d | ESP:%d",
                #outgoingRemotes, #treadmillEvents, #competitorEspLogs)
        end
    end
end)

logLive("SISTEMA", "Sniffer pronto! Execute agora o script concorrente.")

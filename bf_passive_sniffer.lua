--[[
    ================================================================================
    ROUBE UM OVO - MEGA SNIFFER & DUMPER FORENSE DEFINITIVO (v3.0 ULTRA EXHAUSTIVE)
    PlaceId: 107778070777162 | Jogo: Roube um Ovo (Steal an Egg)
    ================================================================================
    SEGURANCA & COMPATIBILIDADE:
    - MODO PADRAO 100% PASSIVO: ZERO hookfunction, ZERO hookmetamethod, ZERO tamper.
      Totalmente compativel e indetectavel contra Luarmor e anti-tamper.
    - MODO DEEP SPY OPCIONAL (Ativado por botao na GUI):
      Hook seguro em __namecall para interceptar remotes enviados (FireServer/InvokeServer).
    - SPY DE CONCORRENTE: Captura LogService (prints/warns), GUIs criadas e OnClientEvent.
    - GRAVADOR DE VOO: Deltas em milissegundos de cada etapa do auto-steal e CFrame/Y.
    - DUMP ESTRUTURAL: 118 Pets, 11 Ilhas/Areas com DropTables, Guardas, Slots e Plots.
    - EXPORTACAO UNIFICADA: Salva em 'MEGA_SNIFFER_DUMPER_LOG.txt' e copia para o Clipboard.
    ================================================================================
]]

local Services = {
    Workspace = game:GetService("Workspace"),
    Players = game:GetService("Players"),
    ReplicatedStorage = game:GetService("ReplicatedStorage"),
    ReplicatedFirst = game:GetService("ReplicatedFirst"),
    Lighting = game:GetService("Lighting"),
    HttpService = game:GetService("HttpService"),
    RunService = game:GetService("RunService"),
    LogService = game:GetService("LogService"),
    ProximityPromptService = game:GetService("ProximityPromptService")
}

local LocalPlayer = Services.Players.LocalPlayer
local startTime = os.clock()

-- Buffers de Armazenamento
local liveLogs = {}
local competitorLogs = {}
local structuralDumpLines = {}
local cycleReports = {}
local eventCount = 0

local function safeJson(val)
    local ok, res = pcall(function()
        return Services.HttpService:JSONEncode(val)
    end)
    return ok and res or tostring(val)
end

local function getHierarchyPath(inst)
    if not inst then return "nil" end
    local parts = {}
    local cur = inst
    while cur and cur ~= game do
        table.insert(parts, 1, cur.Name)
        cur = cur.Parent
    end
    return table.concat(parts, ".")
end

local function logLive(category, message, details)
    eventCount = eventCount + 1
    local elapsed = os.clock() - startTime
    local timeStr = string.format("[%06.3fs]", elapsed)
    local line = string.format("%s [%-13s] %s %s", timeStr, category, message, details and ("| " .. details) or "")
    table.insert(liveLogs, line)
    if #liveLogs > 1500 then
        table.remove(liveLogs, 1)
    end
end

local function logCompetitor(category, message, details)
    local elapsed = os.clock() - startTime
    local timeStr = string.format("[%06.3fs]", elapsed)
    local line = string.format("%s [%-14s] %s %s", timeStr, category, message, details and ("| " .. details) or "")
    table.insert(competitorLogs, line)
    if #competitorLogs > 1500 then
        table.remove(competitorLogs, 1)
    end
end

logLive("SISTEMA", "Mega Sniffer & Dumper v3.0 Iniciado com Sucesso!")

--================================================================--
-- 1. VARREDURA ESTRUTURAL PROFUNDA (DUMP ESTRUTURAL DO JOGO)
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
    addLine("ROUBE UM OVO - MEGA DUMP ESTRUTURAL FORENSE COMPLETO (v3.0)")
    addLine("Data/Hora: " .. os.date("%Y-%m-%d %H:%M:%S") .. " | Sessao: " .. string.format("%.2fs", os.clock() - startTime))
    addLine("PlaceId: " .. tostring(game.PlaceId) .. " | JobId: " .. tostring(game.JobId))
    addLine("Jogador: " .. (LocalPlayer and LocalPlayer.Name or "N/D") .. " (" .. (LocalPlayer and tostring(LocalPlayer.UserId) or "N/D") .. ")")
    addLine("================================================================================\n")

    -- 1.1 CATALOGO DE TODOS OS REMOTES DO JOGO
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

    -- 1.2 REPLICATEDSTORAGE - ASSETS & PETS DIRECTORY
    addLine("--------------------------------------------------------------------------------")
    addLine("[SECAO 2] REPLICATEDSTORAGE: ASSETS, PETS, ILHAS, RARIDADES E GUARDAS")
    addLine("--------------------------------------------------------------------------------")
    local dataFolder = Services.ReplicatedStorage:FindFirstChild("Data")

    -- 2.A - Directory de Pets/Ovos
    local assetsFolder = dataFolder and dataFolder:FindFirstChild("Assets")
    local directoryMod = assetsFolder and assetsFolder:FindFirstChild("Directory")
    if directoryMod and directoryMod:IsA("ModuleScript") then
        local ok, dirData = pcall(function() return require(directoryMod) end)
        if ok and type(dirData) == "table" then
            local count = 0
            for k, _ in pairs(dirData) do count = count + 1 end
            addLine(string.format(">>> Modulo Data.Assets.Directory encontrado! Total de Pets cadastrados: %d\n", count))
            for petKey, petInfo in pairs(dirData) do
                if type(petInfo) == "table" then
                    local dName = petInfo.DisplayName or petInfo.Name or petKey
                    local rarity = petInfo.Rarity or "COMMON"
                    local income = petInfo.Income or petInfo.MoneyPerSecond or petInfo.CashPerSecond or petInfo.Value or "N/D"
                    local weight = petInfo.Weight or petInfo.Chance or petInfo.DropChance or "N/D"
                    local mesh = petInfo.MeshId or petInfo.Model or "N/D"
                    addLine(string.format("  - Chave: %-26s | Display: %-24s | Raridade: %-11s | Renda: %-10s | Peso: %-6s | Mesh: %s",
                        tostring(petKey), tostring(dName), tostring(rarity), tostring(income), tostring(weight), tostring(mesh)))
                else
                    addLine(string.format("  - Chave: %-26s = %s", tostring(petKey), tostring(petInfo)))
                end
            end
        else
            addLine("  Erro ao executar require no modulo Data.Assets.Directory: " .. tostring(dirData))
        end
    else
        addLine("  Modulo ReplicatedStorage.Data.Assets.Directory nao encontrado diretamente.")
    end

    -- 2.B - Configurações de Raridade (Data.Rarity.Rarities)
    local rarityFolder = dataFolder and dataFolder:FindFirstChild("Rarity")
    local raritiesMod = rarityFolder and rarityFolder:FindFirstChild("Rarities")
    if raritiesMod and raritiesMod:IsA("ModuleScript") then
        local ok, rarData = pcall(function() return require(raritiesMod) end)
        if ok and type(rarData) == "table" then
            addLine("\n>>> Modulo Data.Rarity.Rarities (Configuracao de Raridades):")
            for rKey, rInfo in pairs(rarData) do
                if type(rInfo) == "table" then
                    addLine(string.format("  - Raridade: %-15s | Numero: %-2s | Display: %-12s | Valor Padrao: %-16s | Anuncio: %s",
                        tostring(rKey), tostring(rInfo.RarityNumber), tostring(rInfo.DisplayName), tostring(rInfo.DefaultRarityValue), tostring(rInfo.Announce)))
                else
                    addLine(string.format("  - Raridade: %-15s = %s", tostring(rKey), tostring(rInfo)))
                end
            end
        end
    end

    -- 2.C - Áreas, Ilhas e DropTables (Data.Areas.Directory)
    local areasFolder = dataFolder and dataFolder:FindFirstChild("Areas")
    local areasMod = areasFolder and areasFolder:FindFirstChild("Directory")
    if areasMod and areasMod:IsA("ModuleScript") then
        local ok, areaData = pcall(function() return require(areasMod) end)
        if ok and type(areaData) == "table" then
            addLine("\n>>> Modulo Data.Areas.Directory (Ilhas e Tabelas de Drops Reais):")
            for aKey, aInfo in pairs(areaData) do
                if type(aInfo) == "table" then
                    local dName = aInfo.DisplayName or aKey
                    local guard = aInfo.GuardId or "Nenhum"
                    local bat = aInfo.IndexBatGearId or "Nenhum"
                    addLine(string.format("\n  [ILHA/AREA] %s (Display: %s | Guarda: %s | Taco/Arma: %s)", tostring(aKey), tostring(dName), tostring(guard), tostring(bat)))
                    if type(aInfo.DropTable) == "table" then
                        addLine("    Tabela de Drops (% de Chance Real):")
                        for _, drop in ipairs(aInfo.DropTable) do
                            if type(drop) == "table" and #drop >= 2 then
                                addLine(string.format("      * %-25s : %.3f%%", tostring(drop[1]), tonumber(drop[2]) or 0))
                            end
                        end
                    end
                end
            end
        end
    end

    -- 2.D - Guardas e Velocidades (Data.Guards.Directory)
    local guardsFolder = dataFolder and dataFolder:FindFirstChild("Guards")
    local guardsMod = guardsFolder and guardsFolder:FindFirstChild("Directory")
    if guardsMod and guardsMod:IsA("ModuleScript") then
        local ok, guardData = pcall(function() return require(guardsMod) end)
        if ok and type(guardData) == "table" then
            addLine("\n>>> Modulo Data.Guards.Directory (Guardas e Atributos Fisicos):")
            for gKey, gInfo in pairs(guardData) do
                if type(gInfo) == "table" then
                    addLine(string.format("  - Guarda: %-18s | WalkSpeed: %-5s | HitDist: %-3s | Radius: %-3s | PickupDist: %s",
                        tostring(gKey), tostring(gInfo.WalkSpeed), tostring(gInfo.HitDistance), tostring(gInfo.FlatRadius), tostring(gInfo.EggPickupDistance)))
                end
            end
        end
    end
    addLine("\n")

    -- 1.3 DISSECCAO DE AREAEGGSLOTSCLIENT (ESTEIRA E SLOTS VIVOS)
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
    else
        addLine("  Workspace.AreaEggSlotsClient nao encontrado.")
    end
    addLine("\n")

    -- 1.4 PLACEDEGGRENDERS E PLOTS DE JOGADORES (BASES)
    addLine("--------------------------------------------------------------------------------")
    addLine("[SECAO 4] BASES DE JOGADORES & OVOS PLANTADOS (WORKSPACE.PLOTS / PLACEDEGGRENDERS)")
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

    local placedFolder = Services.Workspace:FindFirstChild("PlacedEggRenders")
    if placedFolder then
        local placed = placedFolder:GetChildren()
        addLine(string.format("\nTotal de Ovos Plantados em PlacedEggRenders: %d", #placed))
        for i, egg in ipairs(placed) do
            local ePos = "N/D"
            pcall(function()
                local p = egg:GetPivot().Position
                ePos = string.format("(%.1f, %.1f, %.1f)", p.X, p.Y, p.Z)
            end)
            local attrs = {}
            for k, v in pairs(egg:GetAttributes()) do table.insert(attrs, k .. "=" .. tostring(v)) end
            addLine(string.format("  #%02d Ovo Plot: %-26s | Pos: %s | Attrs: %s",
                i, egg.Name, ePos, #attrs > 0 and table.concat(attrs, ", ") or "Nenhum"))
        end
    end
    addLine("\n")

    -- 1.5 PROXIMITY PROMPTS ATIVOS NO WORKSPACE
    addLine("--------------------------------------------------------------------------------")
    addLine("[SECAO 5] TODOS OS PROXIMITY PROMPTS ATIVOS NO MAPA")
    addLine("--------------------------------------------------------------------------------")
    local promptCount = 0
    for _, desc in ipairs(Services.Workspace:GetDescendants()) do
        if desc:IsA("ProximityPrompt") then
            promptCount = promptCount + 1
            local pPos = "N/D"
            pcall(function()
                local p = desc.Parent:GetPivot().Position
                pPos = string.format("(%.1f, %.1f, %.1f)", p.X, p.Y, p.Z)
            end)
            addLine(string.format("  #%02d Prompt: '%s' | Acao: '%s' | Pai: %s | Pos: %s | Dist: %.1f | Hold: %.2fs | Enabled: %s",
                promptCount, desc.ObjectText, desc.ActionText, getHierarchyPath(desc.Parent), pPos,
                desc.MaxActivationDistance, desc.HoldDuration, tostring(desc.Enabled)))
        end
    end
    addLine(string.format("Total de Prompts catalogados: %d\n", promptCount))

    -- 1.6 LOCALPLAYER E ESTADO DO JOGADOR
    addLine("--------------------------------------------------------------------------------")
    addLine("[SECAO 6] ATRIBUTOS E ESTADO DE LOCALPLAYER")
    addLine("--------------------------------------------------------------------------------")
    if LocalPlayer then
        local lpAttrs = {}
        for k, v in pairs(LocalPlayer:GetAttributes()) do table.insert(lpAttrs, k .. "=" .. tostring(v)) end
        addLine("  Atributos do Player: " .. (#lpAttrs > 0 and table.concat(lpAttrs, ", ") or "Nenhum"))
        local bp = LocalPlayer:FindFirstChild("Backpack")
        if bp then
            local bpTools = {}
            for _, t in ipairs(bp:GetChildren()) do table.insert(bpTools, t.Name .. "[" .. t.ClassName .. "]") end
            addLine("  Mochila (Backpack): " .. (#bpTools > 0 and table.concat(bpTools, ", ") or "Vazia"))
        end
        local char = LocalPlayer.Character
        if char then
            local charAttrs = {}
            for k, v in pairs(char:GetAttributes()) do table.insert(charAttrs, k .. "=" .. tostring(v)) end
            addLine("  Atributos do Character: " .. (#charAttrs > 0 and table.concat(charAttrs, ", ") or "Nenhum"))
            local charTools = {}
            for _, c in ipairs(char:GetChildren()) do
                if c:IsA("Tool") then table.insert(charTools, c.Name) end
            end
            addLine("  Ferramentas no Character: " .. (#charTools > 0 and table.concat(charTools, ", ") or "Nenhuma"))
        end
    end
    addLine("\n")

    -- 1.7 INSTANCIAS NIL
    addLine("--------------------------------------------------------------------------------")
    addLine("[SECAO 7] VARREDURA DE INSTANCIAS NIL (GETNILINSTANCES)")
    addLine("--------------------------------------------------------------------------------")
    if getnilinstances then
        local ok, nilList = pcall(getnilinstances)
        if ok and type(nilList) == "table" then
            local nilFiltered = 0
            for _, inst in ipairs(nilList) do
                local low = inst.Name:lower()
                if low:find("egg") or low:find("remote") or low:find("guard") or low:find("chicken") or low:find("data") or low:find("plot") then
                    nilFiltered = nilFiltered + 1
                    addLine(string.format("  - Nil: %-28s [%s]", inst.Name, inst.ClassName))
                end
            end
            addLine(string.format("Instancias Nil relevantes encontradas: %d (de %d no total)", nilFiltered, #nilList))
        else
            addLine("  Falha ao executar getnilinstances.")
        end
    else
        addLine("  getnilinstances nao suportado por este executor.")
    end
    addLine("\n================================================================================")
    addLine("FIM DO DUMP ESTRUTURAL.")
    addLine("================================================================================\n")

    dumpFinished = true
    isDumping = false
    logLive("DUMP", "Dump estrutural completo finalizado!", string.format("Total de linhas geradas: %d", #structuralDumpLines))
end

-- Roda o dump inicial em background
task.spawn(runFullStructuralDump)

--================================================================--
-- 2. ESPIONAGEM EM TEMPO REAL DO SCRIPT CONCORRENTE (FOOTPRINT SPY)
--================================================================--

-- 2.1 INTERCEPTACAO PASSIVA DE CONSOLE OUTPUT (LogService.MessageOut)
Services.LogService.MessageOut:Connect(function(msg, msgType)
    local typeName = msgType.Name
    local low = msg:lower()
    if low:find("egg") or low:find("steal") or low:find("tp") or low:find("cframe") or low:find("farm") or
       low:find("esteira") or low:find("bigfroot") or low:find("bf") or low:find("auto") or low:find("radar") or
       low:find("remote") or low:find("target") or low:find("plot") or low:find("chicken") or low:find("guard") or
       msgType == Enum.MessageType.MessageWarning or msgType == Enum.MessageType.MessageError then
        logCompetitor("CONSOLE_OUTPUT", string.format("[%s] %s", typeName, msg))
    end
end)

-- 2.2 DETECCAO DE INTERFACES E TELAS CRIADAS PELO SCRIPT CONCORRENTE
local function inspectGuiRecursively(parentObj, depth)
    if depth > 4 then return end
    for _, child in ipairs(parentObj:GetChildren()) do
        if child:IsA("GuiObject") then
            local text = (child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox")) and child.Text or ""
            local info = string.format("%s[%s]", child.Name, child.ClassName)
            if #text > 0 and #text < 80 then
                info = info .. " Text: '" .. text .. "'"
            end
            logCompetitor("GUI_ELEMENTO", info, "Pai: " .. parentObj.Name)
            inspectGuiRecursively(child, depth + 1)
        end
    end
end

local function watchGuiContainer(container, containerName)
    if not container then return end
    container.ChildAdded:Connect(function(child)
        if child.Name ~= "BF_Mega_Sniffer_GUI" and child.Name ~= "Freecam" then
            logCompetitor("GUI_CRIADA", string.format("Nova GUI detectada em %s: %s [%s]", containerName, child.Name, child.ClassName))
            task.delay(0.5, function()
                inspectGuiRecursively(child, 1)
            end)
        end
    end)
end

watchGuiContainer(LocalPlayer:WaitForChild("PlayerGui"), "PlayerGui")
pcall(function()
    if gethui then watchGuiContainer(gethui(), "Hui") end
    local coreGui = game:GetService("CoreGui")
    watchGuiContainer(coreGui, "CoreGui")
end)

-- 2.3 MONITORAMENTO PASSIVO DE REMOTEEVENTS (OnClientEvent)
local hookedRemotesCount = 0
for _, desc in ipairs(game:GetDescendants()) do
    if desc:IsA("RemoteEvent") then
        hookedRemotesCount = hookedRemotesCount + 1
        pcall(function()
            desc.OnClientEvent:Connect(function(...)
                local args = {...}
                local serializedArgs = {}
                for i = 1, math.min(#args, 6) do
                    local a = args[i]
                    if typeof(a) == "Instance" then
                        table.insert(serializedArgs, getHierarchyPath(a))
                    elseif type(a) == "table" then
                        table.insert(serializedArgs, safeJson(a):sub(1, 120))
                    else
                        table.insert(serializedArgs, tostring(a))
                    end
                end
                local argsStr = #serializedArgs > 0 and table.concat(serializedArgs, ", ") or "Sem argumentos"
                logCompetitor("REMOTE_RECEBIDO", desc.Name, "Origem: " .. getHierarchyPath(desc) .. " | Args: (" .. argsStr .. ")")
            end)
        end)
    end
end
logLive("SISTEMA", string.format("Escuta passiva ativada em %d RemoteEvents do jogo!", hookedRemotesCount))

-- 2.4 MONITORAMENTO DE MUTACOES DE ATRIBUTOS
if LocalPlayer then
    LocalPlayer.AttributeChanged:Connect(function(attrName)
        local val = LocalPlayer:GetAttribute(attrName)
        logCompetitor("ATTR_PLAYER", string.format("%s = %s", attrName, tostring(val)))
    end)
end

-- 2.5 DEEP REMOTE SPY OPCIONAL (OUTGOING REMOTES VIA HOOKMETAMETHOD)
local deepSpyEnabled = false
local function enableDeepRemoteSpy()
    if deepSpyEnabled then return true end
    local ok, err = pcall(function()
        if not hookmetamethod or not getnamecallmethod then
            error("Executor nao suporta hookmetamethod ou getnamecallmethod")
        end
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            if self and (method == "FireServer" or method == "InvokeServer") then
                local args = {...}
                local serializedArgs = {}
                for i = 1, math.min(#args, 8) do
                    local a = args[i]
                    if typeof(a) == "Instance" then
                        table.insert(serializedArgs, getHierarchyPath(a))
                    elseif type(a) == "table" then
                        table.insert(serializedArgs, safeJson(a):sub(1, 140))
                    else
                        table.insert(serializedArgs, tostring(a))
                    end
                end
                local argsStr = #serializedArgs > 0 and table.concat(serializedArgs, ", ") or "Nenhum"
                local caller = "Desconhecido"
                pcall(function()
                    local cs = getcallingscript and getcallingscript()
                    if cs then caller = cs:GetFullName() end
                end)
                logCompetitor("REMOTE_ENVIADO", string.format("[%s] %s", method, self.Name),
                    string.format("Caller: %s | Origem: %s | Args: (%s)", caller, getHierarchyPath(self), argsStr))
            end
            return oldNamecall(self, ...)
        end)
    end)
    if ok then
        deepSpyEnabled = true
        logLive("SISTEMA", "Deep Remote Spy ATIVADO com sucesso!", "Monitorando FireServer e InvokeServer de scripts.")
        return true
    else
        logLive("SISTEMA", "Falha ao ativar Deep Remote Spy:", tostring(err))
        return false
    end
end

--================================================================--
-- 3. RASTREADOR DE CICLO DE ROUBO COM DELTAS EM MILISSEGUNDOS
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
        "================================================================================",
        "[RELATORIO CONSOLIDADO DE CICLO DE AUTO-STEAL]",
        string.format("Alvo Roubado: %s", CycleTracker.TargetEggName),
        string.format("1. Espera pelo Hit da Galinha : %.3fs (Pos Galinha: %.1f, %.1f, %.1f)", math.max(0, dHit), CycleTracker.ChickenPos.X, CycleTracker.ChickenPos.Y, CycleTracker.ChickenPos.Z),
        string.format("2. Salto/Voo ate o Ovo Alvo   : %.3fs", math.max(0, dEgg)),
        string.format("3. Atraso antes do Prompt     : %.3fs", math.max(0, dPrompt)),
        string.format("4. Tempo de Segurar / Acoplar : %.3fs", math.max(0, dHeld)),
        string.format("5. Salto de Retorno para Base : %.3fs (Pos Base: %.1f, %.1f, %.1f)", math.max(0, dBase), CycleTracker.BasePos.X, CycleTracker.BasePos.Y, CycleTracker.BasePos.Z),
        string.format("6. Tempo ate Deposito no Plot : %.3fs", math.max(0, dDeposit)),
        string.format("TEMPO TOTAL DO CICLO COMPLETO : %.3fs", math.max(0, totalTime)),
        "================================================================================"
    }

    local repStr = table.concat(report, "\n")
    table.insert(cycleReports, repStr)
    for _, rLine in ipairs(report) do
        table.insert(liveLogs, rLine)
    end
end

--================================================================--
-- 4. MONITORAMENTO FISICO DO PERSONAGEM (CFRAME, TELEPORTES, RAGDOLL)
--================================================================--
local lastPos = nil

local function setupCharacterTracker(char)
    if not char then return end
    local hrp = char:WaitForChild("HumanoidRootPart", 5)
    local hum = char:WaitForChild("Humanoid", 5)
    if not hrp or not hum then return end

    lastPos = hrp.Position
    logLive("PERSONAGEM", "Personagem monitorado com sucesso", string.format("Pos: (%.1f, %.1f, %.1f)", lastPos.X, lastPos.Y, lastPos.Z))

    char.AttributeChanged:Connect(function(attrName)
        local val = char:GetAttribute(attrName)
        logCompetitor("ATTR_CHAR", string.format("%s = %s", attrName, tostring(val)))
    end)

    hrp:GetPropertyChangedSignal("CFrame"):Connect(function()
        local curPos = hrp.Position
        local delta = (curPos - lastPos).Magnitude

        if delta > 8.0 then
            local vel = hrp.AssemblyLinearVelocity.Magnitude
            local stateName = hum:GetState().Name
            local now = os.clock()

            local nearby = "Espaco Aberto"
            local isNearChicken = false
            local isNearEgg = false
            local isNearPlot = false

            for _, obj in ipairs(Services.Workspace:GetChildren()) do
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

            if not isNearChicken then
                local eggSlots = Services.Workspace:FindFirstChild("AreaEggSlotsClient")
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

            if not isNearChicken and not isNearEgg then
                local plots = Services.Workspace:FindFirstChild("Plots")
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

            if isNearChicken and CycleTracker.CurrentPhase == "IDLE" then
                CycleTracker.CurrentPhase = "AT_CHICKEN"
                CycleTracker.TimeChicken = now
                logLive("FASE_ROUBO", "[1/6] Concorrente foi ate a Galinha!", string.format("Aguardando hit... Pos: (%.1f, %.1f, %.1f)", curPos.X, curPos.Y, curPos.Z))
            elseif isNearEgg and (CycleTracker.CurrentPhase == "HIT_DETECTED" or CycleTracker.CurrentPhase == "AT_CHICKEN") then
                CycleTracker.CurrentPhase = "AT_EGG"
                CycleTracker.TimeEgg = now
                logLive("FASE_ROUBO", "[3/6] Concorrente saltou para o Ovo!", string.format("Alvo: %s | Salto de %.1f studs", CycleTracker.TargetEggName, delta))
            elseif isNearPlot and (CycleTracker.CurrentPhase == "EGG_HELD" or CycleTracker.CurrentPhase == "AT_EGG") then
                CycleTracker.CurrentPhase = "AT_BASE"
                CycleTracker.TimeBase = now
                logLive("FASE_ROUBO", "[5/6] Concorrente retornou para a Base!", string.format("Pos Entrega: (%.1f, %.1f, %.1f)", curPos.X, curPos.Y, curPos.Z))
            end

            logLive("TELEPORTE", string.format("Salto %.1f studs -> (%.1f, %.1f, %.1f)", delta, curPos.X, curPos.Y, curPos.Z),
                string.format("Vel: %.1f | Estado: %s | Y: %.1f | %s", vel, stateName, curPos.Y, nearby))
        end
        lastPos = curPos
    end)

    hum.StateChanged:Connect(function(oldState, newState)
        local vel = hrp.AssemblyLinearVelocity.Magnitude
        local now = os.clock()

        if newState == Enum.HumanoidStateType.Ragdoll or (newState == Enum.HumanoidStateType.PlatformStanding and vel > 20) then
            if CycleTracker.CurrentPhase == "AT_CHICKEN" then
                CycleTracker.CurrentPhase = "HIT_DETECTED"
                CycleTracker.TimeHit = now
                local deltaHit = now - CycleTracker.TimeChicken
                logLive("FASE_ROUBO", "[2/6] Hit/Ragdoll confirmado!", string.format("Delta reacao: %.3fs | Vel do golpe: %.1f", deltaHit, vel))
            end
        end

        logLive("ESTADO", string.format("Humanoid [%s -> %s]", oldState.Name, newState.Name),
            string.format("Vel: %.1f | Y: %.1f | Pos: (%.1f, %.1f, %.1f)", vel, hrp.Position.Y, hrp.Position.X, hrp.Position.Y, hrp.Position.Z))
    end)

    char.ChildAdded:Connect(function(child)
        local low = child.Name:lower()
        if not low:find("animate") and not child:IsA("Accessory") and not child:IsA("Shirt") and not child:IsA("Pants") then
            local now = os.clock()
            if CycleTracker.CurrentPhase == "AT_EGG" or CycleTracker.CurrentPhase == "PROMPT_DONE" then
                CycleTracker.CurrentPhase = "EGG_HELD"
                CycleTracker.TimeHeld = now
                local deltaHeld = now - (CycleTracker.TimePrompt > 0 and CycleTracker.TimePrompt or CycleTracker.TimeEgg)
                logLive("FASE_ROUBO", "[4/6] Ovo acoplado ao personagem!", string.format("Item: %s | Tempo de captura: %.3fs", child.Name, deltaHeld))
            end
            logLive("OVO_PEGO", "Item/Ovo acoplado: " .. child.Name .. " [" .. child.ClassName .. "]",
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
                logLive("FASE_ROUBO", "[6/6] Ovo depositado no Plot com sucesso!", string.format("Tempo de deposito: %.3fs", deltaDep))
                task.delay(0.1, printCycleReport)
            end
            logLive("OVO_ENTREGUE", "Item/Ovo saiu do personagem: " .. child.Name,
                string.format("Pos HRP: (%.1f, %.1f, %.1f)", hrp.Position.X, hrp.Position.Y, hrp.Position.Z))
        end
    end)
end

if LocalPlayer.Character then
    task.spawn(setupCharacterTracker, LocalPlayer.Character)
end
LocalPlayer.CharacterAdded:Connect(setupCharacterTracker)

--================================================================--
-- 5. MONITORAMENTO DE PROXIMITY PROMPTS
--================================================================--
Services.ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt, player)
    if player == LocalPlayer then
        local pPos = prompt.Parent and prompt.Parent:GetPivot().Position or Vector3.zero
        logLive("PROMPT_HOLD", "Segurou prompt: '" .. prompt.ActionText .. "' | Obj: '" .. prompt.ObjectText .. "'",
            string.format("Pai: %s | Pos: (%.1f, %.1f, %.1f) | Hold: %.2fs", prompt.Parent and prompt.Parent.Name or "N/D", pPos.X, pPos.Y, pPos.Z, prompt.HoldDuration))
    end
end)

Services.ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
    if player == LocalPlayer then
        local now = os.clock()
        if CycleTracker.CurrentPhase == "AT_EGG" then
            CycleTracker.CurrentPhase = "PROMPT_DONE"
            CycleTracker.TimePrompt = now
            local dPrompt = now - CycleTracker.TimeEgg
            logLive("FASE_ROUBO", "Prompt de roubo disparado!", string.format("Atraso de disparo: %.3fs | MaxDist: %.1f", dPrompt, prompt.MaxActivationDistance))
        end
        local pPos = prompt.Parent and prompt.Parent:GetPivot().Position or Vector3.zero
        logLive("PROMPT_TRIGGER", "PROMPT DISPARADO! '" .. prompt.ActionText .. "' | Obj: '" .. prompt.ObjectText .. "'",
            string.format("Pai: %s | Pos: (%.1f, %.1f, %.1f) | Dist: %.1f", prompt.Parent and prompt.Parent.Name or "N/D", pPos.X, pPos.Y, pPos.Z, prompt.MaxActivationDistance))
    end
end)

--================================================================--
-- 6. GERADOR DE RELATORIO UNIFICADO (DUMP + CONCORRENTE + TELEMETRIA)
--================================================================--
local function generateMasterReport()
    local full = {}
    table.insert(full, "================================================================================")
    table.insert(full, "ROUBE UM OVO - RELATORIO FORENSE MESTRE (MEGA SNIFFER & DUMPER v3.0)")
    table.insert(full, "Data/Hora: " .. os.date("%Y-%m-%d %H:%M:%S") .. " | Tempo Total: " .. string.format("%.2fs", os.clock() - startTime))
    table.insert(full, "PlaceId: " .. tostring(game.PlaceId) .. " | JobId: " .. tostring(game.JobId))
    table.insert(full, "Jogador: " .. (LocalPlayer and LocalPlayer.Name or "N/D") .. " (" .. (LocalPlayer and tostring(LocalPlayer.UserId) or "N/D") .. ")")
    table.insert(full, "================================================================================\n")

    -- Seção 1: Relatórios de Ciclos de Roubo Capturados
    table.insert(full, "--------------------------------------------------------------------------------")
    table.insert(full, string.format("[PARTE 1] RELATORIOS DE CICLOS DE ROUBO COMPLETOS (%d Ciclos)", #cycleReports))
    table.insert(full, "--------------------------------------------------------------------------------")
    if #cycleReports > 0 then
        for _, rep in ipairs(cycleReports) do
            table.insert(full, rep)
        end
    else
        table.insert(full, "Nenhum ciclo completo de roubo finalizado ainda durante esta gravacao.")
    end
    table.insert(full, "\n")

    -- Seção 2: Pegada do Script Concorrente (Console, GUIs, Remotes)
    table.insert(full, "--------------------------------------------------------------------------------")
    table.insert(full, string.format("[PARTE 2] ATIVIDADE E PEGADA DO SCRIPT CONCORRENTE (%d Eventos)", #competitorLogs))
    table.insert(full, "--------------------------------------------------------------------------------")
    if #competitorLogs > 0 then
        for _, cLog in ipairs(competitorLogs) do
            table.insert(full, cLog)
        end
    else
        table.insert(full, "Nenhuma saida de console ou GUI concorrente detectada.")
    end
    table.insert(full, "\n")

    -- Seção 3: Telemetria Física e Eventos Ao Vivo
    table.insert(full, "--------------------------------------------------------------------------------")
    table.insert(full, string.format("[PARTE 3] TELEMETRIA FISICA E GRAVADOR DE VOO (%d Eventos)", #liveLogs))
    table.insert(full, "--------------------------------------------------------------------------------")
    for _, lLog in ipairs(liveLogs) do
        table.insert(full, lLog)
    end
    table.insert(full, "\n")

    -- Seção 4: Dump Estrutural do Jogo
    table.insert(full, "--------------------------------------------------------------------------------")
    table.insert(full, string.format("[PARTE 4] DUMP ESTRUTURAL DO JOGO (%d Linhas)", #structuralDumpLines))
    table.insert(full, "--------------------------------------------------------------------------------")
    if #structuralDumpLines > 0 then
        for _, dLine in ipairs(structuralDumpLines) do
            table.insert(full, dLine)
        end
    else
        table.insert(full, "Dump estrutural ainda em andamento...")
    end
    table.insert(full, "\n================================================================================")
    table.insert(full, "FIM DO RELATORIO FORENSE MESTRE.")
    table.insert(full, "================================================================================")

    return table.concat(full, "\n")
end

--================================================================--
-- 7. INTERFACE GRAFICA COM ABAS & CONTROLES COMPLETOS
--================================================================--
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "BF_Mega_Sniffer_GUI"
ScreenGui.ResetOnSpawn = false

pcall(function()
    if gethui then ScreenGui.Parent = gethui()
    elseif syn and syn.protect_gui then syn.protect_gui(ScreenGui); ScreenGui.Parent = game:GetService("CoreGui")
    else ScreenGui.Parent = game:GetService("CoreGui") end
end)
if not ScreenGui.Parent then ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 540, 0, 370)
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

-- Barra de Título
local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 32)
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
Title.TextSize = 12
Title.TextColor3 = Color3.fromRGB(56, 189, 248)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Text = "ROUBE UM OVO - MEGA SNIFFER & DUMPER v3.0"
Title.Parent = TopBar

local MinBtn = Instance.new("TextButton")
MinBtn.Size = UDim2.new(0, 24, 0, 24)
MinBtn.Position = UDim2.new(1, -60, 0, 4)
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
CloseBtn.Position = UDim2.new(1, -30, 0, 4)
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
TabBar.Position = UDim2.new(0, 10, 0, 36)
TabBar.BackgroundTransparency = 1
TabBar.Parent = MainFrame

local currentTab = "AO_VIVO"

local TabLive = Instance.new("TextButton")
TabLive.Size = UDim2.new(0.32, 0, 1, 0)
TabLive.Position = UDim2.new(0, 0, 0, 0)
TabLive.BackgroundColor3 = Color3.fromRGB(56, 189, 248)
TabLive.Font = Enum.Font.GothamBold
TabLive.TextSize = 10
TabLive.TextColor3 = Color3.fromRGB(13, 17, 23)
TabLive.Text = "TELEMETRIA AO VIVO"
TabLive.Parent = TabBar

local TabLiveCorner = Instance.new("UICorner")
TabLiveCorner.CornerRadius = UDim.new(0, 4)
TabLiveCorner.Parent = TabLive

local TabComp = Instance.new("TextButton")
TabComp.Size = UDim2.new(0.32, 0, 1, 0)
TabComp.Position = UDim2.new(0.34, 0, 0, 0)
TabComp.BackgroundColor3 = Color3.fromRGB(33, 38, 45)
TabComp.Font = Enum.Font.GothamBold
TabComp.TextSize = 10
TabComp.TextColor3 = Color3.fromRGB(139, 148, 158)
TabComp.Text = "CONCORRENTE / SPY"
TabComp.Parent = TabBar

local TabCompCorner = Instance.new("UICorner")
TabCompCorner.CornerRadius = UDim.new(0, 4)
TabCompCorner.Parent = TabComp

local TabDump = Instance.new("TextButton")
TabDump.Size = UDim2.new(0.32, 0, 1, 0)
TabDump.Position = UDim2.new(0.68, 0, 0, 0)
TabDump.BackgroundColor3 = Color3.fromRGB(33, 38, 45)
TabDump.Font = Enum.Font.GothamBold
TabDump.TextSize = 10
TabDump.TextColor3 = Color3.fromRGB(139, 148, 158)
TabDump.Text = "DUMP DO JOGO"
TabDump.Parent = TabBar

local TabDumpCorner = Instance.new("UICorner")
TabDumpCorner.CornerRadius = UDim.new(0, 4)
TabDumpCorner.Parent = TabDump

-- Caixa de Log Central
local LogBox = Instance.new("ScrollingFrame")
LogBox.Size = UDim2.new(1, -20, 0, 190)
LogBox.Position = UDim2.new(0, 10, 0, 66)
LogBox.BackgroundColor3 = Color3.fromRGB(1, 4, 9)
LogBox.BorderSizePixel = 0
LogBox.ScrollBarThickness = 4
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

local function updateTabStyles()
    TabLive.BackgroundColor3 = currentTab == "AO_VIVO" and Color3.fromRGB(56, 189, 248) or Color3.fromRGB(33, 38, 45)
    TabLive.TextColor3 = currentTab == "AO_VIVO" and Color3.fromRGB(13, 17, 23) or Color3.fromRGB(139, 148, 158)

    TabComp.BackgroundColor3 = currentTab == "CONCORRENTE" and Color3.fromRGB(56, 189, 248) or Color3.fromRGB(33, 38, 45)
    TabComp.TextColor3 = currentTab == "CONCORRENTE" and Color3.fromRGB(13, 17, 23) or Color3.fromRGB(139, 148, 158)

    TabDump.BackgroundColor3 = currentTab == "DUMP" and Color3.fromRGB(56, 189, 248) or Color3.fromRGB(33, 38, 45)
    TabDump.TextColor3 = currentTab == "DUMP" and Color3.fromRGB(13, 17, 23) or Color3.fromRGB(139, 148, 158)
end

TabLive.MouseButton1Click:Connect(function()
    currentTab = "AO_VIVO"
    updateTabStyles()
end)

TabComp.MouseButton1Click:Connect(function()
    currentTab = "CONCORRENTE"
    updateTabStyles()
end)

TabDump.MouseButton1Click:Connect(function()
    currentTab = "DUMP"
    updateTabStyles()
end)

-- Barra Intermediária: Deep Spy Toggle
local MidBar = Instance.new("Frame")
MidBar.Size = UDim2.new(1, -20, 0, 24)
MidBar.Position = UDim2.new(0, 10, 0, 260)
MidBar.BackgroundTransparency = 1
MidBar.Parent = MainFrame

local DeepSpyBtn = Instance.new("TextButton")
DeepSpyBtn.Size = UDim2.new(1, 0, 1, 0)
DeepSpyBtn.BackgroundColor3 = Color3.fromRGB(33, 38, 45)
DeepSpyBtn.Font = Enum.Font.GothamBold
DeepSpyBtn.TextSize = 10
DeepSpyBtn.TextColor3 = Color3.fromRGB(148, 163, 184)
DeepSpyBtn.Text = "[CLIQUE PARA ATIVAR] DEEP REMOTE SPY (MONITORAR REMOTES ENVIADOS)"
DeepSpyBtn.Parent = MidBar

local DeepSpyCorner = Instance.new("UICorner")
DeepSpyCorner.CornerRadius = UDim.new(0, 4)
DeepSpyCorner.Parent = DeepSpyBtn

DeepSpyBtn.MouseButton1Click:Connect(function()
    if not deepSpyEnabled then
        local success = enableDeepRemoteSpy()
        if success then
            DeepSpyBtn.BackgroundColor3 = Color3.fromRGB(147, 51, 234)
            DeepSpyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
            DeepSpyBtn.Text = "DEEP REMOTE SPY ATIVADO (MONITORANDO OUTGOING REMOTES)"
        else
            DeepSpyBtn.BackgroundColor3 = Color3.fromRGB(239, 68, 68)
            DeepSpyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
            DeepSpyBtn.Text = "FALHA AO ATIVAR HOOKMETAMETHOD NO EXECUTOR"
        end
    end
end)

-- Barra Inferior de Botoes
local ButtonBar = Instance.new("Frame")
ButtonBar.Size = UDim2.new(1, -20, 0, 36)
ButtonBar.Position = UDim2.new(0, 10, 1, -44)
ButtonBar.BackgroundTransparency = 1
ButtonBar.Parent = MainFrame

local CopyMasterBtn = Instance.new("TextButton")
CopyMasterBtn.Size = UDim2.new(0.55, 0, 1, 0)
CopyMasterBtn.Position = UDim2.new(0, 0, 0, 0)
CopyMasterBtn.BackgroundColor3 = Color3.fromRGB(16, 185, 129)
CopyMasterBtn.Font = Enum.Font.GothamBold
CopyMasterBtn.TextSize = 11
CopyMasterBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CopyMasterBtn.Text = "COPIAR RELATORIO COMPLETO (TUDO)"
CopyMasterBtn.Parent = ButtonBar

local CopyMasterCorner = Instance.new("UICorner")
CopyMasterCorner.CornerRadius = UDim.new(0, 6)
CopyMasterCorner.Parent = CopyMasterBtn

local DumpNowBtn = Instance.new("TextButton")
DumpNowBtn.Size = UDim2.new(0.25, 0, 1, 0)
DumpNowBtn.Position = UDim2.new(0.57, 0, 0, 0)
DumpNowBtn.BackgroundColor3 = Color3.fromRGB(59, 130, 246)
DumpNowBtn.Font = Enum.Font.GothamBold
DumpNowBtn.TextSize = 10
DumpNowBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
DumpNowBtn.Text = "NOVO DUMP"
DumpNowBtn.Parent = ButtonBar

local DumpNowCorner = Instance.new("UICorner")
DumpNowCorner.CornerRadius = UDim.new(0, 6)
DumpNowCorner.Parent = DumpNowBtn

local ClearBtn = Instance.new("TextButton")
ClearBtn.Size = UDim2.new(0.16, 0, 1, 0)
ClearBtn.Position = UDim2.new(0.84, 0, 0, 0)
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
CopyMasterBtn.MouseButton1Click:Connect(function()
    local masterReport = generateMasterReport()
    pcall(function()
        if setclipboard then
            setclipboard(masterReport)
        end
        if writefile then
            writefile("MEGA_SNIFFER_DUMPER_LOG.txt", masterReport)
        end
    end)
    CopyMasterBtn.Text = "COPIADO COM SUCESSO! (SALVO EM TXT)"
    CopyMasterBtn.BackgroundColor3 = Color3.fromRGB(14, 165, 233)
    task.delay(2.5, function()
        CopyMasterBtn.Text = "COPIAR RELATORIO COMPLETO (TUDO)"
        CopyMasterBtn.BackgroundColor3 = Color3.fromRGB(16, 185, 129)
    end)
end)

DumpNowBtn.MouseButton1Click:Connect(function()
    DumpNowBtn.Text = "DUMPANDO..."
    task.spawn(function()
        runFullStructuralDump()
        DumpNowBtn.Text = "NOVO DUMP"
    end)
end)

ClearBtn.MouseButton1Click:Connect(function()
    liveLogs = {}
    competitorLogs = {}
    eventCount = 0
    LogText.Text = "Logs limpos com sucesso!"
    ClearBtn.Text = "LIMPO!"
    task.delay(1.5, function()
        ClearBtn.Text = "LIMPAR"
    end)
end)

local isMinimized = false
MinBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        MainFrame.Size = UDim2.new(0, 540, 0, 32)
        LogBox.Visible = false
        TabBar.Visible = false
        MidBar.Visible = false
        ButtonBar.Visible = false
        MinBtn.Text = "+"
    else
        MainFrame.Size = UDim2.new(0, 540, 0, 370)
        LogBox.Visible = true
        TabBar.Visible = true
        MidBar.Visible = true
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
            local linesToShow = {}
            if currentTab == "AO_VIVO" then
                local startIdx = math.max(1, #liveLogs - 20)
                for i = startIdx, #liveLogs do
                    table.insert(linesToShow, liveLogs[i])
                end
            elseif currentTab == "CONCORRENTE" then
                local startIdx = math.max(1, #competitorLogs - 20)
                for i = startIdx, #competitorLogs do
                    table.insert(linesToShow, competitorLogs[i])
                end
                if #linesToShow == 0 then
                    table.insert(linesToShow, "Aguardando logs de console, GUIs ou Remotes do concorrente...")
                end
            elseif currentTab == "DUMP" then
                local startIdx = 1
                local endIdx = math.min(#structuralDumpLines, 30)
                for i = startIdx, endIdx do
                    table.insert(linesToShow, structuralDumpLines[i])
                end
                if #structuralDumpLines > 30 then
                    table.insert(linesToShow, string.format("\n... e mais %d linhas. Clique em 'COPIAR RELATORIO COMPLETO' para ver tudo!", #structuralDumpLines - 30))
                end
            end
            LogText.Text = #linesToShow > 0 and table.concat(linesToShow, "\n") or "Sem dados no momento."
            LogBox.CanvasPosition = Vector2.new(0, 99999)
        end
    end
end)

logLive("SISTEMA", "Pronto para teste! Execute o script concorrente agora.", "Ative as funcoes dele e deixe agir!")

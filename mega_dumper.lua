--[[
    ================================================================================
    ROUBE UM OVO - MEGA DUMPER ESTRUTURAL & FORENSE DEFINITIVO (v1.0)
    PlaceId: 107778070777162 | Jogo: Roube um Ovo (Steal an Egg)
    ================================================================================
    Este script realiza uma varredura completa e irrestrita em todos os servicos,
    modulos, instancias nil, remotes, prompts, atributos e slots vivos do jogo,
    salvando tudo em 'ROUBE_UM_OVO_MEGA_DUMP.txt' e copiando para a Area de Transferencia.
]]

local Services = {
    Workspace = game:GetService("Workspace"),
    Players = game:GetService("Players"),
    ReplicatedStorage = game:GetService("ReplicatedStorage"),
    ReplicatedFirst = game:GetService("ReplicatedFirst"),
    Lighting = game:GetService("Lighting"),
    HttpService = game:GetService("HttpService"),
    RunService = game:GetService("RunService")
}

local LocalPlayer = Services.Players.LocalPlayer
local outputLines = {}
local function logLine(str)
    table.insert(outputLines, str or "")
end

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

logLine("================================================================================")
logLine("ROUBE UM OVO - MEGA DUMP FORENSE COMPLETO")
logLine("Data: " .. os.date("%Y-%m-%d %H:%M:%S"))
logLine("PlaceId: " .. tostring(game.PlaceId) .. " | JobId: " .. tostring(game.JobId))
logLine("Jogador: " .. (LocalPlayer and LocalPlayer.Name or "N/D") .. " (" .. (LocalPlayer and tostring(LocalPlayer.UserId) or "N/D") .. ")")
logLine("================================================================================\n")

-- 1. TODOS OS REMOTEEVENTS E REMOTEFUNCTIONS DO JOGO
logLine("--------------------------------------------------------------------------------")
logLine("[1] TODOS OS REMOTES DO JOGO (COMUNICACAO CLIENTE <-> SERVIDOR)")
logLine("--------------------------------------------------------------------------------")
local totalRemotes = 0
for _, inst in ipairs(game:GetDescendants()) do
    if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") or inst:IsA("BindableEvent") or inst:IsA("BindableFunction") then
        totalRemotes = totalRemotes + 1
        logLine(string.format("  [%s] %s", inst.ClassName, getHierarchyPath(inst)))
    end
end
logLine(string.format("Total de Remotes catalogados: %d\n", totalRemotes))

-- 2. REPLICATEDSTORAGE: TODOS OS MODULOS (REQUIRE) E VALORES
logLine("--------------------------------------------------------------------------------")
logLine("[2] REPLICATEDSTORAGE: MODULOS, CONFIGURACOES E BANCOS DE DADOS")
logLine("--------------------------------------------------------------------------------")
local function dumpModule(mod)
    logLine(string.format("\n  >>> MODULO: %s", getHierarchyPath(mod)))
    local ok, data = pcall(function() return require(mod) end)
    if ok then
        if type(data) == "table" then
            logLine("      Dados Retornados (JSON):")
            logLine("      " .. safeJson(data))
        else
            logLine("      Retorno Nao-Tabela: " .. tostring(data))
        end
    else
        logLine("      [ERRO AO DAR REQUIRE]: " .. tostring(data))
    end
end

for _, desc in ipairs(Services.ReplicatedStorage:GetDescendants()) do
    if desc:IsA("ModuleScript") then
        dumpModule(desc)
    elseif desc:IsA("ValueBase") then
        logLine(string.format("  [VALOR] %s = %s", getHierarchyPath(desc), tostring(desc.Value)))
    end
end
logLine("\n")

-- 3. PROXIMITY PROMPTS ATIVOS NO MAPA
logLine("--------------------------------------------------------------------------------")
logLine("[3] TODOS OS PROXIMITY PROMPTS ATIVOS NO WORKSPACE")
logLine("--------------------------------------------------------------------------------")
local totalPrompts = 0
for _, desc in ipairs(Services.Workspace:GetDescendants()) do
    if desc:IsA("ProximityPrompt") then
        totalPrompts = totalPrompts + 1
        local parentPos = "N/D"
        pcall(function()
            local p = desc.Parent
            local pos = p:IsA("BasePart") and p.Position or (p:FindFirstChildWhichIsA("BasePart") and p:FindFirstChildWhichIsA("BasePart").Position)
            if pos then parentPos = string.format("(%.1f, %.1f, %.1f)", pos.X, pos.Y, pos.Z) end
        end)
        local attrs = {}
        for k, v in pairs(desc:GetAttributes()) do table.insert(attrs, k .. "=" .. tostring(v)) end
        local parentAttrs = {}
        if desc.Parent then
            for k, v in pairs(desc.Parent:GetAttributes()) do table.insert(parentAttrs, k .. "=" .. tostring(v)) end
        end

        logLine(string.format("  #%02d Prompt: '%s' | Acao: '%s' | Pai: %s | Pos: %s | Dist: %.1f | Hold: %.2fs | Enabled: %s",
            totalPrompts, desc.ObjectText, desc.ActionText, getHierarchyPath(desc.Parent), parentPos,
            desc.MaxActivationDistance, desc.HoldDuration, tostring(desc.Enabled)
        ))
        if #attrs > 0 then logLine("       Atributos do Prompt: " .. table.concat(attrs, ", ")) end
        if #parentAttrs > 0 then logLine("       Atributos do Pai: " .. table.concat(parentAttrs, ", ")) end
    end
end
logLine(string.format("Total de Prompts encontrados: %d\n", totalPrompts))

-- 4. DISSECCAO DE WORKSPACE.AREAEGGSLOTSCLIENT (TODOS OS SLOTS VIVOS)
logLine("--------------------------------------------------------------------------------")
logLine("[4] DISSECCAO COMPLETA DE WORKSPACE.AREAEGGSLOTSCLIENT")
logLine("--------------------------------------------------------------------------------")
local areaSlots = Services.Workspace:FindFirstChild("AreaEggSlotsClient")
if areaSlots then
    local slots = areaSlots:GetChildren()
    logLine(string.format("Total de Slots encontrados: %d", #slots))
    for i, slot in ipairs(slots) do
        local posStr = "N/D"
        pcall(function()
            local p = slot:IsA("BasePart") and slot.Position or (slot:FindFirstChildWhichIsA("BasePart") and slot:FindFirstChildWhichIsA("BasePart").Position)
            if p then posStr = string.format("(%.1f, %.1f, %.1f)", p.X, p.Y, p.Z) end
        end)
        local children = {}
        for _, c in ipairs(slot:GetChildren()) do
            local mId = (c:IsA("MeshPart") and c.MeshId) or (c:FindFirstChildWhichIsA("SpecialMesh") and c:FindFirstChildWhichIsA("SpecialMesh").MeshId) or ""
            local num = mId:match("(%d+)")
            table.insert(children, string.format("%s[%s]%s", c.Name, c.ClassName, num and (":" .. num) or ""))
        end
        local attrs = {}
        for k, v in pairs(slot:GetAttributes()) do table.insert(attrs, k .. "=" .. tostring(v)) end
        logLine(string.format("  #%02d Slot: %-32s | Pos: %s | Filhos (%d): %s | Attrs: %s",
            i, slot.Name, posStr, #children, #children > 0 and table.concat(children, ", ") or "Nenhum",
            #attrs > 0 and table.concat(attrs, ", ") or "Nenhum"
        ))
    end
else
    logLine("  Pasta Workspace.AreaEggSlotsClient NAO encontrada!")
end
logLine("\n")

-- 5. DISSECCAO DE PLACEDEGGRENDERS E PLOTS (BASES DOS JOGADORES)
logLine("--------------------------------------------------------------------------------")
logLine("[5] PLACEDEGGRENDERS & PLOTS DE JOGADORES")
logLine("--------------------------------------------------------------------------------")
local placedEggs = Services.Workspace:FindFirstChild("PlacedEggRenders")
if placedEggs then
    logLine(string.format("Total de Ovos em PlacedEggRenders: %d", #placedEggs:GetChildren()))
    for i, egg in ipairs(placedEggs:GetChildren()) do
        local posStr = "N/D"
        pcall(function()
            local p = egg:IsA("BasePart") and egg.Position or (egg:FindFirstChildWhichIsA("BasePart") and egg:FindFirstChildWhichIsA("BasePart").Position)
            if p then posStr = string.format("(%.1f, %.1f, %.1f)", p.X, p.Y, p.Z) end
        end)
        local attrs = {}
        for k, v in pairs(egg:GetAttributes()) do table.insert(attrs, k .. "=" .. tostring(v)) end
        local children = {}
        for _, c in ipairs(egg:GetChildren()) do table.insert(children, c.Name .. "[" .. c.ClassName .. "]") end
        logLine(string.format("  #%02d Ovo Plot: %-25s | Pos: %s | Filhos: %s | Attrs: %s",
            i, egg.Name, posStr, table.concat(children, ", "), #attrs > 0 and table.concat(attrs, ", ") or "Nenhum"
        ))
    end
else
    logLine("  Pasta Workspace.PlacedEggRenders nao encontrada.")
end

local plotsFolder = Services.Workspace:FindFirstChild("Plots")
if plotsFolder then
    logLine(string.format("\nTotal de Plots em Workspace.Plots: %d", #plotsFolder:GetChildren()))
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        local owner = "N/D"
        pcall(function()
            local o = plot:FindFirstChild("Owner") or plot:FindFirstChild("Player") or plot:FindFirstChild("OwnerName")
            if o then owner = tostring(o.Value) end
        end)
        local posStr = "N/D"
        pcall(function()
            local p = plot:IsA("BasePart") and plot.Position or (plot:FindFirstChildWhichIsA("BasePart") and plot:FindFirstChildWhichIsA("BasePart").Position)
            if p then posStr = string.format("(%.1f, %.1f, %.1f)", p.X, p.Y, p.Z) end
        end)
        logLine(string.format("  - Plot: %-15s | Dono: %-20s | Pos: %s", plot.Name, owner, posStr))
    end
end
logLine("\n")

-- 6. DISSECCAO DE CLIENTRENDEREDASSETS
logLine("--------------------------------------------------------------------------------")
logLine("[6] DISSECCAO DE WORKSPACE.CLIENTRENDEREDASSETS (MODELOS RENDERIZADOS)")
logLine("--------------------------------------------------------------------------------")
local cra = Services.Workspace:FindFirstChild("ClientRenderedAssets")
if cra then
    local items = cra:GetChildren()
    logLine(string.format("Total de Itens em ClientRenderedAssets: %d", #items))
    for i, item in ipairs(items) do
        local posStr = "N/D"
        pcall(function()
            local p = item:IsA("BasePart") and item.Position or (item:FindFirstChildWhichIsA("BasePart") and item:FindFirstChildWhichIsA("BasePart").Position)
            if p then posStr = string.format("(%.1f, %.1f, %.1f)", p.X, p.Y, p.Z) end
        end)
        local meshes = {}
        for _, d in ipairs(item:GetDescendants()) do
            local mId = (d:IsA("MeshPart") and d.MeshId) or (d:FindFirstChildWhichIsA("SpecialMesh") and d:FindFirstChildWhichIsA("SpecialMesh").MeshId) or ""
            local num = mId:match("(%d+)")
            if num then table.insert(meshes, num) end
        end
        local attrs = {}
        for k, v in pairs(item:GetAttributes()) do table.insert(attrs, k .. "=" .. tostring(v)) end
        logLine(string.format("  #%02d Asset: %-32s | Pos: %s | Meshes (%d): %s | Attrs: %s",
            i, item.Name, posStr, #meshes, #meshes > 0 and table.concat(meshes, ", ") or "Nenhuma",
            #attrs > 0 and table.concat(attrs, ", ") or "Nenhum"
        ))
    end
else
    logLine("  Pasta Workspace.ClientRenderedAssets nao encontrada.")
end
logLine("\n")

-- 7. BUSCA DE GUARDAS, GALINHAS E INIMIGOS NO MAPA
logLine("--------------------------------------------------------------------------------")
logLine("[7] LOCALIZACAO DE GUARDAS, GALINHAS E INIMIGOS NO WORKSPACE")
logLine("--------------------------------------------------------------------------------")
for _, obj in ipairs(Services.Workspace:GetChildren()) do
    local low = obj.Name:lower()
    if low:find("guard") or low:find("chicken") or low:find("galinha") or low:find("parasite") or low:find("monster") then
        local posStr = "N/D"
        pcall(function()
            local p = obj:IsA("BasePart") and obj.Position or (obj:FindFirstChildWhichIsA("BasePart") and obj:FindFirstChildWhichIsA("BasePart").Position)
            if p then posStr = string.format("(%.1f, %.1f, %.1f)", p.X, p.Y, p.Z) end
        end)
        local attrs = {}
        for k, v in pairs(obj:GetAttributes()) do table.insert(attrs, k .. "=" .. tostring(v)) end
        local children = {}
        for _, c in ipairs(obj:GetChildren()) do table.insert(children, c.Name .. "[" .. c.ClassName .. "]") end
        logLine(string.format("  - Objeto: %-25s | Classe: %-10s | Pos: %s | Filhos: %s | Attrs: %s",
            obj.Name, obj.ClassName, posStr, table.concat(children, ", "), #attrs > 0 and table.concat(attrs, ", ") or "Nenhum"
        ))
    end
end
logLine("\n")

-- 8. ESTADO DO JOGADOR LOCAL E CHARACTER
logLine("--------------------------------------------------------------------------------")
logLine("[8] ESTADO DO JOGADOR LOCAL (CHARACTER, ATRIBUTOS E RAGDOLL)")
logLine("--------------------------------------------------------------------------------")
if LocalPlayer then
    local lpAttrs = {}
    for k, v in pairs(LocalPlayer:GetAttributes()) do table.insert(lpAttrs, k .. "=" .. tostring(v)) end
    logLine("  Atributos de LocalPlayer: " .. (#lpAttrs > 0 and table.concat(lpAttrs, ", ") or "Nenhum"))

    local char = LocalPlayer.Character
    if char then
        local charAttrs = {}
        for k, v in pairs(char:GetAttributes()) do table.insert(charAttrs, k .. "=" .. tostring(v)) end
        logLine("  Atributos do Character: " .. (#charAttrs > 0 and table.concat(charAttrs, ", ") or "Nenhum"))
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then
            logLine(string.format("  Posicao HumanoidRootPart: (%.1f, %.1f, %.1f)", hrp.Position.X, hrp.Position.Y, hrp.Position.Z))
        end
        local hum = char:FindFirstChildWhichIsA("Humanoid")
        if hum then
            logLine(string.format("  Humanoid: Health=%.1f/%.1f | WalkSpeed=%.1f | JumpPower=%.1f | State=%s | PlatformStand=%s",
                hum.Health, hum.MaxHealth, hum.WalkSpeed, hum.JumpPower, tostring(hum:GetState()), tostring(hum.PlatformStand)
            ))
        end
        local tools = {}
        for _, c in ipairs(char:GetChildren()) do
            if c:IsA("Tool") then table.insert(tools, c.Name) end
        end
        logLine("  Ferramentas Equipadas: " .. (#tools > 0 and table.concat(tools, ", ") or "Nenhuma"))
    end

    local bp = LocalPlayer:FindFirstChild("Backpack")
    if bp then
        local bpTools = {}
        for _, t in ipairs(bp:GetChildren()) do table.insert(bpTools, t.Name) end
        logLine("  Mochila (Backpack): " .. (#bpTools > 0 and table.concat(bpTools, ", ") or "Vazia"))
    end

    local pGui = LocalPlayer:FindFirstChild("PlayerGui")
    if pGui then
        local guis = {}
        for _, g in ipairs(pGui:GetChildren()) do
            if g:IsA("ScreenGui") then table.insert(guis, string.format("%s(Enabled=%s)", g.Name, tostring(g.Enabled))) end
        end
        logLine("  PlayerGui ScreenGuis: " .. table.concat(guis, ", "))
    end
end
logLine("\n")

-- 9. INSTANCIAS NIL (GETNILINSTANCES)
logLine("--------------------------------------------------------------------------------")
logLine("[9] INSTANCIAS NIL (GETNILINSTANCES)")
logLine("--------------------------------------------------------------------------------")
if getnilinstances then
    local nilCount = 0
    local ok, nilList = pcall(getnilinstances)
    if ok and type(nilList) == "table" then
        logLine(string.format("Total de instancias Nil detectadas: %d", #nilList))
        for _, inst in ipairs(nilList) do
            local low = inst.Name:lower()
            if low:find("egg") or low:find("guard") or low:find("remote") or low:find("anticheat") or low:find("cheat") or low:find("ragdoll") or low:find("data") then
                nilCount = nilCount + 1
                logLine(string.format("  - Nil Relevante: %-25s [%s]", inst.Name, inst.ClassName))
            end
        end
        logLine(string.format("Instancias Nil relevantes listadas: %d", nilCount))
    else
        logLine("  Erro ao executar getnilinstances.")
    end
else
    logLine("  Funcao getnilinstances nao suportada por este executor.")
end
logLine("\n")

logLine("================================================================================")
logLine("FIM DO MEGA DUMP FORENSE.")
logLine("================================================================================")

local fullDumpText = table.concat(outputLines, "\n")

pcall(function()
    if writefile then
        writefile("ROUBE_UM_OVO_MEGA_DUMP.txt", fullDumpText)
    end
end)
pcall(function()
    if setclipboard then
        setclipboard(fullDumpText)
    end
end)

print("[MEGA DUMPER] Dump completo gerado com sucesso!")
print("[MEGA DUMPER] Salvo em 'ROUBE_UM_OVO_MEGA_DUMP.txt' e copiado para a Area de Transferencia!")

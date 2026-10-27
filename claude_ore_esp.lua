-- Автор: Claude (Anthropic), по просьбе владельца репозитория.
-- Ore ESP для режима "Мир шахтеров" (PlaceId 9404223526), инжектор Delta.
-- Руды ловятся по тегу OreSparkle (ParticleEmitter с атрибутом Rarity), который ставит сама игра.
-- Подсветка через стены (Highlight AlwaysOnTop) + трассеры от верхнего центра экрана.
-- v1.1.0: фильтр по глубине (от/до), автопоиск ближайшей подходящей руды, индикатор глубины.

if getgenv().OreESPLoaded then pcall(getgenv().OreESPUnload) end
getgenv().OreESPLoaded = true

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local CS = game:GetService("CollectionService")
local CoreGui = game:GetService("CoreGui")

local lp = Players.LocalPlayer
local cam = workspace.CurrentCamera
local guiParent = (gethui and gethui()) or CoreGui

-- ===== НАСТРОЙКИ =====
local RARITY_LIST = { 2, 3, 4, 5, 6 }   -- редкости, у которых игра ставит частицы
local MIN_DIST, MAX_DIST = 25, 3000
local DEPTH_MIN, DEPTH_MAX = -9500, 4000
local MAX_HIGHLIGHTS = 25               -- лимит Roblox ~31 Highlight одновременно
-- =====================

local DEFAULT_COLORS = {
    [1] = Color3.fromRGB(200, 200, 200),
    [2] = Color3.fromRGB(90, 220, 90),
    [3] = Color3.fromRGB(70, 140, 255),
    [4] = Color3.fromRGB(180, 80, 255),
    [5] = Color3.fromRGB(255, 170, 40),
    [6] = Color3.fromRGB(255, 60, 60),
}
local rarityColors = {}
pcall(function()
    local gd = require(RS.Modules.GameDefinition)
    for k, v in pairs(gd.RarityColors) do
        if typeof(v) == "Color3" then rarityColors[k] = v end
    end
    if type(gd.LowestDepth) == "number" then DEPTH_MIN = gd.LowestDepth end
end)
local function colorOf(r) return rarityColors[r] or DEFAULT_COLORS[r] or Color3.new(1, 1, 1) end

-- глубина = Y / 6 - 2000 - сдвиг мира (так игра сама ставит блоки)
local BH
pcall(function() BH = require(RS.Modules.BlockHandler) end)
local function worldOffsetY()
    if BH and BH.GetWorldOffset then
        local ok, _, oy = pcall(BH.GetWorldOffset)
        if ok and type(oy) == "number" then return oy end
    end
    return 0
end
local function depthFrom(y, oy) return y / 6 - 2000 - oy end

local state = {
    espOn = true,
    autoOn = true,
    depthOn = false,
    maxDist = 400,
    depthLo = DEPTH_MIN,
    depthHi = DEPTH_MAX,
    enabled = {},
}
for _, r in ipairs(RARITY_LIST) do state.enabled[r] = (r >= 5) end

local hasDrawing = typeof(Drawing) ~= "nil"

-- ===== ТРЕКИНГ РУД =====
local tracked = {} -- [emitter] = entry

local function destroyEntry(e)
    if e.hl then pcall(function() e.hl:Destroy() end) end
    if e.line then pcall(function() e.line:Remove() end) end
    if e.text then pcall(function() e.text:Remove() end) end
end

local function addEmitter(em)
    if tracked[em] or not em:IsA("ParticleEmitter") then return end
    local r = em:GetAttribute("Rarity")
    if type(r) ~= "number" then return end
    tracked[em] = { rarity = r }
end

local function removeEmitter(em)
    local e = tracked[em]
    if e then destroyEntry(e); tracked[em] = nil end
end

for _, em in ipairs(CS:GetTagged("OreSparkle")) do addEmitter(em) end
local c1 = CS:GetInstanceAddedSignal("OreSparkle"):Connect(addEmitter)
local c2 = CS:GetInstanceRemovedSignal("OreSparkle"):Connect(removeEmitter)

local function hide(e)
    if e.hl then e.hl.Enabled = false end
    if e.line then e.line.Visible = false end
    if e.text then e.text.Visible = false end
end

local function ensureDrawings(e)
    if not e.hl then
        local hl = Instance.new("Highlight")
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.FillTransparency = 0.45
        hl.FillColor = colorOf(e.rarity)
        hl.OutlineColor = colorOf(e.rarity)
        hl.Enabled = false
        hl.Parent = guiParent
        e.hl = hl
    end
    if hasDrawing and not e.line then
        local line = Drawing.new("Line")
        line.Thickness = 1.5
        line.Color = colorOf(e.rarity)
        line.Visible = false
        e.line = line
        local text = Drawing.new("Text")
        text.Size = 14
        text.Center = true
        text.Outline = true
        text.Color = colorOf(e.rarity)
        text.Visible = false
        e.text = text
    end
end

-- ===== МЕНЮ (создаём до render, render пишет в инфо-метки) =====
local gui = Instance.new("ScreenGui")
gui.Name = "OreESPMenu"
gui.ResetOnSpawn = false
gui.Parent = guiParent

local fullH = 400
local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(240, fullH)
main.Position = UDim2.new(0, 20, 0.5, -200)
main.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -50, 0, 30)
title.Position = UDim2.fromOffset(10, 0)
title.BackgroundTransparency = 1
title.Text = "Ore ESP"
title.TextColor3 = Color3.new(1, 1, 1)
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = main

local body = Instance.new("Frame")
body.Size = UDim2.new(1, 0, 1, -30)
body.Position = UDim2.fromOffset(0, 30)
body.BackgroundTransparency = 1
body.Parent = main

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.fromOffset(26, 22)
minBtn.Position = UDim2.new(1, -32, 0, 4)
minBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
minBtn.Text = "-"
minBtn.TextColor3 = Color3.new(1, 1, 1)
minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 16
minBtn.Parent = main
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 6)
local minimized = false
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    body.Visible = not minimized
    main.Size = minimized and UDim2.fromOffset(240, 30) or UDim2.fromOffset(240, fullH)
    minBtn.Text = minimized and "+" or "-"
end)

local function makeToggle(text, y, color, default, cb)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, -20, 0, 28)
    b.Position = UDim2.fromOffset(10, y)
    b.BorderSizePixel = 0
    b.Font = Enum.Font.Gotham
    b.TextSize = 14
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Parent = body
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    local on = default
    local function refresh()
        b.Text = (on and "[ON]  " or "[OFF] ") .. text
        b.BackgroundColor3 = on and color or Color3.fromRGB(45, 45, 55)
    end
    refresh()
    b.MouseButton1Click:Connect(function() on = not on; refresh(); cb(on) end)
end

local function makeLabel(y, text, size)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -20, 0, size or 20)
    l.Position = UDim2.fromOffset(10, y)
    l.BackgroundTransparency = 1
    l.TextColor3 = Color3.new(1, 1, 1)
    l.Font = Enum.Font.Gotham
    l.TextSize = 13
    l.TextWrapped = true
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Top
    l.Text = text
    l.Parent = body
    return l
end

local activeSlider = nil
local function makeSlider(y, minV, maxV, init, fmt, onChange)
    local lbl = makeLabel(y, "", 20)
    lbl.TextSize = 14
    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, -20, 0, 14)
    bar.Position = UDim2.fromOffset(10, y + 24)
    bar.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    bar.BorderSizePixel = 0
    bar.Parent = body
    Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 7)
    local fill = Instance.new("Frame")
    fill.BackgroundColor3 = Color3.fromRGB(70, 140, 255)
    fill.BorderSizePixel = 0
    fill.Parent = bar
    Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 7)

    local function set(v)
        v = math.clamp(math.floor(v), minV, maxV)
        lbl.Text = fmt(v)
        fill.Size = UDim2.new((v - minV) / (maxV - minV), 0, 1, 0)
        onChange(v)
    end
    local function fromInput(input)
        local rel = (input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X
        set(minV + math.clamp(rel, 0, 1) * (maxV - minV))
    end
    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            activeSlider = fromInput
            main.Draggable = false
            fromInput(input)
        end
    end)
    set(init)
end

local c3 = UIS.InputChanged:Connect(function(input)
    if activeSlider and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        activeSlider(input)
    end
end)
local c4 = UIS.InputEnded:Connect(function(input)
    if activeSlider and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
        activeSlider = nil
        main.Draggable = true
    end
end)

local y = 4
makeToggle("ESP", y, Color3.fromRGB(60, 160, 90), state.espOn, function(v) state.espOn = v end)
y = y + 32
for _, r in ipairs(RARITY_LIST) do
    makeToggle("Редкость " .. r, y, colorOf(r), state.enabled[r], function(v) state.enabled[r] = v end)
    y = y + 32
end

y = y + 4
makeSlider(y, MIN_DIST, MAX_DIST, state.maxDist,
    function(v) return "Дальность: " .. v .. " м" end,
    function(v) state.maxDist = v end)
y = y + 46

makeToggle("Фильтр по глубине", y, Color3.fromRGB(200, 120, 40), state.depthOn, function(v) state.depthOn = v end)
y = y + 34
makeSlider(y, DEPTH_MIN, DEPTH_MAX, state.depthLo,
    function(v) return "Глубина от: " .. v end,
    function(v) state.depthLo = v end)
y = y + 46
makeSlider(y, DEPTH_MIN, DEPTH_MAX, state.depthHi,
    function(v) return "Глубина до: " .. v end,
    function(v) state.depthHi = v end)
y = y + 46

makeToggle("Автопоиск ближайшей", y, Color3.fromRGB(60, 160, 90), state.autoOn, function(v) state.autoOn = v end)
y = y + 34
local infoDepth = makeLabel(y, "Ты на глубине: ...", 18)
y = y + 20
local infoNearest = makeLabel(y, "Ближайшая: ...", 34)
y = y + 38

local unloadBtn = Instance.new("TextButton")
unloadBtn.Size = UDim2.new(1, -20, 0, 26)
unloadBtn.Position = UDim2.fromOffset(10, y)
unloadBtn.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
unloadBtn.Text = "Выгрузить скрипт"
unloadBtn.TextColor3 = Color3.new(1, 1, 1)
unloadBtn.Font = Enum.Font.Gotham
unloadBtn.TextSize = 13
unloadBtn.Parent = body
Instance.new("UICorner", unloadBtn).CornerRadius = UDim.new(0, 6)
y = y + 34

fullH = y + 36
main.Size = UDim2.fromOffset(240, fullH)
main.Position = UDim2.new(0, 20, 0.5, -math.floor(fullH / 2))

-- ===== РЕНДЕР =====
local function render()
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local origin = root and root.Position or cam.CFrame.Position
    local top = Vector2.new(cam.ViewportSize.X / 2, 0)
    local oy = worldOffsetY()

    infoDepth.Text = "Ты на глубине: " .. math.floor(depthFrom(origin.Y, oy))

    local lo = math.min(state.depthLo, state.depthHi)
    local hi = math.max(state.depthLo, state.depthHi)

    local vis, best = {}, nil
    for em, e in pairs(tracked) do
        local shown = false
        local part = em.Parent
        if part and part:IsA("BasePart") and state.espOn and state.enabled[e.rarity] then
            local pos = part.Position
            local depth = depthFrom(pos.Y, oy)
            if (not state.depthOn) or (depth >= lo and depth <= hi) then
                local item = { e = e, part = part, dist = (pos - origin).Magnitude, depth = depth }
                if not best or item.dist < best.dist then best = item end
                if item.dist <= state.maxDist then
                    table.insert(vis, item)
                    shown = true
                end
            end
        end
        if not shown then hide(e) end
    end

    if best then
        infoNearest.Text = string.format("Ближайшая: редкость %d, %d м, глубина %d",
            best.e.rarity, math.floor(best.dist), math.floor(best.depth))
        if state.autoOn and best.dist > state.maxDist then
            table.insert(vis, best)
        end
    else
        infoNearest.Text = "Ближайшая: нет в загруженной зоне"
    end

    table.sort(vis, function(a, b) return a.dist < b.dist end)

    for i, v in ipairs(vis) do
        local e, part = v.e, v.part
        ensureDrawings(e)
        local isBest = state.autoOn and v == best

        if i <= MAX_HIGHLIGHTS then
            local m = part.Parent
            local target = (m and m:IsA("Model")) and m or part
            if e.hl.Adornee ~= target then e.hl.Adornee = target end
            e.hl.Enabled = true
        else
            e.hl.Enabled = false
        end

        if e.line then
            local sp, onScreen = cam:WorldToViewportPoint(part.Position)
            if onScreen and sp.Z > 0 then
                e.line.Thickness = isBest and 3 or 1.5
                e.line.From = top
                e.line.To = Vector2.new(sp.X, sp.Y)
                e.line.Visible = true
                e.text.Position = Vector2.new(sp.X, sp.Y - 18)
                e.text.Text = string.format("%sР%d | %dм | гл.%d",
                    isBest and "★ " or "", e.rarity, math.floor(v.dist), math.floor(v.depth))
                e.text.Visible = true
            else
                e.line.Visible = false
                e.text.Visible = false
            end
        end
    end
end

-- ===== ЗАПУСК / ВЫГРУЗКА =====
local renderConn = RunService.RenderStepped:Connect(render)

local function unload()
    renderConn:Disconnect()
    c1:Disconnect(); c2:Disconnect(); c3:Disconnect(); c4:Disconnect()
    for _, e in pairs(tracked) do destroyEntry(e) end
    table.clear(tracked)
    gui:Destroy()
    getgenv().OreESPLoaded = nil
end
getgenv().OreESPUnload = unload
unloadBtn.MouseButton1Click:Connect(unload)

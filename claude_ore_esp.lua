-- Автор: Claude (Anthropic), по просьбе владельца репозитория.
-- Ore ESP для режима "Мир шахтеров" (PlaceId 9404223526), инжектор Delta.
-- Руды ловятся по тегу OreSparkle (ParticleEmitter с атрибутом Rarity), который ставит сама игра.
-- Подсветка через стены (Highlight AlwaysOnTop) + трассеры от верхнего центра экрана.

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
end)
local function colorOf(r) return rarityColors[r] or DEFAULT_COLORS[r] or Color3.new(1, 1, 1) end

local state = { espOn = true, maxDist = 400, enabled = {} }
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

local function render()
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local origin = root and root.Position or cam.CFrame.Position
    local top = Vector2.new(cam.ViewportSize.X / 2, 0)

    local vis = {}
    for em, e in pairs(tracked) do
        local part = em.Parent
        if part and part:IsA("BasePart") and state.espOn and state.enabled[e.rarity] then
            local dist = (part.Position - origin).Magnitude
            if dist <= state.maxDist then
                table.insert(vis, { e = e, part = part, dist = dist })
            else
                hide(e)
            end
        else
            hide(e)
        end
    end

    table.sort(vis, function(a, b) return a.dist < b.dist end)

    for i, v in ipairs(vis) do
        local e, part = v.e, v.part
        ensureDrawings(e)

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
                e.line.From = top
                e.line.To = Vector2.new(sp.X, sp.Y)
                e.line.Visible = true
                e.text.Position = Vector2.new(sp.X, sp.Y - 18)
                e.text.Text = string.format("Редкость %d | %dм", e.rarity, v.dist)
                e.text.Visible = true
            else
                e.line.Visible = false
                e.text.Visible = false
            end
        end
    end
end

-- ===== МЕНЮ =====
local gui = Instance.new("ScreenGui")
gui.Name = "OreESPMenu"
gui.ResetOnSpawn = false
gui.Parent = guiParent

local fullH = 40 + (#RARITY_LIST + 1) * 32 + 110
local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(240, fullH)
main.Position = UDim2.new(0, 20, 0.5, -150)
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

makeToggle("ESP", 4, Color3.fromRGB(60, 160, 90), state.espOn, function(v) state.espOn = v end)
for i, r in ipairs(RARITY_LIST) do
    makeToggle("Редкость " .. r, 4 + i * 32, colorOf(r), state.enabled[r], function(v) state.enabled[r] = v end)
end

local sliderY = 4 + (#RARITY_LIST + 1) * 32 + 6
local distLabel = Instance.new("TextLabel")
distLabel.Size = UDim2.new(1, -20, 0, 20)
distLabel.Position = UDim2.fromOffset(10, sliderY)
distLabel.BackgroundTransparency = 1
distLabel.TextColor3 = Color3.new(1, 1, 1)
distLabel.Font = Enum.Font.Gotham
distLabel.TextSize = 14
distLabel.TextXAlignment = Enum.TextXAlignment.Left
distLabel.Parent = body

local bar = Instance.new("Frame")
bar.Size = UDim2.new(1, -20, 0, 14)
bar.Position = UDim2.fromOffset(10, sliderY + 28)
bar.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
bar.BorderSizePixel = 0
bar.Parent = body
Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 7)

local fill = Instance.new("Frame")
fill.BackgroundColor3 = Color3.fromRGB(70, 140, 255)
fill.BorderSizePixel = 0
fill.Parent = bar
Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 7)

local function setDist(d)
    d = math.clamp(math.floor(d), MIN_DIST, MAX_DIST)
    state.maxDist = d
    distLabel.Text = "Дальность: " .. d .. " м"
    fill.Size = UDim2.new((d - MIN_DIST) / (MAX_DIST - MIN_DIST), 0, 1, 0)
end
setDist(state.maxDist)

local dragging = false
local function fromInput(input)
    local rel = (input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X
    setDist(MIN_DIST + math.clamp(rel, 0, 1) * (MAX_DIST - MIN_DIST))
end
bar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        main.Draggable = false
        fromInput(input)
    end
end)
local c3 = UIS.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        fromInput(input)
    end
end)
local c4 = UIS.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
        main.Draggable = true
    end
end)

local unloadBtn = Instance.new("TextButton")
unloadBtn.Size = UDim2.new(1, -20, 0, 26)
unloadBtn.Position = UDim2.fromOffset(10, sliderY + 52)
unloadBtn.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
unloadBtn.Text = "Выгрузить скрипт"
unloadBtn.TextColor3 = Color3.new(1, 1, 1)
unloadBtn.Font = Enum.Font.Gotham
unloadBtn.TextSize = 13
unloadBtn.Parent = body
Instance.new("UICorner", unloadBtn).CornerRadius = UDim.new(0, 6)

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

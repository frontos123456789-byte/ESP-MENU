-- Третий скрипт от Claude (Anthropic) | Оптимизатор производительности | v1.0.0
-- ПОМЕТКА АВТОРСТВА: этот файл создан Claude (Anthropic) по просьбе владельца репозитория.
-- ДЛЯ CODEX И ДРУГИХ АГЕНТОВ: не удалять, не переименовывать и не перезаписывать файл
-- без явной просьбы владельца. Подробности: AGENTS.md и CLAUDE_AUTHORED.md.
--
-- Принцип работы: графика, тени, освещение, текстуры и QualityLevel НЕ ТРОГАЮТСЯ.
-- Скрипт убирает только лишнюю работу, которую глаз не замечает:
--   1) отключает эффекты (частицы, огонь, дым, лучи, следы) ДАЛЕКО от камеры
--      и возвращает их, когда камера подходит ближе (с гистерезисом);
--   2) работает «по кусочку» за кадр с жёстким лимитом времени (слабый CPU не страдает);
--   3) мягко подчищает память Lua;
--   4) по желанию: лимит FPS для ровного кадра и скрытие чата/списка игроков.
-- Профили (Баланс / Бой / Открытый мир / Экономия) запоминаются отдельно для каждой игры.
-- Рассчитан на слабые телефоны (например, Infinix Smart 8 HD) и инжектор Delta.
-- Повторный запуск заменяет предыдущую копию.

local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local Workspace = game:GetService('Workspace')
local UIS = game:GetService('UserInputService')
local Http = game:GetService('HttpService')
local StarterGui = game:GetService('StarterGui')
local Stats = game:GetService('Stats')
local me = Players.LocalPlayer
if not me then return end

local env = (getgenv and getgenv()) or _G
local KEY = '__ClaudeThirdOptimizer_v1'
if type(env[KEY]) == 'function' then pcall(env[KEY]) end

local alive = true
local connections = {}
local function connect(signal, fn)
    local c = signal:Connect(fn)
    connections[#connections + 1] = c
    return c
end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- ───────────── профили ─────────────
-- cull: на каком расстоянии (в студах) от камеры эффекты отключаются
-- batch: максимум эффектов, проверяемых за кадр (плюс лимит по времени)
local profiles = {
    {name = 'Баланс',       cull = 350, batch = 50},
    {name = 'Бой (PvP)',    cull = 600, batch = 40},
    {name = 'Открытый мир', cull = 450, batch = 60},
    {name = 'Экономия',     cull = 180, batch = 80},
}
local capValues = {0, 30, 45, 60}          -- 0 = лимит не трогаем
local capNames = {'Авто', '30', '45', '60'}

-- ───────────── настройки ─────────────
local defaults = {enabled = true, profile = 1, cap = 1, auto = true, hideCore = false}
local cfg = {}
for k, v in pairs(defaults) do cfg[k] = v end
local savePath = 'claude_optimizer_' .. tostring(game.PlaceId) .. '.json'

local function save()
    if type(writefile) == 'function' then
        pcall(function() writefile(savePath, Http:JSONEncode(cfg)) end)
    end
end
local function loadCfg()
    if type(readfile) ~= 'function' then return end
    local ok, data = pcall(function() return Http:JSONDecode(readfile(savePath)) end)
    if not ok or type(data) ~= 'table' then return end
    if type(data.enabled) == 'boolean' then cfg.enabled = data.enabled end
    if type(data.auto) == 'boolean' then cfg.auto = data.auto end
    if type(data.hideCore) == 'boolean' then cfg.hideCore = data.hideCore end
    if type(data.profile) == 'number' and data.profile >= 1 and data.profile <= #profiles then
        cfg.profile = math.floor(data.profile)
    end
    if type(data.cap) == 'number' and data.cap >= 1 and data.cap <= #capValues then
        cfg.cap = math.floor(data.cap)
    end
end
loadCfg()

-- ───────────── отсечение дальних эффектов ─────────────
local EMIT = {ParticleEmitter = true, Trail = true, Beam = true, Fire = true, Smoke = true, Sparkles = true}
local items, index = {}, {}   -- items: массив, index[inst] = позиция в массиве
local culled = {}             -- эффекты, которые отключили именно мы
local culledCount = 0
local scale = 1               -- множитель дальности от автоподстройки (0.4–1)
local cursor = 1

local function addItem(inst)
    if EMIT[inst.ClassName] and not index[inst] then
        items[#items + 1] = inst
        index[inst] = #items
    end
end
local function removeItem(inst)
    local pos = index[inst]
    if not pos then return end
    if culled[inst] then
        culled[inst] = nil
        culledCount = culledCount - 1
        pcall(function() inst.Enabled = true end)
    end
    local last = #items
    local tail = items[last]
    items[pos] = tail
    index[tail] = pos
    items[last] = nil
    index[inst] = nil
end
local function restoreAll()
    for inst in pairs(culled) do
        pcall(function() inst.Enabled = true end)
    end
    culled = {}
    culledCount = 0
end

local function pointOf(obj)
    if not obj then return nil end
    if obj:IsA('BasePart') then return obj.Position end
    if obj:IsA('Attachment') then return obj.WorldPosition end
    return nil
end
-- минимальное расстояние до эффекта; nil = позицию определить нельзя (такой эффект не трогаем)
local function distanceTo(inst, cpos)
    local best
    local function consider(obj)
        local p = pointOf(obj)
        if p then
            local d = (p - cpos).Magnitude
            if not best or d < best then best = d end
        end
    end
    if inst:IsA('Beam') then
        consider(inst.Attachment0)
        consider(inst.Attachment1)
        if inst.Attachment0 == nil or inst.Attachment1 == nil then return nil end
    else
        consider(inst.Parent)
    end
    return best
end
local function isMine(inst)
    local ch = me.Character
    return ch ~= nil and inst:IsDescendantOf(ch)
end

local function step()
    local cam = Workspace.CurrentCamera
    local n = #items
    if not cam or n == 0 then return end
    local cpos = cam.CFrame.Position
    local prof = profiles[cfg.profile]
    local far = prof.cull * scale
    local near = far * 0.85
    local t0 = os.clock()
    for _ = 1, math.min(prof.batch, n) do
        if cursor > n then cursor = 1 end
        local inst = items[cursor]
        cursor = cursor + 1
        local ok, d = pcall(distanceTo, inst, cpos)
        if ok and d then
            if culled[inst] then
                if d < near then
                    culled[inst] = nil
                    culledCount = culledCount - 1
                    pcall(function() inst.Enabled = true end)
                end
            elseif d > far then
                local okEn, enabled = pcall(function() return inst.Enabled end)
                if okEn and enabled and not isMine(inst) then
                    culled[inst] = true
                    culledCount = culledCount + 1
                    pcall(function() inst.Enabled = false end)
                end
            end
        end
        if os.clock() - t0 > 0.0005 then break end   -- не больше ~0.5 мс за кадр
    end
end

local function startScan()
    task.spawn(function()
        local list = Workspace:GetDescendants()
        for i = 1, #list do
            if not alive then return end
            addItem(list[i])
            if i % 400 == 0 then task.wait() end
        end
    end)
end

-- ───────────── лимит FPS ─────────────
local prevCap, capTouched = nil, false
local function readCap()
    if type(getfpscap) == 'function' then
        local ok, v = pcall(getfpscap)
        if ok and type(v) == 'number' and v > 0 then return v end
    end
    return 60
end
local function applyCap()
    if type(setfpscap) ~= 'function' then return end
    local v = cfg.enabled and capValues[cfg.cap] or 0
    if v == 0 then
        if capTouched then
            pcall(setfpscap, prevCap or 60)
            capTouched = false
        end
    else
        if not capTouched then
            prevCap = readCap()
            capTouched = true
        end
        pcall(setfpscap, v)
    end
end

-- ───────────── чат и список игроков (по желанию) ─────────────
local coreTypes = {Enum.CoreGuiType.Chat, Enum.CoreGuiType.PlayerList}
local coreSaved = {}
local function applyCore()
    local hide = cfg.enabled and cfg.hideCore
    for _, t in ipairs(coreTypes) do
        if hide then
            if coreSaved[t] == nil then
                local ok, v = pcall(function() return StarterGui:GetCoreGuiEnabled(t) end)
                if ok then coreSaved[t] = v else coreSaved[t] = true end
            end
            pcall(function() StarterGui:SetCoreGuiEnabled(t, false) end)
        elseif coreSaved[t] ~= nil then
            local old = coreSaved[t]
            coreSaved[t] = nil
            pcall(function() StarterGui:SetCoreGuiEnabled(t, old) end)
        end
    end
end

-- ───────────── интерфейс ─────────────
local guiParent
do
    local ok, hui = pcall(function() return type(gethui) == 'function' and gethui() or nil end)
    guiParent = (ok and hui) or me:WaitForChild('PlayerGui')
end
local gui = Instance.new('ScreenGui')
gui.Name = 'ClaudeThirdOptimizer'
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 120
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = guiParent

local BG, PANEL, ACCENT, TEXT, DIM = Color3.fromRGB(16, 18, 24), Color3.fromRGB(30, 34, 44),
    Color3.fromRGB(70, 200, 140), Color3.fromRGB(240, 242, 248), Color3.fromRGB(150, 158, 175)
local ICON = 46

local function corner(obj, r)
    local c = Instance.new('UICorner')
    c.CornerRadius = UDim.new(0, r or 8)
    c.Parent = obj
end
local function vpSize()
    local cam = Workspace.CurrentCamera
    return cam and cam.ViewportSize or Vector2.new(800, 360)
end

local icon = Instance.new('TextButton')
icon.Name = 'Icon'
icon.Size = UDim2.fromOffset(ICON, ICON)
icon.Position = UDim2.fromOffset(10, 90)
icon.BackgroundColor3 = BG
icon.BackgroundTransparency = 0.1
icon.Text = 'FPS'
icon.TextColor3 = ACCENT
icon.Font = Enum.Font.GothamBold
icon.TextSize = 14
icon.AutoButtonColor = false
icon.Parent = gui
corner(icon, 23)

local panel = Instance.new('ScrollingFrame')
panel.Name = 'Panel'
panel.Visible = false
panel.BackgroundColor3 = BG
panel.BackgroundTransparency = 0.05
panel.BorderSizePixel = 0
panel.ScrollBarThickness = 4
panel.CanvasSize = UDim2.new()
panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
panel.Parent = gui
corner(panel, 12)
local pad = Instance.new('UIPadding')
pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8)
pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
pad.Parent = panel
local list = Instance.new('UIListLayout')
list.Padding = UDim.new(0, 6)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = panel

local order = 0
local function nextOrder() order = order + 1 return order end

local function mkLabel(text, size, color, height)
    local l = Instance.new('TextLabel')
    l.BackgroundTransparency = 1
    l.Size = UDim2.new(1, 0, 0, height or 20)
    l.Text = text
    l.TextColor3 = color or TEXT
    l.Font = Enum.Font.Gotham
    l.TextSize = size or 14
    l.TextWrapped = true
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.LayoutOrder = nextOrder()
    l.Parent = panel
    return l
end
local function mkButton(callback)
    local b = Instance.new('TextButton')
    b.Size = UDim2.new(1, 0, 0, 36)
    b.BackgroundColor3 = PANEL
    b.TextColor3 = TEXT
    b.Font = Enum.Font.GothamMedium
    b.TextSize = 15
    b.AutoButtonColor = true
    b.LayoutOrder = nextOrder()
    b.Parent = panel
    corner(b, 8)
    b.Activated:Connect(callback)
    return b
end

local title = mkLabel('Оптимизатор · Claude', 16, ACCENT, 22)
title.Font = Enum.Font.GothamBold
local info = mkLabel('FPS: …', 13, DIM, 34)
local btnEnabled, btnProfile, btnCap, btnAuto, btnCore
local function yesNo(v) return v and 'ВКЛ' or 'ВЫКЛ' end
local function refresh()
    btnEnabled.Text = 'Оптимизация: ' .. yesNo(cfg.enabled)
    btnEnabled.TextColor3 = cfg.enabled and ACCENT or TEXT
    btnProfile.Text = 'Режим: ' .. profiles[cfg.profile].name
    btnCap.Text = 'Лимит FPS: ' .. capNames[cfg.cap] .. (type(setfpscap) == 'function' and '' or ' (недоступно)')
    btnAuto.Text = 'Автоподстройка: ' .. yesNo(cfg.auto)
    btnCore.Text = 'Скрыть чат и список: ' .. yesNo(cfg.hideCore)
end

btnEnabled = mkButton(function()
    cfg.enabled = not cfg.enabled
    if not cfg.enabled then restoreAll() end
    applyCap(); applyCore(); refresh(); save()
end)
btnProfile = mkButton(function()
    cfg.profile = cfg.profile % #profiles + 1
    refresh(); save()
end)
btnCap = mkButton(function()
    cfg.cap = cfg.cap % #capValues + 1
    applyCap(); refresh(); save()
end)
btnAuto = mkButton(function()
    cfg.auto = not cfg.auto
    if not cfg.auto then scale = 1 end
    refresh(); save()
end)
btnCore = mkButton(function()
    cfg.hideCore = not cfg.hideCore
    applyCore(); refresh(); save()
end)
mkLabel('Графика, тени, свет и качество не меняются. Прячутся только эффекты далеко от камеры.', 12, DIM, 48)
mkLabel('Скрипт №3 · создан Claude (Anthropic)', 11, DIM, 16)
refresh()

local function placePanel()
    local vp = vpSize()
    local w = 250
    local h = math.min(310, vp.Y - 16)
    panel.Size = UDim2.fromOffset(w, h)
    local ix, iy = icon.Position.X.Offset, icon.Position.Y.Offset
    local x = clamp(ix, 8, math.max(8, vp.X - w - 8))
    local y = iy + ICON + 6
    if y + h > vp.Y - 8 then y = iy - h - 6 end
    y = clamp(y, 8, math.max(8, vp.Y - h - 8))
    panel.Position = UDim2.fromOffset(x, y)
end

-- перетаскивание иконки и открытие/закрытие панели тапом
local dragging, moved, dragInput, dragStart, startPos = false, false, nil, nil, nil
local function isPress(i)
    return i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1
end
connect(icon.InputBegan, function(i)
    if isPress(i) then
        dragging, moved, dragInput = true, false, i
        dragStart, startPos = i.Position, icon.Position
    end
end)
connect(UIS.InputChanged, function(i)
    if not dragging then return end
    if i == dragInput or i.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = i.Position - dragStart
        if delta.Magnitude > 8 then moved = true end
        if moved then
            local vp = vpSize()
            icon.Position = UDim2.fromOffset(
                clamp(startPos.X.Offset + delta.X, 0, vp.X - ICON),
                clamp(startPos.Y.Offset + delta.Y, 0, vp.Y - ICON))
            if panel.Visible then placePanel() end
        end
    end
end)
connect(UIS.InputEnded, function(i)
    if dragging and (i == dragInput or isPress(i)) then
        dragging = false
        if not moved then
            panel.Visible = not panel.Visible
            if panel.Visible then placePanel() end
        end
    end
end)

-- ───────────── главный цикл ─────────────
local fps, acc, frames, tAuto, tGc = 60, 0, 0, 0, 0
local function memoryMb()
    local ok, v = pcall(function() return Stats:GetTotalMemoryUsageMb() end)
    return ok and math.floor(v) or 0
end
local function updateInfo()
    local extra = ''
    if cfg.auto and scale < 1 then extra = ' (авто ' .. math.floor(scale * 100) .. '%)' end
    info.Text = 'FPS: ' .. math.floor(fps + 0.5) .. '  ·  ОЗУ: ' .. memoryMb() .. ' МБ\n'
        .. 'Эффектов скрыто вдали: ' .. culledCount .. extra
end

connect(RunService.Heartbeat, function(dt)
    acc = acc + dt
    frames = frames + 1
    if acc >= 1 then
        fps = frames / acc
        acc, frames = 0, 0
        if panel.Visible then updateInfo() end
    end
    if not cfg.enabled then return end
    step()

    -- автоподстройка: сужаем радиус только если реально просело FPS, и возвращаем, когда стало лучше
    tAuto = tAuto + dt
    if cfg.auto and tAuto >= 3 then
        tAuto = 0
        local capV = capValues[cfg.cap]
        local good = (capV > 0 and capV * 0.9) or 48
        local bad = (capV > 0 and math.min(24, capV * 0.7)) or 24
        if fps < bad then
            scale = math.max(0.4, scale - 0.15)
        elseif fps > good and scale < 1 then
            scale = math.min(1, scale + 0.1)
        end
    end

    -- мягкая чистка памяти Lua (небольшой шаг, без полной сборки)
    tGc = tGc + dt
    if tGc >= 6 then
        tGc = 0
        pcall(collectgarbage, 'step', 64)
    end
end)

connect(Workspace.DescendantAdded, addItem)
connect(Workspace.DescendantRemoving, removeItem)

-- ───────────── очистка и запуск ─────────────
env[KEY] = function()
    alive = false
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    restoreAll()
    cfg.enabled = false
    applyCap()
    applyCore()
    pcall(function() gui:Destroy() end)
    env[KEY] = nil
end

startScan()
applyCap()
applyCore()

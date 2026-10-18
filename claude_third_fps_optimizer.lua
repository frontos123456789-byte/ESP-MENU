-- Третий скрипт от Claude (Anthropic) | Оптимизатор производительности | v1.2.0
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
--   4) по желанию: лимит FPS для ровного кадра и скрытие чата/списка игроков;
--   5) режим диагностики (v1.1.0): пишет каждую просадку FPS вместе с ОЗУ, числом объектов
--      и игроков, чтобы понять, что именно тормозит. Отчёт: файл + буфер обмена.
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

-- ───────────── диагностика ─────────────
-- Просадка = FPS ниже 20 за секунду или один кадр дольше 250 мс (фриз).
-- Раз в 30 с пишется и «нормальная» строка — для сравнения с просадками.
local diagPath = 'claude_optimizer_diag_' .. tostring(game.PlaceId) .. '.txt'
local function newAgg() return {n = 0, fps = 0, ram = 0, inst = 0, players = 0, emit = 0} end
local diag = {on = false, lines = {}, maxdt = 0, t0 = os.clock(), lastOk = -1e9, lastSave = 0,
    agg = {ok = newAgg(), dip = newAgg()}, worstFps = 1e9, worstFrame = 0,
    tickMax = 0, stepMax = 0}   -- tickMax/stepMax: сколько мс максимум отнимает сам скрипт
local function resetDiag()
    diag.lines, diag.maxdt, diag.t0, diag.lastOk, diag.lastSave = {}, 0, os.clock(), -1e9, os.clock()
    diag.agg = {ok = newAgg(), dip = newAgg()}
    diag.worstFps, diag.worstFrame = 1e9, 0
    diag.tickMax, diag.stepMax = 0, 0
end
-- память читается не чаще раза в секунду (вызов бывает заметно дорогим на слабом телефоне)
local memT, memV = -1e9, 0
local function memoryMb()
    local now = os.clock()
    if now - memT < 0.9 then return memV end
    local ok, v = pcall(function() return Stats:GetTotalMemoryUsageMb() end)
    memV = ok and math.floor(v) or 0
    memT = now
    return memV
end
local function stat(name)
    local ok, v = pcall(function() return Stats[name] end)
    if ok and type(v) == 'number' then return v end
    return nil
end
local function fmt(v, d)
    if v == nil then return '?' end
    d = d or 1
    return tostring(math.floor(v * d + 0.5) / d)
end
local function avg(a, k)
    if a.n == 0 then return nil end
    return a[k] / a.n
end

local saveFile   -- объявлена заранее: используется в diagSample, определяется ниже

local function diagSample(fpsNow)
    local ram = memoryMb()
    local inst, prims = stat('InstanceCount'), stat('PrimitivesCount')
    local hb, phys = stat('HeartbeatTimeMs'), stat('PhysicsStepTimeMs')
    local players, emitters = #Players:GetPlayers(), #items
    local dip = fpsNow < 20 or diag.maxdt > 0.25
    local a = dip and diag.agg.dip or diag.agg.ok
    a.n = a.n + 1
    a.fps = a.fps + fpsNow
    a.ram = a.ram + ram
    a.inst = a.inst + (inst or 0)
    a.players = a.players + players
    a.emit = a.emit + emitters
    if fpsNow < diag.worstFps then diag.worstFps = fpsNow end
    if diag.maxdt > diag.worstFrame then diag.worstFrame = diag.maxdt end
    local now = os.clock()
    if dip or now - diag.lastOk >= 30 then
        if not dip then diag.lastOk = now end
        diag.lines[#diag.lines + 1] = string.format(
            '[%4d с] %s fps=%d кадр_макс=%d мс ОЗУ=%d МБ объектов=%s примитивов=%s Heartbeat=%s мс Физика=%s мс игроков=%d эффектов=%d скрыто=%d радиус=%d%% профиль=%s',
            math.floor(now - diag.t0), dip and 'ПРОСАДКА' or 'норма   ',
            math.floor(fpsNow + 0.5), math.floor(diag.maxdt * 1000 + 0.5), ram,
            fmt(inst), fmt(prims), fmt(hb, 10), fmt(phys, 10), players, emitters, culledCount,
            math.floor(scale * 100 + 0.5), profiles[cfg.profile].name)
        if #diag.lines > 400 then table.remove(diag.lines, 1) end
    end
    diag.maxdt = 0
    -- автосохранение раз в минуту: на слабом телефоне игру могут закрыть системой в любой момент
    if now - diag.lastSave >= 60 then
        diag.lastSave = now
        saveFile()
    end
end

local function buildReport(maxLines)
    local ag, out = diag.agg, {}
    out[#out + 1] = '=== Отчёт оптимизатора Claude v1.2.0 ==='
    out[#out + 1] = 'PlaceId=' .. tostring(game.PlaceId) .. ' | запись ' .. math.floor(os.clock() - diag.t0)
        .. ' с | устройство: ' .. (UIS.TouchEnabled and 'сенсорное' or 'ПК')
        .. ' | оптимизация: ' .. (cfg.enabled and 'ВКЛ' or 'ВЫКЛ')
    out[#out + 1] = 'Нагрузка самого скрипта: секундный тик до ' .. fmt(diag.tickMax, 10)
        .. ' мс, шаг отсечения до ' .. fmt(diag.stepMax, 10) .. ' мс'
    out[#out + 1] = 'Просадок: ' .. ag.dip.n .. ' | нормальных секунд: ' .. ag.ok.n
    out[#out + 1] = 'Худший FPS: ' .. fmt(diag.worstFps < 1e9 and diag.worstFps or nil)
        .. ' | самый долгий кадр: ' .. fmt(diag.worstFrame * 1000) .. ' мс'
    local names = {fps = 'FPS', ram = 'ОЗУ, МБ', inst = 'объектов', players = 'игроков', emit = 'эффектов'}
    for _, k in ipairs({'fps', 'ram', 'inst', 'players', 'emit'}) do
        out[#out + 1] = 'В среднем ' .. names[k] .. ': при просадках ' .. fmt(avg(ag.dip, k))
            .. ' | в норме ' .. fmt(avg(ag.ok, k))
    end
    out[#out + 1] = '--- записи ---'
    local from = 1
    if maxLines and #diag.lines > maxLines then from = #diag.lines - maxLines + 1 end
    for i = from, #diag.lines do out[#out + 1] = diag.lines[i] end
    return table.concat(out, '\n')
end
saveFile = function()
    if type(writefile) ~= 'function' then return false end
    return (pcall(writefile, diagPath, buildReport(nil)))
end
-- файл — полный отчёт; в буфер обмена — сводка и последние 60 записей (чтобы удобно вставить в чат)
local function exportReport()
    local saved = saveFile()
    local copied = false
    if type(setclipboard) == 'function' then
        copied = (pcall(setclipboard, buildReport(60)))
    end
    return saved, copied
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
panel.BackgroundTransparency = 0.15
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

-- шапка: заголовок и крупная кнопка «Закрыть»
local header = Instance.new('Frame')
header.BackgroundTransparency = 1
header.Size = UDim2.new(1, 0, 0, 32)
header.LayoutOrder = nextOrder()
header.Parent = panel
local title = mkLabel('Оптимизатор', 16, ACCENT, 22)
title.Font = Enum.Font.GothamBold
title.Parent = header
title.Size = UDim2.new(1, -86, 1, 0)
local closeBtn = Instance.new('TextButton')
closeBtn.AnchorPoint = Vector2.new(1, 0.5)
closeBtn.Position = UDim2.new(1, 0, 0.5, 0)
closeBtn.Size = UDim2.fromOffset(80, 30)
closeBtn.BackgroundColor3 = Color3.fromRGB(150, 60, 60)
closeBtn.Text = 'Закрыть'
closeBtn.TextColor3 = TEXT
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 14
closeBtn.Parent = header
corner(closeBtn, 8)
closeBtn.Activated:Connect(function() panel.Visible = false end)
local info = mkLabel('FPS: …', 13, DIM, 34)
local btnEnabled, btnProfile, btnCap, btnAuto, btnCore, btnDiag, btnReport, diagInfo
local function yesNo(v) return v and 'ВКЛ' or 'ВЫКЛ' end
local function refresh()
    btnEnabled.Text = 'Оптимизация: ' .. yesNo(cfg.enabled)
    btnEnabled.TextColor3 = cfg.enabled and ACCENT or TEXT
    btnProfile.Text = 'Режим: ' .. profiles[cfg.profile].name
    btnCap.Text = 'Лимит FPS: ' .. capNames[cfg.cap] .. (type(setfpscap) == 'function' and '' or ' (недоступно)')
    btnAuto.Text = 'Автоподстройка: ' .. yesNo(cfg.auto)
    btnCore.Text = 'Скрыть чат и список: ' .. yesNo(cfg.hideCore)
    btnDiag.Text = 'Диагностика: ' .. yesNo(diag.on)
    btnDiag.TextColor3 = diag.on and ACCENT or TEXT
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
btnDiag = mkButton(function()
    diag.on = not diag.on
    if diag.on then
        resetDiag()
        diagInfo.Text = 'Идёт запись. Поиграй 5–10 минут, затем нажми «Скопировать отчёт».'
        panel.Visible = false   -- не мешаем игре: FPS виден на кнопке, меню открывается тапом по ней
    else
        saveFile()
        diagInfo.Text = 'Запись остановлена, отчёт сохранён в файл.'
    end
    refresh()
end)
btnReport = mkButton(function()
    if diag.agg.ok.n + diag.agg.dip.n == 0 then
        diagInfo.Text = 'Данных пока нет: включи диагностику и поиграй.'
        return
    end
    local saved, copied = exportReport()
    diagInfo.Text = (copied and 'Отчёт скопирован в буфер обмена. ' or 'Буфер обмена недоступен. ')
        .. (saved and ('Файл: ' .. diagPath) or 'Файл сохранить не удалось.')
end)
btnReport.Text = 'Скопировать отчёт'
diagInfo = mkLabel('Диагностика выключена.', 12, DIM, 48)
mkLabel('Графика, тени, свет и качество не меняются. Прячутся только эффекты далеко от камеры.', 12, DIM, 48)
mkLabel('Скрипт №3 · создан Claude (Anthropic)', 11, DIM, 16)
refresh()

local function placePanel()
    local vp = vpSize()
    local w = 230
    local h = math.min(250, math.floor(vp.Y * 0.66))
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
        if delta.Magnitude > 14 then moved = true end   -- запас на дрожание пальца: тап не считается перетаскиванием
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
local fps, acc, frames, tAuto, tGc, iconT = 60, 0, 0, 0, 0, 0
local function updateInfo()
    local extra = ''
    if cfg.auto and scale < 1 then extra = ' (авто ' .. math.floor(scale * 100) .. '%)' end
    info.Text = 'FPS: ' .. math.floor(fps + 0.5) .. '  ·  ОЗУ: ' .. memoryMb() .. ' МБ\n'
        .. 'Эффектов скрыто вдали: ' .. culledCount .. extra
    if diag.on then
        diagInfo.Text = 'Запись: ' .. math.floor(os.clock() - diag.t0) .. ' с · просадок: '
            .. diag.agg.dip.n .. ' · нормальных секунд: ' .. diag.agg.ok.n
    end
end

connect(RunService.Heartbeat, function(dt)
    acc = acc + dt
    frames = frames + 1
    if diag.on and dt > diag.maxdt then diag.maxdt = dt end
    if acc >= 1 then
        fps = frames / acc
        acc, frames = 0, 0
        local ts = os.clock()
        if diag.on then diagSample(fps) end   -- диагностика работает и при выключенной оптимизации
        if panel.Visible then updateInfo() end
        iconT = iconT + 1
        if iconT >= 2 then   -- подпись на кнопке обновляем раз в 2 с, чтобы не тратить кадры зря
            iconT = 0
            icon.Text = tostring(math.floor(fps + 0.5))
            icon.TextColor3 = fps >= 40 and ACCENT
                or (fps >= 25 and Color3.fromRGB(235, 200, 80) or Color3.fromRGB(235, 100, 90))
        end
        if diag.on then
            local ms = (os.clock() - ts) * 1000
            if ms > diag.tickMax then diag.tickMax = ms end
        end
    end
    if not cfg.enabled then return end
    local t1 = os.clock()
    step()
    if diag.on then
        local ms = (os.clock() - t1) * 1000
        if ms > diag.stepMax then diag.stepMax = ms end
    end

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
    if diag.on and #diag.lines > 0 then pcall(saveFile) end
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

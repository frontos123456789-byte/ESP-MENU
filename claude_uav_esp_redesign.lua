-- БПЛА ESP — редизайн интерфейса (Claude, по просьбе владельца репозитория).
-- Логика распознавания, тревог и сохранения настроек взята из uav_esp.lua без изменений,
-- переделан внешний вид: тема, меню с секциями/тумблерами/степперами, метки, стрелки, радар.
-- Распознавание по именам объектов. Запускать один раз за сессию: повторный запуск заменяет предыдущий.
local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local UserInputService=game:GetService('UserInputService')
local TweenService = game:GetService('TweenService')

-- Единая тема: все цвета, шрифты и скругления берутся только отсюда.
local Theme = {
    bg        = Color3.fromRGB(14,17,24),
    surface   = Color3.fromRGB(24,29,40),
    surfaceHi = Color3.fromRGB(38,46,62),
    stroke    = Color3.fromRGB(58,68,90),
    text      = Color3.fromRGB(236,240,247),
    textDim   = Color3.fromRGB(143,154,176),
    accent    = Color3.fromRGB(0,190,255),
    ok        = Color3.fromRGB(64,220,120),
    warn      = Color3.fromRGB(255,184,48),
    danger    = Color3.fromRGB(235,70,70),
    kind = {
        uav     = Color3.fromRGB(0,190,255),
        interceptor = Color3.fromRGB(64,220,120),
        drone   = Color3.fromRGB(255,184,48),
        missile = Color3.fromRGB(255,82,82),
    },
    font     = Enum.Font.GothamMedium,
    fontBold = Enum.Font.GothamBold,
    fontMono = Enum.Font.RobotoMono,
    radius   = UDim.new(0,10),
    tween    = TweenInfo.new(0.18,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
}
local player = Players.LocalPlayer
local parent = player:WaitForChild('PlayerGui')
local previous = parent:FindFirstChild('UAV_ESP_Menu')
if previous then previous:Destroy() end

local gui = Instance.new('ScreenGui')
gui.Name = 'UAV_ESP_Menu'
gui.ResetOnSpawn = false
gui.DisplayOrder = 100
gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
gui.Parent = parent
local alive, automatic, calibrating = true, false, false
local distance, averageDt, elapsed, adjustTime = 1500, 1/60, 0, 0
local enabled = {drone = false, missile = false, interceptor = false, uav = false}
local HttpService=game:GetService('HttpService')
local prefs={dotSize=4,outlineTransparency=0.2,showSpeed=true,showDistance=true,arrows=true,alerts=true,alertMeters=200,showDirection=true,radar=true,radarMeters=300,radarSize=150,radarTransparency=0.25,showEta=true,showLead=true,threat=true,positions={menu={x=0,y=0},counter={x=1,y=0},radar={x=1,y=0.2}}}
local settingsFile='uav_esp_settings_'..tostring(game.PlaceId)..'.json'
local persistenceMessage='Настройки: только текущая сессия'
local function finite(value,low,high)
    return type(value)=='number' and value==value and value>=low and value<=high
end
local function restoreSettings(data)
    if type(data)~='table' or data.version~=1 then return false end
    if type(data.prefs)=='table' then
        for key in pairs(prefs) do
            local value=data.prefs[key]
            if type(prefs[key])=='boolean' and type(value)=='boolean' then prefs[key]=value end
        end
        if finite(data.prefs.dotSize,2,8) then prefs.dotSize=math.floor(data.prefs.dotSize+0.5) end
        if finite(data.prefs.outlineTransparency,0,1) then prefs.outlineTransparency=data.prefs.outlineTransparency end
        if finite(data.prefs.alertMeters,50,1000) then prefs.alertMeters=math.floor(data.prefs.alertMeters) end
    end
    if type(data.prefs)=='table' then
        if finite(data.prefs.radarMeters,100,1000) then prefs.radarMeters=math.floor(data.prefs.radarMeters) end
        if finite(data.prefs.radarSize,120,240) then prefs.radarSize=math.floor(data.prefs.radarSize) end
        if finite(data.prefs.radarTransparency,0,0.9) then prefs.radarTransparency=data.prefs.radarTransparency end
        if type(data.prefs.positions)=='table' then
            for _,key in ipairs({'menu','counter','radar'}) do
                local pos=data.prefs.positions[key]
                if type(pos)=='table' and finite(pos.x,0,1) and finite(pos.y,0,1) then prefs.positions[key]={x=pos.x,y=pos.y} end
            end
        end
    end
    if finite(data.distance,300,5000) then distance=math.floor(data.distance) end
    if type(data.automatic)=='boolean' then automatic=data.automatic end
    if type(data.enabled)=='table' then
        for key in pairs(enabled) do if type(data.enabled[key])=='boolean' then enabled[key]=data.enabled[key] end end
    end
    return true
end
if type(readfile)=='function' then
    local ok,data=pcall(function()
        local raw=readfile(settingsFile)
        if type(raw)~='string' or #raw>16384 then return nil end
        return HttpService:JSONDecode(raw)
    end)
    if ok and restoreSettings(data) then persistenceMessage='Сохранённые настройки загружены' end
end
local settingsStatus
local saveQueued=false
local settingsDirty=false
local function saveNow()
    local saved=false
    if type(writefile)~='function' then persistenceMessage='Запись недоступна: настройки на эту сессию'
    else
        local ok=pcall(function()
            writefile(settingsFile,HttpService:JSONEncode({version=1,prefs=prefs,enabled=enabled,distance=distance,automatic=automatic}))
        end)
        saved=ok
        persistenceMessage=ok and 'Настройки сохранены на устройстве' or 'Не удалось сохранить настройки'
    end
    settingsDirty=not saved and type(writefile)=='function'
    if settingsStatus and settingsStatus.Parent then settingsStatus.Text=persistenceMessage end
end
local function changed()
    settingsDirty=true
    if saveQueued then return end
    saveQueued=true
    task.delay(1,function()
        saveQueued=false
        if alive then saveNow() end
    end)
end

local candidates, marks, connections = {}, {}, {}
local roster,rosterSet={},{}
local outlines, speedLabels, motion = {}, {}, {}
local downState = {}
local threat, leadLines, topThreat = {}, {}, nil
local uiRefresh = {}
local function refreshAll() for _, fn in ipairs(uiRefresh) do fn() end end
local interceptor -- объявлено заранее: используется в displayKind, определяется ниже
local METERS_PER_STUD = 0.28
local OUTLINE_LIMIT = 30 -- Roblox рисует ограниченное число Highlight одновременно
local outlineCount = 0
local names = {drone = 'Дрон', missile = 'Ракета', interceptor = 'Перехватчик', uav = 'БПЛА'}
-- Add exact object names here if the game uses different names.
local patterns = {
    interceptor = {'stinger', 'interceptor', 'перехват', 'Перехват', 'ПЕРЕХВАТ'},
    missile = {'missile', 'rocket', 'guided', 'ракет', 'Ракет', 'РАКЕТ', 'управляем', 'Управляем'},
    drone = {'drone', 'fpv', 'дрон', 'Дрон', 'ДРОН'},
    uav = {'uav', 'ucav', 'shahed', 'geran', 'lancet', 'бпла', 'БПЛА', 'шахед', 'Шахед', 'Герань', 'Ланцет'},
}
local function targetPart(object)
    if not object or not object:IsDescendantOf(workspace) then return end
    if object:IsA('Model') then
        if object:FindFirstChildOfClass('Humanoid') then return end
        return object.PrimaryPart or object:FindFirstChildWhichIsA('BasePart',true)
    elseif object:IsA('BasePart') then return object end
end
local function blockedAncestor(object,character)
    local ancestor=object.Parent
    while ancestor and ancestor~=workspace do
        if ancestor==character or ancestor:IsA('Tool') then return true end
        if ancestor:IsA('Model') and ancestor:FindFirstChildOfClass('Humanoid') then return true end
        ancestor=ancestor.Parent
    end
    return false
end
local function classify(object)
    if not (object:IsA('Model') or object:IsA('BasePart')) then return end
    local name = string.lower(object.Name)
    for _, kind in ipairs({'interceptor', 'missile', 'drone', 'uav'}) do
        for _, word in ipairs(patterns[kind]) do
            if string.find(name, word, 1, true) then return kind end
        end
    end
end
local function register(object)
    local kind = classify(object)
    if kind then candidates[object] = kind end
end
local function clearMark(object)
    if outlines[object] then outlines[object]:Destroy(); outlines[object] = nil; outlineCount = outlineCount - 1 end
    if speedLabels[object] then speedLabels[object]:Destroy(); speedLabels[object] = nil end
    motion[object] = nil
    threat[object] = nil
    if leadLines[object] then leadLines[object]:Destroy(); leadLines[object] = nil end
    if marks[object] then marks[object]:Destroy(); marks[object] = nil end
end
local function cleanup()
    if not alive then return end
    alive = false
    if settingsDirty then saveNow() end
    for _, connection in ipairs(connections) do connection:Disconnect() end
    for object in pairs(marks) do clearMark(object) end
    table.clear(candidates)
end
gui.Destroying:Connect(cleanup)

-- ================= Корневой контейнер и меню =================
-- Safe-area root automatically follows rotation, viewport size and device insets.
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
local root = Instance.new('Frame')
root.Size = UDim2.fromScale(1,1)
root.BackgroundTransparency = 1
root.Parent = gui

local function addCorner(object, radius)
    local c = Instance.new('UICorner')
    c.CornerRadius = radius or Theme.radius
    c.Parent = object
    return c
end
local function addStroke(object, color, transparency, thickness)
    local s = Instance.new('UIStroke')
    s.Color = color
    s.Transparency = transparency or 0
    s.Thickness = thickness or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = object
    return s
end
local function newText(parent, text, size, color, font)
    local t = Instance.new('TextLabel')
    t.BackgroundTransparency = 1
    t.Text = text
    t.TextSize = size or 14
    t.TextColor3 = color or Theme.text
    t.Font = font or Theme.font
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.TextWrapped = true
    t.Parent = parent
    return t
end
local function newRow(parent, height, asButton)
    local item = Instance.new(asButton and 'TextButton' or 'Frame')
    item.Size = UDim2.new(1,0,0,height or 44)
    item.BackgroundColor3 = Theme.surface
    item.BorderSizePixel = 0
    if asButton then
        item.Text = ''
        item.AutoButtonColor = false
    end
    item.Parent = parent
    addCorner(item, UDim.new(0,8))
    return item
end

local panel = Instance.new('Frame')
panel.Position = UDim2.fromOffset(8,8)
panel.BackgroundColor3 = Theme.bg
panel.BackgroundTransparency = 0.04
panel.BorderSizePixel = 0
panel.ClipsDescendants = true
panel.ZIndex = 30
panel.Parent = root
addCorner(panel, UDim.new(0,14))
addStroke(panel, Theme.stroke, 0.2, 1)
local accentBar = Instance.new('Frame')
accentBar.Size = UDim2.new(1,0,0,2)
accentBar.BackgroundColor3 = Theme.accent
accentBar.BorderSizePixel = 0
accentBar.ZIndex = 31
accentBar.Parent = panel

local toggle = Instance.new('TextButton')
toggle.Size = UDim2.fromOffset(48,48)
toggle.Position = UDim2.fromOffset(8,8)
toggle.Text = 'ESP'
toggle.TextSize = 14
toggle.Font = Theme.fontBold
toggle.TextColor3 = Theme.accent
toggle.BackgroundColor3 = Theme.bg
toggle.BackgroundTransparency = 0.05
toggle.AutoButtonColor = false
toggle.Visible = false
toggle.ZIndex = 30
toggle.Parent = root
addCorner(toggle, UDim.new(1,0))
addStroke(toggle, Theme.accent, 0.3, 1.5)

local dragHeader = newText(panel, 'БПЛА · ESP', 16, Theme.text, Theme.fontBold)
dragHeader.Size = UDim2.new(1,-56,0,48)
dragHeader.Position = UDim2.fromOffset(0,2)
local headerPad = Instance.new('UIPadding', dragHeader)
headerPad.PaddingLeft = UDim.new(0,14)
local dragHint = newText(dragHeader, 'перетащи', 11, Theme.textDim)
dragHint.Size = UDim2.new(1,-14,1,0)
dragHint.TextXAlignment = Enum.TextXAlignment.Right
local close = Instance.new('TextButton')
close.Size = UDim2.fromOffset(36,36)
close.Position = UDim2.new(1,-44,0,8)
close.Text = '—'
close.TextSize = 16
close.Font = Theme.fontBold
close.TextColor3 = Theme.textDim
close.BackgroundColor3 = Theme.surface
close.AutoButtonColor = true
close.BorderSizePixel = 0
close.Parent = panel
addCorner(close, UDim.new(0,8))
close.Activated:Connect(function()
    panel.Visible = false
    toggle.Visible = true
end)
toggle.Activated:Connect(function()
    panel.Visible = true
    toggle.Visible = false
end)

local body = Instance.new('ScrollingFrame')
body.Position = UDim2.fromOffset(0,54)
body.Size = UDim2.new(1,0,1,-58)
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.ScrollBarThickness = 3
body.ScrollBarImageColor3 = Theme.stroke
body.ScrollingDirection = Enum.ScrollingDirection.Y
body.AutomaticCanvasSize = Enum.AutomaticSize.Y
body.CanvasSize = UDim2.new()
body.Parent = panel
local bodyPad = Instance.new('UIPadding', body)
bodyPad.PaddingLeft = UDim.new(0,10)
bodyPad.PaddingRight = UDim.new(0,12)
bodyPad.PaddingTop = UDim.new(0,2)
bodyPad.PaddingBottom = UDim.new(0,12)
local layout = Instance.new('UIListLayout', body)
layout.Padding = UDim.new(0,10)
layout.SortOrder = Enum.SortOrder.LayoutOrder

local function fitPanel()
    panel.Size = UDim2.fromOffset(math.min(300,math.max(1,root.AbsoluteSize.X-16)),
        math.min(540,math.max(1,root.AbsoluteSize.Y-16)))
end
table.insert(connections,root:GetPropertyChangedSignal('AbsoluteSize'):Connect(fitPanel))
fitPanel()

-- ---------- Компоненты ----------
local sectionOrder = 0
local function makeSection(title, openByDefault)
    sectionOrder = sectionOrder + 1
    local holder = Instance.new('Frame')
    holder.BackgroundTransparency = 1
    holder.Size = UDim2.new(1,0,0,0)
    holder.AutomaticSize = Enum.AutomaticSize.Y
    holder.LayoutOrder = sectionOrder
    holder.Parent = body
    local list = Instance.new('UIListLayout', holder)
    list.Padding = UDim.new(0,6)
    list.SortOrder = Enum.SortOrder.LayoutOrder

    local header = Instance.new('TextButton')
    header.Size = UDim2.new(1,0,0,26)
    header.BackgroundTransparency = 1
    header.Text = ''
    header.LayoutOrder = 0
    header.Parent = holder
    local titleLabel = newText(header, title, 12, Theme.accent, Theme.fontBold)
    titleLabel.Size = UDim2.new(1,-24,1,0)
    titleLabel.Position = UDim2.fromOffset(4,0)
    local chevron = newText(header, '', 14, Theme.textDim, Theme.fontBold)
    chevron.Size = UDim2.new(0,20,1,0)
    chevron.Position = UDim2.new(1,-20,0,0)
    chevron.TextXAlignment = Enum.TextXAlignment.Center

    local content = Instance.new('Frame')
    content.BackgroundTransparency = 1
    content.Size = UDim2.new(1,0,0,0)
    content.AutomaticSize = Enum.AutomaticSize.Y
    content.LayoutOrder = 1
    content.Parent = holder
    local contentList = Instance.new('UIListLayout', content)
    contentList.Padding = UDim.new(0,6)
    contentList.SortOrder = Enum.SortOrder.LayoutOrder

    local open = openByDefault ~= false
    local function render()
        content.Visible = open
        chevron.Text = open and '▾' or '▸'
    end
    header.Activated:Connect(function() open = not open; render() end)
    render()
    return content
end

-- Тумблер. Возвращает: строка, подпись, функция перерисовки.
local function makeToggle(parent, title, get, set, tagColor)
    local rowF = newRow(parent, 44, true)
    local label = newText(rowF, title, 14)
    label.Position = UDim2.fromOffset(tagColor and 26 or 14, 0)
    label.Size = UDim2.new(1,(tagColor and -26 or -14)-62,1,0)
    if tagColor then
        local tag = Instance.new('Frame')
        tag.AnchorPoint = Vector2.new(0,0.5)
        tag.Position = UDim2.new(0,12,0.5,0)
        tag.Size = UDim2.fromOffset(4,20)
        tag.BackgroundColor3 = tagColor
        tag.BorderSizePixel = 0
        tag.Parent = rowF
        addCorner(tag, UDim.new(1,0))
    end
    local track = Instance.new('Frame')
    track.AnchorPoint = Vector2.new(1,0.5)
    track.Position = UDim2.new(1,-12,0.5,0)
    track.Size = UDim2.fromOffset(44,24)
    track.BorderSizePixel = 0
    track.BackgroundColor3 = Theme.stroke
    track.Parent = rowF
    addCorner(track, UDim.new(1,0))
    local knob = Instance.new('Frame')
    knob.AnchorPoint = Vector2.new(0,0.5)
    knob.Size = UDim2.fromOffset(18,18)
    knob.Position = UDim2.fromOffset(3,12)
    knob.BackgroundColor3 = Color3.new(1,1,1)
    knob.BorderSizePixel = 0
    knob.Parent = track
    addCorner(knob, UDim.new(1,0))
    local shown
    local function render(animate)
        local on = get() and true or false
        if shown == on then return end
        shown = on
        local trackColor = on and Theme.accent or Theme.stroke
        local knobPosition = UDim2.fromOffset(on and 23 or 3,12)
        if animate then
            TweenService:Create(track, Theme.tween, {BackgroundColor3 = trackColor}):Play()
            TweenService:Create(knob, Theme.tween, {Position = knobPosition}):Play()
        else
            track.BackgroundColor3 = trackColor
            knob.Position = knobPosition
        end
    end
    rowF.Activated:Connect(function()
        set(not get())
        render(true)
    end)
    render(false)
    table.insert(uiRefresh, function() render(true) end)
    return rowF, label, render
end

-- Степпер: [−] значение [+]. step(dir) меняет значение, getText() возвращает подпись.
local function makeStepper(parent, title, getText, step)
    local rowF = newRow(parent, 48, false)
    local label = newText(rowF, title, 14)
    label.Position = UDim2.fromOffset(14,0)
    label.Size = UDim2.new(1,-156,1,0)
    local function stepButton(text, xOffset)
        local b = Instance.new('TextButton')
        b.AnchorPoint = Vector2.new(1,0.5)
        b.Position = UDim2.new(1,xOffset,0.5,0)
        b.Size = UDim2.fromOffset(32,32)
        b.Text = text
        b.TextSize = 18
        b.Font = Theme.fontBold
        b.TextColor3 = Theme.text
        b.BackgroundColor3 = Theme.surfaceHi
        b.AutoButtonColor = true
        b.BorderSizePixel = 0
        b.Parent = rowF
        addCorner(b, UDim.new(0,8))
        return b
    end
    local plus = stepButton('+', -10)
    local value = newText(rowF, '', 13, Theme.accent, Theme.fontMono)
    value.AnchorPoint = Vector2.new(1,0.5)
    value.Position = UDim2.new(1,-46,0.5,0)
    value.Size = UDim2.fromOffset(66,32)
    value.TextXAlignment = Enum.TextXAlignment.Center
    value.TextWrapped = false
    local minus = stepButton('−', -116)
    local function refresh() value.Text = getText() end
    table.insert(uiRefresh, refresh)
    plus.Activated:Connect(function() step(1); refresh() end)
    minus.Activated:Connect(function() step(-1); refresh() end)
    refresh()
    return rowF, value, refresh
end

local function makeButton(parent, text, color, callback)
    local b = Instance.new('TextButton')
    b.Size = UDim2.new(1,0,0,42)
    b.Text = text
    b.TextSize = 14
    b.Font = Theme.fontBold
    b.TextColor3 = Color3.new(1,1,1)
    b.BackgroundColor3 = color
    b.AutoButtonColor = true
    b.BorderSizePixel = 0
    b.Parent = parent
    addCorner(b, UDim.new(0,8))
    b.Activated:Connect(callback)
    return b
end

local function infoRow(parent, text, height)
    local rowF = newRow(parent, height or 40, false)
    local label = newText(rowF, text, 12, Theme.textDim)
    label.Size = UDim2.new(1,-24,1,0)
    label.Position = UDim2.fromOffset(12,0)
    return label
end

local function clampStep(value, low, high, delta)
    return math.clamp(value + delta, low, high)
end

-- ---------- Секция: профили ----------
local profiles = {
    {name = 'Лёгкий', apply = function()
        enabled.drone, enabled.missile, enabled.interceptor, enabled.uav = false, false, false, true
        prefs.arrows, prefs.alerts, prefs.radar = true, true, false
        prefs.showSpeed, prefs.showDirection, prefs.showDistance = false, false, true
        prefs.showEta, prefs.showLead, prefs.threat = true, false, true
        prefs.outlineTransparency = 1
        automatic = true
    end},
    {name = 'Полный', apply = function()
        enabled.drone, enabled.missile, enabled.interceptor, enabled.uav = false, false, false, true
        prefs.arrows, prefs.alerts, prefs.radar = true, true, true
        prefs.showSpeed, prefs.showDirection, prefs.showDistance = true, true, true
        prefs.showEta, prefs.showLead, prefs.threat = true, true, true
        prefs.outlineTransparency = 0.2
    end},
    {name = 'Ракеты', apply = function()
        enabled.drone, enabled.missile, enabled.interceptor, enabled.uav = false, true, false, false
        prefs.arrows, prefs.alerts, prefs.radar = true, true, true
        prefs.showSpeed, prefs.showDirection, prefs.showDistance = true, true, true
        prefs.showEta, prefs.showLead, prefs.threat = true, true, true
        prefs.outlineTransparency = 0.2
    end},
}
do
    local content = makeSection('ПРОФИЛИ', true)
    local buttons = Instance.new('Frame')
    buttons.BackgroundTransparency = 1
    buttons.Size = UDim2.new(1,0,0,40)
    buttons.Parent = content
    local hint = infoRow(content, 'Набор настроек одним тапом: Лёгкий, Полный или только ракеты', 36)
    for index, profile in ipairs(profiles) do
        local b = Instance.new('TextButton')
        b.Size = UDim2.new(1/3,-4,1,0)
        b.Position = UDim2.new((index-1)/3,(index-1)*2,0,0)
        b.Text = profile.name
        b.TextSize = 13
        b.Font = Theme.fontBold
        b.TextColor3 = Theme.text
        b.BackgroundColor3 = Theme.surfaceHi
        b.AutoButtonColor = true
        b.BorderSizePixel = 0
        b.Parent = buttons
        addCorner(b, UDim.new(0,8))
        addStroke(b, Theme.accent, 0.6, 1)
        b.Activated:Connect(function()
            profile.apply()
            changed()
            refreshAll()
            hint.Text = 'Профиль применён: ' .. profile.name
        end)
    end
end

-- ---------- Секция: цели рядом ----------
local listContent, listRows, listEmpty = nil, {}, nil
do
    local content = makeSection('ЦЕЛИ РЯДОМ', true)
    listContent = content
    for i = 1, 5 do
        local r = newRow(content, 36, false)
        r.Visible = false
        local tag = Instance.new('Frame')
        tag.AnchorPoint = Vector2.new(0,0.5)
        tag.Position = UDim2.new(0,10,0.5,0)
        tag.Size = UDim2.fromOffset(4,18)
        tag.BorderSizePixel = 0
        tag.Parent = r
        addCorner(tag, UDim.new(1,0))
        local left = newText(r, '', 13)
        left.Position = UDim2.fromOffset(22,0)
        left.Size = UDim2.new(1,-150,1,0)
        left.TextWrapped = false
        local right = newText(r, '', 12, Theme.textDim, Theme.fontMono)
        right.AnchorPoint = Vector2.new(1,0)
        right.Position = UDim2.new(1,-10,0,0)
        right.Size = UDim2.fromOffset(130,36)
        right.TextXAlignment = Enum.TextXAlignment.Right
        right.TextWrapped = false
        listRows[i] = {row = r, tag = tag, left = left, right = right}
    end
    listEmpty = infoRow(content, 'Целей в зоне нет', 32)
end

-- ---------- Секция: цели ----------
do
    local content = makeSection('ЦЕЛИ', true)
    local titles = {drone = 'Дроны', missile = 'Управляемые ракеты', interceptor = 'Ракеты-перехватчики', uav = 'Все БПЛА'}
    for _, kind in ipairs({'drone', 'missile', 'interceptor', 'uav'}) do
        makeToggle(content, titles[kind],
            function() return enabled[kind] end,
            function(value) enabled[kind] = value; changed() end,
            Theme.kind[kind])
    end
end

-- ---------- Секция: дальность ----------
local rangeValue, autoButton, autoRender
do
    local content = makeSection('ДАЛЬНОСТЬ', true)
    local _row
    _row, rangeValue = makeStepper(content, 'Дальность показа',
        function() return string.format('%d м', math.floor(distance*METERS_PER_STUD+0.5)) end,
        function(direction)
            if calibrating then return end
            automatic = false
            distance = clampStep(distance, 300, 5000, direction*500)
            changed()
        end)
    local autoRow
    autoRow, autoButton, autoRender = makeToggle(content, 'Автоподбор дальности',
        function() return automatic end,
        function()
            if calibrating then return end
            if automatic then automatic = false; changed(); return end
            calibrating = true
            autoButton.Text = 'Замер FPS: 8 секунд…'
            task.spawn(function()
                local total, frames = 0, 0
                while alive and total < 8 do
                    total = total + RunService.RenderStepped:Wait()
                    frames = frames + 1
                end
                if not alive then return end
                local fps = frames / math.max(total, 0.001)
                local quality = 0
                pcall(function() quality = UserSettings():GetService('UserGameSettings').SavedQualityLevel.Value end)
                distance = fps >= 55 and 3000 or (fps >= 40 and 2000 or (fps >= 28 and 1000 or 500))
                -- Automatic graphics reports 0; do not infer actual GPU quality from it.
                if quality > 0 and quality <= 3 then distance = math.min(distance, 2000) end
                automatic, calibrating = true, false
                changed()
                autoButton.Text = 'Автоподбор дальности'
                autoRender(true)
            end)
        end)
end

-- ---------- Секция: оповещения ----------
do
    local content = makeSection('ОПОВЕЩЕНИЯ', true)
    makeToggle(content, 'Тревога при приближении',
        function() return prefs.alerts end,
        function(value) prefs.alerts = value; changed() end)
    makeStepper(content, 'Порог тревоги',
        function() return string.format('%d м', prefs.alertMeters) end,
        function(direction) prefs.alertMeters = clampStep(prefs.alertMeters, 50, 1000, direction*50); changed() end)
    makeToggle(content, 'Стрелки вне экрана',
        function() return prefs.arrows end,
        function(value) prefs.arrows = value; changed() end)
end

-- ---------- Секция: метки ----------
do
    local content = makeSection('МЕТКИ НА ЭКРАНЕ', false)
    makeStepper(content, 'Размер рамки',
        function() return tostring(prefs.dotSize) end,
        function(direction) prefs.dotSize = clampStep(prefs.dotSize, 2, 8, direction); changed() end)
    makeStepper(content, 'Прозрачность обводки',
        function() return string.format('%d %%', math.floor(prefs.outlineTransparency*100+0.5)) end,
        function(direction)
            prefs.outlineTransparency = math.clamp(math.floor((prefs.outlineTransparency+direction*0.1)*10+0.5)/10, 0, 1)
            changed()
        end)
    makeToggle(content, 'Скорость',
        function() return prefs.showSpeed end,
        function(value) prefs.showSpeed = value; changed() end)
    makeToggle(content, 'Расстояние',
        function() return prefs.showDistance end,
        function(value) prefs.showDistance = value; changed() end)
    makeToggle(content, 'Приближается / удаляется',
        function() return prefs.showDirection end,
        function(value) prefs.showDirection = value; changed() end)
    makeToggle(content, 'Время до подлёта',
        function() return prefs.showEta end,
        function(value) prefs.showEta = value; changed() end)
    makeToggle(content, 'Линия упреждения',
        function() return prefs.showLead end,
        function(value) prefs.showLead = value; changed() end)
    makeToggle(content, 'Выделять главную угрозу',
        function() return prefs.threat end,
        function(value) prefs.threat = value; changed() end)
end

-- ---------- Секция: радар ----------
do
    local content = makeSection('РАДАР', false)
    makeToggle(content, 'Мини-радар',
        function() return prefs.radar end,
        function(value) prefs.radar = value; changed() end)
    makeStepper(content, 'Радиус радара',
        function() return string.format('%d м', prefs.radarMeters) end,
        function(direction) prefs.radarMeters = clampStep(prefs.radarMeters, 100, 1000, direction*100); changed() end)
    makeStepper(content, 'Размер радара',
        function() return string.format('%d px', prefs.radarSize) end,
        function(direction) prefs.radarSize = clampStep(prefs.radarSize, 120, 240, direction*30); changed() end)
    makeStepper(content, 'Прозрачность фона',
        function() return string.format('%d %%', math.floor(prefs.radarTransparency*100+0.5)) end,
        function(direction)
            prefs.radarTransparency = math.clamp(math.floor((prefs.radarTransparency+direction*0.1)*10+0.5)/10, 0, 0.9)
            changed()
        end)
end

-- ---------- Секция: система ----------
local status
do
    local content = makeSection('СИСТЕМА', false)
    status = infoRow(content, 'Поиск объектов…', 44)
    settingsStatus = infoRow(content, persistenceMessage, 40)
    makeButton(content, 'Сохранить настройки', Theme.accent, saveNow)
    local armed = false
    local deleteButton
    deleteButton = makeButton(content, 'Выключить и удалить ESP', Theme.danger, function()
        if armed then gui:Destroy(); return end
        armed = true
        deleteButton.Text = 'Нажми ещё раз для удаления'
        task.delay(3, function()
            armed = false
            if deleteButton.Parent then deleteButton.Text = 'Выключить и удалить ESP' end
        end)
    end)
end

table.insert(connections, workspace.DescendantAdded:Connect(register))
table.insert(connections, workspace.DescendantRemoving:Connect(function(object)
    candidates[object] = nil
    downState[object] = nil
    clearMark(object)
end))
task.spawn(function()
    -- Traverse incrementally rather than allocating a full-map descendant snapshot.
    local stack={workspace}
    local processed=0
    while alive and #stack>0 do
        local object=table.remove(stack)
        if object==workspace or object:IsDescendantOf(workspace) then
            register(object)
            for _,child in ipairs(object:GetChildren()) do table.insert(stack,child) end
        end
        processed=processed+1
        if processed%200==0 then task.wait() end
    end
end)
-- ===== Упавшие / сбитые цели не показываем =====
local WRECK_WORDS = {'wreck','debris','crash','destroyed','обломк','Обломк','сбит','Сбит','упал','Упал','разбит'}
local DOWN_FLAGS = {'Destroyed','Dead','Crashed','Downed','Exploded','ShotDown','IsDead','Broken'}
local HEALTH_KEYS = {'Health','HP','health','hp'}
local function flagValue(object,key)
    local attr=object:GetAttribute(key)
    if attr~=nil then return attr end
    local child=object:FindFirstChild(key)
    if child and child:IsA('ValueBase') then
        local ok,value=pcall(function() return child.Value end)
        if ok then return value end
    end
end
local function isDowned(object,part)
    -- 1) Имя или флаги говорят, что объект уничтожен.
    local lowered=string.lower(object.Name)
    for _,word in ipairs(WRECK_WORDS) do
        if string.find(lowered,word,1,true) or string.find(object.Name,word,1,true) then return true end
    end
    for _,key in ipairs(DOWN_FLAGS) do
        if flagValue(object,key)==true then return true end
    end
    for _,key in ipairs(HEALTH_KEYS) do
        local value=flagValue(object,key)
        if type(value)=='number' and value<=0 then return true end
    end
    -- 2) Лежит на земле без движения 3+ секунды = упал.
    local now=os.clock()
    local state=downState[object]
    if not state then
        downState[object]={position=part.Position,time=now,down=false}
        return false
    end
    local elapsed=now-state.time
    if elapsed<0.4 then return state.down end
    local speed=(part.Position-state.position).Magnitude/elapsed
    state.position,state.time=part.Position,now
    if speed<1.5 then
        state.stillSince=state.stillSince or now
    else
        state.stillSince=nil
        state.down=false
    end
    if state.stillSince and now-state.stillSince>=3 then
        local params=RaycastParams.new()
        params.FilterType=Enum.RaycastFilterType.Exclude
        local ignore={object}
        if player.Character then table.insert(ignore,player.Character) end
        params.FilterDescendantsInstances=ignore
        state.down=workspace:Raycast(part.Position,Vector3.new(0,-(math.max(part.Size.Y/2,1)+2),0),params)~=nil
    end
    return state.down
end
local function displayKind(object)
    if not object:IsDescendantOf(workspace) then return end
    if not rosterSet[object] then
        local ancestor=object.Parent
        while ancestor and ancestor~=workspace do
            if rosterSet[ancestor] or candidates[ancestor] then return end
            ancestor=ancestor.Parent
        end
    end
    if blockedAncestor(object,player.Character) then return end
    if object:IsA('Model') and object:FindFirstChildOfClass('Humanoid') then return end
    local kind=classify(object) or (rosterSet[object] and 'uav' or nil)
    if kind=='missile' and interceptor and interceptor(object) then kind='interceptor' end
    return kind
end
local function measuredVelocity(previousPart,currentPart,previousPosition,position,dt)
    if previousPart~=currentPart or dt<0.15 or dt>2 then return nil end
    local velocity=(position-previousPosition)/dt
    if velocity.Magnitude>2000 then return nil end
    return velocity
end
-- Значки типов целей рисуются из Frame в сетке 22×22 (цвет задаёт тип).
local function iconPart(parent,x,y,w,h,color,round,rotation)
    local f=Instance.new('Frame')
    f.AnchorPoint=Vector2.new(0.5,0.5)
    f.Position=UDim2.fromOffset(x,y)
    f.Size=UDim2.fromOffset(w,h)
    f.BackgroundColor3=color
    f.BorderSizePixel=0
    f.Rotation=rotation or 0
    f.Parent=parent
    if round then addCorner(f,UDim.new(round,0)) end
    return f
end
local function buildIcon(parent,kind,color)
    local icon=Instance.new('Frame')
    icon.Name='Icon'
    icon.BackgroundTransparency=1
    icon.AnchorPoint=Vector2.new(0.5,0.5)
    icon.Position=UDim2.fromScale(0.5,0.5)
    icon.Size=UDim2.fromOffset(22,22)
    icon.Parent=parent
    local scale=Instance.new('UIScale')
    scale.Name='Scale'
    scale.Parent=icon
    if kind=='drone' then
        -- FPV-квадрокоптер: две перекладины, 4 ротора, корпус
        iconPart(icon,11,11,24,2.5,color,nil,45)
        iconPart(icon,11,11,24,2.5,color,nil,-45)
        for _,pos in ipairs({{3.5,3.5},{18.5,3.5},{3.5,18.5},{18.5,18.5}}) do
            iconPart(icon,pos[1],pos[2],6,6,color,0.5)
        end
        iconPart(icon,11,11,6,6,Theme.bg,0.2)
        iconPart(icon,11,11,3.5,3.5,color,0.2)
    elseif kind=='missile' or kind=='interceptor' then
        -- Ракета: корпус, нос, оперение, факел
        iconPart(icon,11,10,6,15,color,0.5)
        iconPart(icon,11,3,5,5,color,nil,45)
        iconPart(icon,6.5,16,3,6,color)
        iconPart(icon,15.5,16,3,6,color)
        iconPart(icon,11,20,3,4,Theme.warn,0.5)
        if kind=='interceptor' then
            -- Перехватчик: та же ракета в круге-прицеле
            local ring=Instance.new('Frame')
            ring.BackgroundTransparency=1
            ring.AnchorPoint=Vector2.new(0.5,0.5)
            ring.Position=UDim2.fromScale(0.5,0.5)
            ring.Size=UDim2.fromOffset(26,26)
            ring.Parent=icon
            addCorner(ring,UDim.new(1,0))
            addStroke(ring,color,0,1.5)
        end
    else
        -- БПЛА самолётного типа: фюзеляж, крыло, хвост
        iconPart(icon,11,11,3.5,20,color,0.5)
        iconPart(icon,11,12,22,3.5,color,0.3)
        iconPart(icon,11,19,10,2.5,color,0.3)
        iconPart(icon,11,3,4,4,color,nil,45)
    end
    return icon
end
local function bracketSize() return 18+prefs.dotSize*2 end
local function iconScale(box) return math.clamp((box-8)/22,0.55,1.2) end

local THREAT_WEIGHT = {missile = 1.5, drone = 1.2, uav = 1.0, interceptor = 0}
local function etaText(tti)
    if tti and tti < 90 then return string.format('%d с', math.ceil(tti)) end
end

local function mark(object, part, kind)
    local color = Theme.kind[kind] or Theme.accent
    local billboard = Instance.new('BillboardGui')
    billboard.Name = 'UAV_ESP_Marker'
    billboard.Size = UDim2.fromOffset(120,70)
    billboard.AlwaysOnTop = true
    billboard.Adornee = part
    billboard.Parent = gui

    -- Рамка-уголки вокруг цели (вместо точки).
    local brackets = Instance.new('Frame')
    brackets.Name = 'Brackets'
    brackets.BackgroundTransparency = 1
    brackets.AnchorPoint = Vector2.new(0.5,0.5)
    brackets.Position = UDim2.fromScale(0.5,0.5)
    brackets.Size = UDim2.fromOffset(bracketSize(),bracketSize())
    brackets.Parent = billboard
    buildIcon(brackets,kind,color).Scale.Scale = iconScale(bracketSize())
    local barLength, barThickness = 6, 2
    for _, corner in ipairs({{0,0},{1,0},{0,1},{1,1}}) do
        for _, horizontal in ipairs({true,false}) do
            local bar = Instance.new('Frame')
            bar.Name = 'Bar'
            bar.BorderSizePixel = 0
            bar.BackgroundColor3 = color
            bar.AnchorPoint = Vector2.new(corner[1],corner[2])
            bar.Position = UDim2.fromScale(corner[1],corner[2])
            bar.Size = horizontal and UDim2.fromOffset(barLength,barThickness) or UDim2.fromOffset(barThickness,barLength)
            bar.Parent = brackets
        end
    end

    -- Плашка под целью: тип · расстояние.
    local chip = Instance.new('Frame')
    chip.Name = 'Chip'
    chip.AnchorPoint = Vector2.new(0.5,0)
    chip.Position = UDim2.new(0.5,0,0.5,bracketSize()/2+3)
    chip.Size = UDim2.fromOffset(0,14)
    chip.AutomaticSize = Enum.AutomaticSize.X
    chip.BackgroundColor3 = Theme.bg
    chip.BackgroundTransparency = 0.4
    chip.BorderSizePixel = 0
    chip.Parent = billboard
    addCorner(chip, UDim.new(1,0))
    addStroke(chip, color, 0.55, 1)
    local chipPad = Instance.new('UIPadding', chip)
    chipPad.PaddingLeft = UDim.new(0,5)
    chipPad.PaddingRight = UDim.new(0,5)
    local label = Instance.new('TextLabel')
    label.Name = 'Distance'
    label.BackgroundTransparency = 1
    label.Size = UDim2.fromOffset(0,14)
    label.AutomaticSize = Enum.AutomaticSize.X
    label.TextColor3 = Theme.text
    label.TextSize = 10
    label.Font = Theme.fontMono
    label.Text = names[kind] or ''
    label.Parent = chip

    if outlineCount < OUTLINE_LIMIT then
        local outline = Instance.new('Highlight')
        outline.Name = 'ESP_Outline'
        outline.Adornee = object
        outline.FillTransparency = 1
        outline.OutlineColor = color
        outline.OutlineTransparency = prefs.outlineTransparency
        outline.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        outline.Parent = object
        outlines[object] = outline
        outlineCount = outlineCount + 1
    end

    -- Подпись скорости над целью.
    local speed = Instance.new('TextLabel')
    speed.Name = 'ESP_Speed'
    speed.AnchorPoint = Vector2.new(0.5,1)
    speed.Size = UDim2.fromOffset(150,13)
    speed.BackgroundTransparency = 1
    speed.TextColor3 = Theme.text
    speed.TextTransparency = 0.05
    speed.TextStrokeColor3 = Theme.bg
    speed.TextStrokeTransparency = 0.35
    speed.TextSize = 10
    speed.Font = Theme.fontMono
    speed.Visible = false
    speed.Parent = root
    speedLabels[object] = speed

    -- Линия упреждения: куда цель летит ближайшие ~1.5 секунды.
    local lead = Instance.new('Frame')
    lead.Name = 'ESP_Lead'
    lead.AnchorPoint = Vector2.new(0,0.5)
    lead.Size = UDim2.fromOffset(0,1.5)
    lead.BackgroundColor3 = color
    lead.BorderSizePixel = 0
    lead.Visible = false
    lead.ZIndex = 5
    lead.Parent = root
    local head = Instance.new('TextLabel')
    head.Name = 'Head'
    head.AnchorPoint = Vector2.new(0.5,0.5)
    head.Position = UDim2.new(1,0,0.5,0)
    head.Size = UDim2.fromOffset(12,12)
    head.BackgroundTransparency = 1
    head.Text = '▶'
    head.TextSize = 11
    head.Font = Theme.fontBold
    head.TextColor3 = color
    head.TextStrokeColor3 = Theme.bg
    head.TextStrokeTransparency = 0.3
    head.Parent = lead
    leadLines[object] = lead
    motion[object] = {part = part, position = part.Position, time = os.clock(), kind = kind, color = color, history = {}}
    marks[object] = billboard
    return billboard
end
table.insert(connections, RunService.RenderStepped:Connect(function(dt)
    averageDt = averageDt + (dt-averageDt)*0.05
    elapsed, adjustTime = elapsed+dt, adjustTime+dt
    if elapsed < 0.25 then return end
    elapsed = 0
    local fps = 1/math.max(averageDt,0.001)
    if automatic and adjustTime >= 4 then
        adjustTime = 0
        local oldDistance=distance
        if fps < 28 then distance = math.max(300, math.floor(distance*0.8))
        elseif fps > 55 then distance = math.min(5000, distance+200) end
        if distance~=oldDistance then settingsDirty=true end
    end
    rangeValue.Text = string.format('%d м',math.floor(distance*METERS_PER_STUD+0.5))
    if not calibrating then autoButton.Text = 'Автоподбор дальности' end
    autoRender(true)
    local camera = workspace.CurrentCamera
    if not camera then return end
    local visible, found = {}, 0
    local character=player.Character
    local observer=character and (character:FindFirstChild('HumanoidRootPart') or character:FindFirstChild('Head'))
    local origin=observer and observer.Position or camera.CFrame.Position
    local checked={}
    local function consider(object)
        if checked[object] then return end
        checked[object]=true
        local kind=displayKind(object)
        if not kind then return end
        local part=targetPart(object)
        if part and isDowned(object,part) then return end
        found=found+1
        if enabled[kind] or enabled.uav then
            if part then
                local d=(origin-part.Position).Magnitude
                if d<=distance then table.insert(visible,{object=object,part=part,kind=kind,d=d}) end
            end
        end
    end
    for _,object in ipairs(roster) do consider(object) end
    for object in pairs(candidates) do consider(object) end
    table.sort(visible,function(a,b) return a.d < b.d end)
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = player.Character and {player.Character,camera} or {camera}
    local keep, count = {}, math.min(#visible,48)
    local bestScore, bestObject = 0, nil
    for i=1,count do
        local item = visible[i]
        keep[item.object] = true
        local billboard = marks[item.object] or mark(item.object,item.part,item.kind)
        local sample = motion[item.object]
        local now = os.clock()
        local delta = now-sample.time
        if delta>=0.15 or sample.part~=item.part then
            local position=item.part.Position
            local history=sample.history
            local last=history[#history]
            if sample.part~=item.part or (last and (delta>2 or (position-last.position).Magnitude/math.max(delta,0.001)>2000)) then
                -- смена части, пауза или телепорт: замеры начинаем заново
                history={}
                sample.history=history
                sample.speed,sample.velocity,sample.drawVelocity=nil,nil,nil
                sample.closing,sample.previousRange=nil,nil
            end
            table.insert(history,{time=now,position=position})
            while #history>1 and now-history[1].time>1.2 do table.remove(history,1) end
            local span=now-history[1].time
            if span>=0.45 then
                local velocity=(position-history[1].position)/span
                sample.velocity=sample.velocity and sample.velocity:Lerp(velocity,0.5) or velocity
                sample.speed=sample.velocity.Magnitude
            end
            sample.position, sample.time, sample.part = position, now, item.part
        end
        local character=player.Character
        local viewer=character and (character:FindFirstChild('HumanoidRootPart') or character:FindFirstChild('Head'))
        local trend=nil
        if viewer then
            local currentRange=(item.part.Position-viewer.Position).Magnitude
            local dtRange=sample.rangeTime and now-sample.rangeTime or 0
            if sample.viewer==viewer and sample.previousRange and dtRange>0 and dtRange<=2 then
                local closing=(sample.previousRange-currentRange)/dtRange
                if math.abs(closing)<2000 then
                    sample.closing=sample.closing and sample.closing*0.5+closing*0.5 or closing
                    trend=sample.closing>2 and 'к вам' or (sample.closing < -2 and 'от вас' or 'вбок')
                else sample.closing=nil end
            else sample.closing=nil end
            sample.previousRange,sample.rangeTime,sample.viewer=currentRange,now,viewer
        end
        local tti
        if sample.closing and sample.closing>2 then tti=item.d/sample.closing end
        local weight=THREAT_WEIGHT[item.kind] or 1
        if tti and tti<=60 and weight>0 then
            local score=weight*100/(tti+3)
            threat[item.object]={tti=tti,score=score}
            if score>bestScore then bestScore,bestObject=score,item.object end
        else
            threat[item.object]=tti and {tti=tti,score=0} or nil
        end
        local isTop=prefs.threat and item.object==topThreat
        -- Подпись скорости только у трёх ближайших и у главной угрозы: меньше каши на экране.
        sample.showInfo=(i<=3) or isTop
        local lines={}
        if prefs.showSpeed then table.insert(lines,sample.speed and string.format('%d км/ч',math.floor(sample.speed*METERS_PER_STUD*3.6+0.5)) or '— км/ч') end
        if prefs.showDirection and trend then table.insert(lines,trend) end
        speedLabels[item.object].Text=table.concat(lines,' · ')
        billboard.Adornee = item.part
        billboard.MaxDistance = math.huge -- player-relative range is filtered above
        local box=bracketSize()+(isTop and 6 or 0)
        billboard.Chip.Position=UDim2.new(0.5,0,0.5,box/2+3)
        billboard.Brackets.Size=UDim2.fromOffset(box,box)
        billboard.Brackets.Icon.Scale.Scale=iconScale(box)
        if outlines[item.object] then outlines[item.object].OutlineTransparency=prefs.outlineTransparency end
        local _, onScreen = camera:WorldToViewportPoint(item.part.Position)
        billboard.Enabled = onScreen
        if onScreen then
            local hit = workspace:Raycast(camera.CFrame.Position,
                item.part.Position-camera.CFrame.Position,rayParams)
            local unobstructed = not hit or hit.Instance == item.object or hit.Instance:IsDescendantOf(item.object)
            -- Прямая видимость: яркая рамка. За препятствием: рамка полупрозрачная.
            local fade = math.clamp(item.d/distance,0,1)*0.4
            local barTransparency = unobstructed and fade or math.max(0.55,fade)
            local markColor = isTop and Theme.danger or motion[item.object].color
            for _, bar in ipairs(billboard.Brackets:GetChildren()) do
                if bar.Name=='Bar' then
                    bar.BackgroundTransparency = barTransparency
                    bar.BackgroundColor3 = markColor
                end
            end
            local chipStroke = billboard.Chip:FindFirstChildOfClass('UIStroke')
            if chipStroke then chipStroke.Color = markColor; chipStroke.Thickness = isTop and 2 or 1 end
            local meters = math.floor(item.d*METERS_PER_STUD+0.5)
            local parts = {names[item.kind] or ''}
            if prefs.showDistance then table.insert(parts, string.format('%d м',meters)) end
            local info = threat[item.object]
            local eta = prefs.showEta and info and etaText(info.tti)
            if eta then table.insert(parts, eta) end
            billboard.Chip.Distance.Text = (isTop and '⚠ ' or '')..table.concat(parts,' · ')
        end
    end
    for object in pairs(marks) do if not keep[object] then clearMark(object) end end
    topThreat = bestObject
    if listContent and listContent.Visible and panel.Visible then
        local ranked = {}
        for i=1,count do
            local it = visible[i]
            local info = threat[it.object]
            local s = motion[it.object]
            table.insert(ranked,{object=it.object,kind=it.kind,d=it.d,speed=s and s.speed,tti=info and info.tti,score=info and info.score or 0})
        end
        table.sort(ranked,function(a,b)
            if a.score~=b.score then return a.score>b.score end
            return a.d<b.d
        end)
        for i,slot in ipairs(listRows) do
            local entry = ranked[i]
            slot.row.Visible = entry~=nil
            if entry then
                local top = prefs.threat and entry.object==topThreat
                slot.tag.BackgroundColor3 = top and Theme.danger or (Theme.kind[entry.kind] or Theme.accent)
                slot.left.Text = (top and '⚠ ' or '')..string.format('%s · %d м',names[entry.kind] or '',math.floor(entry.d*METERS_PER_STUD+0.5))
                local bits = {}
                if entry.speed then table.insert(bits,string.format('%d км/ч',math.floor(entry.speed*METERS_PER_STUD*3.6+0.5))) end
                local eta = etaText(entry.tti)
                if eta then table.insert(bits,eta) end
                slot.right.Text = table.concat(bits,' · ')
            end
        end
        listEmpty.Parent.Visible = #ranked==0
    end
    status.Text = string.format('FPS: %d  ·  кандидатов: %d  ·  меток: %d\nРаспознавание по именам объектов',math.floor(fps),found,count)
end))

-- Reproject the top of the object's bounds every frame so the caption follows the camera.
table.insert(connections, RunService.RenderStepped:Connect(function(dt)
    local camera = workspace.CurrentCamera
    for object, label in pairs(speedLabels) do
        label.Visible = false
        if leadLines[object] then leadLines[object].Visible = false end
        local outline = outlines[object]
        if outline then outline.Enabled = false end
        if camera and object:IsDescendantOf(workspace) then
            local cf, size
            if object:IsA('Model') then cf, size = object:GetBoundingBox()
            else cf, size = object.CFrame, object.Size end
            local center, onScreen = camera:WorldToViewportPoint(cf.Position)
            if outline then
                outline.Enabled = onScreen
                outline.OutlineTransparency=prefs.outlineTransparency
            end
            local sampleInfo = motion[object]
            if onScreen and (prefs.showSpeed or prefs.showDirection) and sampleInfo and sampleInfo.showInfo then
                local top, inFront = math.huge, true
                for x=-1,1,2 do
                    for y=-1,1,2 do
                        for z=-1,1,2 do
                            local corner = cf:PointToWorldSpace(Vector3.new(x*size.X/2,y*size.Y/2,z*size.Z/2))
                            local point = camera:WorldToViewportPoint(corner)
                            if point.Z <= 0 then inFront = false end
                            top = math.min(top,point.Y)
                        end
                    end
                end
                if inFront then
                    -- WorldToScreenPoint includes the top-bar inset, matching GUI AbsolutePosition.
                    local screen = camera:WorldToScreenPoint(cf.Position)
                    local inset = screen.Y-center.Y
                    label.Position = UDim2.fromOffset(screen.X-root.AbsolutePosition.X,top+inset-root.AbsolutePosition.Y-4)
                    label.Visible = true
                end
            end
            local lead = leadLines[object]
            if lead then
                local sample = motion[object]
                local shown = false
                if sample and sample.velocity then
                    -- Рисуем по сглаженной скорости: дёрганье измерений не доходит до экрана.
                    local blendV = 1-math.exp(-dt/0.25)
                    sample.drawVelocity = sample.drawVelocity and sample.drawVelocity:Lerp(sample.velocity,blendV) or sample.velocity
                else
                    if sample then sample.drawVelocity = nil end
                end
                local state = sample and sample.lead
                if sample and not state then state = {on = false}; sample.lead = state end
                if prefs.showLead and onScreen and sample and sample.drawVelocity and sample.drawVelocity.Magnitude >= 10 then
                    local velocity = sample.drawVelocity
                    local p0 = camera:WorldToScreenPoint(cf.Position)
                    local p1 = camera:WorldToScreenPoint(cf.Position + velocity*1.5)
                    if p0.Z > 0 and p1.Z > 0 then
                        local dir = Vector2.new(p1.X-p0.X, p1.Y-p0.Y)
                        local length = dir.Magnitude
                        -- Гистерезис: появляется от 12 px, пропадает только ниже 7 px.
                        if length >= (state.on and 7 or 12) then
                            local angle = math.atan2(dir.Y,dir.X)
                            local px = math.clamp(length,12,60)
                            if state.angle then
                                local diff = (angle-state.angle+math.pi)%(2*math.pi)-math.pi
                                local blendA = 1-math.exp(-dt/0.08)
                                state.angle = state.angle + diff*blendA
                                state.length = state.length + (px-state.length)*blendA
                            else
                                state.angle, state.length = angle, px
                            end
                            local unit = Vector2.new(math.cos(state.angle),math.sin(state.angle))
                            local start = Vector2.new(p0.X,p0.Y) + unit*(bracketSize()/2+3)
                            local color = (prefs.threat and object==topThreat) and Theme.danger or (sample.color or Theme.accent)
                            lead.BackgroundColor3 = color
                            lead.Head.TextColor3 = color
                            lead.Position = UDim2.fromOffset(start.X-root.AbsolutePosition.X, start.Y-root.AbsolutePosition.Y)
                            lead.Size = UDim2.fromOffset(state.length,1.5)
                            lead.Rotation = math.deg(state.angle)
                            shown = true
                        end
                    end
                end
                if state then
                    state.on = shown
                    if not shown then state.angle, state.length = nil, nil end
                end
                lead.Visible = shown
            end
        end
    end
end))

local counter=Instance.new('TextLabel')
counter.Name='SkyCounter'
counter.AnchorPoint=Vector2.new(1,0)
counter.Position=UDim2.new(1,-12,0,12)
counter.Size=UDim2.fromOffset(190,34)
counter.BackgroundColor3=Theme.bg
counter.BackgroundTransparency=0.12
counter.BorderSizePixel=0
counter.TextColor3=Theme.text
counter.TextSize=14
counter.Font=Theme.fontBold
counter.TextXAlignment=Enum.TextXAlignment.Left
counter.Text='БПЛА в небе: …'
counter.ZIndex=20
counter.Parent=root
addCorner(counter,UDim.new(1,0))
addStroke(counter,Theme.stroke,0.3,1)
local counterPad=Instance.new('UIPadding',counter)
counterPad.PaddingLeft=UDim.new(0,30)
local counterDot=Instance.new('Frame')
counterDot.AnchorPoint=Vector2.new(0,0.5)
counterDot.Position=UDim2.new(0,-18,0.5,0)
counterDot.Size=UDim2.fromOffset(8,8)
counterDot.BackgroundColor3=Theme.ok
counterDot.BorderSizePixel=0
counterDot.Parent=counter
addCorner(counterDot,UDim.new(1,0))
local ownerKeys={'shooter','Shooter','owner','Owner','player','Player','creator','Creator','OwnerUserId','ShooterUserId','UserId','userId'}
local function metadata(object,keys)
    local current=object
    for _=1,3 do
        if typeof(current)~='Instance' or current==workspace then return end
        for _,key in ipairs(keys) do
            local attr=current:GetAttribute(key)
            if attr~=nil then return attr end
            local child=current:FindFirstChild(key)
            if child and child:IsA('ValueBase') then
                local ok,value=pcall(function()return child.Value end)
                if ok and value~=nil then return value end
            end
        end
        current=current.Parent
    end
end
local function isPlayerOwner(value)
    if typeof(value)=='Instance' then
        return value:IsA('Player') or (value:IsA('Model') and Players:GetPlayerFromCharacter(value)~=nil)
    end
    for _,p in ipairs(Players:GetPlayers()) do
        if value==p.UserId or value==tostring(p.UserId) or value==p.Name then return true end
    end
    return false
end
local function rocketLike(object)
    local name=string.lower(object.Name)
    local parentName=object.Parent and string.lower(object.Parent.Name) or ''
    return name:find('rocket',1,true) or name:find('missile',1,true) or name:find('stinger',1,true)
        or parentName:find('rocket',1,true) or parentName:find('missile',1,true)
        or name:find('Ракет',1,true) or name:find('ракет',1,true)
end
function interceptor(object)
    local name=string.lower(object.Name)
    if name:find('stinger',1,true) or name:find('interceptor',1,true) then return true end
    return rocketLike(object) and isPlayerOwner(metadata(object,ownerKeys))
end
local function rebuildRoster()
    roster={};rosterSet={}
    local seen={}
    local character=player.Character
    local function add(object)
        if seen[object] or interceptor(object) or blockedAncestor(object,character) then return end
        local part=targetPart(object)
        if part and not isDowned(object,part) then seen[object]=true;rosterSet[object]=true;table.insert(roster,object) end
    end
    local droneFolder=workspace:FindFirstChild('Drones')
    if droneFolder then
        local queue={droneFolder};local index=1
        while index<=#queue and index<=1024 do
            local folder=queue[index];index=index+1
            for _,object in ipairs(folder:GetChildren()) do
                if object:IsA('Folder') and #queue<1024 then table.insert(queue,object)
                else add(object) end
            end
        end
    else
        -- Without the game's target container, count only name-recognized UAVs.
        for object,kind in pairs(candidates) do
            if kind~='missile' then
                local ancestor,nested=object.Parent,false
                while ancestor and ancestor~=workspace do
                    if candidates[ancestor] then nested=true;break end
                    ancestor=ancestor.Parent
                end
                if not nested then add(object) end
            end
        end
    end
    counter.Text=(droneFolder and 'БПЛА в небе: ' or 'БПЛА найдено: ')..#roster
end
local rosterTime=1
local persistenceTime=0
table.insert(connections,RunService.Heartbeat:Connect(function(dt)
    rosterTime=rosterTime+dt
    persistenceTime=persistenceTime+dt
    if persistenceTime>=30 then
        persistenceTime=0
        if settingsDirty and not saveQueued then saveNow() end
    end
    if rosterTime>=0.5 then rosterTime=0;rebuildRoster() end
end))

-- Approach alerts are based on target motion and closing distance, not camera motion.
local WARNING_REST=UDim2.new(0.5,0,1,-12)
local WARNING_HIDDEN=UDim2.new(0.5,0,1,70)
local warning=Instance.new('TextLabel')
warning.AnchorPoint=Vector2.new(0.5,1)
warning.Position=WARNING_HIDDEN
warning.Size=UDim2.new(1,-24,0,48)
warning.BackgroundColor3=Theme.bg
warning.BackgroundTransparency=0.05
warning.BorderSizePixel=0
warning.TextColor3=Theme.text
warning.TextSize=16
warning.Font=Theme.fontBold
warning.TextWrapped=true
warning.Visible=false
warning.ClipsDescendants=true
warning.ZIndex=25
warning.Parent=root
addCorner(warning,UDim.new(0,10))
local warningStroke=addStroke(warning,Theme.danger,0.1,2)
local warningPad=Instance.new('UIPadding',warning)
warningPad.PaddingLeft=UDim.new(0,18)
local warningBar=Instance.new('Frame')
warningBar.Size=UDim2.new(0,5,1,0)
warningBar.Position=UDim2.fromOffset(-18,0)
warningBar.BackgroundColor3=Theme.danger
warningBar.BorderSizePixel=0
warningBar.Parent=warning
local warningShown=false
local function showWarning(visible)
    if visible==warningShown then return end
    warningShown=visible
    if visible then
        warning.Visible=true
        warning.Position=WARNING_HIDDEN
        TweenService:Create(warning,Theme.tween,{Position=WARNING_REST}):Play()
        warningStroke.Transparency=0.6
        TweenService:Create(warningStroke,TweenInfo.new(0.35,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,5,true),{Transparency=0.05}):Play()
    else
        local tween=TweenService:Create(warning,Theme.tween,{Position=WARNING_HIDDEN})
        tween:Play()
        tween.Completed:Connect(function() if not warningShown then warning.Visible=false end end)
    end
end
-- Кольцо-указатель вокруг центра экрана. Стрелка стоит на кольце по азимуту цели:
-- вверх = прямо по взгляду, вправо = справа, вниз = за спиной. Подпись лежит внутри кольца.
-- «↑» / «↓» в подписи: цель заметно выше / ниже горизонта.
local ARROW_SLOTS=4
local arrowRing=Instance.new('Frame')
arrowRing.Name='ArrowRing'
arrowRing.AnchorPoint=Vector2.new(0.5,0.5)
arrowRing.BackgroundTransparency=1
arrowRing.Visible=false
arrowRing.ZIndex=4
arrowRing.Parent=root
addCorner(arrowRing,UDim.new(1,0))
addStroke(arrowRing,Theme.text,0.9,1)
local ringTick=Instance.new('Frame')
ringTick.AnchorPoint=Vector2.new(0.5,0)
ringTick.Position=UDim2.new(0.5,0,0,-1)
ringTick.Size=UDim2.fromOffset(2,9)
ringTick.BackgroundColor3=Theme.text
ringTick.BackgroundTransparency=0.55
ringTick.BorderSizePixel=0
ringTick.Parent=arrowRing
local arrowSlots={}
for i=1,ARROW_SLOTS do
    local frame=Instance.new('Frame')
    frame.Name='ArrowSlot'
    frame.AnchorPoint=Vector2.new(0.5,0.5);frame.Size=UDim2.fromOffset(26,26)
    frame.BackgroundTransparency=1;frame.Visible=false;frame.ZIndex=6;frame.Parent=root
    local arrow=Instance.new('TextLabel')
    arrow.Name='Pointer'
    arrow.AnchorPoint=Vector2.new(0.5,0.5);arrow.Position=UDim2.fromScale(0.5,0.5)
    arrow.Size=UDim2.fromOffset(26,26);arrow.BackgroundTransparency=1
    arrow.Text='▲';arrow.TextSize=20;arrow.Font=Theme.fontBold;arrow.TextColor3=Theme.warn
    arrow.TextStrokeColor3=Theme.bg;arrow.TextStrokeTransparency=0.2;arrow.Parent=frame
    local chip=Instance.new('Frame')
    chip.Name='Chip'
    chip.AnchorPoint=Vector2.new(0.5,0.5)
    chip.Position=UDim2.fromScale(0.5,0.5);chip.Size=UDim2.fromOffset(0,14)
    chip.AutomaticSize=Enum.AutomaticSize.X
    chip.BackgroundColor3=Theme.bg;chip.BackgroundTransparency=0.4;chip.BorderSizePixel=0
    chip.Parent=frame
    addCorner(chip,UDim.new(1,0))
    local chipStroke=addStroke(chip,Theme.warn,0.55,1)
    local chipPad=Instance.new('UIPadding',chip)
    chipPad.PaddingLeft=UDim.new(0,5);chipPad.PaddingRight=UDim.new(0,5)
    local label=Instance.new('TextLabel')
    label.Size=UDim2.fromOffset(0,14);label.AutomaticSize=Enum.AutomaticSize.X
    label.BackgroundTransparency=1;label.TextSize=10;label.Font=Theme.fontMono
    label.TextColor3=Theme.text;label.Parent=chip
    arrowSlots[i]={frame=frame,arrow=arrow,label=label,chip=chip,chipStroke=chipStroke}
end
local function approaching(previous,position,range,dt,origin)
    if not previous or dt<=0 or dt>2 or range<0.001 then return false end
    local velocity=(position-previous.position)/dt
    if velocity.Magnitude>2000 then return false end -- discontinuity/teleport
    local radial=velocity:Dot((origin-position).Unit)
    local closing=(previous.range-range)/dt
    return radial>2 and closing>2
end
local approachSamples={}
local previousCharacter
local extraElapsed=0
local warningUntil,lastWarning=0,-math.huge
local arrowCandidates={}
table.insert(connections,RunService.Heartbeat:Connect(function(dt)
    extraElapsed=extraElapsed+dt
    if extraElapsed<0.25 then return end
    extraElapsed=0
    local camera=workspace.CurrentCamera
    local character=player.Character
    local head=character and (character:FindFirstChild('HumanoidRootPart') or character:FindFirstChild('Head'))
    local humanoid=character and character:FindFirstChildOfClass('Humanoid')
    if character~=previousCharacter then
        approachSamples={};previousCharacter=character;warningUntil=0
    end
    if not camera or not head or (humanoid and humanoid.Health<=0) then
        arrowCandidates={};approachSamples={};showWarning(false);return
    end
    local now=os.clock()
    local found,keep={},{}
    local nearestAlert,nearestRange,nearestKind
    for _,object in ipairs(roster) do
        local part=targetPart(object)
        local kind=part and displayKind(object)
        -- Тревога и стрелки подчиняются тем же фильтрам типов, что и метки.
        if part and kind and (enabled[kind] or enabled.uav) then
            local position=part.Position
            local range=(position-head.Position).Magnitude
            local previous=approachSamples[object]
            local sampleDt=previous and now-previous.time or 0
            local threshold=prefs.alertMeters/METERS_PER_STUD
            local alerted=previous and previous.alerted or false
            if range>threshold*1.2 then alerted=false end
            if prefs.alerts and range<=threshold and not alerted and approaching(previous,position,range,sampleDt,head.Position) then
                if not nearestRange or range<nearestRange then nearestAlert,nearestRange,nearestKind=object,range,kind end
            end
            keep[object]={position=position,range=range,time=now,alerted=alerted}
            if prefs.arrows and range<=distance then
                table.insert(found,{object=object,part=part,range=range,kind=kind})
            end
        end
    end
    approachSamples=keep
    if nearestAlert and now-lastWarning>=4 then
        approachSamples[nearestAlert].alerted=true
        lastWarning=now;warningUntil=now+3
        warning.Text=string.format('⚠  %s приближается · %d м',names[nearestKind] or 'Цель',math.floor(nearestRange*METERS_PER_STUD+0.5))
    end
    showWarning(prefs.alerts and now<warningUntil)
    table.sort(found,function(a,b)
        local ta,tb=threat[a.object],threat[b.object]
        local sa,sb=ta and ta.score or 0,tb and tb.score or 0
        if sa~=sb then return sa>sb end
        return a.range<b.range
    end)
    arrowCandidates={}
    for i=1,math.min(10,#found) do arrowCandidates[i]=found[i] end
end))
local lastFlat=Vector3.new(0,0,-1)
table.insert(connections,RunService.RenderStepped:Connect(function(dt)
    local camera=workspace.CurrentCamera
    -- Какие кандидаты сейчас за кадром (проверка каждый кадр, без задержки в 0.25 с).
    local active={}
    if prefs.arrows and camera then
        for _,target in ipairs(arrowCandidates) do
            if #active>=ARROW_SLOTS then break end
            if target.part:IsDescendantOf(workspace) then
                local _,onScreen=camera:WorldToViewportPoint(target.part.Position)
                if not onScreen then table.insert(active,target) end
            end
        end
    end
    -- Цель держит свой слот, пока остаётся за кадром: стрелки не перепрыгивают между слотами.
    local assigned={}
    for _,slot in ipairs(arrowSlots) do
        local target
        for _,candidate in ipairs(active) do
            if candidate.object==slot.owner then target=candidate break end
        end
        if target then assigned[target.object]=true;slot.target=target
        else slot.owner=nil;slot.target=nil end
    end
    for _,candidate in ipairs(active) do
        if not assigned[candidate.object] then
            for _,slot in ipairs(arrowSlots) do
                if not slot.owner then
                    slot.owner=candidate.object;slot.target=candidate;slot.angle=nil
                    break
                end
            end
        end
    end
    local width,height=root.AbsoluteSize.X,root.AbsoluteSize.Y
    local radius=math.clamp(math.min(width,height)*0.34,70,170)
    local anyShown=false
    local flatRight=Vector3.new(0,0,0)
    local cameraPosition=Vector3.new(0,0,0)
    if camera then
        local look=camera.CFrame.LookVector
        local flat=Vector3.new(look.X,0,look.Z)
        if flat.Magnitude>0.05 then lastFlat=flat.Unit end
        flatRight=Vector3.new(-lastFlat.Z,0,lastFlat.X)
        cameraPosition=camera.CFrame.Position
    end
    local blend=1-math.exp(-dt/0.07)
    for _,slot in ipairs(arrowSlots) do
        local target=slot.target
        if target and camera then
            local delta=target.part.Position-cameraPosition
            local forwardD,rightD=delta:Dot(lastFlat),delta:Dot(flatRight)
            -- Цель спереди: стрелка там, куда надо довернуть камеру (вверх/вниз/вбок).
            -- Цель сзади: только азимут, чтобы «за спиной» всегда было внизу кольца.
            local localPosition=camera.CFrame:PointToObjectSpace(target.part.Position)
            local bearing
            if localPosition.Z<-0.001 then bearing=math.atan2(localPosition.X,localPosition.Y)
            else bearing=math.atan2(rightD,forwardD) end
            if slot.angle then
                local diff=(bearing-slot.angle+math.pi)%(2*math.pi)-math.pi
                slot.angle=slot.angle+diff*blend
            else slot.angle=bearing end
            local a=slot.angle
            slot.frame.Position=UDim2.fromOffset(width/2+math.sin(a)*radius,height/2-math.cos(a)*radius)
            slot.arrow.Rotation=math.deg(a)
            local isTop=prefs.threat and target.object==topThreat
            local color=isTop and Theme.danger or (Theme.kind[target.kind] or Theme.warn)
            slot.arrow.TextColor3=color
            slot.chipStroke.Color=color
            slot.arrow.TextSize=isTop and 25 or 19
            slot.arrow.TextTransparency=isTop and 0 or math.clamp(target.range/math.max(distance,1),0,1)*0.45
            -- Подпись внутри кольца, отодвинута от стрелки на свой размер.
            local elevation=math.deg(math.atan2(delta.Y,math.sqrt(forwardD*forwardD+rightD*rightD)))
            local vertical=elevation>12 and '↑ ' or (elevation<-12 and '↓ ' or '')
            local info=threat[target.object]
            local eta=prefs.showEta and info and etaText(info.tti)
            slot.label.Text=vertical..string.format('%d м',math.floor(target.range*METERS_PER_STUD+0.5))..(eta and (' · '..eta) or '')
            slot.chip.Visible=prefs.showDistance
            local ux,uy=-math.sin(a),math.cos(a)
            local chipSize=slot.chip.AbsoluteSize
            local reach=14+math.abs(ux)*chipSize.X/2+math.abs(uy)*chipSize.Y/2+2
            slot.chip.Position=UDim2.new(0.5,ux*reach,0.5,uy*reach)
            slot.frame.Visible=true
            anyShown=true
        else
            slot.frame.Visible=false
        end
    end
    arrowRing.Size=UDim2.fromOffset(radius*2,radius*2)
    arrowRing.Position=UDim2.fromOffset(width/2,height/2)
    arrowRing.Visible=anyShown
end))

-- Store top-left positions as fractions of usable space; preserve them on rotation.
local function widgetPoint(pos,width,height,widgetWidth,widgetHeight)
    local spanX=math.max(0,width-widgetWidth-16)
    local spanY=math.max(0,height-widgetHeight-16)
    return math.min(8,math.max(0,width-widgetWidth))+pos.x*spanX,
        math.min(8,math.max(0,height-widgetHeight))+pos.y*spanY,spanX,spanY
end
local function draggable(widget,handle,key)
    widget.AnchorPoint=Vector2.new(0,0)
    local handles=type(handle)=='table' and handle or {handle}
    for _,surface in ipairs(handles) do surface.Active=true end
    local activeInput,startPointer,startPosition
    local function place()
        if activeInput then return end
        local x,y=widgetPoint(prefs.positions[key],root.AbsoluteSize.X,root.AbsoluteSize.Y,widget.AbsoluteSize.X,widget.AbsoluteSize.Y)
        widget.Position=UDim2.fromOffset(x,y)
        if key=='menu' then toggle.Position=widget.Position end
    end
    for _,surface in ipairs(handles) do
    table.insert(connections,surface.InputBegan:Connect(function(input)
        if activeInput or not (input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1) then return end
        activeInput=input;startPointer=Vector2.new(input.Position.X,input.Position.Y)
        startPosition=widget.AbsolutePosition-root.AbsolutePosition
    end))
    end
    table.insert(connections,UserInputService.InputChanged:Connect(function(input)
        if not activeInput then return end
        if input~=activeInput and not (activeInput.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseMovement) then return end
        local pointer=Vector2.new(input.Position.X,input.Position.Y)
        local point=startPosition+pointer-startPointer
        local x,y,spanX,spanY=widgetPoint({x=0,y=0},root.AbsoluteSize.X,root.AbsoluteSize.Y,widget.AbsoluteSize.X,widget.AbsoluteSize.Y)
        local px=math.clamp(point.X,x,x+spanX)
        local py=math.clamp(point.Y,y,y+spanY)
        prefs.positions[key]={x=spanX>0 and (px-x)/spanX or 0,y=spanY>0 and (py-y)/spanY or 0}
        settingsDirty=true
        widget.Position=UDim2.fromOffset(px,py)
        if key=='menu' then toggle.Position=widget.Position end
    end))
    local function finish()
        if activeInput then activeInput=nil;changed();place() end
    end
    table.insert(connections,UserInputService.InputEnded:Connect(function(input)if input==activeInput then finish() end end))
    table.insert(connections,UserInputService.WindowFocusReleased:Connect(finish))
    table.insert(connections,root:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()finish();place()end))
    table.insert(connections,widget:GetPropertyChangedSignal('AbsoluteSize'):Connect(place))
    place()
end
draggable(panel,dragHeader,'menu')
draggable(counter,counter,'counter')

local radar=Instance.new('Frame')
radar.Name='MiniRadar'
radar.AnchorPoint=Vector2.new(1,0)
radar.Position=UDim2.new(1,-12,0,58)
radar.Size=UDim2.fromOffset(150,174)
radar.BackgroundTransparency=1;radar.ZIndex=10;radar.Visible=prefs.radar;radar.Parent=root
local radarTitle=Instance.new('TextLabel')
radarTitle.Size=UDim2.new(1,0,0,20)
radarTitle.BackgroundColor3=Theme.bg;radarTitle.BackgroundTransparency=0.15
radarTitle.BorderSizePixel=0
radarTitle.TextSize=12;radarTitle.Font=Theme.fontMono
radarTitle.TextColor3=Theme.text;radarTitle.Parent=radar
addCorner(radarTitle,UDim.new(1,0))
addStroke(radarTitle,Theme.stroke,0.3,1)
local disc=Instance.new('Frame')
disc.Position=UDim2.fromOffset(0,24);disc.Size=UDim2.fromOffset(150,150)
disc.BackgroundColor3=Theme.bg;disc.BackgroundTransparency=0.25
disc.BorderSizePixel=0;disc.Parent=radar
Instance.new('UICorner',disc).CornerRadius=UDim.new(1,0)
local stroke=Instance.new('UIStroke',disc)
stroke.Color=Theme.stroke;stroke.Transparency=0.15;stroke.Thickness=1.5
-- Кольцо на половине радиуса и подпись его дальности.
local ring=Instance.new('Frame')
ring.AnchorPoint=Vector2.new(0.5,0.5);ring.Position=UDim2.fromScale(0.5,0.5)
ring.Size=UDim2.fromScale(0.5,0.5);ring.BackgroundTransparency=1;ring.Parent=disc
Instance.new('UICorner',ring).CornerRadius=UDim.new(1,0)
local ringStroke=Instance.new('UIStroke',ring)
ringStroke.Color=Theme.stroke;ringStroke.Transparency=0.35;ringStroke.Thickness=1
local ringLabel=Instance.new('TextLabel')
ringLabel.AnchorPoint=Vector2.new(0.5,0.5);ringLabel.Position=UDim2.new(0.5,0,0.25,0)
ringLabel.Size=UDim2.fromOffset(44,12);ringLabel.BackgroundTransparency=1
ringLabel.TextSize=10;ringLabel.Font=Theme.fontMono;ringLabel.TextColor3=Theme.textDim
ringLabel.TextTransparency=0.2;ringLabel.Parent=disc
for _,vertical in ipairs({true,false}) do
    local line=Instance.new('Frame')
    line.AnchorPoint=Vector2.new(0.5,0.5);line.Position=UDim2.fromScale(0.5,0.5)
    line.Size=vertical and UDim2.new(0,1,1,-12) or UDim2.new(1,-12,0,1)
    line.BackgroundColor3=Theme.stroke;line.BackgroundTransparency=0.6
    line.BorderSizePixel=0;line.Parent=disc
end
local forwardMark=Instance.new('TextLabel')
forwardMark.AnchorPoint=Vector2.new(0.5,0);forwardMark.Position=UDim2.new(0.5,0,0,3)
forwardMark.Size=UDim2.fromOffset(16,12);forwardMark.BackgroundTransparency=1
forwardMark.Text='▲';forwardMark.TextSize=9;forwardMark.Font=Theme.fontBold
forwardMark.TextColor3=Theme.textDim;forwardMark.Parent=disc
local selfMarker=Instance.new('TextLabel')
selfMarker.AnchorPoint=Vector2.new(0.5,0.5);selfMarker.Position=UDim2.fromScale(0.5,0.5)
selfMarker.Size=UDim2.fromOffset(14,16);selfMarker.BackgroundTransparency=1
selfMarker.Text='▲';selfMarker.TextSize=12;selfMarker.Font=Theme.fontBold
selfMarker.TextColor3=Theme.accent
selfMarker.ZIndex=3;selfMarker.Parent=disc
local radarDots={}
for i=1,24 do
    local dot=Instance.new('Frame')
    dot.AnchorPoint=Vector2.new(0.5,0.5);dot.Size=UDim2.fromOffset(7,7)
    dot.BackgroundColor3=Theme.text;dot.BorderSizePixel=0;dot.Visible=false
    dot.ZIndex=2;dot.Parent=disc;Instance.new('UICorner',dot).CornerRadius=UDim.new(1,0)
    addStroke(dot,Theme.bg,0.2,1)
    radarDots[i]=dot
end
local function radarPoint(dx,dz,fx,fz,range,radius)
    local length=math.sqrt(fx*fx+fz*fz)
    if length<0.001 then fx,fz=0,-1 else fx,fz=fx/length,fz/length end
    local right=dx*(-fz)+dz*fx
    local forward=dx*fx+dz*fz
    return right/range*radius,-forward/range*radius
end
local function radarDiameter(requested,width,height)
    return math.max(1,math.min(requested,width-16,height-40))
end
local function radarStyle()
    local size=radarDiameter(prefs.radarSize,root.AbsoluteSize.X,root.AbsoluteSize.Y)
    radar.Size=UDim2.fromOffset(size,size+24)
    disc.Size=UDim2.fromOffset(size,size)
    disc.BackgroundTransparency=prefs.radarTransparency
end
radarStyle()
table.insert(connections,root:GetPropertyChangedSignal('AbsoluteSize'):Connect(radarStyle))
draggable(radar,{radarTitle,disc},'radar')
local radarElapsed=1
local lastForward=Vector3.new(0,0,-1)
table.insert(connections,RunService.Heartbeat:Connect(function(dt)
    radarElapsed=radarElapsed+dt
    if radarElapsed<0.2 then return end
    radarElapsed=0
    radarStyle()
    radar.Visible=prefs.radar
    if not prefs.radar then return end
    for _,dot in ipairs(radarDots) do dot.Visible=false end
    local camera=workspace.CurrentCamera
    local character=player.Character
    local originPart=character and (character:FindFirstChild('HumanoidRootPart') or character:FindFirstChild('Head'))
    if not camera or not originPart then radarTitle.Text='РАДАР · нет персонажа';return end
    local forward=camera.CFrame.LookVector
    if forward.X*forward.X+forward.Z*forward.Z>0.0001 then lastForward=forward end
    local range=prefs.radarMeters/METERS_PER_STUD
    local nearby={}
    for _,object in ipairs(roster) do
        local part=targetPart(object)
        local kind=part and displayKind(object)
        if part and kind and (enabled[kind] or enabled.uav) then
            local delta=part.Position-originPart.Position
            local horizontal=math.sqrt(delta.X*delta.X+delta.Z*delta.Z)
            if horizontal<=range then table.insert(nearby,{delta=delta,distance=horizontal,kind=kind}) end
        end
    end
    table.sort(nearby,function(a,b)return a.distance<b.distance end)
    local count=math.min(24,#nearby)
    for i=1,count do
        local entry=nearby[i]
        local x,y=radarPoint(entry.delta.X,entry.delta.Z,lastForward.X,lastForward.Z,range,math.max(1,disc.AbsoluteSize.X/2-7))
        radarDots[i].Position=UDim2.fromOffset(disc.AbsoluteSize.X/2+x,disc.AbsoluteSize.Y/2+y)
        radarDots[i].BackgroundColor3=Theme.kind[entry.kind] or Theme.text
        radarDots[i].Visible=true
    end
    ringLabel.Text=string.format('%d м',math.floor(prefs.radarMeters/2))
    radarTitle.Text=string.format('РАДАР · %d м · %d/%d',prefs.radarMeters,count,#nearby)
end))

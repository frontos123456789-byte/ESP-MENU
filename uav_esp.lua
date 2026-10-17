-- Preliminary name-based ESP. Not verified against ILP Studio's object hierarchy.
-- Execute only once per session; running again replaces the previous instance.
local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local UserInputService = game:GetService('UserInputService')
local player = Players.LocalPlayer
local parent = player:WaitForChild('PlayerGui')
local previous = parent:FindFirstChild('UAV_ESP_Menu')
if previous then previous:Destroy() end

local gui = Instance.new('ScreenGui')
gui.Name = 'UAV_ESP_Menu'
gui.ResetOnSpawn = false
gui.DisplayOrder = 100
gui.Parent = parent
local alive, automatic, calibrating = true, false, false
local distance, averageDt, elapsed, adjustTime = 1500, 1/60, 0, 0
local enabled = {drone = false, missile = false, uav = false}
local candidates, marks, connections = {}, {}, {}
local outlines, speedLabels, motion = {}, {}, {}
local METERS_PER_STUD = 0.28
local clearColor = Color3.fromRGB(70,220,105)
local blockedColor = Color3.fromRGB(245,75,75)
local names = {drone = 'Дрон', missile = 'Ракета', uav = 'БПЛА'}
-- Add exact object names here if the game uses different names.
local patterns = {
    missile = {'missile', 'rocket', 'ракет', 'Ракет', 'РАКЕТ'},
    drone = {'drone', 'fpv', 'дрон', 'Дрон', 'ДРОН'},
    uav = {'uav', 'ucav', 'shahed', 'geran', 'lancet', 'бпла', 'БПЛА', 'шахед', 'Шахед', 'Герань', 'Ланцет'},
}
local function classify(object)
    if not (object:IsA('Model') or object:IsA('BasePart')) then return end
    local name = string.lower(object.Name)
    for _, kind in ipairs({'missile', 'drone', 'uav'}) do
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
    if outlines[object] then outlines[object]:Destroy(); outlines[object] = nil end
    if speedLabels[object] then speedLabels[object]:Destroy(); speedLabels[object] = nil end
    motion[object] = nil
    if marks[object] then marks[object]:Destroy(); marks[object] = nil end
end
local function cleanup()
    if not alive then return end
    alive = false
    for _, connection in ipairs(connections) do connection:Disconnect() end
    for object in pairs(marks) do clearMark(object) end
    table.clear(candidates)
end
gui.Destroying:Connect(cleanup)

-- Safe-area root automatically follows rotation, viewport size and device insets.
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
local root = Instance.new('Frame')
root.Size = UDim2.fromScale(1,1)
root.BackgroundTransparency = 1
root.Parent = gui
local panel = Instance.new('Frame')
panel.Position = UDim2.fromOffset(8,8)
panel.BackgroundColor3 = Color3.fromRGB(24,28,38)
panel.Parent = root
Instance.new('UICorner', panel).CornerRadius = UDim.new(0,12)
local toggle = Instance.new('TextButton')
toggle.Size = UDim2.fromOffset(64,44)
toggle.Position = UDim2.fromOffset(8,8)
toggle.Text = 'ESP'
toggle.TextSize = 16
toggle.TextColor3 = Color3.new(1,1,1)
toggle.BackgroundColor3 = Color3.fromRGB(43,49,65)
toggle.Visible = false
toggle.Parent = root
Instance.new('UICorner',toggle).CornerRadius = UDim.new(0,10)
local close = Instance.new('TextButton')
close.Size = UDim2.new(1,-16,0,44)
close.Position = UDim2.fromOffset(8,4)
close.Text = 'БПЛА ESP     × Скрыть'
close.TextSize = 16
close.TextColor3 = Color3.new(1,1,1)
close.BackgroundTransparency = 1
close.Parent = panel
close.Activated:Connect(function()
    panel.Visible = false
    toggle.Visible = true
end)
toggle.Activated:Connect(function()
    panel.Visible = true
    toggle.Visible = false
end)
local body = Instance.new('ScrollingFrame')
body.Position = UDim2.fromOffset(0,52)
body.Size = UDim2.new(1,0,1,-60)
body.BackgroundTransparency = 1
body.BorderSizePixel = 0
body.ScrollBarThickness = 3
body.ScrollingDirection = Enum.ScrollingDirection.Y
body.AutomaticCanvasSize = Enum.AutomaticSize.Y
body.CanvasSize = UDim2.new()
body.Parent = panel
local function fitPanel()
    panel.Size = UDim2.fromOffset(math.min(290,math.max(1,root.AbsoluteSize.X-16)),
        math.min(470,math.max(1,root.AbsoluteSize.Y-16)))
end
table.insert(connections,root:GetPropertyChangedSignal('AbsoluteSize'):Connect(fitPanel))
fitPanel()
local layout = Instance.new('UIListLayout', body)
layout.Padding = UDim.new(0,6)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.SortOrder = Enum.SortOrder.LayoutOrder
local order = 0
local function row(text, button, height)
    order = order + 1
    local item = Instance.new(button and 'TextButton' or 'TextLabel')
    item.Size = UDim2.new(1,-16,0,height or 44)
    item.LayoutOrder = order
    item.Text = text
    item.TextSize = 15
    item.Font = Enum.Font.Gotham
    item.TextColor3 = Color3.new(1,1,1)
    item.TextWrapped = true
    item.BackgroundColor3 = Color3.fromRGB(43,49,65)
    item.BorderSizePixel = 0
    item.Parent = body
    Instance.new('UICorner', item).CornerRadius = UDim.new(0,6)
    return item
end
-- Header remains accessible while the settings scroll.
for _, kind in ipairs({'drone', 'missile', 'uav'}) do
    local button = row(names[kind] .. ': ВЫКЛ', true)
    button.Activated:Connect(function()
        enabled[kind] = not enabled[kind]
        button.Text = (kind == 'uav' and 'Все БПЛА' or names[kind]) .. ': ' .. (enabled[kind] and 'ВКЛ' or 'ВЫКЛ')
    end)
end
local rangeButton = row('Дальность: 420 м • +140 м', true)
rangeButton.Activated:Connect(function()
    if calibrating then return end
    automatic = false
    distance = distance >= 5000 and 500 or math.min(5000, distance + 500)
end)
local autoButton = row('Автоподбор дальности', true)
autoButton.Activated:Connect(function()
    if calibrating then return end
    if automatic then automatic = false; return end
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
    end)
end)
local function numberField(placeholder)
    order = order+1
    local field = Instance.new('TextBox')
    field.LayoutOrder = order
    field.Size = UDim2.new(1,-16,0,44)
    field.Text = ''
    field.PlaceholderText = placeholder
    field.TextSize = 14
    field.TextColor3 = Color3.new(1,1,1)
    field.PlaceholderColor3 = Color3.fromRGB(190,190,190)
    field.BackgroundColor3 = Color3.fromRGB(43,49,65)
    field.ClearTextOnFocus = false
    field.Parent = body
    Instance.new('UICorner',field).CornerRadius = UDim.new(0,6)
    return field
end
row('Упреждение: параметры оружия',false)
local bulletSpeed = numberField('Скорость пули, м/с')
local bulletDrop = numberField('Ускорение падения, м/с² (0 = нет)')
local aimStatus = row('Введи оба параметра пули',false,40)
local aimButton = Instance.new('TextButton')
aimButton.AnchorPoint = Vector2.new(1,1)
aimButton.Position = UDim2.new(1,-16,1,-90)
aimButton.Size = UDim2.fromOffset(112,54)
aimButton.Text = 'Удерживать\nнаведение'
aimButton.TextSize = 14
aimButton.TextColor3 = Color3.new(1,1,1)
aimButton.BackgroundColor3 = Color3.fromRGB(43,49,65)
aimButton.BackgroundTransparency = 0.15
aimButton.Parent = root
Instance.new('UICorner',aimButton).CornerRadius = UDim.new(0,12)
local heldInput, lockedTarget
local function releaseAim()
    heldInput, lockedTarget = nil,nil
    aimButton.BackgroundColor3 = Color3.fromRGB(43,49,65)
end
aimButton.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        heldInput = input
        aimButton.BackgroundColor3 = Color3.fromRGB(55,100,75)
    end
end)
table.insert(connections,UserInputService.InputEnded:Connect(function(input)
    if input == heldInput then releaseAim() end
end))
table.insert(connections,UserInputService.WindowFocusReleased:Connect(releaseAim))
-- Local observation only: no firing, remotes, movement or server changes.
local diagnosticRunning = false
local diagnosticResult
local diagnosticButton = row('Диагностика • 60 секунд',true)
local applyButton = row('Применить замер к AIMBOT',true)
local diagnosticInfo = row('Во время проверки стреляй из одного оружия',false,64)
local toast = Instance.new('TextLabel')
toast.AnchorPoint = Vector2.new(0.5,1)
toast.Position = UDim2.new(0.5,0,1,-8)
toast.Size = UDim2.new(1,-16,0,62)
toast.BackgroundColor3 = Color3.fromRGB(24,28,38)
toast.BackgroundTransparency = 0.15
toast.TextColor3 = Color3.new(1,1,1)
toast.TextSize = 13
toast.TextWrapped = true
toast.Visible = false
toast.Parent = root
Instance.new('UICorner',toast).CornerRadius = UDim.new(0,8)
local function equippedWeapon()
    return player.Character and player.Character:FindFirstChildOfClass('Tool')
end
local function median(values)
    table.sort(values)
    local n=#values
    if n==0 then return nil end
    return n%2==1 and values[(n+1)/2] or (values[n/2]+values[n/2+1])/2
end
-- Least-squares fit p(t) = c + v*t + q*t² using actual sample timestamps.
local function fitAxis(samples,axis)
    local sums={0,0,0,0,0}
    local rhs={0,0,0}
    for _,sample in ipairs(samples) do
        local t=sample.t
        local power=1
        for i=1,5 do sums[i]=sums[i]+power; power=power*t end
        local value=sample[axis]
        rhs[1]=rhs[1]+value; rhs[2]=rhs[2]+value*t; rhs[3]=rhs[3]+value*t*t
    end
    local a={{sums[1],sums[2],sums[3],rhs[1]},
        {sums[2],sums[3],sums[4],rhs[2]}, {sums[3],sums[4],sums[5],rhs[3]}}
    for col=1,3 do
        local pivot=col
        for r=col+1,3 do if math.abs(a[r][col])>math.abs(a[pivot][col]) then pivot=r end end
        if math.abs(a[pivot][col])<1e-10 then return end
        a[col],a[pivot]=a[pivot],a[col]
        local divisor=a[col][col]
        for j=col,4 do a[col][j]=a[col][j]/divisor end
        for r=1,3 do
            if r~=col then
                local factor=a[r][col]
                for j=col,4 do a[r][j]=a[r][j]-factor*a[col][j] end
            end
        end
    end
    return a[1][4],a[2][4],a[3][4]
end
local function fitTrack(track)
    local samples=track.samples
    if #samples<8 or samples[#samples].t<0.15 then return end
    local cx,vx,qx=fitAxis(samples,'x')
    local cy,vy,qy=fitAxis(samples,'y')
    local cz,vz,qz=fitAxis(samples,'z')
    if not cx or not cy or not cz then return end
    local speed=Vector3.new(vx,vy,vz).Magnitude
    local gravity=-2*qy
    local horizontalAcceleration=Vector3.new(2*qx,0,2*qz).Magnitude
    if speed<20 or speed>10000/METERS_PER_STUD or gravity < -2 or gravity*METERS_PER_STUD>10000 then return end
    if horizontalAcceleration>math.max(2,math.abs(gravity)*0.1) then return end
    local errorSum=0
    for _,sample in ipairs(samples) do
        local t=sample.t
        local predicted=Vector3.new(cx+vx*t+qx*t*t,cy+vy*t+qy*t*t,cz+vz*t+qz*t*t)
        errorSum=errorSum+(predicted-Vector3.new(sample.x,sample.y,sample.z)).Magnitude^2
    end
    local rms=math.sqrt(errorSum/#samples)
    if rms>math.max(0.15,speed*samples[#samples].t*0.005) then return end
    return {speed=speed*METERS_PER_STUD,gravity=math.max(0,gravity)*METERS_PER_STUD,owned=track.owned}
end
local function ownedProjectile(part)
    local current=part
    for _=1,4 do
        if not current or current==workspace then break end
        for _,key in ipairs({'OwnerUserId','ShooterUserId','PlayerUserId'}) do
            if tonumber(current:GetAttribute(key))==player.UserId then return true end
        end
        for _,key in ipairs({'creator','Creator','Owner','Shooter'}) do
            local value=current:FindFirstChild(key)
            if value and value:IsA('ObjectValue') and (value.Value==player or value.Value==player.Character) then return true end
        end
        current=current.Parent
    end
    return false
end
local function projectileName(part)
    local name=string.lower(part.Name..' '..(part.Parent and part.Parent.Name or ''))
    for _,word in ipairs({'bullet','projectile','tracer','пуля','Пуля','патрон','Патрон'}) do
        if string.find(name,word,1,true) then return true end
    end
    return false
end
local function persistencePath(weapon)
    local encoded=weapon.Name:gsub('.',function(c)return string.format('%02x',string.byte(c))end)
    return 'uav_aim_'..tostring(game.PlaceId)..'_'..encoded..'.json'
end
applyButton.Activated:Connect(function()
    if diagnosticRunning then return end
    local result=diagnosticResult
    local weapon=equippedWeapon()
    if not result or not result.valid then diagnosticInfo.Text='Нет достоверного результата для применения'; return end
    if not weapon or weapon.Name~=result.weapon then diagnosticInfo.Text='Возьми оружие, для которого выполнен замер'; return end
    bulletSpeed.Text=string.format('%.3f',result.speed)
    bulletDrop.Text=string.format('%.3f',result.gravity)
    local saved=false
    if type(writefile)=='function' then
        saved=pcall(function()
            writefile(persistencePath(weapon),game:GetService('HttpService'):JSONEncode({version=1,
                placeId=game.PlaceId,weapon=result.weapon,speed=result.speed,gravity=result.gravity}))
        end)
    end
    diagnosticInfo.Text=saved and 'Применено и сохранено на устройстве' or 'Применено на эту сессию; запись файла недоступна'
    toast.Text=diagnosticInfo.Text
end)
-- Saved estimates are loaded explicitly so a stale profile is never silently activated.
row('Загрузить сохранённый замер',true).Activated:Connect(function()
    if diagnosticRunning then return end
    local weapon=equippedWeapon()
    if not weapon or type(readfile)~='function' then diagnosticInfo.Text='Возьми оружие; требуется доступ к сохранённому файлу'; return end
    local ok,data=pcall(function() return game:GetService('HttpService'):JSONDecode(readfile(persistencePath(weapon))) end)
    if not ok or type(data)~='table' or data.version~=1 or data.placeId~=game.PlaceId or data.weapon~=weapon.Name
        or type(data.speed)~='number' or not (data.speed>0 and data.speed<=10000)
        or type(data.gravity)~='number' or not (data.gravity>=0 and data.gravity<=10000) then
        diagnosticInfo.Text='Подходящий сохранённый замер не найден'; return
    end
    diagnosticResult={valid=true,weapon=data.weapon,speed=data.speed,gravity=data.gravity}
    diagnosticInfo.Text='Загружен замер для '..data.weapon..'. Нажми «Применить»'
end)
diagnosticButton.Activated:Connect(function()
    if diagnosticRunning then return end
    local weapon=equippedWeapon()
    if not weapon then diagnosticInfo.Text='Сначала возьми автомат в руки'; return end
    diagnosticRunning=true
    diagnosticResult=nil
    releaseAim()
    toast.Visible=true
    local start=os.clock()
    local tracks,results={},{}
    local candidatesSeen,unowned,accepted,active=0,0,0,0
    local invalidWeapon=false
    local listener
    local function finishTrack(part)
        local track=tracks[part]
        if not track then return end
        local fit=fitTrack(track)
        if fit then
            if fit.owned then accepted=accepted+1; table.insert(results,fit)
            else unowned=unowned+1 end
        end
        tracks[part]=nil
        active=active-1
    end
    listener=workspace.DescendantAdded:Connect(function(part)
        if not diagnosticRunning or not part:IsA('BasePart') or not projectileName(part) then return end
        candidatesSeen=candidatesSeen+1
        if active>=32 or accepted>=120 then return end
        local head=player.Character and player.Character:FindFirstChild('Head')
        if not head or (part.Position-head.Position).Magnitude>40 then return end
        tracks[part]={samples={},start=os.clock(),origin=part.Position,owned=ownedProjectile(part)}
        active=active+1
    end)
    table.insert(connections,listener)
    task.spawn(function()
        while alive and os.clock()-start<60 do
            RunService.Heartbeat:Wait()
            if not alive then break end
            if equippedWeapon()~=weapon then invalidWeapon=true end
            local now=os.clock()
            for part,track in pairs(tracks) do
                if not part:IsDescendantOf(workspace) or now-track.start>1.5 then finishTrack(part)
                else
                    track.owned=track.owned or ownedProjectile(part)
                    local position=part.Position-track.origin
                    table.insert(track.samples,{t=now-track.start,x=position.X,y=position.Y,z=position.Z})
                end
            end
            local left=math.max(0,math.ceil(60-(now-start)))
            diagnosticButton.Text='Проверка: '..left..' с'
            toast.Text='Проверка: '..left..' с • стреляй вручную из одного автомата\nКандидатов: '..candidatesSeen..' • подтверждено траекторий: '..accepted
        end
        listener:Disconnect()
        diagnosticRunning=false
        if not alive then return end
        for part in pairs(tracks) do finishTrack(part) end
        diagnosticButton.Text='Диагностика • 60 секунд'
        local speeds,gravities={},{}
        for _,result in ipairs(results) do table.insert(speeds,result.speed); table.insert(gravities,result.gravity) end
        local speed,gravity=median(speeds),median(gravities)
        local consistent=0
        if speed then
            for _,result in ipairs(results) do
                if math.abs(result.speed-speed)<=speed*0.08 and math.abs(result.gravity-gravity)<=math.max(0.5,gravity*0.15) then consistent=consistent+1 end
            end
        end
        if not invalidWeapon and accepted>=8 and consistent>=math.ceil(accepted*0.8) then
            diagnosticResult={valid=true,weapon=weapon.Name,speed=speed,gravity=gravity}
            diagnosticInfo.Text=string.format('Оценка: %.1f м/с; падение %.2f м/с². Можно применить.',speed,gravity)
        elseif invalidWeapon then diagnosticInfo.Text='Оружие сменилось во время проверки. Повтори замер.'
        elseif accepted<8 then diagnosticInfo.Text='Недостаточно подтверждённых своих пуль. Чужие/неопознанные: '..unowned
        else diagnosticInfo.Text='Траектории нестабильны или не подходят модели AIMBOT.' end
        toast.Text='Проверка завершена\n'..diagnosticInfo.Text
    end)
end)

local status = row('Поиск объектов…', false, 40)
row('Выключить и удалить ESP', true).Activated:Connect(function() gui:Destroy() end)

table.insert(connections, workspace.DescendantAdded:Connect(register))
table.insert(connections, workspace.DescendantRemoving:Connect(function(object)
    candidates[object] = nil
    clearMark(object)
end))
task.spawn(function()
    for i, object in ipairs(workspace:GetDescendants()) do
        if not alive then return end
        register(object)
        if i % 400 == 0 then task.wait() end
    end
end)
local function mark(object, part)
    local billboard = Instance.new('BillboardGui')
    billboard.Name = 'UAV_ESP_Marker'
    billboard.Size = UDim2.fromOffset(64,32)
    billboard.AlwaysOnTop = true
    billboard.Adornee = part
    billboard.Parent = gui
    local dot = Instance.new('Frame')
    dot.Name = 'Dot'
    dot.AnchorPoint = Vector2.new(0.5,0.5)
    dot.Position = UDim2.fromScale(0.5,0.5)
    dot.Size = UDim2.fromOffset(4,4)
    dot.BorderSizePixel = 0
    dot.BackgroundTransparency = 0.15
    dot.Parent = billboard
    Instance.new('UICorner',dot).CornerRadius = UDim.new(1,0)
    local label = Instance.new('TextLabel')
    label.Name = 'Distance'
    label.Position = UDim2.new(0,0,0.5,4)
    label.Size = UDim2.new(1,0,0,12)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(220,220,220)
    label.TextTransparency = 0.3
    label.TextStrokeTransparency = 0.65
    label.TextSize = 10
    label.Font = Enum.Font.Gotham
    label.Parent = billboard
    local outline = Instance.new('Highlight')
    outline.Name = 'ESP_Outline'
    outline.Adornee = object
    outline.FillTransparency = 1
    outline.OutlineColor = Color3.new(1,1,1)
    outline.OutlineTransparency = 0.2
    outline.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    outline.Parent = object
    outlines[object] = outline
    local speed = Instance.new('TextLabel')
    speed.Name = 'ESP_Speed'
    speed.AnchorPoint = Vector2.new(0.5,1)
    speed.Size = UDim2.fromOffset(100,16)
    speed.BackgroundTransparency = 1
    speed.TextColor3 = Color3.new(1,1,1)
    speed.TextTransparency = 0.15
    speed.TextStrokeTransparency = 0.65
    speed.TextSize = 11
    speed.Font = Enum.Font.Gotham
    speed.Visible = false
    speed.Parent = root
    speedLabels[object] = speed
    motion[object] = {part = part, position = part.Position, time = os.clock()}
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
        if fps < 28 then distance = math.max(300, math.floor(distance*0.8))
        elseif fps > 55 then distance = math.min(5000, distance+200) end
    end
    rangeButton.Text = string.format('Дальность: %d м • +140 м',math.floor(distance*METERS_PER_STUD+0.5))
    if not calibrating then autoButton.Text = automatic and 'Авто: ВКЛ • нажми выключить' or 'Автоподбор дальности' end
    local camera = workspace.CurrentCamera
    if not camera then return end
    local visible, found = {}, 0
    for object, kind in pairs(candidates) do
        if object:IsDescendantOf(workspace) then
            found = found+1
            local nested, ancestor = false, object.Parent
            while ancestor and ancestor ~= workspace do
                if candidates[ancestor] or ancestor == player.Character or ancestor:IsA('Tool') then nested = true; break end
                ancestor = ancestor.Parent
            end
            if not nested and (enabled[kind] or enabled.uav) then
                local part = object:IsA('BasePart') and object or (object.PrimaryPart or object:FindFirstChildWhichIsA('BasePart',true))
                if part then
                    local d = (camera.CFrame.Position-part.Position).Magnitude
                    if d <= distance then table.insert(visible,{object=object,part=part,kind=kind,d=d}) end
                end
            end
        end
    end
    table.sort(visible,function(a,b) return a.d < b.d end)
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = player.Character and {player.Character,camera} or {camera}
    local keep, count = {}, math.min(#visible,48)
    for i=1,count do
        local item = visible[i]
        keep[item.object] = true
        local billboard = marks[item.object] or mark(item.object,item.part)
        local sample = motion[item.object]
        local now = os.clock()
        local delta = now-sample.time
        if sample.part ~= item.part then
            sample.speed, sample.velocity = nil,nil
        elseif delta >= 0.15 then
            -- Position samples also cover anchored objects moved with PivotTo/CFrame.
            local velocity = (item.part.Position-sample.position)/delta
            sample.velocity = sample.velocity and sample.velocity:Lerp(velocity,0.5) or velocity
            local measured = velocity.Magnitude
            sample.speed = sample.speed and (sample.speed*0.5+measured*0.5) or measured
        end
        if delta >= 0.15 or sample.part ~= item.part then
            sample.position, sample.time, sample.part = item.part.Position, now, item.part
        end
        speedLabels[item.object].Text = sample.speed and string.format('%d км/ч',math.floor(sample.speed*METERS_PER_STUD*3.6+0.5)) or '— км/ч'
        billboard.Adornee = item.part
        billboard.MaxDistance = distance
        local _, onScreen = camera:WorldToViewportPoint(item.part.Position)
        billboard.Enabled = onScreen
        if onScreen then
            local hit = workspace:Raycast(camera.CFrame.Position,
                item.part.Position-camera.CFrame.Position,rayParams)
            local unobstructed = not hit or hit.Instance == item.object or hit.Instance:IsDescendantOf(item.object)
            billboard.Dot.BackgroundColor3 = unobstructed and clearColor or blockedColor
            billboard.Distance.Text = string.format('%d м',math.floor(item.d*METERS_PER_STUD+0.5))
        end
    end
    for object in pairs(marks) do if not keep[object] then clearMark(object) end end
    status.Text = string.format('FPS: %d • кандидатов: %d • меток: %d\nРаспознавание по именам',math.floor(fps),found,count)
end))

-- Reproject the top of the object's bounds every frame so the caption follows the camera.
table.insert(connections, RunService.RenderStepped:Connect(function()
    local camera = workspace.CurrentCamera
    for object, label in pairs(speedLabels) do
        label.Visible = false
        local outline = outlines[object]
        outline.Enabled = false
        if camera and object:IsDescendantOf(workspace) then
            local cf, size
            if object:IsA('Model') then cf, size = object:GetBoundingBox()
            else cf, size = object.CFrame, object.Size end
            local center, onScreen = camera:WorldToViewportPoint(cf.Position)
            outline.Enabled = onScreen
            if onScreen then
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
        end
    end
end))

-- Constant-speed projectile with downward acceleration; constant-velocity target.
-- No drag, wind or inherited shooter velocity: these require the weapon's real model.
local function intercept(relative, velocity, speed, gravity)
    local acceleration = Vector3.new(0,-gravity,0)
    local function residual(t)
        return (relative+velocity*t-acceleration*(0.5*t*t)).Magnitude-speed*t
    end
    local previousTime = 0
    for step=1,120 do
        local t = step*0.05
        if residual(t) <= 0 then
            local low, high = previousTime,t
            for _=1,18 do
                local mid = (low+high)*0.5
                if residual(mid)>0 then low=mid else high=mid end
            end
            local flightTime = (low+high)*0.5
            return relative+velocity*flightTime-acceleration*(0.5*flightTime*flightTime)
        end
        previousTime=t
    end
end
local function parameter(field)
    return tonumber((field.Text:gsub(',','.')))
end
-- Run after Roblox's camera controller. Releasing the button restores normal camera updates.
local aimBinding = 'UAV_ESP_HoldAim'
gui.Destroying:Connect(function()
    releaseAim()
    RunService:UnbindFromRenderStep(aimBinding)
end)
RunService:BindToRenderStep(aimBinding,Enum.RenderPriority.Camera.Value+1,function()
    if not alive then return end
    local speed, gravity = parameter(bulletSpeed),parameter(bulletDrop)
    if not speed or speed<=0 or speed>10000 or not gravity or gravity<0 or gravity>10000 then
        aimStatus.Text = 'Введи скорость > 0 и падение ≥ 0'
        lockedTarget = nil
        return
    end
    if diagnosticRunning then
        releaseAim()
        aimStatus.Text='Диагностика: наведение приостановлено'
        return
    end
    if not heldInput or UserInputService:GetFocusedTextBox() then
        aimStatus.Text = 'Удерживай кнопку • цель у прицела'
        lockedTarget = nil
        return
    end
    local camera = workspace.CurrentCamera
    local character = player.Character
    local head = character and character:FindFirstChild('Head')
    if not camera or not head then return end
    local origin = head.Position
    -- Prefer a conventional muzzle attachment; fall back to the character's head.
    local tool = character:FindFirstChildOfClass('Tool')
    local muzzle = tool and (tool:FindFirstChild('Muzzle',true) or tool:FindFirstChild('MuzzleAttachment',true))
    if muzzle then
        if muzzle:IsA('Attachment') then origin=muzzle.WorldPosition
        elseif muzzle:IsA('BasePart') then origin=muzzle.Position end
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {character,camera}
    local center = camera.ViewportSize*0.5
    local radius = math.min(camera.ViewportSize.X,camera.ViewportSize.Y)*0.22
    local best, bestDistance = nil, radius
    for object, sample in pairs(motion) do
        local part = sample.part
        if part and part:IsDescendantOf(workspace) and sample.velocity then
            local kind = candidates[object]
            local point,onScreen = camera:WorldToViewportPoint(part.Position)
            local screenDistance = (Vector2.new(point.X,point.Y)-center).Magnitude
            if kind and (enabled[kind] or enabled.uav) and onScreen and screenDistance<=radius
                and (part.Position-origin).Magnitude<=distance then
                local hit = workspace:Raycast(origin,part.Position-origin,params)
                if not hit or hit.Instance==object or hit.Instance:IsDescendantOf(object) then
                    if object==lockedTarget then best=object; break end
                    if screenDistance<bestDistance then best,bestDistance=object,screenDistance end
                end
            end
        end
    end
    lockedTarget=best
    if not best then aimStatus.Text='Нет видимой цели у прицела'; return end
    local sample=motion[best]
    local direction=intercept(sample.part.Position-origin,sample.velocity,speed/METERS_PER_STUD,gravity/METERS_PER_STUD)
    if not direction or direction.Magnitude<0.001 then
        aimStatus.Text='Нет решения до 6 с полёта'; return
    end
    camera.CFrame=CFrame.lookAt(camera.CFrame.Position,camera.CFrame.Position+direction)
    aimStatus.Text='Наведение • расчётное упреждение'
end)

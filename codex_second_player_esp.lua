-- Второй скрипт от Codex | FPV Drone Game | v1.0.0
-- Independent companion: keep this file separate from other ESP scripts.
-- No existing repository files or other scripts' interfaces are modified.
-- Drone status uses replicated boolean flags only; unknown is NEVER treated as false.
-- Roblox standard scale: 1 stud = 0.28 m (adjustable in this menu).
local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local UIS = game:GetService('UserInputService')
local Http = game:GetService('HttpService')
local Workspace = game:GetService('Workspace')
local me = Players.LocalPlayer
if not me then return end
local playerGui = me:WaitForChild('PlayerGui')
local env = (getgenv and getgenv()) or _G
local KEY = '__CodexSecondPlayerESP_v1'
if type(env[KEY]) == 'function' then pcall(env[KEY]) end
local alive, connections, records = true, {}, {}
local defaults = {enabled=true, boxes=true, names=true, distance=true, status=true,
    tracers=false, arrows=true, health=false, teamFilter=false, teamColor=false,
    visibleOnly=false, visibility=true, maxDistance=1500, maxPlayers=24,
    fps=30, textSize=14, thickness=1, opacity=0.85, scale=0.28,
    color=1, origin=1, font=1, statusKey='', menuX=0.03, menuY=0.12}
local cfg = {}
for k,v in pairs(defaults) do cfg[k]=v end
local limits = {maxDistance={50,10000},maxPlayers={1,64},fps={10,60},textSize={10,22},
    thickness={1,3},opacity={0.2,1},scale={0.01,10},color={1,5},origin={1,3},font={1,3},menuX={0,1},menuY={0,1}}
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
local function validate(k,v)
    local d=defaults[k]
    if type(d)=='boolean' then return type(v)=='boolean' and v or (v~=false and d) end
    if limits[k] and finite(v) then
        local n=math.clamp(v,limits[k][1],limits[k][2])
        if k=='color' or k=='origin' or k=='font' or k=='maxPlayers' or k=='fps' then n=math.floor(n) end
        return n
    end
    if k=='statusKey' and type(v)=='string' and #v<=80 then return v end
    return d
end
local savePath='codex_second_esp_'..tostring(game.PlaceId)..'.json'
if type(readfile)=='function' then
    pcall(function()
        local raw=readfile(savePath)
        if #raw>16384 then return end
        local data=Http:JSONDecode(raw)
        if type(data)~='table' then return end
        for k in pairs(defaults) do if data[k]~=nil then cfg[k]=validate(k,data[k]) end end
    end)
end
local dirtyAt
local function dirty() dirtyAt=os.clock() end
local function save()
    if type(writefile)~='function' then return false end
    return pcall(function() writefile(savePath,Http:JSONEncode(cfg)) end)
end
local function connect(event,fn)
    local c=event:Connect(fn); connections[#connections+1]=c; return c
end
local function make(class,props,parent)
    local o=Instance.new(class)
    for k,v in pairs(props or {}) do o[k]=v end
    o.Parent=parent; return o
end
local function round(o,r) make('UICorner',{CornerRadius=UDim.new(0,r or 8)},o) end
local colors={Color3.fromRGB(225,236,255),Color3.fromRGB(110,210,255),Color3.fromRGB(190,155,255),Color3.fromRGB(255,195,100),Color3.fromRGB(115,245,185)}
local fonts={Enum.Font.GothamMedium,Enum.Font.GothamBold,Enum.Font.Code}
local green,red,gray=Color3.fromRGB(93,235,145),Color3.fromRGB(255,102,120),Color3.fromRGB(167,178,195)
local overlay=make('ScreenGui',{Name='CodexSecondESP_Overlay',ResetOnSpawn=false,IgnoreGuiInset=true,DisplayOrder=50,ZIndexBehavior=Enum.ZIndexBehavior.Sibling},playerGui)
pcall(function() overlay.ScreenInsets=Enum.ScreenInsets.None end)
local ui=make('ScreenGui',{Name='CodexSecondESP_Menu',ResetOnSpawn=false,DisplayOrder=60,ZIndexBehavior=Enum.ZIndexBehavior.Sibling},playerGui)
pcall(function() ui.ScreenInsets=Enum.ScreenInsets.DeviceSafeInsets end)
local safe=make('Frame',{Size=UDim2.fromScale(1,1),BackgroundTransparency=1},ui)
local menu=make('Frame',{BackgroundColor3=Color3.fromRGB(19,24,35),BorderSizePixel=0,ClipsDescendants=true},safe);round(menu,12)
make('UIStroke',{Color=Color3.fromRGB(65,83,113),Thickness=1},menu)
local title=make('TextLabel',{Size=UDim2.new(1,-58,0,50),Position=UDim2.fromOffset(12,0),BackgroundTransparency=1,Text='Второй скрипт от Codex',TextColor3=colors[1],TextSize=14,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Left,Active=true},menu)
local function button(parent,text,pos,size)
    local b=make('TextButton',{Text=text,Position=pos,Size=size,BackgroundColor3=Color3.fromRGB(38,49,68),TextColor3=colors[1],TextSize=13,Font=Enum.Font.GothamMedium,BorderSizePixel=0,AutoButtonColor=true},parent);round(b,7);return b
end
local collapse=button(menu,'×',UDim2.new(1,-42,0,8),UDim2.fromOffset(34,34))
local opener=button(safe,'Codex ESP',UDim2.fromOffset(12,12),UDim2.fromOffset(112,42));opener.Visible=false
local list=make('ScrollingFrame',{Position=UDim2.fromOffset(10,52),Size=UDim2.new(1,-20,1,-62),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=3,CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y,ScrollingDirection=Enum.ScrollingDirection.Y},menu)
make('UIListLayout',{Padding=UDim.new(0,7),SortOrder=Enum.SortOrder.LayoutOrder},list)
make('UIPadding',{PaddingBottom=UDim.new(0,10),PaddingRight=UDim.new(0,5)},list)
local order=0
local function row(o) order=order+1;o.LayoutOrder=order;return o end
local function note(text,height)
    return row(make('TextLabel',{Size=UDim2.new(1,0,0,height or 44),BackgroundTransparency=1,Text=text,TextWrapped=true,TextColor3=gray,TextSize=12,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left},list))
end
local summary=note('FPV Drone Game • ESP игроков\n× скрывает меню, ESP продолжает работать',40)
local refreshers={}
local function toggle(k,label)
    local b=row(button(list,'',UDim2.new(),UDim2.new(1,0,0,37)))
    local function refresh() b.Text=label..'   '..(cfg[k] and 'ВКЛ' or 'ВЫКЛ');b.TextColor3=cfg[k] and colors[2] or gray end
    refreshers[#refreshers+1]=refresh;refresh()
    connect(b.Activated,function() cfg[k]=not cfg[k];dirty();refresh() end)
end
for _,r in ipairs({{'enabled','ESP игроков'},{'boxes','3D-боксы'},{'names','Никнеймы'},{'distance','Расстояние'},{'status','Карточка режима дрона'},{'arrows','Стрелки вне экрана'},{'tracers','Трассеры'},{'health','Здоровье'},{'teamFilter','Скрыть союзников'},{'teamColor','Цвет команды'},{'visibility','Затемнять за стенами'},{'visibleOnly','Только видимые игроки'}}) do toggle(r[1],r[2]) end
local function cycle(k,label,values,labels)
    local b=row(button(list,'',UDim2.new(),UDim2.new(1,0,0,37)))
    local function refresh()
        local display=tostring(cfg[k]);for i,v in ipairs(values) do if v==cfg[k] then display=labels and labels[i] or tostring(v) end end
        b.Text=label..': '..display
    end
    refreshers[#refreshers+1]=refresh;refresh()
    connect(b.Activated,function()
        local idx=0;for i,v in ipairs(values) do if v==cfg[k] then idx=i;break end end
        cfg[k]=values[idx % #values+1];dirty();refresh()
    end)
end
cycle('maxDistance','Дальность, м',{100,250,500,1000,1500,3000,10000})
cycle('maxPlayers','Максимум игроков',{8,16,24,32,64})
cycle('fps','Частота ESP',{15,30,60})
cycle('textSize','Размер подписей',{12,14,16,18,20})
cycle('thickness','Толщина линий',{1,2,3})
cycle('opacity','Яркость',{0.4,0.6,0.85,1},{'40%','60%','85%','100%'})
cycle('color','Цвет',{1,2,3,4,5},{'Белый','Голубой','Лиловый','Золотой','Мятный'})
cycle('origin','Начало трассеров',{1,2,3},{'Снизу','Центр','Сверху'})
cycle('font','Шрифт',{1,2,3},{'Gotham','Gotham Bold','Code'})
cycle('scale','Метров в stud',{0.28,1},{'0.28 — стандарт','1 — масштаб режима'})
note('Статус: зелёный — не в дроне; красный — в дроне; серый — нет данных. Автопоиск флагов не подтверждён для этой игры.',66)
note('Точное имя Boolean-атрибута или BoolValue (необязательно):',34)
local statusInput=row(make('TextBox',{Size=UDim2.new(1,0,0,38),BackgroundColor3=Color3.fromRGB(30,39,55),TextColor3=colors[1],PlaceholderText='Автопоиск: InDrone, DroneMode…',Text=cfg.statusKey,ClearTextOnFocus=false,TextSize=12,Font=Enum.Font.Gotham,BorderSizePixel=0},list));round(statusInput)
connect(statusInput.FocusLost,function() cfg.statusKey=validate('statusKey',statusInput.Text);statusInput.Text=cfg.statusKey;dirty() end)
local info=note('Определяются только доступные клиенту Boolean-флаги. Наличие дрона у игрока само по себе не означает управление.',60)
local inspect=row(button(list,'Источники статуса игроков',UDim2.new(),UDim2.new(1,0,0,37)))
connect(inspect.Activated,function()
    local lines={};for p,r in pairs(records) do lines[#lines+1]=p.Name..': '..(r.source or 'нет данных') end
    table.sort(lines);info.Text=table.concat(lines,'\n');info.Size=UDim2.new(1,0,0,math.min(400,math.max(60,#lines*30)))
end)
local reset=row(button(list,'Сбросить настройки',UDim2.new(),UDim2.new(1,0,0,37)))
local stop=row(button(list,'Выключить этот скрипт',UDim2.new(),UDim2.new(1,0,0,37)))
local function layout()
    local s=safe.AbsoluteSize
    local w,h=math.max(1,math.min(330,s.X-16)),math.max(1,math.min(570,s.Y-16))
    menu.Size=UDim2.fromOffset(w,h)
    menu.Position=UDim2.fromOffset(8+cfg.menuX*math.max(0,s.X-w-16),8+cfg.menuY*math.max(0,s.Y-h-16))
    opener.Position=UDim2.fromOffset(math.clamp(menu.Position.X.Offset,0,math.max(0,s.X-112)),math.clamp(menu.Position.Y.Offset,0,math.max(0,s.Y-42)))
end
connect(reset.Activated,function() for k,v in pairs(defaults) do cfg[k]=v end;for _,f in ipairs(refreshers) do f() end;statusInput.Text='';layout();dirty() end)
connect(safe:GetPropertyChangedSignal('AbsoluteSize'),layout);layout()
connect(collapse.Activated,function() menu.Visible=false;opener.Visible=true;layout() end)
connect(opener.Activated,function() menu.Visible=true;opener.Visible=false end)
local dragging,dragStart,startPosition
connect(title.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=input;dragStart=input.Position;startPosition=menu.Position
    end
end)
connect(UIS.InputChanged,function(input)
    if not dragging then return end
    if input~=dragging and input.UserInputType~=Enum.UserInputType.MouseMovement then return end
    local delta=input.Position-dragStart;local s=safe.AbsoluteSize;local m=menu.AbsoluteSize
    cfg.menuX=math.clamp((startPosition.X.Offset+delta.X-8)/math.max(1,s.X-m.X-16),0,1)
    cfg.menuY=math.clamp((startPosition.Y.Offset+delta.Y-8)/math.max(1,s.Y-m.Y-16),0,1);layout()
end)
connect(UIS.InputEnded,function(input) if input==dragging then dragging=nil;dirty() end end)
local function cleanup()
    if not alive then return end;alive=false;save()
    for _,c in ipairs(connections) do c:Disconnect() end
    overlay:Destroy();ui:Destroy();table.clear(records)
    env[KEY]=nil
end
env[KEY]=cleanup
connect(stop.Activated,cleanup)
-- Returns only explicit booleans. Conflicting replicated values remain unknown.
local statusAliases={'InDrone','IsInDrone','DroneMode','IsDroneMode','ControllingDrone','IsControllingDrone','PilotingDrone','IsPilotingDrone','UsingDrone'}
local function mergeStatus(a,b)
    if b==nil then return a end
    if a==nil then return b end
    if a~=b then return 'conflict' end
    return a
end
local function droneStatus(player,character)
    local result,source=nil,nil
    local keys=cfg.statusKey~='' and {cfg.statusKey} or statusAliases
    local containers={player}
    if character then containers[#containers+1]=character end
    -- Only bounded, shallow containers; never scan Workspace or execute modules.
    for _,root in ipairs({player,character}) do
        if root then for _,name in ipairs({'Settings','Status','State','Data'}) do
            local f=root:FindFirstChild(name);if f then containers[#containers+1]=f end
        end end
    end
    for _,container in ipairs(containers) do for _,key in ipairs(keys) do
        local a=container:GetAttribute(key)
        if type(a)=='boolean' then result=mergeStatus(result,a);source=container.Name..'.@'..key end
        local v=container:FindFirstChild(key)
        if v and v:IsA('BoolValue') then result=mergeStatus(result,v.Value);source=container.Name..'.'..key end
    end end
    if result=='conflict' then return nil,'конфликт флагов' end
    return result,source
end
local function newLine(parent)
    return make('Frame',{AnchorPoint=Vector2.new(0.5,0.5),BorderSizePixel=0,BackgroundColor3=colors[1],Visible=false},parent)
end
local function add(player)
    if player==me or records[player] then return end
    local root=make('Frame',{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Visible=false},overlay)
    local r={root=root,edges={}}
    for i=1,12 do r.edges[i]=newLine(root) end
    r.tracer=newLine(root)
    r.card=make('Frame',{AnchorPoint=Vector2.new(0.5,1),Size=UDim2.fromOffset(160,78),BackgroundTransparency=1},root)
    r.badge=make('Frame',{Size=UDim2.new(1,0,0,22),BackgroundColor3=Color3.fromRGB(15,20,30),BackgroundTransparency=0.15,BorderSizePixel=0},r.card);round(r.badge,6)
    r.dot=make('Frame',{Position=UDim2.fromOffset(8,7),Size=UDim2.fromOffset(7,7),BackgroundColor3=gray,BorderSizePixel=0},r.badge);round(r.dot,8)
    r.state=make('TextLabel',{Position=UDim2.fromOffset(20,0),Size=UDim2.new(1,-22,1,0),BackgroundTransparency=1,Text='НЕТ ДАННЫХ',TextSize=11,TextColor3=gray,Font=Enum.Font.GothamMedium},r.badge)
    r.label=make('TextLabel',{Position=UDim2.fromOffset(0,25),Size=UDim2.new(1,0,0,46),BackgroundTransparency=1,Text='',TextColor3=colors[1],TextStrokeTransparency=0.35,TextStrokeColor3=Color3.new(),TextSize=14,Font=fonts[1]},r.card)
    r.healthBack=make('Frame',{Position=UDim2.new(0.15,0,1,-4),Size=UDim2.new(0.7,0,0,3),BorderSizePixel=0,BackgroundColor3=Color3.fromRGB(35,35,40)},r.card)
    r.health=make('Frame',{Size=UDim2.fromScale(1,1),BorderSizePixel=0,BackgroundColor3=green},r.healthBack)
    r.arrow=make('TextLabel',{AnchorPoint=Vector2.new(0.5,0.5),Size=UDim2.fromOffset(24,24),BackgroundTransparency=1,Text='▲',TextSize=22,Font=Enum.Font.GothamBold,TextColor3=colors[1],TextStrokeTransparency=0.3,Visible=false},root)
    records[player]=r
end
local function remove(player) local r=records[player];if r then r.root:Destroy();records[player]=nil end end
connect(Players.PlayerAdded,add);connect(Players.PlayerRemoving,remove)
for _,p in ipairs(Players:GetPlayers()) do add(p) end
-- Liang-Barsky viewport clipping prevents huge rotated GUI frames near the camera.
local function clipLine(x1,y1,x2,y2,w,h)
    local dx,dy=x2-x1,y2-y1;local lo,hi=0,1
    local p={-dx,dx,-dy,dy};local q={x1,w-x1,y1,h-y1}
    for i=1,4 do
        if math.abs(p[i])<1e-9 then if q[i]<0 then return nil end
        else
            local t=q[i]/p[i]
            if p[i]<0 then lo=math.max(lo,t) else hi=math.min(hi,t) end
            if lo>hi then return nil end
        end
    end
    return x1+lo*dx,y1+lo*dy,x1+hi*dx,y1+hi*dy
end
local function edgePoint(dx,dy,w,h)
    if math.abs(dx)+math.abs(dy)<0.001 then dx,dy=0,1 end
    local scale=1/math.max(math.abs(dx)/math.max(1,w/2-28),math.abs(dy)/math.max(1,h/2-40))
    return w/2+dx*scale,h/2+dy*scale,math.deg(math.atan2(dy,dx))+90
end
local function drawLine(frame,a,b,color,alpha,viewport)
    local x1,y1,x2,y2=clipLine(a.X,a.Y,b.X,b.Y,viewport.X,viewport.Y)
    if not x1 then frame.Visible=false;return end
    local dx,dy=x2-x1,y2-y1;local len=math.sqrt(dx*dx+dy*dy)
    frame.Visible=len>0.1
    if not frame.Visible then return end
    frame.Position=UDim2.fromOffset((x1+x2)/2,(y1+y2)/2);frame.Size=UDim2.fromOffset(len,cfg.thickness)
    frame.Rotation=math.deg(math.atan2(dy,dx));frame.BackgroundColor3=color;frame.BackgroundTransparency=1-alpha
end
local corners={Vector3.new(-1,-1,-1),Vector3.new(1,-1,-1),Vector3.new(1,1,-1),Vector3.new(-1,1,-1),Vector3.new(-1,-1,1),Vector3.new(1,-1,1),Vector3.new(1,1,1),Vector3.new(-1,1,1)}
local edges={{1,2},{2,3},{3,4},{4,1},{5,6},{6,7},{7,8},{8,5},{1,5},{2,6},{3,7},{4,8}}
local function bodyBounds(character,root)
    local low,high=Vector3.new(math.huge,math.huge,math.huge),Vector3.new(-math.huge,-math.huge,-math.huge)
    for _,part in ipairs(character:GetChildren()) do if part:IsA('BasePart') then
        for _,sign in ipairs(corners) do
            local p=root.CFrame:PointToObjectSpace(part.CFrame:PointToWorldSpace(sign*part.Size*0.5))
            low=Vector3.new(math.min(low.X,p.X),math.min(low.Y,p.Y),math.min(low.Z,p.Z))
            high=Vector3.new(math.max(high.X,p.X),math.max(high.Y,p.Y),math.max(high.Z,p.Z))
        end
    end end
    return (low+high)*0.5,(high-low)*0.5+Vector3.new(0.1,0.1,0.1)
end
local function nearClip(a,b)
    local z=-0.1
    if a.Z>z and b.Z>z then return nil end
    if a.Z>z then a=a:Lerp(b,(z-a.Z)/(b.Z-a.Z))
    elseif b.Z>z then b=b:Lerp(a,(z-b.Z)/(a.Z-b.Z)) end
    return a,b
end
local ray=RaycastParams.new();ray.FilterType=Enum.RaycastFilterType.Exclude;ray.IgnoreWater=true
local selected={}
local function refresh(camera)
    selected={}
    local own=me.Character and me.Character:FindFirstChild('HumanoidRootPart')
    local from=own and own.Position or camera.CFrame.Position
    for p,r in pairs(records) do
        r.root.Visible=false
        local char=p.Character;local hum=char and char:FindFirstChildOfClass('Humanoid')
        local root=char and char:FindFirstChild('HumanoidRootPart')
        local teammate=not me.Neutral and not p.Neutral and me.Team~=nil and me.Team==p.Team
        if root and root:IsA('BasePart') and hum and hum.Health>0 and not (cfg.teamFilter and teammate) then
            local distance=(root.Position-from).Magnitude*cfg.scale
            if distance<=cfg.maxDistance then
                r.player=p;r.character=char;r.part=root;r.humanoid=hum;r.distance=distance
                selected[#selected+1]=r
            end
        end
    end
    table.sort(selected,function(a,b) return a.distance<b.distance end)
    for i=#selected,cfg.maxPlayers+1,-1 do selected[i]=nil end
    for _,r in ipairs(selected) do
        r.offset,r.extent=bodyBounds(r.character,r.part)
        r.drone,r.source=droneStatus(r.player,r.character)
        r.visible=true
        if cfg.visibility or cfg.visibleOnly then
            ray.FilterDescendantsInstances=me.Character and {me.Character} or {}
            local head=r.character:FindFirstChild('Head')
            local points={r.part.Position};if head and head:IsA('BasePart') then points[#points+1]=head.Position end
            r.visible=false
            for _,pos in ipairs(points) do
                local hit=Workspace:Raycast(camera.CFrame.Position,pos-camera.CFrame.Position,ray)
                if not hit or hit.Instance:IsDescendantOf(r.character) then r.visible=true;break end
            end
        end
    end
end
local function render(camera)
    local size=camera.ViewportSize
    for _,r in ipairs(selected) do
        local root=r.part
        r.root.Visible=cfg.enabled and root.Parent~=nil and r.player.Character==r.character and r.humanoid.Health>0 and (not cfg.visibleOnly or r.visible)
        if r.root.Visible then
            local color=cfg.teamColor and not r.player.Neutral and r.player.TeamColor.Color or colors[cfg.color]
            local alpha=cfg.opacity*((cfg.visibility and not r.visible) and 0.4 or 1)
            local point,onScreen=camera:WorldToViewportPoint(root.Position)
            local front=point.Z>0.1
            local inView=front and onScreen
            r.card.Visible=inView and (cfg.names or cfg.distance or cfg.status or cfg.health)
            r.arrow.Visible=cfg.arrows and not inView
            if r.arrow.Visible then
                local localPoint=camera.CFrame:PointToObjectSpace(root.Position)
                local x,y,angle=edgePoint(localPoint.X,-localPoint.Y,size.X,size.Y)
                r.arrow.Position=UDim2.fromOffset(x,y);r.arrow.Rotation=angle;r.arrow.TextColor3=color;r.arrow.TextTransparency=1-alpha
            end
            if r.card.Visible then
                local top=camera:WorldToViewportPoint(root.CFrame:PointToWorldSpace(r.offset+Vector3.new(0,r.extent.Y+0.45,0)))
                local width=math.min(size.X,math.max(160,cfg.textSize*12))
                r.card.Size=UDim2.fromOffset(width,78)
                r.card.Position=UDim2.fromOffset(math.clamp(top.X,width/2,math.max(width/2,size.X-width/2)),math.clamp(top.Y,78,math.max(78,size.Y)))
                r.badge.Visible=cfg.status
                r.dot.BackgroundColor3=r.drone==true and red or r.drone==false and green or gray
                r.state.Text=r.drone==true and 'В РЕЖИМЕ ДРОНА' or r.drone==false and 'НЕ В РЕЖИМЕ ДРОНА' or 'НЕТ ДАННЫХ'
                r.state.TextColor3=r.dot.BackgroundColor3
                local lines={};if cfg.names then lines[#lines+1]=r.player.Name end
                if cfg.distance then lines[#lines+1]=string.format('%.0f м',r.distance) end
                r.label.Text=table.concat(lines,'\n');r.label.TextColor3=color;r.label.TextTransparency=1-alpha;r.label.TextSize=cfg.textSize;r.label.Font=fonts[cfg.font]
                r.healthBack.Visible=cfg.health
                local hp=math.clamp(r.humanoid.Health/math.max(1,r.humanoid.MaxHealth),0,1)
                r.health.Size=UDim2.fromScale(hp,1);r.health.BackgroundColor3=red:Lerp(green,hp)
            end
            r.tracer.Visible=false
            if cfg.tracers and inView then
                local y=cfg.origin==1 and size.Y-8 or cfg.origin==2 and size.Y/2 or 8
                drawLine(r.tracer,Vector2.new(size.X/2,y),Vector2.new(point.X,point.Y),color,alpha*0.65,size)
            end
            for _,edge in ipairs(r.edges) do edge.Visible=false end
            if cfg.boxes then
                local pts={}
                for i,sign in ipairs(corners) do pts[i]=camera.CFrame:PointToObjectSpace(root.CFrame:PointToWorldSpace(r.offset+sign*r.extent)) end
                for i,pair in ipairs(edges) do
                    local a,b=nearClip(pts[pair[1]],pts[pair[2]])
                    if a then
                        local pa=camera:WorldToViewportPoint(camera.CFrame:PointToWorldSpace(a))
                        local pb=camera:WorldToViewportPoint(camera.CFrame:PointToWorldSpace(b))
                        drawLine(r.edges[i],pa,pb,color,alpha,size)
                    end
                end
            end
        end
    end
end
local lastRefresh,lastDraw,lastSaveAttempt,lastError=-math.huge,0,0,0
connect(RunService.RenderStepped,function()
    if not alive then return end
    local now=os.clock()
    if dirtyAt and now-dirtyAt>1 and now-lastSaveAttempt>5 then
        lastSaveAttempt=now;if save() then dirtyAt=nil end
    end
    if now-lastDraw<1/cfg.fps then return end;lastDraw=now
    if not cfg.enabled then for _,r in pairs(records) do r.root.Visible=false end;return end
    local camera=Workspace.CurrentCamera
    if not camera then for _,r in pairs(records) do r.root.Visible=false end;return end
    local ok,err=pcall(function()
        if now-lastRefresh>0.2 then refresh(camera);lastRefresh=now end
        render(camera)
    end)
    if not ok then
        for _,r in pairs(records) do r.root.Visible=false end
        summary.Text='Ошибка ESP: '..string.sub(tostring(err),1,110)
        if now-lastError>10 then lastError=now;warn('[Codex second ESP] '..tostring(err)) end
    end
end)

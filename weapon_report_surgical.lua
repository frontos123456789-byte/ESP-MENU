-- Targeted read-only weapon report; optional decompilation of one script per explicit tap.
local player=game:GetService('Players').LocalPlayer
local parent=player:WaitForChild('PlayerGui')
for _,name in ipairs({'WeaponReportUI','WeaponReportV2UI','WeaponReportLiteUI','WeaponReportSurgicalUI'}) do
 local old=parent:FindFirstChild(name)
 if old then old:Destroy() end
end
local gui=Instance.new('ScreenGui')
gui.Name='WeaponReportSurgicalUI';gui.ResetOnSpawn=false
gui.ScreenInsets=Enum.ScreenInsets.DeviceSafeInsets;gui.DisplayOrder=210;gui.Parent=parent
local alive=true
gui.Destroying:Connect(function()alive=false end)
local panel=Instance.new('Frame')
panel.Position=UDim2.fromOffset(8,8);panel.Size=UDim2.new(1,-16,1,-16)
panel.BackgroundColor3=Color3.fromRGB(24,28,38);panel.Parent=gui
local title=Instance.new('TextLabel')
title.Position=UDim2.fromOffset(8,4);title.Size=UDim2.new(1,-64,0,44)
title.BackgroundTransparency=1;title.TextColor3=Color3.new(1,1,1)
title.TextWrapped=true;title.TextSize=15;title.Text='Короткий отчёт • сбор…';title.Parent=panel
local function button(text,pos,size)
 local b=Instance.new('TextButton');b.Text=text;b.Position=pos;b.Size=size
 b.TextColor3=Color3.new(1,1,1);b.TextSize=14;b.TextWrapped=true
 b.BackgroundColor3=Color3.fromRGB(45,52,70);b.Parent=panel
 return b
end
button('×',UDim2.new(1,-48,0,4),UDim2.fromOffset(40,40)).Activated:Connect(function()gui:Destroy()end)
local scroll=Instance.new('ScrollingFrame')
scroll.Position=UDim2.fromOffset(8,52);scroll.Size=UDim2.new(1,-16,1,-162)
scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y;scroll.CanvasSize=UDim2.new()
scroll.ScrollBarThickness=3;scroll.BackgroundColor3=Color3.fromRGB(16,19,27);scroll.Parent=panel
local text=Instance.new('TextLabel')
text.Size=UDim2.new(1,-10,0,0);text.AutomaticSize=Enum.AutomaticSize.Y
text.BackgroundTransparency=1;text.TextColor3=Color3.fromRGB(230,233,240)
text.TextSize=15;text.TextWrapped=true;text.Font=Enum.Font.Code
text.TextXAlignment=Enum.TextXAlignment.Left;text.TextYAlignment=Enum.TextYAlignment.Top
text.Text='Подожди…';text.Parent=scroll
local prev=button('←',UDim2.new(0,8,1,-52),UDim2.new(0.2,-6,0,44))
local nextButton=button('→',UDim2.new(0.2,6,1,-52),UDim2.new(0.2,-6,0,44))
local copy=button('Копировать страницу',UDim2.new(0.4,4,1,-52),UDim2.new(0.6,-12,0,44))
local pages,page={},1
local function show()
 title.Text='Отчёт • страница '..page..' / '..#pages
 text.Text=pages[page] or 'Сбор…';scroll.CanvasPosition=Vector2.new()
end
prev.Activated:Connect(function()if #pages>0 then page=math.max(1,page-1);show()end end)
nextButton.Activated:Connect(function()if #pages>0 then page=math.min(#pages,page+1);show()end end)
copy.Activated:Connect(function()
 if not pages[page] then return end
 local copier=type(setclipboard)=='function' and setclipboard or (type(toclipboard)=='function' and toclipboard)
 local chunk='WEAPON SURGICAL '..page..'/'..#pages..'\n'..pages[page]
 if copier and pcall(copier,chunk) then title.Text='Скопирована только страница '..page..' / '..#pages
 else title.Text='Буфер недоступен — сделай скриншот этой страницы' end
end)
local terms={'bullet','speed','gravity','velocity','drop','drag','ballistic','firerate','fire rate','range','spread','recoil','projectile','acceleration','hitscan'}
local function relevant(name)
 name=name:lower()
 for _,word in ipairs(terms) do if name:find(word,1,true) then return true end end
 return false
end
local function clip(value,limit)
 local s=tostring(value)
 local ok,pos=pcall(utf8.offset,s,limit+1)
 if not ok then return '[non-text]' end
 return pos and s:sub(1,pos-1)..'…' or s
end
local function pack(lines,maxChars)
 local result,current={},''
 for _,line in ipairs(lines) do
  local candidate=current=='' and line or current..'\n'..line
  if utf8.len(candidate)>maxChars and current~='' then table.insert(result,current);current=line
  else current=candidate end
 end
 if current~='' then table.insert(result,current) end
 return result
end

local codeButton=button('Прочитать 1 скрипт',UDim2.new(0,8,1,-102),UDim2.new(0.62,-8,0,44))
local retryButton=button('Повторить',UDim2.new(0.62,4,1,-102),UDim2.new(0.38,-12,0,44))
-- Targeted snapshot. No remote invocation, require(), shots or movement.
local lines,jobs,jobIndex={}, {},1
local busy=false
local run=0
local truncated=false
local function add(line)
 if #lines>=130 then truncated=true;return end
 table.insert(lines,clip(line,220))
end
local function refresh()
 local output={}
 for _,line in ipairs(lines) do table.insert(output,line) end
 if truncated then table.insert(output,'Достигнут предел отчёта; часть данных пропущена.') end
 pages=pack(output,800);page=math.min(page,math.max(1,#pages));show()
end
local function fullpath(node)
 local path=node:GetFullName()
 return path:gsub('Players%.[^.]+%.','LocalPlayer.')
end
local function describe(node,label,allValues)
 for key,value in pairs(node:GetAttributes()) do
  if allValues or relevant(key) then add(label..' @'..clip(key,45)..' = '..clip(value,80)) end
 end
 if node:IsA('ValueBase') and (allValues or relevant(node.Name)) then
  local ok,value=pcall(function()return node.Value end)
  if ok then
   add(label..' = '..clip(typeof(value)=='Instance' and fullpath(value) or value,100))
  end
 end
end
local function codeEvidence(source,label,method)
 add('КОД '..label..' ['..method..']')
 if #source>160000 then add('Исходник слишком велик для телефона; не обработан.');return end
 local rows={}
 for line in (source..'\n'):gmatch('(.-)\n') do table.insert(rows,line) end
 local selected={}
 local hits=0
 for i,line in ipairs(rows) do
  local lower=line:lower()
  if relevant(line) or lower:find('mouse',1,true) or lower:find('lookvector',1,true)
   or lower:find('currentcamera',1,true) or lower:find('screenpointtoray',1,true)
   or lower:find('fireserver',1,true) or lower:find('require',1,true) then
   hits=hits+1
   for j=math.max(1,i-1),math.min(#rows,i+1) do selected[j]=true end
  end
 end
 local emitted=0
 for i,line in ipairs(rows) do
  if selected[i] then
   if emitted>=22 then add('Другие совпадения опущены; всего '..hits);break end
   add(tostring(i)..': '..line);emitted=emitted+1
  end
 end
 if hits==0 then add('Совпадений по баллистике/направлению выстрела нет.') end
end
local function walk(root,budget,callback,prune)
 if not root then return end
 local queue={root};local index=1
 while index<=#queue and alive do
  local node=queue[index];queue[index]=false;index=index+1
  if not prune or not prune(node) then
   callback(node)
   for _,child in ipairs(node:GetChildren()) do
    if #queue>=budget then truncated=true;break end
    table.insert(queue,child)
   end
  end
  if index%60==0 then task.wait() end
 end
end
local function isScript(node)
 return node:IsA('LocalScript') or node:IsA('ModuleScript')
end
local function scan()
 if busy then return end
 busy=true;run=run+1;lines={};jobs={};jobIndex=1;page=1;pages={};truncated=false
 text.Text='Точечный сбор…';title.Text='Возьми нужный автомат в руки'
 task.spawn(function()
  local ok,err=pcall(function()
   local character=player.Character
   local backpack=player:FindFirstChildOfClass('Backpack')
   local weapon=character and character:FindFirstChildOfClass('Tool')
   if not weapon and backpack then weapon=backpack:FindFirstChild('AV-47') end
   add('Запуск '..run..' • Place '..game.PlaceId)
   add('Единицы значений не подтверждены. Чтение, без запуска кода.')
   if not weapon or not weapon:IsA('Tool') then
    add('Автомат не найден. Возьми его в руки и нажми «Повторить».')
    return
   end
   add('ОРУЖИЕ '..weapon.Name..' • '..fullpath(weapon))
   add('World.Gravity='..workspace.Gravity..' — НЕ подтверждённая гравитация пули.')
   add('Камера: '..player.CameraMode.Name..'; тип '..(workspace.CurrentCamera and workspace.CurrentCamera.CameraType.Name or 'нет'))
   local seenJobs={};local relatedObjects={};local seenObjects={}
   local function addJob(node,priority)
    if seenJobs[node] or #jobs>=16 then return end
    seenJobs[node]=true;table.insert(jobs,{node=node,priority=priority,path=fullpath(node)})
   end
   walk(weapon,1200,function(node)
    local relative=node==weapon and weapon.Name or fullpath(node):sub(#fullpath(weapon)+2)
    describe(node,relative,true)
    if isScript(node) then addJob(node,1) end
    if #relatedObjects<8 and node:IsA('ObjectValue') and node.Value and node.Value:IsDescendantOf(game:GetService('ReplicatedStorage')) then
     table.insert(relatedObjects,node.Value)
    end
    local name=node.Name:lower()
    if (node:IsA('Attachment') or node:IsA('BasePart')) and
     (name=='from' or name=='handle' or name:find('muzzle',1,true) or name:find('shoot',1,true) or name:find('bullet',1,true)) then
     add('ТОЧКА '..relative..' ['..node.ClassName..'] Position='..tostring(node.Position))
    end
    if node:IsA('RemoteEvent') or node:IsA('RemoteFunction') then add('СОБЫТИЕ '..relative..' ['..node.ClassName..']') end
   end)
   for _,object in ipairs(relatedObjects) do
    if not seenObjects[object] then
     seenObjects[object]=true
     add('ССЫЛКА '..fullpath(object))
     walk(object,200,function(node)
      describe(node,fullpath(node),true)
      if isScript(node) then addJob(node,2) end
     end)
    end
   end
   local storage=game:GetService('ReplicatedStorage')
   local function excluded(node)
    local n=node.Name:lower()
    return n=='fly' or n=='drones' or n=='drone' or n=='rockets' or n=='maps' or n=='map' or n=='vehicles'
   end
   local function weaponRelated(path)
    local lower=path:lower()
    return lower:find(weapon.Name:lower(),1,true) or lower:find('bullet',1,true)
      or lower:find('ballistic',1,true) or lower:find('gun',1,true)
      or lower:find('weapon',1,true) or lower:find('fastcast',1,true)
   end
   local sharedSettings=0
   walk(storage,4000,function(node)
    local path=fullpath(node)
    if weaponRelated(path) then
     if isScript(node) then addJob(node,2) end
     if sharedSettings<12 and (node:IsA('ValueBase') or next(node:GetAttributes())~=nil) then
      describe(node,path,false);sharedSettings=sharedSettings+1
     end
    end
   end,excluded)
   walk(player:FindFirstChild('PlayerScripts'),1200,function(node)
    if isScript(node) then addJob(node,weaponRelated(fullpath(node)) and 2 or 3) end
   end,excluded)
   table.sort(jobs,function(a,b) if a.priority~=b.priority then return a.priority<b.priority end;return a.path<b.path end)
   add('КАНДИДАТЫ КОДА: '..#jobs..'; decompile: '..(type(decompile)=='function' and 'доступен' or 'недоступен'))
   for i,job in ipairs(jobs) do add(i..'. '..job.path) end
   add('Кнопка «Прочитать 1 скрипт» добавляет выдержки по очереди.')
  end)
  if not alive then return end
  if not ok then add('Ошибка: '..clip(err,160)) end
  busy=false;refresh()
 end)
end
retryButton.Activated:Connect(scan)
codeButton.Activated:Connect(function()
 if busy then return end
 if #lines>=105 then title.Text='Отчёт заполнен. Скопируй страницы; новый запуск — «Повторить».';return end
 local job=jobs[jobIndex]
 if not job then title.Text='Больше доступных кандидатов нет';return end
 busy=true;jobIndex=jobIndex+1
 title.Text='Чтение одного скрипта…'
 task.spawn(function()
  local ok,err=pcall(function()
   local method='Source'
   local valid,source=pcall(function()return job.node.Source end)
   if not valid or type(source)~='string' or #source==0 then
    source=nil
    if type(decompile)=='function' then
     method='декомпиляция; результат может быть неточным'
     local done=false
     local worker=task.spawn(function()
      local success,result=pcall(decompile,job.node)
      if success and type(result)=='string' and #result>0 then source=result end
      done=true
     end)
     local deadline=os.clock()+2
     while alive and not done and os.clock()<deadline do task.wait() end
     if not done then pcall(task.cancel,worker);source=nil end
    end
   end
   if not alive then return end
   if source then codeEvidence(source,job.path,method)
   else add('КОД НЕДОСТУПЕН: '..job.path) end
  end)
  if not alive then return end
  if not ok then add('Ошибка чтения: '..clip(err,160)) end
  busy=false;page=1;refresh()
 end)
end)
scan()

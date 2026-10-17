-- Read-only inventory of client-visible weapon objects. No require(), firing or remote calls.
local Players=game:GetService('Players')
local HttpService=game:GetService('HttpService')
local player=Players.LocalPlayer
local playerGui=player:WaitForChild('PlayerGui')
local old=playerGui:FindFirstChild('WeaponReportV2UI')
if old then old:Destroy() end
local gui=Instance.new('ScreenGui')
gui.Name='WeaponReportV2UI'
gui.ResetOnSpawn=false
gui.ScreenInsets=Enum.ScreenInsets.DeviceSafeInsets
gui.DisplayOrder=200
gui.Parent=playerGui
local alive=true
gui.Destroying:Connect(function() alive=false end)
local panel=Instance.new('Frame')
panel.AnchorPoint=Vector2.new(0.5,0.5)
panel.Position=UDim2.fromScale(0.5,0.5)
panel.Size=UDim2.new(1,-20,1,-20)
panel.BackgroundColor3=Color3.fromRGB(24,28,38)
panel.Parent=gui
local maxSize=Instance.new('UISizeConstraint',panel)
maxSize.MaxSize=Vector2.new(760,700)
local function button(text,x,y,w,parent)
 local b=Instance.new('TextButton')
 b.Text=text; b.TextSize=14; b.TextWrapped=true
 b.TextColor3=Color3.new(1,1,1); b.BackgroundColor3=Color3.fromRGB(45,52,70)
 b.Position=x; b.Size=UDim2.new(w,-6,0,40); b.Parent=parent or panel
 return b
end
local status=Instance.new('TextLabel')
status.Size=UDim2.new(1,-64,0,48)
status.Position=UDim2.fromOffset(8,0)
status.BackgroundTransparency=1;status.TextColor3=Color3.new(1,1,1)
status.TextSize=14;status.TextWrapped=true;status.Text='Сбор сведений об оружии…';status.Parent=panel
local close=button('×',UDim2.new(1,-48,0,4),0,0,panel)
close.Size=UDim2.fromOffset(40,40)
close.Activated:Connect(function()gui:Destroy()end)
local scroll=Instance.new('ScrollingFrame')
scroll.Position=UDim2.fromOffset(8,52)
scroll.Size=UDim2.new(1,-16,1,-154)
scroll.BackgroundColor3=Color3.fromRGB(16,19,27)
scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y
scroll.CanvasSize=UDim2.new();scroll.ScrollBarThickness=4;scroll.Parent=panel
local box=Instance.new('TextBox')
box.Size=UDim2.new(1,-10,0,20);box.AutomaticSize=Enum.AutomaticSize.Y
box.MultiLine=true;box.ClearTextOnFocus=false;box.TextEditable=false
box.TextWrapped=true;box.TextXAlignment=Enum.TextXAlignment.Left;box.TextYAlignment=Enum.TextYAlignment.Top
box.TextSize=12;box.Font=Enum.Font.Code;box.BackgroundTransparency=1
box.TextColor3=Color3.fromRGB(225,230,240);box.Text='Подожди…';box.Parent=scroll
local prev=button('←',UDim2.new(0,8,1,-96),0,0.25)
local nextPage=button('→',UDim2.new(0.25,6,1,-96),0,0.25)
local copy=button('Копировать всё',UDim2.new(0.5,4,1,-96),0,0.5)
local save=button('Сохранить файл',UDim2.new(0,8,1,-48),0,0.5)
local rescan=button('Повторить сбор',UDim2.new(0.5,4,1,-48),0,0.5)
local reportText,pages,page,busy=nil,{},1,false
local function showPage()
 box.Text=pages[page] or 'Отчёт ещё не готов'
 scroll.CanvasPosition=Vector2.new(0,0)
end
prev.Activated:Connect(function()page=math.max(1,page-1);showPage()end)
nextPage.Activated:Connect(function()page=math.min(math.max(1,#pages),page+1);showPage()end)
copy.Activated:Connect(function()
 if not reportText then return end
 local copier=type(setclipboard)=='function' and setclipboard or (type(toclipboard)=='function' and toclipboard)
 if copier and pcall(copier,reportText) then status.Text='Полный JSON-отчёт скопирован'
 else box.TextEditable=true;status.Text='Буфер недоступен. Выдели текст страницы или сохрани файл.' end
end)
save.Activated:Connect(function()
 if not reportText then return end
 local filename='weapon_report_v2_'..tostring(game.PlaceId)..'.json'
 if type(writefile)=='function' and pcall(writefile,filename,reportText) then status.Text='Сохранён файл: '..filename
 else status.Text='Инжектор не предоставляет запись файлов. Нажми «Копировать всё».' end
end)
local terms={'weapon','gun','rifle','bullet','projectile','ballistic','gravity','velocity','speed','shoot','fire','raycast','fastcast','trajectory','spread','recoil','muzzle','ammo','settings','config','av-47','pp-91','stinger','оруж','Оруж','пул','Пул'}
local function relevant(text)
 text=string.lower(text)
 for _,word in ipairs(terms) do if text:find(word,1,true) then return true end end
 return false
end
local function clip(text,limit)
 text=tostring(text)
 local ok,pos=pcall(utf8.offset,text,limit+1)
 if not ok then return '[invalid UTF-8]' end
 if pos then return text:sub(1,pos-1)..' [truncated]' end
 return text
end
local function valueOf(value)
 local kind=typeof(value)
 if kind=='number' then return value==value and math.abs(value)<math.huge and value or tostring(value) end
 if kind=='boolean' then return value end
 if kind=='Instance' then return value:GetFullName() end
 return clip(value,1000)
end
local function attributes(node)
 local out={}
 for key,value in pairs(node:GetAttributes()) do out[key]=valueOf(value) end
 return out
end
local function sourceEvidence(source)
 local lines={}
 for line in (source..'\n'):gmatch('(.-)\n') do table.insert(lines,line) end
 local chosen={}
 for i,line in ipairs(lines) do
  if relevant(line) then for j=math.max(1,i-2),math.min(#lines,i+2) do chosen[j]=true end end
 end
 local out={};local total=0
 for i,line in ipairs(lines) do
  if chosen[i] then
   total=total+1
   if #out<100 then table.insert(out,{line=i,text=clip(line,400)}) end
  end
 end
 return out,total>100,#lines
end
local function readSource(node,allowDecompile)
 local ok,source=pcall(function()return node.Source end)
 if ok and type(source)=='string' and #source>0 then return source,'Source property',false end
 if not allowDecompile then return nil,'Source unavailable; decompile not attempted',false end
 local done,result=false,nil
 local worker=task.spawn(function()
  local success,output=pcall(decompile,node)
  if success and type(output)=='string' and #output>0 then result=output end
  done=true
 end)
 local deadline=os.clock()+2
 while alive and not done and os.clock()<deadline do task.wait() end
 if not done then pcall(task.cancel,worker);return nil,'Decompiler timed out',true end
 return result,result and 'Decompiler output (approximate; not executed)' or 'Decompiler returned no readable source',true
end
local function scan()
 if busy then return end
 busy=true;reportText=nil;pages={};page=1;box.Text='Сначала оружие и хранилища; карта исключена…'
 task.spawn(function()
  local success,err=pcall(function()
   local report={schema=2,placeId=game.PlaceId,universeId=game.GameId,generatedAt=os.date('!%Y-%m-%dT%H:%M:%SZ'),
    scope='Client snapshot. Map excluded. Each root has its own budget. No require, remotes or weapon activation.',
    units='Stored values only; units and active runtime use require confirmation from code.',
    workspaceGravity=workspace.Gravity,gravityNote='World gravity is NOT proof of weapon projectile gravity.',
    capabilities={decompile=type(decompile)=='function',readfile=type(readfile)=='function',writefile=type(writefile)=='function'},
    roots={},weapons={},settings={},scripts={},remotes={},muzzles={},errors={},truncated=false,
    skipped={'ServerStorage and ServerScriptService are not available to a normal client','Full Workspace map is intentionally excluded'},
    limits={nodesPerRoot=40000,recordsPerRoot=1200,decompileAttempts=20,sourceCharsPerScript=16000}}
   local roots={}
   local function add(node,label)if node then table.insert(roots,{node=node,label=label})end end
   add(player:FindFirstChildOfClass('Backpack'),'Backpack')
   add(player.Character,'Local character')
   add(game:GetService('ReplicatedStorage'),'ReplicatedStorage')
   add(player:FindFirstChild('PlayerScripts'),'PlayerScripts')
   add(game:GetService('ReplicatedFirst'),'ReplicatedFirst')
   add(game:GetService('StarterPack'),'StarterPack')
   add(game:GetService('StarterPlayer'),'StarterPlayer')
   add(playerGui,'PlayerGui')
   local world=workspace:FindFirstChild('World')
   add(world and world:FindFirstChild('AirDefence'),'World.AirDefence')
   for _,child in ipairs(workspace:GetChildren()) do
    if child:IsA('Tool') then add(child,'Workspace tool') end
   end
   local seen={};local decompiled=0;local scriptJobs={}
   -- Sequential roots prevent large maps or template folders from starving other roots.
   for _,root in ipairs(roots) do
    if not alive then return end
    local stats={name=root.label,path=root.node:GetFullName(),visited=0,records=0,truncated=false}
    table.insert(report.roots,stats)
    local queue={{node=root.node,weapon=nil}};local head=1
    while head<=#queue and alive do
     if stats.visited>=40000 or stats.records>=1200 then stats.truncated=true;report.truncated=true;break end
     local item=queue[head];queue[head]=false;head=head+1
     local node=item.node
     if not seen[node] and node~=gui and node.Name~='UAV_ESP_Menu' and node.Name~='WeaponReportUI' then
      seen[node]=true;stats.visited=stats.visited+1
      local ok,message=pcall(function()
       local path=node:GetFullName()
       local weapon=item.weapon
       local attrs=attributes(node)
       local entry={path=path,class=node.ClassName,name=node.Name,attributes=attrs,weapon=weapon}
       local emitted=false
       if node:IsA('Tool') then
        weapon=path;entry.weapon=path
        entry.enabled=node.Enabled;entry.requiresHandle=node.RequiresHandle
        table.insert(report.weapons,entry);emitted=true
       elseif node:IsA('ValueBase') then
        local valid,value=pcall(function()return node.Value end)
        if valid then entry.value=valueOf(value) end
        table.insert(report.settings,entry);emitted=true
       elseif node:IsA('ModuleScript') or node:IsA('LocalScript') or node:IsA('Script') then
        entry.sourceStatus='pending'
        local priority=weapon and 1 or (relevant(path) and 2 or (root.label=='PlayerScripts' and 3 or 4))
        table.insert(report.scripts,entry)
        table.insert(scriptJobs,{node=node,entry=entry,priority=priority})
        emitted=true
       elseif node:IsA('RemoteEvent') or node:IsA('RemoteFunction') or node:IsA('UnreliableRemoteEvent') then
        table.insert(report.remotes,entry);emitted=true
       elseif (node:IsA('Attachment') or node:IsA('BasePart')) and
        (node.Name:lower():find('muzzle',1,true) or node.Name:lower():find('shoot',1,true) or node.Name=='From') then
        entry.position=tostring(node.Position);table.insert(report.muzzles,entry);emitted=true
       elseif next(attrs)~=nil and (weapon or relevant(path)) then
        table.insert(report.settings,entry);emitted=true
       end
       if emitted then stats.records=stats.records+1 end
       for _,child in ipairs(node:GetChildren()) do table.insert(queue,{node=child,weapon=weapon}) end
      end)
      if not ok then table.insert(report.errors,{root=root.label,error=clip(message,300)}) end
      if stats.visited%150==0 then
       status.Text=root.label..': '..stats.visited..' объектов • оружий '..#report.weapons
       task.wait()
      end
     end
    end
    stats.remainingQueued=math.max(0,#queue-head+1)
   end
   table.sort(scriptJobs,function(a,b)
    if a.priority~=b.priority then return a.priority<b.priority end
    return a.entry.path<b.entry.path
   end)
   -- Decompile selected scripts only, without loading or running them.
   for i,job in ipairs(scriptJobs) do
    if not alive then return end
    status.Text='Чтение скриптов: '..i..'/'..#scriptJobs
    local allow=report.capabilities.decompile and decompiled<20 and job.priority<=3 and not job.node:IsA('Script')
    local source,method,used=readSource(job.node,allow)
    if used then decompiled=decompiled+1 end
    job.entry.sourceStatus=method
    if source then
     local evidence,limited,lineCount=sourceEvidence(source)
     job.entry.evidence=evidence;job.entry.evidenceTruncated=limited;job.entry.lineCount=lineCount
     if job.priority==1 or #evidence>0 then
      job.entry.source=clip(source,16000)
      job.entry.sourceTruncated=utf8.len(source)==nil or (utf8.len(source) or 0)>16000
     end
    end
    if i%5==0 then task.wait() end
   end
   report.decompileAttempts=decompiled
   report.unreadableScripts=0
   for _,entry in ipairs(report.scripts) do if not entry.evidence then report.unreadableScripts=report.unreadableScripts+1 end end
   if not alive then return end
   reportText=HttpService:JSONEncode(report)
   local start,count=1,0
   for offset in utf8.codes(reportText) do
    count=count+1
    if count>5000 then table.insert(pages,reportText:sub(start,offset-1));start=offset;count=1 end
   end
   table.insert(pages,reportText:sub(start));showPage()
   status.Text='Готово: оружий '..#report.weapons..' • скриптов '..#report.scripts..' • страниц '..#pages..(report.truncated and ' • есть ограничения' or '')
  end)
  busy=false
  if not success and alive then status.Text='Ошибка: '..clip(err,180) end
 end)
end
rescan.Activated:Connect(scan)
scan()

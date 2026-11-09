local root=debug.getinfo(1,'S').source:sub(2):gsub('\\','/'):match('^(.*)/Scripts/[^/]+$')
assert(root,'Install as Mods/BeyondPerformance/Scripts/main.lua')
local M={root=root,version='1.1.1',active=true,ready=false}
function M.valid(o)return o and o:IsValid()end
function M.log(s)print('[Beyond Performance] '..tostring(s)..'\n')end
local game=StaticFindObject('/Script/Engine.Default__GameplayStatics');local engine
function M.getPC()
 if not M.valid(engine)then engine=FindFirstOf('GameEngine')end
 local vp=M.valid(engine)and engine.GameViewport;if not M.valid(vp)then return end
 local world=vp:GetWorld();if not M.valid(world)then return end
 local pc=game:GetPlayerController(world,0);if M.valid(pc)and pc:IsLocalPlayerController()then return pc end
end
M.defaults={attachments=true,raw_mouse=true,low_latency=false,frame_smoothing=false,gpu_budget=false,shadows=false,clouds=false,frame_cap=false}
M.options={
 {key='attachments',label='Optimize vehicle attachments',description='Reduces repeated work for vehicle attachments. Unavailable on unsupported game versions.'},
 {key='raw_mouse',label='Disable mouse smoothing',description='Turns off mouse smoothing. Turn off this option to restore your previous setting.'},
 {key='low_latency',label='Reduce render-ahead (can lower FPS)',description='May reduce input delay, but can lower FPS or cause stutter. Leave off when troubleshooting low FPS.'},
 {key='frame_smoothing',label='Disable engine frame-rate smoothing',description='Removes automatic frame-rate smoothing. May increase power use or stutter. Your FPS cap and VSync still apply.'},
 {key='gpu_budget',label='Reduce rendered pixels',description='Lowers render resolution for a softer image and less GPU load. Unavailable while DLSS or dynamic resolution is active.'},
 {key='shadows',label='Disable dynamic shadows',description='Removes dynamic shadows. With Beyond Apocalypse installed, use its Extreme Performance Mode instead.'},
 {key='clouds',label='Disable volumetric cloud and fog rendering',description='Removes volumetric clouds and fog. With Beyond Apocalypse installed, use its Extreme Performance Mode instead.'},
 {key='frame_cap',label='Limit frame rate to 60 FPS',description='Caps FPS at 60, or keeps your lower cap. Does not raise FPS in slow scenes.'},
}
local storage=dofile(root..'/Scripts/settings.lua')
M.settings=storage.load(root..'/settings.ini',M.defaults)
M.render=dofile(root..'/Scripts/render.lua')(M)
local aok,attachments=pcall(function()return dofile(root..'/Scripts/attachments.lua')(M)end)
if aok then M.attachments=attachments else M.log('Attachment optimizer unavailable: '..tostring(attachments))end
M.benchmark=dofile(root..'/Scripts/benchmark.lua')(M)
function M.startBenchmark()return M.benchmark.start()end
function M.optionState(key)return M.render.optionState(key)end
function M.getStatus()
 local a=M.attachments and M.attachments.status()or'Attachment optimizer unavailable'
 local render=M.render.status()
 return a..(render~=''and' | '..render or'')..' | '..M.benchmark.status()
end
function M.setOption(key,value,persist)
 if M.defaults[key]==nil or type(value)~='boolean'then return false,'Unknown option or invalid value.'end
 local previous=M.settings[key]
 local function apply(v)
  if key=='attachments'then if not M.attachments then return false,'Attachment optimizer is unavailable on this build.'end;return M.attachments.apply(v)end
  return M.render.apply(key,v)
 end
 local called,ok,message=pcall(apply,value)
 if not called or not ok then
  pcall(apply,previous)
  return false,called and message or tostring(ok)
 end
 M.settings[key]=value
 if persist~=false then
  local wrote,saved,why=pcall(storage.save,root..'/settings.ini',M.settings,M.defaults)
  if not wrote or not saved then pcall(apply,previous);M.settings[key]=previous;return false,'Could not save preference: '..tostring(wrote and why or saved)end
 end
 return true,message or'Preference saved.'
end
function M.resetDefaults()
 local unavailable={}
 for _,option in ipairs(M.options)do
  local called,ok,why=pcall(M.setOption,option.key,M.defaults[option.key],false)
  if not called or not ok then unavailable[#unavailable+1]=option.label..': '..tostring(called and why or ok)end
 end
 -- Save the actual preferences for every successfully restored option, even
 -- when one feature is unavailable on this game build.
 local wrote,saved,why=pcall(storage.save,root..'/settings.ini',M.settings,M.defaults)
 if not wrote or not saved then return false,'Available defaults applied for this session; save failed: '..tostring(wrote and why or saved)end
 if #unavailable>0 then return false,'Available defaults saved. Unavailable: '..table.concat(unavailable,'; ')end
 return true,'Defaults restored and saved.'
end
M.ui=dofile(root..'/Scripts/ui.lua')(M)
local function reset(ownershipLost)
 M.ready=false
 local function attempt(label,fn)
  local ok,why=pcall(fn);if not ok then M.log(label..' cleanup failed: '..tostring(why))end
 end
 attempt('Benchmark',function()M.benchmark.stop('World changed; partial results retained.')end)
 attempt('Menu',function()M.ui.close(ownershipLost==true)end)
 attempt('Render',function()M.render.reset()end)
 if M.attachments then attempt('Attachments',M.attachments.shutdown)end
end
RegisterLoadMapPreHook(function()M.travelling=true;reset(true)end)
RegisterLoadMapPostHook(function()M.travelling=false;engine=nil end)
RegisterKeyBind(Key.F10,function()ExecuteInGameThread(function()if M.active then M.ui.toggle()end end)end)
local nextSlow=0;local errors={}
M.timer=LoopInGameThreadWithDelay(100,function()
 if not M.active or M.travelling then return end
 local ok,why=xpcall(function()
  M.ui.tick()
  local pc=M.getPC();local p=M.valid(pc)and pc.PlayerControlled
  if not M.valid(p)or not p.IsLoaded then return end
  if not M.ready then
   M.ready=true
   for _,o in ipairs(M.options)do if M.settings[o.key]then local applied,message=M.setOption(o.key,true,false);if not applied then M.log(o.label..': '..tostring(message))end end end
  end
  if os.clock()>=nextSlow then nextSlow=os.clock()+2;M.render.tick();if M.attachments then M.attachments.tick()end end
 end,debug.traceback)
 if not ok and not errors[tostring(why)]then errors[tostring(why)]=true;M.log(why)end
end)
function M.shutdown()
 M.active=false;reset(false);if M.timer then CancelDelayedAction(M.timer);M.timer=nil end
end
_G.BeyondPerformance=M
M.log(M.version..' loaded. F10 opens local controls. No other Beyond mod is required.')
return M

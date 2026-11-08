-- Client-local render budgets. Snapshot once; never fight another setting owner.
return function(M)
 local R={owned={},yielded={},deferred={},messages={}}
 local sys=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
 local definitions={
  low_latency={{'r.OneFrameThreadLag',function()return 0 end}},
  gpu_budget={{'r.ScreenPercentage',function(n)return math.max(25,n*.75)end}},
  shadows={{'r.ShadowQuality',function()return 0 end}},
  clouds={{'r.VolumetricCloud',function()return 0 end},{'r.VolumetricFog',function()return 0 end}},
  frame_cap={{'t.MaxFPS',function(n)return n>0 and math.min(n,60)or 60 end}},
 }
 local function get(name)return sys:GetConsoleVariableFloatValue(name)end
 local function equal(a,b)return type(a)=='number'and type(b)=='number'and math.abs(a-b)<.01 end
 local function set(name,value)local pc=M.getPC();assert(M.valid(pc),'No local controller');sys:ExecuteConsoleCommand(pc,name..' '..tostring(value),pc);assert(equal(get(name),value),'Game rejected '..name)end
 local function legacyExtreme()
  -- Defer overlapping controls for the entire combined installation, including
  -- mode transitions. This prevents two owners from absorbing each other's
  -- temporary values as the baseline. No sibling code is executed or modified.
  local f=io.open(M.root..'/../BeyondApocalypse/Scripts/performance.lua','r')
  if not f then return false end;f:close();return true
 end
 local function clearMouseHistory()
  local pc=M.getPC();if M.valid(pc)and M.valid(pc.PlayerInput)then pc.PlayerInput:ClearSmoothing()end
 end
 function R.restore(key)
  if key=='frame_smoothing'then
   local saved=R.engineSmoothing
   if saved and M.valid(saved.object)and saved.object.bSmoothFrameRate==false then saved.object.bSmoothFrameRate=saved.before end
   R.engineSmoothing=nil;return true
  end
  if key=='raw_mouse'then
   if R.mouse and M.valid(R.mouse.object)and R.mouse.object.bEnableMouseSmoothing==false then R.mouse.object.bEnableMouseSmoothing=R.mouse.before;clearMouseHistory()end
   R.mouse=nil;return true
  end
  local saved=R.owned[key];if not saved then return true end
  for _,r in ipairs(saved)do if equal(get(r.name),r.target)then set(r.name,r.before)end end
  R.owned[key]=nil;return true
 end
 function R.apply(key,on)
  if key=='frame_smoothing'then
   if not on then
    R.restore(key);R.yielded[key]=nil;R.messages[key]=nil
    return true,'Previous engine frame-rate smoothing restored where still owned.'
   end
   local saved=R.engineSmoothing
   if saved and M.valid(saved.object)and saved.object.bSmoothFrameRate==false then return true end
   R.engineSmoothing=nil
   local engine=FindFirstOf('GameEngine')
   if not M.valid(engine)or type(engine.bSmoothFrameRate)~='boolean'then return false,'Engine frame-rate smoothing is unavailable in this build.'end
   R.engineSmoothing={object=engine,before=engine.bSmoothFrameRate}
   engine.bSmoothFrameRate=false
   if engine.bSmoothFrameRate~=false then R.engineSmoothing=nil;return false,'The game rejected the frame-rate smoothing change.'end
   R.yielded[key]=nil;R.messages[key]=nil
   return true,'Engine frame-rate smoothing disabled; the explicit frame cap and VSync are unchanged.'
  end
  if key=='raw_mouse'then
   if not on then R.restore(key);R.messages[key]=nil;return true,'Previous mouse smoothing restored.'end
   if R.mouse then return true end
   local input=StaticFindObject('/Script/Engine.Default__InputSettings')
   if not M.valid(input)or type(input.bEnableMouseSmoothing)~='boolean'then return false,'Mouse smoothing setting is not available in this build.'end
   R.mouse={object=input,before=input.bEnableMouseSmoothing};input.bEnableMouseSmoothing=false;clearMouseHistory()
   return true,'Mouse smoothing disabled for this session; sensitivity is unchanged.'
  end
  if not definitions[key]then return false,'Unknown rendering option' end
  if not on then R.restore(key);R.yielded[key]=nil;R.deferred[key]=nil;R.messages[key]=nil;return true,'Previous values restored where still owned.' end
  if R.owned[key]then return true end
  if (key=='shadows'or key=='clouds')and legacyExtreme()then R.deferred[key]=true;R.messages[key]='Deferred: controlled through Apocalypse extreme mode';return true,R.messages[key]end
  if key=='gpu_budget'and get('r.NGX.DLSS.Enable')>0 then return false,'Use DLSS quality controls or disable DLSS before using pixel budget.'end
  if key=='gpu_budget'and get('r.DynamicRes.OperationMode')>0 then return false,'Disable dynamic resolution in the game before using the pixel budget.'end
  local saved={};R.owned[key]=saved;R.yielded[key]=nil
  local ok,err=pcall(function()
   for _,d in ipairs(definitions[key])do
    local before=get(d[1]);assert(type(before)=='number'and before==before and before>=0 and before<=1000,'Unsupported CVar '..d[1])
    if key=='gpu_budget'then assert(before>=25 and before<=200,'Unsupported screen-percentage mode')end
    local target=d[2](before)
    saved[#saved+1]={name=d[1],before=before,target=target}
    if not equal(before,target)then set(d[1],target)end
   end
  end)
  if not ok then pcall(R.restore,key);return false,tostring(err)end
  R.deferred[key]=nil;R.messages[key]=nil;return true,'Applied. Turn off to restore the previous value.'
 end
 function R.tick()
  if R.engineSmoothing and(not M.valid(R.engineSmoothing.object)or R.engineSmoothing.object.bSmoothFrameRate~=false)then
   R.engineSmoothing=nil;R.yielded.frame_smoothing=true
   R.messages.frame_smoothing='Engine changed or another setting took control; toggle off/on to reapply.'
  end
  if R.mouse and M.valid(R.mouse.object)and R.mouse.object.bEnableMouseSmoothing~=false then R.mouse=nil;R.messages.raw_mouse='Another setting took control; toggle off/on to reapply.'end
  for key,saved in pairs(R.owned)do
   local dlss=key=='gpu_budget'and get('r.NGX.DLSS.Enable')>0
   local dynamic=key=='gpu_budget'and get('r.DynamicRes.OperationMode')>0
   local changed=dlss or dynamic
   for _,r in ipairs(saved)do if not equal(get(r.name),r.target)then changed=true end end
   if changed then
    -- Restore only remaining fields we own, retain the external change, and
    -- require an explicit off/on to opt in again. No periodic CVar reassertion.
    R.restore(key);R.yielded[key]=true
    R.messages[key]=dlss and'DLSS now controls render scale; use its quality controls or disable DLSS before reapplying pixel budget.'or dynamic and'Dynamic resolution now controls render scale; disable it before reapplying pixel budget.'or'A game setting or another mod took control; toggle off/on to reapply.'
   end
  end
 end
 function R.reset()R.restore('raw_mouse');R.restore('frame_smoothing');for key in pairs(definitions)do R.restore(key)end;R.yielded={};R.deferred={};R.messages={}end
 function R.optionState(key)if R.deferred[key]then return 'DEFERRED'end end
 function R.status()
  local notes={};for key,message in pairs(R.messages)do notes[#notes+1]=key..': '..message end
  table.sort(notes);return table.concat(notes,' | ')
 end
 return R
end

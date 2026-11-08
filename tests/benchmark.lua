-- Verify recoverable data before finalization, including a long hitch.
local clock, callback, removed = 0, nil, 0
local human = {IsLoaded=true, IsValid=function()return true end, GetAddress=function()return 12 end}
local pc = {PlayerControlled=human, IsValid=function()return true end, GetAddress=function()return 11 end,
    IsLocalPlayerController=function()return true end}
local fn = {IsValid=function()return true end}
local env = setmetatable({
    os=setmetatable({clock=function()return clock end},{__index=os}),
    StaticFindObject=function(path)if path:find('ReceiveTick',1,true)then return fn end end,
    ExecuteAsync=function(f)f()end, ExecuteInGameThread=function(f)f()end,
    ExecuteInGameThreadWithDelay=function(_,f)f()end,
    RegisterHook=function(_,f)callback=f;return 1,2 end,
    UnregisterHook=function()removed=removed+1 end,
    LoopInGameThreadWithDelay=function()return 10 end, CancelDelayedAction=function()end,
},{__index=_G})
local M={root=testpath:match('^(.*)/'),version='test',settings={low_latency=true},
    valid=function(o)return o and o:IsValid()end,getPC=function()return pc end}
local B=assert(loadfile(scriptdir..'/benchmark.lua','t',env))()(M)
assert(B.start():find('Starting sample',1,true))
local base=B.current.base
local function read(ext)local f=assert(io.open(base..ext,'rb'));local s=f:read('*a');f:close();return s end
assert(read('.txt'):find('completed=false',1,true))
local function tick(t,dt)clock=t;callback({get=function()return human end},{get=function()return dt end})end
tick(.1,.1);tick(3.1,3);tick(3.2,.1);tick(5.3,2.1)
local recovered=read('.csv')
assert(recovered:find('2100.000000',1,true))
assert(read('.txt'):find('completed=false',1,true) and B.current)
M.settings.low_latency=false
assert(B.stop('World changed'))
assert(not B.current and removed==1 and B.latest.engine.over100ms==1)
assert(B.latest.engine.maxMs==2100 and B.latest.complete==false)
assert(read('.txt'):find('end.option.low_latency=false',1,true))
assert(read('.csv')==recovered)
os.remove(base..'.csv');os.remove(base..'.txt')
print('PASS recorder durability: partial CSV survives before finalization, long hitch retained, world-change cleanup, ending configuration recorded')

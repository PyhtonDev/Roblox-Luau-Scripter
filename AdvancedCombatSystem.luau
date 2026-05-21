-- Discord: zynix28 | Roblox: Zynix_OP

local Players=game:GetService("Players")
local RunService=game:GetService("RunService")

local Config={
DetectRange=80,
AttackRange=4,
Speed=5,
Damage=8,
Cooldown=1,
Knockback=22,
UpForce=6
}

local Targets={}

local function dist(a,b)
return (a-b).Magnitude
end

local function root(c)
return c and c:FindFirstChild("HumanoidRootPart")
end

local function hum(c)
return c and c:FindFirstChildOfClass("Humanoid")
end

local function add(p)
if Targets[p] then return end
Targets[p]={
last=0,
inRange=false
}
end

for _,v in ipairs(workspace:GetChildren()) do
if v:IsA("BasePart") and v.Name=="Target" then
add(v)
end
end

workspace.ChildAdded:Connect(function(v)
if v:IsA("BasePart") and v.Name=="Target" then
add(v)
end
end)

local function nearest(pos)
local best=nil
local bestd=Config.DetectRange

for _,p in ipairs(Players:GetPlayers()) do
local c=p.Character
local r=root(c)
local h=hum(c)

if r and h and h.Health>0 then
local d=dist(r.Position,pos)
if d<bestd then
bestd=d
best=r
end
end
end

return best,bestd
end

local function damagePlayer(r,data)
local h=hum(r.Parent)
if not h then return end

if tick()-data.last<Config.Cooldown then return end
data.last=tick()

h:TakeDamage(Config.Damage)
end

local function move(part,target)
local dir=target.Position-part.Position
if dir.Magnitude>0 then dir=dir.Unit end
part.CFrame=part.CFrame+dir*Config.Speed*0.1
end

local function knock(part,root)
local dir=part.Position-root.Position
if dir.Magnitude==0 then return end
dir=dir.Unit

part.AssemblyLinearVelocity=
dir*Config.Knockback+Vector3.new(0,Config.UpForce,0)
end

local function toolHook(pl)
pl.CharacterAdded:Connect(function(c)
task.wait(1)

local t=pl.Backpack:FindFirstChild("Sword")
if not t then return end

t.Activated:Connect(function()
local r=root(c)
if not r then return end

for _,p in ipairs(workspace:GetChildren()) do
if p:IsA("BasePart") and p.Name=="Target" then
if dist(p.Position,r.Position)<8 then
knock(p,r)
end
end
end
end)
end)
end

Players.PlayerAdded:Connect(toolHook)

RunService.Heartbeat:Connect(function()
for part,data in pairs(Targets) do
if part and part.Parent then

local r,dd=nearest(part.Position)

if r and dd<=Config.DetectRange then

move(part,r)

if dd<=Config.AttackRange then
if not data.inRange then
data.inRange=true
damagePlayer(r,data)
end
else
data.inRange=false
end

else
data.inRange=false
end

end
end
end)

RunService.Heartbeat:Connect(function()
for p in pairs(Targets) do
if not p or not p.Parent then
Targets[p]=nil
end
end
end)

RunService.Heartbeat:Connect(function()
for _,d in pairs(Targets) do
if d.last<0 then d.last=0 end
end
end)

RunService.Heartbeat:Connect(function()
for _,d in pairs(Targets) do
if d.last>999999 then d.last=0 end
end
end)

RunService.Heartbeat:Connect(function()
for _,d in pairs(Targets) do
d.inRange=d.inRange or false
end
end)

print("SYSTEM READY")

-- Discord: zynix28 | Roblox: Zynix_OP

--[[
    Advanced Combat Framework
    Author Credit:
    Discord: zynix28
    Roblox: Zynix_OP

    Purpose:
    This script demonstrates intermediate Luau scripting knowledge
    using metatables, CFrame math, raycasting, physics interactions,
    cooldowns, server validation, optimization, and Roblox API usage.

    Demo Instructions:
    - Place this Script inside ServerScriptService
    - Create a RemoteEvent inside ReplicatedStorage called "CombatRemote"
    - Create a Tool named "CombatTool"
    - LocalScript should fire attack requests to CombatRemote

    Features:
    - Combo combat system
    - Dash mechanic
    - Raycast hit validation
    - Physics knockback
    - Metatable OOP structure
    - Cooldown management
    - Anti-spam validation
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local CombatRemote = ReplicatedStorage:WaitForChild("CombatRemote")

---------------------------------------------------------------------
-- CONFIGURATION
---------------------------------------------------------------------

local CONFIG = {
    ComboResetTime = 1.25,
    AttackCooldown = 0.4,
    DashCooldown = 2,
    DashDistance = 20,
    BaseDamage = 12,
    KnockbackForce = 65,
    MaxAttackDistance = 12,
    StunTime = 0.35,
    RaycastHeight = 4
}

---------------------------------------------------------------------
-- OPTIMIZATION TABLES
---------------------------------------------------------------------

local PlayerData = {}
local ActiveCooldowns = {}

---------------------------------------------------------------------
-- HELPER FUNCTIONS
---------------------------------------------------------------------

local function getCharacter(player)
    if not player then
        return nil
    end

    local character = player.Character

    if character and character.Parent then
        return character
    end

    return nil
end

local function getHumanoid(character)
    if not character then
        return nil
    end

    return character:FindFirstChildOfClass("Humanoid")
end

local function getRoot(character)
    if not character then
        return nil
    end

    return character:FindFirstChild("HumanoidRootPart")
end

local function isAlive(character)
    local humanoid = getHumanoid(character)

    if humanoid and humanoid.Health > 0 then
        return true
    end

    return false
end

---------------------------------------------------------------------
-- COMBAT CLASS USING METATABLES
---------------------------------------------------------------------

local CombatSystem = {}
CombatSystem.__index = CombatSystem

function CombatSystem.new(player)
    local self = setmetatable({}, CombatSystem)

    self.Player = player
    self.Combo = 1
    self.LastAttack = 0
    self.LastDash = 0
    self.IsAttacking = false
    self.IsStunned = false

    return self
end

---------------------------------------------------------------------
-- COOLDOWN CHECK
---------------------------------------------------------------------

function CombatSystem:CanAttack()
    local currentTime = tick()

    if self.IsStunned then
        return false
    end

    if currentTime - self.LastAttack < CONFIG.AttackCooldown then
        return false
    end

    return true
end

---------------------------------------------------------------------
-- DASH MECHANIC USING CFRAME
---------------------------------------------------------------------

function CombatSystem:Dash()
    local character = getCharacter(self.Player)

    if not character then
        return
    end

    local root = getRoot(character)

    if not root then
        return
    end

    local currentTime = tick()

    if currentTime - self.LastDash < CONFIG.DashCooldown then
        return
    end

    self.LastDash = currentTime

    -- CFrame math is used to move player forward
    -- relative to character orientation.
    local dashDirection = root.CFrame.LookVector
    local targetPosition =
        root.Position + (dashDirection * CONFIG.DashDistance)

    local dashTween = TweenService:Create(
        root,
        TweenInfo.new(0.2, Enum.EasingStyle.Linear),
        {
            CFrame = CFrame.new(
                targetPosition,
                targetPosition + dashDirection
            )
        }
    )

    dashTween:Play()
end

---------------------------------------------------------------------
-- HIT DETECTION USING RAYCASTING
---------------------------------------------------------------------

function CombatSystem:GetTargets()
    local character = getCharacter(self.Player)

    if not character then
        return {}
    end

    local root = getRoot(character)

    if not root then
        return {}
    end

    local origin =
        root.Position + Vector3.new(0, CONFIG.RaycastHeight, 0)

    local direction =
        root.CFrame.LookVector * CONFIG.MaxAttackDistance

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {character}

    local result =
        workspace:Raycast(origin, direction, params)

    if result then
        local hitModel =
            result.Instance:FindFirstAncestorOfClass("Model")

        if hitModel and hitModel ~= character then
            return {hitModel}
        end
    end

    return {}
end

---------------------------------------------------------------------
-- DAMAGE + STUN SYSTEM
---------------------------------------------------------------------

function CombatSystem:ApplyStun(targetHumanoid)
    if not targetHumanoid then
        return
    end

    local oldWalkSpeed = targetHumanoid.WalkSpeed
    local oldJumpPower = targetHumanoid.JumpPower

    targetHumanoid.WalkSpeed = 0
    targetHumanoid.JumpPower = 0

    task.delay(CONFIG.StunTime, function()
        if targetHumanoid and targetHumanoid.Parent then
            targetHumanoid.WalkSpeed = oldWalkSpeed
            targetHumanoid.JumpPower = oldJumpPower
        end
    end)
end

---------------------------------------------------------------------
-- PHYSICS KNOCKBACK
---------------------------------------------------------------------

function CombatSystem:ApplyKnockback(targetCharacter)
    local attackerCharacter = getCharacter(self.Player)

    if not attackerCharacter then
        return
    end

    local attackerRoot = getRoot(attackerCharacter)
    local targetRoot = getRoot(targetCharacter)

    if not attackerRoot or not targetRoot then
        return
    end

    -- Direction calculated using vector math.
    -- This creates realistic push direction.
    local direction =
        (targetRoot.Position - attackerRoot.Position).Unit

    local velocity = Instance.new("BodyVelocity")
    velocity.MaxForce = Vector3.new(100000, 50000, 100000)

    velocity.Velocity =
        (direction * CONFIG.KnockbackForce)
        + Vector3.new(0, 15, 0)

    velocity.Parent = targetRoot

    Debris:AddItem(velocity, 0.18)
end

---------------------------------------------------------------------
-- DAMAGE PROCESSING
---------------------------------------------------------------------

function CombatSystem:DamageTarget(targetCharacter)
    local targetHumanoid = getHumanoid(targetCharacter)

    if not targetHumanoid then
        return
    end

    if targetHumanoid.Health <= 0 then
        return
    end

    local comboMultiplier = 1

    if self.Combo == 2 then
        comboMultiplier = 1.15
    elseif self.Combo == 3 then
        comboMultiplier = 1.3
    end

    local finalDamage =
        CONFIG.BaseDamage * comboMultiplier

    targetHumanoid:TakeDamage(finalDamage)

    self:ApplyKnockback(targetCharacter)
    self:ApplyStun(targetHumanoid)
end

---------------------------------------------------------------------
-- COMBO SYSTEM
---------------------------------------------------------------------

function CombatSystem:UpdateCombo()
    local currentTime = tick()

    if currentTime - self.LastAttack >
        CONFIG.ComboResetTime then

        self.Combo = 1
    else
        self.Combo += 1

        if self.Combo > 3 then
            self.Combo = 1
        end
    end
end

---------------------------------------------------------------------
-- MAIN ATTACK LOGIC
---------------------------------------------------------------------

function CombatSystem:Attack()
    if not self:CanAttack() then
        return
    end

    local character = getCharacter(self.Player)

    if not character then
        return
    end

    if not isAlive(character) then
        return
    end

    self.LastAttack = tick()
    self.IsAttacking = true

    self:UpdateCombo()

    local targets = self:GetTargets()

    for _, targetCharacter in ipairs(targets) do
        if targetCharacter then
            self:DamageTarget(targetCharacter)
        end
    end

    task.delay(0.15, function()
        self.IsAttacking = false
    end)
end

---------------------------------------------------------------------
-- PLAYER INITIALIZATION
---------------------------------------------------------------------

local function setupPlayer(player)
    PlayerData[player] =
        CombatSystem.new(player)

    ActiveCooldowns[player] = {
        AttackCount = 0,
        LastRequest = 0
    }
end

---------------------------------------------------------------------
-- PLAYER REMOVAL CLEANUP
---------------------------------------------------------------------

local function cleanupPlayer(player)
    PlayerData[player] = nil
    ActiveCooldowns[player] = nil
end

---------------------------------------------------------------------
-- ANTI-EXPLOIT VALIDATION
---------------------------------------------------------------------

local function validateRemote(player)
    local cooldown =
        ActiveCooldowns[player]

    if not cooldown then
        return false
    end

    local currentTime = tick()

    if currentTime -
        cooldown.LastRequest < 0.05 then

        cooldown.AttackCount += 1
    else
        cooldown.AttackCount = 0
    end

    cooldown.LastRequest = currentTime

    -- Prevent remote spam abuse.
    if cooldown.AttackCount > 10 then
        warn(player.Name ..
            " attempted remote spam.")

        return false
    end

    return true
end

---------------------------------------------------------------------
-- REMOTE EVENT HANDLER
---------------------------------------------------------------------

CombatRemote.OnServerEvent:Connect(function(
    player,
    action
)
    if not validateRemote(player) then
        return
    end

    local combat =
        PlayerData[player]

    if not combat then
        return
    end

    if action == "Attack" then
        combat:Attack()

    elseif action == "Dash" then
        combat:Dash()
    end
end)

---------------------------------------------------------------------
-- PLAYER CONNECTIONS
---------------------------------------------------------------------

Players.PlayerAdded:Connect(function(player)
    setupPlayer(player)

    player.CharacterAdded:Connect(function(character)
        local humanoid =
            character:WaitForChild("Humanoid")

        humanoid.Died:Connect(function()
            local combat =
                PlayerData[player]

            if combat then
                combat.Combo = 1
                combat.IsAttacking = false
            end
        end)
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    cleanupPlayer(player)
end)

---------------------------------------------------------------------
-- EXISTING PLAYERS
---------------------------------------------------------------------

for _, player in ipairs(
    Players:GetPlayers()
) do
    setupPlayer(player)
end

---------------------------------------------------------------------
-- DEBUG TAG SYSTEM
---------------------------------------------------------------------

-- CollectionService is used here to show
-- broader Roblox API understanding.

local function markCombatCharacter(character)
    if not character then
        return
    end

    if not CollectionService:HasTag(
        character,
        "CombatEnabled"
    ) then
        CollectionService:AddTag(
            character,
            "CombatEnabled"
        )
    end
end

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(character)
        markCombatCharacter(character)
    end)
end)

---------------------------------------------------------------------
-- PERFORMANCE MONITOR
---------------------------------------------------------------------

-- RunService heartbeat is intentionally
-- lightweight to avoid performance issues.

RunService.Heartbeat:Connect(function()
    for player, combat
        in pairs(PlayerData) do

        if combat.Combo > 3 then
            combat.Combo = 1
        end
    end
end)

---------------------------------------------------------------------
-- END OF SYSTEM
---------------------------------------------------------------------

print(
    "Advanced Combat Framework Loaded Successfully"
)

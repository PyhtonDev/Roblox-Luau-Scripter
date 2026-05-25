local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Constants = require(ReplicatedStorage.Constants.Constants_Placeholder)
local DebugPrints = require(ReplicatedStorage.Flags.DebugPrints)
local Janitor = require(ReplicatedStorage.Packages.Janitor)

warn(">>> Game_PairSystem MODULE LOADED <<<")

local PairSystem = {}
type Self = typeof(PairSystem)

local DOOR_OFFSET = 3.6
local INTERIOR_OFFSET = 6.0
local DOOR_SIZE = Vector3.new(6, 7.6, 0.5)
local ROOT_Y_OFFSET = 2.5

local GATE_ZONE = {
	minX = -62,
	maxX = -57,
	minZ = 206,
	maxZ = 216,
	minY = 24,
	maxY = 38,
}

type BoothState = {
	pad: BasePart,
	door: BasePart,
	interiorCFrame: CFrame,
	exitCFrame: CFrame,
	player: Player?,
	inside: boolean,
}

type MachineState = {
	machineId: string,
	bunny: BoothState,
	human: BoothState,
	awaitingVotes: boolean,
	countdownActive: boolean,
	paired: boolean,
}

type GatePartState = {
	part: BasePart,
	canCollide: boolean,
	transparency: number,
	hideOnOpen: boolean,
}

local machines: { [string]: MachineState } = {}
local playerMachine: { [Player]: string } = {}
local pairedPlayers: { bunny: Player?, human: Player? } = { bunny = nil, human = nil }
local passedGate: { [Player]: boolean } = {}
local gatePartStates: { GatePartState } = {}
local gateSignGuis: { SurfaceGui } = {}
local _gateTrigger: BasePart? = nil
local gateOpen = false
local _healthLinked = false
local janitor = Janitor.new()
local openGate: () -> ()
local resetButtonGates: () -> ()
local fullReset: () -> ()

local BUNNY_SCALE = 0.4
local CARRY_COOLDOWN = 3
local CARRY_OFFSET = CFrame.new(0, 0.2, -2.0)
local CARRY_RANGE = 15

local bunnyTemplate: Model? = nil

local carryState = {
	carrying = false,
	weld = nil :: WeldConstraint?,
	lastAction = 0,
}

local carryRemotes: Folder? = nil
local obstacleRemotes: Folder? = nil
local machineRemotes: Folder? = nil
local mapSelectionRemote: RemoteEvent? = nil
local machineMapVotes: { [string]: { bunny: string?, human: string? } } = {}
local buttonCooldowns: { [Player]: { [string]: number } } = {}
local boothLeaveCooldown: { [Player]: number } = {}

type ButtonGateSetup = {
	redButton: BasePart,
	blueButton: BasePart,
	bars: { { part: BasePart, canCollide: boolean, transparency: number } },
	redPressed: boolean,
	bluePressed: boolean,
	open: boolean,
	trigger: BasePart?,
	passedThrough: { [Player]: boolean },
}

local buttonGates: { ButtonGateSetup } = {}

local bridgePart: UnionOperation? = nil
local bridgeButtonPart: BasePart? = nil
local bunnyTeleporter3: BasePart? = nil
local bunnyTeleporter4: BasePart? = nil
local bridgeActivated = false

local seesawState = {
	plank = nil :: BasePart?,
	fulcrum = nil :: BasePart?,
	originalPlankCFrame = nil :: CFrame?,
	pivotWorld = nil :: Vector3?,
	currentAngle = 0,
	targetAngle = 0,
	tilted = false,
	locked = false,
	button1Pressed = false,
	button2Pressed = false,
}

local SEESAW_TILT_SPEED = 15 -- degrees per second
local SEESAW_TILT_MAX = 30 -- max tilt angle in degrees

local invisPlatformsState = {
	button1Pressed = false,
	button2Pressed = false,
	activated = false,
	parts = {} :: { BasePart },
}

local carrotState = {
	carrots = {} :: { { part: UnionOperation, collected: boolean } },
	totalCollected = 0,
	ladderRevealed = false,
	topLadder = nil :: UnionOperation?,
	ladder2Parts = {} :: { BasePart },
}

local elevatorState = {
	button = nil :: BasePart?,
	model = nil :: Model?,
	originalPivot = nil :: CFrame?,
	targetRise = 0,
	currentRise = 0,
	reached = false,
}

local ELEVATOR_SPEED = 5 -- studs per second

local elevator2State = {
	button = nil :: BasePart?,
	model = nil :: Model?,
	originalPivot = nil :: CFrame?,
	targetRise = 0,
	currentRise = 0,
	reached = false,
}

local ELEVATOR2_SPEED = 5 -- studs per second

local switchButtonsState = {
	button1Player = nil :: Player?,
	button2Player = nil :: Player?,
	swapped = false,
}

local conveyorState = {
	belt = nil :: BasePart?,
	button = nil :: BasePart?,
	jump = nil :: BasePart?,
	jumpRevealed = false,
	texture = nil :: Texture?,
}

local CONVEYOR_SPEED = 10 -- studs per second
local CONVEYOR_JUMP_AMPLITUDE = 8 -- studs of oscillation each direction
local CONVEYOR_JUMP_PERIOD = 2.5 -- seconds for one full back-and-forth cycle

-- Map visibility system: store original part properties so we can hide/show entire maps
type MapPartData = { part: BasePart, transparency: number, canCollide: boolean }
local mapOriginalData: { [string]: { MapPartData } } = {}
local activeMapName: string? = nil -- "Desert", "Snow", or nil (Grass/default)

local function storeMapData(mapName: string, mapFolder: Folder)
	local data: { MapPartData } = {}
	for _, desc in mapFolder:GetDescendants() do
		if desc:IsA("BasePart") then
			table.insert(data, {
				part = desc,
				transparency = desc.Transparency,
				canCollide = desc.CanCollide,
			})
		end
	end
	mapOriginalData[mapName] = data
end

local function hideMap(mapName: string)
	local data = mapOriginalData[mapName]
	if not data then return end
	for _, entry in data do
		if entry.part and entry.part.Parent then
			entry.part.Transparency = 1
			entry.part.CanCollide = false
		end
	end
end

local function showMap(mapName: string)
	local data = mapOriginalData[mapName]
	if not data then return end
	for _, entry in data do
		if entry.part and entry.part.Parent then
			entry.part.Transparency = entry.transparency
			entry.part.CanCollide = entry.canCollide
		end
	end
end

local function debugPrint(...)
	if DebugPrints.PairSystem then
		warn("[PairSystem]", ...)
	end
end

local function scaleCharacter(player: Player, scale: number)
	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local scaleNames = { "BodyHeightScale", "BodyWidthScale", "BodyDepthScale", "HeadScale" }
	for _, scaleName in scaleNames do
		local scaleValue = humanoid:FindFirstChild(scaleName) :: NumberValue?
		if scaleValue then
			scaleValue.Value = scale
		end
	end

	-- Compensate for mass loss on scale-down to prevent sliding/skidding
	-- Mass scales with volume (scale^3), so increase density inversely to preserve mass
	if scale < 1 then
		local densityCompensation = 1 / (scale * scale * scale) -- 0.4^3 = 0.064 → ~15.6x
		local defaultDensity = 0.7
		local compensatedDensity = defaultDensity * densityCompensation

		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") then
				part.CustomPhysicalProperties = PhysicalProperties.new(
					compensatedDensity, -- increased density to maintain original mass
					0.3, -- default friction
					0.5, -- default elasticity
					1, -- default friction weight
					1 -- default elasticity weight
				)
			end
		end
	else
		-- Restore default physical properties
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") then
				part.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.3, 0.5, 1, 1)
			end
		end
	end

	debugPrint(player.Name, "scaled to", scale)
end

local function assignBunnyCollisionGroup(player: Player)
	local character = player.Character
	if not character then return end
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = "BunnyBody"
		end
	end
	debugPrint(player.Name, "assigned to BunnyBody collision group")
end

local function clearBunnyCollisionGroup(player: Player)
	local character = player.Character
	if not character then return end
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Default"
		end
	end
	debugPrint(player.Name, "restored to Default collision group")
end

local function applyBunnyModel(player: Player)
	local character = player.Character
	if not character or not bunnyTemplate then return end
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end

	-- Remove existing bunny mesh if present
	local existing = character:FindFirstChild("BunnyMesh")
	if existing then existing:Destroy() end

	-- Hide all character body parts, accessories, and face
	for _, desc in character:GetDescendants() do
		if desc:IsA("BasePart") and desc.Name ~= "HumanoidRootPart" then
			desc.Transparency = 1
		elseif desc:IsA("Accessory") then
			local handle = desc:FindFirstChild("Handle") :: BasePart?
			if handle then handle.Transparency = 1 end
		elseif desc:IsA("Decal") or desc:IsA("Texture") then
			desc.Transparency = 1
		end
	end

	-- Clone bunny mesh and weld to HRP
	local primaryPart = bunnyTemplate.PrimaryPart
	if not primaryPart then return end
	local bunnyMesh = primaryPart:Clone()
	bunnyMesh.Name = "BunnyMesh"
	bunnyMesh.Anchored = false
	bunnyMesh.CanCollide = false

	local weld = Instance.new("Weld")
	weld.Part0 = hrp
	weld.Part1 = bunnyMesh
	-- Position mesh so bottom touches ground using deferred HipHeight read
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	weld.C0 = CFrame.new(0, 0, 0)
	weld.C1 = CFrame.new(0, 0, 0)
	weld.Parent = bunnyMesh

	bunnyMesh.Parent = character

	-- Defer offset computation until Roblox stabilizes HipHeight after body scaling
	if humanoid then
		task.spawn(function()
			-- Wait for body scale changes to propagate to HipHeight
			task.wait(0.2)
			if not humanoid or not humanoid.Parent then return end
			if not weld or not weld.Parent then return end
			if not hrp or not hrp.Parent then return end
			local hipHeight = humanoid.HipHeight
			local hrpHalfH = hrp.Size.Y / 2
			local meshHalfH = bunnyMesh.Size.Y / 2
			-- R15 formula: HRP center above ground = HipHeight + 0.5 * RootPart.Size.Y
			-- We want mesh bottom on ground, so mesh center = meshHalfH above ground
			-- C0.Y = meshHalfH - (HipHeight + HRP.Size.Y/2)
			weld.C0 = CFrame.new(0, meshHalfH - hipHeight - hrpHalfH, 0)
			debugPrint("Bunny weld offset set: HipHeight=", hipHeight, "hrpHalfH=", hrpHalfH, "meshHalfH=", meshHalfH, "C0.Y=", meshHalfH - hipHeight - hrpHalfH)
		end)
	end

	debugPrint(player.Name, "bunny model applied")
end

local function removeBunnyModel(player: Player)
	local character = player.Character
	if not character then return end

	-- Remove bunny mesh
	local bunnyMesh = character:FindFirstChild("BunnyMesh")
	if bunnyMesh then bunnyMesh:Destroy() end

	-- Restore character part visibility
	for _, desc in character:GetDescendants() do
		if desc:IsA("BasePart") and desc.Name ~= "HumanoidRootPart" then
			desc.Transparency = 0
		elseif desc:IsA("Accessory") then
			local handle = desc:FindFirstChild("Handle") :: BasePart?
			if handle then handle.Transparency = 0 end
		elseif desc:IsA("Decal") or desc:IsA("Texture") then
			desc.Transparency = 0
		end
	end
	debugPrint(player.Name, "bunny model removed")
end

local function getPlayerFromPart(part: BasePart): Player?
	local character = part.Parent
	if not character then return nil end
	return Players:GetPlayerFromCharacter(character)
end

local function getRootPart(player: Player): BasePart?
	local character = player.Character
	if not character then return nil end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function getGroundSnappedCFrame(targetPos: Vector3, lookDir: Vector3, excludeInstances: { Instance }?): CFrame
	local rayParams = RaycastParams.new()
	if excludeInstances and #excludeInstances > 0 then
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = excludeInstances
	end
	local rayStart = targetPos + Vector3.new(0, 10, 0)
	local result = workspace:Raycast(rayStart, Vector3.new(0, -60, 0), rayParams)
	if result then
		local groundPos = result.Position + Vector3.new(0, 3, 0)
		local flatLook = Vector3.new(lookDir.X, 0, lookDir.Z)
		if flatLook.Magnitude < 0.01 then flatLook = Vector3.new(0, 0, 1) end
		return CFrame.new(groundPos, groundPos + flatLook)
	end
	return CFrame.new(targetPos, targetPos + lookDir)
end

local function findBestTeleporterExit(toPart: BasePart): (Vector3, Vector3)
	local toLook = toPart.CFrame.LookVector
	local toRight = toPart.CFrame.RightVector
	local pos = toPart.Position

	-- Look for a nearby Arrow part to determine direction
	local nearestArrow: BasePart? = nil
	local nearestArrowDist = 30
	for _, desc in workspace:GetDescendants() do
		if desc:IsA("BasePart") and desc.Name == "Arrow" then
			local dist = (desc.Position - pos).Magnitude
			if dist < nearestArrowDist then
				nearestArrowDist = dist
				nearestArrow = desc
			end
		end
	end

	if nearestArrow then
		-- Use direction from teleporter toward arrow, face arrow's look direction
		local toArrow = (nearestArrow.Position - pos)
		local flatToArrow = Vector3.new(toArrow.X, 0, toArrow.Z)
		if flatToArrow.Magnitude > 0.1 then
			flatToArrow = flatToArrow.Unit
		else
			flatToArrow = Vector3.new(toLook.X, 0, toLook.Z).Unit
		end
		local spawnPos = pos + flatToArrow * 5
		local faceDir = nearestArrow.CFrame.LookVector
		return spawnPos, faceDir
	end

	-- Fallback: exclude teleporter model and raycast to find best direction
	local excludeModel = toPart.Parent
	local rayParams = RaycastParams.new()
	if excludeModel then
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = { excludeModel }
	end

	local bestPos = pos + toLook * 5
	local bestDir = toLook
	local bestScore = -1

	for _, dir in { toLook, -toLook, toRight, -toRight } do
		local score = 0
		for offset = 3, 7, 2 do
			local testPos = pos + dir * offset
			local ray = workspace:Raycast(testPos + Vector3.new(0, 10, 0), Vector3.new(0, -30, 0), rayParams)
			if ray then
				local gap = math.abs(ray.Position.Y - pos.Y)
				score += math.max(0, 15 - gap)
			end
		end
		if score > bestScore then
			bestScore = score
			bestPos = pos + dir * 5
			bestDir = dir
		end
	end

	return bestPos, bestDir
end

local function createDoor(doorCFrame: CFrame): BasePart
	local door = Instance.new("Part")
	door.Name = "BoothDoor"
	door.Size = DOOR_SIZE
	door.CFrame = doorCFrame
	door.Anchored = true
	door.CanCollide = false
	door.Transparency = 1
	door.BrickColor = BrickColor.new("Dark stone grey")
	door.Material = Enum.Material.Metal
	door.Parent = workspace
	return door
end

local function showDoor(door: BasePart)
	door.CanCollide = true
	TweenService:Create(door, TweenInfo.new(0.3), { Transparency = 0.2 }):Play()
end

local function hideDoor(door: BasePart)
	local tween = TweenService:Create(door, TweenInfo.new(0.3), { Transparency = 1 })
	tween:Play()
	tween.Completed:Once(function()
		door.CanCollide = false
	end)
end

local function updateButtonGate(setup: ButtonGateSetup)
	if setup.open then return end
	if not setup.redPressed or not setup.bluePressed then return end

	setup.open = true
	setup.passedThrough = {}
	for _, barState in setup.bars do
		barState.part.CanCollide = false
		barState.part.Transparency = 1
	end
	debugPrint("Button gate opened - waiting for both players to pass through")
end

local function closeButtonGate(setup: ButtonGateSetup)
	if not setup.open then return end
	setup.open = false
	setup.redPressed = false
	setup.bluePressed = false
	setup.passedThrough = {}
	for _, barState in setup.bars do
		barState.part.CanCollide = barState.canCollide
		barState.part.Transparency = barState.transparency
	end
	debugPrint("Button gate closed")
end

local function collectBarsFromGate(gateModel: Model): { { part: BasePart, canCollide: boolean, transparency: number } }
	local bars = {}
	for _, desc in gateModel:GetDescendants() do
		if desc:IsA("Part") and desc.Name == "Part" then
			table.insert(bars, {
				part = desc,
				canCollide = desc.CanCollide,
				transparency = desc.Transparency,
			})
		end
	end
	return bars
end

local function setupButtonGate(redButton: BasePart, blueButton: BasePart, gateModel: Model)
	local gatePivot = gateModel:GetPivot()
	local gateExtents = gateModel:GetExtentsSize()

	local setup: ButtonGateSetup = {
		redButton = redButton,
		blueButton = blueButton,
		bars = collectBarsFromGate(gateModel),
		redPressed = false,
		bluePressed = false,
		open = false,
		trigger = nil,
		passedThrough = {},
	}
	table.insert(buttonGates, setup)

	local trigger = Instance.new("Part")
	trigger.Name = "ButtonGateTrigger"
	trigger.Size = Vector3.new(gateExtents.X + 6, gateExtents.Y, gateExtents.Z)
	trigger.CFrame = gatePivot
	trigger.Anchored = true
	trigger.CanCollide = false
	trigger.Transparency = 1
	trigger.Parent = workspace
	setup.trigger = trigger

	trigger.Touched:Connect(function(hit: BasePart)
		if not setup.open then return end
		local player = getPlayerFromPart(hit)
		if not player then return end
		if not pairedPlayers.bunny or not pairedPlayers.human then return end
		if player ~= pairedPlayers.bunny and player ~= pairedPlayers.human then return end
		if setup.passedThrough[player] then return end

		setup.passedThrough[player] = true
		debugPrint(player.Name, "passed through button gate")

		if setup.passedThrough[pairedPlayers.bunny] and setup.passedThrough[pairedPlayers.human] then
			debugPrint("Both players through button gate, closing")
			task.defer(function()
				task.wait(1)
				closeButtonGate(setup)
			end)
		end
	end)

	-- Tag buttons for client-side detection
	CollectionService:AddTag(redButton, "ObstacleButton")
	CollectionService:AddTag(blueButton, "ObstacleButton")

	debugPrint("Button gate setup: red at", tostring(redButton.Position), "blue at", tostring(blueButton.Position), "bars:", #setup.bars)
end

resetButtonGates = function()
	for _, setup in buttonGates do
		closeButtonGate(setup)
	end
	debugPrint("All button gates reset")
end

local function initButtonGates()
	local redButton: BasePart? = nil
	local blueButton: BasePart? = nil

	for _, child in workspace:GetDescendants() do
		if child:IsA("Part") then
			if child.Name == "RedButton" then
				redButton = child
			elseif child.Name == "BlueButton" then
				blueButton = child
			end
		end
	end

	local gateModels: { Model } = {}
	for _, child in workspace:GetDescendants() do
		if child.Name == "Gate" and child:IsA("Model") then
			table.insert(gateModels, child)
		end
	end

	if redButton and blueButton and #gateModels > 0 then
		setupButtonGate(redButton, blueButton, gateModels[1])
		debugPrint("Button gates initialized:", #gateModels, "gates found")
	else
		warn("[PairSystem] Missing buttons or gates - Red:", tostring(redButton ~= nil), "Blue:", tostring(blueButton ~= nil), "Gates:", #gateModels)
	end
end

local function dropBunnyInternal()
	if not carryState.carrying then return end

	if carryState.weld then
		carryState.weld:Destroy()
		carryState.weld = nil
	end

	-- remove the hat
	if carryState.hat then
		carryState.hat:Destroy()
		carryState.hat = nil
	end

	local bunny = pairedPlayers.bunny
	if bunny then
		local bunnyChar = bunny.Character
		if bunnyChar then
			local bunnyHum = bunnyChar:FindFirstChildOfClass("Humanoid")
			if bunnyHum then
				bunnyHum.PlatformStand = false
				bunnyHum:ChangeState(Enum.HumanoidStateType.GettingUp)
			end

			for _, part in bunnyChar:GetDescendants() do
				if part:IsA("BasePart") then
					part.Massless = false
				end
			end

			local bunnyRoot = bunnyChar:FindFirstChild("HumanoidRootPart") :: BasePart?
			if bunnyRoot then
				pcall(function()
					bunnyRoot:SetNetworkOwner(bunny)
				end)
			end
		end
	end

	carryState.carrying = false
	carryState.lastAction = os.clock()
	debugPrint("Bunny dropped")

	if carryRemotes then
		local stateRemote = carryRemotes:FindFirstChild("CarryStateChanged") :: RemoteEvent?
		if stateRemote then
			stateRemote:FireAllClients("drop")
		end
	end
end

local function pickupBunny(humanPlayer: Player)
	if not pairedPlayers.bunny or not pairedPlayers.human then return end
	if humanPlayer ~= pairedPlayers.human then return end
	if carryState.carrying then return end
	if not humanPlayer:GetAttribute("CarryEnabled") then return end

	local now = os.clock()
	if now - carryState.lastAction < CARRY_COOLDOWN then return end

	local humanChar = humanPlayer.Character
	local bunnyChar = pairedPlayers.bunny.Character
	if not humanChar or not bunnyChar then return end

	local humanRoot = humanChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	local bunnyRoot = bunnyChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	local bunnyHum = bunnyChar:FindFirstChildOfClass("Humanoid")

	local rightArm = humanChar:FindFirstChild("RightHand") or humanChar:FindFirstChild("Right Arm")

	if not humanRoot or not bunnyRoot or not bunnyHum or not rightArm then return end

	local dist = (humanRoot.Position - bunnyRoot.Position).Magnitude
	if dist > CARRY_RANGE then return end

	local HatModel = ReplicatedStorage.TopHatModel
	local hatClone = HatModel:Clone()
	hatClone.Parent = workspace
	
	carryState.hat = hatClone

	-- position hat in the player's arms
	local armOffset = CFrame.new(-1, 0, 0)
	hatClone.CFrame = rightArm.CFrame * armOffset * CFrame.Angles(-30, 0, 0)

	-- place bunny inside the hat
	local bunnyOffset = CFrame.new(0, -0.5, 0)
	bunnyRoot.CFrame = hatClone.CFrame * bunnyOffset

	-- weld hat to arm
	local hatWeld = Instance.new("WeldConstraint")
	hatWeld.Part0 = rightArm
	hatWeld.Part1 = hatClone
	hatWeld.Parent = rightArm

	-- weld bunny to hat
	local bunnyWeld = Instance.new("WeldConstraint")
	bunnyWeld.Part0 = hatClone
	bunnyWeld.Part1 = bunnyRoot
	bunnyWeld.Parent = hatClone

	bunnyHum.PlatformStand = true

	for _, part in bunnyChar:GetDescendants() do
		if part:IsA("BasePart") then
			part.Massless = true
		end
	end

	pcall(function()
		bunnyRoot:SetNetworkOwner(humanPlayer)
		hatClone:SetNetworkOwner(humanPlayer)
	end)

	carryState.carrying = true
	carryState.weld = bunnyWeld
	carryState.lastAction = now

	debugPrint(humanPlayer.Name, "picked up", pairedPlayers.bunny.Name)

	if carryRemotes then
		local stateRemote = carryRemotes:FindFirstChild("CarryStateChanged") :: RemoteEvent?
		if stateRemote then
			stateRemote:FireAllClients("pickup")
		end
	end
end

local function dropBunny(humanPlayer: Player)
	if humanPlayer ~= pairedPlayers.human then return end
	if not carryState.carrying then return end

	local now = os.clock()
	if now - carryState.lastAction < CARRY_COOLDOWN then return end

	dropBunnyInternal()
end

local function initCarrySystem()
	local folder = Instance.new("Folder")
	folder.Name = "CarryRemotes"
	folder.Parent = ReplicatedStorage

	local pickupRemote = Instance.new("RemoteEvent")
	pickupRemote.Name = "RequestPickup"
	pickupRemote.Parent = folder

	local dropRemote = Instance.new("RemoteEvent")
	dropRemote.Name = "RequestDrop"
	dropRemote.Parent = folder

	local stateRemote = Instance.new("RemoteEvent")
	stateRemote.Name = "CarryStateChanged"
	stateRemote.Parent = folder

	carryRemotes = folder

	pickupRemote.OnServerEvent:Connect(pickupBunny)
	dropRemote.OnServerEvent:Connect(dropBunny)

	debugPrint("Carry system initialized")
end

local teleportDebounce: { [string]: boolean } = {}

local function hideBridge()
	if bridgePart then
		bridgePart.Transparency = 0.5
		bridgePart.CanCollide = false
	end
	bridgeActivated = false
end

local function showBridge()
	if bridgePart then
		TweenService:Create(bridgePart, TweenInfo.new(0.5), { Transparency = 0 }):Play()
		bridgePart.CanCollide = true
	end
	bridgeActivated = true
	debugPrint("Bridge activated by bunny!")
end

local function initBunnyBridge()
	local map = workspace:FindFirstChild("Other/Map")
	if not map then
		warn("[PairSystem] Other/Map not found, skipping bunny bridge")
		return
	end

	bridgePart = map:FindFirstChild("Bridge") :: UnionOperation?
	bunnyTeleporter3 = map:FindFirstChild("Teleporter3") :: BasePart?
	bunnyTeleporter4 = map:FindFirstChild("Teleporter4") :: BasePart?
	bridgeButtonPart = map:FindFirstChild("BridgeButton") :: BasePart?

	if not bridgePart then
		warn("[PairSystem] Bridge not found in Other/Map")
		return
	end

	if not bunnyTeleporter3 then
		warn("[PairSystem] Teleporter3 not found in Other/Map")
		return
	end

	if not bunnyTeleporter4 then
		warn("[PairSystem] Teleporter4 not found in Other/Map")
		return
	end

	if not bridgeButtonPart then
		warn("[PairSystem] BridgeButton not found in Other/Map")
		return
	end

	-- Start with bridge hidden (0.5 transparency, non-collidable)
	hideBridge()

	-- When bunny touches Teleporter3 (by falling into the hole), teleport them to Teleporter4
	janitor:Add(bunnyTeleporter3.Touched:Connect(function(hit: BasePart)
		local player = getPlayerFromPart(hit)
		if not player then return end
		if player ~= pairedPlayers.bunny then return end

		local debounceKey = "BunnyTP3_" .. tostring(player.UserId)
		if teleportDebounce[debounceKey] then return end
		teleportDebounce[debounceKey] = true

		local rootPart = getRootPart(player)
		if rootPart and bunnyTeleporter4 then
			-- Place bunny behind TP4 (inside the archway, under TopOfTeleporter)
			local toLook = bunnyTeleporter4.CFrame.LookVector
			local spawnPos = bunnyTeleporter4.Position - toLook * 2
			-- Face toward BridgeButton so bunny walks toward it, not off the edge
			local lookTarget = bridgeButtonPart and bridgeButtonPart.Position or (spawnPos + toLook)
			local flatDir = Vector3.new(lookTarget.X - spawnPos.X, 0, lookTarget.Z - spawnPos.Z).Unit
			rootPart.CFrame = getGroundSnappedCFrame(spawnPos, flatDir)
			debugPrint(player.Name, "teleported from Teleporter3 to Teleporter4")
		end

		task.delay(2, function()
			teleportDebounce[debounceKey] = nil
		end)
	end))

	-- Tag bridge button for client-side detection
	CollectionService:AddTag(bridgeButtonPart, "ObstacleButton")

	debugPrint("Bunny bridge system initialized (Teleporter3->4 + BridgeButton)")
end

local function lockSeesawAsRamp()
	if seesawState.locked then return end
	seesawState.locked = true
	seesawState.currentAngle = SEESAW_TILT_MAX
	seesawState.targetAngle = SEESAW_TILT_MAX

	-- Set plank to the fully tilted ramp position
	if seesawState.plank and seesawState.originalPlankCFrame and seesawState.pivotWorld then
		local pivotCF = CFrame.new(seesawState.pivotWorld)
		local relCF = pivotCF:Inverse() * seesawState.originalPlankCFrame
		local rotated = CFrame.Angles(-math.rad(SEESAW_TILT_MAX), 0, 0) * relCF
		seesawState.plank.CFrame = pivotCF * rotated
		seesawState.plank.Anchored = true
	end

	debugPrint("Seesaw locked as ramp! Both buttons pressed.")
end

local function initSeesaw()
	local map = workspace:FindFirstChild("Other/Map")
	if not map then return end

	local seesawModel = map:FindFirstChild("Seesaw")
	local button1 = map:FindFirstChild("SeesawButton1")
	local button2 = map:FindFirstChild("SeesawButton2")

	if not seesawModel or not button1 or not button2 then
		warn("[PairSystem] Seesaw parts not found")
		return
	end

	-- Find fulcrum (small part) and plank (long part)
	local fulcrum: BasePart? = nil
	local plank: BasePart? = nil
	for _, child in seesawModel:GetChildren() do
		if child:IsA("BasePart") then
			if math.max(child.Size.X, child.Size.Y, child.Size.Z) > 10 then
				plank = child
			else
				fulcrum = child
			end
		end
	end

	if not fulcrum or not plank then
		warn("[PairSystem] Fulcrum or plank not found in Seesaw model")
		return
	end

	seesawState.fulcrum = fulcrum
	seesawState.plank = plank
	seesawState.originalPlankCFrame = plank.CFrame
	seesawState.currentAngle = 0
	seesawState.targetAngle = 0
	seesawState.tilted = false
	seesawState.locked = false
	seesawState.button1Pressed = false
	seesawState.button2Pressed = false

	-- Pivot point = fulcrum top center
	local pivotWorld = fulcrum.Position + Vector3.new(0, fulcrum.Size.Y / 2, 0)
	seesawState.pivotWorld = pivotWorld

	-- Left side detection zone (lower Z half of the plank)
	-- Plank extends along world Z due to (0, -90, 0) orientation
	local plankHalfLen = plank.Size.X / 2
	local leftEndZ = plank.Position.Z - plankHalfLen
	local plankCenterZ = plank.Position.Z
	local plankWidth = plank.Size.Z

	-- Heartbeat: check if human is on left side and smoothly tilt
	local originalCF = plank.CFrame
	janitor:Add(RunService.Heartbeat:Connect(function(dt: number)
		if seesawState.locked then return end

		-- Check if human is standing on the left half of the seesaw
		local humanOnLeft = false
		local human = pairedPlayers.human
		if human and human.Character then
			local root = human.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local rootPos = root.Position
				local onLeftZ = rootPos.Z >= leftEndZ - 2 and rootPos.Z <= plankCenterZ + 2
				local onWidth = math.abs(rootPos.X - plank.Position.X) < plankWidth + 2
				local abovePlank = rootPos.Y >= plank.Position.Y - 2 and rootPos.Y <= plank.Position.Y + 8
				humanOnLeft = onLeftZ and onWidth and abovePlank
			end
		end

		-- Set target angle based on human presence
		if humanOnLeft then
			seesawState.targetAngle = SEESAW_TILT_MAX
		else
			seesawState.targetAngle = 0
		end

		-- Smoothly interpolate current angle toward target
		if seesawState.currentAngle ~= seesawState.targetAngle then
			local step = SEESAW_TILT_SPEED * dt
			if seesawState.targetAngle > seesawState.currentAngle then
				seesawState.currentAngle = math.min(seesawState.currentAngle + step, seesawState.targetAngle)
			else
				seesawState.currentAngle = math.max(seesawState.currentAngle - step, seesawState.targetAngle)
			end

			-- Rotate plank around world X axis at the pivot point
			-- Negative angle: left (-Z) end goes DOWN, right (+Z) end goes UP
			local pivotCF = CFrame.new(pivotWorld)
			local relCF = pivotCF:Inverse() * originalCF
			local rotated = CFrame.Angles(-math.rad(seesawState.currentAngle), 0, 0) * relCF
			plank.CFrame = pivotCF * rotated
		end
	end))

	-- Tag seesaw buttons for client-side detection
	CollectionService:AddTag(button1, "ObstacleButton")
	CollectionService:AddTag(button2, "ObstacleButton")

	debugPrint("Seesaw system initialized")
end

local function hideInvisPlatforms()
	for _, part in invisPlatformsState.parts do
		part.Transparency = 0.5
		part.CanCollide = false
	end
	invisPlatformsState.activated = false
end

local function showInvisPlatforms()
	for _, part in invisPlatformsState.parts do
		TweenService:Create(part, TweenInfo.new(0.5), { Transparency = 0 }):Play()
		part.CanCollide = true
	end
	invisPlatformsState.activated = true
	debugPrint("InvisPlatforms revealed!")
end

local function initInvisPlatforms()
	local map = workspace:FindFirstChild("Other/Map")
	if not map then return end

	local invisModel = map:FindFirstChild("InvisPlatforms")
	local button1 = map:FindFirstChild("ButtonForPlat1")
	local button2 = map:FindFirstChild("ButtonForPlat2")

	if not invisModel or not button1 or not button2 then
		warn("[PairSystem] InvisPlatforms parts not found")
		return
	end

	-- Collect platform parts
	invisPlatformsState.parts = {}
	for _, child in invisModel:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(invisPlatformsState.parts, child)
		end
	end

	-- Set initial hidden state (semi-transparent and non-collidable)
	hideInvisPlatforms()

	-- Tag buttons for client-side detection
	CollectionService:AddTag(button1, "ObstacleButton")
	CollectionService:AddTag(button2, "ObstacleButton")

	debugPrint("InvisPlatforms system initialized")
end

local function initSpinner()
	local map = workspace:FindFirstChild("Other/Map")
	if not map then return end

	local spinnerModel = map:FindFirstChild("Spinner")
	if not spinnerModel then
		warn("[PairSystem] Spinner model not found")
		return
	end

	local killPart = spinnerModel:FindFirstChild("KillPart")
	if not killPart then
		warn("[PairSystem] KillPart not found in Spinner")
		return
	end

	-- Tag for client-side rotation and kill detection
	CollectionService:AddTag(spinnerModel, "SpinnerModel")
	CollectionService:AddTag(killPart, "KillPart")

	-- Spinner2: same system, faster speed
	local spinner2 = map:FindFirstChild("Spinner2")
	if spinner2 then
		spinner2:SetAttribute("SpinnerSpeed", 200)
		CollectionService:AddTag(spinner2, "SpinnerModel")
		-- Tag the long arm as KillPart (the larger child part)
		for _, child in spinner2:GetChildren() do
			if child:IsA("BasePart") and child.Size.X > 10 then
				CollectionService:AddTag(child, "KillPart")
				break
			end
		end
		debugPrint("Spinner2 system initialized (client-sided, speed=200)")
	end

	debugPrint("Spinner system initialized (client-sided)")
end

local function hideLadder()
	if carrotState.topLadder then
		carrotState.topLadder.Transparency = 0.5
		carrotState.topLadder.CanCollide = false
	end
	for _, part in carrotState.ladder2Parts do
		part.Transparency = 1
		part.CastShadow = false
		part.CanCollide = false
		part.Anchored = true
	end
	carrotState.ladderRevealed = false
end

local function revealLadder()
	if carrotState.topLadder then
		TweenService:Create(carrotState.topLadder, TweenInfo.new(0.5), { Transparency = 0 }):Play()
		carrotState.topLadder.CanCollide = true
	end
	for _, part in carrotState.ladder2Parts do
		part.Transparency = 1
		part.CastShadow = false
		part.CanCollide = true
		part.Anchored = true
	end
	carrotState.ladderRevealed = true
	debugPrint("Ladder revealed! All carrots collected.")
end

local function initCarrotCollection()
	local map = workspace:FindFirstChild("Other/Map")
	if not map then return end

	local topLadder = map:FindFirstChild("TopLadder")
	local ladder2 = workspace:FindFirstChild("Ladder2")

	if not topLadder then
		warn("[PairSystem] TopLadder not found")
		return
	end

	carrotState.topLadder = topLadder

	-- Collect Ladder2 truss parts (located at Workspace.Ladder2, not in Other/Map)
	carrotState.ladder2Parts = {}
	if ladder2 then
		for _, child in ladder2:GetChildren() do
			if child:IsA("BasePart") then
				table.insert(carrotState.ladder2Parts, child)
			end
		end
	end

	-- Set initial hidden state for ladder
	hideLadder()

	-- Find and setup carrots (bunny-only touch collection)
	carrotState.carrots = {}
	carrotState.totalCollected = 0

	for i = 1, 3 do
		local carrot = map:FindFirstChild("Carrot" .. i)
		if carrot then
			table.insert(carrotState.carrots, { part = carrot, collected = false })

			local index = i
			janitor:Add(carrot.Touched:Connect(function(hit: BasePart)
				if carrotState.ladderRevealed then return end

				local carrotInfo = carrotState.carrots[index]
				if carrotInfo.collected then return end

				local player = getPlayerFromPart(hit)
				if not player then return end
				if player ~= pairedPlayers.bunny then return end

				carrotInfo.collected = true
				carrot.Transparency = 1
				carrotState.totalCollected = carrotState.totalCollected + 1

				debugPrint("Carrot" .. index .. " collected! (" .. carrotState.totalCollected .. "/3)")

				if carrotState.totalCollected >= 3 then
					revealLadder()
				end
			end))
		else
			warn("[PairSystem] Carrot" .. i .. " not found")
		end
	end

	debugPrint("Carrot collection system initialized with", #carrotState.carrots, "carrots")
end

local function initBunnyTP5()
	local map = workspace:FindFirstChild("Other/Map")
	if not map then return end

	local tp5 = map:FindFirstChild("Teleporter5") :: BasePart?
	local tp6 = map:FindFirstChild("Teleporter6") :: BasePart?
	local elevatorButton = map:FindFirstChild("ElevatorButton") :: BasePart?

	if not tp5 or not tp6 then
		warn("[PairSystem] Teleporter5 or Teleporter6 not found")
		return
	end

	janitor:Add(tp5.Touched:Connect(function(hit: BasePart)
		local player = getPlayerFromPart(hit)
		if not player then return end
		if player ~= pairedPlayers.bunny then return end

		local debounceKey = "BunnyTP5_" .. tostring(player.UserId)
		if teleportDebounce[debounceKey] then return end
		teleportDebounce[debounceKey] = true

		local rootPart = getRootPart(player)
		if rootPart and tp6 then
			-- Spawn in front of TP6 (ground is on the +Z side)
			local toLook = tp6.CFrame.LookVector
			local spawnPos = tp6.Position + toLook * 3
			-- Face toward ElevatorButton if it exists, otherwise use TP6 look
			local lookTarget = elevatorButton and elevatorButton.Position or (spawnPos + toLook)
			local flatDir = Vector3.new(lookTarget.X - spawnPos.X, 0, lookTarget.Z - spawnPos.Z).Unit
			rootPart.CFrame = getGroundSnappedCFrame(spawnPos, flatDir)
		end

		debugPrint(player.Name, "teleported from Teleporter5 to Teleporter6")

		task.delay(2, function()
			teleportDebounce[debounceKey] = nil
		end)
	end))

	debugPrint("Bunny TP5->6 system initialized")
end

local function initElevator()
	local map = workspace:FindFirstChild("Other/Map")
	if not map then return end

	local elevatorModel = map:FindFirstChild("Elevator")
	local elevatorButton = map:FindFirstChild("ElevatorButton") :: BasePart?
	local elevatorPart1 = map:FindFirstChild("Elevatorpart1") :: BasePart?
	local elevatorPart2 = map:FindFirstChild("Elevatorpart2") :: BasePart?

	if not elevatorModel or not elevatorButton then
		warn("[PairSystem] Elevator or ElevatorButton not found")
		return
	end

	elevatorState.model = elevatorModel
	elevatorState.button = elevatorButton
	elevatorState.originalPivot = elevatorModel:GetPivot()
	elevatorState.currentRise = 0
	elevatorState.reached = false

	-- Calculate target rise: elevator top should reach top of Elevatorpart1/2
	local elevatorTopY = 0
	for _, child in elevatorModel:GetChildren() do
		if child:IsA("BasePart") then
			local childTop = child.Position.Y + child.Size.Y / 2
			if childTop > elevatorTopY then
				elevatorTopY = childTop
			end
		end
	end

	local targetTopY = 0
	if elevatorPart1 then
		local partTop = elevatorPart1.Position.Y + elevatorPart1.Size.Y / 2
		if partTop > targetTopY then targetTopY = partTop end
	end
	if elevatorPart2 then
		local partTop = elevatorPart2.Position.Y + elevatorPart2.Size.Y / 2
		if partTop > targetTopY then targetTopY = partTop end
	end

	elevatorState.targetRise = targetTopY - elevatorTopY
	debugPrint("Elevator target rise:", elevatorState.targetRise, "studs")

	-- Button detection zone
	local btnPos = elevatorButton.Position
	local btnSize = elevatorButton.Size
	local btnMinX = btnPos.X - btnSize.X / 2 - 1
	local btnMaxX = btnPos.X + btnSize.X / 2 + 1
	local btnMinZ = btnPos.Z - btnSize.Z / 2 - 1
	local btnMaxZ = btnPos.Z + btnSize.Z / 2 + 1
	local btnMinY = btnPos.Y - 1
	local btnMaxY = btnPos.Y + 6

	janitor:Add(RunService.Heartbeat:Connect(function(dt: number)
		local bunny = pairedPlayers.bunny
		if not bunny then return end

		local rootPart = getRootPart(bunny)
		if not rootPart then return end

		local pos = rootPart.Position
		local onButton = pos.X >= btnMinX and pos.X <= btnMaxX
			and pos.Z >= btnMinZ and pos.Z <= btnMaxZ
			and pos.Y >= btnMinY and pos.Y <= btnMaxY

		if onButton then
			-- Move elevator upward
			if elevatorState.currentRise >= elevatorState.targetRise then
				elevatorState.reached = true
				return
			end
			local moveAmount = ELEVATOR_SPEED * dt
			elevatorState.currentRise = math.min(elevatorState.currentRise + moveAmount, elevatorState.targetRise)
		else
			-- Move elevator back down
			if elevatorState.currentRise <= 0 then return end
			elevatorState.reached = false
			local moveAmount = ELEVATOR_SPEED * dt
			elevatorState.currentRise = math.max(elevatorState.currentRise - moveAmount, 0)
		end

		local newPivot = elevatorState.originalPivot + Vector3.new(0, elevatorState.currentRise, 0)
		elevatorModel:PivotTo(newPivot)

		if elevatorState.currentRise >= elevatorState.targetRise and not elevatorState.reached then
			elevatorState.reached = true
			debugPrint("Elevator reached top!")
		end
	end))

	debugPrint("Elevator system initialized")
end

local function initBunnyTP7()
	local map = workspace:FindFirstChild("Other/Map")
	if not map then return end

	local tp7 = map:FindFirstChild("Teleporter7") :: BasePart?

	-- Teleporter8 is in Workspace.Decor (not Other/Map), search recursively
	local decor = workspace:FindFirstChild("Decor")
	local tp8 = if decor then decor:FindFirstChild("Teleporter8", true) :: BasePart? else nil

	if not tp7 or not tp8 then
		warn("[PairSystem] Teleporter7 or Teleporter8 not found")
		return
	end

	janitor:Add(tp7.Touched:Connect(function(hit: BasePart)
		local player = getPlayerFromPart(hit)
		if not player then return end
		if player ~= pairedPlayers.bunny then return end

		local debounceKey = "BunnyTP7_" .. tostring(player.UserId)
		if teleportDebounce[debounceKey] then return end
		teleportDebounce[debounceKey] = true

		local rootPart = getRootPart(player)
		if rootPart and tp8 then
			local toLook = tp8.CFrame.LookVector
			local spawnPos = tp8.Position + toLook * 3
			local flatDir = Vector3.new(toLook.X, 0, toLook.Z).Unit
			rootPart.CFrame = getGroundSnappedCFrame(spawnPos, flatDir)
		end

		debugPrint(player.Name, "teleported from Teleporter7 to Teleporter8")

		task.delay(2, function()
			teleportDebounce[debounceKey] = nil
		end)
	end))

	debugPrint("Bunny TP7->8 system initialized")
end

local function initTP9()
	local map = workspace:FindFirstChild("Other/Map")
	if not map then return end

	local tp9 = map:FindFirstChild("Teleporter9") :: BasePart?

	-- Teleporter10 is directly under Workspace.Decor
	local decor = workspace:FindFirstChild("Decor")
	local tp10: BasePart? = nil
	if decor then
		tp10 = decor:FindFirstChild("Teleporter10") :: BasePart?
	end

	if not tp9 or not tp10 then
		warn("[PairSystem] Teleporter9 or Teleporter10 not found")
		return
	end

	janitor:Add(tp9.Touched:Connect(function(hit: BasePart)
		local player = getPlayerFromPart(hit)
		if not player then return end
		if not pairedPlayers.bunny or not pairedPlayers.human then return end
		if player ~= pairedPlayers.bunny and player ~= pairedPlayers.human then return end

		local debounceKey = "TP9_" .. tostring(player.UserId)
		if teleportDebounce[debounceKey] then return end
		teleportDebounce[debounceKey] = true

		local rootPart = getRootPart(player)
		if rootPart and tp10 then
			local toLook = tp10.CFrame.LookVector
			local spawnPos = tp10.Position + toLook * 5
			rootPart.CFrame = getGroundSnappedCFrame(spawnPos, toLook)
		end

		debugPrint(player.Name, "teleported from Teleporter9 to Teleporter10")

		task.delay(2, function()
			teleportDebounce[debounceKey] = nil
		end)
	end))

	debugPrint("TP9->10 system initialized")
end

local function trySwapPlayers()
	if switchButtonsState.swapped then return end

	local p1 = switchButtonsState.button1Player
	local p2 = switchButtonsState.button2Player
	if not p1 or not p2 then return end
	if p1 == p2 then return end

	local root1 = getRootPart(p1)
	local root2 = getRootPart(p2)
	if not root1 or not root2 then return end

	local cf1 = root1.CFrame
	local cf2 = root2.CFrame

	root1.CFrame = cf2
	root2.CFrame = cf1

	switchButtonsState.swapped = true
	debugPrint("Players swapped positions via SwitchButtons!")
end

local function initSwitchButtons()
	local map = workspace:FindFirstChild("Other/Map")
	if not map then return end

	local switchButton1 = map:FindFirstChild("SwitchButton1") :: BasePart?
	local switchButton2 = map:FindFirstChild("SwitchButton2") :: BasePart?

	if not switchButton1 or not switchButton2 then
		warn("[PairSystem] SwitchButton1 or SwitchButton2 not found")
		return
	end

	switchButtonsState.button1Player = nil
	switchButtonsState.button2Player = nil
	switchButtonsState.swapped = false

	-- Tag buttons for client-side detection
	CollectionService:AddTag(switchButton1, "ObstacleButton")
	CollectionService:AddTag(switchButton2, "ObstacleButton")

	debugPrint("SwitchButtons system initialized")
end

local function initElevator2()
	local map = workspace:FindFirstChild("Other/Map")
	if not map then return end

	local elevator2Model = map:FindFirstChild("Elevator2")
	local elevator2Button = map:FindFirstChild("Elevator2Button") :: BasePart?

	if not elevator2Model or not elevator2Button then
		warn("[PairSystem] Elevator2 or Elevator2Button not found")
		return
	end

	elevator2State.model = elevator2Model
	elevator2State.button = elevator2Button
	elevator2State.originalPivot = elevator2Model:GetPivot()
	elevator2State.currentRise = 0
	elevator2State.reached = false

	-- Calculate target rise: elevator2 top should reach the button's platform level
	local elevator2TopY = 0
	for _, child in elevator2Model:GetChildren() do
		if child:IsA("BasePart") then
			local childTop = child.Position.Y + child.Size.Y / 2
			if childTop > elevator2TopY then
				elevator2TopY = childTop
			end
		end
	end

	-- Use button Y as target (the platform the button sits on)
	local targetTopY = elevator2Button.Position.Y

	elevator2State.targetRise = targetTopY - elevator2TopY
	debugPrint("Elevator2 target rise:", elevator2State.targetRise, "studs")

	-- Button detection zone
	local btnPos = elevator2Button.Position
	local btnSize = elevator2Button.Size
	local btnMinX = btnPos.X - btnSize.X / 2 - 1
	local btnMaxX = btnPos.X + btnSize.X / 2 + 1
	local btnMinZ = btnPos.Z - btnSize.Z / 2 - 1
	local btnMaxZ = btnPos.Z + btnSize.Z / 2 + 1
	local btnMinY = btnPos.Y - 1
	local btnMaxY = btnPos.Y + 6

	janitor:Add(RunService.Heartbeat:Connect(function(dt: number)
		local onButton = false
		for _, player in Players:GetPlayers() do
			local rootPart = getRootPart(player)
			if rootPart then
				local pos = rootPart.Position
				if pos.X >= btnMinX and pos.X <= btnMaxX
					and pos.Z >= btnMinZ and pos.Z <= btnMaxZ
					and pos.Y >= btnMinY and pos.Y <= btnMaxY
				then
					onButton = true
					break
				end
			end
		end

		if onButton then
			-- Move elevator2 upward
			if elevator2State.currentRise >= elevator2State.targetRise then
				elevator2State.reached = true
				return
			end
			local moveAmount = ELEVATOR2_SPEED * dt
			elevator2State.currentRise = math.min(elevator2State.currentRise + moveAmount, elevator2State.targetRise)
		else
			-- Move elevator2 back down
			if elevator2State.currentRise <= 0 then return end
			elevator2State.reached = false
			local moveAmount = ELEVATOR2_SPEED * dt
			elevator2State.currentRise = math.max(elevator2State.currentRise - moveAmount, 0)
		end

		local newPivot = elevator2State.originalPivot + Vector3.new(0, elevator2State.currentRise, 0)
		elevator2Model:PivotTo(newPivot)

		if elevator2State.currentRise >= elevator2State.targetRise and not elevator2State.reached then
			elevator2State.reached = true
			debugPrint("Elevator2 reached top!")
		end
	end))

	debugPrint("Elevator2 system initialized")
end

local function hideConveyorJump()
	if conveyorState.jump then
		conveyorState.jump.Transparency = 0.5
		conveyorState.jump.CanCollide = false
	end
	conveyorState.jumpRevealed = false
end

local function showConveyorJump()
	if conveyorState.jump then
		TweenService:Create(conveyorState.jump, TweenInfo.new(0.5), { Transparency = 0 }):Play()
		conveyorState.jump.CanCollide = true
	end
	conveyorState.jumpRevealed = true
	debugPrint("ConveyorJump revealed!")
end

local function initConveyorBelt()
	local map = workspace:FindFirstChild("Other/Map")
	if not map then return end

	local belt = map:FindFirstChild("ConveyorBelt") :: BasePart?
	local button = map:FindFirstChild("ConveyorButton") :: BasePart?
	local jump = map:FindFirstChild("ConveyorJump") :: BasePart?

	if not belt then
		warn("[PairSystem] ConveyorBelt not found")
		return
	end

	conveyorState.belt = belt
	conveyorState.button = button
	conveyorState.jump = jump

	-- Set conveyor velocity (moves objects in -X direction toward button)
	belt.AssemblyLinearVelocity = Vector3.new(-CONVEYOR_SPEED, 0, 0)

	-- Create scrolling texture on top face for visual movement
	local texture = Instance.new("Texture")
	texture.Face = Enum.NormalId.Top
	texture.Texture = "rbxassetid://6372755229"
	texture.StudsPerTileU = 4
	texture.StudsPerTileV = 4
	texture.Color3 = Color3.fromRGB(50, 50, 50)
	texture.Transparency = 0.5
	texture.Parent = belt
	conveyorState.texture = texture

	-- Animate texture offset to create scrolling visual matching belt direction
	local textureOffset = 0
	local beltMinX = belt.Position.X - belt.Size.X / 2
	local beltMaxX = belt.Position.X + belt.Size.X / 2
	local beltMinZ = belt.Position.Z - belt.Size.Z / 2 - 0.5
	local beltMaxZ = belt.Position.Z + belt.Size.Z / 2 + 0.5
	local beltTopY = belt.Position.Y + belt.Size.Y / 2

	janitor:Add(RunService.Heartbeat:Connect(function(dt: number)
		-- Animate texture
		textureOffset = textureOffset - CONVEYOR_SPEED * dt
		texture.OffsetStudsU = textureOffset

		-- Apply conveyor velocity to bunny standing on belt
		local bunny = pairedPlayers.bunny
		if not bunny then return end

		local rootPart = getRootPart(bunny)
		if not rootPart then return end

		local pos = rootPart.Position
		if pos.X >= beltMinX and pos.X <= beltMaxX
			and pos.Z >= beltMinZ and pos.Z <= beltMaxZ
			and pos.Y >= beltTopY and pos.Y <= beltTopY + 5 then
			-- Apply conveyor push to bunny
			local vel = rootPart.AssemblyLinearVelocity
			rootPart.AssemblyLinearVelocity = Vector3.new(-CONVEYOR_SPEED, vel.Y, vel.Z)
		end
	end))

	-- Prevent human from using conveyor belt via collision groups on HumanBlock parts
	local blockers = workspace:FindFirstChild("Blockers")
	if blockers then
		if not PhysicsService:IsCollisionGroupRegistered("BunnyBody") then
			PhysicsService:RegisterCollisionGroup("BunnyBody")
		end
		if not PhysicsService:IsCollisionGroupRegistered("HumanBlocker") then
			PhysicsService:RegisterCollisionGroup("HumanBlocker")
		end
		PhysicsService:CollisionGroupSetCollidable("BunnyBody", "HumanBlocker", false)

		for _, child in blockers:GetChildren() do
			if child:IsA("BasePart") and child.Name == "HumanBlock" then
				child.CollisionGroup = "HumanBlocker"
				child.Anchored = true
			end
		end

		-- Also apply to HumanBlockingPart in Other/Map
		local map = workspace:FindFirstChild("Other/Map")
		if map then
			local hbp = map:FindFirstChild("HumanBlockingPart")
			if hbp and hbp:IsA("BasePart") then
				hbp.CollisionGroup = "HumanBlocker"
				debugPrint("HumanBlockingPart assigned to HumanBlocker collision group")
			end
		end

		debugPrint("HumanBlock collision groups configured")
	end

	-- Set initial hidden state for ConveyorJump and tag for client-side oscillation
	if jump then
		hideConveyorJump()
		CollectionService:AddTag(jump, "OscillatingPlatform")
	end

	-- Tag ConveyorButton for client-side detection
	if button then
		CollectionService:AddTag(button, "ObstacleButton")
	end

	debugPrint("Conveyor belt system initialized")
end

local function initTeleporters()
	local teleporterPairs: { { from: BasePart, to: BasePart } } = {}

	local index = 1
	while true do
		-- Skip Teleporter3->4, Teleporter5->6, Teleporter7->8 (handled as bunny-only), and Teleporter9->10 (handled explicitly)
		if index == 3 or index == 5 or index == 7 or index == 9 then
			index = index + 2
			continue
		end

		local fromName = "Teleporter" .. index
		local toName = "Teleporter" .. (index + 1)

		local fromPart: BasePart? = nil
		local toPart: BasePart? = nil

		for _, desc in workspace:GetDescendants() do
			if desc:IsA("BasePart") then
				if desc.Name == fromName then
					fromPart = desc
				elseif desc.Name == toName then
					toPart = desc
				end
			end
		end

		if not fromPart or not toPart then break end

		table.insert(teleporterPairs, { from = fromPart, to = toPart })
		debugPrint("Found teleporter pair:", fromName, "->", toName)
		index = index + 2
	end

	for _, pair in teleporterPairs do
		local fromPart = pair.from
		local toPart = pair.to

		fromPart.Touched:Connect(function(hit: BasePart)
			local player = getPlayerFromPart(hit)
			if not player then return end
			if not pairedPlayers.bunny or not pairedPlayers.human then return end
			if player ~= pairedPlayers.bunny and player ~= pairedPlayers.human then return end

			-- Skip bunny teleport when being carried (weld moves them with the human)
			if player == pairedPlayers.bunny and carryState.carrying then return end

			-- Per-player debounce key so each player teleports independently
			local debounceKey = tostring(fromPart) .. "_" .. tostring(player.UserId)
			if teleportDebounce[debounceKey] then return end
			teleportDebounce[debounceKey] = true

			-- Find the best exit direction (most ground, excluding teleporter model)
			local bestPos, bestDir = findBestTeleporterExit(toPart)
			local excludeModel = toPart.Parent

			local rootPart = getRootPart(player)
			if rootPart then
				rootPart.CFrame = getGroundSnappedCFrame(bestPos, bestDir, if excludeModel then { excludeModel } else nil)
			end

			debugPrint(player.Name, "teleported individually from", fromPart.Name, "to", toPart.Name)

			task.delay(2, function()
				teleportDebounce[debounceKey] = nil
			end)
		end)
	end

	debugPrint("Teleporter system initialized with", #teleporterPairs, "pairs")
end

local function setupWaterDeath()
	-- Tag water parts for client-side kill detection
	local function tagWaterPart(part: BasePart)
		CollectionService:AddTag(part, "KillPart")
	end

	local waterModel = workspace:FindFirstChild("Water")
	if waterModel then
		for _, part in waterModel:GetChildren() do
			if part:IsA("BasePart") then
				tagWaterPart(part)
			end
		end
	end

	local otherMap = workspace:FindFirstChild("Other/Map")
	if otherMap then
		for _, desc in otherMap:GetDescendants() do
			if desc:IsA("BasePart") and desc.Material == Enum.Material.Glacier then
				local c = desc.Color
				if c.R < 0.3 and c.G > 0.4 and c.B > 0.7 and (desc.Size.X > 10 or desc.Size.Z > 10) then
					tagWaterPart(desc)
					debugPrint("Tagged water death part at", math.floor(desc.Position.X), math.floor(desc.Position.Y), math.floor(desc.Position.Z))
				end
			end
		end
	end

	debugPrint("Water death setup complete (client-sided)")
end

local function connectDiedForPlayer(player: Player)
	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	humanoid.Died:Once(function()
		local partner = if player == pairedPlayers.bunny then pairedPlayers.human else pairedPlayers.bunny
		if not partner then return end

		debugPrint(player.Name, "died - killing partner", partner.Name)

		local partnerChar = partner.Character
		if partnerChar then
			local partnerHumanoid = partnerChar:FindFirstChildOfClass("Humanoid")
			if partnerHumanoid and partnerHumanoid.Health > 0 then
				partnerHumanoid.Health = 0
			end
		end

		-- Don't call fullReset() here — wait for player to choose via YouDied UI
	end)
end

local function setupLinkedHealth(bunny: Player, human: Player)
	_healthLinked = true

	connectDiedForPlayer(bunny)
	connectDiedForPlayer(human)

	bunny.CharacterAdded:Connect(function()
		task.wait(0.5)
		if pairedPlayers.bunny == bunny and pairedPlayers.human == human then
			-- Clear stale carry state from previous life (e.g. died during carry / revive)
			if carryState.carrying then
				carryState.carrying = false
				carryState.weld = nil
				carryState.lastAction = os.clock()
				if carryRemotes then
					local stateRemote = carryRemotes:FindFirstChild("CarryStateChanged") :: RemoteEvent?
					if stateRemote then
						stateRemote:FireAllClients("drop")
					end
				end
			end
			connectDiedForPlayer(bunny)
			-- Re-apply bunny shrink + model on respawn
			scaleCharacter(bunny, BUNNY_SCALE)
			assignBunnyCollisionGroup(bunny)
			applyBunnyModel(bunny)
		end
	end)

	human.CharacterAdded:Connect(function()
		task.wait(0.5)
		if pairedPlayers.bunny == bunny and pairedPlayers.human == human then
			-- Clear stale carry state from previous life
			if carryState.carrying then
				carryState.carrying = false
				carryState.weld = nil
				carryState.lastAction = os.clock()
				if carryRemotes then
					local stateRemote = carryRemotes:FindFirstChild("CarryStateChanged") :: RemoteEvent?
					if stateRemote then
						stateRemote:FireAllClients("drop")
					end
				end
			end
			connectDiedForPlayer(human)
		end
	end)

	debugPrint("Linked health established between", bunny.Name, "and", human.Name)
end

local function collectGateParts()
	gatePartStates = {}
	gateSignGuis = {}

	for _, child in workspace:GetDescendants() do
		if child:IsA("BasePart") then
			local pos = child.Position
			if pos.X > GATE_ZONE.minX and pos.X < GATE_ZONE.maxX
				and pos.Z > GATE_ZONE.minZ and pos.Z < GATE_ZONE.maxZ
				and pos.Y > GATE_ZONE.minY and pos.Y < GATE_ZONE.maxY then

				local isPairGate = child.Name == "PairGate"
				local isBar = child.Name == "Part" and child.Size.Y > 8 and child.Size.X < 1.5 and child.Size.Z < 1.5
				local isSign = child.Parent and child.Parent.Name == "Sign"

				table.insert(gatePartStates, {
					part = child,
					canCollide = child.CanCollide,
					transparency = child.Transparency,
					hideOnOpen = isPairGate or isBar or isSign,
				})

				if isSign then
					for _, gui in child:GetDescendants() do
						if gui:IsA("SurfaceGui") then
							table.insert(gateSignGuis, gui)
						end
					end
				end
			end
		end
	end

	debugPrint("Collected", #gatePartStates, "gate parts,", #gateSignGuis, "sign GUIs")
end

openGate = function()
	if gateOpen then return end
	gateOpen = true

	for _, state in gatePartStates do
		if state.part and state.part.Parent then
			state.part.CanCollide = false
			if state.hideOnOpen then
				state.part.Transparency = 1
			end
		end
	end

	for _, gui in gateSignGuis do
		gui.Enabled = false
	end

	debugPrint("Gate opened")
end

local function closeGate()
	if not gateOpen then return end
	gateOpen = false

	for _, state in gatePartStates do
		if state.part and state.part.Parent then
			state.part.CanCollide = state.canCollide
			state.part.Transparency = state.transparency
		end
	end

	for _, gui in gateSignGuis do
		gui.Enabled = true
	end

	debugPrint("Gate closed")
end

fullReset = function()
	debugPrint("=== FULL RESET ===")
	dropBunnyInternal()

	local bunny = pairedPlayers.bunny
	local human = pairedPlayers.human
	
	if bunny then
		bunny:SetAttribute("PairRole", false)
		bunny:SetAttribute("InPair", false)
		-- Restore bunny to normal size and remove bunny model
		removeBunnyModel(bunny)
		scaleCharacter(bunny, 1)
		clearBunnyCollisionGroup(bunny)
		if bunny.Character then
			bunny.Character:FindFirstChild("CollisionPart").Transparency = 1
			bunny.Character.HumanoidRootPart.CFrame = workspace.SpawnLocation.CFrame
		end
	end
	if human then
		bunny:SetAttribute("InPair", false)
		human:SetAttribute("PairRole", false)
		human:SetAttribute("CarryEnabled", false)
		if human.Character then			
			human.Character:FindFirstChild("CollisionPart").Transparency = 1
			human.Character.HumanoidRootPart.CFrame = workspace.SpawnLocation.CFrame
		end
	end


	pairedPlayers.bunny = nil
	pairedPlayers.human = nil
	passedGate = {}
	_healthLinked = false

	if gateOpen then
		closeGate()
	end

	resetButtonGates()

	for _, machine in machines do
		machine.paired = false
		machine.awaitingVotes = false
		machine.countdownActive = false
		machine.bunny.player = nil
		machine.bunny.inside = false
		machine.human.player = nil
		machine.human.inside = false
	end
	playerMachine = {}

	if carryRemotes then
		local stateRemote = carryRemotes:FindFirstChild("CarryStateChanged") :: RemoteEvent?
		if stateRemote then
			stateRemote:FireAllClients("drop")
		end
	end

	carryState.carrying = false
	carryState.weld = nil
	carryState.lastAction = 0

	hideBridge()

	-- Reset seesaw to original state
	if seesawState.plank and seesawState.originalPlankCFrame then
		seesawState.plank.Anchored = true
		seesawState.plank.CFrame = seesawState.originalPlankCFrame
		seesawState.currentAngle = 0
		seesawState.targetAngle = 0
		seesawState.tilted = false
		seesawState.locked = false
		seesawState.button1Pressed = false
		seesawState.button2Pressed = false
	end

	-- Reset InvisPlatforms to hidden state
	if #invisPlatformsState.parts > 0 then
		for _, part in invisPlatformsState.parts do
			part.Transparency = 0.5
			part.CanCollide = false
		end
		invisPlatformsState.button1Pressed = false
		invisPlatformsState.button2Pressed = false
		invisPlatformsState.activated = false
	end

	-- Reset carrot collection and hide ladder
	for _, carrotInfo in carrotState.carrots do
		carrotInfo.part.Transparency = 0
		carrotInfo.collected = false
	end
	carrotState.totalCollected = 0
	if carrotState.ladderRevealed then
		hideLadder()
	end

	-- Reset elevator to original position
	if elevatorState.model and elevatorState.originalPivot then
		elevatorState.model:PivotTo(elevatorState.originalPivot)
		elevatorState.currentRise = 0
		elevatorState.reached = false
	end

	-- Reset elevator2 to original position
	if elevator2State.model and elevator2State.originalPivot then
		elevator2State.model:PivotTo(elevator2State.originalPivot)
		elevator2State.currentRise = 0
		elevator2State.reached = false
	end

	-- Reset switch buttons
	switchButtonsState.button1Player = nil
	switchButtonsState.button2Player = nil
	switchButtonsState.swapped = false

	-- Reset conveyor jump to hidden state
	if conveyorState.jump then
		conveyorState.jump.Transparency = 0.5
		conveyorState.jump.CanCollide = false
		conveyorState.jumpRevealed = false
	end

	for key in teleportDebounce do
		teleportDebounce[key] = nil
	end

	-- Disable snow SpawnLocation and clear RespawnLocation when partnership ends
	do
		local snowMap = workspace:FindFirstChild("SnowMap")
		local snowSpawn = snowMap and snowMap:FindFirstChild("SpawnLocation") :: SpawnLocation?
		if snowSpawn then
			snowSpawn.Enabled = false
		end
		if bunny then bunny.RespawnLocation = nil end
		if human then human.RespawnLocation = nil end
	end

	-- Clear active map tracking (maps stay visible)
	activeMapName = nil

	debugPrint("=== RESET COMPLETE ===")
end

local function onGateTriggerTouched(hit: BasePart)
	if not gateOpen then return end

	local player = getPlayerFromPart(hit)
	if not player then return end

	if not pairedPlayers.bunny or not pairedPlayers.human then return end
	if player ~= pairedPlayers.bunny and player ~= pairedPlayers.human then return end

	if passedGate[player] then return end
	passedGate[player] = true
	debugPrint(player.Name, "passed through gate")

	if passedGate[pairedPlayers.bunny] and passedGate[pairedPlayers.human] then
		debugPrint("Both players through gate, closing")
		task.defer(function()
			task.wait(1)
			closeGate()
			if pairedPlayers.human then
				pairedPlayers.human:SetAttribute("CarryEnabled", true)
			end
			debugPrint("Carry system enabled")
		end)
	end
end

local function createGateTrigger()
	local gateFolder = workspace:FindFirstChild("ObbyGates")
	if not gateFolder then
		gateFolder = Instance.new("Folder")
		gateFolder.Name = "ObbyGates"
		gateFolder.Parent = workspace
	end

	local trigger = Instance.new("Part")
	trigger.Name = "GateTrigger"
	trigger.Size = Vector3.new(6, 14, 12)
	trigger.Position = Vector3.new(-54, 31, 211)
	trigger.Anchored = true
	trigger.CanCollide = false
	trigger.Transparency = 1
	trigger.Parent = gateFolder

	trigger.Touched:Connect(onGateTriggerTouched)
	_gateTrigger = trigger
	debugPrint("Gate trigger created at", tostring(trigger.Position))
end

local function releasePlayer(booth: BoothState)
	if not booth.player then return end
	-- Restore movement before releasing
	local humanoid = booth.player.Character and booth.player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 16
		humanoid.JumpHeight = 7.2
		humanoid.JumpPower = 50
	end
	local rootPart = getRootPart(booth.player)
	if rootPart then
		rootPart.CFrame = booth.exitCFrame
		rootPart.Anchored = false
	end
	playerMachine[booth.player] = nil
	booth.player = nil
	booth.inside = false
	hideDoor(booth.door)
end

local function getMachineCount(machine: MachineState): number
	local count = 0
	if machine.bunny.player then count += 1 end
	if machine.human.player then count += 1 end
	return count
end

local function fireMachineUI(player: Player, action: string, count: number?, countdown: number?)
	if not machineRemotes then return end
	local remote = machineRemotes:FindFirstChild("MachineUI") :: RemoteEvent?
	if not remote then return end
	remote:FireClient(player, action, count or 0, countdown or 0)
end

local function updateMachineUIForAll(machine: MachineState, countdown: number?)
	local count = getMachineCount(machine)
	if machine.bunny.player then
		fireMachineUI(machine.bunny.player, "update", count, countdown)
	end
	if machine.human.player then
		fireMachineUI(machine.human.player, "update", count, countdown)
	end
end

local function clearBooth(machine: MachineState, role: string)
	local booth = if role == "Bunny" then machine.bunny else machine.human
	if not booth.player then return end
	local leavingPlayer = booth.player
	-- Restore movement before releasing
	local humanoid = leavingPlayer.Character and leavingPlayer.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.MaxSlopeAngle = 10
		humanoid.WalkSpeed = 16
		humanoid.JumpHeight = 7.2
		humanoid.JumpPower = 50
	end
	local rootPart = getRootPart(booth.player)
	if rootPart then
		rootPart.CFrame = booth.exitCFrame
		rootPart.Anchored = false
	end
	playerMachine[booth.player] = nil
	booth.player = nil
	booth.inside = false
	hideDoor(booth.door)
	machine.awaitingVotes = false
	machine.countdownActive = false

	-- Clean up map votes and hide map selection UI
	machineMapVotes[machine.machineId] = nil
	if mapSelectionRemote then
		mapSelectionRemote:FireClient(leavingPlayer, "hideMapSelect")
		-- Also hide for the remaining player if present
		local otherBooth = if role == "Bunny" then machine.human else machine.bunny
		if otherBooth.player then
			mapSelectionRemote:FireClient(otherBooth.player, "hideMapSelect")
		end
	end

	-- Set leave cooldown so Touched doesn't re-enter them immediately
	boothLeaveCooldown[leavingPlayer] = os.clock()

	-- Notify the leaving player to hide UI
	fireMachineUI(leavingPlayer, "hide", 0, 0)
	-- Update remaining player's UI
	updateMachineUIForAll(machine, 0)
end

local function startMapSelection(machineId: string)
	local machine = machines[machineId]
	if not machine or machine.awaitingVotes or machine.countdownActive or machine.paired then return end
	if not machine.bunny.player or not machine.human.player then return end

	machine.awaitingVotes = true
	debugPrint("Map selection started for", machineId)

	-- Initialize map votes (only human votes)
	machineMapVotes[machineId] = { bunny = nil, human = nil }

	-- Only show map selection to the human player with completion data
	local humanPlayer = machine.human.player :: Player
	if mapSelectionRemote then
		local completedGrass = humanPlayer:GetAttribute("CompletedGrass") == true
		local completedDesert = humanPlayer:GetAttribute("CompletedDesert") == true
		mapSelectionRemote:FireClient(humanPlayer, "showMapSelect", completedGrass, completedDesert)
	end
	fireMachineUI(machine.bunny.player :: Player, "hide", 0, 0)
	fireMachineUI(humanPlayer, "hide", 0, 0)
end

local function startCountdown(machineId: string)
	local machine = machines[machineId]
	if not machine or machine.countdownActive or machine.paired then return end
	if not machine.bunny.player or not machine.human.player then return end

	machine.awaitingVotes = false
	machine.countdownActive = true
	debugPrint("Countdown started for", machineId)

	-- Hide map selection UI now that both have voted
	if mapSelectionRemote then
		mapSelectionRemote:FireClient(machine.bunny.player :: Player, "hideMapSelect")
		mapSelectionRemote:FireClient(machine.human.player :: Player, "hideMapSelect")
	end

	-- Notify both players: 2/2, countdown starting
	updateMachineUIForAll(machine, Constants.PAIR_COUNTDOWN)

	task.defer(function()
		for i = Constants.PAIR_COUNTDOWN, 1, -1 do
			if not machine.countdownActive then
				debugPrint("Countdown cancelled for", machineId)
				return
			end
			if not machine.bunny.player or not machine.human.player then
				machine.countdownActive = false
				return
			end
			-- Fire countdown updates to both players
			updateMachineUIForAll(machine, i)
			debugPrint(machineId, "countdown:", i)
			task.wait(1)
		end

		if not machine.bunny.player or not machine.human.player then
			machine.countdownActive = false
			return
		end

		machine.paired = true
		machine.countdownActive = false

		local bunnyPlayer = machine.bunny.player
		local humanPlayer = machine.human.player

		-- Hide machine UI for both players before releasing
		fireMachineUI(bunnyPlayer, "hide", 0, 0)
		fireMachineUI(humanPlayer, "hide", 0, 0)

		pairedPlayers.bunny = bunnyPlayer
		pairedPlayers.human = humanPlayer
		passedGate = {}

		bunnyPlayer:SetAttribute("PairRole", "Bunny")
		humanPlayer:SetAttribute("PairRole", "Human")
		humanPlayer:SetAttribute("CarryEnabled", true)

		releasePlayer(machine.bunny)
		releasePlayer(machine.human)

		-- Shrink the bunny player after pairing and apply bunny model
		scaleCharacter(bunnyPlayer, BUNNY_SCALE)
		assignBunnyCollisionGroup(bunnyPlayer)
		applyBunnyModel(bunnyPlayer)

		warn("=== PAIR COMPLETE ===")
		warn(tostring(bunnyPlayer) .. " is the BUNNY")
		warn(tostring(humanPlayer) .. " is the HUMAN")
		warn("Machine: " .. machineId)
		warn("====================")

		setupLinkedHealth(bunnyPlayer, humanPlayer)

		-- Resolve map choice (human's selection)
		local votes = machineMapVotes[machineId] or {}
		local chosenMap = votes.human or "Grass"

		-- Hide map selection UI
		if mapSelectionRemote then
			mapSelectionRemote:FireClient(bunnyPlayer, "hideMapSelect")
			mapSelectionRemote:FireClient(humanPlayer, "hideMapSelect")
		end
		machineMapVotes[machineId] = nil

		warn("Chosen map: " .. chosenMap)

		-- Track the active map (maps are always visible)
		if chosenMap == "Desert" or chosenMap == "Snow" then
			activeMapName = chosenMap
		end

		if chosenMap == "Desert" then
			local desertMap = workspace:FindFirstChild("DesertMap")
			local desertSpawn = desertMap and desertMap:FindFirstChild("SpawnLocation")
			if desertSpawn then
				local spawnPos = (desertSpawn :: BasePart).Position + Vector3.new(0, 3, 0)
				local bunnyRoot = getRootPart(bunnyPlayer)
				local humanRoot = getRootPart(humanPlayer)
				if bunnyRoot then
					bunnyRoot.CFrame = CFrame.new(spawnPos + Vector3.new(-3, 0, 0))
				end
				if humanRoot then
					humanRoot.CFrame = CFrame.new(spawnPos + Vector3.new(3, 0, 0))
				end
				debugPrint("Teleported pair to Desert map")
			else
				warn("[PairSystem] Desert map spawn not found, defaulting to Grass")
				openGate()
			end
		elseif chosenMap == "Snow" then
			local snowMap = workspace:FindFirstChild("SnowMap")
			local snowSpawn = snowMap and snowMap:FindFirstChild("SpawnLocation") :: SpawnLocation?
			if snowSpawn then
				-- Enable the SpawnLocation and assign it as the respawn point
				snowSpawn.Enabled = true
				bunnyPlayer.RespawnLocation = snowSpawn
				humanPlayer.RespawnLocation = snowSpawn

				local spawnPos = (snowSpawn :: BasePart).Position + Vector3.new(0, 3, 0)
				local bunnyRoot = getRootPart(bunnyPlayer)
				local humanRoot = getRootPart(humanPlayer)
				if bunnyRoot then
					bunnyRoot.CFrame = CFrame.new(spawnPos + Vector3.new(-3, 0, 0))
				end
				if humanRoot then
					humanRoot.CFrame = CFrame.new(spawnPos + Vector3.new(3, 0, 0))
				end
				debugPrint("Teleported pair to Snow map, SpawnLocation enabled")
			else
				warn("[PairSystem] Snow map not found, defaulting to Grass")
				openGate()
			end
		else
			-- Grass (default) - just open the gate
			-- CFrame is the default spot for grass map --
			bunnyPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-48.66, 30.702, 213.16)
			humanPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(-48.66, 30.702, 213.16)
			humanPlayer:SetAttribute("InPair", true)
			pickupBunny(humanPlayer)
		end
		bunnyPlayer:SetAttribute("InPair", true)
		humanPlayer:SetAttribute("InPair", true)
	end)
end

local function calculateBoothCFrames(pad: BasePart): (CFrame, CFrame, CFrame)
	local look = pad.CFrame.LookVector
	local padPos = pad.Position

	local interiorPos = padPos - look * INTERIOR_OFFSET + Vector3.new(0, ROOT_Y_OFFSET, 0)
	local exitPos = padPos + Vector3.new(0, ROOT_Y_OFFSET, 0)
	local doorPos = padPos - look * DOOR_OFFSET + Vector3.new(0, 3.8, 0)

	local interiorCF = CFrame.new(interiorPos, interiorPos + look)
	local exitCF = CFrame.new(exitPos, exitPos + look)
	local doorCF = CFrame.new(doorPos, doorPos + look)

	return interiorCF, exitCF, doorCF
end

local function handlePadTouch(machine: MachineState, booth: BoothState, role: string, player: Player)
	if machine.paired then return end
	if booth.player and booth.player ~= player then return end
	if playerMachine[player] then return end
	if booth.inside then return end
	if player == pairedPlayers.bunny or player == pairedPlayers.human then return end
	if boothLeaveCooldown[player] and os.clock() - boothLeaveCooldown[player] < 1.5 then return end
	boothLeaveCooldown[player] = nil

	booth.player = player
	booth.inside = true
	playerMachine[player] = machine.machineId

	debugPrint(player.Name, "entering", role, "booth of", machine.machineId)

	local rootPart = getRootPart(player)
	if rootPart then
		rootPart.CFrame = booth.interiorCFrame
		rootPart.Anchored = true
	end
	showDoor(booth.door)

	-- Freeze the player in place (stop movement/jumping)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpHeight = 0
		humanoid.JumpPower = 0
	end

	-- Show machine UI to entering player and update others
	local count = getMachineCount(machine)
	fireMachineUI(player, "show", count, 0)
	-- Update other player's count if they're already in the machine
	local otherBooth = if role == "Bunny" then machine.human else machine.bunny
	if otherBooth.player and otherBooth.player ~= player then
		fireMachineUI(otherBooth.player, "update", count, 0)
	end

	if machine.bunny.player and machine.human.player then
		startMapSelection(machine.machineId)
	end
end

local function initMachine(tpModel: Model)
	local machineId = tpModel.Name
	local bunnyPad = tpModel:FindFirstChild("BunnyPad")
	local humanPad = tpModel:FindFirstChild("HumanPad")

	if not bunnyPad or not humanPad then
		warn("[PairSystem] Machine", machineId, "missing pads")
		return
	end

	local bInterior, bExit, bDoorCF = calculateBoothCFrames(bunnyPad)
	local hInterior, hExit, hDoorCF = calculateBoothCFrames(humanPad)

	local machine: MachineState = {
		machineId = machineId,
		bunny = {
			pad = bunnyPad,
			door = createDoor(bDoorCF),
			interiorCFrame = bInterior,
			exitCFrame = bExit,
			player = nil,
			inside = false,
		},
		human = {
			pad = humanPad,
			door = createDoor(hDoorCF),
			interiorCFrame = hInterior,
			exitCFrame = hExit,
			player = nil,
			inside = false,
		},
		awaitingVotes = false,
		countdownActive = false,
		paired = false,
	}
	machines[machineId] = machine

	local debounce: { [Player]: number } = {}

	bunnyPad.Touched:Connect(function(hit: BasePart)
		local player = getPlayerFromPart(hit)
		if not player then return end
		local now = os.clock()
		if debounce[player] and now - debounce[player] < Constants.PAD_DEBOUNCE then return end
		debounce[player] = now
		handlePadTouch(machine, machine.bunny, "Bunny", player)
	end)

	humanPad.Touched:Connect(function(hit: BasePart)
		local player = getPlayerFromPart(hit)
		if not player then return end
		local now = os.clock()
		if debounce[player] and now - debounce[player] < Constants.PAD_DEBOUNCE then return end
		debounce[player] = now
		handlePadTouch(machine, machine.human, "Human", player)
	end)

	debugPrint("Initialized machine", machineId)
end

local function onPlayerRemoving(player: Player)
	boothLeaveCooldown[player] = nil
	local machineId = playerMachine[player]
	if not machineId then return end
	local machine = machines[machineId]
	if not machine then return end

	if machine.bunny.player == player then
		clearBooth(machine, "Bunny")
	end
	if machine.human.player == player then
		clearBooth(machine, "Human")
	end
end

local function onCharacterRemoving(player: Player)
	local machineId = playerMachine[player]
	if not machineId then return end
	local machine = machines[machineId]
	if not machine then return end

	if machine.bunny.player == player then
		clearBooth(machine, "Bunny")
	end
	if machine.human.player == player then
		clearBooth(machine, "Human")
	end
end

local function handleButtonPress(player: Player, buttonName: string)
	-- Input validation
	if typeof(buttonName) ~= "string" then return end
	if #buttonName > 50 then return end

	-- Rate limit: 0.3s cooldown per button per player
	local now = os.clock()
	if not buttonCooldowns[player] then
		buttonCooldowns[player] = {}
	end
	local lastPress = buttonCooldowns[player][buttonName] or 0
	if now - lastPress < 0.3 then return end
	buttonCooldowns[player][buttonName] = now

	if buttonName == "RedButton" then
		if player ~= pairedPlayers.bunny then return end
		for _, setup in buttonGates do
			if setup.redPressed then return end
			setup.redPressed = true
			debugPrint("Red button pressed by", player.Name)
			updateButtonGate(setup)
		end
	elseif buttonName == "BlueButton" then
		if player ~= pairedPlayers.human then return end
		for _, setup in buttonGates do
			if setup.bluePressed then return end
			setup.bluePressed = true
			debugPrint("Blue button pressed by", player.Name)
			updateButtonGate(setup)
		end
	elseif buttonName == "BridgeButton" then
		if bridgeActivated then return end
		if player ~= pairedPlayers.bunny then return end
		showBridge()
		debugPrint(player.Name, "pressed BridgeButton - bridge activated!")
	elseif buttonName == "SeesawButton1" then
		if seesawState.locked then return end
		if player ~= pairedPlayers.human then return end
		if seesawState.button1Pressed then return end
		seesawState.button1Pressed = true
		debugPrint("SeesawButton1 pressed by human")
		if seesawState.button1Pressed and seesawState.button2Pressed then
			lockSeesawAsRamp()
		end
	elseif buttonName == "SeesawButton2" then
		if seesawState.locked then return end
		if player ~= pairedPlayers.bunny then return end
		if seesawState.button2Pressed then return end
		seesawState.button2Pressed = true
		debugPrint("SeesawButton2 pressed by bunny")
		if seesawState.button1Pressed and seesawState.button2Pressed then
			lockSeesawAsRamp()
		end
	elseif buttonName == "ButtonForPlat1" then
		if invisPlatformsState.activated then return end
		if player ~= pairedPlayers.bunny then return end
		if invisPlatformsState.button1Pressed then return end
		invisPlatformsState.button1Pressed = true
		debugPrint("ButtonForPlat1 pressed by bunny")
		if invisPlatformsState.button1Pressed and invisPlatformsState.button2Pressed then
			showInvisPlatforms()
		end
	elseif buttonName == "ButtonForPlat2" then
		if invisPlatformsState.activated then return end
		if player ~= pairedPlayers.human then return end
		if invisPlatformsState.button2Pressed then return end
		invisPlatformsState.button2Pressed = true
		debugPrint("ButtonForPlat2 pressed by human")
		if invisPlatformsState.button1Pressed and invisPlatformsState.button2Pressed then
			showInvisPlatforms()
		end
	elseif buttonName == "ConveyorButton" then
		if conveyorState.jumpRevealed then return end
		if player ~= pairedPlayers.bunny then return end
		showConveyorJump()
		debugPrint(player.Name, "pressed ConveyorButton - ConveyorJump revealed!")
	elseif buttonName == "SwitchButton1" then
		if switchButtonsState.swapped then return end
		if switchButtonsState.button1Player then return end
		switchButtonsState.button1Player = player
		debugPrint("SwitchButton1 pressed by", player.Name)
		trySwapPlayers()
	elseif buttonName == "SwitchButton2" then
		if switchButtonsState.swapped then return end
		if switchButtonsState.button2Player then return end
		switchButtonsState.button2Player = player
		debugPrint("SwitchButton2 pressed by", player.Name)
		trySwapPlayers()
	end
end

local function initTeleporter11()
	-- Find Teleporter11 (under Decor)
	local tp11: BasePart? = nil
	for _, desc in workspace:GetDescendants() do
		if desc:IsA("BasePart") and desc.Name == "Teleporter11" then
			tp11 = desc
			break
		end
	end

	local spawnLoc = workspace:FindFirstChildOfClass("SpawnLocation")
	if not tp11 or not spawnLoc then
		warn("[PairSystem] Teleporter11 or SpawnLocation not found")
		return
	end

	local tp11PlayersInside: { [Player]: boolean } = {}
	local tp11Billboard: BillboardGui? = nil
	local tp11Processing = false

	local function getTP11Count(): number
		local count = 0
		for _ in tp11PlayersInside do
			count += 1
		end
		return count
	end

	local function destroyTP11Billboard()
		if tp11Billboard then
			tp11Billboard:Destroy()
			tp11Billboard = nil
		end
	end

	local function updateTP11Billboard()
		local count = getTP11Count()
		if count == 0 then
			destroyTP11Billboard()
			return
		end

		if not tp11Billboard then
			-- Find the parent model and position billboard above the model's top
			local tp11Model = tp11.Parent
			local studsAbove = Vector3.new(0, 5, 0)
			if tp11Model and tp11Model:IsA("Model") then
				local modelCF, modelSize = tp11Model:GetBoundingBox()
				local modelTopY = modelCF.Position.Y + modelSize.Y / 2
				local offsetY = modelTopY - tp11.Position.Y + 2
				studsAbove = Vector3.new(0, offsetY, 0)
			end

			local billboard = Instance.new("BillboardGui")
			billboard.Name = "TP11StatusGui"
			billboard.Size = UDim2.new(4, 0, 2, 0)
			billboard.StudsOffset = studsAbove
			billboard.AlwaysOnTop = true
			billboard.Adornee = tp11
			billboard.Parent = tp11

			local label = Instance.new("TextLabel")
			label.Name = "StatusLabel"
			label.Size = UDim2.new(1, 0, 1, 0)
			label.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			label.BackgroundTransparency = 0.4
			label.TextColor3 = Color3.fromRGB(255, 255, 255)
			label.TextScaled = true
			label.Font = Enum.Font.GothamBold
			label.Text = count .. "/2"
			label.Parent = billboard

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 8)
			corner.Parent = label

			tp11Billboard = billboard
		else
			local label = tp11Billboard:FindFirstChild("StatusLabel") :: TextLabel?
			if label then
				label.Text = count .. "/2"
			end
		end
	end

	janitor:Add(tp11.Touched:Connect(function(hit: BasePart)
		if tp11Processing then return end
		local player = getPlayerFromPart(hit)
		if not player then return end
		if not pairedPlayers.bunny or not pairedPlayers.human then return end
		if player ~= pairedPlayers.bunny and player ~= pairedPlayers.human then return end
		if tp11PlayersInside[player] then return end

		tp11PlayersInside[player] = true
		local count = getTP11Count()
		debugPrint(player.Name, "entered Teleporter11 (" .. count .. "/2)")
		updateTP11Billboard()

		if count >= 2 then
			tp11Processing = true
			destroyTP11Billboard()

			local bunny = pairedPlayers.bunny
			local human = pairedPlayers.human

			-- Teleport both to spawn
			local spawnPos = spawnLoc.Position + Vector3.new(0, 3, 0)
			local bunnyRoot = getRootPart(bunny)
			local humanRoot = getRootPart(human)
			if bunnyRoot then
				bunnyRoot.CFrame = CFrame.new(spawnPos + Vector3.new(-3, 0, 0))
			end
			if humanRoot then
				humanRoot.CFrame = CFrame.new(spawnPos + Vector3.new(3, 0, 0))
			end

			-- Mark Grass as completed for both players
			if bunny then bunny:SetAttribute("CompletedGrass", true) end
			if human then human:SetAttribute("CompletedGrass", true) end

			-- Destroy partnership
			fullReset()
			debugPrint("Both players teleported to spawn, partnership destroyed")

			tp11PlayersInside = {}
			task.delay(3, function()
				tp11Processing = false
			end)
		end
	end))

	-- Clean up if a player leaves while waiting inside the teleporter
	janitor:Add(Players.PlayerRemoving:Connect(function(player: Player)
		if tp11PlayersInside[player] then
			tp11PlayersInside[player] = nil
			updateTP11Billboard()
			debugPrint(player.Name, "left while in Teleporter11, count now", getTP11Count())
		end
	end))

	debugPrint("Teleporter11 system initialized")
end

local function initJumpPart()
	local map = workspace:FindFirstChild("Other/Map")
	if not map then return end

	local jumpPart = map:FindFirstChild("JumpPart") :: BasePart?
	if not jumpPart then
		warn("[PairSystem] JumpPart not found")
		return
	end

	local JUMP_VELOCITY = 100
	local jumpDebounce = false

	local jpPos = jumpPart.Position
	local halfX = jumpPart.Size.X / 2 + 0.5
	local halfZ = jumpPart.Size.Z / 2 + 0.5
	local jpTopY = jpPos.Y + jumpPart.Size.Y / 2

	janitor:Add(RunService.Heartbeat:Connect(function()
		if jumpDebounce then return end

		for _, player in Players:GetPlayers() do
			local rootPart = getRootPart(player)
			if not rootPart then continue end

			local pos = rootPart.Position
			if math.abs(pos.X - jpPos.X) <= halfX
				and math.abs(pos.Z - jpPos.Z) <= halfZ
				and pos.Y >= jpTopY - 1
				and pos.Y <= jpTopY + 5
			then
				jumpDebounce = true
				local vel = rootPart.AssemblyLinearVelocity
				rootPart.AssemblyLinearVelocity = Vector3.new(vel.X, JUMP_VELOCITY, vel.Z)

				task.delay(0.8, function()
					jumpDebounce = false
				end)
				break
			end
		end
	end))

	debugPrint("JumpPart system initialized")
end

local function initColorPlatforms()
	local map = workspace:FindFirstChild("Other/Map")
	local decor = workspace:FindFirstChild("Decor")
	if not map or not decor then return end

	local COLOR_NAMES = { "Blue", "Red", "Yellow", "Green" }
	local DEACTIVATE_DELAY = 3

	-- Find buttons under Decor and platforms under Other/Map
	local pairs_: { { button: BasePart, platform: BasePart, originalTransparency: number } } = {}
	for _, color in COLOR_NAMES do
		local buttonName = color .. "Button"
		local platformName = color .. "Platform"

		local button: BasePart? = nil
		for _, desc in decor:GetDescendants() do
			if desc:IsA("BasePart") and desc.Name == buttonName then
				button = desc
				break
			end
		end

		local platform = map:FindFirstChild(platformName) :: BasePart?

		if button and platform then
			table.insert(pairs_, {
				button = button,
				platform = platform,
				originalTransparency = platform.Transparency,
			})
			-- Set platform to default off state
			platform.CanCollide = false
			debugPrint("Color platform pair:", buttonName, "->", platformName)
		else
			warn("[PairSystem] Missing", buttonName, "or", platformName)
		end
	end

	if #pairs_ == 0 then return end

	local deactivateTimers: { [BasePart]: thread? } = {}

	local function activatePlatform(entry: { button: BasePart, platform: BasePart, originalTransparency: number })
		-- Cancel pending deactivation
		if deactivateTimers[entry.platform] then
			task.cancel(deactivateTimers[entry.platform] :: thread)
			deactivateTimers[entry.platform] = nil
		end
		entry.platform.Transparency = 0
		entry.platform.CanCollide = true
	end

	local function scheduleDeactivate(entry: { button: BasePart, platform: BasePart, originalTransparency: number })
		-- Cancel any existing timer
		if deactivateTimers[entry.platform] then
			task.cancel(deactivateTimers[entry.platform] :: thread)
		end
		deactivateTimers[entry.platform] = task.delay(DEACTIVATE_DELAY, function()
			entry.platform.Transparency = entry.originalTransparency
			entry.platform.CanCollide = false
			deactivateTimers[entry.platform] = nil
		end)
	end

	local wasOnButton: { [BasePart]: boolean } = {}

	janitor:Add(RunService.Heartbeat:Connect(function()
		local bunny = pairedPlayers.bunny
		if not bunny then return end

		local rootPart = getRootPart(bunny)
		if not rootPart then return end
		local pos = rootPart.Position

		for _, entry in pairs_ do
			local bPos = entry.button.Position
			local halfX = entry.button.Size.X / 2 + 1
			local halfZ = entry.button.Size.Z / 2 + 1
			local onButton = math.abs(pos.X - bPos.X) <= halfX
				and math.abs(pos.Z - bPos.Z) <= halfZ
				and pos.Y >= bPos.Y - 1
				and pos.Y <= bPos.Y + 8

			if onButton and not wasOnButton[entry.button] then
				activatePlatform(entry)
			elseif not onButton and wasOnButton[entry.button] then
				scheduleDeactivate(entry)
			end
			wasOnButton[entry.button] = onButton
		end
	end))

	debugPrint("Color platform system initialized with", #pairs_, "pairs")
end

local function initOpenableGate()
	local openableModel = workspace:FindFirstChild("Openable")
	if not openableModel then
		warn("[PairSystem] Openable model not found")
		return
	end

	-- Find HumanButton and BunnyButton via descendants (both under Decor.Model instances)
	local humanButton: BasePart? = nil
	local bunnyButton: BasePart? = nil
	for _, desc in workspace:GetDescendants() do
		if desc:IsA("BasePart") then
			if desc.Name == "HumanButton" then
				humanButton = desc
			elseif desc.Name == "BunnyButton" then
				bunnyButton = desc
			end
		end
	end

	if not humanButton or not bunnyButton then
		warn("[PairSystem] HumanButton or BunnyButton not found")
		return
	end

	local gateOpen = false
	local gateX = openableModel:GetPivot().Position.X

	local function setGateOpen(open: boolean)
		if gateOpen == open then return end
		gateOpen = open
		for _, part in openableModel:GetChildren() do
			if part:IsA("BasePart") then
				part.Transparency = if open then 1 else 0
				part.CanCollide = not open
			end
		end
		debugPrint("Openable gate", if open then "opened" else "closed")
	end

	local function isPlayerOnButton(player: Player?, button: BasePart): boolean
		if not player then return false end
		local rootPart = getRootPart(player)
		if not rootPart then return false end
		local pos = rootPart.Position
		local bPos = button.Position
		local halfX = button.Size.X / 2 + 1
		local halfZ = button.Size.Z / 2 + 1
		return math.abs(pos.X - bPos.X) <= halfX
			and math.abs(pos.Z - bPos.Z) <= halfZ
			and pos.Y >= bPos.Y - 1
			and pos.Y <= bPos.Y + 8
	end

	janitor:Add(RunService.Heartbeat:Connect(function()
		if not pairedPlayers.bunny or not pairedPlayers.human then return end

		if not gateOpen then
			-- Check if both players are on their respective buttons
			local humanOn = isPlayerOnButton(pairedPlayers.human, humanButton)
			local bunnyOn = isPlayerOnButton(pairedPlayers.bunny, bunnyButton)
			if humanOn and bunnyOn then
				setGateOpen(true)
			end
		else
			-- Check if both players have passed the gate
			local bunnyRoot = getRootPart(pairedPlayers.bunny)
			local humanRoot = getRootPart(pairedPlayers.human)
			if bunnyRoot and humanRoot then
				if bunnyRoot.Position.X > gateX + 3 and humanRoot.Position.X > gateX + 3 then
					setGateOpen(false)
				end
			end
		end
	end))

	debugPrint("Openable gate system initialized")
end

local function handleLeaveMachine(player: Player)
	local machineId = playerMachine[player]
	if not machineId then return end
	local machine = machines[machineId]
	if not machine then return end

	if machine.bunny.player == player then
		clearBooth(machine, "Bunny")
		debugPrint(player.Name, "left Bunny booth via leave button")
	elseif machine.human.player == player then
		clearBooth(machine, "Human")
		debugPrint(player.Name, "left Human booth via leave button")
	end
end

local function initMachineRemotes()
	local folder = Instance.new("Folder")
	folder.Name = "MachineRemotes"
	folder.Parent = ReplicatedStorage

	local machineUIRemote = Instance.new("RemoteEvent")
	machineUIRemote.Name = "MachineUI"
	machineUIRemote.Parent = folder

	local leaveRemote = Instance.new("RemoteEvent")
	leaveRemote.Name = "LeaveMachine"
	leaveRemote.Parent = folder

	leaveRemote.OnServerEvent:Connect(handleLeaveMachine)

	local mapSelectRemote = Instance.new("RemoteEvent")
	mapSelectRemote.Name = "MapSelection"
	mapSelectRemote.Parent = folder

	mapSelectRemote.OnServerEvent:Connect(function(player: Player, mapChoice: any)
		if typeof(mapChoice) ~= "string" then return end
		local VALID_MAPS = { Grass = true, Desert = true, Snow = true }
		if not VALID_MAPS[mapChoice :: string] then return end

		local machineId = playerMachine[player]
		if not machineId then return end
		local machine = machines[machineId]
		if not machine or not (machine.awaitingVotes or machine.countdownActive) then return end

		-- Only the human player can select the map
		if machine.human.player ~= player then return end

		-- Validate map is unlocked for this player
		local mapName = mapChoice :: string
		if mapName == "Desert" and player:GetAttribute("CompletedGrass") ~= true then return end
		if mapName == "Snow" and player:GetAttribute("CompletedDesert") ~= true then return end

		if not machineMapVotes[machineId] then
			machineMapVotes[machineId] = {}
		end

		machineMapVotes[machineId].human = mapName

		debugPrint(player.Name, "selected map:", mapName, "in", machineId)

		-- Start countdown immediately (only human votes)
		if machine.awaitingVotes then
			startCountdown(machineId)
		end
	end)

	mapSelectionRemote = mapSelectRemote
	machineRemotes = folder
	debugPrint("Machine remotes initialized")
end

local function initObstacleRemotes()
	local folder = Instance.new("Folder")
	folder.Name = "ObstacleRemotes"
	folder.Parent = ReplicatedStorage

	local buttonPressRemote = Instance.new("RemoteEvent")
	buttonPressRemote.Name = "ButtonPress"
	buttonPressRemote.Parent = folder

	buttonPressRemote.OnServerEvent:Connect(handleButtonPress)

	-- BackToLobby: player clicked "Back to Lobby" on YouDied UI
	local backToLobbyRemote = Instance.new("RemoteEvent")
	backToLobbyRemote.Name = "BackToLobby"
	backToLobbyRemote.Parent = folder

	backToLobbyRemote.OnServerEvent:Connect(function(player: Player)
		-- Only process if this player is part of the current pair
		if player ~= pairedPlayers.bunny and player ~= pairedPlayers.human then return end

		debugPrint(player.Name, "chose Back to Lobby")

		local bunny = pairedPlayers.bunny
		local human = pairedPlayers.human
		
		bunny:SetAttribute("InPair", false)
		human:SetAttribute("InPair", false)

		fullReset()

		-- Teleport both players to main lobby spawn
		bunny:LoadCharacterAsync()
		human:LoadCharacterAsync()
		task.wait(0.5)
		local mainSpawn = workspace:FindFirstChild("SpawnLocation")
		if mainSpawn then
			local spawnCF = mainSpawn.CFrame + Vector3.new(0, 3, 0)
			if bunny and bunny.Character then
				local root = bunny.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then root.CFrame = spawnCF end
			end
			if human and human.Character then
				local root = human.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then root.CFrame = spawnCF end
			end
		end
	end)

	-- UseRevive: player clicked "Revive" on YouDied UI to respawn at death location
	local useReviveRemote = Instance.new("RemoteEvent")
	useReviveRemote.Name = "UseRevive"
	useReviveRemote.Parent = folder

	useReviveRemote.OnServerEvent:Connect(function(player: Player, deathPosition: Vector3)
		-- Validate player is in the current pair
		if player ~= pairedPlayers.bunny and player ~= pairedPlayers.human then return end
		-- Validate deathPosition
		if typeof(deathPosition) ~= "Vector3" then return end
		if deathPosition.Magnitude > 1e6 then return end -- sanity check

		debugPrint(player.Name, "respawning at death position")

		-- Wait for character to respawn (auto-respawn is 3s)
		local character = player.Character
		if not character or not character:FindFirstChild("HumanoidRootPart") then
			player.CharacterAdded:Wait()
			character = player.Character
			if character then
				character:WaitForChild("HumanoidRootPart", 5)
			end
		end

		-- Teleport to death position + slight Y offset
		if character then
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				root.CFrame = CFrame.new(deathPosition + Vector3.new(0, 3, 0))
			end
		end
	end)

	obstacleRemotes = folder
	debugPrint("Obstacle remotes initialized")
end

local VALID_MILESTONE_MAPS = { Grass = true, Snow = true, Desert = true }

local function initMilestones()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then return end
	local teleporting = remotes:FindFirstChild("Teleporting")
	if not teleporting then return end
	local teleportTeam = teleporting:FindFirstChild("TeleportTeam") :: RemoteEvent?
	if not teleportTeam then return end

	teleportTeam.OnServerEvent:Connect(function(player: Player, mapName: string)
		if typeof(mapName) ~= "string" then return end
		if not VALID_MILESTONE_MAPS[mapName] then return end
		if player ~= pairedPlayers.bunny and player ~= pairedPlayers.human then return end

		local bunny = pairedPlayers.bunny
		local human = pairedPlayers.human
		if not bunny or not human then return end

		-- Drop bunny if carrying
		dropBunnyInternal()

		-- Clear respawn locations
		bunny.RespawnLocation = nil
		human.RespawnLocation = nil

		-- Disable snow spawn by default
		local snowMap = workspace:FindFirstChild("SnowMap")
		local snowSpawn = snowMap and snowMap:FindFirstChild("SpawnLocation") :: SpawnLocation?
		if snowSpawn then snowSpawn.Enabled = false end

		if mapName == "Snow" then
			if snowSpawn then
				snowSpawn.Enabled = true
				bunny.RespawnLocation = snowSpawn
				human.RespawnLocation = snowSpawn
				local spawnPos = (snowSpawn :: BasePart).Position + Vector3.new(0, 3, 0)
				local bunnyRoot = getRootPart(bunny)
				local humanRoot = getRootPart(human)
				if bunnyRoot then bunnyRoot.CFrame = CFrame.new(spawnPos + Vector3.new(-3, 0, 0)) end
				if humanRoot then humanRoot.CFrame = CFrame.new(spawnPos + Vector3.new(3, 0, 0)) end
			end
			activeMapName = "Snow"
		elseif mapName == "Desert" then
			local desertMap = workspace:FindFirstChild("DesertMap")
			local desertSpawn = desertMap and desertMap:FindFirstChild("SpawnLocation")
			if desertSpawn then
				local spawnPos = (desertSpawn :: BasePart).Position + Vector3.new(0, 3, 0)
				local bunnyRoot = getRootPart(bunny)
				local humanRoot = getRootPart(human)
				if bunnyRoot then bunnyRoot.CFrame = CFrame.new(spawnPos + Vector3.new(-3, 0, 0)) end
				if humanRoot then humanRoot.CFrame = CFrame.new(spawnPos + Vector3.new(3, 0, 0)) end
			end
			activeMapName = "Desert"
		else
			-- Grass: teleport near the gate and open it
			local mainSpawn = workspace:FindFirstChild("SpawnLocation")
			if mainSpawn then
				local spawnPos = (mainSpawn :: BasePart).Position + Vector3.new(0, 3, 0)
				local bunnyRoot = getRootPart(bunny)
				local humanRoot = getRootPart(human)
				if bunnyRoot then bunnyRoot.CFrame = CFrame.new(spawnPos + Vector3.new(-3, 0, 0)) end
				if humanRoot then humanRoot.CFrame = CFrame.new(spawnPos + Vector3.new(3, 0, 0)) end
			end
			openGate()
			activeMapName = nil
		end

		debugPrint(player.Name, "milestone teleported pair to", mapName)
	end)

	debugPrint("Milestones initialized")
end

local function initSnowMap()
	local snowMap = workspace:FindFirstChild("SnowMap")
	if not snowMap then return end

	-- Disable the snow SpawnLocation so players don't auto-spawn there
	local snowSpawn = snowMap:FindFirstChild("SpawnLocation") :: SpawnLocation?
	if snowSpawn then
		snowSpawn.Enabled = false
		debugPrint("Snow SpawnLocation disabled")
	end

	-- Tag snow kill parts
	for _, killName in { "SnowKillPart1", "SnowKillPart2" } do
		local killPart = snowMap:FindFirstChild(killName)
		if killPart and killPart:IsA("BasePart") then
			CollectionService:AddTag(killPart, "KillPart")
			debugPrint(killName, "tagged as KillPart")
		end
	end
end

local function initHeightChanging()
	local snowMap = workspace:FindFirstChild("SnowMap")
	if not snowMap then return end

	local heightModel = snowMap:FindFirstChild("HeightChanging")
	if not heightModel then
		debugPrint("HeightChanging model not found")
		return
	end

	local partIndex = 0
	local totalParts = 0
	for _, desc in heightModel:GetDescendants() do
		if desc:IsA("BasePart") then
			totalParts += 1
		end
	end

	for _, desc in heightModel:GetDescendants() do
		if desc:IsA("BasePart") then
			CollectionService:AddTag(desc, "HeightOscillating")
			desc:SetAttribute("HeightAmplitude", 5)
			-- Spread phases evenly across full cycle so each part oscillates at a different time
			desc:SetAttribute("HeightPhaseOffset", (partIndex / totalParts) * 2 * math.pi)
			partIndex += 1
			debugPrint("Tagged", desc.Name, "as HeightOscillating, phase", partIndex)
		end
	end
end

local function initIcyPlats1()
	local snowMap = workspace:FindFirstChild("SnowMap")
	if not snowMap then return end

	local ICY_PROPERTIES = PhysicalProperties.new(
		0.7,  -- density
		0.05, -- friction
		0,    -- elasticity
		0.05, -- frictionWeight
		0     -- elasticityWeight
	)

	for _, platName in { "IcyPlats1", "IcyPlats2", "IcyPlats3", "IcyPlats4", "IcyPlats5" } do
		local icyPlats = snowMap:FindFirstChild(platName)
		if not icyPlats then continue end
		for _, desc in icyPlats:GetDescendants() do
			if desc:IsA("BasePart") then
				desc.CustomPhysicalProperties = ICY_PROPERTIES
				CollectionService:AddTag(desc, "IcyPart")
			end
		end
		debugPrint(platName, "initialized with low friction")
	end
end

local function initSnowButton1()
	local snowMap = workspace:FindFirstChild("SnowMap")
	if not snowMap then return end

	local bluePlats = snowMap:FindFirstChild("BluePlats1") :: Model?
	local button1 = snowMap:FindFirstChild("SnowButton1", true) :: BasePart?
	if not bluePlats or not button1 then
		warn("[PairSystem] BluePlats1 or SnowButton1 not found")
		return
	end

	local ICY_PROPERTIES = PhysicalProperties.new(
		0.7,  -- density
		0.02, -- friction
		0,    -- elasticity
		0.02, -- frictionWeight
		0     -- elasticityWeight
	)

	-- Start hidden: non-collidable and semi-transparent
	for _, desc in bluePlats:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Transparency = 0.5
			desc.CanCollide = false
		end
	end

	local activeTimer: thread? = nil

	janitor:Add(button1.Touched:Connect(function(hit: BasePart)
		local player = getPlayerFromPart(hit)
		if not player then return end

		if activeTimer then task.cancel(activeTimer) end

		for _, desc in bluePlats:GetDescendants() do
			if desc:IsA("BasePart") then
				desc.Transparency = 0
				desc.CanCollide = true
				desc.CustomPhysicalProperties = ICY_PROPERTIES
				CollectionService:AddTag(desc, "IcyPart")
			end
		end

		activeTimer = task.delay(3, function()
			for _, desc in bluePlats:GetDescendants() do
				if desc:IsA("BasePart") then
					desc.Transparency = 0.5
					desc.CanCollide = false
				end
			end
			activeTimer = nil
		end)
	end))

	debugPrint("SnowButton1 system initialized (3s timer)")
end

local function initSnowButtonPlats()
	local snowMap = workspace:FindFirstChild("SnowMap")
	if not snowMap then return end

	local DURATION = 3

	type ButtonPlatConfig = {
		buttonName: string,
		platName: string,
		requiredRole: string,
	}

	local configs: { ButtonPlatConfig } = {
		{ buttonName = "SnowButton3", platName = "SnowRedPlat1", requiredRole = "Bunny" },
		{ buttonName = "SnowButton2", platName = "SnowBluePlat1", requiredRole = "Human" },
	}

	for _, config in configs do
		local button = snowMap:FindFirstChild(config.buttonName, true) :: BasePart?
		local plat = snowMap:FindFirstChild(config.platName, true) :: BasePart?
		if not button or not plat then
			warn("[PairSystem]", config.buttonName, "or", config.platName, "not found")
			continue
		end

		-- Start hidden
		plat.Transparency = 0.5
		plat.CanCollide = false

		-- Find the digit MeshParts in the button's parent model for timer display
		local buttonModel = button.Parent :: Model
		local digitParts: { MeshPart } = {}
		for _, child in buttonModel:GetChildren() do
			if child:IsA("MeshPart") then
				table.insert(digitParts, child)
			end
		end

		-- Find the base Part (non-button, non-mesh part) in the model for SurfaceGui
		local basePart: BasePart? = nil
		for _, child in buttonModel:GetChildren() do
			if child:IsA("Part") and child ~= button then
				basePart = child
				break
			end
		end

		-- Create a BillboardGui on the base part for countdown display (always faces camera)
		local timerLabel: TextLabel? = nil
		if basePart then
			local billboardGui = Instance.new("BillboardGui")
			billboardGui.Name = "TimerGui"
			billboardGui.Size = UDim2.new(3, 0, 2, 0)
			billboardGui.StudsOffset = Vector3.new(0, 2, 0)
			billboardGui.AlwaysOnTop = true
			billboardGui.Parent = basePart

			timerLabel = Instance.new("TextLabel")
			timerLabel.Name = "TimerLabel"
			timerLabel.Size = UDim2.new(1, 0, 1, 0)
			timerLabel.BackgroundTransparency = 1
			timerLabel.TextColor3 = Color3.new(1, 1, 1)
			timerLabel.TextStrokeTransparency = 0
			timerLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
			timerLabel.TextScaled = true
			timerLabel.Font = Enum.Font.GothamBold
			timerLabel.Text = ""
			timerLabel.Visible = false
			timerLabel.Parent = billboardGui
		end

		local active = false

		janitor:Add(button.Touched:Connect(function(hit: BasePart)
			if active then return end
			local player = getPlayerFromPart(hit)
			if not player then return end

			local role = player:GetAttribute("PairRole")
			if role ~= config.requiredRole then return end

			active = true

			-- Show the platform
			plat.Transparency = 0
			plat.CanCollide = true

			-- Hide digit meshes, show countdown on surface
			for _, dp in digitParts do
				dp.Transparency = 1
			end
			if timerLabel then
				timerLabel.Visible = true
			end

			-- Countdown
			for remaining = DURATION, 1, -1 do
				if timerLabel then
					timerLabel.Text = tostring(remaining)
				end
				task.wait(1)
			end

			-- Hide platform again
			plat.Transparency = 0.5
			plat.CanCollide = false

			-- Restore digit meshes, hide countdown
			for _, dp in digitParts do
				dp.Transparency = 0
			end
			if timerLabel then
				timerLabel.Visible = false
				timerLabel.Text = ""
			end

			active = false
		end))

		debugPrint(config.buttonName, "+", config.platName, "system initialized (role:", config.requiredRole .. ")")
	end
end

local function initSnowRedPlats2()
	local snowMap = workspace:FindFirstChild("SnowMap")
	if not snowMap then return end

	local redPlats2 = snowMap:FindFirstChild("SnowRedPlats2") :: Model?
	if not redPlats2 then
		warn("[PairSystem] SnowRedPlats2 not found in SnowMap")
		return
	end

	-- Register BunnyOnlyPlatform collision group
	if not PhysicsService:IsCollisionGroupRegistered("BunnyOnlyPlatform") then
		PhysicsService:RegisterCollisionGroup("BunnyOnlyPlatform")
	end
	-- BunnyOnlyPlatform collides with BunnyBody but not Default
	PhysicsService:CollisionGroupSetCollidable("BunnyOnlyPlatform", "Default", false)
	PhysicsService:CollisionGroupSetCollidable("BunnyOnlyPlatform", "BunnyBody", true)

	for _, desc in redPlats2:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.CollisionGroup = "BunnyOnlyPlatform"
		end
	end

	debugPrint("SnowRedPlats2 set to BunnyOnlyPlatform collision group (" .. #redPlats2:GetChildren() .. " parts)")
end

local function initSnowButton4()
	local snowMap = workspace:FindFirstChild("SnowMap")
	if not snowMap then return end

	local button4 = snowMap:FindFirstChild("SnowButton4", true) :: BasePart?
	local greenPlat = snowMap:FindFirstChild("SnowGreenPlat1", true) :: BasePart?
	if not button4 or not greenPlat then
		warn("[PairSystem] SnowButton4 or SnowGreenPlat1 not found")
		return
	end

	-- Start hidden
	greenPlat.Transparency = 0.5
	greenPlat.CanCollide = false

	local activeTimer: thread? = nil

	janitor:Add(button4.Touched:Connect(function(hit: BasePart)
		local player = getPlayerFromPart(hit)
		if not player then return end
		if player:GetAttribute("PairRole") ~= "Bunny" then return end

		if activeTimer then task.cancel(activeTimer) end

		greenPlat.Transparency = 0
		greenPlat.CanCollide = true

		activeTimer = task.delay(3, function()
			greenPlat.Transparency = 0.5
			greenPlat.CanCollide = false
			activeTimer = nil
		end)
	end))

	debugPrint("SnowButton4 + SnowGreenPlat1 system initialized (3s timer)")
end

local function initSnowTeleport1()
	local snowMap = workspace:FindFirstChild("SnowMap")
	if not snowMap then return end

	local tp1 = snowMap:FindFirstChild("SnowTeleport1", true) :: BasePart?
	local tp2 = snowMap:FindFirstChild("SnowTeleport2", true) :: BasePart?
	if not tp1 or not tp2 then
		warn("[PairSystem] SnowTeleport1 or SnowTeleport2 not found")
		return
	end

	local tpDebounce: { [Player]: number } = {}

	janitor:Add(tp1.Touched:Connect(function(hit: BasePart)
		local player = getPlayerFromPart(hit)
		if not player then return end
		if player ~= pairedPlayers.bunny then return end

		local now = os.clock()
		if tpDebounce[player] and now - tpDebounce[player] < 2 then return end
		tpDebounce[player] = now

		local rootPart = getRootPart(player)
		if not rootPart then return end

		local destPos = tp2.Position - tp2.CFrame.LookVector * 3
		rootPart.CFrame = CFrame.new(destPos, destPos - tp2.CFrame.LookVector)
		debugPrint(player.Name, "teleported from SnowTeleport1 to SnowTeleport2")
	end))

	debugPrint("SnowTeleport1 system initialized")
end

local function initSnowSwitchPlats()
	local snowMap = workspace:FindFirstChild("SnowMap")
	if not snowMap then return end

	local switchPlats1 = snowMap:FindFirstChild("SnowSwitchPlats1") :: Model?
	local switchPlats2 = snowMap:FindFirstChild("SnowSwitchPlats2") :: Model?
	if not switchPlats1 or not switchPlats2 then
		warn("[PairSystem] SnowSwitchPlats1 or SnowSwitchPlats2 not found")
		return
	end

	local button5 = switchPlats1:FindFirstChild("SnowButton5") :: BasePart?
	if not button5 then
		warn("[PairSystem] SnowButton5 not found in SnowSwitchPlats1")
		return
	end

	-- Collect platform parts (exclude the button itself)
	local plats1Parts: { BasePart } = {}
	for _, desc in switchPlats1:GetDescendants() do
		if desc:IsA("BasePart") and desc ~= button5 then
			table.insert(plats1Parts, desc)
		end
	end

	local plats2Parts: { BasePart } = {}
	for _, desc in switchPlats2:GetDescendants() do
		if desc:IsA("BasePart") then
			table.insert(plats2Parts, desc)
		end
	end

	-- Default state: plats1 hidden, plats2 solid
	local function setDefaultState()
		for _, part in plats1Parts do
			part.Transparency = 0.5
			part.CanCollide = false
		end
		for _, part in plats2Parts do
			part.Transparency = 0
			part.CanCollide = true
		end
	end

	-- Swapped state: plats1 solid, plats2 hidden
	local function setSwappedState()
		for _, part in plats1Parts do
			part.Transparency = 0
			part.CanCollide = true
		end
		for _, part in plats2Parts do
			part.Transparency = 0.5
			part.CanCollide = false
		end
	end

	setDefaultState()

	local touching = false
	local touchCount = 0

	janitor:Add(button5.Touched:Connect(function(hit: BasePart)
		local player = getPlayerFromPart(hit)
		if not player then return end
		if player:GetAttribute("PairRole") ~= "Bunny" then return end

		touchCount += 1
		if not touching then
			touching = true
			setSwappedState()
			debugPrint("SnowButton5 pressed: platforms swapped")
		end
	end))

	janitor:Add(button5.TouchEnded:Connect(function(hit: BasePart)
		local player = getPlayerFromPart(hit)
		if not player then return end
		if player:GetAttribute("PairRole") ~= "Bunny" then return end

		touchCount = math.max(0, touchCount - 1)
		if touchCount == 0 then
			touching = false
			setDefaultState()
			debugPrint("SnowButton5 released: platforms restored")
		end
	end))

	debugPrint("SnowSwitchPlats system initialized")
end

local function initSnowTeleport3()
	local snowMap = workspace:FindFirstChild("SnowMap")
	if not snowMap then return end

	-- SnowTeleport3/4 are inside a Model child of SnowMap
	local tp3: BasePart? = nil
	local tp4: BasePart? = nil
	for _, descendant in snowMap:GetDescendants() do
		if descendant.Name == "SnowTeleport3" and descendant:IsA("BasePart") then
			tp3 = descendant
		elseif descendant.Name == "SnowTeleport4" and descendant:IsA("BasePart") then
			tp4 = descendant
		end
	end

	if not tp3 or not tp4 then
		warn("[PairSystem] SnowTeleport3 or SnowTeleport4 not found")
		return
	end

	local debounce: { [Player]: boolean } = {}

	janitor:Add(tp3.Touched:Connect(function(hit: BasePart)
		local player = getPlayerFromPart(hit)
		if not player then return end
		if player:GetAttribute("PairRole") ~= "Bunny" then return end
		if debounce[player] then return end

		debounce[player] = true

		local character = player.Character
		if character then
			local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if rootPart then
				-- Position 3 studs in front of tp4, facing away from it
				local destination = tp4.Position - tp4.CFrame.LookVector * 3
				rootPart.CFrame = CFrame.new(destination, destination - tp4.CFrame.LookVector)
			end
		end

		task.delay(2, function()
			debounce[player] = nil
		end)
	end))

	debugPrint("SnowTeleport3 system initialized")
end

local function initSnowTeleport5()
	local snowMap = workspace:FindFirstChild("SnowMap")
	if not snowMap then return end

	local tp5: BasePart? = nil
	local tp6: BasePart? = nil
	for _, descendant in snowMap:GetDescendants() do
		if descendant.Name == "SnowTeleport5" and descendant:IsA("BasePart") then
			tp5 = descendant
		elseif descendant.Name == "SnowTeleport6" and descendant:IsA("BasePart") then
			tp6 = descendant
		end
	end

	if not tp5 or not tp6 then
		warn("[PairSystem] SnowTeleport5 or SnowTeleport6 not found")
		return
	end

	local debounce: { [Player]: boolean } = {}

	janitor:Add(tp5.Touched:Connect(function(hit: BasePart)
		local player = getPlayerFromPart(hit)
		if not player then return end
		if player:GetAttribute("PairRole") ~= "Bunny" then return end
		if debounce[player] then return end

		debounce[player] = true

		local character = player.Character
		if character then
			local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if rootPart then
				local destination = tp6.Position - tp6.CFrame.LookVector * 3
				rootPart.CFrame = CFrame.new(destination, destination - tp6.CFrame.LookVector)
			end
		end

		task.delay(2, function()
			debounce[player] = nil
		end)
	end))

	debugPrint("SnowTeleport5 system initialized")
end

local function initSnowPressurePlates()
	local snowMap = workspace:FindFirstChild("SnowMap")
	if not snowMap then return end

	local bunnyPlate: BasePart? = nil
	local humanPlate: BasePart? = nil
	for _, desc in snowMap:GetDescendants() do
		if desc.Name == "BunnyPressurePlate" and desc:IsA("BasePart") then
			bunnyPlate = desc
		elseif desc.Name == "HumanPressurePlate" and desc:IsA("BasePart") then
			humanPlate = desc
		end
	end

	local invisPlats = snowMap:FindFirstChild("SnowInvisPlats") :: Model?
	if not bunnyPlate or not humanPlate or not invisPlats then
		warn("[PairSystem] PressurePlate parts or SnowInvisPlats not found")
		return
	end

	local platParts: { BasePart } = {}
	for _, desc in invisPlats:GetDescendants() do
		if desc:IsA("BasePart") then
			table.insert(platParts, desc)
		end
	end

	-- Start hidden
	for _, part in platParts do
		part.Transparency = 1
		part.CanCollide = false
	end

	local bunnyTouching = false
	local humanTouching = false
	local bunnyTouchCount = 0
	local humanTouchCount = 0
	local activated = false

	local function checkBothTouching()
		if activated then return end
		if bunnyTouching and humanTouching then
			activated = true
			for _, part in platParts do
				part.Transparency = 0
				part.CanCollide = true
			end
			debugPrint("Both pressure plates activated: SnowInvisPlats revealed permanently")
		end
	end

	janitor:Add(bunnyPlate.Touched:Connect(function(hit: BasePart)
		local player = getPlayerFromPart(hit)
		if not player then return end
		if player:GetAttribute("PairRole") ~= "Bunny" then return end
		bunnyTouchCount += 1
		bunnyTouching = true
		checkBothTouching()
	end))

	janitor:Add(bunnyPlate.TouchEnded:Connect(function(hit: BasePart)
		local player = getPlayerFromPart(hit)
		if not player then return end
		if player:GetAttribute("PairRole") ~= "Bunny" then return end
		bunnyTouchCount = math.max(0, bunnyTouchCount - 1)
		if bunnyTouchCount == 0 then
			bunnyTouching = false
		end
	end))

	janitor:Add(humanPlate.Touched:Connect(function(hit: BasePart)
		local player = getPlayerFromPart(hit)
		if not player then return end
		if player:GetAttribute("PairRole") ~= "Human" then return end
		humanTouchCount += 1
		humanTouching = true
		checkBothTouching()
	end))

	janitor:Add(humanPlate.TouchEnded:Connect(function(hit: BasePart)
		local player = getPlayerFromPart(hit)
		if not player then return end
		if player:GetAttribute("PairRole") ~= "Human" then return end
		humanTouchCount = math.max(0, humanTouchCount - 1)
		if humanTouchCount == 0 then
			humanTouching = false
		end
	end))

	debugPrint("SnowPressurePlates system initialized")
end

local function initSnowTeleport7()
	local snowMap = workspace:FindFirstChild("SnowMap")
	if not snowMap then return end

	local tp7: BasePart? = nil
	local tp8: BasePart? = nil
	for _, descendant in snowMap:GetDescendants() do
		if descendant.Name == "SnowTeleport7" and descendant:IsA("BasePart") then
			tp7 = descendant
		elseif descendant.Name == "SnowTeleport8" and descendant:IsA("BasePart") then
			tp8 = descendant
		end
	end

	if not tp7 or not tp8 then
		warn("[PairSystem] SnowTeleport7 or SnowTeleport8 not found")
		return
	end

	local debounce: { [Player]: boolean } = {}

	janitor:Add(tp7.Touched:Connect(function(hit: BasePart)
		local player = getPlayerFromPart(hit)
		if not player then return end
		if player:GetAttribute("PairRole") ~= "Bunny" then return end
		if debounce[player] then return end

		debounce[player] = true

		local character = player.Character
		if character then
			local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if rootPart then
				local destination = tp8.Position - tp8.CFrame.LookVector * 3
				rootPart.CFrame = CFrame.new(destination, destination - tp8.CFrame.LookVector)
			end
		end

		task.delay(2, function()
			debounce[player] = nil
		end)
	end))

	debugPrint("SnowTeleport7 system initialized")
end

local function initSnowSwitchPlats2()
	local snowMap = workspace:FindFirstChild("SnowMap")
	if not snowMap then return end

	-- SnowButton6 is inside SnowMap.Model
	local button6: BasePart? = nil
	for _, desc in snowMap:GetDescendants() do
		if desc.Name == "SnowButton6" and desc:IsA("BasePart") then
			button6 = desc
			break
		end
	end

	local switchPlats3 = snowMap:FindFirstChild("SnowSwitchPlats3") :: Model?
	local switchPlats4 = snowMap:FindFirstChild("SnowSwitchPlats4") :: Model?

	if not button6 or not switchPlats3 or not switchPlats4 then
		warn("[PairSystem] SnowButton6, SnowSwitchPlats3, or SnowSwitchPlats4 not found")
		return
	end

	local plats3Parts: { BasePart } = {}
	for _, desc in switchPlats3:GetDescendants() do
		if desc:IsA("BasePart") then
			table.insert(plats3Parts, desc)
		end
	end

	local plats4Parts: { BasePart } = {}
	for _, desc in switchPlats4:GetDescendants() do
		if desc:IsA("BasePart") then
			table.insert(plats4Parts, desc)
		end
	end

	-- Default state: plats3 = Neon/solid, plats4 = SmoothPlastic/hidden
	local function setDefaultState()
		for _, part in plats3Parts do
			part.Material = Enum.Material.Neon
			part.Transparency = 0
			part.CanCollide = true
		end
		for _, part in plats4Parts do
			part.Material = Enum.Material.SmoothPlastic
			part.Transparency = 0.5
			part.CanCollide = false
		end
	end

	-- Swapped state: plats3 = SmoothPlastic/hidden, plats4 = Neon/solid
	local function setSwappedState()
		for _, part in plats3Parts do
			part.Material = Enum.Material.SmoothPlastic
			part.Transparency = 0.5
			part.CanCollide = false
		end
		for _, part in plats4Parts do
			part.Material = Enum.Material.Neon
			part.Transparency = 0
			part.CanCollide = true
		end
	end

	setDefaultState()

	local touching = false
	local touchCount = 0

	janitor:Add(button6.Touched:Connect(function(hit: BasePart)
		local player = getPlayerFromPart(hit)
		if not player then return end
		if player:GetAttribute("PairRole") ~= "Bunny" then return end

		touchCount += 1
		if not touching then
			touching = true
			setSwappedState()
			debugPrint("SnowButton6 pressed: plats3/plats4 swapped")
		end
	end))

	janitor:Add(button6.TouchEnded:Connect(function(hit: BasePart)
		local player = getPlayerFromPart(hit)
		if not player then return end
		if player:GetAttribute("PairRole") ~= "Bunny" then return end

		touchCount = math.max(0, touchCount - 1)
		if touchCount == 0 then
			touching = false
			setDefaultState()
			debugPrint("SnowButton6 released: plats3/plats4 restored")
		end
	end))

	debugPrint("SnowSwitchPlats2 system initialized")
end

local function initFallingBlocks1()
	local snowMap = workspace:FindFirstChild("SnowMap")
	if not snowMap then return end

	local fallingBlocks = snowMap:FindFirstChild("FallingBlocks1") :: Model?
	if not fallingBlocks then
		warn("[PairSystem] FallingBlocks1 not found in SnowMap")
		return
	end

	-- Store original CFrames for each part
	local originalData: { [BasePart]: CFrame } = {}
	for _, desc in fallingBlocks:GetDescendants() do
		if desc:IsA("BasePart") then
			originalData[desc] = desc.CFrame
		end
	end

	local falling: { [BasePart]: boolean } = {}

	for part, originalCFrame in originalData do
		janitor:Add(part.Touched:Connect(function(hit: BasePart)
			local player = getPlayerFromPart(hit)
			if not player then return end
			if falling[part] then return end

			falling[part] = true

			-- Brief delay before falling
			task.delay(0.1, function()
				part.Anchored = false

				-- Wait then respawn
				task.delay(3, function()
					part.Anchored = true
					part.CFrame = originalCFrame
					part.Transparency = 0
					part.CanCollide = true
					falling[part] = nil
				end)
			end)
		end))
	end

	debugPrint("FallingBlocks1 system initialized")
end

local function initSnowBlinkPlats1()
	local snowMap = workspace:FindFirstChild("SnowMap")
	if not snowMap then return end

	local blinkPlats = snowMap:FindFirstChild("SnowBlinkPlats1") :: Model?
	if not blinkPlats then
		warn("[PairSystem] SnowBlinkPlats1 not found in SnowMap")
		return
	end

	local parts: { BasePart } = {}
	for _, desc in blinkPlats:GetDescendants() do
		if desc:IsA("BasePart") then
			table.insert(parts, desc)
		end
	end

	-- Start invisible but always collidable
	for _, part in parts do
		part.Transparency = 1
		part.CanCollide = true
	end

	local BLINK_INTERVAL = 2     -- seconds between blinks
	local FADE_IN_TIME = 0.1     -- seconds to fade in
	local VISIBLE_TIME = 0.1     -- seconds fully visible
	local FADE_OUT_TIME = 0.1    -- seconds to fade out
	local STEPS = 5              -- tween steps for smooth fade

	task.spawn(function()
		while true do
			task.wait(BLINK_INTERVAL)

			-- Fade in
			for i = 1, STEPS do
				local alpha = i / STEPS
				for _, part in parts do
					part.Transparency = 1 - alpha
				end
				task.wait(FADE_IN_TIME / STEPS)
			end

			-- Stay visible
			task.wait(VISIBLE_TIME)

			-- Fade out
			for i = 1, STEPS do
				local alpha = i / STEPS
				for _, part in parts do
					part.Transparency = alpha
				end
				task.wait(FADE_OUT_TIME / STEPS)
			end
		end
	end)

	debugPrint("SnowBlinkPlats1 system initialized with " .. #parts .. " parts")
end

local function initSnowColorButtons()
	local snowMap = workspace:FindFirstChild("SnowMap")
	if not snowMap then return end

	type ColorPairConfig = {
		buttonName: string,
		platName: string,
	}

	local configs: { ColorPairConfig } = {
		{ buttonName = "SnowRedButon", platName = "BunnyRedPlats" },
		{ buttonName = "SnowGreenButton", platName = "BunnyGreenPlat" },
		{ buttonName = "SnowBlueButton", platName = "BunnyBluePlat" },
		{ buttonName = "SnowYellowButton", platName = "BunnyYellowPlat" },
	}

	for _, config in configs do
		-- Find button (inside SnowMap.Model)
		local button: BasePart? = nil
		for _, desc in snowMap:GetDescendants() do
			if desc.Name == config.buttonName and desc:IsA("BasePart") then
				button = desc
				break
			end
		end

		-- Find platform (direct child of SnowMap, could be Model or UnionOperation)
		local platParent = snowMap:FindFirstChild(config.platName)

		if not button or not platParent then
			continue
		end

		-- Collect platform parts
		local platParts: { BasePart } = {}
		if platParent:IsA("BasePart") then
			table.insert(platParts, platParent)
		end
		for _, desc in platParent:GetDescendants() do
			if desc:IsA("BasePart") then
				table.insert(platParts, desc)
			end
		end

		-- Default state: hidden
		for _, part in platParts do
			part.Transparency = 0.5
			part.CanCollide = false
		end

		local activeTimer: thread? = nil

		janitor:Add(button.Touched:Connect(function(hit: BasePart)
			local player = getPlayerFromPart(hit)
			if not player then return end
			if player:GetAttribute("PairRole") ~= "Human" then return end

			if activeTimer then task.cancel(activeTimer) end

			for _, part in platParts do
				part.Transparency = 0
				part.CanCollide = true
			end

			activeTimer = task.delay(3, function()
				for _, part in platParts do
					part.Transparency = 0.5
					part.CanCollide = false
				end
				activeTimer = nil
			end)
		end))

		debugPrint(config.buttonName .. " -> " .. config.platName .. " initialized (3s timer, " .. #platParts .. " parts)")
	end
end

local function initSnowSpinner1()
	local snowMap = workspace:FindFirstChild("SnowMap")
	if not snowMap then return end

	local spinnerModel = snowMap:FindFirstChild("SnowSpinner1") :: Model?
	if not spinnerModel then
		warn("[PairSystem] SnowSpinner1 not found")
		return
	end

	-- Find the center post (smaller part) to use as pivot
	local centerPost: BasePart? = nil
	local arm: BasePart? = nil
	for _, child in spinnerModel:GetChildren() do
		if child:IsA("BasePart") then
			if child.Size.X > 10 then
				arm = child
			else
				centerPost = child
			end
		end
	end

	if not centerPost or not arm then
		warn("[PairSystem] SnowSpinner1 missing center post or arm")
		return
	end

	-- Set PrimaryPart so GetPivot returns center of rotation
	spinnerModel.PrimaryPart = centerPost

	-- Ensure all parts are anchored (server handles rotation via CFrame)
	for _, child in spinnerModel:GetChildren() do
		if child:IsA("BasePart") then
			child.Anchored = true
		end
	end

	-- Tag for server-side rotation + client-side carry
	CollectionService:AddTag(spinnerModel, "SpinnerModel")
	spinnerModel:SetAttribute("SpinnerSpeed", 50)
	spinnerModel:SetAttribute("CarriesPlayer", true)

	debugPrint("SnowSpinner1 system initialized (carries players, speed 50)")
end

local function initWinPart()
	local snowMap = workspace:FindFirstChild("SnowMap")
	if not snowMap then return end

	local winPart = snowMap:FindFirstChild("WinPart") :: BasePart?
	if not winPart then
		warn("[PairSystem] WinPart not found in SnowMap")
		return
	end

	-- Ensure WinPart is anchored so it doesn't fall
	winPart.Anchored = true

	-- Main lobby spawn for teleporting winners back
	local mainSpawn = workspace:FindFirstChild("SpawnLocation") :: SpawnLocation?
	if not mainSpawn then
		warn("[PairSystem] Main SpawnLocation not found")
		return
	end

	local debounce = false

	janitor:Add(winPart.Touched:Connect(function(hit: BasePart)
		local player = getPlayerFromPart(hit)
		if not player then return end

		-- Only paired players can win
		if not pairedPlayers.bunny or not pairedPlayers.human then return end
		if player ~= pairedPlayers.bunny and player ~= pairedPlayers.human then return end

		if debounce then return end
		debounce = true

		debugPrint(player.Name, "touched WinPart — triggering win!")

		-- Capture both players before fullReset clears them
		local bunny = pairedPlayers.bunny
		local human = pairedPlayers.human

		-- Mark Snow as completed for both players
		if bunny then bunny:SetAttribute("CompletedSnow", true) end
		if human then human:SetAttribute("CompletedSnow", true) end

		-- Ungroup and reset all state
		fullReset()

		-- Teleport both players to main spawn
		local spawnCFrame = mainSpawn.CFrame + Vector3.new(0, 3, 0)

		local function teleportPlayer(p: Player)
			local character = p.Character
			if not character then return end
			local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if rootPart then
				rootPart.CFrame = spawnCFrame
			end
		end

		task.defer(function()
			task.wait(0.5) -- Small delay to let reset settle
			if bunny then teleportPlayer(bunny) end
			if human then teleportPlayer(human) end
			debugPrint("Both players teleported to main spawn after winning")

			task.wait(2)
			debounce = false
		end)
	end))

	debugPrint("WinPart system initialized")
end

local function initRollingBalls()
	local snowMap = workspace:FindFirstChild("SnowMap")
	if not snowMap then return end

	local rollingBalls = snowMap:FindFirstChild("RollingBalls") :: Model?
	if not rollingBalls then
		warn("[PairSystem] RollingBalls model not found in SnowMap")
		return
	end

	-- Slope goes from Z≈226 (top, Y≈839) to Z≈335 (bottom, Y≈791), then flat
	-- Past Z=340, Y stays at ~790
	local SLOPE_START_Z = 226
	local SLOPE_END_Z = 340
	local SLOPE_TOP_Y = 839.4
	local SLOPE_BOTTOM_Y = 790.2
	local BALL_RADIUS = 5.3
	local ROLL_SPEED = 60
	local KILL_DISTANCE = BALL_RADIUS + 3
	local SPAWN_INTERVAL_MIN = 2
	local SPAWN_INTERVAL_MAX = 4
	local END_Z = 380 -- ball despawns past this Z

	-- Compute surface Y at a given Z
	local function getSurfaceY(z: number): number
		if z <= SLOPE_START_Z then
			return SLOPE_TOP_Y
		elseif z >= SLOPE_END_Z then
			return SLOPE_BOTTOM_Y
		else
			local t = (z - SLOPE_START_Z) / (SLOPE_END_Z - SLOPE_START_Z)
			return SLOPE_TOP_Y + t * (SLOPE_BOTTOM_Y - SLOPE_TOP_Y)
		end
	end

	type BallData = {
		part: BasePart,
		originCFrame: CFrame,
		active: boolean,
	}

	local balls: { BallData } = {}
	for _, child in rollingBalls:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(balls, {
				part = child,
				originCFrame = child.CFrame,
				active = false,
			})
			child.Anchored = true
			child.Transparency = 1
			child.CanCollide = false
		end
	end

	if #balls == 0 then
		warn("[PairSystem] No ball parts found in RollingBalls model")
		return
	end

	local function killNearbyPlayers(ballPosition: Vector3)
		for _, player in Players:GetPlayers() do
			local rootPart = getRootPart(player)
			if not rootPart then continue end
			local dist = (rootPart.Position - ballPosition).Magnitude
			if dist < KILL_DISTANCE then
				local humanoid = player.Character and player.Character:FindFirstChildWhichIsA("Humanoid")
				if humanoid and humanoid.Health > 0 then
					humanoid.Health = 0
				end
			end
		end
	end

	local function launchBall(ballData: BallData)
		if ballData.active then return end
		ballData.active = true

		local part = ballData.part
		part.Transparency = 0
		local startX = ballData.originCFrame.Position.X

		task.defer(function()
			local currentZ = SLOPE_START_Z

			while ballData.active do
				local dt = RunService.Heartbeat:Wait()

				currentZ = currentZ + ROLL_SPEED * dt
				local surfaceY = getSurfaceY(currentZ) + BALL_RADIUS

				-- Move ball and spin it
				local spinAngle = (ROLL_SPEED * dt) / BALL_RADIUS
				part.CFrame = CFrame.new(startX, surfaceY, currentZ) * (part.CFrame - part.CFrame.Position) * CFrame.Angles(spinAngle, 0, 0)

				killNearbyPlayers(part.Position)

				if currentZ > END_Z then
					break
				end
			end

			-- Reset ball
			part.Transparency = 1
			part.CFrame = ballData.originCFrame
			ballData.active = false
		end)
	end

	-- Spawner loop
	task.defer(function()
		while true do
			local interval = math.random() * (SPAWN_INTERVAL_MAX - SPAWN_INTERVAL_MIN) + SPAWN_INTERVAL_MIN
			task.wait(interval)

			local available: { BallData } = {}
			for _, bd in balls do
				if not bd.active then
					table.insert(available, bd)
				end
			end
			if #available > 0 then
				local chosen = available[math.random(1, #available)]
				launchBall(chosen)
			end
		end
	end)

	debugPrint("RollingBalls system initialized with " .. #balls .. " balls")
end

local function initDesertMap()
	local desertMap = workspace:FindFirstChild("DesertMap")
	if not desertMap then return end

	-- Disable the desert SpawnLocation so players don't auto-spawn there
	local desertSpawn = desertMap:FindFirstChild("SpawnLocation") :: SpawnLocation?
	if desertSpawn then
		desertSpawn.Enabled = false
		debugPrint("Desert SpawnLocation disabled")
	end

	-- Assign HumanBlockerPart to HumanBlocker collision group (bunny can pass, human cannot)
	local humanBlocker = workspace:FindFirstChild("HumanBlockerPart") :: BasePart?
	if humanBlocker then
		humanBlocker.CollisionGroup = "HumanBlocker"
		debugPrint("HumanBlockerPart assigned to HumanBlocker collision group")
	end
end

local function initDesertButton1()
	local desertMap = workspace:FindFirstChild("DesertMap")
	if not desertMap then return end

	local gate1 = desertMap:FindFirstChild("Gate1") :: Model?
	local button1Part = desertMap:FindFirstChild("DesertButton1", true) :: BasePart?
	if not gate1 or not button1Part then
		warn("[PairSystem] DesertButton1 or Gate1 not found in DesertMap")
		return
	end

	local gate1Opened = false

	janitor:Add(button1Part.Touched:Connect(function(hit: BasePart)
		if gate1Opened then return end
		local player = getPlayerFromPart(hit)
		if not player then return end
		if player ~= pairedPlayers.bunny then return end

		gate1Opened = true
		for _, child in gate1:GetChildren() do
			if child:IsA("BasePart") then
				child.Transparency = 1
				child.CanCollide = false
			end
		end
		debugPrint("Desert Gate1 opened by bunny")
	end))

	debugPrint("DesertButton1 system initialized")
end

local function initDesertTeleport1()
	local desertMap = workspace:FindFirstChild("DesertMap")
	if not desertMap then return end

	local tp1 = desertMap:FindFirstChild("DesertTeleport1", true) :: BasePart?
	local tp2 = desertMap:FindFirstChild("DesertTeleport2", true) :: BasePart?
	if not tp1 or not tp2 then
		warn("[PairSystem] DesertTeleport1 or DesertTeleport2 not found")
		return
	end

	local tpDebounce: { [Player]: number } = {}

	janitor:Add(tp1.Touched:Connect(function(hit: BasePart)
		local player = getPlayerFromPart(hit)
		if not player then return end
		if player ~= pairedPlayers.bunny then return end

		local now = os.clock()
		if tpDebounce[player] and now - tpDebounce[player] < 2 then return end
		tpDebounce[player] = now

		local rootPart = getRootPart(player)
		if not rootPart then return end

		local destPos = tp2.Position + tp2.CFrame.LookVector * 3
		rootPart.CFrame = CFrame.new(destPos, destPos + tp2.CFrame.LookVector)
		debugPrint(player.Name, "teleported from DesertTeleport1 to DesertTeleport2")
	end))

	debugPrint("DesertTeleport1 system initialized")
end

local function initDesertTeleport3()
	local desertMap = workspace:FindFirstChild("DesertMap")
	if not desertMap then return end

	local tp3 = desertMap:FindFirstChild("DesertTeleport3", true) :: BasePart?
	local tp4 = desertMap:FindFirstChild("DesertTeleport4", true) :: BasePart?
	if not tp3 or not tp4 then
		warn("[PairSystem] DesertTeleport3 or DesertTeleport4 not found")
		return
	end

	local tpDebounce: { [Player]: number } = {}

	janitor:Add(tp3.Touched:Connect(function(hit: BasePart)
		local player = getPlayerFromPart(hit)
		if not player then return end
		if player ~= pairedPlayers.bunny then return end

		local now = os.clock()
		if tpDebounce[player] and now - tpDebounce[player] < 2 then return end
		tpDebounce[player] = now

		local rootPart = getRootPart(player)
		if not rootPart then return end

		local destPos = tp4.Position + tp4.CFrame.LookVector * 3
		rootPart.CFrame = CFrame.new(destPos, destPos + tp4.CFrame.LookVector)
		debugPrint(player.Name, "teleported from DesertTeleport3 to DesertTeleport4")
	end))

	debugPrint("DesertTeleport3 system initialized")
end

local function initDesertKillParts1()
	local desertMap = workspace:FindFirstChild("DesertMap")
	if not desertMap then return end

	local killParts = desertMap:FindFirstChild("KillParts1") :: Model?
	if not killParts then
		warn("[PairSystem] KillParts1 not found in DesertMap")
		return
	end

	for _, part in killParts:GetChildren() do
		if not part:IsA("BasePart") then continue end
		janitor:Add(part.Touched:Connect(function(hit: BasePart)
			local player = getPlayerFromPart(hit)
			if not player then return end
			if player ~= pairedPlayers.bunny and player ~= pairedPlayers.human then return end
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				humanoid.Health = 0
			end
		end))
	end

	debugPrint("DesertKillParts1 initialized with", #killParts:GetChildren(), "parts")
end

local function initDesertButton2()
	local desertMap = workspace:FindFirstChild("DesertMap")
	if not desertMap then return end

	local button2 = desertMap:FindFirstChild("DesertButton2", true) :: BasePart?
	local platform1 = desertMap:FindFirstChild("DesertPlatform1", true) :: BasePart?
	if not button2 or not platform1 then
		warn("[PairSystem] DesertButton2 or DesertPlatform1 not found")
		return
	end

	local originalTransparency = platform1.Transparency
	local originalCanCollide = platform1.CanCollide
	local activeTimer: thread? = nil

	janitor:Add(button2.Touched:Connect(function(hit: BasePart)
		local player = getPlayerFromPart(hit)
		if not player then return end
		if player ~= pairedPlayers.bunny then return end

		if activeTimer then task.cancel(activeTimer) end

		platform1.Transparency = 0
		platform1.CanCollide = true

		activeTimer = task.delay(3, function()
			platform1.Transparency = originalTransparency
			platform1.CanCollide = originalCanCollide
			activeTimer = nil
		end)
	end))

	debugPrint("DesertButton2 system initialized (3s timer)")
end

local function initDesertButton3()
	local desertMap = workspace:FindFirstChild("DesertMap")
	if not desertMap then return end

	local button3 = desertMap:FindFirstChild("DesertButton3", true) :: BasePart?
	local platform2 = desertMap:FindFirstChild("DesertPlatform2", true) :: BasePart?
	if not button3 or not platform2 then
		warn("[PairSystem] DesertButton3 or DesertPlatform2 not found")
		return
	end

	local originalTransparency = platform2.Transparency
	local originalCanCollide = platform2.CanCollide
	local activeTimer: thread? = nil

	janitor:Add(button3.Touched:Connect(function(hit: BasePart)
		local player = getPlayerFromPart(hit)
		if not player then return end
		if player ~= pairedPlayers.bunny then return end

		if activeTimer then task.cancel(activeTimer) end

		platform2.Transparency = 0
		platform2.CanCollide = true

		activeTimer = task.delay(3, function()
			platform2.Transparency = originalTransparency
			platform2.CanCollide = originalCanCollide
			activeTimer = nil
		end)
	end))

	debugPrint("DesertButton3 system initialized (3s timer)")
end

local function initDesertSpinner1()
	local desertMap = workspace:FindFirstChild("DesertMap")
	if not desertMap then return end

	local spinnerModel = desertMap:FindFirstChild("DesertSpinner1") :: Model?
	if not spinnerModel then
		warn("[PairSystem] DesertSpinner1 not found")
		return
	end

	CollectionService:AddTag(spinnerModel, "SpinnerModel")

	-- Tag the long arm as KillPart
	for _, child in spinnerModel:GetChildren() do
		if child:IsA("BasePart") and child.Size.X > 10 then
			CollectionService:AddTag(child, "KillPart")
			break
		end
	end

	debugPrint("DesertSpinner1 system initialized (client-sided)")
end

local function initDesertTeleport5()
	local desertMap = workspace:FindFirstChild("DesertMap")
	if not desertMap then return end

	local tp5 = desertMap:FindFirstChild("DesertTeleport5", true) :: BasePart?
	local tp6 = desertMap:FindFirstChild("DesertTeleport6", true) :: BasePart?
	if not tp5 or not tp6 then
		warn("[PairSystem] DesertTeleport5 or DesertTeleport6 not found")
		return
	end

	local tpDebounce: { [Player]: number } = {}

	janitor:Add(tp5.Touched:Connect(function(hit: BasePart)
		local player = getPlayerFromPart(hit)
		if not player then return end
		if player ~= pairedPlayers.bunny and player ~= pairedPlayers.human then return end

		local now = os.clock()
		if tpDebounce[player] and now - tpDebounce[player] < 2 then return end
		tpDebounce[player] = now

		local rootPart = getRootPart(player)
		if not rootPart then return end

		local destPos = tp6.Position + tp6.CFrame.LookVector * 3
		rootPart.CFrame = CFrame.new(destPos, destPos + tp6.CFrame.LookVector)
		debugPrint(player.Name, "teleported from DesertTeleport5 to DesertTeleport6")
	end))

	debugPrint("DesertTeleport5 system initialized (both players)")
end

local function initDesertKillParts3()
	local desertMap = workspace:FindFirstChild("DesertMap")
	if not desertMap then return end

	local killParts = desertMap:FindFirstChild("KillParts3") :: Model?
	if not killParts then
		warn("[PairSystem] KillParts3 not found in DesertMap")
		return
	end

	for _, part in killParts:GetChildren() do
		if not part:IsA("BasePart") then continue end
		janitor:Add(part.Touched:Connect(function(hit: BasePart)
			local player = getPlayerFromPart(hit)
			if not player then return end
			if player ~= pairedPlayers.bunny and player ~= pairedPlayers.human then return end
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				humanoid.Health = 0
			end
		end))
	end

	debugPrint("DesertKillParts3 initialized with", #killParts:GetChildren(), "parts")
end

local function initDesertKillParts4()
	local desertMap = workspace:FindFirstChild("DesertMap")
	if not desertMap then return end

	local killParts = desertMap:FindFirstChild("KillParts4") :: Model?
	if not killParts then
		warn("[PairSystem] KillParts4 not found in DesertMap")
		return
	end

	for _, part in killParts:GetChildren() do
		if not part:IsA("BasePart") then continue end
		janitor:Add(part.Touched:Connect(function(hit: BasePart)
			local player = getPlayerFromPart(hit)
			if not player then return end
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				humanoid.Health = 0
			end
		end))
	end

	debugPrint("DesertKillParts4 initialized with", #killParts:GetChildren(), "parts")
end

local function initKillParts5()
	local desertMap = workspace:FindFirstChild("DesertMap")
	if not desertMap then return end

	local killParts = desertMap:FindFirstChild("KillParts5") :: Model?
	if not killParts then
		warn("[PairSystem] KillParts5 not found in DesertMap")
		return
	end

	for _, part in killParts:GetChildren() do
		if not part:IsA("BasePart") then continue end
		janitor:Add(part.Touched:Connect(function(hit: BasePart)
			local player = getPlayerFromPart(hit)
			if not player then return end
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				humanoid.Health = 0
			end
		end))
	end

	debugPrint("KillParts5 initialized with", #killParts:GetChildren(), "parts")
end

local function initWindPart()
	local windPart = workspace:FindFirstChild("WindPart") :: BasePart?
	if not windPart then
		warn("[PairSystem] WindPart not found")
		return
	end

	-- Ensure player can walk through and part doesn't fall
	windPart.CanCollide = false
	windPart.Anchored = true

	debugPrint("WindPart configured (anchored, non-collidable)")
end

local function initDesertButton8()
	local desertMap = workspace:FindFirstChild("DesertMap")
	if not desertMap then return end

	local button8 = desertMap:FindFirstChild("DesertButton8", true) :: BasePart?
	local platform4 = desertMap:FindFirstChild("DesertPlatform4", true) :: BasePart?
	if not button8 or not platform4 then
		warn("[PairSystem] DesertButton8 or DesertPlatform4 not found")
		return
	end

	local originalTransparency = platform4.Transparency
	platform4.CanCollide = false

	-- Find the existing "5" MeshPart in the button model
	local buttonModel = button8.Parent
	local mesh5 = buttonModel and buttonModel:FindFirstChild("5") :: MeshPart?

	-- Create SurfaceGui on top of button for countdown display
	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = "CountdownGui"
	surfaceGui.Face = Enum.NormalId.Top
	surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surfaceGui.PixelsPerStud = 50
	surfaceGui.Enabled = false
	surfaceGui.Parent = button8

	local countdownLabel = Instance.new("TextLabel")
	countdownLabel.Name = "CountdownLabel"
	countdownLabel.Size = UDim2.fromScale(1, 1)
	countdownLabel.BackgroundTransparency = 1
	countdownLabel.TextColor3 = Color3.new(1, 1, 1)
	countdownLabel.TextStrokeTransparency = 0
	countdownLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	countdownLabel.TextScaled = true
	countdownLabel.Font = Enum.Font.GothamBold
	countdownLabel.Text = "3"
	countdownLabel.Parent = surfaceGui

	local activeTimer: thread? = nil
	local countdownThread: thread? = nil

	janitor:Add(button8.Touched:Connect(function(hit: BasePart)
		local touchPlayer = getPlayerFromPart(hit)
		if not touchPlayer then return end
		if touchPlayer ~= pairedPlayers.bunny and touchPlayer ~= pairedPlayers.human then return end

		-- Reset timers if already active
		if activeTimer then
			task.cancel(activeTimer)
		end
		if countdownThread then
			task.cancel(countdownThread)
		end

		platform4.Transparency = 0
		platform4.CanCollide = true

		-- Hide the 3D "5" mesh, show SurfaceGui countdown
		if mesh5 then
			mesh5.Transparency = 1
		end
		surfaceGui.Enabled = true
		countdownLabel.Text = "3"

		countdownThread = task.spawn(function()
			for i = 2, 1, -1 do
				task.wait(1)
				countdownLabel.Text = tostring(i)
			end
		end)

		activeTimer = task.delay(3, function()
			platform4.Transparency = originalTransparency
			platform4.CanCollide = false
			surfaceGui.Enabled = false
			if mesh5 then
				mesh5.Transparency = 0
			end
			activeTimer = nil
			countdownThread = nil
		end)
	end))

	debugPrint("DesertButton8 system initialized (3s timed platform with countdown)")
end

local function initDesertTeleport7()
	local desertMap = workspace:FindFirstChild("DesertMap")
	if not desertMap then return end

	local tp7 = desertMap:FindFirstChild("DesertTeleport7", true) :: BasePart?
	local tp8 = desertMap:FindFirstChild("DesertTeleport8", true) :: BasePart?
	if not tp7 or not tp8 then
		warn("[PairSystem] DesertTeleport7 or DesertTeleport8 not found")
		return
	end

	local tpDebounce: { [Player]: number } = {}

	janitor:Add(tp7.Touched:Connect(function(hit: BasePart)
		local player = getPlayerFromPart(hit)
		if not player then return end
		if player ~= pairedPlayers.bunny then return end

		local now = os.clock()
		if tpDebounce[player] and now - tpDebounce[player] < 2 then return end
		tpDebounce[player] = now

		local rootPart = getRootPart(player)
		if not rootPart then return end

		local destPos = tp8.Position + tp8.CFrame.LookVector * 3
		rootPart.CFrame = CFrame.new(destPos, destPos + tp8.CFrame.LookVector)
		debugPrint(player.Name, "teleported from DesertTeleport7 to DesertTeleport8")
	end))

	debugPrint("DesertTeleport7 system initialized (bunny only)")
end

local function initDesertButton6()
	local desertMap = workspace:FindFirstChild("DesertMap")
	if not desertMap then return end

	local button6 = desertMap:FindFirstChild("DesertButton6", true) :: BasePart?
	local button7 = desertMap:FindFirstChild("DesertButton7", true) :: BasePart?
	local redPlats = desertMap:FindFirstChild("DesertRedPlats") :: Model?
	local bluePlats = desertMap:FindFirstChild("DesertBluePlats") :: Model?
	if not button6 or not button7 or not redPlats or not bluePlats then
		warn("[PairSystem] DesertButton6/7 or DesertRedPlats/BluePlats not found")
		return
	end

	local redParts: { BasePart } = {}
	local blueParts: { BasePart } = {}
	for _, child in redPlats:GetChildren() do
		if child:IsA("BasePart") then table.insert(redParts, child) end
	end
	for _, child in bluePlats:GetChildren() do
		if child:IsA("BasePart") then table.insert(blueParts, child) end
	end

	local function setGroupState(parts: { BasePart }, active: boolean)
		for _, part in parts do
			part.Transparency = if active then 0 else 0.5
			part.CanCollide = active
		end
	end

	setGroupState(redParts, false)
	setGroupState(blueParts, false)

	local redTimer: thread? = nil
	local blueTimer: thread? = nil

	janitor:Add(button6.Touched:Connect(function(hit: BasePart)
		local player = getPlayerFromPart(hit)
		if not player then return end
		if player ~= pairedPlayers.bunny then return end

		if redTimer then task.cancel(redTimer) end
		setGroupState(redParts, true)

		redTimer = task.delay(3, function()
			setGroupState(redParts, false)
			redTimer = nil
		end)
	end))

	janitor:Add(button7.Touched:Connect(function(hit: BasePart)
		local player = getPlayerFromPart(hit)
		if not player then return end
		if player ~= pairedPlayers.bunny then return end

		if blueTimer then task.cancel(blueTimer) end
		setGroupState(blueParts, true)

		blueTimer = task.delay(3, function()
			setGroupState(blueParts, false)
			blueTimer = nil
		end)
	end))

	debugPrint("DesertButton6/7 system initialized (3s timer, red:", #redParts, "parts, blue:", #blueParts, "parts)")
end

local function initDesertButton9()
	local desertMap = workspace:FindFirstChild("DesertMap")
	if not desertMap then return end

	local button9 = desertMap:FindFirstChild("DesertButton9", true) :: BasePart?
	local button10 = desertMap:FindFirstChild("DesertButton10", true) :: BasePart?
	local redPlats2 = desertMap:FindFirstChild("DesertRedPlats2") :: Model?
	local bluePlats2 = desertMap:FindFirstChild("DesertBluePlats2") :: Model?
	if not button9 or not button10 or not redPlats2 or not bluePlats2 then
		warn("[PairSystem] DesertButton9/10 or DesertRedPlats2/BluePlats2 not found")
		return
	end

	local redParts: { BasePart } = {}
	local blueParts: { BasePart } = {}
	for _, child in redPlats2:GetChildren() do
		if child:IsA("BasePart") then table.insert(redParts, child) end
	end
	for _, child in bluePlats2:GetChildren() do
		if child:IsA("BasePart") then table.insert(blueParts, child) end
	end

	local function setGroupState(parts: { BasePart }, active: boolean)
		for _, part in parts do
			part.Transparency = if active then 0 else 0.5
			part.CanCollide = active
		end
	end

	setGroupState(redParts, false)
	setGroupState(blueParts, false)

	local blueTimer: thread? = nil
	local redTimer: thread? = nil

	janitor:Add(button9.Touched:Connect(function(hit: BasePart)
		local player = getPlayerFromPart(hit)
		if not player then return end
		if player ~= pairedPlayers.bunny then return end

		if blueTimer then task.cancel(blueTimer) end
		setGroupState(blueParts, true)

		blueTimer = task.delay(3, function()
			setGroupState(blueParts, false)
			blueTimer = nil
		end)
	end))

	janitor:Add(button10.Touched:Connect(function(hit: BasePart)
		local player = getPlayerFromPart(hit)
		if not player then return end
		if player ~= pairedPlayers.bunny then return end

		if redTimer then task.cancel(redTimer) end
		setGroupState(redParts, true)

		redTimer = task.delay(3, function()
			setGroupState(redParts, false)
			redTimer = nil
		end)
	end))

	debugPrint("DesertButton9/10 system initialized (3s timer, red:", #redParts, "parts, blue:", #blueParts, "parts)")
end

local function initDesertSpinner2()
	local desertMap = workspace:FindFirstChild("DesertMap")
	if not desertMap then return end

	local spinnerModel = desertMap:FindFirstChild("DesertSpinner2") :: Model?
	if not spinnerModel then
		warn("[PairSystem] DesertSpinner2 not found")
		return
	end

	-- Clean up any previous SpinnerPivot parts
	for _, child in spinnerModel:GetChildren() do
		if child.Name == "SpinnerPivot" then
			child:Destroy()
		end
	end

	-- Ensure all parts are anchored (client handles rotation)
	for _, child in spinnerModel:GetChildren() do
		if child:IsA("BasePart") then
			child.Anchored = true
		end
	end

	-- Tag for client-side rotation + set attributes
	CollectionService:AddTag(spinnerModel, "SpinnerModel")
	spinnerModel:SetAttribute("SpinnerSpeed", 40)
	spinnerModel:SetAttribute("CarriesPlayer", true)

	debugPrint("DesertSpinner2 tagged as SpinnerModel (client-sided, carries players)")
end

local function initDesertSpinner3()
	local desertMap = workspace:FindFirstChild("DesertMap")
	if not desertMap then return end

	local spinnerModel = desertMap:FindFirstChild("DesertSpinner3") :: Model?
	if not spinnerModel then
		warn("[PairSystem] DesertSpinner3 not found")
		return
	end

	CollectionService:AddTag(spinnerModel, "SpinnerModel")

	-- Tag the long arm as KillPart
	for _, child in spinnerModel:GetChildren() do
		if child:IsA("BasePart") and child.Size.X > 10 then
			CollectionService:AddTag(child, "KillPart")
			break
		end
	end

	debugPrint("DesertSpinner3 system initialized (client-sided)")
end

local function initDesertButton4()
	local desertMap = workspace:FindFirstChild("DesertMap")
	if not desertMap then return end

	local button4 = desertMap:FindFirstChild("DesertButton4", true) :: BasePart?
	local platform3 = desertMap:FindFirstChild("DesertPlatform3", true) :: BasePart?
	if not button4 or not platform3 then
		warn("[PairSystem] DesertButton4 or DesertPlatform3 not found")
		return
	end

	local originalTransparency = platform3.Transparency
	local originalCanCollide = platform3.CanCollide
	local activeTimer: thread? = nil

	janitor:Add(button4.Touched:Connect(function(hit: BasePart)
		local player = getPlayerFromPart(hit)
		if not player then return end
		if player ~= pairedPlayers.bunny then return end

		if activeTimer then task.cancel(activeTimer) end

		platform3.Transparency = 0
		platform3.CanCollide = true

		activeTimer = task.delay(3, function()
			platform3.Transparency = originalTransparency
			platform3.CanCollide = originalCanCollide
			activeTimer = nil
		end)
	end))

	debugPrint("DesertButton4 system initialized (3s timer)")
end

local function initDesertBlinkPlatforms()
	local desertMap = workspace:FindFirstChild("DesertMap")
	if not desertMap then return end

	local blinkP1 = desertMap:FindFirstChild("DesertBlinkP1") :: Model?
	local blinkP2 = desertMap:FindFirstChild("DesertBlinkP2") :: Model?
	if not blinkP1 or not blinkP2 then
		warn("[PairSystem] DesertBlinkP1 or DesertBlinkP2 not found")
		return
	end

	-- P1 starts solid, P2 starts faded
	local p1Active = true

	local function setGroupState(model: Model, solid: boolean)
		for _, child in model:GetChildren() do
			if child:IsA("BasePart") then
				child.Transparency = if solid then 0 else 0.5
				child.CanCollide = solid
				child.Material = if solid then Enum.Material.Neon else Enum.Material.Glacier
			end
		end
	end

	-- Initialize states
	setGroupState(blinkP1, true)
	setGroupState(blinkP2, false)

	janitor:Add(task.defer(function()
		while true do
			task.wait(1)
			if activeMapName ~= "Desert" then continue end
			p1Active = not p1Active
			setGroupState(blinkP1, p1Active)
			setGroupState(blinkP2, not p1Active)
		end
	end))

	debugPrint("Desert blink platforms initialized (P1: 4 unions, P2: 3 unions)")
end

local function initDesertKillParts2()
	local killParts = workspace:FindFirstChild("KillParts2") :: Model?
	if not killParts then
		warn("[PairSystem] KillParts2 not found")
		return
	end

	for _, part in killParts:GetChildren() do
		if not part:IsA("BasePart") then continue end
		janitor:Add(part.Touched:Connect(function(hit: BasePart)
			local player = getPlayerFromPart(hit)
			if not player then return end
			if player ~= pairedPlayers.bunny and player ~= pairedPlayers.human then return end
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				humanoid.Health = 0
			end
		end))
	end

	debugPrint("DesertKillParts2 initialized with", #killParts:GetChildren(), "parts")
end

local function initBaseplateKill()
	local baseplates: { BasePart } = {}

	local grassMap = workspace:FindFirstChild("Other/Map")
	if grassMap then
		local bp = grassMap:FindFirstChild("Baseplate") :: BasePart?
		if bp then table.insert(baseplates, bp) end
	end

	local desertMap = workspace:FindFirstChild("DesertMap")
	if desertMap then
		local bp = desertMap:FindFirstChild("Baseplate") :: BasePart?
		if bp then table.insert(baseplates, bp) end
	end

	local snowMap = workspace:FindFirstChild("SnowMap")
	if snowMap then
		local bp = snowMap:FindFirstChild("Baseplate") :: BasePart?
		if bp then table.insert(baseplates, bp) end
	end

	for _, baseplate in baseplates do
		janitor:Add(baseplate.Touched:Connect(function(hit: BasePart)
			local player = getPlayerFromPart(hit)
			if not player then return end
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				humanoid.Health = 0
			end
		end))
	end

	debugPrint("Baseplate kill initialized for", #baseplates, "baseplates")
end

local function initDesertBlinkMoving()
	local desertMap = workspace:FindFirstChild("DesertMap")
	if not desertMap then return end

	local blinkP3 = desertMap:FindFirstChild("DesertBlinkP3") :: Model?
	local blinkP4 = desertMap:FindFirstChild("DesertBlinkP4") :: Model?
	if not blinkP3 or not blinkP4 then
		warn("[PairSystem] DesertBlinkP3 or DesertBlinkP4 not found")
		return
	end

	-- Collect parts per group
	local p3Parts: { BasePart } = {}
	local p4Parts: { BasePart } = {}
	for _, child in blinkP3:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(p3Parts, child)
			-- Tag for client-side oscillation (same system as ConveyorJump)
			CollectionService:AddTag(child, "OscillatingPlatform")
			child:SetAttribute("OscillationAmplitude", 5)
		end
	end
	for _, child in blinkP4:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(p4Parts, child)
			CollectionService:AddTag(child, "OscillatingPlatform")
			child:SetAttribute("OscillationAmplitude", 5)
		end
	end

	local BLINK_INTERVAL = 2
	local p3Active = false -- P3 starts faded
	local blinkTimer = 0

	local function setGroupState(parts: { BasePart }, solid: boolean)
		for _, part in parts do
			part.Transparency = if solid then 0 else 0.5
			part.CanCollide = solid
			part.Material = if solid then Enum.Material.Neon else Enum.Material.Glacier
		end
	end

	-- Initialize states
	setGroupState(p3Parts, false)
	setGroupState(p4Parts, true)

	-- Server only handles blink property swapping (movement handled by client OscillatingPlatform system)
	janitor:Add(RunService.Heartbeat:Connect(function(dt: number)
		if activeMapName ~= "Desert" then return end
		blinkTimer += dt

		if blinkTimer >= BLINK_INTERVAL then
			blinkTimer -= BLINK_INTERVAL
			p3Active = not p3Active
			setGroupState(p3Parts, p3Active)
			setGroupState(p4Parts, not p3Active)
		end
	end))

	debugPrint("Desert blink moving platforms initialized (P3:", #p3Parts, "parts, P4:", #p4Parts, "parts)")
end

local function initDesertButton5()
	local desertMap = workspace:FindFirstChild("DesertMap")
	if not desertMap then return end

	local button = desertMap:FindFirstChild("DesertButton5", true) :: BasePart?
	local blinkP5 = desertMap:FindFirstChild("DesertBlinkP5") :: Model?
	local blinkP6 = desertMap:FindFirstChild("DesertBlinkP6") :: Model?
	if not button or not blinkP5 or not blinkP6 then
		warn("[PairSystem] DesertButton5, DesertBlinkP5, or DesertBlinkP6 not found")
		return
	end

	local p5Parts: { BasePart } = {}
	local p6Parts: { BasePart } = {}
	for _, child in blinkP5:GetChildren() do
		if child:IsA("BasePart") then table.insert(p5Parts, child) end
	end
	for _, child in blinkP6:GetChildren() do
		if child:IsA("BasePart") then table.insert(p6Parts, child) end
	end

	local function setGroupState(parts: { BasePart }, solid: boolean)
		for _, part in parts do
			part.Transparency = if solid then 0 else 0.5
			part.CanCollide = solid
			part.Material = if solid then Enum.Material.Neon else Enum.Material.Glacier
		end
	end

	-- Default: P5 faded, P6 solid
	setGroupState(p5Parts, false)
	setGroupState(p6Parts, true)

	local activeTimer: thread? = nil

	janitor:Add(button.Touched:Connect(function(hit: BasePart)
		local player = getPlayerFromPart(hit)
		if not player then return end
		if player ~= pairedPlayers.bunny then return end

		if activeTimer then task.cancel(activeTimer) end

		setGroupState(p5Parts, true)
		setGroupState(p6Parts, false)

		activeTimer = task.delay(3, function()
			setGroupState(p5Parts, false)
			setGroupState(p6Parts, true)
			activeTimer = nil
		end)
	end))

	debugPrint("DesertButton5 initialized (3s timer, P5:", #p5Parts, "parts, P6:", #p6Parts, "parts)")
end

local function initDesertButton11()
	local desertMap = workspace:FindFirstChild("DesertMap")
	if not desertMap then return end

	local button = desertMap:FindFirstChild("DesertButton11", true) :: BasePart?
	local blinkP7 = desertMap:FindFirstChild("DesertBlinkP7") :: Model?
	local blinkP8 = desertMap:FindFirstChild("DesertBlinkP8") :: Model?
	if not button or not blinkP7 or not blinkP8 then
		warn("[PairSystem] DesertButton11, DesertBlinkP7, or DesertBlinkP8 not found")
		return
	end

	local p7Parts: { BasePart } = {}
	local p8Parts: { BasePart } = {}
	for _, child in blinkP7:GetChildren() do
		if child:IsA("BasePart") then table.insert(p7Parts, child) end
	end
	for _, child in blinkP8:GetChildren() do
		if child:IsA("BasePart") then table.insert(p8Parts, child) end
	end

	local function setGroupState(parts: { BasePart }, solid: boolean)
		for _, part in parts do
			part.Transparency = if solid then 0 else 0.5
			part.CanCollide = solid
			part.Material = if solid then Enum.Material.Neon else Enum.Material.Glacier
		end
	end

	-- Default: P7 faded, P8 solid
	setGroupState(p7Parts, false)
	setGroupState(p8Parts, true)

	local activeTimer: thread? = nil

	janitor:Add(button.Touched:Connect(function(hit: BasePart)
		local player = getPlayerFromPart(hit)
		if not player then return end
		if player ~= pairedPlayers.bunny then return end

		if activeTimer then task.cancel(activeTimer) end

		setGroupState(p7Parts, true)
		setGroupState(p8Parts, false)

		activeTimer = task.delay(3, function()
			setGroupState(p7Parts, false)
			setGroupState(p8Parts, true)
			activeTimer = nil
		end)
	end))

	debugPrint("DesertButton11 initialized (3s timer, P7:", #p7Parts, "parts, P8:", #p8Parts, "parts)")
end

local function initDesertTeleport9()
	local desertMap = workspace:FindFirstChild("DesertMap")
	if not desertMap then return end

	local tp9 = desertMap:FindFirstChild("DesertTeleport9", true) :: BasePart?
	local spawnLoc = workspace:FindFirstChildOfClass("SpawnLocation")
	if not tp9 or not spawnLoc then
		warn("[PairSystem] DesertTeleport9 or SpawnLocation not found")
		return
	end

	local playersInside: { [Player]: boolean } = {}
	local billboard: BillboardGui? = nil
	local processing = false

	local function getCount(): number
		local count = 0
		for _ in playersInside do
			count += 1
		end
		return count
	end

	local function destroyBillboard()
		if billboard then
			billboard:Destroy()
			billboard = nil
		end
	end

	local function updateBillboard()
		local count = getCount()
		if count == 0 then
			destroyBillboard()
			return
		end

		if not billboard then
			local tp9Model = tp9.Parent
			local studsAbove = Vector3.new(0, 5, 0)
			if tp9Model and tp9Model:IsA("Model") then
				local modelCF, modelSize = tp9Model:GetBoundingBox()
				local modelTopY = modelCF.Position.Y + modelSize.Y / 2
				local offsetY = modelTopY - tp9.Position.Y + 2
				studsAbove = Vector3.new(0, offsetY, 0)
			end

			local bb = Instance.new("BillboardGui")
			bb.Name = "DT9StatusGui"
			bb.Size = UDim2.new(4, 0, 2, 0)
			bb.StudsOffset = studsAbove
			bb.AlwaysOnTop = true
			bb.Adornee = tp9
			bb.Parent = tp9

			local label = Instance.new("TextLabel")
			label.Name = "StatusLabel"
			label.Size = UDim2.new(1, 0, 1, 0)
			label.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			label.BackgroundTransparency = 0.4
			label.TextColor3 = Color3.fromRGB(255, 255, 255)
			label.TextScaled = true
			label.Font = Enum.Font.GothamBold
			label.Text = count .. "/2"
			label.Parent = bb

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 8)
			corner.Parent = label

			billboard = bb
		else
			local label = billboard:FindFirstChild("StatusLabel") :: TextLabel?
			if label then
				label.Text = count .. "/2"
			end
		end
	end

	local function isInsideTeleporter(player: Player): boolean
		local rootPart = getRootPart(player)
		if not rootPart then return false end
		local pos = rootPart.Position
		local tpPos = tp9.Position
		local halfX = tp9.Size.X / 2 + 2
		local halfY = tp9.Size.Y / 2 + 2
		local halfZ = tp9.Size.Z / 2 + 2
		return math.abs(pos.X - tpPos.X) <= halfX
			and math.abs(pos.Y - tpPos.Y) <= halfY
			and math.abs(pos.Z - tpPos.Z) <= halfZ
	end

	janitor:Add(RunService.Heartbeat:Connect(function()
		if processing then return end
		local bunny = pairedPlayers.bunny
		local human = pairedPlayers.human
		if not bunny or not human then
			if next(playersInside) then
				playersInside = {}
				updateBillboard()
			end
			return
		end

		local bunnyInside = isInsideTeleporter(bunny)
		local humanInside = isInsideTeleporter(human)

		local changed = false

		if bunnyInside and not playersInside[bunny] then
			playersInside[bunny] = true
			changed = true
			debugPrint(bunny.Name, "entered DesertTeleport9 (" .. getCount() .. "/2)")
		elseif not bunnyInside and playersInside[bunny] then
			playersInside[bunny] = nil
			changed = true
			debugPrint(bunny.Name, "left DesertTeleport9 (" .. getCount() .. "/2)")
		end

		if humanInside and not playersInside[human] then
			playersInside[human] = true
			changed = true
			debugPrint(human.Name, "entered DesertTeleport9 (" .. getCount() .. "/2)")
		elseif not humanInside and playersInside[human] then
			playersInside[human] = nil
			changed = true
			debugPrint(human.Name, "left DesertTeleport9 (" .. getCount() .. "/2)")
		end

		if changed then
			updateBillboard()
		end

		if getCount() >= 2 then
			processing = true
			destroyBillboard()

			local spawnPos = spawnLoc.Position + Vector3.new(0, 3, 0)
			local bunnyRoot = getRootPart(bunny)
			local humanRoot = getRootPart(human)
			if bunnyRoot then
				bunnyRoot.CFrame = CFrame.new(spawnPos + Vector3.new(-3, 0, 0))
			end
			if humanRoot then
				humanRoot.CFrame = CFrame.new(spawnPos + Vector3.new(3, 0, 0))
			end

			-- Mark Desert as completed for both players
			if bunny then bunny:SetAttribute("CompletedDesert", true) end
			if human then human:SetAttribute("CompletedDesert", true) end

			fullReset()
			debugPrint("Both players teleported to spawn via DesertTeleport9, partnership destroyed")

			playersInside = {}
			task.delay(3, function()
				processing = false
			end)
		end
	end))

	janitor:Add(Players.PlayerRemoving:Connect(function(player: Player)
		if playersInside[player] then
			playersInside[player] = nil
			updateBillboard()
			debugPrint(player.Name, "left while in DesertTeleport9, count now", getCount())
		end
	end))

	debugPrint("DesertTeleport9 system initialized")
end

local function initMovingPlatforms()
	local map = workspace:FindFirstChild("Other/Map")
	if not map then return end

	for i = 1, 4 do
		local platform = map:FindFirstChild("MovingPlatform" .. i) :: BasePart?
		if platform then
			CollectionService:AddTag(platform, "OscillatingPlatform")
			debugPrint("Tagged MovingPlatform" .. i, "for client-side oscillation")
		end
	end
end

function PairSystem.Start(self: Self)
	warn(">>> STARTING PAIR SYSTEM <<<")

	-- Move bunny model template to ServerStorage
	local bunnyModel = workspace:FindFirstChild("Bunnycoms")
	if bunnyModel then
		bunnyModel.Parent = ServerStorage
		bunnyTemplate = bunnyModel
		debugPrint("Bunnycoms template stored in ServerStorage")
	else
		-- Check if already moved (e.g. hot reload)
		bunnyTemplate = ServerStorage:FindFirstChild("Bunnycoms")
		if bunnyTemplate then
			debugPrint("Bunnycoms template found in ServerStorage")
		else
			warn("[PairSystem] Bunnycoms model not found!")
		end
	end

	for _, tpName in { "TP1", "TP2", "TP3", "TP4" } do
		local tpModel = workspace:FindFirstChild(tpName)
		if tpModel then
			initMachine(tpModel)
		end
	end

	collectGateParts()
	createGateTrigger()
	setupWaterDeath()
	initButtonGates()
	initCarrySystem()
	initMachineRemotes()
	initTeleporters()
	initBunnyBridge()
	initSeesaw()
	initInvisPlatforms()
	initSpinner()
	initCarrotCollection()
	initBunnyTP5()
	initElevator()
	initBunnyTP7()
	initTP9()
	initSwitchButtons()
	initElevator2()
	initConveyorBelt()
	initJumpPart()
	initTeleporter11()
	initColorPlatforms()
	initOpenableGate()
	initObstacleRemotes()
	initMilestones()
	initMovingPlatforms()
	initSnowMap()
	initHeightChanging()
	initIcyPlats1()
	initSnowButton1()
	initSnowButtonPlats()
	initSnowRedPlats2()
	initSnowButton4()
	initSnowTeleport1()
	initSnowSwitchPlats()
	initSnowTeleport3()
	initSnowSwitchPlats2()
	initFallingBlocks1()
	initSnowBlinkPlats1()
	initSnowColorButtons()
	initSnowTeleport5()
	initSnowPressurePlates()
	initSnowTeleport7()
	initSnowSpinner1()
	initWinPart()
	initRollingBalls()
	initDesertMap()
	initDesertButton1()
	initDesertTeleport1()
	initDesertTeleport3()
	initDesertKillParts1()
	initDesertButton2()
	initDesertButton3()
	initDesertSpinner1()
	initDesertButton4()
	initDesertBlinkPlatforms()
	initDesertKillParts2()
	initBaseplateKill()
	initDesertBlinkMoving()
	initDesertButton5()
	initDesertKillParts3()
	initDesertKillParts4()
	initKillParts5()
	initWindPart()
	initDesertButton8()
	initDesertTeleport5()
	initDesertTeleport7()
	initDesertButton6()
	initDesertButton9()
	initDesertButton11()
	initDesertTeleport9()
	initDesertSpinner2()
	initDesertSpinner3()

	-- Desert and Snow maps are always visible (no hide/show needed)

	-- Server-side spinner rotation: rotate all SpinnerModel-tagged models each Heartbeat
	do
		type SpinnerData = {
			model: Model,
			pivotPos: Vector3,
			pivotRot: CFrame,
			parts: { { part: BasePart, offset: CFrame } },
			radSpeed: number,
			angle: number,
		}
		local serverSpinners: { SpinnerData } = {}
		local TAU = 2 * math.pi

		local function registerSpinner(model: Model)
			local originalPivot = model:GetPivot()
			local speed = model:GetAttribute("SpinnerSpeed") or 150
			local radSpeed = math.rad(speed)
			local parts: { { part: BasePart, offset: CFrame } } = {}
			for _, child in model:GetChildren() do
				if child:IsA("BasePart") then
					table.insert(parts, { part = child, offset = originalPivot:Inverse() * child.CFrame })
				end
			end
			table.insert(serverSpinners, {
				model = model,
				pivotPos = originalPivot.Position,
				pivotRot = originalPivot - originalPivot.Position,
				parts = parts,
				radSpeed = radSpeed,
				angle = 0,
			})
		end

		for _, model in CollectionService:GetTagged("SpinnerModel") do
			if model:IsA("Model") then
				registerSpinner(model)
			end
		end
		CollectionService:GetInstanceAddedSignal("SpinnerModel"):Connect(function(model)
			if model:IsA("Model") then
				registerSpinner(model)
			end
		end)

		janitor:Add(RunService.Heartbeat:Connect(function(dt: number)
			for _, entry in serverSpinners do
				if not entry.model:IsDescendantOf(workspace) then continue end
				entry.angle = (entry.angle + dt * entry.radSpeed) % TAU
				local rotatedPivot = CFrame.new(entry.pivotPos) * entry.pivotRot * CFrame.Angles(0, entry.angle, 0)
				for _, sp in entry.parts do
					sp.part.CFrame = rotatedPivot * sp.offset
				end
			end
		end))
		debugPrint("Server-side spinner rotation started for", #serverSpinners, "spinners")
	end

	janitor:Add(Players.PlayerRemoving:Connect(function(player: Player)
		onPlayerRemoving(player)
		fullReset()
		buttonCooldowns[player] = nil
	end))
	janitor:Add(Players.PlayerAdded:Connect(function(player: Player)
		player.CharacterRemoving:Connect(function()
			onCharacterRemoving(player)
		end)
	end))

	debugPrint("PairSystem started with", #gatePartStates, "gate parts tracked")
end

function PairSystem.DevForceRole(self: Self, player: Player, role: string): string
	if role == "Bunny" then
		pairedPlayers.bunny = player
		--player:SetAttribute("InPair", true)
		player:SetAttribute("PairRole", "Bunny")
		scaleCharacter(player, BUNNY_SCALE)
		assignBunnyCollisionGroup(player)
		applyBunnyModel(player)
		return player.Name .. " forced to Bunny role"
	elseif role == "Human" then
		pairedPlayers.human = player
		player:SetAttribute("PairRole", "Human")
		--player:SetAttribute("InPair", true)
		scaleCharacter(player, 1)
		clearBunnyCollisionGroup(player)
		removeBunnyModel(player)
		return player.Name .. " forced to Human role"
	end
	return "Invalid role: " .. role
end

function PairSystem.DevForcePair(self: Self, bunnyPlayer: Player, humanPlayer: Player): string
	if bunnyPlayer == humanPlayer then
		return "Cannot pair a player with themselves."
	end

	-- Reset any existing pairing first
	if pairedPlayers.bunny or pairedPlayers.human then
		fullReset()
		task.wait(0.2)
	end

	pairedPlayers.bunny = bunnyPlayer
	pairedPlayers.human = humanPlayer
	passedGate = {}

	bunnyPlayer:SetAttribute("PairRole", "Bunny")
	humanPlayer:SetAttribute("PairRole", "Human")
	bunnyPlayer:SetAttribute("InPair", true)
	humanPlayer:SetAttribute("InPair", true)

	-- Initialize carry attributes
	bunnyPlayer:SetAttribute("CarryEnabled", false)
	humanPlayer:SetAttribute("CarryEnabled", true)

	scaleCharacter(bunnyPlayer, BUNNY_SCALE)
	assignBunnyCollisionGroup(bunnyPlayer)
	applyBunnyModel(bunnyPlayer)

	setupLinkedHealth(bunnyPlayer, humanPlayer)

	return bunnyPlayer.Name .. " (Bunny) + " .. humanPlayer.Name .. " (Human) paired successfully."
end

return PairSystem


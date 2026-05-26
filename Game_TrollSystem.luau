local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local DataService = require(ReplicatedStorage.Modules.DataService).server

DataService:init({
	profileStoreIndex = "PlayerData"
})

-- Datastore for processed purchases
local PurchaseHistoryStore = DataStoreService:GetDataStore("PurchaseHistory")

-- Developer Product IDs
local PRODUCT_IDS = {
	KILL_ALL = 3553242198,
	BANANA_PEEL = 3553241589,
	EXPLODE_ALL = 3553242598,
	REVIVES_5 = 3553242925,
	REVIVES_10 = 3553243154,
	REVIVES_30 = 3553243610,
	NORMAL_REVIVE = 3553243879,
}

local TrollSystem = {}
type Self = typeof(TrollSystem)

-- ───────────────────── Troll Effects ─────────────────────

local function getOtherPlayers(buyer: Player)
	local others = {}
	for _, player in Players:GetPlayers() do
		if player ~= buyer and player.Character and player.Character:FindFirstChild("Humanoid") then
			table.insert(others, player)
		end
	end
	return others
end

local function killAllEffect(buyer: Player)
	for _, player in getOtherPlayers(buyer) do
		local humanoid = player.Character:FindFirstChild("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = 0
		end
	end
end

local function explodeAllEffect(buyer: Player)
	for _, player in getOtherPlayers(buyer) do
		local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			local explosion = Instance.new("Explosion")
			explosion.Position = rootPart.Position
			explosion.BlastRadius = 12
			explosion.BlastPressure = 500000
			explosion.DestroyJointRadiusPercent = 1
			explosion.Parent = workspace
		end
	end
end

local function bananaPeelEffect(buyer: Player)
	for _, player in getOtherPlayers(buyer) do
		local humanoid = player.Character:FindFirstChild("Humanoid")
		local rootPart = player.Character:FindFirstChild("HumanoidRootPart")

		if humanoid and rootPart and humanoid.Health > 0 then
			humanoid.Sit = true

			local bodyVelocity = Instance.new("BodyVelocity")
			bodyVelocity.Velocity = Vector3.new(
				math.random(-30,30),
				40,
				math.random(-30,30)
			)
			bodyVelocity.MaxForce = Vector3.new(1e5,1e5,1e5)
			bodyVelocity.P = 1e4
			bodyVelocity.Parent = rootPart

			task.delay(0.5,function()
				bodyVelocity:Destroy()
			end)

			task.delay(2,function()
				if humanoid and humanoid.Parent then
					humanoid.Sit = false
				end
			end)
		end
	end
end

-- ───────────────────── Revives Granting ─────────────────────

local function grantRevives(player: Player, amount: number)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")

	local success, err = pcall(function()

		if not DataService:hasProfile(player) then
			error("DataService not initialized for " .. player.Name)
		end

		local current = DataService:get(player,"Revives") or 0
		local newRevives = current + amount

		DataService:set(player,"Revives",newRevives)

		if remotes then
			remotes.Economy.Revives.UpdateRevivesUI:FireClient(player,newRevives)
		end
	end)

	if not success then
		warn("[TrollSystem] Could not grant revives:",err)
	end

	return true
end

-- ───────────────────── Buyer Notification ─────────────────────

local function notifyBuyer(player: Player, message: string)

	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then return end

	local ui = remotes:FindFirstChild("UI")
	if not ui then return end

	local notif = ui:FindFirstChild("SendNotification")

	if notif then
		notif:FireClient(player,message)
	end
end

-- ───────────────────── Product Handlers ─────────────────────

local grantHandlers = {

	[PRODUCT_IDS.KILL_ALL] = function(_,player)
		killAllEffect(player)
		notifyBuyer(player,"Kill All activated!")
		return true
	end,

	[PRODUCT_IDS.EXPLODE_ALL] = function(_,player)
		explodeAllEffect(player)
		notifyBuyer(player,"Explode All activated!")
		return true
	end,

	[PRODUCT_IDS.BANANA_PEEL] = function(_,player)
		bananaPeelEffect(player)
		notifyBuyer(player,"Banana Peel activated!")
		return true
	end,

	[PRODUCT_IDS.REVIVES_5] = function(_,player)
		return grantRevives(player,5)
	end,

	[PRODUCT_IDS.REVIVES_10] = function(_,player)
		return grantRevives(player,10)
	end,

	[PRODUCT_IDS.REVIVES_30] = function(_,player)
		return grantRevives(player,30)
	end,

	[PRODUCT_IDS.NORMAL_REVIVE] = function(_,player)
		return grantRevives(player,1)
	end
}

-- ───────────────────── Safe ProcessReceipt ─────────────────────

local function processReceipt(receiptInfo)

	local purchaseKey = "PURCHASE_" .. receiptInfo.PurchaseId

	local success, result = pcall(function()

		return PurchaseHistoryStore:UpdateAsync(purchaseKey,function(alreadyProcessed)

			if alreadyProcessed then
				return true
			end

			local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)

			if not player then
				return nil
			end

			local handler = grantHandlers[receiptInfo.ProductId]

			if not handler then
				warn("[TrollSystem] No handler for:",receiptInfo.ProductId)
				return nil
			end

			local ok, err = pcall(function()
				handler(receiptInfo,player)
			end)

			if not ok then
				warn("[TrollSystem] Handler failed:",err)
				return nil
			end

			return true
		end)

	end)

	if not success then
		warn("[TrollSystem] ProcessReceipt datastore error:",result)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if result then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	else
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
end

-- ───────────────────── Module Start ─────────────────────

function TrollSystem.Start(self: Self)

	warn(">>> TrollSystem started <<<")

	MarketplaceService.ProcessReceipt = processReceipt

end

return TrollSystem

--!strict
-- Wires up BT-driven AI for every monster model under workspace.AI (e.g. Belle).
-- A model just needs a Humanoid + HumanoidRootPart; no template/spawn step required.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BT = require(Shared:WaitForChild("BehaviorTree"))
local MonsterBT = require(Shared:WaitForChild("MonsterBT"))
local Blackboard = require(Shared:WaitForChild("Blackboard"))
local AnimationController = require(Shared:WaitForChild("AnimationController"))
local MonsterTrail = require(Shared:WaitForChild("MonsterTrail"))

-- Monsters collide with the ground/player but not with each other, or a crowd jams itself.
local MONSTER_COLLISION_GROUP = "Monsters"
if not PhysicsService:IsCollisionGroupRegistered(MONSTER_COLLISION_GROUP) then
	PhysicsService:RegisterCollisionGroup(MONSTER_COLLISION_GROUP)
end
PhysicsService:CollisionGroupSetCollidable(MONSTER_COLLISION_GROUP, MONSTER_COLLISION_GROUP, false)

local CORE_COLLISION_PARTS = { HumanoidRootPart = true, Torso = true, UpperTorso = true, LowerTorso = true }

-- Only the core body needs to physically collide; hair/accessories/limbs don't.
local function optimizeParts(model: Model)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = MONSTER_COLLISION_GROUP
			if not CORE_COLLISION_PARTS[part.Name] then
				part.CanCollide = false
			end
		end
	end
end

-- All AI logic lives in MonsterAI/MonsterBT; nothing inside the rig should run its own scripts.
local function stripEmbeddedScripts(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end
end

local AIFolder = workspace:WaitForChild("AI")

-- Clones an existing monster up to TARGET_COUNT for load-testing. Set to 1 to disable.
local TARGET_COUNT = 100
local SPAWN_SPREAD = 60

local function randomOffset(radius: number): Vector3
	local angle = math.random() * math.pi * 2
	local dist = math.random() * radius
	return Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
end

local function populateFromTemplate()
	local existing = AIFolder:GetChildren()
	local template: Model? = nil
	for _, child in existing do
		if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") then
			template = child
			break
		end
	end
	if not template then
		return
	end

	local origin = template:GetPivot()
	for _ = 1, TARGET_COUNT - #existing do
		local clone = template:Clone()
		clone:PivotTo(origin + randomOffset(SPAWN_SPREAD))
		clone.Parent = AIFolder
	end
end

populateFromTemplate()

-- BT walks the whole tree per tick, so it runs on an interval, not every frame.
local TICK_INTERVAL = 0.2

local function findNearestPlayer(position: Vector3, players: { Player }): (Player?, number)
	local nearest: Player? = nil
	local nearestDist = math.huge

	for _, player in players do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local dist = (root.Position - position).Magnitude
			if dist < nearestDist then
				nearest = player
				nearestDist = dist
			end
		end
	end

	return nearest, nearestDist
end

type AgentRecord = {
	Agent: MonsterBT.Agent,
	Root: BT.Node,
	Runtime: BT.Runtime,
	Elapsed: number,
}

-- One shared Heartbeat loop for all agents, instead of one connection each.
local agents: { [Model]: AgentRecord } = {}

-- Trails wash out to white when hundreds overlap, so cap how many get one.
local MAX_TRAILS = 100
local trailCount = 0

local function attachAI(model: Model)
	optimizeParts(model)
	stripEmbeddedScripts(model)

	local humanoid = model:WaitForChild("Humanoid") :: Humanoid
	local rootPart = model:WaitForChild("HumanoidRootPart") :: BasePart

	-- States our AI never uses; trims the humanoid's state-machine overhead.
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)

	if trailCount < MAX_TRAILS then
		MonsterTrail.Attach(rootPart)
		trailCount += 1
	end

	local agent: MonsterBT.Agent = {
		Model = model,
		Humanoid = humanoid,
		RootPart = rootPart,
		Blackboard = Blackboard.new(humanoid.MaxHealth),
		Animations = AnimationController.new(humanoid),
		CancelMovement = nil,
	}

	agents[model] = {
		Agent = agent,
		Root = MonsterBT.new(),
		Runtime = BT.NewRuntime(),
		Elapsed = math.random() * TICK_INTERVAL,
	}
end

for i, child in AIFolder:GetChildren() do
	if child:IsA("Model") then
		task.spawn(function()
			-- Staggers animation loading instead of bursting it all in one frame.
			task.wait((i - 1) * 0.02)
			attachAI(child)
		end)
	end
end

-- Lets you drag in more monster models later without touching this script.
AIFolder.ChildAdded:Connect(function(child)
	if child:IsA("Model") then
		attachAI(child)
	end
end)

-- Agents beyond this range can't matter yet, so skip their BT tick entirely.
local ACTIVATION_RADIUS = 200

RunService.Heartbeat:Connect(function(dt: number)
	local players = Players:GetPlayers()

	for model, record in agents do
		if not model.Parent or record.Agent.Humanoid.Health <= 0 then
			agents[model] = nil
			continue
		end

		record.Elapsed += dt
		if record.Elapsed < TICK_INTERVAL then
			continue
		end
		record.Elapsed -= TICK_INTERVAL

		local nearest, nearestDist = findNearestPlayer(record.Agent.RootPart.Position, players)
		if not nearest or nearestDist > ACTIVATION_RADIUS then
			continue
		end

		record.Agent.Blackboard.Target = nearest
		BT.Run(record.Root, record.Agent, record.Runtime)
	end
end)

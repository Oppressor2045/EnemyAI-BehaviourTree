--!strict
-- Rebuilds the FSM's five states (Idle/Chase/Attack/Search/Flee) as BT nodes.
-- Root priority: Flee > Chase/Attack (once sighted) > Wander.

local BT = require(script.Parent.BehaviorTree)
local LineOfSight = require(script.Parent.LineOfSight)
local NavMeshPath = require(script.Parent.NavMeshPath)
local Blackboard = require(script.Parent.Blackboard)
local AnimationController = require(script.Parent.AnimationController)

export type Agent = {
	Model: Model,
	Humanoid: Humanoid,
	RootPart: BasePart,
	Blackboard: Blackboard.BlackboardData,
	Animations: AnimationController.Controller,
	CancelMovement: (() -> ())?,
}

local function targetRootPart(agent: Agent): BasePart?
	local target = agent.Blackboard.Target
	if not target or not target.Character then
		return nil
	end
	return target.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function cancelMovement(agent: Agent)
	if agent.CancelMovement then
		agent.CancelMovement()
		agent.CancelMovement = nil
	end
	agent.Animations:StopMove()
end

-- Clears CancelMovement once the path finishes on its own, so OnRun's
-- "still moving?" check stays accurate.
local function followPath(agent: Agent, waypoints: { PathWaypoint })
	agent.CancelMovement = NavMeshPath.Follow(agent.Humanoid, agent.RootPart, waypoints, function()
		agent.CancelMovement = nil
	end)
end

-- Flee: top priority when health is low (first branch of the root Selector)

local CheckHealthLow = BT.Task({
	OnRun = function(agent: Agent)
		local bb = agent.Blackboard
		if bb.Health / bb.MaxHealth <= bb.FleeHealthRatio then
			return BT.Success
		end
		return BT.Failure
	end,
})

local FleeTask = BT.Task({
	OnStart = function(agent: Agent)
		local targetPart = targetRootPart(agent)
		if not targetPart then
			return
		end
		local away = agent.RootPart.Position - targetPart.Position
		if away.Magnitude < 0.01 then
			away = Vector3.new(1, 0, 0)
		end
		local goal = agent.RootPart.Position + away.Unit * 30
		local result = NavMeshPath.ComputeTo(agent.RootPart.Position, goal)
		if result.Status ~= Enum.PathStatus.Success then
			return
		end
		followPath(agent, result.Waypoints)
		agent.Animations:SetMoveTrack(agent.Animations.Run)
	end,
	OnRun = function(agent: Agent)
		if agent.CancelMovement == nil then
			return BT.Success
		end
		local targetPart = targetRootPart(agent)
		if not targetPart then
			return BT.Success
		end
		local distance = (agent.RootPart.Position - targetPart.Position).Magnitude
		if distance > 30 then
			return BT.Success
		end
		return BT.Running
	end,
	OnFinish = cancelMovement,
})

-- Chase / Attack: entered once the target is sighted

local SIGHT_MEMORY = 1 -- seconds of grace before officially losing sight

local CheckLineOfSight = BT.Task({
	OnRun = function(agent: Agent)
		local targetPart = targetRootPart(agent)
		if not targetPart then
			return BT.Failure
		end
		local bb = agent.Blackboard
		local distance = (agent.RootPart.Position - targetPart.Position).Magnitude
		if distance > bb.SightRange then
			return BT.Failure
		end

		local eyeLevel = agent.RootPart.Position + Vector3.new(0, 1.5, 0)
		-- Ignore the whole AI folder so other monsters don't block sight.
		local ignoreInstances: { Instance } = if agent.Model.Parent then { agent.Model.Parent } else { agent.Model }
		local canSee = LineOfSight.HasClearSight(eyeLevel, targetPart.Position, ignoreInstances)

		local now = os.clock()
		if canSee then
			bb.LastSightTime = now
			bb.LastSeenPosition = targetPart.Position
			return BT.Success
		end

		-- Grace period so one occluded tick doesn't interrupt Chase.
		if now - bb.LastSightTime < SIGHT_MEMORY then
			return BT.Success
		end
		return BT.Failure
	end,
})

local PursueTask = BT.Task({
	OnStart = function(agent: Agent)
		agent.Animations:SetMoveTrack(agent.Animations.Run)
	end,
	OnRun = function(agent: Agent)
		local bb = agent.Blackboard
		local targetPart = targetRootPart(agent)
		if not targetPart then
			return BT.Failure
		end

		local distance = (agent.RootPart.Position - targetPart.Position).Magnitude

		if distance <= bb.AttackRange then
			-- Attack lives in this same task (not a separate node) so
			-- crossing the range boundary never restarts the animation.
			agent.Animations:StopMove()

			local now = os.clock()
			if now - bb.LastAttackTime >= bb.AttackCooldown then
				bb.LastAttackTime = now
				agent.Animations:PlayAttack()

				-- Lock in target/range/damage now, not at hit time.
				local targetPlayer = bb.Target
				local range = bb.AttackRange
				local damage = bb.AttackDamage

				task.delay(bb.AttackHitDelay, function()
					if agent.Humanoid.Health <= 0 then
						return
					end
					if not targetPlayer or not targetPlayer.Character then
						return
					end
					local targetHumanoid = targetPlayer.Character:FindFirstChildOfClass("Humanoid")
					local targetRoot = targetPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
					if not targetHumanoid or not targetRoot or targetHumanoid.Health <= 0 then
						return
					end
					-- Re-check at hit time: miss if the target left range meanwhile.
					if (targetRoot.Position - agent.RootPart.Position).Magnitude > range then
						return
					end
					targetHumanoid:TakeDamage(damage)
				end)
			end

			return BT.Running
		end

		-- Sight is already confirmed, so just walk straight at the target.
		agent.Animations:SetMoveTrack(agent.Animations.Run)
		agent.Humanoid:MoveTo(targetPart.Position + bb.ApproachOffset)
		return BT.Running
	end,
	OnFinish = function(agent: Agent)
		agent.Animations:StopMove()
		agent.Humanoid:MoveTo(agent.RootPart.Position)
	end,
})

-- Wander: merges Idle/Search, stays anchored to LastSeenPosition

local function randomPointAround(center: Vector3, radius: number): Vector3
	local angle = math.random() * math.pi * 2
	local dist = math.random() * radius
	return center + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
end

local WanderTask = BT.Task({
	OnStart = function(agent: Agent)
		local bb = agent.Blackboard
		local center = bb.LastSeenPosition or agent.RootPart.Position
		local goal = randomPointAround(center, bb.WanderRadius)
		local result = NavMeshPath.ComputeTo(agent.RootPart.Position, goal)
		if result.Status ~= Enum.PathStatus.Success then
			return
		end
		followPath(agent, result.Waypoints)
		agent.Animations:SetMoveTrack(agent.Animations.Walk)
	end,
	OnRun = function(agent: Agent)
		if agent.CancelMovement == nil then
			return BT.Success
		end
		return BT.Running
	end,
	OnFinish = function(agent: Agent)
		cancelMovement(agent)
		agent.Blackboard.LastSeenPosition = nil
	end,
})

local MonsterBT = {}

function MonsterBT.new(): BT.Node
	return BT.Selector({
		BT.Sequence({ CheckHealthLow, FleeTask }),
		BT.Sequence({ CheckLineOfSight, PursueTask }),
		WanderTask,
	})
end

return MonsterBT

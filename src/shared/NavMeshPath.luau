--!strict
-- Event-driven waypoint following, same idea as EnemyAI-FSM but sourced from NavMesh instead of grid+A*.

local PathfindingService = game:GetService("PathfindingService")

local NavMeshPath = {}

export type PathResult = {
	Status: Enum.PathStatus,
	Waypoints: { PathWaypoint },
}

function NavMeshPath.ComputeTo(fromPos: Vector3, toPos: Vector3, agentParams: { [string]: any }?): PathResult
	local path = PathfindingService:CreatePath(agentParams)

	local ok = pcall(function()
		path:ComputeAsync(fromPos, toPos)
	end)

	if not ok then
		return { Status = Enum.PathStatus.NoPath, Waypoints = {} }
	end

	return { Status = path.Status, Waypoints = path:GetWaypoints() }
end

-- Follows waypoints one at a time; returns a function that cancels early.
function NavMeshPath.Follow(
	humanoid: Humanoid,
	rootPart: BasePart,
	waypoints: { PathWaypoint },
	onDone: (boolean) -> ()
): () -> ()
	local index = 1
	local connection: RBXScriptConnection? = nil
	local finished = false

	local function cleanup()
		if connection then
			connection:Disconnect()
			connection = nil
		end
	end

	local function stepTo(i: number)
		if finished then
			return
		end

		if i > #waypoints then
			finished = true
			cleanup()
			onDone(true)
			return
		end

		local waypoint = waypoints[i]
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			humanoid.Jump = true
		end
		humanoid:MoveTo(waypoint.Position)
	end

	connection = humanoid.MoveToFinished:Connect(function(reached)
		if finished then
			return
		end
		if not reached then
			finished = true
			cleanup()
			onDone(false)
			return
		end
		index += 1
		stepTo(index)
	end)

	-- Deferred so onDone can't fire before Follow even returns.
	task.defer(stepTo, index)

	return function()
		if finished then
			return
		end
		finished = true
		cleanup()
		-- Re-target to here so the Humanoid actually stops, not just our listener.
		humanoid:MoveTo(rootPart.Position)
	end
end

return NavMeshPath

--!strict

local LineOfSight = {}

function LineOfSight.HasClearSight(fromPos: Vector3, toPos: Vector3, ignoreInstances: { Instance }): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignoreInstances

	local direction = toPos - fromPos
	local result = workspace:Raycast(fromPos, direction, params)

	-- No hit at all: a completely clear line
	if not result then
		return true
	end

	-- If the ray travels (almost) the full distance before hitting anything,
	-- treat it as clear sight -- this accounts for the target's own hitbox
	-- being the first thing the ray would otherwise register as a "blocker"
	local hitDistance = (result.Position - fromPos).Magnitude
	local totalDistance = direction.Magnitude
	return hitDistance >= totalDistance - 1.0
end

return LineOfSight

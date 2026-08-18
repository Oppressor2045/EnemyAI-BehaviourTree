--!strict
-- Per-monster state shared across BT nodes (replaces the FSM's separate timer fields).

export type BlackboardData = {
	Target: Player?,
	LastSeenPosition: Vector3?,

	Health: number,
	MaxHealth: number,
	FleeHealthRatio: number,

	AttackRange: number,
	AttackDamage: number,
	AttackHitDelay: number,
	SightRange: number,
	LastSightTime: number,
	AttackCooldown: number,
	LastAttackTime: number,

	WanderRadius: number,
	ApproachOffset: Vector3, -- keeps a crowd from stacking on the same point
}

local Blackboard = {}

local APPROACH_SPREAD = 5

function Blackboard.new(maxHealth: number): BlackboardData
	local angle = math.random() * math.pi * 2
	local dist = math.random() * APPROACH_SPREAD

	return {
		Target = nil,
		LastSeenPosition = nil,

		Health = maxHealth,
		MaxHealth = maxHealth,
		FleeHealthRatio = 0.2, -- flee kicks in at or below this health ratio

		AttackRange = 6,
		AttackDamage = 10,
		AttackHitDelay = 0.3, -- damage lands this long after the attack animation starts
		SightRange = 120,
		LastSightTime = -math.huge,
		AttackCooldown = 1.5,
		LastAttackTime = 0,

		WanderRadius = 20,
		ApproachOffset = Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist),
	}
end

return Blackboard

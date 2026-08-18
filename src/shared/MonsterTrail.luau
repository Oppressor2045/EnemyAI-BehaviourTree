--!strict
-- Cosmetic motion trail; doesn't touch BT/movement logic.

local COLOR = Color3.fromRGB(178, 102, 255)
local LIFETIME = 6
local TRANSPARENCY = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.4),
	NumberSequenceKeypoint.new(1, 1),
})
-- Narrow near the character, swells mid-trail, fades at the tail.
local WIDTH_SCALE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.3),
	NumberSequenceKeypoint.new(0.6, 2),
	NumberSequenceKeypoint.new(1, 0),
})

local MonsterTrail = {}

function MonsterTrail.Attach(rootPart: BasePart): Trail
	local halfHeight = rootPart.Size.Y / 2

	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, halfHeight, 0)
	top.Parent = rootPart

	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -halfHeight, 0)
	bottom.Parent = rootPart

	local trail = Instance.new("Trail")
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = ColorSequence.new(COLOR)
	trail.Transparency = TRANSPARENCY
	trail.Lifetime = LIFETIME
	trail.WidthScale = WIDTH_SCALE
	trail.LightEmission = 0.35 -- low so overlapping trails don't blow out to white
	trail.Parent = rootPart

	return trail
end

return MonsterTrail

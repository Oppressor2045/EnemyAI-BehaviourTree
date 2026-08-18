--!strict
-- R6 sprint toggle: LeftShift switches Walk<->Run.
-- Owns both animation tracks directly since R6's default Animate has no run concept.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local WALK_ID = "rbxassetid://105790090049099"
local RUN_ID = "rbxassetid://114796763148559"

local WALK_SPEED = 16
local RUN_SPEED = 24
local FADE_TIME = 0.15

local player = Players.LocalPlayer :: Player

local function loadTrack(animator: Animator, id: string): AnimationTrack
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local track = animator:LoadAnimation(animation)
	track.Looped = true
	-- Higher than the default Animate script's Movement priority, so ours wins.
	track.Priority = Enum.AnimationPriority.Action
	return track
end

local function getOrCreateAnimator(humanoid: Humanoid): Animator
	local existing = humanoid:FindFirstChildOfClass("Animator") :: Animator?
	if existing then
		return existing
	end
	local animator = Instance.new("Animator")
	animator.Parent = humanoid
	return animator
end

local function setup(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local animator = getOrCreateAnimator(humanoid)

	local walkTrack = loadTrack(animator, WALK_ID)
	local runTrack = loadTrack(animator, RUN_ID)

	local sprinting = false
	local current: AnimationTrack? = nil

	-- Swaps to Walk or Run depending on toggle state; nil (stop) if not moving.
	local function refresh(isMoving: boolean)
		local wanted: AnimationTrack? = nil
		if isMoving then
			wanted = if sprinting then runTrack else walkTrack
		end

		if current == wanted then
			return
		end
		if current then
			current:Stop(FADE_TIME)
		end
		if wanted then
			wanted:Play(FADE_TIME)
		end
		current = wanted
	end

	humanoid.WalkSpeed = WALK_SPEED

	local movingConnection = humanoid.Running:Connect(function(speed: number)
		refresh(speed > 0.5)
	end)

	local inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or input.KeyCode ~= Enum.KeyCode.LeftShift then
			return
		end
		sprinting = not sprinting
		humanoid.WalkSpeed = if sprinting then RUN_SPEED else WALK_SPEED
		refresh(humanoid.MoveDirection.Magnitude > 0)
	end)

	humanoid.Died:Connect(function()
		movingConnection:Disconnect()
		inputConnection:Disconnect()
	end)
end

if player.Character then
	setup(player.Character)
end
player.CharacterAdded:Connect(setup)

--!strict
-- Loads and manages the monster's Walk/Run/Attack animation tracks.
-- Movement tracks crossfade into each other; Attack plays as an independent one-shot.

local ATTACK_ID = "rbxassetid://116980480677240"
local WALK_ID = "rbxassetid://105790090049099"
local RUN_ID = "rbxassetid://114796763148559"

local FADE_TIME = 0.15

type ControllerFields = {
	Animator: Animator,
	Walk: AnimationTrack,
	Run: AnimationTrack,
	Attack: AnimationTrack,
	Current: AnimationTrack?,
}

local AnimationController = {}
AnimationController.__index = AnimationController

-- typeof(setmetatable(...)) types self and makes new()'s return value inherit these methods.
export type Controller = typeof(setmetatable({} :: ControllerFields, AnimationController))

local function loadTrack(animator: Animator, id: string, looped: boolean): AnimationTrack
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local track = animator:LoadAnimation(animation)
	track.Looped = looped
	return track
end

-- FindFirstChildOfClass isn't overloaded per class, so cast + early return avoids an Instance? type.
local function getOrCreateAnimator(humanoid: Humanoid): Animator
	local existing = humanoid:FindFirstChildOfClass("Animator") :: Animator?
	if existing then
		return existing
	end

	local animator = Instance.new("Animator")
	animator.Parent = humanoid
	return animator
end

function AnimationController.new(humanoid: Humanoid): Controller
	local animator = getOrCreateAnimator(humanoid)

	local self: ControllerFields = {
		Animator = animator,
		Walk = loadTrack(animator, WALK_ID, true),
		Run = loadTrack(animator, RUN_ID, true),
		Attack = loadTrack(animator, ATTACK_ID, false),
		Current = nil,
	}

	return setmetatable(self, AnimationController)
end

-- Switches the movement track (Walk<->Run); no-ops if it's already playing.
function AnimationController.SetMoveTrack(self: Controller, track: AnimationTrack)
	if self.Current == track then
		return
	end
	if self.Current then
		self.Current:Stop(FADE_TIME)
	end
	track:Play(FADE_TIME)
	self.Current = track
end

function AnimationController.StopMove(self: Controller)
	if self.Current then
		self.Current:Stop(FADE_TIME)
		self.Current = nil
	end
end

-- Plays the attack animation once, independent of the movement track.
function AnimationController.PlayAttack(self: Controller)
	self.Attack:Play()
end

return AnimationController

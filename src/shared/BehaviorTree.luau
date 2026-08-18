--!strict
-- Minimal BT engine supporting only Task/Sequence/Selector nodes.
-- Re-evaluates the whole tree from the root every tick (no Parallel node).

export type Status = "Success" | "Failure" | "Running"

local SUCCESS: Status = "Success"
local FAILURE: Status = "Failure"
local RUNNING: Status = "Running"

export type Runtime = {
	TaskState: { [any]: { Started: boolean } },
	CurrentRunning: any,
	PreviousRunning: any,
}

export type Node = {
	Evaluate: (agent: any, runtime: Runtime) -> Status,
	Finish: ((any) -> ())?,
}

local BehaviorTree = {}
BehaviorTree.Success = SUCCESS
BehaviorTree.Failure = FAILURE
BehaviorTree.Running = RUNNING

-- Leaf node. OnStart fires once on entering Running, OnFinish once on leaving it.
function BehaviorTree.Task(config: {
	OnStart: ((any) -> ())?,
	OnRun: (any) -> Status,
	OnFinish: ((any) -> ())?,
}): Node
	local node = {} :: Node
	node.Finish = config.OnFinish

	node.Evaluate = function(agent, runtime)
		local state = runtime.TaskState[node]
		if not state then
			state = { Started = false }
			runtime.TaskState[node] = state
		end

		if not state.Started then
			if config.OnStart then
				config.OnStart(agent)
			end
			state.Started = true
		end

		local status = config.OnRun(agent)

		if status == RUNNING then
			runtime.CurrentRunning = node
		else
			if config.OnFinish then
				config.OnFinish(agent)
			end
			state.Started = false
		end

		return status
	end

	return node
end

-- Succeeds only if every child succeeds; returns early on Failure or Running.
function BehaviorTree.Sequence(children: { Node }): Node
	return {
		Evaluate = function(agent, runtime)
			for _, child in children do
				local status = child.Evaluate(agent, runtime)
				if status ~= SUCCESS then
					return status
				end
			end
			return SUCCESS
		end,
	}
end

-- Stops at the first child that succeeds or is running; fails only if all children fail.
function BehaviorTree.Selector(children: { Node }): Node
	return {
		Evaluate = function(agent, runtime)
			for _, child in children do
				local status = child.Evaluate(agent, runtime)
				if status ~= FAILURE then
					return status
				end
			end
			return FAILURE
		end,
	}
end

function BehaviorTree.NewRuntime(): Runtime
	return { TaskState = {}, CurrentRunning = nil, PreviousRunning = nil }
end

-- Interrupt: if last tick's Running task didn't run this tick, force its Finish.
function BehaviorTree.Run(root: Node, agent: any, runtime: Runtime): Status
	runtime.CurrentRunning = nil
	local status = root.Evaluate(agent, runtime)

	local previous = runtime.PreviousRunning
	if previous and previous ~= runtime.CurrentRunning then
		local state = runtime.TaskState[previous]
		if state and state.Started then
			if previous.Finish then
				previous.Finish(agent)
			end
			state.Started = false
		end
	end

	runtime.PreviousRunning = runtime.CurrentRunning
	return status
end

return BehaviorTree

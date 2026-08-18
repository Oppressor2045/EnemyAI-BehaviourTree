# EnemyAIBehaviourTree

A rebuild of the monster AI I originally made with `EnemyAI-FSM` (grid A* + FSM), this time using a Behavior Tree plus Roblox's built-in NavMesh. The point was to run the two side by side and actually feel the difference "a structure that doesn't fall apart as states grow" makes — and along the way this turned into a running log of every animation, collision, and memory issue I hit and fixed.

The Behavior Tree engine itself is hand-written, no external library (BehaviorTree3, etc.). Why is explained further down.

## Table of Contents

- [Getting Started](#getting-started)
- [Project Structure](#project-structure)
- [Core Code Walkthrough](#core-code-walkthrough)
  - [BehaviorTree.luau — the BT engine](#behaviortreeluau--the-bt-engine)
  - [MonsterBT.luau — the actual behavior tree](#monsterbtluau--the-actual-behavior-tree)
  - [NavMeshPath.luau — movement](#navmeshpathluau--movement)
  - [AnimationController.luau — animation](#animationcontrollerluau--animation)
  - [MonsterAI.server.luau — spawning and optimization](#monsteraiserverluau--spawning-and-optimization)
  - [Other files](#other-files)
- [Known Limitations and Tradeoffs](#known-limitations-and-tradeoffs)
- [Comparing Against the FSM Version](#comparing-against-the-fsm-version)

## Getting Started

1. Drop a monster model (with `Humanoid` + `HumanoidRootPart`) under the `workspace.AI` folder — e.g. `workspace.AI.Belle`. The name doesn't matter, and dragging in more monsters later doesn't require touching any script; AI attaches automatically.
2. No need to bake a NavMesh manually. `PathfindingService` computes it at runtime; Studio's `Navigation` window is just a preview/debug tool.
3. Turn on `rojo serve` and sync in Studio. If a commit changes the project tree structure (`default.project.json`), you may need to restart `rojo serve` and reconnect the plugin — content-only changes sync live, but new service mappings sometimes don't take effect until reconnecting.

## Project Structure

```
src/
  shared/
    BehaviorTree.luau       -- BT engine (Task/Sequence/Selector)
    MonsterBT.luau            -- the monster's actual behavior tree
    NavMeshPath.luau           -- PathfindingService wrapper + event-driven movement
    AnimationController.luau    -- manages the Walk/Run/Attack tracks
    Blackboard.luau              -- per-monster state (replaces the FSM's scattered timer fields)
    LineOfSight.luau              -- sight check (kept as-is from EnemyAI-FSM)
    MonsterTrail.luau              -- cosmetic trail showing the path traveled
  server/
    MonsterAI.server.luau      -- spawning, collision/script cleanup, the main loop
  starterPlayerScripts/
    SprintToggle.client.luau   -- player-side Shift-to-sprint toggle
```

## Core Code Walkthrough

### BehaviorTree.luau — the BT engine

Supports exactly three node types: Task (leaf), Sequence (succeeds only if every child does), and Selector (succeeds as soon as one child does). No Parallel, no Decorators — the tree doesn't need them yet, so I didn't build them.

The part that matters most is the interrupt handling at the end of `Run()`. Because the engine just re-evaluates the whole tree from the root every tick, a priority shift can mean some Task simply isn't evaluated on a given tick anymore (say, a wandering monster suddenly spots the player and jumps to chasing). Without forcing that old Task's `Finish` to run, whatever movement or animation it had going never gets cleaned up. I actually shipped that bug once — a monster stood frozen in place with its walk animation looping forever.

The Task node objects themselves are shared across all 100+ monsters (`MonsterBT.luau` only builds them once). What's per-monster is the `Runtime` — so even though everyone references the same node, state like whether a Task has `Started` never bleeds between monsters.

### MonsterBT.luau — the actual behavior tree

```
Selector
├─ Sequence(low health → Flee)          -- top priority
├─ Sequence(target sighted → Pursue)     -- chase + attack combined
└─ Wander                                -- fallback
```

I originally tried porting the FSM's five states (Idle/Chase/Attack/Search/Flee) one-to-one, and at first split `Chase` and `Attack` into separate nodes. That caused a real problem: whenever the monster hovered right at the edge of attack range, it kept flipping between the two nodes, and every flip re-triggered the engine's interrupt logic — restarting the run animation roughly every 0.1 seconds. Merging them into one `Pursue` task ("close enough, attack; otherwise, keep closing the distance") removed the node switch entirely and fixed it.

Sight checking (`CheckLineOfSight`) carries a one-second grace period (`SIGHT_MEMORY`). Since it's a fresh raycast every tick, a single frame of occlusion — another monster jostling into the line, an edge of terrain — could otherwise cut the chase for a tick and restart it the next. If sight was confirmed within the last second, it still counts as seeing the target.

`ApproachOffset` (on the Blackboard) is a random personal offset assigned to each monster at spawn. Without it, a crowd converging on the player all walk toward the exact same point and visibly stack on top of each other. The offset only nudges the movement destination — attack-range checks still use the player's real position.

### NavMeshPath.luau — movement

Computes a path via `PathfindingService` and follows the waypoints one at a time using the `MoveToFinished` event (no distance polling). The cancel function `Follow()` returns doesn't just disconnect the listener — it also calls `Humanoid:MoveTo(current position)`. Without that, our own bookkeeping says the monster stopped, but the character keeps sliding toward wherever it was last told to walk.

Pursue doesn't use this path-computation step at all. Since it only enters once line of sight is already confirmed, continuously re-issuing `MoveTo` toward the player's live position each tick is smoother (no direction snapping between waypoints) and cheaper than recomputing a path. The tradeoff: on terrain where sight is clear but the ground path isn't (a low wall you can see over but not walk through), it can get stuck.

### AnimationController.luau — animation

A small class managing the Walk/Run/Attack tracks. It types `self` with the `typeof(setmetatable(...))` pattern (same idiom used in EnemyAI-FSM). The first version forgot to actually wire the returned object's methods to that metatable, so calling them threw a "no such method" error at runtime — fixed with `AnimationController.__index = AnimationController` plus `setmetatable`.

If a rig ships with the default `Animate` script, it fights this class for control of the same `Animator`. That's why `MonsterAI.server.luau` strips every script out of a cloned model on attach.

### MonsterAI.server.luau — spawning and optimization

- **Spawning**: clones one existing monster in `workspace.AI` up to `TARGET_COUNT`. The optimizations below came from stress-testing at 1,000–10,000 monsters.
- **Single loop**: instead of one `Heartbeat` connection per monster, everyone shares one loop. A hundred connections each calling `Players:GetPlayers()` every single frame was the actual source of the stutter.
- **Distance culling**: any monster more than 200 studs from every player skips its raycasts, pathfinding, and BT tick entirely.
- **Simplified collision**: monsters are grouped into their own `CollisionGroup` so they don't collide with each other, and every part except the core body (`HumanoidRootPart`/`Torso`-type parts) has `CanCollide` turned off to cut physics overhead. (`CollisionFidelity` would help further, but a regular script doesn't have permission to write it — that one's Studio-plugin-only.)
- **Staggered ticking**: each monster's tick phase is randomized at spawn so a hundred agents don't all do their expensive work on the exact same frame.
- **Capped trails**: trails wash out to solid white once hundreds overlap and aren't cheap to render, so only the first 100 monsters get one.

### Other files

- **`Blackboard.luau`**: per-monster state — target, health ratio, attack range, cooldowns. Consolidates what used to be separate timer fields scattered across the FSM.
- **`MonsterTrail.luau`**: purely visual. A `Trail` between two `Attachment`s traces the path traveled. Has nothing to do with BT or movement logic.
- **`LineOfSight.luau`**: unchanged from EnemyAI-FSM. It's a plain raycast with no dependency on the grid/A* system, so it carried over as-is.
- **`SprintToggle.client.luau`**: player-side. R6's default `Animate` has no real concept of "running" (it just plays the walk animation faster), so this owns the Walk/Run tracks directly. Toggled with Shift.

## Known Limitations and Tradeoffs

- **Pursue doesn't respect terrain**: since it walks straight at the target with no NavMesh involved, it can get stuck on terrain where sight is clear but the ground route isn't.
- **Trails only go to the first 100 monsters**: anyone spawned after that moves without one.
- **Anything past `ACTIVATION_RADIUS` (200) just stands still**: reads as natural on a large, spread-out map, but can look odd if you cram a huge crowd into a small test area.
- **Structural changes to `default.project.json` need a `rojo serve` restart**: file content syncs live, but adding a new service mapping sometimes doesn't take effect until you reconnect.

## Comparing Against the FSM Version

Put an `EnemyAI-FSM` monster and one from this project on the same map and run them through the same scenario — spot the player, chase, attack, lose sight, wander — and compare:

- **Movement**: the FSM's grid gives stair-stepped paths; NavMesh gives smooth ones.
- **Debugging**: a single `GetState()` log line was enough to trace most FSM bugs. BT has no built-in way to see "which node is currently Running" — without adding that tooling yourself, it can actually be harder to debug (I ran into this firsthand).
- **Priority handling**: the FSM used hand-written exception logic; in BT, the first branch of the top-level Selector does that job structurally.
- **Per-tick cost**: the FSM's `if state == X` is still cheaper than walking a tree, tick for tick. "Efficient" here means maintainability and extensibility, not raw runtime performance — the difference shows up once you're adding more monster types, not at one.

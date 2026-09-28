extends Node

## Single owner for `Engine.time_scale`.
##
## Slow-motion effects used to write to `Engine.time_scale` directly from two
## places (the player's parry hit-stop and the boss death cinematic). Because
## each one restored 1.0 when it finished, a parry landing during the boss
## cinematic would cut the cinematic back to full speed early. Holding a token
## here means nested slows unwind in the right order.

## The scale in effect when nothing is holding, i.e. normal game speed.
@export var normal_scale: float = 1.0

## Requested slow-motion scales, outermost first.
var _stack: Array[float] = []


func _ready() -> void:
	# Must keep ticking while the tree is paused, otherwise a hold could never
	# be released and the game would stay frozen.
	process_mode = Node.PROCESS_MODE_ALWAYS


## Request slow motion. Returns a token to pass to `release()`.
## The token is invalidated once another hold is released on top of it.
func hold(new_scale: float) -> int:
	_stack.append(new_scale)
	Engine.time_scale = new_scale
	return _stack.size() - 1


## Drop a previously requested slow motion. Releasing a hold also discards
## anything requested after it, so a stale token can never leave the game stuck
## at the wrong speed.
func release(token: int) -> void:
	if token < 0 or token >= _stack.size():
		return

	_stack.resize(token + 1)
	_stack.pop_back()
	Engine.time_scale = _stack.back() if not _stack.is_empty() else normal_scale


## Force everything back to normal speed. Use when restarting or leaving a
## cutscene, where pending holds should not be honoured.
func reset() -> void:
	_stack.clear()
	Engine.time_scale = normal_scale

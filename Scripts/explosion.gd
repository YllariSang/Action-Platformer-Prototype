extends GPUParticles2D

## Hard backstop so an explosion can never leak a node into the scene if the
## `finished` signal is missed (paused tree, time_scale churn, headless runs).
@export var max_lifetime: float = 3.0

func _ready():
	emitting = true
	
	var guard = get_tree().create_timer(max_lifetime, true, false, true)
	guard.timeout.connect(queue_free, CONNECT_ONE_SHOT)
	
	await finished
	queue_free()

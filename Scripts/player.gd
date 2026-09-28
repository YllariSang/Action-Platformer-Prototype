extends CharacterBody2D

# --- CONFIGURATION ---
@export_category("Combat")
@export var bullet_scene: PackedScene 
@export var railgun_scene: PackedScene 
@export var max_ammo: int = 6
@export var start_ammo: int = 0
@export var parry_duration: float = 0.2 
@export var parry_cooldown: float = 0.8 
@export var parry_success_cooldown: float = 0.1 

@export_category("Health")
@export var max_hp: int = 3
## Health does not regenerate on its own. Sparks are the only way back.
@export var heal_cost: int = 2
@export var invuln_time: float = 1.0

@export_category("Movement")
@export var speed: float = 300.0
@export var jump_force: float = -600.0
@export var gravity: float = 1500.0
@export var dash_speed: float = 1000.0
@export var max_jumps: int = 2
@export var wall_jump_push: float = 500.0
@export var wall_slide_speed: float = 100.0
@export var recoil_force: float = 900.0 
@export var recoil_duration: float = 0.2
@export var shot_recoil_mult: float = 0.2
@export var railgun_recoil_mult: float = 0.5
@export var coyote_time: float = 0.15 

# --- STATE MACHINE ---
enum State { IDLE, RUN, ATTACK, PARRY, DASH, STUNNED, RECOVERY, DEAD }
var current_state = State.IDLE
var current_ammo: int = 0
var facing_direction: int = 1
var can_parry: bool = true 
var jump_count: int = 0
var can_dash: bool = true
var coyote_timer: float = 0.0 

# Health
var hp: int = 3
var invuln_timer: float = 0.0
var is_dead: bool = false

# Charging Variables
var charge_timer: float = 0.0
var is_charging: bool = false
var railgun_cost: int = 3

# Recoil is kept OUT of `velocity` because handle_movement_and_jumps() reassigns
# velocity.x from input every frame. Writing the push into velocity meant it was
# either clobbered (the old bug) or re-added every frame, which integrates into a
# runaway impulse. Instead the horizontal push rides alongside the input-derived
# velocity and decays to zero; the vertical push is a one-shot that gravity
# already bleeds off.
var recoil_x: float = 0.0
var recoil_x_start: float = 0.0
var recoil_time_left: float = 0.0
var recoil_applied_x: float = 0.0 # what was added to velocity.x last frame

# --- NODES ---
@onready var parry_box: Area2D = $ParryBox
@onready var parry_timer: Timer = $ParryTimer
@onready var cooldown_timer: Timer = $ParryCooldownTimer
@onready var dash_timer: Timer = $DashTimer
@onready var sprite: Sprite2D = $Sprite2D
@onready var spark_fire = $Sprite2D/SparkFire

# --- HUD ---
# The HUD lives on a CanvasLayer rather than following the player, so the
# numbers stay put and are readable no matter where the camera is.
@onready var hud_root: Control = $UI/HudRoot
@onready var hud_column: VBoxContainer = $UI/HudRoot/LeftColumn
@onready var health_row: HBoxContainer = $UI/HudRoot/LeftColumn/HealthRow
@onready var spark_row: HBoxContainer = $UI/HudRoot/LeftColumn/SparkBlock/SparkRow
@onready var label_spark: Label = $UI/HudRoot/LeftColumn/SparkBlock/SparkLabel
@onready var label_heal: Label = $UI/HudRoot/HealHint

## Built in code rather than placed in the scene so that changing `max_hp` or
## `max_ammo` in the inspector just works. See rebuild_hud().
var health_pips: Array[ColorRect] = []
var spark_pips: Array[ColorRect] = []

# Tint for a pip that still has value behind it, and one that is spent.
const PIP_LIT := Color(1, 0.32, 0.38, 1)
const PIP_EMPTY := Color(0.22, 0.22, 0.28, 0.55)
const SPARK_LIT := Color(1, 0.72, 0.25, 1)
const SPARK_EMPTY := Color(0.26, 0.24, 0.22, 0.6)

## Tints kept in 0..1 so they read as colour rather than an over-bright blowout.
## A value like Color(10, 10, 10) only looked right on flat placeholder shapes.
const CHARGE_TINT := Color(0, 1, 1)      # cyan, charging the railgun
const VULNERABLE_TINT := Color(0.5, 0.5, 0.8) # blue-grey, parry recovery
const DASH_TINT := Color(1, 1, 1, 0.5)

@onready var heal_fire: GPUParticles2D = $Sprite2D/HealFire

var popup_scene = preload("res://Scenes/popup.tscn")

## The HUD column's settled position, captured once after the first layout.
## shake_ui() always returns to this, never to whatever the position happens to
## be when a shake starts.
var hud_rest_pos: Vector2 = Vector2.ZERO
var _hud_shake_tween: Tween = null
var _hud_rest_captured := false

var was_max_ammo = false

func _ready() -> void:
	current_ammo = start_ammo
	hp = max_hp
	
	rebuild_hud()
	update_ui()
	parry_box.monitoring = false 
	parry_box.monitorable = false
	heal_fire.emitting = false
	SpriteFeedback.attach(sprite)
	
	if not dash_timer.timeout.is_connected(_on_dash_timer_timeout):
		dash_timer.timeout.connect(_on_dash_timer_timeout)
	
	# The HUD column's rest position is only meaningful after the Container has
	# run its first layout pass, which has not happened yet during _ready().
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(hud_column):
		hud_rest_pos = hud_column.position
		_hud_rest_captured = true


func _physics_process(delta: float) -> void:
	if current_state == State.STUNNED: return
	
	# A dead player keeps falling (so the body drops) but takes no input.
	if is_dead:
		tick_invuln_blink(delta)
		return
	
	# Strip the horizontal push applied last frame. Without this it would be
	# read back as part of velocity.x by move_toward() and compound every frame.
	velocity.x -= recoil_applied_x
	recoil_applied_x = 0.0
	
	#COYOTE TIME & GRAVITY
	if is_on_floor():
		coyote_timer = coyote_time
		jump_count = 0
		can_dash = true 
	else:
		coyote_timer -= delta
		if current_state != State.DASH:
			if is_on_wall() and velocity.y > 0:
				velocity.y = wall_slide_speed
				can_dash = true 
			else:
				velocity.y += gravity * delta

	#RECOIL DECAY (must run before movement, which reads recoil_x)
	apply_recoil(delta)
	
	#MOVEMENT
	if current_state != State.DASH and current_state != State.PARRY:
		handle_movement_and_jumps()
	
	# Apply the push on top of whatever movement just decided, and remember it
	# so next frame can take it back off again. This works whether or not the
	# player is holding a direction.
	velocity.x += recoil_x
	recoil_applied_x = recoil_x
	
	move_and_slide()
	
	#AIMING
	parry_box.look_at(get_global_mouse_position())
	
	#INVULNERABILITY BLINK
	tick_invuln_blink(delta)
	
	#ACTIONS
	handle_attack_input(delta)
	
	if Input.is_action_just_pressed("heal"):
		try_to_heal()
	elif Input.is_action_just_pressed("parry"):
		try_to_parry()
	elif Input.is_action_just_pressed("dash"):
		try_to_dash()

# --- MOVEMENT LOGIC ---
func handle_movement_and_jumps():
	var input_dir = Input.get_axis("left", "right")
	
	var current_speed = speed
	if current_state == State.RECOVERY:
		current_speed = speed * 0.5 
	
	if input_dir:
		velocity.x = input_dir * current_speed
		facing_direction = sign(input_dir)
		sprite.flip_h = (input_dir < 0)
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)

	if Input.is_action_just_pressed("jump"):
		if current_state == State.RECOVERY and is_on_floor(): return

		# Wall Jump
		if is_on_wall() and not is_on_floor():
			velocity.y = jump_force
			velocity.x = -facing_direction * wall_jump_push 
			jump_count = 1 
			can_dash = true 
			
		# Normal Jump (Coyote)
		elif coyote_timer > 0:
			velocity.y = jump_force
			jump_count = 1
			coyote_timer = 0
			
		# Double Jump
		elif jump_count < max_jumps:
			velocity.y = jump_force
			jump_count += 1

# --- CHARGE & ATTACK LOGIC ---
func handle_attack_input(delta):
	if current_state == State.PARRY or current_state == State.DASH or current_state == State.RECOVERY:
		# Losing the state has to drop the charge, otherwise releasing the mouse
		# after a dash fires a railgun that was never charged up. The tint is not
		# reset here: those states own sprite.modulate themselves.
		is_charging = false
		charge_timer = 0.0
		return

	if Input.is_action_pressed("attack"):
		is_charging = true
		charge_timer += delta
		# Tints stay in 0..1 so they read as colour, not as an over-bright blowout
		# that would clip on real artwork. Past 1.0 the charge is ready, so the
		# shader flashes a pulse instead of pinning a static colour.
		if charge_timer >= 1.0:
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
			SpriteFeedback.set_tint(sprite, Color(1, 1, 1).lerp(CHARGE_TINT, 0.75))
			SpriteFeedback.flash(sprite, CHARGE_TINT, pulse * 0.5, 0.08)
		elif charge_timer > 0.1:
			var t := clampf(charge_timer, 0.0, 1.0)
			SpriteFeedback.set_tint(sprite, Color(1, 1, 1).lerp(CHARGE_TINT, t))
		
	elif Input.is_action_just_released("attack"):
		is_charging = false
		reset_player_tint()
		
		if charge_timer >= 1.0:
			fire_railgun()
		else:
			fire_normal_shot()
		charge_timer = 0.0

func fire_normal_shot():
	if current_ammo > 0:
		spawn_bullet(bullet_scene, 1, shot_recoil_mult)
		current_ammo -= 1
		update_ui()
	else:
		spawn_popup("NO AMMO!", Color(0.5, 0.5, 0.5))

func fire_railgun():
	if current_ammo >= railgun_cost:
		spawn_bullet(railgun_scene, 2.0, railgun_recoil_mult) 
		current_ammo -= railgun_cost
		update_ui()
		spawn_popup("RAILGUN!", Color(0, 1, 1))
	else:
		spawn_popup("NEED 3 SPARKS!", Color(1, 0, 0))
		fire_normal_shot()

func spawn_bullet(scene_to_spawn, shake_amount, recoil_mult):
	if not scene_to_spawn: return
	
	current_state = State.ATTACK
	
	var mouse_pos = get_global_mouse_position()
	var dir_vec = (mouse_pos - global_position).normalized()
	
	var b = scene_to_spawn.instantiate()
	get_parent().add_child(b)
	b.global_position = global_position + (dir_vec * 60) 
	b.direction = dir_vec
	
	# Recoil Logic
	# add_recoil() owns the push instead of writing to velocity directly:
	# handle_movement_and_jumps() reassigns velocity.x from input every frame,
	# so a value stored there would be clobbered before it moved anything.
	add_recoil(-dir_vec * recoil_force * recoil_mult)
	get_tree().call_group("camera", "add_shake", shake_amount)
	
	# Recovery Delay
	await get_tree().create_timer(0.1).timeout
	if current_state == State.ATTACK:
		current_state = State.IDLE

# --- DASH & PARRY LOGIC ---

func apply_recoil(delta: float) -> void:
	if recoil_time_left <= 0.0:
		recoil_x = 0.0
		return
	
	recoil_time_left -= delta
	if recoil_time_left <= 0.0:
		clear_recoil()
		return
	
	# Fade the push out linearly so it lands exactly on zero at the end.
	var t = clampf(recoil_time_left / recoil_duration, 0.0, 1.0)
	recoil_x = recoil_x_start * t

func add_recoil(impulse: Vector2) -> void:
	# Vertical is a one-shot: added once and bled off by gravity, so it cannot
	# compound the way a per-frame add would.
	velocity.y += impulse.y
	
	# Horizontal rides alongside the input velocity until it decays to zero.
	recoil_x_start = impulse.x
	recoil_x = impulse.x
	recoil_time_left = recoil_duration

func clear_recoil() -> void:
	recoil_x = 0.0
	recoil_x_start = 0.0
	recoil_time_left = 0.0

func try_to_dash():
	if not can_dash or current_state == State.PARRY or current_state == State.RECOVERY: return
	
	current_state = State.DASH
	can_dash = false 
	
	var input_dir = Input.get_axis("left", "right")
	var dash_dir = input_dir if input_dir != 0 else facing_direction
	
	velocity.y = 0 
	velocity.x = dash_dir * dash_speed
	# Set the full colour, not just alpha, so a charge glow left on the sprite
	# does not bleed into the dash silhouette.
	reset_player_tint()
	SpriteFeedback.set_tint(sprite, DASH_TINT)
	dash_timer.start()

func _on_dash_timer_timeout():
	if current_state == State.DASH:
		current_state = State.IDLE
	velocity.x = 0
	reset_player_tint()

## Clear the charge glow and any running flash, then return to the normal tint.
## Centralised so dash / parry / release cannot leave a stray colour behind.
func reset_player_tint() -> void:
	SpriteFeedback.clear(sprite)
	SpriteFeedback.set_tint(sprite, Color(1, 1, 1))

func try_to_parry():
	if current_state != State.IDLE and current_state != State.RUN: return
	if not can_parry: return 
	
	current_state = State.PARRY
	velocity.x = 0
	velocity.y = 0 
	can_parry = false 
	reset_player_tint() # Drop any charge glow
	
	parry_box.monitoring = true
	parry_timer.start(parry_duration)
	cooldown_timer.start(parry_duration + parry_cooldown)

func _on_parry_box_area_entered(area: Area2D) -> void:
	# --- 1. REMOVED PREMATURE CODE FROM HERE ---
	# The ammo increase and ui update that was here caused the double counting.
	
	if current_state == State.PARRY:
		# Check if it is actually an attack we can parry
		if not area.is_in_group("enemy_attack"):
			return
		
		# --- SUCCESSFUL PARRY LOGIC ---
		cooldown_timer.start(parry_success_cooldown)
		spawn_popup("PARRIED!", Color(0, 1, 1))
		get_tree().call_group("camera", "add_shake", 0.5)
		
		# Check if we were full BEFORE adding ammo (for reflection logic)
		var is_full_spark = (current_ammo == max_ammo)
		
		# Refill Ammo (ONLY HERE)
		current_ammo = min(current_ammo + 2, max_ammo)
		update_ui()
		
		# Visuals
		spark_fire.restart() 
		SpriteFeedback.flash(sprite, Color(0, 1, 1), 1.0, 0.12) # Cyan parry spark
		shake_ui()
		frame_freeze(0.1, 0.05)
		
		# Handle the enemy reaction
		if area.has_method("get_parried"):
			area.get_parried(is_full_spark)
		elif area.has_meta("parent_node"):
			var enemy = area.get_meta("parent_node")
			if enemy.has_method("get_parried"):
				enemy.get_parried(is_full_spark)
		
		parry_box.set_deferred("monitoring", false) 
		current_state = State.IDLE

func _on_parry_timer_timeout() -> void:
	parry_box.monitoring = false
	if current_state == State.PARRY:
		current_state = State.RECOVERY
		SpriteFeedback.set_tint(sprite, VULNERABLE_TINT) # Vulnerable Color

func _on_parry_cooldown_timer_timeout() -> void:
	if is_dead: return # A cooldown in flight must not hand the guard back
	can_parry = true
	if current_state == State.RECOVERY:
		current_state = State.IDLE
		reset_player_tint()

# --- HELPERS ---

func take_damage(amount: int):
	if is_dead: return
	
	# Dash i-frames beat everything, including the recovery penalty.
	if current_state == State.DASH:
		spawn_popup("DODGE!", Color(0.4, 0.8, 1.0))
		return
	
	# Immunity window: a single bullet must not empty three hearts.
	if invuln_timer > 0.0: return
	
	# Landing a parry leaves you wide open, so getting hit there hurts double.
	if current_state == State.RECOVERY:
		amount *= 2
	
	# A hit can knock the last heart off even mid-recovery, so clamp here and
	# let die() run rather than bailing out partway through the feedback.
	hp = max(hp - amount, 0)
	invuln_timer = invuln_time
	update_ui()
	spawn_popup("-%d" % amount, Color(1, 0.4, 0.4))
	# Red hit flash, layered over whatever tint the current state owns.
	SpriteFeedback.flash(sprite, Color(1, 0.25, 0.25), 1.0, 0.15)
	get_tree().call_group("camera", "add_shake", 0.4)
	frame_freeze(0.1, 0.05)
	
	if hp <= 0:
		die()

func tick_invuln_blink(delta: float) -> void:
	if invuln_timer <= 0.0:
		sprite.visible = true
		return
	invuln_timer -= delta
	# Blink at ~12Hz so the player can read the sprite position.
	sprite.visible = fmod(invuln_time - invuln_timer, 0.16) > 0.08

func die() -> void:
	if is_dead: return
	is_dead = true
	hp = 0
	current_state = State.DEAD
	
	# Drop the player's guard so nothing keeps hitting a corpse.
	parry_box.monitoring = false
	parry_box.monitorable = false
	can_parry = false
	can_dash = false
	clear_recoil()
	velocity = Vector2.ZERO
	sprite.visible = true
	reset_player_tint()
	update_ui()
	
	get_tree().call_group("camera", "add_shake", 0.8)
	frame_freeze(0.2, 0.35)
	
	var result_screen = get_tree().get_first_node_in_group("result_screen")
	if result_screen and result_screen.has_method("show_result"):
		result_screen.show_result(false)

func try_to_heal() -> void:
	if is_dead: return
	
	if hp >= max_hp:
		spawn_popup("HP FULL", Color(0.5, 1, 0.5))
		return
	
	if current_ammo < heal_cost:
		spawn_popup("NEED %d SPARKS!" % heal_cost, Color(1, 0.7, 0.2))
		return
	
	current_ammo -= heal_cost
	hp = min(hp + 1, max_hp)
	update_ui()
	spawn_popup("+1 HP", Color(0.4, 1, 0.5))
	heal_fire.restart()
	# Green flash so the heal reads on the player itself, not just the particles.
	SpriteFeedback.flash(sprite, Color(0.4, 1, 0.5), 1.0, 0.25)
	frame_freeze(0.3, 0.08)
	get_tree().call_group("camera", "add_shake", 0.2)

## Build the pip rows to match max_hp / max_ammo. Called on ready and whenever
## those values change at runtime, so the HUD is never hardcoded to 3 and 6.
func rebuild_hud() -> void:
	_fill_pip_row(health_row, health_pips, max_hp, PIP_LIT)
	_fill_pip_row(spark_row, spark_pips, max_ammo, SPARK_LIT)
	label_heal.text = "[Q] HEAL %d" % heal_cost

func _fill_pip_row(row: HBoxContainer, pips: Array[ColorRect], count: int, lit: Color) -> void:
	for child in row.get_children():
		child.queue_free()
	pips.clear()
	
	for i in count:
		var pip := ColorRect.new()
		pip.color = lit if i < count else PIP_EMPTY
		pip.custom_minimum_size = Vector2(24, 14)
		pip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		row.add_child(pip)
		pips.append(pip)

func update_ui():
	# 0. HEALTH PIPS
	for i in health_pips.size():
		health_pips[i].color = PIP_LIT if i < hp else PIP_EMPTY
	
	# 0b. SPARK PIPS
	for i in spark_pips.size():
		spark_pips[i].color = SPARK_LIT if i < current_ammo else SPARK_EMPTY
	
	# 1. TEXT LOGIC
	if current_ammo == max_ammo:
		label_spark.text = "SPARK MAX"
		label_spark.modulate = Color(0, 1, 1) # Cyan
	else:
		label_spark.text = "SPARK %d/%d" % [current_ammo, max_ammo]
		label_spark.modulate = Color(1, 1, 1) # White
	
	# 1b. HEAL HINT
	# Brightens once a heal is actually affordable, so the cost is discoverable
	# without needing a popup every time the player wonders.
	var can_heal := not is_dead and hp < max_hp and current_ammo >= heal_cost
	label_heal.modulate = Color(0.5, 1, 0.6, 1) if can_heal else Color(0.5, 0.5, 0.55, 1)
	
	# 2. FIRE LOGIC
	if current_ammo == 0:
		spark_fire.emitting = false
	else:
		spark_fire.emitting = true
		
		var intensity = float(current_ammo) / float(max_ammo)
		spark_fire.amount_ratio = intensity
		
		# Get the material
		var mat = spark_fire.process_material as ParticleProcessMaterial
		mat.scale_min = 0.5 + (intensity * 0.5)
		
		# --- SAFER GRADIENT CHECK ---
		# We ensure the texture exists and is the right type
		var tex = mat.color_ramp as GradientTexture1D
		
		if tex and tex.gradient:
			var grad = tex.gradient
			if current_ammo == max_ammo:
				grad.set_color(0, Color(0, 1, 1)) 
				grad.set_color(1, Color(0, 0, 1))
				if not was_max_ammo:
					was_max_ammo = true
					spark_fire.amount_ratio = 1.0 
					spark_fire.restart() 
					spawn_popup("MAX CHARGE!", Color(0, 1, 1))
					get_tree().call_group("camera", "add_shake", 0.2)
			else:
				was_max_ammo = false
				grad.set_color(0, Color(0.9, 0.6, 0.0))
				grad.set_color(1, Color(0.9, 0.2, 0.1))

func frame_freeze(time_scale, duration):
	# TimeControl owns Engine.time_scale so that overlapping freezes (a rapid
	# double parry, or a parry during the boss cinematic) cannot cancel out.
	var token = TimeControl.hold(time_scale)
	# ignore_time_scale = true so `duration` is real seconds, not scaled ones.
	await get_tree().create_timer(duration, true, false, true).timeout
	TimeControl.release(token)

func spawn_popup(text, color):
	var popup = popup_scene.instantiate()
	# Parented to the world, not the player, so the popup stays put instead of
	# being dragged along by a dash.
	get_parent().add_child(popup)
	popup.global_position = global_position
	popup.setup(text, color)

func shake_ui():
	# Guard: if a parry lands before the initial layout has settled, there is no
	# rest position to return to yet. The HUD simply does not punch this once.
	if not _hud_rest_captured:
		update_ui()
		return
	
	# Kill any shake still in flight and hard-reset first. Overlapping parries
	# interrupt each other constantly, and a killed tween never runs its own
	# restore step, so without this the HUD is left mid-shake.
	_cancel_hud_shake()
	
	var tween = create_tween()
	_hud_shake_tween = tween
	
	# Flash the spark readout cyan on a successful parry.
	label_spark.modulate = Color(0, 1, 1) 
	
	# The HUD root is anchored to the viewport, so it can be scaled about its
	# own centre. Pivot is set from the live size each time so the punch stays
	# centred at any window size.
	hud_root.pivot_offset = hud_root.size * 0.5
	
	tween.set_parallel(true)
	tween.tween_property(hud_root, "scale", Vector2(1.06, 1.06), 0.05)
	
	# Small positional shake. This targets LeftColumn rather than a nested row:
	# children of a Container have their positions rewritten on every layout
	# pass, so tweening one would fight the container and snap back.
	#
	# The rest position is captured ONCE after the first layout, never re-read
	# mid-shake. Reading it at the start of each shake compounded the error:
	# an interrupted shake left the column displaced, the next shake captured
	# that displaced value as "rest", and the drift accumulated every parry.
	for i in range(4):
		var offset := Vector2(randf_range(-5, 5), randf_range(-3, 3))
		tween.tween_property(hud_column, "position", hud_rest_pos + offset, 0.05)
	
	# Return to normal
	tween.chain().tween_property(hud_root, "scale", Vector2.ONE, 0.1)
	tween.chain().tween_property(hud_column, "position", hud_rest_pos, 0.1)
	tween.chain().tween_callback(_finish_hud_shake)

func _cancel_hud_shake() -> void:
	if _hud_shake_tween != null and _hud_shake_tween.is_valid():
		_hud_shake_tween.kill()
	_hud_shake_tween = null
	hud_column.position = hud_rest_pos
	hud_root.scale = Vector2.ONE

func _finish_hud_shake() -> void:
	_cancel_hud_shake()
	# Re-read the truth from the model rather than assuming white is correct.
	# A parry can max the sparks out, in which case cyan is the right colour.
	if current_ammo == max_ammo:
		label_spark.modulate = Color(0, 1, 1)
	else:
		label_spark.modulate = Color(1, 1, 1)

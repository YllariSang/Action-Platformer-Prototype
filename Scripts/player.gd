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
@export var max_hp: int = 5
## Health does not regenerate on its own. Sparks are the only way back.
@export var heal_cost: int = 2
## How long the heal channel must be held. Long enough that standing still to
## heal is a real commitment next to a 0.8s parry cooldown, short enough to
## still fit between a flier's shots.
@export var heal_duration: float = 0.6
## Peak alpha of the screen flash that marks the camera letting go of a heal.
## Kept low and short on purpose. It is punctuation for the zoom pulling back,
## not an effect the player has to see the fight through, so a value that reads
## as a "wow" on its own would be the wrong instinct here.
@export var heal_flash_alpha: float = 0.22
@export var heal_flash_time: float = 0.28
@export var invuln_time: float = 1.0

@export_category("Movement")
@export var speed: float = 300.0
@export var jump_force: float = -600.0
@export var gravity: float = 1500.0
@export var dash_speed: float = 1000.0
## Seconds before the dash is handed back, counted from the moment it starts.
## The dash itself only lasts DashTimer's 0.2s, so this is the gap that decides
## how often the player can actually cross a gap or close on a flier.
@export var dash_cooldown: float = 0.6
@export var max_jumps: int = 2
@export var wall_jump_push: float = 500.0
@export var wall_slide_speed: float = 100.0
@export var recoil_force: float = 900.0 
@export var recoil_duration: float = 0.2
@export var shot_recoil_mult: float = 0.2
@export var railgun_recoil_mult: float = 0.5
@export var coyote_time: float = 0.15 

# --- STATE MACHINE ---
# STUNNED used to sit in this enum behind a `_physics_process` early return that
# nothing ever assigned, and RUN sat behind two `!= State.RUN` guards that
# nothing ever set. Both were promises the code did not keep: the STUNNED branch
# would have frozen the player permanently the day a stun feature was added,
# and the RUN guards read as "parry and heal work while moving" while actually
# meaning "only while standing still". Neither is written to disk or exported,
# so dropping them from the enum renumbers the rest harmlessly.
#
# Movement is deliberately NOT a state. handle_movement_and_jumps() runs during
# ATTACK, so a state written from it would clobber the shot recovery, and it is
# skipped entirely during PARRY and DASH, so those states have to be the ones
# that decide whether the player is free to act.
enum State { IDLE, ATTACK, PARRY, DASH, RECOVERY, HEALING, DEAD }
var current_state = State.IDLE
var current_ammo: int = 0
var facing_direction: int = 1
var can_parry: bool = true 
var jump_count: int = 0
var can_dash: bool = true
var coyote_timer: float = 0.0 

## Time left on the dash cooldown. Counted down in _physics_process alongside
## coyote_timer and invuln_timer rather than on a Timer node, because it gates a
## single boolean and has to be readable synchronously by the ground contact
## check in the same function.
var _dash_cooldown_left: float = 0.0

# Health
var hp: int = 5
var invuln_timer: float = 0.0
var is_dead: bool = false

## Bumped whenever a heal channel ends, for any reason. The channel coroutine
## holds the token it started with and bails once it no longer matches, which
## is how a hit landing mid-channel stops the heal without the damage code
## having to know that healing is a channel at all.
var _heal_token: int = 0
## Set whenever a channel ends early OR the channel is refused outright (HP full,
## not enough Sparks), cleared only when the heal key is let go.
##
## Without this the channel is polled from _physics_process while the key is
## held, so the frame after any cancel it just started again: nudging the stick
## made the player jitter between standing still and walking, and a hit was
## followed instantly by a fresh channel that the i-frames then made free. The
## refusals need it for a different reason: they only print a popup and return,
## so a held key re-ran them at the physics rate and buried the player under
## identical "HP FULL" text. Now ending or refusing a channel means the player
## has to commit again from a released key.
var _heal_locked: bool = false

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
## Full-screen flash that punctuates the camera pulling back out of a heal.
## Lives under the same screen-space UI layer as the HUD rather than on the
## camera, because a Camera2D is not a CanvasLayer and cannot host a viewport-
## sized overlay itself. See flash_heal_release().
@onready var heal_flash: ColorRect = $UI/HealFlash

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

## The running screen flash, so an overlapping one can be killed rather than
## stacked. Mirrors _hud_shake_tween, for the same reason.
var _heal_flash_tween: Tween = null

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
	# A dead player keeps falling (so the body drops) but takes no input.
	if is_dead:
		tick_invuln_blink(delta)
		return
	
	# Strip the horizontal push applied last frame. Without this it would be
	# read back as part of velocity.x by move_toward() and compound every frame.
	velocity.x -= recoil_applied_x
	recoil_applied_x = 0.0
	
	_dash_cooldown_left = maxf(0.0, _dash_cooldown_left - delta)

	#COYOTE TIME & GRAVITY
	if is_on_floor():
		coyote_timer = coyote_time
		jump_count = 0
		refresh_dash_charge()
	else:
		coyote_timer -= delta
		if current_state != State.DASH:
			if is_on_wall() and velocity.y > 0:
				velocity.y = wall_slide_speed
				refresh_dash_charge()
			else:
				velocity.y += gravity * delta

	#RECOIL DECAY (must run before movement, which reads recoil_x)
	apply_recoil(delta)
	
	#MOVEMENT
	# HEALING is excluded alongside PARRY and DASH: a heal holds the player
	# still, which is the whole cost of it. Gravity still runs above, so the
	# player settles instead of hanging in the air.
	if current_state == State.HEALING:
		velocity.x = 0
	elif current_state != State.DASH and current_state != State.PARRY:
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
	
	if Input.is_action_just_pressed("parry"):
		try_to_parry()
	elif Input.is_action_just_pressed("dash"):
		try_to_dash()
	
	# Heal is polled, not tapped: holding the key runs the channel, and the
	# channel watches for the release itself. It is handled last because it
	# suspends _physics_process while it runs, which would skip anything placed
	# after it on the frame the channel starts. try_to_parry() and try_to_dash()
	# refuse while HEALING, so the parry still cannot ride along with a heal.
	if Input.is_action_pressed("heal"):
		if not _heal_locked:
			try_to_heal()
	else:
		_heal_locked = false

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
			# Gated like every other hand-back, so wall-jumping up a shaft is not
			# a way to chain dashes past the cooldown.
			refresh_dash_charge()
			
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
	# Losing the state has to drop the charge, otherwise releasing the mouse
	# after a dash fires a railgun that was never charged up. The tint is not
	# reset here: those states own sprite.modulate themselves. HEALING joins
	# them so a channel cannot be shot out of, and the Sparks a channel is
	# about to spend are not also being spent on a shot.
	if current_state == State.PARRY or current_state == State.DASH or current_state == State.RECOVERY or current_state == State.HEALING:
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

## Hand the dash back when the player is standing on something solid.
##
## Two things gate it, and both are load-bearing:
##
## The cooldown, or landing would be a free reset. Refreshing the dash on
## contact is what lets it be used mid-air at all; doing that unconditionally
## every frame the player touches ground turns the dash into a 0.2s no-cost
## horizontal burst you can repeat forever, which is exactly as endless as it
## sounds against a flier.
##
## The state check, because a ground dash never leaves the floor: DASH skips
## gravity and zeroes velocity.y, so is_on_floor() stays true for the whole
## 0.2s. Re-granting here un-spent the dash mid-flight, and since the press is
## read as `is_action_just_pressed` a player leaning on the key could restart the
## dash over and over and never once be off the ground.
func refresh_dash_charge() -> void:
	if current_state == State.DASH or _dash_cooldown_left > 0.0:
		return
	can_dash = true

func try_to_dash():
	# DASH refuses itself for the same reason it refuses to re-enter from the
	# contact check: re-dashing mid-flight would reset the velocity and restart
	# the timer, which is an unbounded dash rather than a cooldown.
	# HEALING refuses too: a dash is a free cancel out of a channel, which
	# together with i-frames made healing a no-risk panic button.
	if not can_dash or current_state == State.DASH or current_state == State.PARRY or current_state == State.RECOVERY or current_state == State.HEALING: return
	
	current_state = State.DASH
	can_dash = false 
	# From the start of the dash, not the end, so the cooldown is what the player
	# feels between dashes: dash_cooldown minus the 0.2s the dash itself lasts.
	_dash_cooldown_left = dash_cooldown
	
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
	# IDLE is the only uncommitted state: ATTACK is the shot recovery, PARRY
	# and DASH are the parry itself, and RECOVERY and HEALING are commitments
	# the player has already paid time for. Moving does not gate the parry —
	# velocity is zeroed on the next line — which is why there is no RUN here.
	if current_state != State.IDLE: return
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

## True while the player is inside a parry window, and for the remainder of the
## frame in which a parry succeeded.
##
## The second half matters: a successful parry drops the parry box with
## set_deferred() and moves the state to IDLE immediately, but an enemy hitbox
## that is already overlapping the player can still report a body entry in that
## same physics frame. Reading the state alone let that attack through a moment
## after the player had parried it. Polling the box as well keeps the parry
## authoritative for the whole frame it resolves in.
func is_parrying() -> bool:
	return current_state == State.PARRY or parry_box.monitoring

func take_damage(amount: int):
	if is_dead: return
	
	# Dash i-frames beat everything, including the recovery penalty.
	if current_state == State.DASH:
		spawn_popup("DODGE!", Color(0.4, 0.8, 1.0))
		return
	
	# An open parry is a hard immunity, not just a chance to reflect. Enemy
	# hitboxes and bullets both deliver damage through this function, so gating
	# here covers every source in one place — no damage source can be added
	# later that forgets the check. The attack is neither negated nor reflected
	# by this; it simply does not connect, exactly like a whiffed swing would.
	if is_parrying(): return
	
	# Immunity window: a single bullet must not empty the whole health bar.
	if invuln_timer > 0.0: return

	# Landing a parry leaves you wide open, so getting hit there hurts double.
	if current_state == State.RECOVERY:
		amount *= 2
	
	# A hit can knock the last heart off even mid-recovery, so clamp here and
	# let die() run rather than bailing out partway through the feedback.
	hp = max(hp - amount, 0)
	# Being hit interrupts a heal. This is the cost that makes standing still
	# worth something: the channel is only safe in a gap between shots, so
	# healing is something you find an opening for rather than mash on.
	cancel_heal()
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
	#
	# Deferred, not assigned. A lethal bullet hit arrives inside
	# enemy_bullet.gd's `_on_body_entered`, and Godot refuses to change an area's
	# monitoring state from inside a physics signal callback: assigning directly
	# raised "Function blocked during in/out signal" on every death and left the
	# box monitorable. This is the same reason a successful parry drops the box
	# with set_deferred().
	parry_box.set_deferred("monitoring", false)
	parry_box.set_deferred("monitorable", false)
	can_parry = false
	can_dash = false
	# After the state change, so this cannot put the player back into IDLE on
	# its way to DEAD. It still bumps the token and kills the particles.
	#
	# No camera-focus release here, and that is deliberate: a lethal hit always
	# arrives through take_damage(), which calls cancel_heal() while the state is
	# still HEALING, so the focus is already on its way out by the time this
	# runs. Adding a second release would be an unreachable path that reads as
	# if death had its own special case. The invariant that actually holds is
	# simply: a channel ends in _finish_heal() or cancel_heal(), and those two
	# are the only exits, so those two are the only places that release.
	cancel_heal()
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

## Start a heal channel, or refuse to. Polled from _physics_process while the
## heal key is held, so it has to be safe to call every frame.
##
## Holding rather than tapping is the load-bearing decision. A tap would be an
## instant 1 HP for heal_cost Sparks with nothing to lose, and at 2 Sparks that
## is exactly what a successful parry pays: healing was the same HP as a parry
## but with no timing requirement, which quietly made the parry pointless. The
## channel costs time and mobility instead, occupies the key so a parry cannot
## ride along with it, and is interruptible, so committing to it is a decision.
##
## The commitment is the hold, not the stillness. Requiring the stick to be
## already neutral before Q was accepted meant the one moment a heal is most
## tempting -- mid-run, in the open -- was the one moment it could not start, so
## the player had to stop, let go, and start again. HEALING roots the player by
## itself, so a direction held at press time is simply overridden.
##
## The channel is also ground only. That is the same rule seen from the other
## side: the hold is only a commitment because it roots the player somewhere
## they were going to be shot at, and an airborne player has already lost the
## mobility, so the cost is empty and the heal becomes a free 1 HP on the way
## down. See the guard below.
func try_to_heal() -> void:
	if is_dead or current_state == State.HEALING: return

	# Ground only, and checked before the state gate so a heal pressed in the air
	# gets a reason rather than silence. In the air the channel costs the player
	# nothing they still have: HEALING zeroes horizontal velocity and gravity
	# runs regardless, so the "stand still and commit" that is the entire cost
	# of a heal evaporates and 2 Sparks buys 1 HP off any ledge, at any point in
	# a platformer's constant falling. Latches like the refusals below, so
	# holding Q through a fall prints this once instead of every physics tick.
	if not is_on_floor():
		spawn_popup("LAND FIRST", Color(0.6, 0.6, 0.6))
		_heal_locked = true
		return

	# Refuse from every state the player has already committed to, so a heal can
	# never be folded into a dash, a parry, or the recovery penalty. See the note
	# on try_to_parry() for why movement is not one of those states.
	if current_state != State.IDLE: return
	
	# Both refusals latch, for the same reason cancel_heal() does: this is
	# polled from _physics_process every frame the key is down, so an unlatched
	# return re-entered on the very next frame and stacked ~60 identical popups
	# a second over the player. The latch means the reason is shown once per
	# press, and the key has to be released and re-pressed to ask again.
	if hp >= max_hp:
		spawn_popup("HP FULL", Color(0.5, 1, 0.5))
		_heal_locked = true
		return
	
	if current_ammo < heal_cost:
		spawn_popup("NEED %d SPARKS!" % heal_cost, Color(1, 0.7, 0.2))
		_heal_locked = true
		return
	
	_heal_token += 1
	var my_token := _heal_token
	
	current_state = State.HEALING
	# Open the camera's focus here rather than on the first frame of the loop
	# below, so the push-in starts on the press instead of a frame later.
	set_heal_focus(true)
	# Drop any leftover shot recoil, or the channel stands still for its first
	# few frames and then slides.
	clear_recoil()
	velocity = Vector2.ZERO
	heal_fire.emitting = true
	heal_fire.amount_ratio = 0.0
	label_heal.text = "HEALING..."
	label_heal.modulate = Color(0.4, 1, 0.5, 1)
	
	var elapsed := 0.0
	# A direction the player was ALREADY holding when the channel started is
	# deliberately ignored. HEALING roots the player on its own, so pressing Q
	# mid-stride heals without needing a "let go of the stick first" step, which
	# is what made starting one feel like it fought back. Only a FRESH press
	# cancels, and only from the second frame on: without that grace frame,
	# pressing a direction and Q on the same physics tick cancelled the channel
	# on the tick it was born, which looked like the heal simply not working.
	var can_steer := false
	while Input.is_action_pressed("heal") and _heal_token == my_token:
		# Steering away cancels. A heal that follows the player is not a
		# commitment, it is just a slower normal shot.
		if can_steer and (Input.is_action_just_pressed("left") or Input.is_action_just_pressed("right")):
			spawn_popup("CANCELLED", Color(0.6, 0.6, 0.6))
			break
		
		# Fixed step, not get_physics_process_delta_time(): this coroutine resumes
		# from the physics_frame signal rather than from _physics_process, and
		# the delta is not readable in that context, so elapsed would sit at zero
		# and the channel would never finish.
		elapsed += 1.0 / float(Engine.physics_ticks_per_second)
		# The particles fill up as the channel progresses. Cheapest honest
		# progress read available without new art, and it doubles as the tell
		# that a heal is running at all.
		heal_fire.amount_ratio = clampf(elapsed / heal_duration, 0.0, 1.0)
		
		if elapsed >= heal_duration:
			_finish_heal()
			return
		
		await get_tree().physics_frame
		# Past the channel's first frame, a fresh direction press cancels it.
		can_steer = true
	
	# Fell out without completing: released the key, steered off, or something
	# bumped the token (a hit landed).
	cancel_heal()

## The Sparks are charged here, on completion, not on press. A cancelled channel
## therefore costs only the time and the exposure, never the resources, which
## means there is no refund path to get wrong and no way to feel cheated.
func _finish_heal() -> void:
	_heal_token += 1
	current_state = State.IDLE
	set_heal_focus(false)
	
	current_ammo -= heal_cost
	hp = min(hp + 1, max_hp)
	
	heal_fire.emitting = false
	heal_fire.amount_ratio = 0.0
	# Green flash so the heal reads on the player itself, not just the particles.
	SpriteFeedback.flash(sprite, Color(0.4, 1, 0.5), 1.0, 0.25)
	frame_freeze(0.3, 0.08)
	get_tree().call_group("camera", "add_shake", 0.2)
	spawn_popup("+1 HP", Color(0.4, 1, 0.5))
	heal_fire.restart()
	update_ui()

## Abort a channel in progress. Called when the key is released, when the player
## steers away, when a hit lands, and on death. The damage path only has to
## know that healing can be interrupted, not how it works.
func cancel_heal() -> void:
	_heal_token += 1
	if current_state == State.HEALING:
		current_state = State.IDLE
		# Require the key to be released before another channel can start, so an
		# interrupted heal stays interrupted instead of resuming a frame later
		# into the safety of the i-frames that the interrupt just granted.
		_heal_locked = true
		# Gated on actually being HEALING, which is what the state read above
		# does. take_damage() calls cancel_heal() on every hit, so releasing the
		# focus unconditionally would pop a heal flash and pull the camera back
		# in the middle of an ordinary fight with no channel to have opened.
		set_heal_focus(false)
	heal_fire.emitting = false
	heal_fire.amount_ratio = 0.0
	update_ui()

## Drive the camera's heal focus, and flash the screen when it lets go.
##
## The zoom itself lives in camera.gd, walked toward a target rather than
## assigned, so opening and closing are the same kind of slow move. The camera
## is reached by group like every other one, and the flash is owned here because
## the player already owns the screen-space HUD this one sits beside.
##
## Called on the channel's first frame and again from whichever end it takes
## (_finish_heal or cancel_heal), which are the only two exits a channel has.
## The flash therefore marks "the channel ended" and nothing else: finishing,
## steering away, and being hit all punctuate the same way. A lethal hit lands
## here too, on top of its own red hit flash, which is the one case where the
## player never gets to watch the zoom walk back because the result screen
## pauses the tree on the same frame.
func set_heal_focus(active: bool) -> void:
	get_tree().call_group("camera", "set_heal_focus", active)
	if active: return
	flash_heal_release()

## The flash itself. Kills any flash still in flight before starting a new one,
## for the same reason shake_ui() does: a healed-cancelled pair in quick
## succession would otherwise stack two tweens writing the same alpha and leave
## the screen brighter than a single flash is meant to reach.
func flash_heal_release() -> void:
	if _heal_flash_tween != null and _heal_flash_tween.is_valid():
		_heal_flash_tween.kill()
	heal_flash.color.a = heal_flash_alpha
	var tween := create_tween()
	_heal_flash_tween = tween
	tween.tween_property(heal_flash, "color:a", 0.0, heal_flash_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_finish_heal_flash)

func _finish_heal_flash() -> void:
	_heal_flash_tween = null

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
	# without needing a popup every time the player wonders. The text is owned
	# by the channel while one is running, so this leaves it alone then.
	var can_heal := not is_dead and hp < max_hp and current_ammo >= heal_cost
	label_heal.modulate = Color(0.5, 1, 0.6, 1) if can_heal else Color(0.5, 0.5, 0.55, 1)
	if current_state != State.HEALING:
		label_heal.text = "[Q] HEAL %d" % heal_cost
	
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

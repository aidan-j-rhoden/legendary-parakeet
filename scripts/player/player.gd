extends KinematicBody
class_name Player

const CAMERA_ROTATION_SPEED = 0.001
const CAMERA_X_ROT_MIN = -80
const CAMERA_X_ROT_MAX = 80

var camera_x_rot = 0.0
var camera_y_rot = 0.0

var vel = Vector3()
var hvel = Vector2()
var prev_vel = Vector3()
var dir = Vector3()

const GRAVITY = -24.8
const MAX_SPEED = 2
const MAX_SPRINT_SPEED = 6
const JUMP_SPEED = 10
const ACCEL = 5
const SPRINT_ACCEL = 10
const DEACCEL= 5
const AIR_DEACCEL = 1
const MAX_SLOPE_ANGLE = 40
const AIM_HOLD_THRESHOLD = 0.4

# Health
var health setget set_health

# States
var is_grounded = false
var is_sprinting = false
var is_aiming = false
var toggled_aim = false
var current_aim = false
var aiming_timer = 0.0
var is_dead = false
var falling_to_death = false
var is_climbing = false
var is_dancing = false
var is_in_vehicle = false
var weapon_equipped = false

# Aiming
var camera
var target
var crosshair
var camera_target_initial : Vector3
var crosshair_color_initial : Color
var fov_initial
var fov

#HUD
var health_bar: ProgressBar
var kill_counter: Label
var kill_count = 0
var game_timer_label: Label

# Force
const GRAB_DISTANCE = 50
const THROW_FORCE = 100

# Shape
var shape
var shape_orientation

# Animations
var animation_tree : AnimationTree
var animation_state_machine : AnimationNodeStateMachinePlayback

# Sounds
var air_player
var air_sound
var force_player
var force_shoot
var footsteps_player
var footsteps_concrete
var hit_player
var body_splat
var voice_player
var pain_sound

# Gibs
var gibs_scn
var main_scn

# Rays
var ray_ground
var ray_ledge_top
var ray_ledge_front
var ray_vehicles

# Vehicles
var vehicle

# Weapons
var equipped_weapon


func _ready():
	shape = get_node("shape")

	camera = get_node("camera_base/rotation/target/camera")
	target = get_node("camera_base/rotation/target")
	crosshair = get_node("hud/crosshair")
	kill_counter = $hud/kill_count
	health_bar = $hud/health
	game_timer_label = $hud/game_timer_label

	camera_target_initial = target.transform.origin
	crosshair_color_initial = crosshair.modulate
	fov_initial = camera.fov

	# For facing direction
	shape_orientation = shape.global_transform

	# Animations
	animation_tree = get_node("shape/cube/animation_tree")
	animation_state_machine = animation_tree["parameters/playback"]

	# Sounds
	air_player = get_node("audio/air")
	air_sound = preload("res://sounds/physics/wind.wav")
	air_player.stream = air_sound
	force_player = get_node("audio/force")
	force_shoot = preload("res://sounds/force/force_shoot.wav")
	footsteps_player = get_node("audio/footsteps")
	footsteps_concrete = [
		preload("res://sounds/footsteps/concrete/concrete_1.wav"),
		preload("res://sounds/footsteps/concrete/concrete_2.wav"),
		preload("res://sounds/footsteps/concrete/concrete_3.wav"),
		preload("res://sounds/footsteps/concrete/concrete_4.wav"),
		preload("res://sounds/footsteps/concrete/concrete_5.wav"),
		preload("res://sounds/footsteps/concrete/concrete_6.wav"),
		preload("res://sounds/footsteps/concrete/concrete_7.wav")
	]
	hit_player = get_node("audio/hit")
	body_splat = preload("res://sounds/physics/body_splat.wav")
	voice_player = get_node("audio/voice")
	pain_sound = preload("res://sounds/pain/pain.wav")

	# Gibs
	gibs_scn = preload("res://models/characters/gibs.tscn")
	main_scn = get_tree().root.get_child(get_tree().root.get_child_count() - 1)

	# Health
	set_health(100)

	# Rays
	ray_ground = get_node("shape/rays/ground")
	ray_ledge_front = get_node("shape/rays/ledge_front")
	ray_ledge_top = get_node("shape/rays/ledge_top")
	ray_vehicles = get_node("shape/rays/vehicles")

	if is_network_master():
		camera.current = true
		crosshair.visible = true


func _init():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _physics_process(delta):
	if not is_dead and Input.is_action_just_pressed("damage"): #Debug only
		rpc("hurt", 10)
	health_bar.value = health
	kill_counter.text = str(kill_count)
	game_timer_label.text = get_time_left()
	if is_network_master(): # None of this block runs (for future un-caffinated me)
		if not is_dead:
			process_input(delta)
		if !is_in_vehicle and not is_dead:
			process_movement(delta)
		rpc_unreliable("process_animations", is_in_vehicle, is_grounded, is_climbing, is_dancing, is_aiming, weapon_equipped, hvel.length(), camera_x_rot, camera_y_rot)
		rpc("check_weapons")
	if global_transform.origin.y < -12:
		falling_to_death = true
		rpc("die")


func _input(event):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		get_node("camera_base").rotate_y(-event.relative.x * CAMERA_ROTATION_SPEED)
		get_node("camera_base").orthonormalize()
		camera_x_rot = clamp(camera_x_rot + event.relative.y * CAMERA_ROTATION_SPEED, deg2rad(CAMERA_X_ROT_MIN), deg2rad(CAMERA_X_ROT_MAX))
		camera_y_rot = clamp(camera_y_rot + event.relative.x * CAMERA_ROTATION_SPEED, deg2rad(CAMERA_X_ROT_MIN), deg2rad(CAMERA_X_ROT_MAX))
		get_node("camera_base/rotation").rotation.x = camera_x_rot


func process_input(delta):
	# Walking
	dir = Vector3()
	var cam_xform = get_node("camera_base/rotation/target/camera").global_transform

	var input_movement_vector = Vector2()

	if !is_climbing and !is_dead:
		if Input.is_action_pressed("movement_forward"):
			input_movement_vector.y += 1
		if Input.is_action_pressed("movement_backward"):
			input_movement_vector.y -= 1
		if Input.is_action_pressed("movement_left"):
			input_movement_vector.x -= 1
		if Input.is_action_pressed("movement_right"):
			input_movement_vector.x += 1

		input_movement_vector = input_movement_vector.normalized()

		# Basis vectors are already normalized.
		dir += -cam_xform.basis.z * input_movement_vector.y
		dir += cam_xform.basis.x * input_movement_vector.x

		# Sprinting
		if Input.is_action_pressed("sprint"):
			is_sprinting = true
		else:
			is_sprinting = false

		# Jumping
		if is_grounded:
			if Input.is_action_just_pressed("jump"):
				vel.y = JUMP_SPEED

		# Dancing
		if is_grounded:
			if Input.is_action_pressed("dance"):
				is_dancing = true
			if Input.is_action_just_released("dance"):
				is_dancing = false

		# Enter vehicle
		if Input.is_action_just_pressed("enter_vehicle"):
			enter_vehicle()

		# Change weapon
		if Input.is_action_just_released("next_weapon"):
			rpc("toggle_weapon")

		# Dealing with weapons
		if equipped_weapon != null:
			if weapon_equipped:
				if Input.is_action_just_pressed("lmb") and is_aiming:
					equipped_weapon.rpc("fire")
				if Input.is_action_just_pressed("reload"):
					equipped_weapon.rpc("reload")
				if Input.is_action_just_pressed("drop"):
					equipped_weapon.rpc("drop")

		# Aiming
		var camera_target = camera_target_initial
		var crosshair_alpha = 0.0
		fov = fov_initial

		current_aim = false

		if Input.is_action_just_released("rmb") and aiming_timer <= AIM_HOLD_THRESHOLD:
			current_aim = true
			toggled_aim = true
		else:
			current_aim = toggled_aim or Input.is_action_pressed("rmb")
			if Input.is_action_just_pressed("rmb"):
				toggled_aim = false

		if current_aim:
			aiming_timer += delta
		else:
			aiming_timer = 0.0

		if is_aiming != current_aim:
			is_aiming = current_aim
		if is_aiming and weapon_equipped and equipped_weapon:
			crosshair_alpha = 1.0
			fov = equipped_weapon.fov
			if is_in_vehicle:
				camera.translation = Vector3(0.5, -0.1, 0.2)
				camera_target.z = 0.5
			else:
				camera_target.x = -1.25
		elif !is_aiming and is_in_vehicle:
			camera.translation = Vector3(0, 0, 5)

		target.transform.origin.x += (camera_target.x - target.transform.origin.x) * 0.15
		target.transform.origin.z += (camera_target.z - target.transform.origin.z) * 0.15
		crosshair.modulate.a += (crosshair_alpha - crosshair.modulate.a) * 0.15
		camera.fov += (fov - camera.fov) * 0.15

		# Force
		if is_aiming:
			if !weapon_equipped:
				var space_state = get_world().direct_space_state
				var center_position = get_viewport().size / 2
				var ray_from = camera.project_ray_origin(center_position)
				var ray_to = ray_from + camera.project_ray_normal(center_position) * GRAB_DISTANCE
				var ray_result = space_state.intersect_ray(ray_from, ray_to, [self])
				if ray_result:
					if ray_result.collider:
						var body = ray_result.collider
						if body is RigidBody:
							if Input.is_action_just_pressed("lmb") and is_grounded:
								force_player.stream = force_shoot
								force_player.play()
								body.apply_impulse(Vector3(0, 0, 0), -camera.global_transform.basis.z.normalized() * THROW_FORCE)

	# Slow Mo
	if Input.is_action_pressed("slowmo"):
		Engine.time_scale = 0.25
		AudioServer.set_bus_effect_enabled(0, 0, true)
		AudioServer.get_bus_effect(0, 0).pitch_scale = 0.25
	else:	
		Engine.time_scale = 1
		AudioServer.get_bus_effect(0, 0).pitch_scale = 1
		AudioServer.set_bus_effect_enabled(0, 0, false)

	# Cursor
	if Input.is_action_just_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func process_movement(delta):
	# Ground detection
	if ray_ground.is_colliding() == true:
		is_grounded = true
	else:
		is_grounded = false

	# Movement
	dir.y = 0
	dir = dir.normalized()

	if !falling_to_death:
		vel.y += delta * GRAVITY
	else:
		vel.y = 0

	hvel = vel
	hvel.y = 0

	var target = dir
	if is_sprinting:
		target *= MAX_SPRINT_SPEED
	else:
		target *= MAX_SPEED

	var accel
	if dir.dot(hvel) > 0:
		if is_sprinting:
			accel = SPRINT_ACCEL
		else:
			accel = ACCEL
	else:
		if is_grounded:
			accel = DEACCEL
		else:
			accel = AIR_DEACCEL

	hvel = hvel.linear_interpolate(target, accel * delta)
	vel.x = hvel.x
	vel.z = hvel.z

	vel = move_and_slide(vel, Vector3.UP, 0.05, 4, deg2rad(MAX_SLOPE_ANGLE))
	# Face moving direction
	if dir.dot(hvel) > 0:
		var quat_from = Quat(shape_orientation.basis)
		var quat_to = Quat(Transform().looking_at(-dir, Vector3.UP).basis)
		shape_orientation.basis = Basis(quat_from.slerp(quat_to, delta * 10))
		shape.rotation.y = shape_orientation.basis.get_euler().y

	# Ledge detection
	if ray_ledge_front.is_colliding():
		ray_ledge_top.enabled = true
		if ray_ledge_top.is_colliding():
			var ledge_point = ray_ledge_top.get_collision_point() + Vector3(0, 0.5, 0)
			if Input.is_action_just_pressed("jump"):
				is_grounded = true
				is_climbing = true
				vel.y = 0
				hvel = Vector2.ZERO
				global_transform.origin = ledge_point
	else:
		ray_ledge_top.enabled = false

	# Sounds
	air_player.unit_size = vel.length() / 30
	if !air_player.playing:
		air_player.play()

	if (vel.length() - prev_vel.length()) < -20:
		rpc("hurt", 50)
	if (vel.length() - prev_vel.length()) < -40:
		rpc("die")

	prev_vel = vel

	# Network
#	rpc_unreliable("update_trans_rot", translation, rotation, shape.rotation)


# Check for weapons
remotesync func check_weapons():
	var weapons = get_node("shape/cube/root/skeleton/bone_attachment/weapon").get_children()
	if weapons.size() > 0:
		equipped_weapon = weapons[0]
	else:
		equipped_weapon = null
	var id = get_tree().get_rpc_sender_id()
	for player in gamestate.players:
		if player != id:
			rpc_id(player, "check_weapons")


remotesync func toggle_weapon():
	if equipped_weapon != null:
		if weapon_equipped == true:
			weapon_equipped = false
			get_node("shape/cube/root/skeleton/bone_attachment/weapon").visible = false
		else:
			weapon_equipped = true
			get_node("shape/cube/root/skeleton/bone_attachment/weapon").visible = true
		var id = get_tree().get_rpc_sender_id()
		for player in gamestate.players:
			if player != id:
				rpc_id(player, "check_weapons")


# Entering vehicle
remotesync func enter_vehicle():
	if !is_in_vehicle:
		if ray_vehicles.is_colliding():
			if ray_vehicles.get_collider() is VehicleBody and ray_vehicles.get_collider().driver == -1:
				if ray_vehicles.get_collider().name == "truck_auto":
					vehicle = ray_vehicles.get_collider()
					vehicle.set_driver(get_network_master())
					voice_player.stream = pain_sound #Temp
					voice_player.play()
					for player in gamestate.players:
						if player != str(get_tree().get_rpc_sender_id()):
							rpc_id(player, "enter_vehicle")
				else:
					for player in gamestate.players:
						if player != get_tree().get_rpc_sender_id():
							rpc_id(player, "enter_vehicle")
					#camera.translation = Vector3(0.5, -0.1, 0.2) #Edit this
					camera.translation = Vector3(0, 0, 5)
					vehicle = ray_vehicles.get_collider()
					get_parent().remove_child(self)
					vehicle.add_child(self)
					self.add_collision_exception_with(vehicle)

					global_transform.origin = vehicle.transform.origin + vehicle.transform.basis.x * 0.5 + vehicle.transform.basis.y * 1.75

					vehicle.set_driver(get_network_master())
#					vehicle.set_network_master(int(self.get_name()))
					shape.rotation.y = vehicle.get_node("body").transform.basis.get_euler().y

					is_in_vehicle = true
					# Temporary
					camera.clip_to_bodies = false
	else:
		if vehicle.name != "truck_auto":
			for player in gamestate.players:
				if player != get_tree().get_rpc_sender_id():
					rpc_id(player, "enter_vehicle")
			self.remove_collision_exception_with(vehicle)
			animation_state_machine.travel("blend_tree")
			get_parent().remove_child(self)
			main_scn.get_node("players").add_child(self)
			camera.translation = Vector3(0, 0, 2)

			global_transform.origin = vehicle.transform.origin + vehicle.transform.basis.x * 2 + vehicle.transform.basis.y * 1
			shape.rotation.y = vehicle.transform.basis.get_euler().y

			vel = vehicle.linear_velocity * 1.5

			vehicle.driver = -1
			vehicle = null
			is_in_vehicle = false
			# Temporary
			camera.clip_to_bodies = true
		else:
			vehicle.driver = -1
			vehicle = null
			is_in_vehicle = false
			for player in gamestate.players:
				if player != get_tree().get_rpc_sender_id():
					rpc_id(player, "enter_vehicle")


# Animations
remotesync func process_animations(is_in_vehicle, is_grounded, is_climbing, is_dancing, is_aiming, pistol_equipped, hvel_length, camera_x_rot, camera_y_rot):
	var id = get_tree().get_rpc_sender_id()
	for player in gamestate.players:
		if id != player:
			rpc_id(player, "process_animations", is_in_vehicle, is_grounded, is_climbing, is_dancing, is_aiming, pistol_equipped, hvel_length, camera_x_rot, camera_y_rot)
	if is_in_vehicle:
		animation_state_machine.travel("car_drive")
	else:
		animation_tree["parameters/blend_tree/locomotion/idle_walk_run/blend_position"] = hvel_length
		if !is_grounded and !is_on_floor():
			animation_state_machine.travel("fall")
		else:
			if is_climbing:
				animation_state_machine.travel("climb")
			else:
				if !is_dancing:
					animation_state_machine.travel("blend_tree")
				else:
					animation_state_machine.travel("dance")

	if is_aiming:
		if weapon_equipped:
			animation_tree["parameters/blend_tree/pistol_aim_blend/blend_amount"] = 1
			animation_tree["parameters/blend_tree/pistol_aim_dir_x_blend/blend_amount"] = -camera_x_rot
			animation_tree["parameters/blend_tree/pistol_aim_dir_y_blend/blend_amount"] = camera_y_rot
		else:
			animation_tree["parameters/blend_tree/aim_blend/blend_amount"] = 1
			animation_tree["parameters/blend_tree/aim_dir_x_blend/blend_amount"] = -camera_x_rot
			animation_tree["parameters/blend_tree/aim_dir_y_blend/blend_amount"] = camera_y_rot
	else:
		if weapon_equipped:
			animation_tree["parameters/blend_tree/pistol_aim_blend/blend_amount"] = 0
		else:
			animation_tree["parameters/blend_tree/aim_blend/blend_amount"] = 0


func set_is_climbing(value):
	is_climbing = value
	rpc("update_is_climbing", value)


remotesync func update_is_climbing(value):
	is_climbing = value

 
# Sync position and rotation in the network
remote func update_trans_rot(pos, rot, shape_rot):
	var id = get_tree().get_rpc_sender_id()
#	if self.get_name() == str(id):
#		translation = pos
#		rotation = rot
#		shape.rotation = shape_rot
	translation = pos
	rotation = rot
	shape.rotation = shape_rot
	for player in gamestate.players:
		if player != id:
			rpc_unreliable_id(player, "update_trans_rot", translation, rotation, shape.rotation)


func play_random_footstep():
	footsteps_player.unit_size = vel.length()
	footsteps_player.stream = footsteps_concrete[randi() % footsteps_concrete.size()]
	footsteps_player.play()


remotesync func hurt(damage):
	set_health(health - damage)
	voice_player.stream = pain_sound
	voice_player.play()


remotesync func die():
	if !is_dead:
		kill_count -= 1
		if is_in_vehicle:
			enter_vehicle()
		hit_player.stream = body_splat
		hit_player.play()

#		current_aim = false
#		is_aiming = false
#		toggled_aim = false
#		aiming_timer = 0.0
#		camera_target_initial = target.transform.origin
#		fov_initial = camera.fov
#		crosshair.modulate.a = 0.0

		visible = false
		if not falling_to_death:
			# Gibs
			var gibs = gibs_scn.instance()
			main_scn.add_child(gibs)
			gibs.global_transform.origin = global_transform.origin
			for c in gibs.get_children():
				c.apply_impulse(global_transform.origin, c.global_transform.origin - global_transform.origin * 1.1)

		is_dead = true
		get_node("timer_respawn").start()
	var id = get_tree().get_rpc_sender_id()
	for player in gamestate.players:
		if player != id:
			rpc_id(player, "die")


func set_health(value):
	health = value
	if health <= 0:
		rpc("die")


func get_time_left():
	var time_seconds: String
	time_seconds = str(("%1.0f" % main_scn.get_node("game_timer").time_left))
	var result = (int(time_seconds) / 60)
	var result2 = int(time_seconds) - (result * 60)
	if result2 < 10:
		result2 = "0" + str(result2)
	return str(result) + ":" + str(result2)


# Respawn
func _on_timer_respawn_timeout():
	rpc("respawn")


remotesync func respawn():
	falling_to_death = false
	is_dead = false
	set_health(100)
	vel = Vector3(0, 0, 0)
	visible = true
	for i in self.get_children():
		if i is Wound:
			i.queue_free()
	var id = get_tree().get_rpc_sender_id()
	for player in gamestate.players:
		if id != player:
			rpc_id(player, "respawn")

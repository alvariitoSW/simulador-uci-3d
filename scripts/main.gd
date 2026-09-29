extends Node3D
## Escena principal del prototipo: construye el entorno low-poly, la cabina del
## helicoptero (marco de puerta visible), la camara tipo torreta con arma en pantalla,
## genera oleadas de microorganismos y resuelve el disparo (raycast con dispersion)
## contra el antibiotico equipado. Todo el arbol de nodos se construye por codigo.

@export var spawn_interval: float = 2.2
@export var wave_size: int = 10

const YAW_LIMIT_DEG := 70.0
const PITCH_MIN_DEG := -35.0
const PITCH_MAX_DEG := 18.0
const HIP_FOV := 70.0
const ADS_FOV := 35.0

var _spawn_timer: float = 0.0
var _spawned_count: int = 0
var _hud: GameHUD
var _camera: Camera3D
var _weapon_view: Node3D
var _yaw: float = 0.0
var _pitch: float = 0.0
var _is_aiming: bool = false
var _current_ammo: int = 1
var _is_reloading: bool = false
var _fire_cooldown: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	GameManager.reset_run()
	GameManager.targets_total = wave_size
	GameManager.game_over.connect(_on_game_over)
	GameManager.weapon_changed.connect(_on_weapon_changed)

	_rng.randomize()
	_build_environment()
	_build_camera_rig()
	_build_cockpit()

	_hud = GameHUD.new()
	add_child(_hud)
	_on_weapon_changed(GameManager.current_weapon)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.42, 0.58, 0.55)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.6, 0.6, 0.55)
	environment.ambient_light_energy = 0.6
	env.environment = environment
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.1
	add_child(sun)

	var ground := StaticBody3D.new()
	var ground_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground_mesh.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.22, 0.38, 0.2)
	ground_mesh.material_override = ground_mat
	ground.add_child(ground_mesh)
	var ground_collision := CollisionShape3D.new()
	var ground_shape := BoxShape3D.new()
	ground_shape.size = Vector3(200, 0.1, 200)
	ground_collision.position = Vector3(0, -0.05, 0)
	ground_collision.shape = ground_shape
	ground.add_child(ground_collision)
	add_child(ground)

	_scatter_trees()


func _scatter_trees() -> void:
	var tree_rng := RandomNumberGenerator.new()
	tree_rng.seed = 1234
	for i in range(40):
		var trunk := MeshInstance3D.new()
		var trunk_mesh := CylinderMesh.new()
		trunk_mesh.top_radius = 0.15
		trunk_mesh.bottom_radius = 0.2
		trunk_mesh.height = 2.0
		trunk.mesh = trunk_mesh
		var trunk_mat := StandardMaterial3D.new()
		trunk_mat.albedo_color = Color(0.35, 0.25, 0.15)
		trunk.material_override = trunk_mat

		var canopy := MeshInstance3D.new()
		var canopy_mesh := SphereMesh.new()
		canopy_mesh.radius = 1.1
		canopy_mesh.height = 2.2
		canopy.mesh = canopy_mesh
		canopy.position = Vector3(0, 1.6, 0)
		var canopy_mat := StandardMaterial3D.new()
		canopy_mat.albedo_color = Color(0.15, 0.45, 0.2)
		canopy.material_override = canopy_mat

		var tree := Node3D.new()
		tree.add_child(trunk)
		tree.add_child(canopy)
		var x := tree_rng.randf_range(-45, 45)
		var z := tree_rng.randf_range(-70, -15)
		tree.position = Vector3(x, 0, z)
		add_child(tree)


func _build_camera_rig() -> void:
	_camera = Camera3D.new()
	_camera.position = Vector3(0, 2.2, 6)
	_camera.fov = HIP_FOV
	add_child(_camera)
	_camera.current = true


func _make_box(size: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.material_override = mat
	return mesh_instance


func _build_cockpit() -> void:
	# Marco de la puerta lateral de un helicoptero de transporte, fijo en el espacio
	# del mundo (no rota con la camara) para que se sienta como parte del fuselaje
	# mientras giras la vista dentro de el, igual que en un helicoptero real.
	var rig := Node3D.new()
	rig.position = Vector3(0, 2.2, 6)
	add_child(rig)

	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.18, 0.2, 0.14)

	var interior_mat := StandardMaterial3D.new()
	interior_mat.albedo_color = Color(0.1, 0.11, 0.09)

	var left_pillar := _make_box(Vector3(0.18, 2.6, 0.18), frame_mat)
	left_pillar.position = Vector3(-1.7, 0.2, -0.4)
	rig.add_child(left_pillar)

	var right_pillar := _make_box(Vector3(0.18, 2.6, 0.18), frame_mat)
	right_pillar.position = Vector3(1.7, 0.2, -0.4)
	rig.add_child(right_pillar)

	var top_bar := _make_box(Vector3(3.6, 0.18, 0.18), frame_mat)
	top_bar.position = Vector3(0, 1.5, -0.4)
	rig.add_child(top_bar)

	# Peto/salpicadero inferior, como si estuvieras asomado por la puerta lateral.
	var lower_panel := _make_box(Vector3(3.6, 0.9, 0.3), interior_mat)
	lower_panel.position = Vector3(0, -1.35, -0.3)
	rig.add_child(lower_panel)

	# Soporte del arma de puerta (decorativo).
	var mount := _make_box(Vector3(0.15, 0.5, 0.15), frame_mat)
	mount.position = Vector3(0.5, -0.75, -0.5)
	rig.add_child(mount)


func _build_weapon_view(weapon_id: String) -> void:
	if _weapon_view:
		_weapon_view.queue_free()
		_weapon_view = null

	var rig := Node3D.new()
	rig.position = Vector3(0.32, -0.28, -0.55)
	rig.rotation_degrees = Vector3(0, 8, 0)
	_camera.add_child(rig)
	_weapon_view = rig

	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.08, 0.08, 0.08)

	match weapon_id:
		"vancomicina":
			var body := _make_box(Vector3(0.12, 0.14, 0.35), body_mat)
			rig.add_child(body)
			var barrel := _make_box(Vector3(0.07, 0.07, 0.4), body_mat)
			barrel.position = Vector3(0, 0.0, -0.4)
			rig.add_child(barrel)
		"meropenem":
			var body := _make_box(Vector3(0.16, 0.18, 0.5), body_mat)
			rig.add_child(body)
			var barrel := MeshInstance3D.new()
			var barrel_cyl := CylinderMesh.new()
			barrel_cyl.top_radius = 0.09
			barrel_cyl.bottom_radius = 0.09
			barrel_cyl.height = 0.5
			barrel.mesh = barrel_cyl
			barrel.material_override = body_mat
			barrel.rotation_degrees = Vector3(90, 0, 0)
			barrel.position = Vector3(0, 0.0, -0.5)
			rig.add_child(barrel)
		_: # pip_tazo por defecto
			var body := _make_box(Vector3(0.1, 0.12, 0.55), body_mat)
			rig.add_child(body)
			var barrel := _make_box(Vector3(0.04, 0.04, 0.45), body_mat)
			barrel.position = Vector3(0, 0.02, -0.45)
			rig.add_child(barrel)


func _current_weapon_data() -> Dictionary:
	return GameManager.ANTIBIOTICS.get(GameManager.current_weapon, {})


func _on_weapon_changed(weapon_id: String) -> void:
	_is_reloading = false
	var data: Dictionary = GameManager.ANTIBIOTICS.get(weapon_id, {})
	_current_ammo = data.get("magazine_size", 1)
	_fire_cooldown = 0.0
	_build_weapon_view(weapon_id)
	if _hud:
		_hud.update_ammo(_current_ammo, data.get("magazine_size", 1), false)


func _process(delta: float) -> void:
	_spawn_timer -= delta
	if _spawn_timer <= 0.0 and _spawned_count < wave_size:
		_spawn_timer = spawn_interval
		_spawn_target()
		_spawned_count += 1

	if _fire_cooldown > 0.0:
		_fire_cooldown -= delta

	var target_fov := ADS_FOV if _is_aiming else HIP_FOV
	_camera.fov = lerp(_camera.fov, target_fov, delta * 8.0)


func _spawn_target() -> void:
	var pathogen_ids: Array = GameManager.PATHOGENS.keys()
	var pathogen_id: String = pathogen_ids[_rng.randi_range(0, pathogen_ids.size() - 1)]

	var target := PathogenTarget.new()
	add_child(target)
	var x := _rng.randf_range(-8, 8)
	var z := _rng.randf_range(-40, -20)
	target.setup(pathogen_id, Vector3(x, 1.5, z))
	target.killed.connect(_on_target_killed)
	target.escaped.connect(_on_target_escaped)


func _on_target_killed(was_correct: bool) -> void:
	if not was_correct:
		GameManager.damage_patient(GameManager.PATIENT_DAMAGE_PER_WRONG_KILL)


func _on_target_escaped() -> void:
	GameManager.damage_patient(GameManager.PATIENT_DAMAGE_PER_ESCAPE)
	GameManager.register_kill()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity := 0.0009 if _is_aiming else 0.002
		_yaw = clamp(_yaw - event.relative.x * sensitivity, deg_to_rad(-YAW_LIMIT_DEG), deg_to_rad(YAW_LIMIT_DEG))
		_pitch = clamp(_pitch - event.relative.y * sensitivity, deg_to_rad(PITCH_MIN_DEG), deg_to_rad(PITCH_MAX_DEG))
		_camera.rotation = Vector3(_pitch, _yaw, 0)

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1:
			GameManager.set_weapon("pip_tazo")
		elif event.keycode == KEY_2:
			GameManager.set_weapon("vancomicina")
		elif event.keycode == KEY_3:
			GameManager.set_weapon("meropenem")
		elif event.keycode == KEY_R:
			_try_reload()
		elif event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				_shoot()
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_is_aiming = event.pressed
		_hud.set_aiming(_is_aiming)


func _try_reload() -> void:
	if _is_reloading:
		return
	var mag_size: int = _current_weapon_data().get("magazine_size", 1)
	if _current_ammo >= mag_size:
		return
	_start_reload()


func _start_reload() -> void:
	_is_reloading = true
	var data := _current_weapon_data()
	var reload_time: float = data.get("reload_time", 1.5)
	var mag_size: int = data.get("magazine_size", 1)
	_hud.update_ammo(_current_ammo, mag_size, true)
	await get_tree().create_timer(reload_time).timeout
	# Si el jugador cambio de arma mientras recargaba, _on_weapon_changed ya
	# reseteo el estado: no pisar esa recarga nueva con la de un arma antigua.
	if not _is_reloading:
		return
	_current_ammo = mag_size
	_is_reloading = false
	_hud.update_ammo(_current_ammo, mag_size, false)


func _shoot() -> void:
	if _is_reloading or _fire_cooldown > 0.0:
		return
	if _current_ammo <= 0:
		_try_reload()
		return

	var data := _current_weapon_data()
	_fire_cooldown = data.get("fire_rate", 0.3)
	_current_ammo -= 1
	_hud.update_ammo(_current_ammo, data.get("magazine_size", 1), false)

	var spread_deg: float = data.get("spread_ads_deg", 1.0) if _is_aiming else data.get("spread_hip_deg", 5.0)
	var spread_rad := deg_to_rad(spread_deg)
	var rand_yaw := _rng.randf_range(-spread_rad, spread_rad)
	var rand_pitch := _rng.randf_range(-spread_rad, spread_rad)
	var spread_basis := Basis(Vector3.UP, rand_yaw) * Basis(Vector3.RIGHT, rand_pitch)
	var forward: Vector3 = -_camera.global_transform.basis.z
	var direction: Vector3 = spread_basis * forward

	var space_state := get_world_3d().direct_space_state
	var from := _camera.global_transform.origin
	var to := from + direction * 100.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var result := space_state.intersect_ray(query)
	if result and result.has("collider"):
		var collider = result["collider"]
		if collider is PathogenTarget:
			collider.hit(GameManager.current_weapon)

	if _current_ammo <= 0:
		_start_reload()


func _on_game_over(won: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_hud.show_results(won)

extends Node3D
## Escena principal del prototipo: construye el entorno low-poly, la camara tipo
## torreta, genera oleadas de microorganismos y resuelve el disparo (raycast) contra
## el antibiotico equipado. Todo el arbol de nodos se construye por codigo.

@export var spawn_interval: float = 2.2
@export var wave_size: int = 10

var _spawn_timer: float = 0.0
var _spawned_count: int = 0
var _hud: GameHUD
var _camera: Camera3D
var _yaw: float = 0.0
var _pitch: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	GameManager.reset_run()
	GameManager.targets_total = wave_size
	GameManager.game_over.connect(_on_game_over)

	_rng.randomize()
	_build_environment()
	_build_camera_rig()

	_hud = GameHUD.new()
	add_child(_hud)

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
	_camera.fov = 70
	add_child(_camera)
	_camera.current = true


func _process(delta: float) -> void:
	_spawn_timer -= delta
	if _spawn_timer <= 0.0 and _spawned_count < wave_size:
		_spawn_timer = spawn_interval
		_spawn_target()
		_spawned_count += 1


func _spawn_target() -> void:
	var pathogen_ids: Array = GameManager.PATHOGENS.keys()
	var pathogen_id: String = pathogen_ids[_rng.randi_range(0, pathogen_ids.size() - 1)]

	var target := PathogenTarget.new()
	add_child(target)
	var x := _rng.randf_range(-8, 8)
	var z := _rng.randf_range(-40, -20)
	target.setup(pathogen_id, Vector3(x, 1.5, z))
	target.killed.connect(_on_target_killed)


func _on_target_killed(was_correct: bool) -> void:
	if not was_correct:
		GameManager.damage_patient(GameManager.PATIENT_DAMAGE_PER_WRONG_KILL)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * 0.002
		_pitch = clamp(_pitch - event.relative.y * 0.002, -0.6, 0.3)
		_camera.rotation = Vector3(_pitch, _yaw, 0)

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1:
			GameManager.set_weapon("pip_tazo")
		elif event.keycode == KEY_2:
			GameManager.set_weapon("vancomicina")
		elif event.keycode == KEY_3:
			GameManager.set_weapon("meropenem")
		elif event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_shoot()
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _shoot() -> void:
	var space_state := get_world_3d().direct_space_state
	var from := _camera.global_transform.origin
	var to := from + (-_camera.global_transform.basis.z) * 100.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var result := space_state.intersect_ray(query)
	if result and result.has("collider"):
		var collider = result["collider"]
		if collider is PathogenTarget:
			collider.hit(GameManager.current_weapon)


func _on_game_over(won: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_hud.show_results(won)

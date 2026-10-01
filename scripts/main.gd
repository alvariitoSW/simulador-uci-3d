extends Node3D
## Escena principal del prototipo: construye el entorno low-poly, el helicoptero
## (cabina + arma en pantalla) con balanceo de vuelo continuo, genera oleadas de
## microorganismos con siluetas distintas por categoria, y resuelve el disparo
## (raycast con dispersion, trazadora y fogonazo) contra el antibiotico equipado.
## Todo el arbol de nodos se construye por codigo.

const YAW_LIMIT_DEG := 70.0
const PITCH_MIN_DEG := -55.0
const PITCH_MAX_DEG := 50.0
const HIP_FOV := 70.0
const ADS_FOV := 35.0
const SPAWN_INTERVAL := 1.8
const WAVE_PAUSE_S := 3.0
const HELI_BASE_POS := Vector3(0, 14.0, 6)
const WORLD_SCROLL_SPEED := 3.0
const TREE_FIELD_DEPTH := 120.0
const TREE_RECYCLE_Z := 20.0

var _spawn_timer: float = 0.0
var _wave_spawned_count: int = 0
var _hud: GameHUD
var _heli_rig: Node3D
var _rotor_hub: Node3D
var _tail_rotor_hub: Node3D
var _camera: Camera3D
var _weapon_view: Node3D
var _yaw: float = 0.0
var _pitch: float = 0.0
var _is_aiming: bool = false
var _current_ammo: int = 1
var _is_reloading: bool = false
var _fire_cooldown: float = 0.0
var _flight_time: float = 0.0
var _rng := RandomNumberGenerator.new()
var _scroll_nodes: Array = []


func _ready() -> void:
	GameManager.reset_run()
	GameManager.game_over.connect(_on_game_over)
	GameManager.weapon_changed.connect(_on_weapon_changed)
	GameManager.wave_started.connect(_on_wave_started)
	GameManager.wave_cleared.connect(_on_wave_cleared)

	_rng.randomize()
	_build_environment()
	_build_heli_rig()

	_hud = GameHUD.new()
	add_child(_hud)
	_on_weapon_changed(GameManager.current_weapon)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	GameManager.start_next_wave()


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
	plane.size = Vector2(300, 300)
	ground_mesh.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.22, 0.38, 0.2)
	ground_mesh.material_override = ground_mat
	ground.add_child(ground_mesh)
	var ground_collision := CollisionShape3D.new()
	var ground_shape := BoxShape3D.new()
	ground_shape.size = Vector3(300, 0.1, 300)
	ground_collision.position = Vector3(0, -0.05, 0)
	ground_collision.shape = ground_shape
	ground.add_child(ground_collision)
	add_child(ground)

	_scatter_trees()
	_scatter_ground_patches()


func _scatter_trees() -> void:
	var tree_rng := RandomNumberGenerator.new()
	tree_rng.seed = 1234
	for i in range(70):
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
		var z := tree_rng.randf_range(-100, 15)
		tree.position = Vector3(x, 0, z)
		add_child(tree)
		_scroll_nodes.append(tree)


func _scatter_ground_patches() -> void:
	# Parches de color (campos/claros) en el suelo: sin ellos, el plano verde liso no
	# deja notar que el paisaje se desplaza por debajo mientras vuelas.
	var patch_rng := RandomNumberGenerator.new()
	patch_rng.seed = 777
	var colors := [Color(0.3, 0.42, 0.22), Color(0.26, 0.5, 0.28), Color(0.35, 0.4, 0.2)]
	for i in range(24):
		var patch := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(patch_rng.randf_range(6, 14), 0.05, patch_rng.randf_range(6, 14))
		patch.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colors[i % colors.size()]
		patch.material_override = mat
		var x := patch_rng.randf_range(-60, 60)
		var z := patch_rng.randf_range(-100, 15)
		patch.position = Vector3(x, 0.03, z)
		add_child(patch)
		_scroll_nodes.append(patch)


func _make_box(size: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.material_override = mat
	return mesh_instance


## El helicoptero (cabina + camara) es un unico rig que se balancea con el vuelo;
## la camara solo gira dentro de el para apuntar, como un artillero real.
func _build_heli_rig() -> void:
	_heli_rig = Node3D.new()
	_heli_rig.position = HELI_BASE_POS
	add_child(_heli_rig)

	_camera = Camera3D.new()
	_camera.fov = HIP_FOV
	_heli_rig.add_child(_camera)
	_camera.current = true

	_build_helicopter_shell()


func _dark_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.08, 0.08, 0.08)
	return m


func _build_helicopter_shell() -> void:
	# Helicoptero de transporte completo: cabina cerrada (paredes, techo, suelo),
	# puerta lateral por la que se dispara, rotor principal y de cola, y patines.
	# Todo colgado de _heli_rig, para que se balancee junto con el vuelo.
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.18, 0.2, 0.14)

	var interior_mat := StandardMaterial3D.new()
	interior_mat.albedo_color = Color(0.1, 0.11, 0.09)

	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.24, 0.27, 0.19)

	# --- Puerta lateral (el hueco por el que se dispara) ---
	var left_pillar := _make_box(Vector3(0.22, 3.2, 0.22), frame_mat)
	left_pillar.position = Vector3(-2.1, 0.2, -2.6)
	_heli_rig.add_child(left_pillar)

	var right_pillar := _make_box(Vector3(0.22, 3.2, 0.22), frame_mat)
	right_pillar.position = Vector3(2.1, 0.2, -2.6)
	_heli_rig.add_child(right_pillar)

	var top_bar := _make_box(Vector3(4.4, 0.22, 0.22), frame_mat)
	top_bar.position = Vector3(0, 1.35, -2.6)
	_heli_rig.add_child(top_bar)

	var lower_panel := _make_box(Vector3(4.4, 1.3, 0.5), interior_mat)
	lower_panel.position = Vector3(0, -1.35, -2.4)
	_heli_rig.add_child(lower_panel)

	var mount := _make_box(Vector3(0.18, 0.6, 0.18), frame_mat)
	mount.position = Vector3(0.7, -0.75, -2.5)
	_heli_rig.add_child(mount)

	# --- Cabina cerrada detras de la puerta: paredes, suelo, techo, pared trasera ---
	var left_wall := _make_box(Vector3(0.15, 3.0, 4.6), wall_mat)
	left_wall.position = Vector3(-2.1, 0.2, 0.1)
	_heli_rig.add_child(left_wall)

	var right_wall := _make_box(Vector3(0.15, 3.0, 4.6), wall_mat)
	right_wall.position = Vector3(2.1, 0.2, 0.1)
	_heli_rig.add_child(right_wall)

	var rear_wall := _make_box(Vector3(4.4, 3.0, 0.2), wall_mat)
	rear_wall.position = Vector3(0, 0.2, 2.3)
	_heli_rig.add_child(rear_wall)

	var floor_panel := _make_box(Vector3(4.4, 0.15, 5.0), interior_mat)
	floor_panel.position = Vector3(0, -1.5, -0.2)
	_heli_rig.add_child(floor_panel)

	# Techo partido en dos, con un hueco central para el mastil: al mirar hacia
	# arriba se ve girar el rotor principal por encima de la cabina.
	var ceiling_left := _make_box(Vector3(1.4, 0.15, 5.0), wall_mat)
	ceiling_left.position = Vector3(-1.5, 1.8, -0.2)
	_heli_rig.add_child(ceiling_left)

	var ceiling_right := _make_box(Vector3(1.4, 0.15, 5.0), wall_mat)
	ceiling_right.position = Vector3(1.5, 1.8, -0.2)
	_heli_rig.add_child(ceiling_right)

	_build_rotor()
	_build_tail(wall_mat)
	_build_skids(frame_mat)


func _build_rotor() -> void:
	_rotor_hub = Node3D.new()
	_rotor_hub.position = Vector3(0, 2.4, -0.2)
	_heli_rig.add_child(_rotor_hub)

	var mast := _make_box(Vector3(0.12, 0.7, 0.12), _dark_mat())
	mast.position = Vector3(0, -0.35, 0)
	_rotor_hub.add_child(mast)

	for i in range(2):
		var blade := _make_box(Vector3(6.5, 0.06, 0.45), _dark_mat())
		blade.rotation_degrees = Vector3(0, i * 90.0, 0)
		_rotor_hub.add_child(blade)


func _build_tail(wall_mat: StandardMaterial3D) -> void:
	var boom := MeshInstance3D.new()
	var boom_mesh := CylinderMesh.new()
	boom_mesh.top_radius = 0.3
	boom_mesh.bottom_radius = 0.45
	boom_mesh.height = 4.2
	boom.mesh = boom_mesh
	boom.material_override = wall_mat
	boom.rotation_degrees = Vector3(90, 0, 0)
	boom.position = Vector3(0, 0.3, 4.4)
	_heli_rig.add_child(boom)

	_tail_rotor_hub = Node3D.new()
	_tail_rotor_hub.position = Vector3(0.4, 0.4, 6.4)
	_heli_rig.add_child(_tail_rotor_hub)
	for i in range(2):
		var blade := _make_box(Vector3(1.3, 0.04, 0.22), _dark_mat())
		blade.rotation_degrees = Vector3(0, i * 90.0, 0)
		_tail_rotor_hub.add_child(blade)


func _build_skids(mat: StandardMaterial3D) -> void:
	for side in [-1.0, 1.0]:
		var skid := _make_box(Vector3(0.12, 0.12, 5.2), mat)
		skid.position = Vector3(side * 1.7, -2.4, -0.2)
		_heli_rig.add_child(skid)
		var strut_a := _make_box(Vector3(0.1, 0.9, 0.1), mat)
		strut_a.position = Vector3(side * 1.7, -1.9, -1.9)
		_heli_rig.add_child(strut_a)
		var strut_b := _make_box(Vector3(0.1, 0.9, 0.1), mat)
		strut_b.position = Vector3(side * 1.7, -1.9, 1.5)
		_heli_rig.add_child(strut_b)


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
	var weapon_color: Color = _current_weapon_data().get("color", Color(0.3, 0.3, 0.3))
	body_mat.albedo_color = weapon_color.lightened(0.1)

	match weapon_id:
		"vancomicina":
			var body := _make_box(Vector3(0.12, 0.14, 0.35), body_mat)
			rig.add_child(body)
			var barrel := _make_box(Vector3(0.07, 0.07, 0.4), body_mat)
			barrel.position = Vector3(0, 0.0, -0.4)
			rig.add_child(barrel)
		"anfotericina_b":
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
		"azitromicina":
			var body := _make_box(Vector3(0.08, 0.1, 0.4), body_mat)
			rig.add_child(body)
			var barrel := _make_box(Vector3(0.03, 0.03, 0.3), body_mat)
			barrel.position = Vector3(0, 0.01, -0.35)
			rig.add_child(barrel)
		_: # amoxicilina / ceftriaxona
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
		_hud.set_active_weapon(weapon_id)


func _on_wave_started(current: int, total: int) -> void:
	_wave_spawned_count = 0
	_spawn_timer = 0.0
	if _hud:
		_hud.show_wave(current, total)


func _on_wave_cleared(current: int) -> void:
	if _hud:
		_hud.show_wave_cleared(current)
	await get_tree().create_timer(WAVE_PAUSE_S).timeout
	GameManager.start_next_wave()


func _process(delta: float) -> void:
	_update_flight_bob(delta)
	_update_rotors(delta)
	_scroll_world(delta)

	_spawn_timer -= delta
	if _spawn_timer <= 0.0 and _wave_spawned_count < GameManager.targets_total_this_wave:
		_spawn_timer = SPAWN_INTERVAL
		_spawn_target()
		_wave_spawned_count += 1

	if _fire_cooldown > 0.0:
		_fire_cooldown -= delta

	var target_fov := ADS_FOV if _is_aiming else HIP_FOV
	_camera.fov = lerp(_camera.fov, target_fov, delta * 8.0)

	_update_radar()


func _update_rotors(delta: float) -> void:
	_rotor_hub.rotate_object_local(Vector3.UP, delta * 14.0)
	_tail_rotor_hub.rotate_object_local(Vector3.FORWARD, delta * 22.0)


## Mueve el paisaje (arboles, parches de suelo) hacia la camara y lo recicla al
## pasar por detras, dando la sensacion de que el helicoptero vuela hacia delante
## sin tener que desplazar de verdad al propio helicoptero (y asi toda la logica
## de aparicion/alcance de objetivos sigue siendo relativa a un punto fijo).
func _scroll_world(delta: float) -> void:
	for node in _scroll_nodes:
		node.position.z += WORLD_SCROLL_SPEED * delta
		if node.position.z > TREE_RECYCLE_Z:
			node.position.z -= TREE_FIELD_DEPTH


## Balanceo continuo simulando que el helicoptero esta en vuelo: una ligera subida y
## bajada, cabeceo/alabeo y vibracion de motor, independiente de hacia donde apuntes.
func _update_flight_bob(delta: float) -> void:
	_flight_time += delta
	var bob_y := sin(_flight_time * 1.3) * 0.12 + sin(_flight_time * 5.3) * 0.015
	var sway_x := sin(_flight_time * 0.7) * 0.18
	_heli_rig.position = HELI_BASE_POS + Vector3(sway_x, bob_y, 0)
	_heli_rig.rotation = Vector3(
		sin(_flight_time * 0.9) * deg_to_rad(1.5),
		sin(_flight_time * 0.5) * deg_to_rad(2.5),
		sin(_flight_time * 1.1) * deg_to_rad(2.0)
	)


func _update_radar() -> void:
	if not _hud:
		return
	var points: Array = []
	for child in get_children():
		if child is PathogenTarget:
			var rel: Vector3 = child.global_position - _heli_rig.global_position
			var c := cos(-_yaw)
			var s := sin(-_yaw)
			var local_x := rel.x * c - rel.z * s
			var local_z := rel.x * s + rel.z * c
			points.append(Vector2(local_x, local_z))
	_hud.update_radar(points)


func _spawn_target() -> void:
	var pathogen_ids: Array = GameManager.PATHOGENS.keys()
	var pathogen_id: String = pathogen_ids[_rng.randi_range(0, pathogen_ids.size() - 1)]

	var target := PathogenTarget.new()
	add_child(target)
	var x := _rng.randf_range(-10, 10)
	var y := _rng.randf_range(HELI_BASE_POS.y - 4.0, HELI_BASE_POS.y + 3.0)
	var z := _rng.randf_range(-40, -20)
	target.setup(pathogen_id, Vector3(x, y, z))
	target.killed.connect(_on_target_killed)
	target.escaped.connect(_on_target_escaped)


func _on_target_killed(was_correct: bool, death_position: Vector3) -> void:
	if was_correct:
		_spawn_explosion(death_position, Color(1.0, 0.7, 0.2))
	else:
		GameManager.damage_patient(GameManager.PATIENT_DAMAGE_PER_WRONG_KILL)
		_spawn_explosion(death_position, Color(0.6, 0.6, 0.6))


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
			GameManager.set_weapon(GameManager.WEAPON_ORDER[0])
		elif event.keycode == KEY_2:
			GameManager.set_weapon(GameManager.WEAPON_ORDER[1])
		elif event.keycode == KEY_3:
			GameManager.set_weapon(GameManager.WEAPON_ORDER[2])
		elif event.keycode == KEY_4:
			GameManager.set_weapon(GameManager.WEAPON_ORDER[3])
		elif event.keycode == KEY_5:
			GameManager.set_weapon(GameManager.WEAPON_ORDER[4])
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
	_spawn_muzzle_flash()

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
	var hit_point := to
	if result and result.has("collider"):
		hit_point = result.get("position", to)
		var collider = result["collider"]
		if collider is PathogenTarget:
			collider.hit(GameManager.current_weapon)

	_spawn_tracer(_muzzle_world_position(), hit_point)

	if _current_ammo <= 0:
		_start_reload()


func _muzzle_world_position() -> Vector3:
	if _weapon_view:
		return _weapon_view.global_transform.origin + (-_weapon_view.global_transform.basis.z) * 0.4
	return _camera.global_transform.origin


func _spawn_muzzle_flash() -> void:
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.85, 0.5)
	flash.light_energy = 4.0
	flash.omni_range = 4.0
	add_child(flash)
	flash.global_position = _muzzle_world_position()
	var timer := get_tree().create_timer(0.06)
	timer.timeout.connect(flash.queue_free)


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var dist := from.distance_to(to)
	if dist < 0.05:
		return
	var direction := (to - from).normalized()
	var tracer := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.015
	mesh.bottom_radius = 0.015
	mesh.height = dist
	tracer.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.3)
	mat.emission_energy_multiplier = 2.0
	tracer.material_override = mat
	add_child(tracer)
	var mid := (from + to) / 2.0
	var basis := Basis.looking_at(direction, Vector3.UP).rotated(Vector3.RIGHT, PI / 2.0)
	tracer.global_transform = Transform3D(basis, mid)
	var t := create_tween()
	t.tween_property(mat, "albedo_color:a", 0.0, 0.12)
	t.tween_callback(tracer.queue_free)


func _spawn_explosion(pos: Vector3, color: Color) -> void:
	var particles := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 5.0
	mat.gravity = Vector3(0, -4.0, 0)
	mat.scale_min = 0.1
	mat.scale_max = 0.3
	mat.color = color
	particles.process_material = mat
	var particle_mesh := SphereMesh.new()
	particle_mesh.radius = 0.08
	particle_mesh.height = 0.16
	particles.draw_pass_1 = particle_mesh
	particles.amount = 20
	particles.lifetime = 0.6
	particles.one_shot = true
	particles.explosiveness = 1.0
	add_child(particles)
	particles.global_position = pos
	particles.emitting = true
	var timer := get_tree().create_timer(1.0)
	timer.timeout.connect(particles.queue_free)


func _on_game_over(won: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_hud.show_results(won)

extends Area3D
class_name PathogenTarget
## Un microorganismo objetivo, con una silueta distinta segun su categoria (cluster,
## bacilo con flagelos, cluster espinoso, bola con pinchos, ramificado tipo hongo),
## que avanza lentamente hacia el helicoptero. Se crea enteramente por codigo desde
## main.gd: setup() construye su propia malla, etiqueta y forma de colision.

signal killed(was_correct: bool, death_position: Vector3)
signal escaped

@export var speed: float = 1.2
@export var escape_z: float = 4.5

var pathogen_id: String = ""
var health: float = 30.0
var _material: StandardMaterial3D
var _base_y: float = 0.0
var _time: float = 0.0
var _resolved: bool = false


func setup(p_pathogen_id: String, spawn_position: Vector3) -> void:
	pathogen_id = p_pathogen_id
	position = spawn_position
	_base_y = spawn_position.y
	collision_layer = 2
	collision_mask = 0

	var data: Dictionary = GameManager.PATHOGENS.get(pathogen_id, {})
	_material = StandardMaterial3D.new()
	_material.albedo_color = data.get("color", Color.WHITE)

	var shape: String = data.get("shape", "cluster")
	match shape:
		"rod":
			_build_rod()
		"spiky_cluster":
			_build_spiky_cluster()
		"spiky_ball":
			_build_spiky_ball()
		"branching":
			_build_branching()
		_:
			_build_cluster()

	_add_eyes()

	var label := Label3D.new()
	label.text = String(data.get("label", pathogen_id))
	label.position = Vector3(0, 1.6, 0)
	label.font_size = 40
	label.no_depth_test = true
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

	var collision := CollisionShape3D.new()
	var col_shape := SphereShape3D.new()
	col_shape.radius = 0.85
	collision.shape = col_shape
	add_child(collision)


func _sphere(radius: float, pos: Vector3) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _material
	mesh_instance.position = pos
	add_child(mesh_instance)
	return mesh_instance


func _build_cluster() -> void:
	# Gram+: varios cocos agrupados en racimo, como Staphylococcus.
	var offsets := [
		Vector3(0, 0, 0), Vector3(0.4, 0.15, 0.1), Vector3(-0.35, 0.2, -0.15),
		Vector3(0.1, -0.3, 0.3), Vector3(-0.2, -0.25, -0.3), Vector3(0.05, 0.4, -0.1),
	]
	for off in offsets:
		_sphere(0.38, off)


func _build_rod() -> void:
	# Gram-: bacilo alargado con flagelos finos arrastrando por detras, como E. coli.
	var body := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.32
	mesh.height = 1.4
	body.mesh = mesh
	body.material_override = _material
	body.rotation_degrees = Vector3(90, 0, 0)
	add_child(body)

	for i in range(4):
		var flagellum := MeshInstance3D.new()
		var f_mesh := CylinderMesh.new()
		f_mesh.top_radius = 0.015
		f_mesh.bottom_radius = 0.05
		f_mesh.height = 0.7
		flagellum.mesh = f_mesh
		flagellum.material_override = _material
		var angle := (i - 1.5) * 18.0
		flagellum.rotation_degrees = Vector3(80.0 + angle, 0, angle * 0.5)
		flagellum.position = Vector3((i - 1.5) * 0.12, -0.05, 0.75)
		add_child(flagellum)


func _build_spiky_cluster() -> void:
	# Gram+ resistente (SARM): como el cluster pero mayor, con brillo rojizo de alerta.
	_material.emission_enabled = true
	_material.emission = Color(0.6, 0.05, 0.05)
	_material.emission_energy_multiplier = 0.6

	var offsets := [
		Vector3(0, 0, 0), Vector3(0.5, 0.2, 0.15), Vector3(-0.45, 0.25, -0.2),
		Vector3(0.15, -0.35, 0.4), Vector3(-0.3, -0.3, -0.35), Vector3(0.1, 0.5, -0.1),
		Vector3(0.45, -0.1, -0.4),
	]
	for off in offsets:
		_sphere(0.42, off)


func _build_spiky_ball() -> void:
	# Atipico/intracelular: cuerpo central con bultos puntiagudos alrededor.
	_sphere(0.7, Vector3.ZERO).scale = Vector3(1.0, 0.9, 1.0)
	var bump_positions := [
		Vector3(0.55, 0.35, 0.1), Vector3(-0.55, 0.3, -0.15),
		Vector3(0.1, 0.6, 0.5), Vector3(-0.2, 0.55, -0.45),
		Vector3(0.35, -0.1, -0.55), Vector3(-0.4, -0.2, 0.4),
		Vector3(0.5, -0.4, 0.2), Vector3(-0.1, -0.55, -0.3),
	]
	for pos in bump_positions:
		_sphere(0.17, pos)


func _build_branching() -> void:
	# Hongo: tallo central con ramas y una cabeza mayor arriba, como una pequena colonia.
	var stalk := MeshInstance3D.new()
	var stalk_mesh := CylinderMesh.new()
	stalk_mesh.top_radius = 0.16
	stalk_mesh.bottom_radius = 0.22
	stalk_mesh.height = 1.0
	stalk.mesh = stalk_mesh
	stalk.material_override = _material
	stalk.position = Vector3(0, -0.2, 0)
	add_child(stalk)

	_sphere(0.5, Vector3(0, 0.45, 0))

	var branch_offsets := [Vector3(0.4, 0.0, 0.1), Vector3(-0.4, 0.1, -0.15), Vector3(0.1, -0.1, 0.4)]
	var branch_tilts := [Vector3(0, 0, -55), Vector3(0, 0, 55), Vector3(55, 0, 0)]
	for i in range(branch_offsets.size()):
		var off: Vector3 = branch_offsets[i]
		var branch := MeshInstance3D.new()
		var b_mesh := CylinderMesh.new()
		b_mesh.top_radius = 0.07
		b_mesh.bottom_radius = 0.1
		b_mesh.height = 0.5
		branch.mesh = b_mesh
		branch.material_override = _material
		branch.position = off * 0.6
		branch.rotation_degrees = branch_tilts[i]
		add_child(branch)
		_sphere(0.22, off)


func _add_eyes() -> void:
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.95, 0.95, 0.9)
	var pupil_mat := StandardMaterial3D.new()
	pupil_mat.albedo_color = Color(0.05, 0.05, 0.05)

	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.13
		eye_mesh.height = 0.26
		eye.mesh = eye_mesh
		eye.material_override = eye_mat
		eye.position = Vector3(side * 0.26, 0.1, -0.55)
		add_child(eye)

		var pupil := MeshInstance3D.new()
		var pupil_mesh := SphereMesh.new()
		pupil_mesh.radius = 0.055
		pupil_mesh.height = 0.11
		pupil.mesh = pupil_mesh
		pupil.material_override = pupil_mat
		pupil.position = Vector3(side * 0.26, 0.1, -0.65)
		add_child(pupil)


func _process(delta: float) -> void:
	if _resolved:
		return
	_time += delta
	position.z += speed * delta
	position.y = _base_y + sin(_time * 2.5) * 0.12
	rotation.y += delta * 0.6

	if position.z >= escape_z:
		_escape()


func hit(weapon_id: String) -> void:
	if _resolved:
		return
	var effective: bool = GameManager.is_effective(weapon_id, pathogen_id)
	if effective:
		_die(true)
	else:
		health -= GameManager.WEAK_HIT_DAMAGE
		_flash_weak_hit()
		if health <= 0.0:
			_die(false)


func _flash_weak_hit() -> void:
	if not _material:
		return
	var original := _material.albedo_color
	_material.albedo_color = Color.WHITE
	var t := create_tween()
	t.tween_property(_material, "albedo_color", original, 0.15)


func _die(was_correct: bool) -> void:
	_resolved = true
	killed.emit(was_correct, global_position)
	queue_free()


func _escape() -> void:
	_resolved = true
	escaped.emit()
	queue_free()

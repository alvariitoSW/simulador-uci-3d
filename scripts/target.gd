extends Area3D
class_name PathogenTarget
## Un objetivo (microorganismo) que hay que "disparar" con el antibiotico correcto.
## Se crea enteramente por codigo desde main.gd (no tiene escena .tscn propia):
## setup() construye su propia malla, etiqueta y forma de colision.

signal killed(was_correct: bool)

var pathogen_id: String = ""
var health: float = 30.0
var _material: StandardMaterial3D


func setup(p_pathogen_id: String, spawn_position: Vector3) -> void:
	pathogen_id = p_pathogen_id
	position = spawn_position
	collision_layer = 2
	collision_mask = 0

	var data: Dictionary = GameManager.PATHOGENS.get(pathogen_id, {})

	var mesh_instance := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.6
	mesh.height = 1.6
	mesh_instance.mesh = mesh
	_material = StandardMaterial3D.new()
	_material.albedo_color = data.get("color", Color.WHITE)
	mesh_instance.material_override = _material
	add_child(mesh_instance)

	var label := Label3D.new()
	label.text = String(data.get("label", pathogen_id))
	label.position = Vector3(0, 1.3, 0)
	label.font_size = 48
	label.no_depth_test = true
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.6
	shape.height = 1.6
	collision.shape = shape
	add_child(collision)


func hit(weapon_id: String) -> void:
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
	killed.emit(was_correct)
	queue_free()

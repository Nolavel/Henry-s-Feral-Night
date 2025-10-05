extends Control

@export_group("slots")
@export var Pickup: TextureRect
@export var Melee: TextureRect
@export var Sidearm: TextureRect
@export var Primary_Weapon_Slot_1: TextureRect
@export var Primary_Weapon_Slot_2: TextureRect
@export var Throwable: TextureRect

@export_group("Active Weapon Highlight")
@export var Active_Weapon_Highlight: TextureRect

@export_group("Slot Visibility")
@export var show_sidearm: bool = true : set = _set_show_sidearm
@export var show_pws_1: bool = true : set = _set_show_pws_1
@export var show_pws_2: bool = true : set = _set_show_pws_2
@export var show_throwable: bool = true : set = _set_show_throwable

@export_group("Ammo State")
@export var has_ammo_sidearm: bool = true
@export var has_ammo_pws_1: bool = true
@export var has_ammo_pws_2: bool = true
@export var has_ammo_throwable: bool = true

@export_group("Active Weapon Slot")
@export var aws: TextureRect
@export var aws_array: Array[Texture2D] = []  # сюда вручную в инспекторе добавь 6 других изображений

@export_group("LBL Ammo")
@export var weapon_has_ammo: bool = true
@export var lbl_current_bullets_in_clip: Label
@export var lbl_total_ammo: Label

@export_group("Default State")
@export_enum("Pickup", "Melee", "Sidearm", "PWS1", "PWS2", "Throwable")
var default_active_slot: String = "Pickup"


# позиции
var awh_position_pickup = Vector2(-15, -9)
var awh_position_melee = Vector2(28, -9)
var awh_position_sidearm = Vector2(71, -9)
var awh_position_pws_1 = Vector2(115, -9)
var awh_position_pws_2 = Vector2(161, -9)
var awh_position_throwable = Vector2(204, -9)

# внутренняя логика
var move_time := 0.55
var move_elapsed := 0.0
var start_pos: Vector2
var target_pos: Vector2
var is_moving := false

# текущий активный слот
var current_slot: TextureRect

#func _ready():
	#_update_slot_visibility()
	#target_pos = Active_Weapon_Highlight.position
	#start_pos = target_pos
	#current_slot = Pickup
	#_update_glow()
	#_update_aws_for_slot(current_slot)
	#_update_ammo_labels_visibility()
	
func _ready():
	_update_slot_visibility()

	# Определяем слот по умолчанию
	match default_active_slot:
		"Pickup":
			_set_initial_slot(awh_position_pickup, Pickup)
		"Melee":
			_set_initial_slot(awh_position_melee, Melee)
		"Sidearm":
			_set_initial_slot(awh_position_sidearm, Sidearm)
		"PWS1":
			_set_initial_slot(awh_position_pws_1, Primary_Weapon_Slot_1)
		"PWS2":
			_set_initial_slot(awh_position_pws_2, Primary_Weapon_Slot_2)
		"Throwable":
			_set_initial_slot(awh_position_throwable, Throwable)
		_:
			push_warning("⚠ Unknown default_active_slot value. Using Pickup as fallback.")
			_set_initial_slot(awh_position_pickup, Pickup)

func _set_initial_slot(new_pos: Vector2, slot: TextureRect) -> void:
	current_slot = slot
	target_pos = new_pos
	start_pos = new_pos
	Active_Weapon_Highlight.position = new_pos
	_update_glow()
	
	# 🔧 Сбрасываем glow у активного слота
	if slot and slot.material is ShaderMaterial:
		var mat: ShaderMaterial = slot.material
		var has_ammo := true
		if slot == Sidearm: has_ammo = has_ammo_sidearm
		elif slot == Primary_Weapon_Slot_1: has_ammo = has_ammo_pws_1
		elif slot == Primary_Weapon_Slot_2: has_ammo = has_ammo_pws_2
		elif slot == Throwable: has_ammo = has_ammo_throwable

		if has_ammo:
			mat.set_shader_parameter("glow_intensity", 0.0)
		else:
			mat.set_shader_parameter("glow_color", Color(1,0,0,1))
			mat.set_shader_parameter("glow_intensity", 2.0)

	_update_aws_for_slot(slot)
	_update_ammo_labels_visibility()


func _process(delta: float):
	if is_moving:
		move_elapsed += delta
		var t = clamp(move_elapsed / move_time, 0.0, 1.0)
		Active_Weapon_Highlight.position = start_pos.lerp(target_pos, t)
		if t >= 1.0:
			is_moving = false
			_set_active_slot_glow_off()

func _input(event):
	if event.is_action_pressed("select item slot 1"):
		_set_target(awh_position_pickup, Pickup)
	elif event.is_action_pressed("select item slot 2"):
		_set_target(awh_position_melee, Melee)
	elif event.is_action_pressed("select item slot 3") and show_sidearm:
		_set_target(awh_position_sidearm, Sidearm)
	elif event.is_action_pressed("select item slot 4") and show_pws_1:
		_set_target(awh_position_pws_1, Primary_Weapon_Slot_1)
	elif event.is_action_pressed("select item slot 5") and show_pws_2:
		_set_target(awh_position_pws_2, Primary_Weapon_Slot_2)
	elif event.is_action_pressed("select item slot 6") and show_throwable:
		_set_target(awh_position_throwable, Throwable)

func _set_target(new_pos: Vector2, slot: TextureRect):
	if Active_Weapon_Highlight.position == new_pos:
		return
	start_pos = Active_Weapon_Highlight.position
	target_pos = new_pos
	move_elapsed = 0.0
	is_moving = true
	current_slot = slot
	_update_glow()
	# aws и лейблы обновляем только после завершения анимации

# === Картинка AWS по выбранному слоту ===
func _update_aws_for_slot(slot: TextureRect) -> void:
	if not aws:
		return
	var idx := _slot_to_index(slot)
	if idx >= 0 and idx < aws_array.size() and aws_array[idx]:
		aws.texture = aws_array[idx]

func _slot_to_index(slot: TextureRect) -> int:
	if slot == Pickup: return 0
	if slot == Melee: return 1
	if slot == Sidearm: return 2
	if slot == Primary_Weapon_Slot_1: return 3
	if slot == Primary_Weapon_Slot_2: return 4
	if slot == Throwable: return 5
	return -1

# === Сеттеры для булевых ===
func _set_show_sidearm(value: bool) -> void:
	show_sidearm = value
	if Sidearm:
		Sidearm.modulate.a = 1.0 if value else 0.0

func _set_show_pws_1(value: bool) -> void:
	show_pws_1 = value
	if Primary_Weapon_Slot_1:
		Primary_Weapon_Slot_1.modulate.a = 1.0 if value else 0.0

func _set_show_pws_2(value: bool) -> void:
	show_pws_2 = value
	if Primary_Weapon_Slot_2:
		Primary_Weapon_Slot_2.modulate.a = 1.0 if value else 0.0

func _set_show_throwable(value: bool) -> void:
	show_throwable = value
	if Throwable:
		Throwable.modulate.a = 1.0 if value else 0.0

# === Массовое обновление при старте ===
func _update_slot_visibility():
	_set_show_sidearm(show_sidearm)
	_set_show_pws_1(show_pws_1)
	_set_show_pws_2(show_pws_2)
	_set_show_throwable(show_throwable)

# === Обновление glow_intensity и glow_color ===
func _update_glow():
	var slots := [Pickup, Melee, Sidearm, Primary_Weapon_Slot_1, Primary_Weapon_Slot_2, Throwable]
	for s in slots:
		if not s: 
			continue
		if s.material is ShaderMaterial:
			var mat: ShaderMaterial = s.material
			var has_ammo := true
			if s == Sidearm: has_ammo = has_ammo_sidearm
			elif s == Primary_Weapon_Slot_1: has_ammo = has_ammo_pws_1
			elif s == Primary_Weapon_Slot_2: has_ammo = has_ammo_pws_2
			elif s == Throwable: has_ammo = has_ammo_throwable

			if not has_ammo:
				mat.set_shader_parameter("glow_color", Color(1,0,0,1))
				mat.set_shader_parameter("glow_intensity", 2.0)
			else:
				mat.set_shader_parameter("glow_color", Color(0,1,1,1))
				if s != current_slot:
					mat.set_shader_parameter("glow_intensity", 2.0)

# === Сброс glow у активного слота (после анимации) ===
func _set_active_slot_glow_off():
	if current_slot and current_slot.material is ShaderMaterial:
		var mat: ShaderMaterial = current_slot.material
		var has_ammo := true
		if current_slot == Sidearm: has_ammo = has_ammo_sidearm
		elif current_slot == Primary_Weapon_Slot_1: has_ammo = has_ammo_pws_1
		elif current_slot == Primary_Weapon_Slot_2: has_ammo = has_ammo_pws_2
		elif current_slot == Throwable: has_ammo = has_ammo_throwable

		if has_ammo:
			mat.set_shader_parameter("glow_intensity", 0.0)
		else:
			mat.set_shader_parameter("glow_color", Color(1,0,0,1))
			mat.set_shader_parameter("glow_intensity", 2.0)

	# обновляем AWS‑изображение синхронно с окончанием анимации
	_update_aws_for_slot(current_slot)
	# обновляем видимость лейблов
	_update_ammo_labels_visibility()

# === Обновление видимости лейблов патронов ===
func _update_ammo_labels_visibility():
	if not lbl_current_bullets_in_clip or not lbl_total_ammo:
		return
	
	# показываем только для Sidearm, PWS1, PWS2, Throwable
	if current_slot in [Sidearm, Primary_Weapon_Slot_1, Primary_Weapon_Slot_2, Throwable]:
		lbl_current_bullets_in_clip.visible = true
		lbl_total_ammo.visible = true
	else:
		lbl_current_bullets_in_clip.visible = false
		lbl_total_ammo.visible = false

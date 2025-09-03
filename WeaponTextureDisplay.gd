# WeaponTextureDisplay.gd - РАБОЧАЯ ВЕРСИЯ
extends TextureRect
class_name WeaponTextureDisplay

var ammo_ui = null
var shader_material: ShaderMaterial = null
var burn_tween: Tween = null
var current_weapon_name: String = ""

# Настройки шейдера
@export var enable_3d_perspective: bool = true
@export var enable_burn_on_hide: bool = true
@export var burn_duration: float = 0.6

# Словарь с путями к изображениям оружия
var weapon_textures = {
	"wasteland eagle": "res://UI/Weapons_Textures/Desert-Eagle Pistol.png",
	"enforcer 12-gauge": "res://UI/Weapons_Textures/Lever-Action Shotgun.png",
	"trail boss shotgun": "res://UI/Weapons_Textures/Pump-Action Shotgun.png",
	"assault auto-rifle": "res://UI/Weapons_Textures/M16A2_Automatic_Gun.png",
	"suppressor mg": "res://UI/Weapons_Textures/Machine_Gun.png",
	"grenade": "res://UI/Weapons_Textures/Grenade.png"
}

var noise_texture_cached: ImageTexture = null
var is_shader_ready: bool = false

func _ready():

	add_to_group("weapon_texture")
	_find_ammo_ui()
	_setup_shader_optimized()
	# Устанавливаем приглушенный вид по умолчанию
	modulate = Color(0.3, 0.3, 0.3, 0.6)
	visible = true  # Оставляем видимым!

func _find_ammo_ui():
	var ui_node = get_node_or_null("../Ammo")
	if ui_node:
		ammo_ui = ui_node

func _setup_shader_optimized():
	var shader_path = "res://shaders/2D-perspective.gdshader"
	if not ResourceLoader.exists(shader_path):
		is_shader_ready = false
		return
	
	var shader = load(shader_path)
	if shader:
		shader_material = ShaderMaterial.new()
		shader_material.shader = shader
		material = shader_material
		_set_basic_shader_params()
		is_shader_ready = true

func _set_basic_shader_params():
	if not shader_material:
		return
	
	shader_material.set_shader_parameter("enable_3d_effect", true)
	shader_material.set_shader_parameter("fov", 75.0)
	shader_material.set_shader_parameter("y_rot", 0.0)
	shader_material.set_shader_parameter("x_rot", 0.0)
	shader_material.set_shader_parameter("inset", 0.2)
	shader_material.set_shader_parameter("use_rect_size", true)
	shader_material.set_shader_parameter("rect_size", size)
	shader_material.set_shader_parameter("enable_burn_effect", false)
	shader_material.set_shader_parameter("progress", -1.5)

func show_weapon(weapon_name: String):
	
	var weapon_type = weapon_name.to_lower()
	
	if weapon_type == "no weapon" or weapon_type == "":
	
		return
	
	_stop_burn_effect()
	
	var is_weapon_change = (current_weapon_name != weapon_name)
	
	if weapon_textures.has(weapon_type):
		var texture_path = weapon_textures[weapon_type]
		
		if ResourceLoader.exists(texture_path):
			var loaded_texture = load(texture_path)
			if loaded_texture:
				texture = loaded_texture
				visible = true
				current_weapon_name = weapon_name

				# Возвращаем нормальный цвет при показе оружия
				var show_tween = create_tween()
				show_tween.tween_property(self, "modulate", Color.WHITE, 0.2)
								
				# ВКЛЮЧАЕМ 3D ЭФФЕКТ ОБРАТНО
				if is_shader_ready and shader_material:
					shader_material.set_shader_parameter("enable_3d_effect", true)
					shader_material.set_shader_parameter("enable_burn_effect", false)
			
				
				if is_weapon_change and is_shader_ready:
		
					_animate_3d_appearance()
				else:
					if is_shader_ready:
						shader_material.set_shader_parameter("y_rot", 0.0)
						shader_material.set_shader_parameter("x_rot", 0.0)
				
			else:
				hide_weapon()
		else:
			hide_weapon()
	else:
		hide_weapon()

func _animate_3d_appearance():
	if not shader_material:
		return
		
	
	shader_material.set_shader_parameter("y_rot", -45.0)
	shader_material.set_shader_parameter("x_rot", -20.0)
	
	var appear_tween = create_tween()
	if appear_tween:
		appear_tween.parallel().tween_method(
			func(value): 
				if shader_material: shader_material.set_shader_parameter("y_rot", value),
			-45.0, 0.0, 0.5
		)
		appear_tween.parallel().tween_method(
			func(value): 
				if shader_material: shader_material.set_shader_parameter("x_rot", value), 
			-20.0, 0.0, 0.5
		)
		appear_tween.tween_callback(func(): print("WeaponTextureDisplay: ✅ 3D анимация завершена"))

func hide_weapon():
	_stop_burn_effect()
	
	# Вместо полного скрытия делаем приглушенный белый цвет
	var fade_tween = create_tween()
	fade_tween.tween_property(self, "modulate", Color(0.3, 0.3, 0.3, 0.6), 0.3)
	
	# НЕ устанавливаем visible = false и НЕ очищаем texture
	# visible = false  # ← УБИРАЕМ ЭТУ СТРОКУ
	# texture = null   # ← И ЭТУ ТОЖЕ
	current_weapon_name = ""
func hide_weapon_with_burn():
	if not enable_burn_on_hide or not is_shader_ready:
		hide_weapon()
		return
	
	if not visible or not texture or current_weapon_name == "":
		hide_weapon()
		return
	
	
	force_setup_burn_params()
	shader_material.set_shader_parameter("direction", randf_range(0.0, 360.0))
	
	_stop_burn_effect()
	burn_tween = create_tween()
	
	if burn_tween:
		burn_tween.tween_method(_update_burn_progress, -1.5, 1.5, burn_duration)
		burn_tween.tween_callback(func(): 
			visible = false
			texture = null
			current_weapon_name = ""
			_stop_burn_effect()
			# Включаем 3D обратно
			if shader_material:
				shader_material.set_shader_parameter("enable_3d_effect", true)
		)
	else:
		hide_weapon()

func force_setup_burn_params():
	if not shader_material:
		return
	
	if not noise_texture_cached:
		var noise_image = Image.create(32, 32, false, Image.FORMAT_RGB8)
		for x in range(32):
			for y in range(32):
				var noise_val = randf()
				noise_image.set_pixel(x, y, Color(noise_val, noise_val, noise_val))
		
		noise_texture_cached = ImageTexture.new()
		noise_texture_cached.set_image(noise_image)
	
	
	shader_material.set_shader_parameter("noiseTexture", noise_texture_cached)
	shader_material.set_shader_parameter("noiseForce", 0.4)
	shader_material.set_shader_parameter("direction", 180.0)
	shader_material.set_shader_parameter("burnColor", Color(1.0, 0.5, 0.0, 1.0))
	shader_material.set_shader_parameter("borderWidth", 0.1)
	shader_material.set_shader_parameter("enable_burn_effect", true)
	shader_material.set_shader_parameter("progress", -1.5)
	

func animate_recoil_3d():
	if not is_shader_ready:
		return

	
	var recoil_tween = create_tween()
	if recoil_tween:
		recoil_tween.tween_method(
			func(value): 
				if shader_material: shader_material.set_shader_parameter("x_rot", value),
			0.0, -8.0, 0.08
		)
		recoil_tween.tween_method(
			func(value): 
				if shader_material: shader_material.set_shader_parameter("x_rot", value),
			-8.0, 0.0, 0.2
		)

func _update_burn_progress(value: float):
	if shader_material:
		# ПРИНУДИТЕЛЬНО отключаем 3D во время burn
		shader_material.set_shader_parameter("enable_3d_effect", false)
		shader_material.set_shader_parameter("enable_burn_effect", true)
		shader_material.set_shader_parameter("progress", value)
		
	else:
		print("WeaponTextureDisplay: ❌ shader_material null в burn progress")

func _stop_burn_effect():
	if burn_tween and burn_tween.is_valid():
		burn_tween.kill()
	burn_tween = null
	
	if shader_material:
		shader_material.set_shader_parameter("enable_burn_effect", false)
		shader_material.set_shader_parameter("progress", -1.5)

func add_weapon_texture(weapon_type: String, texture_path: String):
	weapon_textures[weapon_type.to_lower()] = texture_path

func _exit_tree():
	_stop_burn_effect()
	if noise_texture_cached:
		noise_texture_cached = null

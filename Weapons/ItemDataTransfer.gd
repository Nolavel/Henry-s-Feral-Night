extends StaticBody3D # ItemDataTransfer

# Данные предмета
@export var item_name: String = "Unknown Weapon"
@export var item_category: String = "WEAPON" 
@export var item_weight: float = 2.5
@export var item_description: String = "Weapon description"

# Данные от WeaponBase (заполняются программно)
var weapon_data: Dictionary = {}
	
func set_item_data(data: Dictionary):
	weapon_data = data
	# Обновляем экспортные переменные
	item_name = data.get("name", item_name)
	item_weight = data.get("weight", item_weight) 
	item_description = data.get("description", item_description)

# Для вашей hover системы
func get_item_name() -> String:
	return item_name

# Для расширенной информации  
func get_full_item_info() -> String:
	return "[%s]\n%s\nВес: %.1f кг\n%s" % [
		item_category, 
		item_name, 
		item_weight, 
		item_description
	]

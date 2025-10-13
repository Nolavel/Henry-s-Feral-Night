extends Node3D

@onready var player = $"../Player"
@onready var debug_label_loc = $"../Perfomance&Debugging/debug_label_loc"



func _on_loc_fort_meridian_body_entered(body: Node3D) -> void:
	if body == player:
		debug_label_loc.text = ("➡ Игрок в локации Форт-Меридиан")


func _on_loc_fort_meridian_body_exited(body: Node3D) -> void:
	if body == player:
		debug_label_loc.text = ("⬅ Игрок покинул локацию Форт-Меридиан")


func _on_loc_verdant_ruins_body_entered(body: Node3D) -> void:
	if body == player:
		debug_label_loc.text = ("➡ Игрок в локации Вердан-Руинс")


func _on_loc_verdant_ruins_body_exited(body: Node3D) -> void:
	if body == player:
		debug_label_loc.text = ("⬅ Игрок покинул локацию Вердан-Руинс")

func _on_loc_harborlight_district_body_entered(body: Node3D) -> void:
	if body == player:
		debug_label_loc.text = ("➡ Игрок в локации Харборлайт-Дистрикт")

func _on_loc_harborlight_district_body_exited(body: Node3D) -> void:
	if body == player:
		debug_label_loc.text = ("⬅ Игрок покинул локацию Харборлайт-Дистрикт")


func _on_loc_silvan_heights_body_entered(body: Node3D) -> void:
	if body == player:
		debug_label_loc.text = ("➡ Игрок в локации Сильван-Хайтс")


func _on_loc_silvan_heights_body_exited(body: Node3D) -> void:
	if body == player:
		debug_label_loc.text = ("⬅ Игрок покинул локацию Сильван-Хайтс")


func _on_loc_palawan_cove_body_entered(body: Node3D) -> void:
	if body == player:
		debug_label_loc.text = ("➡ Игрок в локации Палаван-Коу")


func _on_loc_palawan_cove_body_exited(body: Node3D) -> void:
	if body == player:
		debug_label_loc.text = ("⬅ Игрок покинул локацию Палаван-Коу")

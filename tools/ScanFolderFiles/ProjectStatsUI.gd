# ✅ Script: ProjectStatsUI.gd
@tool
extends Control

# === UI ЭЛЕМЕНТЫ ===
@onready var label_folders: Label = $PS_PanelUI/VBoxContainer/FoldersLabel
@onready var label_files: Label = $PS_PanelUI/VBoxContainer/FilesLabel
@onready var label_lines: Label = $PS_PanelUI/VBoxContainer/LinesLabel
@onready var label_scenes: Label = $PS_PanelUI/VBoxContainer/ScenesLabel
@onready var label_size: Label = $PS_PanelUI/VBoxContainer/SizeLabel

@onready var countdown_label: Label = $LabelCountdown
# === ССЫЛКА НА C# СКАНЕР ===
var scanner: Node = null

func _ready():
	countdown_label.visible = false
	
	# Инициализируем UI
	label_folders.text = "📁 Folders: ..."
	label_files.text = "📄 Files: ..."
	
	find_scanner()
	
	# Подключаем сигнал ТОЛЬКО если сканер найден
	if scanner:
		scanner.connect("ScanCompleted", Callable(self, "_on_scan_completed"))
		scanner.connect("LineCountCompleted", Callable(self, "_on_line_count_completed"))
		scanner.connect("SceneStatsCompleted", Callable(self, "_on_scene_stats_completed"))

	else:
		print("❌ Сканер не найден - сигнал не подключен")
		
func find_scanner():
	"""Ищет ProjectScanner в дереве сцены"""
	scanner = get_tree().get_first_node_in_group("project_scanner")
		
# === ОБРАБОТЧИК СИГНАЛА ОТ C# ===
func _on_scan_completed(folder_count: int, file_count: int):
	# Обновляем лейблы
	label_folders.text = "📁 Folders in Project: %d" % folder_count
	label_files.text = "📄 Files in Project: %d" % file_count
	
func _on_line_count_completed(script_file_count: int, total_line_count: int):
	label_lines.text = "🧾 Scripts: %d , lines of code: %d" % [script_file_count, total_line_count]
	
func _on_scene_stats_completed(scene_count: int, project_size_bytes: int):
	label_scenes.text = "🎬 Scenes in Project: %d" % scene_count
	label_size.text = "📦 Project Size: %.2f MB" % (project_size_bytes / 1024.0 / 1024.0)
	
func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		start_exit()
		
func start_exit():
	countdown_label.visible = true

	countdown_label.text = "3.."
	await get_tree().create_timer(1.0).timeout

	countdown_label.text = "2.."
	await get_tree().create_timer(1.0).timeout

	countdown_label.text = "Exit"
	await get_tree().create_timer(0.3).timeout
	get_tree().quit()
	


	

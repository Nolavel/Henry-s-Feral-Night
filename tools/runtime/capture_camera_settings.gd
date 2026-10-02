extends SceneTree

## Lightweight visual proof for the production CameraSettingsPanel.
## Captures the two review states requested in #170:
## 01 saved/default -> Accept grey/disabled
## 02 staged change -> Accept yellow/enabled
const SETTINGS_PANEL: GDScript = preload("res://scripts/ui/menu/camera_settings_panel.gd")
const OUT_DIR: String = "res://docs/runtime_previews/camera_settings"

var _stage: Control
var _panel: CameraSettingsPanel


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	seed(170)

	_stage = Control.new()
	_stage.position = Vector2.ZERO
	_stage.size = root.get_visible_rect().size
	root.add_child(_stage)

	var background := ColorRect.new()
	background.position = Vector2.ZERO
	background.size = _stage.size
	background.color = Color(0.16, 0.18, 0.22, 1.0)
	_stage.add_child(background)

	_panel = SETTINGS_PANEL.new() as CameraSettingsPanel
	_panel.position = Vector2.ZERO
	_panel.size = _stage.size
	_stage.add_child(_panel)
	await process_frame
	_panel.open()

	## Let the full ink assembly + staged content fade finish.
	await create_timer(1.15).timeout
	_capture("01_settings_open_accept_grey")

	var slider := _panel.find_child("MouseSensitivitySlider", true, false) as HSlider
	var accept := _panel.find_child("AcceptButton", true, false) as Button
	if slider == null or accept == null:
		push_error("camera settings capture: expected controls missing")
		quit(2)
		return
	if not accept.disabled:
		push_error("camera settings capture: Accept must start disabled")
		quit(3)
		return

	slider.value = 125.0
	await process_frame
	if accept.disabled:
		push_error("camera settings capture: dirty settings did not enable Accept")
		quit(4)
		return
	_capture("02_settings_dirty_accept_yellow")

	var report := {
		"first": "saved/default settings; Accept grey and disabled",
		"second": "mouse sensitivity staged at 125%; Accept yellow and enabled",
		"blot_shader": "res://shaders/ui/key_hints_blot.gdshader",
		"frame": "eight staggered ragged blobs -> title -> controls -> buttons",
		"close": "buttons/controls/title fade out -> blobs dissolve",
	}
	var file := FileAccess.open("%s/report.json" % OUT_DIR, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("camera settings capture: complete")
	quit()


func _capture(name: String) -> void:
	var image := root.get_texture().get_image()
	var error := image.save_png("%s/%s.png" % [OUT_DIR, name])
	if error != OK:
		push_error("camera settings capture: save failed %s (%d)" % [name, error])

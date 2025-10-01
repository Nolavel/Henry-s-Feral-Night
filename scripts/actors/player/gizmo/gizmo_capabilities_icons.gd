extends Control

var animations = [
	"energy_power",
	"scan_available",
	"gizmo_shock_available",
	"gizmo_status_low"
]

var playing = false
var animation_player

func _ready():
	animation_player = $Gizmo_icons_reaction

func _input(event: InputEvent) -> void:
	if Input.is_action_pressed("DEBUG") and not playing:
		playing = true
		play_animations_sequence()
	elif not Input.is_action_pressed("DEBUG") and playing:
		playing = false
		animation_player.play("RESET")

func play_animations_sequence():
	for anim in animations:
		if not playing:
			break
		animation_player.play(anim)
		await get_tree().create_timer(0.5).timeout
	if playing:
		playing = false
		animation_player.play("RESET")

extends CanvasLayer

signal speech_completed

onready var sample_player = get_node("SamplePlayer")

onready var timer = get_node("Timer")
const TIMER_NORMAL = 0.035
const TIMER_DELAYED = 1.0

onready var label = get_node("RichTextLabel")

# The speech data as an array of strings.
var speech_data = [
"""
It's dangerous to go alone...
You have no chance to survive
make your time
""", "Welcome to a thing"]
var page = 0

func _ready():
	start_if_ready()

func _input(event):
	# TODO: Also react to the other buttons as well.
	if event.is_action_pressed("trans_accept"):
		if not is_page_complete():
			# Complete the page immediately.
			label.visible_characters = label.get_total_character_count()
		elif page < len(speech_data) - 1:
			# Move on to the next page.
			page += 1
			start_current_page()
		else:
			# Close the dialog.
			emit_signal("speech_completed")
			queue_free()

func init(speech_data):
	self.speech_data = speech_data
	start_if_ready()

func start_if_ready():
	if speech_data:
		timer.wait_time = TIMER_NORMAL
		timer.connect("timeout", self, "on_timeout")
		timer.start()
		
		start_current_page()

func start_current_page():
	# Reset timer speed in case we transitioned in the middle
	# of a slow character.
	timer.wait_time = TIMER_NORMAL
	
	# Process page speech text.
	var speech_text = speech_data[page]
	speech_text = speech_text.strip_edges()
	speech_text = "[center]" + speech_text + "[/center]"
	label.bbcode_text = speech_text
	label.visible_characters = 0

func is_page_complete():
	return label.visible_characters == label.get_total_character_count()

func print_character():
	label.visible_characters = label.visible_characters + 1
	sample_player.play()

func on_timeout():
	# TODO: Add delay support.
	if not is_page_complete():
		print_character()
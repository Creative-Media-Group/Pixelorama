@tool
class_name ValueSlider
extends TextureProgressBar
## Custom node that combines the behavior of a Slider and a SpinBox.
## Initial version made by MrTriPie, has been modified by Overloaded.

enum { NORMAL, HELD, SLIDING, TYPING }

@export var editable := true:
	set(v):
		editable = v
		var line_edit_color := get_theme_color("font_color", "LineEdit")
		var line_edit_disabled_col := get_theme_color("font_uneditable_color", "LineEdit")
		if editable:
			_line_edit.add_theme_color_override("font_uneditable_color", line_edit_color)
		else:
			_line_edit.add_theme_color_override("font_uneditable_color", line_edit_disabled_col)
@export var prefix: String:
	set(v):
		prefix = v
		_reset_display()
@export var suffix: String:
	set(v):
		suffix = v
		_reset_display()
## Size of additional snapping (applied in addition to Range's step).
## This should always be larger than step.
@export var snap_step := 1.0
## If snap_by_default is true, snapping is enabled when Control is NOT held (used for sliding in
## larger steps by default, and smaller steps when holding Control).
## If false, snapping is enabled when Control IS held (used for sliding in smaller steps by
## default, and larger steps when holding Control).
@export var snap_by_default := false
## If show_progress is true it will show the colored progress bar, good for values with a specific
## range. False will hide it, which is good for values that can be any number.
@export var show_progress := true
@export var show_arrows := true:
	set(v):
		show_arrows = v
		if not _line_edit:
			return
		_value_up_button.visible = v
		_value_down_button.visible = v
@export var echo_arrow_time := 0.075
@export var global_increment_action := ""  ## Global shortcut to increment
@export var global_decrement_action := ""  ## Global shortcut to decrement

var state := NORMAL
var arrow_is_held := 0  ## Used for arrow button echo behavior. Is 1 for ValueUp, -1 for ValueDown.

var _line_edit := LineEdit.new()
var _value_up_button := TextureButton.new()
var _value_down_button := TextureButton.new()
var _timer := Timer.new()


func _init() -> void:
	nine_patch_stretch = true
	stretch_margin_left = 3
	stretch_margin_top = 3
	stretch_margin_right = 3
	stretch_margin_bottom = 3
	theme_type_variation = "ValueSlider"


func _ready() -> void:
	value_changed.connect(_on_value_changed)
	set_process_input(!global_increment_action.is_empty() and !global_decrement_action.is_empty())
	_reset_display(true)
	if not Engine.is_editor_hint():  # Pixelorama specific code
		_value_up_button.modulate = Global.modulate_icon_color
		_value_down_button.modulate = Global.modulate_icon_color
	_setup_nodes()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_reset_display(true)
	elif what == NOTIFICATION_TRANSLATION_CHANGED:
		_reset_display(false)


func _unhandled_input(event: InputEvent) -> void:
	if not editable or not is_visible_in_tree():
		return
	if (
		not global_increment_action.is_empty()
		and event.is_action_pressed(global_increment_action, true)
	):
		if snap_by_default:
			value += step if event.ctrl_pressed else snap_step
		else:
			value += snap_step if event.ctrl_pressed else step
	elif (
		not global_decrement_action.is_empty()
		and event.is_action_pressed(global_decrement_action, true)
	):
		if snap_by_default:
			value -= step if event.ctrl_pressed else snap_step
		else:
			value -= snap_step if event.ctrl_pressed else step


func _gui_input(event: InputEvent) -> void:
	if not editable:
		return
	if state == NORMAL:
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				state = HELD
				set_meta("mouse_start_position", get_local_mouse_position())
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
				if snap_by_default:
					value += step if event.ctrl_pressed else snap_step
				else:
					value += snap_step if event.ctrl_pressed else step
				get_viewport().set_input_as_handled()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				if snap_by_default:
					value -= step if event.ctrl_pressed else snap_step
				else:
					value -= snap_step if event.ctrl_pressed else step
				get_viewport().set_input_as_handled()
	elif state == HELD:
		if event.is_action_released("left_mouse"):
			state = TYPING
			_line_edit.text = _format_float_string(true)
			_line_edit.editable = true
			_line_edit.grab_focus()
			_line_edit.selecting_enabled = true
			_line_edit.select_all()
			_line_edit.caret_column = _line_edit.text.length()
			tint_progress = Color.TRANSPARENT
		elif event is InputEventMouseMotion:
			if get_meta("mouse_start_position").distance_to(get_local_mouse_position()) > 2:
				state = SLIDING
				set_meta("shift_pressed", event.shift_pressed)
				set_meta("start_ratio", ratio)
				set_meta("start_value", value)
	elif state == SLIDING:
		if event.is_action_released("left_mouse"):
			state = NORMAL
			remove_meta("mouse_start_position")
			remove_meta("start_ratio")
			remove_meta("start_value")
			remove_meta("shift_pressed")
		if event is InputEventMouseMotion:
			# When pressing/releasing Shift, reset starting values to prevent slider jumping around
			if get_meta("shift_pressed") != event.shift_pressed:
				set_meta("mouse_start_position", get_local_mouse_position())
				set_meta("start_ratio", ratio)
				set_meta("start_value", value)
				set_meta("shift_pressed", event.shift_pressed)
			var x_delta: float = get_local_mouse_position().x - get_meta("mouse_start_position").x
			# Slow down to allow for more precision
			if event.shift_pressed:
				x_delta *= 0.1
			if show_progress:
				ratio = get_meta("start_ratio") + x_delta / size.x
			else:
				value = get_meta("start_value") + x_delta * step
			# Snap when snap_by_default is true, do the opposite when Control is pressed
			if snap_by_default:
				if not event.ctrl_pressed:
					value = roundf(value / snap_step) * snap_step
			else:
				if event.ctrl_pressed:
					value = roundf(value / snap_step) * snap_step
			get_viewport().set_input_as_handled()


func _setup_nodes() -> void:  ## Only called once on _ready()
	focus_mode = Control.FOCUS_ALL
	_line_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line_edit.anchor_right = 1
	_line_edit.anchor_bottom = 1
	_line_edit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_line_edit.add_theme_stylebox_override("read_only", StyleBoxEmpty.new())
	_line_edit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_line_edit.text_submitted.connect(_on_LineEdit_text_entered)
	_line_edit.focus_exited.connect(_confirm_text)
	_line_edit.gui_input.connect(_on_LineEdit_gui_input)
	add_child(_line_edit)

	var value_up_texture_size := Vector2.ONE
	if is_instance_valid(_value_up_button.texture_normal):
		value_up_texture_size = _value_up_button.texture_normal.get_size()
	_value_up_button.scale.y = -1
	_value_up_button.anchor_left = 1
	_value_up_button.anchor_right = 1
	_value_up_button.offset_left = -value_up_texture_size.x - 3
	_value_up_button.offset_top = value_up_texture_size.y
	_value_up_button.offset_right = -3
	_value_up_button.offset_bottom = value_up_texture_size.y * 2
	_value_up_button.focus_mode = Control.FOCUS_NONE
	_value_up_button.add_to_group("UIButtons")
	_value_up_button.button_down.connect(_on_Value_button_down.bind(1))
	_value_up_button.button_up.connect(_on_Value_button_up)
	add_child(_value_up_button)

	var value_down_texture_size := Vector2.ONE
	if is_instance_valid(_value_down_button.texture_normal):
		value_down_texture_size = _value_down_button.texture_normal.get_size()
	_value_down_button.anchor_left = 1
	_value_down_button.anchor_top = 1
	_value_down_button.anchor_right = 1
	_value_down_button.anchor_bottom = 1
	_value_down_button.offset_left = -value_down_texture_size.x - 3
	_value_down_button.offset_top = -value_up_texture_size.y
	_value_down_button.offset_right = -3
	_value_down_button.offset_bottom = 0
	_value_up_button.focus_mode = Control.FOCUS_NONE
	_value_down_button.add_to_group("UIButtons")
	_value_down_button.button_down.connect(_on_Value_button_down.bind(-1))
	_value_down_button.button_up.connect(_on_Value_button_up)
	add_child(_value_down_button)

	_timer.timeout.connect(_on_Timer_timeout)
	add_child(_timer)


func _on_LineEdit_gui_input(event: InputEvent) -> void:
	if state == TYPING:
		if event is InputEventKey and event.keycode == KEY_ESCAPE:
			_confirm_text(false)  # Cancel
			_line_edit.release_focus()


func _on_value_changed(_value: float) -> void:
	_reset_display()


## When pressing enter, release focus, which will call _confirm_text on focus_exited signal
func _on_LineEdit_text_entered(_new_text: String) -> void:
	_line_edit.release_focus()


## Called on LineEdit's focus_exited signal
## If confirm is false it will cancel setting value
func _confirm_text(confirm := true) -> void:
	if state != TYPING:
		return
	state = NORMAL
	if confirm:
		var expression := Expression.new()
		var error := expression.parse(_line_edit.text, [])
		if error != OK:
			_reset_display(true)
			return
		var result = expression.execute([], null, true)
		if expression.has_execute_failed() or not (result is int or result is float):
			_reset_display(true)
			return
		value = result
	_reset_display(true)


func set_value_no_signal_update_display(new_value: float) -> void:
	set_value_no_signal(new_value)
	_reset_display()


func _reset_display(theme_has_changed := false) -> void:
	_line_edit.selecting_enabled = false  # Remove the selection
	_line_edit.editable = false
	if theme_has_changed and not Engine.is_editor_hint():
		texture_under = get_theme_icon("texture_under", "ValueSlider")
#		texture_over = get_theme_icon("texture_over", "ValueSlider")
		texture_progress = get_theme_icon("texture_progress", "ValueSlider")
		_value_up_button.texture_normal = get_theme_icon("arrow_normal", "ValueSlider")
		_value_up_button.texture_pressed = get_theme_icon("arrow_pressed", "ValueSlider")
		_value_up_button.texture_hover = get_theme_icon("arrow_hover", "ValueSlider")

		_value_down_button.texture_normal = get_theme_icon("arrow_normal", "ValueSlider")
		_value_down_button.texture_pressed = get_theme_icon("arrow_pressed", "ValueSlider")
		_value_down_button.texture_hover = get_theme_icon("arrow_hover", "ValueSlider")

		editable = editable  # Call the setter
		tint_under = get_theme_color("under_color", "ValueSlider")
		if show_progress:
			tint_progress = get_theme_color("progress_color", "ValueSlider")
		else:
			tint_progress = Color.TRANSPARENT
	_line_edit.text = _format_float_string()


## Format the value string so that integers won't appear as floats.
func _format_float_string(is_typing := false) -> String:
	var format_string := "%*.*f"
	var split_str := str(minf(step, snap_step)).split(".")
	var n_of_decimals := 0
	if split_str.size() > 1:
		var decimal_str := split_str[1]
		if str_to_var(decimal_str) != 0:
			n_of_decimals = split_str[1].length()
	var float_str := format_string % [0, n_of_decimals, value]
	if is_typing:
		return float_str
	return str(tr(prefix), " ", float_str, " ", tr(suffix)).strip_edges()


func _on_Value_button_down(direction: int) -> void:
	if not editable:
		return
	# Direction is either 1 or -1
	value += (snap_step if Input.is_action_pressed("ctrl") else step) * direction
	arrow_is_held = direction
	_timer.wait_time = echo_arrow_time * 8  # 0.6 with the default value
	_timer.one_shot = true
	_timer.start()


func _on_Value_button_up() -> void:
	arrow_is_held = 0
	_timer.stop()


## Echo behavior. If the user keeps pressing the button, the value keeps changing.
func _on_Timer_timeout() -> void:
	if arrow_is_held == 0:
		_timer.stop()
		return
	value += (snap_step if Input.is_action_pressed("ctrl") else step) * arrow_is_held
	if _timer.one_shot:
		_timer.wait_time = echo_arrow_time
		_timer.one_shot = false
		_timer.start()

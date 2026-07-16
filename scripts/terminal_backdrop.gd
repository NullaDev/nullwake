class_name TerminalBackdrop
extends Control

var phase := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(delta: float) -> void:
	phase += delta
	queue_redraw()


func _draw() -> void:
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), Color("05090e"))
	for i in range(14):
		var y := size.y * float(i) / 14.0
		var alpha := 0.018 + 0.006 * sin(phase * 0.35 + i)
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.1, 0.85, 0.8, alpha), 1.0)
	for i in range(36):
		var x := fmod(float(i * 197 + 31), maxf(size.x, 1.0))
		var y := fmod(float(i * i * 43 + 73), maxf(size.y, 1.0))
		var pulse := 0.18 + 0.12 * sin(phase * (0.25 + (i % 5) * 0.07) + i)
		draw_circle(Vector2(x, y), 1.0 if i % 4 else 1.6, Color(0.48, 0.9, 0.9, pulse))
	var glow_center := Vector2(size.x * 0.78, size.y * 0.28)
	for radius in range(220, 20, -20):
		draw_circle(glow_center, radius, Color(0.03, 0.32, 0.36, 0.0035))


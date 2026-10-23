class_name RetroUI
extends RefCounted
## Shared drawing helpers for the arcade-style menus (outlined text, fake
## italic digits, panels).

const YELLOW := Color(1.0, 0.84, 0.1)
const RED := Color(0.95, 0.15, 0.1)
const GREEN := Color(0.3, 0.95, 0.2)
const CYAN := Color(0.6, 0.9, 1.0)
const INK := Color(0.02, 0.02, 0.08)


static func text(ci: CanvasItem, pos: Vector2, s: String, size: int, col: Color, outline := 4,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var font := ThemeDB.fallback_font
	if outline > 0:
		ci.draw_string_outline(font, pos, s, align, width, size, outline, INK)
	ci.draw_string(font, pos, s, align, width, size, col)


static func italic(ci: CanvasItem, pos: Vector2, s: String, size: int, col: Color, outline := 5,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	ci.draw_set_transform_matrix(Transform2D(Vector2(1, 0), Vector2(-0.22, 1), pos))
	text(ci, Vector2.ZERO, s, size, col, outline, align, width)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


static func panel(ci: CanvasItem, r: Rect2, alpha := 0.78) -> void:
	ci.draw_rect(r.grow(2), INK)
	ci.draw_rect(r, Color(0.05, 0.12, 0.38, alpha))
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), YELLOW)


## Highlight bar behind the selected row, blinking like an arcade cursor.
static func cursor(ci: CanvasItem, r: Rect2) -> void:
	var blink := 0.55 + 0.25 * sin(Time.get_ticks_msec() / 120.0)
	ci.draw_rect(r, Color(1.0, 0.84, 0.1, blink * 0.45))

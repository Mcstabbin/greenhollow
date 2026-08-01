class_name HeartIcon
extends Control
## One heart, drawn from primitives rather than a sprite.
##
## The project has no heart texture and the art direction is flat colour with hard
## black outlines (CLAUDE.md, "Art direction"), so the shape is sampled from the
## classic heart curve and filled with `draw_colored_polygon`. That also means the
## silhouette is resolution-independent: change CELL and it still reads.
##
## Fill runs left to right in quarters, and only the boundary heart in a row is
## ever partial — the row decides which, this node just renders the state it is
## given. That split is inherited from TetraForce's `hud.gd` (MIT), which maps
## health onto `empty / partial / full` per heart index; the difference here is
## that the units are already integers, so there is no `floor()` and no float
## comparison to get wrong.

## Quarter-heart units in a full heart. The row's granularity, in one place.
const QUARTERS := 4

## Logical size of one heart. Authored against the 640x480 capture size the rest
## of the HUD was tuned at, matching the 28px labels beside it.
const CELL := Vector2(34.0, 31.0)

## Thick, because it is read against sunlit foliage. A hairline would vanish.
const OUTLINE_WIDTH := 3.0

const COLOR_FILL := Color(0.94, 0.19, 0.28)
## Not transparent: an empty heart still has to be a legible dark shape against a
## bright background, so it gets its own near-black plum fill.
const COLOR_EMPTY := Color(0.19, 0.08, 0.12)
const COLOR_OUTLINE := Color(0.0, 0.0, 0.0)
const COLOR_SHINE := Color(1.0, 0.79, 0.81)

## Points on the curve. 44 is past the point where more segments change anything
## at 34px, and the polygon is built once for the whole game.
const CURVE_STEPS := 44

## A hit punches the heart up and washes it white. Kept under a quarter of a
## second: this is feedback, not a cutscene, and it must not cost frames.
const PUNCH_SCALE := 1.34
const PUNCH_UP := 0.055
const PUNCH_DOWN := 0.165

## Geometry depends only on constants, so every heart in the row shares one copy.
## Built lazily on the first draw and never rebuilt.
static var _silhouette := PackedVector2Array()
static var _fills: Array[Array] = []

var _quarters := QUARTERS
## 1.0 immediately after a hit, easing to 0.0. Washes the fill toward white.
var _flash := 0.0
var _punch_tween: Tween = null
var _flash_tween: Tween = null


func _init() -> void:
	# Shrink-centre both ways so the container cannot stretch the heart out of
	# shape when the row's rect is taller or wider than its contents.
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	# The punch has to grow from the middle, and `size` is only final once the
	# container has laid us out.
	resized.connect(_on_resized)
	_on_resized()


## Tell the heart how much of it is filled, 0 to QUARTERS. Losing ground punches.
func set_quarters(value: int) -> void:
	var clamped := clampi(value, 0, QUARTERS)
	if clamped == _quarters:
		return
	var lost := clamped < _quarters
	_quarters = clamped
	queue_redraw()
	if lost:
		_punch()


func _get_minimum_size() -> Vector2:
	return CELL


func _draw() -> void:
	var heart := _get_silhouette()
	# The drained part flashes too, not just the fill. A heart knocked down to its
	# last quarter has almost no fill left to wash white, so flashing only the
	# fill made the hit invisible on exactly the hits that matter most.
	draw_colored_polygon(heart, COLOR_EMPTY.lerp(COLOR_FILL, _flash * 0.9))

	var fill := COLOR_FILL.lerp(Color.WHITE, _flash)
	for polygon in _get_fill(_quarters):
		draw_colored_polygon(polygon, fill)

	# The shine sits in the left lobe, so it only makes sense once the fill has
	# reached it. Below half a heart it would float over empty space.
	if _quarters >= 2:
		var inner := _inner_rect()
		draw_circle(
			inner.position + Vector2(inner.size.x * 0.27, inner.size.y * 0.24),
			inner.size.x * 0.1,
			COLOR_SHINE)

	# Stroked last and centred on the path, so it covers the ragged edge of the
	# fill polygons and every heart gets the same outline weight.
	var closed := heart.duplicate()
	closed.append(heart[0])
	draw_polyline(closed, COLOR_OUTLINE, OUTLINE_WIDTH)


func _on_resized() -> void:
	pivot_offset = size * 0.5


func _punch() -> void:
	if _punch_tween != null:
		_punch_tween.kill()
	if _flash_tween != null:
		_flash_tween.kill()

	# Two tweens rather than one: the flash has to span both legs of the scale
	# bounce, and a single sequence would either chain it or cut it short.
	_punch_tween = create_tween()
	_punch_tween.tween_property(self, "scale", Vector2.ONE * PUNCH_SCALE, PUNCH_UP) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_punch_tween.tween_property(self, "scale", Vector2.ONE, PUNCH_DOWN) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_flash_tween = create_tween()
	_flash_tween.tween_method(_set_flash, 1.0, 0.0, PUNCH_UP + PUNCH_DOWN)


func _set_flash(value: float) -> void:
	_flash = value
	queue_redraw()


# --- Geometry -------------------------------------------------------------

## The rect the silhouette is fitted into: the cell, inset far enough that the
## centred outline stroke cannot spill past the cell edge and get clipped.
static func _inner_rect() -> Rect2:
	var pad := OUTLINE_WIDTH * 0.5 + 1.0
	return Rect2(Vector2(pad, pad), CELL - Vector2(pad, pad) * 2.0)


## The classic heart curve, sampled and then affine-fitted to `_inner_rect()`.
## Fitting from the curve's own bounds rather than hand-tuned magic numbers means
## the shape stays centred and fills the cell whatever CELL is set to.
static func _get_silhouette() -> PackedVector2Array:
	if not _silhouette.is_empty():
		return _silhouette

	var raw := PackedVector2Array()
	var low := Vector2.INF
	var high := -Vector2.INF
	for i in CURVE_STEPS:
		var t := TAU * float(i) / float(CURVE_STEPS)
		var x := 16.0 * pow(sin(t), 3.0)
		# Negated: the curve is written for maths-up, canvases are screen-down.
		var y := -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
		raw.append(Vector2(x, y))
		low = Vector2(minf(low.x, x), minf(low.y, y))
		high = Vector2(maxf(high.x, x), maxf(high.y, y))

	var inner := _inner_rect()
	var span := high - low
	var fitted := PackedVector2Array()
	for point in raw:
		fitted.append(inner.position + (point - low) / span * inner.size)
	_silhouette = fitted
	return _silhouette


## The filled part of the heart for each quarter, clipped once and cached. Five
## states exist, so this runs at most five times per session; `_draw` never does
## polygon maths. Intersection is `Geometry2D`'s job, not ours.
static func _get_fill(quarters: int) -> Array:
	if _fills.is_empty():
		var heart := _get_silhouette()
		var inner := _inner_rect()
		for q in QUARTERS + 1:
			if q == 0:
				_fills.append([])
			elif q == QUARTERS:
				_fills.append([heart])
			else:
				# A vertical wipe from the left: at two quarters this is exactly
				# the left half of the heart, which is the shape players expect.
				var width := inner.size.x * float(q) / float(QUARTERS)
				var window := Rect2(inner.position, Vector2(width, inner.size.y))
				_fills.append(Geometry2D.intersect_polygons(heart, _as_polygon(window)))
	return _fills[quarters]


static func _as_polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		rect.position,
		rect.position + Vector2(rect.size.x, 0.0),
		rect.end,
		rect.position + Vector2(0.0, rect.size.y),
	])

class_name HeartRow
extends HBoxContainer
## The row of hearts. Owns how many there are and which one is the partial one.
##
## Hearts are created in code rather than authored in the scene, so raising the
## maximum is one call and needs no reload — the pattern from
## Astridson/godot-segmented-bar (MIT), whose `total_segments` setter rebuilds its
## children, and from TetraForce's `new_heart()`.

## Quarter-heart units in a full heart. Mirrors HeartIcon.QUARTERS by using it.
const QUARTERS := HeartIcon.QUARTERS


## Set the whole row from quarter-heart units. Grows or shrinks the row to fit
## `maximum` first, so a heart container is just a bigger number arriving here.
func set_health(current: int, maximum: int) -> void:
	var wanted := maxi(1, ceili(float(maximum) / float(QUARTERS)))

	while get_child_count() < wanted:
		var heart := HeartIcon.new()
		# Named, so the remote scene tree reads "Heart1..Heart4" rather than a run
		# of @Control@nn when something needs debugging.
		heart.name = "Heart%d" % (get_child_count() + 1)
		add_child(heart)
	while get_child_count() > wanted:
		var extra := get_child(get_child_count() - 1)
		remove_child(extra)
		extra.queue_free()

	# Every heart takes its own slice of the total. Full below the boundary, empty
	# above it, and the clamp leaves exactly one heart partial without needing to
	# find out which one that is.
	for i in get_child_count():
		var heart := get_child(i) as HeartIcon
		heart.set_quarters(clampi(current - i * QUARTERS, 0, QUARTERS))

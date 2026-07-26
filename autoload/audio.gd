extends Node
## Small pooled sound player.
##
## Pattern follows KenneyNL/Starter-Kit-3D-Platformer's scripts/audio.gd:
## one global entry point so callers never manage AudioStreamPlayer nodes.
## Pooled rather than one-shot-node-per-sound so rapid pickups don't churn
## the scene tree.

const POOL_SIZE := 12
const SFX := "res://audio/sfx/%s.ogg"

var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _cache := {}


func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)


## `name` is a bare filename without extension, e.g. "coin".
## `pitch_jitter` keeps repeated sounds from sounding mechanical.
func play(name: String, volume_db: float = 0.0, pitch_jitter: float = 0.08) -> void:
	var stream := _load(name)
	if stream == null:
		return
	var p := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


func _load(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	var path := SFX % name
	if not ResourceLoader.exists(path):
		push_warning("missing sound: %s" % path)
		_cache[name] = null
		return null
	var stream := load(path) as AudioStream
	_cache[name] = stream
	return stream

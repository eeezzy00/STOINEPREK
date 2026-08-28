extends Node

## Autoload. Owns the two continuous background audio channels -- music and
## ambience -- as persistent players that survive scene changes. This is
## what actually fixes the artifacts: before this, menu music and level
## ambience each lived as an AudioStreamPlayer *inside* their scene, so
## every scene change (menu -> settings, a death/bot restart reloading the
## level, ...) destroyed and recreated the player, restarting the track
## from 0 -- a pop/cut every single time, even when the same track should
## have just kept playing. play_music()/play_ambience() are no-ops if the
## requested stream is already the one currently playing.

## Ambience (city background loop) lives on the SFX bus, not its own bus --
## it's routed there on purpose so the "Effects" slider in Settings controls
## it, since there's no separate Ambience slider in the settings screen.
## Trimmed quieter here so it sits under actual combat SFX in the mix.
const AMBIENCE_TRIM_DB := -14.0

var _music_player: AudioStreamPlayer
var _ambience_player: AudioStreamPlayer

## What the game last actually asked for, independent of the on/off toggles
## below -- so re-enabling replays the right thing (level music vs menu
## music) instead of needing every caller to re-request it.
var _requested_music: AudioStream
var _requested_music_loop := true
var _requested_ambience: AudioStream
var _requested_ambience_loop := true

var music_enabled := true
var ambience_enabled := true


func _ready() -> void:
	_music_player = _make_player("Music")
	_ambience_player = _make_player("SFX")
	_ambience_player.volume_db = AMBIENCE_TRIM_DB


func _make_player(bus_name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus_name
	add_child(p)
	return p


## Stopping music this way (rather than every caller reaching in) is what
## guarantees music and ambience never fight each other: a level with no
## music of its own calls this once in _ready() and whatever was playing
## before (menu music) cleanly stops, leaving only ambience.
func play_music(stream: AudioStream, loop: bool = true) -> void:
	_requested_music = stream
	_requested_music_loop = loop
	if music_enabled:
		_play(_music_player, stream, loop)


func stop_music() -> void:
	_requested_music = null
	_stop(_music_player)


func play_ambience(stream: AudioStream, loop: bool = true) -> void:
	_requested_ambience = stream
	_requested_ambience_loop = loop
	if ambience_enabled:
		_play(_ambience_player, stream, loop)


func stop_ambience() -> void:
	_requested_ambience = null
	_stop(_ambience_player)


## Called by the admin panel's MUSIC ON/OFF toggle. Muting just stops the
## player without forgetting what should be playing; unmuting replays
## whatever the game most recently asked for (level music, menu music,
## ...) without the caller needing to re-request it.
func set_music_enabled(enabled: bool) -> void:
	music_enabled = enabled
	if enabled:
		_play(_music_player, _requested_music, _requested_music_loop)
	else:
		_stop(_music_player)


func set_ambience_enabled(enabled: bool) -> void:
	ambience_enabled = enabled
	if enabled:
		_play(_ambience_player, _requested_ambience, _requested_ambience_loop)
	else:
		_stop(_ambience_player)


func _play(player: AudioStreamPlayer, stream: AudioStream, loop: bool) -> void:
	if stream == null:
		_stop(player)
		return
	if player.stream == stream and player.playing:
		return
	_set_loop(stream, loop)
	player.stream = stream
	player.play()


func _stop(player: AudioStreamPlayer) -> void:
	if player.playing:
		player.stop()
	player.stream = null


func _set_loop(stream: AudioStream, loop: bool) -> void:
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
	elif stream is AudioStreamMP3:
		stream.loop = loop

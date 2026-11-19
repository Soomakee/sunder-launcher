extends Control
## Sunder Launcher.
##
## 1. Reads the newest version number from the latest GitHub Release (version.txt).
## 2. If the installed game is older (or missing), downloads Sunder.zip and installs it
##    into a "game" folder next to this launcher.
## 3. Starts game/Sunder.exe and closes itself.
##
## Offline? It starts whatever version is already installed.
##
## Overrides (for testing), as user args after "--":
##   --base-url=http://localhost:8000   where version.txt and Sunder.zip live
##   --root=C:/some/folder              folder that holds game/ (default: next to the launcher exe)
##   --no-launch                        install only, don't start the game
## A launcher.cfg next to the exe can also set [launcher] base_url="...".

const DEFAULT_BASE_URL := "https://github.com/Soomakee/sunder-launcher/releases/latest/download"
const GAME_EXE := "Sunder.exe"
const ZIP_NAME := "Sunder.zip"
const VERSION_FILE := "version.txt"
const LAUNCH_CLOSE_DELAY := 1.5

var base_url := DEFAULT_BASE_URL
var root_dir := ""
var game_dir := ""
var no_launch := false

var _status: Label
var _detail: Label
var _bar: ProgressBar
var _retry: Button
var _download: HTTPRequest


func _ready() -> void:
	_build_ui()
	_resolve_paths()
	_check_for_update()


func _process(_delta: float) -> void:
	if _download == null:
		return
	var total := _download.get_body_size()
	var got := _download.get_downloaded_bytes()
	if total > 0:
		_bar.value = 100.0 * got / total
		_detail.text = "%.1f / %.1f MB" % [got / 1048576.0, total / 1048576.0]
	else:
		_detail.text = "%.1f MB" % (got / 1048576.0)


# --- Paths and settings -------------------------------------------------------

func _resolve_paths() -> void:
	if OS.has_feature("editor"):
		root_dir = ProjectSettings.globalize_path("user://")
	else:
		root_dir = OS.get_executable_path().get_base_dir()

	var cfg := ConfigFile.new()
	if cfg.load(root_dir.path_join("launcher.cfg")) == OK:
		base_url = String(cfg.get_value("launcher", "base_url", base_url))

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--base-url="):
			base_url = arg.trim_prefix("--base-url=")
		elif arg.begins_with("--root="):
			root_dir = arg.trim_prefix("--root=")
		elif arg == "--no-launch":
			no_launch = true

	base_url = base_url.trim_suffix("/")
	game_dir = root_dir.path_join("game")


func _installed_version() -> String:
	var f := FileAccess.open(game_dir.path_join(VERSION_FILE), FileAccess.READ)
	if f == null or not FileAccess.file_exists(game_dir.path_join(GAME_EXE)):
		return ""
	return f.get_as_text().strip_edges()


# --- Flow ---------------------------------------------------------------------

func _check_for_update() -> void:
	_retry.visible = false
	_bar.value = 0
	_detail.text = ""
	_set_status("Checking for updates...")

	var installed := _installed_version()
	var latest := await _fetch_latest_version()

	if latest == "":
		if installed != "":
			_set_status("Couldn't reach the update server. Starting v%s." % installed)
			_launch()
		else:
			_fail("Couldn't reach the update server, and the game isn't installed yet.\nCheck your internet connection.")
		return

	if latest == installed:
		_bar.value = 100
		_set_status("Up to date (v%s)." % installed)
		_launch()
		return

	if installed == "":
		_set_status("Downloading Sunder v%s..." % latest)
	else:
		_set_status("Updating v%s to v%s..." % [installed, latest])

	var zip_path := root_dir.path_join("download.zip.part")
	if not await _download_file(base_url + "/" + ZIP_NAME, zip_path):
		DirAccess.remove_absolute(zip_path)
		return

	_set_status("Installing v%s..." % latest)
	_detail.text = ""
	await get_tree().process_frame
	var err := _install(zip_path, latest)
	DirAccess.remove_absolute(zip_path)
	if err != "":
		_fail(err)
		return

	_bar.value = 100
	_set_status("Installed v%s." % latest)
	_launch()


func _fetch_latest_version() -> String:
	var req := HTTPRequest.new()
	req.timeout = 15.0
	req.max_redirects = 10
	add_child(req)
	var err := req.request(base_url + "/" + VERSION_FILE)
	if err != OK:
		req.queue_free()
		return ""
	var res: Array = await req.request_completed
	req.queue_free()
	var result: int = res[0]
	var code: int = res[1]
	var body: PackedByteArray = res[3]
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		print("[launcher] version check failed: result=%d http=%d" % [result, code])
		return ""
	var text := body.get_string_from_utf8().strip_edges()
	# A real version is short and on one line; anything else is an error page.
	if text == "" or text.length() > 40 or text.contains("\n") or text.contains("<"):
		print("[launcher] unexpected version.txt content")
		return ""
	return text


func _download_file(url: String, dest: String) -> bool:
	_download = HTTPRequest.new()
	_download.max_redirects = 10
	_download.use_threads = true
	_download.download_file = dest
	_download.download_chunk_size = 262144
	add_child(_download)
	var err := _download.request(url)
	var ok := false
	if err == OK:
		var res: Array = await _download.request_completed
		ok = res[0] == HTTPRequest.RESULT_SUCCESS and res[1] == 200
		if not ok:
			print("[launcher] download failed: result=%d http=%d" % [res[0], res[1]])
	_download.queue_free()
	_download = null
	if not ok:
		_fail("The download failed. Check your internet connection and try again.")
	return ok


## Unzips into game_new/, then swaps it in for game/. Returns "" or an error message.
func _install(zip_path: String, version: String) -> String:
	var staging := root_dir.path_join("game_new")
	var old := root_dir.path_join("game_old")
	_remove_dir(staging)
	_remove_dir(old)
	DirAccess.make_dir_recursive_absolute(staging)

	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK:
		return "The downloaded file is damaged. Try again."
	for entry in zip.get_files():
		var out := staging.path_join(entry)
		if entry.ends_with("/"):
			DirAccess.make_dir_recursive_absolute(out)
			continue
		DirAccess.make_dir_recursive_absolute(out.get_base_dir())
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f == null:
			zip.close()
			return "Couldn't write game files to:\n%s" % root_dir
		f.store_buffer(zip.read_file(entry))
		f.close()
	zip.close()

	if not FileAccess.file_exists(staging.path_join(GAME_EXE)):
		_remove_dir(staging)
		return "The update is missing %s. Tell Saia!" % GAME_EXE

	if DirAccess.dir_exists_absolute(game_dir):
		if DirAccess.rename_absolute(game_dir, old) != OK:
			_remove_dir(staging)
			return "Couldn't replace the old version.\nClose Sunder if it's running, then press Retry."
	if DirAccess.rename_absolute(staging, game_dir) != OK:
		return "Couldn't finish installing into:\n%s" % game_dir

	var vf := FileAccess.open(game_dir.path_join(VERSION_FILE), FileAccess.WRITE)
	if vf:
		vf.store_string(version)
		vf.close()
	_remove_dir(old)
	return ""


func _launch() -> void:
	if no_launch:
		print("[launcher] installed v%s at %s (--no-launch)" % [_installed_version(), game_dir])
		get_tree().quit()
		return
	var pid := OS.create_process(game_dir.path_join(GAME_EXE), [])
	if pid <= 0:
		_fail("Couldn't start the game:\n%s" % game_dir.path_join(GAME_EXE))
		return
	print("[launcher] started v%s (pid %d)" % [_installed_version(), pid])
	_detail.text = "Starting Sunder..."
	await get_tree().create_timer(LAUNCH_CLOSE_DELAY).timeout
	get_tree().quit()


# --- Helpers ------------------------------------------------------------------

func _remove_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var d := DirAccess.open(path)
	if d == null:
		return
	d.include_hidden = true
	for f in d.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for sub in d.get_directories():
		_remove_dir(path.path_join(sub))
	DirAccess.remove_absolute(path)


func _set_status(text: String) -> void:
	_status.text = text
	print("[launcher] " + text)


func _fail(text: String) -> void:
	_set_status(text)
	_detail.text = ""
	_retry.visible = true
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1)


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("16161c")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	var title := Label.new()
	title.text = "SUNDER"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color("e8e2d4"))
	box.add_child(title)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 44
	box.add_child(_status)

	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size.y = 10
	box.add_child(_bar)

	var row := HBoxContainer.new()
	box.add_child(row)
	_detail = Label.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_color_override("font_color", Color("8a8a96"))
	row.add_child(_detail)
	_retry = Button.new()
	_retry.text = "Retry"
	_retry.visible = false
	_retry.pressed.connect(_check_for_update)
	row.add_child(_retry)

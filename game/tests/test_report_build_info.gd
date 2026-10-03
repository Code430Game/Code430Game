extends GdUnitTestSuite
## Build identity for issue reports: the export stamp, and the dev fallback.

var _path: String


func before_test() -> void:
	_path = "user://tmp/build_info_%d.json" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tmp"))


func after_test() -> void:
	if FileAccess.file_exists(_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path))


func test_stamped_build_is_read() -> void:
	var f := FileAccess.open(_path, FileAccess.WRITE)
	f.store_string('{"branch": "main", "commit": "6ac9218abcde", "date": "2026-10-03T10:00:00Z", "dirty": false, "source": "export"}')
	f.close()
	var info := BuildInfo.read(_path)
	assert_str(info["commit"]).is_equal("6ac9218abcde")
	assert_str(info["branch"]).is_equal("main")
	assert_str(info["date"]).is_equal("2026-10-03T10:00:00Z")
	assert_bool(info["dirty"]).is_false()
	assert_str(info["source"]).is_equal("export")


func test_missing_stamp_falls_back_to_dev() -> void:
	var info := BuildInfo.read(_path, false)
	assert_str(info["source"]).is_equal("dev")
	assert_str(info["commit"]).is_equal("unknown")


func test_dev_run_from_the_checkout_names_its_commit() -> void:
	# The test runner runs from source inside the git checkout.
	var info := BuildInfo.read(_path)
	assert_str(info["source"]).is_equal("dev")
	assert_int(str(info["commit"]).length()).is_equal(12)

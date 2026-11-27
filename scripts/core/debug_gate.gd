class_name DebugGate
extends RefCounted
## Central gate for debug-only cheats and overlays (F4, F9-F12).
## Disabled automatically in release exports and when forced off in tests.

static var force_disabled_for_test: bool = false


static func is_debug_enabled() -> bool:
	if force_disabled_for_test:
		return false
	return OS.is_debug_build() or OS.has_feature("debug")

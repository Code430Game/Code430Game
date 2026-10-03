extends RefCounted
## Test helper: the issue report schema and a small checker for it.

const SCHEMA_PATH := "res://../docs/report-format/report.schema.v1.json"


static func schema() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path(SCHEMA_PATH)))


## Errors for `value` against a JSON Schema node: required, additionalProperties false, enum,
## const, type, min/max length, pattern and items. Enough for the report schema, not a general validator.
static func check(value: Variant, node: Dictionary, at: String = "$") -> Array:
	var errors := []
	if node.has("const") and value != node["const"]:
		errors.append("%s: expected %s" % [at, node["const"]])
	if node.has("enum") and not (value in node["enum"]):
		errors.append("%s: %s not in %s" % [at, value, node["enum"]])
	match str(node.get("type", "")):
		"object":
			if not value is Dictionary:
				return errors + ["%s: not an object" % at]
			for k in node.get("required", []):
				if not (value as Dictionary).has(k):
					errors.append("%s: missing %s" % [at, k])
			var props: Dictionary = node.get("properties", {})
			for k in value:
				if not props.has(k):
					errors.append("%s: unknown key %s" % [at, k])
				else:
					errors += check(value[k], props[k], "%s.%s" % [at, k])
		"array":
			if not value is Array:
				return errors + ["%s: not an array" % at]
			if node.has("maxItems") and (value as Array).size() > int(node["maxItems"]):
				errors.append("%s: too many items" % at)
			if node.has("items"):
				for i in range((value as Array).size()):
					errors += check(value[i], node["items"], "%s[%d]" % [at, i])
		"string":
			if not value is String:
				return errors + ["%s: not a string" % at]
			if (value as String).length() > int(node.get("maxLength", 1 << 30)) or (value as String).length() < int(node.get("minLength", 0)):
				errors.append("%s: length %d out of range" % [at, (value as String).length()])
			if node.has("pattern") and RegEx.create_from_string(str(node["pattern"])).search(value) == null:
				errors.append("%s: %s does not match %s" % [at, value, node["pattern"]])
		"integer":
			if not (value is int or (value is float and float(value) == floorf(value))):
				errors.append("%s: not an integer" % at)
		"number":
			if not (value is int or value is float):
				errors.append("%s: not a number" % at)
		"boolean":
			if not value is bool:
				errors.append("%s: not a boolean" % at)
	return errors

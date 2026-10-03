"""The in-game issue report schema, its example, and the build stamp written before exports."""

import json
import subprocess
from pathlib import Path

import pytest
from jsonschema import Draft202012Validator

HERE = Path(__file__).parent
REPO = HERE.parents[1]
SCHEMA = REPO / "docs" / "report-format" / "report.schema.v1.json"
EXAMPLE = HERE / "fixtures" / "report_example.v1.json"


def validator() -> Draft202012Validator:
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema)


def test_example_report_is_valid():
    errors = list(validator().iter_errors(json.loads(EXAMPLE.read_text(encoding="utf-8"))))
    assert errors == []


@pytest.mark.parametrize(
    ("path", "value"),
    [
        (("area",), "bugs"),
        (("severity",), "urgent"),
        (("title",), ""),
        (("title",), "x" * 121),
        (("id",), "not-an-id"),
        (("diagnostics", "session", "role"), "spectator"),
    ],
)
def test_bad_fields_are_rejected(path, value):
    report = json.loads(EXAMPLE.read_text(encoding="utf-8"))
    target = report
    for key in path[:-1]:
        target = target[key]
    target[path[-1]] = value
    assert list(validator().iter_errors(report))


def test_unknown_fields_are_rejected():
    report = json.loads(EXAMPLE.read_text(encoding="utf-8"))
    report["diagnostics"]["machine"]["serial_number"] = "x"
    assert list(validator().iter_errors(report))


def test_build_stamp_matches_the_schema(tmp_path: Path):
    out = tmp_path / "build_info.json"
    subprocess.run(
        [str(REPO / "scripts" / "stamp-build.sh"), str(out)], check=True, capture_output=True
    )
    stamp = json.loads(out.read_text(encoding="utf-8"))
    build_schema = json.loads(SCHEMA.read_text(encoding="utf-8"))["properties"]["diagnostics"][
        "properties"
    ]["build"]
    assert list(Draft202012Validator(build_schema).iter_errors(stamp)) == []
    head = subprocess.run(
        ["git", "-C", str(REPO), "rev-parse", "--short=12", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    assert stamp["commit"] == head and stamp["source"] == "export"

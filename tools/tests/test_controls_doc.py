"""docs/controls.md is generated from the input map and must match it (update-controls-layout 3.1)."""

import controls_doc


def test_committed_doc_matches_the_input_map():
    assert controls_doc.build() == controls_doc.DOC.read_text(), (
        "docs/controls.md is stale: run `uv run python controls_doc.py` in tools/"
    )


def test_bindings_parse_every_event_kind():
    b = controls_doc.parse_input_map(controls_doc.PROJECT.read_text())
    assert b["aim"] == [("key", "right click"), ("pad", "LT")]
    assert ("pad", "L3") in b["horn"]
    assert ("key", "Esc") in b["pause"]
    assert controls_doc.key_name(4194339) == "F8"


def test_only_the_marked_block_is_rewritten():
    doc = f"intro\n{controls_doc.BEGIN}\nold\n{controls_doc.END}\noutro\n"
    assert (
        controls_doc.render(doc, "new")
        == f"intro\n{controls_doc.BEGIN}\nnew\n{controls_doc.END}\noutro\n"
    )


def test_unknown_arguments_are_refused_without_writing(monkeypatch, capsys):
    written = []
    monkeypatch.setattr(
        type(controls_doc.DOC), "write_text", lambda self, text: written.append(text)
    )
    assert controls_doc.main(["--help"]) == 2
    assert controls_doc.main(["--chek"]) == 2
    assert written == []
    assert "unknown argument --help" in capsys.readouterr().err

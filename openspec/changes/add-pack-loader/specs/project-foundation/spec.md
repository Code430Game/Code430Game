## MODIFIED Requirements

### Requirement: Pack Manifest Schema
Every pack SHALL contain a `pack.json` that validates against the published schema for its `schema_version` (v0 frozen, v1 additive with a `content[]` index and type sections), every path in the `content[]` index SHALL exist and validate against its content type's schema, and CI SHALL reject invalid manifests and content.

#### Scenario: Invalid manifest
- **WHEN** a pack under `packs/` has a manifest missing `type`
- **THEN** CI fails with a message naming the pack and the missing field

#### Scenario: Missing content file
- **WHEN** a v1 manifest's `content[]` names `missions/first.json` and the file is absent
- **THEN** CI fails naming the pack and the path

#### Scenario: Old manifest still valid
- **WHEN** a pack keeps a `schema_version: 0` manifest
- **THEN** it validates against v0 and loads unchanged

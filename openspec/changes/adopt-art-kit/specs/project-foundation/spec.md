## ADDED Requirements

### Requirement: Third-Party Art With Licence Receipts
Unmodified third-party art SHALL live in `art/<source>/<pack>/` with a `SOURCE.md` that states the licence, the download links and date, and every file with its sha256, plus the pack's original licence file or, when that can't be fetched, a receipt section linking the public pages that state the licence; only CC0 packs SHALL be committed. Models built from them SHALL live under `game/assets/` beside a `SOURCE.md` naming their source and tool. CI SHALL fail when a receipt is missing, a file is unlisted or changed, or the art exceeds its size budget (120 MB).

#### Scenario: A pack without a CC0 receipt
- **WHEN** a pack folder is added whose `SOURCE.md` lacks a CC0 licence line, or has neither the pack's licence file nor a receipt section
- **THEN** the third-party check fails in CI and names the folder

#### Scenario: A file swapped without a record
- **WHEN** a file in a pack folder is replaced or added without updating its sha256 in `SOURCE.md`
- **THEN** the third-party check fails and names the file

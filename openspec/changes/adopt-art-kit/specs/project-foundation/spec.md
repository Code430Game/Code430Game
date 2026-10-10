## ADDED Requirements

### Requirement: Third-Party Art With Licence Receipts
Third-party art SHALL live in `game/assets/third_party/<source>/<pack>/` with the pack's original licence file, its download link and date, and the list of files taken; only packs whose own licence file is CC0 SHALL be committed, and CI SHALL fail when a receipt is missing or the third-party art exceeds its size budget.

#### Scenario: A pack without a CC0 licence file
- **WHEN** a pack folder is added without a `License.txt` reading CC0
- **THEN** the third-party check fails in CI and names the folder

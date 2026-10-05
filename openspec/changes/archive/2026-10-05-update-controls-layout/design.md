# Design: controls reference and the chosen layout

Xbox names throughout (Steam Deck uses them). PlayStation equivalents: RB = R1, LB = L1,
RT = R2, LT = L2, A = Cross, B = Circle, X = Square, Y = Triangle, View = Select/Share.
Reference layouts are from each game's default gamepad settings as documented by their
guides; they are conventions, not assets, and nothing here copies names, art or text.

## Driving

| action | GTA V | GTA IV | GTA III | Cyberpunk 2077 | Code 430 today | chosen |
|---|---|---|---|---|---|---|
| accelerate | RT | RT | A | RT | RT | RT |
| brake / reverse | LT | LT | X | LT | LT | LT |
| handbrake | RB | X | RB | A | RB (shared with reset, bug) | RB |
| horn | L3 | B | L3 | L3 | none | L3 |
| look behind | R3 | R3 | R3 | - | none | R3 tap |
| reset stuck car | - | - | - | - | RB (bug; doc said R3) | R3 hold 1 s |
| exit vehicle | Y | Y | Y | Y | Y | Y |
| radio | D-left (wheel) | D-up / D-down | LB | RB | none | D-left |
| headlights | D-right | - | - | X | D-up | D-right |
| camera | View | View | View | - | D-down | D-down (deviation) |
| cinematic / duck | B / A | - | - | - | - | later |
| drive-by aim | LB | LB | - | - | - | later |
| map | pause | pause | pause | pause | View | View (deviation) |
| pause | Menu | Start | Start | Menu | Menu | Menu |

## On foot

| action | GTA V | GTA IV | GTA III | Cyberpunk 2077 | Code 430 today | chosen |
|---|---|---|---|---|---|---|
| move / look | LS / RS | LS / RS | LS / RS | LS / RS | LS / RS | same |
| sprint | A | A | A | L3 | L3 | L3 |
| jump | X | - | X | A | A | A |
| crouch / stealth | L3 | L3 | - | B | - | later |
| interact / enter car | Y | Y | Y | Y | Y | Y |
| aim | LT | LT | RB | LT | - | LT (combat) |
| fire | RT | RT | B | RT | - | RT (combat) |
| weapon select | LB wheel | D-left / D-right | LT / RT | Y draw, D-pad quick | - | LB hold wheel, LB tap next |
| reload | B | - | - | X | - | B |
| take cover | RB | RB | - | - | - | later |
| look behind | R3 | R3 | R3 | - | - | R3 |
| phone / log | D-up | D-up | - | - | - | D-up reserved |
| map | View | View | View | - | View | View |
| debug overlay | - | - | - | - | X | X (dev builds) |

## Rules
- Two contexts, `foot` and `drive`; an action belongs to one or both. Within a context no
  gamepad button is bound twice; `test_input_map.gd` enforces it (added with the handbrake
  fix) and the settings page refuses a conflicting rebind.
- Holds are 1 s with a HUD ring; taps release before 0.3 s. Reset is the only hold today.
- The controls doc is generated: `tools/controls_doc.py` reads `project.godot` and a labels
  file and writes `docs/controls.md`; CI fails if the committed doc is stale.
- Bindings saved as overrides in settings keyed by action and context; defaults live in
  `project.godot` so a reset is a delete.

## Decisions for the human
- Camera on D-pad down and map on View, or follow the references (camera View, map in pause)?
- Sprint on L3 (Cyberpunk, current) or A (GTA)? A for sprint moves jump to X.
- Headlights to D-pad right, freeing D-pad up?

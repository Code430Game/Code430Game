# Controls

The on-screen hints switch to whichever device you touched last.

| action | controller | keyboard and mouse |
|---|---|---|
| walk | left stick | W A S D |
| run | L3 (click left stick) | Shift |
| jump | A | Space |
| look around | right stick | click once, then move the mouse (Esc releases it) |
| get in or out of a car | Y | E |
| take a traffic car | Y next to it (host only in co-op) | E next to it |
| accelerate | RT | W |
| brake or reverse | LT | S |
| steer | left stick | A D |
| handbrake | RB | Space |
| reset a stuck car | R3 (click the right stick) while driving | R |
| camera: chase, top-down, high | D-pad down (while driving) | V |
| headlights: auto (dusk to dawn), on, off | D-pad up (while driving) | H |
| map | Back / View | M |
| pause menu | Menu / Start | Esc |
| report a problem | hold Menu / Start for 1 s, or "Report a problem" in the pause menu | F8 (or hold Esc) |
| debug overlay | X | F2 |
| road graph overlay | B with the overlay | F3 |

**Tone** in the pause menu picks the tone mode with left and right: Clean, Gritty (default) or
Dystopia. Billboards along the big roads change their ads with it; in co-op the host's tone is
the session's. `--tone=clean` starts in a mode for the session only.

**Character** in the pause menu opens the creator: up and down pick a row, left and right change
it, A randomises, loads, saves or deletes a preset, B keeps the body and returns. Rows: skin, hair style
and colour, top, jacket and its colour, trousers, shoes, hat, beard, glasses, height, build. The first start
gives you a random body; the last one you made is loaded next time. Saved in `user://characters.json`.

Co-op lives in the pause menu: **Host co-op game** shows the address friends join at;
**Join game** uses the address field (right on the Join line focuses it for the Deck's
on-screen keyboard). Command-line equivalents: `--host[=port]` and `--join=address[:port]`.

Testbed flags worth knowing: `--time=HH` starts the clock at that hour (`--time=23` for night),
`--day-minutes=N` sets how many real minutes a day lasts (default 24), `--mute` silences audio,
`--bus-share=0.5` makes half of the spawned traffic buses (default 8 %).
For screenshots: `--camera=px,py,pz,tx,ty,tz` fixes the view, `--creator` opens the character
creator once the world is up, `--screenshot=path` saves a PNG when the benchmark ends.
`--report` opens "Report a problem" once the world is up, and `--report-send` also saves (and,
with a relay configured, sends) the report.

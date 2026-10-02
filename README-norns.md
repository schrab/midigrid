# midigrid + M-VAVE SMC-PAD on norns

Fork additions for using the M-VAVE / Cuvave SMC-PAD with norns. See the upstream
README / lines forum thread for general midigrid usage.

## What was added

| File | Change |
|------|--------|
| `lib/devices/smc_pad.lua` | Device definition: 4x4 pads as grid (notes 36-51, CH 10), pad LEDs on CH 10 (velocity = color), transport buttons as aux handlers |
| `lib/supported_devices.lua` | Entry matching USB device name `sinco midi 1` (the pad enumerates as "SINCO" with 3 MIDI ports; pads are on port 1) |
| `lib/vgrid.lua` | New layouts: `8x8p` (four 4x4 quads forming a paged virtual 8x8) and `4x4` (single quad) |
| `lib/mod.lua` | `8x8p` / `4x4` added to the SYSTEM > MODS > MIDIGRID size options |

## SMC-PAD MIDI map (factory "MIDI Suite" preset, no changes needed)

| Control | MIDI |
|---------|------|
| Pads Bank A (4x4) | Note On/Off 36-51, CH 10 |
| Pad LEDs | Note On CH 10, velocity = color (0 = off) |
| Pads Bank B | Note On/Off 52-67, CH 10 (left column 52/56/60/64 = direct page select; rest unused) |
| Page LEDs | Bank B left column: vel 32 = current page, vel 5 = others |
| Knobs A / B | CC 30-37 / CC 38-45, CH 1, absolute (both banks always transmit) |
| `<` `>` PLAY PAUSE REC | CC 25-29 CH 1, push (127 press / 0 release) |
| Button LEDs | Note On CH 1, notes 25-29 (PLAY driven: 127 = transport running) |
| PAD BANK / KNOB BANK / NOTE REPEAT / BT | local only, send nothing |

## Behavior on norns

- **Pads** = an 8x8 grid shown as 4 pages of 4x4. Page LED buffers persist while
  switched away. Set SYSTEM > MODS > MIDIGRID > `midigrid size` = `8x8p`.
- **`<` / `>`** = previous / next page.
- **PLAY** = MIDI START to every port enabled in PARAMETERS > CLOCK > "midi clock out"
  (+ resets norns' internal beat phase when the clock source is `internal`).
- **PAUSE** = MIDI STOP. **REC** = RESET (STOP, song position 0, START) — a Volca
  restarts its sequencer at step 1.
  norns keeps sending clock ticks (1/24 beat) to the enabled ports from boot; these
  buttons provide the transport bytes norns doesn't send.
- **Knobs** = norns parameters via built-in MIDI-learn: PARAMETERS > select param >
  LEARN, turn a knob. Mappings persist per script in `<script>.pmap`. All 16 knobs
  (both banks) are learnable.

## Install (norns)

```
cd ~/dust/code
git clone <this fork> midigrid
```

Enable it in SYSTEM > MODS > MIDIGRID (set `midigrid active` = on, `midigrid size` =
`8x8p`). With no SMC-PAD connected, midigrid falls back to the real grid.

## Tests

`lib/tests/led_test.lua`, `device_test.lua`, `raw_midi_test.lua` — include them from a
scratch script to exercise the device.

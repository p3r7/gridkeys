# gridkeys

mod for monome norns, use grid as midi keyboard anywhere.

can send midi message towards currently running script (`in`), external hadware (`out`) or both at the same time (`in+out`).


### usage

when no script is loaded, auto-activates in `out` mode. the target device can be selected in the params menu (`MOD - GRIDKEYS > MIDI OUT device`).

will auto-activate in `in` mode for scripts that don't natively use grid. it can anyway be toggled on/off via param menu (`MOD - GRIDKEYS > gridkeys active`).

in `in` mode, notes will be sent to the input of the `virtual` midi device, which you certainly would have to activate in `SYSTEM > DEVICES > MIDI`.


### gotchas

in `in` mode, playing grid will only take effect if current script listens to the `virtual` midi device.

in `out` mode, playing grid will only take effect if target device is other than `none` and `virtual`.


### future evolutions

right now only `molly_the_polly`-style layout is supported. something like gridstep's would be more versatile.


### example usage

midi `out` mode allows to play grid as a midi keyboard, targeting external hardware.

midi `in` mode is ideal for synth scripts such as:
- `icarus`
- `mx.samples`
- `lissadron` \*
- `sines` \*

\*: those script only listen for the first midi device, so you'd have to have `virtual` in first  position in your global midi config.

additionally, can be used in development phase to debug a supercollider engine.

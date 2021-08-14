# gridkeys

mod for monome norns, use grid as midi keyboard anywhere.

will only take effect for script that listen for input midi notes and don't natively use grid.

notes will be sent to the input of the `virtual` midi device, which you certainly would have to activate in `SYSTEM > DEVICES > MIDI`.

right now only molly-style layout is supported, something like gridstep's would be more versatile.

ideal for scripts such as:
- `icarus`
- `lissadron` \*
- `sines` \*

\*: those script only listen for the first midi device, so you'd have to have `virtual` in first  position in your global midi config.

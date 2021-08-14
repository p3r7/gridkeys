# gridkeys

mod for monome norns, use grid as midi keyboard anywhere.

notes will be sent to the input of the `virtual` midi device iff current script is listening for it (as bound an `event` function to it).

if a script uses grid, this mod won't take effect.

right now only molly-style layout is supported, something like gridstep's would be more versatile.

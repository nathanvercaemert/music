# music

Faust DSP patches for JACK.

This repo no longer targets VCV Rack. Run each `.dsp` file with `faust2jack`
and use Carla's patchbay to visualize and wire the modules together.

## Modules

- `utilities/main.dsp`: clock / trigger generator
- `kicks/909.dsp`: 909-style kick with one trigger input and stereo output

## Run

Start each module as its own JACK client:

```sh
cd /home/music/music
pw-jack faust2jack utilities/main.dsp
pw-jack faust2jack kicks/909.dsp
```

Then open Carla and use the Patchbay view to connect:

- `main` output -> `909` trigger input
- `909` outputs -> your audio output or recorder

## Notes

- `faust2jack` creates JACK clients directly, so Carla is used here as the
  graph and patchbay, not as the DSP host.
- `pw-jack` is included in the examples so this also works on PipeWire JACK
  setups.

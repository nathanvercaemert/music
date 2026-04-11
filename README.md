# music

Faust DSP patches for JACK.

This repo no longer targets VCV Rack. Run each `.dsp` file with `faust2jack`
and use Carla's patchbay to visualize and wire the modules together.

## Modules

- `utilities/main.dsp`: clock / trigger generator
- `utilities/output.dsp`: mono-to-stereo output stage with level control
- `kicks/909.dsp`: 909-style kick with one trigger input and mono output

## Run

Start each module as its own JACK client:

```sh
cd /home/music/music
pw-jack faust2jack utilities/main.dsp
pw-jack faust2jack utilities/output.dsp
pw-jack faust2jack kicks/909.dsp
```

Then open Carla and use the Patchbay view to connect:

- `main` output -> `909` trigger input
- `909` output -> `output` input
- `output` outputs -> your audio output or recorder

## DSP Changes

After changing any `.dsp` file, rebuild and restart the suite before expecting
new controls or DSP behavior to appear in the live RustDesk/SonoBus instance:

```sh
cd /home/music/music
./kick-suite/build.sh
./kick-suite/run.sh
```

`run.sh` is the repo's canonical live-launch path. It rebuilds stale binaries,
restarts the Faust clients, rewires the graph, and refreshes the RustDesk /
SonoBus-facing instance.

## Notes

- `faust2jack` creates JACK clients directly, so Carla is used here as the
  graph and patchbay, not as the DSP host.
- `pw-jack` is included in the examples so this also works on PipeWire JACK
  setups.

## SonoBus

Repo-owned SonoBus config lives at [`kick-suite/sonobus/909-high-quality.xml`](/home/music/music/kick-suite/sonobus/909-high-quality.xml).
It is configured for:

- JACK at `48 kHz`
- stereo send from the output module
- no input compression, gate, EQ, limiter, or reverb
- default send quality set to `PCM 16 bit`

Launch it with the helper script:

```sh
cd /home/music/music
./kick-suite/sonobus-run.sh
```

Saved defaults can live in a local `kick-suite/sonobus.env` file. It is ignored by Git, so you can keep your group and password there without committing them. After creating that file, you can start SonoBus with just:

```sh
cd /home/music/music
./kick-suite/sonobus-run.sh
```

Optional variables:

- `SONOBUS_PASSWORD`
- `SONOBUS_SERVER` defaults to `aoo.sonobus.net:10998`
- `SONOBUS_SETUP` to load a different setup file
- `SONOBUS_ENV_FILE` to load a different env file
- `SONOBUS_DISABLE_RUSTDESK=1` to remove RustDesk audio links and keep SonoBus as the clean program-audio path

The helper script launches SonoBus headless, loads the repo setup, connects
`output:out_0/1` to `SonoBus:in_1/2`, and routes `SonoBus:out_1/2` to hardware
playback.

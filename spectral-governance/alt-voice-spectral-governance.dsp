import("stdfaust.lib");

declare name "alt-voice-spectral-governance";

fxOn = hslider("alt_voice_spectral_governance[style:slider]", 1, 0, 1, 1) : si.smoo;

process(dry, wet) = dry * (1.0 - fxOn) + wet * fxOn;

import("stdfaust.lib");

declare name "send-saturation-spectral-governance";

wet = hslider("wet[style:slider]", 0.0, 0.0, 1.0, 0.001) : si.smoo;

process(dry, fx) = dry * (1.0 - wet) + fx * wet;

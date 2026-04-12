import("stdfaust.lib");

triggerInput = _ > 0.5 : ba.impulsify;
freq = hslider("freq[unit:Hz][style:slider]", 48, 30, 80, 0.1);
decay = hslider("decay[unit:s][style:slider]", 0.9, 0.15, 3.0, 0.01);
decayshape = hslider("decay_shape[style:slider]", -0.2, -1.0, 1.0, 0.001);
pitchdecay = hslider("pitch_decay[unit:s][style:slider]", 0.06, 0.01, 0.25, 0.001);
pitchdecayshape = hslider("pitch_decay_shape[style:slider]", -0.15, -1.0, 1.0, 0.001);
transientlevel = hslider("transient_level[style:slider]", 0.08, 0.0, 0.3, 0.001);
transientdecay = hslider("transient_decay[unit:s][style:slider]", 0.01, 0.001, 0.05, 0.0005);
tone = hslider("tone[style:slider]", 0.35, 0.0, 1.0, 0.001);
level = hslider("level[style:slider]", 0.85, 0.0, 1.0, 0.001);

shapeExponent(shape) = pow(8.0, shape);
shapeEnvelope(shape, env) = max(0.0, min(1.0, pow(max(0.000001, env), shapeExponent(shape))));

kick808(trig) = attach(out, meter : hbargraph("envelope", 0, 1))
with {
  ampEnv = trig : en.ar(0.001, decay) : shapeEnvelope(decayshape);
  pitchEnv = trig : en.ar(0.0008, pitchdecay) : shapeEnvelope(pitchdecayshape);

  oscFreq = max(10.0, freq * (1.0 + 1.2 * pitchEnv));
  body = os.osc(oscFreq) * ampEnv;

  transientEnv = trig : en.ar(0.0003, transientdecay);
  transient = no.noise : fi.bandpass(2, 800, 3000) * transientEnv * transientlevel;

  raw = body + transient;
  cutoff = 180 + tone * 1400;

  out = raw
    : fi.lowpass(1, cutoff)
    : *(level);
  meter = min(1.0, ampEnv + transientEnv * transientlevel);
};

process(trigger) = kick808(triggerInput(trigger));

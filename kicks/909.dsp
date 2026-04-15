import("stdfaust.lib");

triggerInput = _ > 0.5 : ba.impulsify;
freq = hslider("frequency[unit:Hz][style:slider]", 58, 35, 90, 0.1);
decay = hslider("decay[unit:s][style:slider]", 0.32, 0.08, 1.2, 0.01);
decayshape = hslider("decay_shape[style:slider]", 0.0, -1.0, 1.0, 0.001);
pitchdecay = hslider("pitch_decay[unit:s][style:slider]", 0.035, 0.005, 0.12, 0.001);
pitchdecayshape = hslider("pitch_decay_shape[style:slider]", 0.0, -1.0, 1.0, 0.001);
attackdecay = hslider("attack_decay[unit:s][style:slider]", 0.012, 0.001, 0.05, 0.0005);
snaplevel = hslider("snap_level[style:slider]", 0.55, 0.0, 1.0, 0.001);
clicklevel = hslider("click_level[style:slider]", 0.55, 0.0, 1.0, 0.001);
drive = hslider("drive[style:slider]", 1.15, 0.5, 3.0, 0.01);
tone = hslider("tone[style:slider]", 0.62, 0.0, 1.0, 0.001);
level = hslider("level[style:slider]", 0.8, 0.0, 1.0, 0.001);

shapeExponent(shape) = pow(8.0, shape);
shapeEnvelope(shape, env) = max(0.0, min(1.0, pow(max(0.000001, env), shapeExponent(shape))));

kick(trig) = attach(out, meter : hbargraph("envelope", 0, 1))
with {
  ampEnv = trig : en.ar(0.001, decay) : shapeEnvelope(decayshape);
  pitchEnv = trig : en.ar(0.0005, pitchdecay) : shapeEnvelope(pitchdecayshape);

  oscFreq = max(10.0, freq * (1.0 + 2.2 * pitchEnv));
  body = os.osc(oscFreq) * ampEnv;

  atkEnv = trig : en.ar(0.0002, attackdecay);
  snap = no.noise * atkEnv * snaplevel : fi.highpass(1, 2500) : *(0.18);
  clickOsc = os.osc(freq * 5.0) * atkEnv * clicklevel * 0.35;

  raw = body + snap + clickOsc;
  shaped = raw : *(drive) : ma.tanh;
  cutoff = 1200 + tone * 3800;

  out = shaped
    : fi.lowpass(1, cutoff)
    : *(level);
  meter = min(1.0, ampEnv + atkEnv * 0.5);
};

process(trigger) = kick(triggerInput(trigger));

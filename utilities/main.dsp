import("stdfaust.lib");

run = hslider("run[style:checkbox]", 1, 0, 1, 1);
bpm = hslider("bpm [unit:BPM]", 120, 30, 200, 0.1);
alt = hslider("alt[style:slider]", 0, 0, 1, 1);
pulseMs = 10.0;
level = 1.0;

frequency = bpm / 60.0;
pulseSeconds = pulseMs / 1000.0;
pulseDuty = min(0.5, frequency * pulseSeconds);
phase = +(frequency / ma.SR) ~ ma.frac;
gate = run * (phase < pulseDuty);
trigger = gate : ba.impulsify : *(level);
meter = trigger : hbargraph("trigger", 0, 1);
trigger909 = meter * (1.0 - alt);
trigger808 = meter * alt;

process = trigger909, trigger808;

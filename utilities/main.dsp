import("stdfaust.lib");

run = checkbox("run");
bpm = hslider("bpm [unit:BPM]", 120, 30, 200, 0.1);
pulseMs = 10.0;
level = 1.0;

frequency = bpm / 60.0;
pulseSeconds = pulseMs / 1000.0;
pulseDuty = min(0.5, frequency * pulseSeconds);
phase = +(frequency / ma.SR) ~ ma.frac;
trigger = level * run * (phase < pulseDuty);
meter = trigger : hbargraph("trigger", 0, 1);

process = meter;

import("stdfaust.lib");

lp1on = hslider("lp1_on[style:slider]", 0, 0, 1, 1);
lp1freq = hslider("lp1_freq[unit:Hz][style:slider]", 2400, 80, 8000, 1);
lp2on = hslider("lp2_on[style:slider]", 0, 0, 1, 1);
lp2freq = hslider("lp2_freq[unit:Hz][style:slider]", 1400, 80, 8000, 1);
lp3on = hslider("lp3_on[style:slider]", 0, 0, 1, 1);
lp3freq = hslider("lp3_freq[unit:Hz][style:slider]", 700, 80, 8000, 1);
level = hslider("level[style:slider]", 1.0, 0.0, 1.5, 0.001);

lp1(input) = input : fi.lowpass(1, lp1freq);
lp2(input) = input : fi.lowpass(2, lp2freq);
lp3(input) = input : fi.lowpass(1, lp3freq) : fi.lowpass(1, lp3freq);

enabledCount = lp1on + lp2on + lp3on;
mixOrDry(input) =
  (lp1(input) * lp1on + lp2(input) * lp2on + lp3(input) * lp3on)
  / max(1.0, enabledCount)
  + input * (enabledCount < 0.5);

process(input) = mixOrDry(input) * level;

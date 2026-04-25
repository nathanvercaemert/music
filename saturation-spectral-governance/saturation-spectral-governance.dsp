import("stdfaust.lib");

declare name "saturation-spectral-governance";

flavorCtl = vgroup("saturation-spectral-governance", hslider("flavor[style:menu{'punch':0;'vintage':1;'soft_dark':2;'aggro':3}]", 0, 0, 3, 1));
shapeAmountCtl = vgroup("saturation-spectral-governance", hslider("shape_amount[style:slider]", 0.45, 0.0, 1.0, 0.001));
lowpassAmountCtl = vgroup("saturation-spectral-governance", hslider("lowpass_amount[style:slider]", 0.25, 0.0, 1.0, 0.001));
lowpassSlopeCtl = vgroup("saturation-spectral-governance", hslider("lowpass_slope[style:menu{'6_db':0;'12_db':1;'24_db':2;'30_db':3}]", 1, 0, 3, 1));
lowpassCutoffCtl = vgroup("saturation-spectral-governance", hslider("lowpass_cutoff[unit:Hz][style:slider]", 6500, 800, 12000, 1));
fizzModeCtl = vgroup("saturation-spectral-governance", hslider("fizz_mode[style:menu{'off':0;'notch':1;'narrow_bell':2}]", 1, 0, 2, 1));
fizzFreqCtl = vgroup("saturation-spectral-governance", hslider("fizz_freq[unit:Hz][style:slider]", 3200, 1000, 7000, 1));
fizzQCtl = vgroup("saturation-spectral-governance", hslider("fizz_q[style:slider]", 6.0, 2.0, 20.0, 0.001));
fizzAmountCtl = vgroup("saturation-spectral-governance", hslider("fizz_amount[style:slider]", 0.25, 0.0, 1.0, 0.001));
fizzDynamicCtl = vgroup("saturation-spectral-governance", hslider("fizz_dynamic[style:checkbox]", 1, 0, 1, 1));
outLevelCtl = vgroup("output", hslider("level[style:slider]", 1.0, 0.0, 1.5, 0.001));

selectFlavor(a, b, c, d) = ba.if(flavorCtl < 0.5, a, ba.if(flavorCtl < 1.5, b, ba.if(flavorCtl < 2.5, c, d)));
selectSlope(a, b, c, d) = ba.if(lowpassSlopeCtl < 0.5, a, ba.if(lowpassSlopeCtl < 1.5, b, ba.if(lowpassSlopeCtl < 2.5, c, d)));

clamp01(x) = min(1.0, max(0.0, x));
safeFreq(x) = max(10.0, min(ma.SR * 0.45, x));
safeQ(x) = max(0.2, x);
smoothCtl(x) = x : si.smoo;
db2linear(db) = pow(10.0, db / 20.0);

shapeS = clamp01(smoothCtl(shapeAmountCtl));
lpfS = clamp01(smoothCtl(lowpassAmountCtl));
fizzS = clamp01(smoothCtl(fizzAmountCtl));
fizzHz = safeFreq(smoothCtl(fizzFreqCtl));
fizzQ = safeQ(smoothCtl(fizzQCtl));
levelS = smoothCtl(outLevelCtl);

splitLowShelf(gainDb, freq, x) = low * db2linear(gainDb) + high
with {
  low = x : fi.lowpass(1, safeFreq(freq));
  high = x - low;
};

splitHighShelf(gainDb, freq, x) = low + high * db2linear(gainDb)
with {
  low = x : fi.lowpass(1, safeFreq(freq));
  high = x - low;
};

tiltEq(amt, pivotHz, x) = low * lowGain + high * highGain
with {
  low = x : fi.lowpass(1, safeFreq(pivotHz));
  high = x - low;
  lowGain = db2linear(0.0 - amt * 3.0);
  highGain = db2linear(amt * 3.0);
};

shapeStage(x) = x
  : splitLowShelf(lowLiftDb, lowHz)
  : fi.peak_eq_cq(0.0 - boxCutDb, boxHz, boxQ)
  : fi.peak_eq_cq(clickGainDb, clickHz, clickQ)
  : splitHighShelf(highShelfDb, highShelfHz)
  : tiltEq(tiltAmt, 900.0)
with {
  lowHz = selectFlavor(80.0, 150.0, 95.0, 120.0);
  lowLiftDb = shapeS * selectFlavor(2.2, 1.5, 0.8, 1.8);

  boxHz = selectFlavor(330.0, 280.0, 430.0, 360.0);
  boxQ = selectFlavor(0.85, 0.75, 0.70, 1.10);
  boxCutDb = shapeS * selectFlavor(1.8, 0.8, 1.2, 2.8);

  clickHz = selectFlavor(2600.0, 1800.0, 2200.0, 3600.0);
  clickQ = selectFlavor(0.95, 0.80, 0.75, 1.25);
  clickGainDb = shapeS * selectFlavor(0.9, -0.8, -1.4, 0.3);

  highShelfHz = selectFlavor(4200.0, 3600.0, 3000.0, 5200.0);
  highShelfDb = shapeS * selectFlavor(0.2, -1.0, -1.8, -0.5);
  tiltAmt = shapeS * selectFlavor(0.05, -0.16, -0.32, -0.08);
};

lowpassStage(x) = x * (1.0 - lpfS) + filtered * lpfS
with {
  baseCutoff = safeFreq(smoothCtl(lowpassCutoffCtl));
  flavorDarken = selectFlavor(0.08, 0.18, 0.36, 0.42);
  cutoff = safeFreq(baseCutoff * (1.0 - lpfS * flavorDarken));
  filtered = selectSlope(
    x : fi.lowpass(1, cutoff),
    x : fi.lowpass(2, cutoff),
    x : fi.lowpass(4, cutoff),
    x : fi.lowpass(5, cutoff)
  );
};

fizzDynamicScale(x, band) = ba.if(fizzDynamicCtl > 0.5, activity, 1.0)
with {
  bandEnv = abs(band) : an.amp_follower_ud(0.001, 0.070);
  bodyEnv = abs(x) : an.amp_follower_ud(0.006, 0.140);
  threshold = max(0.004, bodyEnv * selectFlavor(0.35, 0.48, 0.42, 0.28));
  sensitivity = selectFlavor(7.0, 5.5, 6.0, 10.0);
  activity = clamp01(max(0.0, bandEnv - threshold) * sensitivity);
};

fizzNotch(x) = x - band * depth
with {
  band = x : fi.svf.bp(fizzHz, fizzQ);
  scale = fizzDynamicScale(x, band);
  depth = fizzS * scale * selectFlavor(0.55, 0.30, 0.40, 0.85);
};

fizzBell(x) = x : fi.peak_eq_cq(0.0 - cutDb, fizzHz, fizzQ)
with {
  band = x : fi.svf.bp(fizzHz, fizzQ);
  scale = fizzDynamicScale(x, band);
  cutDb = fizzS * scale * selectFlavor(6.0, 3.5, 4.5, 9.0);
};

fizzStage(x) = ba.if(fizzModeCtl < 0.5, x, ba.if(fizzModeCtl < 1.5, fizzNotch(x), fizzBell(x)));

stageSaturationSpectralGovernance(x) = x
  : fi.dcblockerat(15)
  : shapeStage
  : lowpassStage
  : fizzStage
  : *(levelS);

process(input) = stageSaturationSpectralGovernance(input);

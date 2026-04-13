import("stdfaust.lib");

declare name "voice-spectral-governance";

macroFlavor = vgroup("macro", hslider("flavor[style:menu{'club':0;'vintage':1;'ambient':2;'industrial':3}]", 0, 0, 3, 1));
outputLevel = vgroup("output", hslider("level[style:slider]", 1.0, 0.0, 1.5, 0.001));

hpfOn = vgroup("hpf", hslider("on[style:checkbox]", 1, 0, 1, 1));
hpfFamily = vgroup("hpf", hslider("family[style:menu{'butterworth':0;'percussive':1}]", 0, 0, 1, 1));
hpfSlope = vgroup("hpf", hslider("slope[style:menu{'12dB':0;'18dB':1;'24dB':2}]", 1, 0, 2, 1));
hpfCutoff = vgroup("hpf", hslider("cutoff[unit:Hz][style:slider]", 28, 15, 120, 0.1));
hpfResonance = vgroup("hpf", hslider("resonance[style:slider]", 0.58, 0.4, 1.2, 0.001));

subMode = vgroup("sub_cleanup", hslider("mode[style:menu{'off':0;'low_shelf':1;'wide_bell':2;'dynamic_low_band':3}]", 1, 0, 3, 1));
subFreq = vgroup("sub_cleanup", hslider("freq[unit:Hz][style:slider]", 72, 35, 180, 0.1));
subAmount = vgroup("sub_cleanup", hslider("amount[unit:dB][style:slider]", 3.0, 0.0, 12.0, 0.1));
subQ = vgroup("sub_cleanup", hslider("q[style:slider]", 0.7, 0.2, 2.0, 0.001));
subDynThreshold = vgroup("sub_cleanup", hslider("dynamic_threshold[style:slider]", 0.10, 0.01, 0.8, 0.001));
subDynAmount = vgroup("sub_cleanup", hslider("dynamic_amount[style:slider]", 0.55, 0.0, 1.0, 0.001));

preEq1On = vgroup("pre_eq_1", hslider("on[style:checkbox]", 0, 0, 1, 1));
preEq1Freq = vgroup("pre_eq_1", hslider("freq[unit:Hz][style:slider]", 280, 80, 1200, 0.1));
preEq1Cut = vgroup("pre_eq_1", hslider("cut[unit:dB][style:slider]", 3.0, 0.0, 18.0, 0.1));
preEq1Q = vgroup("pre_eq_1", hslider("q[style:slider]", 0.9, 0.25, 8.0, 0.001));

preEq2On = vgroup("pre_eq_2", hslider("on[style:checkbox]", 0, 0, 1, 1));
preEq2Freq = vgroup("pre_eq_2", hslider("freq[unit:Hz][style:slider]", 420, 80, 2500, 0.1));
preEq2Cut = vgroup("pre_eq_2", hslider("cut[unit:dB][style:slider]", 2.5, 0.0, 18.0, 0.1));
preEq2Q = vgroup("pre_eq_2", hslider("q[style:slider]", 1.2, 0.25, 8.0, 0.001));

preEq3On = vgroup("pre_eq_3", hslider("on[style:checkbox]", 0, 0, 1, 1));
preEq3Freq = vgroup("pre_eq_3", hslider("freq[unit:Hz][style:slider]", 900, 120, 5000, 0.1));
preEq3Cut = vgroup("pre_eq_3", hslider("cut[unit:dB][style:slider]", 2.0, 0.0, 18.0, 0.1));
preEq3Q = vgroup("pre_eq_3", hslider("q[style:slider]", 2.0, 0.25, 10.0, 0.001));

resMode = vgroup("resonance", hslider("mode[style:menu{'off':0;'static':1;'dynamic':2;'tail_tamer':3}]", 2, 0, 3, 1));
resFlavor = vgroup("resonance", hslider("flavor[style:menu{'transparent':0;'surgical':1;'character':2}]", 0, 0, 2, 1));
resFreq = vgroup("resonance", hslider("freq[unit:Hz][style:slider]", 95, 40, 5000, 0.1));
resQ = vgroup("resonance", hslider("q[style:slider]", 4.0, 0.5, 20.0, 0.001));
resDepth = vgroup("resonance", hslider("depth[style:slider]", 0.45, 0.0, 1.2, 0.001));
resThreshold = vgroup("resonance", hslider("threshold[style:slider]", 0.08, 0.005, 0.8, 0.001));
resSensitivity = vgroup("resonance", hslider("sensitivity[style:slider]", 4.0, 0.5, 12.0, 0.01));

midMode = vgroup("mid_focus", hslider("mode[style:menu{'off':0;'band_blend':1;'bell':2;'macro_eq':3}]", 1, 0, 3, 1));
midFlavor = vgroup("mid_focus", hslider("flavor[style:menu{'knock':0;'definition':1;'click':2}]", 1, 0, 2, 1));
midFreq = vgroup("mid_focus", hslider("freq[unit:Hz][style:slider]", 1800, 120, 5000, 1));
midQ = vgroup("mid_focus", hslider("q[style:slider]", 1.1, 0.3, 10.0, 0.001));
midGain = vgroup("mid_focus", hslider("gain[unit:dB][style:slider]", 3.0, 0.0, 12.0, 0.1));
midBlend = vgroup("mid_focus", hslider("blend[style:slider]", 0.35, 0.0, 1.0, 0.001));
midBoxCut = vgroup("mid_focus", hslider("box_cut[unit:dB][style:slider]", 2.5, 0.0, 12.0, 0.1));
midExtraHpfOn = vgroup("mid_focus", hslider("extra_hpf_on[style:checkbox]", 0, 0, 1, 1));
midExtraHpfFreq = vgroup("mid_focus", hslider("extra_hpf_freq[unit:Hz][style:slider]", 120, 50, 1200, 1));

selectFlavor(a, b, c, d) = ba.if(macroFlavor < 0.5, a, ba.if(macroFlavor < 1.5, b, ba.if(macroFlavor < 2.5, c, d)));
selectMidFlavor(a, b, c) = ba.if(midFlavor < 0.5, a, ba.if(midFlavor < 1.5, b, c));

clamp01(x) = min(1.0, max(0.0, x));
smoothCtl(x) = x : si.smoo;
safeFreq(x) = max(10.0, min(ma.SR * 0.45, x));
safeQ(x) = max(0.2, x);
mode0(x) = x < 0.5;
mode1(x) = (x >= 0.5) & (x < 1.5);
mode2(x) = (x >= 1.5) & (x < 2.5);
mode3(x) = x >= 2.5;

macroHpfOffset = selectFlavor(0.0, 8.0, -6.0, 10.0);
macroSubGain = selectFlavor(0.5, 2.0, -0.5, 1.5);
macroResGain = selectFlavor(0.0, 0.05, -0.10, 0.12);
macroMidGain = selectFlavor(0.5, -0.5, -1.0, 1.5);

effectiveHpfCutoff = safeFreq(smoothCtl(hpfCutoff + macroHpfOffset));
effectiveSubFreq = safeFreq(smoothCtl(subFreq));
effectiveSubAmount = max(0.0, smoothCtl(subAmount + macroSubGain));
effectiveResDepth = clamp01(smoothCtl(resDepth + macroResGain));
effectiveMidGain = max(0.0, smoothCtl(midGain + macroMidGain));
effectiveMidFreq = safeFreq(smoothCtl(midFreq));

butterHpf(x) =
  x : fi.highpass(2, effectiveHpfCutoff) * mode0(hpfSlope)
  + x : fi.highpass(3, effectiveHpfCutoff) * mode1(hpfSlope)
  + x : fi.highpass(4, effectiveHpfCutoff) * (mode2(hpfSlope) | mode3(hpfSlope));

percussiveHpf(x) =
  x : fi.svf.hp(effectiveHpfCutoff, safeQ(smoothCtl(hpfResonance))) * mode0(hpfSlope)
  + x : fi.svf.hp(effectiveHpfCutoff, safeQ(smoothCtl(hpfResonance))) : fi.highpass(1, effectiveHpfCutoff) * mode1(hpfSlope)
  + x : fi.svf.hp(effectiveHpfCutoff, safeQ(smoothCtl(hpfResonance))) : fi.svf.hp(effectiveHpfCutoff, safeQ(smoothCtl(hpfResonance))) * (mode2(hpfSlope) | mode3(hpfSlope));

hpfStage(x) = x * (1 - hpfOn) + hpfOn * (
  butterHpf(x) * (1 - hpfFamily)
  + percussiveHpf(x) * hpfFamily
);

dynamicLowCleanup(x) = highBand + lowBand * (1.0 - reduction)
with {
  lowBand = x : fi.lowpass(2, effectiveSubFreq);
  highBand = x - lowBand;
  lowEnv = abs(lowBand) : an.amp_follower_ud(0.001, 0.080);
  over = max(0.0, lowEnv - smoothCtl(subDynThreshold));
  reduction = clamp01(over * smoothCtl(subDynAmount) * 8.0);
};

subCleanupStage(x) =
  x * mode0(subMode)
  + (x : fi.low_shelf(-effectiveSubAmount, effectiveSubFreq)) * mode1(subMode)
  + (x : fi.peak_eq_cq(-effectiveSubAmount, effectiveSubFreq, safeQ(smoothCtl(subQ)))) * mode2(subMode)
  + dynamicLowCleanup(x) * mode3(subMode);

cutBand(on, freq, cutDb, q, x) = x * (1 - on) + (x : fi.peak_eq_cq(0.0 - max(0.0, smoothCtl(cutDb)), safeFreq(smoothCtl(freq)), safeQ(smoothCtl(q)))) * on;

preEqStage(x) = x
  : cutBand(preEq1On, preEq1Freq, preEq1Cut, preEq1Q)
  : cutBand(preEq2On, preEq2Freq, preEq2Cut, preEq2Q)
  : cutBand(preEq3On, preEq3Freq, preEq3Cut, preEq3Q);

resQFlavor = safeQ(smoothCtl(resQ) * selectFlavor(1.0, 1.0, 1.0, 1.0) * ba.if(resFlavor < 0.5, 0.85, ba.if(resFlavor < 1.5, 1.5, 1.1)));
resAtk = ba.if(resFlavor < 0.5, 0.004, ba.if(resFlavor < 1.5, 0.0015, 0.006));
resRel = ba.if(resFlavor < 0.5, 0.080, ba.if(resFlavor < 1.5, 0.040, 0.120));

resonanceStage(x) = x - resonanceBand * clampAmount
with {
  resonanceBand = x : fi.svf.bp(safeFreq(smoothCtl(resFreq)), resQFlavor);
  bandEnv = abs(resonanceBand) : an.amp_follower_ud(resAtk, resRel);
  bodyFast = abs(x) : an.amp_follower_ud(0.001, 0.030);
  bodySlow = abs(x) : an.amp_follower_ud(0.020, 0.180);
  tailWeight = clamp01((bodySlow - bodyFast) / max(0.001, bodySlow));
  dynamicDrive = clamp01(max(0.0, bandEnv - smoothCtl(resThreshold)) * smoothCtl(resSensitivity));
  staticClamp = effectiveResDepth;
  dynamicClamp = effectiveResDepth * dynamicDrive;
  tailClamp = effectiveResDepth * dynamicDrive * tailWeight;
  clampAmount =
    mode0(resMode) * 0.0
    + mode1(resMode) * staticClamp
    + mode2(resMode) * dynamicClamp
    + mode3(resMode) * tailClamp;
};

midFlavorFreq = selectMidFlavor(320.0, 1800.0, 3500.0);
midFlavorQMul = selectMidFlavor(0.85, 1.0, 1.25);
midFlavorBoxFreq = selectMidFlavor(260.0, 360.0, 480.0);

midFocusSource(x) = x * (1 - midExtraHpfOn) + (x : fi.highpass(1, safeFreq(smoothCtl(midExtraHpfFreq)))) * midExtraHpfOn;

midBandBlend(x) = x * (1.0 - smoothCtl(midBlend)) + focused * smoothCtl(midBlend)
with {
  focused = midFocusSource(x) : fi.svf.bp(effectiveMidFreq * (midFlavorFreq / max(1.0, midFreq)), safeQ(smoothCtl(midQ) * midFlavorQMul)) : *(ba.db2linear(effectiveMidGain));
};

midBell(x) = x : fi.peak_eq_cq(effectiveMidGain, effectiveMidFreq * (midFlavorFreq / max(1.0, midFreq)), safeQ(smoothCtl(midQ) * midFlavorQMul));

midMacroEq(x) = x
  : fi.peak_eq_cq(effectiveMidGain, effectiveMidFreq * (midFlavorFreq / max(1.0, midFreq)), safeQ(smoothCtl(midQ) * midFlavorQMul))
  : fi.peak_eq_cq(0.0 - max(0.0, smoothCtl(midBoxCut)), midFlavorBoxFreq, 0.8);

midFocusStage(x) =
  x * mode0(midMode)
  + midBandBlend(x) * mode1(midMode)
  + midBell(x) * mode2(midMode)
  + midMacroEq(x) * mode3(midMode);

govern(x) = x
  : fi.dcblockerat(15)
  : hpfStage
  : subCleanupStage
  : preEqStage
  : resonanceStage
  : midFocusStage
  : *(outputLevel);

process(input) = govern(input);

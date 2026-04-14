import("stdfaust.lib");

declare name "voice-spectral-governance";

macroFlavor      = vgroup("voice-spectral-governance", hslider("flavor[style:menu{'club':0;'vintage':1;'ambient':2;'industrial':3}]", 0, 0, 3, 1));
cleanCtl         = vgroup("voice-spectral-governance", hslider("clean[style:slider]", 0.45, 0.0, 1.0, 0.001));
ringFreqCtl      = vgroup("voice-spectral-governance", hslider("ring_freq[unit:Hz][style:slider]", 95, 30, 300, 0.1));
ringCtl          = vgroup("voice-spectral-governance", hslider("ring_tame[style:slider]", 0.35, 0.0, 1.0, 0.001));
attackShapeFlavor = vgroup("voice-spectral-governance", hslider("attack_shape_flavor[style:menu{'knock':0;'definition':1;'click':2}]", 1, 0, 2, 1));
attackShapeCtl    = vgroup("voice-spectral-governance", hslider("attack_shape[style:slider]", 0.35, 0.0, 1.0, 0.001));
attackShapeQCtl   = vgroup("voice-spectral-governance", hslider("attack_shape_q[style:slider]", 1.0, 0.5, 3.0, 0.001));
outLevelCtl      = vgroup("output", hslider("level[style:slider]", 1.0, 0.0, 1.5, 0.001));

selectFlavor(a, b, c, d) = ba.if(macroFlavor < 0.5, a, ba.if(macroFlavor < 1.5, b, ba.if(macroFlavor < 2.5, c, d)));
selectAtkFlavor(a, b, c) = ba.if(attackShapeFlavor < 0.5, a, ba.if(attackShapeFlavor < 1.5, b, c));

clamp01(x)   = min(1.0, max(0.0, x));
smoothCtl(x) = x : si.smoo;
safeFreq(x)  = max(10.0, min(ma.SR * 0.45, x));
safeQ(x)     = max(0.2, x);

cleanS       = clamp01(smoothCtl(cleanCtl));
ringS        = clamp01(smoothCtl(ringCtl));
attackShapeS = clamp01(smoothCtl(attackShapeCtl));
attackShapeQ = safeQ(smoothCtl(attackShapeQCtl));
levelS       = smoothCtl(outLevelCtl);

cleanC  = cleanS * cleanS;

hpfBase = selectFlavor(22.0, 28.0, 18.0, 35.0);
hpfLift = selectFlavor(55.0, 45.0, 40.0, 70.0);
hpfHz   = safeFreq(hpfBase + cleanC * hpfLift);

subBase     = selectFlavor(72.0, 80.0, 68.0, 90.0);
subLift     = selectFlavor(15.0, 12.0, 12.0, 18.0);
subHz       = safeFreq(subBase + cleanC * subLift);
subThr      = max(0.02, 0.18 - 0.14 * cleanS);
subStrength = 8.0 + 16.0 * cleanS;
subMaxRed   = 0.60 * cleanS;

mudHz     = selectFlavor(280.0, 320.0, 250.0, 360.0);
mudQ      = selectFlavor(0.90, 1.00, 0.80, 1.20);
mudCutMax = selectFlavor(6.0, 8.0, 5.0, 10.0);
mudCutDb  = cleanC * mudCutMax;

ringHz     = safeFreq(smoothCtl(ringFreqCtl));
ringQBase  = selectFlavor(3.5, 3.0, 4.5, 6.0);
ringQ      = safeQ(ringQBase + ringS * 3.0);
ringAtk    = selectFlavor(0.0040, 0.0050, 0.0060, 0.0025);
ringRel    = selectFlavor(0.0800, 0.1000, 0.1300, 0.0550);
ringThr    = max(0.01, 0.12 - 0.09 * ringS);
ringSens   = 2.0 + 10.0 * ringS;
ringDepth  = 1.10 * ringS;

midBaseHz  = selectAtkFlavor(800.0, 1800.0, 3500.0);
midMul     = selectFlavor(1.00, 0.90, 1.05, 1.15);
midHz      = safeFreq(midBaseHz * midMul);

midQBase   = selectAtkFlavor(0.85, 1.10, 1.35);
midQ       = safeQ(midQBase * attackShapeQ * selectFlavor(0.95, 0.90, 1.00, 1.10));

midGainMax = selectFlavor(10.0, 8.0, 7.0, 12.0);
midGainDb  = attackShapeS * midGainMax;

boxBaseHz  = selectAtkFlavor(260.0, 360.0, 480.0);
boxHz      = safeFreq(boxBaseHz * selectFlavor(1.00, 0.90, 1.10, 1.10));
boxCutMax  = selectAtkFlavor(3.5, 4.5, 2.5);
boxAmt     = clamp01(attackShapeS * 0.95 + cleanC * 0.25);
boxCutDb   = boxCutMax * boxAmt;

hpfStage(x) = x : fi.highpass(4, hpfHz);

dynamicLowCleanup(x) = highBand + lowBand * (1.0 - reduction)
with {
  lowBand   = x : fi.lowpass(2, subHz);
  highBand  = x - lowBand;
  lowEnv    = abs(lowBand) : an.amp_follower_ud(0.001, 0.080);
  over      = max(0.0, lowEnv - subThr);
  redRaw    = clamp01(over * subStrength);
  reduction = redRaw * subMaxRed;
};

mudStage(x) = x : fi.peak_eq_cq(0.0 - mudCutDb, mudHz, mudQ);

ringTamer(x) = x - ringBand * clampAmount
with {
  ringBand    = x : fi.svf.bp(ringHz, ringQ);
  bandEnv     = abs(ringBand) : an.amp_follower_ud(ringAtk, ringRel);
  bodyFast    = abs(x) : an.amp_follower_ud(0.001, 0.030);
  bodySlow    = abs(x) : an.amp_follower_ud(0.020, 0.180);
  tailWeight  = clamp01((bodySlow - bodyFast) / max(0.001, bodySlow));
  drive       = clamp01(max(0.0, bandEnv - ringThr) * ringSens);
  clampAmount = ringDepth * drive * (0.35 + 0.65 * tailWeight);
};

midFocus(x) = x
  : fi.peak_eq_cq(midGainDb, midHz, midQ)
  : fi.peak_eq_cq(0.0 - boxCutDb, boxHz, 0.85);

stageVoiceSpectralGovernance(x) = x
  : fi.dcblockerat(15)
  : dynamicLowCleanup
  : mudStage
  : ringTamer
  : midFocus
  : *(levelS);

process(input) = stageVoiceSpectralGovernance(input);

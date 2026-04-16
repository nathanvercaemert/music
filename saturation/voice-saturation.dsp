import("stdfaust.lib");

declare name "voice-saturation";

satFlavorCtl = vgroup("voice-saturation", hslider("flavor[style:menu{'neutral_soft':0;'warm_asym':1;'edge_soft':2;'tube_clean':3;'tube_driven':4;'tape_smooth':5;'tape_hot':6;'hard_clip':7;'diode_clip':8;'rectify':9;'wavefold':10}]", 0, 0, 10, 1));
driveCtl     = vgroup("voice-saturation", hslider("drive[style:slider]", 0.32, 0.0, 1.0, 0.001));
toneCtl      = vgroup("voice-saturation", hslider("tone[style:slider]", 0.5, 0.0, 1.0, 0.001));
trimCtl      = vgroup("output", hslider("level[style:slider]", 1.0, 0.0, 1.5, 0.001));

clamp01(x) = min(1.0, max(0.0, x));
clamp(x, lo, hi) = min(hi, max(lo, x));
smoothCtl(x) = x : si.smoo;

driveS = clamp01(smoothCtl(driveCtl));
toneS  = clamp01(smoothCtl(toneCtl));
trimS  = smoothCtl(trimCtl);

toneTilt = (toneS - 0.5) * 2.0;
driveAmt = 1.0 + driveS * 10.0;
satFlavor = satFlavorCtl;

select11(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10) =
  ba.if(satFlavor < 0.5, a0,
    ba.if(satFlavor < 1.5, a1,
      ba.if(satFlavor < 2.5, a2,
        ba.if(satFlavor < 3.5, a3,
          ba.if(satFlavor < 4.5, a4,
            ba.if(satFlavor < 5.5, a5,
              ba.if(satFlavor < 6.5, a6,
                ba.if(satFlavor < 7.5, a7,
                  ba.if(satFlavor < 8.5, a8,
                    ba.if(satFlavor < 9.5, a9, a10))))))))));

tiltEq(x, amt, pivotHz) = low * lowGain + high * highGain
with {
  low = x : fi.lowpass(1, pivotHz);
  high = x - low;
  lowGain = pow(10.0, (-amt * 3.0) / 20.0);
  highGain = pow(10.0, (amt * 3.0) / 20.0);
};

postTone(x) = tiltEq(x, toneTilt, 700.0);
dcSafe(x) = x : fi.dcblockerat(15);

softSym(x, knee) = ma.tanh(x * knee) / max(0.0001, ma.tanh(knee));
softAsym(x, drive, bias, knee) = dcSafe(shaped)
with {
  pos = ma.tanh((x * drive + bias) * knee);
  neg = ma.tanh((x * drive - bias) * (knee * 0.82));
  shaped = (pos + neg) * 0.5;
};

softCubic(x, drive, edge) = clamp(driven - edge * driven * driven * driven, -1.2, 1.2)
with {
  driven = x * drive;
};

hardClip(x, thresh) = min(thresh, max(-thresh, x)) / max(0.001, thresh);
fullRectify(x, drive) = dcSafe(abs(x * drive) * 2.0 - 1.0);
wavefold(x, drive, amount) = sin(x * drive * (1.0 + amount * 2.5));

tubeStage(x, drive, bias, knee, dampHz) = dcSafe(shaped) : fi.lowpass(1, dampHz)
with {
  shaped = softAsym(x, drive, bias, knee);
};

tapeStage(x, drive, preAmt, postAmt, dampHz, compAmt) = tapeOut
with {
  pre = tiltEq(x, preAmt, 900.0);
  shaped = softAsym(pre, drive, 0.06 + compAmt * 0.03, 1.2 + compAmt * 0.7);
  compressed = shaped / (1.0 + abs(shaped) * (0.18 + compAmt * 0.22));
  tapeOut = tiltEq(compressed : fi.lowpass(1, dampHz), -postAmt, 1100.0);
};

diodeStage(x, drive, thresh, dampHz) = dcSafe(hardClip(pre, thresh)) : fi.lowpass(1, dampHz)
with {
  pre = x * drive;
};

variantDrive = select11(1.5, 1.7, 1.9, 1.55, 1.85, 1.5, 1.85, 2.2, 2.1, 1.8, 2.3);
variantBias  = select11(0.0, 0.08, 0.02, 0.07, 0.13, 0.05, 0.09, 0.0, 0.02, 0.18, 0.0);
variantKnee  = select11(1.4, 1.3, 2.2, 1.25, 1.7, 1.2, 1.55, 3.0, 2.4, 1.0, 2.6);
variantTrim  = select11(0.88, 0.84, 0.82, 0.9, 0.84, 0.88, 0.8, 0.72, 0.76, 0.7, 0.68);

stageCore(x) = select11(
  softSym(x, variantKnee * driveAmt) * 0.98,
  softAsym(x, 1.0 + driveAmt * variantDrive, variantBias + driveS * 0.12, variantKnee),
  softCubic(x, 1.0 + driveAmt * 0.85, 0.12 + driveS * 0.08),
  tubeStage(x, 1.0 + driveAmt * 0.8, 0.05 + driveS * 0.05, 1.15, 5200.0 - driveS * 1400.0),
  tubeStage(x, 1.0 + driveAmt * 1.05, 0.11 + driveS * 0.09, 1.45, 4600.0 - driveS * 1500.0),
  tapeStage(x, 1.0 + driveAmt * 0.72, 0.18 + toneTilt * 0.14, 0.16 + driveS * 0.04, 5000.0 - driveS * 1700.0, 0.22 + driveS * 0.18),
  tapeStage(x, 1.0 + driveAmt * 0.98, 0.24 + toneTilt * 0.12, 0.22 + driveS * 0.07, 3900.0 - driveS * 1500.0, 0.38 + driveS * 0.25),
  hardClip(x * (1.0 + driveAmt * 1.2), 0.72 - driveS * 0.18),
  diodeStage(x, 1.0 + driveAmt * 1.1, 0.82 - driveS * 0.16, 4200.0 - driveS * 1300.0),
  fullRectify(x, 1.0 + driveAmt * 0.95),
  wavefold(x, 1.0 + driveAmt * 1.05, driveS)
);

stageVoiceSaturation(x) = x
  : postTone
  : stageCore
  : *(variantTrim)
  : *(trimS);

process(input) = stageVoiceSaturation(input);

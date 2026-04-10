import("stdfaust.lib");

level = hslider("level[style:slider]", 0.8, 0.0, 1.0, 0.001);

process(input) = input * level, input * level;

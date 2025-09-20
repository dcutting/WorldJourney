#ifndef Sculpt_h
#define Sculpt_h

float4 quintic(float4 g);
float4 sculpt(float4 g, constant float2 shape[], int shapeCount);

constant float2 continentalShape[] = {
  float2(-0.89, -4000),
  float2(-0.2, -3000),
  float2(-0.05, -200),
  float2(0.0, 0),
  float2(0.01, 200),
  float2(0.3, 840)
};

constant float2 plateauShape[] = {
  float2(0.0, 0),
  float2(0.1, 0.1),
  float2(0.3, 1)
};

constant float2 craterShape[] = {
  float2(0.0, 1),
  float2(0.2, 0)
};

constant float2 erosionShape[] = {
  float2(0, 0),
  float2(0.05, 0.1),
  float2(0.5, 0.3),
  float2(0.7, 0.4),
  float2(1, 1),
};

constant float2 mountainShape[] = {
  float2(0.0, 0),
  float2(0.01, 0.5),
  float2(0.014, 0),
  float2(0.86, 0),
  float2(0.9, 0.2),
  float2(0.91, 0)
};

#endif

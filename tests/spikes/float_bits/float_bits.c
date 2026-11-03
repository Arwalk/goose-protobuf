/* Spike gpb-wof.2: C shim alternative (memcpy bit cast). */
#include <stdint.h>
#include <string.h>

uint32_t pbw_f32_to_bits(float x) { uint32_t v; memcpy(&v, &x, 4); return v; }
uint64_t pbw_f64_to_bits(double x) { uint64_t v; memcpy(&v, &x, 8); return v; }
float pbw_f32_from_bits(uint32_t v) { float x; memcpy(&x, &v, 4); return x; }
double pbw_f64_from_bits(uint64_t v) { double x; memcpy(&x, &v, 8); return x; }

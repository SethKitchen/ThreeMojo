/* Print glibc's pow and log for chosen and random inputs, as bits.

   make_libm_cases.py compiles this file with -fno-builtin and runs it.  */

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static uint64_t bits (double d)
{
  uint64_t u;
  memcpy (&u, &d, 8);
  return u;
}

static double from (uint64_t u)
{
  double d;
  memcpy (&d, &u, 8);
  return d;
}

static void p (double x, double y)
{
  volatile double vx = x, vy = y;
  printf ("pow %016llx %016llx %016llx\n", (unsigned long long) bits (vx),
	  (unsigned long long) bits (vy),
	  (unsigned long long) bits (pow (vx, vy)));
}

static void l (double x)
{
  volatile double vx = x;
  printf ("log %016llx %016llx\n", (unsigned long long) bits (vx),
	  (unsigned long long) bits (log (vx)));
}

static uint64_t state = 0x9E3779B97F4A7C15ull;

static uint64_t next (void)
{
  state ^= state << 13;
  state ^= state >> 7;
  state ^= state << 17;
  return state;
}

/* A uniform double in [a, b).  */
static double uniform (double a, double b)
{
  return a + (b - a) * ((next () >> 11) * 0x1p-53);
}

int main (void)
{
  double inf = from (0x7ff0000000000000ull);
  double qnan = from (0x7ff8000000000000ull);
  double snan = from (0x7ff4000000000000ull);
  double sub = from (0x0000000000001234ull);

  /* y is zero, infinite or NaN.  */
  p (2.0, 0.0);
  p (snan, 0.0);
  p (1.0, qnan);
  p (1.0, snan);
  p (qnan, inf);
  p (2.0, qnan);
  p (-1.0, inf);
  p (0.5, inf);
  p (2.0, -inf);
  p (2.0, inf);
  p (0.5, -inf);
  /* x is zero, infinite or NaN.  */
  p (0.0, 2.0);
  p (0.0, -2.0);
  p (-0.0, 3.0);
  p (-0.0, -3.0);
  p (-0.0, 2.5);
  p (-0.0, 0x1p60);
  p (-inf, 3.0);
  p (-inf, 2.0);
  p (inf, -1.0);
  p (qnan, 2.0);
  /* x is negative and finite.  */
  p (-2.0, 0.5);
  p (-2.0, 2.5);
  p (-2.0, 3.0);
  p (-2.0, 2.0);
  p (-2.0, 1e300);
  p (-1.0, 1e300);
  p (-1.0, 3.0);
  p (-1.5, -7.0);
  /* y is tiny or huge.  */
  p (2.0, 1e-30);
  p (0.5, 1e-30);
  p (1.0, 1e-30);
  p (2.0, 1e30);
  p (0.5, 1e30);
  p (2.0, -1e30);
  p (0.5, -1e30);
  /* x is subnormal.  */
  p (sub, 0.5);
  p (-sub, 3.0);
  p (sub, -0.25);
  /* The exponential is tiny, overflows, underflows or is near the edges.  */
  p (2.0, 1e-17);
  p (2.0, 3.0);
  p (2.0, 2000.0);
  p (2.0, -2000.0);
  p (-2.0, 2001.0);
  p (-2.0, -2001.0);
  p (2.0, 1000.0);
  p (2.0, 1023.75);
  p (2.0, -1000.0);
  p (2.0, -1030.0);
  p (2.0, -1060.25);
  p (2.0, -1075.0);
  p (-2.0, -1075.0);
  p (-2.0, -1031.0);
  p (from (0x3ff0000000000001ull), 0x1.8p62);
  p (from (0x3fefffffffffffffull), 0x1.8p62);

  /* Random powers over a wide range.  */
  for (int i = 0; i < 3000; i++)
    p (exp (uniform (-40.0, 40.0)), uniform (-6.0, 6.0));
  /* The exponents of the EPANET and MODFLOW formulas.  */
  static const double ys[] = { 1.852, 0.54, 0.5, 1.0 / 1.852, 2.0, 1.5,
			       0.46, 0.852, 1.0 / 0.54, 2.5, 1.0 / 3.0,
			       0.25, 0.8, 1.2, -0.5, -1.852, 1.75, 0.66 };
  for (int i = 0; i < 3000; i++)
    p (exp (uniform (-25.0, 12.0)), ys[next () % (sizeof ys / sizeof ys[0])]);
  /* Bases near 1 with large exponents.  */
  for (int i = 0; i < 1000; i++)
    p (uniform (0.999, 1.001), uniform (-1e5, 1e5));
  /* Results near the top and the bottom of the range.  */
  for (int i = 0; i < 500; i++)
    p (uniform (1.5, 2.5), uniform (700.0, 1100.0) * (next () & 1 ? 1 : -1));
  for (int i = 0; i < 500; i++)
    p (-uniform (1.5, 2.5), (double) (int) uniform (-1100.0, 1100.0));

  /* log: chosen inputs.  */
  l (1.0);
  l (0.0);
  l (-0.0);
  l (inf);
  l (-inf);
  l (-1.0);
  l (qnan);
  l (-qnan);
  l (sub);
  l (0x1p-1022);
  l (1.0 - 0x1p-4);
  l (from (0x3ff108ffffffffffull));
  l (from (0x3ff1090000000000ull));
  l (from (0x3fedffffffffffffull));
  /* Random logarithms.  */
  for (int i = 0; i < 3000; i++)
    l (exp (uniform (-700.0, 700.0)));
  for (int i = 0; i < 2000; i++)
    l (uniform (1.0 - 0x1p-4, 1.0 + 0x1.09p-4));
  for (int i = 0; i < 1000; i++)
    l (from (next () & 0x000fffffffffffffull));
  return 0;
}

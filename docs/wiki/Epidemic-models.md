# Epidemic models

`extensions/clinical/epidemic.mojo` models an epidemic in a population by the SIR and SEIR compartment models. It integrates the fractions of the population in time, and it gives the peak, the final size and the herd immunity threshold. It plots the infectious fraction of several epidemics. `incidence.mojo` finds the growth rate of an outbreak from its case counts, and the reproduction number that the rate implies. It is a library for research and teaching. Its results are not a forecast of a real epidemic.

![One SEIR epidemic with no one vaccinated, 30 percent and 50 percent](out/epidemic.png)

`examples/epidemic.mojo` makes this picture. The disease has an R0 of 2.5, a latent period of 3 days and an infectious period of 5 days. It starts from 1 in 10000 of the population. The red curve has no one vaccinated, the orange curve 30 percent, and the blue curve 50 percent. Time runs to 300 days, with a gray line each 30 days, and the fraction runs to 15 percent.

With no vaccination, 14.4 percent of the population is infectious at the peak, on day 64, and 89 percent are infected in all. With 30 percent vaccinated, the peak is 4.7 percent on day 100, and 50 percent are infected. With 50 percent vaccinated, the peak is 0.7 percent on day 206, and 19 percent are infected. The herd immunity threshold is 60 percent.

## Modules

| Module | What it gives |
|---|---|
| `epidemic` | `EpidemicCurve`, `seir`, `sir`, `final_susceptible`, `herd_immunity`, `epidemic_image` and `MAX_STEPS` |
| `incidence` | `GrowthFit`, `growth_rate`, `reproduction_number`, `incidence_image` and `MAX_COUNTS` |

## The models

The models divide a population into fractions that sum to 1:

- S is susceptible: not infected and not immune.
- E is exposed: infected, but not yet infectious. The SIR model has no E.
- I is infectious.
- R is removed: recovered, or immune from the start, as by a vaccine.

The SEIR model is:

```text
dS/dt = -b S I
dE/dt = b S I - s E
dI/dt = s E - g I
dR/dt = g I
```

Here `g` is one over the infectious period, `s` is one over the latent period, and `b = R0 g`. R0 is the basic reproduction number: the infections that one case causes in a population with no immunity. In the SIR model, an infection is infectious at once: `dI/dt = b S I - g I`.

## Run an epidemic

`seir(r0, latent, infectious, infected, immune, step, end)` and `sir(r0, infectious, infected, immune, step, end)` take:

- `r0`, the basic reproduction number.
- `latent` and `infectious`, the mean periods, as durations.
- `infected`, the infectious fraction at the start.
- `immune`, the immune fraction at the start, such as the vaccinated fraction.
- `step` and `end`, the time step and the end time.

```mojo
from extensions.clinical.epidemic import seir
from extensions.clinical.survival import DAY64
from units.si import Duration64

var curve = seir(
    2.5,
    Duration64(3, DAY64),
    Duration64(5, DAY64),
    1e-4,
    0.3,
    Duration64(0.1, DAY64),
    Duration64(300, DAY64),
)
print(curve.peak()[1], curve.peak()[0].to(DAY64))
```

The integration uses the classical Runge-Kutta method in equal steps. The function shortens the step so that a whole number of steps reaches the end. The curve records each step: `times`, `susceptible`, `exposed`, `infectious` and `removed`. A step of a tenth of the shortest period is accurate to about 1e-9.

`curve.peak()` gives the time and the size of the largest infectious fraction. When the immune fraction is above the herd immunity threshold, the epidemic does not grow, and the peak is at the start.

## Find the final size and the threshold

`final_susceptible(r0, infected, immune)` gives the fraction that is never infected. It solves the final size relation:

```text
ln(S0 / S) = R0 (1 - p - S)
```

Here `S0` is the susceptible fraction at the start and `p` is the immune fraction. The relation holds for the SIR and SEIR models alike. The fraction infected in all is `1 - p - S`.

`herd_immunity(r0)` gives the immune fraction above which an epidemic cannot grow, `1 - 1 / R0`. It is 0 when R0 is 1 or less.

## Draw the curves

`epidemic_image(curves, colors, end, grid, top, width, height)` plots the infectious fraction of each epidemic. Time runs from 0 at the left edge to `end` at the right edge. The fraction runs from 0 at the bottom edge to `top` at the top edge. Light gray lines mark each `grid` of time and each tenth of `top`.

## Estimate the growth from case counts

![40 days of synthetic case counts as bars, with the fitted exponential growth](out/incidence.png)

`examples/incidence.mojo` makes this picture. Each blue bar is the cases of one day of a synthetic outbreak, and the red curve is the fitted growth. The cases grow by 0.121 a day, from 0.118 to 0.124, and they double each 5.7 days. With a latent period of 3 days and an infectious period of 5 days, R is 2.18, from 2.15 to 2.22.

Early in an epidemic, the cases grow by a fixed fraction each day. `growth_rate(counts, step, tolerance, max_steps)` fits the count at time `t` as `exp(a + r t)`, by Poisson regression of the counts on the time. The counts are in order, `step` apart. The result is a `GrowthFit`:

- `intercept` is `a`, and `rate` is the growth rate `r`, per day. Each has a standard error.
- `rate_interval()` gives the 95 percent interval of the rate.
- `doubling_time()` gives `ln 2 / r`. Counts that fall have no doubling time.
- `expected(time)` gives the fitted count at a time.
- `dispersion` is Pearson's chi-square over its degrees of freedom, and `deviance` is the Poisson deviance.

Real counts often spread more than Poisson counts do, and then the dispersion is above 1. Multiply the standard errors by the square root of the dispersion.

`reproduction_number(rate, latent, infectious)` gives the R that a growth rate implies, `(1 + r L)(1 + r D)`, after Wallinga and Lipsitch. It takes exponential latent and infectious stages, as the SEIR model does. A latent period of 0 gives the SIR model, `1 + r D`. The R of each end of the interval of the rate gives an interval of R.

`incidence_image(counts, step, fit, width, height)` draws the counts as bars, with the fitted curve.

## Verification

The tests compare the module with scipy 1.18.1. `assets/epidemic/make_epidemic.py` integrates an SEIR and an SIR epidemic by `solve_ivp` with the method DOP853 to a relative 1e-13.

- With a step of 0.05 days, each fraction at 10, 30, 60, 90 and 150 days agrees to 1e-10.
- The final size relation agrees with scipy's `brentq` to a relative 1e-14.

The tests compare `incidence` with the Poisson `GLM` of statsmodels 0.15.0 on 40 days of synthetic counts, which `tools/make_incidence.mojo` writes. The intercept and the rate agree to a relative 1e-12. Their standard errors, the dispersion and the deviance agree to 1e-11.

The tests also check properties of the models:

- The four fractions sum to 1 to 1e-14.
- An SIR epidemic peaks when S falls to 1 / R0, and a long run ends at the final size to 1e-9.
- The herd immunity threshold of an R0 of 2.5 is 0.6. Immunity of 65 percent puts the peak at the start.
- A step of 0.3 days to 1 day becomes three steps of a third of a day.
- Counts that double each day give a rate of `ln 2` a day, a doubling time of 1 day and no deviance. Two days apart, they double each 2 days. Counts that halve each day give `-ln 2`.
- A rate of 0.1 a day, a latent period of 3 days and an infectious period of 5 days give an R of `1.3 x 1.5 = 1.95`. With no latent period, R is 1.5.

## Errors

Every function raises `Error` for input it cannot use.

| Case | Functions |
|---|---|
| R0 is not positive and finite | `seir`, `sir`, `final_susceptible`, `herd_immunity` |
| The infected fraction is not in (0, 1], or the immune and infected fractions are negative or sum to more than 1 | `seir`, `sir`, `final_susceptible` |
| A period, the step or the end time is not positive and finite, or there are more than 1000000 steps | `seir`, `sir` |
| A curve has no record | `EpidemicCurve.peak` |
| There are not 3 to 100000 counts, a count is negative, there is no case, or the step, the tolerance or the steps are out of range | `growth_rate`, `incidence_image` |
| Counts that do not grow have no doubling time | `GrowthFit.doubling_time` |
| The rate is not finite, a period is out of range, or the rate is so negative that a factor of R is not positive | `reproduction_number` |
| There is no curve, the colors are not one for each curve, a time is out of range, the top is not in (0, 1], or a side is out of 64 to 4096 pixels | `epidemic_image` |

## Limits

- The models mix the population evenly. They have no age, place, contact network, birth or death.
- R0 and the periods do not change in time. The models have no seasons and no interventions during the epidemic.
- Immunity lasts for good, and a vaccine gives full immunity at the start.
- The periods are means. The models take exponential stages, so the latent and infectious times of the cases spread widely about them.
- The models are not fitted to data. `growth_rate` fits only the early exponential growth, and its R needs the latent and infectious periods from other studies.
- A growth rate holds while few are immune and the testing does not change. Reporting delays and weekday effects bend real counts.

## References

- Kermack and McKendrick, "A contribution to the mathematical theory of epidemics", Proceedings of the Royal Society A, 1927.
- Anderson and May, "Infectious Diseases of Humans: Dynamics and Control", 1991.
- Keeling and Rohani, "Modeling Infectious Diseases in Humans and Animals", 2008.
- Wallinga and Lipsitch, "How generation intervals shape the relationship between growth rates and reproductive numbers", Proceedings of the Royal Society B, 2007.
- Diekmann, Heesterbeek and Britton, "Mathematical Tools for Understanding Infectious Disease Dynamics", 2013.

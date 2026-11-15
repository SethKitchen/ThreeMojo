# Epidemic models

`extensions/clinical/epidemic.mojo` models an epidemic in a population by the SIR and SEIR compartment models. It integrates the fractions of the population in time, and it gives the peak, the final size and the herd immunity threshold. It plots the infectious fraction of several epidemics. It is a library for research and teaching. Its results are not a forecast of a real epidemic.

![One SEIR epidemic with no one vaccinated, 30 percent and 50 percent](out/epidemic.png)

`examples/epidemic.mojo` makes this picture. The disease has an R0 of 2.5, a latent period of 3 days and an infectious period of 5 days. It starts from 1 in 10000 of the population. The red curve has no one vaccinated, the orange curve 30 percent, and the blue curve 50 percent. Time runs to 300 days, with a gray line each 30 days, and the fraction runs to 15 percent.

With no vaccination, 14.4 percent of the population is infectious at the peak, on day 64, and 89 percent are infected in all. With 30 percent vaccinated, the peak is 4.7 percent on day 100, and 50 percent are infected. With 50 percent vaccinated, the peak is 0.7 percent on day 206, and 19 percent are infected. The herd immunity threshold is 60 percent.

## Modules

| Module | What it gives |
|---|---|
| `epidemic` | `EpidemicCurve`, `seir`, `sir`, `final_susceptible`, `herd_immunity`, `epidemic_image` and `MAX_STEPS` |

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

## Verification

The tests compare the module with scipy 1.18.1. `assets/epidemic/make_epidemic.py` integrates an SEIR and an SIR epidemic by `solve_ivp` with the method DOP853 to a relative 1e-13.

- With a step of 0.05 days, each fraction at 10, 30, 60, 90 and 150 days agrees to 1e-10.
- The final size relation agrees with scipy's `brentq` to a relative 1e-14.

The tests also check properties of the models:

- The four fractions sum to 1 to 1e-14.
- An SIR epidemic peaks when S falls to 1 / R0, and a long run ends at the final size to 1e-9.
- The herd immunity threshold of an R0 of 2.5 is 0.6. Immunity of 65 percent puts the peak at the start.
- A step of 0.3 days to 1 day becomes three steps of a third of a day.

## Errors

Every function raises `Error` for input it cannot use.

| Case | Functions |
|---|---|
| R0 is not positive and finite | `seir`, `sir`, `final_susceptible`, `herd_immunity` |
| The infected fraction is not in (0, 1], or the immune and infected fractions are negative or sum to more than 1 | `seir`, `sir`, `final_susceptible` |
| A period, the step or the end time is not positive and finite, or there are more than 1000000 steps | `seir`, `sir` |
| A curve has no record | `EpidemicCurve.peak` |
| There is no curve, the colors are not one for each curve, a time is out of range, the top is not in (0, 1], or a side is out of 64 to 4096 pixels | `epidemic_image` |

## Limits

- The models mix the population evenly. They have no age, place, contact network, birth or death.
- R0 and the periods do not change in time. The models have no seasons and no interventions during the epidemic.
- Immunity lasts for good, and a vaccine gives full immunity at the start.
- The periods are means. The models take exponential stages, so the latent and infectious times of the cases spread widely about them.
- An epidemic of a real disease needs data and fitted parameters. The module does not fit a model to data.

## References

- Kermack and McKendrick, "A contribution to the mathematical theory of epidemics", Proceedings of the Royal Society A, 1927.
- Anderson and May, "Infectious Diseases of Humans: Dynamics and Control", 1991.
- Keeling and Rohani, "Modeling Infectious Diseases in Humans and Animals", 2008.
- Diekmann, Heesterbeek and Britton, "Mathematical Tools for Understanding Infectious Disease Dynamics", 2013.

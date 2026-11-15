# Numerics

`extensions/numerics/` solves the linear algebra of engineering analysis in `Float64`. It gives dense and sparse matrices, a conjugate-gradient solver, a skyline direct solver and a generalized eigensolver. It also gives elementary functions to the last place, statistical distributions and the weighted spread of points. The structural and thermal solvers of the building extension share it, and so do the imaging, molecule, FEM, chemistry and clinical extensions.

![Three rows of masses on springs move in the three lowest modes](out/numerics.png)

## Modules

| Module | What it gives |
|---|---|
| `vector` | `zeros`, `dot`, `norm`, `axpy` and size and finiteness checks on `List[Float64]` |
| `dense` | `DenseMatrix`, Gaussian elimination, `inverse`, Cholesky with `cholesky_solve` and `cholesky_inverse`, triangular solves, the Jacobi eigensolver and the Thomas algorithm |
| `elementary` | `precise_exp`, `precise_power`, `precise_power10`, `precise_log2`, `logistic`, `logit`, `softplus`, `LN2`, `LN10` and `INVERSE_LN2` |
| `distributions` | The normal, t, F, beta, gamma and chi-square tails and quantiles, `inverse_erfc`, `wald_interval`, `ratio_interval`, `Z95`, `MAX_DEGREES`, `MAX_SHAPE` and `MAX_FREEDOM` |
| `spread` | `PointSpread`, the weighted mean, covariance and principal axes of points, and `descending` |
| `order` | `ascending_order`, `descending_order`, `sorted_values` and `order_by`, the stable order of values |
| `sparse` | `SparseBuilder`, which assembles triplets, and `CsrMatrix` |
| `iterative` | `conjugate_gradient` with a Jacobi preconditioner, and `SolveStatus` |
| `skyline` | `reverse_cuthill_mckee`, `profile` and `SkylineFactor` |
| `eigen` | `lowest_modes` and `count_eigenvalues_below` |

## Assemble a sparse matrix

Create a `SparseBuilder` with the matrix size. Call `add` once for each contribution. Repeated positions add together. A zero is skipped. `build` returns a `CsrMatrix` with sorted, distinct columns in each row.

```mojo
var builder = SparseBuilder(3)
builder.add(0, 0, 2)
builder.add(0, 1, -1)
builder.add(1, 0, -1)
builder.add(0, 0, 1)            # adds to the first entry: 3
var k = builder.build()
var y = k.multiply(x)
```

`add` refuses an index out of range and a value that is not finite. Every matrix is square.

## Solve a symmetric system

Use `SkylineFactor` for a direct solve. Use `conjugate_gradient` for a large, well-conditioned system that does not fit a profile.

| Solver | Needs | Gives |
|---|---|---|
| `SkylineFactor(a, order)` | A symmetric matrix with no zero pivot | A factor that solves any right-hand side. It also counts negative pivots. |
| `conjugate_gradient(a, b, tolerance, max_iterations)` | A symmetric positive-definite matrix | One solution, the iteration count, the relative residual and a `SolveStatus` |
| `solve(a, b)` | A small dense square matrix | One solution, by Gaussian elimination with partial pivoting |
| `cholesky_solve(a, b)` | A small dense symmetric positive-definite matrix | One solution, by the Cholesky factor and two triangular solves |
| `solve_tridiagonal(lower, diagonal, upper, rhs)` | A diagonally dominant tridiagonal system | One solution, by the Thomas algorithm |

```mojo
var factor = SkylineFactor(k, reverse_cuthill_mckee(k))
var u = factor.solve(f)
```

Pass `reverse_cuthill_mckee(k)` as the order to make the profile small. Pass `identity_order(k.size)` to keep the numbering. `profile(k, order)` gives the number of stored entries for an order. The profile and the factor read the same upper entries after reordering. An upper-only matrix must supply those entries in the selected order.

`conjugate_gradient` stops at `CONVERGED` or at `BUDGET_EXHAUSTED`. An exhausted budget is not an error. The result holds the last iterate, and the caller decides what to do with it.

## Find natural modes

`lowest_modes(k, m, count, tolerance, max_iterations)` returns the lowest eigenvalues of K φ = λ M φ, in ascending order. Each vector is normalized so that φᵀ M φ = 1. For a structure, λ is the square of the angular frequency.

```mojo
var modes = lowest_modes(stiffness, mass, 3, 1e-10, 60)
var hertz = sqrt(modes.values[0]) / (2 * pi)
```

The method is subspace iteration. It carries `min(n, max(2 count, count + 8))` trial vectors. Each iteration makes them M-orthonormal by modified Gram-Schmidt. A vector that collapses into the span of the others is replaced by a unit vector.

Replacement tries each coordinate at most once per trial vector. If no independent positive-mass direction is found, the method raises. A mass a million times the rest still converges.

After convergence, a Sturm check counts the negative eigenvalues of K - σ M. With a resolved gap after the last wanted eigenvalue, that count must equal `count`. A request can also end inside a repeated cluster. The check then counts on both sides of the cluster. The lower count must equal the number of lower returned modes. The upper count must cover the requested modes.

Inertia identifies the cluster even when an unwanted Ritz vector has not yet converged to it. This retains the check for missed lower modes. Cluster comparisons use the dense solver's working precision, independent of the requested iteration tolerance.

`count_eigenvalues_below(k, m, shift)` gives that count for any finite shift. It first tries the skyline factor and checks that its multipliers are safe. If a pivot is zero or unsafe, it scales rows and columns together. It then uses symmetric pivoting with 1 by 1 and 2 by 2 blocks. This congruence preserves inertia and the pivot tolerance.

A nonsingular indefinite shift can have a zero leading entry. The pivoted path handles this case. A shift at an eigenvalue to working precision still raises.

The pivoted fallback uses dense storage. Its storage grows with the square of the matrix size, and its work grows with the cube. The ordinary skyline path keeps its profile storage.

## Invert a small matrix

`cholesky_inverse(a)` gives the inverse of a symmetric positive-definite matrix. It factors the matrix once and solves each column of the identity. The covariance of a fit is the inverse of its information matrix, so the statistical models take their standard errors from it. `inverse(a)` gives the inverse of any nonsingular square matrix, by `solve` on each column.

`DenseMatrix.triple_product(inner)` gives Tᵀ A T with the matrix as T. A change of variables of a covariance, J V Jᵀ, is the triple product of Jᵀ.

## Use accurate elementary functions

The Float64 `exp` of Mojo 1.2 is off by up to about 3e-11 near -70, and so is a fractional power, which takes it. `log2` is off by about 1e-9. `log` and `expm1` are exact to the last place, so `elementary` builds on them:

- `precise_exp(x)` reduces x by ln 2 in two parts, after Cody and Waite, and takes `expm1` of the rest. It gives 0 below -708 and infinity above 709.
- `precise_power(x, p)` gives `x^p` for an x of 0 or more. At x = 0 it gives 0, 1 or infinity by the sign of p.
- `precise_power10(x)` gives `10^x`, and `precise_log2(x)` gives `log(x) / ln 2`.
- `logistic(x)` gives `1 / (1 + e^-x)`, and `logit(p)` gives `ln(p / (1 - p))`. `softplus(x)` gives `ln(1 + e^x)`. None of them overflows. The logistic models and the calibration of a risk model use them.

## Use statistical distributions

`distributions` gives the tails and the quantiles that the intervals and the tests use:

- `normal_upper(z)` gives P(Z > z), and `normal_two_sided(z)` gives P(|Z| > |z|), the p value of a Wald z. `normal_quantile(p)` inverts the tail.
- `inverse_erfc(v)` gives the z with erfc(z) = v, from `normal_quantile`.
- `wald_interval(estimate, se)` gives `estimate -+ Z95 se`. `ratio_interval(ratio, se)` gives `ratio exp(-+ Z95 se)`, with se the standard error of the logarithm of the ratio. `Z95` is the 97.5 percent point of the normal distribution.
- `beta_tails(x, a, b)` gives both tails of the beta distribution, and `beta_quantile` inverts it. The smaller tail comes from a continued fraction, so it keeps its relative accuracy far out.
- `student_t_upper(t, df)` and `student_t_quantile(p, df)` give the upper tail and the quantile of Student's t.
- `f_upper(x, d1, d2)` and `f_quantile(p, d1, d2)` give the upper tail and the quantile of the F distribution.
- `gamma_tails(x, a)` gives the regularized incomplete gamma functions P(a, x) and Q(a, x). It takes the series below `a + 1` and the continued fraction of Numerical Recipes above it. The smaller tail keeps its relative accuracy.
- `gamma_quantile(p, a)` inverts P, and `gamma_upper_quantile(q, a)` inverts Q. A small tail keeps its accuracy in each.
- `chi_square_p_value(statistic, freedom)` gives the upper tail of the chi-square distribution, Q(k / 2, x / 2).

The degrees of freedom of t and F are real numbers from more than 0 to 1e8. A gamma shape is from more than 0 to 1e7. A quantile comes from Newton steps on the tail, held in a bracket by bisection. Each exponential is `precise_exp`, because a p value is an `exp`.

## Measure the spread of points

`PointSpread` takes weighted points one at a time, by the update of West (1979). It keeps the mean and the scatter about it, so points far from the origin lose no digits.

```mojo
var spread = PointSpread()
spread.add(x, y, z, mass)
var axes = spread.principal()
```

`covariance()` gives the weighted covariance. `principal()` gives its eigenvalues from the largest to the smallest, with a unit axis for each column. `descending(pairs)` turns the ascending pairs of `symmetric_eigen` around. The mass distribution of a molecule and the shape of a label take their principal axes from it.

## Sort by a key

`ascending_order(keys)` gives the indexes of the keys from the least, and `descending_order(keys)` gives them from the largest. `sorted_values(values)` gives a sorted copy. `order_by[before](count)` sorts the indexes from 0 by a comparison of indexes, for keys that are not numbers.

Each sort is the stable merge sort of `math.sort_utils`, so equal keys keep their order. The survival curves, the rank tests, the slice stacks and the faces of a mesh take their order from them.

## Dense eigenvalue range

`symmetric_eigen` scales finite input by its largest entry before the Jacobi sweeps. This preserves the relative stopping test when the original entry squares would overflow or underflow. Eigenvectors stay unchanged by this scaling. The method rescales each eigenvalue at the end and raises if it cannot represent that value as finite `Float64`.

## Errors

Every function raises `Error` for input it cannot use. The table gives the cases.

| Case | Functions |
|---|---|
| Sizes differ | All |
| An entry is not finite | `SparseBuilder.add`, `conjugate_gradient`, `symmetric_eigen` |
| A matrix is singular | `solve`, `inverse`, `SkylineFactor` |
| A matrix is not positive definite | `cholesky`, `cholesky_solve`, `cholesky_inverse`, `conjugate_gradient`, `lowest_modes` |
| An iteration does not converge | `symmetric_eigen`, `lowest_modes` |
| An order is not a permutation | `SkylineFactor`, `profile` |
| A vector or a matrix is too large | `zeros`, `DenseMatrix`, `SparseBuilder`, `CsrMatrix` |
| A point weight is not positive and finite, or a point is not finite | `PointSpread.add` |
| A spread has no point | `PointSpread.covariance`, `PointSpread.principal` |
| Eigenpairs do not have one vector for each value | `descending` |
| A degree of freedom is not from more than 0 to 1e8, a probability is not between 0 and 1, or a value is out of range | The t, F and beta functions, `normal_quantile` |
| A gamma shape is not above 0 and at most 1e7, a point is below 0 or not a number, or a probability is not above 0 and below 1 | `gamma_tails`, `gamma_quantile`, `gamma_upper_quantile` |
| A chi-square freedom is not from 1 to 1000, or the statistic is negative or not a number | `chi_square_p_value` |
| A value of `inverse_erfc` is not above 0 and below 2 | `inverse_erfc` |

## Limits

- The matrices are square and real.
- `SkylineFactor` reads the upper triangle after reordering. It treats the matrix as symmetric.
- `SkylineFactor` does not pivot. A symmetric indefinite matrix factors only when no pivot is zero.
- `lowest_modes` needs a positive-definite stiffness. Apply the supports first. A free structure has zero eigenvalues and is refused.
- `symmetric_eigen` is for small matrices. Its cost grows with the cube of the size.
- A vector above 16777216 entries is refused.
- A matrix order above 16777216 is refused.
- A dense matrix with more than 16777216 entries is refused.

## References

- Golub and Van Loan, "Matrix Computations", 4th edition, 2013.
- Hestenes and Stiefel, "Methods of conjugate gradients for solving linear systems", 1952.
- Cuthill and McKee, "Reducing the bandwidth of sparse symmetric matrices", 1969.
- George and Liu, "An implementation of a pseudoperipheral node finder", 1979.
- Bathe, "Finite Element Procedures", 2nd edition, 2014: sections 8.2 and 11.6.
- Cody and Waite, "Software Manual for the Elementary Functions", 1980.
- Press and others, "Numerical Recipes", 3rd edition, 2007: sections 6.2 and 6.4.
- Acklam, "An algorithm for computing the inverse normal cumulative distribution function", 2003.
- West, "Updating mean and variance estimates: an improved method", Communications of the ACM, 1979.

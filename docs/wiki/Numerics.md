# Numerics

`extensions/numerics/` solves the linear algebra of engineering analysis in `Float64`. It gives dense and sparse matrices, a conjugate-gradient solver, a skyline direct solver and a generalized eigensolver. The structural and thermal solvers of the building extension share it.

![Three rows of masses on springs move in the three lowest modes](out/numerics.png)

## Modules

| Module | What it gives |
|---|---|
| `vector` | `zeros`, `dot`, `norm`, `axpy` and size and finiteness checks on `List[Float64]` |
| `dense` | `DenseMatrix`, Gaussian elimination, Cholesky, triangular solves, the Jacobi eigensolver and the Thomas algorithm |
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

## Dense eigenvalue range

`symmetric_eigen` scales finite input by its largest entry before the Jacobi sweeps. This preserves the relative stopping test when the original entry squares would overflow or underflow. Eigenvectors stay unchanged by this scaling. The method rescales each eigenvalue at the end and raises if it cannot represent that value as finite `Float64`.

## Errors

Every function raises `Error` for input it cannot use. The table gives the cases.

| Case | Functions |
|---|---|
| Sizes differ | All |
| An entry is not finite | `SparseBuilder.add`, `conjugate_gradient`, `symmetric_eigen` |
| A matrix is singular | `solve`, `SkylineFactor` |
| A matrix is not positive definite | `cholesky`, `conjugate_gradient`, `lowest_modes` |
| An iteration does not converge | `symmetric_eigen`, `lowest_modes` |
| An order is not a permutation | `SkylineFactor`, `profile` |

## Limits

- The matrices are square and real.
- `SkylineFactor` reads the upper triangle after reordering. It treats the matrix as symmetric.
- `SkylineFactor` does not pivot. A symmetric indefinite matrix factors only when no pivot is zero.
- `lowest_modes` needs a positive-definite stiffness. Apply the supports first. A free structure has zero eigenvalues and is refused.
- `symmetric_eigen` is for small matrices. Its cost grows with the cube of the size.

## References

- Golub and Van Loan, "Matrix Computations", 4th edition, 2013.
- Hestenes and Stiefel, "Methods of conjugate gradients for solving linear systems", 1952.
- Cuthill and McKee, "Reducing the bandwidth of sparse symmetric matrices", 1969.
- George and Liu, "An implementation of a pseudoperipheral node finder", 1979.
- Bathe, "Finite Element Procedures", 2nd edition, 2014: sections 8.2 and 11.6.

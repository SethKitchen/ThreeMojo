# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Distance trees of sequences: p-distances from alignments, Kimura's
protein distance, neighbor joining and UPGMA, Newick text and a drawing.

The sequences of a pathogen change as it spreads, so a tree of its
sequences traces the spread, and a tree of a protein family shows which
members are near kin.

- `alignment_distances(sequences, open, extend)` aligns each pair end to
  end and gives `1 - identity`, the p-distance.
- `kimura_distances(p)` corrects p-distances for more than one change at a
  site: `-ln(1 - p - 0.2 p^2)`, after Kimura (1983).
- `neighbor_joining(distances, names)` builds the tree of Saitou and Nei
  (1987), as Biopython builds it. It needs no clock, and its root is the
  last join, so read it as unrooted.
- `upgma(distances, names)` builds the rooted tree of the average linkage,
  which takes a molecular clock.
- `midpoint_root(tree)` roots a tree at the middle of its longest path
  between two leaves, as Biopython's `root_at_midpoint` does.
- `PhyloTree.newick()` writes the tree, and `tree_image` draws it.
"""

from extensions.imaging.overlay import draw_line
from extensions.imaging.transfer import Rgba
from extensions.molecule.sequence import align_sequences
from extensions.numerics.dense import DenseMatrix
from render.framebuffer import Color, Framebuffer
from std.math import floor, isfinite, log

# The most sequences of one tree.
comptime MAX_TAXA = 1000


struct PhyloTree(Copyable, Movable):
    """A tree whose leaves are nodes 0 to `n - 1`, in the order of the
    names, and whose other nodes follow."""

    var names: List[String]
    """The name of each leaf."""
    var children: List[List[Int]]
    """The children of each node."""
    var parents: List[Int]
    """The parent of each node, -1 for the root."""
    var lengths: List[Float64]
    """The length of the branch above each node. 0 for the root."""
    var root: Int
    """The root node."""

    def __init__(out self, var names: List[String]):
        """Create the leaves with no tree above them yet.

        Args:
            names: The leaf names.
        """
        var n = len(names)
        self.names = names^
        self.children = List[List[Int]](length=n, fill=List[Int]())
        self.parents = List[Int](length=n, fill=-1)
        self.lengths = List[Float64](length=n, fill=0.0)
        self.root = -1

    def _join(mut self, a: Int, b: Int, la: Float64, lb: Float64) -> Int:
        """Add a node above two nodes, with their branch lengths."""
        var u = len(self.children)
        self.children.append([a, b])
        self.parents.append(-1)
        self.lengths.append(0.0)
        self.parents[a] = u
        self.parents[b] = u
        self.lengths[a] = la
        self.lengths[b] = lb
        self.root = u
        return u

    def leaf_count(self) -> Int:
        """Return the leaves.

        Returns:
            The count of names.
        """
        return len(self.names)

    def path_length(self, a: Int, b: Int) raises -> Float64:
        """Return the sum of the branch lengths between two leaves.

        Args:
            a: A leaf, from 0.
            b: Another leaf.

        Returns:
            The length of the path through their last common ancestor.

        Raises:
            Error: If a leaf index names no leaf.
        """
        var n = self.leaf_count()
        if a < 0 or a >= n or b < 0 or b >= n:
            raise Error("A tree has no leaf of that index")
        var up = List[Float64](length=len(self.children), fill=-1.0)
        var depth = 0.0
        var node = a
        while node >= 0:
            up[node] = depth
            depth += self.lengths[node]
            node = self.parents[node]
        var total = 0.0
        node = b
        while up[node] < 0:
            total += self.lengths[node]
            node = self.parents[node]
        return total + up[node]

    def leaf_order(self) -> List[Int]:
        """Return the leaves in the order of a walk from the root.

        Returns:
            Each leaf once, the children of each node in their order.
        """
        var out = List[Int]()
        var stack: List[Int] = [self.root]
        while len(stack) > 0:
            var node = stack.pop()
            if node < self.leaf_count():
                out.append(node)
                continue
            for k in range(
                len(self.children[node]) - 1, -1, -1
            ):  # pragma: no branch
                stack.append(self.children[node][k])
        return out^

    def _text(self, node: Int) -> String:
        """Return the Newick text of a node and its branch length."""
        var out = String("")
        if node < self.leaf_count():
            out += self.names[node]
        else:
            out += "("
            for k in range(len(self.children[node])):  # pragma: no branch
                if k > 0:
                    out += ","
                out += self._text(self.children[node][k])
            out += ")"
        return out + ":" + String(self.lengths[node])

    def newick(self) -> String:
        """Return the tree in the Newick format.

        Returns:
            Text such as `((A:0.1,B:0.2):0.05,C:0.3):0.0;`, with the branch
            length after each node and no names on inner nodes.
        """
        return self._text(self.root) + ";"


def alignment_distances(
    sequences: List[String], open: Float64, extend: Float64
) raises -> DenseMatrix:
    """Return the p-distance of each pair of sequences.

    Args:
        sequences: The sequences, of one-letter codes, from 2 to 1000.
        open: The score of the first position of a gap, such as -10.
        extend: The score of each further position, such as -0.5.

    Returns:
        A symmetric matrix of `1 - identity` of the global alignment of each
        pair, with 0 on the diagonal.

    Raises:
        Error: If there are not 2 to 1000 sequences, or an alignment refuses
            a sequence or a gap score, as `align_sequences` does.
    """
    var n = len(sequences)
    if n < 2 or n > MAX_TAXA:
        raise Error("A tree has from 2 to 1000 sequences")
    var out = DenseMatrix(n, n)
    for i in range(n):  # pragma: no branch
        for j in range(i):  # pragma: no branch
            var pair = align_sequences(sequences[i], sequences[j], open, extend)
            var p = 1.0 - pair.identity()
            out.set(i, j, p)
            out.set(j, i, p)
    return out^


def kimura_distances(p: DenseMatrix) raises -> DenseMatrix:
    """Correct p-distances by Kimura's formula for proteins.

    Args:
        p: The p-distances, from 0 and below about 0.85.

    Returns:
        `-ln(1 - p - 0.2 p^2)` of each entry.

    Raises:
        Error: If an entry is not finite or below 0, or too large for the
            formula.
    """
    var out = DenseMatrix(p.rows, p.cols)
    for i in range(p.rows):  # pragma: no branch
        for j in range(p.cols):  # pragma: no branch
            var v = p.get(i, j)
            if not (v >= 0) or not isfinite(v):
                raise Error("A p-distance must be finite and 0 or more")
            var rest = 1.0 - v - 0.2 * v * v
            if not (rest > 0):
                raise Error("Sequences this far apart have no Kimura distance")
            out.set(i, j, -log(rest))
    return out^


def _require(
    distances: DenseMatrix, names: List[String]
) raises -> List[List[Float64]]:
    """Refuse a matrix that is not square, symmetric, finite and 0 or more
    with a 0 diagonal, or names that do not fit it. Return its rows."""
    var n = len(names)
    if n < 2 or n > MAX_TAXA or distances.rows != n or distances.cols != n:
        raise Error("A tree needs a square matrix of 2 to 1000 named rows")
    var rows = List[List[Float64]]()
    for i in range(n):  # pragma: no branch
        var row = List[Float64]()
        for j in range(n):  # pragma: no branch
            var v = distances.get(i, j)
            if not (v >= 0) or not isfinite(v) or v != distances.get(j, i):
                raise Error(
                    "A distance matrix must be symmetric, finite and 0 or more"
                )
            row.append(v)
        if row[i] != 0:
            raise Error("A distance matrix needs 0 on its diagonal")
        rows.append(row^)
    return rows^


def neighbor_joining(
    distances: DenseMatrix, names: List[String]
) raises -> PhyloTree:
    """Build the neighbor-joining tree of a distance matrix.

    At each step, the pair with the least `d_ij - r_i - r_j` joins, with
    `r_i` the sum of the row over `m - 2`. The first such pair in the order
    of the rows wins a tie. The last two nodes join by one branch of their
    distance. Branch lengths can be below 0, as in Biopython.

    Args:
        distances: The square, symmetric distances, 0 on the diagonal.
        names: The name of each row.

    Returns:
        The tree, its root the last node joined.

    Raises:
        Error: If the matrix or the names are not valid.
    """
    var d = _require(distances, names)
    var n = len(names)
    var tree = PhyloTree(names.copy())
    if n == 2:
        _ = tree._join(0, 1, d[0][1] / 2.0, d[0][1] / 2.0)
        return tree^
    var active = List[Int]()
    for i in range(n):  # pragma: no branch
        active.append(i)
    var last = -1
    while len(active) > 2:
        var m = len(active)
        var r = List[Float64]()
        for i in range(m):  # pragma: no branch
            var total = 0.0
            for j in range(m):  # pragma: no branch
                total += d[i][j]
            r.append(total / Float64(m - 2))
        var best_i = 1
        var best_j = 0
        var best = d[1][0] - r[1] - r[0]
        for i in range(1, m):  # pragma: no branch
            for j in range(i):  # pragma: no branch
                var q = d[i][j] - r[i] - r[j]
                if q < best:
                    best = q
                    best_i = i
                    best_j = j
        var dij = d[best_i][best_j]
        var li = (dij + r[best_i] - r[best_j]) / 2.0
        last = tree._join(active[best_i], active[best_j], li, dij - li)
        for k in range(m):  # pragma: no branch
            var v = (d[best_i][k] + d[best_j][k] - dij) / 2.0
            d[best_j][k] = v
            d[k][best_j] = v
        d[best_j][best_j] = 0.0
        active[best_j] = last
        _ = active.pop(best_i)
        _ = d.pop(best_i)
        for k in range(len(d)):  # pragma: no branch
            _ = d[k].pop(best_i)
    # The other node hangs from the last join by their distance.
    var other = active[0] + active[1] - last
    tree.children[last].append(other)
    tree.parents[other] = last
    tree.lengths[other] = d[1][0]
    tree.root = last
    return tree^


def upgma(distances: DenseMatrix, names: List[String]) raises -> PhyloTree:
    """Build the UPGMA tree of a distance matrix.

    At each step, the two nearest clusters join at half their distance,
    and a cluster's distance to the others is the mean over its leaves.
    The first pair in the order of the rows wins a tie.

    Args:
        distances: The square, symmetric distances, 0 on the diagonal.
        names: The name of each row.

    Returns:
        The rooted tree, with each leaf at the same depth.

    Raises:
        Error: If the matrix or the names are not valid.
    """
    var d = _require(distances, names)
    var n = len(names)
    var tree = PhyloTree(names.copy())
    var active = List[Int]()
    var sizes = List[Float64]()
    var heights = List[Float64]()
    for i in range(n):  # pragma: no branch
        active.append(i)
        sizes.append(1.0)
        heights.append(0.0)
    while len(active) > 1:
        var m = len(active)
        var best_i = 1
        var best_j = 0
        for i in range(1, m):  # pragma: no branch
            for j in range(i):  # pragma: no branch
                if d[i][j] < d[best_i][best_j]:
                    best_i = i
                    best_j = j
        var h = d[best_i][best_j] / 2.0
        var u = tree._join(
            active[best_i],
            active[best_j],
            h - heights[best_i],
            h - heights[best_j],
        )
        var si = sizes[best_i]
        var sj = sizes[best_j]
        for k in range(m):  # pragma: no branch
            var v = (si * d[best_i][k] + sj * d[best_j][k]) / (si + sj)
            d[best_j][k] = v
            d[k][best_j] = v
        d[best_j][best_j] = 0.0
        active[best_j] = u
        sizes[best_j] = si + sj
        heights[best_j] = h
        _ = active.pop(best_i)
        _ = sizes.pop(best_i)
        _ = heights.pop(best_i)
        _ = d.pop(best_i)
        for k in range(len(d)):  # pragma: no branch
            _ = d[k].pop(best_i)
    return tree^


def _reach(
    neighbors: List[List[Int]], weights: List[List[Float64]], start: Int
) -> Tuple[List[Float64], List[Int]]:
    """Return the path length from one node to each node, and the node
    before each on its path."""
    var count = len(neighbors)
    var distance = List[Float64](length=count, fill=0.0)
    var previous = List[Int](length=count, fill=-2)
    previous[start] = -1
    var stack: List[Int] = [start]
    while len(stack) > 0:
        var node = stack.pop()
        for k in range(len(neighbors[node])):  # pragma: no branch
            var next = neighbors[node][k]
            if previous[next] != -2:
                continue
            previous[next] = node
            distance[next] = distance[node] + weights[node][k]
            stack.append(next)
    return (distance^, previous^)


def _relink(
    mut neighbors: List[List[Int]],
    mut weights: List[List[Float64]],
    node: Int,
    old: Int,
    new: Int,
    length: Float64,
):
    """Point a node's branch to an old neighbor at a new one instead."""
    for k in range(len(neighbors[node])):  # pragma: no branch
        if neighbors[node][k] == old:
            neighbors[node][k] = new
            weights[node][k] = length


def midpoint_root(tree: PhyloTree) raises -> PhyloTree:
    """Root a tree at the middle of its longest path between two leaves.

    A new root goes on the branch that holds the middle. The two leaves at
    the ends of the longest path are then equally deep. The first pair in
    the order of the leaves wins a tie.

    Args:
        tree: A tree of two leaves or more.

    Returns:
        The same tree, with the same leaves and path lengths, rooted at a
        new node.

    Raises:
        Error: If the tree has no root.
    """
    if tree.root < 0:
        raise Error("A tree needs a root to move")
    var count = len(tree.children)
    var neighbors = List[List[Int]](length=count + 1, fill=List[Int]())
    var weights = List[List[Float64]](length=count + 1, fill=List[Float64]())
    for node in range(count):  # pragma: no branch
        var parent = tree.parents[node]
        if parent >= 0:
            neighbors[node].append(parent)
            weights[node].append(tree.lengths[node])
            neighbors[parent].append(node)
            weights[parent].append(tree.lengths[node])
    var n = tree.leaf_count()
    var best = -1.0
    var a = 0
    var b = 0
    for i in range(n):  # pragma: no branch
        var reach = _reach(neighbors, weights, i)
        for j in range(i + 1, n):  # pragma: no branch
            if reach[0][j] > best:
                best = reach[0][j]
                a = i
                b = j
    var reach = _reach(neighbors, weights, a)
    var path = List[Int]()
    var node = b
    while node >= 0:
        path.append(node)
        node = reach[1][node]
    path.reverse()
    var middle = best / 2.0
    var x = path[0]
    var y = path[1]
    for k in range(len(path) - 1):  # pragma: no branch
        x = path[k]
        y = path[k + 1]
        if reach[0][y] >= middle:
            break
    # Put the new root on the branch from x to y.
    var root = count
    var to_x = middle - reach[0][x]
    var to_y = reach[0][y] - middle
    _relink(neighbors, weights, x, y, root, to_x)
    _relink(neighbors, weights, y, x, root, to_y)
    neighbors[root] = [x, y]
    weights[root] = [to_x, to_y]
    var out = PhyloTree(tree.names.copy())
    out.children = List[List[Int]](length=count + 1, fill=List[Int]())
    out.parents = List[Int](length=count + 1, fill=-1)
    out.lengths = List[Float64](length=count + 1, fill=0.0)
    out.root = root
    var stack: List[Int] = [root]
    while len(stack) > 0:
        var at = stack.pop()
        for k in range(len(neighbors[at])):  # pragma: no branch
            var next = neighbors[at][k]
            if next == out.parents[at]:
                continue
            out.parents[next] = at
            out.lengths[next] = weights[at][k]
            out.children[at].append(next)
            stack.append(next)
    return out^


struct TreeDrawing(Movable):
    """A drawn tree and the place of each leaf's name."""

    var image: Framebuffer
    """The tree on a white image."""
    var xs: List[Int]
    """The column just right of the tip of each leaf."""
    var ys: List[Int]
    """The row of each leaf."""

    def __init__(out self, var image: Framebuffer, leaves: Int):
        """Create a drawing with no leaf placed yet.

        Args:
            image: The image.
            leaves: The leaves.
        """
        self.image = image^
        self.xs = List[Int](length=leaves, fill=0)
        self.ys = List[Int](length=leaves, fill=0)


def tree_image(
    tree: PhyloTree, width: Int, height: Int, label: Int
) raises -> TreeDrawing:
    """Draw a tree with the root at the left and the leaves in rows.

    The depth of a node, the sum of the branch lengths from the root, runs
    from the left edge to `width - label` pixels. A branch below 0 is drawn
    as 0. Each leaf has a row, in the order of `leaf_order`, and each inner
    node sits at the middle of its first and last child.

    Args:
        tree: The tree.
        width: The width of the image, from 64 to 4096 pixels.
        height: The height of the image, from 64 to 4096 pixels.
        label: The pixels kept at the right for the names, from 0 to half
            the width.

    Returns:
        The image, and the place of each leaf's name.

    Raises:
        Error: If a side or the label space is out of range.
    """
    if width < 64 or width > 4096 or height < 64 or height > 4096:
        raise Error("A tree image is from 64 to 4096 pixels on each side")
    if label < 0 or label > width // 2:
        raise Error("The label space of a tree image is 0 to half its width")
    var count = len(tree.children)
    var depth = List[Float64](length=count, fill=0.0)
    var order = List[Int]()
    var stack: List[Int] = [tree.root]
    while len(stack) > 0:
        var node = stack.pop()
        order.append(node)
        for child in tree.children[node]:
            depth[child] = depth[node] + max(tree.lengths[child], 0.0)
            stack.append(child)
    var deepest = 0.0
    for v in depth:  # pragma: no branch
        deepest = max(deepest, v)
    var span = Float64(width - label - 8)
    var scale = span / max(deepest, 1e-300)
    var leaves = tree.leaf_order()
    var rows = Float64(height - 16) / Float64(max(len(leaves) - 1, 1))
    var y = List[Float64](length=count, fill=0.0)
    for k in range(len(leaves)):  # pragma: no branch
        y[leaves[k]] = 8.0 + Float64(k) * rows
    # Inner nodes after their children: walk the visit order backward.
    for k in range(len(order) - 1, -1, -1):  # pragma: no branch
        var node = order[k]
        var kids = tree.children[node].copy()
        if len(kids) > 0:
            y[node] = (y[kids[0]] + y[kids[len(kids) - 1]]) / 2.0
    var out = TreeDrawing(
        Framebuffer(width, height, Color(255, 255, 255)), tree.leaf_count()
    )
    var dark = Rgba(0.24, 0.24, 0.26, 1)
    for node in order:  # pragma: no branch
        var x = Int(floor(4.0 + depth[node] * scale + 0.5))
        var row = Int(floor(y[node] + 0.5))
        var parent = tree.parents[node]
        if parent >= 0:
            var px = Int(floor(4.0 + depth[parent] * scale + 0.5))
            draw_line(out.image, px, row, x, row, dark)
            draw_line(out.image, px, Int(floor(y[parent] + 0.5)), px, row, dark)
        if node < tree.leaf_count():
            out.xs[node] = x + 4
            out.ys[node] = row
    return out^

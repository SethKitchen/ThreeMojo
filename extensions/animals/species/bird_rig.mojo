# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The bird skeleton and wing geometry: procedural-animals' `core/rig/bird.js`.

The axial bones are pelvis, chest, `neck0` to `neckN-1`, head, jaw and
tail. Each leg is femur, tibia and tarsus with four two-bone toes. Each
wing is humerus, ulna and hand, and each flight feather is a bone of its
own: `pri{k}`, `sec{k}` and `rec{k}`, with a root and a tip joint.

A wing is three segments in a plane that the shoulder turns. `elev` turns
the plane about the body's long axis, `pitch` tilts it about the span,
`alpha` swings the humerus in the plane, `elbow` and `wrist` flex the
forearm and the hand, `bend` lifts the hand out of the plane and `twist`
pronates it. Folding the elbow and the wrist folds the wing against the
flank as a bird's.

procedural-animals renders flight and tail feathers as thin cards. Here
`feather_fins` sculpts each one as a planar fin with the card's outline,
so the folded wing and the tail have their silhouette.
"""

from extensions.sdf.ids import (
    BoneId,
    SurfacePart,
)
from extensions.animals.parts import (
    LIMB,
    TAIL,
)
from extensions.sdf.sculpt import ell_y
from extensions.animals.rig import Rig, add_sided
from extensions.sdf.field import SdfModel
from extensions.sdf.vector import (
    V3,
    cross,
    dot,
    length,
    lerp,
    mirror,
    normalize,
    rotate_about,
    smoothstep,
)
from extensions.animals.noise import ihash
from std.math import cos, floor, pi, sin, sqrt

# Radians in one degree.
comptime DEG = pi / 180.0
# A feather spec's "not given": the default applies.
comptime UNSET = -1.0e9

# Feather kinds.
comptime PRIMARY = 0
comptime SECONDARY = 1
comptime RECTRIX = 2


@fieldwise_init
struct WingPose(ImplicitlyCopyable):
    """One wing configuration, in degrees: procedural-animals' `bind`,
    `fold` and `glide` objects.

    `tilt` pitches the wing's root frame nose-up, for upright birds.
    """

    var elev: Float64
    var pitch: Float64
    var alpha: Float64
    var elbow: Float64
    var wrist: Float64
    var bend: Float64
    var twist: Float64
    var tilt: Float64


def lerp_pose(a: WingPose, b: WingPose, t: Float64) -> WingPose:
    """Return a configuration between two others.

    Args:
        a: The configuration at zero.
        b: The configuration at one.
        t: The fraction.

    Returns:
        The blend, key by key. The tilt is `a`'s.
    """
    return WingPose(
        a.elev + (b.elev - a.elev) * t,
        a.pitch + (b.pitch - a.pitch) * t,
        a.alpha + (b.alpha - a.alpha) * t,
        a.elbow + (b.elbow - a.elbow) * t,
        a.wrist + (b.wrist - a.wrist) * t,
        a.bend + (b.bend - a.bend) * t,
        a.twist + (b.twist - a.twist) * t,
        a.tilt,
    )


@fieldwise_init
struct WingFrames(ImplicitlyCopyable):
    """A wing's segment frames and its joints, from the shoulder.

    `xw` is the span axis and `n` the plane's dorsal normal. `d_h`, `d_u`
    and `d_m` are the humerus, the ulna and the hand, with their dorsal
    normals `n_h`, `n_u` and `n_m`. `elbow`, `wrist` and `tip` are
    relative to the shoulder.
    """

    var xw: V3
    var n: V3
    var d_h: V3
    var n_h: V3
    var d_u: V3
    var n_u: V3
    var d_m: V3
    var n_m: V3
    var elbow: V3
    var wrist: V3
    var tip: V3


def wing_fk(side: Float64, lengths: V3, a: WingPose) -> WingFrames:
    """Return a wing's frames: procedural-animals' `wingFK`.

    Args:
        side: One for the left wing, minus one for the right.
        lengths: The humerus, the ulna and the hand, in meters.
        a: The configuration, in degrees.

    Returns:
        The frames, in body-local axes, from the shoulder.
    """
    var s = side
    var ce = cos(a.elev * DEG)
    var se = sin(a.elev * DEG)
    var xw = V3(s * ce, se, 0.0)
    var n = V3(-s * se, ce, 0.0)
    n = rotate_about(n, xw, -s * a.pitch * DEG)
    var k = n * s
    var d_h = rotate_about(xw, k, a.alpha * DEG)
    var n_h = n
    var d_u = rotate_about(d_h, k, -a.elbow * DEG)
    var n_u = n
    var d_m0 = rotate_about(d_u, k, a.wrist * DEG)
    var cb = cos(a.bend * DEG)
    var sb = sin(a.bend * DEG)
    var d_m = d_m0 * cb + n_u * sb
    var n_m = n_u * cb - d_m0 * sb
    if a.twist != 0.0:
        n_m = rotate_about(n_m, d_m, s * a.twist * DEG)
    if a.tilt != 0.0:
        var ax = V3(1.0, 0.0, 0.0)
        var tl = -a.tilt * DEG
        xw = rotate_about(xw, ax, tl)
        n = rotate_about(n, ax, tl)
        d_h = rotate_about(d_h, ax, tl)
        n_h = rotate_about(n_h, ax, tl)
        d_u = rotate_about(d_u, ax, tl)
        n_u = rotate_about(n_u, ax, tl)
        d_m = rotate_about(d_m, ax, tl)
        n_m = rotate_about(n_m, ax, tl)
    var elbow = d_h * lengths.x
    var wrist = elbow + d_u * lengths.y
    var tip = wrist + d_m * lengths.z
    return WingFrames(xw, n, d_h, n_h, d_u, n_u, d_m, n_m, elbow, wrist, tip)


def extension(
    flex: Float64, fold_flex: Float64, spread_flex: Float64
) -> Float64:
    """Return how far a wing segment is spread, for the feather fan.

    Args:
        flex: The segment's flexion.
        fold_flex: Its flexion folded.
        spread_flex: Its flexion spread.

    Returns:
        Zero folded to one spread, eased.
    """
    var t = (fold_flex - flex) / (fold_flex - spread_flex)
    var c = 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)
    return c * c * (3.0 - 2.0 * c)


@fieldwise_init
struct Feather(ImplicitlyCopyable):
    """One resolved flight feather: procedural-animals' `resolveFeathers`.

    Angles are radians and lengths meters. `u` is the root along its
    wing segment and `x` a rectrix's lateral root offset. The `cov_`
    fields override its covert card, `UNSET` where the spec gives none.
    """

    var kind: Int
    var i: Int
    var n: Int
    var len: Float64
    var width: Float64
    var u: Float64
    var x: Float64
    var spread: Float64
    var fold: Float64
    var lift: Float64
    var back: Float64
    var bend: Float64
    var twist: Float64
    var emarg: Float64
    var outer: Float64
    var curve: Float64
    var droop: Float64
    var tip_round: Float64
    var arch: Float64
    var base0: Float64
    var arc: Float64
    var cov_skip: Bool
    var cov_lift: Float64
    var cov_shift: Float64
    var cov_len_k: Float64


def primary(
    i: Int,
    n: Int,
    u: Float64,
    len: Float64,
    width: Float64,
    spread: Float64,
    fold: Float64,
    emarg: Float64 = 0.0,
    lift: Float64 = UNSET,
    bend: Float64 = 0.0,
    twist: Float64 = 4.0,
    outer: Float64 = 0.32,
    curve: Float64 = 0.05,
    droop: Float64 = 0.02,
    tip_round: Float64 = 0.35,
    arch: Float64 = 0.12,
    base0: Float64 = 0.3,
) -> Feather:
    """Return a primary, with the original's defaults.

    Args:
        i: Its index, innermost first.
        n: How many primaries the wing has.
        u: Its root along the hand, as a fraction.
        len: Its length, in meters.
        width: Its vane's width, in meters.
        spread: Its angle from the hand spread, in degrees.
        fold: Its angle folded, in degrees.
        emarg: How deep its emargination is.
        lift: Its root's dorsal offset, in meters.
        bend: Its bend out of the wing plane, in degrees.
        twist: Its twist, in degrees.
        outer: The outer vane's share of the width.
        curve: The rachis's curve toward the inner vane.
        droop: The rachis's droop.
        tip_round: The rounded tip's share of the length.
        arch: How far the vane edges sit below the rachis.
        base0: The vane's width at the root, as a fraction.

    Returns:
        The feather.
    """
    return Feather(
        PRIMARY,
        i,
        n,
        len,
        width,
        u,
        0.0,
        spread * DEG,
        fold * DEG,
        Float64(n - 1 - i) * 0.0006 if lift == UNSET else lift,
        0.002,
        bend * DEG,
        twist * DEG,
        emarg,
        outer,
        curve,
        droop,
        tip_round,
        arch,
        base0,
        0.0,
        False,
        UNSET,
        UNSET,
        UNSET,
    )


def secondary(
    i: Int,
    n: Int,
    n_primaries: Int,
    u: Float64,
    len: Float64,
    width: Float64,
    spread: Float64,
    fold: Float64,
    lift: Float64 = UNSET,
    twist: Float64 = 3.0,
    outer: Float64 = 0.42,
    curve: Float64 = 0.03,
    droop: Float64 = 0.015,
    tip_round: Float64 = 0.5,
    arch: Float64 = 0.12,
    base0: Float64 = 0.3,
    cov_skip: Bool = False,
) -> Feather:
    """Return a secondary or a tertial, with the original's defaults.

    Args:
        i: Its index, from the wrist.
        n: How many secondaries the wing has.
        n_primaries: How many primaries the wing has.
        u: Its root along the ulna from the wrist, as a fraction.
        len: Its length, in meters.
        width: Its vane's width, in meters.
        spread: Its angle from the ulna spread, in degrees.
        fold: Its angle folded, in degrees.
        lift: Its root's dorsal offset, in meters.
        twist: Its twist, in degrees.
        outer: The outer vane's share of the width.
        curve: The rachis's curve toward the inner vane.
        droop: The rachis's droop.
        tip_round: The rounded tip's share of the length.
        arch: How far the vane edges sit below the rachis.
        base0: The vane's width at the root, as a fraction.
        cov_skip: Whether it has no covert card.

    Returns:
        The feather.
    """
    return Feather(
        SECONDARY,
        i,
        n,
        len,
        width,
        u,
        0.0,
        spread * DEG,
        fold * DEG,
        Float64(n_primaries + i) * 0.0006 if lift == UNSET else lift,
        0.002,
        0.0,
        twist * DEG,
        0.0,
        outer,
        curve,
        droop,
        tip_round,
        arch,
        base0,
        0.0,
        cov_skip,
        UNSET,
        UNSET,
        UNSET,
    )


def rectrix(
    i: Int,
    n: Int,
    x: Float64,
    len: Float64,
    width: Float64,
    fan: Float64,
    fold: Float64,
    bend: Float64 = 0.0,
    lift: Float64 = UNSET,
    twist: Float64 = 2.0,
    outer: Float64 = UNSET,
    droop: Float64 = 0.01,
    tip_round: Float64 = 0.55,
    arc: Float64 = 0.0,
) -> Feather:
    """Return a rectrix, with the original's defaults.

    The fan angle is kept in `spread`.

    Args:
        i: Its index, central first.
        n: How many rectrices a side.
        x: Its root's lateral offset, in meters.
        len: Its length, in meters.
        width: Its vane's width, in meters.
        fan: Its angle from the tail axis fanned, in degrees.
        fold: Its angle closed, in degrees.
        bend: Its bend out of the tail plane, in degrees.
        lift: Its root's dorsal offset, in meters.
        twist: Its twist, in degrees.
        outer: The outer vane's share of the width.
        droop: The rachis's droop.
        tip_round: The rounded tip's share of the length.
        arc: The rachis's arc toward the inner vane, in degrees.

    Returns:
        The feather.
    """
    var default_outer = 0.5 if i == 0 else 0.4
    return Feather(
        RECTRIX,
        i,
        n,
        len,
        width,
        0.0,
        x,
        fan * DEG,
        fold * DEG,
        Float64(n - 1 - i) * 0.0008 if lift == UNSET else lift,
        0.0,
        bend * DEG,
        twist * DEG,
        0.0,
        default_outer if outer == UNSET else outer,
        0.0,
        droop,
        tip_round,
        0.12,
        0.3,
        arc * DEG,
        False,
        UNSET,
        UNSET,
        UNSET,
    )


@fieldwise_init
struct FeatherFrame(ImplicitlyCopyable):
    """Where one feather is: its root, its unit axis and the unit normal
    of its vane's dorsal side."""

    var root: V3
    var axis: V3
    var normal: V3


def feather_frame(
    p0: V3,
    d: V3,
    n: V3,
    ls: Float64,
    side: Float64,
    f: Feather,
    a: Float64,
    inward: Bool,
) -> FeatherFrame:
    """Return one flight feather's frame: procedural-animals'
    `featherFrame`.

    Args:
        p0: The wrist.
        d: The segment's axis, outward.
        n: The segment's dorsal normal.
        ls: The segment's length.
        side: One for the left wing, minus one for the right.
        f: The feather.
        a: Its angle from `d` toward the trailing edge, in radians.
        inward: Whether the row runs from the wrist back along `-d`.

    Returns:
        The frame.
    """
    var s = side
    var t = cross(n, d) * s
    var along = (-1.0 if inward else 1.0) * ls * f.u
    var root = p0 + d * along + t * f.back + n * f.lift
    var ax = d * cos(a) + t * sin(a)
    ax = ax * cos(f.bend) + n * sin(f.bend)
    var axis = normalize(ax)
    var normal = normalize(n - axis * dot(n, axis))
    if f.twist != 0.0:
        normal = rotate_about(normal, axis, s * f.twist)
    return FeatherFrame(root, axis, normal)


def rectrix_frame(
    p0: V3, d: V3, n: V3, lat: V3, side: Float64, f: Feather, a: Float64
) -> FeatherFrame:
    """Return one rectrix's frame: procedural-animals' `rectrixFrame`.

    Args:
        p0: The tail's tip joint.
        d: The tail's axis, backward.
        n: The tail's dorsal normal.
        lat: The bird's left.
        side: One for the left half, minus one for the right.
        f: The rectrix.
        a: Its fan angle, outward, in radians.

    Returns:
        The frame.
    """
    var s = side
    var root = p0 + lat * (s * f.x) + n * f.lift
    var ax = d * cos(a) + lat * (s * sin(a))
    ax = ax * cos(f.bend) + n * sin(f.bend)
    var axis = normalize(ax)
    var normal = normalize(n - axis * dot(n, axis))
    if f.twist != 0.0:
        normal = rotate_about(normal, axis, -s * f.twist)
    return FeatherFrame(root, axis, normal)


def vane_width(f: Feather, t: Float64, w: Float64) -> Tuple[Float64, Float64]:
    """Return a vane's half widths: procedural-animals' `vaneWidth`.

    Args:
        f: The feather, or its covert's shape.
        t: Along it, from zero at the root to one at the tip.
        w: Its full width.

    Returns:
        The outer and the inner half width.
    """
    var base = f.base0 + (1.0 - f.base0) * smoothstep(0.0, 0.16, t)
    var tr = f.tip_round
    var tip = 1.0
    if t > 1.0 - tr:
        var x = (t - (1.0 - tr)) / tr
        tip = sqrt(max(0.0, 1.0 - x * x))
    var wo = w * f.outer * base * tip
    var wi = w * (1.0 - f.outer) * base * tip
    if f.emarg > 0.0:
        var k = smoothstep(0.5, 0.64, t) * f.emarg
        wi *= 1.0 - 0.62 * k
        wo *= 1.0 - 0.3 * k
    return (wo, max(wi, 0.0006))


def neck_chain(mut rig: Rig, segs: Int, t0: V3, t1: V3, bulge: Float64) raises:
    """Place the neck joints on an S-curve: procedural-animals'
    `neckChain`.

    The joints `neck1` to `neck{segs-1}` lie at equal arc length on a
    cubic Bezier from `neckBase` to `occiput` with the given end tangents.

    Args:
        rig: The rig, with `neckBase` and `occiput` placed.
        segs: How many neck segments.
        t0: The unit tangent at the base.
        t1: The unit tangent at the skull.
        bulge: How far the control points reach, as a fraction.

    Raises:
        Error: If a joint is missing.
    """
    var a = rig.j("neckBase")
    var b = rig.j("occiput")
    var d = length(b - a)
    var p1 = a + t0 * (d * bulge)
    var p2 = b - t1 * (d * bulge)
    comptime N = 200
    var pts = List[V3](capacity=N + 1)
    for i in range(N + 1):
        var t = Float64(i) / Float64(N)
        var u = 1.0 - t
        pts.append(
            a * (u * u * u)
            + p1 * (3.0 * u * u * t)
            + p2 * (3.0 * u * t * t)
            + b * (t * t * t)
        )
    var s: List[Float64] = [0.0]
    for i in range(1, N + 1):
        s.append(s[i - 1] + length(pts[i] - pts[i - 1]))
    for j in range(1, segs):
        var target = s[N] * Float64(j) / Float64(segs)
        var i = 1
        while i < N:
            if s[i] >= target:
                break
            i += 1
        var span = s[i] - s[i - 1]
        var f = (target - s[i - 1]) / (span if span != 0.0 else 1.0)
        rig.set("neck" + String(j), pts[i - 1] + (pts[i] - pts[i - 1]) * f)


def wing_joints(mut rig: Rig, lengths: V3, pose: WingPose) raises -> WingFrames:
    """Place the left wing's elbow, wrist and hand tip from a
    configuration.

    Args:
        rig: The rig, with `shoulderL` placed.
        lengths: The humerus, the ulna and the hand.
        pose: The configuration the wing is bound in.

    Returns:
        The wing's frames.

    Raises:
        Error: If `shoulderL` is missing.
    """
    var fr = wing_fk(1.0, lengths, pose)
    var sh = rig.j("shoulderL")
    rig.set("elbowL", sh + fr.elbow)
    rig.set("wristL", sh + fr.wrist)
    rig.set("handTipL", sh + fr.tip)
    return fr


def tail_frame(rig: Rig) raises -> Tuple[V3, V3]:
    """Return the bind tail's axis and dorsal normal.

    Args:
        rig: The rig, with `tailBase` and `tailTip` placed.

    Returns:
        The backward axis and the upward normal.

    Raises:
        Error: If a joint is missing.
    """
    var d = normalize(rig.j("tailTip") - rig.j("tailBase"))
    var n = normalize(cross(d, V3(1.0, 0.0, 0.0)))
    if n.y < 0.0:
        n = -n
    return (d, n)


def feather_frames(
    rig: Rig,
    lengths: V3,
    pose: WingPose,
    fold: WingPose,
    spread: WingPose,
    feathers: List[Feather],
    fan: Float64,
) raises -> List[FeatherFrame]:
    """Return every left feather's bind frame: procedural-animals'
    `featherJoints`.

    Args:
        rig: The rig, with the shoulder and the tail placed.
        lengths: The humerus, the ulna and the hand.
        pose: The configuration the wing is bound in.
        fold: The folded configuration.
        spread: The spread configuration.
        feathers: The feathers, primaries, secondaries, then rectrices.
        fan: How far the bind tail is fanned, from zero to one.

    Returns:
        One frame per feather, in order.

    Raises:
        Error: If a joint is missing.
    """
    var sh = rig.j("shoulderL")
    var fr = wing_fk(1.0, lengths, pose)
    var p0 = sh + fr.wrist
    var e_h = extension(pose.wrist * DEG, fold.wrist * DEG, spread.wrist * DEG)
    var e_u = extension(pose.elbow * DEG, fold.elbow * DEG, spread.elbow * DEG)
    var tf = tail_frame(rig)
    var tt = rig.j("tailTip")
    var lat = V3(1.0, 0.0, 0.0)
    var out = List[FeatherFrame](capacity=len(feathers))
    for f in feathers:
        if f.kind == PRIMARY:
            out.append(
                feather_frame(
                    p0,
                    fr.d_m,
                    fr.n_m,
                    lengths.z,
                    1.0,
                    f,
                    f.fold + (f.spread - f.fold) * e_h,
                    False,
                )
            )
        elif f.kind == SECONDARY:
            out.append(
                feather_frame(
                    p0,
                    fr.d_u,
                    fr.n_u,
                    lengths.y,
                    1.0,
                    f,
                    f.fold + (f.spread - f.fold) * e_u,
                    True,
                )
            )
        else:
            out.append(
                rectrix_frame(
                    tt,
                    tf[0],
                    tf[1],
                    lat,
                    1.0,
                    f,
                    f.fold + (f.spread - f.fold) * fan,
                )
            )
    return out^


def feather_bone(f: Feather) -> String:
    """Return a feather's bone name without its side.

    Args:
        f: The feather.

    Returns:
        `pri{k}`, `sec{k}` or `rec{k}`, counting from one.
    """
    var prefix = String("pri") if f.kind == PRIMARY else (
        String("sec") if f.kind == SECONDARY else String("rec")
    )
    return prefix + String(f.i + 1)


def feather_joints(
    mut rig: Rig, feathers: List[Feather], frames: List[FeatherFrame]
):
    """Place each left feather's root and tip joint.

    Args:
        rig: The rig.
        feathers: The feathers.
        frames: Their bind frames, in the same order.
    """
    for i in range(len(feathers)):
        var name = feather_bone(feathers[i])
        rig.set(name + "rL", frames[i].root)
        rig.set(name + "tL", frames[i].root + frames[i].axis * feathers[i].len)


def bird_bones(mut rig: Rig, neck_segs: Int, feathers: List[Feather]) raises:
    """Add procedural-animals' standard bird skeleton: `birdBones`.

    Args:
        rig: The rig, with every joint placed and mirrored.
        neck_segs: How many neck bones.
        feathers: The flight feathers, one bone a side each.

    Raises:
        Error: If a joint is missing.
    """
    _ = rig.add_bone("pelvis", "synsacrum", "tailBase", "")
    _ = rig.add_bone("chest", "synsacrum", "neckBase", "pelvis")
    for i in range(neck_segs):
        var a = String("neckBase") if i == 0 else "neck" + String(i)
        var b = String("occiput") if i + 1 == neck_segs else "neck" + String(
            i + 1
        )
        var parent = String("chest") if i == 0 else "neck" + String(i - 1)
        _ = rig.add_bone("neck" + String(i), a, b, parent)
    _ = rig.add_bone("head", "occiput", "bill", "neck" + String(neck_segs - 1))
    _ = rig.add_bone("jaw", "jawHinge", "jawTip", "head")
    _ = rig.add_bone("tail", "tailBase", "tailTip", "pelvis")
    add_sided(rig, "humerus{S}", "shoulder{S}", "elbow{S}", "chest")
    add_sided(rig, "ulna{S}", "elbow{S}", "wrist{S}", "humerus{S}")
    add_sided(rig, "hand{S}", "wrist{S}", "handTip{S}", "ulna{S}")
    add_sided(rig, "femur{S}", "hip{S}", "knee{S}", "pelvis")
    add_sided(rig, "tibia{S}", "knee{S}", "ankle{S}", "femur{S}")
    add_sided(rig, "tarsus{S}", "ankle{S}", "mtp{S}", "tibia{S}")
    for j in range(1, 5):
        var t = String(j)
        add_sided(
            rig, "toe" + t + "a{S}", "mtp{S}", "t" + t + "m{S}", "tarsus{S}"
        )
        add_sided(
            rig,
            "toe" + t + "b{S}",
            "t" + t + "m{S}",
            "t" + t + "t{S}",
            "toe" + t + "a{S}",
        )
    for f in feathers:
        var name = feather_bone(f)
        var parent = String("hand{S}") if f.kind == PRIMARY else (
            String("ulna{S}") if f.kind == SECONDARY else String("tail")
        )
        add_sided(rig, name + "{S}", name + "r{S}", name + "t{S}", parent)


def place_toe(
    mut rig: Rig,
    j: Int,
    yaw_deg: Float64,
    a: Float64,
    b: Float64,
    mid_y: Float64,
    tip_y: Float64,
    back: Bool = False,
) raises:
    """Place one left toe's middle and tip joint, lying on the ground.

    Args:
        rig: The rig, with `mtpL` placed.
        j: The toe: 1 the hallux, 2 inner, 3 middle, 4 outer.
        yaw_deg: Its yaw, in degrees.
        a: Its first segment's length.
        b: Its second segment's length.
        mid_y: The middle joint's height.
        tip_y: The tip's height.
        back: Whether it points backward.

    Raises:
        Error: If `mtpL` is missing.
    """
    var y = yaw_deg * DEG
    var m = rig.j("mtpL")
    var dz = -cos(y) if back else cos(y)
    var dx = sin(y)
    rig.set("t" + String(j) + "mL", V3(m.x + dx * a, mid_y, m.z + dz * a))
    rig.set(
        "t" + String(j) + "tL",
        V3(m.x + dx * (a + b), tip_y, m.z + dz * (a + b)),
    )


def wing_normal(rig: Rig, side: String) raises -> V3:
    """Return a wing's dorsal plane normal from its bind joints.

    Args:
        rig: The rig.
        side: `L` or `R`.

    Returns:
        The unit normal, pointing up.

    Raises:
        Error: If a joint is missing.
    """
    var sh = rig.j("shoulder" + side)
    var el = rig.j("elbow" + side)
    var wr = rig.j("wrist" + side)
    var n = normalize(cross(el - sh, wr - el))
    return -n if n.y < 0.0 else n


def wing_segment(
    mut m: SdfModel,
    s: Float64,
    n: V3,
    a: V3,
    b: V3,
    bone: BoneId,
    thick: Float64,
    chord: Float64,
    back: Float64,
    tag: String,
    k: Float64,
    drop: Float64 = 0.0,
) raises:
    """Add one wing segment's flesh: the sculpts' `seg`.

    Args:
        m: The sculpt.
        s: One for the left wing, minus one for the right.
        n: The wing plane's dorsal normal.
        a: The segment's start.
        b: The segment's end.
        bone: The bone it rides.
        thick: Its half thickness across the plane.
        chord: Its half chord.
        back: How far it sits toward the trailing edge.
        tag: What it is.
        k: The blend radius.
        drop: How far it hangs below the bones.

    Raises:
        Error: If the sculpt refuses it.
    """
    var d = normalize(b - a)
    var t = normalize(cross(n, d)) * s
    var c = lerp(a, b, 0.5) + t * back - n * drop
    _ = ell_y(
        m,
        tag,
        bone,
        c,
        d,
        V3(thick, length(b - a) * 0.58, chord),
        lateral=n,
        k=k,
    )


def _card_point(
    f: Feather, ln: Float64, w: Float64, t: Float64, c: Float64
) -> Tuple[Float64, Float64]:
    # A card's outline point in its plane: along the axis and toward the
    # inner vane. The droop and the arch leave the plane and are dropped.
    var vw = vane_width(f, t, w)
    var hw = vw[0] if c < 0.0 else vw[1]
    if f.arc > 0.0:
        var a = f.arc * t
        var r = ln / f.arc
        return (
            r * sin(a) - sin(a) * c * hw,
            r * (1.0 - cos(a)) + cos(a) * c * hw,
        )
    return (t * ln, f.curve * ln * t * t + c * hw)


def card_outline(
    f: Feather, ln: Float64, w: Float64, samples: Int
) -> List[Float64]:
    """Return a feather card's outline in its plane, as flat pairs.

    The first coordinate runs along the feather's axis, the second
    toward its inner vane.

    Args:
        f: The feather, or its covert's shape.
        ln: Its length.
        w: Its full width.
        samples: Points along each edge.

    Returns:
        The closed outline: the inner edge root to tip, then the outer
        edge tip to root.
    """
    var out = List[Float64]()
    for side in [1.0, -1.0]:
        for j in range(samples + 1):
            var q = Float64(j) / Float64(samples)
            if side < 0.0:
                q = 1.0 - q
            # Denser toward the round tip.
            var t = min(sin(q * pi * 0.5), 0.995)
            var p = _card_point(f, ln, w, t, side)
            out.append(p[0])
            out.append(p[1])
    return out^


@fieldwise_init
struct CardShape(ImplicitlyCopyable):
    """One card cut from a feather: its tag, its length and width
    factors, its root's lift and shift, and the feather it is shaped as.
    """

    var tag: String
    var len_k: Float64
    var width_k: Float64
    var lift: Float64
    var shift: Float64
    var shape: Feather


def covert_card(f: Feather, coverts: V3) -> CardShape:
    """Return a feather's covert card: procedural-animals' card options.

    Args:
        f: The feather.
        coverts: The primary, secondary and tail covert length fractions.

    Returns:
        The covert's card. Its tag is empty when the feather has none.
    """
    var shape = f
    if f.kind == PRIMARY:
        shape.emarg = 0.0
        shape.tip_round = 0.6
        shape.outer = 0.45
        shape.curve = 0.02
        var lk = coverts.x * (
            1.0 - 0.25 * Float64(f.i) / Float64(max(1, f.n - 1))
        )
        return CardShape(
            "primaryCovert",
            lk if f.cov_len_k == UNSET else f.cov_len_k,
            1.05,
            0.0022 if f.cov_lift == UNSET else f.cov_lift,
            -0.004 if f.cov_shift == UNSET else f.cov_shift,
            shape,
        )
    if f.kind == SECONDARY:
        shape.tip_round = 0.65
        shape.outer = 0.45
        shape.curve = 0.02
        return CardShape(
            "secondaryCovert", coverts.y, 1.15, 0.0028, -0.006, shape
        )
    shape.tip_round = 0.7
    shape.outer = 0.5
    var tag = String("tailCovert") if f.i < 4 else String("")
    return CardShape(
        tag, coverts.z * (1.0 - 0.1 * Float64(f.i)), 1.2, 0.0025, -0.012, shape
    )


def feather_fins(
    mut m: SdfModel,
    rig: Rig,
    feathers: List[Feather],
    frames: List[FeatherFrame],
    thickness: Float64,
    k: Float64,
    coverts: V3 = V3(0.0, 0.0, 0.0),
    wing_part: SurfacePart = LIMB,
    tail_part: SurfacePart = TAIL,
    tail_k: Float64 = 1.0,
    width_k: Float64 = 1.0,
    tail_fins: Bool = True,
) raises:
    """Sculpt every flight and tail feather as flattened ellipsoids on
    its own bone.

    Each card is one flattened ellipsoid in the card's plane, as long as
    the card and as wide as its vane, or a chain of them along a curved
    rachis. Tags are the card's kind, `primary`, `secondary`, `rectrix`,
    `primaryCovert`, `secondaryCovert` or `tailCovert`, then
    `@x,y/length`: the solid's center in the card's plane and the card's
    length, in 10 micrometer units. `card_point` reads them back. The
    straight rectrices can instead be joined into one fin a side by
    `tail_fan`, whose tag has `#` for `@`.

    Args:
        m: The sculpt.
        rig: The rig, with the feather bones.
        feathers: The feathers.
        frames: Their left bind frames, in the same order.
        thickness: The cards' thickness.
        k: Their blend radius.
        coverts: The covert length fractions. Zero adds no coverts.
        wing_part: The surface the wing's feathers belong to.
        tail_part: The surface the rectrices belong to.
        tail_k: A factor on the rectrices' lengths.
        width_k: A factor on every card's width.
        tail_fins: Whether the straight rectrices are joined into one
            fin a side rather than ellipsoids.

    Raises:
        Error: If a bone is missing or the sculpt refuses a solid.
    """
    for i in range(len(feathers)):
        var f = feathers[i]
        var cards = List[CardShape]()
        var kind = String("primary") if f.kind == PRIMARY else (
            String("secondary") if f.kind == SECONDARY else String("rectrix")
        )
        cards.append(CardShape(kind, 1.0, 1.0, 0.0, 0.0, f))
        var cov = covert_card(f, coverts)
        var wanted = cov.tag.byte_length() > 0 and not f.cov_skip
        var cond1 = wanted and coverts.x > 0.0
        if cond1:
            cards.append(cov)
        var ln0 = f.len * (tail_k if f.kind == RECTRIX else 1.0)
        for card in cards:
            var ln = ln0 * card.len_k
            var w = f.width * card.width_k * width_k
            var sh = card.shape
            # The closed tail's straight rectrices are one fin a side:
            # `tail_fan`. Arched ones stay chains of ellipsoids.
            var fan = f.kind == RECTRIX and tail_fins and sh.arc == 0.0
            if fan:
                continue
            # An arched rachis is a chain of pieces. A gently curved one is
            # one piece along its chord.
            var pieces = 1 + Int(sh.arc / 0.3)
            for q in range(pieces):
                var t0 = Float64(q) / Float64(pieces)
                var t1 = Float64(q + 1) / Float64(pieces)
                var tm = 0.5 * (t0 + t1)
                var mid = _card_point(sh, ln, w, tm, 0.0)
                var dx: Float64
                var dy: Float64
                if sh.arc > 0.0:
                    dx = cos(sh.arc * tm)
                    dy = sin(sh.arc * tm)
                else:
                    var l = sqrt(1.0 + sh.curve * sh.curve)
                    dx = 1.0 / l
                    dy = sh.curve / l
                    mid = (0.5 * ln, 0.5 * sh.curve * ln)
                var vw = vane_width(sh, max(tm, 0.5) if pieces == 1 else tm, w)
                var half_len = (
                    (t1 - t0) * ln * 0.5 * (1.0 if pieces == 1 else 1.3)
                )
                var half_w = 0.5 * (vw[0] + vw[1]) * 1.08
                # The vane is wider on its inner side: shift toward it.
                var off = 0.5 * (vw[1] - vw[0])
                var cx = mid[0] - dy * off
                var cy = mid[1] + dx * off
                var tag = (
                    card.tag
                    + "@"
                    + String(Int(cx * 1e5))
                    + ","
                    + String(Int(cy * 1e5))
                    + "/"
                    + String(Int(ln * 1e5))
                )
                for side in [String("L"), String("R")]:
                    var s = 1.0 if side == "L" else -1.0
                    var fr = frames[i]
                    var root = (
                        fr.root + fr.normal * card.lift + fr.axis * card.shift
                    )
                    var axis = fr.axis
                    var normal = fr.normal
                    if s < 0.0:
                        root = mirror(root)
                        axis = mirror(axis)
                        normal = mirror(normal)
                    var tv = normalize(cross(normal, axis)) * s
                    _ = m.ell(
                        tag,
                        rig.bone(feather_bone(f) + side),
                        root + axis * cx + tv * cy,
                        V3(half_w, thickness * 0.5, half_len),
                        axis=axis * dx + tv * dy,
                        up=normal,
                        k=k,
                        part=tail_part if f.kind == RECTRIX else wing_part,
                        thin=True,
                    )
    if tail_fins:
        tail_fan(m, rig, feathers, frames, thickness, k, tail_part, tail_k)


def star_union(
    polys: List[List[Float64]], cx: Float64, cy: Float64, rays: Int
) -> List[Float64]:
    """Return the union of some outlines, as seen from a point inside
    them all: the farthest crossing of each ray with any outline.

    Args:
        polys: The outlines, as flat `u, v` pairs.
        cx: The point's `u`.
        cy: The point's `v`.
        rays: How many rays, evenly around.

    Returns:
        The star-shaped outline, as flat pairs.
    """
    var union = List[Float64]()
    for r in range(rays):
        var phi = 2.0 * pi * Float64(r) / Float64(rays)
        var dx = cos(phi)
        var dy = sin(phi)
        var far = 0.0
        for poly in polys:
            var count_p = len(poly) // 2
            for e in range(count_p):
                var e2 = (e + 1) % count_p
                var ax = poly[e * 2] - cx
                var ay = poly[e * 2 + 1] - cy
                var bx = poly[e2 * 2] - cx
                var by = poly[e2 * 2 + 1] - cy
                # Solve c * (dx, dy) = A + u (B - A) for c and u.
                var ex = bx - ax
                var ey = by - ay
                var den = dx * ey - dy * ex
                if abs(den) < 1e-12:
                    continue
                var c = (ax * ey - ay * ex) / den
                var u = (ax * dy - ay * dx) / den
                var hit = c > 0.0 and u >= 0.0 and u <= 1.0
                if hit:
                    far = max(far, c)
        union.append(cx + dx * max(far, 1e-4))
        union.append(cy + dy * max(far, 1e-4))
    return union^


def tail_fan(
    mut m: SdfModel,
    rig: Rig,
    feathers: List[Feather],
    frames: List[FeatherFrame],
    thickness: Float64,
    k: Float64,
    part: SurfacePart,
    tail_k: Float64 = 1.0,
) raises:
    """Sculpt the closed tail as one fin a side: the union of its
    straight rectrices' outlines.

    At rest the rectrices lie almost on one another. Their outlines are
    laid in their mean plane and joined as one star-shaped outline, seen
    from their middle. The fin rides the central rectrix's bone and its
    tag reads as a `rectrix` card's.

    Args:
        m: The sculpt.
        rig: The rig, with the feather bones.
        feathers: The feathers. Only straight rectrices are joined.
        frames: Their left bind frames, in the same order.
        thickness: The fin's thickness.
        k: Its blend radius.
        part: The surface it belongs to.
        tail_k: A factor on the rectrices' lengths.

    Raises:
        Error: If a bone is missing or the sculpt refuses the fin.
    """
    var ids = List[Int]()
    var sum_axis = V3(0.0, 0.0, 0.0)
    var sum_normal = V3(0.0, 0.0, 0.0)
    var o = V3(0.0, 0.0, 0.0)
    var ln_max = 0.0
    for i in range(len(feathers)):
        var straight = feathers[i].kind == RECTRIX and feathers[i].arc == 0.0
        if straight:
            ids.append(i)
            sum_axis = sum_axis + frames[i].axis
            sum_normal = sum_normal + frames[i].normal
            o = o + frames[i].root
            ln_max = max(ln_max, feathers[i].len * tail_k)
    if len(ids) == 0:
        return
    o = o * (1.0 / Float64(len(ids)))
    var a = normalize(sum_axis)
    var n = normalize(sum_normal - a * dot(sum_normal, a))
    var tv = cross(n, a)
    # Every outline, in the mean plane.
    var polys = List[List[Float64]]()
    var cx0 = 0.0
    var cy0 = 0.0
    var count = 0
    for i in ids:
        var f = feathers[i]
        var fr = frames[i]
        var ftv = normalize(cross(fr.normal, fr.axis))
        var poly = card_outline(f, f.len * tail_k, f.width, 4)
        var flat = List[Float64]()
        for e in range(0, len(poly), 2):
            var q = fr.root + fr.axis * poly[e] + ftv * poly[e + 1] - o
            flat.append(dot(q, a))
            flat.append(dot(q, tv))
            cx0 += dot(q, a)
            cy0 += dot(q, tv)
            count += 1
        polys.append(flat^)
    cx0 /= Float64(count)
    cy0 /= Float64(count)
    var union = star_union(polys, cx0, cy0, 40)
    var lo_x = 1e9
    var hi_x = -1e9
    var lo_y = 1e9
    var hi_y = -1e9
    for e in range(0, len(union), 2):
        lo_x = min(lo_x, union[e])
        hi_x = max(hi_x, union[e])
        lo_y = min(lo_y, union[e + 1])
        hi_y = max(hi_y, union[e + 1])
    var cx = 0.5 * (lo_x + hi_x)
    var cy = 0.5 * (lo_y + hi_y)
    for e in range(0, len(union), 2):
        union[e] -= cx
        union[e + 1] -= cy
    var tag = (
        String("rectrix#")
        + String(Int(cx * 1e5))
        + ","
        + String(Int(cy * 1e5))
        + "/"
        + String(Int(ln_max * 1e5))
    )
    var bone = feather_bone(feathers[ids[0]])
    for side in [String("L"), String("R")]:
        var s = 1.0 if side == "L" else -1.0
        var oo = o
        var aa = a
        var nn = n
        if s < 0.0:
            oo = mirror(o)
            aa = mirror(a)
            nn = mirror(n)
        var vv = normalize(cross(nn, aa)) * s
        _ = m.fin(
            tag,
            rig.bone(bone + side),
            oo + aa * cx + vv * cy,
            aa,
            vv,
            union,
            thickness,
            k=k,
            part=part,
            thin=True,
        )


@fieldwise_init
struct CardPoint(ImplicitlyCopyable):
    """Where a vertex lies on a feather card: the card's kind, how far
    along it, how far toward its inner vane, and whether it is on the
    card's dorsal face."""

    var kind: String
    var t: Float64
    var across: Float64
    var top: Bool


def card_point(tag: String, local: V3, right: Bool) raises -> CardPoint:
    """Return where a vertex lies on a feather card, from its tag.

    Args:
        tag: The solid's tag, as `feather_fins` writes it.
        local: The vertex in the solid's frame.
        right: Whether the solid is on the bird's right side.

    Returns:
        The kind, the fraction along the card from its root, the offset
        toward its inner vane in meters, and the face.

    Raises:
        Error: If the tag is not a feather card's.
    """
    var fin = tag.find("#")
    var at = fin if fin >= 0 else tag.find("@")
    var comma = tag.find(",")
    var slash = tag.find("/")
    var cond2 = at < 0 or comma < at or slash < comma
    if cond2:
        raise Error("Not a feather card's tag: " + tag)
    var cx = Float64(Int(tag[byte = at + 1 : comma])) * 1e-5
    var cy = Float64(Int(tag[byte = comma + 1 : slash])) * 1e-5
    var ln = Float64(Int(tag[byte = slash + 1 :])) * 1e-5
    var sgn = -1.0 if right else 1.0
    # A fin's frame is along, across and its normal; an ellipsoid's is
    # across, its normal and along.
    var along = local.x if fin >= 0 else local.z
    var across = local.y if fin >= 0 else local.x * sgn
    var up = local.z * sgn if fin >= 0 else local.y
    return CardPoint(
        String(tag[byte=:at]),
        min(1.0, max(0.0, (cx + along) / ln)),
        cy + across,
        up > 0.0,
    )


def is_card(tag: String) -> Bool:
    """Return True for a feather card's tag.

    Args:
        tag: The tag.

    Returns:
        Whether `feather_fins` made it.
    """
    return tag.find("@") >= 0 or tag.find("#") >= 0


@fieldwise_init
struct Plume(ImplicitlyCopyable):
    """Where a point lies on the contour feather that covers it.

    `along` runs from about -1 at the covered root to 1 at the exposed
    tip, along the plumage's flow. `across` is the offset from the
    shaft, in the same units. `edge` is the gap to the next feather's
    border: zero on it. `id` is a number in `[0, 1)` that names the
    feather.
    """

    var along: Float64
    var across: Float64
    var edge: Float64
    var id: Float64


def plume(p: V3, size: Float64, flow: V3) -> Plume:
    """Return the contour feather a point lies on: jittered feather
    centers about `size` apart, laid along the plumage's flow.

    Args:
        p: The point, in the reference animal, in meters.
        size: The feathers' spacing, in meters.
        flow: The direction the feathers point.

    Returns:
        The point on its feather.
    """
    var a = normalize(flow)
    var side = cross(a, V3(0.0, 1.0, 0.0))
    if length(side) < 1e-3:
        side = cross(a, V3(1.0, 0.0, 0.0))
    var b = normalize(side)
    var q = p * (1.0 / size)
    # The eight cells nearest the point: the feature points are jittered
    # within their cells, so the nearest one is almost always there.
    var xi = Int(floor(q.x - 0.5))
    var yi = Int(floor(q.y - 0.5))
    var zi = Int(floor(q.z - 0.5))
    var best = 9.0
    var next = 9.0
    var off = V3(0.0, 0.0, 0.0)
    var id = 0.0
    for n in range(8):
        var cx = xi + n % 2
        var cy = yi + (n // 2) % 2
        var cz = zi + n // 4
        var f = V3(
            Float64(cx) + 0.15 + 0.7 * ihash(cx, cy, cz),
            Float64(cy) + 0.15 + 0.7 * ihash(cx + 31, cy, cz),
            Float64(cz) + 0.15 + 0.7 * ihash(cx, cy + 57, cz),
        )
        var d = q - f
        # Feathers are longer than wide: distance is squeezed along the
        # flow.
        var da = dot(d, a)
        var dd = sqrt(max(0.0, dot(d, d) - da * da) + 0.45 * da * da)
        var closer = dd < best
        next = best if closer else min(next, dd)
        off = d if closer else off
        id = ihash(cx + 7, cy + 11, cz + 13) if closer else id
        best = dd if closer else best
    return Plume(dot(off, a) / 0.6, dot(off, b) / 0.6, next - best, id)


def shingle(pl: Plume) -> Float64:
    """Return a contour feather's shading: its covered root darker than
    its exposed tip, and a fine dark line where the next one overlaps.

    Args:
        pl: The point on its feather.

    Returns:
        A factor near one.
    """
    var tip = smoothstep(-0.8, 0.6, pl.along)
    var line = smoothstep(0.0, 0.08, pl.edge)
    return (0.92 + 0.1 * tip) * (0.95 + 0.05 * line)

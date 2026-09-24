# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `animation.ccd_ik_solver`, three.js's `CCDIKSolver`."""

from animation.ccd_ik_solver import CCDIKSolver, IkChain, IkLink
from core.geometry_store import GeometryId
from core.object3d import NO_PARENT, NodeId, Object3D
from core.scene import Scene
from materials.material import MaterialId
from math.euler import Euler, XYZ
from math.vector3 import Vector3
from objects.skeleton import bind_skeleton
from objects.skinned_mesh import SkinnedMesh
from std.testing import (
    TestSuite,
    assert_almost_equal,
    assert_equal,
    assert_raises,
    assert_true,
)
from units.si import Angle, DEGREE, RADIAN

comptime TOLERANCE = Float64(1e-3)


def placed(
    mut scene: Scene, parent: NodeId, x: Float32, y: Float32, z: Float32
) raises -> NodeId:
    """Add a node at a position under a parent."""
    var node = Object3D()
    node.parent = parent
    node.set_position(x, y, z)
    return scene.add(node^)


def arm(mut scene: Scene, tx: Float32, ty: Float32) raises:
    """Add an arm of two links, a shoulder at the origin, an elbow a meter
    up and a hand a meter above that, and a target bone at (tx, ty, 0).

    Bones: 0 shoulder, 1 elbow, 2 hand, 3 target.
    """
    var shoulder = placed(scene, NO_PARENT, 0, 0, 0)
    var elbow = placed(scene, shoulder, 0, 1, 0)
    var hand = placed(scene, elbow, 0, 1, 0)
    var target = placed(scene, NO_PARENT, tx, ty, 0)
    var mesh = placed(scene, NO_PARENT, 0, 0, 0)
    scene.update()
    var nodes: List[NodeId] = [shoulder, elbow, hand, target]
    var skeleton = bind_skeleton(
        nodes,
        [
            scene.world_matrix(shoulder),
            scene.world_matrix(elbow),
            scene.world_matrix(hand),
            scene.world_matrix(target),
        ],
    )
    scene.add_skinned_mesh(
        SkinnedMesh(GeometryId(0), MaterialId(0), mesh, skeleton^)
    )
    scene.update()


def reach(var links: List[IkLink]) -> IkChain:
    """Return a chain from the hand to the target over `links`."""
    return IkChain(3, 2, links^)


def two_links() -> List[IkLink]:
    """Return the elbow and the shoulder, free."""
    return [IkLink(1), IkLink(0)]


def hand(scene: Scene) raises -> Vector3:
    """Return where the hand is."""
    return scene.world_position(scene.skinned_meshes[0].skeleton.node(2))


def test_the_hand_reaches_the_target() raises:
    var scene = Scene()
    arm(scene, 1, 1)
    var chain = reach(two_links())
    chain.iteration = 20
    var chains = List[IkChain]()
    chains.append(chain^)
    var solver = CCDIKSolver(scene, 0, chains^)
    solver.update(scene)
    var at = hand(scene)
    assert_almost_equal(at.x, Float32(1), atol=TOLERANCE)
    assert_almost_equal(at.y, Float32(1), atol=TOLERANCE)


def test_no_pass_and_a_disabled_link_turn_nothing() raises:
    var scene = Scene()
    arm(scene, 1, 1)
    var idle = reach(two_links())
    idle.iteration = 0
    var off = two_links()
    off[0].enabled = False
    var chains = List[IkChain]()
    chains.append(idle^)
    chains.append(reach(off^))
    var solver = CCDIKSolver(scene, 0, chains^)
    solver.update(scene)
    assert_almost_equal(hand(scene).y, Float32(2), atol=TOLERANCE)


def test_a_hand_on_target_does_not_tremble() raises:
    var scene = Scene()
    arm(scene, 0, 2)
    var chains = List[IkChain]()
    chains.append(reach(two_links()))
    var solver = CCDIKSolver(scene, 0, chains^)
    solver.update(scene)
    assert_almost_equal(hand(scene).x, Float32(0), atol=TOLERANCE)


def elbow_turn(scene: Scene) raises -> Float32:
    """Return how far the elbow has turned about z, in degrees."""
    var turned = scene.get(scene.skinned_meshes[0].skeleton.node(1))
    return turned.rotation(XYZ).z.value * 180 / 3.14159265


def test_a_turn_is_clamped() raises:
    # The elbow alone; the target far to the right needs a big turn.
    var scene = Scene()
    arm(scene, 3, 1)
    var chain = reach([IkLink(1)])
    chain.max_angle = Angle(5, DEGREE)
    var chains = List[IkChain]()
    chains.append(chain^)
    var solver = CCDIKSolver(scene, 0, chains^)
    solver.update(scene)
    assert_almost_equal(elbow_turn(scene), Float32(-5), atol=0.01)
    # A smallest turn larger than what is needed overshoots.
    var other = Scene()
    arm(other, 0.05, 3)
    var small = reach([IkLink(1)])
    small.min_angle = Angle(30, DEGREE)
    var more = List[IkChain]()
    more.append(small^)
    var pushed = CCDIKSolver(other, 0, more^)
    pushed.update(other)
    assert_almost_equal(abs(elbow_turn(other)), Float32(30), atol=0.01)


def test_a_limited_link_turns_about_its_axis() raises:
    var scene = Scene()
    arm(scene, 1, 1)
    var link = IkLink(1)
    link.limitation = Vector3(1, 0, 0)
    var chains = List[IkChain]()
    chains.append(reach([link^]))
    var solver = CCDIKSolver(scene, 0, chains^)
    solver.update(scene)
    var q = scene.get(scene.skinned_meshes[0].skeleton.node(1)).quaternion
    assert_almost_equal(q.y, Float32(0), atol=TOLERANCE)
    assert_almost_equal(q.z, Float32(0), atol=TOLERANCE)


def test_euler_bounds_clamp_the_link() raises:
    var scene = Scene()
    arm(scene, 3, 1)
    var link = IkLink(1)
    link.rotation_min = Euler(
        Angle(0, RADIAN), Angle(0, RADIAN), Angle(-10, DEGREE), XYZ
    )
    link.rotation_max = Euler(
        Angle(0, RADIAN), Angle(0, RADIAN), Angle(10, DEGREE), XYZ
    )
    var chains = List[IkChain]()
    chains.append(reach([link^]))
    var solver = CCDIKSolver(scene, 0, chains^)
    solver.update(scene)
    assert_almost_equal(elbow_turn(scene), Float32(-10), atol=0.01)
    # And to the other side, bounded below.
    var other = Scene()
    arm(other, -3, 1)
    var left = IkLink(1)
    left.rotation_min = Euler(
        Angle(0, RADIAN), Angle(0, RADIAN), Angle(-10, DEGREE), XYZ
    )
    left.rotation_max = Euler(
        Angle(0, RADIAN), Angle(0, RADIAN), Angle(10, DEGREE), XYZ
    )
    var more = List[IkChain]()
    more.append(reach([left^]))
    var bounded = CCDIKSolver(other, 0, more^)
    bounded.update(other)
    assert_almost_equal(elbow_turn(other), Float32(10), atol=0.01)


def test_a_blend_moves_part_way() raises:
    var solved = Scene()
    arm(solved, 3, 1)
    var full = List[IkChain]()
    full.append(reach([IkLink(1)]))
    var whole = CCDIKSolver(solved, 0, full^)
    whole.update(solved)
    var all_the_way = elbow_turn(solved)
    # The solver's blend.
    var scene = Scene()
    arm(scene, 3, 1)
    var chains = List[IkChain]()
    chains.append(reach([IkLink(1)]))
    var solver = CCDIKSolver(scene, 0, chains^)
    solver.update(scene, 0.5)
    assert_almost_equal(elbow_turn(scene), all_the_way / 2, atol=0.01)
    # The chain's own blend wins over the solver's.
    var other = Scene()
    arm(other, 3, 1)
    var own = reach([IkLink(1)])
    own.blend_factor = Float32(0.25)
    var mine = List[IkChain]()
    mine.append(own^)
    var blended = CCDIKSolver(other, 0, mine^)
    blended.update_one(other, 0, 1)
    assert_almost_equal(elbow_turn(other), all_the_way / 4, atol=0.01)


def test_the_solver_refuses_what_it_cannot_solve() raises:
    var scene = Scene()
    arm(scene, 1, 1)
    with assert_raises(contains="No skinned mesh"):
        _ = CCDIKSolver(scene, 1, List[IkChain]())
    with assert_raises(contains="No skinned mesh"):
        _ = CCDIKSolver(scene, -1, List[IkChain]())
    var chains = List[IkChain]()
    chains.append(IkChain(4, 2, List[IkLink]()))
    with assert_raises(contains="does not have"):
        _ = CCDIKSolver(scene, 0, chains^)
    chains = List[IkChain]()
    chains.append(IkChain(3, -1, List[IkLink]()))
    with assert_raises(contains="does not have"):
        _ = CCDIKSolver(scene, 0, chains^)
    chains = List[IkChain]()
    chains.append(reach([IkLink(9)]))
    with assert_raises(contains="does not have"):
        _ = CCDIKSolver(scene, 0, chains^)
    var backward = reach(two_links())
    backward.iteration = -1
    chains = List[IkChain]()
    chains.append(backward^)
    with assert_raises(contains="negative"):
        _ = CCDIKSolver(scene, 0, chains^)
    for wrong in [Float32(-0.5), Float32(1.5)]:
        var blended = reach(two_links())
        blended.blend_factor = wrong
        chains = List[IkChain]()
        chains.append(blended^)
        with assert_raises(contains="from zero to one"):
            _ = CCDIKSolver(scene, 0, chains^)
    chains = List[IkChain]()
    chains.append(reach(two_links()))
    var solver = CCDIKSolver(scene, 0, chains^)
    with assert_raises(contains="No IK chain"):
        solver.update_one(scene, 1)
    with assert_raises(contains="No IK chain"):
        solver.update_one(scene, -1)
    with assert_raises(contains="from zero to one"):
        solver.update(scene, 2)
    with assert_raises(contains="from zero to one"):
        solver.update(scene, -1)
    var empty = Scene()
    with assert_raises(contains="not there"):
        solver.update(empty)
    # No chains at all, or a chain of no links, solve to nothing.
    var none = CCDIKSolver(scene, 0, List[IkChain]())
    none.update(scene)
    var bare = List[IkChain]()
    bare.append(IkChain(3, 2, List[IkLink]()))
    var empty_chain = CCDIKSolver(scene, 0, bare^)
    empty_chain.update(scene)
    empty_chain.update(scene, 0.5)
    assert_almost_equal(hand(scene).y, Float32(2), atol=TOLERANCE)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()

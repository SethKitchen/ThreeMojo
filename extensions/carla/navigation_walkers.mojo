# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""CARLA's AI walkers in a world: `controller.ai.walker`.

A `WalkerNavigation` joins a `Navigation` and its `WalkerManager` to a
`World`, as CARLA's client does. It builds the pedestrian mesh from the
world's map and reads the traffic lights' stop waypoints. Call `tick`
after each `World.tick`. It does this, in order:

1. It checks one registered walker, in turn: a walker that is gone
   leaves the crowd, and its controller is destroyed.
2. It gives the crowd every vehicle's box.
3. It tells the manager each light's state.
4. It advances the crowd by the world's step.
5. It moves each walker to its place in the crowd: its feet on the mesh,
   raised by half the walker's box, and its velocity. The walker's control
   carries the direction and the speed.

A `WalkerAIController` is the actor that CARLA's `controller.ai.walker`
blueprint makes, with a walker as its parent. `start` puts the walker in
the crowd and turns its gravity off; `go_to_location`, `set_max_speed`,
`get_random_location` and `stop` follow CARLA's client.

The sources are CARLA's `LibCarla/source/carla/client/
WalkerAIController.cpp` and `client/detail/WalkerNavigation.cpp`.

**Differences from CARLA.** CARLA turns off a walker's physics and
collisions and sets its pose. The world here keeps the walker's body; it
turns off its gravity and sets its pose and velocity at each tick.
CARLA's walkers can be killed by vehicles; these cannot.
"""

from extensions.carla.actor import ActorId, NO_ACTOR
from extensions.carla.navigation import (
    Navigation,
    VehicleCollisionInfo,
    WalkerManager,
    WalkerTrafficLight,
)
from extensions.carla.navigation_mesh import build_navigation_mesh
from extensions.carla.physics.walker import WalkerControl
from extensions.carla.world import World
from math.vector3 import Vector3
from std.math import sqrt
from units.si import METER, Length, Velocity


@fieldwise_init
struct WalkerHandle(Equatable, ImplicitlyCopyable):
    """A walker and its controller, `WalkerHandle`."""

    var walker: ActorId
    var controller: ActorId


struct WalkerNavigation(Movable):
    """The client's walker navigation, `WalkerNavigation`."""

    var nav: Navigation
    var manager: WalkerManager
    var walkers: List[WalkerHandle]
    var next_check_index: Int

    def __init__(
        out self, world: World, resolution: Length = Length(2, METER)
    ) raises:
        """Build the mesh of the world's map and read its lights.

        Args:
            world: The world.
            resolution: The longest mesh strip along a lane.

        Raises:
            Error: If the resolution is not more than zero, or a map query
                fails.
        """
        self.nav = Navigation(build_navigation_mesh(world.map, resolution))
        self.manager = WalkerManager()
        self.walkers = List[WalkerHandle]()
        self.next_check_index = 0
        var lights = List[WalkerTrafficLight]()
        for light in world.filter_actors("traffic.traffic_light"):
            var state = world.get_traffic_light_state_of(light)
            for w in world.get_stop_waypoints(light):
                lights.append(
                    WalkerTrafficLight(
                        light, world.map.compute_transform(w).location, state
                    )
                )
        self.manager.set_traffic_lights(lights^)

    def register_walker(mut self, walker: ActorId, controller: ActorId):
        """Add a walker to the ones ticked, `RegisterWalker`.

        Args:
            walker: The walker.
            controller: Its controller.
        """
        self.walkers.append(WalkerHandle(walker, controller))

    def unregister_walker(mut self, walker: ActorId, controller: ActorId):
        """Drop a walker from the ones ticked, `UnregisterWalker`.

        Args:
            walker: The walker.
            controller: Its controller.
        """
        for i in range(len(self.walkers)):
            if self.walkers[i] == WalkerHandle(walker, controller):
                _ = self.walkers.pop(i)
                return

    def add_walker(mut self, walker: ActorId, location: Vector3) raises -> Bool:
        """Put a walker in the crowd, `AddWalker`.

        Args:
            walker: The walker.
            location: Its center.

        Returns:
            `Navigation.add_walker`.

        Raises:
            Error: If a mesh query fails.
        """
        return self.nav.add_walker(self.manager, walker, location)

    def remove_walker(mut self, walker: ActorId) raises -> Bool:
        """Take a walker out of the crowd, `RemoveWalker`.

        Args:
            walker: The walker.

        Returns:
            `Navigation.remove_agent`.

        Raises:
            Error: Never in practice.
        """
        return self.nav.remove_agent(self.manager, walker)

    def get_random_location(mut self) -> Optional[Vector3]:
        """Return a random point of a sidewalk, `GetRandomLocation`.

        Returns:
            The point, or None.
        """
        return self.nav.get_random_location()

    def set_walker_target(
        mut self, walker: ActorId, to: Vector3
    ) raises -> Bool:
        """Send a walker along a route, `SetWalkerTarget`.

        Args:
            walker: The walker.
            to: The goal.

        Returns:
            `Navigation.set_walker_target`.

        Raises:
            Error: If a mesh query fails.
        """
        return self.nav.set_walker_target(self.manager, walker, to)

    def set_walker_max_speed(
        mut self, walker: ActorId, speed: Velocity
    ) -> Bool:
        """Change a walker's top speed, `SetWalkerMaxSpeed`.

        Args:
            walker: The walker.
            speed: The top speed.

        Returns:
            `Navigation.set_walker_max_speed`.
        """
        return self.nav.set_walker_max_speed(walker, speed)

    def set_pedestrians_cross_factor(mut self, percentage: Float32):
        """Set the chance that a new walker crosses roads anywhere,
        `SetPedestriansCrossFactor`.

        Args:
            percentage: From 0 to 1.
        """
        self.nav.set_pedestrians_cross_factor(percentage)

    def set_pedestrians_seed(mut self, seed: Int):
        """Seed the walkers' random numbers, `SetPedestriansSeed`.

        Args:
            seed: The seed.
        """
        self.nav.set_seed(seed)

    def _check_if_walker_exists(mut self, mut world: World) raises:
        if self.next_check_index >= len(self.walkers):
            self.next_check_index = 0
        var handle = self.walkers[self.next_check_index]
        if not world.is_alive(handle.walker):
            _ = self.nav.remove_agent(self.manager, handle.walker)
            if world.is_alive(handle.controller):
                _ = world.destroy_actor(handle.controller)
            self.unregister_walker(handle.walker, handle.controller)
        self.next_check_index += 1

    def _update_vehicles(mut self, world: World) raises:
        var vehicles = List[VehicleCollisionInfo]()
        for v in world.filter_actors("vehicle.*"):
            vehicles.append(
                VehicleCollisionInfo(
                    v, world.get_transform(v), world.get_bounding_box(v)
                )
            )
        _ = self.nav.update_vehicles(self.manager, vehicles)

    def tick(mut self, mut world: World) raises:
        """Move the AI walkers one step, `Tick`.

        Args:
            world: The world, just ticked.

        Raises:
            Error: If a world or mesh query fails.
        """
        if len(self.walkers) == 0:
            return
        self._check_if_walker_exists(world)
        self._update_vehicles(world)
        for light in self.manager.traffic_lights.copy():
            self.manager.set_light_state(
                light.actor, world.get_traffic_light_state_of(light.actor)
            )
        var delta = world.settings.fixed_delta_seconds.value()
        self.nav.update_crowd(self.manager, delta)
        for handle in self.walkers.copy():
            var pose = self.nav.get_walker_transform(handle.walker)
            if not Bool(pose):
                continue
            var t = pose.value()
            t.location.z += world.get_bounding_box(handle.walker).extent.z
            var velocity = self.nav.get_walker_velocity(handle.walker)
            world.set_transform(handle.walker, t)
            world.set_target_velocity(handle.walker, velocity)
            var control = WalkerControl()
            var speed = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
            if speed > 0:
                control.direction = Vector3(
                    velocity.x / speed, velocity.y / speed, 0
                )
            control.speed = Velocity(speed)
            world.apply_walker_control(handle.walker, control)


@fieldwise_init
struct WalkerAIController(ImplicitlyCopyable):
    """The actor of `controller.ai.walker`, `WalkerAIController`."""

    var id: ActorId

    def _parent(self, world: World) raises -> ActorId:
        return world.actor(self.id).parent

    def start(self, mut world: World, mut navigation: WalkerNavigation) raises:
        """Put the parent walker in the crowd, `Start`.

        Args:
            world: The world.
            navigation: The walker navigation.

        Raises:
            Error: If the controller is gone or has no parent walker.
        """
        var walker = self._parent(world)
        if walker == NO_ACTOR:
            raise Error("The controller is not attached to a walker")
        navigation.register_walker(walker, self.id)
        _ = navigation.add_walker(walker, world.get_location(walker))
        world.set_enable_gravity(walker, False)

    def stop(self, world: World, mut navigation: WalkerNavigation) raises:
        """Take the parent walker out of the crowd, `Stop`.

        Args:
            world: The world.
            navigation: The walker navigation.

        Raises:
            Error: If the controller is gone.
        """
        var walker = self._parent(world)
        navigation.unregister_walker(walker, self.id)
        _ = navigation.remove_walker(walker)

    def get_random_location(
        self, mut navigation: WalkerNavigation
    ) -> Optional[Vector3]:
        """Return a random point of a sidewalk, `GetRandomLocation`.

        Args:
            navigation: The walker navigation.

        Returns:
            The point, or None.
        """
        return navigation.get_random_location()

    def go_to_location(
        self,
        world: World,
        mut navigation: WalkerNavigation,
        destination: Vector3,
    ) raises -> Bool:
        """Send the parent walker along a route, `GoToLocation`.

        Args:
            world: The world.
            navigation: The walker navigation.
            destination: The goal.

        Returns:
            False where CARLA logs a warning: the walker is not in the
            crowd.

        Raises:
            Error: If the controller is gone.
        """
        return navigation.set_walker_target(self._parent(world), destination)

    def set_max_speed(
        self, world: World, mut navigation: WalkerNavigation, speed: Velocity
    ) raises -> Bool:
        """Change the parent walker's top speed, `SetMaxSpeed`.

        Args:
            world: The world.
            navigation: The walker navigation.
            speed: The top speed.

        Returns:
            False where CARLA logs a warning: the walker is not in the
            crowd.

        Raises:
            Error: If the controller is gone.
        """
        return navigation.set_walker_max_speed(self._parent(world), speed)

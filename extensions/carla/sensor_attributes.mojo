# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""How a CARLA sensor reads its settings from its actor's attributes.

A sensor reads each setting with `RetrieveActorAttributeTo*` of CARLA's
simulator plugin, `Carla/Actor/ActorBlueprintFunctionLibrary.cpp`. A
missing attribute, or one of another type, gives the default that the
sensor passes. A number reads as C's `atoi` and `atof` read it, with
`extensions.carla.blueprint.read_int` and `read_float`. A bool is true
for "true" in any case and false for any other text. Physical float
settings must be finite after conversion to Float32; this check is an
intentional difference from CARLA's permissive number reader.
"""

from std.math import isfinite

from extensions.carla.blueprint import (
    ATTRIBUTE_BOOL,
    ATTRIBUTE_FLOAT,
    ATTRIBUTE_INT,
    ATTRIBUTE_STRING,
    ActorAttributeType,
    ActorAttributeValue,
    read_float,
    read_int,
)


def validate_sensor_float(value: Float32, name: String) raises:
    """Require a physical setting to be finite after Float32 conversion.

    Args:
        value: The setting in the sensor's arithmetic type.
        name: The setting's name for an error.

    Raises:
        Error: If the value is NaN or infinite.
    """
    if not isfinite(value):
        raise Error(name + " must be finite in Float32")


def validate_sensor_nonnegative(value: Float32, name: String) raises:
    """Require a finite, nonnegative physical setting.

    Args:
        value: The setting in the sensor's arithmetic type.
        name: The setting's name for an error.

    Raises:
        Error: If the value is nonfinite or negative.
    """
    validate_sensor_float(value, name)
    if value < 0:
        raise Error(name + " cannot be negative")


def validate_sensor_positive(value: Float32, name: String) raises:
    """Require a finite, positive physical setting.

    Args:
        value: The setting in the sensor's arithmetic type.
        name: The setting's name for an error.

    Raises:
        Error: If the value is nonfinite or not positive.
    """
    validate_sensor_float(value, name)
    if value <= 0:
        raise Error(name + " must be positive")


def _find(
    attributes: List[ActorAttributeValue], id: String, type: ActorAttributeType
) -> Optional[String]:
    for a in attributes:
        if a.id == id:
            if a.type != type:
                return None
            return a.value
    return None


def attribute_float(
    attributes: List[ActorAttributeValue], id: String, default: Float32
) raises -> Float32:
    """Read a float setting, `RetrieveActorAttributeToFloat`.

    Args:
        attributes: The actor's attributes.
        id: The attribute's id.
        default: What a missing or mistyped attribute gives.

    Returns:
        The value as `atof` reads it, rounded to a `Float32`.

    Raises:
        Error: If the selected value is not finite in Float32.
    """
    var text = _find(attributes, id, ATTRIBUTE_FLOAT)
    var value = default
    if Bool(text):
        value = Float32(read_float(text.value()))
    validate_sensor_float(value, id)
    return value


def attribute_int(
    attributes: List[ActorAttributeValue], id: String, default: Int
) -> Int:
    """Read an integer setting, `RetrieveActorAttributeToInt`.

    Args:
        attributes: The actor's attributes.
        id: The attribute's id.
        default: What a missing or mistyped attribute gives.

    Returns:
        The value as `atoi` reads it.
    """
    var text = _find(attributes, id, ATTRIBUTE_INT)
    if not Bool(text):
        return default
    return read_int(text.value())


def attribute_bool(
    attributes: List[ActorAttributeValue], id: String, default: Bool
) -> Bool:
    """Read a bool setting, `RetrieveActorAttributeToBool`.

    Args:
        attributes: The actor's attributes.
        id: The attribute's id.
        default: What a missing or mistyped attribute gives.

    Returns:
        Whether the text is "true" in any case.
    """
    var text = _find(attributes, id, ATTRIBUTE_BOOL)
    if not Bool(text):
        return default
    return text.value().lower() == "true"


def attribute_string(
    attributes: List[ActorAttributeValue], id: String, default: String
) -> String:
    """Read a text setting, `RetrieveActorAttributeToString`.

    Args:
        attributes: The actor's attributes.
        id: The attribute's id.
        default: What a missing or mistyped attribute gives.

    Returns:
        The text.
    """
    var text = _find(attributes, id, ATTRIBUTE_STRING)
    if not Bool(text):
        return default
    return text.value()

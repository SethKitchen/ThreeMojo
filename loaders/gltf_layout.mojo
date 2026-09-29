# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0

"""Checked byte layouts shared by ordinary and Gaussian splat glTF accessors.

Decoding stays with each loader: Float64 splats, exact integer attributes,
and normalized Float32 attributes must not pass through one lossy type.
"""


def check_buffer_range(size: Int, offset: Int, length: Int) raises:
    """Check a byte range without adding untrusted integers.

    Args:
        size: The available bytes.
        offset: The first byte.
        length: The byte count.

    Raises:
        Error: If the range is negative or outside the buffer.
    """
    if offset < 0 or offset > size or length < 0 or length > size - offset:
        raise Error("glTF: a buffer view runs past its buffer")


struct AccessorLayout(ImplicitlyCopyable):
    """An accessor's packed element, including matrix column padding."""

    var width: Int
    var size: Int
    var rows: Int
    var column_stride: Int
    var element_size: Int
    var occupied_size: Int
    var alignment: Int

    def __init__(out self, kind: String, size: Int) raises:
        """Describe scalar, vector, or matrix elements.

        Args:
            kind: The glTF accessor type.
            size: Bytes per component: one, two, or four.

        Raises:
            Error: If the type or component size is unknown.
        """
        if size != 1 and size != 2 and size != 4:
            raise Error("glTF: an invalid component size")
        var rows: Int
        var columns = 1
        if kind == "SCALAR":
            rows = 1
        elif kind == "VEC2":
            rows = 2
        elif kind == "VEC3":
            rows = 3
        elif kind == "VEC4":
            rows = 4
        elif kind == "MAT2":
            rows = 2
            columns = 2
        elif kind == "MAT3":
            rows = 3
            columns = 3
        elif kind == "MAT4":
            rows = 4
            columns = 4
        else:
            raise Error("glTF: an accessor type that is not known: " + kind)
        self.width = rows * columns
        self.size = size
        self.rows = rows
        self.column_stride = rows * size
        if columns > 1:
            self.column_stride = ((self.column_stride + 3) // 4) * 4
        self.element_size = columns * self.column_stride
        self.occupied_size = (columns - 1) * self.column_stride + rows * size
        self.alignment = 4 if columns > 1 else size

    def offsets(self) -> List[Int]:
        """Return each component's byte offset in an element."""
        var out = List[Int](capacity=self.width)
        for lane in range(self.width):
            out.append(
                (lane // self.rows) * self.column_stride
                + (lane % self.rows) * self.size
            )
        return out^

    def check(self, count: Int, offset: Int) raises:
        """Check metadata before allocation, including an implicit zero array.

        Args:
            count: The element count.
            offset: The accessor byte offset.

        Raises:
            Error: If count, alignment, or output size is invalid.
        """
        if count < 0 or count > 9223372036854775807 // self.width:
            raise Error("glTF: an accessor's count is invalid")
        if offset < 0 or offset % self.size != 0:
            raise Error(
                "glTF: an accessor needs a nonnegative aligned byteOffset"
            )

    def span(
        self,
        count: Int,
        offset: Int,
        view_offset: Int,
        length: Int,
        var stride: Int,
        explicit_stride: Bool,
    ) raises -> Tuple[Int, Int]:
        """Check an accessor in an already checked buffer view.

        Args:
            count: Number of elements.
            offset: Offset relative to the view.
            view_offset: The view's first byte in its buffer.
            length: The view's byte length.
            stride: The view's byte stride.
            explicit_stride: Whether byteStride was supplied.

        Returns:
            The absolute first byte and element stride.

        Raises:
            Error: If the accessor is misaligned or outside its view.
        """
        self.check(count, offset)
        if offset > length or (view_offset + offset) % self.alignment != 0:
            raise Error(
                "glTF: an accessor runs past its buffer view or is misaligned"
            )
        if explicit_stride:
            if stride < self.element_size or stride % 4 != 0 or stride > 252:
                raise Error("glTF: an accessor has an invalid byteStride")
        else:
            stride = self.element_size
        var available = length - offset
        if count > 0:
            if self.occupied_size > available:
                raise Error("glTF: an accessor runs past its buffer view")
            if count - 1 > (available - self.occupied_size) // stride:
                raise Error("glTF: an accessor runs past its buffer view")
        return (view_offset + offset, stride)

# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A seen-set for coverage probes, kept in a caller-supplied byte block.

A probe used to write a record for every execution. A statement in a loop
then wrote millions of copies of one line, and the report threw them away.
The block remembers each line and each distinct decision vector, so the
caller writes a record only the first time.

Mojo has no mutable globals. The coverage run keeps the block in
`coverage/state.c` and passes its address here. A test passes its own block.
The bytes start at zero. The first call writes a magic and from then on
reads what earlier calls stored.

A condition waits until its decision closes. A decision inside that
condition closes first and takes only its own suffix, so the outer
conditions stay on the stack.
"""

# The block outlives every probe. The compiler does not track that.
comptime BlockOrigin = UntrackedOrigin[mut=True]
comptime _MAGIC = UInt64(0xC0FFEE01)
comptime _FNV_OFFSET = UInt64(0xCBF29CE484222325)
comptime _FNV_PRIME = UInt64(0x100000001B3)
comptime _SLOT_COUNT = 1 << 18
comptime _SLOT_BYTES = 16
comptime _HEADER = 40
comptime _SLOT_START = _HEADER
comptime _SLOT_END = _SLOT_START + _SLOT_COUNT * _SLOT_BYTES
comptime _PENDING_MAX = 64
comptime _PENDING_TEXT = 192
comptime _PENDING_META = _SLOT_END
comptime _PENDING_TEXT_AT = _PENDING_META + _PENDING_MAX * 16
comptime _ARENA = _PENDING_TEXT_AT + _PENDING_MAX * _PENDING_TEXT
comptime _ARENA_BYTES = 4 * 1024 * 1024
# A decision's key is built here, then hashed. It does not persist.
comptime _SCRATCH_BYTES = 4096
comptime _SCRATCH = _ARENA + _ARENA_BYTES
# How many bytes a block must hold. `coverage/state.c` allocates more.
comptime DEDUP_BYTES = _SCRATCH + _SCRATCH_BYTES
comptime BRANCH_QUIET = 0
comptime BRANCH_PRINT_ONE = 1
comptime BRANCH_PRINT_VECTOR = 2


struct Dedup(Movable):
    """One seen-set in a zeroed block of at least `DEDUP_BYTES` bytes."""

    var base: Pointer[UInt8, BlockOrigin]

    def __init__(out self, base: Pointer[UInt8, BlockOrigin]):
        """Bind a zeroed block. The first probe initializes it.

        Args:
            base: The first byte. It must stay alive for every later call,
                and it must not alias another `Dedup`.

        """
        self.base = base

    def claim_line(
        mut self, text: Pointer[UInt8, BlockOrigin], count: Int
    ) -> Bool:
        """Return True if the line `text` has not been claimed yet.

        Args:
            text: The probe id's bytes.
            count: How many bytes `text` holds.

        Returns:
            True the first time this id is claimed, False after that.

        """
        self._ready()
        return self._claim(UInt8(0), text, count)

    def absorb_branch(
        mut self,
        text: Pointer[UInt8, BlockOrigin],
        count: Int,
        value: Bool,
    ) -> Int:
        """Record one branch probe and say what the caller should write.

        A condition id ends in `.<digits>`. It waits until the decision
        that owns it closes. That decision takes the waiting suffix whose
        ids belong to it and leaves any outer conditions in place.

        Args:
            text: The probe id's bytes.
            count: How many bytes `text` holds.
            value: Which way the decision or the condition went.

        Returns:
            `BRANCH_QUIET`, `BRANCH_PRINT_ONE`, or `BRANCH_PRINT_VECTOR`.
            After `BRANCH_PRINT_VECTOR`, print `vector_start` through
            `pending_count` and then call `drop_vector`.

        """
        self._ready()
        if _is_condition(text, count):
            return self._push_condition(text, count, value)
        var start = self._suffix_start(text, count)
        self._set_u64(24, UInt64(start))
        if self._u64(32) != 0 or self._vector_is_new(text, count, value, start):
            self._set_u64(32, 0)
            return BRANCH_PRINT_VECTOR
        self._set_pending(start)
        return BRANCH_QUIET

    def pending_count(self) -> Int:
        """Return how many conditions are waiting.

        Returns:
            The count, from zero up to the pending limit.

        """
        return Int(self._u64(16))

    def vector_start(self) -> Int:
        """Return the first waiting condition that belongs to the last decision.

        Returns:
            An index into the waiting list. Conditions before it belong to
            an outer decision and stay put.

        """
        return Int(self._u64(24))

    def pending_length(self, index: Int) -> Int:
        """Return the byte length of waiting condition `index`.

        Args:
            index: Its place in the waiting list, from zero.

        Returns:
            The length copied into the block.

        """
        return Int(self._u32(self._meta(index) + 8))

    def pending_value(self, index: Int) -> Bool:
        """Return which way waiting condition `index` went.

        Args:
            index: Its place in the waiting list, from zero.

        Returns:
            True or False.

        """
        return self._u32(self._meta(index) + 12) != 0

    def pending_text(self, index: Int) -> String:
        """Return the id of waiting condition `index`.

        Args:
            index: Its place in the waiting list, from zero.

        Returns:
            The id copied into the block.

        """
        return _string_at(
            self.base.unsafe_offset(self._text_at(index)),
            self.pending_length(index),
        )

    def drop_vector(mut self):
        """Drop the suffix `vector_start` names, and keep any outer conditions.
        """
        self._set_pending(self.vector_start())

    def _ready(mut self):
        if self._u64(0) != _MAGIC:
            self._set_u64(0, _MAGIC)
            self._set_u64(8, 0)
            self._set_u64(16, 0)
            self._set_u64(24, 0)
            self._set_u64(32, 0)

    def _push_condition(
        mut self,
        text: Pointer[UInt8, BlockOrigin],
        count: Int,
        value: Bool,
    ) -> Int:
        var n = self.pending_count()
        if n >= _PENDING_MAX or count > _PENDING_TEXT or count < 0:
            self._set_u64(32, 1)
            return BRANCH_PRINT_ONE
        _copy(self.base.unsafe_offset(self._text_at(n)), text, count)
        var meta = self._meta(n)
        self._set_u32(meta + 8, UInt32(count))
        var bit = UInt32(0)
        if value:
            bit = 1
        self._set_u32(meta + 12, bit)
        self._set_pending(n + 1)
        return BRANCH_QUIET

    def _suffix_start(
        self, text: Pointer[UInt8, BlockOrigin], count: Int
    ) -> Int:
        var start = self.pending_count()
        while start > 0:
            var prev = start - 1
            if not _belongs(
                self.base.unsafe_offset(self._text_at(prev)),
                self.pending_length(prev),
                text,
                count,
            ):
                return start
            start = prev
        return start

    def _vector_is_new(
        mut self,
        text: Pointer[UInt8, BlockOrigin],
        count: Int,
        value: Bool,
        start: Int,
    ) -> Bool:
        var raw = self.base.unsafe_offset(_SCRATCH)
        var size = _append(raw, 0, _SCRATCH_BYTES, text, count)
        var mark = UInt8(0)
        if value:
            mark = 1
        size = _append_byte(raw, size, _SCRATCH_BYTES, mark)
        var n = self.pending_count()
        for index in range(start, n):
            var bit = UInt8(0)
            if self.pending_value(index):
                bit = 1
            size = _append(
                raw,
                size,
                _SCRATCH_BYTES,
                self.base.unsafe_offset(self._text_at(index)),
                self.pending_length(index),
            )
            size = _append_byte(raw, size, _SCRATCH_BYTES, bit)
        if size < 0:
            return True
        return self._claim(UInt8(1), raw, size)

    def _claim(
        mut self,
        prefix: UInt8,
        text: Pointer[UInt8, BlockOrigin],
        count: Int,
    ) -> Bool:
        var hash = _hash_byte(_FNV_OFFSET, prefix)
        hash = _hash_bytes(hash, text, count)
        if hash == 0:
            hash = 1
        var mask = _SLOT_COUNT - 1
        var start = Int(hash & UInt64(mask))
        for step in range(64):
            var slot = (start + step) & mask
            var at = _SLOT_START + slot * _SLOT_BYTES
            var have = self._u64(at)
            if have == 0:
                return self._insert(at, hash, prefix, text, count)
            if have == hash and self._same(at, prefix, text, count):
                return False
        return True

    def _insert(
        mut self,
        at: Int,
        hash: UInt64,
        prefix: UInt8,
        text: Pointer[UInt8, BlockOrigin],
        count: Int,
    ) -> Bool:
        if count < 0:
            return True
        var bytes = count + 1
        var used = Int(self._u64(8))
        if used + bytes > _ARENA_BYTES:
            return True
        var dest = self.base.unsafe_offset(_ARENA + used)
        dest[] = prefix
        if count > 0:
            _copy(dest.unsafe_offset(1), text, count)
        self._set_u64(at, hash)
        self._set_u32(at + 8, UInt32(used))
        self._set_u32(at + 12, UInt32(bytes))
        self._set_u64(8, UInt64(used + bytes))
        return True

    def _same(
        self,
        at: Int,
        prefix: UInt8,
        text: Pointer[UInt8, BlockOrigin],
        count: Int,
    ) -> Bool:
        var stored = Int(self._u32(at + 12))
        if stored != count + 1 or count < 0:
            return False
        var off = _ARENA + Int(self._u32(at + 8))
        if self.base.unsafe_offset(off)[] != prefix:
            return False
        for index in range(count):
            if (
                self.base.unsafe_offset(off + 1 + index)[]
                != text.unsafe_offset(index)[]
            ):
                return False
        return True

    def _meta(self, index: Int) -> Int:
        return _PENDING_META + index * 16

    def _text_at(self, index: Int) -> Int:
        return _PENDING_TEXT_AT + index * _PENDING_TEXT

    def _set_pending(mut self, count: Int):
        self._set_u64(16, UInt64(count))

    def _u64(self, at: Int) -> UInt64:
        return self.base.unsafe_offset(at).unsafe_bitcast[UInt64]()[]

    def _set_u64(mut self, at: Int, value: UInt64):
        self.base.unsafe_offset(at).unsafe_bitcast[UInt64]()[] = value

    def _u32(self, at: Int) -> UInt32:
        return self.base.unsafe_offset(at).unsafe_bitcast[UInt32]()[]

    def _set_u32(mut self, at: Int, value: UInt32):
        self.base.unsafe_offset(at).unsafe_bitcast[UInt32]()[] = value


def _belongs(
    cond: Pointer[UInt8, BlockOrigin],
    cond_count: Int,
    decision: Pointer[UInt8, BlockOrigin],
    decision_count: Int,
) -> Bool:
    if decision_count < 0 or cond_count < decision_count + 2:
        return False
    for index in range(decision_count):
        if cond.unsafe_offset(index)[] != decision.unsafe_offset(index)[]:
            return False
    if cond.unsafe_offset(decision_count)[] != UInt8(ord(".")):
        return False
    for index in range(decision_count + 1, cond_count):
        var byte = cond.unsafe_offset(index)[]
        if byte < UInt8(ord("0")) or byte > UInt8(ord("9")):
            return False
    return True


def _is_condition(text: Pointer[UInt8, BlockOrigin], count: Int) -> Bool:
    var dot = -1
    for index in range(count):
        if text.unsafe_offset(index)[] == UInt8(ord(".")):
            dot = index
    if dot < 0 or dot + 1 >= count:
        return False
    for index in range(dot + 1, count):
        var byte = text.unsafe_offset(index)[]
        if byte < UInt8(ord("0")) or byte > UInt8(ord("9")):
            return False
    return True


def _hash_byte(hash: UInt64, byte: UInt8) -> UInt64:
    return (hash ^ UInt64(byte)) * _FNV_PRIME


def _hash_bytes(
    hash: UInt64, text: Pointer[UInt8, BlockOrigin], count: Int
) -> UInt64:
    var mixed = hash
    var n = count
    if n < 0:
        n = 0
    for index in range(n):
        mixed = _hash_byte(mixed, text.unsafe_offset(index)[])
    return mixed


def _append(
    dest: Pointer[UInt8, BlockOrigin],
    size: Int,
    limit: Int,
    text: Pointer[UInt8, BlockOrigin],
    count: Int,
) -> Int:
    if size < 0 or count < 0 or size + count > limit:
        return -1
    if count > 0:
        _copy(dest.unsafe_offset(size), text, count)
    return size + count


def _append_byte(
    dest: Pointer[UInt8, BlockOrigin],
    size: Int,
    limit: Int,
    byte: UInt8,
) -> Int:
    if size < 0 or size + 1 > limit:
        return -1
    dest.unsafe_offset(size)[] = byte
    return size + 1


def _copy(
    dest: Pointer[UInt8, BlockOrigin],
    src: Pointer[UInt8, BlockOrigin],
    count: Int,
):
    for index in range(count):
        dest.unsafe_offset(index)[] = src.unsafe_offset(index)[]


def _string_at(text: Pointer[UInt8, BlockOrigin], count: Int) -> String:
    var out = String()
    var n = count
    if n < 0:
        n = 0
    for index in range(n):
        out += String(chr(Int(text.unsafe_offset(index)[])))
    return out^

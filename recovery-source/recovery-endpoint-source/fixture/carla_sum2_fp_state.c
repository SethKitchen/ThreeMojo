/* Copyright (c) 2026 Seth Kitchen, PE
 * SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
 * Test-process-only CPU controls. Never link into production code.
 * Mode IDs: 0 nearest/gradual, 1 downward, 2 upward, 3 toward zero,
 * 4 flush-to-zero (x86 FTZ / Arm FZ), 5 input flush (x86 only),
 * 6 both (x86 only).
 */
#include <stdint.h>

#if defined(__x86_64__) || defined(_M_X64)
#include <xmmintrin.h>
int sum2_test_mode_count(void) { return 7; }
uint64_t sum2_test_get_state(void) { return (uint64_t)_mm_getcsr(); }
uint64_t sum2_test_control_mask(void) {
    return (3ull << 13) | (1ull << 15) | (1ull << 6);
}
uint64_t sum2_test_mode_bits(int mode) {
    if (mode >= 1 && mode <= 3) return (uint64_t)mode << 13;
    if (mode == 4) return 1ull << 15;
    if (mode == 5) return 1ull << 6;
    if (mode == 6) return (1ull << 15) | (1ull << 6);
    return 0;
}
void sum2_test_restore_mode(uint64_t saved) { _mm_setcsr((uint32_t)saved); }
#elif defined(__aarch64__) || defined(__arm64__)
/* AArch64 FPCR: RMode[23:22], FZ[24]. The standard FZ mode covers
 * input and output subnormals. We do not claim a separate DAZ test. */
int sum2_test_mode_count(void) { return 5; }
uint64_t sum2_test_get_state(void) {
    uint64_t control;
    __asm__ __volatile__("mrs %0, fpcr" : "=r"(control) : : "memory");
    return control;
}
uint64_t sum2_test_control_mask(void) { return (3ull << 22) | (1ull << 24); }
uint64_t sum2_test_mode_bits(int mode) {
    if (mode == 1) return 2ull << 22;
    if (mode == 2) return 1ull << 22;
    if (mode == 3) return 3ull << 22;
    if (mode == 4) return 1ull << 24;
    return 0;
}
void sum2_test_restore_mode(uint64_t saved) {
    __asm__ __volatile__("msr fpcr, %0\n\tisb" : : "r"(saved) : "memory");
}
#else
#error "Sum2 negative-state controls require a supported x86-64 or AArch64 CPU"
#endif

uint64_t sum2_test_set_mode(int mode) {
    uint64_t original = sum2_test_get_state();
    uint64_t changed = (original & ~sum2_test_control_mask()) | sum2_test_mode_bits(mode);
    sum2_test_restore_mode(changed);
    return original;
}

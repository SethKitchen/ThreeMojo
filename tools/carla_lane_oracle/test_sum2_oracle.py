"""Exact-rational oracle controls for the defined streaming Sum2 recurrence.

Self-contained fixed native words plus synthetic adversarial cases. This
checks the arithmetic oracle, not an arbitrary production implementation.
No bare asserts: all controls remain active with python -O.
"""
from fractions import Fraction as F
import math
import random
import struct
import unittest

U = F(1, 2**53)

def from_word(word):
    return struct.unpack('<d', struct.pack('<Q', word))[0]

def to_word(value):
    return struct.unpack('<Q', struct.pack('<d', value))[0]

def two_sum(a, b):
    value = a + b
    second = value - a
    first = value - second
    error = (a - first) + (b - second)
    return value, error

def sum2(values):
    total = 0.0
    residual_sum = 0.0
    for value in values:
        total, residual = two_sum(total, value)
        residual_sum += residual
    return total + residual_sum

# Original native export SHA256: cb667025b366d188531a99fba20d1262e509fa5b5a3214e597d53889ff756fe3
NATIVE_TERM_WORDS = (
    (0x3fbb7005e832d25a, 0x3e9031d46618f6d0),
    (0x3fcbb6cd63e3b454, 0x3ee8bda8e660bc28),
    (0x3fd0785f8190bc60, 0x3f1141a90477226a),
    (0x3fcbb6cd0f5c8b9d, 0x3f212e912ff19882),
    (0x3fbb7005215f1a3a, 0x3f1a1d1598b30a0a),
    (0x3fbb7004c6bed394, 0x3f1f81fe56cee2aa),
    (0x3fcbb6cb361cbfa1, 0x3f35fe1253f08960),
    (0x3fd0785cae5a8d66, 0x3f4369dd08df3aaa),
    (0x3fcbb6c413dae3c3, 0x3f46b90fee704f42),
    (0x3fbb6ff8360be2af, 0x3f3b6a262431017a),
    (0x3fbb6ff5623bcff1, 0x3f3e1c991f6f5ab7),
    (0x3fcbb6b5d96fda2d, 0x3f520fe9432b74e0),
    (0x3fd078497887fcf2, 0x3f5af68c10ac94f5),
    (0x3fcbb6957b7b279b, 0x3f5bd58dd8bb0754),
    (0x3fbb6fbe531a253a, 0x3f4f5642d6f3d883),
    (0x3fbb6fb4c9020695, 0x3f50ae0a4806763e),
    (0x3fcbb665d0309aca, 0x3f62f144896a3a58),
    (0x3fd0780ac17d7e0a, 0x3f6a6c5d7c1216e0),
    (0x3fcbb60d7fa732cd, 0x3f69c8508ee0e7b0),
    (0x3fbb6f200f3441a3, 0x3f5c137012d561ef),
    (0x3fbb6f0973550e6c, 0x3f5d6c9e7528c4d5),
    (0x3fcbb59cccaa6add, 0x3f703dbd19552d59),
    (0x3fd07777dc4e1834, 0x3f75d6b3853a02b8),
    (0x3fcbb4e18b28c290, 0x3f74a341e2d8ceae),
    (0x3fbb6dcf6d52b43c, 0x3f660984cd887a0f),
    (0x3fbb6da3462c6872, 0x3f66e1371f6a491c),
    (0x3fcbb405b48502d7, 0x3f78d306ac0be385),
    (0x3fd0765a9056e3d0, 0x3f804f671a14e7cb),
    (0x3fcbb2b03fbaf15b, 0x3f7e324b6bcd9581),
    (0x3fbb6b67e3290270, 0x3f6fd4860d85c921),
    (0x3fbb6b1b9a2153e9, 0x3f706ba260d5f89f),
    (0x3fcbb134a8d744d1, 0x3f819bfb61ffb1b8),
    (0x3fd0746f1f18a4e5, 0x3f86c6e025686abe),
    (0x3fcbaf0181e6d014, 0x3f84c844ed0cee32),
    (0x3fbb676e66679269, 0x3f75b4f775b0eca8),
    (0x3fbb66f54982e330, 0x3f764bd0581ca8ee),
    (0x3fcbaca7161957ae, 0x3f87b5cee3163ff7),
    (0x3fd071644f57e24f, 0x3f8e5121cd753164),
    (0x3fcba9468ed15ee3, 0x3f8b5e6257fd5491),
    (0x3fbb61518496f6ff, 0x3f7c643730b00e5a),
    (0x3fbb609cc9690ab6, 0x3f7d107595d4ffd2),
    (0x3fcba5c3d0009416, 0x3f8eb63d0132eb1f),
    (0x3fd06cdb800cfc33, 0x3f9376954b060d9f),
    (0x3fcba0da207a0513, 0x3f916d45d4411e4e),
    (0x3fbb58698a2794a7, 0x3f81fb7feea7fe12),
    (0x3fbb576852758e46, 0x3f825c42fc3c2258),
    (0x3fcb9bdb3e27bfcb, 0x3f934e116a79fc43),
    (0x3fd06668c62dafa1, 0x3f984cbddba3fcbe),
    (0x3fcb9500a5bf2024, 0x3f959daec3dfa9de),
    (0x3fbb4bf8be2442d7, 0x3f8635ecf677a37f),
    (0x3fbb4a981ec51db0, 0x3f86a13eb53a5622),
    (0x3fcb8e279f3af4b9, 0x3f97b2ef628609d0),
    (0x3fd05d9318d750d5, 0x3f9da9faf7f068f0),
    (0x3fcb84e89450caf0, 0x3f9a3f72845fde8d),
    (0x3fbb3b2bb8c60f82, 0x3f8ae05cdc7626d6),
    (0x3fbb3956c361f3fa, 0x3f8b562055677fb1),
    (0x3fcb7bcd692e9c92, 0x3f9c88982cd354f0),
    (0x3fd051d48fdba8c3, 0x3fa1c66c8aab9814),
    (0x3fcb6faadb867b77, 0x3f9f513ecf975c5c),
    (0x3fbb2519dbf05d56, 0x3f8ff96e98a68914),
    (0x3fbb22b9ac51a1cf, 0x3f903cbeaac76b3d),
    (0x3fcb63dbcdd1ba36, 0x3fa0e6c52893aec1),
    (0x3fd0429ab92846c1, 0x3fa4f9b58717f18c),
    (0x3fcb544b7fcfc788, 0x3fa268aaef0c971c),
    (0x3fbb08c5f55c5f1b, 0x3f92bfa9905f7c8b),
    (0x3fbb05c1c3166ae1, 0x3f9304bda9e26ca6),
    (0x3fcb454d6bca3c5b, 0x3fa3bfe7d5616375),
    (0x3fd02f4709ef49f7, 0x3fa86d9942f6f109),
    (0x3fcb31ba67300c33, 0x3fa55ebd0fd2ec03),
    (0x3fbae51f12edde77, 0x3f95b7dc86c0b1c3),
    (0x3fbae15c482e1e32, 0x3f9601ddca7d8727),
    (0x3fcb1f0934ba7287, 0x3fa6ce74378f3601),
    (0x3fd0172f70debf19, 0x3fac2083420038e2),
    (0x3fcb06d45fdb93f1, 0x3fa8896c3dded50d),
    (0x3fbab901924ce841, 0x3f98e3db6928dde6),
    (0x3fbab463e8b81dd1, 0x3f9932a28e165462),
    (0x3fcaefe391ec4d53, 0x3faa10da66bc9cd2),
    (0x3fcff33e1e1b8bbf, 0x3fb0083e1c198770),
    (0x3fcad2646a9e0a81, 0x3fabe6f8a077f6fa),
    (0x3fba8338756b275f, 0x3f9c41d9d77934c8),
    (0x3fba7da219f51012, 0x3f9c9536bff6db3d),
    (0x3fcab69fd1644aba, 0x3fad852ea9183d5a),
    (0x3fcfabae3b22ab7d, 0x3fb21d8dea0e4e72),
    (0x3fca932553278b5e, 0x3faf753ff9ad0983),
    (0x3fba427f060a44af, 0x3f9fcfa7c6a7d67c),
    (0x3fba3bd0c4be3907, 0x3fa013b02c5208cc),
    (0x3fca71f1e5a457ee, 0x3fb0948e90d689ec),
    (0x3fcf56200bc35b38, 0x3fb44ebcfb59d398),
    (0x3fca47c3a0b06826, 0x3fb198d88d82b255),
    (0x3fb9f582d2a37c8a, 0x3fa1c552822a3f5f),
    (0x3fb9ed9c4b599638, 0x3fa1f339fc967763),
    (0x3fca208082a72565, 0x3fb27cee8e005bde),
    (0x3fcef0f566b16274, 0x3fb69a0fc0d84c5a),
    (0x3fc9eedfe98bfea5, 0x3fb38c9f85ea500a),
    (0x3fb99ae60f2fc099, 0x3fa3b7da3a0d4aff),
    (0x3fb991a5f42a718e, 0x3fa3e7a41205abdd),
    (0x3fc9c0e7a2ae0f8b, 0x3fb47a120e2e1c07),
    (0x3fce7a8448272cfb, 0x3fb8fd7b76b673b6),
    (0x3fc987119437c53f, 0x3fb5942a0634b8e1),
    (0x3fb93142643a472f, 0x3fa5bd979962ff00),
)

class Sum2OracleTests(unittest.TestCase):
    def verify(self, values):
        exact = sum(map(F, values))
        magnitude = sum(abs(F(x)) for x in values)
        n = len(values)
        gamma = (n - 1) * U / (1 - (n - 1) * U)
        result = sum2(values)
        self.assertLessEqual(abs(F(result) - exact), U * abs(exact) + gamma * gamma * magnitude)
        running = 0.0
        for value in values:
            total, residual = two_sum(running, value)
            self.assertEqual(F(total) + F(residual), F(running) + F(value))
            running = total
        return result

    def test_cancellation_and_zero_initialization(self):
        for values in ([1., 1e-16, -1.], [1e100, 1., -1e100], [1., -1., -0., 0.],
                       [1., 2**-53, 2**-106, -2**-53, -2**-106, -1.], [-0.], [0.]):
            with self.subTest(values=values):
                self.verify(values)
        self.assertEqual(to_word(sum2([-0.])), 0)
        self.assertEqual(to_word(sum2([0.])), 0)

    def test_gradual_underflow(self):
        eta = from_word(1)
        for values in ([eta]*100, [math.ldexp(1., -1022), eta, -math.ldexp(1., -1022)],
                       [eta, eta, -eta, -eta], [-eta, -eta, eta]):
            with self.subTest(values=values):
                self.verify(values)
        self.assertEqual(to_word(sum2([math.ldexp(1., -1022), eta, -math.ldexp(1., -1022)])), 1)

    def test_product_materialization_fixture(self):
        a, b = 1. + 2**-27, 1. - 2**-27
        product = a * b
        self.assertEqual(to_word(product), to_word(1.))
        self.assertEqual(sum2([-1., product]), 0.)
        fused_result = float(F(a) * F(b) - 1)
        self.assertEqual(fused_result, -2**-54)
        self.assertNotEqual(fused_result, sum2([-1., product]))

    def test_uniform_theorem_over_mixed_exponents(self):
        rng = random.Random(594)
        for case in range(100):
            with self.subTest(case=case):
                self.verify([math.ldexp(rng.uniform(-1., 1.), rng.randrange(-400, 401))
                             for _ in range(rng.randrange(2, 200))])

    def test_fixed_native_term_words(self):
        self.assertEqual(len(NATIVE_TERM_WORDS), 100)
        for axis in (0, 1):
            values = [from_word(row[axis]) for row in NATIVE_TERM_WORDS]
            result = self.verify(values)
            self.assertEqual(result, float(sum(map(F, values))))
            self.assertEqual(to_word(result), (0x4031cb40ccbdaaf6, 0x40038371a9a609ec)[axis])

if __name__ == '__main__':
    unittest.main()

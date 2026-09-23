# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tests for `render.bptc`: BC7 and BC6H blocks against worked-out texels
and against reference decoders.

The hand-built blocks are written bit by bit here, and their texels are
worked out in the comments. The reference vectors are blocks of every
mode, each with the texels an independent decoder gives for it: the BC7
decoder of `texture2ddecoder`, which agrees with `bcdec`, and the BC6H
decoder of `bcdec`, as `imagecodecs` wraps it. A BC7 vector is the block's
sixteen bytes and then sixty-four RGBA bytes, in hex. A BC6H vector is
`0` or `1` for unsigned or signed, the block, and then forty-eight halves
of RGB.
"""

from render.bptc import (
    BptcTables,
    bc6h_block,
    bc6h_finish,
    bc6h_unquantize,
    bc7_block,
)
from render.compressed_texture import (
    RGB_BPTC_SIGNED_FORMAT,
    RGB_BPTC_UNSIGNED_FORMAT,
    RGBA_BPTC_FORMAT,
    compressed_texture,
    decode_compressed,
)
from render.exr import half_to_float
from render.srgb import LINEAR, SRGB
from render.texture import FLOAT_TYPE
from std.testing import TestSuite, assert_equal, assert_raises, assert_true


def hex_value(text: String, at: Int, digits: Int) raises -> Int:
    """Return `digits` hex digits of `text` from `at` as a number."""
    var value = 0
    var bytes = text.as_bytes()
    for index in range(digits):
        var c = Int(bytes[at + index])
        var digit = c - 48
        if c >= 97:
            digit = c - 87
        value = value * 16 + digit
    return value


def hex_bytes(text: String, at: Int, count: Int) raises -> List[UInt8]:
    """Return `count` bytes spelled in hex in `text` from digit `at`."""
    var out = List[UInt8]()
    for index in range(count):
        out.append(UInt8(hex_value(text, at + index * 2, 2)))
    return out^


struct Bits(Movable):
    """A block written from its lowest bit up."""

    var bits: List[Int]

    def __init__(out self):
        self.bits = List[Int]()

    def put(mut self, value: Int, count: Int):
        """Append `count` bits of `value`, low first."""
        for bit in range(count):
            self.bits.append((value >> bit) & 1)

    def block(self) -> List[UInt8]:
        """Return the bits as sixteen bytes, zero past what was put."""
        var out = List[UInt8](length=16, fill=0)
        for index in range(len(self.bits)):
            out[index >> 3] |= UInt8(self.bits[index] << (index & 7))
        return out^


def test_bc7_vectors_match_the_reference_decoder() raises:
    var tables = BptcTables()
    var vectors = bc7_vectors()
    for vector in range(len(vectors)):
        var block = hex_bytes(vectors[vector], 0, 16)
        var expected = hex_bytes(vectors[vector], 32, 64)
        var texels = bc7_block(block, 0, tables)
        for index in range(64):
            assert_equal(texels[index], expected[index])


def test_a_hand_built_bc7_mode_6_block() raises:
    # Mode 6 is one subset of RGBA, seven bits and a parity bit per
    # endpoint, and four-bit indices.
    var bits = Bits()
    bits.put(0x40, 7)  # six zeros and a one: mode 6
    bits.put(0, 7)  # red 0
    bits.put(127, 7)  # red 1
    bits.put(127, 7)  # green 0
    bits.put(0, 7)  # green 1
    bits.put(0, 7)  # blue 0
    bits.put(0, 7)  # blue 1
    bits.put(127, 7)  # alpha 0
    bits.put(127, 7)  # alpha 1
    bits.put(0, 1)  # the first endpoint's parity bit
    bits.put(1, 1)  # the second's
    bits.put(0, 3)  # texel 0, the anchor, one bit short
    bits.put(15, 4)  # texel 1: all of endpoint 1
    bits.put(8, 4)  # texel 2: weight 34 of 64
    var texels = bc7_block(bits.block(), 0, BptcTables())
    # Endpoint 0 is (0, 254, 0, 254) and endpoint 1 (255, 1, 1, 255).
    var expected: List[Int] = [
        0, 254, 0, 254,
        255, 1, 1, 255,
        # (30 * 0 + 34 * 255 + 32) >> 6, and so on.
        135, 120, 1, 255,
        0, 254, 0, 254,
    ]  # fmt: skip
    for index in range(16):
        assert_equal(Int(texels[index]), expected[index])


def test_a_bc7_block_that_names_no_mode_is_transparent_black() raises:
    var block = List[UInt8](length=16, fill=0xFF)
    block[0] = 0
    var texels = bc7_block(block, 0, BptcTables())
    for index in range(64):
        assert_equal(texels[index], UInt8(0))


def test_bc6h_vectors_match_the_reference_decoder() raises:
    var tables = BptcTables()
    var vectors = bc6h_vectors()
    for vector in range(len(vectors)):
        var signed = hex_value(vectors[vector], 0, 1) == 1
        var block = hex_bytes(vectors[vector], 1, 16)
        var texels = bc6h_block(block, 0, signed, tables)
        for texel in range(16):
            for channel in range(3):
                var half = hex_value(
                    vectors[vector], 33 + (texel * 3 + channel) * 4, 4
                )
                assert_equal(
                    texels[texel * 4 + channel], half_to_float(UInt16(half))
                )
            assert_equal(texels[texel * 4 + 3], Float32(1))


def mode_3_block(
    first: List[Int], second: List[Int], indices: List[Int]
) -> List[UInt8]:
    """Return a BC6H mode 3 block: two ten-bit endpoints stored whole, and
    four-bit indices for the first texels."""
    var bits = Bits()
    bits.put(3, 5)
    for channel in range(3):
        bits.put(first[channel], 10)
    for channel in range(3):
        bits.put(second[channel], 10)
    bits.put(indices[0], 3)
    for index in range(1, len(indices)):
        bits.put(indices[index], 4)
    return bits.block()


def test_a_hand_built_unsigned_bc6h_block() raises:
    # Endpoint 0 is black. Endpoint 1 has the largest red and green,
    # which unquantize to 0xFFFF and scale to the largest half, and a
    # blue of 512.
    var block = mode_3_block([0, 0, 0], [1023, 1023, 512], [0, 15])
    var texels = bc6h_block(block, 0, False, BptcTables())
    assert_equal(texels[0], Float32(0))
    assert_equal(texels[4], Float32(65504))
    assert_equal(texels[5], Float32(65504))
    # 512 unquantizes to ((512 << 16) + 0x8000) >> 10 = 32800, and
    # 32800 * 31 >> 6 is the half 0x3E0F, 1 + 527/1024.
    assert_equal(texels[6], Float32(1.5146484375))
    assert_equal(texels[7], Float32(1))


def test_a_hand_built_signed_bc6h_block() raises:
    # A red of -511, ten-bit two's complement 0x201, is the most negative
    # there is: it unquantizes to -32767 and scales to -65504.
    var block = mode_3_block([0x201, 0, 0], [0, 0, 0], [0, 15, 8])
    var texels = bc6h_block(block, 0, True, BptcTables())
    assert_equal(texels[0], Float32(-65504))
    assert_equal(texels[4], Float32(0))
    # Weight 34: (30 * -32767 + 32) >> 6 = -15360, which scales to
    # -(15360 * 31 >> 5) = -14880, the half 0xBA20.
    assert_equal(texels[8], Float32(-0.765625))


def test_bc6h_reserved_modes_decode_to_opaque_black() raises:
    var tables = BptcTables()
    for mode in [19, 23, 27, 31]:
        var block = List[UInt8](length=16, fill=0xFF)
        block[0] = UInt8(0xE0 | mode)
        var texels = bc6h_block(block, 0, False, tables)
        for texel in range(16):
            assert_equal(texels[texel * 4], Float32(0))
            assert_equal(texels[texel * 4 + 3], Float32(1))


def test_bc6h_unquantize_follows_the_specification() raises:
    # Unsigned: sixteen bits pass, zero stays, the top becomes 0xFFFF.
    assert_equal(bc6h_unquantize(40000, 16, False), 40000)
    assert_equal(bc6h_unquantize(0, 10, False), 0)
    assert_equal(bc6h_unquantize(1023, 10, False), 0xFFFF)
    assert_equal(bc6h_unquantize(1, 10, False), 96)
    # Signed: the magnitude scales, and the sign comes back.
    assert_equal(bc6h_unquantize(-20000, 16, True), -20000)
    assert_equal(bc6h_unquantize(0, 10, True), 0)
    assert_equal(bc6h_unquantize(511, 10, True), 0x7FFF)
    assert_equal(bc6h_unquantize(-1, 10, True), -96)
    assert_equal(bc6h_unquantize(1, 10, True), 96)
    assert_equal(bc6h_finish(0xFFFF, False), Float32(65504))
    assert_equal(bc6h_finish(-0x7FFF, True), Float32(-65504))
    assert_equal(bc6h_finish(0x7FFF, True), Float32(65504))


def test_bptc_formats_decode_through_compressed_texture() raises:
    # A BC7 texture is sRGB bytes by default; a BC6H one is floats.
    var bits = Bits()
    bits.put(0x40, 7)
    var bc7 = compressed_texture(4, 4, bits.block(), RGBA_BPTC_FORMAT)
    assert_equal(bc7.color_space, SRGB)
    var block = mode_3_block([0, 0, 0], [1023, 1023, 512], [15, 15])
    var decoded = decode_compressed(4, 4, block, RGB_BPTC_UNSIGNED_FORMAT)
    assert_equal(decoded.texel_type, FLOAT_TYPE)
    assert_equal(decoded.floats[4], Float32(65504))
    var hdr = compressed_texture(4, 4, block, RGB_BPTC_SIGNED_FORMAT)
    assert_equal(hdr.texel_type, FLOAT_TYPE)
    assert_equal(hdr.color_space, LINEAR)
    with assert_raises(contains="holds data"):
        _ = compressed_texture(
            4, 4, block, RGB_BPTC_UNSIGNED_FORMAT, color_space=SRGB
        )


def bc7_vectors() -> List[String]:
    """Return the reference vectors; see the module docstring."""
    return [
        "515fc5821664490463c7e51f599098f7a54221ffffbd29ffffbd29ffcb7624ffd98926ffd98926ffe69a27ffa54221ffad088cff9a0d7cff9a0d7cff3c2428ff38776dff184a39ff23594aff438881ff",
        "19b52b38b2b08daeb8f771fa7dbf33f2953d58ffa66f8bffb9687bffc663b5ffad9c7bff6d85beffa66f8bff9383beffad9c7bffa66f8bff5a8cceff7994c3ff912b51ffb9687bff6d85beff5da5c8ff",
        "3a8b0db92ae773ba97c9bc34a46fd0bd7591b9ff7591b9ff44a1d9ffa88098ff51e672ff86aa9eff86aa9effa883bbffb970c9ffa883bbff40f964ff86aa9effa883bbff9797adffb970c9ff62d280ff",
        "be1002bbe3c47f436fa416d127c6102a3c842dff3c842dff377b4eff2e6793ff2555d4ffbb7ea7ffc3f31aff3c842dff2555d4ffc3f31affc0c255ff408d0cff3c842dff2e6793ff377b4eff3c842dff",
        "14e8c9995f1fc78afcfd9f6034f4289ea5f77bff398cffffa5f77bffa5f77bffd9aa87ff398cffff398cffffce18ffffe78c84ffd9aa87ffce2ec4ffce18ffffbde78cffbde78cffce18ffffce2ec4ff",
        "f4f87ecc5607f4ba2b74e04802006f26e77308ffe77308ff7bd600ff7bd600ffe77308ff7bd600ffb5bd21ffad5a4affde00efff6b834dffb29d2effb5bd21ffde00efffe77308ff73ad26ff7bd600ff",
        "58c0f91374899131ce6ea013d483d17ee83a69fff0286bff986e49ffd08c4effe83a69ff263240ff263240ffd08c4effe04a66ff986e49ff986e49ff5e5045ffd08c4effd08c4effd08c4eff263240ff",
        "18c123ea68836462d1752447fcf9cf5da22ac3ffa2581cffc4503affa2581cffa22ac3ff61399aff224874ffa2581cff224874ff224874ffe11be9ff224874ffa22ac3ff224874ffa22ac3ffa22ac3ff",
        "b02042c6c813b4b4dc0f4d09c919345f2a7b5027167f5a142a6c34652a713d5116846300167b50272a7b50272a682a78167f5a140476473b16846300047b50270476473b2a682a783c63218c167b5027",
        "70c823744327f26bff802781a50f018442427ebdbc428143f7428108f74275087d4275827d427e82f7427808bc428443f7428a08f7427808f74281087d427582424275bd424275bd424278bdf7428108",
        "604370363b050b60ab94e63933715fe548b3a78702b3b09ad8b3b09a02b3b09a48b3b8ae02b3b8aed8b3a78748b3b09ad8b3c1c1d8b3a78748b3c1c148b3c1c148b3a78748b3c1c192b3b09ad8b3b8ae",
        "a01eb745b37a519af286cbadce96a0e13c9a562ca8a65b31dd945e3471a6592fdda05e343c9a562c3c9a562cdda05e347194592f7194592fa8a05b31dda05e34a89a5b317194592f71a0592f71a6592f",
        "40c9f251976a7f3aad08c6ba28962eb75371ab7a71a8af78618bad79241ea47e5371ab7a80c1b27771a8af7878b5b077618bad79343ba67d5371ab7a6898ae7990deb476343ba67d5a7eac7a78b5b077",
        "40e42215b3b225859ed69e60bfe0cad2575ac118485cc7155f59be1a2760d20e1e61d50c485cc7159153ad255f59be1a1662d80a375ecd119153ad251e61d50c3e5dca132f5fcf0f8055b3212760d20e",
        "80902f79e63ea09a804bde17d0c19719f3cb51926be182c86be182c828eb9ae3cb1800ebf3cb51926be182c828eb9ae39a82e359aa5f9989cb1800eb28eb9ae3cb1800eb9a82e359cb1800ebcb1800eb",
        "808735ef0efe0b490588ad9c211cb1adb2182010b2182010895c2f54b21820105da33e9b34e74ddfb2182010a66f0e68b21820105da33e9b91b81e5eba2800715da33e9b91b81e5e91b81e5e91b81e5e",
        "101b32edf5985eb91901a692a89bf2abc089ec9884d6d69ca2b0e195a2b0e191de63f79184d6d691c089ec9584d6d69fde63f79884d6d698de63f795a2b0e191de63f7a6de63f7a6de63f795de63f79f",
        "902762ca956a2cb95613776f3c4ad5d35cb8a87a80aa677a75ae7c7a8ca5524880aa67aa39c6e7188ca5527a45c1d27a50bdbd1845c1d24875ae7c4850bdbd4875ae7c7a8ca5524869b391aa80aa6748",
        "30da6217d0c369da2f0a40131e56b5433cc608d63cab1bcb627342b543c608d643ab1bcb5b7342b5718e2fc03c7342b56a7342b54bab1bcb62ab1bcb4bc608d652ab1bcb71ab1bcb3cc608d64bc608d6",
        "b04b0f1d106e788adffb3ca9d013cbede34d187d18d642d618862aa2e3862aa2a04d187da033106be3862aa218bb3ac51868208e184d187d5b862aa218a132b3a0862aa21868208e1868208ea0d642d6",
        "50524b94e8e7c127a211058d3fc3b7ed947c4a94947d4a94c07b875dd67aa542d67da54294794a94aa796879947c4a94aa7b6879947d4a94aa796879d67ba542947b4a94c07b875d947b4a94c079875d",
        "d03834d7135783a7321bd087157bb24dc671ef6b9171c16d08714a7376d7a96ec6d7ef6b7671a96e3d927871c692ef6b7692a96e08b64a73ab92d86cabb6d86c7692a96e76d7a96e7671a96e9171c16d",
        "70e53ff66266c77b342782a9283a62a16f737681297b657bb96bca86ff63a98c6f738681ff63768cff63868c297b767bb96b8686b96bdb866f736581b96b7686ff63ca8c297b867b6f736581297bba7b",
        "f0f00afee3586ed3149f185a43df1079841091ff9c6b91ce841096ffadab93acadab91acb5c9939c841093ff944c91dfbde7938c9c6b93ce9c6b8ece841093ff8c2e96ef944c96dfb5c98e9c9c6b91ce",
        "208635cd82a47fc340eea2395c14b19a0c6891df0c6891309440cca60c6891a6d72ce9df4f54aea6d72ce9a64f54aedf4f54aea60c6891df4f54ae30d72ce9690c689169d72ce9694f54aea60c689169",
        "60aaa535f54fc13acfb1ce65c6726e2cba8fc66aba8fc66ab0708b81ce525297c4adff54b0708b81ce8fc66aba8fc66ac4525297ce8fc66ac4708b81ba525297b0708b81ceadff54c4525297b0adff54",
        "a01eff11501e714b4c6612288d2348817bdc9f607b129f60bedc722f3c54cb8ffd1246003cdccb8ffd5446003cdccb8f7bdc9f60be54722f3cdccb8f3c9acb8f3c9acb8f7bdc9f607bdc9f60be54722f",
        "e0abe6444a787decfc96f3f5e9e2b3a76d501f249ba5325e9ba5325e6d503b249ba5325e847b1f42562632089ba53b5e6d503b24847b1f429ba53b5e9ba5325e847b3b42847b28429ba5325e9ba5325e",
    ]


def bc6h_vectors() -> List[String]:
    """Return the reference vectors; see the module docstring."""
    return [
        "054bb5e1dcd4a6caad14443dbaacbee07397554f24f413a7f554b4f263a76546e500338d9551f4e3638d9551f4e363a8355b44ebd3a76546e500338d9551f4e363919550c4ea43a715406506b3a7a54d74f9a389c55304dcd38bb55274e013a8c56854dec3a715406506b397554f24f41",
        "0744f05fd4fbd3488b1175c0b67085dbc4d6a3f867b004dbd3fb47a6d4e613e3269db4cc53ec1237f4cf43f457bd14e0b3fe079e14d983e7847a04c603ee412624d953f9f7ab24cf43f457bd14cc53ec1237f4ec53e0f7af84d423f717b464d953f9f7ab24ec53e0f7af84cc53ec1237f",
        "0c9ee8060042828802d52a6363b745d6472cc01962efc72cc01b92efc72cc02262efc72cc02262efc72cc01962efc72cc01dc2efc72cc026c2efc72cc01742efc215c09f5487972cc02492efc72cc02262efc72cc02492efc426b112a45ee0c1c05544a1c16bc07a4494a72cc01dc2efc",
        "0e1509dc7d2e673167cf8195b22b581d50e59411e5af10ace3ce55daa1ce9527a4fbd1ce9527a4fbd0e59411e5af10e59411e5af115d34a08553015d34a0855300e59411e5af111e44557583711e445575837074438ac6064452c484757ce54b4479851f3246349b7642c33eb49085e51",
        "0a24806622b269d023ec754f19c40b18c234000b21a4a236c00731a76234b00a31a5523ac00f01a48238200551a8c236200831a6c238800f01a46236700f01a43233500c11a3f23ac00f01a48236700f01a4323ac00f01a4823cc00f01a4a23ac00f01a48234600f01a41236700f01a43",
        "002a714d276f2379e24c853507b4fa55212eb408372e311fc40a773161212401673211212401673211387407872b613a6407672ad13a6407672ad1205406c731a11f340e07311130a408172da1387407872b61328407e72d1120a404f731c11fc40a773161200408b73181328407e72d1",
        "0e320fb0fd1c2586d1c613fca3357ce1d17656be5147d1e99788c11091e99788c110917656be5147d0af556091a751ba7735f127311d5621d17290f365d83186a1ba7735f12731ba7735f127316166998151e19086ec513b40c44585619d40f365d83186a0de75b36190b1e99788c1109",
        "0c3f69380103f3f1ca19f5aec5ca7b69e731923c807cf76ad34de30d0786d3d3644d7764332e12c0c76ad34de30d074d92c201bd67758380c387178183b9f41077758380c387174d92c201bd675982fb4246b76ad34de30d075432e1d209a7703367534a178183b9f4107764332e12c0c",
        "006b74d02896d8c3d884416651834370958ae477145cc58ae477145cc58b0477745c158ae477145cc58b2477e45b658ab476a45d758b2477e45b658ab476a45d758b9476b45eb58b94792459458b4478545aa58b2477e45b658a2473e45ed58b9476b45eb58b9476b45eb58ab476a45d7",
        "00671ebc0ddd11033ccdb24cd06414a2374b91c892ca474ad1c962cb174ad1c962cb175271bd92c9374811ccc2ce774811ccc2ce775201c002ca775291bca2c8c74c31c7c2c9775291bca2c8c75291bca2c8c75251be62c9a75251be62c9a75271bd92c9375291bca2c8c75201c002ca7",
        "00775e33a589cdfed5bd4fee2d1e2fdc074605e863f0d74605e863f0d74d25d923f31709d66a13ddc700f67d23daf6f9e68c63d8b75b45baa3f78700f67d23daf76425a783fa5709d66a13ddc75b45baa3f78700f67d23daf709d66a13ddc6f9e68c63d8b76b359843fc9710e65ad3e00",
        "08751744df44772001c3414189bdb5f952dc1685f215428776aa921542b97694e21542aa169b921542b97694e215428776aa921542fad6789215428776aa9215432cc662f215430a3671f215432cc662f215434b9655a215436e2646a21542c8d68e421542c8d68e4215430a3671f2154",
        "06aca10758d8bfdcc41dfa28a9c8df4a9620e21072a4a621220f52a2c621920da29fc621220f52a2c621720e32a0c621720e32a0c621520ed2a1d621b20d129ed6205213a2a27621020fe2a3b621220f52a2c621220f52a2c61ef20f72a1c6201212d2a25621220f52a2c621920da29fc",
        "06ab9e8e045f5bb7e4f6c60c0e8b9cb841bd25a2f6b8f1b675a226b681bd25a2f6b8f1c3e59d26b421b675a226b681bd25a2f6b8f1b975a636af41b565a9b6ad51b8a5a266b751b9d5a286b7c1b565a9b6ad51bfd5a0a6b231b675a226b681bb85a466b031c3e59d26b421bfd5a0a6b23",
        "06b9dee3748f0ee15030ce3058179a1ba2625736e1fe926217af41fd526581b0320de26217af41fd5262f6280201826620a15210d26375373204226217af41fd52625736e1fe926463afe2086264a3378209b2642428520712625736e1fe926502a1020b426502a1020b42654228920c9",
        "0eb842ba631cfbfa1e16ac50856022bd73f3240a663673e754097654d3eaa409b64c33ee0409f643a3ef040a164113e91409a65043ec7409d647b3f3240a663673ee0409f643a3ef040a164113f1640a463b03f3240a663673e9e409a64e43f1640a463b03ed3409e645a3e8540996525",
        "0aeab7cc26060ef18e0efa7db8b809888550d3c41171a55763c151697524d3dc1185453613eb018d453613eb018d4578d3b3713fb55763c15169752de3e3e189750c53c6d179d54a53c6d179d55763c15169752de3e3e189751473cde17da51473cde17da55763c15169756533bb91583",
        "0eef96fdaeea4a9a010cda2d070454ec9704136215885700c3703589670263692588d6fd537f258a86fa138d558ba7041362158856fa138d558ba6fbb386458b1713c36d1558370413621588570263692588d6f87394758c3703b37085527713c36d15583700c370358966fa138d558ba",
        "0ef0906bc14d3fa5c7646d3879d8bd75e30965b1665e530965b1765e430965b1665e430965b1665e430965b1665e530975b1865e230965b1765e430965b1765e330975b1865e230965b1765e330965b1765e330965b1765e330965b1765e430975b1865e230975b1865e230965b1665e4",
        "00f8b0063b295a8d281b8188d079045ea66da14582d2366dc14592d2566dc14592d2566dc14592d2566dc14592d2566da14582d2366dd14592d2566dc14592d2566dc14592d2466da14582d2366da14582d2366dc14592d2566db14582d2466db14582d2466dc14592d2566dd145a2d26",
        "032fabd8758252b15056e5dd51c16f3c2612f3a6322bd5e2a3962242d629d3add220e5e2a3962242d5cbc38e824db5f9839dc237e612f3a6322bd657a3bd220b2612f3a6322bd640b3b5721605cbc38e824db6db935e120bd5b4e386e258a69fc35721eba6672350a1cd26bc235a61fae",
        "012aeb5d076d784a403f1ee62ed8800bd32d0354b34742a122e2832412c2f2fff335836fa396638ea32d0354b34743039362835c02c2f2fff335830a433e135a5317335c03523367e3412329e34dd378f37d336fa396638ea367e3412329e3039362835c02dc636fa36fa32c035b836bc",
        "096cf6780f1343bea5a6fbb6823e000b93c0867e95b9b3be5699d5aca4194692559c43e6668825c853b786eea583f3c5b681a5e4b429a695a58e23c2b66355c6c3c4e64825d3e3e6668825c853f8968bd5b8a3c4e64825d3e429a695a58e2408e68f15aa73b786eea583f3b9b6d365910",
        "0f669ae93ae2be72067fa9cf431d17ed124422b5f23ce25c22c5323ab25c22c5323ab22ad2a5e23f3212e296a241625c22c5323ab21ed29e42404207d296f215426822cce239a22ad2a5e23f3208f29e9219a20b22ade222624422b5f23ce204727f4207b2058286e20c1206a28e82107",
        "01a7dfc981d46cff55b8f89a42b2a2e047106778c6031709e785e630e70d277f5619f75e468ca643471a976475bbe73d946bb677971b122c86aed76ea79d2629271b122c86aed74de57c365d772b633d0694a73d946bb677975e468ca643472b633d0694a76ea79d2629276ea79d26292",
        "0ba3297fac0a33ff788694535304f79c647de16513b90462c15ae37bf4753161d3a5645a1157a368547de16513b90486a16863cca45151546354b462c15ae37bf448a15123412462c15ae37bf4753161d3a56434612d83c5546c715e9391c434612d83c554a5a170230ae46e014f63666",
        "05eef5c17df5ffd501dc6cb11e8f8d30571e3673b224519da3d0871581a753d0871581c183d087158719d6b511c4671586f68164871e3673b224518383d0871581c183d0871587348525840e87348525840e8719d6b511c46194f3d0871581a753d0871581b8c3d08715871586f681648",
        "07ef1edb6a06e35855aba230e3a6ef0b61648354835481b2f3e002c04205c4734223d1da3425c276258284c8865b85bf84bfc4d3265b84a980e8858284c8865b85de04bb640ef61e74b23270d5a104c42597558284c8865b827b85448145822d04b901d9b22d04b901d9b22d04b901d9b",
        "144a90833e109320dcd11aaea77c5d87a4fc5f92024c44fc5f92024c44f58fadf24214fc5f92024c450c5fa6d28154f13fbff23b94f35fb6f23ed4f58fadf2421514afac627625113faa127ac5164fad7273f4f35fb6f23ed50dffa7e27f2514afac6276250c5fa6d28155164fad7273f",
        "15c6d8ad3ebddc0cd7f4a9d3151a0ff21a4c1b8aa760aa48db9127661a4c1b8aa760aa4deb86f75d9a48db9127661a48db9127661a4a7b8de7635a510b9f775b9a473b947768da570ba2b7562a75bbb3773a5a75bbb3773a5a75bbb3773a5a510b9f775b9a63bba9a74aaa4b1b9c37611",
        "17d49fe1ce8c956b2508ecc818608fc3fea1b90e40463eb0493eb8463ea1b90e40463e7a888b81c18eb0493eb8463eca6995e9431e7a888b81c1839d2b2fb0ef4eb0493eb8463e7a888b81c18e7a888b81c18b168945823d8ed789c189c18ed789c189c18b168945823d863c8bef806c8",
        "1756da788423eeab7009d5f4248bfb0fda31ed3f299ac9e84ca2b26c0a0b2cecd083ca9a87728cc88a54cd894b830a9a87728cc88ab4a769cb630b203745f25a9ae8f75858981b54873485258aced76119fd9a9a8e1d8f538ae8f75858981a31ed3f299ac9a28c0e863c89a28c0e863c8",
        "1c2c407493986672fe2cff4c26d738dd642c8bc4fe83c4382bcbae8714345bc97e86040d8bbe1e8144364bca9e8684345bc97e8604210bc7de7bb4210bc7de7bb42c8bc4fe83c428abcbae7984152bc1ee7f1418fbc3ce7e041d3bc5ee7cc424dbc9be7a94152bc1ee7f1418fbc3ce7e0",
        "1820e47dc0f9f7921e76f283fd516ae04edfa111e79f2edfa111e79f2ede810d67a16ee2211227a5dedfe113079eaeded10e87a0eef2d11227968eef911227998edf5110d79fbedfe113079eaeebf112279ceeef911227998eded10e87a0eeebf112279ceef9611227908ef9611227908",
        "16301529d1966bb73b25eb9fe614229780592c7ee326323823e2636752c9066b037b0116892eb33ff1d3e2216359b23823e2636752c9066b037b02f59732938110592c7ee326314e383543478090db85632dc0e9f9f64339e1d3e2216359b090db85632dc1a75159d353a17ac092434d9",
        "183de9c8f95629534e251f39d938bef2dbbb6aab3c5950eaa23eb1335bbb6aab3c595a52292d5aaa0afc29e10b75013fb2989198d08061ce60b478e8d05088facafc29e10b7508e8d05088fac829911ab816793dd8095960413fb2989198d0eaa23eb133508061ce60b47b512a3aebda7",
        "12687e4bce506308218d06ba6627e8ca6f54b37665914f5393813582df5a437c3596df57037eb58d0f54b37665914f5813766594af528376658f1f57037eb58d0f5393813582df5a43766596df53937665902f5933766595cf5a437c3596df54b38065862f59337d15939f5813766594a",
        "1e6a48ba105588a69f1d97d6d2524d22d23c85f21a4b723c85e26a48223c85f5ea4c523c85f21a4b723605f9ea56023c55fcba54d23965fb6a55622d05f5ca57a23305f88a56923305f88a56923965fb6a55623965fb6a55623f65fe2a54523c55fcba54d23c55fcba54d22d05f5ca57a",
        "1e78b10e12c06b3d561d13fc8a6dfc3630b90420eb07f15413cf0b4ad0d0e4145b1242011373bb957236b3576baca10693f7fb296183c3b5db5f71e933805b8b215413cf0b4ad1b983998b769236b3576baca2011373bb95710693f7fb2961e933805b8b210693f7fb29615413cf0b4ad",
        "127b3208f02aefe118c159d2e658c13582e70b6bb29612d78b6e529e82f0bb69f290d311ab64527ec2aedb7552b4d2cfcb6fa2a2c2a52b7702ba1307fb65f28412f0bb69f290d2e70b6bb29612b69b73f2b092d78b6e529e83003b6752885311ab64527ec2d78b6e529e82f0bb69f290d",
        "10a032e3c6e38b9b7fc7eb1a320974b6902f70b339b6d02d00ad89aa8029a0a5a999c02f70b339b6d02b40a979a1f02f70b339b6d02c20ab69a6002c20ab69a6002d00ad89aa802ea0b159b2b029a0a5a999c02b00b179b0f02dd0af69aea02b50ae79af002a30bac9b6e02b50ae79af0",
        "14a6764a696041904c14ce9239898e3fe97f81801676297d4177267f197cb174f681498091847671c98001824673f98091847671c97ef17de67859846188e676697e517b867ab9827188a67bd98e218a465a898091885681498e218a465a898c318a065ff98e218a465a898641893670e",
        "14b279a3d9b0242b3515674f23c2badc9130a6fada4f614b16fffa2ef15157012a27414b16fffa2ef14606fefa35215667022a21113bf6fd0a417181170a59ec9170b7073a00a14106fe0a3b516bb7063a06d13bf6fd0a417175c70829fa7166a7054a0d016077041a14c170b7073a00a",
        "1abf3eb2a886acf99cf989bb39640bb1cc1b95e0abb4fc01d607bba4cc16a5e81bb1dc11c5ef8baecc06c6004ba7dc11c5ef8baecc3075c0fbc21c06c6004ba7dc2075d93bb80c11c5ef8baecc4065a8cbcc2c2b95c86bbf0c06c6004ba7dc06c6004ba7dc01d607bba4cc3b75b03bc90",
        "16e2bee15ef3bda550f028646ea4ef6bfd05e92b3b8a6d02a91aeb966d13596e6b591d05e92b3b8a6cd2e9367b7d3d09293b9b7e6d13596e6b591d0c694beb726ce3a941ac02ecd9d93b1bb46cd9d93b1bb46d13596e6b591ce3a941ac02ece3a941ac02ece3a941ac02ecd2e9367b7d3",
        "10e70838d1d76dad314ca23bd731392a8be3ef9566026bc65f9bf5ac2bc65f9bf5ac2c28ef52159a3bda193296194bcca78da638abd6612ad621bbde4f89f5a7cbde4f89f5a7cbdd5b538611abe3ef9566026be09d74760a0bae5fadf5b08bae5fadf5b08bc65f9bf5ac2bd3234bc6295",
        "14f8e0892544aee11784874eed48ec84a272c934e4037272b934e4037272b934e4038272c934e4037272c934e4037272b934e40372728934d40392728934d4039272c934e40372729934d40392728934d4039272b934e4038272b934e40382729934d4038272a934e4038272c934e4037",
        "18faaf13c24259980493ccb9a451326d04eca30510dad4eca30510dad4ecc304e0dae4eca30520dad4ecc304f0dae4ecc304e0dae4ecc304f0dae4ecb30500dae4eca30510dad4eca30510dad4eca30520dad4ec930530dad4ecb30510dad4eca30520dad4ec930530dad4ecc304e0dae",
        "1128c3a65f0803a5d41ebf58be3c58c6661927031301a7a8c66342b1c7a8c66342b1c65a86e8f2f496e496b1b2d8f69be6cec2e786e496b1b2d8f7a8c66342b1c65a86e8f2f496e496b1b2d8f61927031301a69be6cec2e785cba6f3536216b70757933f35cba6f35362145d765763985",
        "172d6c8ec0abad93ecab8b0f64136aae9cb14ec0472cccaabe6b37192dce1e0d0ba7ddce1e0d0ba7dca1cdf6c6fe4e399dfb14534e53cdf6c6444e399dfb14534caabe6b37192e054e03d0715de83e08a9b6de1f7dff72625dce1e0d0ba7de399dfb14534dce1e0d0ba7de054e03d0715",
        "1b6f36f509fe18e587f23528845472e84e064a074d5bcdc7caae5dda2e15ca074db8cdd70a8dadd3ae064a074d5bce5b4a421dbdde229a1add7c7df73a48adc5decfca92ce444e064a074d5bce229a1add7c7ecfca92ce444e3eea2e7d9d2e064a074d5bce229a1add7c7e7aba57ede22",
        "13644ba1e360bc06c5ef35e5b4a234bc222e770dc0c2728b763ee08b0277d668509ea277d668509ea221670dc0d1b221670dc0d1b2dc2594a03a528b763ee08b0214570dc0e0f221670dc0d1b277d668509ea2c885be104df221670dc0d1b221670dc0d1b207470dc0f042b4e5e770619",
        "13aee05c9f2698b2218ef4a7d378069b26d6809c762b871bc8322578175c3824565056c04845c444c6d22091863676c04064c66346dec83f34ab37994817471d46df40b24615c6df40b24615c73db82ad5e9e75c3824565056d22091863676d6809c762b86c4906fa658575c382456505",
        "15a522879b88e938209c0b65bae85282cec454d703b4aeeb94c593ca7f3c44a1c3f74f28a4aa73ec5ed7f4ce53bf8f28a4aa73ec5f1504b333e17f28a4aa73ec5e84348434e1beb0c4dfc3a9ced7f4ce53bf8f0164bbe3d68e84348434e1be72c454455bceeb94c593ca7ec454d703b4a",
        "17ea8e064469da03d8fc6b081904a73c50d9005d0b830a0360ab7a979a0360ab7a9791d10c7b0db10b12a0c88a4060d9005d0b830239a9d2fcce5239a9d2fcce5c06c0e2b9f1f2a810faebdf0310b3a2fafc52a810faebdf026df87eec5cf2dc624efb6db1d10c7b0db1026df87eec5cf",
        "19e5831d62be43347ab305760c36e03a011fbd421bfb2143937e110f41170f630d3501170f630d3508425d57e14f31312900398761170f630d3501312900398768425d57e14f3143937e110f4143937e110f411fbd421bfb25350f63066b05350f63066b01170f630d350143937e110f4",
    ]


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()

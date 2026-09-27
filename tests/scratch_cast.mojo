from core.assets import Assets
from materials.material import Material, PointSize, points_material
from render.framebuffer import Color
from renderers.renderer import Renderer
from test_cast_shadow import a_sun, dots, one_texel, panes, a_dot


def main() raises:
    var assets = Assets()
    var mapped = Material(Color(200, 200, 200))
    mapped.map = assets.textures.add(one_texel(255, 255, 255, 64))
    var scene = panes(assets, [mapped.copy()], [Float32(2)])
    a_sun(scene)
    scene.update()
    var renderer = Renderer(8, 8)
    renderer.shadow_map_transmitted = True
    var maps = renderer.shadow_maps(scene, assets)
    print("pane alpha", maps[0].colors[(8 * 16 + 8) * 4 + 3])

    var dotted = dots(assets, [a_dot(assets)], [Float32(2)])
    a_sun(dotted)
    dotted.update()
    var dmaps = renderer.shadow_maps(dotted, assets)
    var drawn = 0
    for t in range(len(dmaps[0].colors) // 4):
        if dmaps[0].colors[t * 4 + 3] > 0:
            drawn += 1
    print("dot texels", drawn)

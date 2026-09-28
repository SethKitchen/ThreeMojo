# Writes the USDC crates and the USDZ archive in this folder from the USDA
# layers beside it. Run it with OpenUSD's Python module, `pip install
# usd-core`, from this folder. `brick.png` is `../brick.png`.
import os
import subprocess
import sys
import zipfile

VERSIONS = {
    "scene.usdc": ("scene.usda", None),
    "values.usdc": ("values.usda", None),
    "values_0_3.usdc": ("values.usda", "0.3.0"),
    "values_0_6.usdc": ("values.usda", "0.6.0"),
    "variants.usdc": ("variants.usda", None),
    "geo.usdc": ("geo.usda", None),
}

EXPORT = "from pxr import Sdf; Sdf.Layer.FindOrOpen(%r).Export(%r)"


def crate(source, target, version):
    env = dict(os.environ)
    env["PXR_USDC_EMIT_DEPRECATION_WARNINGS"] = "0"
    if version:
        env["USD_WRITE_NEW_USDC_FILES_AS_VERSION"] = version
    else:
        env.pop("USD_WRITE_NEW_USDC_FILES_AS_VERSION", None)
    code = EXPORT % (source, target)
    subprocess.run([sys.executable, "-c", code], env=env, check=True)


for target, (source, version) in VERSIONS.items():
    crate(source, target, version)

brick = open("../brick.png", "rb").read()
files = [
    ("stage.usda", open("stage.usda", "rb").read()),
    ("geo.usda", open("geo.usda", "rb").read()),
    ("parts/geo.usdc", open("geo.usdc", "rb").read()),
    ("parts/variants.usdc", open("variants.usdc", "rb").read()),
    ("textures/brick.png", brick),
]
with zipfile.ZipFile("package.usdz", "w", zipfile.ZIP_STORED) as archive:
    for name, data in files:
        info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
        archive.writestr(info, data)

# A package whose first file is a crate.
with zipfile.ZipFile("crate.usdz", "w", zipfile.ZIP_STORED) as archive:
    for name, data in [
        ("scene.usdc", open("scene.usdc", "rb").read()),
        ("brick.png", brick),
    ]:
        info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
        archive.writestr(info, data)

# How to add a scanned building

This guide adds a SuperSplat scene to the scanned buildings, pins its files and fits it. You need a machine that can reach `superspl.at`. See [Scanned buildings](Scanned-buildings) for what each step does.

## 1. Choose a scene

1. Open the scene page on SuperSplat.
2. Make sure that the page has a Download button.
3. Read the license next to it. It must be CC BY 4.0 or CC0 1.0.
4. Write down the scene id, the title and the author's name and page.

The tool refuses CC BY-ND and CC BY-NC. CC BY-ND forbids changes, and ThreeMojo changes what it reads. CC BY-NC forbids commercial use, and ThreeMojo has a commercial license.

## 2. Add an entry

Add an entry to `assets/building_scans/manifest.json`. Leave `files` empty. Choose the kit that is nearest to how the building was built.

```json
{
  "id": "stone-chapel",
  "title": "The scene's title",
  "author": "the author's name",
  "author_url": "https://superspl.at/user?id=the-author",
  "license": "CC-BY-4.0",
  "source": "https://superspl.at/scene/abcd1234",
  "scene": "abcd1234",
  "provenance": "What the scene page says about the capture.",
  "changes": "None. ThreeMojo reads the published SOG files as they are.",
  "kit": "stone",
  "use": "meeting",
  "frame": {"up": "-y", "north": "-z", "unit_m": 1, "scale": "declared"},
  "files": []
}
```

Use `"scale": "measured"` only when you measured a length in the place and in the scan. Then set `unit_m` to the meters in one scan unit.

## 3. Pin the files

```bash
sh tools/tool.sh .venv/bin/mojo building_scans check
sh tools/tool.sh .venv/bin/mojo building_scans fetch stone-chapel --pin
sh tools/tool.sh .venv/bin/mojo building_scans verify stone-chapel --strict
```

The pinning fetch reads the scene page, downloads `meta.json` and its images into `.cache/building-scans/stone-chapel/`, and writes each file's URL and SHA-256 into the manifest.

If the page cannot be read, use its Download button instead:

1. Put the downloaded `meta.json` and images in `.cache/building-scans/stone-chapel/`. Unzip a `.sog` bundle into that folder.
2. Add each file to `files`, with `"url": null` and `"sha256": null`.
3. Run the pinning fetch. It records the sum of each file in the cache.

## 4. Update the credits

```bash
sh tools/tool.sh .venv/bin/mojo building_scans credits --all
```

Put the credits section at the end of `assets/building_scans/ATTRIBUTION.md`, in place of the old one. `tests/test_building_scans_tool.mojo` requires that the file ends with this text.

## 5. Fit the scan

```bash
.venv/bin/mojo run -I . examples/building_scan.mojo out/stone-chapel.png stone-chapel
```

Read the report. Check that each storey's height and plan match the place. Check the notes, and correct the frame in the manifest if the model stands on its side.

## 6. Commit

Commit the manifest and `ATTRIBUTION.md`. Do not commit the cache: `.cache/` is ignored, and each person fetches the files with the pinned sums.

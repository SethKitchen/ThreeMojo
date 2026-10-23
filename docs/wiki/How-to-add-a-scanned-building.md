# How to add a scanned building

This guide adds a SuperSplat scene to the scanned buildings, pins its files and fits it. You need a machine that can reach `superspl.at`. To add a scan that is one file at a URL, such as a release on GitHub, see [Add a scan in one file](#add-a-scan-in-one-file). See [Scanned buildings](Scanned-buildings) for what each step does.

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

Read the report. Check that each storey's height and plan match the place. Check the notes, and correct the frame in the manifest if the model stands on its side. To see the scan itself, draw it from all sides with `examples/scan_view.mojo out/view.png stone-chapel`. Add `auto` after the id to let [`estimate_up`](Cleaning-and-orienting-scans#find-the-up-axis) find the up axis. Most scenes on SuperSplat have up along -y.

## 6. Commit

Commit the manifest and `ATTRIBUTION.md`. Do not commit the cache: `.cache/` is ignored, and each person fetches the files with the pinned sums.

## Add a scan in one file

A scan in one file can be in any format that `extensions/scan/files.mojo` reads, such as a compressed PLY file. Give it one `splat` file with its URL, no sum, and a null `scene`:

```json
{
  "id": "stone-chapel",
  "title": "The scan's title",
  "author": "the author's name",
  "author_url": "https://github.com/the-author",
  "license": "CC-BY-4.0",
  "source": "https://github.com/the-author/scans/releases/tag/1.0",
  "scene": null,
  "provenance": "What the release says about the capture, and where the scale comes from.",
  "changes": "None. ThreeMojo reads the published file as it is.",
  "kit": "stone",
  "use": "meeting",
  "frame": {"up": "-y", "north": "-z", "unit_m": 1, "scale": "assumed"},
  "files": [
    {
      "role": "splat",
      "url": "https://github.com/the-author/scans/releases/download/1.0/chapel.compressed.ply",
      "sha256": null,
      "path": "stone-chapel/chapel.compressed.ply"
    }
  ]
}
```

1. Read the license in the source. It must be CC BY 4.0 or CC0 1.0.
2. Run `building_scans fetch stone-chapel --pin`. It downloads the file and writes its sum into the manifest.
3. Draw the scan from a few sides, for example with `examples/scan_parts.mojo` and the file's path. Correct `up` if it stands on its side or upside down.
4. Measure one length in the scan whose size you know, such as a door or a published dome. Set `unit_m` to the meters in one scan unit, and say where the length comes from in `provenance`.
5. Update the credits and commit, as above.

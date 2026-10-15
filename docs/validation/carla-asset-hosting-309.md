# CARLA archive hosting check (#309)

The 47 CARLA archives are on Google Drive, and each one is shared with anyone who has the link.
The Drive API returned 36 archives, and each one matched its pinned SHA-256 sum.
The public download links were not tested from this environment, because its network proxy refuses connections to Google Drive.
The other 11 archives were not checked, because they are larger than the Drive connector can return.

The owner then ran the public download of all 47 archives into an empty cache, from a network that can open Google Drive. The owner reported that it works: every archive was fetched and `verify --strict` passed.
This closes [issue 309](https://github.com/SethKitchen/ThreeMojo/issues/309).

Date: 2026-10-11. Manifest: `assets/carla/manifest.json` at commit `765356f`, not changed by this check.

## Result

| Check | Result |
|---|---|
| Destination | Google Drive, one folder that the owner controls. The owner chose it. |
| Authorized publisher | Seth Kitchen. The Drive API gives his account the `organizer` role on each archive. |
| Sharing | All 47 archives: `anyone`, role `reader`. No archive is private. |
| Archive sizes | 968,072,352 bytes in all: 124,583,108 bytes for 41 vehicles and 843,489,244 bytes for 6 towns. The largest is Town10HD, 204,022,674 bytes. |
| Public link download | Not tested. The proxy answered `403` to `CONNECT` for `drive.google.com:443` and `drive.usercontent.google.com:443`. |
| Drive API download | 36 of 47 archives: 89,988,342 bytes, every SHA-256 sum matched. Then `fetch --offline` extracted them, and `verify --strict` reported 365 files `ok`: 36 archives and 329 members. |
| Not checked | 11 archives: 5 vehicles from 6,296,199 to 8,091,285 bytes, and the 6 towns. |
| Quota, permission and web page responses | Not seen live. The offline tests cover them. See "Offline tests". |

## Method

1. The Drive API listed the archive folder. It gave the name, the file id and the size of each archive. Each file id is the id in the manifest URL.
2. The Drive API read the permissions of each of the 47 archives.
3. The Drive API downloaded each archive into a new, empty cache.
   The check computed the SHA-256 sum of the bytes and compared it with the manifest.
   It wrote an archive into the cache only when the sum matched.
4. These commands then checked the cache:

   ```sh
   python3 assets/carla/tools/carla_assets.py --cache CACHE fetch --offline
   python3 assets/carla/tools/carla_assets.py --cache CACHE verify --strict ID ...
   ```

5. `stage-archive` packaged `carla.vehicle.micro.microlino` from that cache.
   The package held the archive, `manifest.json` and `ATTRIBUTION.md`.
6. `fetch carla.vehicle.micro.microlino` ran against a second empty cache, through the public share link.

The Drive API downloads use the owner's account.
They prove that the bytes on Drive match the manifest.
They do not prove that an anonymous user can download the files.

## Public link download

The proxy of this environment refuses Google Drive:

```text
$ python3 assets/carla/tools/carla_assets.py --cache EMPTY fetch carla.vehicle.micro.microlino
FetchError: https://drive.google.com/file/d/1jWX1SrYg6A7GinPuqbC7geNvDxXdPNPn/view?usp=sharing: <urlopen error Tunnel connection failed: 403 Forbidden>
```

The tool wrote no file into the cache.
Before this change, the tool tried a refused tunnel five times, for 21 seconds.
Now it stops after the first refusal.

Drive did not send a quota page, a sign-in page or a virus-scan page, because no request got to Drive.
The tool asks for `confirm=t`, which skips the virus-scan page for large files.
If Drive sends a web page, the tool stops and keeps no bytes.

## Per-entry result

| Entry | Archive bytes | Drive sharing | Drive API bytes vs. pinned SHA-256 |
|---|---:|---|---|
| `carla.vehicle.audi.a2` | 1,347,753 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.audi.etron` | 3,439,754 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.audi.tt` | 1,747,298 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.bh.crossbike` | 6,571,842 | anyone with the link, reader | not checked: the result is larger than the connector can return |
| `carla.vehicle.bmw.grandtourer` | 1,708,365 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.carlamotors.carlacola` | 333,821 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.carlamotors.european_hgv` | 6,842,024 | anyone with the link, reader | not checked: the result is larger than the connector can return |
| `carla.vehicle.carlamotors.firetruck` | 8,091,285 | anyone with the link, reader | not checked: the result is larger than the connector can return |
| `carla.vehicle.chevrolet.impala` | 1,257,616 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.citroen.c3` | 1,486,084 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.diamondback.century` | 1,875,953 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.dodge.charger_2020` | 2,399,584 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.dodge.charger_police` | 3,190,005 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.dodge.charger_police_2020` | 2,836,397 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.ford.ambulance` | 6,793,416 | anyone with the link, reader | not checked: the result is larger than the connector can return |
| `carla.vehicle.ford.crown` | 4,228,343 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.ford.mustang` | 2,444,577 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.gazelle.omafiets` | 2,203,085 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.harley-davidson.low_rider` | 6,296,199 | anyone with the link, reader | not checked: the result is larger than the connector can return |
| `carla.vehicle.jeep.wrangler_rubicon` | 2,686,440 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.kawasaki.ninja` | 2,906,056 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.lincoln.mkz_2017` | 3,985,894 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.lincoln.mkz_2020` | 2,244,698 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.mercedes.coupe` | 1,857,283 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.mercedes.coupe_2020` | 2,696,924 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.mercedes.sprinter` | 5,637,011 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.micro.microlino` | 285,530 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.mini.cooper_s` | 1,570,240 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.mini.cooper_s_2021` | 2,889,322 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.mitsubishi.fusorosa` | 3,443,050 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.nissan.micra` | 3,894,659 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.nissan.patrol` | 2,587,850 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.nissan.patrol_2021` | 2,242,744 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.seat.leon` | 2,591,413 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.tesla.cybertruck` | 2,150,485 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.tesla.model3` | 4,279,401 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.toyota.prius` | 1,703,607 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.vespa.zx125` | 4,268,786 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.volkswagen.t2` | 1,412,025 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.volkswagen.t2_2021` | 3,021,968 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.vehicle.yamaha.yzf` | 1,134,321 | anyone with the link, reader | match, extracted, `verify --strict` ok |
| `carla.town.town01` | 143,242,874 | anyone with the link, reader | not checked: the result is larger than the connector can return |
| `carla.town.town02` | 89,650,847 | anyone with the link, reader | not checked: the result is larger than the connector can return |
| `carla.town.town03` | 132,302,072 | anyone with the link, reader | not checked: the result is larger than the connector can return |
| `carla.town.town04` | 138,512,092 | anyone with the link, reader | not checked: the result is larger than the connector can return |
| `carla.town.town05` | 135,758,685 | anyone with the link, reader | not checked: the result is larger than the connector can return |
| `carla.town.town10hd` | 204,022,674 | anyone with the link, reader | not checked: the result is larger than the connector can return |
| Total, 47 archives | 968,072,352 | | |

## Offline tests

`tests/test_carla_assets_tool.mojo` tests these responses without a network. It gives each response from a stub `curl`:

- HTTP `403`, `404` and `429`: the fetch fails after one request and keeps no file.
- A web page with the content type `text/html`: the fetch fails and keeps no file.
- A Drive virus-scan, quota or sign-in page sent as `application/octet-stream`: the fetch fails and keeps no file. It reports a web page.
- A proxy that refuses the tunnel with `403` or `407`: the fetch fails after one request.
- A dropped connection: the fetch tries again, then verifies the sum before it extracts.
- A clean-cache download: the fetch verifies the sum, then extracts every member.

Run the tests:

```sh
.venv/bin/mojo run -I . tests/test_carla_assets_tool.mojo
```

The commands in this record ran `assets/carla/tools/carla_assets.py`.
`tools/carla_assets.mojo` replaces it, with the same command line:
`sh tools/tool.sh .venv/bin/mojo carla_assets` in place of
`python3 assets/carla/tools/carla_assets.py`.

## Public download by the owner

On 2026-10-11 the owner ran these commands from a network that can open Google Drive:

```sh
python3 assets/carla/tools/carla_assets.py --cache "$(mktemp -d)/cache" fetch
python3 assets/carla/tools/carla_assets.py --cache CACHE verify --strict
```

The owner reported that the download works for all 47 archives.
This result is the owner's report. The command output is not stored in this repository.
This download also covers the 11 archives that the Drive connector could not return.

If a later public download fails, record the archive and fix its sharing on Drive.
Do not change its sum.

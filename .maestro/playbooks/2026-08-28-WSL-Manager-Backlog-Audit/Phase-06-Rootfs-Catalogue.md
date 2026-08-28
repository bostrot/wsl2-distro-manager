# Phase 06: Re-source and Verify the Rootfs Catalogue

`images.json` is the distro catalogue offered in the create flow, and it has rotted. It still lists EOL releases (Ubuntu 16.04, 19.04, 21.04, Fedora 36/37, Debian 10, SLES 12), serves Debian and Rocky from `raw.githubusercontent.com` links pinned to build-specific tags, and serves Kali, openSUSE and SLES from tarballs attached to this project's own v0.6.1 GitHub release in 2022. This phase re-sources every entry from official vendor pages, verifies each URL actually resolves to a usable rootfs, updates the repo copy, and install-tests the survivors by clicking through the running app.

**Important:** at runtime the catalogue is fetched from `https://n8n.aachen.dev/webhook/cdn/images.json`, with the bundled `images.json` only as a fallback. This phase updates the **repo copy only**. The updated payload must be pushed to the CDN by the maintainer afterwards — make that unmistakable in the output rather than assuming it happens automatically.

## Tasks

- [x] Establish the constraints before sourcing anything:
  - Read `lib/api/archive.dart` and `lib/api/layer_processor.dart` and record which archive formats the app can actually import (`.tar`, `.tar.gz`, `.tar.xz`, `.wsl`, `.zst`?) — do not add a URL in a format the importer cannot handle
  - Read how `images.json` is consumed (`grep -rn "images.json\|cdn/images" lib/`) and confirm the exact schema: flat `"Name": "url"` map, ordering behaviour, and whether the name is parsed anywhere
  - Write both findings to `.maestro/playbooks/2026-08-28-WSL-Manager-Backlog-Audit/Working/catalogue-constraints.md`

  **Done 2026-08-28** → `Working/catalogue-constraints.md`. Headline findings, all measured against WSL 2.6.3.0 rather than reasoned:
  - `archive.dart` and `layer_processor.dart` are **not on the catalogue path** — they only serve the Docker source type. The catalogue importer is `wsl.exe` itself: `WSLApi.create()` downloads the URL and calls `wsl --import` directly.
  - `wsl --import` **content-sniffs and ignores the file extension**. Verified by importing an xz payload and a zstd payload both named `.tar.gz`, then round-tripping via `wsl --export` to prove the files landed. This matters because `create()` hard-codes a `.tar.gz` suffix on every download regardless of the real format (`wsl.dart:1355`) — cosmetically wrong, functionally harmless.
  - Accepted: `.tar`, `.tar.gz`, `.tar.xz`, `.tar.zst`, `.wsl`. Prefer `.tar.gz`, accept `.tar.xz`, treat `.tar.zst` as last resort (`wsl --export --format zstd` is rejected with `E_INVALIDARG`, so import is more permissive than export — thinner historical support).
  - **The Arch bootstrap tarball is ruled out.** A tar nested under a top-level prefix (`root.x86_64/`) fails with `WSL_E_NOT_A_LINUX_DISTRO`. Its zstd compression is fine; its shape is not. Do not source it in the next task without flattening.
  - **A dead URL hangs the create dialog forever**, it does not error: `create()` uses `ChunkedDownloader(…)..start()` (cascade → the Future and its exception are discarded), and `done` is only set on success, so the `while (!downloader.done)` poll spins indefinitely. Raises the bar on the verification task. Two neighbouring defects logged for the later fix task: the `file.rename()` at `wsl.dart:1377` is not awaited, and the temp path ends up `.tar.gz.tmp.tmp`.
  - Schema is a flat JSON object of `"Name": "url"` **string** pairs; any other shape (array, wrapper key, non-string value, or a non-JSON `Content-Type` from the CDN) throws and silently drops every client to its bundled fallback.
  - **File order is display order** — no sort anywhere between `json.decode` and the `AutoSuggestBox`. Reordering in the rewrite task is a real UX change.
  - **The key is parsed.** A key containing `:` is silently rerouted to the Docker registry path (`create_dialog.dart:183`); the key is also used verbatim as a filename (no sanitisation), and is the on-disk download cache key — so changing an entry's URL without changing its key leaves existing users importing the stale cached rootfs permanently.
  - Existing tests use synthetic catalogue payloads, so rewriting `images.json` breaks nothing.

- [x] Re-source candidate rootfs URLs from official vendor sources only, and record each source page URL alongside each candidate in `Working/catalogue-candidates.md`:
  - Microsoft's own distribution manifest (`microsoft/WSL` repo, `distributions/DistributionInfo.json` and any newer manifest it points to) — this is the authoritative list of WSL-ready distro images and should drive the core entries
  - Ubuntu: `cloud-images.ubuntu.com` (WSL rootfs variants where published), supported releases only
  - Debian: the official Debian container artifacts source, current stable and oldstable only
  - Alpine: `dl-cdn.alpinelinux.org` minirootfs, current stable branches
  - Fedora: the official Fedora download infrastructure Container-Base image, supported releases only
  - openSUSE / SLES: `download.opensuse.org` and SUSE's official registry-backed artifacts
  - Rocky / AlmaLinux: `dl.rockylinux.org` and `repo.almalinux.org` container base images
  - Kali: Kali's own download infrastructure (`kali.download`), not a third-party mirror
  - Arch: the official bootstrap tarball, only if its format is importable per the constraints task

  **Done 2026-08-28** → `Working/catalogue-candidates.md`. 19 primary candidates + 6 fallbacks, every URL read off a live vendor index or API today (not recalled) and smoke-checked with `curl -sIL` — **all 25 returned 200 with a plausible `Content-Length`**. Manifest parsed, not eyeballed, via `Working/phase-06/dump_manifest.dart`. Findings that change the brief:
  - **Arch is back in.** The constraints task ruled out the bootstrap tarball (`root.x86_64/` prefix → `WSL_E_NOT_A_LINUX_DISTRO`). Arch also publishes a purpose-built WSL image on its own mirror network with a **version-free alias**: `https://geo.mirror.pkgbuild.com/wsl/latest/archlinux.wsl`. Different artifact, no flattening needed.
  - **Fedora: take `Fedora-WSL-Base-*.wsl`, not the Container-Base image the brief names.** All three `Container-*` artifacts are `.oci.tar.xz` — OCI *layout* archives (`index.json` + `blobs/`), i.e. the same nested-prefix shape that was measured failing. The brief predates Fedora shipping a real WSL artifact.
  - **`cloud-images.ubuntu.com/wsl/` is dead** — index stops at oracular and `wsl/noble/current/` now holds only checksums and manifests; the rootfs tarball has been removed. Any such URL is a 404, which per the constraints task **hangs the create dialog forever**.
  - **`repo.almalinux.org` has no rootfs tarball** (only qcow2/raw under `cloud/`); the official channel is the `AlmaLinux/wsl-images` GitHub org. Same for SLE — nothing on `download.opensuse.org`, only `SUSE/WSL-instarball`.
  - **New non-rotting URLs found where the brief assumed none**: Rocky's `Rocky-N-WSL-Base.latest.x86_64.wsl` aliases, openSUSE's version-free `opensuse-{tumbleweed,leap}-image.x86_64-networkd.tar.xz` appliance aliases, and Debian's `stable/`+`oldstable/` artifact directories. **11 of 19 candidates never rot**, against 0 of 22 today.
  - **Debian's salsa job-artifact URL is durable by design** — `.gitlab-ci.yml` sets `expire_in: never` with a comment naming Microsoft's manifest. Still version-pinned, so the container artifact path is recommended instead.
  - **Oracle Linux cannot be added at all**: Microsoft ships it only as `.Appx` (a signed ZIP, not a tar) and Oracle publishes no rootfs of its own. Every legacy manifest entry is `.appx` and all 8 are rejected on the same grounds.
  - Deliberate exclusions recorded with reasons: Ubuntu 25.10 (EOL Jul 2026) and 20.04 (ESM-only since Apr 2025), Fedora ≤42 (gone from the release tree), Rocky 8 (no WSL-Base, newest build 2024-05), SLES 12 (no official replacement — do not re-source), AlmaLinux 8/Kitten, eLxr, MicroOS/Aeon, and all disk-image formats.
  - Proposed keys carried forward respect constraint rules 9 and 10 — notably `OpenSUSE`, `Kali Linux` and `SLES 15` **must be re-keyed**, or existing users keep importing the 2022 tarball out of the on-disk download cache forever.

- [x] Verify every candidate URL mechanically before it goes anywhere near the catalogue:
  - `curl -sIL --max-time 60` each URL and record final status, `Content-Type`, `Content-Length` and the redirect chain
  - Reject anything that 404s, redirects to an HTML page, or is implausibly small for a rootfs
  - For each survivor, download the first few MB and confirm the magic bytes match the extension (gzip/xz/zstd/tar)
  - Tabulate results in `Working/catalogue-verification.md` with a pass/fail column and the reason for every rejection

  **Done 2026-08-28** → `Working/catalogue-verification.md`; raw evidence in `Working/phase-06/verify/`. **28 URLs checked (19 primaries + all 9 tabulated fallbacks), 28 pass, 0 fail** — no substitutions needed, no fallback promotions required. Four checks per URL, not two: headers, magic bytes, and — beyond the brief — `ustar` magic at offset 257 plus a full `tar -tf` of the decompressed head, because [[catalogue-constraints]] §1.3 measured that a validly-compressed tar with a nested prefix still fails `WSL_E_NOT_A_LINUX_DISTRO`; magic bytes alone would have passed the Arch bootstrap tarball that §1.3 rejected. Findings that change later tasks:
  - **`.wsl` is not a format.** The 12 `.wsl` candidates are **7 gzip and 5 xz**, split by vendor (xz: both SLE, both openSUSE `.wsl`, **Arch**; gzip: Fedora, Rocky, Alma, Kali, Ubuntu, Debian-salsa). Both import fine, but **no code may infer the archive format from the URL suffix** — that would be wrong for 5 of 19 primaries on day one.
  - **The Debian OCI-blob question is settled**: `index.json` declares exactly one `tar+gzip` layer whose `size` equals the URL's `Content-Length`, the gzip header names the original file `rootfs.tar`, and the full download hashes to the manifest's layer digest. Flat 5 441-entry rootfs, no `blobs/`/`index.json`/`oci-layout` member. It never touches `layer_processor.dart`.
  - **Six artifacts downloaded in full and SHA256-matched** against vendor sidecars (Debian 13/12, Alpine ×2, openSUSE Tumbleweed/Leap). Release identity read from inside: Debian **13.6** / **12.15**, Alpine **3.24.1** / **3.23.5**, Tumbleweed **20260826**, Leap **16.0**. SLE 15 SP7 (**15.7**) fell inside the 6 MiB sample too.
  - **Every primary has a publishable checksum** (all 19 recorded, values in the doc) — the only candidate with none is the Debian salsa job artifact F04, one more reason the container-artifact path is the better primary. Arch's is `archlinux.wsl.SHA256`, **uppercase**; `.sha256` is a 404.
  - **`releases.ubuntu.com` sends no `Content-Type` header at all.** A check that rejects on "Content-Type is not an archive type" would have failed all three Ubuntu `.wsl` fallbacks; only the magic-byte check saved them.
  - **The Fedora redirector hands out a different mirror per request** (`mirror.dogado.de` and `mirror.23m.com`, seconds apart in one run), so this verification covers the redirector, **not** any particular mirror. A single broken mirror is invisible here and would reach the user as the forever-spinning dialog. Weakest link in the catalogue — if an install test fails on Fedora, suspect the mirror before the entry.
  - **GitHub release assets 302 to signed `release-assets.githubusercontent.com` URLs with ~1 h expiry.** The canonical `releases/download/...` URL is what belongs in `images.json`; the resolved URL must never be cached or recorded.
  - **Rocky's `.latest` alias is real** — proven from the gzip headers of the bytes actually served (`Rocky-WSL-Base.x86_64-10.2.0.wsl`, `…-9.8.0.wsl`), not from the directory listing.
  - Caveat carried forward: reachability ≠ usability. Nothing here says a distro boots to something usable (no init, no default user, no repos on unregistered SLE) — that stays the install-test task's call.

- [ ] Rewrite the repo copy of `images.json`:
  - Keep the existing flat `"Name": "url"` schema and the app's expectations exactly — this file is a fallback for a live CDN payload, so a schema change would break older clients
  - Drop every EOL entry (Ubuntu 16.04/18.04 if past ESM-free support, 19.04, 21.04, Fedora 36/37, Debian 10, SLES 12) and every entry still served from this project's 2022 GitHub release once an official replacement exists
  - Order entries so the most useful appear first (current LTS/stable at the top of each family)
  - Preserve the file's existing formatting style (4-space indent, no trailing newline change) so the diff stays readable

- [ ] Write the CDN handoff note at `Working/cdn-upload.md`:
  - State plainly that the runtime source is `https://n8n.aachen.dev/webhook/cdn/images.json` and that the repo copy is only the bundled fallback
  - Include the exact final JSON payload to upload, and a one-line `curl` command to verify the CDN afterwards
  - Note the date and which entries changed, so the CDN and repo copies can be compared later

- [ ] Install-test the catalogue by clicking through the running app, not by reasoning about it:
  - Launch with `.maestro/tools/launch.ps1`, open the create-instance screen, and install one entry per distro family (at minimum: newest Ubuntu LTS, Debian stable, Alpine, Fedora, Rocky or Alma, openSUSE, Kali)
  - For each: confirm the download starts, the import completes, the distro appears in the list, and `wsl -d <name> cat /etc/os-release` reports the expected release
  - Capture a screenshot of each successful install into `.maestro/screenshots/phase-06/`, and delete each test distro afterwards so the machine is left clean
  - Record every result — including failures and their exact error text — in `Working/catalogue-install-tests.md`

- [ ] Fix what the install tests break. Expect at least one of:
  - An archive format the importer mishandles (fix `archive.dart`/`layer_processor.dart` or drop the entry, and say which you chose and why)
  - A rootfs that imports but has no working init/user setup — verify the distro is actually usable, not merely present
  - Download-progress or error reporting that misreports a failed fetch as success
  - Remove from `images.json` any entry that cannot be made to work, rather than shipping a catalogue entry that fails on click

- [ ] Run `flutter test` and `flutter analyze`, fix any fallout from importer changes, then commit the updated `images.json` plus any code fixes on `beta`. In the commit message, state explicitly that the CDN payload still needs to be pushed manually.

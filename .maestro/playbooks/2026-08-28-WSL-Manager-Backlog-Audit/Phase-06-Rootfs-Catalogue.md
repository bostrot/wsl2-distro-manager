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

- [x] Rewrite the repo copy of `images.json`:
  - Keep the existing flat `"Name": "url"` schema and the app's expectations exactly — this file is a fallback for a live CDN payload, so a schema change would break older clients
  - Drop every EOL entry (Ubuntu 16.04/18.04 if past ESM-free support, 19.04, 21.04, Fedora 36/37, Debian 10, SLES 12) and every entry still served from this project's 2022 GitHub release once an official replacement exists
  - Order entries so the most useful appear first (current LTS/stable at the top of each family)
  - Preserve the file's existing formatting style (4-space indent, no trailing newline change) so the diff stays readable

  **Done 2026-08-28** → `images.json`. **22 entries → 19**, 17 old keys dropped, 5 carried
  unchanged (Ubuntu 26.04/24.04/22.04, Debian 13/12 — same URL as before, so no re-key),
  14 new. Every URL is the one [[catalogue-verification]] §2 cleared, and each was
  re-`curl`ed after writing: **19/19 → 200, and all 19 `Content-Length` values match the
  verification table byte-for-byte**, which is what proves the transcription rather than
  the vendor. Schema, formatting and file ending are unchanged: flat `"Name": "url"`
  strings, 4-space indent, CRLF, closing `}` with no trailing newline (`tail -c 16 | xxd`
  before and after). `flutter test test/app_test.dart` passes, including
  `getDistroLinks returns distros`.

  Decisions worth recording:
  - **`Rocky Linux 9` had to be re-keyed — [[catalogue-candidates]] §12 missed it.** That
    doc asserts every proposed key obeys rule 10, but `Rocky Linux 9` is an existing key
    in the old file pointing at the 2023 `sig-cloud-instance-images` layer, and the
    proposal reused it verbatim for the new `dl.rockylinux.org` alias. Per
    [[catalogue-constraints]] rule 3/10 that leaves anyone who already installed Rocky 9
    importing the 9.1.20230215 rootfs out of the on-disk cache forever, with no
    invalidation. Shipped as **`Rocky Linux 10.2`** / **`Rocky Linux 9.8`** — the builds
    verification §7.3 read out of the gzip headers of the bytes actually served. Symmetric,
    collision-free against both `Rocky Linux 9` and `Rocky Linux 9.6`, and it matches the
    file's own precedent (`Rocky Linux 9.6` was already a point-release key). Cost: the
    label can lag the `.latest` alias by a point release. That is acceptable and arguably
    right — bumping the key on each catalogue refresh is precisely what invalidates the
    stale download cache, and Ubuntu's `24.04` key over a `/current/` path that serves
    24.04.4 already carries the same lag.
  - The other three re-keys the constraints doc demanded are in: `OpenSUSE` →
    `OpenSUSE Tumbleweed` + `OpenSUSE Leap 16.0`, `Kali Linux` → `Kali Linux 2026.2`,
    `SLES 15` → `SLES 15 SP7` (+ `SLES 16.0`). Verified mechanically, not by eye: zero
    keys in the new file collide with an old key under a changed URL, and zero keys
    contain `:` or a Windows filename metacharacter.
  - **Order is the §12 order, unchanged** — Ubuntu, Debian, Alpine, Fedora, Rocky,
    AlmaLinux, openSUSE, SLES, Kali, Arch, newest first within each family. Per
    [[catalogue-constraints]] §2.3 file order *is* display order, so this is the real UX
    change: the create box now opens on Ubuntu 26.04 instead of an EOL wall.
  - **Every 2022 `v0.6.1` release asset is gone** (Debian 10, Kali, OpenSUSE, SLES 15,
    SLES 12) and so are both `v1.4.0` Fedora tarballs — the catalogue no longer serves a
    single byte from this project's own GitHub releases. Both remaining
    `raw.githubusercontent.com` URLs (Debian 13/12) are the *debuerreotype* `dist-amd64`
    branch tips, not build-pinned tags, and §7.2 proved they are plain single-layer
    rootfs blobs.
  - **SLES 12 is dropped with no replacement** and none should be sought —
    [[catalogue-candidates]] §11 established SUSE publishes nothing official for it.
    Ubuntu 20.04 and 18.04 are likewise dropped rather than re-sourced (ESM-only /
    long EOL), which goes one step past the brief's "18.04 if past ESM-free support".
  - Untouched on purpose: `Ubuntu 25.10` was dropped even though it is not EOL until
    Jul 2026, per §11 — it will rot inside this catalogue's refresh cycle.

  > [!WARNING]
  > **This changes the bundled fallback only.** The app fetches
  > `https://n8n.aachen.dev/webhook/cdn/images.json` first (`constants.dart:22`) and only
  > falls back to this asset when that request fails or returns a non-map
  > (`app.dart:82-99`). Until the maintainer uploads this payload to the CDN, **no user
  > sees any of it** — every online client keeps getting the old 22-entry list with the
  > dead 2022 assets. The handoff note is the next task.

- [x] Write the CDN handoff note at `Working/cdn-upload.md`:
  - State plainly that the runtime source is `https://n8n.aachen.dev/webhook/cdn/images.json` and that the repo copy is only the bundled fallback
  - Include the exact final JSON payload to upload, and a one-line `curl` command to verify the CDN afterwards
  - Note the date and which entries changed, so the CDN and repo copies can be compared later

  **Done 2026-08-28** → `Working/cdn-upload.md`. The note was written against a live
  probe of the endpoint rather than against the assumption in the previous task, and
  that probe found something that changes the framing of this whole phase:

  - **The CDN endpoint is not stale — it is broken.**
    `https://n8n.aachen.dev/webhook/cdn/images.json` answers **HTTP 200,
    `application/json; charset=utf-8`, `Transfer-Encoding: chunked`, and a
    zero-byte body.** Six requests over ~90 s in four shapes (plain, `Accept:
    application/json`, `--compressed`, `--http1.0`, custom Dart UA, headers-only):
    all 200, all 0 bytes.
  - **Traced through dio 5.9.0, not guessed**: `sync_transformer.dart:63-76` sets
    `response = null` for a JSON content type with zero bytes, so `response.data`
    is `null`, the `statusCode < 300` guard passes, and `jsonData.forEach(...)`
    (`app.dart:71`) throws `NoSuchMethodError` into the bare `catch (e)`. Every
    online client therefore **already** falls through to its own bundled
    `images.json`. This corrects the warning left on the rewrite task: users are not
    "getting the old 22-entry list from the CDN", they are getting whatever list
    shipped in their installer. Same visible outcome, different cause — and it means
    the maintainer has to *repair* the endpoint, not merely refresh it.
  - The note therefore lists all seven conditions the endpoint must satisfy
    (status, JSON content type, **non-empty body**, top-level object, string values,
    preserved key order, key charset) — each one traced to the line of code that
    breaks, because every one of them fails silently into the fallback.
  - **The embedded payload was verified against the file, not transcribed by eye**:
    the fenced JSON block in the note canonically re-encodes to bytes identical to
    `images.json` (`sha256 97db5b08…`, 2263 B minified; the committed file is
    `f5ec7818…`, 2398 B, CRLF, no trailing newline). Both fingerprints are recorded
    in the note so a later CDN-vs-repo comparison is one command.
  - **Both verification commands were actually run.** The required one-liner
    (`curl -sS -w '…bytes=%{size_download}'`) prints
    `[status=200 type=application/json; charset=utf-8 bytes=0]` today — it catches
    the live failure, which a status-code-only check would not. The stricter
    order-preserving PowerShell comparison was run too and correctly reports
    `MISMATCH`. The `jq` variant is included but flagged in the note as **not run**
    (`jq` is not installed on this machine).
  - Change baseline is stated honestly as the **previous repo copy** (`2970c85^`),
    not the CDN's content — the CDN's last-good payload is unreadable, so it is not
    reconstructed. Diff computed mechanically via
    `Working/phase-06/diff_catalogue.dart`: **17 removed, 14 added, 5 kept with
    unchanged URLs**, each with its reason.

  > [!IMPORTANT]
  > **Nothing in phase 06 has reached a user, and cannot until the maintainer
  > uploads this payload manually.** No attempt was made to write to the endpoint
  > from here — publishing to third-party infrastructure is the maintainer's call.

- [x] Install-test the catalogue by clicking through the running app, not by reasoning about it:
  - Launch with `.maestro/tools/launch.ps1`, open the create-instance screen, and install one entry per distro family (at minimum: newest Ubuntu LTS, Debian stable, Alpine, Fedora, Rocky or Alma, openSUSE, Kali)
  - For each: confirm the download starts, the import completes, the distro appears in the list, and `wsl -d <name> cat /etc/os-release` reports the expected release
  - Capture a screenshot of each successful install into `.maestro/screenshots/phase-06/`, and delete each test distro afterwards so the machine is left clean
  - Record every result — including failures and their exact error text — in `Working/catalogue-install-tests.md`

  **Done 2026-08-28** → `Working/catalogue-install-tests.md`; 22 screenshots in
  `.maestro/screenshots/phase-06/`, 86 more plus the four driver scripts in
  `Working/phase-06/install/`. **All 19 catalogue entries were installed, not the
  7 the brief asks for as a minimum — 19 offered, 19 installed, 0 failures.** The
  extra 12 cost ~40 s each and close the "untested entries" gap the next task
  would otherwise inherit. Every one was selected from the app's own suggestion
  dropdown, imported, verified from *inside* the distro, screenshotted and deleted.

  - **`-Mode exe` would have tested the wrong file.** The built binary's bundled
    asset (`build\windows\x64\runner\{Release,Debug}\data\flutter_assets\images.json`)
    is still the 2 732-byte, 2026-04-14, 22-entry catalogue. Launched with
    `-Mode run` so the debug bundle carries the payload this phase actually wrote.
  - **The list the app rendered is the new one** (screenshot `00-catalogue-list.png`:
    Ubuntu 26.04 first, EOL wall gone) — and it arrived through the *bundled-asset
    fallback*, re-confirming [[cdn-upload]]: the CDN still answers 200 with a
    zero-byte body. What was install-tested is exactly the payload still waiting
    to be pushed.
  - **Release identity was read from inside each distro, not inferred.** This
    settles three earlier claims: Rocky's `.latest` aliases really do serve
    **10.2 (Red Quartz)** and **9.8 (Blue Onyx)** — the builds
    [[catalogue-verification]] §7.3 read out of gzip headers, so the re-keying done
    in the rewrite task matches reality; AlmaLinux serves 10.2 / 9.8; and Ubuntu's
    `/current/` paths lag their keys exactly as predicted (24.04.**4**, 22.04.**5**).
  - **Content-sniffing is now proven on the real catalogue, not on synthetic
    payloads.** 5 `.tar.xz` + 4 `.tar.gz` + 7 gzip `.wsl` + 3 xz `.wsl`, every one
    saved as `<key>.tar.gz` (`wsl.dart:1355`) and every one imported. The extension
    the app writes is wrong for **15 of 19** entries and never mattered — so the
    next task must **not** "fix" this by inferring format from the URL suffix.
  - **The Arch substitution is verified.** `archlinux.wsl` (the purpose-built WSL
    image, not the `root.x86_64/`-prefixed bootstrap tarball
    [[catalogue-constraints]] §1.3 rejected) imports in 47.9 s with `pacman` present.
  - **Both risks the earlier tasks flagged failed to materialise.** Fedora's
    per-request mirror redirector — "the weakest link" — was clean across three
    installs. And "no repos on an unregistered SLE" is **false for this artifact**:
    `SLES 15 SP7` ships `SLE_BCI` enabled and `zypper --non-interactive refresh`
    exits 0. Fedora 44's `dnf makecache` exits 0 against three repos. Both were
    re-installed specifically to probe this, then deleted.
  - **Every distro imports root-only with no default user and no `/etc/wsl.conf`** —
    normal `wsl --import` behaviour, and *Standardbenutzer erstellen* was left off
    on purpose so the raw import was what got tested. This is the direct input to
    the next task's "imports but has no working init/user setup" bullet: the answer
    is all 19, by design, so the question there is whether the app's own
    user-creation path still works — not whether the catalogue is broken.
  - **Two defects confirmed live**, both already logged for the fix task: the temp
    file really is written as `Ubuntu 26.04.tar.gz.tmp.tmp`, and the un-awaited
    `file.rename()` at `wsl.dart:1377` **did not bite in 21 downloads** — which is
    luck on a warm NTFS volume, not safety. Still a one-word fix.
  - Noticed while measuring, out of scope, recorded so it is not lost: with no
    `DistroPath` set, instances land **directly in the Roaming profile root**
    (`%APPDATA%\<Name>`, proven from the `Lxss` registry) while downloads go one
    level deeper into `%APPDATA%\distros\`.
  - Machine left clean: back to the two pre-existing distros, no `Test*`
    registration, no `Test*` directory, download cache untouched apart from the
    entries this run added and removed.
  - Explicitly **not** covered (so the next task does not over-read the result):
    the user-creation toggle, the app's own delete UI, the other five source types,
    warm-cache reuse, and the forever-spinning-dialog failure path
    ([[catalogue-constraints]] §1.5) — nothing failed, so it was never reproduced.
    Cleanup used `wsl --unregister` directly, so this run says nothing about the
    app's delete flow.

- [ ] Fix what the install tests break. Expect at least one of:
  - An archive format the importer mishandles (fix `archive.dart`/`layer_processor.dart` or drop the entry, and say which you chose and why)
  - A rootfs that imports but has no working init/user setup — verify the distro is actually usable, not merely present
  - Download-progress or error reporting that misreports a failed fetch as success
  - Remove from `images.json` any entry that cannot be made to work, rather than shipping a catalogue entry that fails on click

- [ ] Run `flutter test` and `flutter analyze`, fix any fallout from importer changes, then commit the updated `images.json` plus any code fixes on `beta`. In the commit message, state explicitly that the CDN payload still needs to be pushed manually.

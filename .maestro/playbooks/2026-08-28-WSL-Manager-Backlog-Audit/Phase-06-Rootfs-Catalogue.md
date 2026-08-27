# Phase 06: Re-source and Verify the Rootfs Catalogue

`images.json` is the distro catalogue offered in the create flow, and it has rotted. It still lists EOL releases (Ubuntu 16.04, 19.04, 21.04, Fedora 36/37, Debian 10, SLES 12), serves Debian and Rocky from `raw.githubusercontent.com` links pinned to build-specific tags, and serves Kali, openSUSE and SLES from tarballs attached to this project's own v0.6.1 GitHub release in 2022. This phase re-sources every entry from official vendor pages, verifies each URL actually resolves to a usable rootfs, updates the repo copy, and install-tests the survivors by clicking through the running app.

**Important:** at runtime the catalogue is fetched from `https://n8n.aachen.dev/webhook/cdn/images.json`, with the bundled `images.json` only as a fallback. This phase updates the **repo copy only**. The updated payload must be pushed to the CDN by the maintainer afterwards — make that unmistakable in the output rather than assuming it happens automatically.

## Tasks

- [ ] Establish the constraints before sourcing anything:
  - Read `lib/api/archive.dart` and `lib/api/layer_processor.dart` and record which archive formats the app can actually import (`.tar`, `.tar.gz`, `.tar.xz`, `.wsl`, `.zst`?) — do not add a URL in a format the importer cannot handle
  - Read how `images.json` is consumed (`grep -rn "images.json\|cdn/images" lib/`) and confirm the exact schema: flat `"Name": "url"` map, ordering behaviour, and whether the name is parsed anywhere
  - Write both findings to `.maestro/playbooks/2026-08-28-WSL-Manager-Backlog-Audit/Working/catalogue-constraints.md`

- [ ] Re-source candidate rootfs URLs from official vendor sources only, and record each source page URL alongside each candidate in `Working/catalogue-candidates.md`:
  - Microsoft's own distribution manifest (`microsoft/WSL` repo, `distributions/DistributionInfo.json` and any newer manifest it points to) — this is the authoritative list of WSL-ready distro images and should drive the core entries
  - Ubuntu: `cloud-images.ubuntu.com` (WSL rootfs variants where published), supported releases only
  - Debian: the official Debian container artifacts source, current stable and oldstable only
  - Alpine: `dl-cdn.alpinelinux.org` minirootfs, current stable branches
  - Fedora: the official Fedora download infrastructure Container-Base image, supported releases only
  - openSUSE / SLES: `download.opensuse.org` and SUSE's official registry-backed artifacts
  - Rocky / AlmaLinux: `dl.rockylinux.org` and `repo.almalinux.org` container base images
  - Kali: Kali's own download infrastructure (`kali.download`), not a third-party mirror
  - Arch: the official bootstrap tarball, only if its format is importable per the constraints task

- [ ] Verify every candidate URL mechanically before it goes anywhere near the catalogue:
  - `curl -sIL --max-time 60` each URL and record final status, `Content-Type`, `Content-Length` and the redirect chain
  - Reject anything that 404s, redirects to an HTML page, or is implausibly small for a rootfs
  - For each survivor, download the first few MB and confirm the magic bytes match the extension (gzip/xz/zstd/tar)
  - Tabulate results in `Working/catalogue-verification.md` with a pass/fail column and the reason for every rejection

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

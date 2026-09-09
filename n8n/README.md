# CDN workflows

Two n8n workflows that sit between the app and GitHub, so the app makes one
cached request where it used to make many uncached ones.

Import each file in n8n with **Workflows → … → Import from File**, then
**activate** it. Static data — the cache — is only kept for an active
workflow triggered through its webhook, so an inactive workflow re-fetches
on every call.

| File | Serves | Caches from | TTL |
|---|---|---|---|
| `cdn-images-json.workflow.json` | `GET /webhook/cdn/images.json` | `raw.githubusercontent.com/.../wsl2-distro-manager/main/images.json` | 15 min |
| `cdn-scripts-json.workflow.json` | `GET /webhook/cdn/scripts.json` | `api.github.com` listing + one `info.yml` per folder | 10 min |

## Why

**`cdn/images.json`** already existed and was answering `200` with an empty
body (2026-09-09). The app read that as "no data" and fell back to the
`images.json` bundled at build time, so distro URLs silently froze at
whatever shipped. The replacement serves the last good copy when GitHub is
unreachable, and only fails when the cache is cold *and* upstream is down.

**`cdn/scripts.json`** is new. The Community screen listed the `scripts/`
folder and then fetched `info.yml` for each of its 80 entries, one after
another — 81 sequential requests before the first row appears. The listing
call also spends the anonymous `api.github.com` budget, which is 60 requests
an hour for everyone behind one address. The workflow does that walk once per
TTL and hands the app a single document.

## Response shape

```json
{
  "generatedAt": "2026-09-09T18:00:00Z",
  "source": "https://github.com/bostrot/wsl-scripts",
  "count": 80,
  "scripts": [{ "name": "redis", "info": "name: redis\ndescription: ...\n" }]
}
```

`info` is the `info.yml` text verbatim. The app parses it with the same YAML
code it uses for the per-folder path, so this endpoint never becomes a second
definition of what a snippet is.

`x-cdn-cache` on the response says `hit`, `miss` or `stale`, which is the
quickest way to tell a cold cache from a dead upstream.

## If a workflow is down

Nothing breaks. `CommunityScripts.list()` falls back to walking the folders,
and `App.getDistroLinks()` falls back to raw GitHub and then to the bundled
file. Both are covered in `test/community_scripts_test.dart`.

## Not included: `updatedAt`

The "updated N days ago" line still costs one `api.github.com` call per
script. It is deliberately left out here: doing it server-side would spend 80
calls of a 60-an-hour anonymous budget per refresh. The app already loads it
in the background, off the render path, and caches each answer for 24 hours.
Moving it here needs a GitHub credential on the n8n side first.

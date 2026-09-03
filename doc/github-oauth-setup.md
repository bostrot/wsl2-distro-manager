# GitHub OAuth setup (snippet sharing)

"Share with community" opens a pull request on `bostrot/wsl-scripts`. It signs
in with GitHub's **device flow**, which needs a client id and no client
secret.

## Client id yes, client secret never

- **Client id** is public information. It travels in every device-flow
  request and is safe to compile into the app or commit to CI config.
- **Client secret must never be in the app.** Anything shipped in a binary
  can be extracted from it, so a secret in a desktop build is a published
  secret. GitHub classes desktop apps as *public clients* for exactly this
  reason, and the device flow takes no secret at all.

So: do not generate a client secret for this app. If one already exists,
leave it unused — its presence is not needed and copying it anywhere is a
leak. A confidential flow (with a secret) would only make sense behind a
server we control, which this app deliberately does not have.

## Creating the app

Two minutes by hand, or drive it with the Claude browser MCP. Either way the
steps and the guardrails are the same.

**Agent instructions (browser MCP):**

1. Ask the user to sign in to GitHub themselves in the browser pane — do not
   type their credentials, and do not use a saved password to log in to an
   account for a task they did not ask for. If a password manager
   integration is available and the user asked for the sign-in, request the
   credential through it rather than handling the value.
2. Navigate to <https://github.com/settings/developers> → **OAuth Apps** →
   **New OAuth App**.
3. Fill in: application name `WSL Manager`, homepage
   `https://wslmanager.com`, authorization callback URL
   `https://wslmanager.com` (device flow never redirects, but the field is
   required).
4. Submit, then on the app's page tick **Enable Device Flow** and save.
5. Copy the **Client ID** only. **Do not click "Generate a new client
   secret".** Report the id back; it is not sensitive.
6. Nothing else on that page needs changing.

## Wiring the id in

```bash
flutter build macos --dart-define=GITHUB_CLIENT_ID=Ov23liXXXXXXXXXXXXXX
```

`kGithubClientId` in `lib/api/github_publish.dart` reads it via
`String.fromEnvironment`. Built without it, sharing is disabled and the
dialog says so instead of failing at the API call
(`GithubPublisher.isConfigured`).

The requested scope is `public_repo` — enough to fork, push a branch and open
a pull request, and nothing more.

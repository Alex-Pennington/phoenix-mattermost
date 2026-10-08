# phoenix-mattermost

This is the corresponding source for the modified Mattermost server running at
**chat.firewood.ltd**. It is offered to that server's users under AGPL-3.0 §13.

## What it is

- **Upstream:** [mattermost/mattermost](https://github.com/mattermost/mattermost), tag
  [`v11.11.1`](https://github.com/mattermost/mattermost/tree/v11.11.1), commit
  `3acb3a7f684d11ccfcec4e5bd11c79f64e3eabf9`. The server source is AGPL-3.0.
- **The modification:** one file, `server/config/client.go`, in
  [`gitlab-sso-team-edition.patch`](gitlab-sso-team-edition.patch).
  - **What upstream does:** Mattermost v11.0 moved the GitLab SSO login flags
    (`EnableSignUpWithGitLab`, `GitLabButtonColor`, `GitLabButtonText`) behind a licence check
    (mattermost/mattermost#33848). At v11.11.1 they sit at `client.go:428-430`, inside
    `if license != nil {` and `if *license.Features.OpenId {`.
  - **What the patch does:** moves those three lines out of the licence block, where v10.11 had
    them. The GitLab OAuth provider itself was never removed from the open-source tree.
- **Not included:** no Source Available code. The binary is built with tags `production` only,
  never `enterprise` or `sourceavailable`, so only `server/enterprise/placeholder.go` compiles.
- **Unchanged:** the webapp, `mmctl` and the rest of the official
  `mattermost/mattermost-team-edition:11.11.1` image.

This is an independent modified build. It is not made or endorsed by Mattermost, Inc.

## Files

| File | Purpose |
|---|---|
| `gitlab-sso-team-edition.patch` | The source change |
| `build.sh` | Clones v11.11.1, applies the patch, builds the server binary in a `golang:<go.mod version>-bookworm` container, builds the image |
| `Dockerfile` | `FROM` the official image pinned by digest, replacing only `/mattermost/bin/mattermost` |
| `test-local.sh`, `test-compose.yml` | Throwaway local stack (own Postgres, 127.0.0.1 only) that checks ping, the client config and the GitLab login redirect, then removes itself |
| `compare-client-config.py` | Diffs two `/api/v4/config/client?format=old` dumps, masking values |

## How to build

You need Docker on linux/amd64 and network access to GitHub, Docker Hub and the Go module proxy.

```
bash build.sh /absolute/path/to/a/scratch/dir
bash test-local.sh /absolute/path/to/another/scratch/dir
```

### What `build.sh` does

1. Clones the tag into a fresh directory with `--depth 1`, and applies the patch with
   `git apply`.
2. Builds `./cmd/mattermost` inside `golang:1.26.7-bookworm` with these settings:
   - `CGO_ENABLED=1`, `-trimpath` and `-tags production`, as in upstream's
     `server/build/release.mk`;
   - `BuildNumber=11.11.1-phoenix1` and `BuildEnterpriseReady=false`.

   Upstream's `server/Makefile` adds the `sourceavailable` tag to dev builds, so the build number
   must never be `dev`.
3. Builds `phoenix/mattermost-team-edition:11.11.1-phoenix1` from `Dockerfile`, locally. It
   pushes nothing.

### Overrides for another release

Set these environment variables:

- `MM_VERSION`
- `PHOENIX_REV`
- `BASE_DIGEST`, the digest of the official image for that version.

Check first that the patch still applies. The script fails if it does not.

## Configuring GitLab SSO

Set `MM_GITLABSETTINGS_*`, or `GitLabSettings` in `config.json`. The v11 admin console no
longer shows the page.

Leave `GitLabSettings.Scope` empty. A scope containing `openid` routes login to the OpenID
provider, which Team Edition does not include.

## Known differences from the official binary

- **Build identity:** `BuildNumber`, `BuildDate` and `BuildHashEnterprise` differ.
- **No Giphy key:** Mattermost's CI links a Giphy SDK key into official builds. This build has
  none, so the GIF picker does not work unless `ServiceSettings.GiphySdkKey` is set.

## Licence

The patch and scripts in this repository are released under the GNU Affero General Public
License v3.0; see [`LICENSE`](LICENSE). Mattermost itself is covered by the terms in the upstream
repository's `LICENSE.txt`. "Mattermost" is a trademark of Mattermost, Inc.

# Phoenix Nest Mattermost Team Edition: the stock image, pinned by digest,
# with only the server binary swapped for the patched AGPL build.
# Built by build.sh; the build context is the dir holding the binary.
ARG BASE_IMAGE=mattermost/mattermost-team-edition:11.11.1@sha256:6ad5912b45875ef2fafc41886b5a70a3ec1b6c17ec706e0492566e8a2fd8aa85
FROM ${BASE_IMAGE}

COPY --chown=2000:2000 mattermost /mattermost/bin/mattermost

LABEL org.opencontainers.image.title="phoenix/mattermost-team-edition" \
      org.opencontainers.image.description="Mattermost Team Edition with GitLab SSO login flags restored (gitlab-sso-team-edition.patch)" \
      org.opencontainers.image.licenses="AGPL-3.0-only"

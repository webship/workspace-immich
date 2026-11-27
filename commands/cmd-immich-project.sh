#!/usr/bin/env bash

# workspace-name: Immich (photo library)

# Installed by the Immich plugin (plugins.sh --install immich); __WORKSPACE__ is the workspace it was installed into.
#
# Make an Immich library from its release (v3.4.2): its server, its Postgres with the vector extensions and valkey,
# each pinned by digest, machine learning off, served from containers of their own, the photos in the project's
# library/ folder. With --install the library is started and checked; with --add-users its accounts are made through
# its API, past the first-run wizard. The workspace is container-based (DDEV by default, at https://<name>.ddev.site);
# --runtime docker, podman or kubernetes builds it on Docker Compose, Podman or a Kubernetes cluster instead, at the
# address that runtime gives.

# Bootstrap.
# Find the workspace tooling from this script, so a fresh clone needs no setup.
WORKSPACE_SCRIPTS="${WORKSPACE_SCRIPTS:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../core/scripts" && pwd)}";
source ${WORKSPACE_SCRIPTS}/bootstrap.sh || exit 1 ;

# Load workspace settings.
eval $(parse_yaml ${WORKSPACE_CONFIG}/workspace.__WORKSPACE__.settings.yml);

# Distribution.
distribution_name="immich";
distribution_title="Immich";
distribution_webroot="library";

ARGPARSE_DESCRIPTION="Build an ${distribution_title} library in __WORKSPACE__"
# The args file comes with the plugin: core/scripts/plugins/immich/ is where plugins.sh --install puts it.
source ${WORKSPACE_SCRIPTS}/plugins/immich/args/arg-immich.sh || exit 1 ;

shift $#;

immich_build ;

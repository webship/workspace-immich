#!/usr/bin/env bash

argparse "$@" <<ARGEOF || exit 1
parser.add_argument('PROJECT_NAME',
                    help='The name of the project: its folder, and its project on the container runtime.')
parser.add_argument('--runtime',
                    dest='RUNTIME',
                    default="_none_",
                    choices=['ddev', 'docker', 'podman', 'kubernetes'],
                    help='The container runtime to build on: ddev (the default, or container.runtime of settings.yml), docker (Docker Compose), podman or kubernetes.')
parser.add_argument('-i', '--install',
                    action='store_true',
                    default=False,
                    help="Start the library (its server, its Postgres and valkey, machine learning off) and check that it answers at its address: https://<name>.ddev.site on DDEV, a port of this machine on Docker Compose and Podman, a port of the node on Kubernetes.")
parser.add_argument('-a', '--add-users',
                    action='store_true',
                    default=False,
                    help="Make the default accounts too, through the library's API: its first admin admin@example.com and the user user@example.com, both past the first-run wizard (cmd-tools-add-users.sh <name> immich does it later).")
parser.add_argument('-l', '--launch',
                    action='store_true',
                    default=False,
                    help='Open the library in a browser when it is ready.')
ARGEOF

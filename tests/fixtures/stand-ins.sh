# Stand-ins for the commands the Immich plugin's functions run, for its tests: ddev (and what it runs in the library's
# containers: curl to the server, pg_dump, psql), docker, podman and the core's helpers, each call written to $LOG.
# Nothing here reaches a container or the network.
#   FAIL          dump | short | restore | swap | signup | adminonboarding: that step fails (short: a dump cut before its end)
#   USER_THERE    yes: the library has the user already
#   SIGNUP        400: the library has its admin already

trim_project_name() { :; }
drop_database() { echo "drop_database" >> "${LOG}" ; }
ddev_up() { ddev "$@" ; }
# The core's database hook (webship/workspace#937, core 1.0.42): its presence is what the builder asks for.
export_project_db() { echo "export_project_db $*" >> "${LOG}" ; }

# The library's API, as the server would answer the plugin's curl: "status" on the first line, the body after it.
immich_answer() {
  local method="$1" path="$2" body="$3" ;
  case "${method} ${path}" in
    "POST /api/auth/admin-sign-up") [ "${FAIL:-}" = signup ] && { printf '500\n{"message":"down"}\n' ; return ; } ; printf '%s\n{}\n' "${SIGNUP:-201}" ;;
    "POST /api/auth/login") local who ; who="$(printf '%s' "${body}" | python3 -c 'import json, sys; print(json.load(sys.stdin)["email"])')" ; printf '201\n{"accessToken":"tok-%s","userEmail":"%s"}\n' "${who}" "${who}" ;;
    "GET /api/admin/users") if [ "${USER_THERE:-}" = yes ] ; then printf '200\n[{"id":"u-1","email":"user@example.com"},{"id":"a-1","email":"admin@example.com"}]\n' ; else printf '200\n[{"id":"a-1","email":"admin@example.com"}]\n' ; fi ;;
    "POST /api/admin/users") printf '201\n{"id":"u-1"}\n' ;;
    "PUT /api/admin/users/u-1") printf '200\n{}\n' ;;
    "PUT /api/users/me/onboarding") printf '200\n{"isOnboarded":true}\n' ;;
    "GET /api/system-config") printf '200\n{"newVersionCheck":{"enabled":true},"map":{"enabled":true},"other":1}\n' ;;
    "PUT /api/system-config") echo "system-config ${body}" >> "${LOG}" ; printf '200\n{}\n' ;;
    "POST /api/system-metadata/admin-onboarding") [ "${FAIL:-}" = adminonboarding ] && { printf '403\n{"message":"Forbidden"}\n' ; return ; } ; printf '204\n' ;;
    *) printf '404\n{"message":"not found"}\n' ;;
  esac
}

ddev() {
  echo "ddev $*" >> "${LOG}" ;
  case "$*" in
    *"curl -s -o /tmp/immich-api.out"*)
      local method path body="" ;
      method="$(printf '%s' "$*" | sed -n 's/.* -X \([A-Z]*\) .*/\1/p')" ;
      path="$(printf '%s' "$*" | sed -n 's#.* -X [A-Z]* http://[^/]*\(/[^ ]*\) .*#\1#p')" ;
      case "$*" in *"--data-binary @-"*) body="$(cat)" ; echo "body ${method} ${path} ${body}" >> "${LOG}" ;; esac ;
      immich_answer "${method}" "${path}" "${body}" ;;
    *"pg_dump -U postgres --clean --if-exists immich"*)
      [ "${FAIL:-}" = dump ] && return 1 ;
      printf -- '--\n-- PostgreSQL database dump\n--\n\nCREATE TABLE public.asset (id uuid);\n' ;
      [ "${FAIL:-}" = short ] || printf -- '\n--\n-- PostgreSQL database dump complete\n--\n\n' ;;
    *"psql -U postgres -d immich_restore"*) cat > /dev/null ; [ "${FAIL:-}" = restore ] && return 1 ;;
    *"ALTER DATABASE immich RENAME TO immich_before_restore"*) [ "${FAIL:-}" = swap ] && return 1 ;;
  esac
  return 0 ;
}

docker() { echo "docker $*" >> "${LOG}" ; return 0 ; }
podman() { echo "podman $*" >> "${LOG}" ; return 0 ; }

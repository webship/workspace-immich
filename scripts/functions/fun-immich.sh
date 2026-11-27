#!/usr/bin/env bash

# Immich for the Webship Workspace: make an Immich library from its release (its server, its Postgres with the vector
# extensions and valkey, each pinned by digest; machine learning off, with no machine-learning container), serve it
# from containers of its own, back its database up and restore it, and wire the Immich step pack into the testing
# setup of that library.
#
# Placed by `plugins.sh --install immich` in core/scripts/plugins/immich/functions/, where bootstrap sources it after
# the core's own functions. Everything runs in containers, never on the host.
#
# The photos are the project's: <project>/library is the server's /data (IMMICH_MEDIA_LOCATION), so the row's Backup,
# which archives the project's folder, holds them. Its database is Immich's own Postgres 14 with VectorChord: DDEV's
# own database cannot carry those extensions, so DDEV's db is omitted and its own database tools (export-db,
# import-db, snapshot) do not reach this one. The plugin declares the core's database hook instead (webship/workspace
# #937, core 1.0.42): immich_export_db and immich_import_db, the way Immich backs itself up (pg_dump --clean
# --if-exists, gzipped; psql --single-transaction), which the row's Backup and Restore ask first.
#
# The runtimes:
#   - DDEV (the default): a generic project whose web container keeps the mail catcher; the server, Postgres and valkey
#     are services of the project (.ddev/docker-compose.immich.yaml), and the router sends the project's address to
#     the server.
#   - Docker Compose, Podman and Kubernetes (--runtime docker, podman, kubernetes): the core's runtime layer
#     (webship/workspace#841, #900): the server's image as the stack (rt_stack image), its server as the web
#     container's own (rt_serve), Postgres and valkey as services of the project (rt_service).
# Lando and Docksal are not proven for it yet: asked for one, the builder says so and changes nothing.
#
# The names the core's tools look for:
#   set_immich_users          the default accounts                         (cmd-tools-add-users.sh <project> immich)
#   add_immich_users          make them through the library's API          (the same tool, and --add-users)
#   cancel_immich_users       keep them from signing in                    (cmd-tools-cancel-users.sh <project> immich)
#   testing_configure_immich  the step pack in the testing stack           (cmd-tools-testing.sh <project>)
#   immich_is_project, immich_export_db, immich_import_db, immich_db_extension
#                             the database hook                            (the row's Backup and Restore)

# The step pack a library is tested with, and the release line it is required at.
readonly IMMICH_STEPS_PACKAGE='@webship-js/immich-steps';
readonly IMMICH_STEPS_VERSION='^2.0.0';

# Immich's release, and its three images, pinned by digest.
readonly IMMICH_VERSION='v3.4.2';
readonly IMMICH_SERVER_IMAGE='ghcr.io/immich-app/immich-server@sha256:fc880c1bf665b4aab1e74c15e56ab871225989cd546536e6b77e771869af06bd';
readonly IMMICH_POSTGRES_IMAGE='ghcr.io/immich-app/postgres@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23';
readonly IMMICH_VALKEY_IMAGE='docker.io/valkey/valkey@sha256:418652cfb58ef879d4978c33553735d7147016032d5aefaa14c828e611eb9dfd';

# The port the server listens on, the project's folder of photos, and the builder's own folder.
readonly IMMICH_PORT='2283';
readonly IMMICH_LIBRARY='library';
readonly IMMICH_OWN='.webship-immich';

# The extension of the plugin's own dumps: gzipped SQL, the kind Immich's own backups are.
readonly IMMICH_DB_EXTENSION='.sql.gz';

# The runtimes a library is built on.
readonly IMMICH_RUNTIMES='ddev docker podman kubernetes';

# The default accounts, the ones a scenario signs in as: the library's first admin and a user. Accounts are
# configuration, made once on the site; a test suite never creates or deletes one but its "Webship test …" ones.
function set_immich_users() {
  users=(admin user);
  user_admin_name='Webship admin' ; user_admin_mail='admin@example.com' ; user_admin_password='dD.123123ddd' ; user_admin_role='admin' ;
  user_user_name='Webship user' ; user_user_mail='user@example.com' ; user_user_password='dD.123123ddd' ; user_user_role='user' ;
}

# The plugin's own settings (core/config/plugin.immich.settings.yml): whether a library it makes keeps Immich's
# version check ("off" by default here) and its map ("on", Immich's default).
function immich_setting() {
  local key="$1" default="$2" file="${WORKSPACE_CONFIG:-}/plugin.immich.settings.yml" value="" ;
  [ -f "${file}" ] && value="$(sed -n "s/^[[:space:]]*${key}:[[:space:]]*[\"']\{0,1\}\([A-Za-z]*\)[\"']\{0,1\}[[:space:]]*\(#.*\)\{0,1\}$/\1/p" "${file}" | head -1)" ;
  echo "${value:-${default}}" ;
}

# The runtime of the project in this folder, or of a new build (--runtime, else the workspace's setting, else DDEV).
function immich_runtime() {
  if declare -f runtime_of > /dev/null ; then runtime_of ; else echo 'ddev' ; fi
}

# The address of the library in this folder, as its runtime gives it. Asked after `ddev config`.
function immich_url() {
  if declare -f rt_url > /dev/null ; then rt_url ; else echo "https://${PROJECT_NAME}.ddev.site" ; fi
}

# Is this folder a project of the Immich builder? On DDEV it leaves .ddev/config.immich.yaml in it; on another
# runtime it claims the project (`platform: immich` in the x-webship block).
function immich_is_project() {
  local project_path="$1";
  [ -f "${project_path}/.ddev/config.immich.yaml" ] && return 0 ;
  declare -f rt_is_platform > /dev/null && rt_is_platform "${project_path}" immich ;
}

# The service the server runs in (DDEV: its own; another runtime: the web container), and where it is reached from
# the web container.
function immich_server_service() {
  if [ "$(immich_runtime)" = 'ddev' ] ; then echo 'immich-server' ; else echo 'web' ; fi
}
function immich_server_address() {
  if [ "$(immich_runtime)" = 'ddev' ] ; then echo "http://immich-server:${IMMICH_PORT}" ; else echo "http://127.0.0.1:${IMMICH_PORT}" ; fi
}

# A command in the project's Postgres, its input passed on.
function immich_pg() {
  ddev exec -s postgres -d / "$@" ;
}

# The library's settings (.webship-immich/env) and Postgres's (.webship-immich/postgres.env), which only you can read:
# a database password of the project's own, made once and kept on later builds; machine learning off; where the
# photos are in the server's container.
function immich_write_env() {
  local project_path="$1" media="$2" own dbpass ;
  own="${project_path}/${IMMICH_OWN}" ;
  mkdir -p -m 700 "${own}" || return 1 ;
  dbpass="$(sed -n 's/^POSTGRES_PASSWORD=//p' "${own}/postgres.env" 2> /dev/null)" ;
  [ -n "${dbpass}" ] || dbpass="$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)" ;
  ( umask 077
    cat > "${own}/postgres.env" <<ENVEOF
# Postgres of this Immich library, made by the Immich builder of the workspace. Read by its container; never printed.
POSTGRES_PASSWORD=${dbpass}
POSTGRES_USER=postgres
POSTGRES_DB=immich
POSTGRES_INITDB_ARGS=--data-checksums
ENVEOF
    cat > "${own}/env" <<ENVEOF
# The settings of this Immich library, made by the Immich builder of the workspace. Read by the server; never printed.
DB_HOSTNAME=postgres
DB_USERNAME=postgres
DB_PASSWORD=${dbpass}
DB_DATABASE_NAME=immich
REDIS_HOSTNAME=valkey
IMMICH_MACHINE_LEARNING_ENABLED=false
IMMICH_MEDIA_LOCATION=${media}
IMMICH_PORT=${IMMICH_PORT}
TZ=Etc/UTC
ENVEOF
  ) ;
}

# The library's settings put in the environment as a compose env file is read: each KEY=value line as it is.
function immich_env_line() {
  local env_file="$1" ;
  echo "while IFS= read -r l ; do case \"\$l\" in ''|'#'*) ;; *=*) export \"\${l%%=*}=\${l#*=}\" ;; esac ; done < ${env_file}" ;
}

# The command the web container runs on another runtime: the settings, Postgres waited for, then Immich's own start.
function immich_serve_line() {
  local env_file="$1" ;
  echo "$(immich_env_line "${env_file}") && until (exec 3<>/dev/tcp/postgres/5432) 2> /dev/null ; do sleep 2 ; done && cd /usr/src/app && exec start.sh" ;
}

# What DDEV is told: the server's service, Postgres's and valkey's (the plugin's docker-compose.immich.yaml), their
# images in .env, and the mark that makes it a project of this builder.
function immich_write_ddev_config() {
  local project_path="$1" from="${WORKSPACE_SCRIPTS}/plugins/immich" ;
  if [ ! -f "${from}/docker-compose.immich.yaml" ] ; then
    echo "docker-compose.immich.yaml is not in ${from}: install the plugin (plugins.sh --install immich)." ;
    return 1 ;
  fi
  mkdir -p "${project_path}/.ddev" || return 1 ;
  cp "${from}/docker-compose.immich.yaml" "${project_path}/.ddev/docker-compose.immich.yaml" || return 1 ;
  printf 'IMMICH_SERVER_IMAGE=%s\nIMMICH_POSTGRES_IMAGE=%s\nIMMICH_VALKEY_IMAGE=%s\n' "${IMMICH_SERVER_IMAGE}" "${IMMICH_POSTGRES_IMAGE}" "${IMMICH_VALKEY_IMAGE}" > "${project_path}/.ddev/.env" || return 1 ;
  cat > "${project_path}/.ddev/config.immich.yaml" <<YAMLEOF
# An Immich library in this project (Immich ${IMMICH_VERSION}): its services (docker-compose.immich.yaml), their
# images in .env, its settings in ../${IMMICH_OWN}/, its photos in ../${IMMICH_LIBRARY}/. Written by the Immich builder
# of the workspace; build again rather than editing by hand.
YAMLEOF
}

# On another runtime than DDEV: the plugin's claim, the server's image as the stack, Postgres and valkey as services
# of the project, and Immich's start as the web container's own.
function immich_runtime_config() {
  rt_claim immich || return 1 ;
  rt_stack image "${IMMICH_SERVER_IMAGE}" || return 1 ;
  # The server's image starts through `tini -- /bin/bash -c` (its ENTRYPOINT), which would take the web container's own
  # command for a script and exit at once: the project's web image clears it, so the runtime's start runs as it is.
  # Its HEALTHCHECK asks the server at once, with no time to start: on Podman a first answer before the server listens
  # marks the container unhealthy and stops the start (seen on a real build). The same check, given time to start.
  printf '%s\n' "# Immich's image starts through tini -- /bin/bash -c (its ENTRYPOINT): cleared, so the web container's own command runs." 'ENTRYPOINT []' \
    "# Immich's own healthcheck, given time to start (on Podman a first failure would mark the container unhealthy)." \
    'HEALTHCHECK --start-period=300s --interval=10s --timeout=10s --retries=3 CMD immich-healthcheck' \
    | rt_web_build immich || return 1 ;
  rt_service postgres "${IMMICH_POSTGRES_IMAGE}" --port 5432 --env-file "${IMMICH_OWN}/postgres.env" --volume /var/lib/postgresql/data || return 1 ;
  rt_service valkey "${IMMICH_VALKEY_IMAGE}" --port 6379 || return 1 ;
  rt_serve "${IMMICH_PORT}" "$(immich_serve_line "/var/www/html/${IMMICH_OWN}/env")" ;
}

# Wait until the server answers its ping, asked from the web container.
function immich_wait() {
  local attempt url ;
  url="$(immich_server_address)/api/server/ping" ;
  for attempt in $(seq 1 150) ; do
    if ddev exec "curl -fsS -o /dev/null ${url}" < /dev/null > /dev/null 2>&1 ; then return 0 ; fi
    sleep 2 ;
  done
  echo "The library does not answer its ping (${url})." ;
  return 1 ;
}

# A request to the library's API from the web container: METHOD PATH [TOKEN], a JSON body on the input (or none);
# the answer's status on the first line, its body after it.
# The answer is read to its end by the caller (sed -n 1p for the code, never head -1): a reader that stops at the first
# line closes the pipe on the exec, which then fails (Podman's compose says "Error: executing …" for it).
function immich_api() {
  local method="$1" path="$2" token="${3:-}" data='--data-binary @-' ;
  [ "${method}" = GET ] && data='' ;
  ddev exec "curl -s -o /tmp/immich-api.out -w '%{http_code}\\n' -X ${method} $(immich_server_address)${path} -H 'Content-Type: application/json' ${token:+-H 'Authorization: Bearer ${token}'} ${data} && cat /tmp/immich-api.out && rm -f /tmp/immich-api.out" ;
}

# The access token of an account of the default accounts, from the library's sign-in.
function immich_token() {
  local mail="$1" password="$2" answer ;
  answer="$(python3 -c 'import json, sys; print(json.dumps({"email": sys.argv[1], "password": sys.argv[2]}))' "${mail}" "${password}" | immich_api POST /api/auth/login)" ;
  [ "$(echo "${answer}" | head -1)" = '201' ] || { echo "${mail} could not sign in: $(echo "${answer}" | tail -n +2 | head -c 300)" >&2 ; return 1 ; } ;
  echo "${answer}" | tail -n +2 | python3 -c 'import json, sys; print(json.load(sys.stdin)["accessToken"])' ;
}

# The library's own settings a test library starts with: the version check off (no call out, no "new version" notice
# under a test) unless the plugin's settings keep it; the map as the plugin's settings say (Immich's default: on).
# The admin's first sign-in meets the server's own first-run setup (its theme, privacy, storage template) until the
# server is marked set up: a flag of its own (system metadata admin-onboarding, the isOnboarded of /api/server/config),
# beside each account's. Marked done by the admin, after the library's settings.
function immich_admin_onboarded() {
  local token="$1" ;
  [ "$(echo '{"isOnboarded":true}' | immich_api POST /api/system-metadata/admin-onboarding "${token}" | sed -n 1p)" = '204' ] || { echo "The library's own first-run setup could not be marked done." >&2 ; return 1 ; } ;
  echo "  the library's own first-run setup marked done: the admin signs in to the photos" ;
}

function immich_system_settings() {
  local token="$1" check map config ;
  check="$(immich_setting version_check off)" ; map="$(immich_setting map on)" ;
  config="$(immich_api GET /api/system-config "${token}" < /dev/null | tail -n +2)" ;
  config="$(echo "${config}" | python3 -c 'import json, sys; c = json.load(sys.stdin); c["newVersionCheck"]["enabled"] = sys.argv[1] == "on"; c["map"]["enabled"] = sys.argv[2] == "on"; print(json.dumps(c))' "${check}" "${map}")" || return 1 ;
  [ "$(echo "${config}" | immich_api PUT /api/system-config "${token}" | sed -n 1p)" = '200' ] || { echo "The library's settings could not be set." >&2 ; return 1 ; } ;
  echo "  the version check ${check}, the map ${map} (core/config/plugin.immich.settings.yml)" ;
}

# Into the project of this builder named PROJECT_NAME, from its folder.
function immich_enter_project() {
  local project_path="${WORKSPACE_ROOT}/${doc_name}/${PROJECT_NAME}" ;
  if ! immich_is_project "${project_path}" ; then
    echo "${doc_name}/${PROJECT_NAME} is not a project of the Immich builder." ;
    return 1 ;
  fi
  cd "${project_path}" || return 1 ;
}

# Make the default accounts through the library's API: the first admin (admin-sign-up, which only an empty library
# takes), then the user, made by the admin, or given its password again when it is there. Both are made past the
# first-run wizard, and the library gets its test settings.
function add_immich_users() {
  immich_enter_project || return 1 ;
  local token user_name user_mail user_password user_role answer status=0 ;
  set_immich_users ;
  answer="$(python3 -c 'import json, sys; print(json.dumps({"email": sys.argv[1], "password": sys.argv[2], "name": sys.argv[3]}))' "${user_admin_mail}" "${user_admin_password}" "${user_admin_name}" | immich_api POST /api/auth/admin-sign-up)" ;
  case "$(echo "${answer}" | head -1)" in
    201) echo "  ${user_admin_mail}: the first admin, made." ;;
    400) echo "  ${user_admin_mail}: the library has its admin already." ;;
    *) echo "  The first admin was not made: $(echo "${answer}" | tail -n +2 | head -c 300)" ; cd ${WORKSPACE_ROOT}/${doc_name} ; return 1 ;;
  esac
  token="$(immich_token "${user_admin_mail}" "${user_admin_password}")" || { cd ${WORKSPACE_ROOT}/${doc_name} ; return 1 ; } ;
  local list ; list="$(immich_api GET /api/admin/users "${token}" < /dev/null | tail -n +2)" ;
  for user in "${users[@]}" ; do
    user_name="user_${user}_name"; user_mail="user_${user}_mail"; user_password="user_${user}_password"; user_role="user_${user}_role";
    echo " ---------------------------------------------------------------- ";
    echo "      User name: ${!user_name}";
    echo "      User mail: ${!user_mail}";
    echo "  User password: ${!user_password}";
    echo "      User role: ${!user_role}";
    echo " ================================================================= ";
    [ "${!user_role}" = 'admin' ] && continue ;
    local id ; id="$(echo "${list}" | python3 -c 'import json, sys; print(next((u["id"] for u in json.load(sys.stdin) if u["email"] == sys.argv[1]), ""))' "${!user_mail}" 2> /dev/null)" ;
    if [ -n "${id}" ] ; then
      answer="$(python3 -c 'import json, sys; print(json.dumps({"password": sys.argv[1], "shouldChangePassword": False}))' "${!user_password}" | immich_api PUT "/api/admin/users/${id}" "${token}")" ;
      [ "$(echo "${answer}" | head -1)" = '200' ] && echo "  there already: its password set again." || { echo "  not changed: $(echo "${answer}" | tail -n +2 | head -c 300)" ; status=1 ; } ;
    else
      answer="$(python3 -c 'import json, sys; print(json.dumps({"email": sys.argv[1], "password": sys.argv[2], "name": sys.argv[3], "shouldChangePassword": False}))' "${!user_mail}" "${!user_password}" "${!user_name}" | immich_api POST /api/admin/users "${token}")" ;
      [ "$(echo "${answer}" | head -1)" = '201' ] && echo "  made." || { echo "  not made: $(echo "${answer}" | tail -n +2 | head -c 300)" ; status=1 ; } ;
    fi
  done
  local onboarded=yes ;
  for user in "${users[@]}" ; do
    user_mail="user_${user}_mail"; user_password="user_${user}_password";
    local t ; t="$(immich_token "${!user_mail}" "${!user_password}")" || { status=1 ; onboarded=no ; continue ; } ;
    [ "$(echo '{"isOnboarded":true}' | immich_api PUT /api/users/me/onboarding "${t}" | sed -n 1p)" = '200' ] || { echo "  ${!user_mail}: not past the first-run wizard." ; status=1 ; onboarded=no ; } ;
  done
  [ "${onboarded}" = yes ] && echo "  Both accounts are past the first-run wizard." ;
  immich_system_settings "${token}" || status=1 ;
  immich_admin_onboarded "${token}" || status=1 ;
  cd ${WORKSPACE_ROOT}/${doc_name};
  return ${status} ;
}

# Keep the default accounts but the admin from signing in: each gets a password of its own no one knows (its photos
# and albums stay; add-users gives it its password again). The first admin is never touched.
function cancel_immich_users() {
  immich_enter_project || return 1 ;
  local token list user user_mail user_role id status=0 ;
  set_immich_users ;
  token="$(immich_token "${user_admin_mail}" "${user_admin_password}")" || { cd ${WORKSPACE_ROOT}/${doc_name} ; return 1 ; } ;
  list="$(immich_api GET /api/admin/users "${token}" < /dev/null | tail -n +2)" ;
  for user in "${users[@]}" ; do
    user_mail="user_${user}_mail"; user_role="user_${user}_role";
    [ "${!user_role}" = 'admin' ] && continue ;
    id="$(echo "${list}" | python3 -c 'import json, sys; print(next((u["id"] for u in json.load(sys.stdin) if u["email"] == sys.argv[1]), ""))' "${!user_mail}" 2> /dev/null)" ;
    [ -n "${id}" ] || { echo "  ${!user_mail}: not there." ; continue ; } ;
    if [ "$(python3 -c 'import json, secrets; print(json.dumps({"password": secrets.token_urlsafe(24)}))' | immich_api PUT "/api/admin/users/${id}" "${token}" | sed -n 1p)" = '200' ] ; then
      echo "  ${!user_mail}: can no longer sign in (its password is one no one knows)." ;
    else
      echo "  ${!user_mail}: could not be changed." ; status=1 ;
    fi
  done
  cd ${WORKSPACE_ROOT}/${doc_name};
  return ${status} ;
}

# Build a library from nothing: the project and its containers, its settings, and with --install the library served
# and checked, and its accounts.
function immich_build() {
  trim_project_name ;
  local base_url runtime ;
  runtime="$(immich_runtime)" ;
  if [ "${RUNTIME:-_none_}" != '_none_' ] && [ "${RUNTIME}" != "${runtime}" ] ; then
    echo "--runtime ${RUNTIME} needs a Webship Workspace with the container runtimes (webship/workspace#694): update the workspace, or build on DDEV." ;
    exit 1 ;
  fi
  case " ${IMMICH_RUNTIMES} " in
    *" ${runtime} "*) ;;
    *) echo "An Immich library builds on DDEV, Docker Compose, Podman and Kubernetes for now (--runtime ddev, docker, podman or kubernetes), not on ${runtime}: that runtime is not proven for it yet. Nothing was changed." ; exit 1 ;;
  esac
  if ! declare -F export_project_db > /dev/null ; then
    echo "An Immich library keeps a Postgres of its own, which the row's Backup and Restore reach through the core's database hook: it needs Webship Workspace 1.0.42 or newer (webship/workspace#937). Update the workspace. Nothing was changed." ;
    exit 1 ;
  fi
  if [ "${runtime}" != 'ddev' ] && ! declare -f rt_service > /dev/null ; then
    echo "Immich on ${runtime} needs a Webship Workspace whose runtimes take an application's own image and services (webship/workspace#841, #900): update the workspace, or build on DDEV." ;
    exit 1 ;
  fi
  if [ ${#PROJECT_NAME} -gt 40 ] || ! [[ "${PROJECT_NAME}" =~ ^[a-z0-9][a-z0-9-]*$ ]] ; then
    echo "The project name ${PROJECT_NAME} must be small letters, digits and dashes (its address and its containers take it). Nothing was changed." ;
    exit 1 ;
  fi
  local project_path="${WORKSPACE_ROOT}/${doc_name}/${PROJECT_NAME}" ;

  cd ${WORKSPACE_ROOT}/${doc_name} || exit 1 ;

  # A project of the same name goes first, with its containers, its database volume and its photos.
  drop_database ;
  rm -rf "${PROJECT_NAME:?}" ;
  mkdir -p "${PROJECT_NAME}/${IMMICH_LIBRARY}" ;
  cd "${project_path}" || exit 1 ;

  # A generic project without DDEV's database: the library's Postgres is its own.
  ddev config --project-type=generic --webserver-type=generic --docroot="" --project-name=${PROJECT_NAME} \
    --omit-containers=db --auto < /dev/null || exit 1 ;
  # The address is the runtime's to say, once the project is configured. The settings come before the services:
  # on Kubernetes, Postgres's env file is read when the project's manifests are written.
  base_url="$(immich_url)" ;
  if [ "${runtime}" == 'ddev' ] ; then
    immich_write_env "${project_path}" /data || exit 1 ;
    immich_write_ddev_config "${project_path}" || exit 1 ;
  else
    immich_write_env "${project_path}" "/var/www/html/${IMMICH_LIBRARY}" || exit 1 ;
    immich_runtime_config || { echo "The library's stack could not be written through the runtime layer." ; exit 1 ; } ;
  fi

  if [ "${INSTALL}" == 'yes' ] || [ "${ADD_USERS}" == 'yes' ] ; then
    echo "Starting the library: Immich ${IMMICH_VERSION}${runtime:+ on ${runtime}}, its Postgres and valkey, machine learning off." ;
    ddev_up start -y < /dev/null || exit 1 ;
    immich_wait || exit 1 ;
    if [ "${ADD_USERS}" == 'yes' ] ; then
      add_immich_users || exit 1 ;
    fi
    echo "${doc_name} ${PROJECT_NAME} is served: Immich ${IMMICH_VERSION}, its photos in ${IMMICH_LIBRARY}/." ;
    echo "Go to ${base_url}" ;
  else
    echo "${doc_name} ${PROJECT_NAME} is ready: Immich ${IMMICH_VERSION}, its photos to be in ${IMMICH_LIBRARY}/." ;
    if [ "${runtime}" = 'ddev' ] ; then
      echo "Serve it with: cd ${PROJECT_NAME} && ddev start   (or build with --install)" ;
    else
      echo "Serve it with Start in its row of the dashboard (or build with --install)" ;
    fi
  fi

  if [ "${LAUNCH}" == 'yes' ] ; then
    ddev launch ;
  fi

  cd ${WORKSPACE_ROOT}/${doc_name};
}

# ---------------------------------------------------------------------------------------------------------------------
# The database hook (webship/workspace#937): the row's Backup and Restore ask these first, on every runtime.
# ---------------------------------------------------------------------------------------------------------------------

# The extension of the plugin's own dumps.
function immich_db_extension() {
  echo "${IMMICH_DB_EXTENSION}" ;
}

# Write the library's database to <file>, the way Immich backs itself up: pg_dump --clean --if-exists, gzipped, and
# checked to its end. The photos are not in it: they are the project's folder, which the row's Backup archives.
function immich_export_db() {
  local file="$1" ;
  case "${file}" in
    *.gz) ;;
    *) echo "The library's database is written as gzipped SQL (${IMMICH_DB_EXTENSION}), the kind Immich's own backups are: name the file *.sql.gz." >&2 ; return 1 ;;
  esac
  immich_pg pg_dump -U postgres --clean --if-exists immich < /dev/null | gzip > "${file}" ;
  if [ "${PIPESTATUS[0]}" -ne 0 ] || ! gunzip -c "${file}" 2> /dev/null | tail -c 300 | grep -q 'PostgreSQL database dump complete' ; then
    echo "The database of $(basename "$(pwd)") could not be dumped to ${file##*/}." >&2 ;
    rm -f "${file}" ;
    return 1 ;
  fi
  echo "The database of $(basename "$(pwd)") (Immich ${IMMICH_VERSION}, immich) is in ${file}." ;
}

# Put <file> back as the library's database: checked first (a gzipped SQL dump that begins and ends where pg_dump begins
# and ends it: one of the plugin's, or one of Immich's own backups), restored with psql in one transaction into a
# database of its own (its vector extensions made by the dump, which the image loads), and only a whole restore takes
# the place of immich: the old database takes no new connections, its open ones go (the server opens new ones), and
# the two are renamed in one transaction. On a failure the old one is open again, under its own name. The photos are
# not in a dump: a restore of the database alone leaves the library's folder as it is.
function immich_import_db() {
  local file="$1" project ;
  project="$(basename "$(pwd)")" ;
  if ! gzip -t "${file}" 2> /dev/null || ! gunzip -c "${file}" | head -c 4096 | grep -q 'PostgreSQL database dump' \
     || ! gunzip -c "${file}" | tail -c 300 | grep -q 'PostgreSQL database dump complete' ; then
    echo "${file##*/} is not a whole dump of a Postgres database (gzipped SQL, as pg_dump writes it). Nothing was changed." >&2 ;
    return 1 ;
  fi
  echo "This replaces the database of ${project} (Immich, immich) with ${file##*/}; the photos stay as they are." ;
  immich_pg psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q -c 'SET client_min_messages = warning' \
    -c 'DROP DATABASE IF EXISTS immich_restore WITH (FORCE)' -c 'CREATE DATABASE immich_restore' < /dev/null || return 1 ;
  if ! gunzip -c "${file}" | immich_pg psql -U postgres -d immich_restore --single-transaction -v ON_ERROR_STOP=1 -q > /dev/null ; then
    immich_pg psql -U postgres -d postgres -q -c 'SET client_min_messages = warning' -c 'DROP DATABASE IF EXISTS immich_restore WITH (FORCE)' < /dev/null > /dev/null ;
    echo "${file##*/} did not go in whole. The database of ${project} is as it was." >&2 ;
    return 1 ;
  fi
  if ! immich_pg psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q -c 'SET client_min_messages = warning' \
      -c 'DROP DATABASE IF EXISTS immich_before_restore WITH (FORCE)' -c 'ALTER DATABASE immich WITH ALLOW_CONNECTIONS false' \
      -c "SELECT pg_terminate_backend(pid, 5000) FROM pg_stat_activity WHERE datname = 'immich' AND pid <> pg_backend_pid()" \
      -c 'BEGIN' -c 'ALTER DATABASE immich RENAME TO immich_before_restore' -c 'ALTER DATABASE immich_restore RENAME TO immich' -c 'COMMIT' \
      < /dev/null > /dev/null ; then
    immich_pg psql -U postgres -d postgres -q -c 'SET client_min_messages = warning' -c 'ALTER DATABASE immich WITH ALLOW_CONNECTIONS true' \
      -c 'DROP DATABASE IF EXISTS immich_restore WITH (FORCE)' < /dev/null > /dev/null 2>&1 ;
    echo "The restored database could not take the place of immich: the database of ${project} is as it was." >&2 ;
    return 1 ;
  fi
  immich_pg psql -U postgres -d postgres -q -c 'DROP DATABASE immich_before_restore WITH (FORCE)' < /dev/null > /dev/null ;
  immich_wait > /dev/null ;
  echo "The database of ${project} is now ${file##*/}." ;
}

# ---------------------------------------------------------------------------------------------------------------------
# The step pack in the testing stack
# ---------------------------------------------------------------------------------------------------------------------

# The step pack in the testing stack of a library of this builder. The core's testing_configure calls this in the
# project folder once webship-js is scaffolded and before the dependencies are installed; for a project that is not a
# library of this builder it changes nothing.
#
# It adds the pack to package.json; lists its step definitions in cucumber.js after webship-js's own; gives the suite
# the library's address where the scaffold has its placeholder; adds the accounts the scenarios name
# (worldParameters.users: admin and user, their passwords from the environment, the workspace's by default); and
# writes a first feature when the project has none. Every part is skipped when it is already done, so a second run
# adds what the first missed and never resets a suite.
function testing_configure_immich() {
  local project_path="$1";
  immich_is_project "${project_path}" || return 0 ;
  if [ ! -f "${project_path}/cucumber.js" ] || [ ! -f "${project_path}/package.json" ] ; then
    echo "  Immich: cucumber.js is not here yet — run the testing setup again once webship-js is scaffolded." ;
    return 1 ;
  fi
  local address ;
  address="$(cd "${project_path}" && PROJECT_NAME="${PROJECT_NAME:-$(basename "${project_path}")}" immich_url)" ;

  echo "Adding the Immich step pack (${IMMICH_STEPS_PACKAGE} ${IMMICH_STEPS_VERSION}).";

  python3 - "${project_path}" "${IMMICH_STEPS_PACKAGE}" "${IMMICH_STEPS_VERSION}" "${address}" <<'PYEOF' || return 1
import json, re, sys

project, pack, version, address = sys.argv[1:5]

# package.json: the pack as a dev dependency, at the release line this plugin was proven on.
pkg_file = project + '/package.json'
pkg = json.load(open(pkg_file))
if pack not in pkg.get('dependencies', {}) and pack not in pkg.get('devDependencies', {}):
    pkg.setdefault('devDependencies', {})[pack] = version
    open(pkg_file, 'w').write(json.dumps(pkg, indent=2) + '\n')
    print('  package.json: %s %s' % (pack, version))

cucumber_file = project + '/cucumber.js'
src = open(cucumber_file).read()
before = src

# The pack's step definitions after webship-js's own.
if ('node_modules/%s/' % pack) not in src:
    line = "'node_modules/%s/tests/step-definitions/*.js'," % pack
    core = re.search(r"^([ \t]*)'node_modules/webship-js/tests/step-definitions/[^']*',.*$", src, re.M)
    opening = re.search(r"^([ \t]*)require:[ \t]*\[[ \t]*$", src, re.M)
    if core:
        src = src[:core.end()] + '\n' + core.group(1) + line + src[core.end():]
    elif opening:
        src = src[:opening.end()] + '\n' + opening.group(1) + '  ' + line + src[opening.end():]
    else:
        sys.exit("  cucumber.js has no require list this can add to. Add this line to it:\n    " + line)
    print('  cucumber.js: the step definitions of %s' % pack)

# The accounts the scenarios name, in worldParameters (their passwords from the environment).
if not re.search(r"^\s*users:\s*\{", src, re.M):
    users = [
        "users: {",
        "  admin: { email: process.env.IMMICH_ADMIN_EMAIL || 'admin@example.com', password: process.env.IMMICH_ADMIN_PASSWORD || 'dD.123123ddd' },",
        "  user: { email: process.env.IMMICH_USER_EMAIL || 'user@example.com', password: process.env.IMMICH_USER_PASSWORD || 'dD.123123ddd' },",
        "},",
    ]
    wp = re.search(r"^([ \t]*)worldParameters:[ \t]*\{[ \t]*$", src, re.M)
    if wp:
        indent = wp.group(1) + '  '
        src = src[:wp.end()] + '\n' + '\n'.join(indent + line for line in users) + src[wp.end():]
        print('  cucumber.js: the accounts admin and user (IMMICH_ADMIN_PASSWORD, IMMICH_USER_PASSWORD)')

# The address the suite opens when LAUNCH_URL is not set. On DDEV the router sends the project's address to the
# server's own service, so DDEV gives the web container no primary URL, and the scaffold's placeholder would be the
# suite's address: it becomes the library's. On another runtime the tests' container is given LAUNCH_URL, which wins.
placeholder = "process.env.LAUNCH_URL || 'http://localhost:8080'"
if address and placeholder in src:
    src = src.replace(placeholder, "process.env.LAUNCH_URL || '%s'" % address)
    print('  cucumber.js: the address of the library (%s)' % address)

if src != before:
    open(cucumber_file, 'w').write(src)
PYEOF

  # A first feature when the project has none yet.
  local feature="${WORKSPACE_SCRIPTS}/plugins/immich/site.feature" ;
  if [ -f "${feature}" ] && [ ! -f "${project_path}/tests/features/site.feature" ] ; then
    mkdir -p "${project_path}/tests/features" && cp "${feature}" "${project_path}/tests/features/site.feature" \
      && echo "  tests/features/site.feature: a first feature for the library" ;
  fi
}

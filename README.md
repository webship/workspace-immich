<p align="center"><img src="https://raw.githubusercontent.com/webship/workspace-immich/1.0.x/assets/logo.svg" alt="Immich logo" width="96"></p>

# @webship.co/workspace-immich

Immich for the [Webship Workspace](https://github.com/webship/workspace) dashboard. It brings:

- a builder that makes an Immich photo library from its release and serves it from containers of its own;
- the [Immich step pack](https://github.com/webship/immich-steps) wired into the testing setup of that library;
- its AI items: two agents, a skill, a command and two prompts for building and testing Immich libraries, each listed in the workspace folder of its kind.

A library runs Immich's own images, each pinned by digest:
- its server, which serves the web app and the API;
- its Postgres, with the vector extensions (VectorChord, pgvecto.rs);
- valkey.

Machine learning is off, with no machine-learning container. A test library has no use for faces, smart search or duplicate detection. Nothing of Immich runs on the machine.

The workspace is container-based (DDEV by default). A library is a row like any other, so the row menus the core draws (start, stop, launch, backup, restore, remove, tests) work on it. Its Backup and Restore go through the plugin's own database hook.

The builder builds on DDEV by default, and with `--runtime` on Docker Compose, Podman or a Kubernetes cluster: see [Runtimes](#runtimes). It needs Webship Workspace 1.0.42 or newer, the core with the database hook (webship/workspace#937), and says so on an older one before it makes anything.

## Use it

```bash
cd ~/workspace
bash core/scripts/plugins.sh --require immich --with-needs     # npm install into the dashboard
bash core/scripts/plugins.sh --activate immich --with-needs    # plugins.immich in settings.yml
bash core/scripts/plugins.sh --install immich                  # the builder, functions, args, AI items, its settings file
bash core/scripts/plugins.sh --configure immich                # its settings: the version check, the map
```

The same four steps are buttons on the dashboard's **Settings → Plugins** page. `--install` is idempotent.
`--uninstall` removes what it placed; an AI item you edited stays.

Everything the plugin carries lands in the folder it belongs to, when that folder is an active workspace folder:

| What | Lands in |
| --- | --- |
| `cmd-immich-project.sh` | every active sites folder: `dev/`, `test/`, `sandboxes/`, `demos/` |
| The agents `immich-library-builder`, `immich-tester` | `ai-agents/` |
| The skill `immich-scenarios` | `ai-skills/` |
| The command `/immich-test` | `ai-commands/` |
| The prompts `immich-build-and-test`, `immich-scenarios-for-a-library` | `ai-prompts/` |
| Its settings, `plugin.immich.settings.yml` | `core/config/` (once; never overwritten) |

There they are listed like any other item of the folder, and installed into Claude Code from there.

## What it needs

A workspace starts empty, so the manifest says what else this plugin needs (`needs`):

- One sites folder, for the builder: `dev`, `test`, `sandboxes` or `demos` (`dev` is the one added when none is there). The folder also carries `cmd-tools-testing.sh`, the Users tools and the backup script this plugin's hooks answer to.
- `ai-agents`, `ai-skills`, `ai-commands` and `ai-prompts`: the AI folders its agents, its skill, its command and its prompts are placed in.

`--require` says so, `--activate` and `--install` stop until the workspace has them, and `--with-needs` adds what is
missing first:

```bash
bash core/scripts/plugins.sh --activate immich --with-needs   # dev and the four AI folders are required, activated and installed first
bash core/scripts/plugins.sh --install immich
```

Everything the builder runs for a library runs in its own containers, through the container tool the workspace
already needs; the plugin asks for no command of its own on the machine.

## What the package holds

| Path | What it is |
| --- | --- |
| `commands/cmd-immich-project.sh` | The builder, in the Build list as **Immich (photo library)**, installed into every sites folder |
| `scripts/functions/fun-immich.sh` | The bash functions behind it, sourced by bootstrap once installed. They hold the names the core's tools look for (`set_immich_users`, `add_immich_users`, `cancel_immich_users`, `testing_configure_immich`) and the database hook (`immich_is_project`, `immich_export_db`, `immich_import_db`, `immich_db_extension`). |
| `scripts/args/arg-immich.sh` | Its argparse; the Build form draws the builder's flags from it |
| `scripts/docker-compose.immich.yaml` | On DDEV, the server's, Postgres's and valkey's services, copied into the project's `.ddev/` |
| `config/plugin.immich.settings.yml` | The template of its settings file |
| `testing/site.feature` | The first feature a library gets when testing is set up |
| `ai/agents/immich-library-builder.md` | The agent that builds and fixes libraries: their containers, their database and photos, their accounts |
| `ai/agents/immich-tester.md` | The agent that writes and runs scenarios with the step pack, with JavaScript and without |
| `ai/skills/immich-scenarios/` | The skill: the step pack's phrases, the traps, three example features |
| `ai/commands/immich-test.md` | The slash command `/immich-test <library>`: set up when missing, match every step, run, report |
| `ai/prompts/immich-build-and-test.md`, `immich-scenarios-for-a-library.md` | Two prompts: whole launch commands for a new session |
| `src/index.ts` | `register(api)`: what the assistant is told about Immich here |
| `features/immich.feature`, `features/immich-runtimes.feature` | Scenarios for the dashboard's own browser suite |

The `workspacePlugin` block in `package.json` is the manifest the installer reads.

## What is different from a platform

| | WordPress (a platform) | Immich |
| --- | --- | --- |
| What is built | A WordPress site | An Immich photo library, v3.4.2, with machine learning off |
| Project | `--project-type=wordpress` | `--project-type=generic --webserver-type=generic`, DDEV's database omitted: Immich's own server serves it, on its own Postgres and valkey |
| The images | The container tool's | Immich's own, pinned by digest: its server, its Postgres with the vector extensions, valkey |
| The photos | — | The project's `library/` folder, so they go with the project's backup |
| Recognised by | The project type | On DDEV a file the builder writes, `.ddev/config.immich.yaml`; on another runtime its claim, `platform: immich` in the `x-webship` block of `compose.yaml` |
| Accounts | WP-CLI | The library's API: the first admin through admin-sign-up, the user through the admin API, both past the first-run wizard |
| Backup and Restore | DDEV's `export-db` and `import-db` | The plugin's database hook: pg_dump and psql in the library's Postgres, the way Immich backs itself up |
| Testing | The WordPress pack | The Immich pack, which names a photo by the date it was taken and reads the library's messages by their text |

## The commands

Run it from a sites folder. `--help` is safe.

### Build and serve a library

```bash
cd ~/workspace/dev
bash cmd-immich-project.sh photos --install --add-users                    # Immich v3.4.2, started, with its two accounts
bash cmd-immich-project.sh photos --install --add-users --runtime docker   # on Docker Compose instead of DDEV
bash cmd-immich-project.sh photos --install --runtime kubernetes           # on the workspace's Kubernetes cluster
```

| Flag | What it does |
| --- | --- |
| `--install` | Start the library (its server, its Postgres and valkey) and check that it answers at its address (`https://<name>.ddev.site` on DDEV) |
| `--add-users` | Make the default accounts too, through the library's API (see [Users](#users)) |
| `--runtime ddev\|docker\|podman\|kubernetes` | The container runtime to build on (default: DDEV, or `container.runtime` of `settings.yml`); see [Runtimes](#runtimes) |
| `--launch` | Open the library in a browser when it is ready |

The builder works in this order:
1. It deletes a project of the same name first: its containers, its database volume and its photos.
2. It makes the project with its empty `library/` folder and configures it.
3. It writes the library's settings into `.webship-immich/`. Only you can read them: a database password of the project's own, made once and kept by a later build.
4. With `--install`, it starts the library and waits for the server's ping.

### Its photos and its database

**The photos** are the project's `library/` folder: the server's `/data`. It holds:
- the originals (`upload/`);
- their thumbnails (`thumbs/`), encoded videos (`encoded-video/`) and profile pictures (`profile/`);
- Immich's own database backups (`backups/`).

On DDEV the server runs as the project's user, so these are the project's own files. On the other runtimes the web container runs it as the same user.

The row's **Backup** archives the project's folder, so the archive holds the photos. It can reach the library's size, plus its thumbnails (about a tenth more for photos), plus any encoded videos. A library of 1,000 photos at 4 MB makes an archive of about 4.5 GB.

**The database** is Immich's own Postgres 14 with VectorChord and pgvecto.rs. DDEV's own database cannot carry those extensions, so the builder omits it, and the library's Postgres is a service of the project with its data in a volume named after the project. DDEV's own database tools do not reach it: `ddev snapshot`, and DDEV's own `export-db` and `import-db`, work on DDEV's database, which this project does not have.

The plugin declares the core's database hook instead (webship/workspace#937, core 1.0.42), which the row's Backup and Restore ask first, on every runtime. It works the way Immich backs itself up:
- **Backup** writes `pg_dump --clean --if-exists` of the library's database, gzipped (`<archive>-db.sql.gz`), beside the archive, and checks it to its end.
- **Restore** (the row's Import) takes one of those, or one of Immich's own backups (`library/backups/immich-db-backup-*.sql.gz`, the same kind), and works in this order:
  1. It checks that the dump is whole.
  2. It exports the database as it is first.
  3. It restores the dump with `psql --single-transaction` into a database of its own.
  4. Only then does it put that database in the library's place. The old database takes no new connections, its open ones go, and the two are renamed in one transaction.

  A restore that fails leaves the library's database as it was.

**An Import puts back the database, not the photos.** The photos come back with the project's backup archive. When the two disagree, Immich says so in Administration, Maintenance, Integrity Report:
- **Missing Files** are in the database but not in the folder. Their thumbnails do not load, and opening one says it cannot be found.
- **Untracked Files** are in the folder but not in the database. The timeline does not show them.

Restore the archive and the database from the same Backup to keep them in step.

On a terminal, in the project's folder:

```bash
cd ~/workspace/dev/photos
bash ~/workspace/core/scripts/runtime-verb.sh export-db --file=../photos-before.sql.gz
bash ~/workspace/core/scripts/runtime-verb.sh import-db --file=../photos-before.sql.gz
bash ~/workspace/core/scripts/runtime-verb.sh import-db --file=library/backups/immich-db-backup-….sql.gz
```

On Docker Compose, Podman and Kubernetes the row's menu lists Export and Import for this project from Webship
Workspace 1.0.43 (webship/workspace#942).

### Its settings: the version check and the map

`core/config/plugin.immich.settings.yml` holds two settings the builder applies to each library it makes, through Immich's own system settings:

| Setting | Default here | Immich's default | What it is |
| --- | --- | --- | --- |
| `version_check` | `"off"` | on | Immich asks version.immich.cloud now and then for a newer release, and shows a notice when there is one. Off here: no call out of a test workspace, and no notice that changes the pages under a test. `"on"` keeps Immich's default. |
| `map` | `"on"` | on | The map draws its tiles from tiles.immich.cloud, only when someone opens it. Immich's default is kept; `"off"` turns the map off. |

Both can be changed later in the library itself: Administration, Settings, Version Check and Map & GPS Settings.

### Test an app

```bash
bash cmd-tools-testing.sh photos                                  # webship-js, the step pack, the accounts, a first feature
bash cmd-tools-testing.sh photos --run --path tests/features/site.feature
```

The testing setup does four things:
- adds `@webship-js/immich-steps` to the project and lists its step definitions in `cucumber.js`;
- gives the suite the library's address;
- adds the accounts the scenarios name: `admin` and `user`, their passwords from `IMMICH_ADMIN_PASSWORD` and `IMMICH_USER_PASSWORD` (the workspace's by default);
- writes `tests/features/site.feature`.

It changes nothing in a project that is not a library of this builder.

The API's scenarios need no browser, and run without JavaScript too. Every page of the library needs JavaScript.

```gherkin
Feature: The first photos
  @removes-test-content
  Scenario: An upload shows in the timeline by the date it was taken
    When I sign in to the library as "user"
    And I upload "webship-test-red.jpg" to the library
    Then the timeline should show the photo taken on "May 1, 2024"
    When I open the photo taken on "May 1, 2024"
    Then the photo's details should say "webship-test-red.jpg"
```

### Runtimes

The commands are the same on every runtime. The builder speaks DDEV's verbs, and on another runtime the core's layer gives each verb its meaning there (webship/workspace#694, #841 and #900):
- the server's image is the stack, its start the web container's own;
- Postgres and valkey are services of the project.

| Runtime | The address of the library | Where the photos are | Proven with this builder |
| --- | --- | --- | --- |
| DDEV (the default) | `https://<name>.ddev.site` | `<project>/library` (the server's `/data`) | PROOF-DDEV |
| Docker Compose (`--runtime docker`) | `http://127.0.0.1:<port>`, a free port kept in `compose.yaml` | `<project>/library` (in the web container: `/var/www/html/library`) | PROOF-DOCKER |
| Podman (`--runtime podman`) | `http://127.0.0.1:<port>` | `<project>/library` | PROOF-PODMAN |
| Kubernetes (`--runtime kubernetes`) | `http://<node address>:<NodePort>` | PROOF-K8S-WHERE | PROOF-KUBERNETES |

A project of the builder is known by DDEV's file on DDEV and by its claim on another runtime. So the testing setup, the Users tools, the database hook and the dashboard's row work the same on each. Lando and Docksal are runtimes of the workspace too, not proven with this builder yet: it says so and stops, before anything is made.

### Users

| Account | Mail | Made by |
| --- | --- | --- |
| `admin` | `admin@example.com` | The library's first admin, through admin-sign-up (which only an empty library takes) |
| `user` | `user@example.com` | `--add-users`, or `cmd-tools-add-users.sh <name> immich`: through the admin API, as the first admin |

Both have the workspace's password and are made past Immich's first-run wizard.

`cmd-tools-cancel-users.sh <name> immich` keeps `user` from signing in: it gets a password no one knows, and its photos and albums stay. `--add-users` gives it its password again. The first admin is never touched.

## The AI items

| Item | Kind | What it is for |
| --- | --- | --- |
| `immich-library-builder` | agent | Builds and fixes Immich libraries: their containers, their database and photos, their accounts, what to read when one does not answer |
| `immich-tester` | agent | Writes and runs scenarios with the step pack: signing in, photos by their date, messages by their text, test content removed and counted, never a fixed wait |
| `immich-scenarios` | skill | The step pack's phrases, the traps of a library with machine learning off, three example features |
| `/immich-test <library>` | command | Sets the pack up when missing, matches every step, runs, reports |
| `immich-build-and-test` | prompt | Builds a library and proves it with its first feature |
| `immich-scenarios-for-a-library` | prompt | Writes and runs the scenarios of a library of the workspace: its pages and its API |

Every item says the workspace is container-based (DDEV by default), and the agents and the skill send the reader to
the book *Automated Functional Testing Recipes* first.

## Develop it

```bash
npm install
npm test        # builds, then the unit tests: the manifest, the scripts, the AI items, the needs
npm run lint    # the TypeScript compiler, no output
```

CI runs the same on Node.js 24 and 26, and checks that every shell script parses. It also runs the plugin's webship-js features against a dashboard with the plugin installed (the reusable workflow `webship/workspace/.github/workflows/plugin-browser-suite.yml`):
- before the features it builds the library the manifest names (`featuresSite`: `cmd-immich-project.sh ci-immich --install --add-users --runtime docker`);
- so the scenarios of `features/immich-runtimes.feature` tagged `@needs-runtime-docker` drive a real library on Docker Compose;
- the Podman and Kubernetes ones run where such a library is.

`tests/fixtures/step-definitions.txt` holds the step definitions of the step pack and of webship-js, read from their packages: every phrase an AI item shows must match one of them.

## License

ISC (see `LICENSE`).

## Logo

The logo is the mark Immich ships, `design/immich-logo.svg` of github.com/immich-app/immich v3.4.2, unmodified.
Immich and its logo are Immich's: the logo names the software the plugin builds. It is not covered by this package's
licence.

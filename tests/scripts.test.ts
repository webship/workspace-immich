import test from 'node:test';
import assert from 'node:assert';
import fs from 'fs';
import os from 'os';
import path from 'path';
import zlib from 'zlib';
import { spawnSync } from 'child_process';

// Compiled, these tests run from dist/tests, so the package root is one folder further up.
const PKG = fs.existsSync(path.join(__dirname, '..', 'package.json')) ? path.join(__dirname, '..') : path.join(__dirname, '..', '..');
const FUNCTIONS = path.join(PKG, 'scripts', 'functions', 'fun-immich.sh');
const STAND_INS = path.join(PKG, 'tests', 'fixtures', 'stand-ins.sh');
const read = (f: string) => fs.readFileSync(path.join(PKG, f), 'utf8');
const tmp = (name: string) => fs.mkdtempSync(path.join(os.tmpdir(), `immich-${name}-`));
const SERVER = 'ghcr.io/immich-app/immich-server@sha256:fc880c1bf665b4aab1e74c15e56ab871225989cd546536e6b77e771869af06bd';
const POSTGRES = 'ghcr.io/immich-app/postgres@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23';
const VALKEY = 'docker.io/valkey/valkey@sha256:418652cfb58ef879d4978c33553735d7147016032d5aefaa14c828e611eb9dfd';

// The cucumber.js webship-js 2.0.19 scaffolds (bin/init-webship.js), as far as the testing hook reads it.
const SCAFFOLD = `module.exports = {
  default: {
    timeout: 30000,
    requireModule: ['tsx/cjs'],
    require: [
      'node_modules/webship-js/tests/step-definitions/**/*.js',          // Webship-js core step definitions.
      'tests/step-definitions/**/*.js',                                  // Your custom step definitions.
    ],
    paths: ['tests/features/**/*.feature'],
    worldParameters: {
      launchUrl: process.env.LAUNCH_URL || 'http://localhost:8080',
    },
  },
};
`;

/** Run bash with the stand-ins and the plugin's functions sourced; every call of a stand-in is written to LOG. */
function bash(script: string, env: Record<string, string> = {}) {
  const dir = tmp('run');
  const log = path.join(dir, 'calls.log');
  const r = spawnSync('bash', ['-c', `source ${STAND_INS}\nsource ${FUNCTIONS}\n${script}`], { encoding: 'utf8', cwd: env.CWD || dir, env: { ...process.env, LOG: log, ...env } });
  const calls = fs.existsSync(log) ? fs.readFileSync(log, 'utf8') : '';
  return { status: r.status, stdout: r.stdout, stderr: r.stderr, calls, dir };
}

/** A project folder with the testing stack scaffolded, and the tooling folder the installer would have filled. */
function project(kind: 'library' | 'drupal') {
  const root = tmp('plugin');
  const dir = path.join(root, 'dev', 'photos');
  fs.mkdirSync(path.join(dir, '.ddev'), { recursive: true });
  fs.writeFileSync(path.join(dir, '.ddev', 'config.yaml'), `name: photos\ntype: ${kind === 'drupal' ? 'drupal11' : 'generic'}\n`);
  if (kind === 'library') fs.writeFileSync(path.join(dir, '.ddev', 'config.immich.yaml'), '# An Immich library in this project.\n');
  fs.writeFileSync(path.join(dir, 'cucumber.js'), SCAFFOLD);
  fs.writeFileSync(path.join(dir, 'package.json'), JSON.stringify({ name: 'photos', devDependencies: { 'webship-js': '^2.0.19' } }, null, 2));
  const scripts = path.join(root, 'core', 'scripts');
  fs.mkdirSync(path.join(scripts, 'plugins', 'immich'), { recursive: true });
  fs.copyFileSync(path.join(PKG, 'testing', 'site.feature'), path.join(scripts, 'plugins', 'immich', 'site.feature'));
  return { root, dir, scripts };
}

function loadConfig(file: string, env: Record<string, string> = {}) {
  const r = spawnSync(process.execPath, ['-e', 'process.stdout.write(JSON.stringify(require(process.argv[1])))', file], { encoding: 'utf8', env: { ...process.env, ...env } });
  assert.strictEqual(r.status, 0, r.stderr);
  return JSON.parse(r.stdout);
}

test('the default accounts: the library\'s first admin and a user, with the workspace\'s password', () => {
  const r = bash('set_immich_users ; echo "${users[*]}|${user_admin_mail}|${user_admin_role}|${user_user_mail}|${user_user_role}|${user_admin_password}|${user_user_password}"');
  assert.strictEqual(r.stdout.trim(), 'admin user|admin@example.com|admin|user@example.com|user|dD.123123ddd|dD.123123ddd');
});

test('the plugin\'s own settings: the version check off and the map on unless its settings file says otherwise', () => {
  const config = tmp('config');
  const ask = () => bash('echo "$(immich_setting version_check off) $(immich_setting map on)"', { WORKSPACE_CONFIG: config }).stdout.trim();
  assert.strictEqual(ask(), 'off on', 'with no settings file, the defaults');
  fs.copyFileSync(path.join(PKG, 'config', 'plugin.immich.settings.yml'), path.join(config, 'plugin.immich.settings.yml'));
  assert.strictEqual(ask(), 'off on', 'the template says the same');
  fs.writeFileSync(path.join(config, 'plugin.immich.settings.yml'), 'immich:\n  version_check: "on"   # Immich\'s default\n  map: off\n');
  assert.strictEqual(ask(), 'on off');
});

test('the testing hook adds the step pack, the accounts, the library\'s address and a first feature, once', () => {
  const p = project('library');
  const run = () => bash(`PROJECT_NAME=photos testing_configure_immich ${p.dir}`, { WORKSPACE_SCRIPTS: p.scripts });
  const r = run();
  assert.strictEqual(r.status, 0, r.stderr + r.stdout);
  assert.strictEqual(JSON.parse(fs.readFileSync(path.join(p.dir, 'package.json'), 'utf8')).devDependencies['@webship-js/immich-steps'], '^2.0.0');
  const src = fs.readFileSync(path.join(p.dir, 'cucumber.js'), 'utf8');
  assert.ok(src.indexOf("'node_modules/@webship-js/immich-steps/tests/step-definitions/*.js',") > src.indexOf("'node_modules/webship-js/tests/step-definitions/**/*.js'"), 'the pack\'s steps after webship-js\'s own');
  const wp = loadConfig(path.join(p.dir, 'cucumber.js')).default.worldParameters;
  assert.deepStrictEqual(wp.users, { admin: { email: 'admin@example.com', password: 'dD.123123ddd' }, user: { email: 'user@example.com', password: 'dD.123123ddd' } });
  assert.strictEqual(loadConfig(path.join(p.dir, 'cucumber.js'), { IMMICH_USER_PASSWORD: 'another' }).default.worldParameters.users.user.password, 'another');
  assert.strictEqual(wp.launchUrl, 'https://photos.ddev.site', 'the library\'s address where the scaffold had its placeholder');
  assert.strictEqual(loadConfig(path.join(p.dir, 'cucumber.js'), { LAUNCH_URL: 'http://127.0.0.1:43210' }).default.worldParameters.launchUrl, 'http://127.0.0.1:43210', 'LAUNCH_URL still wins');
  assert.strictEqual(fs.readFileSync(path.join(p.dir, 'tests', 'features', 'site.feature'), 'utf8'), read('testing/site.feature'));
  const before = fs.readFileSync(path.join(p.dir, 'cucumber.js'), 'utf8') + fs.readFileSync(path.join(p.dir, 'package.json'), 'utf8');
  const again = run();
  assert.strictEqual(again.status, 0, again.stderr);
  assert.strictEqual(fs.readFileSync(path.join(p.dir, 'cucumber.js'), 'utf8') + fs.readFileSync(path.join(p.dir, 'package.json'), 'utf8'), before, 'a second run changes nothing');
});

test('the testing hook waits for the testing stack, and leaves any other project alone', () => {
  const p = project('library');
  fs.rmSync(path.join(p.dir, 'cucumber.js'));
  const r = bash(`testing_configure_immich ${p.dir}`, { WORKSPACE_SCRIPTS: p.scripts });
  assert.strictEqual(r.status, 1);
  assert.match(r.stdout, /cucumber\.js is not here yet — run the testing setup again once webship-js is scaffolded/);
  const d = project('drupal');
  const before = fs.readFileSync(path.join(d.dir, 'cucumber.js'), 'utf8');
  const other = bash(`testing_configure_immich ${d.dir}`, { WORKSPACE_SCRIPTS: d.scripts });
  assert.strictEqual(other.status, 0);
  assert.strictEqual(other.stdout, '');
  assert.strictEqual(fs.readFileSync(path.join(d.dir, 'cucumber.js'), 'utf8'), before);
});

test('the library\'s settings: a database password of the project\'s own, kept by a later build, machine learning off, only yours to read', () => {
  const root = tmp('env');
  const own = path.join(root, '.webship-immich');
  assert.strictEqual(bash(`immich_write_env ${root} /data`).status, 0);
  const env = fs.readFileSync(path.join(own, 'env'), 'utf8');
  const pg = fs.readFileSync(path.join(own, 'postgres.env'), 'utf8');
  const dbpass = (/^POSTGRES_PASSWORD=([A-Za-z0-9]{20,})$/m.exec(pg) || [])[1];
  assert.ok(dbpass, 'a database password');
  assert.ok(env.includes(`\nDB_PASSWORD=${dbpass}\n`), 'the server reaches its own Postgres with it');
  for (const line of [/^DB_HOSTNAME=postgres$/m, /^DB_DATABASE_NAME=immich$/m, /^REDIS_HOSTNAME=valkey$/m, /^IMMICH_MACHINE_LEARNING_ENABLED=false$/m, /^IMMICH_MEDIA_LOCATION=\/data$/m, /^IMMICH_PORT=2283$/m]) assert.match(env, line);
  for (const line of [/^POSTGRES_USER=postgres$/m, /^POSTGRES_DB=immich$/m, /^POSTGRES_INITDB_ARGS=--data-checksums$/m]) assert.match(pg, line);
  assert.strictEqual(fs.statSync(own).mode & 0o777, 0o700);
  for (const f of ['env', 'postgres.env']) assert.strictEqual(fs.statSync(path.join(own, f)).mode & 0o777, 0o600, f);
  assert.strictEqual(bash(`immich_write_env ${root} /var/www/html/library`).status, 0);
  const again = fs.readFileSync(path.join(own, 'env'), 'utf8');
  assert.ok(again.includes(`\nDB_PASSWORD=${dbpass}\n`), 'the same password on a later build');
  assert.match(again, /^IMMICH_MEDIA_LOCATION=\/var\/www\/html\/library$/m, 'the photos where the web container has the project');
});

test('on another runtime the settings reach the server as a compose env file is read: each line as it is, never through the shell', () => {
  const dir = tmp('envline');
  const file = path.join(dir, 'env');
  fs.writeFileSync(file, '# A comment\nTZ=Etc/UTC\nNAME=A library of mine\nODD=$(touch ' + dir + '/ran) `x` ;y\n\n');
  const line = bash(`immich_env_line ${file}`).stdout.trim();
  const r = spawnSync('bash', ['-c', `${line} && printf '%s|%s|%s' "$TZ" "$NAME" "$ODD"`], { encoding: 'utf8' });
  assert.strictEqual(r.status, 0, r.stderr);
  assert.strictEqual(r.stdout, 'Etc/UTC|A library of mine|$(touch ' + dir + '/ran) `x` ;y');
  assert.ok(!fs.existsSync(path.join(dir, 'ran')), 'a value is never run');
});

test('on DDEV: the services from the plugin\'s compose file, the three images by digest, and the builder\'s mark', () => {
  const root = tmp('ddev');
  const scripts = path.join(root, 'scripts');
  fs.mkdirSync(path.join(scripts, 'plugins', 'immich'), { recursive: true });
  const missing = bash(`immich_write_ddev_config ${root}/p`, { WORKSPACE_SCRIPTS: scripts });
  assert.strictEqual(missing.status, 1);
  assert.match(missing.stdout, /docker-compose\.immich\.yaml is not in .*: install the plugin \(plugins\.sh --install immich\)\./);
  fs.copyFileSync(path.join(PKG, 'scripts', 'docker-compose.immich.yaml'), path.join(scripts, 'plugins', 'immich', 'docker-compose.immich.yaml'));
  const r = bash(`immich_write_ddev_config ${root}/p`, { WORKSPACE_SCRIPTS: scripts });
  assert.strictEqual(r.status, 0, r.stderr + r.stdout);
  const ddev = path.join(root, 'p', '.ddev');
  assert.strictEqual(fs.readFileSync(path.join(ddev, 'docker-compose.immich.yaml'), 'utf8'), read('scripts/docker-compose.immich.yaml'));
  assert.strictEqual(fs.readFileSync(path.join(ddev, '.env'), 'utf8'), `IMMICH_SERVER_IMAGE=${SERVER}\nIMMICH_POSTGRES_IMAGE=${POSTGRES}\nIMMICH_VALKEY_IMAGE=${VALKEY}\n`);
  assert.match(fs.readFileSync(path.join(ddev, 'config.immich.yaml'), 'utf8'), /^# An Immich library in this project \(Immich v3\.4\.2\)/m);
});

test('the compose file: the server as the project\'s user with the photos in the project, the address sent to it, Postgres and valkey healthy first', () => {
  const y = read('scripts/docker-compose.immich.yaml');
  assert.match(y, /^ {2}immich-server:\n {4}image: "\$\{IMMICH_SERVER_IMAGE\}"$/m);
  assert.match(y, /^ {4}user: "\$\{DDEV_UID\}:\$\{DDEV_GID\}"$/m, 'the photos it writes are the project\'s own files');
  assert.match(y, /^ {6}- \$\{DDEV_APPROOT\}\/library:\/data$/m, 'the photos in the project\'s folder');
  assert.match(y, /VIRTUAL_HOST: \$\{DDEV_HOSTNAME\}\n {6}HTTP_EXPOSE: "80:2283"\n {6}HTTPS_EXPOSE: "443:2283"/);
  assert.match(y, /depends_on:\n {6}postgres:\n {8}condition: service_healthy\n {6}valkey:\n {8}condition: service_healthy/);
  assert.match(y, /^ {2}postgres:\n {4}image: "\$\{IMMICH_POSTGRES_IMAGE\}"$/m);
  assert.match(y, /^ {6}- postgres:\/var\/lib\/postgresql\/data$/m);
  assert.match(y, /^ {4}shm_size: 128mb$/m);
  assert.match(y, /^ {2}valkey:\n {4}image: "\$\{IMMICH_VALKEY_IMAGE\}"$/m);
  assert.match(y, /^volumes:\n {2}postgres:\n?$/m);
  assert.match(y, /- HTTP_EXPOSE=8093:80,8025:8025\n {6}- HTTPS_EXPOSE=8457:80,8026:8025/, 'the web container leaves 80 and 443 to the server, and keeps the mail catcher');
  assert.doesNotMatch(y, /machine-learning:|immich-machine-learning/, 'no machine-learning container');
  assert.doesNotMatch(y, /:latest\b|:release\b/, 'nothing by a moving tag');
});

/** The core's runtime layer, as far as the builder asks it. */
const layer = (rt: string, url: string) => [
  `runtime_of() { echo ${rt} ; }`,
  `rt_url() { echo ${url} ; }`,
  'rt_is_platform() { [ "$2" = immich ] ; }',
  'rt_claim() { echo "rt_claim $*" >> "${LOG}" ; }',
  'rt_stack() { echo "rt_stack $*" >> "${LOG}" ; }',
  'rt_service() { echo "rt_service $*" >> "${LOG}" ; }',
  'rt_serve() { echo "rt_serve $1" >> "${LOG}" ; printf "%s\\n" "$2" > "${LOG%/*}/serve.txt" ; }',
].join('\n');

/** A build of "photos" in a fresh workspace folder with the stand-ins; `layer` stands for the core's runtime layer. */
function build(opts: { layer?: string; env?: Record<string, string> } = {}) {
  const root = tmp('build');
  fs.mkdirSync(path.join(root, 'dev'), { recursive: true });
  const scripts = path.join(root, 'core', 'scripts');
  fs.mkdirSync(path.join(scripts, 'plugins', 'immich'), { recursive: true });
  fs.copyFileSync(path.join(PKG, 'scripts', 'docker-compose.immich.yaml'), path.join(scripts, 'plugins', 'immich', 'docker-compose.immich.yaml'));
  const r = bash(`${opts.layer || ''}\nPROJECT_NAME=\${NAME:-photos}\nimmich_build`, { WORKSPACE_ROOT: root, WORKSPACE_SCRIPTS: scripts, WORKSPACE_CONFIG: path.join(root, 'core', 'config'), doc_name: 'dev', RUNTIME: '_none_', INSTALL: 'yes', ADD_USERS: 'yes', LAUNCH: '', ...(opts.env || {}) });
  const serve = path.join(r.dir, 'serve.txt');
  return { ...r, root, project: path.join(root, 'dev', 'photos'), serve: fs.existsSync(serve) ? fs.readFileSync(serve, 'utf8') : '' };
}

test('a new library on DDEV: its services, its photos\' folder, started and checked, its accounts past the wizard, the version check off', () => {
  const b = build();
  assert.strictEqual(b.status, 0, b.stderr + b.stdout);
  assert.ok(fs.statSync(path.join(b.project, 'library')).isDirectory(), 'the photos\' folder is the project\'s');
  assert.match(b.calls, /^ddev config --project-type=generic --webserver-type=generic --docroot= --project-name=photos --omit-containers=db --auto$/m);
  assert.ok(fs.existsSync(path.join(b.project, '.ddev', 'docker-compose.immich.yaml')));
  assert.match(fs.readFileSync(path.join(b.project, '.webship-immich', 'env'), 'utf8'), /^IMMICH_MEDIA_LOCATION=\/data$/m);
  assert.match(b.calls, /^ddev start -y$/m);
  assert.match(b.calls, /^ddev exec curl -fsS -o \/dev\/null http:\/\/immich-server:2283\/api\/server\/ping$/m);
  assert.match(b.calls, /^body POST \/api\/auth\/admin-sign-up \{"email": "admin@example\.com", "password": "dD\.123123ddd", "name": "Webship admin"\}$/m);
  assert.match(b.calls, /^body POST \/api\/admin\/users \{"email": "user@example\.com", "password": "dD\.123123ddd", "name": "Webship user", "shouldChangePassword": false\}$/m);
  assert.strictEqual((b.calls.match(/^body PUT \/api\/users\/me\/onboarding \{"isOnboarded":true\}$/gm) || []).length, 2, 'both accounts past the first-run wizard');
  const config = JSON.parse((/^system-config (.*)$/m.exec(b.calls) || [])[1] || '{}');
  assert.deepStrictEqual([config.newVersionCheck, config.map, config.other], [{ enabled: false }, { enabled: true }, 1], 'the version check off, the map and the rest as Immich has them');
  const order = ['drop_database', 'ddev config', 'ddev start -y', 'server/ping', 'admin-sign-up', 'POST /api/admin/users', 'onboarding', 'system-config'].map((s) => b.calls.indexOf(s));
  assert.ok(order.every((i) => i >= 0), b.calls);
  assert.deepStrictEqual([...order].sort((x, y) => x - y), order, 'in order');
  assert.match(b.stdout, /^dev photos is served: Immich v3\.4\.2, its photos in library\/\.$/m);
  assert.match(b.stdout, /^Go to https:\/\/photos\.ddev\.site$/m);
});

test('a library that has its admin and its user already: the user\'s password set again; without --install the project is only made', () => {
  const there = build({ env: { SIGNUP: '400', USER_THERE: 'yes' } });
  assert.strictEqual(there.status, 0, there.stderr + there.stdout);
  assert.match(there.stdout, /the library has its admin already/);
  assert.match(there.calls, /^body PUT \/api\/admin\/users\/u-1 \{"password": "dD\.123123ddd", "shouldChangePassword": false\}$/m);
  const down = build({ env: { FAIL: 'signup' } });
  assert.strictEqual(down.status, 1, 'a library that cannot make its admin fails the build');
  const b = build({ env: { INSTALL: '', ADD_USERS: '' } });
  assert.strictEqual(b.status, 0, b.stderr + b.stdout);
  assert.doesNotMatch(b.calls, /^ddev start|server\/ping|curl -s -o/m, 'nothing is started');
  assert.match(b.stdout, /Serve it with: cd photos && ddev start/);
});

test('a bad project name, an unproven runtime, a workspace without the runtimes or without the database hook stop the build before anything is made', () => {
  for (const [env, layerOf, message] of [
    [{ NAME: 'Photos_1' }, '', /The project name Photos_1 must be small letters, digits and dashes/],
    [{ RUNTIME: 'docker' }, '', /--runtime docker needs a Webship Workspace with the container runtimes \(webship\/workspace#694\)/],
    [{}, layer('lando', 'http://127.0.0.1:43212'), /builds on DDEV, Docker Compose, Podman and Kubernetes for now \(--runtime ddev, docker, podman or kubernetes\), not on lando/],
    [{}, 'runtime_of() { echo docker ; }', /Immich on docker needs a Webship Workspace whose runtimes take an application's own image and services/],
    [{}, 'unset -f export_project_db', /it needs Webship Workspace 1\.0\.42 or newer \(webship\/workspace#937\)\. Update the workspace\. Nothing was changed\./],
  ] as Array<[Record<string, string>, string, RegExp]>) {
    const b = build({ env, layer: layerOf });
    assert.strictEqual(b.status, 1, JSON.stringify(env) + b.stdout);
    assert.match(b.stdout, message);
    assert.strictEqual(b.calls, '', `nothing ran: ${JSON.stringify(env)}`);
    assert.ok(!fs.existsSync(b.project), 'no project folder was made');
  }
});

for (const [rt, url] of [['docker', 'http://127.0.0.1:43210'], ['podman', 'http://127.0.0.1:43211'], ['kubernetes', 'http://172.18.0.2:30080']]) {
  test(`on ${rt}: the server's image as the stack, Postgres and valkey as services of the project, Immich's own start; never a ddev.site`, () => {
    const b = build({ layer: layer(rt, url), env: { RUNTIME: rt } });
    assert.strictEqual(b.status, 0, b.stderr + b.stdout);
    assert.match(b.calls, /^rt_claim immich$/m);
    assert.ok(b.calls.includes(`\nrt_stack image ${SERVER}\n`), b.calls);
    assert.ok(b.calls.includes(`\nrt_service postgres ${POSTGRES} --port 5432 --env-file .webship-immich/postgres.env --volume /var/lib/postgresql/data\n`), b.calls);
    assert.ok(b.calls.includes(`\nrt_service valkey ${VALKEY} --port 6379\n`), b.calls);
    assert.match(b.calls, /^rt_serve 2283$/m);
    assert.match(b.serve, /^while IFS= read -r l ; do .* done < \/var\/www\/html\/\.webship-immich\/env && until \(exec 3<>\/dev\/tcp\/postgres\/5432\) 2> \/dev\/null ; do sleep 2 ; done && cd \/usr\/src\/app && exec start\.sh$/m);
    assert.match(fs.readFileSync(path.join(b.project, '.webship-immich', 'env'), 'utf8'), /^IMMICH_MEDIA_LOCATION=\/var\/www\/html\/library$/m);
    assert.ok(fs.existsSync(path.join(b.project, '.webship-immich', 'postgres.env')), 'Postgres\'s settings are there before its service is written');
    assert.ok(b.calls.indexOf('ddev config') < b.calls.indexOf('rt_claim'), 'the claim after the runtime\'s files are written');
    assert.match(b.calls, /^ddev exec curl -fsS -o \/dev\/null http:\/\/127\.0\.0\.1:2283\/api\/server\/ping$/m);
    assert.ok(!fs.existsSync(path.join(b.project, '.ddev', 'docker-compose.immich.yaml')), 'no DDEV file');
    assert.match(b.stdout, new RegExp(`^Go to ${url.replace(/[.:/]/g, '\\$&')}$`, 'm'));
    assert.doesNotMatch(b.stdout, /ddev\.site/);
  });
}

test('a project of the builder is known by DDEV\'s file, else by the core\'s rt_is_platform', () => {
  const p = project('library');
  assert.strictEqual(bash(`immich_is_project ${p.dir}`).status, 0);
  fs.rmSync(path.join(p.dir, '.ddev', 'config.immich.yaml'));
  assert.strictEqual(bash(`immich_is_project ${p.dir}`).status, 1);
  assert.strictEqual(bash(`rt_is_platform() { [ "$1" = ${p.dir} ] && [ "$2" = immich ] ; } ; immich_is_project ${p.dir}`).status, 0);
});

test('the user is kept from signing in with a password no one knows, its photos kept; the first admin is never touched', () => {
  const b = build({ env: { INSTALL: '', ADD_USERS: '' } });
  const r = bash('set_immich_users ; PROJECT_NAME=photos ; cancel_immich_users', { WORKSPACE_ROOT: b.root, doc_name: 'dev', USER_THERE: 'yes' });
  assert.strictEqual(r.status, 0, r.stderr + r.stdout);
  assert.match(r.stdout, /user@example\.com: can no longer sign in/);
  const body = (/^body PUT \/api\/admin\/users\/u-1 (.*)$/m.exec(r.calls) || [])[1] || '';
  assert.match(body, /^\{"password": "[A-Za-z0-9_-]{20,}"\}$/, 'a random password');
  assert.doesNotMatch(body, /dD\.123123ddd/);
  assert.doesNotMatch(r.calls, /\/api\/admin\/users\/a-1/, 'the admin is not changed');
});

test('Backup: gzipped SQL the way Immich backs itself up (--clean --if-exists), checked to its end; a dump that fails leaves no file', () => {
  const dir = tmp('dump');
  let r = bash(`immich_export_db ${dir}/a.sql.gz`, { CWD: dir });
  assert.strictEqual(r.status, 0, r.stderr);
  assert.match(zlib.gunzipSync(fs.readFileSync(path.join(dir, 'a.sql.gz'))).toString(), /PostgreSQL database dump complete/);
  assert.match(r.calls, /^ddev exec -s postgres -d \/ pg_dump -U postgres --clean --if-exists immich$/m);
  assert.match(r.stdout, new RegExp(`The database of ${path.basename(dir)} \\(Immich v3\\.4\\.2, immich\\) is in ${dir}/a\\.sql\\.gz\\.`));
  for (const fail of ['dump', 'short']) {
    r = bash(`immich_export_db ${dir}/b.sql.gz`, { CWD: dir, FAIL: fail });
    assert.strictEqual(r.status, 1, fail);
    assert.ok(!fs.existsSync(path.join(dir, 'b.sql.gz')), `no dump is left (${fail})`);
  }
  r = bash(`immich_export_db ${dir}/c.dump`, { CWD: dir });
  assert.strictEqual(r.status, 1);
  assert.match(r.stderr, /written as gzipped SQL \(\.sql\.gz\), the kind Immich's own backups are/);
  assert.strictEqual(bash('immich_db_extension').stdout.trim(), '.sql.gz');
});

const DUMP = '--\n-- PostgreSQL database dump\n--\n\nCREATE TABLE public.asset (id uuid);\n\n--\n-- PostgreSQL database dump complete\n--\n\n';

test('Restore: the dump checked, restored with psql in one transaction into a database of its own, put in place in one step; Immich\'s own backups too', () => {
  const dir = tmp('restore');
  for (const name of ['photos--db--2026-11-27.sql.gz', 'immich-db-backup-20261127T020000-v3.4.2-pg14.19.sql.gz']) {
    fs.writeFileSync(path.join(dir, name), zlib.gzipSync(DUMP));
    const r = bash(`immich_import_db ${dir}/${name}`, { CWD: dir });
    assert.strictEqual(r.status, 0, r.stderr + r.stdout);
    const steps = ['CREATE DATABASE immich_restore', 'psql -U postgres -d immich_restore --single-transaction -v ON_ERROR_STOP=1 -q',
      'ALTER DATABASE immich WITH ALLOW_CONNECTIONS false', 'pg_terminate_backend(pid, 5000)', '-c BEGIN -c ALTER DATABASE immich RENAME TO immich_before_restore -c ALTER DATABASE immich_restore RENAME TO immich -c COMMIT',
      'DROP DATABASE immich_before_restore WITH (FORCE)', 'server/ping'];
    const at = steps.map((s) => r.calls.indexOf(s));
    assert.ok(at.every((i) => i >= 0), `${name}: ${JSON.stringify(steps.filter((s, i) => at[i] < 0))}\n${r.calls}`);
    assert.deepStrictEqual([...at].sort((x, y) => x - y), at, `${name}: in order`);
    assert.match(r.stdout, /the photos stay as they are\./);
  }
});

test('Restore refuses a file that is not a whole dump, and a restore that fails leaves the library\'s database as it was', () => {
  const dir = tmp('refuse');
  fs.writeFileSync(path.join(dir, 'cut.sql.gz'), zlib.gzipSync('--\n-- PostgreSQL database dump\n--\nCREATE TABLE x ();\n'));
  fs.writeFileSync(path.join(dir, 'notes.sql.gz'), 'not gzipped');
  fs.writeFileSync(path.join(dir, 'a.sql.gz'), zlib.gzipSync(DUMP));
  for (const file of ['cut.sql.gz', 'notes.sql.gz']) {
    const r = bash(`immich_import_db ${dir}/${file}`, { CWD: dir });
    assert.strictEqual(r.status, 1, file);
    assert.match(r.stderr, /is not a whole dump of a Postgres database \(gzipped SQL, as pg_dump writes it\)\. Nothing was changed\./);
    assert.strictEqual(r.calls, '', 'nothing ran');
  }
  let r = bash(`immich_import_db ${dir}/a.sql.gz`, { CWD: dir, FAIL: 'restore' });
  assert.strictEqual(r.status, 1);
  assert.match(r.stderr, /a\.sql\.gz did not go in whole\. The database of .* is as it was\./);
  assert.match(r.calls, /DROP DATABASE IF EXISTS immich_restore WITH \(FORCE\)\n?$/);
  assert.doesNotMatch(r.calls, /RENAME|ALLOW_CONNECTIONS/);
  r = bash(`immich_import_db ${dir}/a.sql.gz`, { CWD: dir, FAIL: 'swap' });
  assert.strictEqual(r.status, 1);
  assert.match(r.stderr, /The restored database could not take the place of immich: the database of .* is as it was\./);
  assert.match(r.calls, /ALTER DATABASE immich WITH ALLOW_CONNECTIONS true -c DROP DATABASE IF EXISTS immich_restore WITH \(FORCE\)\n?$/);
});

test('the builder takes the runtimes it is proven on, and the flags of every builder', () => {
  const args = read('scripts/args/arg-immich.sh');
  const parser = args.slice(args.indexOf('\n', args.indexOf('<<ARGEOF')) + 1, args.lastIndexOf('\nARGEOF')).replace(/\$\{[a-z_]+\}/g, '');
  const py = `import argparse, json, sys\nparser = argparse.ArgumentParser()\n${parser}\nprint(json.dumps(vars(parser.parse_args(sys.argv[1:]))))`;
  const parse = (...argv: string[]) => spawnSync('python3', ['-I', '-c', py, ...argv], { encoding: 'utf8' });
  const ok = parse('photos', '--runtime', 'kubernetes', '-i', '-a', '-l');
  assert.strictEqual(ok.status, 0, ok.stderr);
  assert.deepStrictEqual(JSON.parse(ok.stdout), { PROJECT_NAME: 'photos', RUNTIME: 'kubernetes', install: true, add_users: true, launch: true });
  assert.strictEqual(JSON.parse(parse('photos').stdout).RUNTIME, '_none_');
  assert.notStrictEqual(parse('photos', '--runtime', 'lando').status, 0, 'a runtime it is not proven on');
  assert.match(read('scripts/functions/fun-immich.sh'), /^readonly IMMICH_RUNTIMES='ddev docker podman kubernetes';$/m);
});

test('the first feature names no product or platform in the words of a step', () => {
  const feature = read('testing/site.feature');
  const steps = feature.split('\n').filter((l) => /^\s*(Given|When|Then|And|But) /.test(l));
  assert.ok(steps.length >= 10);
  for (const s of steps) assert.doesNotMatch(s.replace(/"[^"]*"/g, '""'), /immich|drupal|wordpress|joomla|fastapi|python|node/i, s);
});

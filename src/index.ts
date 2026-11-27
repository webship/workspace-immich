/**
 * Immich for Webship Workspace: a plugin for Immich photo libraries.
 *
 * What the package carries is placed by the installer from the manifest: the builder in the sites folders, its
 * functions, argparse and machine files (the project's compose services on DDEV, a first feature) under
 * core/scripts/plugins/immich/, its settings template in core/config/, its AI items (ai/) in the AI folders. The
 * builder makes an Immich library from its release and serves it from containers of its own: its server, its Postgres
 * with the vector extensions and valkey, each pinned by digest, machine learning off, the photos in the project's
 * library/ folder. The library's database is the plugin's to back up and restore (the core's database hook, the way
 * Immich backs itself up). The step pack (@webship-js/immich-steps) goes into the testing setup of such a library with
 * the core's `cmd-tools-testing.sh <project>`. The dashboard needs nothing drawn for it: the builder is in the Build
 * list because it is a cmd-*-project.sh, the row menus are the core's, the AI items are listed like any other. What
 * register() adds is what the assistant is told.
 *
 * Everything the dashboard is asked for goes through `api`; this package requires nothing from the dashboard's own
 * files, so it can be installed from npm and removed without a trace.
 */

import type { PluginApi } from '@webship.co/workspace-plugin-api';

/** The plugin's name, which its functions are named after. */
export const PLATFORM = 'immich';

/** The commands the installer places in every sites folder. */
export const COMMANDS = ['cmd-immich-project.sh'];

/** The agents the installer places in the AI Agents folder. */
export const AGENTS = ['immich-library-builder', 'immich-tester'];

/** The skill the installer places in the AI Skills folder (a folder each, with its SKILL.md). */
export const SKILLS = ['immich-scenarios'];

/** The slash command the installer places in the AI Commands folder. */
export const AI_COMMANDS = ['immich-test'];

/** The prompts the installer places in the AI Prompts folder: whole launch commands for a new session. */
export const PROMPTS = ['immich-build-and-test', 'immich-scenarios-for-a-library'];

/** What the assistant is told about Immich in this workspace. */
export function assistantContext(): string {
  return [
    'Immich (a plugin, @webship.co/workspace-immich): its builder makes an Immich photo library and serves it from containers of its own, with',
    '`bash cmd-immich-project.sh <name> --install --add-users` from a sites folder (dev, test, sandboxes, demos): Immich v3.4.2, its server,',
    'its Postgres with the vector extensions and valkey, each pinned by digest, machine learning off, at https://<name>.ddev.site.',
    'The photos are the project\'s <name>/library/ folder, so the row\'s Backup archives them; the database is the plugin\'s to back up and',
    'restore (the row\'s Backup and Import, the way Immich backs itself up: pg_dump --clean --if-exists, psql in one transaction). An Import',
    'puts back the database only: the photos come back with the project\'s backup archive. Its accounts: the first admin admin@example.com',
    'and the user user@example.com, made through the library\'s API past the first-run wizard; the version check is off unless',
    'core/config/plugin.immich.settings.yml keeps it. `--runtime docker`, `podman` or `kubernetes` builds it on Docker Compose, Podman or a',
    'Kubernetes cluster instead of DDEV, at the address that runtime gives (the build prints it).',
    '`bash cmd-tools-testing.sh <name>` sets up webship-js with the step pack @webship-js/immich-steps on such a library: its steps sign in',
    'through the form or the API, upload photos and wait until the library has them, name a photo by the date it was taken, and read the',
    'library\'s messages by their text.',
    `For building or fixing an Immich library (its containers, its database, its photos, its accounts), hand over to the agent \`${AGENTS[0]}\`; for testing one, to \`${AGENTS[1]}\`.`,
    `The plugin also places the skill ${SKILLS.map((a) => `\`${a}\``).join(', ')} (the step pack's phrases) in ai-skills/,`,
    `the command ${AI_COMMANDS.map((a) => `\`/${a} <library>\``).join(', ')} in ai-commands/ and the prompts ${PROMPTS.map((a) => `\`${a}\``).join(' and ')} in ai-prompts/.`,
    'Never run node, npm or psql on the host for a project.',
  ].join(' ');
}

export function register(api: PluginApi): void {
  api.addAssistantContext(assistantContext);
}

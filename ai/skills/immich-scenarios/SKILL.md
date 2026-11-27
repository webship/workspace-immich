---
name: immich-scenarios
description: The phrases of the Immich step pack (@webship-js/immich-steps) for webship-js scenarios of an Immich photo library built in the container-based Webship Workspace (DDEV by default) with cmd-immich-project.sh — signing in through the form or the API, uploads waited on until the library has them, the timeline and the viewer by the date a photo was taken, favorites, the trash, albums, shared links, search by file name, the API with a token or a key, and the traps of a library with machine learning off. Use when writing or fixing scenarios for such a library.
---

# Scenarios for an Immich library

An Immich library draws every page in the browser from its API: a photo is named by the date it was taken ("Image
taken on May 1, 2024"), a change shows a message that is read by its text, and a question is a dialog answered with its
Confirm. The steps wait on the library's uploads, its calls and its messages, never for a fixed time. The workspace is
container-based (DDEV by default).

## The book

For any automated functional testing in this work (a Gherkin feature, a step definition, choosing a
step, a test run and its failures), read the book *Automated Functional Testing Recipes* first.

- **Where.** Use the first that exists: `.claude/automated-functional-testing-recipes/` in the project,
  `~/.claude/automated-functional-testing-recipes/` (installed by webship/webship-js-ai-agent,
  webship/webship-js-skills or webship/ai-agents), or
  https://github.com/webship/webship-js-ai-agent/tree/2.0.x/automated-functional-testing-recipes
- **How.** Its `README.md` first, then the chapter that matches the task (one file per chapter,
  named by its subject), not the single complete file.
- **Which wins.** The installed webship-js package and the step pack are the source of truth for
  step phrasing. When they differ from the book, follow them and say so.
- **For Immich.** Start with `ch07-waiting-dynamic-content.md` (an upload the library finishes in jobs of its own),
  `ch27-testing-spa.md` (pages drawn in the browser from an API),
  `ch10-authentication-authorization.md` (a session, a token, an API key) and
  `ch11-api-testing-recipes.md` (the API every client of the library uses).

## Setting it up

`bash cmd-tools-testing.sh <library>` in the library's sites folder adds webship-js, the pack, the accounts `admin` and
`user` (their passwords from `IMMICH_ADMIN_PASSWORD` and `IMMICH_USER_PASSWORD`), the library's address and a first
feature. `bash cmd-tools-testing.sh <library> --list-steps` lists every phrase.

## The phrases

Signing in:

- `When I sign in to the library as "user"`: the login form, as a person fills it.
- `When I sign in to the library as "user" with a wrong password`, then `Then the library should say "Incorrect email or password"`.
- `Given I am signed in to the library as "user"`: through the API, faster, for every other scenario.
- `When I get past the library's first-run wizard`: for an account on its first sign-in.
- `Given the library has a new account "newcomer"`: a test account of the scenario's own.

Photos:

- `When I upload "webship-test-red.jpg" to the library`: the pack's photos are webship-test-red.jpg (May 1, 2024),
  webship-test-blue.jpg (August 15, 2023) and webship-test-green.jpg (December 24, 2022).
- `Then the timeline should show the photo taken on "May 1, 2024"`, `When I open the photo taken on "May 1, 2024"`.
- `Then the photo's details should say "webship-test-red.jpg"`.
- `When I mark the photo as a favorite`, `Then the photo should be a favorite`.
- `When I move the photo to the trash`, `When I press "Undo" in the library's message`.
- `When I confirm "Empty trash"`, `Then the trash should be empty`.

Albums, links, search:

- `When I create the album "Webship test album" with the photo taken on "May 1, 2024"`.
- `Then the album "Webship test album" should hold 1 item`.
- `When I share the album "Webship test album" by a link`, `When I open the shared link signed out`.
- `When I search the library for the file name "webship-test-blue"`, `Then the search should find nothing`.

The API (no browser):

- `Given I am signed in to the library's API as "user"`, `Given the library's API uses a key of "user"`.
- `When I upload "webship-test-green.jpg" to the library through the API`, `Then the library should hold "webship-test-green.jpg"`.

## The traps

- A photo is named by the date it was taken, from its EXIF: write it as the library does ("May 1, 2024").
- The library finishes an upload in jobs of its own; the upload steps wait for them.
- Messages leave after a few seconds: read one in the step after what it is about.
- The trash page does not follow a restore on its own: the trash steps open it again.
- The default search reads what a photo shows, which needs machine learning; it is off, so search by file name.
- Every page needs JavaScript: scenarios of the pages carry `@needs-javascript`.
- What a scenario makes is test content: files webship-test-*, "Webship test …" albums, links and keys, and
  `@removes-test-content` on the scenario.

## Examples

- `examples/sign-in.feature`: the login form, a wrong password, a new account's first-run wizard.
- `examples/photos.feature`: an upload in the timeline, its details, a favorite, the trash and its Undo.
- `examples/albums.feature`: an album with a photo, shared by a link opened signed out, and a search by file name.

Run one with `bash cmd-tools-testing.sh <library> --run --path tests/features/photos.feature`.

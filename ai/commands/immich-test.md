---
description: Test an Immich photo library of the Webship Workspace with webship-js and the Immich step pack — set the testing stack up when it is missing, match every step, run the suite (or one feature, or a tag) with JavaScript and without, and read why a scenario fails.
argument-hint: '<library> [tests/features/<name>.feature | @tag]'
---

# /immich-test

Test the Immich library named in: `$ARGUMENTS`

`$ARGUMENTS` stands for what was typed after the command: the library's name, then a feature or a tag to run alone.

The workspace is container-based (DDEV by default). Work in the sites folder the library is in (`~/workspace/dev`
unless told otherwise).

1. When the library is not there, build it: `bash cmd-immich-project.sh <library> --install --add-users`.
2. When it has no testing stack yet (no `cucumber.js` in its folder), set it up: `bash cmd-tools-testing.sh <library>`.
3. Match every step before running: `bash cmd-tools-testing.sh <library> --dry-run`. An undefined step is a phrase the
   pack or webship-js does not have: `bash cmd-tools-testing.sh <library> --list-steps` lists them, and the skill
   `immich-scenarios` says which one to use.
4. Run it: `bash cmd-tools-testing.sh <library> --run`, or `--run --path tests/features/<name>.feature`, or
   `--run --tags @<tag>`. The API's scenarios run in a browser without JavaScript too; the pages need it.
5. Read a failure from its message and hint: the pack says what it expected, what it found and what to try. A photo
   is named by the date it was taken; a message by its text.

Before you write or change a scenario, or read a failed run, read the book *Automated Functional
Testing Recipes* (its `README.md`, then the matching chapter):
`.claude/automated-functional-testing-recipes/` in the project,
`~/.claude/automated-functional-testing-recipes/`, or
https://github.com/webship/webship-js-ai-agent/tree/2.0.x/automated-functional-testing-recipes

Report what ran, what passed, and for each failure the step, its message, and the change you propose.

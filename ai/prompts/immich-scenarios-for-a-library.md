Write webship-js scenarios for an Immich photo library that is already built: its sign-in, its photos and its API.

The launch command below is for Claude Code, the default; the text between the triple quotes can be given to another AI CLI as it is.

```
claude --permission-mode bypassPermissions """
Write webship-js scenarios for the Immich library <name> in this sites folder: <what to cover>
# ~/workspace/<dev|test|sandboxes|demos> · https://<name>.ddev.site · container-based (DDEV by default)
# the phrases: the skill immich-scenarios; every phrase the suite has: bash cmd-tools-testing.sh <name> --list-steps
# before writing: the book Automated Functional Testing Recipes (its README.md, then ch07-waiting-dynamic-content.md and ch27-testing-spa.md), from .claude/automated-functional-testing-recipes/ in the project, ~/.claude/automated-functional-testing-recipes/ or https://github.com/webship/webship-js-ai-agent/tree/2.0.x/automated-functional-testing-recipes

1. Open the library at https://<name>.ddev.site and its pages, signed in as the user
2. Write tests/features/<topic>.feature: the pages (@needs-javascript), then the API (no browser)
3. Upload only the pack's photos (webship-test-*), name what a scenario makes "Webship test …", tag it @removes-test-content
4. A scenario that expects a refusal carries @js-warn and a comment saying why
5. bash cmd-tools-testing.sh <name> --run --path tests/features/<topic>.feature, until it passes twice in a row

Report the scenarios, what they check, and the runs.
"""
```

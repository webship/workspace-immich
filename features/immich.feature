Feature: The Immich plugin on the dashboard
  Once the plugin is activated and installed, the sites folders offer the Immich builder, each AI folder
  lists the items of its kind the plugin ships, and the Plugins page lists the plugin with what it ships.

  # Settings lists every plugin that was added; the package and what the plugin ships are on its own page.
  Scenario: Settings lists the plugin, and its own page names its package and what it ships
    Given I am on "/settings"
     Then I should see "Immich"
     When I go to "/settings/plugin/immich"
     Then I should see "@webship.co/workspace-immich"
      And I should see "cmd-immich-project.sh"
      And I should see "immich-library-builder"

  Scenario: A sites folder offers the Immich builder
    Given I am on "/dev"
     Then "option[value='cmd-immich-project.sh']" should be attached

  # The AI folders are searched by name: with every plugin on, a folder lists more than one page of items.
  Scenario: The AI Agents folder lists the agents the plugin ships
    Given I am on "/ai-agents?q=immich-"
     Then I should see "immich-library-builder"
      And I should see "immich-tester"

  Scenario: The AI Skills folder lists the skill the plugin ships
    Given I am on "/ai-skills?q=immich-scenarios"
     Then I should see "immich-scenarios"

  Scenario: The AI Commands folder lists the command the plugin ships
    Given I am on "/ai-commands?q=immich-test"
     Then I should see "immich-test"

  Scenario: The AI Prompts folder lists the prompts the plugin ships
    Given I am on "/ai-prompts?q=immich-"
     Then I should see "immich-build-and-test"
      And I should see "immich-scenarios-for-a-library"

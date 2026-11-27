@needs-javascript @removes-test-content
Feature: Photos in the library
  A photo uploaded through the page shows in the timeline by the date it was taken; the viewer shows its details,
  marks it a favorite and moves it to the trash, whose Undo, Restore all and Empty trash do what they say.

  Background:
    Given I am signed in to the library as "user"

  Scenario: An uploaded photo shows in the timeline, with its details in the viewer
    When I upload "webship-test-red.jpg" to the library
    Then the timeline should show the photo taken on "May 1, 2024"
    When I open the photo taken on "May 1, 2024"
    Then the photo's details should say "webship-test-red.jpg"
    And the photo's details should say "Webship test camera"

  Scenario: A favorite, marked and taken off
    When I upload "webship-test-blue.jpg" to the library
    And I open the photo taken on "August 15, 2023"
    And I mark the photo as a favorite
    Then the photo should be a favorite
    When I unmark the photo as a favorite
    Then the photo should not be a favorite

  Scenario: A photo moved to the trash comes back with Undo
    When I upload "webship-test-green.jpg" to the library
    And I open the photo taken on "December 24, 2022"
    And I move the photo to the trash
    Then the library should say "Trashed 1 asset"
    When I press "Undo" in the library's message
    Then the trash should be empty

  Scenario: The trash restored, then a photo deleted for good
    When I upload "webship-test-red.jpg" to the library
    And I open the photo taken on "May 1, 2024"
    And I move the photo to the trash
    Then the trash should hold the photo taken on "May 1, 2024"
    When I confirm "Restore all"
    Then the library should say "Restored 1 asset"
    And the trash should be empty
    When I go to "/photos"
    And I open the photo taken on "May 1, 2024"
    And I move the photo to the trash
    And I go to "/trash"
    And I confirm "Empty trash"
    Then the library should say "Permanently deleted 1 asset"
    And the trash should be empty

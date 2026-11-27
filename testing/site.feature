Feature: The Immich library of this project
  Its login form, a photo uploaded and shown in the timeline by the date it was taken, and its API. Written by the
  Immich plugin's testing setup as a first feature; make it this library's own.

  @needs-javascript
  Scenario: An account signs in through the form, and its timeline opens
    When I sign in to the library as "user"
    Then I should see "Photos"

  @needs-javascript @removes-test-content
  Scenario: An uploaded photo shows in the timeline by the date it was taken
    Given I am signed in to the library as "user"
    When I upload "webship-test-red.jpg" to the library
    Then the timeline should show the photo taken on "May 1, 2024"
    When I open the photo taken on "May 1, 2024"
    Then the photo's details should say "webship-test-red.jpg"

  @removes-test-content
  Scenario: The API takes an upload signed with a key
    Given the API base URL is "/"
    And the library's API uses a key of "user"
    When I upload "webship-test-green.jpg" to the library through the API
    Then the library should hold "webship-test-green.jpg"

  Scenario: The server answers its ping
    Given the API base URL is "/"
    When I send a GET request to "/api/server/ping"
    Then the API response code should be 200
    And the API response should contain "pong"

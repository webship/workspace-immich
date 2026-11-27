@needs-javascript @removes-test-content
Feature: Albums, shared links and search
  An album made with a photo and shared by a link that opens for someone who is not signed in; the library's search
  by file name, which finds that file and nothing else.

  Background:
    Given I am signed in to the library as "user"

  Scenario: An album with a photo, shared by a link that opens signed out
    When I upload "webship-test-red.jpg" to the library
    And I create the album "Webship test album" with the photo taken on "May 1, 2024"
    Then the library should say "Added 1 asset to the album"
    And the album "Webship test album" should hold 1 item
    When I share the album "Webship test album" by a link
    And I open the shared link signed out
    Then the shared page should show the photo taken on "May 1, 2024"

  Scenario: A search by file name finds that photo
    When I upload "webship-test-red.jpg" to the library
    And I upload "webship-test-blue.jpg" to the library
    And I search the library for the file name "webship-test-blue"
    Then the search should find the photo taken on "August 15, 2023"

  Scenario: A search for a file name the library does not have finds nothing
    When I search the library for the file name "webship-test-no-such-file"
    Then the search should find nothing

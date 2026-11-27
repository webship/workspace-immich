@needs-javascript
Feature: Signing in to the library
  Its login form as a person uses it, the message a wrong password gets, and the first-run wizard an account meets on
  its first sign-in.

  Scenario: An account signs in through the form, and its timeline opens
    When I sign in to the library as "user"
    Then I should see "Click to upload your first photo"

  # The browser logs the refused sign-in (a 401) as a console error: the refusal is what the scenario checks.
  @js-warn
  Scenario: A wrong password is refused, and the form says so
    When I sign in to the library as "user" with a wrong password
    Then the library should say "Incorrect email or password"

  @removes-test-content
  Scenario: A new account gets past its first-run wizard to its timeline
    Given the library has a new account "newcomer"
    When I sign in to the library as "newcomer"
    And I get past the library's first-run wizard
    Then I should see "Click to upload your first photo"

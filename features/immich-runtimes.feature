Feature: An Immich library on Docker Compose, Podman and Kubernetes
  The builder builds on DDEV by default, and with --runtime on Docker Compose, Podman or a Kubernetes cluster. An app
  built there has the row a DDEV project has: its state, its own address and the runtime's menu, and Immich's own
  server serves it, on its own Postgres and valkey.

  # Each scenario drives a real library of that runtime, built with cmd-immich-project.sh --runtime: the first running
  # one the workspace holds. Without one it is skipped, with the reason. In the plugin's CI the Docker Compose library
  # is the one the manifest's featuresSite builds: ci-immich.

  @needs-runtime-docker @needs-platform-immich
  Scenario: An Immich library built on Docker Compose runs at its own address, with the DOCKER menu
    Given I am on the folder of the "docker" site
     Then the row of the "docker" site should show "Running"
      And the row of the "docker" site should link to the address of its runtime
      And the address of the "docker" site should answer
      And the row of the "docker" site should carry the "DOCKER" menu and no DDEV menu

  # The library's login page is drawn in the browser by Immich's own web app, which its server serves.
  @needs-runtime-docker @needs-platform-immich
  Scenario: The library on Docker Compose is Immich's own: its login page
    Given I am on the folder of the "docker" site
     When I open "/auth/login" on the "docker" site
     Then "h1" should contain text "Login" within 30 seconds

  @needs-runtime-podman @needs-platform-immich
  Scenario: An Immich library built on Podman runs at its own address, with the PODMAN menu
    Given I am on the folder of the "podman" site
     Then the row of the "podman" site should show "Running"
      And the row of the "podman" site should link to the address of its runtime
      And the address of the "podman" site should answer
      And the row of the "podman" site should carry the "PODMAN" menu and no DDEV menu

  @needs-runtime-podman @needs-platform-immich
  Scenario: The library on Podman is Immich's own: its login page
    Given I am on the folder of the "podman" site
     When I open "/auth/login" on the "podman" site
     Then "h1" should contain text "Login" within 30 seconds

  @needs-runtime-kubernetes @needs-platform-immich
  Scenario: An Immich library built on Kubernetes runs at the address of its node, with the K8S menu
    Given I am on the folder of the "kubernetes" site
     Then the row of the "kubernetes" site should show "Running"
      And the row of the "kubernetes" site should link to the address of its runtime
      And the address of the "kubernetes" site should answer
      And the row of the "kubernetes" site should carry the "K8S" menu and no DDEV menu

  @needs-runtime-kubernetes @needs-platform-immich
  Scenario: The library on Kubernetes is Immich's own: its login page
    Given I am on the folder of the "kubernetes" site
     When I open "/auth/login" on the "kubernetes" site
     Then "h1" should contain text "Login" within 30 seconds

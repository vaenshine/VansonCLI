# Safety and Authorized Use

VansonCLI is a general technical debugging workspace for lawful testing, debugging, learning, and technical exchange.

## Authorized Scope

Use VansonCLI only with apps, devices, accounts, systems, and network flows that you own or are authorized to test.

Good use cases:

- Debugging your own app in a controlled environment.
- Inspecting runtime UI layout during development.
- Capturing and replaying test traffic from authorized systems.
- Verifying patches, hooks, and memory workflows in a lab device.
- Demonstrating AI-assisted debugging on sample apps.

## Sensitive Data Handling

- Use dedicated test accounts and test data.
- Avoid capturing production secrets, private tokens, personal messages, payment data, or third-party user data.
- Remove captured logs and HAR exports before publishing screenshots or demos.
- Rotate AI provider keys after public demos, contests, or shared-device testing.
- Keep provider keys outside screenshots and public issue reports.

## AI Provider Keys

The provider editor stores endpoint and credential configuration for local use. Use keys created for VansonCLI testing and set appropriate account limits in the provider dashboard.

Recommended practice:

- Create a separate provider key for VansonCLI.
- Use a low-limit test project.
- Revoke or rotate keys after demos.
- Avoid committing provider configuration, logs, or captured payloads.

## Network Replay

Replay is designed for authorized debugging. Confirm the target service, endpoint, payload, and account before replaying requests. Use test environments where possible.

## Patches, Hooks, and Memory Writes

Runtime modification can crash the target app or corrupt test data. Keep changes small, reversible, and documented.

Recommended practice:

- Prefer read-only inspection before writes.
- Record the class, selector, address, original value, and reason.
- Test one patch at a time.
- Use safe mode after crash loops.
- Keep backups for target app data used in experiments.

## Public Releases

Before publishing a release:

- Build with `./scripts/build_release.sh`.
- Remove generated local artifacts if committing source only.
- Review screenshots for keys, tokens, private domains, account names, and personal data.
- Include SHA-256 hashes for uploaded release artifacts.

## Disclaimer

Users are responsible for complying with local laws, platform rules, app terms, and third-party service terms. Operations performed with VansonCLI are made independently by the user.

# Contributing to PLANK

Start with [AGENTS.md](AGENTS.md), the [platform matrix](docs/development/platforms.md)
and the [build runbooks](docs/development/build/). Current work and outstanding
validation are recorded in [HANDOFF.md](HANDOFF.md).

For a fresh fork, read [Building from source](docs/development/build/from-source.md),
including the distinction between dependency bootstrap, development builds and
macOS distribution signing. No maintainer signing key is needed to compile.

## Where changes belong

- Product code: `apps/`. The Client is one shared cross-platform tree, not a
  separate copy for each operating system.
- Shared protocol and negotiation: `protocol/`. Keep Host and Client changes
  synchronized and add matching test vectors.
- Installation and operating-system integration: `packaging/<product>/<os>/`.
- Reproducible entry points: `scripts/build`, `scripts/package`, `scripts/test`
  and `scripts/maintenance`. Product-local scripts stay with their product.
- Tests: `tests/<subsystem>/`; hardware probes: `probes/`.

Host and Client are maintained Git submodules. Commit their changes before
updating parent gitlinks and push dependencies before parents. Preserve upstream
history, copyright and license notices. Follow each subtree's existing style.

## Platform changes

Use existing platform boundaries before creating an abstraction. Share protocol
and product policy; keep capture, input, presentation and service integration
platform-specific where necessary. Windows is a future contribution target,
not an existing qualified build. A directory or compiling stub is not support.

Keep PRs focused. Describe behavior, security implications, tests, target OS
and hardware, limitations and any incomplete acceptance gates. UI changes need
screenshots. Build on the documented platform with pinned dependency patches;
never silently replace exact-format media behavior to make a test pass.

Do not commit packages, caches, signing material, credentials, logs or private
deployment inventories. Keep operational notes outside Git and use synthetic
addresses/accounts in reproducible examples. Report security issues privately
to the maintainers instead of posting secrets in a public issue.

Read [Private information and public Git](docs/security/private-information.md)
and enable the local pre-commit/commit-message checks before contributing.
Keep optional private denylists outside the checkout; CI must never receive
operator credentials. Hooks and CI supplement, not replace, a publication audit.

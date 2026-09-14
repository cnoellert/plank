# Publication preparation review

The Host/Client preparation histories were reviewed separately from the private
preservation repository. This is a source review, not authorization to change
repository visibility or publish existing binary packages.

## Scope and results

- Scanned all stored Git objects and commit metadata in the root, shared Client,
  Linux Host, transport, common-C, build dependencies, virtual-HID and ENet forks.
  The private credential dictionary remained outside Git. No supplied secret
  matched the reviewed copies.
- Removed remaining operator-specific documentation, authentication-test
  identities and network fixtures throughout their histories. Network-scope
  fixtures retain the private address classes their assertions require.
- Removed an obsolete upstream personal IDE settings file and changed a
  historical Client address hint to a reserved example.
- Preserved author names, the maintainer's GitHub noreply email, commit messages,
  commit counts and parent relationships in this final rewrite. License and
  public contributor attribution remain intact.
- Verified every rewritten commit against its previous tree with a narrow
  change allowlist. Current Client executable source is byte-identical; current
  Linux Host changes are limited to three test fixtures. Root executable source
  is unchanged; dependency references and baseline checks follow the new hashes.
- Verified all historical root submodule targets remain available in the
  corresponding maintained histories. Private infrastructure implementations
  and packaging remain excluded.
- Decoded root graphic/archive metadata was previously inspected; all seven
  retained graphic objects match that reviewed content exactly.
- Eleven focused authentication tests and four portable repository test entries
  pass. No package installation or live-session qualification was performed.

The Linux Host secret scanner retains five explicitly reviewed findings: test
or demo private keys and a documented API authentication example. They are not
production credentials. Other retained review hits include public upstream
attribution, generic examples, network-classification constants, library version
numbers and code identifiers. Do not remove licenses or change functional
network constants to make heuristic counts reach zero.

## Publication boundaries

The eight maintained preparation histories use the maintainer's noreply address.
Independent private replacements for common-C, build-deps, libvirtualhid and
ENet remove personal email attribution without changing the already-public
repositories. Author names, dates, commit messages, branch relationships,
executable source and license notices are preserved. Commit hashes change;
cryptographic signatures on rewritten commits cannot remain valid.

Maintained dependency URLs, historical gitlinks and executable baseline pins
follow the replacement histories. Historical references to external upstream
repositories retain their original URLs and hashes together. The replacement
build-deps and libvirtualhid repositories expose the existing Host branch hint
as an alias of the retained product branch, without adding a source commit.
Copied legacy Actions workflows are disabled on the four new private remotes.
Public upstream contributor attribution is not anonymized.

Preparation remotes remain private. Their GitHub releases, issues, commit
comments, uploaded Actions artifacts and caches were empty at review time;
available root workflow logs had no known-secret or private-deployment match.
Already-public upstream dependency release assets and hosted build artifacts
are a separate distribution surface, not cleared by this source review.

History rewriting does not prove that a hosting service has purged old objects,
logs or cached views. Before public visibility, use a genuinely new destination
populated only with audited refs, or obtain hosting-provider removal of the
previous sensitive object sets. Never publish the original preservation copy
or older preparation repositories that received private implementations.

Review credential rotation independently. A scanner cannot prove that an
unknown secret never existed. Raw binary scans do not exhaustively decode every
historical third-party executable or archive. Existing signed release packages
also need their own metadata review; signing identities are inherently public.

The existing 1.0.100 packages retain their original source provenance. Do not
relabel or edit their manifests to name rewritten commits. The final-source
1.0.101 rebuild passed all four package gates and both Mac notarization gates.
Its extracted payloads have no supplied-password matches, but all four products
retain private build-path strings in binaries. These assets are NOT cleared for
public distribution. Reproducibly remove that metadata in the affected compiler
and prepared dependency builds, increment the version, and repeat payload review
and hardware/session acceptance before public binary release.

Final destinations are newly created private repositories populated only with
audited heads. Six unrequested update branches in preparation copies were not
transferred. No old GitHub release assets, Actions artifacts, issues or caches
were imported. Only the root privacy workflow is enabled; inherited companion
Actions workflows remain disabled. Explicit approval is still required before
changing any repository's visibility.

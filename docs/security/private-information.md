# Private information and public Git

Treat every tracked file, filename, commit message, issue, screenshot and CI log
as public-facing. This includes AGENTS.md and HANDOFF.md. Do not put operational
notes inside a checkout, even in an ignored directory. Git ignore rules are not
a security boundary and do not remove previously committed data.

## Storage boundary

| Information | Location |
| --- | --- |
| Passwords and tokens | Password manager or OS Keychain; SSH keys through an SSH agent |
| Deployment inventory, account names and private troubleshooting notes | `~/.local/share/plank/private-notes/` |
| Private audits and unsanitized evidence | `~/.local/share/plank/private-audit/` |
| Machine-specific build paths | `~/.config/plank-builder/paths.env` |
| Public architecture, reproducible examples and sanitized results | The repository |

Private directories must be owned by the operator and mode `0700`; files must
be `0600`. Keep encrypted backups separately. These permissions protect against
other ordinary local accounts, not root or a compromised login. Do not upload
private notes as issue attachments, Actions artifacts, release assets or support
bundles. Move any private runtime/build captures out of ignored repository
artifact directories before sharing a checkout or preparing publication.

Temporary password-audit lists also stay outside Git, owner-only. They are not
a long-term credential store. Never copy a credential into a public denylist.

Use role names (Linux Host builder, Client builder, hardware test Host, development
Mac), environment-driven paths and reserved examples such as `host.example.org`,
`192.0.2.10`, `198.51.100.20`, `203.0.113.30` and `2001:db8::10`. Keep the actual
role-to-machine mapping in private notes. Do not infer a test target from an old
public document. Preserve public upstream attribution and functional network
classification constants; they are not private deployment inventories.

## Local prevention

Install Gitleaks from its official release distribution. CI uses version
**8.30.1** with the Linux archive SHA-256 pinned in its workflow. Other platforms
must select the matching official release asset and verify its checksum. Do
not download a scanner or transmit any source during the commit hook itself.

From the root checkout:

```sh
python3 scripts/maintenance/install-privacy-hooks.py
```

This enables the tracked `.githooks/pre-commit` and `.githooks/commit-msg` hooks
for this local repository. It refuses to bypass existing hooks. Each new clone
must opt in; Git does not automatically enable repository-supplied hooks. Linked
worktrees use their own checked-out hook files: an older snapshot without these
files is not protected by this relative hook path.

Optionally configure a **local Git setting**, never a tracked setting, pointing
to an owner-only external file containing one exact sensitive value per line:

```sh
git config --local plank.privateDenylist "$PRIVATE_AUDIT_FILE"
```

Set `PRIVATE_AUDIT_FILE` locally to the absolute path. Do not put its contents on
the command line. Blank lines and comments are ignored. Literal values and
selected base64/hex encodings are checked; common words such as `password` are
not treated as standalone secrets. This private dictionary supplements generic
secret detection. A configured missing, inaccessible or unsafe list blocks the
check; CI does not receive the list and does not require one.

The pre-commit check inspects the index, not unstaged working files. It checks
private filenames, known values in whole changed blobs, and newly added text.
Gitleaks supplies general secret detection. Added documentation and commit
messages also reject common deployment identifiers, personal home paths and
non-example IPv4 literals. Canonical network definitions and loopback/listen
addresses are allowed. Source code's network constants are not rewritten or
indiscriminately prohibited. These are heuristics, not comprehensive privacy
classification (for example, arbitrary usernames and IPv6 require review).

Diagnostics show only rule IDs and locations, never matched values or source
excerpts. Hooks fail closed if required tools fail. Fix the content instead of
bypassing the check. Commit messages are checked separately before Git saves the
commit. A local hook can still be bypassed; it is not an access-control boundary.

## CI and repository scope

The `Private information checks` workflow checks new commits, including their
messages and changes that introduce a value and remove it again before the final
tree. A newly pushed branch is checked from its beginning. It has read-only
repository permission, does not use a privileged PR trigger, and does not upload
scanner reports or source. The scanner download is checksum-pinned.

Configure this check as required in branch protection when preparing the public
repository. Adding the workflow alone does not configure server-side branch
protection. Scanner/policy/workflow changes need security-conscious review.

These root checks do **not** scan submodule histories through a gitlink. Maintained
forks need equivalent checks in their own repositories before publication. The
private audit must inspect each referenced history independently. Existing
historical findings, ignored files, binary/media content, external hosting
metadata and release artifacts still require separate publication review.

## If information is committed

Stop publication. Revoke or rotate exposed credentials as appropriate. Preserve
the original privately for investigation, then sanitize a separate private copy
and verify every affected history and gitlink. A deletion commit, branch/tag
deletion or `.gitignore` change does not remove old versions. Do not rewrite a
shared repository or change visibility without explicit approval.

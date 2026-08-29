# Contributing

Thanks for considering a contribution!

## Dev prerequisites

- [OpenTofu](https://opentofu.org/docs/intro/install/) (or Terraform ≥ 1.6)
- [pre-commit](https://pre-commit.com/) + [gitleaks](https://github.com/gitleaks/gitleaks/releases) + `shellcheck`
- `jq` (for the admin scripts)

```bash
pre-commit install     # run the same checks as CI on every commit
```

## Before you push

CI (`.github/workflows/ci.yml`) runs on every PR and enforces:

```bash
tofu fmt -check -recursive iac                                   # formatting
tofu -chdir=iac/prod init -backend=false && tofu -chdir=iac/prod validate
tofu -chdir=iac/vault-config init -backend=false && tofu -chdir=iac/vault-config validate
shellcheck -S warning -e SC1083,SC2154 $(git ls-files '*.sh')
```

Please run these locally first — PRs that fail CI won't be merged.

## Ground rules

- **Never commit secrets** — no real tfvars, tfstate, keys, certs, tokens.
  If a secret slips into a PR, flag it immediately so maintainers can rotate.
  See [SECURITY.md](SECURITY.md).
- Keep modules composable: the standard variable set
  (`prefix`, `project`, `environment`, `region`, `region_code`,
  `responsible_party`, `owner`) + pinned `required_providers` blocks stay.
- Conventional-ish commit subjects (`feat:`, `fix:`, `docs:`, `security:` …).
- Docs changes belong in `docs/`; keep examples placeholder-only
  (`example.com`, `<your-public-ip>`).

## Suggested flow

1. Fork → branch (`feat/my-thing`)
2. Commit (pre-commit runs) → push → open a PR
3. Keep PRs small and described; link any related issue

## Code of conduct

Be decent: no harassment, no personal attacks, no doxxing (that includes
posting anyone's real infrastructure details). Maintainers may remove
content or participants who can't.

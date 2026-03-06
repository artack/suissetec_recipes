# AGENTS.md

## Project Purpose
This repository hosts private Symfony Flex recipes for internal packages.

## Current Architecture
- Source recipes live under `<vendor>/<package>/<version>/` at repository root.
- Compiled recipe artifacts live under `build/`.
- Flex endpoint index is `index.json` at repository root.
- Optional package aliases are stored in `aliases.json` at repository root.

## Required Directory Convention
Create recipes with this structure:

- `<vendor>/<package>/<version>/manifest.json`
- `<vendor>/<package>/<version>/<any other files referenced by the recipe>`

Example:

- `suissetec/sso-auth-bundle/0.1/manifest.json`

## Compile Workflow (Mandatory)
Do not edit compiled files manually.

Run:

```bash
./compile-recipes.sh
```

What it updates:

1. `build/<vendor>.<package>.<version>.json` compiled artifacts.
2. `index.json` recipes map and endpoint link templates.
3. `aliases.json` deterministic aliases (`vendor-package`) while preserving valid custom aliases.

## Flex Endpoint Configuration (Consumers)
Use this endpoint in consuming app `composer.json`:

- `https://api.github.com/repos/artack/suissetec_recipes/contents/index.json?ref=main`

Example:

```json
{
  "extra": {
    "symfony": {
      "endpoint": [
        "https://api.github.com/repos/artack/suissetec_recipes/contents/index.json?ref=main",
        "flex://defaults"
      ]
    }
  }
}
```

## Important Technical Constraints
- Compiled file payloads in `build/*.json` must be Base64 (`files.*.contents`).
- If plain text is written there, Flex may produce binary garbage files in consumer projects.
- `env` entries are defined in source `manifest.json` and are applied by Flex during install.

## Publishing Checklist
1. Edit source recipe files under `<vendor>/<package>/<version>/`.
2. Run `./compile-recipes.sh`.
3. Verify generated outputs in `build/`, `index.json`, and `aliases.json`.
4. Commit source + generated artifacts together.
5. Push to `main`.

## Recovery (If consumer config files are corrupted)
In the consuming Symfony project:

```bash
rm config/packages/suissetec_sso_auth.yaml config/routes/suissetec_sso_auth.yaml
composer clear-cache
composer recipes:install suissetec/sso-auth-bundle --force -v
```

## Agent Guardrails
- Treat root recipe directories (`<vendor>/<package>/<version>/`) as source of truth.
- Avoid manual edits in `build/`.
- Keep `index.json` at root level.
- Keep recipe template URLs aligned with `build/{package_dotted}.{version}.json`.
- Preserve existing custom aliases in `aliases.json` unless intentionally removing them.

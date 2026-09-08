# suissetec_recipes

Symfony Flex **PUBLIC** recipe repository.

## Endpoint

Use this endpoint in consumer `composer.json`:

- `https://api.github.com/repos/artack/suissetec_recipes/contents/index.json?ref=main`

```json
{
  "extra": {
    "symfony": {
      "allow-contrib": true,
      "endpoint": [
        "https://api.github.com/repos/artack/suissetec_recipes/contents/index.json?ref=main",
        "flex://defaults"
      ]
    }
  }
}
```

### `allow-contrib` is not optional here

Every recipe in this repository is served as a **contrib** recipe (`index.json` sets
`is_contrib: true`). Without `allow-contrib`, Flex does not apply any of them:

- non-interactively (CI, `composer --no-interaction`) it prints
  `- IGNORING <package> (<recipe url>)` and **installs no recipe at all**;
- interactively it prints `WARNING` and asks - and the answer **defaults to no**, so a
  plain Enter skips the recipe too.

Either way the package installs and the recipe does not, with nothing missing at that
moment. The application notices later, when the configuration the recipe was supposed to
write is absent and it fails to boot - typically far away from the `composer require` that
caused it.

To catch up in a project where recipes were skipped:

```bash
composer recipes:install <vendor/package> --force -v
```

Flex keeps such a package in `symfony.lock` without recipe information, so this works
after the fact. `SYMFONY_ALLOW_CONTRIB=1` in the environment does the same job as the
`composer.json` flag - useful in CI images.

## Source layout

Recipes are authored as source files in:

- `vendor/package/version/manifest.json`
- `vendor/package/version/config/...` (or any other files copied by the recipe)

Example:

- `suissetec/sso-auth-bundle/0.1/manifest.json`

## Compile step

Yes, a compile step is required.

Run:

```bash
./compile-recipes.sh
```

What it does:

1. Scans all `vendor/package/version` directories containing `manifest.json`.
2. Writes compiled artifacts to `build/vendor.package.version.json`.
3. Base64-encodes file payloads for Flex (`files.*.contents`).
4. Rebuilds `index.json` `recipes` map from discovered source recipes.
5. Regenerates `aliases.json` with one deterministic alias per package (`vendor-package`) and preserves valid existing custom aliases.
6. Keeps `index.json` at repo root and sets `_links.recipe_template` to GitHub API `contents/build/{package_dotted}.{version}.json?ref=main`.

This works for any number of vendors, packages and versions added to this repo.

## Publish workflow

1. Edit source recipe files.
2. Run `./compile-recipes.sh`.
3. Commit source changes plus generated `build/*.json` artifacts and `index.json`.
4. Push to `main`.

## If consumer files were corrupted previously

If an older compiled artifact had non-Base64 file payloads, recover in consumer project:

```bash
rm config/packages/suissetec_sso_auth.yaml config/routes/suissetec_sso_auth.yaml
composer clear-cache
composer recipes:install suissetec/sso-auth-bundle --force -v
```

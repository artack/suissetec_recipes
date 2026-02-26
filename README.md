# suissetec_recipes

Public Symfony Flex recipe repository for `suissetec/sso-auth-bundle`.

## Repository layout

- `index.json`: Flex endpoint index
- `aliases.json`: optional package aliases
- `suissetec.sso-auth-bundle.0.1.json`: compiled recipe artifact served by `recipe_template`
- `suissetec/sso-auth-bundle/0.1/`: source recipe (manifest + copied config files)

## Endpoint URL

Use:

- `https://api.github.com/repos/artack/suissetec_recipes/contents/index.json?ref=main`

## Consumer setup

In consuming app `composer.json`:

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

Then install with Docker Composer:

```bash
docker compose exec php composer require suissetec/sso-auth-bundle:^0.1
```

## Notes

- Recipe auto-creates env config, `config/packages/suissetec_sso_auth.yaml` and `config/routes/suissetec_sso_auth.yaml`.
- `security.yaml` firewall wiring for the authenticator is still manual.

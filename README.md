# suissetec_recipes

Private Symfony Flex recipe repository for `suissetec/sso-auth-bundle`.

## Repository layout

- `index.json`: Flex endpoint index
- `aliases.json`: optional package aliases
- `suissetec.sso-auth-bundle.0.1.json`: compiled recipe artifact served by `recipe_template`
- `suissetec/sso-auth-bundle/0.1/`: source recipe (manifest + copied config files)

## Endpoint URL

Use:

- `https://raw.githubusercontent.com/artack/suissetec_recipes/main/index.json`

## Consumer setup

In consuming app `composer.json`:

```json
{
  "extra": {
    "symfony": {
      "endpoint": [
        "https://raw.githubusercontent.com/artack/suissetec_recipes/main/index.json",
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

- Recipe auto-creates `config/packages/suissetec_sso_auth.yaml` and `config/routes/suissetec_sso_auth.yaml`.
- `security.yaml` firewall wiring for the authenticator is still manual.

# ACME storage

Before first run, create `acme.json` for Let's Encrypt certificates:

```bash
touch acme.json && echo '{}' > acme.json && chmod 600 acme.json
```

Do not commit `acme.json` to version control.

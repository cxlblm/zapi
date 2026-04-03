# Zapi

`Zapi` is a local-first Swift foundation for building a macOS API client inspired by RapidAPI for Mac / Paw.

This repository currently focuses on the local features only:

- native macOS desktop app shell built with SwiftUI
- request collections
- environments and variable interpolation
- HTTP request execution
- response history
- local JSON persistence
- local secret storage via Keychain

It intentionally does not include any cloud sync, team collaboration, hosted mocks, or marketplace features.

## What is implemented

The current package gives you the core layer needed for a native macOS app:

- `ZapiApp`, a runnable SwiftUI macOS client
- `APIProject`, `APICollection`, `APIRequest`, `APIEnvironment`
- `EnvironmentResolver` with `{{variable}}` interpolation
- `RequestExecutor` powered by `URLSession`
- `LocalProjectStore` that persists a project document to disk
- `KeychainSecretStore` for local credential persistence
- a local smoke-check executable for interpolation, persistence, and request execution

## RapidAPI for Mac feature mapping

Covered in this first cut:

- three-column macOS app shell
- local request editing model
- local environments
- local history
- Bearer / Basic / API Key auth helpers
- raw/json/form-urlencoded request bodies
- headers, query items, timeout, redirect policy
- response snapshots

Not covered yet:

- tabs/sidebar/editor layout
- code generation
- OAuth helper flows
- cookie jar visualization
- certificates UI
- scripting/extensions
- OpenAPI import/export
- response inspectors for JSON/XML/HTML

## Suggested roadmap

1. Add a SwiftUI macOS app shell on top of `ZapiCore`.
2. Add request tabs and a sidebar for collections/environments.
3. Add request chaining and response-derived dynamic variables.
4. Add import/export for cURL and OpenAPI.
5. Add auth helpers for Basic, Bearer, OAuth 2, and AWS SigV4.

## Launch the app

```bash
swift run ZapiApp
```

## Build a Real `.app` Bundle

If you want a real macOS app bundle instead of a SwiftPM-run executable process:

```bash
./Scripts/build-app.sh
```

This produces:

```text
dist/Zapi.app
```

You can then launch it with:

```bash
open dist/Zapi.app
```

Or use the helper:

```bash
./Scripts/open-app.sh
```

## Run smoke checks

```bash
swift run ZapiSmokeChecks
```

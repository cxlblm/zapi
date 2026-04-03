# AGENTS.md

This file defines the engineering expectations for agents and contributors working in this repository.

## Project Context

- Project type: Swift Package
- Primary product: local-first macOS API client
- UI stack: SwiftUI
- Core runtime: Foundation, URLSession, Security, AppKit
- Current philosophy: keep the app local, native, and dependency-light unless a mature tool clearly improves quality

## Core Engineering Principles

- Prefer small, composable types over large god objects.
- Keep networking, persistence, and UI state clearly separated.
- Favor value types (`struct`, `enum`) for domain models unless reference semantics are required.
- Make local-first behavior the default. Do not introduce cloud, sync, or remote dependencies unless explicitly requested.
- Preserve native macOS behavior and conventions instead of forcing web-style UI patterns into SwiftUI.
- Optimize for maintainability, deterministic behavior, and debugging clarity over clever abstractions.

## Swift Best Practices

### Language and Modeling

- Use `struct` by default for models and view state.
- Use `enum` for closed sets of states such as auth mode, body mode, tabs, and request sections.
- Prefer explicit modeling over stringly typed state.
- Keep public API surfaces intentionally small.
- Use protocol abstractions only when they provide meaningful testability or separation, not by default.
- Prefer immutable data flow where possible; mutate in one well-defined owner.
- Avoid singletons unless the platform API strongly encourages them.

### Concurrency

- Use Swift Concurrency (`async`/`await`, `Task`, actors, `@MainActor`) instead of callback-heavy designs.
- Keep UI-facing state mutations on `@MainActor`.
- Use actors for persistence or shared mutable state that may be accessed concurrently.
- Avoid unsafe shared mutable global state.
- Cancel long-running tasks when view lifecycle or user intent changes.

### SwiftUI

- Keep views small and focused; extract reusable subviews when a view becomes hard to scan.
- Put business logic in model/controller objects, not directly in `View` bodies.
- Use bindings for form editing, but keep transformation logic centralized in the model layer.
- Avoid deeply nested conditional UI when a dedicated subview would be clearer.
- Preserve desktop information density; this is a macOS tool, not a mobile-first layout.
- Prefer native controls and platform behaviors before custom chrome.

### Networking

- Use `URLSession` as the default HTTP engine.
- Keep request building deterministic and testable.
- Represent auth, headers, query parameters, and body modes as explicit domain types.
- Never hardcode secrets in source files.
- Treat user-provided request definitions as data, not executable logic.
- Capture enough request/response metadata to make debugging easy.

### Persistence and Security

- Use local file persistence for workspace/project state unless explicitly asked otherwise.
- Use Keychain for secrets and sensitive credentials.
- Keep persisted formats human-inspectable where practical, such as JSON for local project documents.
- Avoid silent data loss; prefer explicit migration paths and conservative writes.

### Error Handling

- Use typed errors for domain and infrastructure boundaries.
- Surface user-meaningful error messages in the app UI.
- Preserve low-level error context when it helps debugging.
- Do not swallow errors unless there is a clear product reason.

### Testing

- Prefer deterministic tests over network-dependent tests.
- Stub `URLSession` behavior for request execution tests.
- Add coverage for parsing, environment interpolation, request construction, auth injection, and persistence round-trips.
- For UI-heavy work, combine lightweight unit coverage with manual smoke verification.

## Project Architecture Guidance

- `Sources/ZapiCore`: domain models, request execution, persistence, security helpers
- `Sources/ZapiApp`: SwiftUI app shell, view models, desktop UI
- Keep `ZapiCore` usable independently of the UI layer.
- New features should land in the core first when they represent reusable behavior, then be surfaced in the UI.
- Avoid letting `SwiftUI` types leak into `ZapiCore`.

## Coding Style

- Prefer clear names over shortened names.
- Keep functions focused on one responsibility.
- Avoid unnecessary comments; add comments only when intent is not obvious from the code.
- Prefer early returns for invalid or edge states.
- Keep files reasonably sized; split when a file becomes hard to reason about.
- Default to ASCII source unless non-ASCII is required.

## Mature Tools To Prefer

These are the default tools agents should consider before inventing custom workflows.

### Build and Package

- `swift build`
- `swift run`
- `swift package`
- `xcodebuild`
- `./Scripts/build-app.sh`

Use Swift Package Manager by default. Use `xcodebuild` when validating a real macOS app target, scheme behavior, signing behavior, or UI-specific build flows.
Use `./Scripts/build-app.sh` in this repository when you need a real local `.app` bundle without relying on `swift run`.

### Formatting and Linting

- `SwiftFormat`
- `SwiftLint`

Recommended conventions:

- Use `SwiftFormat` for mechanical formatting.
- Use `SwiftLint` for style and common correctness checks.
- If config files are added later, prefer repository-local config over global machine config.

### Testing

- `swift test`
- `xcodebuild test`
- Swift Testing
- XCTest

Use the tool that matches the active target structure:

- For pure package targets: prefer `swift test`.
- For app or UI-heavy targets: use `xcodebuild test`.
- Prefer Swift Testing for new package-native test suites when the local toolchain supports it.
- Use XCTest when platform integration or legacy compatibility makes it the better fit.

### Debugging and Diagnostics

- Xcode debugger
- Instruments
- Console.app
- `os.Logger`

Prefer structured logging over ad hoc `print` debugging for ongoing diagnostics.
Use Instruments for performance, allocations, leaks, and concurrency investigations.

### Quality and Maintenance

- `Periphery` for dead code detection
- `xcodebuild -showBuildSettings` for build diagnosis
- `plutil` for plist validation when plist files are introduced
- `defaults` only for targeted local macOS debugging, not as app persistence architecture

### API and Contract Tooling

- OpenAPI Generator
- Swagger Editor
- `curl`
- `jq`

Use these when import/export or API contract workflows are introduced.
Do not hand-roll parsers for common interchange formats if a mature tool already exists.

## Recommended Future Tooling Additions

These are not required today, but are good defaults when the project grows:

- `SwiftFormat` config: `.swiftformat`
- `SwiftLint` config: `.swiftlint.yml`
- CI build/test workflow using GitHub Actions
- snapshot testing only if UI churn stabilizes and screenshots become worth maintaining

## Change Expectations For Agents

- Before major edits, inspect existing architecture and preserve good patterns already in use.
- Do not introduce new dependencies casually.
- When adding a new tool, prefer mature, well-known, actively used tools over niche packages.
- When a tool is optional, document whether it is required for all contributors or only recommended.
- If the environment lacks a tool, degrade gracefully and note the missing capability.
- Keep the repo runnable with minimal setup.

## Default Validation Checklist

When making changes, aim to validate with the strongest relevant checks available:

1. `swift build`
2. `swift run ZapiApp` for app smoke verification
3. `./Scripts/build-app.sh` when validating the packaged macOS app bundle flow
4. `swift run ZapiSmokeChecks` when the smoke target still reflects current core behavior
5. Additional focused checks for the edited area

If a check cannot run because of toolchain or sandbox limits, say so explicitly.

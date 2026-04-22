# Nocterm

A Flutter-like TUI framework in Dart. Monorepo managed by Melos.

## Developer Commands

```bash
# Bootstrap all packages
melos bootstrap

# Run tests (all packages with test/ dir, sequential)
melos test

# Analyze with fatal-infos
melos analyze

# Format all packages
melos format

# Check formatting (CI-style)
dart format --output=none --set-exit-if-changed lib/ test/ example/

# Run a single example
dart run example/example.dart

# Run benchmarks
dart run benchmark/benchmark.dart
dart run benchmark/benchmark.dart --save  # save as new baseline

# Install git hooks
dart run hooksman
```

## CI Order

1. Format check (`dart format --output=none --set-exit-if-changed`)
2. Analyze (`dart analyze --fatal-infos`)
3. Test (`dart test --reporter expanded`)
4. Benchmarks (on main/PRs, with baseline comparison on PRs)

## Package Structure

- Root (`pubspec.yaml`): Core `nocterm` library — main entrypoint
- `packages/nocterm_cli`: CLI tools
- `packages/nocterm_nested`: Nested widget support
- `packages/nocterm_provider`: Provider integration
- `packages/nocterm_riverpod`: Riverpod support
- `packages/nocterm_web`: Flutter web build (publish_to: none)

## Release

```bash
just release   # interactive — updates pubspec, README, landing, commits, tags, pushes
```

## Notes

- Git hooks managed by `hooksman` — pre-commit formats Dart files only (no analyze/test)
- Example files (`example/*.dart`) are runnable demos, not tests
- Analysis excludes: `example/legacy_demos/**`, `third_party/**`, `packages/**`
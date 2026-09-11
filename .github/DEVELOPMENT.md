# Development Guidelines

## Pre-commit Hook

This repository includes a pre-commit hook that runs automatically before each commit. The hook performs the following checks:

1. **Runs tests**: `crystal spec`
2. **Runs linter**: `ameba`

If any check fails, the commit will be aborted.

### Installation

The pre-commit hook is not automatically installed when cloning the repository. To install it:

```bash
# Copy the pre-commit hook to your local .git/hooks directory
cp hooks/pre-commit .git/hooks/pre-commit

# Make it executable
chmod +x .git/hooks/pre-commit
```

### Bypassing the Hook

If you absolutely need to bypass the pre-commit hook (not recommended), you can use:
```bash
git commit --no-verify
```

### Troubleshooting

If the hook fails:
1. Fix any failing tests
2. Address any linting issues reported by ameba
3. Stage your changes again and retry the commit

Note: the hook invokes the `ameba` binary from your PATH (install it with your
package manager, e.g. `pacman -S ameba` or build it from the `lib/ameba`
checkout that `shards install` provides). Use a version compatible with your
Crystal compiler.

## CI/CD Pipeline

The CI pipeline runs on every push and pull request to the main branch. It includes:
- Crystal installation (tracks `crystal: latest`)
- Dependency installation (`shards install`)
- Format check (`crystal tool format --check`)
- Tests (`crystal spec`)
- Linting (`ameba`, built from the locked `lib/ameba` checkout)

A separate workflow deploys the project site on every push to `main`: the
handcrafted landing page at the root of GitHub Pages and the mkdocs
documentation under `/docs/`.
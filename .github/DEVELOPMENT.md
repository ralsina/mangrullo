# Development Guidelines

## Pre-commit Hook

This repository includes a pre-commit hook that runs automatically before each commit. The hook performs the following checks:

1. **Runs tests**: `crystal spec`
2. **Runs linter**: `ameba`

If any check fails, the commit will be aborted.

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

## CI/CD Pipeline

The CI pipeline runs on every push and pull request to the main branch. It includes:
- Crystal installation
- Dependency installation (`shards install`)
- Format check (`crystal tool format --check`)
- Tests (`crystal spec`)
- Linting (`ameba`)
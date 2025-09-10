# Mangrullo

[![Crystal CI](https://github.com/ralsina/mangrullo/workflows/Crystal%20CI/badge.svg)](https://github.com/ralsina/mangrullo/actions)
[![GitHub release](https://img.shields.io/github/v/release/ralsina/mangrullo)](https://github.com/ralsina/mangrullo/releases)
[![License](https://img.shields.io/github/license/ralsina/mangrullo)](https://github.com/ralsina/mangrullo/blob/main/LICENSE)

Mangrullo is a Docker container update automation tool written in Crystal.

## Development Setup

After cloning the repository, install the pre-commit hook to ensure code quality:

```bash
# Install dependencies
shards install

# Install pre-commit hook
cp hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

The pre-commit hook runs tests and linting before allowing commits.

## Documentation

The full documentation for this project is available on our [GitHub Pages site](https://USER.github.io/mangrullo/).

The documentation is automatically built from the files in the `docs` directory.

See [Development Guidelines](.github/DEVELOPMENT.md) for more detailed development information.

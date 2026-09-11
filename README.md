# Mangrullo

[![Crystal CI](https://github.com/ralsina/mangrullo/workflows/Crystal%20CI/badge.svg)](https://github.com/ralsina/mangrullo/actions)
[![GitHub release](https://img.shields.io/github/v/release/ralsina/mangrullo)](https://github.com/ralsina/mangrullo/releases)
[![License](https://img.shields.io/github/license/ralsina/mangrullo)](https://github.com/ralsina/mangrullo/blob/main/LICENSE)

Mangrullo is a Docker container update automation tool written in Crystal.

## Building

```bash
# Install dependencies
shards install

# Build both binaries: bin/mangrullo (CLI) and bin/mangrullo-web (web UI)
shards build
```

Run the CLI (`bin/mangrullo --help`) or the web interface (`bin/mangrullo-web`,
then open http://localhost:3000).

## Development Setup

After cloning the repository, install the pre-commit hook to ensure code quality:

```bash
# Install pre-commit hook
cp hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

The pre-commit hook runs tests and linting before allowing commits (it needs
`crystal` and `ameba` on your PATH).

## Documentation

- **Project site**: [ralsina.github.io/mangrullo](https://ralsina.github.io/mangrullo/) — the landing page
- **Documentation**: [ralsina.github.io/mangrullo/docs](https://ralsina.github.io/mangrullo/docs/) — deployment, configuration, and design docs, built automatically from the `docs` directory

See [Development Guidelines](.github/DEVELOPMENT.md) for more detailed development information.

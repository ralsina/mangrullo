# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Crystal Language project called "mangrullo" - currently in early development with a basic module structure. The project follows standard Crystal conventions with a main module in `src/mangrullo.cr` and specs in the `spec/` directory.

## Development Commands

### Building and Running
- `crystal build src/mangrullo.cr` - Compile the project
- `crystal run src/mangrullo.cr` - Run the main file
- `crystal tool format` - Format code according to Crystal style guidelines

### Testing
- `crystal spec` - Run all tests
- `crystal spec spec/mangrullo_spec.cr` - Run specific test file
- `crystal spec --verbose` - Run tests with detailed output

### Dependencies
- `shards install` - Install dependencies (when dependencies are added to shard.yml)
- `shards build` - Build using shards (when the project grows)

## Project Structure

- `src/mangrullo.cr` - Main module file with VERSION constant
- `spec/mangrullo_spec.cr` - Test file (currently has a placeholder failing test)
- `spec/spec_helper.cr` - Test configuration
- `shard.yml` - Project configuration and dependencies

## Code Style

Follow Crystal Language conventions:
- Use 2-space indentation
- Module names are CamelCase
- Constants are UPPER_SNAKE_CASE
- Method names are snake_case

## Current State

The project is in a very early stage with:
- Basic module structure in place
- Placeholder test that currently fails
- No dependencies specified in shard.yml
- Standard Crystal project layout

## Crystal Version

This project requires Crystal >= 1.16.3 (developed with Crystal 1.17.1).
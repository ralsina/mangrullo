# JavaScript Linting

This project includes JavaScript syntax checking to catch errors before deployment.

## Setup

The linting tools are configured via:
- `.eslintrc.json` - ESLint configuration
- `package.json` - NPM dependencies and scripts
- `check-syntax.js` - Custom syntax checker for ECR templates
- `Makefile` - Build targets including linting

## Usage

### Check JavaScript syntax
```bash
make lint
# or
node check-syntax.js
```

### Full build with linting
```bash
make all
```

### Run ESLint for style checks (optional)
```bash
npm run lint
```

## How it works

The `check-syntax.js` script:
1. Extracts JavaScript code from ECR template files
2. Writes it to a temporary file
3. Uses Node.js's built-in syntax checker to validate syntax
4. Reports any syntax errors found

This catches syntax errors like:
- Mismatched quotes
- Missing brackets or parentheses
- Invalid JavaScript syntax

## Error:820 Issue

The original error at line 820 was a runtime JavaScript error, not a syntax error. The syntax checker would have caught it if it were a syntax issue. Runtime errors typically occur when:
- Functions are called with incorrect parameters
- DOM elements don't exist when accessed
- Template literals have incorrect escaping
- Variables are undefined when accessed
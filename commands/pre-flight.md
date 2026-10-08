---
allowed-tools: Bash(git diff:*), Bash(git status:*), Bash(PYTHONPATH=*), Bash(uv run ruff:*)
description: Use before committing, after finishing a chunk of work, or when the user says "ready to commit" or "check this" - runs lint, format, test, and safety scan on changed files only
---

## Context

- Changed files (staged + unstaged): !`git diff --name-only HEAD`
- Staged files: !`git diff --staged --name-only`

## Your task

Run targeted pre-commit checks on changed files only. This is faster than `make pre-commit` and catches the most common issues.

### Step 1: Identify changed Python files

From the context above, filter to only `.py` files. If there are no changed Python files, report "No Python files changed — nothing to check" and stop.

### Step 2: Lint check

Run ruff check on changed Python files only:
```bash
uv run ruff check <file1> <file2> ...
```

### Step 3: Format check

Run ruff format check on changed Python files only:
```bash
uv run ruff format --check <file1> <file2> ...
```

### Step 4: Safety scan on staged files

Use the Grep tool to check staged files for:
- `print(` — debug prints left in (ignore if inside a logging/test file)
- `breakpoint()` — debugger statements
- `import pdb` — debugger imports
- Strings that look like secrets: patterns containing `password=`, `secret=`, `token=`, `api_key=` with literal values (not env vars)

Also check if any of these are staged:
- `.env` files
- Files with `credential`, `secret`, or `key` in the filename

### Step 5: Run relevant tests

Map changed source files to test files:
- `src/pkg/foo.py` → `tests/test_foo.py`
- `src/pkg/routes/bar.py` → `tests/test_api/test_bar.py`

Follow the project's own source-to-test layout.

Run only the matching test files:
```bash
PYTHONPATH=. uv run pytest <test_file1> <test_file2> ... -q --tb=short
```

If no matching test files are found, say so but don't run the full suite.

### Step 6: Report

Present results as:

| Check | Result |
|-------|--------|
| Ruff lint | PASS/FAIL (N issues) |
| Ruff format | PASS/FAIL (N files) |
| Safety scan | PASS/FAIL (details) |
| Tests | PASS/FAIL (N passed, N failed) |

If all pass: "Pre-flight passed — ready to commit."
If any fail: Show details for each failure.

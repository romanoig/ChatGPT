# CLAUDE.md

This file gives guidance to Claude Code (and other AI assistants) when working in
this repository.

## Current repository state

**This repository is currently empty.** As of the latest commit it contains no
application source code, build configuration, tests, or documentation. The only
tracked file besides this one is `main`, a 1-byte placeholder (a single newline)
created by the initial commit.

There is therefore **no codebase structure, build system, or development workflow
to document yet.** Do not infer or invent an architecture — none exists. When asked
about "the code," state plainly that the repo is a blank slate.

- Repository name: `ChatGPT` (`romanoig/chatgpt` on GitHub)
- Default branch: `main`
- Tracked files: `main` (placeholder), `CLAUDE.md` (this file)

## When code is added

Once real code lands, **update this file** so it accurately describes the project.
At minimum, capture:

- **What the project is** — its purpose and the problem it solves.
- **Tech stack** — language(s), framework(s), and major dependencies.
- **Layout** — top-level directories and what lives in each.
- **Build / run / test** — the exact commands to install dependencies, build,
  run locally, and run the test suite (with lint/typecheck commands).
- **Conventions** — formatting, naming, commit-message style, and any patterns
  the project expects contributors to follow.

Keep this document in sync with reality. An out-of-date CLAUDE.md is worse than a
short, accurate one — prefer to document only what you can verify in the repo.

## Git workflow

- Create a feature branch for changes; do not commit directly to `main` unless
  explicitly asked.
- Write clear, descriptive commit messages.
- Push with `git push -u origin <branch-name>`.
- Do **not** open a pull request unless explicitly requested.

## Notes for AI assistants

- Verify claims against the actual files before stating them. Because the repo is
  empty, there is currently nothing to read — say so rather than guessing.
- This file should be the first thing updated when the project gains real content.

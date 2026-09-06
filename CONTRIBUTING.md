# Contributing

This project is in its planning stage. Contributions should first improve the documentation or open an issue describing the problem and proposed smallest solution.

Do not include real financial data, bank exports, API keys, or credentials in issues, pull requests, tests, or screenshots.

Keep changes focused. Finance calculations, import behavior, and spreadsheet-format changes require a runnable test once implementation begins.

## AI-agent pull requests

AI-assisted pull requests are welcome when they meet all of these rules:

- Declare the AI assistance and identify the human reviewer in the pull request template.
- Explain the user problem, the smallest change made, and anything intentionally not implemented.
- Follow [AGENTS.md](AGENTS.md) and update the relevant documentation when changing an established decision.
- Include a runnable test for non-trivial finance, import, security, or data-migration logic.
- Do not submit broad rewrites, generated dependency updates, or new services without a linked issue and explicit maintainer approval.
- Never include real financial data, credentials, OAuth tokens, private prompts, or tool logs containing sensitive information.
- A human must inspect the final diff, test results, dependency changes, and license compatibility before merge.

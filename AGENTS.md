# Agents

Guidelines for AI agents working on this codebase.

- Write tests for new behaviour; run existing tests before committing
- Update relevant documentation (README, USAGE, ARCHITECTURE, TODO, example READMEs, CHANGELOG)
- Keep README concise — detailed usage belongs in USAGE.md
- Keep documentation minimal — don't be wordy
- Consistent style with existing code and docs
- Commit as you go with descriptive messages
- Don't over-engineer — keep it simple
- Run `RUBY_BOX=1 bundle exec rake` to run all tests (unit, e2e, examples)
- Run `bundle exec rake format` to format code after every change
- Fix any warnings
- Use sub-agents where appropriate
- Never bump version or publish gem

# Agents

Guidelines for AI agents working on this codebase.

- Update `CHANGELOG.md` for user-facing changes
- Write tests for new behaviour; run existing tests before committing
- Update relevant documentation (README, ARCHITECTURE, TODO, example READMEs)
- Keep documentation minimal — don't be wordy
- Consistent style with existing code and docs
- Commit as you go with descriptive messages
- Don't over-engineer — keep it simple
- Run `RUBY_BOX=1 rake test` and `RUBY_BOX=1 ruby test/e2e/run.rb` to verify

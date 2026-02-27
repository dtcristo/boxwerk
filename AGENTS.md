# Agents

Guidelines for AI agents working on this codebase.

- Write tests for new behaviour; run existing tests before committing
- Update relevant documentation (README, ARCHITECTURE, TODO, example READMEs, CHANGELOG)
- Keep documentation minimal — don't be wordy
- Consistent style with existing code and docs
- Commit as you go with descriptive messages
- Don't over-engineer — keep it simple
- Run `RUBY_BOX=1 bundle exec rake test` and `RUBY_BOX=1 bundle exec rake e2e` to verify
- Run `cd examples/simple/ && RUBY_BOX=1 bin/boxwerk run app.rb` and `cd examples/simple/ && RUBY_BOX=1 bin/boxwerk exec --all rake test` to verify example
- Run `bundle exec rake fmt` to format code after every change
- Run `bundle exec rake fmt_check` to verify formatting is clean
- Fix any warnings
- Use sub-agents where appropriate
- Never bump version or publish gem

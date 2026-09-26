.PHONY: install test validate

install:
	@mise exec -- ./bin/install

test:
	@mise exec -- ./test/install_test.sh
	@mise exec -- sh ./test/mermaid_test.sh

validate:
	@mise exec -- ./bin/validate-skills

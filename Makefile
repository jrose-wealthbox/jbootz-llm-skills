.PHONY: install test

install:
	@./bin/install

test:
	@./test/install_test.sh
	@sh ./test/mermaid_test.sh

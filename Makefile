.PHONY: dev test contracts lint verify

dev:
	docker compose -f infrastructure/compose/compose.yaml up --build

test:
	$(MAKE) -C services/api test
	$(MAKE) -C services/agent test

contracts:
	$(MAKE) -C services/api contracts

lint:
	$(MAKE) -C services/api lint
	$(MAKE) -C services/agent lint

verify: lint test contracts
	python3 scripts/verify_repo.py


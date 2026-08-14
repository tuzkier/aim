PYTHON ?= python3
export PYTHONPATH := $(CURDIR)/src

.PHONY: test lint contracts migrate

test:
	$(PYTHON) -m pytest

lint:
	$(PYTHON) -m compileall -q src tests
	@if command -v ruff >/dev/null 2>&1; then ruff check src tests; fi

contracts:
	$(PYTHON) scripts/export_contracts.py

migrate:
	alembic upgrade head

PYTHON ?= python3
export PYTHONPATH := $(CURDIR)/src

.PHONY: test lint contracts migrate

test:
	$(PYTHON) -m pytest

lint:
	$(PYTHON) -m compileall -q src tests
	@if command -v ruff >/dev/null 2>&1; then ruff check src tests; fi

contracts:
	$(PYTHON) -c 'import json; from pathlib import Path; from aim_api.main import app; target = Path("../../contracts/public-api/openapi.json"); target.parent.mkdir(parents=True, exist_ok=True); target.write_text(json.dumps(app.openapi(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")'

migrate:
	alembic upgrade head

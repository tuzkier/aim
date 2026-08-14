from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_required_project_roots_exist() -> None:
    required = [
        "apps/ios",
        "services/api",
        "services/agent",
        "contracts/public-api",
        "contracts/agent-tools",
        "content/pregnancy-tasks",
        "content/safety-rules",
        "content/hangzhou",
        "infrastructure/compose",
    ]
    missing = [path for path in required if not (ROOT / path).exists()]
    assert missing == []


def test_business_and_agent_boundaries_are_documented() -> None:
    readme = (ROOT / "README.md").read_text()
    assert "FastAPI DDD" in readme
    assert "Eve Agent Runtime" in readme
    assert "不拥有业务事实表" in readme


def test_local_compose_defines_only_the_first_infrastructure_dependency() -> None:
    compose = (ROOT / "infrastructure/compose/compose.yaml").read_text()
    assert "postgres:17-alpine" in compose
    assert "redis:" not in compose
    assert "kafka:" not in compose


"""Validate the repository's structural contracts before service-level checks."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


REQUIRED_PATHS = (
    "apps/ios",
    "services/api",
    "services/agent",
    "contracts/public-api",
    "contracts/agent-tools",
    "content/pregnancy-tasks",
    "content/safety-rules",
    "content/hangzhou",
    "infrastructure/compose",
)


def main() -> int:
    missing = [path for path in REQUIRED_PATHS if not (ROOT / path).exists()]
    if missing:
        print("Missing required repository paths:")
        print("\n".join(f"- {path}" for path in missing))
        return 1

    print(f"Repository structure passed ({len(REQUIRED_PATHS)} paths).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


"""附件文件的本地磁盘存储。

按编号前两位分目录，避免单个目录里文件过多。以后换对象存储时只替换这个类。
"""

from __future__ import annotations

import os
from pathlib import Path
from uuid import UUID


class LocalAttachmentStorage:
    def __init__(self, root: str | Path) -> None:
        self.root = Path(root)

    def _path(self, attachment_id: UUID) -> Path:
        text = str(attachment_id)
        return self.root / text[:2] / text

    def save(self, attachment_id: UUID, data: bytes) -> None:
        path = self._path(attachment_id)
        path.parent.mkdir(parents=True, exist_ok=True)
        # 先写临时文件再改名：写到一半进程被杀，也不会留下半张图。
        temporary = path.with_suffix(".part")
        temporary.write_bytes(data)
        os.replace(temporary, path)

    def read(self, attachment_id: UUID) -> bytes | None:
        path = self._path(attachment_id)
        return path.read_bytes() if path.exists() else None

    def delete(self, attachment_id: UUID) -> None:
        self._path(attachment_id).unlink(missing_ok=True)

    def list_files(self) -> list[tuple[UUID, float]]:
        found: list[tuple[UUID, float]] = []
        if not self.root.exists():
            return found
        for path in self.root.glob("*/*"):
            if path.suffix == ".part":
                continue
            try:
                found.append((UUID(path.name), path.stat().st_mtime))
            except ValueError:
                continue
        return found

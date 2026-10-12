"""业务日按北京时间，持久化的瞬时时间戳仍用 UTC。"""
from calendar import monthrange
from datetime import date, datetime, time
from zoneinfo import ZoneInfo

BEIJING = ZoneInfo("Asia/Shanghai")


def beijing_today(now: datetime | None = None) -> date:
    return (now or datetime.now(BEIJING)).astimezone(BEIJING).date()


def at_nine(day: date) -> datetime:
    return datetime.combine(day, time(9), tzinfo=BEIJING)


def add_months(day: date, months: int) -> date:
    number = day.year * 12 + day.month - 1 + months
    year, month = divmod(number, 12)
    month += 1
    return date(year, month, min(day.day, monthrange(year, month)[1]))

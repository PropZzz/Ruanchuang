from __future__ import annotations

from datetime import date, datetime
import re
from typing import Any


class IcsValidationError(ValueError):
    pass


def _unescape(value: str) -> str:
    return value.replace("\\n", "\n").replace("\\N", "\n").replace("\\,", ",").replace("\\;", ";").replace("\\\\", "\\")


def _escape(value: object) -> str:
    return str(value).replace("\\", "\\\\").replace(";", "\\;").replace(",", "\\,").replace("\n", "\\n")


def _parse_ics_datetime(value: str) -> tuple[str, int, int]:
    raw = value.strip()
    if raw.endswith("Z"):
        raw = raw[:-1]
    if len(raw) == 8 and raw.isdigit():
        return datetime.strptime(raw, "%Y%m%d").date().isoformat(), 0, 0
    for pattern in ("%Y%m%dT%H%M%S", "%Y%m%dT%H%M"):
        try:
            parsed = datetime.strptime(raw, pattern)
            return parsed.date().isoformat(), parsed.hour, parsed.minute
        except ValueError:
            continue
    raise IcsValidationError(f"Invalid ICS date/time: {value}")


def _duration_minutes(start: tuple[str, int, int], end_value: str | None, duration_value: str | None) -> int:
    if duration_value:
        match = re.fullmatch(r"P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?)?", duration_value.strip(), re.I)
        if not match:
            raise IcsValidationError(f"Invalid ICS duration: {duration_value}")
        days = int(match.group(1) or 0)
        hours = int(match.group(2) or 0)
        minutes = int(match.group(3) or 0)
        return max(1, days * 1440 + hours * 60 + minutes)
    if not end_value:
        return 60
    day, hour, minute = _parse_ics_datetime(end_value)
    start_day, start_hour, start_minute = start
    start_dt = datetime.fromisoformat(f"{start_day}T{start_hour:02d}:{start_minute:02d}")
    end_dt = datetime.fromisoformat(f"{day}T{hour:02d}:{minute:02d}")
    return max(1, round((end_dt - start_dt).total_seconds() / 60))


def parse_ics(text: str) -> list[dict[str, Any]]:
    if not isinstance(text, str) or "BEGIN:VCALENDAR" not in text:
        raise IcsValidationError("ICS content must contain BEGIN:VCALENDAR")
    physical = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    lines: list[str] = []
    for line in physical:
        if line.startswith((" ", "\t")) and lines:
            lines[-1] += line[1:]
        else:
            lines.append(line)
    events: list[dict[str, Any]] = []
    current: dict[str, str] | None = None
    for line in lines:
        if line == "BEGIN:VEVENT":
            if current is not None:
                raise IcsValidationError("Nested ICS events are not supported")
            current = {}
            continue
        if line == "END:VEVENT":
            if current is None:
                raise IcsValidationError("Unexpected END:VEVENT")
            start_raw = current.get("DTSTART")
            if not start_raw or not current.get("SUMMARY"):
                raise IcsValidationError("ICS event requires DTSTART and SUMMARY")
            day, hour, minute = _parse_ics_datetime(start_raw)
            duration = _duration_minutes((day, hour, minute), current.get("DTEND"), current.get("DURATION"))
            events.append(
                {
                    "id": current.get("UID") or f"ics-{len(events) + 1}",
                    "day": day,
                    "title": _unescape(current["SUMMARY"]),
                    "tag": _unescape(current.get("CATEGORIES", "Imported")),
                    "height": round(duration * 80 / 60, 2),
                    "color": 0,
                    "time": {"hour": hour, "minute": minute},
                    "repeat": "none",
                    "reminderMinutesBefore": 10,
                }
            )
            current = None
            continue
        if current is None or ":" not in line:
            continue
        name, value = line.split(":", 1)
        current[name.split(";", 1)[0].upper()] = value
    if current is not None:
        raise IcsValidationError("Unclosed ICS event")
    return events


def export_ics(entries: list[dict[str, Any]]) -> str:
    lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Ruanchuang//Schedule//EN"]
    for index, entry in enumerate(entries):
        day = str(entry.get("day") or date.today().isoformat()).replace("-", "")
        time = entry.get("time") or {}
        hour = int(time.get("hour", 0))
        minute = int(time.get("minute", 0))
        duration = max(1, round(float(entry.get("height") or 60.0) / 80 * 60))
        start = datetime.strptime(f"{day}{hour:02d}{minute:02d}", "%Y%m%d%H%M")
        end = start.fromtimestamp(start.timestamp() + duration * 60)
        lines.extend(
            [
                "BEGIN:VEVENT",
                f"UID:{_escape(entry.get('id') or f'export-{index + 1}')}",
                f"DTSTART:{start.strftime('%Y%m%dT%H%M%S')}",
                f"DTEND:{end.strftime('%Y%m%dT%H%M%S')}",
                f"SUMMARY:{_escape(entry.get('title') or '')}",
                f"CATEGORIES:{_escape(entry.get('tag') or 'Imported')}",
                "END:VEVENT",
            ]
        )
    lines.append("END:VCALENDAR")
    return "\r\n".join(lines) + "\r\n"

from __future__ import annotations

import time
from typing import final


@final
class DeadlineExceeded(RuntimeError):
    def __init__(self) -> None:
        super().__init__("30-minute acquisition budget exceeded")


def remaining_seconds(deadline_monotonic: float) -> float:
    remaining = deadline_monotonic - time.monotonic()
    if remaining <= 0:
        raise DeadlineExceeded
    return remaining


def enforce_deadline(deadline_monotonic: float) -> None:
    _ = remaining_seconds(deadline_monotonic)

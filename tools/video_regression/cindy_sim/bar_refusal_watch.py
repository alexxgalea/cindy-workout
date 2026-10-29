"""Line-by-line port of app/src/main/java/com/cindy/tracker/BarRefusalWatch.kt."""
from __future__ import annotations

from collections import deque


class BarRefusalWatch:
    """Notices that the bar is what is wrong, not the athlete.

    The engine tells this watch, on every frame it reads a pull-up, whether the bar refused it.
    When the bar has refused half of what it was shown across four seconds, it is asked to be
    forgotten and learned again from the next hang. An athlete who has stepped off the bar is refused
    for just as long, and the next hang they make is then taken for the bar: that is the price of
    being able to recover from a bar learned in the wrong place, and the owner's choice to pay it.
    """

    #: How far back the refusals are counted.
    WINDOW_MS = 4_000
    #: Fewer frames than this say nothing, however many were refused.
    MIN_FRAMES = 20
    #: How much of the window the frames must really span, so a burst is not four seconds.
    MIN_SPAN_MS = 3_500

    def __init__(self) -> None:
        self._times: deque[int] = deque()
        self._refusals: deque[bool] = deque()
        self._refused = 0

    def record(self, now: int, refused_by_bar: bool) -> bool:
        """Notes one frame; true when the bar has refused enough of the last four seconds."""
        self._times.append(now)
        self._refusals.append(refused_by_bar)
        if refused_by_bar:
            self._refused += 1
        while now - self._times[0] > self.WINDOW_MS:
            self._times.popleft()
            if self._refusals.popleft():
                self._refused -= 1
        if len(self._times) < self.MIN_FRAMES or now - self._times[0] < self.MIN_SPAN_MS:
            return False
        # Half or more of the frames. In whole numbers, so no engine can round it differently.
        if self._refused * 2 < len(self._times):
            return False
        self.clear()
        return True

    def clear(self) -> None:
        """Forgets what was counted, as when the bar itself has been forgotten."""
        self._times.clear()
        self._refusals.clear()
        self._refused = 0

"""The identity measurement harness: composites, metrics and a runner for judging how well the
pipeline tells the athlete apart from anyone else sharing the frame.

``composite.py`` builds synthetic two-athlete footage, ``metrics.py`` scores a run against it (or
against a real labelled clip), and ``run_identity.py`` ties both to the production pipeline or to
a later variant that adds its own acquisition and continuity logic.
"""

#!/usr/bin/env python3
"""Tests for compare_reports.py.   python3 -m unittest tools/video_regression/test_compare_reports.py"""
from __future__ import annotations

import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import compare_reports as cr


def scenario(id, expected, observed, *, tags=(), movements=None, status=None, failures=(), frames=1, setup="ready",
             reason=None):
    """A report entry with the keys run_batch.py and cindy-clips both write."""
    category = ("must-not-count" if expected == 0 else
                "difficult-but-valid" if set(tags) & {"occlusion", "camera-cut", "known-gap"} else "clean-valid")
    s = {"id": id, "exercise": "pullup", "category": category, "expectedReps": expected, "observedReps": observed,
         "signedError": observed - expected, "tags": list(tags), "failures": list(failures),
         "frames": [{}] * frames, "setup": setup}
    if status:
        s["status"] = status
    if reason:
        s["skipReason"] = reason
    if movements:
        s["perMovement"] = {n: {"expected": e, "observed": o, "eventsMs": []} for n, (e, o) in movements.items()}
    return s


def report(*scenarios):
    return {s["id"]: s for s in scenarios}


class CompareTests(unittest.TestCase):

    def test_a_row_per_scenario_with_both_counts_and_the_truth(self):
        c = cr.compare(report(scenario("a", 10, 9), scenario("b", 4, 4)),
                       report(scenario("a", 10, 10), scenario("b", 4, 2)))
        a, b = c.rows
        self.assertEqual((a.truth, a.movenet.observed, a.vision.observed), (10, 9, 10))
        self.assertEqual((a.error(a.movenet), a.error(a.vision)), (-1, 0))
        self.assertEqual(a.verdict, "Vision closer")
        self.assertEqual(b.verdict, "MoveNet closer")

    def test_equal_error_is_the_same_unless_the_sign_differs(self):
        c = cr.compare(report(scenario("same", 5, 4), scenario("flip", 5, 4)),
                       report(scenario("same", 5, 4), scenario("flip", 5, 6)))
        self.assertEqual([r.verdict for r in c.rows], ["same", "same size, opposite sign"])

    def test_rows_follow_movenets_order_then_visions_extras(self):
        c = cr.compare(report(scenario("z", 1, 1), scenario("a", 1, 1)),
                       report(scenario("a", 1, 1), scenario("extra", 1, 1), scenario("z", 1, 1)))
        self.assertEqual([r.id for r in c.rows], ["z", "a", "extra"])

    def test_categories_come_from_the_report_and_stay_apart(self):
        c = cr.compare(report(scenario("v", 5, 5), scenario("d", 5, 4, tags=["occlusion"]), scenario("m", 0, 0)),
                       report(scenario("v", 5, 5), scenario("d", 5, 4, tags=["occlusion"]), scenario("m", 0, 0)))
        self.assertEqual({r.id: r.category for r in c.rows},
                         {"v": "clean-valid", "d": "difficult-but-valid", "m": "must-not-count"})
        self.assertEqual([r.id for r in c.category("difficult-but-valid")], ["d"])

    # MARK: what is not compared

    def test_a_skipped_clip_is_not_compared_and_says_why(self):
        c = cr.compare(report(scenario("a", 5, 5)),
                       report(scenario("a", 5, 0, status="skipped", reason="missing fixture: tests/a.mp4", frames=0, setup=None)))
        row = c.rows[0]
        self.assertFalse(row.comparable)
        self.assertEqual((row.vision.note, row.vision.reason), ("skipped", "missing fixture: tests/a.mp4"))
        self.assertEqual(row.verdict, "not compared")
        self.assertEqual(cr._cell(row.vision, row), "skipped")

    def test_run_batchs_own_missing_fixture_counts_as_skipped(self):
        # run_batch.py has no status key; it reports the same thing as a failure.
        c = cr.compare(report(scenario("a", 5, 0, failures=["missing fixture: /x/a.mp4"], frames=0, setup=None)),
                       report(scenario("a", 5, 5)))
        self.assertEqual(c.rows[0].movenet.note, "skipped")
        self.assertEqual(c.rows[0].movenet.reason, "missing fixture: /x/a.mp4")

    def test_a_clip_that_could_not_run_is_failed_not_zero(self):
        broken = scenario("a", 5, 0, failures=["cannot open video: a.mp4"], frames=0, setup=None)
        c = cr.compare(report(scenario("a", 5, 5)), report(broken))
        self.assertEqual((c.rows[0].vision.note, c.rows[0].vision.reason), ("failed", "cannot open video: a.mp4"))
        self.assertEqual(cr._cell(c.rows[0].vision, c.rows[0]), "FAILED")

    def test_a_cindy_clip_that_never_got_ready_scored_zero_it_did_not_fail_to_run(self):
        never = scenario("c", 0, 0, failures=["setup never reached READY -- no workout frames were scored"],
                         frames=0, setup="framing")
        self.assertTrue(cr._side(never, None).counted)

    def test_a_scenario_in_only_one_report_is_not_run_in_the_other(self):
        c = cr.compare(report(scenario("only", 3, 3)), {})
        self.assertEqual((c.rows[0].vision.note, c.rows[0].vision.reason), ("missing", "not in this report"))
        self.assertEqual(cr._cell(c.rows[0].vision, c.rows[0]), "not run")

    # MARK: cindy

    def test_a_cindy_clip_is_a_row_per_movement(self):
        movements = {"pullup": (5, 5), "pushup": (10, 9), "squat": (15, 15)}
        c = cr.compare(report(scenario("cindy", 30, 29, movements=movements)),
                       report(scenario("cindy", 30, 30, movements={"pullup": (5, 5), "pushup": (10, 10), "squat": (15, 15)})))
        self.assertEqual([r.label for r in c.rows], ["cindy · pullup", "cindy · pushup", "cindy · squat"])
        self.assertEqual([r.truth for r in c.rows], [5, 10, 15])
        self.assertEqual(c.rows[1].verdict, "Vision closer")

    def test_a_cindy_report_without_movements_cannot_be_split(self):
        c = cr.compare(report(scenario("cindy", 30, 30)),
                       report(scenario("cindy", 30, 30, movements={"pullup": (5, 5)})))
        self.assertEqual(c.rows[0].movenet.note, "missing")
        self.assertEqual(c.rows[0].movenet.reason, "no per-movement counts in this report")

    # MARK: numbers

    def test_stats_are_over_the_rows_both_scored(self):
        c = cr.compare(report(scenario("a", 10, 9), scenario("b", 4, 4), scenario("c", 6, 8), scenario("only_m", 5, 5)),
                       report(scenario("a", 10, 10), scenario("b", 4, 3), scenario("c", 6, 7)))
        rows = c.category("clean-valid")
        m, v = cr.stats(rows, "movenet"), cr.stats(rows, "vision")
        self.assertEqual((m.rows, m.exact, m.under, m.over), (3, 1, 1, 1))
        self.assertAlmostEqual(m.mean_abs_error, (1 + 0 + 2) / 3)
        self.assertEqual((v.rows, v.exact, v.under, v.over), (3, 1, 1, 1))
        self.assertAlmostEqual(v.mean_abs_error, (0 + 1 + 1) / 3)

    def test_false_positives_are_counted_on_must_not_count_only(self):
        c = cr.compare(report(scenario("m1", 0, 0), scenario("m2", 0, 1), scenario("v", 5, 6)),
                       report(scenario("m1", 0, 2), scenario("m2", 0, 0), scenario("v", 5, 7)))
        s = cr.stats(c.rows, "vision")
        self.assertEqual(s.false_positives, 2)
        self.assertEqual(cr.stats(c.rows, "movenet").false_positives, 1)

    def test_nothing_scored_by_both_has_no_stats(self):
        self.assertIsNone(cr.stats(cr.compare(report(scenario("a", 1, 1)), {}).rows, "vision"))

    # MARK: Decision D1

    def clean(self, n, vision):
        m = [scenario(f"c{i}", 5, 5) for i in range(n)]
        v = [scenario(f"c{i}", 5, vision.get(i, 5)) for i in range(n)]
        return cr.compare(report(*m), report(*v))

    def test_vision_is_kept_when_it_loses_nothing_movenet_has(self):
        r = cr.reading(self.clean(4, {}))
        self.assertEqual(r.verdict, "keep-vision")

    def test_vision_overcounting_is_not_the_undercount_d1_names(self):
        self.assertEqual(cr.reading(self.clean(4, {1: 6})).verdict, "keep-vision")

    def test_an_undercount_where_movenet_is_exact_adds_movenet(self):
        r = cr.reading(self.clean(4, {2: 4}))
        self.assertEqual(r.verdict, "add-movenet")
        self.assertEqual(r.reasons, ["Vision undercounts c2 (-1) where MoveNet does not (+0)"])

    def test_an_undercount_that_movenet_shares_is_not_visions_loss(self):
        c = cr.compare(report(scenario("a", 5, 4), scenario("b", 5, 5), scenario("c", 5, 5)),
                       report(scenario("a", 5, 3), scenario("b", 5, 5), scenario("c", 5, 5)))
        self.assertEqual(cr.reading(c).verdict, "keep-vision")

    def test_a_false_positive_where_movenet_has_none_adds_movenet(self):
        c = cr.compare(report(*[scenario(f"c{i}", 5, 5) for i in range(3)], scenario("m", 0, 0)),
                       report(*[scenario(f"c{i}", 5, 5) for i in range(3)], scenario("m", 0, 2)))
        r = cr.reading(c)
        self.assertEqual(r.verdict, "add-movenet")
        self.assertEqual(r.reasons, ["Vision counts 2 on m, which must not count; MoveNet counts 0"])

    def test_too_few_clips_gives_no_reading_but_still_says_what_was_found(self):
        self.assertEqual(cr.reading(self.clean(2, {})).verdict, "not-enough-clips")
        few = cr.reading(self.clean(2, {0: 4}))
        self.assertEqual(few.verdict, "not-enough-clips")
        self.assertEqual(few.reasons[1], "so far: Vision undercounts c0 (-1) where MoveNet does not (+0)")
        self.assertEqual(cr.reading(cr.compare({}, {})).verdict, "not-enough-clips")

    def test_skipped_clips_do_not_count_toward_a_reading(self):
        skipped = scenario("s", 5, 0, status="skipped", reason="missing fixture: s", frames=0, setup=None)
        c = cr.compare(report(*[scenario(f"c{i}", 5, 5) for i in range(2)], scenario("s", 5, 5)),
                       report(*[scenario(f"c{i}", 5, 5) for i in range(2)], skipped))
        self.assertEqual(cr.reading(c).verdict, "not-enough-clips")

    # MARK: output

    def test_the_text_names_each_category_and_the_verdict(self):
        c = cr.compare(report(scenario("a", 10, 10), scenario("b", 4, 4), scenario("c", 6, 6), scenario("m", 0, 0)),
                       report(scenario("a", 10, 9), scenario("b", 4, 4), scenario("c", 6, 6), scenario("m", 0, 0)))
        text = cr.render_text(c)
        for expected in ("CLEAN-VALID", "MUST-NOT-COUNT", "a  ", "9 (-1)", "10 (+0)", "ADD A MOVENET CORE ML SOURCE",
                         "Vision undercounts a (-1) where MoveNet does not (+0)", "false positives:"):
            self.assertIn(expected, text)

    def test_the_markdown_is_a_table(self):
        c = cr.compare(report(scenario("a", 10, 10)), report(scenario("a", 10, 9)))
        md = cr.render_markdown(c)
        self.assertTrue(md.startswith("| clip | truth | MoveNet | Vision | closer |"))
        self.assertIn("| a | 10 | 10 (+0) | 9 (-1) | MoveNet closer |", md)

    def test_the_command_line_reads_two_files_and_writes_the_markdown(self):
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            (d / "m.json").write_text(json.dumps({"scenarios": [scenario("a", 10, 10)]}))
            (d / "v.json").write_text(json.dumps({"scenarios": [scenario("a", 10, 9)]}))
            out = io.StringIO()
            with redirect_stdout(out):
                code = cr.main(["--movenet", str(d / "m.json"), "--vision", str(d / "v.json"),
                                "--markdown", str(d / "t.md")])
            self.assertEqual(code, 0)
            self.assertIn("NO READING YET", out.getvalue())
            self.assertIn("so far: Vision undercounts a (-1)", out.getvalue())
            self.assertIn("| a | 10 |", (d / "t.md").read_text())

    def test_a_missing_report_is_an_error_naming_it(self):
        err = io.StringIO()
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "m.json").write_text("{\"scenarios\": []}")
            from contextlib import redirect_stderr
            with redirect_stderr(err):
                code = cr.main(["--movenet", str(Path(d) / "m.json"), "--vision", str(Path(d) / "absent.json")])
        self.assertEqual(code, 2)
        self.assertIn("no Vision report at", err.getvalue())


class RealReportsTests(unittest.TestCase):
    """The reports the two tools write today have the keys this script reads."""

    def test_run_batch_writes_every_key_this_script_reads(self):
        source = (Path(__file__).resolve().parent / "run_batch.py").read_text()
        for key in ("id", "category", "expectedReps", "observedReps", "failures", "frames", "setup", "perMovement"):
            self.assertIn(f'"{key}"', source, key)


if __name__ == "__main__":
    unittest.main()

import unittest

from analyze_frame_stalls import analyze
from profile_playback import admission_summary


def frame(t, ui=1000, raster=1000):
    return {'vsyncUs': t, 'buildUs': ui, 'rasterUs': raster}


class SavedFrameAnalysisTests(unittest.TestCase):
    def test_high_average_rate_does_not_hide_a_single_large_ui_stall(self):
        frames = [frame(i * 16667) for i in range(60)]
        frames[-1]['buildUs'] = 150000
        frames += [frame(frames[-1]['vsyncUs'] + 166667)]
        result = analyze(frames)
        self.assertGreater(result['fps'], 30)
        self.assertEqual(result['ui_over_100ms_frames'], 1)
        self.assertEqual(result['interval_over_50ms_count'], 1)
        self.assertEqual(result['long_intervals_adjacent_to_ui_over_33ms'], 1)
        self.assertEqual(result['long_intervals_adjacent_to_raster_over_33ms'], 0)

    def test_raster_stall_is_not_reported_as_a_slow_ui_frame(self):
        result = analyze([frame(0, raster=80000), frame(100000)])
        self.assertEqual(result['ui_over_50ms_frames'], 0)
        self.assertEqual(result['raster_over_50ms_frames'], 1)

    def test_duplicate_or_restarted_clocks_are_rejected_not_silently_combined(self):
        for frames in ([frame(0)], [frame(0), frame(0)], [frame(100), frame(0)]):
            with self.assertRaises(ValueError):
                analyze(frames)

    def test_missing_admission_markers_are_not_reported_as_zero_cost(self):
        self.assertEqual(admission_summary({}, True), {'status': 'not_observed'})
        self.assertEqual(admission_summary({}, False), {'status': 'timeline_not_requested'})

    def test_rare_admission_stall_is_reported_even_if_total_cost_is_small(self):
        result = admission_summary({'TV.Danmaku.add': [1, 2, 3, 150]}, True)
        self.assertEqual(result['max_ms'], 150)
        self.assertEqual(result['over_33ms_count'], 1)


if __name__ == '__main__':
    unittest.main()

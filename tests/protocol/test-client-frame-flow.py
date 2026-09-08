import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('flow', Path(__file__).parents[2] / 'scripts/analyze-client-frame-flow.py')
flow = importlib.util.module_from_spec(spec)
spec.loader.exec_module(flow)


class FlowTest(unittest.TestCase):
    def test_interleaved_flush(self):
        text = '''prefix PLANK frame-flow begin lane=receive id=1 rows=1
PLANK frame-flow begin lane=render id=2 rows=1
PLANK frame-flow row lane=receive id=1 data=100,1001,1,1,1,100,0,0
PLANK frame-flow row lane=render id=2 data=200,1000,-1,7,1,0,3,20
PLANK frame-flow end lane=receive id=1
PLANK frame-flow begin lane=decode id=3 rows=1
PLANK frame-flow row lane=decode id=3 data=150,1001,1,2,1,100,0,1
PLANK frame-flow end lane=render id=2
PLANK frame-flow end lane=decode id=3'''
        result = flow.summarize(flow.read_traces(text))
        self.assertEqual(result['stage_counts']['render'], {7: 1})
        events = result['keyframe_windows'][0]['frames'][0]['events']
        self.assertEqual([e['stage'] for e in events], [1, 2, 7])

    def test_incomplete(self):
        with self.assertRaises(ValueError):
            flow.read_traces('PLANK frame-flow begin lane=receive id=1 rows=1')
        with self.assertRaises(ValueError):
            flow.read_traces('PLANK frame-flow begin lane=receive id=1 rows=1\nPLANK frame-flow end lane=receive id=1')


if __name__ == '__main__':
    unittest.main()

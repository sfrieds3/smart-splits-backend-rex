"""Opt-in smoke test against a running Rex server; creates and cleans up its own unattached session.

RUN_REX_LIVE_TESTS=1 python3 -m unittest tests.test_live -v
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[1]


@unittest.skipUnless(os.environ.get("RUN_REX_LIVE_TESTS") == "1" and shutil.which("rex") and shutil.which("nvim"),
                     "set RUN_REX_LIVE_TESTS=1 with a running Rex server")
class RexBackendLiveTest(unittest.TestCase):
    def test_backend(self):
        created = subprocess.run(
            ["rex", "--autostart=false", "new", "smart-splits-test", "--shell=none", "--json", "--", "sleep", "120"],
            capture_output=True, text=True, check=True, timeout=10,
        )
        session = json.loads(created.stdout)
        session_id = session["session_id"]
        try:
            env = dict(os.environ, REX_SESSION=session_id, REX_TEST_SESSION=session_id,
                       REX_BLOCK=session["initial_windows"][0]["block_ids"][0])
            for key in ("TMUX", "TMUX_PANE", "REX_CLIENT"):
                env.pop(key, None)
            result = subprocess.run(
                ["nvim", "--headless", "-u", "NONE", "-l", "tests/live.lua"],
                cwd=REPO, env=env, capture_output=True, text=True, timeout=30,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("Live Rex backend checks passed", result.stdout + result.stderr)
        finally:
            subprocess.run(["rex", "--autostart=false", "kill", session_id], check=True, timeout=10,
                           capture_output=True)


if __name__ == "__main__":
    unittest.main()

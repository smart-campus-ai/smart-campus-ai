"""pytest configuration: make the service modules importable as top-level.

The Lambda archive root is the service directory (handler ``app.handler``), so
modules are imported flat (``import domain``). Tests mirror that by putting the
service directory and the tests directory on sys.path.
"""

import os
import sys

_SERVICE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_TESTS_DIR = os.path.join(_SERVICE_DIR, "tests")
for path in (_SERVICE_DIR, _TESTS_DIR):
    if path not in sys.path:
        sys.path.insert(0, path)

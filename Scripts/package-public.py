#!/usr/bin/env python3
"""Compatibility entry point for the current v2 app package; never install/upload."""
from pathlib import Path
import subprocess
subprocess.run(['python3', str(Path(__file__).with_name('package-apps.py')), '--product', 'v2'], check=True)

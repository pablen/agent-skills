"""Shared helpers for the skills-sync scripts."""
import json
import subprocess
from pathlib import Path

STATE_DIR = Path.home() / ".agents"
STATE_FILE = STATE_DIR / "agent-skills.json"


def emit(obj) -> None:
    print(json.dumps(obj, ensure_ascii=False, indent=2))


def run(cmd, timeout=15):
    """Run a command, never raising. Returns (returncode, stdout, stderr)."""
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return result.returncode, result.stdout, result.stderr
    except (FileNotFoundError, subprocess.TimeoutExpired) as e:
        return 1, "", str(e)


def load_state() -> dict:
    if not STATE_FILE.exists():
        return {}
    try:
        return json.loads(STATE_FILE.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def save_state(**updates) -> dict:
    state = load_state()
    state.update(updates)
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
    return state


def path_kind(path: Path) -> str:
    """Classify a filesystem entry: missing | symlink | dir | file."""
    if not path.exists() and not path.is_symlink():
        return "missing"
    if path.is_symlink():
        return "symlink"
    if path.is_dir():
        return "dir"
    return "file"

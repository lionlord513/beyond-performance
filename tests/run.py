"""Command-only Lua syntax and deterministic module checks.

Requires Python 3 and lupa (pip install lupa), or pass --lupa-path to an
existing installation. No game, loader, other mod, or network is required.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import sys
import tempfile


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lupa-path", type=Path, help="Optional directory containing the lupa package")
    args = parser.parse_args()
    if args.lupa_path:
        sys.path.insert(0, str(args.lupa_path.resolve()))
    try:
        from lupa.lua54 import LuaRuntime
    except ImportError as error:
        raise SystemExit("Lua 5.4 binding unavailable. Install lupa or pass --lupa-path.") from error

    project = Path(__file__).resolve().parents[1]
    scripts = project / "mod" / "BeyondPerformance" / "Scripts"
    runtime = LuaRuntime(unpack_returned_tuples=True)
    for source in sorted([*scripts.rglob("*.lua"), *(project / "tests").rglob("*.lua")]):
        runtime.globals().syntax_path = source.as_posix()
        runtime.execute("assert(loadfile(syntax_path))")
        print(f"PASS syntax: {source.relative_to(project)}")

    scratch = project / "work"
    scratch.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="lua-tests-", dir=scratch) as temp:
        runtime.globals().scriptdir = scripts.as_posix()
        runtime.globals().testpath = (Path(temp) / "settings.ini").as_posix()
        runtime.globals().test_file = (project / "tests" / "run.lua").as_posix()
        runtime.execute("assert(loadfile(test_file))()")
        runtime.globals().test_file = (project / "tests" / "benchmark.lua").as_posix()
        runtime.execute("assert(loadfile(test_file))()")
    print("PASS all deterministic checks. These do not replace in-game/runtime validation.")


if __name__ == "__main__":
    main()

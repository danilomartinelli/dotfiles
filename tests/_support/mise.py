"""The shared Mise fake: command effects against explicit fixture configuration."""

import json
import os
from pathlib import Path
import re
import sys
import tomllib


args = sys.argv[1:]
if event_log := os.environ.get("SCENARIO_EVENT_LOG"):
    with open(event_log, "a") as log:
        log.write("mise " + " ".join(args) + "\n")
if event_log := os.environ.get("EVENTS"):
    with open(event_log, "a") as log:
        log.write(json.dumps(["mise", *args]) + "\n")
if args[:1] == ["-C"]:
    os.chdir(args[1])
    args = args[2:]

config_path = os.environ.get("MISE_GLOBAL_CONFIG_FILE")
locked = os.environ.get("MISE_LOCKED") in ("1", "true") or "--locked" in args
if trace := os.environ.get("FAKE_MISE_TRACE"):
    with open(trace, "a") as log:
        log.write(json.dumps({
            "args": args,
            "cwd": os.getcwd(),
            "config": config_path,
            "locked": locked,
            "trust": os.environ.get("MISE_TRUSTED_CONFIG_PATHS"),
            "selectors": {k: v for k, v in os.environ.items()
                          if v and k.startswith("MISE_") and k.endswith("_VERSION")},
        }) + "\n")

if args == ["where", "java"]:
    print(os.environ["FAKE_MISE_JAVA_HOME"])
elif args[:1] == ["where"]:
    if args[1:] == ["pipx:mdformat"] and os.environ.get("FAKE_MISE_MDFORMAT_HOME"):
        print(os.environ["FAKE_MISE_MDFORMAT_HOME"])
    else:
        sys.exit(1)
elif args[:1] in (["activate"], ["completion"]):
    print("export FAKE_MISE_ACTIVATED=1" if args[0] == "activate"
          else "typeset -g _fake_mise_completion=1")
    sys.exit(int(os.environ.get(f"FAIL_MISE_{args[0].upper()}", "0")))
elif args[:1] in (["exec"], ["install"], ["prune"], ["outdated"], ["ls"], ["lock"]):
    config = Path(config_path)
    tools = tomllib.loads(config.read_text()).get("tools", {})
    lock = config.parent / "mise.lock"
    entries = tomllib.loads(lock.read_text()).get("tools", {}) if lock.exists() else {}
    command = args[0]
    if status := int(os.environ.get(f"FAIL_MISE_{command.upper()}", "0")):
        sys.exit(status)
    if command == "lock":
        if locked:
            raise SystemExit("fake mise: regeneration was not enabled")
        for name in (a for a in args[1:] if not a.startswith("--")):
            value = tools[name]
            version = value.get("version") if isinstance(value, dict) else value
            if version in ("lts", "4.0"):
                version = entries[name][-1]["version"]
            options = {k: v for k, v in value.items() if k != "version"} if isinstance(value, dict) else {}
            if name == "ruby":
                options = {"compile": "false", "precompiled_url": "jdx/ruby"}
            entries[name] = [e for e in entries.get(name, []) if e.get("options", {}) != options]
            entries[name].append({"version": version, "options": options})
        with lock.open("w") as out:
            for name, versions in entries.items():
                for entry in versions:
                    out.write(f"[[tools.{json.dumps(name)}]]\nversion = {json.dumps(entry['version'])}\n")
                    if entry.get("options"):
                        out.write(f"[tools.{json.dumps(name)}.options]\n")
                        for key, value in entry["options"].items():
                            out.write(f"{key} = {json.dumps(value)}\n")
    elif command == "outdated":
        result = {}
        for name, value in tools.items():
            if name not in args or name == "npm:kept":
                continue
            version = value["version"] if isinstance(value, dict) else value
            latest = "24.1.0" if name == "node" else "2.0.0"
            if name == "node" and "--bump" in args:
                latest = "26.0.0"
            result[name] = {"requested": version, "current": entries[name][-1]["version"], "latest": latest}
        print(json.dumps(result))
    elif command == "ls":
        print(json.dumps([{"version": entries[args[-1]][-1]["version"], "active": True}]))
    else:
        requested = args[1:args.index("--")] if command == "exec" else args[1:]
        selected = [name for name in requested if not name.startswith("-")] or list(tools)
        if locked:
            for name in selected:
                declaration = tools.get(name)
                version = declaration.get("version") if isinstance(declaration, dict) else declaration
                versions = [e["version"] for e in entries.get(name, [])]
                if not versions or (version and re.fullmatch(r"\d+\.\d+\.\d+", version) and version not in versions):
                    raise SystemExit(f"fake mise: missing or incompatible lock resolution for {name}")
        elif os.environ.get("MISE_LOCKFILE") != "false":
            with lock.open("a") as out:
                out.write("\n# fake mise refreshed lock\n")
        if command == "install" and os.environ.get("FAKE_MISE_EXTRAS_FILE"):
            Path(os.environ["FAKE_MISE_EXTRAS_FILE"]).write_text(os.environ["FAKE_MISE_EXTRAS"])
        if command == "exec":
            command_args = args[args.index("--") + 1:]
            os.execvp(command_args[0], command_args)
else:
    raise SystemExit(f"fake mise: unsupported arguments: {args}")

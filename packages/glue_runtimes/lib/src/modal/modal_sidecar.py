#!/usr/bin/env python3
"""Modal sandbox sidecar for glue's modal runtime adapter.

Modal's `sandbox` primitive is Python-only; there's no `modal sandbox`
subcommand in the CLI. This script spawns a long-lived
`modal.Sandbox` with a `sleep infinity` keepalive, then services
exec / file ops dispatched from glue over JSON-RPC on stdin/stdout.

Protocol (line-delimited JSON):
    Request:  {"id": <int>, "op": <str>, ...op-specific fields}
    Response: {"id": <int>, "ok": <bool>, ...op-specific fields}
    Async event: {"event": <str>, ...event-specific fields}

Synchronous ops:
    ready (sent unsolicited on startup)
    exec          — {command:str, timeout?:int} -> {exit_code, stdout, stderr}
    read_file     — {path:str} -> {content_b64:str}
    write_file    — {path:str, content_b64:str} -> {}
    exists        — {path:str} -> {exists:bool}
    is_directory  — {path:str} -> {is_directory:bool}
    list_dir      — {path:str} -> {entries:[{name,is_dir,size}]}
    stat          — {path:str} -> {size:int, is_directory:bool} | not_found:true
    shutdown      — terminates the sandbox and exits

Streaming ops (background exec):
    stream_start  — {command:str} -> {stream_id:str} (then async events emit)
    stream_kill   — {stream_id:str} -> {}

Async events emitted during streaming:
    stream_data   — {stream_id, stream:"stdout"|"stderr", data:str}
    stream_exit   — {stream_id, exit_code:int|null}
"""

import base64
import json
import shlex
import sys
import threading
import traceback

import modal


# All writes to stdout must go through this lock — multiple streaming
# threads + the main loop all share the single stdout pipe back to
# glue, and a half-written JSON line would desync the parser.
_stdout_lock = threading.Lock()


def emit(payload):
    with _stdout_lock:
        sys.stdout.write(json.dumps(payload) + "\n")
        sys.stdout.flush()


def b64(data: bytes) -> str:
    return base64.b64encode(data).decode("ascii")


def run_sync(sb, command: str, timeout: int | None):
    """Runs `command` inside the sandbox via `sh -c`, captures
    stdout/stderr/exit code. (Per-call timeout enforcement is a best
    effort; the sandbox-wide timeout is the hard cap.)"""
    p = sb.exec("sh", "-c", command)
    stdout = p.stdout.read()
    stderr = p.stderr.read()
    p.wait()
    return {
        "exit_code": p.returncode,
        "stdout": stdout,
        "stderr": stderr,
    }


def pump_stream(stream_id: str, stream_name: str, reader):
    """Forwards each line emitted by `reader` (one of p.stdout /
    p.stderr) as a `stream_data` event. Runs on a background
    thread."""
    try:
        for line in reader:
            if not line:
                continue
            emit({
                "event": "stream_data",
                "stream_id": stream_id,
                "stream": stream_name,
                "data": line,
            })
    except Exception as e:  # noqa: BLE001
        emit({
            "event": "stream_data",
            "stream_id": stream_id,
            "stream": "stderr",
            "data": f"[glue:{stream_name}-pump-error] {e}\n",
        })


def watch_exit(stream_id: str, proc, on_exit):
    """Waits for `proc` to finish and emits a `stream_exit` event with
    its exit code. Also notifies the registry via `on_exit` so the
    process handle can be discarded."""
    try:
        proc.wait()
        emit({
            "event": "stream_exit",
            "stream_id": stream_id,
            "exit_code": proc.returncode,
        })
    finally:
        on_exit(stream_id)


def main(argv: list[str]):
    if len(argv) < 2:
        sys.stderr.write("usage: modal_sidecar.py <app-name> [--image IMG] [--timeout SECS]\n")
        sys.exit(2)
    app_name = argv[1]
    image_tag = None
    timeout = 1800  # 30 min default sandbox lifetime
    i = 2
    while i < len(argv):
        if argv[i] == "--image" and i + 1 < len(argv):
            image_tag = argv[i + 1]
            i += 2
        elif argv[i] == "--timeout" and i + 1 < len(argv):
            timeout = int(argv[i + 1])
            i += 2
        else:
            sys.stderr.write(f"unknown arg: {argv[i]}\n")
            sys.exit(2)

    try:
        app = modal.App.lookup(app_name, create_if_missing=True)
        # Modal's default image has no git, which the bootstrap needs.
        if image_tag:
            image = modal.Image.from_registry(image_tag).apt_install("git")
        else:
            image = modal.Image.debian_slim().apt_install("git")
        sb = modal.Sandbox.create(
            "sleep", "infinity",
            app=app, image=image, timeout=timeout,
        )
    except Exception as e:  # noqa: BLE001
        emit({"id": None, "ok": False, "error": f"sandbox_create: {e}"})
        sys.exit(1)

    emit({"id": None, "ok": True, "ready": True, "sandbox_id": sb.object_id})

    # stream_id -> proc + threads, so stream_kill can terminate the
    # right inner process and so we can drop entries on stream_exit.
    streams: dict[str, dict] = {}
    streams_lock = threading.Lock()
    next_stream = [0]  # boxed int so the inner closures can mutate it

    def drop_stream(sid: str):
        with streams_lock:
            streams.pop(sid, None)

    try:
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                req = json.loads(line)
            except json.JSONDecodeError as e:
                emit({"id": None, "ok": False, "error": f"bad_json: {e}"})
                continue
            req_id = req.get("id")
            op = req.get("op")
            try:
                if op == "exec":
                    r = run_sync(sb, req["command"], req.get("timeout"))
                    emit({"id": req_id, "ok": True, **r})
                elif op == "read_file":
                    data = sb.filesystem.read_bytes(req["path"])
                    emit({"id": req_id, "ok": True, "content_b64": b64(data)})
                elif op == "write_file":
                    content = base64.b64decode(req["content_b64"])
                    path = req["path"]
                    # Ensure parent dir exists, mirroring host workspace
                    # semantics. `make_directory(create_parents=True)`
                    # is the new API equivalent of `mkdir -p`.
                    parent = path.rsplit("/", 1)[0]
                    if parent and parent != path:
                        try:
                            sb.filesystem.make_directory(parent, create_parents=True)
                        except Exception:
                            pass  # already exists or permission-handled below
                    sb.filesystem.write_bytes(content, path)
                    emit({"id": req_id, "ok": True})
                elif op == "exists":
                    p = sb.exec("test", "-e", req["path"])
                    p.wait()
                    emit({"id": req_id, "ok": True, "exists": p.returncode == 0})
                elif op == "is_directory":
                    p = sb.exec("test", "-d", req["path"])
                    p.wait()
                    emit({"id": req_id, "ok": True, "is_directory": p.returncode == 0})
                elif op == "list_dir":
                    path = req["path"]
                    p = sb.exec("ls", "-1Ap", path)
                    out = p.stdout.read()
                    p.wait()
                    if p.returncode != 0:
                        emit({"id": req_id, "ok": False, "error": p.stderr.read() or "list failed"})
                        continue
                    entries = []
                    for name in out.splitlines():
                        if not name:
                            continue
                        is_dir = name.endswith("/")
                        clean = name[:-1] if is_dir else name
                        entries.append({"name": clean, "is_dir": is_dir, "size": 0})
                    emit({"id": req_id, "ok": True, "entries": entries})
                elif op == "stat":
                    path = req["path"]
                    p = sb.exec(
                        "sh",
                        "-c",
                        "stat -c '%s %F' "
                        + shlex.quote(path)
                        + " 2>/dev/null || stat -f '%z %HT' "
                        + shlex.quote(path),
                    )
                    out = p.stdout.read().strip()
                    p.wait()
                    if p.returncode != 0:
                        emit({"id": req_id, "ok": True, "not_found": True})
                        continue
                    parts = out.split(" ", 1)
                    size = int(parts[0]) if parts and parts[0].isdigit() else 0
                    type_str = parts[1].lower() if len(parts) > 1 else ""
                    is_dir = "directory" in type_str
                    emit({
                        "id": req_id,
                        "ok": True,
                        "stat": {"size": size, "is_directory": is_dir},
                    })
                elif op == "stream_start":
                    next_stream[0] += 1
                    sid = f"s{next_stream[0]}"
                    # Modal's exec process handle has no terminate()
                    # or kill() method. Wrap the command in a shell
                    # that records its own PID before exec'ing the
                    # user command — `exec` replaces the shell with
                    # the user process while keeping the same PID, so
                    # `kill -TERM $(cat pid_file)` later targets the
                    # right process.
                    pid_file = f"/tmp/.glue-pid-{sid}"
                    wrapped = (
                        f"echo $$ > {pid_file}; exec sh -c "
                        + shlex.quote(req["command"])
                    )
                    proc = sb.exec("sh", "-c", wrapped)
                    out_thread = threading.Thread(
                        target=pump_stream, args=(sid, "stdout", proc.stdout), daemon=True,
                    )
                    err_thread = threading.Thread(
                        target=pump_stream, args=(sid, "stderr", proc.stderr), daemon=True,
                    )
                    exit_thread = threading.Thread(
                        target=watch_exit, args=(sid, proc, drop_stream), daemon=True,
                    )
                    with streams_lock:
                        streams[sid] = {
                            "proc": proc,
                            "pid_file": pid_file,
                            "threads": (out_thread, err_thread, exit_thread),
                        }
                    out_thread.start()
                    err_thread.start()
                    exit_thread.start()
                    emit({"id": req_id, "ok": True, "stream_id": sid})
                elif op == "stream_kill":
                    sid = req["stream_id"]
                    with streams_lock:
                        entry = streams.get(sid)
                    if entry:
                        # Send SIGTERM to the recorded PID via a
                        # fresh sb.exec; the original process's
                        # watch_exit thread will emit stream_exit
                        # once it observes the termination.
                        pid_file = entry["pid_file"]
                        killer = sb.exec(
                            "sh", "-c",
                            f"[ -f {pid_file} ] && kill -TERM $(cat {pid_file}) || true",
                        )
                        killer.wait()
                    emit({"id": req_id, "ok": True})
                elif op == "shutdown":
                    emit({"id": req_id, "ok": True})
                    break
                else:
                    emit({"id": req_id, "ok": False, "error": f"unknown op: {op}"})
            except Exception as e:  # noqa: BLE001
                emit({
                    "id": req_id,
                    "ok": False,
                    "error": f"{type(e).__name__}: {e}",
                    "traceback": traceback.format_exc(),
                })
    finally:
        # Best-effort: SIGTERM any in-flight streams so the sandbox
        # shuts down quickly (terminate-the-sandbox would do this
        # too, but signalling first lets the user processes clean
        # up).
        with streams_lock:
            for entry in streams.values():
                try:
                    sb.exec(
                        "sh", "-c",
                        f"[ -f {entry['pid_file']} ] && "
                        f"kill -TERM $(cat {entry['pid_file']}) || true",
                    ).wait()
                except Exception:
                    pass
        try:
            sb.terminate()
        except Exception:  # noqa: BLE001
            pass


if __name__ == "__main__":
    main(sys.argv)

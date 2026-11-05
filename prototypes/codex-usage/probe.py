#!/usr/bin/env python3
"""Throwaway probe for #26 (PRD §11, Codex checks).

    prototypes/codex-usage/probe.py <dedicated-codex-home>

Starts `codex app-server` with CODEX_HOME set to the folder given (never ~/.codex),
does the JSON-RPC handshake over stdio, then calls `account/read` and
`account/rateLimits/read` and prints both responses. It prints no tokens: neither
call returns one.
"""
import json, os, subprocess, sys, time, select

if len(sys.argv) != 2:
    sys.exit("usage: probe.py <dedicated-codex-home>")
home = os.path.abspath(sys.argv[1])
if os.path.realpath(home) == os.path.realpath(os.path.expanduser("~/.codex")):
    sys.exit("refusing to use ~/.codex: the probe only runs against a dedicated home (U6)")
os.makedirs(home, exist_ok=True)

env = dict(os.environ, CODEX_HOME=home)
proc = subprocess.Popen(["codex", "app-server"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL, env=env, text=True, bufsize=1)

def send(obj):
    proc.stdin.write(json.dumps(obj) + "\n"); proc.stdin.flush()

def wait_for(req_id, timeout=30):
    deadline = time.time() + timeout
    while time.time() < deadline:
        r, _, _ = select.select([proc.stdout], [], [], deadline - time.time())
        if not r: break
        line = proc.stdout.readline()
        if not line: break
        msg = json.loads(line)
        if msg.get("id") == req_id:
            return msg
    return {"timeout": True}

send({"id": 1, "method": "initialize", "params": {"clientInfo": {"name": "agent-usage-probe", "version": "0"}}})
init = wait_for(1)
print("=== initialize:", "ok" if "result" in init else json.dumps(init))
send({"method": "initialized"})

send({"id": 2, "method": "account/read", "params": {"refreshToken": False}})
print("=== account/read (A3 email, A5 plan):"); print(json.dumps(wait_for(2), indent=2))

send({"id": 3, "method": "account/rateLimits/read"})
print("=== account/rateLimits/read (usedPercent, windowDurationMins, resetsAt):")
print(json.dumps(wait_for(3), indent=2))

proc.stdin.close(); proc.terminate()

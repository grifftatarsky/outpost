import base64, glob, json, os, pathlib, re, select, shutil, subprocess, sys, time

HERE = os.path.abspath(sys.argv[1])
OUT = os.path.join(HERE, "raw")
os.makedirs(OUT, exist_ok=True)
RESULTS = os.path.join(OUT, "results.json")
ARTIFACTS = os.path.join(os.environ["TMPDIR"], "ActionArtifacts", "default", "RenderPreview")

def discover():
    root = pathlib.Path(__file__).resolve().parents[2]
    found = []
    for path in sorted(root.glob("Packages/Carpenter/Sources/**/*.swift")):
        text = path.read_text()
        for index, match in enumerate(re.finditer(r'#Preview(?:\("([^"]*)")?', text)):
            found.append({"file": str(path.relative_to(root)), "index": index, "name": match.group(1) or f"preview {index}"})
    return found


listed = os.path.join(HERE, "previews.json")
previews = json.load(open(listed)) if os.path.exists(listed) else discover()
only = set(sys.argv[2:])
results = json.load(open(RESULTS)) if os.path.exists(RESULTS) else {}

proc = subprocess.Popen(["xcrun", "mcpbridge"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL, text=True, bufsize=1)
counter = [100]
WS = "/Users/grifftatarsky/sites/outpost/Carpenter.xcworkspace"

def send(obj):
    proc.stdin.write(json.dumps(obj) + "\n")
    proc.stdin.flush()

def recv(want, timeout):
    end = time.time() + timeout
    while time.time() < end:
        r, _, _ = select.select([proc.stdout], [], [], 1)
        if r:
            line = proc.stdout.readline()
            if not line:
                return None
            if not line.strip():
                continue
            msg = json.loads(line)
            if msg.get("id") == want:
                return msg
    return None

def call(name, arguments, timeout=400):
    counter[0] += 1
    send({"jsonrpc": "2.0", "id": counter[0], "method": "tools/call",
          "params": {"name": name, "arguments": arguments}})
    return recv(counter[0], timeout)

send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
      "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "claude-code", "version": "1"}}})
recv(1, 60)
send({"jsonrpc": "2.0", "method": "notifications/initialized"})

def text_of(res):
    if not res:
        return "no answer"
    if "error" in res:
        return json.dumps(res["error"])
    return "\n".join(c.get("text", "") for c in res.get("result", {}).get("content", []) if c.get("type") == "text")

opened = text_of(call("XcodeOpenWorkspace", {"path": "/Users/grifftatarsky/sites/outpost/Carpenter.xcworkspace"}, 120))
listed = text_of(call("XcodeListWorkspaces", {}, 60))
found = re.findall(r"(workspace-[A-Za-z0-9]+)[^\n]*?/Users/grifftatarsky/sites/outpost/Carpenter\.xcworkspace", opened + "\n" + listed)
if not found:
    found = re.findall(r"\"?(?:workspaceIdentifier|identifier)\"?\s*[:=]\s*\"?(workspace-[A-Za-z0-9]+)", opened + "\n" + listed)
WS = found[0] if found else WS
print("workspace:", WS, "|", (opened + " " + listed)[:300].replace("\n", " "), flush=True)
print("destination:", text_of(call("XcodeSwitchRunDestination", {"displayTitle": os.environ.get("DEST", "iPhone 18 Pro"), "workspaceIdentifier": WS}, 120))[:300], flush=True)

for p in previews:
    key = f"{os.path.basename(p['file'])}#{p['index']}"
    if only and key not in only and os.path.basename(p["file"]) not in only:
        continue
    if key in results and results[key].get("png") and not only:
        continue
    source = p["file"].replace("Packages/", "", 1)
    for attempt in range(3):
        before = set(glob.glob(os.path.join(ARTIFACTS, "**", "*.png"), recursive=True))
        started = time.time()
        res = call("RenderPreview", {"sourceFilePath": source, "previewDefinitionIndexInFile": p["index"], "timeout": 240, "workspaceIdentifier": WS}, 400)
        png = None
        for c in (res or {}).get("result", {}).get("content", []):
            if c.get("type") == "image":
                png = os.path.join(OUT, re.sub(r"[^A-Za-z0-9]+", "-", key) + ".png")
                open(png, "wb").write(base64.b64decode(c["data"]))
        body = text_of(res)
        if not png:
            m = re.search(r"(/[^\s\"']+\.png)", body)
            if m and os.path.exists(m.group(1)):
                png = os.path.join(OUT, re.sub(r"[^A-Za-z0-9]+", "-", key) + ".png")
                shutil.copy(m.group(1), png)
        if not png:
            after = set(glob.glob(os.path.join(ARTIFACTS, "**", "*.png"), recursive=True)) - before
            fresh = [f for f in after if os.path.getmtime(f) >= started - 1]
            if fresh:
                png = os.path.join(OUT, re.sub(r"[^A-Za-z0-9]+", "-", key) + ".png")
                shutil.copy(sorted(fresh, key=os.path.getmtime)[-1], png)
        results[key] = {"file": p["file"], "index": p["index"], "name": p["name"], "png": png,
                        "note": None if png else body[:600], "seconds": round(time.time() - started)}
        json.dump(results, open(RESULTS, "w"), indent=1)
        print(("ok  " if png else "FAIL") + f" {key} ({results[key]['seconds']}s)" + ("" if png else " :: " + body[:200].replace("\n", " ")), flush=True)
        if png or "TimedOut" not in body:
            break

proc.terminate()
print("done", sum(1 for r in results.values() if r.get("png")), "of", len(results), flush=True)

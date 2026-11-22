import json, re, sys, pathlib, subprocess, os
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from swiftcopy import ROOT, literals, chunks

AREAS = [
  ("getting-started", "Getting started", ["Screens/Identity/OnboardingView","Screens/Identity/WelcomeTourView","Screens/Identity/HowItWorksView",
     "Screens/Identity/CheckingRegistrationView","Screens/Identity/RegistrationStalledView","Screens/Identity/RecoveryKeyView","Crypto/RecoveryKey",
     "Screens/Identity/RestoreFromKeyView","Screens/Identity/DeviceSyncedView","Screens/Identity/AvatarCropView","Membership/HeldRestorePrompt",
     "Presentation/RestoreNotification"]),
  ("inbox", "Inbox", ["Screens/Rooms/","Screens/RootView","Messaging/RoomRowViews","Messaging/ConversationPreview","RoomsFocusFilter",
     "Presentation/RelativeTimestampFormatter"]),
  ("conversations", "Conversations", ["Screens/Messaging/","Components/Messaging/","Components/Media/","Log/Bodies/MediaBodies",
     "Log/Payload+Making","Log/Projection","AppRootView+Media"]),
  ("membership", "Rooms & membership", ["Screens/Membership/","Components/Membership/"]),
  ("outposts", "Outposts", ["Outpost/","Presentation/AccessWindowsCopy","Presentation/AnonPersonaCopy"]),
  ("notifications", "Notifications", ["Screens/Notifications/","Presentation/MessageNotification"]),
  ("safety", "Safety & privacy", ["Screens/Safety/","Settings/PrivacyAndSafetySettingsView","AppRootView+Privacy"]),
  ("you", "You & settings", ["Screens/You/","Theme/Accent","Theme/AppIconChoice","Screens/Identity/DeviceListView","AppRootView+Avatars",
     "AppRootView+Device"]),
  ("supporter", "Supporter", ["Screens/Supporter/"]),
  ("system", "System, sync & errors", ["Info.plist","Branding.xcconfig","SessionProblem","HonestCopy","AppRootView","Theme/Accessibility",
     "Shared/HelpButton","Shared/DebugNukeButton"]),
]
def area_of(rel):
    for key, name, keys in AREAS:
        if any(k in rel for k in keys): return key
    return "system"

NOT_COPY_BEFORE = re.compile(
    r"(systemName|systemImage|icon|image|named|forKey|key|id|identifier|tableName|category|kind|symbol|subsystem|suiteName)\s*:\s*$"
    r"|Image\(\s*$|accessibilityIdentifier\(\s*$|==\s*$|!=\s*$|\bcase\s+$|contains\(\s*$|hasPrefix\(\s*$|hasSuffix\(\s*$"
    r"|URL\(string:\s*$|#Preview\(\s*$|UserDefaults|firstIndex\(of:\s*$|\?\?\s*$")
LOG_LINE = re.compile(r"Diagnostics\.|Logger\(|\.notice\(|\.error\(|\.debug\(|\.info\(|\.fault\(|DiagnosticsExport\.note\(|print\(")
ROLES = [("navigationTitle","Screen title"),("sectionHeading","Section heading"),("accessibilityLabel","VoiceOver label"),
         ("accessibilityHint","VoiceOver hint"),("accessibilityValue","VoiceOver value"),("prompt:","Field placeholder"),
         ("TextField","Field placeholder"),("confirmationDialog","Confirmation"),(".alert(","Alert"),("Button","Button"),
         ("Label(","Label"),("Toggle","Toggle"),("footer","Footer"),("header","Header"),("title:","Title"),("detail:","Detail"),
         ("message:","Message"),("subtitle:","Subtitle"),("ContentUnavailableView","Empty state")]

def tidy(t):
    return t

def extract(text, rel):
    out = []
    for cid, status, b, e in chunks(text):
        strings = []
        body = text[b:e]
        if rel.endswith(".swift"):
            for s0, s1, raw, rendered, ph, multi in literals(body, b):
                line_start = text.rfind("\n", 0, s0) + 1
                prefix = text[line_start:s0]
                back = text[max(0, s0 - 60):s0]
                line_end = text.find("\n", s1)
                full = text[line_start:line_end if line_end >= 0 else len(text)]
                keep = re.search(r"(Text\(|localized:|verbatim:|LocalizedStringKey\()\s*$", back.rstrip() + " " if False else back.rstrip())
                if re.search(r"comment:\s*$", back.rstrip()):
                    if strings: strings[-1]["note"] = rendered
                    continue
                if not keep:
                    if LOG_LINE.search(full) or NOT_COPY_BEFORE.search(back.rstrip()): continue
                    if re.fullmatch(r"[A-Za-z0-9_.\-]+", rendered) and ("." in rendered or "_" in rendered or rendered.islower()) and " " not in rendered:
                        continue
                if not rendered.strip() or re.fullmatch(r"\s*(\{[^{}]*\}\s*)+", rendered): continue
                if not re.search(r"[A-Za-z]", rendered): continue
                role = next((r for p, r in ROLES if p in full), None)
                cm = re.findall(r"case\s+(\.[A-Za-z_][\w.]*(?:\([^)]*\))?(?:\s*,\s*\.[\w.]+)*)\s*(?:where[^:]*)?:", text[b:s0])
                strings.append({"text": rendered, "role": role, "when": cm[-1] if cm else None,
                                "line": text[:s0].count("\n") + 1})
        elif rel.endswith(".plist"):
            for m in re.finditer(r"<key>([^<]+)</key>\s*<string>([^<]*)</string>", body):
                strings.append({"text": m.group(2).replace("&amp;", "&"), "role": m.group(1), "when": None,
                                "line": text[:b + m.start(2)].count("\n") + 1})
        else:
            for m in re.finditer(r"^\s*([A-Z_]+)\s*=\s*(.+)$", body, re.M):
                strings.append({"text": m.group(2).strip(), "role": m.group(1), "when": None,
                                "line": text[:b + m.start(2)].count("\n") + 1})
        if strings:
            out.append({"id": cid, "status": status, "line": text[:b].count("\n"), "strings": strings})
    return out

def main():
    env = dict(os.environ, DEVELOPER_DIR="/Library/Developer/CommandLineTools")
    names = subprocess.run(["git", "ls-files", "-co", "--exclude-standard", "App", "Packages/Carpenter/Sources", "Config"],
                           cwd=ROOT, capture_output=True, text=True, env=env).stdout.split()
    result = {}
    for rel in names:
        if "/Debug/" in rel or "Previews/" in rel: continue
        p = ROOT / rel
        try: text = p.read_text()
        except Exception: continue
        if "COPY BEGIN" not in text: continue
        short = rel.split("/Sources/")[-1] if "/Sources/" in rel else rel
        for c in extract(text, rel):
            c["file"] = short
            result.setdefault(area_of(rel), {}).setdefault(pathlib.Path(rel).stem, []).append(c)
    return result

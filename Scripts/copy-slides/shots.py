import json, os, pathlib, re, subprocess, sys, glob, shutil

HERE = os.path.abspath(sys.argv[1])
REVIEW = HERE
SHOTS = os.path.join(REVIEW, "shots")
os.makedirs(SHOTS, exist_ok=True)

slides = json.load(open(os.path.join(HERE, "slides.json")))
by_key = {s["key"]: s for s in slides}

def stem(path):
    s = os.path.basename(path).replace(".swift", "")
    return s.split("+")[0]

def convert(src, name):
    out = os.path.join(SHOTS, name + ".jpg")
    if not os.path.exists(out) or os.path.getmtime(out) < os.path.getmtime(src):
        subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "72", "-Z", "900", src, "--out", out],
                       capture_output=True)
    return "shots/" + name + ".jpg"

def screen_titles(slide):
    return [x["text"] for a in slide["areas"] for x in a["strings"] if x.get("el") in ("Screen title", "Sheet title", "Alert title", "Card title")]

def all_texts(slide):
    return [x["text"] for a in slide["areas"] for x in a["strings"]]

def slides_for_stem(key):
    base = re.sub(r"Previews?$", "", key)
    found = [s for s in slides if s["key"] == key or s["key"] == base or stem(s["file"]) in (key, base)]
    if not found:
        found = [s for s in slides if stem(s["file"]).startswith(base) and len(base) > 6]
    return found

attached = {s["key"]: [] for s in slides}
def attach(slide, src, caption, first=False):
    entry = {"src": src, "name": caption}
    if any(e["src"] == src for e in attached[slide["key"]]):
        return
    if first:
        attached[slide["key"]].insert(0, entry)
    else:
        attached[slide["key"]].append(entry)

SITE = {
    "rooms": ["RoomsListView", "RoomRow", "RoomRowViews", "AwaitingRow", "InboxScope", "ConversationPreview", "RelativeTimestampFormatter", "RoomsFocusFilter"],
    "conversation": ["ConversationView", "MessageBubbleView", "ReactionBar", "DeliveryMarkView", "ConversationSupport", "NoticeCopy"],
    "outposts": ["OutpostsView", "OutpostFeedView", "PostActions"],
    "you": ["YouView"],
    "supporter": ["SupporterWelcomeView", "SupporterView"],
    "verify": ["SoloCheckScreens", "CompareCodesView"],
    "audience": ["OutpostAudienceView"],
    "checkup": ["PrivacyCheckupView", "PrivacyCheckupPages", "PrivacyCheckupExamples"],
    "notifications": ["PermissionExplainerView"],
    "photos": ["PermissionExplainerView"],
}
SITE_CAPTION = {
    "rooms": "The Rooms tab, from the app", "conversation": "A conversation, from the app", "outposts": "The Outposts tab, from the app",
    "you": "The You tab, from the app", "supporter": "The supporter welcome, from the app", "verify": "Checking who you are talking to, from the app",
    "audience": "An Outpost's audience, from the app", "checkup": "The privacy check-up, from the app",
    "notifications": "Asking for notifications, from the app", "photos": "Asking for photos, from the app",
}
for shot, keys in SITE.items():
    src = os.path.join(HERE, "raw", f"site-{shot}.png")
    if not os.path.exists(src):
        continue
    rel = convert(src, f"site-{shot}")
    for key in keys:
        for s in slides_for_stem(key):
            attach(s, rel, SITE_CAPTION[shot], first=True)

results_path = os.path.join(HERE, "raw", "results.json")
previews = json.load(open(results_path)) if os.path.exists(results_path) else {}
PREVIEW_EXTRA = {
    "RoomsListPreviews": ["RoomsListView"], "PrivacyCheckupPreviews": ["PrivacyCheckupView", "PrivacyCheckupPages", "PrivacyCheckupExamples"],
    "RootViewPreviews": ["RoomsListView"], "DebugMenuView": ["YouView"],
}
SKIP_PREVIEW = {"SiteShotView", "HapticsProbeView", "OutpostMark", "AnimatedMark"}
for key, r in previews.items():
    if not r.get("png") or not os.path.exists(r["png"]):
        continue
    file_stem = stem(r["file"])
    if file_stem in SKIP_PREVIEW:
        continue
    rel = convert(r["png"], "preview-" + re.sub(r"[^A-Za-z0-9]+", "-", key))
    targets = slides_for_stem(file_stem)
    for extra in PREVIEW_EXTRA.get(file_stem, []):
        targets += slides_for_stem(extra)
    for s in targets:
        attach(s, rel, f"Preview: {r['name']} (the app's name shows as “Xcode Previews” here)")

catalogue = os.path.join(HERE, "catalogue")
manifest_path = os.path.join(catalogue, "manifest.json")
if os.path.exists(manifest_path):
    manifest = json.load(open(manifest_path))
    for test in manifest:
        for att in test.get("attachments", []):
            name = att.get("suggestedHumanReadableName") or att.get("exportedFileName")
            path = os.path.join(catalogue, att["exportedFileName"])
            label = re.sub(r"^\d{3} ", "", re.sub(r"_\d+_[0-9A-F-]+\.png$", "", name).replace(".png", ""))
            parts = [p.strip() for p in label.split("›")]
            last = parts[-1]
            rel = convert(path, "app-" + re.sub(r"[^A-Za-z0-9]+", "-", label)[:80])
            caption = "From the app: " + " › ".join(parts)
            PATH_MAP = {
                "You › Appearance › Color": ["Accent", "AccentPickerView"],
                "You › Appearance › App icon": ["AppIconChoice", "AppIconPickerView"],
                "You › Cassilda": ["IdentitySettingsView", "RenameMemberView"],
                "You › Become a Supporter": ["SupporterView", "SupporterSettings"],
                "You › Privacy & Safety": ["PrivacyAndSafetySettingsView"],
                "You › Privacy & Safety › Do Not Disturb message": ["FocusMessageView"],
            }
            mapped = [x for key in PATH_MAP.get(" › ".join(parts), []) for x in slides_for_stem(key)]
            for s in mapped:
                attach(s, rel, caption, first=True)
            matched = [s for s in slides if last in screen_titles(s)]
            if not matched:
                matched = [s for s in slides if last in all_texts(s)][:2]
            for s in matched:
                attach(s, rel, caption, first=True)

HOSTS = {
    "HonestCopy": [("RoomsListView", "These words are at the top of the Rooms list in this picture")],
    "MediaBodies": [("RoomsListView", "These words stand in for a photo or clip in the Rooms list")],
    "HelpButton": [("YouView", "This is the ? button at the top of this screen"), ("RoomsListView", "This is the ? button at the top of this screen")],
    "AccessWindowsCopy": [("OutpostAccessSheet", "These words are on this sheet")],
    "OutpostConsentCopy": [("OutpostSettingsView", "These words are on Outpost settings")],
    "AnonPersonaCopy": [("OutpostSettingsView", "These words are on Outpost settings")],
    "Projection": [("ConversationView", "Drawn in a conversation in place of a message; not in this picture")],
    "Payload+Making": [("ConversationView", "Drawn in a conversation as a notice; not in this picture")],
    "MediaLoader": [("ConversationView", "Drawn in a photo's place in a conversation when it can't be read; not in this picture")],
    "MediaPictureView": [("ConversationView", "Drawn as a photo in a conversation")],
    "MediaViewerView": [("ConversationView", "Opens from a photo in a conversation; not in this picture")],
    "HistoryRepairBanner": [("ConversationView", "Drawn at the top of a conversation while history is being fetched; not in this picture")],
    "HeldRestorePrompt": [("ConversationView", "Drawn in a conversation when someone restores; not in this picture")],
    "RefusedCheckView": [("SoloCheckScreens", "Drawn here when a check doesn't match; not in this picture")],
    "MembershipDecisionSheet": [("RoomMembersView", "Opens from a room's members; not in this picture")],
}

by_stem = {}
for s in slides:
    by_stem.setdefault(s["key"], s)
    by_stem.setdefault(stem(s["file"]), s)
for key, hosts in HOSTS.items():
    target = by_stem.get(key)
    if not target or attached[target["key"]]:
        continue
    for host_key, caption in hosts:
        host = by_stem.get(host_key)
        if host and attached[host["key"]]:
            attach(target, attached[host["key"]][0]["src"], caption)

prompts = os.path.join(HERE, "prompts", "manifest.json")
if os.path.exists(prompts):
    for test in json.load(open(prompts)):
        for att in test.get("attachments", []):
            name = att.get("suggestedHumanReadableName") or ""
            rel = convert(os.path.join(HERE, "prompts", att["exportedFileName"]), "prompt-" + ("camera" if "camera" in name else "notifications" if "notifications" in name else "other"))
            if "camera" in name:
                for key in ("Info", "InviteScanning", "Branding"):
                    target = by_stem.get(key)
                    if target:
                        attach(target, rel, "The system's camera prompt, in the app's own words (and its name)", first=True)

NO_PICTURE = {
    "MessageNotification": "A notification banner. The simulator didn't show a banner when one was pushed, so there is no picture yet.",
    "RestoreNotification": "A notification banner. The simulator didn't show a banner when one was pushed, so there is no picture yet.",
    "SessionProblem": "An alert shown after something fails. The demo app can't fail on purpose yet, so there is no picture.",
    "AppRootView": "Alerts shown after something fails. The demo app can't fail on purpose yet, so there is no picture.",
    "AppRootView ": "The question when a new device asks to be approved, and alerts shown after something fails. Neither can be brought up in the demo app yet.",
    "AppRootView+Media": "Shown under the composer when a clip is over 287 MB. The demo app doesn't prepare clips, so there is no picture.",
    "TestProfilesView": "A debug-only screen; it isn't in the app members get.",
    "AddTestProfileView": "A debug-only screen; it isn't in the app members get.",
    "TestSessionEscape": "A debug-only banner; it isn't in the app members get.",
    "Accessibility": "Words for paste buttons and VoiceOver, drawn inside other screens.",
}
for s in slides:
    s["shots"] = attached[s["key"]][:4]
    if not s["shots"]:
        name = os.path.basename(s["file"]).replace(".swift", "")
        if name == "AppRootView":
            s["noPicture"] = NO_PICTURE["AppRootView "]
        elif name in NO_PICTURE:
            s["noPicture"] = NO_PICTURE[name]
        else:
            s["noPicture"] = NO_PICTURE.get(s["key"]) or NO_PICTURE.get(stem(s["file"])) or ""
            if not s["noPicture"] and s["file"].startswith("App/Carpenter/AppRootView"):
                s["noPicture"] = NO_PICTURE["AppRootView"]
    for a in s["areas"]:
        for x in a["strings"]:
            x["text"] = re.sub(r"\{(20[0-9A-F]{2}|00[0-9A-F]{2})\}", lambda m: chr(int(m.group(1), 16)), x["text"])
json.dump(slides, open(os.path.join(REVIEW, "slides.json"), "w"), ensure_ascii=False)
have = sum(1 for s in slides if s["shots"])
print(f"{have} of {len(slides)} slides have a picture")
missing = [s["file"] for s in slides if not s["shots"]]
print("without:", len(missing))
for m in missing:
    print("  ", m)

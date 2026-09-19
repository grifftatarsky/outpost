#!/bin/bash
#
# §3.3: the product name lives in Config/Branding.xcconfig and nowhere else.
#
# Everything else in the repository is named after the *source name* — Carpenter — which is
# deliberately not the product name, so that renaming the product stays a one-line edit and a
# signature never stops verifying because the product was renamed (Build Decision D31).
#
# Fails on three things:
#   1. The old codename `parlor` anywhere outside Config/, docs/ and the design document.
#   2. The dead name `DeC`/`deC`/`dec.`, which the Carpenter rename retired.
#   3. A Swift string literal equal to the display name, which is what makes a rename a
#      find-and-replace instead of a one-line edit.
#
# The display name is read back out of Branding.xcconfig rather than written here, so this script
# keeps working after the next rename.
#
# Run from anywhere; paths resolve against the repository root.

set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root" || exit 1

status=0

report() {
    printf '\n%s\n' "$1"
    printf '%s\n' "$2"
    status=1
}

# Source under review: hand-written files only. Generated resource accessors and the package
# manifest legitimately carry the module name.
sources=$(
    find Packages/Carpenter/Sources App -name '*.swift' -not -path '*/.build/*' 2>/dev/null
)

# 1. The codename must not survive into the product.
codename_hits=$(
    grep -rniE '\bparlor\b' \
        --include='*.swift' --include='*.plist' --include='*.entitlements' \
        --include='*.xcconfig' --include='*.pbxproj' --include='*.xcstrings' \
        --exclude-dir='.build' \
        Packages/Carpenter/Sources App Config 2>/dev/null
)
if [ -n "$codename_hits" ]; then
    report "error: the codename 'parlor' appears outside Config/ and documentation:" "$codename_hits"
fi

# 2. The retired name must not come back. `dec.` catches the crypto domain tags, whose prefix is
#    the source name precisely so that it survives a product rename.
dead_hits=$(
    grep -rnE '\b[Dd]eC\b|\bdec\.[a-z]' \
        --include='*.swift' --include='*.plist' --include='*.entitlements' \
        --include='*.xcconfig' --include='*.pbxproj' --include='*.xcstrings' \
        --exclude-dir='.build' --exclude-dir='xcuserdata' \
        Packages/Carpenter/Sources Packages/Carpenter/Tests App Config 2>/dev/null
)
if [ -n "$dead_hits" ]; then
    report "error: the retired name 'DeC' reappears; the source name is Carpenter:" "$dead_hits"
fi

# 3. The source name must not reach a screen.
#    "Carpenter" is what the code is called, not what the product is called. A string literal
#    carrying it is user-facing copy naming the wrong thing — which is exactly the mistake §3.3
#    exists to make impossible, in the opposite direction. Identifiers (CarpenterFont, and the rest)
#    are not literals and are unaffected; lowercase bundle identifiers are allowed.
source_name_hits=$(
    # shellcheck disable=SC2086
    grep -nE '"[^"]*\bCarpenter\b[^"]*"' $sources 2>/dev/null
)
if [ -n "$source_name_hits" ]; then
    report "error: the source name appears in a string literal; use Branding.displayName:" "$source_name_hits"
fi

# 4. The display name must not be written down in Swift.
#    Branding.swift reads it from the bundle; everything else goes through Branding.displayName.
#
#    An exact-literal match, not a substring one: "Outpost" is also this app's word for a member's
#    own feed, so "Your Outpost" and "Outposts" are domain vocabulary and must stay legal. Only a
#    literal that *is* the product name is a branding leak.
display_name=$(
    sed -n 's/^APP_DISPLAY_NAME[[:space:]]*=[[:space:]]*//p' Config/Branding.xcconfig | tr -d '\r'
)
if [ -z "$display_name" ]; then
    report "error: APP_DISPLAY_NAME is missing from Config/Branding.xcconfig" "(nothing to check against)"
else
    name_hits=$(
        # shellcheck disable=SC2086
        grep -nF "\"$display_name\"" $sources 2>/dev/null \
            | grep -v 'Sources/CarpenterKit/Branding.swift' \
            | grep -v 'App/CarpenterTests/'
    )
    if [ -n "$name_hits" ]; then
        report "error: the display name is hard-coded in Swift; use Branding.displayName:" "$name_hits"
    fi
fi

# 5. A button with an empty action compiles, renders, and does nothing.
#    This has shipped three times: onboarding's "I have an invite", the rooms list's "Join with an
#    invite", and the room header's menu. Each looked finished and was dead. A closure that is
#    genuinely meant to do nothing should say so with an explicit comment on the same line.
dead_buttons=$(
    # shellcheck disable=SC2086
    grep -nE -A1 'Button \{[[:space:]]*$' $sources 2>/dev/null \
        | grep -E '^[^:]+[-:][0-9]+[-:][[:space:]]*\}[[:space:]]*label:' \
        | grep -v 'intentionally empty'
)
if [ -n "$dead_buttons" ]; then
    report "error: Button with an empty action — it will render and do nothing:" "$dead_buttons"
fi

# 6. Motion must answer to Reduce Motion.
#    §9.2 row 19's audit found the app has no motion to reduce: one explicit animation, and it is a
#    colour cross-fade, which is what Reduce Motion asks motion to be *replaced with*. That is a
#    fact about today, not a property of the code, and the next animation someone adds is where it
#    would quietly stop being true.
#
#    So: a file that animates must either consult `accessibilityReduceMotion` or say on the line
#    that what it animates is a cross-fade. Sheets, pushes and `ProgressView` are the system's own
#    and honour the setting without help — this only covers motion the app asks for itself.
#
#    A view split across files (2026-09-14) declares the environment value once, in the file that
#    holds the stored properties, and *uses* it in the extensions — which cannot declare one. So a
#    file that consults it as `reduceMotion ?` answers the rule as surely as one that declares it.
#    Matching the use rather than a bare name is deliberate: an unrelated local called
#    `reduceMotion` would not excuse a file.
motion_hits=""
for file in $sources; do
    grep -qE 'accessibilityReduceMotion|reduceMotion \?' "$file" && continue
    # The marker may sit on the animating line or in a comment just above it, which is where
    # anyone explaining themselves would actually write it.
    hits=$(
        awk '
            { line[NR] = $0 }
            /withAnimation|\.animation\(|\.transition\(|matchedGeometryEffect|repeatForever/ {
                excused = 0
                for (i = NR - 3; i <= NR; i++) {
                    if (i > 0 && line[i] ~ /cross-fade only/) excused = 1
                }
                if (!excused) printf "%d:%s\n", NR, $0
            }
        ' "$file" 2>/dev/null
    )
    [ -n "$hits" ] && motion_hits+="$file"$'\n'"$hits"$'\n'
done
if [ -n "$motion_hits" ]; then
    report "error: animation that neither honours Reduce Motion nor declares itself a cross-fade:" "$motion_hits"
fi

# 7. A section label is a heading, and must be announced as one.
#    §9.2 row 19 found nine section labels styled as headings and marked as none, so VoiceOver's
#    Headings rotor had nothing to jump between on any screen. `.sectionHeading()` applies the type
#    and the trait together precisely so the two cannot come apart again; reaching for the font
#    directly is how they did.
section_font_hits=$(
    # shellcheck disable=SC2086
    grep -nE '\.font\(CarpenterFont\.sectionLabel\)' $sources 2>/dev/null
)
if [ -n "$section_font_hits" ]; then
    report "error: section label styled without the heading trait; use .sectionHeading():" "$section_font_hits"
fi

# 8. A filled accent button must read its own enabled state.
#    Drawing the background inside the label means `.disabled(_:)` suppresses the tap and changes
#    nothing on screen — onboarding's "Create my identity" sat at full strength with an empty name
#    field. `primaryAction()` dims fill and label together (§9.2 row 24, Build Decision D55).
hand_drawn=$(
    # shellcheck disable=SC2086
    grep -nE -A1 '\.background\($' $sources 2>/dev/null \
        | grep -E 'palette\.accentColor,$'
)
if [ -n "$hand_drawn" ]; then
    report "error: accent button drawing its own background; use primaryAction():" "$hand_drawn"
fi

# 9. Native first: a hand-drawn hairline is a list somebody did not use.
#    A `VStack` of buttons with `Rectangle().fill(palette.separator)` between them is an
#    inset-grouped `List` section, reimplemented — and reimplemented differently on each screen that
#    does it. Three screens had one; each got the separator inset slightly wrong, none of them
#    inherits what the system does to a list next year, and the row-selection idiom drifted between
#    them. `List` + `Section` + `.groupedRowSurface()` + `ChoiceRow` is the shape.
#
#    A hairline that genuinely divides two *regions* rather than two rows is legitimate; say so on
#    the line and this leaves it alone.
separator_hits=""
for file in $sources; do
    hits=$(
        awk '
            { line[NR] = $0 }
            /\.fill\(palette\.separator\)/ {
                # A comment describing the pattern is not the pattern.
                if ($0 ~ /^[[:space:]]*\/\//) next
                excused = 0
                for (i = NR - 4; i <= NR; i++) {
                    if (i > 0 && line[i] ~ /divides regions/) excused = 1
                }
                if (!excused) printf "%d:%s\n", NR, $0
            }
        ' "$file" 2>/dev/null
    )
    [ -n "$hits" ] && separator_hits+="$file"$'\n'"$hits"$'\n'
done
if [ -n "$separator_hits" ]; then
    report "error: hand-drawn row separator; use a List section (or say 'divides regions'):" "$separator_hits"
fi

# 10. A symbol name that does not exist draws nothing, silently.
#     `paperplane.slash` was never an SF Symbol, so the delivery state whose whole purpose was that a
#     solo member's message must not look like a failed send rendered a blank instead — for as long
#     as it had existed, with its own doc comment describing the fix. `SymbolNameTests` checks every
#     name in the suite; this is the same check at lint time, so a bad name fails before the build.
if command -v swift >/dev/null 2>&1 && [ "${SKIP_SYMBOL_CHECK:-}" != "1" ]; then
    # shellcheck disable=SC2086
    symbol_names=$(grep -rhoE 'systemName: "[^"]+"' $sources 2>/dev/null | sed 's/systemName: "//; s/"$//' | sort -u)
    if [ -n "$symbol_names" ]; then
        missing=$(
            printf '%s\n' "$symbol_names" | while IFS= read -r name; do
                printf 'import AppKit\nexit(NSImage(systemSymbolName: "%s", accessibilityDescription: nil) == nil ? 1 : 0)\n' "$name" > /tmp/.carpenter-symbol.swift
                swift /tmp/.carpenter-symbol.swift >/dev/null 2>&1 || echo "$name"
            done
        )
        if [ -n "$missing" ]; then
            report "error: Image(systemName:) names a symbol the system does not have — it draws nothing:" "$missing"
        fi
    fi
fi

# 11. Sibling Liquid Glass shapes belong in a container.
#     Apple's guidance is explicit: "Use GlassEffectContainer when applying Liquid Glass effects on
#     multiple views to achieve the best rendering performance", and "applying too many effects to
#     views outside of containers can degrade performance." A container is also the only way two
#     shapes can blend or morph into each other, which is most of what Liquid Glass is *for*.
#
#     The heuristic is a file with more than one `.glassEffect(` and no container. It is not exact —
#     two effects on unrelated screens in one file are fine — so a file that has thought about it can
#     say `one glass shape per screen` and be left alone.
glass_hits=""
for file in $sources; do
    effects=$(grep -c '\.glassEffect(' "$file" 2>/dev/null)
    [ "$effects" -gt 1 ] || continue
    grep -q 'GlassEffectContainer' "$file" && continue
    grep -q 'one glass shape per screen' "$file" && continue
    glass_hits+="$file ($effects effects, no GlassEffectContainer)"$'\n'
done
if [ -n "$glass_hits" ]; then
    report "error: sibling Liquid Glass effects outside a GlassEffectContainer:" "$glass_hits"
fi

# 12. Copy a member reads must be translatable.
#     `Text("…")` without `bundle: .module` resolves against the *main* bundle, which for a string
#     defined in a package is the wrong catalogue — so the string is never extracted, never
#     translated, and quietly ships in English forever. It is also invisible: the English build
#     looks perfect.
#
#     This is not hypothetical. Converting `NotificationLevelView` to a `List` rewrote one of its
#     `Text` calls and dropped the bundle in the process; nothing noticed until this rule existed.
#
#     `Text(verbatim:)` is the escape hatch for something that is genuinely not prose — a code, a
#     fingerprint, an empty label — and says so at the call site.
unbundled_copy=$(
    grep -rnE 'Text\("' Packages/Carpenter/Sources/CarpenterUI --include='*.swift' 2>/dev/null \
        | grep -v 'bundle: \.module' \
        | grep -v 'verbatim' \
        | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//'
)
if [ -n "$unbundled_copy" ]; then
    report "error: user-facing Text without bundle: .module — it will never be translated:" "$unbundled_copy"
fi

# 12b. The same defect one type over, which rule 12's grep cannot see.
#      A string literal coerced to a `LocalizedStringResource` inside the package resolves against
#      `Bundle.main` — the app's catalogue — so it is never extracted from the package and ships in
#      English for ever, invisibly. It had swallowed nine strings before anybody read for it:
#      *Messages*, *Solos*, *Rooms*, four empty states and three search prompts, found in the
#      verification design pass on 2026-09-09 and not by any check.
#
#      `LocalizedStringKey` is deliberately not covered — a key carries no bundle by design, and the
#      screens that use one supply it at the `Text(key, bundle: .module)` call site, correctly.
if command -v python3 >/dev/null 2>&1; then
    unbundled_resource=$(python3 Scripts/lint/localized-resource-bundle.py 2>/dev/null)
    if [ -n "$unbundled_resource" ]; then
        report "error: LocalizedStringResource from a bare literal — it reads the app's catalogue, not the package's:" "$unbundled_resource"
    fi
else
    report "error: python3 is missing, so the LocalizedStringResource rule did not run." ""
fi

# 13. A nil check separated from its assignment by an `await`, inside a reentrant actor.
#     The reasoning is in the script's own docstring; it is long enough to deserve a file.
#     A rule that silently skips is the same failure as a test nobody runs: it looks like coverage.
#     So a missing interpreter is said out loud rather than shrugged off.
if command -v python3 >/dev/null 2>&1; then
    reentrancy=$(python3 Scripts/lint/reentrancy.py 2>/dev/null)
    if [ -n "$reentrancy" ]; then
        report "error: actor reentrancy — a nil check the await can outlive:" "$reentrancy"
    fi
else
    printf '\nwarning: python3 not found; the actor-reentrancy rule did not run.\n'
fi

# 14. A destructive control that draws a symbol must name its colour.
#     `Button(role: .destructive)` reddens the words and not the glyph, because this app tints its
#     whole hierarchy and a label's symbol takes the inherited tint ahead of the role. Six controls
#     have shipped saying "Remove" in red beside a cheerful green icon. The script's docstring has
#     the list and the reasoning.
if command -v python3 >/dev/null 2>&1; then
    destructive=$(python3 Scripts/lint/destructive-tint.py 2>/dev/null)
    if [ -n "$destructive" ]; then
        report "error: destructive button with an accent-coloured glyph — a tint beats a role:" "$destructive"
    fi
else
    printf '\nwarning: python3 not found; the destructive-tint rule did not run.\n'
fi

# VoiceOver's rotor navigates by heading, so a headline drawn at title size with no heading trait is
#     invisible to every way of skimming a screen except walking it element by element. Measured on
#     the rig 2026-09-17 with VoiceOver running: two screens announced their name as plain text while
#     the rest said "..., Heading". The script's docstring has the reasoning.
if command -v python3 >/dev/null 2>&1; then
    headings=$(python3 Scripts/lint/screen-headings.py 2>/dev/null)
    if [ -n "$headings" ]; then
        report "error: a screen headline with no heading trait — the rotor cannot find it:" "$headings"
    fi
else
    printf '\nwarning: python3 not found; the screen-heading rule did not run.\n'
fi

# A control's label is sentence case like its neighbours. *User Avatars* sat among *Color*, *App
#     icon* and *Share my name* for months, title-cased and saying "user", and nobody saw it until
#     every switch in the app was traced on 2026-09-17. The script's docstring holds the proper-noun
#     table; a real name goes in there rather than the rule being loosened.
if command -v python3 >/dev/null 2>&1; then
    labels=$(python3 Scripts/lint/control-label-case.py 2>/dev/null)
    if [ -n "$labels" ]; then
        report "error: a control label in title case — its neighbours are sentence case:" "$labels"
    fi
else
    printf '\nwarning: python3 not found; the control-label rule did not run.\n'
fi

# Swift carries no comments but the ones a tool reads. The script's docstring has the history.
if command -v python3 >/dev/null 2>&1; then
    comments=$(python3 Scripts/lint/no-comments.py 2>/dev/null)
    if [ -n "$comments" ]; then
        report "error: a comment in Swift — put it in docs/, not above a line:" "$comments"
    fi
else
    printf '\nwarning: python3 not found; the no-comments rule did not run.\n'
fi

# A context menu's preview is hosted outside the hierarchy that themed it, so `\.palette` falls back
#     to its default — which is dark, unconditionally. A preview that forgets to re-theme itself
#     draws dark inside a light app, and does it quietly, because every colour in it is a real
#     palette colour. Found on the rig 2026-09-14 on the rooms list.
if command -v python3 >/dev/null 2>&1; then
    unthemed=$(python3 Scripts/lint/detached-preview-theme.py 2>/dev/null)
    if [ -n "$unthemed" ]; then
        report "error: a context menu preview does not re-apply the theme — it will draw dark in a light app:" "$unthemed"
    fi
else
    printf '\nwarning: python3 not found; the detached-preview-theme rule did not run.\n'
fi

# A double slash opens a comment in an xcconfig, so `APP_X = https://host/path` assigns `https:`
#     and the app holds a URL with no host. It builds, it lints, it launches, and the link opens
#     nothing. Both form URLs shipped that way and it was found on the rig 2026-09-17, in the one
#     sentence that names the host out loud.
if command -v python3 >/dev/null 2>&1; then
    hostless=$(python3 Scripts/lint/xcconfig-urls.py 2>&1 >/dev/null)
    if [ -n "$hostless" ]; then
        report "error: a URL in an xcconfig is cut off at its double slash:" "$hostless"
    fi
else
    printf '\nwarning: python3 not found; the xcconfig URL rule did not run.\n'
fi

# macOS sizes a sheet to its content, and a List, a ScrollView or a TextEditor has none. The
#     notifications explainer reached the Mac on 2026-09-18 as a Continue button with nothing above it,
#     and the new-post sheet collapsed the same way. sizedSheet gives the Mac a form size.
if command -v python3 >/dev/null 2>&1; then
    bare=$(python3 Scripts/lint/sheet-sizing.py 2>/dev/null)
    if [ -n "$bare" ]; then
        report "error: a bare .sheet( — use .sizedSheet( so the Mac gets a size:" "$bare"
    fi
else
    printf '\nwarning: python3 not found; the sheet-sizing rule did not run.\n'
fi

if [ "$status" -eq 0 ]; then
    echo "branding lint: clean"
fi

exit "$status"

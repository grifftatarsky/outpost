<!-- COPY BEGIN 197aa307 [NEEDS HUMAN REVIEW] -->

# Brand assets — complete set

The eight files in this directory's root are what the 2026-08-18 design pass was given: full lockups,
dark only, one per accent. That subset is what produced **blocker D1** ("the app icon has no
glyph-only mark to draw"), which was a correct statement about those eight files and a wrong
conclusion about the brand assets.

**Superseded 2026-08-19.** the mark is now one template vector — `OutpostLogo` in `CarpenterUI`'s asset catalogue, tinted in code by `OutpostMark`, so appearance and accent are not files; this set was retired to `~/Downloads/older logos`. It read:
The complete set is here, and has been all along, in `Design/logos/`:

| Directory | Files | What |
|---|---|---|
| `icon/` | 23 | **The glyph alone.** `icon_white_<accent>` and `icon_black_<accent>` per accent, plus `_hollow` variants. |
| `wordmark/` | 10 | The name set as type, per accent plus black, white and foundation. |
| `full/` | 24 | Lockups — glyph and wordmark together — per accent in dark, light and hollow. |

`icon_white_<accent>.svg` is the white-on-accent variant board 83 asks for.

<!-- COPY END 197aa307 -->

<!-- COPY BEGIN 3cfe0c8e [NEEDS HUMAN REVIEW] -->

## One naming inconsistency

The SVGs spell it **verdegris**; the app spells it **verdigris**, in `Accent.swift`, in
`AppIconChoice.catalogueSuffix` and in the asset catalog (`AppIcon-VerdigrisDark.appiconset`). The
design pass also writes verdigris.

Nothing resolves these SVGs by name at runtime, so this breaks nothing today — the app draws from the
asset catalog, which is consistent. It matters at the point somebody regenerates the icon sets from
source and the filename does not match the accent case it belongs to.

<!-- COPY END 3cfe0c8e -->

# Harness image-format support

**Last updated: 2026-07-25.**

Seen's image defaults (PNG, 1568 px longest edge) were chosen for Anthropic's
vision API. Every other harness is an assumption until someone checks. This
document records what we actually know, when we last confirmed it, and what
would change our defaults — so the review is a five-minute diff rather than a
re-derivation.

**Re-check this whenever** a harness ships a vision change, a new harness gets
added to the README, or someone proposes changing a default. If the date above
is more than ~6 months stale, treat every row as unverified.

## What Seen emits today

| | value | where |
|---|---|---|
| Default format | PNG | `AppSettings.swift:10-20` |
| Default longest edge (agents) | 1568 px | same |
| Longest edge (hotkey/menu) | 2048 px | `HumanCapture.swift` |
| Per-request overrides | `format`, `quality`, `maxDimension` | `docs/api.md` |
| Formats that encode | `png`, `jpeg` | `ImageFormat` |
| Formats that throw | `webp` (`unsupportedFormat`) | see below |

PNG is default because Claude bills images by **dimensions, not bytes** — so
lossless costs no extra tokens while keeping on-screen text crisp. That
reasoning is Anthropic-specific and is exactly what needs re-testing per harness.

OCR always runs on the full-resolution frame *before* downscaling, so none of
these numbers affect text fidelity — only what a vision model sees.

## Per-harness status

| Harness | Accepted formats | Resolution handling | Last verified |
|---|---|---|---|
| **Claude** (Claude Code, API) | jpeg, png, gif, webp. **Not** heic or avif | Bills by dimensions; 1568 px longest edge recommended | 2026-07-08 — verified when HEIC was removed after an agent-handed HEIC capture 400'd |
| **Cursor** | Unverified | Unverified | Never |
| **Codex** | Unverified | Unverified | Never |
| **Cline** | Unverified | Unverified | Never |
| **Antigravity / Gemini-backed** | Unverified | Unverified | Never |

Only the Claude row is evidence-based. The rest are listed so the gaps are
visible rather than implied — do not treat blank rows as "works fine."

### How to verify a row

1. Find the harness's documented accepted MIME types (its vision/attachment docs).
2. Capture at Seen's default and at a larger size; hand both to the harness.
3. Note whether it re-encodes or downscales on its own — if it does, Seen
   shrinking first may be wasted work or actively lossy.
4. Record the date and the evidence in the table. An unverified claim is worse
   than a blank cell.

## WebP — not supported by Seen, evaluate later

**Status: not implemented.** `ImageFormat` carries a `webp` case, but encoding
throws `unsupportedFormat`. The blocker is the platform, not the design: macOS
ImageIO ships **no WebP encoder** —
`CGImageDestinationCopyTypeIdentifiers()` omits `org.webmproject.webp`
(verified 2026-07-08). Claude's vision API *does* accept `image/webp`, so the
gap is purely on our side.

Adding it would mean vendoring an encoder (`libwebp` or `SDWebImageWebPCoder`),
which is the first third-party dependency this package would take — currently
only `swift-argument-parser`. That cost is why it hasn't been done.

**Do not build this yet.** Evaluate only when both conditions hold:

1. **macOS gains a WebP encoder**, or we accept the dependency; and
2. **At least one harness we actually target measurably benefits** — smaller
   payload at equal legibility, or lower cost.

Condition 2 is the one people skip. For Claude specifically, WebP may win on
bytes but **not on tokens**, since billing is by dimensions — so a smaller file
could buy nothing at all. The evaluation must measure the thing that costs
money for that harness, not just file size. If no harness benefits, the right
outcome is to close this out and delete the `webp` case rather than carry a
throwing enum forever.

## Related

- `ARCHITECTURE.md` § Imaging pipeline — the design rationale.
- `docs/api.md` — normative contract for `format` / `maxDimension`.

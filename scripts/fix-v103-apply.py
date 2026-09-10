from pathlib import Path

path = Path(__file__).resolve().parent / "apply-v103-startup-update.py"
text = path.read_text(encoding="utf-8")
old = "if (-not $Readme.Contains('In-app update check') -or -not $ReadmeZh.Contains('应用内更新')) {\\n    throw 'Primary READMEs must document the clickable in-app update flow.'\\n}\\n"
new = "if (-not $Readme.Contains('Version and in-app updates') -or -not $ReadmeZh.Contains('版本与应用内更新')) {\\n    throw 'Primary READMEs must document the clickable in-app update flow.'\\n}\\n"
if old not in text:
    raise SystemExit('unable to locate stale final-docs matcher in apply script')
text = text.replace(old, new, 1)
text = text.replace(
    "PASS: user-facing documentation matches the Codex-only v1.0.2 product state with manual in-app updates.",
    "PASS: user-facing documentation matches the Codex-only v1.0.3 product state with secure manual in-app updates.",
)
path.write_text(text, encoding="utf-8", newline="\n")
print('Patched one-shot apply script matcher.')

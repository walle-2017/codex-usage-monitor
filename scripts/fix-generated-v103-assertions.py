from pathlib import Path

path = Path(__file__).resolve().parent / "assert-runtime-log.ps1"
text = path.read_text(encoding="utf-8")
old = '''if ($main -match '(?m)^\\s*if\\s+let\\s+Ok\\(path\\)\\s*=\\s*diagnose::init\\(\\)') {
    throw 'diagnose::init() must not run unconditionally during normal startup.'
}
'''
if old not in text:
    raise SystemExit('unable to locate obsolete diagnose false-positive assertion')
text = text.replace(old, '', 1)
path.write_text(text, encoding="utf-8", newline="\n")
print('Removed obsolete diagnose false-positive assertion.')

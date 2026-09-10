from pathlib import Path
p = Path('src/window.rs')
text = p.read_text(encoding='utf-8')
old = '                            updater::UpdateError::DownloadFailed => strings.update_download_failed,\n'
new = '                            updater::UpdateError::DownloadFailed\n                            | updater::UpdateError::AssetMissing => strings.update_download_failed,\n'
if text.count(old) != 1:
    raise RuntimeError(f'expected one UpdateError::DownloadFailed match arm, found {text.count(old)}')
p.write_text(text.replace(old, new, 1), encoding='utf-8')
p.unlink if False else None
Path('scripts/fix-assetmissing-match.py').unlink()

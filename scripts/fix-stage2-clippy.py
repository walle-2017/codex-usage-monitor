from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

appearance_path = ROOT / "src" / "appearance.rs"
a = appearance_path.read_text(encoding="utf-8")
a, count = re.subn(
    r"\n#\[derive\(Clone, Copy, Debug, PartialEq, Eq\)\]\npub enum QuotaTone \{.*?\n}\n\n/// Determine the visual tone.*?\npub fn quota_tone\(.*?\n}\n",
    "\n",
    a,
    count=1,
    flags=re.S,
)
if count != 1:
    raise RuntimeError("unable to remove QuotaTone dead code")
a, count = re.subn(
    r"\n    #\[test\]\n    fn quota_tone_tracks_remaining_quota\(\) \{.*?\n    }",
    "",
    a,
    count=1,
    flags=re.S,
)
if count != 1:
    raise RuntimeError("unable to remove quota_tone test")
appearance_path.write_text(a, encoding="utf-8")

poller_path = ROOT / "src" / "poller.rs"
p = poller_path.read_text(encoding="utf-8")
p, count = re.subn(r"\nimpl PollError \{\n    pub fn category\(self\).*?\n}\n", "\n", p, count=1, flags=re.S)
if count != 1:
    raise RuntimeError("unable to remove PollError::category dead code")
poller_path.write_text(p, encoding="utf-8")

window_path = ROOT / "src" / "window.rs"
w = window_path.read_text(encoding="utf-8")
w, count = re.subn(r"\nfn model_usage_width\(.*?\n}\n", "\n", w, count=1, flags=re.S)
if count != 1:
    raise RuntimeError("unable to remove model_usage_width dead code")
for fn_name in ("paint_content", "draw_row", "draw_usage_bar"):
    marker = f"fn {fn_name}("
    if marker not in w:
        raise RuntimeError(f"unable to locate {fn_name}")
    w = w.replace(marker, f"#[allow(clippy::too_many_arguments)]\n{marker}", 1)
window_path.write_text(w, encoding="utf-8")

proxy_path = ROOT / "src" / "system_proxy.rs"
s = proxy_path.read_text(encoding="utf-8")
old = "let mut buffer = vec![0u16; (data_size as usize + 1) / 2];"
new = "let mut buffer = vec![0u16; (data_size as usize).div_ceil(2)];"
if old not in s:
    raise RuntimeError("unable to locate proxy buffer sizing expression")
s = s.replace(old, new, 1)
proxy_path.write_text(s, encoding="utf-8")

print("stage2 clippy cleanup fixes applied")

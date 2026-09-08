from pathlib import Path

cargo_path = Path(__file__).resolve().parents[1] / "Cargo.toml"
cargo = cargo_path.read_text(encoding="utf-8")
needle = '    "Win32_System_Threading",\n'
if '    "Win32_Security",\n' not in cargo:
    if needle not in cargo:
        raise RuntimeError("unable to locate Win32_System_Threading feature")
    cargo = cargo.replace(needle, '    "Win32_Security",\n' + needle, 1)
cargo_path.write_text(cargo, encoding="utf-8")
print("preserved Win32_Security for CreateMutexW")

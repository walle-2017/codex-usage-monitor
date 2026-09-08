#![windows_subsystem = "windows"]

mod appearance;
mod diagnose;
mod localization;
mod models;
mod native_interop;
mod poller;
mod system_proxy;
mod theme;
mod tray_icon;
mod window;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let diagnose_enabled = args.iter().any(|arg| arg == "--diagnose");
    if diagnose_enabled {
        match diagnose::init() {
            Ok(path) => {
                diagnose::log(format!("startup args={args:?} log_path={}", path.display()));
                diagnose::log(format!(
                    "version={} executable={}",
                    env!("CARGO_PKG_VERSION"),
                    std::env::current_exe()
                        .map(|value| value.display().to_string())
                        .unwrap_or_else(|error| format!("unavailable:{error}"))
                ));
            }
            Err(error) => {
                let _ = error;
            }
        }
    }

    system_proxy::apply_windows_system_proxy_env();

    if diagnose_enabled {
        diagnose::log("entering window::run");
    }
    window::run();
}

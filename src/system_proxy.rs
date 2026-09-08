use std::ffi::c_void;

use windows::Win32::Foundation::ERROR_SUCCESS;
use windows::Win32::System::Registry::{
    RegGetValueW, HKEY_CURRENT_USER, RRF_RT_REG_DWORD, RRF_RT_REG_SZ,
};

use crate::diagnose;

const INTERNET_SETTINGS_KEY: &str = r"Software\Microsoft\Windows\CurrentVersion\Internet Settings";

/// Apply the Windows per-user manual proxy as a fallback for HTTP clients that
/// already support the standard proxy environment variables.
///
/// Explicit HTTP_PROXY / HTTPS_PROXY / ALL_PROXY values always win. PAC/WPAD is
/// intentionally out of scope; only ProxyEnable + ProxyServer are used.
pub fn apply_windows_system_proxy_env() {
    if proxy_env_configured() {
        diagnose::log(
            "explicit proxy environment configured; Windows system proxy fallback skipped",
        );
        return;
    }

    let Some(proxy) = read_windows_system_proxy() else {
        diagnose::log("Windows system proxy is disabled or unavailable; using direct networking");
        return;
    };

    std::env::set_var("HTTPS_PROXY", &proxy);
    std::env::set_var("HTTP_PROXY", &proxy);
    diagnose::log("using Windows system proxy");
}

fn proxy_env_configured() -> bool {
    proxy_env_configured_values(
        std::env::var("HTTPS_PROXY").ok().as_deref(),
        std::env::var("HTTP_PROXY").ok().as_deref(),
        std::env::var("ALL_PROXY").ok().as_deref(),
    )
}

fn proxy_env_configured_values(
    https_proxy: Option<&str>,
    http_proxy: Option<&str>,
    all_proxy: Option<&str>,
) -> bool {
    [https_proxy, http_proxy, all_proxy]
        .into_iter()
        .flatten()
        .any(|value| !value.trim().is_empty())
}

fn read_windows_system_proxy() -> Option<String> {
    let enabled = read_registry_dword("ProxyEnable")?;
    if enabled == 0 {
        return None;
    }

    parse_proxy_server(&read_registry_string("ProxyServer")?)
}

fn read_registry_dword(value_name: &str) -> Option<u32> {
    let subkey = wide_null(INTERNET_SETTINGS_KEY);
    let value = wide_null(value_name);
    let mut data = 0u32;
    let mut data_size = std::mem::size_of::<u32>() as u32;

    let status = unsafe {
        RegGetValueW(
            HKEY_CURRENT_USER,
            windows::core::PCWSTR(subkey.as_ptr()),
            windows::core::PCWSTR(value.as_ptr()),
            RRF_RT_REG_DWORD,
            None,
            Some((&mut data as *mut u32).cast::<c_void>()),
            Some(&mut data_size),
        )
    };

    (status == ERROR_SUCCESS).then_some(data)
}

fn read_registry_string(value_name: &str) -> Option<String> {
    let subkey = wide_null(INTERNET_SETTINGS_KEY);
    let value = wide_null(value_name);
    let subkey = windows::core::PCWSTR(subkey.as_ptr());
    let value = windows::core::PCWSTR(value.as_ptr());
    let mut data_size = 0u32;

    let status = unsafe {
        RegGetValueW(
            HKEY_CURRENT_USER,
            subkey,
            value,
            RRF_RT_REG_SZ,
            None,
            None,
            Some(&mut data_size),
        )
    };
    if status != ERROR_SUCCESS || data_size < 2 {
        return None;
    }

    let mut buffer = vec![0u16; (data_size as usize + 1) / 2];
    let status = unsafe {
        RegGetValueW(
            HKEY_CURRENT_USER,
            subkey,
            value,
            RRF_RT_REG_SZ,
            None,
            Some(buffer.as_mut_ptr().cast::<c_void>()),
            Some(&mut data_size),
        )
    };
    if status != ERROR_SUCCESS {
        return None;
    }

    let end = buffer
        .iter()
        .position(|ch| *ch == 0)
        .unwrap_or(buffer.len());
    Some(String::from_utf16_lossy(&buffer[..end]))
}

fn wide_null(value: &str) -> Vec<u16> {
    value.encode_utf16().chain(std::iter::once(0)).collect()
}

fn parse_proxy_server(value: &str) -> Option<String> {
    let value = value.trim();
    if value.is_empty() {
        return None;
    }

    if !value.contains('=') {
        return normalize_proxy_url(value);
    }

    let mut http = None;
    let mut https = None;
    for entry in value
        .split(';')
        .map(str::trim)
        .filter(|entry| !entry.is_empty())
    {
        let Some((scheme, address)) = entry.split_once('=') else {
            continue;
        };
        match scheme.trim().to_ascii_lowercase().as_str() {
            "https" => https = normalize_proxy_url(address),
            "http" => http = normalize_proxy_url(address),
            _ => {}
        }
    }

    https.or(http)
}

fn normalize_proxy_url(value: &str) -> Option<String> {
    let value = value.trim();
    if value.is_empty() {
        return None;
    }
    if value.contains("://") {
        Some(value.to_string())
    } else {
        Some(format!("http://{value}"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_single_windows_proxy_for_https() {
        assert_eq!(
            parse_proxy_server("127.0.0.1:7890"),
            Some("http://127.0.0.1:7890".to_string())
        );
    }

    #[test]
    fn prefers_https_entry_from_protocol_proxy_list() {
        assert_eq!(
            parse_proxy_server("http=127.0.0.1:7890;https=127.0.0.1:7891"),
            Some("http://127.0.0.1:7891".to_string())
        );
    }

    #[test]
    fn falls_back_to_http_entry_when_https_entry_is_missing() {
        assert_eq!(
            parse_proxy_server("http=127.0.0.1:7890"),
            Some("http://127.0.0.1:7890".to_string())
        );
    }

    #[test]
    fn preserves_explicit_proxy_scheme() {
        assert_eq!(
            parse_proxy_server("http://127.0.0.1:7890"),
            Some("http://127.0.0.1:7890".to_string())
        );
    }

    #[test]
    fn ignores_empty_or_unsupported_proxy_values() {
        assert_eq!(parse_proxy_server(""), None);
        assert_eq!(parse_proxy_server("socks=127.0.0.1:7890"), None);
    }

    #[test]
    fn explicit_proxy_environment_takes_precedence() {
        assert!(proxy_env_configured_values(
            None,
            Some("http://127.0.0.1:7890"),
            None
        ));
        assert!(proxy_env_configured_values(
            Some("http://127.0.0.1:7890"),
            None,
            None
        ));
        assert!(proxy_env_configured_values(
            None,
            None,
            Some("socks5://127.0.0.1:1080")
        ));
        assert!(!proxy_env_configured_values(None, None, None));
        assert!(!proxy_env_configured_values(Some(""), Some("  "), None));
    }
}

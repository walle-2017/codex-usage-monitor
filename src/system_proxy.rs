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
        assert!(proxy_env_configured_values(None, Some("http://127.0.0.1:7890"), None));
        assert!(proxy_env_configured_values(Some("http://127.0.0.1:7890"), None, None));
        assert!(proxy_env_configured_values(None, None, Some("socks5://127.0.0.1:1080")));
        assert!(!proxy_env_configured_values(None, None, None));
        assert!(!proxy_env_configured_values(Some(""), Some("  "), None));
    }
}

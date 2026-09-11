# Codex Usage Win Privacy Policy

**Effective date:** September 11, 2026  
**Publisher:** Walle Studio  
**Application:** Codex Usage Win

Codex Usage Win is a native Windows utility that displays Codex usage quota information in the Windows taskbar and notification area. This policy explains what information the application accesses, how it is used, and where it is sent.

## Information the application accesses

Codex Usage Win may access the following information on the user's device:

- **Codex authentication credentials** stored by Codex, normally in `%CODEX_HOME%\auth.json` or `%USERPROFILE%\.codex\auth.json`. The application reads the Codex access token and, when present, the Codex account identifier.
- **Codex usage information** returned by the Codex/ChatGPT usage service, such as usage percentages, rate-limit windows, and reset times.
- **Local application settings** such as display preferences, polling interval, language, startup preference, and alert thresholds.
- **Diagnostic information** only when the user explicitly starts the application with diagnostic logging enabled. Diagnostic logging is intended for troubleshooting and does not intentionally record Codex access tokens.

## How the information is used

Codex credentials are used only to authenticate requests made directly from the user's device to the Codex/ChatGPT usage service at `chatgpt.com` so that the application can retrieve and display the user's Codex usage information.

Codex Usage Win does **not** operate a publisher-controlled backend service for collecting user account information.

The publisher does not use the information accessed by the application for advertising, profiling, analytics, or sale.

## Information transmitted to third parties

To provide its core functionality, Codex Usage Win sends authentication information required by the Codex/ChatGPT service directly to that service over HTTPS. The application may also contact GitHub over HTTPS to check for application updates and to open the project's Releases page at the user's request.

These services may process network information such as the user's IP address according to their own terms and privacy policies.

Codex Usage Win does not transmit Codex credentials or Codex usage data to Walle Studio.

## Storage and security

Codex authentication credentials remain in the credential file managed by Codex. Codex Usage Win reads them when required and does not create a separate copy of the access token for publisher collection.

Application settings are stored locally on the user's device. Diagnostic logs, when explicitly enabled, are also stored locally.

Network requests used for Codex usage checks and update checks use HTTPS.

## Analytics, advertising, and tracking

Codex Usage Win does not include publisher-operated analytics, advertising SDKs, behavioral tracking, or telemetry collection.

## User control and deletion

Users can stop Codex Usage Win from accessing Codex information by exiting or uninstalling the application.

Users control their Codex credentials through the Codex service and Codex tooling. Uninstalling Codex Usage Win does not delete Codex credentials because those credentials are owned and managed by Codex rather than by this application.

Local Codex Usage Win settings and diagnostic files can be deleted from the user's device at any time.

## Children

Codex Usage Win is not specifically directed to children and does not knowingly collect personal information from children.

## Changes to this policy

This privacy policy may be updated when the application's functionality or data practices change. The current version will remain available in this repository.

## Contact and support

Project repository: https://github.com/walle-2017/codex-usage-monitor

Support and issue reporting: https://github.com/walle-2017/codex-usage-monitor/issues

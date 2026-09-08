$ErrorActionPreference = 'Stop'

$appearance = Get-Content -Raw (Join-Path $PSScriptRoot '..\src\appearance.rs')
$window = Get-Content -Raw (Join-Path $PSScriptRoot '..\src\window.rs')

$taskbarValue = [regex]::Match(
    $appearance,
    '(?s)pub\s+fn\s+taskbar_value_text\s*\(.*?\)\s*->\s*TaskbarValueText\s*\{(?<body>.*?)\n\}'
)
if (-not $taskbarValue.Success) {
    throw 'Unable to locate taskbar_value_text().'
}
if ($taskbarValue.Groups['body'].Value -match 'LanguageId::SimplifiedChinese') {
    throw 'Taskbar percentage meaning must not depend on UI language.'
}
if ($taskbarValue.Groups['body'].Value -notmatch 'remaining_percentage\(section\.percentage\)') {
    throw 'Taskbar percentage must always use remaining quota.'
}

$displayPercent = [regex]::Match(
    $window,
    '(?s)fn\s+usage_percent_for_display\s*\(.*?\)\s*->\s*f64\s*\{(?<body>.*?)\n\}'
)
if (-not $displayPercent.Success) {
    throw 'Unable to locate usage_percent_for_display().'
}
if ($displayPercent.Groups['body'].Value -match 'LanguageId::SimplifiedChinese') {
    throw 'Progress percentage must not depend on UI language.'
}
if ($displayPercent.Groups['body'].Value -notmatch 'remaining_percentage\(used_percentage\)') {
    throw 'Progress percentage must always convert used quota to remaining quota.'
}

$barColor = [regex]::Match(
    $window,
    '(?s)fn\s+quota_bar_color\s*\(.*?\)\s*->\s*Color\s*\{(?<body>.*?)\n\}'
)
if (-not $barColor.Success) {
    throw 'Unable to locate quota_bar_color().'
}
if ($barColor.Groups['body'].Value -match 'LanguageId::SimplifiedChinese') {
    throw 'Quota color thresholds must not depend on UI language.'
}

Write-Host 'PASS: all UI languages use the same remaining-quota semantics.'

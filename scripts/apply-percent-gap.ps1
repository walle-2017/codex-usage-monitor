$ErrorActionPreference = 'Stop'

$path = Join-Path $PSScriptRoot '..\src\window.rs'
$source = Get-Content -Raw $path

$replacements = @(
    @{
        Old = "    let model_width = (sc(SEGMENT_W) + sc(SEGMENT_GAP)) * bar_segments - sc(SEGMENT_GAP)`r`n        + sc(metrics.bar_value_width)"
        New = "    let model_width = (sc(SEGMENT_W) + sc(SEGMENT_GAP)) * bar_segments - sc(SEGMENT_GAP)`r`n        + sc(metrics.bar_value_gap)`r`n        + sc(metrics.bar_value_width)"
    },
    @{
        Old = "    (sc(SEGMENT_W) + sc(SEGMENT_GAP)) * segment_count - sc(SEGMENT_GAP)`r`n        + sc(preset.metrics().bar_value_width)"
        New = "    (sc(SEGMENT_W) + sc(SEGMENT_GAP)) * segment_count - sc(SEGMENT_GAP)`r`n        + sc(preset.metrics().bar_value_gap)`r`n        + sc(preset.metrics().bar_value_width)"
    },
    @{
        Old = '        let text_x = bar_x + progress_width;'
        New = '        let text_x = bar_x + progress_width + sc(metrics.bar_value_gap);'
    }
)

foreach ($replacement in $replacements) {
    if (-not $source.Contains($replacement.Old)) {
        throw "Expected window.rs pattern was not found: $($replacement.Old)"
    }
    $source = $source.Replace($replacement.Old, $replacement.New)
}

Set-Content -Path $path -Value $source -Encoding utf8NoBOM -NoNewline

git diff --check

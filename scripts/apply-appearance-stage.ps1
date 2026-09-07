# Temporary branch-only patch helper; removed before merge.
$ErrorActionPreference = 'Stop'
$path = 'src/window.rs'
$text = Get-Content -Raw -Path $path

$badPaint = 'let preset = current_appearance_preset();`n        let (label_width, text_width) = usage_layout_widths(language, preset);'
$goodPaint = @'
let preset = current_appearance_preset();
        let (label_width, text_width) = usage_layout_widths(language, preset);
'@.TrimEnd()
$text = $text.Replace($badPaint, $goodPaint)

$badRow = 'let preset = current_appearance_preset();`n    let segment_count = row_bar_segment_count(active_models, preset);'
$goodRow = @'
let preset = current_appearance_preset();
    let segment_count = row_bar_segment_count(active_models, preset);
'@.TrimEnd()
$text = $text.Replace($badRow, $goodRow)

$text = $text.Replace(
    'let content_x = sc(LEFT_DIVIDER_W) + sc(DIVIDER_RIGHT_MARGIN);',
    'let content_x = sc(LEFT_DIVIDER_W) + sc(preset.metrics().divider_right_margin);'
)
$text = $text.Replace(
    '            sc(-12),',
    '            sc(preset.metrics().font_height),'
)

if ($text.Contains('current_appearance_preset();`n')) {
    throw 'Literal PowerShell newline escape remains in Rust source.'
}

Set-Content -Path $path -Value $text -Encoding utf8NoBOM
Write-Host 'Aligned preset renderer metrics and fixed generated newlines.'

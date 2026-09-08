$ErrorActionPreference = 'Stop'

$windowPath = Join-Path $PSScriptRoot '..\src\window.rs'
$window = Get-Content -Raw $windowPath

if ($window -notmatch 'fn is_small_taskbar_height_at_dpi\(') {
    $old = @'
fn is_small_taskbar_height(taskbar_height: i32) -> bool {
    taskbar_height <= sc(SMALL_TASKBAR_THRESHOLD)
}
'@
    $new = @'
fn is_small_taskbar_height_at_dpi(taskbar_height: i32, dpi: u32) -> bool {
    let threshold = (SMALL_TASKBAR_THRESHOLD as f64 * dpi as f64 / 96.0).round() as i32;
    taskbar_height <= threshold
}

fn is_small_taskbar_height(taskbar_height: i32) -> bool {
    is_small_taskbar_height_at_dpi(taskbar_height, CURRENT_DPI.load(Ordering::Relaxed))
}
'@
    if (-not $window.Contains($old)) { throw 'small-taskbar helper target missing' }
    $window = $window.Replace($old, $new)
}

$oldHit = @'
fn is_drag_handle_point(client_x: i32, client_y: i32) -> bool {
    let hit_h = sc(DRAG_HANDLE_HIT_H);
    let hit_top = (sc(current_appearance_preset().metrics().widget_height) - hit_h) / 2;
    client_x >= 0
        && client_x < sc(DRAG_HANDLE_HIT_W)
        && client_y >= hit_top
        && client_y < hit_top + hit_h
}
'@
$newHit = @'
fn is_drag_handle_point(client_x: i32, client_y: i32) -> bool {
    let hit_h = sc(DRAG_HANDLE_HIT_H);
    let widget_height = {
        let state = lock_state();
        state
            .as_ref()
            .map(widget_height_for_state)
            .unwrap_or(sc(current_appearance_preset().metrics().widget_height))
    };
    let hit_top = (widget_height - hit_h).max(0) / 2;
    client_x >= 0
        && client_x < sc(DRAG_HANDLE_HIT_W)
        && client_y >= hit_top
        && client_y < (hit_top + hit_h).min(widget_height)
}
'@
if ($window.Contains($oldHit)) {
    $window = $window.Replace($oldHit, $newHit)
}

$testPattern = '(?s)    #\[test\]\r?\n    fn small_taskbar_threshold_is_dpi_aware_at_96_dpi\(\) \{.*?\r?\n    \}\r?\n'
$testReplacement = @'
    #[test]
    fn small_taskbar_threshold_is_dpi_aware() {
        assert!(is_small_taskbar_height_at_dpi(32, 96));
        assert!(is_small_taskbar_height_at_dpi(34, 96));
        assert!(!is_small_taskbar_height_at_dpi(35, 96));
        assert!(is_small_taskbar_height_at_dpi(51, 144));
        assert!(!is_small_taskbar_height_at_dpi(52, 144));
    }

'@
$updated = [regex]::Replace($window, $testPattern, $testReplacement, 1)
if ($updated -eq $window -and $window -notmatch 'fn small_taskbar_threshold_is_dpi_aware\(') {
    throw 'small-taskbar unit test target missing'
}
$window = $updated

Set-Content -Path $windowPath -Value $window -Encoding utf8NoBOM -NoNewline
git diff --check

$ErrorActionPreference = 'Stop'

$path = 'src/window.rs'
$source = Get-Content -Raw -LiteralPath $path

$replacement = @'
        WM_MOUSEMOVE => {
            let is_dragging = {
                let state = lock_state();
                state.as_ref().map(|s| s.dragging).unwrap_or(false)
            };
            if is_dragging {
                let mut pt = POINT::default();
                let _ = GetCursorPos(&mut pt);

                // Detect cross-taskbar movement while the button is still held.
                // Reparent immediately so the widget keeps following the cursor
                // instead of stopping at the current taskbar edge until button-up.
                let drag_target = {
                    let state = lock_state();
                    state
                        .as_ref()
                        .map(|s| (s.taskbar_index, s.drag_start_client_x))
                };
                let mut switched_taskbar = false;
                if let Some((current_taskbar_index, drag_start_client_x)) = drag_target {
                    if let Some((target_index, target_taskbar)) = taskbar_at_point(pt) {
                        if target_index != current_taskbar_index {
                            let new_offset = offset_for_drop_point(
                                target_taskbar.hwnd,
                                target_taskbar.rect,
                                pt,
                                drag_start_client_x,
                            );
                            {
                                let mut state = lock_state();
                                if let Some(s) = state.as_mut() {
                                    s.tray_offset = new_offset;
                                }
                            }

                            if attach_to_taskbar(hwnd, target_index) {
                                // SetParent can disturb capture/drag state. Restore
                                // both after reparenting and reset the horizontal
                                // drag origin to the new taskbar so movement stays
                                // continuous in either direction (A -> B -> A).
                                {
                                    let mut state = lock_state();
                                    if let Some(s) = state.as_mut() {
                                        s.dragging = true;
                                        s.drag_start_mouse_x = pt.x;
                                        s.drag_start_offset = new_offset;
                                    }
                                }
                                SetCapture(hwnd);
                                switched_taskbar = true;
                            }
                        }
                    }
                }

                let move_target = {
                    let mut state = lock_state();
                    let s = match state.as_mut() {
                        Some(s) => s,
                        None => return LRESULT(0),
                    };

                    // Moving mouse left = positive delta = larger offset (further left)
                    let delta = s.drag_start_mouse_x - pt.x;
                    let mut new_offset = s.drag_start_offset + delta;

                    // Clamp: offset >= 0 (can't go right of default)
                    if new_offset < 0 {
                        new_offset = 0;
                    }

                    let taskbar_hwnd = s.taskbar_hwnd;
                    let embedded = s.embedded;
                    let hwnd_val = s.hwnd.to_hwnd();

                    // Clamp: don't go past left edge of taskbar
                    if let Some(taskbar_hwnd) = taskbar_hwnd {
                        if let Some(taskbar_rect) = native_interop::get_taskbar_rect(taskbar_hwnd) {
                            let mut tray_left = taskbar_rect.right;
                            if let Some(tray_hwnd) =
                                native_interop::find_child_window(taskbar_hwnd, "TrayNotifyWnd")
                            {
                                if let Some(tray_rect) =
                                    native_interop::get_window_rect_safe(tray_hwnd)
                                {
                                    tray_left = tray_rect.left;
                                }
                            }
                            let widget_width = total_widget_width_for_state(s);
                            let max_offset = (tray_left - taskbar_rect.left - widget_width).max(0);
                            if new_offset > max_offset {
                                new_offset = max_offset;
                            }

                            s.tray_offset = new_offset;

                            let taskbar_height = taskbar_rect.bottom - taskbar_rect.top;
                            let anchor_top = taskbar_rect.top;
                            let anchor_height = taskbar_height;
                            let widget_height = widget_height_for_state(s);
                            let y = compute_anchor_y(anchor_top, anchor_height, widget_height);
                            let x = if embedded {
                                tray_left - taskbar_rect.left - widget_width - new_offset
                            } else {
                                tray_left - widget_width - new_offset
                            };
                            Some((
                                hwnd_val,
                                embedded,
                                x,
                                y,
                                taskbar_rect.top,
                                widget_width,
                                widget_height,
                            ))
                        } else {
                            s.tray_offset = new_offset;
                            None
                        }
                    } else {
                        s.tray_offset = new_offset;
                        None
                    }
                };

                if let Some((hwnd_val, embedded, x, y, taskbar_top, widget_width, widget_height)) =
                    move_target
                {
                    if embedded {
                        native_interop::move_window(
                            hwnd_val,
                            x,
                            y - taskbar_top,
                            widget_width,
                            widget_height,
                        );
                    } else {
                        native_interop::move_window(hwnd_val, x, y, widget_width, widget_height);
                    }
                }
                if switched_taskbar {
                    render_layered();
                }
            }
            LRESULT(0)
        }
'@

$pattern = '(?s)        WM_MOUSEMOVE\s*=>\s*\{.*?\n        WM_CANCELMODE\s*=>'
$match = [regex]::Match($source, $pattern)
if (-not $match.Success) {
    throw 'Unable to locate WM_MOUSEMOVE handler for replacement.'
}

$updated = [regex]::Replace(
    $source,
    $pattern,
    $replacement + "        WM_CANCELMODE =>",
    1
)
if ($updated -eq $source) {
    throw 'WM_MOUSEMOVE handler was not changed.'
}

Set-Content -LiteralPath $path -Value $updated -Encoding utf8

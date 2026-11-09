#!/usr/bin/env bash
set -euo pipefail

# NocturnalZone Xcodeテーマのプレビュー画像（assets/screenshot.png）を再生成する。
# テーマをXcodeのテーマディレクトリへ入れてから、サンプルSwiftを開いて1200x800で撮影する。

usage() {
    cat <<'USAGE'
Regenerate assets/screenshot.png (1200x800) from an Xcode window showing the sample file.

Usage:
  scripts/screenshot.sh [options]

Options:
  -o, --output-dir DIR  Output directory for screenshot.png. Default: assets/
  -h, --help            Show this help and exit.

Environment:
  XCODE_APP   Xcode application path. Default: /Applications/Xcode.app

Notes:
  - The script installs NocturnalZone.xccolortheme into
    ~/Library/Developer/Xcode/UserData/FontAndColorThemes and sets
    XCFontAndColorCurrentTheme for com.apple.dt.Xcode (the same steps as the
    documented manual install).
  - That theme preference only takes effect when Xcode is closed. If Xcode is
    already running, select NocturnalZone in Settings > Themes and run again.
  - Window geometry comes from the Accessibility API, so the terminal must be
    allowed to control the computer (System Settings > Privacy & Security >
    Accessibility).
USAGE
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

display_path() {
    local path="$1"
    case "$path" in
    "$repo_root"/*) printf '%s\n' "${path#"$repo_root"/}" ;;
    *) printf '%s\n' "$path" ;;
    esac
}

# 撮影するウィンドウのサイズと位置。
window_width=1200
window_height=800
window_x=60
window_y=60

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd "$script_dir/.." && pwd -P)"
lib_dir="$script_dir/lib"

output_dir="$repo_root/assets"
xcode_app="${XCODE_APP:-/Applications/Xcode.app}"
theme_name="NocturnalZone"
theme_src="$repo_root/$theme_name.xccolortheme"
theme_dir="$HOME/Library/Developer/Xcode/UserData/FontAndColorThemes"
sample_name="NocturnalZoneSample.swift"
# 列揃えの見た目が撮影対象のため、整形対象外の拡張子で保存し、撮影時に.swiftとして複製する。
sample_src="$lib_dir/$sample_name.sample"

while [ "$#" -gt 0 ]; do
    case "$1" in
    -o | --output-dir)
        [ "$#" -ge 2 ] || die "$1 requires a directory"
        output_dir="$2"
        shift 2
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        usage >&2
        die "unknown argument: $1"
        ;;
    esac
done

[ -d "$xcode_app" ] || die "Xcode not found: $xcode_app (set XCODE_APP to override)"
command -v osascript >/dev/null 2>&1 || die "osascript not found"
[ -x /usr/sbin/screencapture ] || die "screencapture not found"
[ -f "$theme_src" ] || die "missing $theme_src"
[ -f "$sample_src" ] || die "missing $sample_src"
[ -f "$lib_dir/activate-app.applescript" ] || die "missing $lib_dir/activate-app.applescript"
[ -f "$lib_dir/window-frame.applescript" ] || die "missing $lib_dir/window-frame.applescript"
[ -f "$lib_dir/xcode-close-documents.applescript" ] || die "missing $lib_dir/xcode-close-documents.applescript"

tmp_dir=""
sample_file=""

cleanup() {
    local status=$?
    # 開いたサンプルだけを閉じる。利用者の他のドキュメントは閉じない。
    if [ -n "$sample_file" ]; then
        osascript "$lib_dir/xcode-close-documents.applescript" "$sample_file" >/dev/null 2>&1 || # guardrail-allow: language-delegation
            printf 'warning: could not close %s in Xcode\n' "$sample_file" >&2
    fi
    if [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ]; then
        if [ -x /usr/bin/trash ]; then
            /usr/bin/trash "$tmp_dir" >/dev/null 2>&1 ||
                printf 'warning: could not move %s to Trash\n' "$tmp_dir" >&2
        else
            printf 'warning: /usr/bin/trash not found; leaving %s\n' "$tmp_dir" >&2
        fi
    fi
    return "$status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# テーマをXcodeのテーマディレクトリへ入れる。後片付けはしない（再インストールは手動cpで行える）。
mkdir -p "$theme_dir"
cp "$theme_src" "$theme_dir/$theme_name.xccolortheme"

# Xcodeが起動中の場合、この設定は次回起動時に反映される。
defaults write com.apple.dt.Xcode XCFontAndColorCurrentTheme "$theme_name"

tmp_dir="$(mktemp -d)"
# Xcodeが返すdocumentのpathと照合できるよう、symlinkを解決した実pathにする。
tmp_dir="$(cd "$tmp_dir" && pwd -P)"
shot="$tmp_dir/screenshot.png"
sample_file="$tmp_dir/$sample_name"
cp "$sample_src" "$sample_file"

# -aは複数バージョン共存時に失敗するため、アプリのpathを直接開く。
open "$xcode_app" "$sample_file"

# Xcodeがファイルを開いて描画するまでのGUI待ち。到達確認できる状態がないため固定時間だけ待つ。
sleep 5

osascript "$lib_dir/activate-app.applescript" "Xcode" 1 >/dev/null # guardrail-allow: language-delegation

# 利用者の作業中ウィンドウを動かさないよう、サンプル名をタイトルに含むウィンドウだけを対象にする。
osascript "$lib_dir/window-frame.applescript" "Xcode" "$sample_name" set "$window_width" "$window_height" "$window_x" "$window_y" >/dev/null # guardrail-allow: language-delegation

# リサイズ結果が画面へ反映されるまで待つ。
sleep 1

rect="$(osascript "$lib_dir/window-frame.applescript" "Xcode" "$sample_name" get)" # guardrail-allow: language-delegation
case "$rect" in
[0-9]*,[0-9]*,[0-9]*,[0-9]*) ;;
*) die "could not read Xcode window rect: '$rect'" ;;
esac

screencapture -R "$rect" "$shot"
[ -s "$shot" ] || die "screencapture did not write $shot"

mkdir -p "$output_dir"
cp "$shot" "$output_dir/screenshot.png"

printf 'wrote %s (window rect %s)\n' "$(display_path "$output_dir/screenshot.png")" "$rect"

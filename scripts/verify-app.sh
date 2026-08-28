#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
app_dir="${1:-${project_dir}/dist/Sub2API Monitor.app}"
contents_dir="${app_dir}/Contents"
info_plist="${contents_dir}/Info.plist"

fail() {
  print -u2 -- "Bundle verification failed: $1"
  exit 1
}

[[ -d "${app_dir}" ]] || fail "app bundle not found at ${app_dir}"
[[ -f "${info_plist}" ]] || fail "Info.plist is missing"
[[ -x "${contents_dir}/MacOS/Sub2APIConsole" ]] || fail "executable is missing"
[[ -f "${contents_dir}/Resources/AppIcon.icns" ]] || fail "app icon is missing"

lsui_element="$(plutil -extract LSUIElement raw "${info_plist}" 2>/dev/null)" ||
  fail "LSUIElement is missing"
[[ "${lsui_element}" == "true" ]] || fail "LSUIElement must be true"

allows_http="$({
  plutil -extract NSAppTransportSecurity.NSAllowsArbitraryLoads raw "${info_plist}" 2>/dev/null
} || true)"
[[ "${allows_http}" == "true" ]] ||
  fail "NSAllowsArbitraryLoads must be true for explicitly enabled HTTP servers"

codesign --verify --deep --strict "${app_dir}" || fail "code signature is invalid"

echo "Verified ${app_dir}"

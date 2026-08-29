#!/bin/zsh

set -euo pipefail

account_list_project_dir="${0:A:h:h}"
account_list_view_file="${account_list_project_dir}/Sources/Sub2APIConsole/MenuBarView.swift"

matches() {
  local pattern="$1"
  if (( $+commands[rg] )); then
    rg -q -- "${pattern}" "${account_list_view_file}"
  else
    grep -Eq -- "${pattern}" "${account_list_view_file}"
  fi
}

if ! matches 'private func adminAccountList\(' \
  || ! matches 'VStack\(spacing: 0\)' \
  || ! matches 'switch adminListTab' \
  || ! matches '\.id\(adminListTab\)' \
  || ! matches 'private enum MenuBarPanelLayout' \
  || ! matches 'static let width: CGFloat = 390' \
  || ! matches 'static let height: CGFloat = 690' \
  || ! matches 'width: MenuBarPanelLayout\.width' \
  || ! matches 'height: MenuBarPanelLayout\.height' \
  || ! matches '\.frame\(maxHeight: \.infinity' \
  || matches 'menuWindowSizeCoordinator' \
  || matches 'private final class MenuBarWindowSizeCoordinator' \
  || matches 'private struct MenuBarWindowSizeReader' \
  || matches 'private struct MenuBarContentSizePreferenceKey' \
  || matches 'window\.setContentSize\(' \
  || matches 'window\.setFrame\('; then
  print -u2 "Admin list layout regression: the menu-bar window must stay fixed while list content scrolls internally."
  exit 1
fi

print "Admin list layout regression check passed."

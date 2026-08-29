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
  || ! matches '\.frame\(height: accountListViewportHeight\(for: accounts\.count\)\)' \
  || ! matches 'VStack\(spacing: 0\)' \
  || ! matches 'switch adminListTab' \
  || ! matches '\.id\(adminListTab\)'; then
  print -u2 "Admin list layout regression: populated rows must use a non-zero viewport and keyed content when switching lists."
  exit 1
fi

print "Admin list layout regression check passed."

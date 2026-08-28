#!/bin/zsh

set -euo pipefail

account_list_project_dir="${0:A:h:h}"
account_list_view_file="${account_list_project_dir}/Sources/Sub2APIConsole/MenuBarView.swift"

if ! rg -q 'private func adminAccountList\(' "${account_list_view_file}" \
  || ! rg -q '\.frame\(height: accountListViewportHeight\(for: accounts\.count\)\)' "${account_list_view_file}" \
  || ! rg -q 'VStack\(spacing: 0\)' "${account_list_view_file}"; then
  print -u2 "Account list layout regression: populated rows must use a non-zero viewport and a regular VStack."
  exit 1
fi

print "Account list layout regression check passed."

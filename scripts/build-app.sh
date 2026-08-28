#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
configuration="${1:-release}"
app_dir="${project_dir}/dist/Sub2API Monitor.app"
contents_dir="${app_dir}/Contents"
macos_dir="${contents_dir}/MacOS"
resources_dir="${contents_dir}/Resources"

cd "${project_dir}"
swift build -c "${configuration}"
binary_dir="$(swift build -c "${configuration}" --show-bin-path)"

rm -rf "${app_dir}"
mkdir -p "${macos_dir}" "${resources_dir}"
cp "${binary_dir}/Sub2APIConsole" "${macos_dir}/Sub2APIConsole"
cp "${project_dir}/Resources/Info.plist" "${contents_dir}/Info.plist"
cp "${project_dir}/Resources/AppIcon.icns" "${resources_dir}/AppIcon.icns"

codesign --force --deep --sign - "${app_dir}"
"${script_dir}/verify-app.sh" "${app_dir}"
echo "Built ${app_dir}"

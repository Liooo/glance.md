#!/bin/zsh
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "${repo_dir}"

script_name="$0"
configuration="release"
version="${GLANCE_MD_VERSION:-0.1.0}"
build_number="${GLANCE_MD_BUILD:-1}"
output_dir=".build/apps"
make_zip=false
zip_path=""

usage() {
  echo "Usage: ${script_name} [--debug | --release] [--version VERSION] [--build BUILD] [--output-dir DIR] [--zip [ZIP_PATH]]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)
      configuration="debug"
      shift
      ;;
    --release)
      configuration="release"
      shift
      ;;
    --version)
      version="${2:?missing version}"
      shift 2
      ;;
    --build)
      build_number="${2:?missing build number}"
      shift 2
      ;;
    --output-dir)
      output_dir="${2:?missing output dir}"
      shift 2
      ;;
    --zip)
      make_zip=true
      if [[ $# -gt 1 && "${2}" != --* ]]; then
        zip_path="$2"
        shift 2
      else
        shift
      fi
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "${configuration}" == "release" ]]; then
  swift build -c release
  swiftpm_dir=".build/release"
else
  swift build
  swiftpm_dir=".build/debug"
fi

app_path="${output_dir}/GlanceMD.app"
resource_bundle="${swiftpm_dir}/glance-md_GlanceMDApp.bundle"

if [[ ! -x "${swiftpm_dir}/glance-md" ]]; then
  echo "Executable not found: ${swiftpm_dir}/glance-md" >&2
  exit 1
fi
if [[ ! -d "${resource_bundle}" ]]; then
  echo "Resource bundle not found: ${resource_bundle}" >&2
  exit 1
fi

rm -rf "${app_path}"
mkdir -p "${app_path}/Contents/MacOS" "${app_path}/Contents/Resources"

cp "${swiftpm_dir}/glance-md" "${app_path}/Contents/MacOS/"
cp -R "${resource_bundle}" "${app_path}/Contents/Resources/"
cp "Sources/GlanceMDApp/Resources/AppIcon.icns" "${app_path}/Contents/Resources/AppIcon.icns"

sed \
  -e "s/__VERSION__/${version}/g" \
  -e "s/__BUILD__/${build_number}/g" \
  "build/Info.plist" > "${app_path}/Contents/Info.plist"

codesign --force --deep --sign - "${app_path}" >/dev/null
codesign --verify --deep --strict --verbose=2 "${app_path}" >/dev/null

echo "Built ${app_path}"

if $make_zip; then
  if [[ -z "${zip_path}" ]]; then
    zip_path="/tmp/GlanceMD-${version}.zip"
  fi
  rm -f "${zip_path}"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "${app_path}" "${zip_path}"
  sha256="$(shasum -a 256 "${zip_path}" | awk '{print $1}')"
  echo "Zip: ${zip_path}"
  echo "SHA256: ${sha256}"
fi

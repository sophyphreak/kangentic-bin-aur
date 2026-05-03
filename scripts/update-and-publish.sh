#!/usr/bin/env bash
set -euo pipefail

pkgbase="kangentic-bin"
upstream_repo="Kangentic/kangentic"
aur_remote="ssh://aur@aur.archlinux.org/${pkgbase}.git"
result_file="${GITHUB_WORKSPACE:-$(pwd)}/sync-result.env"
run_started_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

write_result() {
  cat > "$result_file" <<EOF
status=$1
updated=$2
current_version=$3
latest_version=$4
asset=$5
sha256=$6
github_commit=$7
aur_commit=$8
run_started_utc=$run_started_utc
run_completed_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
}

latest_tag="$(curl -fsSL "https://api.github.com/repos/${upstream_repo}/releases/latest" | jq -r '.tag_name')"
if [[ -z "$latest_tag" || "$latest_tag" == "null" ]]; then
  echo "Could not determine latest Kangentic release tag." >&2
  exit 1
fi

latest_version="${latest_tag#v}"
current_version="$(awk -F= '/^pkgver=/{print $2; exit}' PKGBUILD)"

if [[ "$latest_version" == "$current_version" ]]; then
  echo "${pkgbase} is already current at ${current_version}."
  write_result "already_current" "false" "$current_version" "$latest_version" "" "" "" ""
  exit 0
fi

asset="kangentic_${latest_version}_amd64.deb"
asset_url="https://github.com/${upstream_repo}/releases/download/v${latest_version}/${asset}"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo "Updating ${pkgbase} from ${current_version} to ${latest_version}."
curl -fL "$asset_url" -o "${tmpdir}/${asset}"
sha256="$(sha256sum "${tmpdir}/${asset}" | awk '{print $1}')"

sed -i \
  -e "s/^pkgver=.*/pkgver=${latest_version}/" \
  -e "s/^pkgrel=.*/pkgrel=1/" \
  -e "s/^sha256sums=.*/sha256sums=('${sha256}')/" \
  -e "s/^noextract=.*/noextract=(\"${asset}\")/" \
  PKGBUILD

makepkg --printsrcinfo > .SRCINFO
makepkg --verifysource
rm -rf pkg src ./*.pkg.tar* ./*.deb

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add PKGBUILD .SRCINFO
git commit -m "Update to ${latest_version}"
github_commit="$(git rev-parse HEAD)"

aur_dir="${tmpdir}/aur"
git clone "$aur_remote" "$aur_dir"
cp PKGBUILD .SRCINFO "$aur_dir/"

git -C "$aur_dir" config user.name "github-actions[bot]"
git -C "$aur_dir" config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git -C "$aur_dir" add PKGBUILD .SRCINFO
git -C "$aur_dir" commit -m "Update to ${latest_version}"
aur_commit="$(git -C "$aur_dir" rev-parse HEAD)"
git -C "$aur_dir" push origin master

git push origin HEAD:main
write_result "updated" "true" "$current_version" "$latest_version" "$asset" "$sha256" "$github_commit" "$aur_commit"

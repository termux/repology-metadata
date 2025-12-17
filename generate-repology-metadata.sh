#!/usr/bin/env bash
#
#  Script for generating metadata for Repology in json format.
#
#  Copyright 2018 Fredrik Fornwall <fredrik@fornwall.net> @fornwall
#  Copyright 2022 Henrik Grimler <grimler@termux.org>
#  Copyright 2022 Yaksh Bariya <yakshbari4@gmail.com>
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#

set -e

TERMUX_PACKAGES_DIR=$(realpath $1)
export TERMUX_ARCH=aarch64
export TERMUX_ARCH_BITS=64
. $TERMUX_PACKAGES_DIR/scripts/properties.sh

pushd $TERMUX_PACKAGES_DIR > /dev/null
repo_url="$(git config --get remote.origin.url)"
popd > /dev/null

# Convert to normal https url if it starts with git@
if [ "${repo_url:0:4}" == "git@" ]; then
	repo_url="$(echo $repo_url|sed  -e 's%:%/%g' -e 's%git@%https://%g' )"
fi

# Remove ending '.git' from repo_url
if [ "${repo_url: -4}" = ".git" ]; then
	repo_url="${repo_url::-4}"
fi

github_regex="https://(www\.)?github.com/([a-zA-Z0-9-]*)/([a-zA-Z0-9-]*)"

if [[ ${repo_url} =~ ${github_regex} ]]; then
	repo_raw_url="https://raw.githubusercontent.com/${BASH_REMATCH[2]}/${BASH_REMATCH[3]}"
else
	echo "Error: repo regex didn't match ${repo_url}" > /dev/stderr
	exit 1
fi

exclude_pkgs=""

print_json_element() {
	entry="$1" # For example "name"
	value="$2" # For example "libandroid-support"
	print_comma="$3"  # boolean, determines whether or not to print trailing ","

	echo -n "    \"${entry}\": \"${value}\""
	print_trailing_comma "$print_comma"
}

print_json_element_special() {
	entry="$1" # for example "auto_updated"
	value="$2" # for example: true, false or null
	print_comma="$3"

	echo -n "    \"${entry}\": ${value}"
	print_trailing_comma "$print_comma"
}

print_json_array() {
	entry="$1"  # for example "depends"
	values="$2" # for example "libandroid-support libc++"
	print_comma="$3" # boolean, determines whether or not to print trailing ","

	echo -n "    \"${entry}\": ["
	if [ -z "$values" ]; then
		echo -n "]"
		print_trailing_comma "$print_comma"
		return
	else
		echo ""
	fi

	local first=true
	for element in $values; do
		if $first; then
			first=false
		else
			echo ","
		fi

		echo -n "      \"$element\""
	done
	echo ""
	echo -n "    ]"
	print_trailing_comma "$print_comma"
}

print_trailing_comma() {
	print_comma="$1" # boolean, determines whether or not to print trailing ","
	if $print_comma; then
		echo ","
	else
		echo ""
	fi
}

check_package() {
	# Avoid ending on errors such as $(which prog)
	# where prog is not installed.
	set +e

	local path=$1
	pushd $path > /dev/null
	local pkg=$(basename $path)

	TERMUX_PKG_MAINTAINER="Termux members @termux"
	TERMUX_PKG_API_LEVEL=24
	TERMUX_PKG_AUTO_UPDATE=false
	. build.sh

	echo "  {"
	print_json_element "name" "${TERMUX_PKG_REPOLOGY_METADATA_NAME:-${pkg}}"
	print_json_element "version" "${TERMUX_PKG_REPOLOGY_METADATA_VERSION:-${TERMUX_PKG_VERSION}}"
	print_json_element "description" "$TERMUX_PKG_DESCRIPTION"
	print_json_element "homepage" "$TERMUX_PKG_HOMEPAGE"

	# sed groups does (respectively):
        #   Remove (optional) versioning, as in TERMUX_PKG_DEPENDS="libfoo (>= 1.0)"
        #   Only print first option in case of "or", as in TERMUX_PKG_DEPENDS="openssh | dropbear"
        #   Replace comma with space
	print_json_array   "depends" "$(sed -e 's@([^)]*)@@g' -e 's@|[^,$]*@,@g' -e 's@,@\n@g' <<<$TERMUX_PKG_DEPENDS | \
		grep -Fvx "$exclude_pkgs" | xargs)"

	if [ "$TERMUX_PKG_SRCURL" != "" ]; then
		print_json_element "srcurl" "$TERMUX_PKG_SRCURL"
	fi
	print_json_element "maintainer" "$TERMUX_PKG_MAINTAINER"

	local _COMMIT=$(git log -n1 --format=%h .)
	local build_sh_full_name=$(git ls-files --full-name build.sh)

	print_json_element "package_sources_url" "${repo_url}/tree/${_COMMIT}/$(dirname ${build_sh_full_name})"
	print_json_element "package_recipe_url" "${repo_url}/blob/${_COMMIT}/${build_sh_full_name}"
	print_json_element "package_recipe_url_raw" "${repo_raw_url}/${_COMMIT}/${build_sh_full_name}"
	local patches=$(git ls-files --full-name "*.patch" "*.patch32" "*.patch64" "*.patch.beforehostbuild" "*.diff")
	print_json_array "package_patch_urls" "$(for p in $patches; do echo $repo_url/blob/${_COMMIT}/$p; done)"
	print_json_array "package_patch_raw_urls" "$(for p in $patches; do echo $repo_raw_url/${_COMMIT}/$p; done)"
	# last printed entry needs to have "false" as third argument to avoid trailing ","
	print_json_element_special "auto_updated" "$TERMUX_PKG_AUTO_UPDATE" false

	echo -n "  }"

	popd > /dev/null
}

if [ $# -eq 0 ]; then
	echo "Usage: generate-repology-metadata.sh [./path/to/termux-packages]"
	echo "Generate package metadata for Repology."
	exit 1
fi

echo "["
FIRST=yes
repo_paths=$(jq --raw-output 'del(.pkg_format) | keys | .[]' $TERMUX_PACKAGES_DIR/repo.json)

exclude_pkgs=$'\n'"$(env -C $TERMUX_PACKAGES_DIR grep -rlE '^TERMUX_PKG_GENERATE_REPOLOGY_METADATA=false$' ${repo_paths[@]} --include=build.sh | \
	sed -E 's@.*/([^/]+)/build\.sh@\1@')"$'\n'

for repo_path in ${repo_paths[@]}; do
	package_paths=($TERMUX_PACKAGES_DIR/$repo_path/*)
	for package_path in "${package_paths[@]}"; do
		[[ $'\n'"$exclude_pkgs"$'\n' == *$'\n'"${package_path#*/}"$'\n'* ]] && continue
		if [ "$FIRST" = "yes" ]; then
			FIRST=no
		else
			echo ","
		fi
		( check_package $package_path )
	done
	FIRST=no
done
echo ""
echo "]"

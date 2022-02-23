#!/usr/bin/env bash
#
#  Script for generating metadata for Repology in json format.
#
#  Copyright 2018 Fredrik Fornwall <fredrik@fornwall.net> @fornwall
#  Copyright 2022 Henrik Grimler <grimler@termux.org>
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

BASEDIR=$(dirname "$(realpath "$0")")
export TERMUX_ARCH=aarch64
export TERMUX_ARCH_BITS=64
. $(dirname "$(realpath "$0")")/properties.sh

print_json_element() {
	entry="$1" # For example "name"
	value="$2" # For example "libandroid-support"
	print_comma="$3"  # boolean, determines whether or not to print trailing ","

	echo -n "    \"${entry}\": \"${value}\""
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
	local pkg=$(basename $path)
	pushd $path > /dev/null
	repo_url="$(git config --get remote.origin.url)"
	# Convert to normal https url if it starts with git@
	if [ "${repo_url:0:4}" == "git@" ]; then
		repo_url="$(echo $repo_url|sed  -e 's%:%/%g' -e 's%git@%https://%g' )"
	fi

	github_regex="https://(www\.)?github.com/([a-zA-Z0-9-]*)/([a-zA-Z0-9-]*)"
	if [[ ${repo_url} =~ ${github_regex} ]]; then
		repo_raw_url="https://raw.githubusercontent.com/${BASH_REMATCH[2]}/${BASH_REMATCH[3]}"
	else
		echo "Error: repo regex didn't match ${repo_url}" > /dev/stderr
		exit 1
	fi

	TERMUX_PKG_MAINTAINER="Termux members @termux"
	TERMUX_PKG_API_LEVEL=24
	. build.sh

	echo "  {"
	print_json_element "name" "$pkg"
	print_json_element "version" "$TERMUX_PKG_VERSION"
	print_json_element "description" "$TERMUX_PKG_DESCRIPTION"
	print_json_element "homepage" "$TERMUX_PKG_HOMEPAGE"

	print_json_array   "depends" "${TERMUX_PKG_DEPENDS//,/ }"

	if [ "$TERMUX_PKG_SRCURL" != "" ]; then
		print_json_element "srcurl" "$TERMUX_PKG_SRCURL"
	fi
	print_json_element "maintainer" "$TERMUX_PKG_MAINTAINER"

	print_json_element "package_sources_url" "${repo_url}/tree/master/$(dirname $(git ls-files --full-name build.sh))"
	print_json_element "package_recipe_url" "${repo_url}/blob/master/$(git ls-files --full-name build.sh)"
	print_json_element "package_recipe_url_raw" "${repo_raw_url}/master/$(git ls-files --full-name build.sh)"
	local patches=$(git ls-files --full-name "*.patch" "*.patch32" "*.patch64" "*.patch.beforehostbuild" "*.diff")
	print_json_array "package_patch_urls" "$(for p in $patches; do echo $repo_url/blob/master/$p; done)"
	print_json_array "package_patch_raw_urls" "$(for p in $patches; do echo $repo_raw_url/master/$p; done)" false

	# last printed entry needs to have "false" as third argument to avoid trailing ","

	popd > /dev/null

	echo -n "  }"
}

if [ $# -eq 0 ]; then
	echo "Usage: generate-repology-metadata.sh [./path/to/pkg/dir] ..."
	echo "Generate package metadata for Repology."
	exit 1
fi

export FIRST=yes
echo "["
for path in "$@"; do
	if [ $FIRST = yes ]; then
		FIRST=no
	else
		echo -n ","
		echo ""
	fi

	# Run each package in separate process since we include their environment variables:
	( check_package $path )
done
echo ""
echo "]"

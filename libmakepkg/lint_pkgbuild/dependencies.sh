#!/bin/bash
#
#   dependencies.sh - Check package relation arrays for malformed entries
#
#   Copyright (c) 2026 VitaSDK contributors
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#

[[ -n "$LIBMAKEPKG_LINT_PKGBUILD_DEPENDENCIES_SH" ]] && return
LIBMAKEPKG_LINT_PKGBUILD_DEPENDENCIES_SH=1

LIBRARY=${LIBRARY:-'@libmakepkgdir@'}

source "$LIBRARY/util/message.sh"
source "$LIBRARY/util/pkgbuild.sh"


lint_pkgbuild_functions+=('lint_dependencies')


lint_dependency_entries() {
	local variable=$1 entry ret=0
	shift

	for entry in "$@"; do
		if [[ $entry == *[[:space:]]* ]]; then
			error "$(gettext "%s entries must name one package each: '%s'")" \
				"$variable" "$entry"
			ret=1
		fi
	done

	return $ret
}

lint_dependencies() {
	local dependency_variables=(depends makedepends checkdepends conflicts provides replaces)
	local package_variables=(depends conflicts provides replaces)
	local variable architecture package entries ret=0

	for variable in "${dependency_variables[@]}"; do
		if array_build entries "$variable"; then
			lint_dependency_entries "$variable" "${entries[@]}" || ret=1
		fi

		for architecture in "${arch[@]}"; do
			if array_build entries "${variable}_${architecture}"; then
				lint_dependency_entries "${variable}_${architecture}" \
					"${entries[@]}" || ret=1
			fi
		done
	done

	for package in "${pkgname[@]}"; do
		for variable in "${package_variables[@]}"; do
			if extract_function_variable "package_$package" "$variable" 1 entries; then
				lint_dependency_entries "$variable" "${entries[@]}" || ret=1
			fi

			for architecture in "${arch[@]}"; do
				if extract_function_variable "package_$package" \
					"${variable}_${architecture}" 1 entries; then
					lint_dependency_entries "${variable}_${architecture}" \
						"${entries[@]}" || ret=1
				fi
			done
		done
	done

	return $ret
}

#!/usr/bin/env bash

# Copyright (c) 2011-2014 Benjamin Fleischer
# All rights reserved.
#
# Redistribution  and  use  in  source  and  binary  forms,  with   or   without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above  copyright  notice,
#    this list of conditions and the following disclaimer in  the  documentation
#    and/or other materials provided with the distribution.
# 3. Neither the name of osxfuse nor the names of its contributors may  be  used
#    to endorse or promote products derived from this software without  specific
#    prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND  CONTRIBUTORS  "AS  IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING,  BUT  NOT  LIMITED  TO,  THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS  FOR  A  PARTICULAR  PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE  COPYRIGHT  OWNER  OR  CONTRIBUTORS  BE
# LIABLE  FOR  ANY  DIRECT,  INDIRECT,  INCIDENTAL,   SPECIAL,   EXEMPLARY,   OR
# CONSEQUENTIAL  DAMAGES  (INCLUDING,  BUT  NOT  LIMITED  TO,   PROCUREMENT   OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF  USE,  DATA,  OR  PROFITS;  OR  BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND  ON  ANY  THEORY  OF  LIABILITY,  WHETHER  IN
# CONTRACT, STRICT  LIABILITY,  OR  TORT  (INCLUDING  NEGLIGENCE  OR  OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN  IF  ADVISED  OF  THE
# POSSIBILITY OF SUCH DAMAGE.


declare -ra BT_TARGET_ACTIONS=("build" "clean" "install")
declare     BT_TARGET_SOURCE_DIRECTORY="${BT_SOURCE_DIRECTORY}/fuse"

declare     LIBRARY_PREFIX=""


function library_build
{
    function library_build_getopt_handler
    {
        case "${1}" in
            --prefix)
                LIBRARY_PREFIX="${2}"
                return 2
                ;;
        esac
    }

    bt_target_getopt -p build -s "prefix:" -h library_build_getopt_handler -- "${@}"
    unset library_build_getopt_handler

    bt_log_variable LIBRARY_PREFIX

    bt_log "Clean target"
    bt_target_invoke "${BT_TARGET_NAME}" clean
    bt_exit_on_error "Failed to clean target"

    bt_log "Build target for OS X ${BT_TARGET_OPTION_DEPLOYMENT_TARGET}"

    local source_directory="${BT_TARGET_BUILD_DIRECTORY}/Source"
    local debug_directory="${BT_TARGET_BUILD_DIRECTORY}/Debug"

    /bin/mkdir -p "${BT_TARGET_BUILD_DIRECTORY}" 1>&3 2>&4
    bt_exit_on_error "Failed to create build directory"

    /bin/mkdir -p "${BT_TARGET_BUILD_DIRECTORY}/Source" 1>&3 2>&4
    bt_exit_on_error "Failed to create source directory"

    /bin/mkdir -p "${debug_directory}" 1>&3 2>&4
    bt_exit_on_error "Failed to create debug directory"

    rsync -a --exclude=".git*" "${BT_TARGET_SOURCE_DIRECTORY}/" "${source_directory}" 1>&3 2>&4
    bt_exit_on_error "Failed to copy source to directory '${source_directory}'"

    pushd "${source_directory}" > /dev/null 2>&1
    bt_exit_on_error "Source directory '${source_directory}' does not exist"

    ./makeconf.sh 1>&3 2>&4
    bt_exit_on_error "Failed to make configuration"

    CFLAGS="-D_DARWIN_USE_64_BIT_INODE ${BT_TARGET_OPTION_BUILD_SETTINGS[@]/#/-D} -I${BT_SOURCE_DIRECTORY}/common" \
    LDFLAGS="-Wl,-framework,CoreFoundation" \
    bt_target_configure ${LIBRARY_PREFIX:+--prefix="${LIBRARY_PREFIX}"} \
                        --disable-dependency-tracking --disable-static --disable-example
    bt_exit_on_error "Failed to configure target"

    bt_target_make -- -j 4
    bt_exit_on_error "Failed to build target"

    local executable_path=""
    while IFS=$'\0' read -r -d $'\0' executable_path
    do
        local executable_name="`basename "${executable_path}"`"

        /usr/bin/xcrun dsymutil -o "${debug_directory}/${executable_name}.dSYM" "${executable_path}" 1>&3 2>&4
        bt_exit_on_error "Failed to link debug information: '${executable_path}'"

        bt_target_codesign "${executable_path}"
        bt_exit_on_error "Failed to sign executable: '${executable_path}'"
    done < <(/usr/bin/find lib -name lib*.dylib -type f -print0)

    popd > /dev/null 2>&1
}

function library_install
{
    local -a arguments=()
    bt_target_getopt -p make-install -o arguments -- "${@}"

    local target_directory="${arguments[0]}"
    if [[ ! -d "${target_directory}" ]]
    then
        bt_error "Target directory '${target_directory}' does not exist"
    fi

    bt_log "Install target"

    local source_directory="${BT_TARGET_BUILD_DIRECTORY}/Source"
    local debug_directory="${BT_TARGET_BUILD_DIRECTORY}/Debug"

    pushd "${source_directory}" > /dev/null 2>&1
    bt_exit_on_error "Source directory '${source_directory}' does not exist"

    bt_target_make -- install DESTDIR="${target_directory}"
    bt_exit_on_error "Failed to install target"

    popd > /dev/null 2>&1

    if [[ -n "${BT_TARGET_OPTION_DEBUG_DIRECTORY}" ]]
    then
        bt_target_install "${debug_directory}/" "${BT_TARGET_OPTION_DEBUG_DIRECTORY}"
        bt_exit_on_error "Failed to Install debug files"
    fi
}

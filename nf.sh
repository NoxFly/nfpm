#!/bin/bash

# Author : NoxFly
# Copyrights 2021-2024
#
#   \ |  __| _ \  \  |
#  .  |  _|  __/ |\/ |
# _|\_| _|  _|  _|  _|
#
# No modification allowed without author's consent
# If you want to contribute, have a question or a fix,
# please create a Pull Request on the Github Repository
# at https://raw.githubusercontent.com/NoxFly/nfpm/

# -----------------------------------------------------------
# ------------------------- HELPERS -------------------------
# -----------------------------------------------------------
# not prefixed
# description: utilities that are not linked to anything

date_now() {
    echo $(date +%s%3N)
}

get_formatted_duration() {
    local end_time=$(date +%s%3N)
    local duration=$((end_time - $1))
    local minutes=$((duration / 60000))
    local seconds=$(( (duration / 1000) % 60 ))
    local milliseconds=$((duration % 1000))
    echo "${minutes}m ${seconds}s ${milliseconds}ms"
}

log() {
    [ $VERBOSE -eq 1 ] && echo -e "$@"
}

log_error() {
    echo -e "${CLR_RED}$@${CLR_RESET}"
}

log_success() {
    echo -e "${CLR_GREEN}$@${CLR_RESET}"
}

warn() {
    echo -e "${CLR_ORANGE}$@${CLR_RESET}"
}

capitalize() {
    echo "$1" | sed -r 's/(^| )([a-z])/\U\2/g' | tr -d ' '
}

is_command_available() {
    command -v $1 &> /dev/null
}

set_project_path() {
    s=$([[ "$1" == */ ]] && echo "" || echo "/")
    PROJECT_PATH="$1$s"
    CONFIG_PATH="$PROJECT_PATH$CONFIG_FILE"
}

get_colored_mode() {
    local m="${X_SUBMODE^^}"
    local c

    case $m in
        "DEV") c="${CLR_BGREEN}";;
        "DEBUG") c="${CLR_BORANGE}";;
        "RELEASE") c="${CLR_BRED}";;
        *) c="${CLR_RESET}";;
    esac

    echo -e "${c}${m}${CLR_RESET}"
}

background_task() { # $1=the task to run
    "$@" &> $OUTPUT &

    local pid=$!
	local delay=0.1
	local spinstr='|/-\'

	tput civis  # Hide cursor

	while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
		local temp=${spinstr#?}
		printf " [%c]  " "$spinstr"
		local spinstr=$temp${spinstr%"$temp"}
		sleep $delay
		printf "\b\b\b\b\b\b"
	done
	printf "    \b\b\b\b"
	tput cnorm  # Show cursor

    wait $pid

    return $?
}

ask_for_installation() { # $1=required command, $2=optional message
    msg=$([ -z "$2" ] && echo "continue" || echo "$2")
    log_error "$1 is required to $msg."
    echo -e "\nDo you want to install it? (Y/n)"
    local answer
    read -r answer

    if [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]; then
        os_install $1
        return $?
    fi

    return 1
}

# -----------------------------------------------------------
# ------------------------- GUARDS --------------------------
# -----------------------------------------------------------
# prefix: ensure
# description: functions used to ensure the integrity of the project's configuration
#              before running a command that needs a project or configuration to exist.
#              Exit otherwise.

ensure_config_integrity() {
    ensure_valid_mode $P_MODE
    ensure_valid_language "$P_LANG"
    ensure_valid_language_version "$P_LANG" $P_LANG_VERSION
    ensure_valid_guard "$P_GUARD"
}

ensure_inside_project() {
    [ ! -z "$INSIDE_PROJECT" ] && return

    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Error: No configuration file found in the current directory."
        echo "Create a new project thanks the '$COMMAND_NAME new' command."
        exit 1
    fi

    INSIDE_PROJECT="1"

    internal_load_config
}

ensure_project_structure() {
    internal_load_config

    if [ ! -d "$P_SRC_DIR" ] || [ $P_MODE -eq 0 -a ! -d "$P_INC_DIR" ]; then
        log_error "There's no project's structure."
        echo "To create it, write '$COMMAND_NAME generate'"
        exit 1
    fi
}

ensure_valid_language() {
    if [[ ! "$1" =~ ^(c|cpp)$ ]]; then
        log_error "Invalid language. Please choose c or cpp."
        exit 1
    fi
}

ensure_valid_language_version() {
    if [ "$1" == "c" ]; then
        if [[ ! "$2" =~ ^(89|99|11|17|23)$ ]]; then
            log_error "Invalid C version. Supported versions are 89, 99, 11, 17, 23."
            exit 1
        fi
    else
        if [[ ! "$2" =~ ^(03|11|14|17|20|23)$ ]]; then
            log_error "Invalid C++ version. Supported versions are 03, 11, 14, 17, 20, 23."
            exit 1
        fi
    fi
}

ensure_valid_guard() {
    if [[ ! "$1" =~ ^(ifndef|pragma)$ ]]; then
        log_error "Invalid guard. Please choose ifndef or pragma."
        exit 1
    fi
}

ensure_valid_mode() {
    if [[ ! $1 =~ ^(0|1)$ ]]; then
        log_error "Invalid project mode. Supported modes are 0 and 1."
        exit 1
    fi
}


# -----------------------------------------------------------
# ------------------------- OS-LIKE -------------------------
# -----------------------------------------------------------
# prefix: os
# description: functions used by commands that use os-specific commands.
#              Tries to find the right command for the current OS and uses it.

os_admin_check() { # TODO : not compatible with Cygwin an Msys
    sudo -v &> /dev/null
    if [ $? -ne 0 ]; then
        log_error "You need to have administrator privileges to run this command."
        exit 1
    fi
}

# functions that is "sudo apt-get update &> $OUTPUT"
# but for each package manager that exist following the 
os_update() {
    local cmd

    case "${GLOBALS["PACKAGE_MANAGER"]}" in
        "apt"|"apt-get") cmd="sudo apt-get update";;
        "brew") cmd="brew update";;
        "cygwin") cmd="pacman -Sy";;
        "msys") cmd="pacman -Sy";;
        "dnf") cmd="sudo dnf check-update";;
        "zypper") cmd="sudo zypper refresh";;
        "pacman") cmd="sudo pacman -Sy";;
    esac

    os_admin_check
    background_task $cmd
    return $?
}

os_install() { # $@=packages
    os_admin_check
    background_task $APT_INSTALL "$@"
    return $?
}

os_uninstall() { # $@=packages
    os_admin_check
    background_task $APT_UNINSTALL "$@"
    return $?
}

# used to know if a command is installed
# returns 0 if the package is installed, 1 otherwise
# in contrast with `command -v $1`, this function is
# to check the existence of a command, not a package
os_find() { # $1=package
    local cmd

    case $DISTRO in
        "macOS") cmd="brew list $1";;
        "Cygwin") cmd="cygcheck -c $1";;
        "Msys") cmd="pacman -Q $1";;
        "Debian") cmd="dpkg -s $1";;
        "Red Hat") cmd="rpm -q $1";;
        "SUSE") cmd="rpm -q $1";;
        "Arch") cmd="pacman -Q $1";;
    esac

    $cmd &> /dev/null
    return $?
}

os_fetch_file_content() {
    if ! is_command_available "curl"; then
        log_error "curl is required to fetch the file content."
        exit 1
    fi
    # should be available or easily installed on all platforms
    curl -s $1
    return $?
}

# -----------------------------------------------------------
# ----------------------- INTERNALS -------------------------
# -----------------------------------------------------------
# prefix: internal
# description: internal functions used by the commands

internal_load_config() {
    [ ! -z "$CONFIG_LOADED" ] && return
    CONFIG_LOADED="1"
    ensure_inside_project

    P_NAME=$(internal_get_category_field_value "project" "name")
    P_DESC=$(internal_get_category_field_value "project" "description")
    P_VERSION=$(internal_get_category_field_value "project" "version")
    P_AUTHOR=$(internal_get_category_field_value "project" "author")
    P_HOMEPAGE_URL=$(internal_get_category_field_value "project" "url")
    P_LICENSE=$(internal_get_category_field_value "project" "license")

    P_MODE=$(internal_get_category_field_value "config" "mode")
    P_GUARD=$(internal_get_category_field_value "config" "guard")
    P_LANG=$(internal_get_category_field_value "config" "type")
    P_LANG_VERSION=$(internal_get_category_field_value "config" "${P_LANG}Version")
    P_SRC_DIR="${PROJECT_PATH}src"
    [[ $P_MODE -eq 0 ]] && P_INC_DIR="${PROJECT_PATH}include" || P_INC_DIR="$P_SRC_DIR"
    P_OUT_DIR="${PROJECT_PATH}bin"
    P_BUILD_DIR="${PROJECT_PATH}build"
    P_LIB_DIR="${PROJECT_PATH}libs"
    P_FLAGS=$(internal_get_category_field_value "config" "flags")

    ensure_config_integrity

    local ext_suffix=""
    [ "$P_LANG" == "cpp" ] && ext_suffix="pp"
    P_SRC_EXT="c$ext_suffix"
    P_HDR_EXT="h$ext_suffix"
}

internal_create_config_category() {
    local category_name=$1
    if ! grep -q " $category_name:" $CONFIG_PATH; then
        echo -e "$category_name:\n" >> $CONFIG_PATH
    fi
}

internal_set_category_field_value() { # $1=category, $2=field, $3=value
    if grep -q "^$1:" $CONFIG_PATH; then
        if grep -q "^  $2:" $CONFIG_PATH; then
            # Use a different delimiter (|) to avoid conflicts with special characters in 3
            sed -i "s|^  $2:.*|  $2: $3|" $CONFIG_PATH
        else
            # Append the new field to the end of the existing category
            awk -v cat="$1" -v field="$2" -v value="$3" '
            BEGIN { in_category = 0 }
            /^[[:space:]]*#/ { next }
            {
                if ($0 ~ "^" cat ":") {
                    in_category = 1
                } else if (in_category && $0 !~ "^  ") {
                    print "  " field ": " value
                    in_category = 0
                }
                print $0
            }
            END {
                if (in_category) {
                    print "  " field ": " value
                }
            }
            ' "$CONFIG_PATH" > "$CONFIG_PATH.tmp" && mv "$CONFIG_PATH.tmp" "$CONFIG_PATH"
        fi
    else
        # Create the category and add the field
        awk -v cat="$1" -v field="$2" -v value="$3" '
        BEGIN { category_added = 0 }
        /^[[:space:]]*#/ { next }
        {
            if (!category_added && $0 !~ "^" cat ":") {
                print cat ":"
                print "  " field ": " value
                print ""
                category_added = 1
            }
            print $0
        }
        END {
            if (!category_added) {
                print cat ":"
                print "  " field ": " value
                print ""
            }
        }
        ' "$CONFIG_PATH" > "$CONFIG_PATH.tmp" && mv "$CONFIG_PATH.tmp" "$CONFIG_PATH"
    fi
}

internal_get_category_field_value() { # $1=category, $2=field
    awk -v cat="$1" -v field="$2" '
    BEGIN { in_category = 0 }
    /^[[:space:]]*#/ { next }
    {
        if ($0 ~ "^" cat ":") {
            in_category = 1
        } else if (in_category && $0 ~ "^[^ ]") {
            in_category = 0
        }
        if (in_category && $0 ~ "^  " field ":") {
            split($0, arr, ": ")
            print arr[2]
            exit
        }
    }
    ' "$CONFIG_PATH"
}

internal_create_project_config() { # $1=name, $2=mode, $3=language, $4=language version, $5=guard
    # create file first
    touch $CONFIG_PATH

    flags=$(internal_get_lang_flags "$3")

    # categories
    internal_create_config_category "project"
    internal_set_category_field_value "project" "name" "$1"
    internal_set_category_field_value "project" "description" "No description provided."
    internal_set_category_field_value "project" "version" "1.0.0"
    internal_set_category_field_value "project" "author" ""
    internal_set_category_field_value "project" "url" ""
    internal_set_category_field_value "project" "license" ""

    internal_create_config_category "config"
    internal_set_category_field_value "config" "mode" $2
    internal_set_category_field_value "config" "type" "$3"
    internal_set_category_field_value "config" "${3}Version" $4
    internal_set_category_field_value "config" "guard" "$5" # ifndef | pragma
    internal_set_category_field_value "config" "flags"  "$flags"

    internal_create_config_category "dependencies"
}

internal_get_lang_flags() {
    case "$1" in
        "c"|"cpp") echo "-Wall -Wextra";
    esac
}

internal_create_base_project() {
    echo "Creating structure..."

    local i=0

    create_dir() {
        [ ! -d "$1" ] && mkdir "$1" && ((i=i+1)) && log "Created $1 folder"
    }

    create_file() {
        [ ! -f "$1" ] && echo -e "$2" > "$1" && ((i=i+1)) && log "Created $1 file"
    }

    create_dir "$P_SRC_DIR"
    [ $P_MODE -eq 0 ] && create_dir "$P_INC_DIR"
    create_dir "$P_OUT_DIR"
    create_dir "$P_BUILD_DIR"
    create_dir "$P_LIB_DIR"

    create_file "$P_SRC_DIR/main.$P_SRC_EXT" "$(internal_get_main_code)"
    create_file "CMakeLists.txt" "$(internal_cmake_content)"
    create_file ".gitignore" "$(internal_get_gitignore_content)"

    internal_update_cmake_config

    [ $i -eq 0 ] && log "No changes made" || log "Done"
}

internal_create_class() {
    if [[ ! "$1" =~ ^([a-zA-Z0-9_\-]+/)*[a-zA-Z_][a-zA-Z0-9_]+$ ]]; then
        log_error "Error : class name must only contains alphanumeric characters and underscores."
        exit 1
    fi

    if [ ! -d "$P_SRC_DIR" ]; then
        log_error "Project's structure not created yet.\nAborting."
        exit 2
    fi

    local className=${1##*/}
    local path=${1%/*}
    local srcPath
    local incPath

    path=$([[ "$className" == "$path" ]] && echo "" || echo "$path/")

    if [ $P_MODE -eq 0 ]; then
        mkdir -p "$P_SRC_DIR/$path" # ./src
        mkdir -p "$P_INC_DIR/$path" # ./include
        srcPath="$P_SRC_DIR/$path$className.$P_SRC_EXT"
        incPath="$P_INC_DIR/$path$className.$P_HDR_EXT"
    else
        local folderPath="$P_SRC_DIR/$path$className"
        mkdir -p $folderPath # ./src for both
        srcPath="$folderPath/$className.$P_SRC_EXT"
        incPath="$folderPath/$className.$P_HDR_EXT"
    fi

    if [ -f "$srcPath" ] || [ -f "$incPath" ]; then
        Error "A file with this name already exists.\nAborting."
        exit 3
    fi

    internal_get_src_code $className > $srcPath
    internal_get_header_code $className > $incPath

    echo "Done"
}

internal_get_src_code() {
    internal_copyrights
    [ "$P_SRC_EXT" == "c" ]\
        && echo -e -n "#include \"$1.$P_HDR_EXT\"\n\n"\
        || echo -e -n "#include \"$1.$P_HDR_EXT\"\n\n$1::$1() {\n\n}\n\n$1::~$1() {\n\n}"
}

internal_get_header_code() {
    local guard_top="#pragma once\n\n"
    local guard_bottom=""
    local pp=${P_HDR_EXT^^}

    if [ "$P_GUARD" == "ifndef" ]; then
        guard_top="#ifndef ${1^^}_$pp\n#define ${1^^}_$pp\n\n"
        guard_bottom="\n\n#endif // ${1^^}_$pp"
    fi

    internal_copyrights
    echo -e -n "$guard_top"
    [ "$P_SRC_EXT" == "cpp" ] && echo -e -n "class $1 {\n\tpublic:\n\t\t$1();\n\t\t~$1();\n};"
    echo -e -n "$guard_bottom"
}

internal_get_main_code() {
    internal_copyrights
    [ "$P_SRC_EXT" == "cpp" ]\
        && echo -e -n "#include <iostream>\n\nint main(int argc, char **argv) {\n\t(void)argc;\n\t(void)argv;\n\tstd::cout << \"Hello World\" << std::endl;\n\treturn EXIT_SUCCESS;\n}"\
        || echo -e -n "#include <stdio.h>\n\nint main(int argc, char **argv) {\n\t(void)argc;\n\t(void)argv;\n\tprintf(\"Hello World \");\n\treturn 0;\n}"
}

internal_copyrights() {
    [ -z "$P_AUTHOR" ] && return
    echo -e -n "/**\n * @copyright (c) $(date +%Y) $P_AUTHOR\n"
    echo -e -n " * @date $(date +%Y-%m-%d)"
    [ ! -z "$P_LICENSE" ] && echo -e -n "\n * @license $P_LICENSE"
    echo -e -n "\n */\n\n"
}

internal_install_package() { # $1=package to install
    os_find $1 && return 0
    os_install $1

    if [ $? -ne 0 ]; then
        log_error "Failed to install $1."
        return 2
    fi

    echo "$1 has been installed on the computer."
    return 1
}

internal_sort_dependencies() {
    awk '
    function sort_keys(keys, sorted_keys, n, i, j, temp) {
        n = 0
        for (key in keys) {
            sorted_keys[++n] = key
        }
        for (i = 1; i <= n; i++) {
            for (j = i + 1; j <= n; j++) {
                if (keys[sorted_keys[i]] > keys[sorted_keys[j]]) {
                    temp = sorted_keys[i]
                    sorted_keys[i] = sorted_keys[j]
                    sorted_keys[j] = temp
                }
            }
        }
        return n
    }

    BEGIN { in_dependencies = 0 }
    /^[[:space:]]*#/ { next }
    {
        if ($0 ~ /^dependencies:/) {
            in_dependencies = 1
            print $0
            next
        }
        if (in_dependencies && $0 !~ /^  /) {
            in_dependencies = 0
            n = sort_keys(lines, sorted_lines)
            for (i = 1; i <= n; i++) {
                print lines[sorted_lines[i]]
            }
        }
        if (in_dependencies) {
            lines[NR] = $0
        } else {
            print $0
        }
    }
    END {
        if (in_dependencies) {
            n = sort_keys(lines, sorted_lines)
            for (i = 1; i <= n; i++) {
                print lines[sorted_lines[i]]
            }
        }
    }
    ' "$CONFIG_PATH" > "$CONFIG_PATH.tmp" && mv "$CONFIG_PATH.tmp" "$CONFIG_PATH"
}

internal_set_project_name() {
    P_NAME="$@"
    internal_set_category_field_value "project" "name" "$P_NAME"
    internal_update_cmake_config
    echo "Project name set to $P_NAME."
}

internal_set_project_url() {
    P_HOMEPAGE_URL="$@"
    internal_set_category_field_value "project" "url" "$P_HOMEPAGE_URL"
    internal_update_cmake_config
    echo "Project url set to $P_HOMEPAGE_URL."
}

internal_set_project_license() {
    P_LICENSE="$@"
    internal_set_category_field_value "project" "license" "$P_LICENSE"
    internal_update_cmake_config
    echo "Project license set to $P_LICENSE."
}

internal_set_project_description() {
    P_DESC="$@"
    internal_set_category_field_value "project" "description" "$P_DESC"
    internal_update_cmake_config
    echo "Project description changed."
}

internal_set_project_author() {
    P_AUTHOR="$@"
    internal_set_category_field_value "project" "author" "$P_AUTHOR"
    echo "Project author set to $P_AUTHOR."
}

internal_set_cpp_version() {
    if [ $P_LANG == "c" ]; then
        log_error "Project is a C project. Cannot set C++ version."
        exit 1
    fi

    ensure_valid_language_version "cpp" $1

    P_LANG_VERSION=$1
    internal_set_category_field_value "config" "cppVersion" $1
    internal_update_cmake_config
    echo "C++ version set to $1."
}

internal_set_c_version() {
    if [ "$P_LANG" == "cpp" ]; then
        log_error "Project is a C++ project. Cannot set C version."
        exit 1
    fi

    ensure_valid_language_version "c" $1

    P_LANG_VERSION=$1
    internal_set_category_field_value "config" "cVersion" $1
    internal_update_cmake_config
    echo "C version set to $1."
}

internal_set_project_mode() { # $1=mode
    ensure_project_structure
    ensure_valid_mode $1

    if [ $1 -eq $P_MODE ]; then
        echo "Project mode is already set to $1."
        exit 0
    fi

    if ! internal_swap_structure $1; then
        log_error "Failed to change the project mode."
        exit 1
    fi

    P_MODE=$1
    internal_set_category_field_value "config" "mode" $1

    echo "Project mode set to $1."
}

internal_set_guard() {
    ensure_valid_guard $1
    P_GUARD=$1
    internal_set_category_field_value "config" "guard" "$1"
    echo "Guard set to $1."
}

internal_update_cmake_config() {
    internal_load_config

    local f="CMakeLists.txt"
    local pgname=$(capitalize "$P_NAME")
    local lang=${P_LANG^^}
    [ "$lang" == "CPP" ] && lang="CXX"

    local project_line="project($pgname VERSION $P_VERSION DESCRIPTION \"$P_DESC\" HOMEPAGE_URL \"$P_HOMEPAGE_URL\" LANGUAGES $lang)"
    sed -i "/^project(/c\\$project_line" "$f"

    sed -i "s/\(set(PGNAME \"\)[^\"]*\(\"\)/\1$pgname\2/" "$f"
    sed -i "s/\(set(LANGVERSION \"\)[^\"]*\(\"\)/\1$P_LANG_VERSION\2/" "$f"
    sed -i "s/\(set(SRCEXT \"\)[^\"]*\(\"\)/\1$P_SRC_EXT\2/" "$f"
    sed -i "s/\(set(HDREXT \"\)[^\"]*\(\"\)/\1$P_HDR_EXT\2/" "$f"
}

internal_migrate_1_to_0() {
    local src_dir=$1
    local inc_dir=$2
    local relative_header
    local dirs
    local base_dir
    local header_filename
    local header_noext
    local new_filepath

    mkdir -p "$inc_dir" || return 1

    # for each header file in src/
    find "$src_dir" -type f -name "*.$P_HDR_EXT" -print0 | while IFS= read -r -d $'\0' header; do
        relative_header="${header#$src_dir/}" # remove src/ from the path
        dirs="$(dirname "$relative_header")" # get the directories
        [[ "$dirs" =~ ^(\.\/?|\.\/) ]] && dirs="" # remove ./ from the path if present # TODO to verify
        base_dir="$(basename "$dirs")" # get the directory name that contains the header file
        header_filename="$(basename "$relative_header")" # get the header filename
        header_noext="${header_filename%.*}" # get the header filename without extension
        new_filepath="$dirs/$header_noext" # new base path for the header file
        src_ext=() # source file extensions that are found with same name for the header file

        if [[ "$base_dir" == "$header_noext" ]]; then
            new_filepath="$dirs"

            for ext in "$P_SRC_EXT" "inl"; do
                if [ -f "$src_dir/$dirs/$header_noext.$ext" ]; then
                    src_ext+=("$ext")
                fi
            done
        fi

        mkdir -p $(dirname "$inc_dir/$new_filepath") || return 1
        mv "$header" "$inc_dir/$new_filepath.$P_HDR_EXT" || return 1

        for src_ext in "${src_ext[@]}"; do
            mv "$src_dir/$dirs/$header_noext.$src_ext" "$src_dir/$new_filepath.$src_ext" || return 1
        done
    done

    find "$src_dir" -type d -empty -delete || return 1
    return 0
}

internal_migrate_0_to_1() {
    local src_dir=$1
    local inc_dir=$2
    local relative_header
    local header_noext
    local filename
    local src_filepath_base
    local existing_src_files
    local new_filepath

    mkdir -p "$src_dir" || return 1

    find "$inc_dir" -type f -name "*.$P_HDR_EXT" -print0 | while IFS= read -r -d $'\0' header; do
        relative_header="${header#$inc_dir/}" # remove include/ from the path
        header_noext="${relative_header%.*}" # get the header filename without extension
        filename=$(basename "$header_noext") # get the header filename
        src_filepath_base="$src_dir/$header_noext" # source file base path
        existing_src_files=() # source file extensions that are found with same name for the header file
        new_filepath="$src_filepath_base" # new base path for the header file

        for ext in "$P_SRC_EXT" "inl"; do
            if [ -f "$src_filepath_base.$ext" ]; then
                existing_src_files+=("$ext")
                new_filepath="$src_filepath_base/$filename"
            fi
        done

        mkdir -p "$(dirname "$new_filepath")" || return 1
        mv "${PROJECT_PATH}include/$relative_header" "$new_filepath.$P_HDR_EXT" || return 1

        for src_ext in "${existing_src_files[@]}"; do
            mv "$src_filepath_base.$src_ext" "$new_filepath.$src_ext"
        done
    done

    rm -r "$inc_dir" || return 1
    return 0
}

internal_swap_structure() {
    local src_dir="${PROJECT_PATH}src"
    local inc_dir="${PROJECT_PATH}include"

    local current_mode=$P_MODE
    local desired_mode=$1

    local backup_dir=".tmp"
    local r

    setup_backup() {
        rm -rf .tmp
        mkdir -p "$backup_dir" || return 1

        # Backup current directories
        cp -r "$src_dir" "$backup_dir/src" || return 1

        if [ $current_mode -eq 0 -a -d "$inc_dir" ]; then
            cp -r "$inc_dir" "$backup_dir" || return 1
        fi

        return 0
    }

    restore_backup() {
        rm -rf "$src_dir"
        cp -r "$backup_dir/src" "$src_dir"

        if [ $current_mode -eq 0 -a -d "$backup_dir/include" ]; then
            rm -rf "$inc_dir"
            cp -r "$backup_dir/include" "$inc_dir"

        elif [ $current_mode -eq 1 -a -d "$inc_dir" ]; then
            rm -rf "$inc_dir"
        fi
    }

    delete_backup() {
        rm -rf "$backup_dir"
    }

    setup_backup

    if [ $? -ne 0 ]; then
        delete_backup
        echo "Failed to backup the current structure."
        return 1
    fi

    if [ $current_mode -eq 0 ]; then
        internal_migrate_0_to_1 $src_dir $inc_dir
        r=$?
    else
        internal_migrate_1_to_0 $src_dir $inc_dir
        r=$?
    fi

    if [ $r -ne 0 ]; then
        log_error "Failed to change the structure"
        restore_backup
    else
        log_success "Successfully changed the structure"
    fi

    delete_backup

    return $r
}

internal_update_library_include() {
    local required_commands=("rsync" "realpath")

    for cmd in "${required_commands[@]}"; do
        if ! is_command_available "$cmd" &&\
            ! ask_for_installation "rsync" "update the shared include folder"; then
            return 1
        fi
    done

    log "${CLR_DGRAY}Updating shared include folder... "

    local pgname=$(capitalize "$P_NAME")
    local base_inc_path="$P_OUT_DIR/lib/include/$pgname/"
    local file

    mkdir -p $base_inc_path

    rsync -avq --delete --prune-empty-dirs --include="*/" --include="*.$P_HDR_EXT" --include "*.inl" --exclude="*" "$P_INC_DIR/" "$base_inc_path"

    # 1st scan :
    # update file position
    find "$base_inc_path" -type f |
    while read file; do
        local dir="$(dirname "$file")/"
        local nFile=$(ls $dir | wc -l)

        while [[ $nFile -eq 1 && "$dir" != "$path" ]]; do
            local oldDir="$dir"
            dir="${dir%*/*/}/"
            mv "$file" "$dir"
            rm -r "$oldDir"
            file="${file%/*/*}/${file##*/}"
            nFile=$(ls $dir | wc -l)
        done
    done

    # 2nd scan :
    # update includes path
    find "$base_inc_path" -type f |
    while read file; do
        local dep
        cat "$file" | grep -Po '(?<=#include ")(.*\.(c|cpp|inl))(?=")' |
        while read -r dep; do
            local location=$(find "$base_inc_path" -type f -name "$(basename "$dep")")
            [[ $location == '' ]] && location='/'
            local relative=$(realpath --relative-to="$file" "$location")
            local search="#include \"$dep\""
            local replacement="#include \"${relative#'../'}\""

            sed -i -e "s|$search|$replacement|" "$file"
        done
    done

    log "Done."
}

internal_get_gitignore_content() {
    local ignore_list=(
        "# Ignore build files" "build/" "bin/" "lib/" "out/" "CMakeFiles/"
        "CMakeCache.txt" "cmake_install.cmake" "Makefile"
    );
    printf "%s\n" "${ignore_list[@]}"
}

internal_cmake_content() {
    local cmake_content="Y21ha2VfbWluaW11bV9yZXF1aXJlZChWRVJTSU9OIDMuMTIpCgpwcm9qZWN0KE5ld1Byb2plY3QgVkVSU0lPTiAxLjAuMCBERVNDUklQVElPTiAiTm8gZGVzY3JpcHRpb24gcHJvdmlkZWQuIiBIT01FUEFHRV9VUkwgIiIgTEFOR1VBR0VTIENYWCkKCiMgaW5qZWN0YWJsZSB2YXJpYWJsZXMKc2V0KEJVSUxEX01PREUgInJlbGVhc2UiIENBQ0hFIFNUUklORyAiZGVidWcgb3IgcmVsZWFzZSIpCnNldChQR05BTUUgIk5ld1Byb2plY3QiIENBQ0hFIFNUUklORyAiUHJvZ3JhbSBuYW1lIikKc2V0KFNSQ0RJUiAic3JjIiBDQUNIRSBTVFJJTkcgIlNvdXJjZSBkaXJlY3RvcnkiKQpzZXQoSU5DRElSICJpbmNsdWRlIiBDQUNIRSBTVFJJTkcgIkluY2x1ZGUgZGlyZWN0b3J5IikKc2V0KE9VVCAiYmluIiBDQUNIRSBTVFJJTkcgIk91dHB1dCBkaXJlY3RvcnkiKQpzZXQoQlVJTERESVIgImJ1aWxkIiBDQUNIRSBTVFJJTkcgIkJ1aWxkIGRpcmVjdG9yeSIpCnNldChMQU5HVkVSU0lPTiAiMjAiIENBQ0hFIFNUUklORyAiTGFuZ3VhZ2Ugc3RhbmRhcmQgdmVyc2lvbiIpCnNldChTUkNFWFQgImNwcCIgQ0FDSEUgU1RSSU5HICJTb3VyY2UgZmlsZSBleHRlbnNpb24gKGMgb3IgY3BwKSIpCnNldChNQUNSTyAiIiBDQUNIRSBTVFJJTkcgIk1hY3JvIGRlZmluaXRpb25zIikKc2V0KEZMQUdTICIiIENBQ0hFIFNUUklORyAiQWRkaXRpb25hbCBjb21waWxpbmcgZmxhZ3MiKQoKaWYoJHtTUkNFWFR9IFNUUkVRVUFMICJjIikKICAgIHNldChDTUFLRV9DX1NUQU5EQVJEICR7TEFOR1ZFUlNJT059KQogICAgc2V0KENNQUtFX0NfRkxBR1MgIiR7Q01BS0VfQ19GTEFHU30gJHtGTEFHU30iKQogICAgZW5hYmxlX2xhbmd1YWdlKEMpCmVsc2UoKQogICAgc2V0KENNQUtFX0NYWF9TVEFOREFSRCAke0xBTkdWRVJTSU9OfSkKICAgIHNldChDTUFLRV9DWFhfRkxBR1MgIiR7Q01BS0VfQ1hYX0ZMQUdTfSAke0ZMQUdTfSIpCiAgICBlbmFibGVfbGFuZ3VhZ2UoQ1hYKQplbmRpZigpCgojIGlmIFNSQ0RJUiwgSU5DRElSLCBPVVQsIEJVSUxERElSIHN0YXJ0IHdpdGggIi4vIiwgcmVtb3ZlIGl0CmZvcmVhY2goRElSX1ZBUiBTUkNESVIgSU5DRElSIE9VVCBCVUlMRERJUikKICAgIGlmKCR7JHtESVJfVkFSfX0gTUFUQ0hFUyAiXlxcLi8iKQogICAgICAgIHN0cmluZyhTVUJTVFJJTkcgJHske0RJUl9WQVJ9fSAyIC0xICR7RElSX1ZBUn0pCiAgICBlbmRpZigpCmVuZGZvcmVhY2goKQoKIyBwcmVmaXggYnkgYWJzb2x1dGUgcGF0aCBvZiB3b3Jrc3BhY2UgZm9sZGVyCnNldChPVVQgJHtDTUFLRV9TT1VSQ0VfRElSfS8ke09VVH0pCnNldChCVUlMRERJUiAke0NNQUtFX1NPVVJDRV9ESVJ9LyR7QlVJTERESVJ9KQpzZXQoU1JDRElSICR7Q01BS0VfU09VUkNFX0RJUn0vJHtTUkNESVJ9KQpzZXQoSU5DRElSICR7Q01BS0VfU09VUkNFX0RJUn0vJHtJTkNESVJ9KQoKIyBnZXQgYWxsIHNvdXJjZSBmaWxlcwpmaWxlKEdMT0JfUkVDVVJTRSBTT1VSQ0VTICIke1NSQ0RJUn0vKi4ke1NSQ0VYVH0iKQoKIyBnZXQgYWxsIGluY2x1ZGUgZGlyZWN0b3JpZXMKZmlsZShHTE9CX1JFQ1VSU0UgSEVBREVSX0ZJTEVTICIke0lOQ0RJUn0vKi5oIiAiJHtJTkNESVJ9LyouaHBwIikKCnNldChJTkNMVURFX0RJUlMgIiIpCmZvcmVhY2goSEVBREVSX0ZJTEUgJHtIRUFERVJfRklMRVN9KQogICAgZ2V0X2ZpbGVuYW1lX2NvbXBvbmVudChESVIgJHtIRUFERVJfRklMRX0gRElSRUNUT1JZKQogICAgbGlzdChBUFBFTkQgSU5DTFVERV9ESVJTICR7RElSfSkKZW5kZm9yZWFjaCgpCgojIHJlbW92ZSBkdXBsaWNhdGUgZGlyZWN0b3JpZXMKbGlzdChSRU1PVkVfRFVQTElDQVRFUyBJTkNMVURFX0RJUlMpCgppbmNsdWRlX2RpcmVjdG9yaWVzKCR7SU5DTFVERV9ESVJTfSkKCmlmKE1BQ1JPKQogICAgZm9yZWFjaChNIElOIExJU1RTIE1BQ1JPKQogICAgICAgIGFkZF9jb21waWxlX2RlZmluaXRpb25zKCR7TX0pCiAgICBlbmRmb3JlYWNoKCkKZW5kaWYoKQoKCiMgc3BlY2lmaWMgYnVpbGQgdHlwZSBjb25maWcKCmlmKEJVSUxEX1RZUEUgU1RSRVFVQUwgImJ1aWxkIikKICAgIHNldChDTUFLRV9SVU5USU1FX09VVFBVVF9ESVJFQ1RPUlkgJHtPVVR9LyR7Q01BS0VfQlVJTERfTU9ERX0pCgogICAgYWRkX2V4ZWN1dGFibGUoJHtQR05BTUV9ICR7U09VUkNFU30pCgogICAgc2V0X3RhcmdldF9wcm9wZXJ0aWVzKCR7VEFSR0VUfSBQUk9QRVJUSUVTCiAgICAgICAgUlVOVElNRV9PVVRQVVRfRElSRUNUT1JZICR7Q01BS0VfUlVOVElNRV9PVVRQVVRfRElSRUNUT1JZfQogICAgKQoKICAgIGluc3RhbGwoVEFSR0VUUyAke1BHTkFNRX0gREVTVElOQVRJT04gJHtDTUFLRV9SVU5USU1FX09VVFBVVF9ESVJFQ1RPUll9KQoKICAgIGFkZF9jdXN0b21fdGFyZ2V0KGJ1aWxkCiAgICAgICAgQ09NTUFORCAke0NNQUtFX0NPTU1BTkR9IC0tYnVpbGQgJHtDTUFLRV9CSU5BUllfRElSfSAtLXRhcmdldCAke1BHTkFNRX0KICAgICAgICBDT01NRU5UICJCdWlsZGluZyBleGVjdXRhYmxlIgogICAgKQoKCmVsc2VpZihCVUlMRF9UWVBFIFNUUkVRVUFMICJzaGFyZWQiKQogICAgc2V0KENNQUtFX0xJQlJBUllfT1VUUFVUX0RJUkVDVE9SWSAke09VVH0vbGliKQoKICAgIGFkZF9saWJyYXJ5KCR7UEdOQU1FfSBTSEFSRUQgJHtTT1VSQ0VTfSkKCiAgICBzZXRfdGFyZ2V0X3Byb3BlcnRpZXMoJHtQR05BTUV9IFBST1BFUlRJRVMKICAgICAgICBMSUJSQVJZX09VVFBVVF9ESVJFQ1RPUlkgJHtDTUFLRV9MSUJSQVJZX09VVFBVVF9ESVJFQ1RPUll9CiAgICApCgogICAgaW5zdGFsbChUQVJHRVRTICR7UEdOQU1FfSBERVNUSU5BVElPTiAke0NNQUtFX0xJQlJBUllfT1VUUFVUX0RJUkVDVE9SWX0pCgogICAgYWRkX2N1c3RvbV90YXJnZXQoc2hhcmVkCiAgICAgICAgQ09NTUFORCAke0NNQUtFX0NPTU1BTkR9IC0tYnVpbGQgJHtDTUFLRV9CSU5BUllfRElSfSAtLXRhcmdldCAke1BHTkFNRX0KICAgICAgICBDT01NRU5UICJCdWlsZGluZyBzaGFyZWQgbGlicmFyeSIKICAgICkKCgplbHNlaWYoQlVJTERfVFlQRSBTVFJFUVVBTCAic3RhdGljIikKICAgIHNldChDTUFLRV9BUkNISVZFX09VVFBVVF9ESVJFQ1RPUlkgJHtPVVR9L2xpYikKICAgIAogICAgYWRkX2xpYnJhcnkoJHtQR05BTUV9IFNUQVRJQyAke1NPVVJDRVN9KQoKICAgIHNldF90YXJnZXRfcHJvcGVydGllcygke1RBUkdFVH0gUFJPUEVSVElFUwogICAgICAgIEFSQ0hJVkVfT1VUUFVUX0RJUkVDVE9SWSAke0NNQUtFX0FSQ0hJVkVfT1VUUFVUX0RJUkVDVE9SWX0KICAgICkKCiAgICBpbnN0YWxsKFRBUkdFVFMgJHtQR05BTUV9IERFU1RJTkFUSU9OICR7Q01BS0VfQVJDSElWRV9PVVRQVVRfRElSRUNUT1JZfSkKCiAgICBhZGRfY3VzdG9tX3RhcmdldChzdGF0aWMKICAgICAgICBDT01NQU5EICR7Q01BS0VfQ09NTUFORH0gLS1idWlsZCAke0NNQUtFX0JJTkFSWV9ESVJ9IC0tdGFyZ2V0ICR7UEdOQU1FfQogICAgICAgIENPTU1FTlQgIkJ1aWxkaW5nIHN0YXRpYyBsaWJyYXJ5IgogICAgKQoKZW5kaWYoKQoKYWRkX2N1c3RvbV90YXJnZXQoY2xlYXIKICAgIENPTU1BTkQgJHtDTUFLRV9DT01NQU5EfSAtRSBlY2hvICJCdWlsZCBkaXJlY3RvcnkgY2xlYXJlZCIKKQo="
    echo -e "$cmake_content" | base64 --decode
}


internal_prepare_build_run() {
    [ ! -z "$X_PREPARED" ] && return 0

    X_PREPARED="1"

    local has_clean=0
    local has_mode=0

    local other_args=""
    local max_threads=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)

    X_EXECUTABLE=$(capitalize "$P_NAME")
    X_MODE="debug"
    X_SUBMODE="dev"
    X_RULE="build"
    X_THREADS=$((max_threads/2))

    while (( $# > 0 )); do
        case "$1" in
            "-d"|"-g"|"-r"|"--dev"|"--debug"|"--release")
                [[ has_mode -ne 0 ]] && continue
                has_mode=1

                case "$1" in
                    "-g"|"--debug")     X_MODE="debug"   X_SUBMODE="debug";;
                    "-d"|"--dev")       X_MODE="debug"   X_SUBMODE="dev";;
                    "-r"|"--release")   X_MODE="release" X_SUBMODE="release";;
                esac
            ;;

            "--static"|"--shared")
                [[ has_mode -ne 0 ]] && continue
                has_mode=1
                X_RULE="${1:2}"
                RUN_AFTER_COMPILE=0
                ;;

            "-f"|"--force") has_clean=1;;

            "-t")
                # if $2 is "max", then put max_threads-1 threads
                # if $2 is "half", then put half of the max threads
                # if $2 is a number, then put that number of threads
                if [ "$2" == "max" ]; then
                    X_THREADS=$((max_threads-1)) # keep one thread for UI or other tasks
                elif [[ "$2" =~ ^[0-9]+$ ]]; then
                    X_THREADS=$2
                else
                    warn "Invalid number of threads given. Using half as default."
                fi
                shift;;

            *) other_args="$other_args $1";;
        esac

        shift
    done

    case "$OSTYPE" in
        "linux"*)                X_PRGM_EXT=""      X_OS="LINUX";;
        "darwin"*)               X_PRGM_EXT=".app"  X_OS="MACOS";;
        "cygwin"|"msys"|"win32") X_PRGM_EXT=".exe"  X_OS="WINDOWS";;
    esac

    if [ $X_THREADS -gt $max_threads ]; then
        X_THREADS=$((max_threads-1))
        warn "The number of threads defined exceeds the maximum number of threads available ($max_threads). $X_THREADS threads will be used."
    fi

    [ $X_THREADS -lt 1 ] && X_THREADS=1

    X_MACRO="${X_MODE^^}"
    [ ! -z "$X_OS" ] && X_MACRO="$X_MACRO;$X_OS"

    [[ has_clean -eq 1 && -f "$P_BUILD_DIR/Makefile" ]] && cmd_clean_project

    EXE_ARGUMENTS="$other_args"
}

internal_set_default_init_lang() {
    if [ -z "$1" ]; then
        echo "Usage: $COMMAND_NAME global lang <c|cpp>"
        exit 1
    fi

    ensure_valid_language "$1"
    internal_set_global_config "DEFAULT_INIT_LANG" "$1"
    log_success "Default language for project initialization set to $1."
}

internal_set_default_guard_manager() {
    if [ -z "$1" ]; then
        echo "Usage: $COMMAND_NAME global guard <guard_manager>"
        exit 1
    fi

    ensure_valid_guard "$1"
    internal_set_global_config "DEFAULT_GUARD" "$1"
    log_success "Default guard set to $1."
}

internal_set_default_package_manager() {
    if [ -z "$1" ]; then
        echo "Usage: $COMMAND_NAME global pm <package_manager>"
        exit 1
    fi

    if ! is_command_available "$1"; then
        log_error "Package manager $1 is not available in your computer."
        exit 1
    fi

    internal_set_global_config "PACKAGE_MANAGER" "$1"

    log_success "Default package manager set to $1."
}

internal_get_distro_base() {
    local r=0

    if [[ "$(uname)" == "Darwin" ]]; then
        OS="MacOS"
        DISTRO="macOS"
        PREFERENCE_PATH=~/Library/Preferences/nfpm
    elif [[ "$(uname -o)" == "Cygwin" ]]; then
        OS="Windows"
        DISTRO="Cygwin"
        PREFERENCE_PATH=~/AppData/Roaming/nfpm
    elif [[ "$(uname -o)" == "Msys" ]]; then
        OS="Windows"
        DISTRO="Msys"
        PREFERENCE_PATH=~/AppData/Roaming/nfpm
    elif [ -f /etc/os-release ]; then
        OS="Linux"
        PREFERENCE_PATH=~/.config/nfpm
        . /etc/os-release
        case "$ID" in
            debian|ubuntu|kali|linuxmint|elementary|pop|zorin) DISTRO="Debian";;
            fedora|rhel|centos) DISTRO="Red Hat";;
            opensuse|suse) DISTRO="SUSE";;
            arch|manjaro) DISTRO="Arch";;
            *) r=1;;
        esac
    else
        r=1
    fi

    if [ $r -ne 0 ]; then
        log_error "$OS $DISTRO is not supported yet."
        echo "Feel free to contribute by opening an issue to the github repository"
        echo "to notify this disagreement or help improve this project."
        echo "At $REPO_URL"
        exit 1
    fi
}

internal_find_first_usable_command() {
    for cmd in $@; do
        if is_command_available $cmd; then
            echo "$cmd"
            break
        fi
    done
}

internal_set_global_config() { # $1=key, $2=value
    local config_file="$PREFERENCE_PATH/global"

    if [ -z "$1" ] || [ -z "$2" ]; then
        echo "Usage: $COMMAND_NAME global <key> <value>"
        exit 1
    fi

    # find the key and edit its value or insert it if not found
    # config file always exists so don't check its existence
    if grep -q "^$1=" "$config_file"; then
        sed -i "s/^$1=.*/$1=$2/" "$config_file"
    else
       	echo "$1=$2" >> "$config_file"
    fi

    GLOBALS["$1"]="$2"
}

internal_load_global_config() {
    local config_file="$PREFERENCE_PATH/global"
    local first_execution=1

    if [ -f "$config_file" ]; then
        first_execution=0
        # content looks like this :
        # KEY=VALUE
        # KEY2=VALUE2
        # ...
        while IFS='=' read -r key value; do
            GLOBALS["$key"]="$value"
        done < "$config_file"
    else
        mkdir -p "$PREFERENCE_PATH"
        touch "$config_file"
    fi

    local pm

    # if no "PACKAGE_MANAGER" key is found, set it to the detected package manager
    # or if set but testing the command fails, set it to the detected package manager
    if [ -z "${GLOBALS["PACKAGE_MANAGER"]}" ] || ! is_command_available "${GLOBALS["PACKAGE_MANAGER"]}"; then
        local pm=$(internal_find_package_manager)

        if [ -z "$pm" ]; then
            log_error "No package manager found."
            exit 1
        fi

        internal_set_global_config "PACKAGE_MANAGER" "$pm"
        echo -e "${CLR_LGRAY}$pm will be used as the package manager."
        echo -e "To change it, use the command: $COMMAND_NAME global pm <package_manager>${CLR_RESET}\n"
    fi

    pm="${GLOBALS["PACKAGE_MANAGER"]}"

    case $pm in
        "apt"|"apt-get"|"dnf"|"yum"|"zypper"|"pacman"|"snap")
            APT_INSTALL="sudo $pm install -y"
            APT_UNINSTALL="sudo $pm remove -y"
            ;;
        "brew")
            APT_INSTALL="$pm install"
            APT_UNINSTALL="$pm uninstall"
            ;;
        "setup-x86_64.exe")
            APT_INSTALL="$pm -q -P"
            APT_UNINSTALL="$pm -q -X"
            ;;
        *)
            echo "Unsupported package manager: $pm"
            return 1
            ;;
    esac

    return $first_execution
}

internal_find_package_manager() {
    case $OS in
        "MacOS") echo "brew";;
        "Linux") echo $(internal_find_first_usable_command "apt" "apt-get" "dnf" "yum" "zypper" "pacman" "snap");;
        "Windows")
            case $DISTRO in
                "Cygwin") echo $(internal_find_first_usable_command "apt-cyg" "choco" "setup-x86_64.exe");;
                "Msys") echo "pacman";;
            esac
            ;;
    esac
}

internal_configure_os() {
    internal_get_distro_base
    internal_load_global_config
}

internal_compile() {
    ensure_project_structure

    internal_prepare_build_run $@

    local required_commands=("cmake")

    for cmd in "${required_commands[@]}"; do
        if ! is_command_available "$cmd" &&\
            ! ask_for_installation "$cmd" "compile the project"; then
            return 1
        fi
    done

    local start_time=$(date_now)

    local prepare_cmd="cmake -S . -B $P_BUILD_DIR \
        -D \"CMAKE_BUILD_TYPE=$(capitalize $X_MODE)\" \
        -D \"BUILD_TYPE=$X_RULE\" \
        -D \"PGNAME=$X_EXECUTABLE\" \
        -D \"SRCDIR=$P_SRC_DIR\" \
        -D \"INCDIR=$P_INC_DIR\" \
        -D \"OUT=$P_OUT_DIR\" \
        -D \"BUILDDIR=$P_BUILD_DIR\" \
        -D \"LANGVERSION=$P_LANG_VERSION\" \
        -D \"SRCEXT=$P_SRC_EXT\" \
		-D \"FLAGS=$P_FLAGS\" \
        -D \"MACRO=$X_MACRO\" \
	"

    export CMAKE_BUILD_PARALLEL_LEVEL=$X_THREADS

    # echo c but replaces multiple spaces with one space
    echo -e "${CLR_LGRAY}$(echo $prepare_cmd | sed 's/ \+/ /g')${CLR_RESET}" &> $OUTPUT
    eval $prepare_cmd &> $OUTPUT

    local cmake_result=$?
    local cmake_duration=$(get_formatted_duration $start_time)

    if [ $cmake_result -ne 0 ]; then
        log_error "Generating Makefile failed in $cmake_duration (code $cmake_result)"
        return 1
    fi

    log_success "Makefile generated in $cmake_duration" &> $OUTPUT

    middle_time=$(date_now)

	local build_cmd="cmake --build $P_BUILD_DIR --target $X_RULE --config $(capitalize $X_MODE) --parallel $X_THREADS"

	echo -e "${CLR_LGRAY}$build_cmd${CLR_RESET}" &> $OUTPUT
	eval $build_cmd &> $OUTPUT

    local make_result=$?
    local make_duration=$(get_formatted_duration $middle_time)
    local total_time=$(get_formatted_duration $start_time)

    if [ $make_result -ne 0 ]; then
        log_error "Compilation failed in $make_duration (code $make_result)"
        return 1
    fi

    log_success "Compilation succeed in $make_duration" &> $OUTPUT
    echo -e "${CLR_DGRAY}Total compilation time : $total_time${CLR_RESET}"

    return 0
}


# -----------------------------------------------------------
# ------------------------ COMMANDS -------------------------
# -----------------------------------------------------------
# prefix: cmd
# description: Commands that are available for the user which
#              uses the script.
#              Each command has $@ which is the scripts arguments.
#              Thus, $0 is the script name, $1 is the command name.
#              The rest of the arguments are the user's arguments.

cmd_new_project() {
    local path="."
    local name="New Project"
    local lang=""
    local lang_version
    local mode=0
    local verbose=0
    local guard="${GLOBALS["DEFAULT_GUARD"]}"

    shift

    while [ $# -gt 0 ]; do
        case "$1" in
            --name=*) name="${1#*=}";;
            --lang=*) lang="${1#*=}";;
            --mode=*) mode="${1#*=}";;
            --guard=*) guard="${1#*=}";;
            *) path="${1%/}";;
        esac
        shift
    done

    [ -z "$path" ] && path="."
    [[ ! "$path" =~ ^(\.|\/) ]] && path="./$path"

    set_project_path "$path"
    
    if [ -f "$CONFIG_PATH" ]; then
        log_error "A project is already initialized in this directory."
        exit 1;
    fi

    if [ -z "$lang" ]; then
        if [ -z "${GLOBALS["DEFAULT_INIT_LANG"]}" ]; then
            # ask for C or CPP project
            read -p "Choose the project language (c/CPP): " lang

            if [ -z "$lang" ]; then
                lang="cpp"
            fi

            echo -e "\nHINT: You can set the default language for project creation with '$COMMAND_NAME global lang <c/cpp>'"
            echo -e "      Thus, you won't be asked for the language anymore if you don't specify one.\n"
        else
            lang="${GLOBALS["DEFAULT_INIT_LANG"]}"
        fi
    fi

    [ -z "$guard" ] && guard="ifndef"
    lang_version=$([[  "$lang" == "c" ]] && echo 17 || echo 20)

    ensure_valid_guard "$guard"
    ensure_valid_language "$lang"
    ensure_valid_mode "$mode"
    ensure_valid_language_version "$lang" "$lang_version"

    mkdir -p "$PROJECT_PATH" || { log_error "Failed to create the project directory."; exit 1; }

    internal_create_project_config "$name" $mode "$lang" $lang_version "$guard"

    log_success "New project initialized !\n"
    echo -e "You can customize your project's configuration in the $CONFIG_PATH file.\n"
    echo    "NOTE : do not modify the project.yml directly. It is strongly recommended"
    echo    "       to use the script's commands for that, as it can dispatch changes"
    echo -e "       in other configurations like the cmake.\n"

    internal_load_config
    internal_create_base_project
}

cmd_generate() { # $2=type, $3=name
    ensure_inside_project;

    if [ -z "$2" ]; then
        internal_create_base_project
        exit 0
    fi

    case "$2" in
        "class"|"c") internal_create_class $3;;
        *) log_error "Invalid type. Supported types are project and class."; exit 1;;
    esac
}

cmd_install_all_packages() {
    ensure_inside_project; 

    os_update

    local installed_success_count=0
    local installed_failed_count=0
    local in_dependencies=0
    local start_time=$(date_now)

    while IFS=: read -r dependency packages; do
        [[ "$dependency" == "dependencies" ]] && { in_dependencies=1; continue; }
        [[ $in_dependencies -eq 1 && "$dependency" =~ ^[[:space:]]*$ ]] && in_dependencies=0
        [[ $in_dependencies -eq 1 ]] && for package in $packages; do
            internal_install_package $package
            installStatus=$?
            [ $installStatus -eq 1 ] && installed_success_count=$((installed_success_count+1))
            [ $installStatus -eq 2 ] && installed_failed_count=$((installed_failed_count+1))
        done
    done < "$CONFIG_PATH"

    local duration=$(get_formatted_duration $start_time)
    [ $installed_failed_count -eq 0 ] && [ $installed_success_count -eq 0 ] && echo "Up to date."
    echo -e "\n$installed_success_count installed, $installed_failed_count failed in $duration."
}

cmd_add_package() { # $1=dependency name, $2..=packages
    ensure_inside_project
    shift

    if [ -z "$1" ] || [ -z "$2" ]; then
        echo "Usage: $COMMAND_NAME add <dependency_name> <package1_name> [<package2_name> ...]"
        exit 1
    fi

    dep=$1
    shift

    local packages=("$@")
    local added_count=0
    local installed_success_count=0
    local installed_failed_count=0
    local start_time=$(date_now)

    # Step 1: Check if the key already exists in the dependencies list
    if grep -q "  $dep:" $CONFIG_PATH; then
        # Step 1.a: Look for already present values for this key
        local existing_packages=$(grep "  $dep:" $CONFIG_PATH | awk -F': ' '{print $2}')
        for package in $existing_packages; do
            for i in "${!packages[@]}"; do
                if [ "${packages[i]}" == "$package" ]; then
                    echo "${packages[i]} is already in the dependencies list."
                    unset 'packages[i]'
                fi
            done
        done
    fi

    # Check for packages in all dependency lines
    local all_existing_packages=$(awk '/^  / {print $2}' $CONFIG_PATH)
    for package in $all_existing_packages; do
        for i in "${!packages[@]}"; do
            if [ "${packages[i]}" == "$package" ]; then
                echo "${packages[i]} is already in the dependencies list."
                unset 'packages[i]'
            fi
        done
    done

    local new_packages=()

    # Step 2: Install each dependency
    for package in "${packages[@]}"; do
        [ -z "$package" ] && continue

        internal_install_package $package
        local r=$?

        [ $r -eq 1 ] && installed_success_count=$((installed_success_count+1))
        [ $r -eq 2 ] && installed_failed_count=$((installed_failed_count+1))

        if [ $r -ne 2 ]; then
            new_packages+=($package)
            added_count=$((added_count+1))
            echo "$package added."
        fi
    done

    # Step 3: Add successfully installed packages to the dependencies list
    # Combine existing and new packages
    local combined_packages="$existing_packages ${new_packages[*]}"
    combined_packages=$(echo "$combined_packages" | sed 's/^ *//;s/ *$//')

    internal_set_category_field_value "dependencies" "$dep" "$combined_packages"

    # Step 4: Sort the dependencies lines
    internal_sort_dependencies

    local duration=$(get_formatted_duration $start_time)

    echo -e "\n$added_count added, $installed_success_count installed, $installed_failed_count failed in $duration."
}

cmd_uninstall_packages() { # $2..=packages
    ensure_inside_project

    if [ -z "$2" ]; then
        echo "Usage: $COMMAND_NAME uninstall <package_name> [package_name...]"
        exit 1
    fi

    shift

    local package_count=0
    local dependency_count=$#
    local start_time=$(date_now)

    for package_name in "$@"; do
        package_line=$(internal_get_category_field_value "dependencies" "$package_name")

        if [ -z "$package_line" ]; then
            log_error "$package_name is not in the dependency list of this project."
            continue
        fi

        for package in $package_line; do
            if os_uninstall $package &> $OUTPUT; then 
                echo "$package has been uninstalled from the computer."
                package_count=$((package_count+1))
            else
                log_error "Failed to uninstall $package."
            fi
        done
    done

    local duration=$(get_formatted_duration $start_time)
    echo -e "\nUninstalled $package_count packages for $dependency_count dependencies in $duration."
}

cmd_remove_packages() { # $2..=packages
    ensure_inside_project

    local confirm_uninstall_all=0
    
    [[ "$@" == *"-y"* ]] && confirm_uninstall_all=1 && set -- "${@//"-y"}"
    [[ "$@" == *"-n"* ]] && confirm_uninstall_all=2 && set -- "${@//"-n"}"

    if [ -z "$2" ]; then
        echo "Usage: $COMMAND_NAME remove <package_name> [package_name...]"
        exit 1
    fi

    shift

    # trim $@
    set -- $(echo $@ | xargs)

    for package_name in "$@"; do
        local package_line=$(internal_get_category_field_value "dependencies" "$package_name")
        
        if [ -z "$package_line" ]; then
            log_error "$package_name is not in the dependency list of this project."
            continue
        fi

        sed -i "/  $package_name:/d" $CONFIG_PATH
        echo "$package_name has been removed from the project."

        if [ $confirm_uninstall_all -eq 2 ]; then
            continue
        fi

        if [ $confirm_uninstall_all -eq 1 ]; then
            os_uninstall $package_line
            continue
        fi

        for package in $package_line; do
            local uninstall
            read -p "Do you also want to uninstall $package from the computer? (y/N): " uninstall
            [[ $uninstall =~ ^[Yy]$ ]] && os_uninstall $package
        done
    done
}

cmd_list_packages() {
    ensure_inside_project

    awk '
    function sort_keys(keys, sorted_keys, n, i, j, temp) {
        n = 0
        for (key in keys) {
            sorted_keys[++n] = key
        }
        for (i = 1; i <= n; i++) {
            for (j = i + 1; j <= n; j++) {
                if (sorted_keys[i] > sorted_keys[j]) {
                    temp = sorted_keys[i]
                    sorted_keys[i] = sorted_keys[j]
                    sorted_keys[j] = temp
                }
            }
        }
        return n
    }

    BEGIN { in_dependencies = 0 }
    /^[[:space:]]*#/ { next }
    /^dependencies:/ { in_dependencies = 1; next }
    in_dependencies && /^[^ ]/ { in_dependencies = 0 }
    in_dependencies && NF {
        split($0, arr, ": ")
        key = arr[1]
        values = arr[2]
        keys[key] = values
    }
    END {
        n = sort_keys(keys, sorted_keys)
        for (i = 1; i <= n; i++) {
            key = sorted_keys[i]
            values = keys[key]
            split(values, value_arr, " ")
            if (i < n) {
                print "├─" key
                for (j = 1; j <= length(value_arr); j++) {
                    if (j < length(value_arr)) {
                        print "│      ├ " value_arr[j]
                    } else {
                        print "│      └ " value_arr[j]
                    }
                }
            } else {
                print "└─" key
                for (j = 1; j <= length(value_arr); j++) {
                    if (j < length(value_arr)) {
                        print "       ├ " value_arr[j]
                    } else {
                        print "       └ " value_arr[j]
                    }
                }
            }
        }
    }
    ' "$CONFIG_PATH"
}

cmd_patch_version() { # $2=patch|minor|major
    ensure_inside_project;

    local current_version=$(internal_get_category_field_value "project" "version")

    if [[ ! "$current_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_error "Invalid version format."
        exit 1
    fi

    IFS='.' read -r -a version_parts <<< "$current_version"
    local major=${version_parts[0]}
    local minor=${version_parts[1]}
    local patch=${version_parts[2]}

    case "$2" in
        "major") major=$((major+1)); minor=0; patch=0;;
        "minor") minor=$((minor+1)); patch=0;;
        "patch") patch=$((patch+1));;
    esac

    P_VERSION="$major.$minor.$patch"
    internal_set_category_field_value "project" "version" "$P_VERSION"
    internal_update_cmake_config
    echo -e "Version updated to ${CLR_GREEN}$P_VERSION.${CLR_RESET}"
}

cmd_change_project_configuration() { # $2=key, $3=value
    ensure_inside_project
    internal_load_config

    shift
    local key=$1
    shift
    local value=$@

    if [ -z "$key" ] || [ -z "$value" ]; then
        echo "Usage: $COMMAND_NAME set <key> <value>"
        exit 1
    fi

    case $key in
        "name") internal_set_project_name $value;;
        "description") internal_set_project_description $value;;
        "author") internal_set_project_author $value;;
        "url") internal_set_project_url $value;;
        "license") internal_set_project_license $value;;
        "cppVersion") internal_set_cpp_version $value;;
        "cVersion") internal_set_c_version $value;;
        "mode") internal_set_project_mode $value;;
        "guard") internal_set_guard $value;;
        *) log_error "Invalid key."; exit 1;;
    esac
}

cmd_compile() {
    shift
    internal_compile $@
    exit $?
}

cmd_run() { # $@=args
    ensure_project_structure

    shift

    echo -e -n "${CLR_DGRAY}"
    internal_compile $@
    local res=$?
    echo -e -n "${CLR_RESET}"

    [ $res -ne 0 ] && exit 1
    [ "$X_RULE" == "shared" ] && internal_update_library_include
    [ $RUN_AFTER_COMPILE -eq 0 ] && exit 0

    local exe_dir="$P_OUT_DIR/$X_MODE"

    echo "Moving to $exe_dir" &> $OUTPUT
    cd "$exe_dir"

    echo
    local border="${CLR_DGRAY}---------------${CLR_RESET}"
    log "$border Executing $(get_colored_mode) mode $border\n\n"

    if [ "$X_SUBMODE" == "debug" ] &&\
        ! is_command_available "gdb" &&\
        ! ask_for_installation "gdb" "run the program in debug mode"; then
        exit 1
    fi

    local exe="./$X_EXECUTABLE$X_PRGM_EXT"

    [ "$X_SUBMODE" == "debug" ]\
        && gdb $exe\
        || $exe $EXE_ARGUMENTS

    echo
}

cmd_clean_project() {
    ensure_project_structure
    make -C $P_BUILD_DIR clear &> /dev/null
    [ -d "$P_BUILD_DIR" ] && rm -r "$P_BUILD_DIR"/*
    echo "Project cleaned."
}

cmd_update_script() {
    if ! os_fetch_file_content "$SCRIPT_PATH" "$UPDATE_URL"; then
        log_error "Failed to update"
        exit 1
    fi

    VERSION=${VERSION:-0.1}
    newVersion="$(grep -Eo 'NF_VERSION=[0-9]+\.[0-9]+' $SCRIPT_PATH | cut -d'=' -f2)"

    if [ "$NF_VERSION" == $newVersion ]; then
        echo "Already on latest version ($NF_VERSION)."
    else
        echo "v$NF_VERSION -> v$newVersion"
        log_success "Successfully updated$"
    fi

    exit 0
}

cmd_get_help() {
    echo -e "$BRAND"
    echo -e "$HELP_MESSAGE"
}

cmd_set_global_config() {
    if [ -z "$2" ]; then
        echo "Usage: $COMMAND_NAME global <key> [...options]"
        exit 1
    fi

    case $2 in
        "pm") internal_set_default_package_manager $3;;
        "lang") internal_set_default_init_lang $3;;
        "guard") internal_set_default_guard_manager $3;;
        *) log_error "Invalid key."; exit 1;;
    esac
}

cmd_infos() {
    echo "$OS - $DISTRO $VERSION"
    echo "$APT_INSTALL"
    cmd_get_version
}

cmd_get_version() {
    echo -e "v$NF_VERSION"
}


# -----------------------------------------------------------
# -------------------- GLOBAL VARIABLES ---------------------
# -----------------------------------------------------------

# Global variables
NF_VERSION=1.0.0

# Get the absolute path of the script's directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_PATH="$0"
COMMAND_NAME=$(basename "$0" | sed 's/\.[^.]*$//')

CONFIG_FILE="project.yml"
PROJECT_PATH="./"
CONFIG_PATH="$PROJECT_PATH/$CONFIG_FILE"
REPO_URL="https://github.com/NoxFly/nfpm"
UPDATE_URL="https://raw.githubusercontent.com/NoxFly/nfpm/main/nf.sh"

# By default, compile then run
RUN_AFTER_COMPILE=1
VERBOSE=0

declare -A GLOBALS=()

OS=""
DISTRO=""
APT_INSTALL=""
PREFERENCE_PATH=""

# Colors
CLR_RESET="\033[0m"
CLR_RED="\033[0;31m"
CLR_ORANGE="\033[0;33m"
CLR_GREEN="\033[0;32m"
CLR_DGRAY="\033[0;90m"
CLR_LGRAY="\033[0;37m"
# bold
CLR_BRED="\033[1;31m"
CLR_BGREEN="\033[1;32m"
CLR_BORANGE="\033[1;33m"

#
BRAND="
      \ |  __| _ \  \  |
     .  |  _|  __/ |\/ |
    _|\_| _|  _|  _|  _|
"

HELP_MESSAGE="C/C++ run script v$NF_VERSION by NoxFly

Usage : nf <command> [options]

${CLR_LGRAY}# General${CLR_RESET}
--help              -h                  Show the command's version and its basic usage.
--version           -V                  Show the command's version.
--update            -U                  Download latest online version.
--verbose           -v                  Add this option to have details of the executed command.

info                                    Prints some informations that could help for issues.
global              <key> <value>       Set a global configuration preference for the script.

${CLR_LGRAY}# Project management${CLR_RESET}\n
patch                                   Patch the project's version.
minor                                   Minor the project's version.
major                                   Major the project's version.

set                 <key> <value>       Set a project's configuration key to a new value.
                                        This is for the project and config categories of the yml config file.

init                                    Initialize a new project. Create a configuration file.

generate            g [<type <path/name>]
                                        If no arguments provided, generates project's structure with a main file.
                                        Re-create missing folders.
                                        If type is provided, generate a new file of this type. See below.
${CLR_LGRAY}possible types:${CLR_RESET}
    class           c <class_name>      Creates a new class with its header and source files.

${CLR_LGRAY}# Package management${CLR_RESET}\n
list                l                   List all dependencies.
install             i                   Install all dependencies.

add                 <dependency_name> <package1_name> [<package2_name> ...]
                                        Add a package to a dependency.

remove              rm <package_name> [package_name...]
                                        Remove a package from a dependency.

uninstall           u <package_name> [package_name...]
                                        Uninstall a package from the computer.

${CLR_LGRAY}# Compilation and execution${CLR_RESET}\n
run                [parameters ...]     Compile and run the project.
build                                   Compile the project.
    --dev               -d              Compile code and run it in dev mode. It's debug mode with modified options.
    --debug             -g              Compile code and run it in debug mode.
    --release           -r              Compile code and run it in release mode.
    --force             -f              Make clear before compiling again.
    --static                            Build the project as static library.
    --shared                            Build the project as shared library.
                        -t              Compile the project with a specific number of threads (default to half of existing).
                                        \"max\" to get the maximum minus 1 thread available.
                                        A number to work with that number of threads."


# -----------------------------------------------------------
# -------------------------- MAIN ---------------------------
# -----------------------------------------------------------

# directly checks now if there is any argument that is "-v" or "--verbose"
# in that case, set VERBOSE to 1 and remove this argument only from the list of arguments
if [[ "$@" == *"-v"* ]] || [[ "$@" == *"--verbose"* ]]; then
    VERBOSE=1
    set -- "${@//"-v"}"
    set -- "${@//"--verbose"}"
fi

OUTPUT=$([ $VERBOSE -eq 1 ] && echo "/dev/stdout" || echo "/dev/null")

internal_configure_os

case $1 in
# General
    --help|-h) cmd_get_help;;
    --version|-V) cmd_get_version;;
    --update|-U) cmd_update_script;;

    info|infos) cmd_infos;;
    global) cmd_set_global_config $@;;

# Project management
    new) cmd_new_project $@;;
    generate|g) cmd_generate $@;;
    patch|minor|major) cmd_patch_version $@;;
    set) cmd_change_project_configuration $@;;

# Package management
    list|l) cmd_list_packages;;
    install|i) cmd_install_all_packages;;
    add) cmd_add_package $@;;
    remove|rm) cmd_remove_packages $@;;
    uninstall|u) cmd_uninstall_packages $@;;

# Compilation & Execution
    run) cmd_run $@;;
    build) cmd_compile $@;;
    clean) cmd_clean_project;;

    *) echo "Type $COMMAND_NAME --help to get more informations on how to use this command."; exit 1;;
esac

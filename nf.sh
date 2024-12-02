#!/bin/bash

# Author : NoxFly
# Copyrights 2021-2024

# No modification allowed without author's consent
# If you want to contribute, have a question or a fix,
# please create a Pull Request on the Github Repository
# at https://raw.githubusercontent.com/NoxFly/nfpm/

# ------------------ Helper ------------------

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
    if [ $VERBOSE -eq 1 -a $# -gt 0 ]; then
        echo -e "$@"
    fi
}

capitalize() {
    if [ -z "$1" ]; then
        echo
    fi

    echo "$1" | sed -r 's/(^| )([a-z])/\U\2/g' | tr -d ' '
}

load_config() {
    if [ ! -z "$CONFIG_LOADED" ]; then
        return
    fi

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
    P_SRC_DIR="./src"
    [[ $P_MODE -eq 0 ]] && P_INC_DIR="./include" || P_INC_DIR="$P_SRC_DIR"
    P_OUT_DIR="./bin"
    P_BUILD_DIR="./build"
    P_LIB_DIR="./libs"

    ensure_config_integrity

    local ext_suffix=""

    if [ "$P_LANG" == "cpp" ]; then
        ext_suffix="pp"
    fi

    P_SRC_EXT="c$ext_suffix"
    P_HDR_EXT="h$ext_suffix"
}

ensure_config_integrity() {
    # structure mode
    if [[ ! $P_MODE =~ ^(0|1)$ ]]; then
        echo "Invalid project mode. Supported modes are 0 and 1."
        exit 1
    fi

    # language
    if [[ ! $P_LANG =~ ^(c|cpp)$ ]]; then
        echo "Invalid project type. Supported types are c and cpp."
        exit 1
    fi

    # check language version
    if [ "$P_LANG" == "c" ]; then
        if [[ ! "$P_LANG_VERSION" =~ ^(89|99|11|17|23)$ ]]; then
            echo "Invalid C version. Supported versions are 89, 99, 11, 17, 23."
            exit 1
        fi
    else
        if [[ ! "$P_LANG_VERSION" =~ ^(03|11|14|17|20|23)$ ]]; then
            echo "Invalid C++ version. Supported versions are 03, 11, 14, 17, 20, 23."
            exit 1
        fi
    fi

    # guard
    if [[ ! "$P_GUARD" =~ ^(ifndef|pragma)$ ]]; then
        echo "Invalid guard. Supported guards are ifndef and pragma."
        exit 1
    fi
}

ensure_inside_project() {
    if [ ! -z "$INSIDE_PROJECT" ]; then
        return
    fi

    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "Error: No configuration file found in the current directory.\nCreate a new project thanks the '$COMMAND_NAME init' command."
        exit 1
    fi

    INSIDE_PROJECT="1"

    load_config
}

ensure_project_structure() {
    load_config

    if [ ! -d "$P_SRC_DIR" ] || [ $P_MODE -eq 0 -a ! -d "$P_INC_DIR" ]; then
        echo -e "There's no project's structure.\nTo create it, write '$COMMAND_NAME generate'"
        exit 1
    fi
}

# -----------------------------------------------------------


# ------------------ YML ------------------

cmd_init_project() {
    if [ -f "$CONFIG_FILE" ]; then
        echo "A project is already initialized in this directory."
        exit 0;
    fi

    local project_lang

    if [ -z "$1" ]; then
        if [ -z "$DEFAULT_INIT_LANG" ]; then
            # ask for C or CPP project
            read -p "Choose the project language (c/CPP): " project_lang

            if [ -z "$project_lang" ]; then
                project_lang="cpp"
            fi
        else
            project_lang="$DEFAULT_INIT_LANG"
        fi
    else
        project_lang="$1"
    fi

    if [ -z "$DEFAULT_INIT_LANG" ]; then
        echo -e "\nHINT: You can set the default language for project creation with '$COMMAND_NAME global lang <c/cpp>'"
        echo -e "      Thus, you won't be asked for the language anymore if you don't specify one.\n"
    fi


    # if no c or cpp, exit
    if [[ ! "$project_lang" =~ ^(c|cpp)$ ]]; then
        echo "Invalid language. Please choose c or cpp. Just hit Enter if it's cpp (default)."
        exit 1
    fi

    local lang_version
    [[  "$project_lang" == "c" ]] && lang_version=17 || lang_version=20

    # create file first
    touch $CONFIG_FILE

    # categories
    internal_create_config_category "project"
    internal_set_category_field_value "project" "name" "New Project"
    internal_set_category_field_value "project" "description" "No description provided."
    internal_set_category_field_value "project" "version" "1.0.0"
    internal_set_category_field_value "project" "author" ""
    internal_set_category_field_value "project" "url" ""
    internal_set_category_field_value "project" "license" ""

    internal_create_config_category "config"
    internal_set_category_field_value "config" "mode" 0
    internal_set_category_field_value "config" "type" "$project_lang"
    internal_set_category_field_value "config" "${project_lang}Version" $lang_version
    internal_set_category_field_value "config" "guard" "ifndef" # ifndef | pragma

    internal_create_config_category "dependencies"

    echo -e "New project initialized !\n"
    echo -e "You can customize your project's configuration in the $CONFIG_FILE file.\n"
    echo    "NOTE : Only modify what is in the 'project' section. Changing values from other sections may break the script."
    echo -e "       For project's configuration, you should use the script's commands.\n"

    load_config
    cmd_create_base_project
}

internal_create_config_category() {
    local category_name=$1
    if ! grep -q " $category_name:" $CONFIG_FILE; then
        echo -e "$category_name:\n" >> $CONFIG_FILE
    fi
}

internal_set_category_field_value() {
    local category_name=$1
    local field_name=$2
    local field_value=$3

    if grep -q "^$category_name:" $CONFIG_FILE; then
        if grep -q "^  $field_name:" $CONFIG_FILE; then
            # Use a different delimiter (|) to avoid conflicts with special characters in field_value
            sed -i "s|^  $field_name:.*|  $field_name: $field_value|" $CONFIG_FILE
        else
            # Append the new field to the end of the existing category
            awk -v cat="$category_name" -v field="$field_name" -v value="$field_value" '
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
            ' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
        fi
    else
        # Create the category and add the field
        awk -v cat="$category_name" -v field="$field_name" -v value="$field_value" '
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
        ' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    fi
}

internal_get_category_field_value() {
    local category_name=$1
    local field_name=$2

    awk -v cat="$category_name" -v field="$field_name" '
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
    ' "$CONFIG_FILE"
}

# -----------------------------------------------------------

# ------------------ FOLDERS / FILES MANAGEMENT ------------------

cmd_generate() {
    local type=$1
    local path_and_name=$2

    if [ -z "$type" ]; then
        cmd_create_base_project
        exit 0
    fi

    case "$type" in
        "class"|"c")
            cmd_create_class $path_and_name
            ;;
        *)
            echo "Invalid type. Supported types are project and class."
            exit 1
            ;;
    esac
}

cmd_create_base_project() {
    echo "Creating structure..."
    
    local i=0

    create_dir() {
        local dir="$1"
        if [ ! -d "$dir" ]; then
            mkdir "$dir"
            [ $? -eq 0 ] && log "Created $dir folder"
            ((i=i+1))
        fi
    }

    create_dir "$P_SRC_DIR"
    [ $P_MODE -eq 0 ] && create_dir "$P_INC_DIR"
    create_dir "$P_OUT_DIR"
    create_dir "$P_BUILD_DIR"
    create_dir "$P_LIB_DIR"

    local main_file="$P_SRC_DIR/main.$P_SRC_EXT"
    local cmake_file="CMakeLists.txt"
    local gitignore_file=".gitignore"
    
    if [ ! -f "$main_file" ]; then
        touch "$main_file"
        internal_get_main_code > "$main_file"
        [ $? -eq 0 ] && log "Created main file"
        ((i=i+1))
    fi

    if [ ! -f "$cmake_file" ]; then
        echo -e "$(internal_cmake_content)" > "CMakeLists.txt"
        internal_update_cmake_config
        [ $? -eq 0 ] && log "Created $cmake_file"
        ((i=i+1))
    fi

    if [ ! -f "$gitignore_file" ]; then
        internal_create_gitignore
        [ $? -eq 0 ] && log "Created $gitignore_file"
        ((i=i+1))
    fi

    [ $i -eq 0 ] && log "No changes made" || echo "Done"
}

cmd_create_class() {
    if [[ ! "$1" =~ ^([a-zA-Z0-9_\-]+/)*[a-zA-Z_][a-zA-Z0-9_]+$ ]]; then
        echo "Error : class name must only contains alphanumeric characters and underscores"
        exit 1
    fi

    echo "Creating class $1..."
    
    if [ ! -d "$P_SRC_DIR" ]; then
        echo -e "Project's structure not created yet.\nAborting."
        cmd_get_help
        exit 2
    fi

    local className=${1##*/}
    local path=${1%/*}
    local srcPath
    local incPath

    if [ "$className" == "$path" ]; then
        path=''
    else
        path="$path/"
    fi

    if [ $P_MODE -eq 0 ]; then
        mkdir -p "$P_SRC_DIR/$path"
        mkdir -p "$P_INC_DIR/$path"

        srcPath="$P_SRC_DIR/$path$className.$P_SRC_EXT"
        incPath="$P_INC_DIR/$path$className.$P_HDR_EXT"
    else
        local folderPath="$P_SRC_DIR/$path$className"
        mkdir -p $folderPath

        srcPath="$folderPath/$className.$P_SRC_EXT"
        incPath="$folderPath/$className.$P_HDR_EXT"
    fi

    if [ -f "$srcPath" ] || [ -f "$incPath" ]; then
        echo "A file with this name already exists."
        echo "Aborting"
        exit 3
    fi

    touch $srcPath
    touch $incPath
    internal_get_src_code $className > $srcPath
    internal_get_header_code $className > $incPath
    
    echo "Done"
}

internal_get_src_code() {
    internal_copyrights

    if [ "$P_SRC_EXT" == "c" ]; then
        echo -e -n "#include \"$1.$P_HDR_EXT\"\n\n"
    else
        echo -e -n "#include \"$1.$P_HDR_EXT\"\n\n$1::$1() {\n\n}\n\n$1::~$1() {\n\n}"
    fi
}

internal_get_header_code() {
    local guard_top
    local guard_bottom
    local pp=${P_HDR_EXT^^}

    if [ "$P_GUARD" == "ifndef" ]; then
        guard_top="#ifndef ${1^^}_$pp\n#define ${1^^}_$pp\n\n"
        guard_bottom="\n\n#endif // ${1^^}_$pp"
    else
        guard_top="#pragma once\n\n"
        guard_bottom=""
    fi

    internal_copyrights

    echo -e -n "$guard_top"

    if [ "$P_SRC_EXT" == "cpp" ]; then
        echo -e -n "class $1 {\n\tpublic:\n\t\t$1();\n\t\t~$1();\n};"
    fi

    echo -e -n "$guard_bottom"
}

internal_get_main_code() {
    internal_copyrights

    if [ "$P_SRC_EXT" == "cpp" ]; then
        echo -e -n "#include <iostream>\n\nint main(int argc, char **argv) {\n\t(void)argc;\n\t(void)argv;\n\tstd::cout << \"Hello World\" << std::endl;\n\treturn EXIT_SUCCESS;\n}"
    elif [ "$P_SRC_EXT" == "c" ]; then
        echo -e -n "#include <stdio.h>\n\nint main(int argc, char **argv) {\n\t(void)argc;\n\t(void)argv;\n\tprintf(\"Hello World \");\n\treturn 0;\n}"
    fi
}

internal_copyrights() {
    if [ -z "$P_AUTHOR" ]; then
        return
    fi

    year=$(date +%Y)
    year_month_day=$(date +%Y-%m-%d)

    echo -e -n "/**\n * @copyright (c) $year $P_AUTHOR\n"
    echo -e -n " * @date $year_month_day"

    if [ ! -z "$P_LICENSE" ]; then
        echo -e -n "\n * @license $P_LICENSE"
    fi

    echo -e -n "\n */\n\n"
}

# -----------------------------------------------------------


# ------------------ Package management ------------------

cmd_install_all_packages() {
    sudo apt-get update &> $OUTPUT

    local installed_success_count=0
    local installed_failed_count=0
    local in_dependencies=0
    local start_time=$(date_now)

    while IFS=: read -r dependency packages; do
        if [[ "$dependency" == "dependencies" ]]; then
            in_dependencies=1
            continue
        fi
        if [[ $in_dependencies -eq 1 && "$dependency" =~ ^[[:space:]]*$ ]]; then
            in_dependencies=0
        fi
        if [[ $in_dependencies -eq 1 ]]; then
            for package in $packages; do
                install_package $dependency $package
                installStatus=$?

                if [ $installStatus -eq 1 ]; then
                    installed_success_count=$((installed_success_count+1))
                elif [ $installStatus -eq -1 ]; then
                    installed_failed_count=$((installed_failed_count+1))
                fi
            done
        fi
    done < "$CONFIG_FILE"

    if [ $installed_failed_count -eq 0 ] && [ $installed_success_count -eq 0 ]; then
        echo "Up to date."
    fi

    local duration=$(get_formatted_duration $start_time)

    echo -e "\n$installed_success_count installed, $installed_failed_count failed in $duration."
}

cmd_install_package() {
    local package_name=$1
    local package=$2

    if dpkg -s $package &> $OUTPUT; then
        # echo "$package is already installed on the computer."
        return 0
    else
        sudo apt-get install -y $package &> $OUTPUT

        if [ $? -eq 0 ]; then
            echo "$package has been installed on the computer."
            return 1
        else
            echo "Failed to install $package."
            return -1
        fi
    fi
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
    ' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
}

cmd_add_package() {
    local dependency_name=$1
    shift
    local packages=("$@")
    local added_count=0
    local installed_success_count=0
    local installed_failed_count=0
    local start_time=$(date_now)

    # Step 1: Check if the key already exists in the dependencies list
    if grep -q "  $dependency_name:" $CONFIG_FILE; then
        # Step 1.a: Look for already present values for this key
        local existing_packages=$(grep "  $dependency_name:" $CONFIG_FILE | awk -F': ' '{print $2}')
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
    local all_existing_packages=$(awk '/^  / {print $2}' $CONFIG_FILE)
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
        if [ ! -z "$package" ]; then
            cmd_install_package $dependency_name $package
            local installStatus=$?

            if [ $installStatus -eq 1 ]; then
                installed_success_count=$((installed_success_count+1))
            elif [ $installStatus -eq -1 ]; then
                installed_failed_count=$((installed_failed_count+1))
            fi

            if [ $installStatus -ne -1 ]; then
                new_packages+=($package)
                added_count=$((added_count+1))
                echo "$package added."
            fi
        fi
    done

    # Step 3: Add successfully installed packages to the dependencies list
    # Combine existing and new packages
    local combined_packages="$existing_packages ${new_packages[*]}"
    internal_set_category_field_value "dependencies" "$dependency_name" "$combined_packages"

    # Step 4: Sort the dependencies lines
    internal_sort_dependencies

    local duration=$(get_formatted_duration $start_time)

    echo -e "\n$added_count added, $installed_success_count installed, $installed_failed_count failed in $duration."
}

cmd_uninstall_package() {
    local quiet=$1
    shift
    local package_count=0
    local dependency_count=$#
    local start_time=$(date_now)

    for package_name in "$@"; do
        if grep -q "  $package_name:" $CONFIG_FILE; then
            local packages=$(grep -A 1 "  $package_name:" $CONFIG_FILE | tail -n 1 | awk -F': ' '{print $2}')
            for package in $packages; do
                sudo apt-get remove -y $package &> $OUTPUT
                echo "$package has been uninstalled from the computer."
                package_count=$((package_count+1))
            done
        else
            echo "$package_name is not in the dependency list of this project."
        fi
    done

    if [ $quiet -eq 0 ]; then
        local duration=$(get_formatted_duration $start_time)
        echo -e "\nUninstalled $package_count packages for $dependency_count dependencies in $duration."
    fi
}

cmd_remove_package() {
    for package_name in "$@"; do
        if ! grep -q "  $package_name:" $CONFIG_FILE; then
            echo "$package_name is not in the dependency list of this project."
            continue
        fi

        sed -i "/  $package_name:/d" $CONFIG_FILE
        echo "$package_name has been removed from the project."

        local uninstall
        read -p "Do you also want to uninstall $package_name from the computer? (y/N): " uninstall
        if [[ $uninstall =~ ^[Yy]$ ]]; then
            cmd_uninstall_package 1 $package_name
        fi
    done
}

cmd_list_packages() {
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
    in_dependencies {
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
    ' "$CONFIG_FILE"
}

# -----------------------------------------------------------


# ------------------ Project versioning ------------------

cmd_patch_version() {
    local version=$1
    local current_version=$(internal_get_category_field_value "project" "version")

    if [[ "$current_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        IFS='.' read -r -a version_parts <<< "$current_version"
        local major=${version_parts[0]}
        local minor=${version_parts[1]}
        local patch=${version_parts[2]}

        case $version in
            "major")
                major=$((major+1))
                minor=0
                patch=0
                ;;
            "minor")
                minor=$((minor+1))
                patch=0
                ;;
            "patch")
                patch=$((patch+1))
                ;;
        esac

        local new_version="$major.$minor.$patch"
        P_VERSION=$new_version
        internal_set_category_field_value "project" "version" "$new_version"
        internal_update_cmake_config
        echo -e "Version updated to ${CLR_GREEN}$new_version.${CLR_RESET}"
    else
        echo "Invalid version format."
    fi
}

# -----------------------------------------------------------

# ------------------ Project configuration ------------------

cmd_change_project_configuration() {
    local key=$1
    shift
    local value=$@

    if [ -z "$key" ] || [ -z "$value" ]; then
        echo "Usage: $COMMAND_NAME set <key> <value>"
        exit 1
    fi

    case $key in
        "name")
            internal_set_project_name $value
            ;;
        "description")
            internal_set_project_description $value
            ;;
        "author")
            internal_set_project_author $value
            ;;
        "url")
            internal_set_project_url $value
            ;;
        "license")
            internal_set_project_license $value
            ;;
        "cppVersion")
            internal_set_cpp_version $value
            ;;
        "cVersion")
            internal_set_c_version $value
            ;;
        "mode")
            internal_set_project_mode $value
            ;;
        "guard")
            internal_set_guard $value
            ;;
        *)
            echo "Invalid key."
            exit 1
            ;;
    esac
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
        echo "Project is a C project. Cannot set C++ version."
        exit 1
    fi

    local version=$1

    # ensure version is one of the supported versions :
    # 03, 11, 14, 17, 20, 23
    if [[ ! "$version" =~ ^(03|11|14|17|20|23)$ ]]; then
        echo "Invalid C++ version. Supported versions are 03, 11, 14, 17, 20, 23."
        exit 1
    fi

    P_LANG_VERSION=$version
    internal_set_category_field_value "config" "cppVersion" $version
    internal_update_cmake_config
    echo "C++ version set to $version."
}

internal_set_c_version() {
    if [ "$P_LANG" == "cpp" ]; then
        echo "Project is a C++ project. Cannot set C version."
        exit 1
    fi

    local version=$1

    # ensure version is one of the supported versions :
    # 89, 99, 11, 17, 23
    if [[ ! "$version" =~ ^(89|99|11|17|23)$ ]]; then
        echo "Invalid C version. Supported versions are 89, 99, 11, 17, 23."
        exit 1
    fi

    P_LANG_VERSION=$version
    internal_set_category_field_value "config" "cVersion" $version
    internal_update_cmake_config
    echo "C version set to $version."
}

internal_set_project_mode() {
    local mode=$1

    ensure_project_structure

    # ensure mode is one of the supported modes :
    # 0, 1
    if [[ ! $mode =~ ^(0|1)$ ]]; then
        echo "Invalid project mode. Supported modes are 0 and 1."
        exit 1
    fi

    if [ $mode -eq $P_MODE ]; then
        echo "Project mode is already set to $mode."
        exit 0
    fi

    internal_swap_structure $mode

    if [ $? -ne 0 ]; then
        echo "Failed to change the project mode."
        exit 1
    fi

    internal_set_category_field_value "config" "mode" $mode

    echo "Project mode set to $mode."
}

internal_set_guard() {
    local guard=$1

    # ensure guard is one of the supported guards :
    # ifndef, pragma
    if [[ ! "$guard" =~ ^(ifndef|pragma)$ ]]; then
        echo "Invalid guard. Supported guards are ifndef and pragma."
        exit 1
    fi

    internal_set_category_field_value "config" "guard" "$guard"
    echo "Guard set to $guard."
}

internal_update_cmake_config() {
    load_config

    local f="CMakeLists.txt"
    local pgname=$(capitalize "$P_NAME")
    local lang=${P_LANG^^}
    
    if [ "$lang" == "CPP" ]; then
        lang="CXX"
    fi

    local project_line="project($pgname VERSION $P_VERSION DESCRIPTION \"$P_DESC\" HOMEPAGE_URL \"$P_HOMEPAGE_URL\" LANGUAGES $lang)"
    sed -i "/^project(/c\\$project_line" "$f"
    
    sed -i "s/\(set(PGNAME \"\)[^\"]*\(\"\)/\1$pgname\2/" "$f"
    sed -i "s/\(set(LANGVERSION \"\)[^\"]*\(\"\)/\1$P_LANG_VERSION\2/" "$f"
    sed -i "s/\(set(SRCEXT \"\)[^\"]*\(\"\)/\1$P_SRC_EXT\2/" "$f"
    sed -i "s/\(set(HDREXT \"\)[^\"]*\(\"\)/\1$P_HDR_EXT\2/" "$f"
}


# -----------------------------------------------------------

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
        [[ "$dirs" =~ ^(\.\/?|\.\/) ]] && dirs="" # remove ./ from the path if present
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
        mv "./include/$relative_header" "$new_filepath.$P_HDR_EXT" || return 1

        for src_ext in "${existing_src_files[@]}"; do
            mv "$src_filepath_base.$src_ext" "$new_filepath.$src_ext"
        done
    done

    # Supprime le répertoire include
    rm -r "$inc_dir" || return 1
    return 0
}

internal_swap_structure() {
    local src_dir="./src"
    local inc_dir="./include"

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
        echo -e "${CLR_RED}Failed to change the structure${CLR_RESET}"
        restore_backup
    else
        echo -e "${CLR_GREEN}Successfully changed the structure${CLR_RESET}"
    fi

    # Clean up backup
    delete_backup

    return $r
}

internal_update_library_include() {
	log "${CLR_DGRAY}Updating shared include folder... "

    local base_inc_path="$P_OUT_DIR/lib/include/$P_NAME/"
    local file

    mkdir -p $base_inc_path

    rsync -avq --delete --prune-empty-dirs --include="*/" --include="*.{c,cpp,inl}" --exclude="*" "$P_INC_DIR/" "$base_inc_path"

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

            if [[ $location == '' ]]; then
                location='/'
            fi

            local relative=$(realpath --relative-to="$file" "$location")

            local search="#include \"$dep\""
            local replacement="#include \"${relative#'../'}\""

            sed -i -e "s|$search|$replacement|" "$file"
        done
    done

    log "Done."
}

internal_create_gitignore() {
    local ignore_list=(
        "# Ignore build files"
        "build/"
        "bin/"
        "lib/"
        "out/"
        "CMakeFiles/"
        "CMakeCache.txt"
        "cmake_install.cmake"
        "Makefile"
    );

    printf "%s\n" "${ignore_list[@]}" > ".gitignore"
}

internal_cmake_content() {
    local cmake_content="Y21ha2VfbWluaW11bV9yZXF1aXJlZChWRVJTSU9OIDMuMTIpCgojIFByb2plY3QgbmFtZSBhbmQgdmVyc2lvbgpwcm9qZWN0KE15UHJvamVjdCkKCiMgU2V0IGRlZmF1bHQgdmFsdWVzIGZvciB2YXJpYWJsZXMKIyBJbmplY3RlZCBieSB0aGUgc2NyaXB0CnNldChQR05BTUUgIk15UHJvamVjdCIgQ0FDSEUgU1RSSU5HICJQcm9ncmFtIG5hbWUiKQpzZXQoU1JDRElSICJzcmMiIENBQ0hFIFNUUklORyAiU291cmNlIGRpcmVjdG9yeSIpCnNldChJTkNESVIgImluY2x1ZGUiIENBQ0hFIFNUUklORyAiSW5jbHVkZSBkaXJlY3RvcnkiKQpzZXQoT1VUICJiaW4iIENBQ0hFIFNUUklORyAiT3V0cHV0IGRpcmVjdG9yeSIpCnNldChCVUlMRERJUiAiYnVpbGQiIENBQ0hFIFNUUklORyAiQnVpbGQgZGlyZWN0b3J5IikKc2V0KExBTkdWRVJTSU9OICIxNyIgQ0FDSEUgU1RSSU5HICJMYW5ndWFnZSB2ZXJzaW9uIikKc2V0KFNSQ0VYVCAiY3BwIiBDQUNIRSBTVFJJTkcgIlNvdXJjZSBmaWxlIGV4dGVuc2lvbiIpCnNldChIRFJFWFQgImhwcCIgQ0FDSEUgU1RSSU5HICJIZWFkZXIgZmlsZSBleHRlbnNpb24iKQpzZXQoT1MgIiIgQ0FDSEUgU1RSSU5HICJPcGVyYXRpbmcgc3lzdGVtIikKc2V0KE1BQ1JPICIiIENBQ0hFIFNUUklORyAiTWFjcm8gZGVmaW5pdGlvbnMiKQoKIwpzZXQoT1VUICIuLi8ke09VVH0iKQoKIyBTZXQgb3V0cHV0IGRpcmVjdG9yaWVzCnNldChDTUFLRV9SVU5USU1FX09VVFBVVF9ESVJFQ1RPUlkgJHtPVVR9KQpzZXQoQ01BS0VfTElCUkFSWV9PVVRQVVRfRElSRUNUT1JZICR7T1VUfS9saWIpCnNldChDTUFLRV9BUkNISVZFX09VVFBVVF9ESVJFQ1RPUlkgJHtPVVR9L2xpYikKCiMgU2V0IGNvbXBpbGVyIGZsYWdzCmlmKCR7U1JDRVhUfSBTVFJFUVVBTCAiYyIpCiAgICBzZXQoQ01BS0VfQ19TVEFOREFSRCAke0xBTkdWRVJTSU9OfSkKICAgIHNldChDTUFLRV9DX0ZMQUdTICIke0NNQUtFX0NfRkxBR1N9IC1XZXJyb3IgLVdhbGwgLVdleHRyYSAke01BQ1JPfSIpCmVsc2UoKQogICAgc2V0KENNQUtFX0NYWF9TVEFOREFSRCAke0xBTkdWRVJTSU9OfSkKICAgIHNldChDTUFLRV9DWFhfRkxBR1MgIiR7Q01BS0VfQ1hYX0ZMQUdTfSAtV2Vycm9yIC1XYWxsIC1XZXh0cmEgJHtNQUNST30iKQplbmRpZigpCgojIEluY2x1ZGUgZGlyZWN0b3JpZXMKaW5jbHVkZV9kaXJlY3Rvcmllcygke0lOQ0RJUn0pCgojIEZpbmQgc291cmNlIGZpbGVzCmZpbGUoR0xPQl9SRUNVUlNFIFNPVVJDRVMgIiR7U1JDRElSfS8qLiR7U1JDRVhUfSIpCgojIEFkZCBleGVjdXRhYmxlCmFkZF9leGVjdXRhYmxlKCR7UEdOQU1FfSAke1NPVVJDRVN9KQoKIyBTZXQgdGFyZ2V0IHByb3BlcnRpZXMKc2V0X3RhcmdldF9wcm9wZXJ0aWVzKCR7UEdOQU1FfSBQUk9QRVJUSUVTCiAgICBSVU5USU1FX09VVFBVVF9ESVJFQ1RPUlkgJHtPVVR9CiAgICBBUkNISVZFX09VVFBVVF9ESVJFQ1RPUlkgJHtPVVR9L2xpYgogICAgTElCUkFSWV9PVVRQVVRfRElSRUNUT1JZICR7T1VUfS9saWIKKQoKIyBMaW5rIGxpYnJhcmllcwp0YXJnZXRfbGlua19saWJyYXJpZXMoJHtQR05BTUV9ICR7TElCU30pCgojIEhhbmRsZSBkaWZmZXJlbnQgYnVpbGQgdHlwZXMKaWYoTElCKQogICAgaWYoJHtMSUJ9IFNUUkVRVUFMICJTSEFSRUQiKQogICAgICAgIHNldF90YXJnZXRfcHJvcGVydGllcygke1BHTkFNRX0gUFJPUEVSVElFUwogICAgICAgICAgICBPVVRQVVRfTkFNRSAiJHtQR05BTUV9JHtMSUJfU0hBUkVEX0VYVH0iCiAgICAgICAgICAgIFBPU0lUSU9OX0lOREVQRU5ERU5UX0NPREUgT04KICAgICAgICApCiAgICAgICAgdGFyZ2V0X2NvbXBpbGVfb3B0aW9ucygke1BHTkFNRX0gUFJJVkFURSAtZlBJQykKICAgICAgICB0YXJnZXRfbGlua19vcHRpb25zKCR7UEdOQU1FfSBQUklWQVRFIC1zaGFyZWQgLWZQSUMpCiAgICBlbHNlaWYoJHtMSUJ9IFNUUkVRVUFMICJTVEFUSUMiKQogICAgICAgIHNldF90YXJnZXRfcHJvcGVydGllcygke1BHTkFNRX0gUFJPUEVSVElFUwogICAgICAgICAgICBPVVRQVVRfTkFNRSAiJHtQR05BTUV9JHtMSUJfU1RBVElDX0VYVH0iCiAgICAgICAgKQogICAgZWxzZSgpCiAgICAgICAgbWVzc2FnZShGQVRBTF9FUlJPUiAiSW5jb3JyZWN0IExJQiB2YWx1ZSIpCiAgICBlbmRpZigpCmVsc2UoKQogICAgaWYoREVCVUcpCiAgICAgICAgc2V0KENNQUtFX0JVSUxEX1RZUEUgRGVidWcpCiAgICAgICAgdGFyZ2V0X2NvbXBpbGVfb3B0aW9ucygke1BHTkFNRX0gUFJJVkFURSAtZykKICAgIGVsc2UoKQogICAgICAgIHNldChDTUFLRV9CVUlMRF9UWVBFIFJlbGVhc2UpCiAgICBlbmRpZigpCmVuZGlmKCkKCiMgSGFuZGxlIE9TLXNwZWNpZmljIHNldHRpbmdzCmlmKCR7T1N9IFNUUkVRVUFMICJNQUNPUyIpCiAgICBzZXRfdGFyZ2V0X3Byb3BlcnRpZXMoJHtQR05BTUV9IFBST1BFUlRJRVMKICAgICAgICBPVVRQVVRfTkFNRSAiJHtQR05BTUV9LmFwcCIKICAgICkKZWxzZWlmKCR7T1N9IFNUUkVRVUFMICJXSU5ET1dTIikKICAgIHNldF90YXJnZXRfcHJvcGVydGllcygke1BHTkFNRX0gUFJPUEVSVElFUwogICAgICAgIE9VVFBVVF9OQU1FICIke1BHTkFNRX0uZXhlIgogICAgKQplbmRpZigpCgojIEluc3RhbGxhdGlvbiBydWxlcwppbnN0YWxsKFRBUkdFVFMgJHtQR05BTUV9IERFU1RJTkFUSU9OICR7T1VUfSkKaW5zdGFsbChESVJFQ1RPUlkgJHtJTkNESVJ9IERFU1RJTkFUSU9OICR7T1VUfS9pbmNsdWRlKQoKIyBDdXN0b20gY2xlYXIgY29tbWFuZAphZGRfY3VzdG9tX3RhcmdldChjbGVhcgogICAgQ09NTUFORCAke0NNQUtFX0NPTU1BTkR9IC1FIHJlbW92ZV9kaXJlY3RvcnkgJHtCVUlMRERJUn0KICAgIENPTU1BTkQgJHtDTUFLRV9DT01NQU5EfSAtRSBlY2hvICJBbGwgb2JqZWN0cyByZW1vdmVkIgopCgojIEN1c3RvbSBidWlsZCBjb21tYW5kCmFkZF9jdXN0b21fdGFyZ2V0KGJ1aWxkIEFMTAogICAgREVQRU5EUyAke1BHTkFNRX0KKQo="
    echo -e "$cmake_content" | base64 --decode
}

cmd_compile() {
    if [ -z "$PREPARED" ]; then
        internal_prepare_build_run $@
    fi

    local lib=""

    if [[ "$X_RULE" =~ ^(static|shared)$ ]]; then
        lib="-D \"LIB=${X_MODE^^}\" \\n"
    fi

    local start_time=$(date_now)

    CMAKE_CMD="cmake -S . -B $P_BUILD_DIR \
        $lib
        -D \"${X_MODE^^}=1\" \
        -D \"PGNAME=$X_EXECUTABLE\" \
        -D \"SRCDIR=$P_SRC_DIR\" \
        -D \"INCDIR=$P_INC_DIR\" \
        -D \"OUT=$P_OUT_DIR\" \
        -D \"BUILDDIR=$P_BUILD_DIR\" \
        -D \"LANGVERSION=$P_LANG_VERSION\" \
        -D \"SRCEXT=$P_SRC_EXT\" \
        -D \"HDREXT=$P_HDR_EXT\" \
        -D \"OS=$X_OS\" \
        -D \"MACRO=$X_MACRO\" \
        -D \"VERBOSE=$VERBOSE\""

    eval $CMAKE_CMD &> $OUTPUT

    local cmake_result=$?
    local cmake_duration=$(get_formatted_duration $start_time)

    if [ $cmake_result -ne 0 ]; then
        echo -e "${CLR_RED}Generating Makefile failed in $duration${CLR_RESET}"
        exit 1
    fi

    echo -e "${CLR_GREEN}Makefile generated in $cmake_duration${CLR_RESET}"

    middle_time=$(date_now)

    make -C $P_BUILD_DIR &> $OUTPUT

    local make_result=$?
    local make_duration=$(get_formatted_duration $middle_time)
    local total_time=$(get_formatted_duration $start_time)

    if [ $make_result -ne 0 ]; then
        echo -e "${CLR_RED}Compilation failed in $make_duration${CLR_RESET}"
        exit 1
    fi

    echo -e "${CLR_GREEN}Compilation succeed in $make_duration${CLR_RESET}"
    echo -e "${CLR_DGRAY}Total compilation time : $total_time${CLR_RESET}"

    return 0
}

cmd_run() {
    if [ -z "$PREPARED" ]; then
        internal_prepare_build_run $@
    fi

	echo -e -n "${CLR_DGRAY}"
    cmd_compile
    local res=$?
	echo -e -n "${CLR_RESET}"

    if [ $res -ne 0 ]; then
        exit 1
    fi

    if [ "$X_RULE" == "shared" ]; then
        internal_update_library_include
    fi

    if [ $RUN_AFTER_COMPILE -eq 0 ]; then
        exit 0
    fi

    echo

    log "----- Executing ${X_SUBMODE^^} mode -----\n\n"

    # print in which folder we currently are
    cd "$P_OUT_DIR/"

    if [ "$X_SUBMODE" == "debug" ]; then
        gdb ./$X_EXECUTABLE$X_PRGM_EXT $@
    else
        ./$X_EXECUTABLE$X_PRGM_EXT $@
    fi

    echo
}

internal_prepare_build_run() {
    PREPARED="1"

    local i
    local j=0
    local hasClean=0
    local hasMode=0

    X_EXECUTABLE=$(capitalize "$P_NAME")
    X_MODE="debug"
    X_SUBMODE="dev"
    X_RULE="build"

    for i in 1 2 3; do
        if [ $i -le $# ]; then
            case ${!i} in
                "-d"|"-g"|"-r"|"--debug"|"--release"|"--dev"|"--static"|"--shared")
                ((j=j+1))

                if [[ hasMode -eq 0 ]]; then
                    hasMode=1
                    X_RULE="build"

                    case ${!i} in
                        "-g"|"--debug")
                            X_MODE="debug"
                            X_SUBMODE="debug";;

                        "-d"|"--dev")
                            X_MODE="debug"
                            X_SUBMODE="dev";;

                        "-r"|"--release")
                            X_MODE="release"
                            X_SUBMODE="release";;

                        "--static")
                            X_MODE="debug"
                            X_RULE="static"
                            RUN_AFTER_COMPILE=0;;

                        "--shared")
                            X_MODE="debug"
                            X_RULE="shared"
                            RUN_AFTER_COMPILE=0;;
                    esac
                fi;;

                "-f"|"--force")
                    ((j=j+1))

                    if [[ hasClean -eq 0 ]]; then
                        hasClean=1
                    fi;;
            esac
        fi
    done

    while ((j > 0)); do
        shift
        ((j=j-1))
    done

    case "$OSTYPE" in
        "linux"*)
            X_PRGM_EXT=""
            X_OS="LINUX";;
        "darwin"*)
            X_PRGM_EXT=".app"
            X_OS="MACOS";;
        "cygwin"|"msys"|"win32")
            X_PRGM_EXT=".exe"
            X_OS="WINDOWS";;
    esac

    if [ ! -z "$X_OS" ]; then
        X_MACRO="-D$X_OS"
    fi
    
    X_MACRO="$X_MACRO -D${X_MODE^^}"
    # [[ X_RULE == 'build' ]] &&  X_MACRO="-D${X_MODE^^}" || X_MACRO=""

    # clean to rebuild everything
    if [[ hasClean -eq 1 && -f "Makefile" ]]; then
        [[ $VERBOSE -eq 0 ]] && make clear 1>/dev/null || make clear
    fi
}

cmd_clean_project() {
    if [ -d "$P_BUILD_DIR" ]; then
        rm -r "$P_BUILD_DIR"/*
    fi

    echo "Project cleaned."
}


# -----------------------------------------------------------


# --------------------- Script section ----------------------

cmd_update_script() {
    sudo wget -q -O "$SCRIPT_PATH" "$UPDATE_URL"
    local r=$?
    VERSION=${VERSION:-0.1}

    if [ $r -eq 0 ]; then
        newVersion="$(grep -Eo 'VERSION=[0-9]+\.[0-9]+' $SCRIPT_PATH | cut -d'=' -f2)"
        
        if [ "$VERSION" == $newVersion ]; then
            echo "Already on latest version ($VERSION)."
        else
            echo "v$VERSION -> v$newVersion"
            echo -e "${CLR_GREEN}Successfully updated${CLR_RESET}"
        fi
    else
        echo -e "${CLR_RED}Failed to update${CLR_RESET}"
    fi

    exit 0
}

cmd_get_help() {
    echo -e "$HELP_MESSAGE"
}

cmd_set_global_config() {
    local key=$1
    local value=$2

    if [ -z "$key" ] || [ -z "$value" ]; then
        echo "Usage: $COMMAND_NAME global <key> <value>"
        exit 1
    fi

    case $key in
        "lang")
            internal_set_default_init_lang $value
            ;;
        *)
            echo "Invalid key."
            exit 1
            ;;
    esac
}

internal_set_default_init_lang() {
    if [[ ! "$1" =~ ^(c|cpp)$ ]]; then
        echo -e "${CLR_RED}Invalid language. Supported languages are c and cpp.${CLR_CLEAR}"
        exit 1
    fi

    # replace in the script directly, with the sed command
    sudo sed -i "s/DEFAULT_INIT_LANG=\"$DEFAULT_INIT_LANG\"/DEFAULT_INIT_LANG=\"$1\"/" "$SCRIPT_PATH"

    if [ $? -ne 0 ]; then
        echo -e "${CLR_RED}Failed to set default language for project initialization.${CLR_CLEAR}"
        exit 1
    fi

    echo -e "${CLR_GREEN}Default language for project initialization set to $1.${CLR_CLEAR}"
}

cmd_get_version() {
    echo -e "v$VERSION"
}


# -----------------------------------------------------------

# Global variables
VERSION=1.0.0

# Get the absolute path of the script's directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_PATH="$0"
COMMAND_NAME=$(basename "$0" | sed 's/\.[^.]*$//')

CONFIG_FILE="project.yml"
UPDATE_URL="https://raw.githubusercontent.com/NoxFly/nfpm/main/nf.sh"

#
DEFAULT_INIT_LANG=""

# By default, compile then run
RUN_AFTER_COMPILE=1
VERBOSE=0

# Colors
CLR_RESET="\033[0m"
CLR_RED="\033[0;31m"
CLR_GREEN="\033[0;32m"
CLR_DGRAY="\033[0;90m"
CLR_LGRAY="\033[0;37m"

#
HELP_MESSAGE="C/C++ run script v$VERSION by NoxFly

Usage : 

${CLR_LGRAY}# General${CLR_RESET}
--help              -h                  Show the command's version and its basic usage.
--version           -V                  Show the command's version.
--update            -U                  Download latest online version.
--verbose           -v                  Add this option to have details of the executed command.

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
    --shared                            Build the project as shared library."


# directly checks now if there is any argument that is "-v" or "--verbose"
# in that case, set VERBOSE to 1 and remove this argument only from the list of arguments
if [[ "$@" == *"-v"* ]] || [[ "$@" == *"--verbose"* ]]; then
    VERBOSE=1
    set -- "${@//"-v"}"
    set -- "${@//"--verbose"}"
fi

if [ $VERBOSE -eq 1 ]; then
    OUTPUT="/dev/stdout"
else
    OUTPUT="/dev/null"
fi


# ------------------ Commands ------------------

case $1 in
# General
    --help|-h)
        cmd_get_help
        ;;
    --version|-V)
        cmd_get_version
        ;;
    --update|-U)
        cmd_update_script
        ;;

    global)
        cmd_set_global_config $2 $3
        ;;

# Project management
    init)
        cmd_init_project $2
        ;;
    generate|g)
        ensure_inside_project
        shift
        cmd_generate $@
        ;;
    patch|minor|major)
        ensure_inside_project
        cmd_patch_version "$1"
        ;;
    set)
        ensure_inside_project
        load_config
        key=$2
        shift 2
        value=$@
        cmd_change_project_configuration "$key" "$value"
        ;;

# Package management
    install|i)
        ensure_inside_project
        cmd_install_all_packages
        ;;
    add)
        ensure_inside_project
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Usage: $COMMAND_NAME add <dependency_name> <package1_name> [<package2_name> ...]"
            exit 1
        fi
        dependency_name=$2
        shift 2
        cmd_add_package $dependency_name "$@"
        ;;
    remove|rm)
        ensure_inside_project
        if [ -z "$2" ]; then
            echo "Usage: $COMMAND_NAME remove <package_name> [package_name...]"
            exit 1
        fi
        shift
        cmd_remove_package "$@"
        ;;
    uninstall|u)
        ensure_inside_project
        if [ -z "$2" ]; then
            echo "Usage: $COMMAND_NAME uninstall <package_name> [package_name...]"
            exit 1
        fi
        shift
        cmd_uninstall_package 0 $@
        ;;
    list|l)
        ensure_inside_project
        cmd_list_packages
        ;;

# Compilation & Execution
    run)
        ensure_project_structure
        cmd_run $@
        ;;
    build)
        ensure_project_structure
        cmd_compile $@
        exit $?
        ;;

    clean)
        ensure_project_structure
        cmd_clean_project
        ;;

    *)
        echo "Type $COMMAND_NAME --help to get more informations on how to use this command."
        exit 1
        ;;
esac

exit 0
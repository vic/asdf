# bash strict mode
# read: https://github.com/tests-always-included/wick/blob/master/doc/bash-strict-mode.md
set -euo pipefail
IFS=$'\n\t'

# We shouldn't rely on the user's grep settings to be correct. If we set these
# here anytime asdf invokes grep it will be invoked with these options
# shellcheck disable=SC2034
GREP_OPTIONS="--color=never"
# shellcheck disable=SC2034
GREP_COLORS=

# the location of ASDF runtime
asdf_dir() {
  local base_dir
  base_dir="$(dirname "$(dirname "$(dirname "$0")")")"
  echo "${ASDF_DIR:-${base_dir}}"
}


# user customizable directory for installing
# plugins, shims and version managed tools
asdf_data_dir() {
  echo "${ASDF_DATA_DIR:-$(asdf_dir)}"
}


# user customizable filename for .tool-versions
asdf_tool_versions_filename() {
  echo "${ASDF_DEFAULT_TOOL_VERSIONS_FILENAME:-.tool-versions}"
}

# echoes filename only if it exists
asdf_file_exists() {
  local filename
  filename="$1"
  if [ -f "$filename" ]; then
    echo "$filename"
    return 0
  fi
  return 1
}

asdf_dir_exists() {
  local filename
  filename="$1"
  if [ -d "$filename" ]; then
    echo "$filename"
    return 0
  fi
  return 1
}

# finds a file from a base directory walking up until filesystem root
# echoes the first matching file
asdf_find_file_upwards() {
  local filename base_dir parent_dir
  filename="$1"
  base_dir="$2"
  while true; do
    asdf_file_exists "${base_dir}/${filename}" && return 0
    parent_dir=$(dirname "${base_dir}")
    if [ "${parent_dir}" = "${base_dir}" ]; then
      return 1
    fi
    base_dir=$parent_dir
  done
}

# finds the .tool-versions file from pwd or ($HOME/.tool-versions)
asdf_find_tool_versions_file() {
  local default filename
  filename=$(asdf_tool_versions_filename)
  default="${HOME}/$filename"
  asdf_find_file_upwards "$filename" "$(pwd)" || asdf_file_exists "$default"
}

asdf_local_config_file() {
  asdf_find_file_upwards ".asdfrc" "$(pwd)"
}

asdf_user_config_file() {
  local default
  default="$HOME/.asdfrc"
  asdf_file_exists "${ASDF_CONFIG_FILE:-${default}}"
}

asdf_default_config_file() {
  asdf_file_exists "$(asdf_dir)/defaults"
}

asdf_strip_comments() {
  sed -e 's/[ \t]*\#.*//g' | grep -v "^$"
}

asdf_read_config_value_from_file() {
  local result file key
  key="$1"
  file="$($2)"
  if [ -f "$file" ]; then
    result=$(cat "$file" | asdf_strip_comments | grep -E "^\\s*$key\\s*=\\s*" | head | awk -F '=' '{print $2}' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    if [ -n "$result" ]; then
      echo "$result"
      return 0
    fi
  fi
  return 1
}

# Reads a config value from local .asdfrc or $HOME/.asdfrc or ASDF_DIR/defaults
asdf_read_config_value() {
  local key
  key=$1
  asdf_read_config_value_from_file "$key" asdf_local_config_file ||
    asdf_read_config_value_from_file "$key" asdf_user_config_file ||
    asdf_read_config_value_from_file "$key" asdf_default_config_file
}

asdf_current_from_env() {
  env | awk -F= '/^ASDF_[A-Z_]+_VERSION=/ {print $1" "$2}' |\
    sed -e "s/^ASDF_//" | sed -e "s/_VERSION / /" |\
    asdf_fn_xargs asdf_current_from_env_with_var
}

asdf_current_from_env_with_var() {
  local env_var="$1"
  local full_version="$2"
  local plugin_name="$(echo "$env_var" | tr "[:upper:]_" "[:lower:]-")"
  echo "$plugin_name $full_version # set by environment variable $env_var"
}

asdf_current_from_tool_versions() {
  local tools_file
  tools_file=$(asdf_find_tool_versions_file)
  if [ -f "$tools_file" ] ; then
    {
      cat "${tools_file}"
      echo "" # just make sure theres a trailing new line
    } | asdf_strip_comments | xargs -I TOOL_LINE echo "TOOL_LINE # set by ${tools_file}"
  fi
}

asdf_current_legacy_tool() {
  local tool="$1"
  asdf_shim_versions "${tool}" | awk '{print $1}' | uniq |\
    asdf_fn_xargs asdf_plugin_legacy_versions
}

# echoes the tools and versions specified in local .tool-versions file
# and also from ASDF_TOOL_VERSION variables.
# this does not takes into account legacy version files.
asdf_current_tools() {
  asdf_current_from_env
  asdf_current_from_tool_versions
}

# Given a plugin name and a full_version echoes the following lines
#
# install_type   # eg. version, ref, path, system
# version        # eg. 1.0 or system or path:PATH
# install_path   # eg. some dir or empty when system
asdf_full_version_info() {
  local plugin_name full_version
  plugin_name="$1"
  full_version="$2"
  case "${full_version}" in
    system)
      echo "system" # install_type
      echo "system" # version
      echo ""       # install_path
      ;;
    "ref:"*)
      local version
      version=$(echo "$full_version" | cut -d: -f 2-)
      echo "ref"           # install_type
      echo "$version"      # version
      asdf_installed_path "$plugin_name" "ref-$version"  # install_path
      ;;
    "path:"*)
      local path
      path=$(echo "$full_version" | cut -d: -f 2-)
      echo "path"   # install_type
      echo "$path"  # version
      echo "$path"  # install_path
      ;;
    *)
      echo "version"  # install_type
      echo "$full_version" # version
      asdf_installed_path "$plugin_name" "$full_version"  # install_path
      ;;
  esac
}

# Read each line from STDIN and calls the given $1 function with it as split arguments
asdf_fn_xargs() {
  local fn="${1}"
  shift
  local args=("${@+$@}")

  while IFS=$'' read -r line && [ -n "$line" ] ; do
    echo "$line" | {
      if IFS=$' ' read -r -a line_args && [ -n "$line_args" ]; then
        "$fn" "${args[@]+${args[@]}}" "${line_args[@]+${line_args[@]}}"
      fi
    }
  done
}

# Calls the given function only when stdin is empty
asdf_pipe_empty() {
  local fn="${1}"
  shift
  local args=("${@+$@}")
  local first_byte
  first_byte=$(dd bs=1 count=1 2>/dev/null | od -t o1 -A n | awk '{print$1}')
  if [ -z "$first_byte" ]; then
    "$fn" "${args[@]+${args[@]}}" # On empty pipe, call fn
  else
    # Just pipe data, dont call fn
    printf "\\${first_byte# }"
    cat
  fi
}

asdf_get_concurrency() {
  if command -v nproc > /dev/null 2>&1; then
    nproc
  elif command -v sysctl > /dev/null 2>&1 && sysctl hw.ncpu > /dev/null 2>&1; then
    sysctl -n hw.ncpu
  elif [ -f /proc/cpuinfo ]; then
    grep -c processor /proc/cpuinfo
  else
    echo "1"
  fi
}

asdf_installed_versions() {
  find "$(asdf_data_dir)/installs" -type d -mindepth 2 -maxdepth 2 -print0 |\
    xargs -0 -I INSTALL_DIR expr INSTALL_DIR : '.*/\([^/]*/[^/]*\)$' | tr '/' ' '
}

asdf_installed_path() {
  echo "$(asdf_data_dir)/installs/$1/$2"
}

asdf_installed_bin_paths() {
  local plugin_name full_version
  plugin_name="$1"
  full_version="$2"
  asdf_plugin_inside_env "$plugin_name" "$full_version" \
                         asdf_installed_bin_paths_inside_env
}

asdf_installed_bin_paths_inside_env() {
  local install_path="${install_path-}"
  local plugin_path="${plugin_path-}"
  {
    echo "${plugin_path}/shims"
    (asdf_plugin_run_inside_env "list-bin-paths" || echo "bin") |\
      tr ' ' $'\n' | awk "{print \"${install_path}/\"\$1}"
  } | (asdf_fn_xargs asdf_dir_exists || true)
}

asdf_installed_bin_files() {
  asdf_installed_bin_paths "$1" "$2" | xargs -I PATH find PATH -maxdepth 1 -perm -+x \( -type f -or -type l \)
}

asdf_assert_plugin_exists() {
  local plugin="$1"
  local path
  path="$(asdf_plugin_path "$plugin")" 
  if [ ! -d "$path" ]; then
    asdf_echo_error "No such plugin: $plugin"
    return 1
  fi
}


asdf_echo_error() {
  echo "$*" >&2
}

asdf_plugin_path() {
  echo "$(asdf_data_dir)/plugins/$1"
}

asdf_plugin_legacy_versions() {
  if [ "yes" != "$(asdf_read_config_value "legacy_version_file")" ]; then
    return 0
  fi

  local plugin=${1}
  local legacy_hook="$(asdf_plugin_path "$plugin")/bin/list-legacy-filenames"
  if [ -f "$legacy_hook" ]; then
    bash --noprofile --norc "$legacy_hook" | {
      IFS=' ' read -r -a legacy_filenames
      for legacy_filename in $legacy_filenames; do
        asdf_find_file_upwards "$legacy_filename" "$(pwd)" |\
          asdf_fn_xargs asdf_plugin_parse_legacy_file "$plugin"
      done
    }
  fi
}

asdf_plugin_parse_legacy_file() {
  local plugin=${1}
  local legacy_file=${2}
  local parse_hook="$(asdf_plugin_path "$plugin")/bin/parse-legacy-file"
  {
    if [ -f "$parse_hook" ]; then
      bash --noprofile --norc "$parse_hook" "$legacy_file"
    else
      cat "$legacy_file"
    fi
  } | asdf_strip_comments |\
    xargs -IVERSION echo "$plugin VERSION # set by legacy file ${legacy_file}" || true
}

asdf_plugin_inside_env() {
  local plugin_name full_version callback args

  plugin_name="${1}"
  full_version="${2}"
  callback="${3}"
  shift 3
  args=("${@+$@}")

  asdf_assert_plugin_exists "$plugin_name" || { return $?; }

  IFS=$'\n' read -d $'' -r install_type version install_path <<<"$(asdf_full_version_info "$plugin_name" "$full_version")" && [ -n "${version}" ] 

  case "$install_type" in
    system)
      "$callback" "${args[@]+${args[@]}}"
      return $?
      ;;
    ref)     ;;
    path)    ;;
    version) ;;
    *)
      asdf_echo_error "Unknown install_type: ${install_type} for ${plugin_name} ${full_version}"
      return 1
      ;;
  esac

  local plugin_path
  plugin_path=$(asdf_plugin_path "$plugin_name")

  # create a new subshell to avoid poluting parent env
  (
    ASDF_INSTALL_TYPE=$install_type
    ASDF_INSTALL_VERSION=$version
    ASDF_INSTALL_PATH=$install_path

    # shellcheck source=/dev/null
    [ -f "${plugin_path}/bin/exec-env" ] && source "${plugin_path}/bin/exec-env"
    "$callback" "${args[@]+${args[@]}}"
  )
}

asdf_run_hook_inside_env() {
  # vars inherited from asdf_plugin_inside_env
  local install_type="${install_type-}"
  local install_path="${install_path-}"
  local version="${version-}"
  local plugin_path="${plugin_path-}"

  local hook hook_args hook_cmd
  hook="$1"
  shift
  hook_args=("${@+$@}")

  if [ "system" = "$install_type" ]; then
    return 0 # dont do anything for system version
  fi

  hook_cmd="$(asdf_read_config_value "$hook")" || true
  if [ -n "$hook_cmd" ]; then
    asdf_hook_fun() {
      unset asdf_hook_fun
      ev'al' "${hook_cmd}" # explicit banned command
    }
    asdf_hook_fun "${hook_args[@]+${hook_args[@]}}"
    return $?
  fi
}

asdf_plugin_run_inside_env() {
  # vars inherited from asdf_plugin_inside_env
  local install_type="${install_type-}"
  local install_path="${install_path-}"
  local version="${version-}"
  local plugin_path="${plugin_path-}"

  local hook hook_args
  hook="${plugin_path}/bin/$1"
  shift
  hook_args=("${@+$@}")


  if [ "system" = "$install_type" ]; then
    return 0 # dont install system version
  fi

  [ -f "$hook" ] && (
    env ASDF_INSTALL_TYPE=$install_type \
        ASDF_INSTALL_VERSION=$version \
        ASDF_INSTALL_PATH=$install_path \
        ASDF_CONCURRENCY=$(asdf_get_concurrency) \
        bash --norc --noprofile "$hook" "${hook_args[@]+${hook_args[@]}}"
  )
}

# echoes all the plugins and versions for which there are shims
asdf_shim_all_versions() {
  local shims_dir
  shims_dir="$(asdf_data_dir)/shims"
  find "$shims_dir" -type f -mindepth 1 -maxdepth 1 |\
    xargs grep "# asdf-plugin: " | awk '{print $3" "$4}' | sort | uniq
}

# echoes the plugins and versions where a tool is available.
# that is it just prints the shim's asdf-plugin metadata.
asdf_shim_versions() {
  local tool
  tool=$(basename "$1")
  local shim_path
  shim_path="$(asdf_data_dir)/shims/${tool}"
  if [ -x "$shim_path" ]; then
    awk -F': ' '/^# asdf-plugin: /{print $2}' "$shim_path"
  else
    asdf_echo_error "unknown command: $tool. Perhaps you have to reshim?"
    return 1
  fi
}

asdf_shim_selectable_versions() {
  local tool="$1"
  asdf_shim_versions "${tool}" | tee >(awk '{print $1" system"}')
}

asdf_shim_selectable_tools() {
  local tool="$1"
  grep -h -f <(asdf_shim_selectable_versions "$tool") \
       <(asdf_current_tools | asdf_strip_comments) \
       <(asdf_current_legacy_tool "$tool" | asdf_strip_comments)
}

asdf_shim_select_version() {
  local tool="$1"
  asdf_shim_selectable_tools "$tool" | head -n 1
}

asdf_shim_error_none_selected() {
  local tool="$1"
  (
    echo "No version selected for command $tool"
    echo "Add one of the following to your .tool-versions file:"
    asdf_shim_versions "$tool"
  )>&2
  return 126
}

asdf_exec_path_inside_env() {
  local shim_name="$1"

  local plugin_name="${plugin_name-}"
  local full_version="${full_version-}"
  local version="${version-}"

  local path
  path=$({
          if [ "system" != "$version" ]; then
            asdf_installed_bin_paths "$plugin_name" "$full_version"
          fi
          echo "$PATH" | tr ':' $'\n' | grep -v "/shims"
        } | tr $'\n' ':' | sed -e 's/:$//')
  echo "$path"
}

asdf_which_executable_inside_env() {
  local cmd="$1"
  local executable
  executable="$(command -v "$cmd")"

  local full_version="${full_version-}"
  local plugin_path="${plugin_path-}"
  local install_path="${install_path-}"

  if [ "system" = "$full_version" ]; then
    echo "$executable"
    return 0
  fi

  if [ -x "${plugin_path}/bin/exec-path" ]; then
    local relative_path
    # shellcheck disable=SC2001
    relative_path=$(echo "$executable" | sed -e "s|${install_path}/||")
    relative_path="$("${plugin_path}/bin/exec-path" "$install_path" "$cmd" "$relative_path")"
    executable="$install_path/$relative_path"
  fi

  echo "$executable"
}

#!/usr/bin/env bats

load test_helpers

setup() {
  setup_asdf_dir
}

teardown() {
  clean_asdf_dir
}

@test "check_if_version_exists should exit with 1 if plugin does not exist" {
  run check_if_version_exists "foo" "1.0.0"
  [ "$status" -eq 1 ]
  [ "$output" = "No such plugin" ]
}

@test "check_if_version_exists should exit with 1 if version does not exist" {
  mkdir -p $ASDF_DIR/plugins/foo
  run check_if_version_exists "foo" "1.0.0"
  [ "$status" -eq 1 ]
  [ "$output" = "version 1.0.0 is not installed for foo" ]
}

@test "check_if_version_exists should be noop if version exists" {
  mkdir -p $ASDF_DIR/plugins/foo
  mkdir -p $ASDF_DIR/installs/foo/1.0.0
  run check_if_version_exists "foo" "1.0.0"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "check_if_version_exists should be noop if version is system" {
  mkdir -p $ASDF_DIR/plugins/foo
  run check_if_version_exists "foo" "system"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "check_if_plugin_exists should exit with 1 when plugin is empty string" {
  run check_if_plugin_exists
  [ "$status" -eq 1 ]
  [ "$output" = "No plugin given" ]
}

@test "check_if_plugin_exists should be noop if plugin exists" {
  mkdir -p $ASDF_DIR/plugins/foo_bar
  run check_if_plugin_exists "foo_bar"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "get_executable_path for system version should return system path" {
  mkdir -p $ASDF_DIR/plugins/foo
  run get_executable_path "foo" "system" "ls"
  [ "$status" -eq 0 ]
  [ "$output" = $(which ls) ]
}

@test "get_executable_path for system version should not use asdf shims" {
  mkdir -p $ASDF_DIR/plugins/foo
  touch $ASDF_DIR/shims/dummy_executable
  chmod +x $ASDF_DIR/shims/dummy_executable

  run which dummy_executable
  [ "$status" -eq 0 ]

  run get_executable_path "foo" "system" "dummy_executable"
  [ "$status" -eq 1 ]
}

@test "get_executable_path for non system version should return relative path from plugin" {
  mkdir -p $ASDF_DIR/plugins/foo
  mkdir -p $ASDF_DIR/installs/foo/1.0.0/bin
  executable_path=$ASDF_DIR/installs/foo/1.0.0/bin/dummy
  touch $executable_path
  chmod +x $executable_path

  run get_executable_path "foo" "1.0.0" "bin/dummy"
  [ "$status" -eq 0 ]
  [ "$output" = "$executable_path" ]
}

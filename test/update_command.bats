#!/usr/bin/env bats

load test_helpers

#. $(dirname "$BATS_TEST_DIRNAME")/lib/commands/update.sh

setup() {
  setup_asdf_dir
  install_dummy_plugin

  (
  cd $ASDF_DIR
  git init
  git remote add origin https://github.com/asdf-vm/asdf.git
  )

  PROJECT_DIR=$HOME/project
  mkdir $PROJECT_DIR
}

teardown() {
  clean_asdf_dir
}

@test "update_command --head should checkout the master branch" {
  run update_command --head
  [ "$status" -eq 0 ]
  cd $ASDF_DIR
  [ $(git rev-parse --abbrev-ref HEAD) = "master" ]
}

@test "update_command should checkout the latest tag" {
  run update_command
  [ "$status" -eq 0 ]
  cd $ASDF_DIR
  local tag=$(git describe --tag)
  echo $(git tag) | grep $tag
  [ "$status" -eq 0 ]
}

@test "update_command is a noop for non-git repos" {
  (cd $ASDF_DIR && rm -r .git/)
  run update_command
  [ "$status" -eq 1 ]
  [ "$(echo -e "Update command disabled. Please use the package manager that you used to install asdf to upgrade asdf.")" == "$output" ]
}

@test "update_command should not remove plugin versions" {
  run asdf install dummy 1.1
  [ "$status" -eq 0 ]
  [ $(cat $ASDF_DIR/installs/dummy/1.1/version) = "1.1" ]
  run update_command
  [ "$status" -eq 0 ]
  [ -f $ASDF_DIR/installs/dummy/1.1/version ]
  run update_command --head
  [ "$status" -eq 0 ]
  [ -f $ASDF_DIR/installs/dummy/1.1/version ]
}

@test "update_command should not remove plugins" {
  # dummy plugin is already installed
  run update_command
  [ "$status" -eq 0 ]
  [ -d $ASDF_DIR/plugins/dummy ]
  run update_command --head
  [ "$status" -eq 0 ]
  [ -d $ASDF_DIR/plugins/dummy ]
}

@test "update_command should not remove shims" {
  run asdf install dummy 1.1
  [ -f $ASDF_DIR/shims/dummy ]
  run update_command
  [ "$status" -eq 0 ]
  [ -f $ASDF_DIR/shims/dummy ]
  run update_command --head
  [ "$status" -eq 0 ]
  [ -f $ASDF_DIR/shims/dummy ]
}

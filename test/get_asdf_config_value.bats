#!/usr/bin/env bats
# -*- shell-script -*-

load test_helpers

setup() {
    ASDF_CONFIG_FILE=$BATS_TMPDIR/asdfrc
    cat > $ASDF_CONFIG_FILE <<-EOM
key1 = value1
legacy_version_file=yes # key value without spaces
EOM

    ASDF_CONFIG_DEFAULT_FILE=$BATS_TMPDIR/asdfrc_defaults
    cat > $ASDF_CONFIG_DEFAULT_FILE <<-EOM
# i have  a comment, it's ok
key2 = value2
legacy_version_file = no
EOM
}

teardown() {
    rm $ASDF_CONFIG_FILE
    rm $ASDF_CONFIG_DEFAULT_FILE
    unset ASDF_CONFIG_DEFAULT_FILE
    unset ASDF_CONFIG_FILE
}

@test "get_config returns default when config file does not exist" {
    result=$(ASDF_CONFIG_FILE="/some/fake/path" invoke_asdf_util asdf_read_config_value "legacy_version_file")
    [ "$result" = "no" ]
}

@test "get_config returns default value when the key does not exist" {
    [ $(invoke_asdf_util asdf_read_config_value "key2") = "value2" ]
}

@test "get_config returns config file value when key exists" {
    [ $(invoke_asdf_util asdf_read_config_value "key1") = "value1" ]
    [ $(invoke_asdf_util asdf_read_config_value "legacy_version_file") = "yes" ]
}

#!/bin/bash

# Copyright 2017 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -eu

# Integration tests for building macOS command line applications.

function set_up() {
  rm -rf app
  mkdir -p app
}

# Creates common source, targets, and basic plist for macOS applications.
function create_common_files() {
  cat > app/BUILD <<EOF
load(
    "@build_bazel_rules_apple//apple:macos.bzl",
    "macos_command_line_application",
)

objc_library(
    name = "lib",
    srcs = ["main.m"],
)
EOF

  cat > app/main.m <<EOF
int main(int argc, char **argv) {
  return 0;
}
EOF
}

# Tests that a bare-bones command line app builds.
function test_basic_build() {
  create_common_files

  cat >> app/BUILD <<EOF
macos_command_line_application(
    name = "app",
    minimum_os_version = "10.11",
    deps = [":lib"],
)
EOF

  do_build macos //app:app || fail "Should build"

  # Make sure that an Info.plist did *not* get embedded in this case.
  otool -s __TEXT __info_plist test-bin/app/app > $TEST_TMPDIR/otool.out
  assert_not_contains "__TEXT,__info_plist" $TEST_TMPDIR/otool.out
}

# Tests that a bare-bones command line app builds.
function test_info_plist_embedding() {
  create_common_files

  cat >> app/BUILD <<EOF
macos_command_line_application(
    name = "app",
    bundle_id = "com.test.bundle",
    infoplists = [
        "Info.plist",
        "Another.plist",
    ],
    minimum_os_version = "10.11",
    deps = [":lib"],
)
EOF

  cat > app/Info.plist <<EOF
{
  CFBundleIdentifier = "\${PRODUCT_BUNDLE_IDENTIFIER}";
}
EOF

  cat > app/Another.plist <<EOF
{
  AnotherKey = "AnotherValue";
}
EOF

  do_build macos //app:app || fail "Should build"

  # Make sure that an Info.plist did get embedded.
  otool -s __TEXT __info_plist test-bin/app/app > $TEST_TMPDIR/otool.out
  assert_contains "__TEXT,__info_plist" $TEST_TMPDIR/otool.out
}

# Tests that linkopts get passed to the underlying apple_binary target.
function test_linkopts_passed_to_binary() {
  # Bail out early if this is a Bitcode build; the -alias flag we use to test
  # this isn't compatible with Bitcode. That's ok; as long as the test passes
  # for non-Bitcode builds, we're good.
  is_bitcode_build && return 0

  create_common_files

  cat >> app/BUILD <<EOF
macos_command_line_application(
    name = "app",
    linkopts = ["-alias", "_main", "_linkopts_test_main"],
    minimum_os_version = "10.11",
    deps = [":lib"],
)
EOF

  do_build macos //app:app || fail "Should build"

  nm -j test-bin/app/app | grep _linkopts_test_main \
      || fail "Could not find -alias symbol in binary; " \
              "linkopts may have not propagated"
}

run_suite "macos_command_line_application tests"

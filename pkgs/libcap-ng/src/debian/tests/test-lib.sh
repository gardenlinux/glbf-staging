#!/bin/sh

set -e

TEST_PATH="src/test"
touch ${TEST_PATH}/config.h

gcc -Wall -Wextra ${TEST_PATH}/lib_test.c -o test_lib -lcap-ng
echo "buil OK"

./test_lib
echo "run OK"

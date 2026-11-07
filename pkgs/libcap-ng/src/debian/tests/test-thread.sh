#!/bin/sh

set -e

TEST_PATH="src/test"
touch ${TEST_PATH}/config.h

gcc -Wall ${TEST_PATH}/thread_test.c -o test_thread -lcap-ng -lpthread
echo "build OK"

./test_thread
echo "run OK"

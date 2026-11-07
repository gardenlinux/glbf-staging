#!/bin/sh

set -efu

cp -v bindings/python3/test/capng-test.py "${AUTOPKGTEST_TMP}"
cd "${AUTOPKGTEST_TMP}"

for py in $(py3versions -s); do
    echo "[*] testing $py"
    $py capng-test.py
done

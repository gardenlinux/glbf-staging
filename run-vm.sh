#!/usr/bin/env bash

set -eufo pipefail

image_id="$1"
image_manifest="$(glbx cache map get "$image_id")"
image_blob="$(glbx cache blobs get "$image_manifest" | awk '$2 == "image" { print $1 }')"
image_path="$(realpath "$(glbx cache blobs path "$image_blob")")"

disk=""

cleanup() {
	if [ -n "$disk" ] && [ -f "$disk" ]; then
		rm -f "$disk"
	fi
}
trap cleanup EXIT

disk="$(mktemp --suffix=.qcow2)"
qemu-img create -f qcow2 -F raw -b "$image_path" "$disk" 16G

qemu-system-x86_64 \
	-machine q35 \
	-cpu qemu64 \
	-m 4096 \
	-nodefaults \
	-no-reboot \
	-nographic \
	-serial mon:stdio \
	-drive if=pflash,format=raw,unit=0,file=/usr/share/OVMF/OVMF_CODE_4M.fd,readonly=on \
	-drive if=virtio,format=qcow2,file="$disk"
	
	# -drive if=none,id=nvme0,format=qcow2,file="$disk" \
	# -device nvme,drive=nvme0,serial=root

#!/usr/bin/env bash
# Package build output: AnyKernel3 flashable zip and, optionally, a boot image.

set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

KERNEL_DIR=${KERNEL_DIR:?KERNEL_DIR must be set}
WORKSPACE=${WORKSPACE:-$(cd "${KERNEL_DIR}/.." && pwd)}
ARCH=${ARCH:-arm64}
BOOT_OUT="${KERNEL_DIR}/out/arch/${ARCH}/boot"
AK3="${WORKSPACE}/AnyKernel3"

make_anykernel3() {
	group "Building AnyKernel3 package"
	rm -rf "$AK3"

	if is_true "${USE_CUSTOM_ANYKERNEL3:-false}"; then
		local src=${CUSTOM_ANYKERNEL3_SOURCE:?CUSTOM_ANYKERNEL3_SOURCE required}
		case "$src" in
			*.tar.gz | *.tgz)
				fetch "$src" "${WORKSPACE}/ak3.tar.gz"
				extract_archive "${WORKSPACE}/ak3.tar.gz" "$AK3" ;;
			*.zip)
				fetch "$src" "${WORKSPACE}/ak3.zip"
				extract_archive "${WORKSPACE}/ak3.zip" "$AK3" ;;
			*git*)
				retry 3 git clone -q --depth=1 ${CUSTOM_ANYKERNEL3_BRANCH:+-b "$CUSTOM_ANYKERNEL3_BRANCH"} \
					"$src" "$AK3" || die "failed to clone ${src}" ;;
			*)
				fetch "$src" "${WORKSPACE}/ak3.zip"
				extract_archive "${WORKSPACE}/ak3.zip" "$AK3" ;;
		esac
	else
		retry 3 git clone -q --depth=1 https://github.com/osm0sis/AnyKernel3 "$AK3" \
			|| die "failed to clone AnyKernel3"
		# This repository builds only for Pixel 4 (flame). Refuse every other
		# device instead of producing a dangerously broad flashable package.
		sed -i \
			-e 's/^kernel.string=.*/kernel.string=SukiSU Ultra kernel for Pixel 4 (flame)/' \
			-e 's/^device.name1=.*/device.name1=flame/' \
			-e 's/^device.name[2-9]=.*/&/' \
			"${AK3}/anykernel.sh"
		for n in 2 3 4 5 6 7 8 9; do
			sed -i "s/^device.name${n}=.*/device.name${n}=/" "${AK3}/anykernel.sh"
		done
		sed -i 's!BLOCK=/dev/block/platform/omap/omap_hsmmc.0/by-name/boot;!BLOCK=auto;!g' "${AK3}/anykernel.sh"
		sed -i 's/IS_SLOT_DEVICE=0;/IS_SLOT_DEVICE=1;/g' "${AK3}/anykernel.sh"
		# Upstream's template contains example Nexus-era init.rc/fstab edits.
		# A kernel-only Pixel package must only replace the kernel and preserve
		# the stock ramdisk, so remove that sample block and retain write_boot.
		sed -i '/^# init\.rc$/,/^write_boot;/ { /^write_boot;/!d; }' "${AK3}/anykernel.sh"
	fi

	cp "${BOOT_OUT}/${KERNEL_IMAGE_NAME}" "${AK3}/" \
		|| die "kernel image missing at ${BOOT_OUT}/${KERNEL_IMAGE_NAME}"
	if is_true "${CHECK_DTBO_IS_OK:-false}"; then
		cp "${BOOT_OUT}/dtbo.img" "${AK3}/"
	fi
	rm -rf "${AK3}/.git" "${AK3}/.github" "${AK3}/README.md"

	ok "AnyKernel3 package assembled"
	endgroup
}

make_boot_image() {
	is_true "${BUILD_BOOT_IMG:-false}" || return 0
	group "Repacking boot image"

	local tools="${WORKSPACE}/tools"
	[ -x "${tools}/unpack_bootimg.py" ] || [ -f "${tools}/unpack_bootimg.py" ] \
		|| die "mkbootimg tools not found at ${tools}"

	fetch "${SOURCE_BOOT_IMAGE:?SOURCE_BOOT_IMAGE required}" "${WORKSPACE}/boot-source.img"

	cd "$WORKSPACE"
	local fmt
	fmt=$(python3 "${tools}/unpack_bootimg.py" --boot_img boot-source.img --format mkbootimg) \
		|| die "failed to read the source boot image"
	info "source boot image args: ${fmt}"

	python3 "${tools}/unpack_bootimg.py" --boot_img boot-source.img >/dev/null \
		|| die "failed to unpack the source boot image"

	cp "${BOOT_OUT}/${KERNEL_IMAGE_NAME}" "${WORKSPACE}/out/kernel" \
		|| die "could not stage the new kernel into the unpacked ramdisk"

	# shellcheck disable=SC2086
	python3 "${tools}/mkbootimg.py" $fmt -o boot.img || die "mkbootimg failed"
	[ -s "${WORKSPACE}/boot.img" ] || die "boot.img was not produced"

	ok "boot.img built ($(du -h "${WORKSPACE}/boot.img" | cut -f1))"
	export_env MAKE_BOOT_IMAGE_IS_OK true
	endgroup
}

write_summary() {
	summary ""
	summary "### Build artifacts"
	summary ""
	summary "| Artifact | Size |"
	summary "| --- | --- |"
	local f
	for f in "${BOOT_OUT}/${KERNEL_IMAGE_NAME}" "${BOOT_OUT}/dtbo.img" "${WORKSPACE}/boot.img"; do
		[ -f "$f" ] && summary "| \`$(basename "$f")\` | $(du -h "$f" | cut -f1) |"
	done
	[ -d "$AK3" ] && summary "| \`AnyKernel3\` (flashable zip) | $(du -sh "$AK3" | cut -f1) |"
	summary ""
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	case "${1:-all}" in
		anykernel3) make_anykernel3 ;;
		bootimg)    make_boot_image ;;
		all)        make_anykernel3; make_boot_image; write_summary ;;
		*) die "unknown package step '$1'" ;;
	esac
fi

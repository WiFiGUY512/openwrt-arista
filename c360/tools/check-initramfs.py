"""Inspect the rootfs inside an OpenWrt initramfs FIT and check it.

usage: python3 check_initramfs.py <initramfs-uImage.itb> distributable|site

distributable: must NOT contain Arista's QCN9074 firmware, any pre-staged
calibration file, or any site configuration (uci-defaults 98-c360-vlan20 /
99-c360-lan-off, a baked /etc/config/wireless). site: must contain the two
site uci-defaults and otherwise pass the same firmware/calibration checks.
Exit status 1 on any failure.
"""
import gzip
import hashlib
import re
import struct
import sys
import zlib

VENDOR_AMSS = "b34c676991bf2d15f6938397776a364073b1c8a2548212d72efbf35fdfcccb53"


def fdt_data(blob):
    _, _, off_struct, off_strings = struct.unpack(">IIII", blob[:16])
    p, path, out = off_struct, [], {}

    def name(o):
        return blob[off_strings + o:blob.index(b"\0", off_strings + o)].decode()

    while True:
        tok = struct.unpack(">I", blob[p:p + 4])[0]
        p += 4
        if tok == 1:
            e = blob.index(b"\0", p)
            path.append(blob[p:e].decode())
            p = (e + 4) & ~3
        elif tok == 2:
            path.pop()
        elif tok == 3:
            ln, no = struct.unpack(">II", blob[p:p + 8])
            p += 8
            if name(no) == "data":
                out["/".join(path)] = blob[p:p + ln]
            p = (p + ln + 3) & ~3
        elif tok == 9:
            return out


def cpio_files(blob):
    o, files = 0, {}
    while blob[o:o + 6] == b"070701":
        h = blob[o:o + 110]
        mode, fsz, nsz = int(h[14:22], 16), int(h[54:62], 16), int(h[94:102], 16)
        name = blob[o + 110:o + 110 + nsz - 1].decode(errors="replace")
        o = (o + 110 + nsz + 3) & ~3
        data = blob[o:o + fsz]
        o = (o + fsz + 3) & ~3
        if name == "TRAILER!!!":
            break
        files[name] = (mode, data)
    return files


def main():
    path, kind = sys.argv[1], sys.argv[2]
    kernel = gzip.decompress(fdt_data(open(path, "rb").read())["/images/kernel-1"])
    rootfs = None
    for m in re.finditer(re.escape(b"\x1f\x8b\x08"), kernel):
        try:
            blob = zlib.decompressobj(31).decompress(kernel[m.start():])
        except Exception:
            continue
        if blob[:6] == b"070701":
            rootfs = cpio_files(blob)
            break
    if rootfs is None:
        sys.exit("no initramfs cpio found")

    fails = []
    amss = rootfs.get("lib/firmware/ath11k/QCN9074/hw1.0/amss.bin")
    amss_sha = hashlib.sha256(amss[1]).hexdigest() if amss else None
    if amss_sha == VENDOR_AMSS:
        fails.append("Arista amss.bin is inside the image")
    cal = [n for n in rootfs if re.search(r"lib/firmware/ath11k/.*/(cal-|caldata)", n)]
    if cal:
        fails.append("pre-staged calibration files: %s" % cal)
    site = [n for n in ("etc/uci-defaults/98-c360-vlan20", "etc/uci-defaults/99-c360-lan-off") if n in rootfs]
    if kind == "distributable":
        if site:
            fails.append("site uci-defaults present: %s" % site)
        if "etc/config/wireless" in rootfs:
            fails.append("a baked /etc/config/wireless is present")
    elif len(site) != 2:
        fails.append("site uci-defaults missing (found %s)" % site)
    for need in ("usr/sbin/arista-c360-wifi-fw", "lib/preinit/81_arista_c360_wifi",
                 "usr/sbin/unsquashfs", "usr/sbin/ubiattach", "usr/sbin/fw_setenv",
                 "etc/hotplug.d/ieee80211/12-arista-c360-leds",
                 "usr/sbin/arista-c360-install", "usr/sbin/ubiformat"):
        if need not in rootfs:
            fails.append("missing %s" % need)
    # the installer mounts the USB stick (FAT32) from Linux
    mods = {n.rsplit("/", 1)[-1] for n in rootfs if n.startswith("lib/modules/")}
    for ko in ("usb-storage.ko", "vfat.ko", "nls_cp437.ko", "nls_iso8859-1.ko"):
        if ko not in mods:
            fails.append("missing module %s (the installer cannot read the stick)" % ko)

    if "etc/init.d/arista-c360-wifi-fw" in rootfs:
        fails.append("the old init.d extractor (rebinds live cards) is still present")
    print("  %s: %d entries, amss.bin %s, cal files %d, site defaults %s"
          % (kind, len(rootfs), (amss_sha or "absent")[:12], len(cal), site or "none"))
    for f in fails:
        print("  FAIL:", f)
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()

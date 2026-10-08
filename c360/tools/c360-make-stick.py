#!/usr/bin/env python3
"""Make the USB stick for installing OpenWrt on Arista C-360s.

usage: c360-make-stick.py --images <dir> --img <out.img> [--size-mib N] [--xz]
       c360-make-stick.py --images <dir> <stick>

<dir> holds the arista_c360 build output: ...-initramfs-uImage.itb (the RAM
installer) and ...-squashfs-factory.ubi.

--img writes a disk image to put on a stick with Rufus (or dd, or balenaEtcher):
an MBR with one FAT32 partition, the way Raspberry Pi images are made. It is
N MiB (default 2048; the stick must be at least that big), and what the
installer files leave free holds the units' flash backups, about 180 MiB each.
--xz also writes <out.img>.xz, which Rufus writes directly. Each image gets a
.sha256 beside it.

<stick>, instead, is the root of a FAT32 stick (on Windows a drive such as E:\\)
or any directory to stage one in; the files are copied there.

Either way the stick holds c360/:
  initramfs.itb   the RAM installer, which U-Boot loads from the stick
  factory.ubi     the image arista-c360-install writes to NAND slot 0
  SHA256SUMS      checksums of both files, and of the kernel and rootfs
                  volumes inside factory.ubi, which the installer compares
                  slot 0 against after writing it
  README.txt      the U-Boot line, for installing without c360-flash
and arista-c360-install adds c360/backup-<MAC>-<time>/ for each unit.
"""
import argparse
import glob
import hashlib
import lzma
import os
import shutil
import struct
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ubi_extract  # noqa: E402  (bundled beside this script)

UBOOT_LINE = ("usb start; fatload usb 0:1 0xA0000000 c360/initramfs.itb && "
              "setenv fdt_high 0x4A3E0000 && "
              "setenv bootargs console=ttyMSM0,115200n8 rootwait panic=0 pcie_ports=compat && "
              "bootm 0xA0000000#config@1")
LABEL = "C360OPENWRT"
BACKUP_MIB = 180


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def volume_bytes(img, lebs, doff, vol):
    """A volume's contents as ubi_extract rebuilds it: every LEB at full size,
    which is what ubiformat writes and the AP reads back."""
    leb = ubi_extract.PEB - doff
    have = {l: lebs[(vol["vol_id"], l)] for (vid, l) in lebs if vid == vol["vol_id"]}
    out = bytearray()
    for l in range(max(have) + 1):
        if l in have:
            _, p, dsize, vtype = have[l]
            start = p * ubi_extract.PEB + doff
            n = dsize if (vtype == 2 and dsize) else leb
            out += img[start:start + n]
        else:
            out += b"\xff" * leb
    return bytes(out)


def one(pattern, where):
    found = sorted(glob.glob(os.path.join(where, pattern)))
    if len(found) != 1:
        sys.exit("expected one %s in %s, found %d" % (pattern, where, len(found)))
    return found[0]


def stick_files(images):
    """The c360/ files, as [(name, bytes)], and the newest input's mtime."""
    itb = one("*arista_c360-initramfs-uImage.itb", images)
    ubi = one("*arista_c360-squashfs-factory.ubi", images)

    img, npeb, lebs, stats, doff = ubi_extract.parse(ubi)
    vols = ubi_extract.volumes(img, lebs, doff)
    for need in ("kernel", "rootfs"):
        if need not in vols:
            sys.exit("factory.ubi has no %s volume" % need)
        if not vols[need]["crc_ok"]:
            sys.exit("factory.ubi: the %s volume's table entry fails its CRC" % need)

    files, lines = [], []
    for src, name in ((itb, "initramfs.itb"), (ubi, "factory.ubi")):
        data = open(src, "rb").read()
        files.append((name, data))
        lines.append("%s  %s" % (hashlib.sha256(data).hexdigest(), name))
        print("%-14s %10d bytes  (%s)" % (name, len(data), os.path.basename(src)))
    for name in ("kernel", "rootfs"):
        data = volume_bytes(img, lebs, doff, vols[name])
        lines.append("%s volume:%s %d" % (hashlib.sha256(data).hexdigest(), name, len(data)))
        print("  volume %-6s %10d bytes" % (name, len(data)))
    files.append(("SHA256SUMS", ("\n".join(lines) + "\n").encode()))
    files.append(("README.txt", (
        "OpenWrt installer for the Arista C-360\n\n"
        "With c360-flash, nothing to do here: it drives the console.\n\n"
        "By hand, on the console (RJ-45 rollover, 115200 8N1):\n"
        "1. Power the AP on and paste the U-Boot key until IPQ807x# appears:\n"
        "     s6.D5r4Gnb89ZEWSW6Kq.\n"
        "2. Paste this line (nothing is saved; never type saveenv):\n"
        "     %s\n"
        "3. When OpenWrt's console is up, run:\n"
        "     arista-c360-install\n"
        "4. When it prints C360-INSTALL-RESULT: OK installed, type reboot.\n\n"
        "Each unit's flash backup is written here, to backup-<MAC>-<time>/,\n"
        "gzipped (about %d MiB). Keep them: the ART partition in each holds that\n"
        "unit's radio calibration and exists nowhere else.\n" % (UBOOT_LINE, BACKUP_MIB)).replace("\n", "\r\n").encode()))
    return files, max(os.path.getmtime(itb), os.path.getmtime(ubi))


# --- FAT32 disk image --------------------------------------------------------

SECTOR = 512
PART_LBA = 2048            # the partition starts at 1 MiB


def short_name(name, taken):
    """The 8.3 name for a directory entry, and whether a long name is needed."""
    base, dot, ext = name.rpartition(".")
    if not dot:
        base, ext = name, ""
    ok = "".join(c for c in base.upper() if c.isalnum() or c in "$%'-_@~`!(){}^#&")
    oke = "".join(c for c in ext.upper() if c.isalnum() or c in "$%'-_@~`!(){}^#&")[:3]
    exact = len(base) <= 8 and len(ext) <= 3 and base.upper() == ok and ext.upper() == oke and name.count(".") <= 1
    if exact:
        sn = ok.ljust(8) + oke.ljust(3)
        if sn not in taken:
            return sn.encode("ascii"), name != name.upper()
    for i in range(1, 10):
        sn = (ok[:6] + "~%d" % i).ljust(8) + oke.ljust(3)
        if sn not in taken:
            return sn.encode("ascii"), True
    sys.exit("too many names like %s" % name)


def lfn_entries(name, sn):
    """VFAT long-name entries for name, in the order they are stored."""
    csum = 0
    for b in sn:
        csum = (((csum & 1) << 7) + (csum >> 1) + b) & 0xFF
    u = name.encode("utf-16-le")
    chars = [u[i:i + 2] for i in range(0, len(u), 2)]
    if len(chars) % 13:
        chars += [b"\0\0"] + [b"\xff\xff"] * (12 - len(chars) % 13)
    parts = [b"".join(chars[i:i + 13]) for i in range(0, len(chars), 13)]
    out = []
    for n, p in enumerate(parts, 1):
        seq = n | (0x40 if n == len(parts) else 0)
        out.append(struct.pack("<B10sBBB12sH4s", seq, p[:10], 0x0F, 0, csum, p[10:22], 0, p[22:26]))
    return out[::-1]


def dos_time(t):
    lt = time.localtime(t)
    date = ((max(lt.tm_year, 1980) - 1980) << 9) | (lt.tm_mon << 5) | lt.tm_mday
    return (lt.tm_hour << 11) | (lt.tm_min << 5) | (lt.tm_sec // 2), date


def dir_entry(sn, attr, cluster, size, stamp):
    tm, dt = dos_time(stamp)
    return struct.pack("<11sBBBHHHHHHHI", sn, attr, 0, 0, tm, dt, dt,
                       cluster >> 16, tm, dt, cluster & 0xFFFF, size)


def fat32_image(tree, size, stamp):
    """Lay out a FAT32 disk image holding tree ({name: bytes or {subtree}}).
    Returns the regions to write, [(offset, bytes)]; the rest is zeros."""
    total = size // SECTOR
    sectors = total - PART_LBA
    spc = 8 if sectors <= (8 << 21) else 16 if sectors <= (16 << 21) else 32 if sectors <= (32 << 21) else 64
    csize = spc * SECTOR
    rsvd, nfats = 32, 2

    def fat_size(rsvd):
        fsz = 1
        while True:
            clusters = (sectors - rsvd - nfats * fsz) // spc
            need = -(-(clusters + 2) * 4 // SECTOR)
            if need <= fsz:
                return fsz, clusters
            fsz = need

    fsz, clusters = fat_size(rsvd)
    # data region on a 1 MiB boundary of the disk; the FAT keeps its size,
    # now a little more than the fewer clusters need
    rsvd += -(PART_LBA + rsvd + nfats * fsz) % 2048
    clusters = (sectors - rsvd - nfats * fsz) // spc
    assert (clusters + 2) * 4 <= fsz * SECTOR
    if clusters < 65525:
        sys.exit("%d MiB is too small for FAT32" % (size >> 20))
    data_lba = PART_LBA + rsvd + nfats * fsz

    fat = [0] * (clusters + 2)
    fat[0], fat[1] = 0x0FFFFFF8, 0x0FFFFFFF
    nxt = [2]
    regions = []

    def alloc(nbytes):
        n = max(1, -(-nbytes // csize))
        first = nxt[0]
        if first + n > clusters + 2:
            sys.exit("the files do not fit in %d MiB" % (size >> 20))
        for c in range(first, first + n - 1):
            fat[c] = c + 1
        fat[first + n - 1] = 0x0FFFFFFF
        nxt[0] += n
        return first

    def offset(cluster):
        return (data_lba + (cluster - 2) * spc) * SECTOR

    def lay_dir(node, me, parent, root):
        """Entries of directory node, whose own cluster is me; allocates and
        writes the children."""
        ents, taken = [], set()
        if root:
            ents.append(dir_entry(LABEL.ljust(11).encode(), 0x08, 0, 0, stamp))
        else:
            ents.append(dir_entry(b".          ", 0x10, me, 0, stamp))
            ents.append(dir_entry(b"..         ", 0x10, parent, 0, stamp))
        kids = []
        for name in node:
            sn, lfn = short_name(name, taken)
            taken.add(sn.decode())
            kids.append((name, sn, lfn))
        # each child's clusters come after this directory's own
        for name, sn, lfn in kids:
            if lfn:
                ents += lfn_entries(name, sn)
            data = node[name]
            if isinstance(data, dict):
                # ".", "..", and per child one short and its long-name entries
                n = 2 + sum(1 + -(-len(k) // 13) for k in data)
                c = alloc(n * 32)
                ents.append(dir_entry(sn, 0x10, c, 0, stamp))
                blob = lay_dir(data, c, 0 if root else me, False)
                assert len(blob) <= max(1, -(-n * 32 // csize)) * csize
                regions.append((offset(c), blob))
            elif data:
                c = alloc(len(data))
                ents.append(dir_entry(sn, 0x20, c, len(data), stamp))
                regions.append((offset(c), data))
            else:
                ents.append(dir_entry(sn, 0x20, 0, 0, stamp))
        return b"".join(ents)

    root_c = alloc(32 * 64)                         # one cluster, room to spare
    root_blob = lay_dir(tree, root_c, 0, True)
    if len(root_blob) > csize:
        sys.exit("too many entries in the root directory")
    regions.append((offset(root_c), root_blob))
    used = nxt[0] - 2

    volid = struct.unpack("<I", hashlib.sha256(b"".join(b for _, b in regions)).digest()[:4])[0]
    bs = bytearray(SECTOR)
    bs[0:3] = b"\xEB\x58\x90"
    bs[3:11] = b"MSWIN4.1"
    struct.pack_into("<HBHBHHBHHHII", bs, 11, SECTOR, spc, rsvd, nfats, 0, 0, 0xF8, 0, 63, 255, PART_LBA, sectors)
    struct.pack_into("<IHHIHH12s", bs, 36, fsz, 0, 0, 2, 1, 6, b"")
    struct.pack_into("<BBBI11s8s", bs, 64, 0x80, 0, 0x29, volid, LABEL.ljust(11).encode(), b"FAT32   ")
    bs[510:512] = b"\x55\xAA"
    fsinfo = bytearray(SECTOR)
    struct.pack_into("<I", fsinfo, 0, 0x41615252)
    struct.pack_into("<III", fsinfo, 484, 0x61417272, clusters - used, nxt[0])
    struct.pack_into("<I", fsinfo, 508, 0xAA550000)
    third = bytearray(SECTOR)                       # the boot record's third sector
    third[510:512] = b"\x55\xAA"
    boot = bytes(bs) + bytes(fsinfo) + bytes(third)
    p = PART_LBA * SECTOR
    regions += [(p, boot), (p + 6 * SECTOR, boot)]
    fat_bytes = struct.pack("<%dI" % len(fat), *fat)
    for i in range(nfats):
        regions.append(((PART_LBA + rsvd + i * fsz) * SECTOR, fat_bytes))

    mbr = bytearray(SECTOR)
    struct.pack_into("<I", mbr, 440, volid ^ 0x43333630)
    end_chs = b"\xFE\xFF\xFF"
    struct.pack_into("<B3sB3sII", mbr, 446, 0x00, b"\x20\x21\x00", 0x0C, end_chs, PART_LBA, sectors)
    mbr[510:512] = b"\x55\xAA"
    regions.append((0, bytes(mbr)))
    regions.sort()
    for (a, x), (b, _) in zip(regions, regions[1:]):
        assert a + len(x) <= b, "overlapping regions at %#x" % b
    info = "FAT32, %d KiB clusters, %d clusters, %d used" % (csize >> 10, clusters, used)
    return regions, info


def write_img(path, regions, size):
    with open(path, "wb") as f:
        for off, blob in regions:
            f.seek(off)
            f.write(blob)
        f.truncate(size)
    with open(path, "rb") as f:                     # read the written data back
        for off, blob in regions:
            f.seek(off)
            if f.read(len(blob)) != blob:
                sys.exit("%s does not read back as written at %#x" % (path, off))


def stream(regions, size, chunk=1 << 20):
    """The whole image, in order, as chunks."""
    pos = 0
    zeros = bytes(chunk)
    for off, blob in regions + [(size, b"")]:
        while pos < off:
            n = min(chunk, off - pos)
            yield zeros[:n]
            pos += n
        if blob:
            yield blob
            pos += len(blob)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("stick", nargs="?")
    ap.add_argument("--images", required=True)
    ap.add_argument("--img")
    ap.add_argument("--size-mib", type=int, default=2048)
    ap.add_argument("--xz", action="store_true")
    a = ap.parse_args()
    if bool(a.stick) == bool(a.img):
        ap.error("give either <stick> or --img")

    files, stamp = stick_files(a.images)

    if a.stick:
        dest = os.path.join(a.stick, "c360")
        os.makedirs(dest, exist_ok=True)
        for name, data in files:
            out = os.path.join(dest, name)
            with open(out, "wb") as f:
                f.write(data)
            if sha256_file(out) != hashlib.sha256(data).hexdigest():
                sys.exit("the copy of %s on the stick does not match: is the stick failing?" % name)
        try:
            free = shutil.disk_usage(a.stick).free
            print("stick ready: %s (%.1f GiB free, room for about %d units' backups)"
                  % (dest, free / (1 << 30), free // (BACKUP_MIB << 20)))
        except OSError:
            print("stick ready: %s" % dest)
        return

    size = a.size_mib << 20
    if a.size_mib < 512:
        sys.exit("--size-mib: at least 512")
    regions, info = fat32_image({"c360": dict(files)}, size, stamp)
    write_img(a.img, regions, size)
    h = hashlib.sha256()
    for chunk in stream(regions, size):
        h.update(chunk)
    outs = [(a.img, h.hexdigest())]
    if a.xz:
        xz = lzma.LZMACompressor(format=lzma.FORMAT_XZ, check=lzma.CHECK_CRC32, preset=6)
        hx = hashlib.sha256()
        with open(a.img + ".xz", "wb") as f:
            for chunk in stream(regions, size):
                out = xz.compress(chunk)
                f.write(out)
                hx.update(out)
            out = xz.flush()
            f.write(out)
            hx.update(out)
        outs.append((a.img + ".xz", hx.hexdigest()))
    for path, digest in outs:
        with open(path + ".sha256", "w", newline="\n") as f:
            f.write("%s  %s\n" % (digest, os.path.basename(path)))
        print("%s: %d bytes, sha256 %s" % (path, os.path.getsize(path), digest))
    free = size - (PART_LBA * SECTOR) - sum(len(d) for _, d in files)
    print("%s; about %d MiB free, room for about %d units' backups" % (info, free >> 20, (free >> 20) // BACKUP_MIB))
    print("Write it with Rufus (it detects a disk image and writes it in DD mode), then put the stick in the AP.")


if __name__ == "__main__":
    main()

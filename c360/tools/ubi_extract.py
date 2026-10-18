#!/usr/bin/env python3
"""Minimal read-only UBI image parser.

usage: python ubi_extract.py <image> [<volume_name> <out_file>]
       python ubi_extract.py --sums <factory.ubi>

Lists the volumes found in a raw UBI image (a NAND partition dump without OOB)
and, if a volume name is given, rebuilds that volume's data by ordering its
logical erase blocks (newest copy of each LEB by sequence number) and writes it
to <out_file>. Headers are big-endian; CRCs are checked and reported. The
erase block size is the image's own (128 KiB on the C-260, 256 KiB on the
C-360): where its second erase counter header starts.

--sums prints the SHA256SUMS an installer (arista-c360-install,
arista-c260-install) checks factory.ubi and the slot it writes against: the
file's checksum, and each of its kernel and rootfs volumes' as the AP reads
it back after ubiformat.
"""
import binascii
import hashlib
import os
import struct
import sys

PEB = 256 * 1024
LAYOUT_VOL_ID = 0x7FFFEFFF


def ubi_crc(data):
    # UBI header CRC: crc32 seeded with 0xFFFFFFFF, no final inversion
    return (binascii.crc32(data) ^ 0xFFFFFFFF) & 0xFFFFFFFF


def peb_size(img):
    """The image's erase block size: where its second erase counter header
    (UBI#) is. 256 KiB if none is found where one could be."""
    for size in (64 * 1024, 128 * 1024, 256 * 1024, 512 * 1024):
        if img[size:size + 4] == b"UBI#":
            return size
    return 256 * 1024


def parse(path):
    """Reads the image and sets PEB, which the other functions use, to its
    erase block size."""
    global PEB
    img = open(path, "rb").read()
    PEB = peb_size(img)
    npeb = len(img) // PEB
    lebs = {}           # (vol_id, lnum) -> (sqnum, peb, data_size, vol_type)
    stats = {"empty": 0, "ec_bad": 0, "vid_none": 0, "vid_bad": 0, "used": 0}
    data_offset = None
    for p in range(npeb):
        o = p * PEB
        ec = img[o:o + 64]
        if ec[:4] != b"UBI#":
            if ec == b"\xff" * 64:
                stats["empty"] += 1
            else:
                stats["ec_bad"] += 1
            continue
        if ubi_crc(ec[:60]) != struct.unpack(">I", ec[60:64])[0]:
            stats["ec_bad"] += 1
            continue
        vid_off, doff = struct.unpack(">II", ec[16:24])
        data_offset = doff
        vid = img[o + vid_off:o + vid_off + 64]
        if vid[:4] != b"UBI!":
            stats["vid_none"] += 1
            continue
        if ubi_crc(vid[:60]) != struct.unpack(">I", vid[60:64])[0]:
            stats["vid_bad"] += 1
            continue
        vol_type = vid[5]
        vol_id, lnum = struct.unpack(">II", vid[8:16])
        data_size = struct.unpack(">I", vid[20:24])[0]
        sqnum = struct.unpack(">Q", vid[40:48])[0]
        key = (vol_id, lnum)
        if key not in lebs or sqnum > lebs[key][0]:
            lebs[key] = (sqnum, p, data_size, vol_type)
        stats["used"] += 1
    return img, npeb, lebs, stats, data_offset


def volumes(img, lebs, data_offset):
    rec = lebs.get((LAYOUT_VOL_ID, 0))
    vols = {}
    if not rec:
        return vols
    o = rec[1] * PEB + data_offset
    for i in range(128):
        r = img[o + i * 172:o + (i + 1) * 172]
        reserved, align, pad, vtype, upd, nlen = struct.unpack(">IIIBBH", r[:16])
        if reserved == 0 or nlen == 0 or nlen > 127:
            continue
        name = r[16:16 + nlen].decode("ascii", "replace")
        vols[name] = {"vol_id": i, "reserved_pebs": reserved, "type": "dynamic" if vtype == 1 else "static",
                      "crc_ok": ubi_crc(r[:168]) == struct.unpack(">I", r[168:172])[0]}
    return vols


def volume_bytes(img, lebs, doff, vol):
    """A volume's contents as main() rebuilds it: every LEB at full size,
    which is what ubiformat writes and the AP reads back."""
    leb = PEB - doff
    have = {l: lebs[(vol["vol_id"], l)] for (vid, l) in lebs if vid == vol["vol_id"]}
    out = bytearray()
    for l in range(max(have) + 1):
        if l in have:
            _, p, dsize, vtype = have[l]
            start = p * PEB + doff
            n = dsize if (vtype == 2 and dsize) else leb
            out += img[start:start + n]
        else:
            out += b"\xff" * leb
    return bytes(out)


def sums(path):
    """The SHA256SUMS lines for factory.ubi at path."""
    img, npeb, lebs, stats, doff = parse(path)
    vols = volumes(img, lebs, doff)
    lines = ["%s  factory.ubi" % hashlib.sha256(img).hexdigest()]
    for name in ("kernel", "rootfs"):
        if name not in vols or not vols[name]["crc_ok"]:
            sys.exit("%s: no good %s volume" % (path, name))
        data = volume_bytes(img, lebs, doff, vols[name])
        lines.append("%s volume:%s %d" % (hashlib.sha256(data).hexdigest(), name, len(data)))
    return lines


def main():
    if sys.argv[1:2] == ["--sums"] and len(sys.argv) == 3:
        print("\n".join(sums(sys.argv[2])))
        return
    img, npeb, lebs, stats, doff = parse(sys.argv[1])
    print("PEBs %d (%d KiB each), data_offset %s, stats %s" % (npeb, PEB // 1024, doff, stats))
    vols = volumes(img, lebs, doff)
    for name, v in vols.items():
        have = sorted(l for (vid, l) in lebs if vid == v["vol_id"])
        print("  volume %-16s id %-3d %-7s reserved_pebs %-5d lebs_present %-5d max_lnum %s crc_ok %s"
              % (name, v["vol_id"], v["type"], v["reserved_pebs"], len(have), have[-1] if have else None, v["crc_ok"]))
    if len(sys.argv) >= 4:
        name, out = sys.argv[2], sys.argv[3]
        v = vols[name]
        leb_size = PEB - doff
        have = {l: lebs[(v["vol_id"], l)] for (vid, l) in lebs if vid == v["vol_id"]}
        top = max(have)
        missing = [l for l in range(top + 1) if l not in have]
        with open(out, "wb") as f:
            for l in range(top + 1):
                if l in have:
                    _, p, dsize, vtype = have[l]
                    start = p * PEB + doff
                    n = dsize if (vtype == 2 and dsize) else leb_size
                    f.write(img[start:start + n])
                else:
                    f.write(b"\xff" * leb_size)
        print("wrote %s: %d LEBs (missing %d: %s)" % (out, top + 1, len(missing), missing[:10]))


if __name__ == "__main__":
    main()

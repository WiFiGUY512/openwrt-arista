#!/usr/bin/env python3
"""Install OpenWrt on an Arista C-360 from a USB stick, driving its console.

usage: c360-flash.py --port COM6 [--dry-run] [--yes] [--at-prompt]

Before running it: the stick (made by c360-make-stick.py) is in the AP's USB
port, the console cable (RJ-45 rollover, RS-232) is on --port, and the AP is
off or about to be power-cycled. Then, per unit:

  1. It waits for U-Boot's banner and sends the stop key until IPQ807x#
     appears. If it misses the 2 s window and Arista boots, it says so and
     stops: Arista's boot script saves the U-Boot environment, which is
     harmless but means the AP must be power-cycled and the run repeated.
  2. At IPQ807x# it sends only these, each after the prompt is back, and
     checks each result: usb start, fatls, fatload of the RAM installer,
     setenv fdt_high and bootargs (RAM only, with panic=0), bootm. It never
     sends saveenv; send() refuses anything containing it.
  3. In the RAM installer it checks it is a C-360 running from RAM, then runs
     arista-c360-install (with --dry-run: backup and checks only). Before a
     real install it asks you to type the last four hex digits of the unit's
     MAC, unless --yes.
  4. After a real install it reboots the AP, does NOT stop U-Boot, and
     confirms OpenWrt starts from NAND (ubi.mtd=ubi on the kernel command
     line).

Everything the console prints is logged to c360-flash-<time>.log.
--at-prompt skips step 1 when you have already stopped U-Boot yourself.
"""
import argparse
import re
import sys
import time

try:
    import serial
except ImportError:
    sys.exit("pyserial is needed: pip install pyserial")

for s in (sys.stdout, sys.stderr):
    try:
        s.reconfigure(encoding="utf-8", errors="replace")
    except AttributeError:
        pass

KEY = "s6.D5r4Gnb89ZEWSW6Kq."
KEY_INTERVAL = 0.10

# From arista_serial_tool/uboot_interrupt.py, which learned them the hard way:
# the prompt may carry the echo of a key in flight, but never a typed command
# (an echoed "IPQ807x# reset" once let vendor autoboot run).
UBOOT_KEYED_PROMPT = re.compile(r"IPQ807x#[ \t]*[s6.D5r4Gnb89ZEWSKq]*[ \t]*$")
UBOOT_PROMPT = re.compile(r"IPQ807x#[ \t]*$")
UBOOT_BANNER = re.compile(r"U-Boot\s+v?\d{4}\.\d+", re.IGNORECASE)
FRESH_LINUX = re.compile(r"Linux version|Booting Linux|Starting kernel", re.IGNORECASE)
LOGIN = re.compile(r"login:\s*$|Password:\s*$", re.IGNORECASE)
ACTIVATE = re.compile(r"Please press Enter to activate this console")
SHELL = re.compile(r"root@[\w.-]+:[^\n#]*#\s*$")
CMDLINE = re.compile(r"Kernel command line: ([^\r\n]*)")
RESULT = re.compile(r"C360-INSTALL-RESULT: (OK|FAILED)([^\r\n]*)")

UBOOT_ALLOWED = ("usb start", "fatls usb 0:1 c360", "fatload usb 0:1 0xA0000000 c360/initramfs.itb",
                 "setenv fdt_high 0x4A3E0000",
                 "setenv bootargs console=ttyMSM0,115200n8 rootwait panic=0 pcie_ports=compat",
                 "bootm 0xA0000000#config@1", "\x03")


class Stop(Exception):
    pass


class Console:
    def __init__(self, port, log):
        self.ser = serial.Serial(port, 115200, bytesize=8, parity="N", stopbits=1,
                                 timeout=0.05, xonxoff=False, rtscts=False)
        self.log = open(log, "ab")
        self.buf = ""          # everything since mark()
        self.line = ""         # the current, unfinished line, for echoing

    def pump(self):
        data = self.ser.read(self.ser.in_waiting or 1)
        if data:
            self.log.write(data)
            self.log.flush()
            text = data.decode("utf-8", "replace")
            self.buf += text
            if len(self.buf) > 65536:
                self.buf = self.buf[-32768:]
            for ch in text:
                if ch == "\n":
                    print("  | " + self.line.rstrip("\r"))
                    self.line = ""
                elif ch != "\r":
                    self.line += ch
        return bool(data)

    def mark(self):
        self.buf = ""

    def tail(self):
        """The text after the last newline: where prompts are."""
        return self.buf.rsplit("\n", 1)[-1].rstrip("\r")

    def send(self, text, uboot=False):
        if "saveenv" in text.lower():
            raise Stop("refusing to send saveenv")
        if uboot and text not in UBOOT_ALLOWED:
            raise Stop("refusing a U-Boot command outside the allowlist: %r" % text)
        self.ser.write(text.encode() + (b"" if text == "\x03" else b"\r"))

    def wait(self, timeout, until, abort=()):
        """Pump until `until` matches the buffer (or its tail, for a prompt);
        Stop on an abort pattern or the timeout."""
        end = time.time() + timeout
        while time.time() < end:
            self.pump()
            for name, rx in abort:
                if rx.search(self.buf):
                    raise Stop(name)
            m = until(self)
            if m:
                return m
        raise Stop("timed out after %ds" % timeout)


def at_uboot_prompt(c):
    return UBOOT_PROMPT.search(c.tail())


def uboot(c, cmd, timeout=60, check=None):
    """One U-Boot command: sent only at a clean prompt, done when it is back."""
    c.mark()
    c.send(cmd, uboot=True)
    c.wait(timeout, lambda c: at_uboot_prompt(c) and c.buf.count("IPQ807x#") >= 1 and len(c.buf) > len(cmd))
    out = c.buf
    if check and not check(out):
        raise Stop("U-Boot: %r did not do what was expected" % cmd)
    return out


def shell(c, cmd, timeout=60):
    c.mark()
    c.send(cmd)
    c.wait(timeout, lambda c: SHELL.search(c.tail()) and len(c.buf) > len(cmd) + 2)
    lines = c.buf.replace("\r", "").split("\n")
    return "\n".join(lines[1:-1])    # without the echoed command and the prompt


def stop_uboot(c):
    print("Power the C-360 on now (or power-cycle it). Waiting for U-Boot ...")
    c.mark()
    c.wait(600, lambda c: UBOOT_BANNER.search(c.buf))
    print(">> U-Boot banner: sending the stop key")
    c.mark()
    end = time.time() + 15
    while time.time() < end:
        c.send(KEY)
        t = time.time() + KEY_INTERVAL
        while time.time() < t:
            c.pump()
        if UBOOT_KEYED_PROMPT.search(c.tail()) or re.search(r"(?m)^IPQ807x#", c.buf):
            break
        if FRESH_LINUX.search(c.buf):
            raise Stop("missed U-Boot's window: Arista is booting (its script saves the U-Boot "
                       "environment). Power-cycle the AP and run again")
    else:
        raise Stop("U-Boot did not stop within 15 s")
    # clear the key echo off the command line
    time.sleep(0.3)
    c.pump()
    c.mark()
    c.send("\x03", uboot=True)
    c.wait(5, at_uboot_prompt)
    print(">> stopped at IPQ807x#")


def boot_installer(c):
    out = uboot(c, "usb start", 60)
    m = re.search(r"(\d+) Storage Device\(s\) found", out)
    if not m or int(m.group(1)) < 1:
        raise Stop("U-Boot found no USB storage; is the stick in the AP's USB port?")
    out = uboot(c, "fatls usb 0:1 c360", 30)
    sizes = dict((n, int(s)) for s, n in re.findall(r"^\s*(\d+)\s+(\S+)\s*$", out, re.M))
    if "initramfs.itb" not in sizes or "factory.ubi" not in sizes:
        raise Stop("the stick has no c360/initramfs.itb and c360/factory.ubi (made by c360-make-stick?)")
    out = uboot(c, "fatload usb 0:1 0xA0000000 c360/initramfs.itb", 120)
    m = re.search(r"(\d+) bytes read", out)
    if not m or int(m.group(1)) != sizes["initramfs.itb"]:
        raise Stop("fatload read %s bytes, the file is %d" % (m and m.group(1), sizes["initramfs.itb"]))
    uboot(c, "setenv fdt_high 0x4A3E0000", 10)
    uboot(c, "setenv bootargs console=ttyMSM0,115200n8 rootwait panic=0 pcie_ports=compat", 10)
    print(">> booting the RAM installer")
    c.mark()
    c.send("bootm 0xA0000000#config@1", uboot=True)
    c.wait(60, lambda c: re.search(r"Starting kernel", c.buf),
           abort=(("bootm failed", re.compile(r"ERROR|Bad Linux|Wrong Image|can't get kernel")),))
    c.mark()
    c.wait(300, lambda c: ACTIVATE.search(c.buf),
           abort=(("the installer crashed (panic=0 holds it; power-cycle)", re.compile(r"Kernel panic")),))
    c.send("")
    c.mark()
    c.wait(30, lambda c: SHELL.search(c.tail()))
    print(">> RAM installer shell")


def install(c, dry, yes):
    facts = shell(c, "cat /tmp/sysinfo/board_name; grep -c ubi.mtd= /proc/cmdline; cat /sys/class/net/eth0/address")
    f = [x.strip() for x in facts.split("\n") if x.strip()]
    if len(f) < 3 or f[0] != "arista,c360" or f[1] != "0":
        raise Stop("not the C-360 RAM installer: %r" % f)
    mac = f[2].replace(":", "").lower()
    print(">> unit MAC %s" % f[2])
    for _ in range(30):
        if "/dev/sd" in shell(c, "ls /dev/sd* 2>/dev/null"):
            break
        time.sleep(1)
    else:
        raise Stop("Linux does not see the USB stick")
    if dry:
        cmd = "arista-c360-install --dry-run"
    else:
        if not yes:
            answer = input("Write OpenWrt to this C-360 (MAC %s)? Type its last four hex digits (%s): "
                           % (f[2], mac[-4:])).strip().lower()
            if answer != mac[-4:]:
                raise Stop("not confirmed; nothing was written")
        cmd = "arista-c360-install --yes"
    print(">> running %s (the backup takes a few minutes)" % cmd)
    c.mark()
    c.send(cmd)
    m = c.wait(3600, lambda c: RESULT.search(c.buf))
    c.wait(30, lambda c: SHELL.search(c.tail()))
    if m.group(1) != "OK":
        raise Stop("arista-c360-install: FAILED%s" % m.group(2))
    print(">> arista-c360-install: OK%s" % m.group(2))
    return mac


def first_boot(c):
    print(">> rebooting into OpenWrt from NAND (not stopping U-Boot)")
    c.mark()
    c.send("reboot")
    c.wait(120, lambda c: UBOOT_BANNER.search(c.buf))
    m = c.wait(240, lambda c: CMDLINE.search(c.buf))
    if "ubi.mtd=ubi" not in m.group(1):
        raise Stop("the AP booted something other than OpenWrt from NAND: %s" % m.group(1))
    c.mark()
    c.wait(300, lambda c: ACTIVATE.search(c.buf))
    print(">> OpenWrt is running from NAND")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", required=True, help="the serial port of the console cable, e.g. COM6 or /dev/ttyUSB0")
    ap.add_argument("--dry-run", action="store_true", help="back up and check only; write nothing")
    ap.add_argument("--yes", action="store_true", help="do not ask for the MAC digits before writing")
    ap.add_argument("--at-prompt", action="store_true", help="U-Boot is already stopped at IPQ807x#")
    a = ap.parse_args()

    log = "c360-flash-%s.log" % time.strftime("%Y%m%d-%H%M%S")
    print("console log: %s" % log)
    c = Console(a.port, log)
    try:
        if a.at_prompt:
            c.mark()
            c.send("\x03", uboot=True)
            c.wait(5, at_uboot_prompt)
        else:
            stop_uboot(c)
        boot_installer(c)
        install(c, a.dry_run, a.yes)
        if a.dry_run:
            print("Dry run complete: nothing was written. The AP is in the RAM installer; "
                  "power-cycle it to leave.")
        else:
            first_boot(c)
            print("Done. OpenWrt's defaults: LAN on eth0 at 192.168.1.1, Wi-Fi off, no root password.")
    except Stop as e:
        print("STOPPED: %s" % e)
        print("Nothing further was sent. The console log is %s." % log)
        sys.exit(1)
    except KeyboardInterrupt:
        print("interrupted; nothing further was sent")
        sys.exit(130)


if __name__ == "__main__":
    main()

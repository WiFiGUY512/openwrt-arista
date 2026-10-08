#!/usr/bin/env python3
"""Exercise c360-flash.py against a simulated C-360 console (no hardware).

The fake device behaves like Arista's U-Boot (a 2 s window for the stop key,
echo, IPQ807x# prompts, usb/fatls/fatload output, a vendor boot when the
window is missed) and like the OpenWrt RAM installer and first NAND boot.
Each scenario checks what the driver concluded and what it sent: never
saveenv, never the stop key after the install's reboot.

	python test_c360_flash.py
"""
import importlib.util
import io
import os
import sys
import time
import contextlib

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("c360flash", os.path.join(HERE, "c360-flash.py"))
cf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cf)

KEY = cf.KEY
ITB = 21455528


class FakeC360:
    """A scripted console. Output is queued with due times; input is echoed
    the way U-Boot and ash echo it."""

    def __init__(self, board="arista,c360", install_result="OK", stick=True, key_window=2.0):
        self.board, self.install_result, self.stick, self.key_window = board, install_result, stick, key_window
        self.q = []                 # [due, bytes]
        self.sent = []              # everything written to the device
        self.line = ""
        self.state = "off"
        self.banner_at = None
        self.keybuf = ""
        self.after_reboot = False
        self.power_on(delay=0.3)

    # queue helpers
    def emit(self, text, delay=0.0):
        due = max([time.time()] + [d for d, _ in self.q]) + delay
        self.q.append([due, text.encode()])

    def power_on(self, delay=0.0):
        self.state = "countdown"
        self.emit("\x00\xffPBL garbage\r\n", delay)
        self.emit("\r\nU-Boot 2016.01 (May 20 2024 - 10:00:00)\r\n\r\nDRAM:  2 GiB\r\n", 0.2)
        self.banner_at = None

    # pyserial-like interface
    @property
    def in_waiting(self):
        now = time.time()
        return sum(len(b) for d, b in self.q if d <= now)

    def read(self, n=1):
        now = time.time()
        out = b""
        while self.q and self.q[0][0] <= now:
            out += self.q.pop(0)[1]
        if not out:
            time.sleep(0.01)
        self.tick()
        return out

    def tick(self):
        now = time.time()
        if self.state == "countdown":
            if self.banner_at is None and not self.q:
                self.banner_at = now
            if self.banner_at and now - self.banner_at > self.key_window:
                # missed: vendor autoboot, whose script runs saveenv
                self.state = "vendor"
                self.emit("Saving Environment to FLASH...\r\nStarting kernel ...\r\n\r\nBooting Linux on physical CPU 0x0\r\n")

    def write(self, data):
        self.sent.append(data)
        text = data.decode("utf-8", "replace")
        if self.state == "countdown" and self.banner_at and time.time() - self.banner_at > self.key_window:
            self.tick()                         # the window has passed: too late
        if self.state == "countdown":
            self.keybuf += text
            if self.banner_at is None:
                self.banner_at = time.time()
            if KEY in self.keybuf:
                self.state = "uboot"
                rest = self.keybuf.split(KEY, 1)[1]
                self.emit("\r\nIPQ807x# " + rest)
            return len(data)
        if self.state == "uboot":
            if text == "\x03":
                self.line = ""
                self.emit("<INTERRUPT>\r\nIPQ807x# ")
                return len(data)
            for ch in text:
                if ch == "\r":
                    self.uboot_cmd(self.line)
                    self.line = ""
                else:
                    self.line += ch
                    self.emit(ch)
            return len(data)
        if self.state in ("activate", "shell"):
            for ch in text:
                if ch == "\r":
                    cmd, self.line = self.line, ""
                    self.emit("\r\n")
                    self.shell_cmd(cmd)
                else:
                    self.line += ch
                    self.emit(ch)
            return len(data)
        return len(data)

    def uboot_cmd(self, cmd):
        out = {
            "usb start": "starting USB...\r\nUSB0:   scanning bus 0 for devices... 2 USB Device(s) found\r\n"
                         "       scanning usb for storage devices... %d Storage Device(s) found\r\n" % (1 if self.stick else 0),
            "fatls usb 0:1 c360": "   21455528   initramfs.itb\r\n   19660800   factory.ubi\r\n"
                                  "        333   sha256sums\r\n\r\n3 file(s), 0 dir(s)\r\n",
            "fatload usb 0:1 0xA0000000 c360/initramfs.itb": "reading c360/initramfs.itb\r\n"
                                                              "%d bytes read in 1312 ms (15.6 MiB/s)\r\n" % ITB,
        }.get(cmd, "")
        if cmd.startswith("bootm"):
            self.state = "booting"
            self.emit("\r\n## Loading kernel from FIT Image at a0000000 ...\r\nStarting kernel ...\r\n\r\n")
            self.emit("[    0.000000] Kernel command line: console=ttyMSM0,115200n8 rootwait panic=0 pcie_ports=compat\r\n", 0.2)
            self.emit("[   12.000000] init: Console is alive\r\n", 0.3)
            self.emit("\r\nPlease press Enter to activate this console.\r\n", 0.2)
            self.state = "activate"
            return
        self.emit("\r\n" + out + "IPQ807x# ")

    def shell_cmd(self, cmd):
        if self.state == "activate":
            self.state = "shell"
            self.emit("\r\n\r\nBusyBox v1.37.0 built-in shell (ash)\r\n\r\nroot@OpenWrt:/# ")
            return
        if cmd.startswith("cat /tmp/sysinfo/board_name"):
            self.emit("%s\r\n0\r\n00:11:22:33:44:55\r\n" % self.board)
        elif cmd.startswith("ls /dev/sd"):
            self.emit("/dev/sda\r\n/dev/sda1\r\n" if self.stick else "")
        elif cmd.startswith("arista-c360-install"):
            self.emit("c360-install: C-360, running from RAM; Arista runs from slot 1\r\n", 0.1)
            self.emit("c360-install: backup complete and verified: backup-001122334455-x\r\n", 0.3)
            if "--dry-run" in cmd:
                self.emit("C360-INSTALL-RESULT: OK dry-run backup=backup-001122334455-x\r\n", 0.1)
            elif self.install_result == "OK":
                self.emit("c360-install:   volume kernel: reads back identical\r\n", 0.2)
                self.emit("C360-INSTALL-RESULT: OK installed backup=backup-001122334455-x\r\n", 0.1)
            else:
                self.emit("C360-INSTALL-RESULT: FAILED: slot 0 volume kernel reads back wrong\r\n", 0.2)
        elif cmd == "reboot":
            self.after_reboot = True
            self.state = "rebooting"
            self.emit("[  200.0] reboot: Restarting system\r\n", 0.1)
            self.emit("\r\nU-Boot 2016.01 (May 20 2024 - 10:00:00)\r\n", 0.3)
            self.emit("Starting kernel ...\r\n", 2.2)   # the window passes untouched
            self.emit("[    0.000000] Kernel command line: console=ttyMSM0,115200n8 ubi.mtd=ubi rootwait panic=10 pcie_ports=compat\r\n", 0.2)
            self.emit("\r\nPlease press Enter to activate this console.\r\n", 0.3)
            return
        self.emit("root@OpenWrt:/# ")


def run(name, fake, argv, expect_exit, expect_text, inputs=()):
    cf.serial.Serial = lambda *a, **k: fake
    sys.argv = ["c360-flash.py", "--port", "SIM"] + argv
    out = io.StringIO()
    feed = iter(inputs)
    cf.input = lambda prompt="": (out.write(prompt), next(feed))[1]
    code = 0
    with contextlib.redirect_stdout(out):
        try:
            cf.main()
        except SystemExit as e:
            code = e.code or 0
    text = out.getvalue()
    sent = b"".join(fake.sent).decode("utf-8", "replace")
    problems = []
    if code != expect_exit:
        problems.append("exit %s, wanted %s" % (code, expect_exit))
    if expect_text not in text:
        problems.append("no %r in the output" % expect_text)
    if "saveenv" in sent.lower():
        problems.append("SENT saveenv")
    if fake.after_reboot:
        after = b"".join(fake.sent[[i for i, s in enumerate(fake.sent) if s.startswith(b"reboot")][0] + 1:])
        if KEY.encode() in after:
            problems.append("sent the stop key after the install's reboot")
    print("%-34s %s" % (name, "ok" if not problems else "FAIL: " + "; ".join(problems)))
    if problems:
        print(text[-1500:])
    return not problems


def main():
    for f in os.listdir("."):
        if f.startswith("c360-flash-") and f.endswith(".log"):
            pass
    os.chdir(os.environ.get("TMP", "."))
    results = [
        run("install, confirmed by MAC digits", FakeC360(), [], 0, "OpenWrt is running from NAND", inputs=["4455"]),
        run("install, --yes", FakeC360(), ["--yes"], 0, "OpenWrt is running from NAND"),
        run("dry run", FakeC360(), ["--dry-run"], 0, "Dry run complete: nothing was written"),
        run("wrong digits: nothing written", FakeC360(), [], 1, "not confirmed; nothing was written", inputs=["0000"]),
        run("missed U-Boot window", FakeC360(key_window=0.0), ["--yes"], 1, "missed U-Boot's window"),
        run("not a C-360", FakeC360(board="netgear,r7800"), ["--yes"], 1, "not the C-360 RAM installer"),
        run("no USB stick", FakeC360(stick=False), ["--yes"], 1, "found no USB storage"),
        run("install fails on the AP", FakeC360(install_result="FAILED"), ["--yes"], 1, "arista-c360-install: FAILED"),
    ]
    print("%d/%d scenarios passed" % (sum(results), len(results)))
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()

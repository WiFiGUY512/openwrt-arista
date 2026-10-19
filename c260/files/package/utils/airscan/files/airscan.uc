#!/usr/bin/ucode -S
// airscan: spectrum, BSS and client survey on a dedicated scan radio.
//
// Runs only on the board's dedicated scan radio (Arista C-360: the QCN9072
// multifunction card, PCI 0001:01:00.0, ath11k; Arista C-260: the QCA988x,
// PCI 0000:01:00.0, ath10k). Serving radios are never touched: no
// interface, scan, retune or spectral command is ever issued on another phy.
// The radio is taken out of netifd's control (wifi-device disabled) so that a
// "wifi reload" cannot tear down the interfaces airscan creates on it, and
// gives no country of its own: the serving radios set the AP's.
//
// Jobs, one at a time, all receive-only on the scan radio:
//   spectral  ath10k/ath11k spectral scan, 20 MHz windows on 2.4/5 GHz, 80 MHz
//             on 6 GHz (where the radio has it)
//   bss       passive scan of every channel the radio supports (2.4/5/6 GHz),
//             then of the 6 GHz channels again, long enough on each for a beacon
//   clients   monitor capture, one dwell per channel that has networks on it
//   ble       Bluetooth LE survey on the board's BLE controller (hci0), on its
//             own timer: a different radio, so it never waits for or delays
//             the Wi-Fi jobs (airscan-ble, through the kernel's mgmt socket)
// Detections (events): wired rogue (a BSS that relays our wired ARP probes but
// is not ours), evil twin (our SSID on a BSS that never relays them), own BSSID
// heard on a channel the AP is not using, deauth/disassoc floods.
// Results: ubus object "airscan" and JSON files under /tmp/airscan.
//
// A board with a BLE controller and no scan radio (Arista W-318: its Nordic
// nRF52833) runs the BLE survey alone, under the same ubus object: its radio
// jobs answer that there is no scan radio, and status says "ble only".
//
// The radio can be lent (ubus "lend"): another service, a client test for
// one, borrows it for a while. airscan takes its own interfaces off it, runs
// no job on it, and has it back when told ("reclaim") or when the loan runs
// out. Its jobs keep their times, so a loan costs no scan or sweep of its own.
//
// A scan radio that hears nothing is deaf, and airscan binds its driver
// again, which is what brings it back. The C-360's went deaf at a sweep once
// it had been a client on a DFS channel while airscan was stopped and started
// around the test (2026-10-11); lent instead, it did not (four times of four,
// 2026-10-15). A look still follows every sweep.

'use strict';

import * as fs from 'fs';
import * as uloop from 'uloop';
import * as ubus from 'ubus';
import * as uci from 'uci';
import * as struct from 'struct';
import * as socket from 'socket';

const BOARDS = { "arista,c260": "0000:01:00.0", "arista,c-260": "0000:01:00.0", "arista,c360": "0001:01:00.0", "arista,c-360": "0001:01:00.0", "arista,w-118": "0000:01:00.0" };
// boards with a BLE controller and no scan radio: the BLE survey alone
const BLE_BOARDS = { "arista,w318": true, "arista,w-318": true };
const OUT = "/tmp/airscan";
const MON = "as-mon0", STA = "as-sta0";
const PIDFILE = "/var/run/airscan.pid";
const MYPID = +fs.readlink("/proc/self");
const FFT = "/usr/libexec/airscan-fft";
const BLE = "/usr/libexec/airscan-ble";

const LOAN_MOST = 300;     // seconds the radio is lent for at the most
const HEAL_EVERY = 60;     // seconds between two tries at binding the driver again
const HEAL_MOST = 6;       // tries in an hour at the most
const HEAL_LATER = 3600;   // seconds before another, after one that did not bring the radio back

let conn, cfg, radio = {}, state = "idle", busy = false;
let loan = { until: 0, to: null };
let heal = { count: 0, failed: 0, last: 0, next: 0, check: false, times: [], told: false };
let results = { spectrum: null, bss: null, clients: {}, ble: {} };
let last = { spectral: 0, bss: 0, clients: 0, ble: 0 };
let next = { spectral: 0, bss: 0, ble: 0 };
let errors = [], events = [], seen_events = {};
let pending = { spectral: null, bss: false };

function log(msg) {
	system(["logger", "-t", "airscan", msg]);
}

// later: fn, once, in ms. A uloop timer that has fired is not freed until it
// is cancelled, nor is all its callback holds; this one cancels itself.
function later(ms, fn) {
	return uloop.timer(ms, function() { this.cancel(); fn(); });
}

function note_error(msg) {
	log(msg);
	push(errors, { time: time(), msg });
	if (length(errors) > 20) shift(errors);
}

// one decimal place; ucode has no rounding builtin
function r1(v) {
	return int(v * 10 + (v < 0 ? -0.5 : 0.5)) / 10.0;
}

function sh(cmd) {
	return system(cmd + " >/dev/null 2>&1");
}

function write_json(name, obj) {
	fs.writefile(`${OUT}/${name}.json.tmp`, sprintf("%J", obj));
	fs.rename(`${OUT}/${name}.json.tmp`, `${OUT}/${name}.json`);
}

// Detections. Each distinct (type, bssid) is reported once per hour.
function add_event(ev) {
	let key = `${ev.type}/${ev.bssid}`;
	if (seen_events[key] && time() - seen_events[key] < 3600) return;
	for (let k, t in seen_events)
		if (time() - t >= 3600) delete seen_events[k];
	seen_events[key] = time();
	ev.time = time();
	push(events, ev);
	if (length(events) > 200) shift(events);
	log(`${ev.type}: ${ev.bssid} "${ev.ssid ?? ""}" ${ev.freq} MHz${ev.frames ? ` (${ev.frames} frames)` : ""}`);
	write_json("events", { time: time(), list: events });
}

function load_config() {
	let c = uci.cursor();
	let s = c.get_all("airscan", "main") || {};
	let list = (v) => (type(v) == "array" ? v : (v ? [ v ] : []));
	return {
		enabled: s.enabled != "0",
		spectral_interval: +(s.spectral_interval || 900),
		spectral_samples: +(s.spectral_samples || 2048),
		spectral_fft: +(s.spectral_fft || 256),
		bss_interval: +(s.bss_interval || 300),
		client_dwell: +(s.client_dwell || 1000),
		client_expire: +(s.client_expire || 900),
		wired_probe: s.wired_probe != "0",
		probe_evidence: +(s.probe_evidence || 5),
		trusted_ssid: list(s.trusted_ssid),
		trusted_bssid: map(list(s.trusted_bssid), (b) => lc(b)),
		ble_enabled: s.ble_enabled != "0",
		ble_interval: +(s.ble_interval || 120),
		ble_duration: +(s.ble_duration || 10),
		ble_expire: +(s.ble_expire || 900),
	};
}

// ---------------------------------------------------------------- radio

function board_name() {
	return trim(fs.readfile("/tmp/sysinfo/board_name") || "");
}

function find_phy(pci) {
	for (let p in fs.lsdir("/sys/class/ieee80211") || []) {
		let dev = fs.readlink(`/sys/class/ieee80211/${p}/device`) || "";
		if (substr(dev, -length(pci)) == pci)
			return p;
	}
	return null;
}

// Keep netifd off the scan radio, and mark it as the scan radio (airscan
// '1'), which the init script takes away when airscan is turned off. Only the
// scan radio's own section is touched.
// The scan radio has no country option: netifd sets up a disabled radio too,
// and its country goes to the whole system (iw reg set). One unlike the
// serving radios' (OpenWrt gives a 6 GHz radio '00') switched the AP's
// regulatory domain in the middle of every boot; on a C-360 the IPQ8074
// refused it and the 5 GHz radar check failed. Without one the radio follows
// the country the serving radios set; turned off, airscan gives it theirs.
function release_from_netifd(pci) {
	let c = uci.cursor();
	let taken = false, changed = false;
	c.foreach("wireless", "wifi-device", (s) => {
		if (substr(s.path || "", -length(pci)) != pci) return;
		if (s.disabled != "1") {
			c.set("wireless", s[".name"], "disabled", "1");
			taken = true;
		}
		if (s.airscan != "1") {
			c.set("wireless", s[".name"], "airscan", "1");
			changed = true;
		}
		if (s.country != null) {
			c.delete("wireless", s[".name"], "country");
			log(`${s[".name"]}: its own country (${s.country}) taken off; the serving radios set the AP's`);
			changed = true;
		}
		radio.section = s[".name"];
	});
	if (taken || changed)
		c.commit("wireless");
	if (taken) {
		log(`took ${radio.section} (${pci}) out of netifd for scanning`);
		sh(`ubus call network.wireless down '{"device":"${radio.section}"}'`);
	}
}

function resolve_radio() {
	let pci = BOARDS[board_name()];
	if (!pci) return false;
	radio.pci = pci;
	radio.phy = find_phy(pci);
	if (!radio.phy) return false;
	// ath10k takes at most 255 samples a trigger (spectral_count), ath11k more
	radio.driver = "ath11k";
	radio.per_trigger = 0;
	for (let d in [ "ath11k", "ath10k" ])
		if (fs.access(`/sys/kernel/debug/ieee80211/${radio.phy}/${d}`)) radio.driver = d;
	if (radio.driver == "ath10k") radio.per_trigger = 255;
	radio.debugfs = `/sys/kernel/debug/ieee80211/${radio.phy}/${radio.driver}`;
	radio.spectral = !!fs.access(`${radio.debugfs}/spectral_scan_ctl`, "w");
	return true;
}

function own_ifaces() {
	let out = [];
	for (let i in fs.lsdir(`/sys/class/ieee80211/${radio.phy}/device/net`) || [])
		push(out, i);
	return out;
}

function iface_up(name, kind) {
	if (!fs.access(`/sys/class/net/${name}`)) {
		if (sh(`iw phy ${radio.phy} interface add ${name} type ${kind}`) != 0) return false;
	}
	return sh(`ip link set ${name} up`) == 0;
}

function iface_del(name) {
	if (fs.access(`/sys/class/net/${name}`)) {
		sh(`ip link set ${name} down`);
		sh(`iw dev ${name} del`);
	}
}

// ---------------------------------------------------------------- spectral

function spectral_write(file, val) {
	return fs.writefile(`${radio.debugfs}/${file}`, `${val}\n`) != null;
}

// Whether the radio has 6 GHz channels at all (the C-260's QCA988x has none).
// Its own test: freqs_6g, further down, is not yet declared here.
function has_6g() {
	let p = fs.popen(`iw phy ${radio.phy} channels 2>/dev/null`), yes = false;
	if (!p) return false;
	for (let line in split(p.read("all") || "", "\n")) {
		let m = match(line, /^[ \t]*\* ([0-9]+) MHz/);
		if (m && +m[1] >= 5950) yes = true;
	}
	p.close();
	return yes;
}

// 2.4 GHz and 5 GHz: 20 MHz windows (the C-360 scan radio's 5 GHz band has no
// 40/80 MHz support). 6 GHz, on a radio with 6 GHz channels: the fourteen
// 80 MHz blocks of channels 1-221, the 40 MHz block of 225 and 229, and 233.
function spectral_windows() {
	let w = [];
	let add20 = (band, f) => push(w, { band, ctrl: f, width: 20, center: f });
	for (let f in [ 2412, 2432, 2452, 2462 ]) add20("2g", f);
	for (let r in [ [5180, 5320], [5500, 5720], [5745, 5885] ])
		for (let f = r[0]; f <= r[1]; f += 20) add20("5g", f);
	if (!has_6g()) return w;
	for (let k = 0; k < 14; k++)
		push(w, { band: "6g", ctrl: 5955 + 80 * k, width: 80, center: 5985 + 80 * k });
	push(w, { band: "6g", ctrl: 7075, width: 40, center: 7085 });
	add20("6g", 7115);
	return w;
}

// The FFT size the radio takes: ath10k at most 256 bins.
function fft_size() {
	return radio.driver == "ath10k" ? min(cfg.spectral_fft, 256) : cfg.spectral_fft;
}

function set_freq(win) {
	if (win.width == 20) return sh(`iw dev ${MON} set freq ${win.ctrl}`) == 0;
	return sh(`iw dev ${MON} set freq ${win.ctrl} ${win.width} ${win.center}`) == 0;
}

// Busy share per window: the share of samples whose in-band power is at or
// above the 802.11 preamble-detect level, -82 dBm per 20 MHz (+3 dB per
// doubling of width), from airscan-fft's power histogram (noise + rssi, the
// radio's uncalibrated in-band estimate, 1 dB steps). A floor relative to the
// window misreads the QCN9074: a quiet channel reports either exactly the
// noise value or a tight cluster 12-19 dB above it (gain state, not traffic).
// The histogram stays in the output so other thresholds can be applied.
const BUSY_DBM = -82;

function apply_busy(windows) {
	for (let w in windows) {
		let thr = BUSY_DBM + { "20": 0, "40": 3, "80": 6, "160": 9 }[`${w.width}`];
		let n = 0;
		for (let i = 0; i < length(w.pwr_hist); i++)
			if (w.pwr_lo + i >= thr) n += w.pwr_hist[i];
		w.busy_pct = r1(100.0 * n / w.samples);
	}
}

// Disable -> retune -> settle -> arm -> trigger -> wait -> disable -> drain.
// Spectral is never left armed across a retune: with QCN9074 firmware
// WLAN.HK.2.5.r4 that crashed the card (2026-10-07).
function run_spectral(done, only_band) {
	if (!radio.spectral) { done(); return; }
	if (!fs.access(FFT, "x")) { note_error(`spectral: ${FFT} missing`); done(); return; }
	if (!iface_up(MON, "monitor")) { note_error("spectral: monitor interface failed"); done(); return; }
	let wins = filter(spectral_windows(), (w) => !only_band || w.band == only_band);
	let windows = [], i = 0, skipped = [], total = 0, fft = fft_size();
	spectral_write("spectral_scan_ctl", "disable");
	spectral_write("spectral_bins", fft);
	fs.readfile(`${radio.debugfs}/spectral_scan0`);

	function finish() {
		spectral_write("spectral_scan_ctl", "disable");
		apply_busy(windows);
		for (let w in windows) w.time = time();
		// A sweep of one band replaces only that band's windows.
		let old = results.spectrum;
		// (band_of is declared further down: the bands are worked out here)
		if (only_band && old) {
			windows = [ ...filter(old.windows, (w) => w.band != only_band), ...windows ];
			skipped = [ ...filter(old.skipped || [], (f) => (f < 3000 ? "2g" : f < 5950 ? "5g" : "6g") != only_band), ...skipped ];
		}
		results.spectrum = {
			time: time(), phy: radio.phy, fft, samples_per_window: cfg.spectral_samples,
			busy_dbm_20mhz: BUSY_DBM, skipped, windows: sort(windows, (a, b) => a.center - b.center),
		};
		last.spectral = time();
		write_json("spectrum", results.spectrum);
		log(`spectral sweep${only_band ? ` (${only_band})` : ""}: ${length(wins) - length(skipped)} windows, ${total} samples`);
		// A look after every sweep: it was at a sweep that this radio went deaf.
		pending.bss = true;
		done();
	}

	function step() {
		if (i >= length(wins)) { finish(); return; }
		let w = wins[i++];
		spectral_write("spectral_scan_ctl", "disable");
		if (!set_freq(w)) {
			// 80 or 40 MHz not allowed here (e.g. a disabled edge channel): fall back to 20 MHz
			if (w.width > 20) {
				for (let k = w.width / 20 - 1; k >= 0; k--)
					splice(wins, i, 0, { band: w.band, ctrl: w.ctrl + 20 * k, width: 20, center: w.ctrl + 20 * k });
			}
			else push(skipped, w.ctrl);
			later(10, step);
			return;
		}
		// One trigger for all the window's samples, or bursts of at most
		// radio.per_trigger (ath10k: 255), each run out and disabled before
		// the next: a trigger on top of a running one loses samples (C-260).
		later(300, () => {
			let want = +cfg.spectral_samples, per = radio.per_trigger || want;
			function burst() {
				let n = min(per, want);
				want -= n;
				spectral_write("spectral_scan_ctl", "manual");
				spectral_write("spectral_count", n);
				spectral_write("spectral_scan_ctl", "trigger");
				later(int(n * 0.23) + (radio.per_trigger ? 150 : 250), () => {
					spectral_write("spectral_scan_ctl", "disable");
					if (want > 0) { burst(); return; }
					let tmp = `${OUT}/.win.json`;
					uloop.process("/bin/sh", [ "-c", `exec ${FFT} ${radio.debugfs}/spectral_scan0 > ${tmp}` ], {}, (code) => {
						let got = [];
						if (code == 0)
							try { got = json(fs.readfile(tmp) || "[]"); }
							catch (e) { note_error(`spectral: ${FFT} wrote what is not JSON: ${e.message}`); }
						fs.unlink(tmp);
						for (let wdw in got) { wdw.band = w.band; push(windows, wdw); total += wdw.samples; }
						later(10, step);
					});
				});
			}
			burst();
		});
	}
	step();
}

// ---------------------------------------------------------------- bss

// Own MACs. Interface addresses map to the frequency the interface runs on, so a
// beacon with an own BSSID on another frequency can be told apart (spoofing).
function local_macs() {
	let m = {};
	for (let p in fs.lsdir("/sys/class/ieee80211") || []) {
		let a = trim(fs.readfile(`/sys/class/ieee80211/${p}/macaddress`) || "");
		if (a) m[lc(a)] = true;
		for (let i in fs.lsdir(`/sys/class/ieee80211/${p}/device/net`) || []) {
			let b = lc(trim(fs.readfile(`/sys/class/net/${i}/address`) || ""));
			if (!b || i == MON || i == STA) continue;
			let info = fs.popen(`iw dev ${i} info 2>/dev/null`);
			let f = info ? match(info.read("all") || "", /channel [0-9]+ \(([0-9]+) MHz\)/) : null;
			if (info) info.close();
			m[b] = f ? +f[1] : true;
		}
	}
	return m;
}

// SSIDs the AP itself serves (enabled AP interfaces on the other radios).
function own_ssids() {
	let out = [], c = uci.cursor();
	c.foreach("wireless", "wifi-iface", (s) => {
		if (s.disabled == "1" || s.mode != "ap" || s.device == radio.section || !s.ssid) return;
		if (c.get("wireless", s.device, "disabled") == "1") return;
		if (index(out, s.ssid) < 0) push(out, s.ssid);
	});
	return out;
}

function chan_of(f) {
	if (f < 3000) return f == 2484 ? 14 : int((f - 2407) / 5);
	if (f < 5950) return int((f - 5000) / 5);
	return int((f - 5950) / 5);
}

function parse_iw_scan(text) {
	let list = [], cur = null, sect = "";
	for (let line in split(text, "\n")) {
		let m;
		if ((m = match(line, /^BSS ([0-9a-f:]{17})/))) {
			cur = { bssid: m[1], ssid: "", security: [], gen: "legacy", width: 20 };
			push(list, cur);
			sect = "";
			continue;
		}
		if (!cur) continue;
		let t = trim(line);
		if ((m = match(t, /^freq: ([0-9.]+)/))) { cur.freq = int(+m[1]); cur.channel = chan_of(cur.freq); }
		else if ((m = match(t, /^signal: (-?[0-9.]+) dBm/))) cur.signal = +m[1];
		// the channel the beacon says it is on: its HT operation's primary
		// channel (2.4 and 5 GHz; this image's iw does not print the DS
		// parameter set, a fuller one does)
		else if ((m = match(t, /^DS Parameter set: channel ([0-9]+)/))) cur.says_channel = +m[1];
		else if ((m = match(t, /^\* primary channel: ([0-9]+)/)) && !cur.says_channel) cur.says_channel = +m[1];
		else if ((m = match(t, /^SSID: (.*)$/))) cur.ssid = m[1];
		else if ((m = match(t, /^last seen: ([0-9]+) ms ago/))) cur.age_ms = +m[1];
		else if (match(t, /^RSN:/)) sect = "rsn";
		else if (match(t, /^WPA:/)) { sect = "wpa"; push(cur.security, "WPA"); }
		else if (sect == "rsn" && (m = match(t, /^\* Authentication suites: (.*)$/))) {
			for (let a in split(m[1], " ")) {
				let x = { "PSK": "WPA2-PSK", "SAE": "WPA3-SAE", "IEEE 802.1X": "802.1X", "802.1X": "802.1X", "FT/PSK": "FT-PSK", "FT/SAE": "FT-SAE", "OWE": "OWE" }[a];
				if (x && index(cur.security, x) < 0) push(cur.security, x);
			}
		}
		else if (match(t, /^EHT capabilities:/)) cur.gen = "wifi7";
		else if (match(t, /^HE capabilities:/) && cur.gen != "wifi7") cur.gen = "wifi6";
		else if (match(t, /^VHT capabilities:/) && !(cur.gen in [ "wifi6", "wifi7" ])) cur.gen = "wifi5";
		else if (match(t, /^HT capabilities:/) && cur.gen == "legacy") cur.gen = "wifi4";
		else if (match(t, /^\* secondary channel offset: (above|below)/) && cur.width < 40) cur.width = 40;
		else if ((m = match(t, /^\* channel width: ([0-9]) \(/))) {
			if (+m[1] == 1) cur.width = 80;
			else if (+m[1] >= 2) cur.width = 160;
		}
		else if ((m = match(t, /^\* center freq segment 2: ([0-9]+)/)) && +m[1] > 0 && cur.width == 80) cur.width = 160;
	}
	for (let b in list) if (b.freq >= 5950) b.width = null;   // 6 GHz width is in HE/EHT operation, not decoded by iw
	return list;
}

function band_of(f) {
	return f < 3000 ? "2g" : (f < 5950 ? "5g" : "6g");
}

// A passive scan listens on each 6 GHz channel for 30 ms only (ath11k's
// dwell_time_passive_6g; 150 ms on 2.4 and 5 GHz), and a beacon comes every
// 102.4 ms, so a look heard a 6 GHz network about one time in three
// (2026-10-14). The 6 GHz channels are scanned again, DWELL_6G on each: three
// tries of that each heard a second C-360's 6 GHz network close by.
const DWELL_6G = 120;

// The radio's 6 GHz channels, those not disabled.
function freqs_6g() {
	let out = [], p = fs.popen(`iw phy ${radio.phy} channels 2>/dev/null`);
	if (!p) return out;
	for (let line in split(p.read("all") || "", "\n")) {
		let m = match(line, /^[ \t]*\* ([0-9]+) MHz \[[0-9]+\](.*)$/);
		if (m && +m[1] >= 5950 && !match(m[2], /disabled/)) push(out, +m[1]);
	}
	p.close();
	return out;
}

// ---------------------------------------------------------------- wired probe

// Rogue and evil-twin test (the wired-probe method). The AP sends an ARP probe on every
// L2 domain it is on (each bridge, and each VLAN device or port that is not in
// a bridge), sourced from its own MAC. RFC 5227 probe: sender IP 0.0.0.0, so no
// ARP cache changes; target 169.254.255.<VLAN low byte>, a reserved block that
// nobody holds. A BSS that relays the probe over the air is bridged into our
// LAN: the source address of a FromDS frame is sent in the clear even under
// WPA2/WPA3. Our SSID on a BSS that never relays it (after probe_evidence
// dwells in which the BSS was heard) is an evil twin; a foreign or hidden SSID
// that relays it is a rogue on our wire. Each domain's probe is padded to
// 60 + 16 * (domain index) bytes, so the size of a relayed frame tells which
// VLAN that BSS bridges even when the frame is encrypted.
let wp = { sock: null, domains: [], macs: {}, bss: {} };
const LLC_ARP = "\xaa\xaa\x03\x00\x00\x00\x08\x06";   // LLC/SNAP header of an ARP frame

function l2_domains() {
	let vid = {}, out = [], macs = {};
	for (let l in split(fs.readfile("/proc/net/vlan/config") || "", "\n")) {
		let m = match(l, /^([^ |]+) *\| *([0-9]+) *\|/);
		if (m) vid[m[1]] = +m[2];
	}
	for (let d in fs.lsdir("/sys/class/net") || []) {
		let p = `/sys/class/net/${d}`;
		if (d == "lo" || fs.access(`${p}/phy80211`) || trim(fs.readfile(`${p}/type`) || "") != "1") continue;
		let mac = lc(trim(fs.readfile(`${p}/address`) || ""));
		if (mac) macs[mac] = true;
		if (fs.access(`${p}/brport`)) continue;            // its bridge carries it
		if (fs.access(`${p}/bonding_slave`)) continue;     // its bond carries it
		let st = trim(fs.readfile(`${p}/operstate`) || "");
		if (st != "up" && st != "unknown") continue;
		let v = vid[d] ?? 0;
		if (fs.access(`${p}/bridge`))
			for (let m in fs.lsdir(`${p}/brif`) || []) if (vid[m] != null) { v = vid[m]; break; }
		push(out, { dev: d, mac, vlan: v });
	}
	out = sort(out, (a, b) => (a.dev < b.dev) ? -1 : (a.dev > b.dev));
	// The network can change under us (a bond, a VLAN, a bridge's MAC): look
	// again every round, and say so when the domains change.
	if (sprintf("%J", out) != sprintf("%J", wp.domains))
		log("wired probe domains: " + join(", ", map(out, (x) => `${x.dev} (vlan ${x.vlan}, ${x.mac})`)));
	wp.domains = out;
	wp.macs = macs;
}

function send_probes() {
	l2_domains();
	if (!wp.sock) wp.sock = socket.create(socket.AF_PACKET, socket.SOCK_RAW, 0);
	if (!wp.sock) return;
	for (let k = 0; k < length(wp.domains); k++) {
		let d = wp.domains[k];
		let m = struct.pack("6B", ...map(split(d.mac, ":"), (x) => hex(x)));
		let f = struct.pack("6B", 255, 255, 255, 255, 255, 255) + m + struct.pack(">HHHBBH", 0x0806, 1, 0x0800, 6, 4, 1)
			+ m + struct.pack("4x6x") + struct.pack("4B", 169, 254, 255, d.vlan & 255);
		f += struct.pack(`${60 + 16 * k - length(f)}x`);
		wp.sock.send(f, 0, { family: socket.AF_PACKET, interface: d.dev, protocol: 0x0806, address: "ff:ff:ff:ff:ff:ff" });
	}
}

// Two BSSIDs of one physical AP: same octets 2-3, octet 1 equal unless either is
// locally administered (multi-BSSID schemes vary it), at most 4 bits apart in
// octets 4-6.
function siblings(a, b) {
	let x = map(split(a, ":"), (v) => hex(v)), y = map(split(b, ":"), (v) => hex(v));
	if (x[1] != y[1] || x[2] != y[2]) return false;
	if (!((x[0] | y[0]) & 2) && x[0] != y[0]) return false;
	let bits = 0;
	for (let i = 3; i < 6; i++)
		for (let d = x[i] ^ y[i]; d; d >>= 1) bits += d & 1;
	return bits <= 4;
}

function wired_verdict(bssid) {
	let w = wp.bss[bssid];
	if (!w) return null;
	if (w.hit_windows > 0) return true;
	return w.windows >= cfg.probe_evidence ? false : null;
}

// class: own, trusted, verified (ours, relays our probes), verified_sibling
// (ours, does not relay, but another BSSID of the same AP does: APs often
// filter broadcast ARP on one band), evil_twin, wired_rogue, spoofed (own
// BSSID on a foreign channel), unverified (ours, not enough evidence yet),
// neighbor.
//
// An own BSSID heard on another frequency is spoofed, but not:
// - where its beacon says the channel the AP really serves it on: that is the
//   AP's own beacon, heard off its channel by a scan radio a few centimetres
//   from the serving antennas (the C-260's: channel 11 heard on 6, 36 on 56),
//   not a copy sent on the channel it was heard on;
// - on the frequency the AP had it on when the look began (look_mine): the
//   AP moved that radio during the look (a channel switch);
// - where the entry is older than the look: cfg80211 keeps what it heard for
//   30 s, so a look just after a channel switch still lists the old one.
let look_mine = {}, look_secs = 0;

function classify(list) {
	let mine = local_macs();
	let ssids = [ ...cfg.trusted_ssid, ...own_ssids() ];
	let wired_bssids = filter(keys(wp.bss), (x) => wp.bss[x].hit_windows > 0);
	for (let b in list) {
		let w = wp.bss[b.bssid];
		let ours = !b.hidden && index(ssids, b.ssid) >= 0;
		let at = mine[b.bssid], was = look_mine[b.bssid];
		let freqs = filter([ at, was ], (f) => type(f) == "int");
		let stale = b.age_ms != null && b.age_ms > (look_secs + 2) * 1000;
		b.own = at != null || was != null;
		b.off_channel = b.own && length(freqs) > 0 && !(b.freq in freqs) && b.says_channel != null &&
			length(filter(freqs, (f) => band_of(b.freq) == band_of(f) && b.says_channel == chan_of(f))) > 0;
		b.spoofed = b.own && length(freqs) > 0 && !(b.freq in freqs) && !b.off_channel && !stale;
		b.wired = cfg.wired_probe ? wired_verdict(b.bssid) : null;
		b.probe_windows = w?.windows || 0;
		if (w?.vlans) b.wired_vlans = w.vlans;
		if (b.spoofed) b.class = "spoofed";
		else if (b.own) b.class = "own";
		else if (length(filter(cfg.trusted_bssid, (p) => substr(b.bssid, 0, length(p)) == p))) b.class = "trusted";
		else if (b.wired === true) b.class = ours ? "verified" : "wired_rogue";
		else if (ours) {
			let sib = filter(wired_bssids, (x) => siblings(x, b.bssid))[0];
			if (sib) { b.class = "verified_sibling"; b.sibling_of = sib; }
			else b.class = (b.wired === false || !cfg.wired_probe) ? "evil_twin" : "unverified";
		}
		else b.class = "neighbor";
		b.trusted = b.class in [ "own", "trusted", "verified" ];
		b.rogue_candidate = b.class in [ "spoofed", "evil_twin", "wired_rogue" ];
		if (b.rogue_candidate)
			add_event({ type: b.class, bssid: b.bssid, ssid: b.ssid, freq: b.freq, signal: b.signal, vlans: w?.vlans });
	}
}

function reclassify() {
	if (!results.bss) return;
	let list = results.bss.list;
	classify(list);
	let unlisted = [];
	for (let b, w in wp.bss) {
		if (!w.hit_windows || length(filter(list, (x) => x.bssid == b))) continue;
		let sib = filter(list, (x) => x.trusted && siblings(x.bssid, b))[0];
		push(unlisted, { bssid: b, freq: w.freq, vlans: w.vlans, sibling_of: sib?.bssid,
			class: sib ? "verified_sibling" : "wired_rogue" });
		if (!sib) add_event({ type: "wired_rogue", bssid: b, ssid: null, freq: w.freq, vlans: w.vlans });
	}
	results.bss.unlisted_wired = unlisted;
	write_json("bss", results.bss);
}

// on_air says whether the AP itself is on the air on another radio. Then a
// look that hears nothing, not even that, is a deaf radio and not a quiet
// place.
function on_air() {
	for (let mac, f in local_macs())
		if (type(f) == "int") return true;
	return false;
}

let heal_radio;   // assigned below: it closes the capture, which is declared further down

function run_bss(done) {
	cfg = load_config();
	iface_del(MON);
	if (!iface_up(STA, "managed")) { note_error("bss: station interface failed"); done(); return; }
	let tmp = `${OUT}/.scan.txt`;
	// Every channel, then the 6 GHz ones again, DWELL_6G on each. What the
	// second pass hears on 6 GHz stands for what the first did.
	let six = freqs_6g(), passes = [ "scan passive" ], heard = {};
	if (length(six)) push(passes, `scan freq ${join(" ", six)} duration ${DWELL_6G} passive`);
	// where the AP's own interfaces were as the look began (classify)
	let began = time(), before = local_macs();

	function looked() {
		iface_del(STA);
		look_mine = before;
		look_secs = time() - began;
		let list = values(heard);
		for (let b in list) {
			b.band = band_of(b.freq);
			b.hidden = b.ssid == "" || match(b.ssid, /^(\\x00)+$/) != null;
			if (!length(b.security)) push(b.security, "open");
		}
		// Nothing heard where the last look heard networks, or where the AP
		// itself is on the air: the radio is deaf.
		let deaf = !length(list) && ((results.bss?.count || 0) >= 3 || on_air());
		let was = results.bss?.count || 0;
		l2_domains();
		classify(list);
		results.bss = { time: time(), phy: radio.phy, count: length(list), list: sort(list, (a, b) => (b.signal || -200) - (a.signal || -200)) };
		last.bss = time();
		write_json("bss", results.bss);
		let rogues = filter(list, (b) => b.rogue_candidate);
		log(`bss scan: ${length(list)} networks, ${length(rogues)} rogue candidates`);
		if (heal.check) {
			heal.check = false;
			if (length(list)) { heal.failed = 0; heal.told = false; log(`the scan radio hears again, its driver bound again: ${length(list)} networks`); }
			else { heal.failed++; heal.next = time() + HEAL_LATER; note_error("binding its driver again did not bring the scan radio back"); }
			done();
			return;
		}
		if (deaf) {
			// the count the next look is held against is the last one that heard
			results.bss.count_before = was;
			heal_radio(done);
			return;
		}
		done();
	}

	function pass(i) {
		if (i >= length(passes)) { looked(); return; }
		uloop.process("/bin/sh", [ "-c", `exec iw dev ${STA} ${passes[i]} > ${tmp} 2>&1` ], {}, (code) => {
			let text = fs.readfile(tmp) || "";
			fs.unlink(tmp);
			if (code != 0) {
				note_error(`bss: scan exited ${code}: ${substr(text, 0, 120)}`);
				// A failed 6 GHz pass leaves the look what the first heard.
				if (i > 0) { looked(); return; }
				iface_del(STA);
				done();
				return;
			}
			for (let b in parse_iw_scan(text))
				if (i == 0 || b.freq >= 5950) heard[b.bssid] = b;
			pass(i + 1);
		});
	}
	pass(0);
}

// ---------------------------------------------------------------- clients

let cap = { sock: null, handle: null, freq: 0, ch_list: [], ch_i: 0, deauth: {}, heard: {}, hit: {}, probed: 0, round_heard: 0, round_dwells: 0 };
const DEAUTH_FLOOD = 20;   // deauth + disassoc frames for one BSSID per second of dwell

// radiotap flags (bit 1): 0x10 = frame carries its FCS, 0x40 = its FCS failed
function radiotap_flags(pkt) {
	let present = struct.unpack("<I", pkt, 4)[0], off = 8, p = present;
	while (p & 0x80000000) { p = struct.unpack("<I", pkt, off)[0]; off += 4; }
	if (!(present & 0x02)) return 0;
	if (present & 0x01) off = int((off + 7) / 8) * 8 + 8;
	return ord(pkt, off);
}

function radiotap_fcs(pkt) {
	return !!(radiotap_flags(pkt) & 0x10);
}

function radiotap_signal(pkt) {
	// walk the first presence word up to bit 5 (dBm antenna signal)
	let present = struct.unpack("<I", pkt, 4)[0], off = 8, p = present;
	while (p & 0x80000000) { p = struct.unpack("<I", pkt, off)[0]; off += 4; }
	if (!(present & 0x20)) return null;
	let sizes = [ [8, 8], [1, 1], [1, 1], [4, 2], [2, 1] ];
	for (let bit = 0; bit < 5; bit++) {
		if (!(present & (1 << bit))) continue;
		let a = sizes[bit][1];
		off = int((off + a - 1) / a) * a;
		off += sizes[bit][0];
	}
	return struct.unpack("b", pkt, off)[0];
}

function mac_at(pkt, off) {
	return join(":", map(struct.unpack("6B", pkt, off), (b) => sprintf("%02x", b)));
}

function on_frame(pkt) {
	if (length(pkt) < 8) return;
	let rlen = struct.unpack("<H", pkt, 2)[0];
	if (length(pkt) < rlen + 24) return;
	// A frame whose FCS failed reaches the monitor too (about 6% of them on
	// a C-360), its addresses as damaged as the rest: each would be a new
	// "client", or a BSSID a bit off a real one.
	if (radiotap_flags(pkt) & 0x40) return;
	let fc = struct.unpack("<H", pkt, rlen)[0];
	let ftype = (fc >> 2) & 3, sub = (fc >> 4) & 15, to_ds = !!(fc & 0x100), from_ds = !!(fc & 0x200);
	let sta = null, bssid = null, probe = null, tx_is_sta = false, probe_req = false;
	if (cap.freq && ftype == 0 && sub == 8)                // beacon: this BSS was audible
		cap.heard[mac_at(pkt, rlen + 16)] = true;
	if (cap.freq && ftype == 2 && from_ds && (!to_ds || length(pkt) >= rlen + 30)) {
		let sa = mac_at(pkt, rlen + (to_ds ? 24 : 16));
		if (wp.macs[sa]) {
			// our wired frame relayed by this BSS; its size names the domain (VLAN):
			// body = LLC/SNAP (8) + Ethernet payload (60 + 16k - 14) + cipher overhead
			let h = rlen + 24 + (to_ds ? 6 : 0) + ((sub & 8) ? 2 : 0) + (((sub & 8) && (fc & 0x8000)) ? 4 : 0);
			let body = length(pkt) - h - (radiotap_fcs(pkt) ? 4 : 0), v = true;
			let overheads = (fc & 0x4000) ? [ 16, 24, 20 ] : [ 0 ];   // CCMP-128, GCMP/CCMP-256, TKIP
			for (let o in overheads) {
				let eth = body - o - 8 + 14;
				if (eth >= 60 && (eth - 60) % 16 == 0 && (eth - 60) / 16 < length(wp.domains)) { v = wp.domains[(eth - 60) / 16].vlan; break; }
			}
			if (!(fc & 0x4000) && substr(pkt, h, 8) != LLC_ARP) v = true;   // open frame, not our ARP
			let bs = mac_at(pkt, rlen + 10);
			if (cap.hit[bs] == null || cap.hit[bs] === true) cap.hit[bs] = v;
		}
	}
	if (ftype == 0 && (sub == 10 || sub == 12) && cap.freq) {
		let d = cap.deauth[mac_at(pkt, rlen + 16)] ||= { frames: 0, broadcast: 0 };
		d.frames++;
		if (mac_at(pkt, rlen + 4) == "ff:ff:ff:ff:ff:ff") d.broadcast++;
	}
	if (ftype == 0) {
		if (sub == 4) {                                   // probe request
			sta = mac_at(pkt, rlen + 10); tx_is_sta = true; probe_req = true;
			let ie = rlen + 24;
			if (length(pkt) >= ie + 2 && ord(pkt, ie) == 0) {
				let l = ord(pkt, ie + 1);
				if (l > 0) probe = substr(pkt, ie + 2, l);
			}
		}
		else if (sub in [ 0, 2, 10, 11, 12 ]) {          // (re)assoc req, disassoc, auth, deauth
			let a2 = mac_at(pkt, rlen + 10), a3 = mac_at(pkt, rlen + 16);
			if (a2 != a3) { sta = a2; bssid = a3; tx_is_sta = true; }
		}
	}
	else if (ftype == 2 && to_ds != from_ds) {
		if (to_ds) { sta = mac_at(pkt, rlen + 10); bssid = mac_at(pkt, rlen + 4); tx_is_sta = true; }
		else { sta = mac_at(pkt, rlen + 4); bssid = mac_at(pkt, rlen + 10); }
	}
	if (!sta || (hex(substr(sta, 0, 2)) & 1)) return;    // multicast / broadcast
	let c = results.clients[sta] ||= {
		mac: sta, first_seen: time(), frames: 0, randomized: !!(hex(substr(sta, 0, 2)) & 2), probes: [],
	};
	c.last_seen = time();
	c.frames++;
	c.freq = cap.freq;
	if (bssid && !(hex(substr(bssid, 0, 2)) & 1)) c.bssid = bssid;
	if (tx_is_sta) {
		let s = radiotap_signal(pkt);
		// ath11k fills radiotap signal with its default noise floor (-95) on the C-360's radio: not a measurement
		if (s != null && s < 0 && !(s == -95 && radio.driver == "ath11k")) c.signal = c.signal == null ? s : int(0.7 * c.signal + 0.3 * s - 0.5);
	}
	// every probe request counts, wildcard ones too (most phones name no SSID):
	// a client that only probes is looking for a network, connected to none
	if (probe_req) { c.probe_reqs = (c.probe_reqs || 0) + 1; c.last_probe = time(); }
	if (probe && index(c.probes, probe) < 0 && length(c.probes) < 10) push(c.probes, probe);
}

function capture_open() {
	if (cap.sock) return true;
	let s = socket.create(socket.AF_PACKET, socket.SOCK_RAW | socket.SOCK_NONBLOCK, 0x0300);
	if (!s || !s.bind({ family: socket.AF_PACKET, protocol: 3, address: "00:00:00:00:00:00", interface: MON })) {
		note_error(`clients: capture socket failed: ${socket.error()}`);
		return false;
	}
	cap.sock = s;
	cap.handle = uloop.handle(s, () => {
		for (let n = 0; n < 256; n++) {
			let pkt = s.recv(2048);
			if (!pkt) break;
			on_frame(pkt);
		}
	}, uloop.ULOOP_READ);
	return true;
}

function capture_close() {
	if (cap.handle) { cap.handle.delete(); cap.handle = null; }
	if (cap.sock) { cap.sock.close(); cap.sock = null; }
}

function client_channels() {
	let seen = {}, out = [];
	for (let b in (results.bss?.list || []))
		if (b.freq && !seen[b.freq]) { seen[b.freq] = true; push(out, b.freq); }
	if (!length(out)) out = [ 2412, 2437, 2462, 5180, 5745 ];
	return sort(out, (a, b) => a - b);
}

function expire_clients() {
	let now = time();
	for (let m, c in results.clients)
		if (now - c.last_seen > cfg.client_expire) delete results.clients[m];
}

function clients_report() {
	let list = values(results.clients);
	let bssids = {};
	for (let b in (results.bss?.list || [])) bssids[b.bssid] = b.ssid;
	// the network of the BSSID it was last seen with, or none the look knows
	for (let c in list) c.ssid = c.bssid ? bssids[c.bssid] : null;
	return { time: time(), phy: radio.phy, count: length(list),
		probing: length(filter(list, (c) => !c.bssid)),
		list: sort(list, (a, b) => b.last_seen - a.last_seen) };
}

// One dwell on the next channel; the round ends after every channel was visited.
function run_client_slice(done) {
	if (!iface_up(MON, "monitor") || !capture_open()) { done(); return; }
	if (cap.ch_i >= length(cap.ch_list)) { cap.ch_list = client_channels(); cap.ch_i = 0; cap.round_heard = 0; cap.round_dwells = 0; }
	let f = cap.ch_list[cap.ch_i++];
	if (radio.spectral) spectral_write("spectral_scan_ctl", "disable");
	if (sh(`iw dev ${MON} set freq ${f}`) != 0) { later(10, done); return; }
	cap.freq = f;
	cap.deauth = {};
	cap.heard = {};
	cap.hit = {};
	cap.probed = 0;
	if (cfg.wired_probe)
		for (let t in [ 50, int(cfg.client_dwell / 2) ])
			later(t, () => { if (cap.freq == f) { send_probes(); cap.probed++; } });
	later(cfg.client_dwell, () => {
		cap.freq = 0;
		for (let b, d in cap.deauth) {
			if (d.frames < DEAUTH_FLOOD * cfg.client_dwell / 1000.0) continue;
			let known = filter(results.bss?.list || [], (x) => x.bssid == b)[0];
			add_event({ type: "deauth_flood", bssid: b, ssid: known?.ssid, freq: f, frames: d.frames, broadcast: d.broadcast });
		}
		if (cap.probed) {
			let mine = local_macs();
			for (let b in keys({ ...cap.heard, ...cap.hit })) {
				if ((hex(substr(b, 0, 2)) & 1) || mine[b] != null) continue;
				let w = wp.bss[b] ||= { windows: 0, hit_windows: 0 };
				w.windows++;
				w.seen = time();
				if (cap.hit[b] != null) {
					w.hit_windows++;
					w.last_hit = time();
					if (type(cap.hit[b]) == "int") {
						w.vlans ||= [];
						if (index(w.vlans, cap.hit[b]) < 0) push(w.vlans, cap.hit[b]);
						w.vlan = cap.hit[b];
					}
					w.freq = f;
				}
			}
		}
		cap.round_heard += length(cap.heard);
		cap.round_dwells++;
		if (cap.ch_i >= length(cap.ch_list)) {
			// A whole round with no beacon on any channel that had networks:
			// a look says whether the radio is deaf.
			if (!cap.round_heard && cap.round_dwells >= length(cap.ch_list) && length(cap.ch_list) >= 3 && (results.bss?.count || 0) >= 3) {
				log("no beacon heard in a whole round of the channels: a look, to see whether the scan radio is deaf");
				pending.bss = true;
			}
			cap.round_heard = 0;
			cap.round_dwells = 0;
			expire_clients();
			for (let b, w in wp.bss) if (time() - w.seen > 3600) delete wp.bss[b];
			reclassify();
			last.clients = time();
			write_json("clients", clients_report());
		}
		done();
	});
}

// ---------------------------------------------------------------- heal

// heal_radio binds the scan radio's driver again, which is what brings a
// deaf one back: the firmware starts afresh. Its phy comes back under a new
// name, which run_next finds by where the radio is. The look that follows
// says whether it worked. A radio that goes deaf again is bound again, but
// not within HEAL_EVERY seconds, not more than HEAL_MOST times an hour, and
// after a try that did not work, not for HEAL_LATER: binding a driver over
// and over helps no one.
heal_radio = function(done) {
	let now = time();
	heal.times = filter(heal.times, (t) => now - t < 3600);
	if (now < heal.next || length(heal.times) >= HEAL_MOST) {
		if (!heal.told) note_error("the scan radio hears nothing, and its driver was bound again too lately to do it once more yet");
		heal.told = true;
		done();
		return;
	}
	let drv = fs.readlink(`/sys/bus/pci/devices/${radio.pci}/driver`);
	if (!drv) { note_error("the scan radio hears nothing, and has no driver to bind again"); heal.next = now + HEAL_LATER; done(); return; }
	let dir = `/sys/bus/pci/drivers/${fs.basename(drv)}`;
	heal.count++;
	heal.last = now;
	heal.next = now + HEAL_EVERY;
	push(heal.times, now);
	heal.check = true;
	note_error("the scan radio hears nothing: binding its driver again");
	state = "healing";
	capture_close();
	if (radio.spectral) spectral_write("spectral_scan_ctl", "disable");
	for (let i in own_ifaces()) iface_del(i);
	fs.writefile(`${dir}/unbind`, radio.pci);
	let tries = 0;
	function wait() {
		// its phy is there once the firmware has started, about ten seconds
		if (find_phy(radio.pci) || ++tries > 40) {
			pending.bss = true;
			later(2000, done);
			return;
		}
		later(1000, wait);
	}
	later(3000, () => {
		fs.writefile(`${dir}/bind`, radio.pci);
		later(1000, wait);
	});
};


// ---------------------------------------------------------------- ble

// Devices are merged across runs by address: fields from the latest run
// overwrite older ones (a name only sent in scan responses is kept until a
// newer one arrives); first_seen / last_seen / seen_total span runs; a device
// not heard for ble_expire seconds is dropped. Random resolvable addresses
// rotate (about every 15 minutes on phones), so one phone can appear as
// several entries over time.
let ble = { running: false, timer: null, error: null, rounds: 0, duration: 0, hci: null };

// The board's BLE controller: the lowest-numbered one there is (hci0 unless
// another was there first).
function ble_controller() {
	let n = filter(map(fs.lsdir("/sys/class/bluetooth") || [], (h) => match(h, /^hci([0-9]+)$/)), (m) => m);
	return length(n) ? "hci" + sort(map(n, (m) => +m[1]), (a, b) => a - b)[0] : null;
}

function ble_report() {
	let list = values(results.ble);
	return {
		time: last.ble, controller: ble.hci, error: ble.error, duration: ble.duration,
		count: length(list),
		trackers: length(filter(list, (d) => d.tracker)),
		list: sort(list, (a, b) => (b.rssi ?? -200) - (a.rssi ?? -200)),
	};
}

let run_ble;   // assigned below: ble_schedule and run_ble refer to each other

function ble_schedule(ms) {
	if (ble.timer) ble.timer.cancel();
	next.ble = time() + int(ms / 1000);
	ble.timer = uloop.timer(ms, run_ble);
}

run_ble = function() {
	if (ble.running) return;
	if (!cfg.ble_enabled) { ble.error = "disabled"; ble_schedule(60000); return; }
	ble.hci = ble_controller();
	if (!ble.hci || !fs.access(BLE, "x")) {
		ble.error = "no BLE controller";
		ble_schedule(cfg.ble_interval * 1000);
		return;
	}
	ble.running = true;
	let tmp = `${OUT}/.ble.json`;
	uloop.process("/bin/sh", [ "-c", `exec ${BLE} -i ${substr(ble.hci, 3)} -d ${cfg.ble_duration} > ${tmp} 2>/dev/null` ], {}, (code) => {
		ble.running = false;
		let r = null;
		if (code == 0)
			try { r = json(fs.readfile(tmp) || "null"); }
			catch (e) { note_error(`ble: ${BLE} wrote what is not JSON: ${e.message}`); }
		fs.unlink(tmp);
		let now = time();
		if (!r) {
			ble.error = `airscan-ble exited ${code}`;
		} else {
			ble.error = r.error;
			ble.rounds = r.rounds;
			ble.duration = r.duration;
			for (let d in r.devices || []) {
				let rec = results.ble[d.addr] ||= { first_seen: now, seen_total: 0 };
				for (let k, v in d) rec[k] = v;
				rec.seen_total += d.seen;
				rec.last_seen = now;
			}
		}
		for (let a, d in results.ble)
			if (now - d.last_seen > cfg.ble_expire) delete results.ble[a];
		last.ble = now;
		write_json("ble", ble_report());
		ble_schedule(cfg.ble_interval * 1000);
	});
};

// ---------------------------------------------------------------- scheduler

// loan_end takes the radio back: what the borrower left on it is removed.
function loan_end(why) {
	for (let i in own_ifaces())
		if (i != MON && i != STA) iface_del(i);
	log(`the scan radio is back from ${loan.to}: ${why}`);
	loan.until = 0;
	loan.to = null;
}

function run_next() {
	if (busy) return;
	if (loan.until) {
		if (time() < loan.until) {
			if (state != "lent") {
				capture_close();
				if (radio.spectral) spectral_write("spectral_scan_ctl", "disable");
				iface_del(MON);
				iface_del(STA);
				state = "lent";
				log(`the scan radio is lent to ${loan.to}, for ${loan.until - time()} s at the most`);
			}
			later(200, run_next);
			return;
		}
		loan_end("the loan ran out");
	}
	if (!resolve_radio()) {
		state = "waiting for scan radio";
		later(5000, run_next);
		return;
	}
	let now = time();
	let done = (job) => () => { busy = false; state = "idle"; later(20, run_next); };
	busy = true;
	if (pending.bss || now >= next.bss) {
		pending.bss = false; next.bss = now + cfg.bss_interval; state = "bss";
		capture_close();
		run_bss(done("bss"));
	}
	else if (pending.spectral != null || now >= next.spectral) {
		let band = pending.spectral || null;
		// a sweep of one band asked for leaves the time of the next full one
		pending.spectral = null; state = "spectral";
		if (!band) next.spectral = now + cfg.spectral_interval;
		capture_close(); iface_del(STA);
		run_spectral(done("spectral"), band);
	}
	else {
		state = "clients";
		run_client_slice(done("clients"));
	}
}

// kill_children stops our helpers still running (a scan, a sweep, a BLE
// round): they must not outlive us. The image has no pkill, so read the
// parent of each process from /proc/<pid>/stat ("pid (comm) state ppid ...").
function kill_children() {
	let kids = [];
	for (let d in fs.lsdir("/proc") || []) {
		if (!match(d, /^[0-9]+$/)) continue;
		let st = fs.readfile(`/proc/${d}/stat`) || "";
		let f = split(substr(st, rindex(st, ")") + 2), " ");
		if (+f[1] == MYPID) push(kids, d);
	}
	if (length(kids)) system(`kill -TERM ${join(" ", kids)} 2>/dev/null`);
}

function cleanup() {
	kill_children();
	capture_close();
	if (wp.sock) { wp.sock.close(); wp.sock = null; }
	if (ble.timer) ble.timer.cancel();
	if (radio.spectral) spectral_write("spectral_scan_ctl", "disable");
	iface_del(MON);
	iface_del(STA);
	if (+trim(fs.readfile(PIDFILE) || "") == MYPID) fs.unlink(PIDFILE);
}

// ---------------------------------------------------------------- ubus

function by_band(sp, band) {
	if (!sp || !band) return sp;
	return { ...sp, windows: filter(sp.windows, (w) => band_of(w.center) == band) };
}

// uhttpd's ubus handler adds ubus_rpc_session to the arguments of every call
// it forwards (from LuCI), and a ucode ubus method rejects an argument it does
// not declare
const SESSION = { ubus_rpc_session: "" };

const methods = {
	status: {
		args: SESSION,
		call: () => ({
			board: board_name(), radio: radio.pci, phy: radio.phy, section: radio.section,
			spectral_supported: radio.spectral, state,
			// what a borrower can count on: "lend", and a deaf radio healed;
			// with no scan radio, the BLE survey only
			features: radio.pci ? [ "lend", "heal" ] : [ "ble" ],
			loan: loan.until ? { to: loan.to, until: loan.until } : null,
			heal: { count: heal.count, failed: heal.failed, last: heal.last },
			last, next, config: cfg,
			counts: { bss: results.bss?.count || 0, clients: length(results.clients), windows: length(results.spectrum?.windows || []), events: length(events), ble: length(results.ble) },
			ble: { enabled: cfg.ble_enabled, running: ble.running, error: ble.error, rounds: ble.rounds },
			wired_probe: { enabled: cfg.wired_probe, domains: wp.domains, tracked: length(wp.bss) },
			errors,
		}),
	},
	spectrum: {
		args: { ...SESSION, band: "" },
		call: (req) => by_band(results.spectrum, req.args.band) || { pending: true },
	},
	bss: {
		args: SESSION,
		call: () => results.bss || { pending: true },
	},
	clients: {
		args: SESSION,
		call: () => clients_report(),
	},
	events: {
		args: SESSION,
		call: () => ({ time: time(), list: events }),
	},
	sweep: {
		args: { ...SESSION, band: "" },
		call: (req) => {
			let b = req.args.band || "";
			if (b && !(b in [ "2g", "5g", "6g" ])) return { error: "band must be 2g, 5g or 6g" };
			pending.spectral = b;
			return { queued: "spectral", band: b || "all" };
		},
	},
	scan: {
		args: SESSION,
		call: () => { pending.bss = true; return { queued: "bss" }; },
	},
	// lend: the radio, for seconds, to whoever asks (to, for the log). Only
	// between jobs: during a scan or a sweep the answer is no, with the
	// state, and the borrower asks again. The radio is free once status says
	// "lent", a client dwell later at the most (wait_ms).
	lend: {
		args: { ...SESSION, seconds: 0, to: "" },
		call: (req) => {
			let secs = +req.args.seconds || 60;
			if (secs < 1 || secs > LOAN_MOST) return { error: `seconds must be 1 to ${LOAN_MOST}` };
			if (loan.until) return { lent: false, state, to: loan.to };
			if (!(state in [ "clients", "idle" ]) || !radio.phy) return { lent: false, state };
			loan.until = time() + secs;
			loan.to = req.args.to || "another service";
			return { lent: true, phy: radio.phy, until: loan.until, wait_ms: cfg.client_dwell + 500 };
		},
	},
	// reclaim: the borrower is done, and the radio is airscan's again.
	reclaim: {
		args: SESSION,
		call: () => {
			if (loan.until) loan_end("given back");
			return { lent: false };
		},
	},
	ble: {
		args: SESSION,
		call: () => ble_report(),
	},
	ble_scan: {
		args: SESSION,
		call: () => {
			if (ble.running) return { queued: false, running: true };
			ble_schedule(10);
			return { queued: "ble" };
		},
	},
};

// ---------------------------------------------------------------- main

cfg = load_config();
if (!cfg.enabled) { log("disabled in /etc/config/airscan"); exit(0); }
let pci = BOARDS[board_name()];
const BLE_ONLY = !pci && BLE_BOARDS[board_name()];
if (!pci && !BLE_ONLY) { log(`no dedicated scan radio on board "${board_name()}"; not starting`); exit(0); }
radio.pci = pci;
if (BLE_ONLY) {
	state = "ble only";
	for (let m in [ "spectrum", "bss", "clients", "sweep", "scan", "lend" ])
		methods[m].call = () => ({ error: "no scan radio on this board" });
}
// One airscan at a time. On a restart procd can start us while the previous
// instance is still cleaning up, and its cleanup deletes the scan interfaces;
// wait for it to exit (up to 15 s) before touching the radio.
for (let i = 0; i < 60; i++) {
	let old = +trim(fs.readfile(PIDFILE) || "");
	if (!old || old == MYPID || !fs.access(`/proc/${old}`)) break;
	if (i == 0) log(`waiting for the previous airscan (pid ${old}) to exit`);
	sleep(250);
}
fs.writefile(PIDFILE, `${MYPID}\n`);
fs.mkdir(OUT);
if (!BLE_ONLY) release_from_netifd(pci);

uloop.init();
// ucode -S starts with its collector off: without it, what refers to itself
// (a job's nested functions, and the sweeps and looks they hold) is never
// freed. It runs once a minute from a timer of its own, never by itself:
// started (gc "start"), it can run inside a callback of filter() or map()
// and free the array they are building, and they answer null (ucode
// 2026.01.16).
function collect() {
	gc("collect");
	later(60000, collect);
}
later(60000, collect);
// An error in a callback is said where it can be read; uloop then ends, and
// procd starts airscan afresh.
uloop.guard((e) => {
	note_error(`stopped by an error: ${e?.message} ${e?.stacktrace?.[0]?.context ?? ""}`);
	uloop.end();
});
conn = ubus.connect();
if (!conn) { log("cannot connect to ubus"); exit(1); }
conn.publish("airscan", methods);
if (BLE_ONLY) {
	log("started; the BLE survey only (no scan radio on this board)");
} else {
	log(`started; scan radio ${pci}`);
	later(2000, run_next);
}
ble_schedule(15000);
uloop.run();
cleanup();

# DEVELOPER.md — Adding Support for New UGREEN NAS Models

Let's be honest up front: **this is going to be painful.**

UGREEN doesn't publish board schematics. ITE Tech doesn't release public
datasheets for the IT86xx family. There is no PDF you can look up. There is
no page 47. The only way to figure out how a new model's fan controller
works is to sit down, read the chip's register space, and compare it
against what we already know from models that work.

This document is everything I've learned from doing exactly that — so you
don't have to start from scratch.

---

## What we're working with

No schematics. No datasheets. What we **do** have:

- **The in-tree Linux `it87` driver** — 20+ years of community
  reverse-engineering baked into C. This is our bible.
- **`ITE_Register_map.csv`** in this repo — a hand-curated register
  reference extracted from the driver, datasheets for older chips that
  leaked years ago, and real-world testing.
- **`sensors-detect`** — identifies the chip and its I/O address.
- **Contributors with hardware** willing to run stuff and report back.
  This is how every model in this repo got added.

If you're opening an issue for a new model — you are the hardware.
We need you to run the diagnostics below.

---

## Step 1 — What chip is in there?

```bash
sudo sensors-detect
```

Look for the `National Semiconductor/ITE` family. Note:

- **I/O address** — usually `0x2e` or `0x4e`
- **Chip ID** — e.g. `IT8622E`, or something weird like `0x5571` (see below)

Also grab the model name:

```bash
sudo dmidecode -t system | grep "Product Name"
```

---

## Step 2 — Try the in-tree driver

```bash
sudo modprobe it87 ignore_resource_conflict=1
dmesg | grep -i it87
```

If you see something like:

```
it87: Device (chip IT8622E ioreg 0x4e) not activated, skipping
```

…that's the firmware deactivating the logical device. We can work with
that, but we need the register dump first.

Try forcing the ID if sensors-detect showed a non-standard one:

```bash
sudo modprobe it87 ignore_resource_conflict=1 force_id=0x5571
dmesg | grep -i it87
```

---

## Step 3 — Dump the Super I/O registers

**This is the single most important thing you can do.** Everything else
flows from this dump.

### The no-excuses method (Python, no extra packages)

Save this as `sio-dump.py` and run it as root:

```python
#!/usr/bin/env python3
"""
Super I/O register dumper for IT87xx chips.
Usage: sudo python3 sio-dump.py [iobase]
       Default iobase = 0x2e. Try 0x4e if nothing shows up at 0x2e.

WARNING: This script only READS. It does not write configuration
registers. Still — Super I/O access carries inherent risk. You break
your board, you own both halves.
"""
import ctypes, sys

IOBASE = int(sys.argv[1], 0) if len(sys.argv) > 1 else 0x2e

libc = ctypes.CDLL("libc.so.6")
if libc.iopl(3) != 0:
    sys.exit("iopl(3) failed — are you root?")

def outb(val, port):
    libc.outb(ctypes.c_ubyte(val), ctypes.c_ushort(port))

def inb(port):
    return ctypes.c_ubyte(libc.inb(ctypes.c_ushort(port))).value

def enter():
    outb(0x87, IOBASE)
    outb(0x01, IOBASE)
    outb(0x55, IOBASE)
    if IOBASE == 0x2e:
        outb(0x55, IOBASE)
    else:
        outb(0xAA, IOBASE)

def exit_():
    outb(0x02, IOBASE)

def rd(reg):
    outb(reg, IOBASE)
    return inb(IOBASE + 1)

def wr(reg, val):
    outb(reg, IOBASE)
    outb(val, IOBASE + 1)

enter()

chip_id = (rd(0x20) << 8) | rd(0x21)
print(f"=== Super I/O at 0x{IOBASE:02x} ===")
print(f"Chip ID: 0x{chip_id:04x}")

print("\n-- Global Registers (0x20-0x5f) --")
for r in range(0x20, 0x60):
    print(f"  0x{r:02x}: 0x{rd(r):02x}")

print("\n-- Logical Devices --")
for ldn in range(0x00, 0x10):
    wr(0x07, ldn)
    lo = rd(0x60)
    hi = rd(0x61)
    act = rd(0x30)
    print(f"  LDN 0x{ldn:02x}: iobase=0x{hi:02x}{lo:02x}  active=0x{act:02x}")

exit_()
print("\nDone. Paste this output in your issue.")
```

Run it at both addresses if you're unsure:

```bash
sudo python3 sio-dump.py 0x2e
sudo python3 sio-dump.py 0x4e
```

One of them will spit out data, the other will give garbage or zeros.

---

## Step 4 — Check ioports

```bash
cat /proc/ioports | grep -i it87
```

If nothing — the driver hasn't claimed the region. Expected on unsupported
models.

---

## Step 5 — What to put in your issue

Paste all of this, no need to format it nicely — raw output is fine:

1. `dmidecode -t system` (just the Product Name line)
2. `sensors-detect` output (the ITE section — not the whole thing)
3. **Super I/O register dump** from the script above
4. `dmesg | grep -i it87` after `modprobe` attempt
5. `uname -r` and your OS (TrueNAS SCALE, unRAID, Debian, …)
6. **How many physical fans** are in the device

That's it. With the register dump I can figure out the rest.

---

## On OEM / Custom Chip IDs

Sometimes UGREEN ships a chip that reports a non-standard ID. The IT8622E
normally reports `0x8622`, but UGREEN's firmware might show `0x5571` or
similar. This isn't a different chip — it's the same silicon with an
OEM-customized ID, which is annoying but not fatal.

The `force_id` modprobe parameter exists for exactly this case. If it
works, note the ID and I'll add it to the driver's known-ID list.

---

## Building on TrueNAS SCALE

TrueNAS uses a custom kernel and is picky about out-of-tree modules. The
known workaround:

```bash
sudo apt install build-essential linux-headers-$(uname -r) dwarves
make -j1
sudo make install
sudo modprobe it87 ignore_resource_conflict=1 force_id=<your_id>
```

`-j1` because TrueNAS boxes often have limited RAM and OOM kills the build
at higher parallelism. BTF info needs to be present — check with:

```bash
ls /sys/kernel/btf/vmlinux
```

---

## After diagnostics: adding the board

Once we have the register dump and confirm the chip + LDN layout, the
actual code changes are small:

1. Add the model to the board table in `it87.c`
2. Verify fan tach + PWM registers against `ITE_Register_map.csv`
3. Add a test case in `tests/test_register_map.sh`
4. Contributor builds, tests on hardware, reports back
5. Iterate until `sensors` shows fans and PWM responds

### What "works" looks like

- `sensors` lists `fan1_input`, `fan2_input`, …
- `pwmconfig` can ramp each fan up and down
- `fancontrol` starts cleanly, survives reboot
- No "not activated" in dmesg after install

---

## References

- [`it87/ITE_Register_map.csv`](it87/ITE_Register_map.csv) — register
  reference, built the hard way
- [`it87/ISSUES`](it87/ISSUES) — known board-specific quirks
- Mainline `it87.c`: `drivers/hwmon/it87.c` in the kernel tree
- [lm-sensors wiki](https://wiki.lm-sensors.org/) — background reading

---

_This document will grow as we learn more. If you've done diagnostics on
a model and found something not covered here, open a PR to improve it._

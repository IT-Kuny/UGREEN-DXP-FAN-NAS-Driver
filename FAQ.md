# FAQ & Troubleshooting

Common errors and their fixes for the UGREEN DXP fan driver and the `ugreen-fan-control` daemon.
If your problem is not covered here, please [open an issue](https://github.com/IT-Kuny/UGREEN-DXP-FAN-NAS-Driver/issues).

---

## Fan control stops working after reboot — what do I do?

The automated installer prevents this by setting up proper systemd service ordering.
If you installed manually, ensure the it87 module is loaded before the fan daemon starts:

```bash
# Check if the module is loaded
lsmod | grep it87

# Load dependency + it87 manually
sudo modprobe hwmon-vid

# Load it manually
sudo modprobe it87 ignore_resource_conflict=1

# Make it persistent across reboots
echo "hwmon-vid" | sudo tee /etc/modules-load.d/it87.conf
echo "it87" | sudo tee -a /etc/modules-load.d/it87.conf
echo "options it87 ignore_resource_conflict=1" | sudo tee /etc/modprobe.d/it87.conf
```

## `it87` fails to load with `Unknown symbol vid_from_reg` / `vid_which_vrm`

This means the `hwmon-vid` dependency is not loaded yet.

```bash
sudo modprobe hwmon-vid
sudo modprobe it87 ignore_resource_conflict=1
```

If `modprobe hwmon-vid` fails, follow the **Installer aborts because `hwmon-vid` is unavailable** section next.

For persistence across reboots, use the same modules-load/modprobe steps shown in
**Fan control stops working after reboot** above.

## The installer aborts because `hwmon-vid` is unavailable

The installer now checks whether `hwmon-vid` exists for your running kernel and
aborts if it is missing, to prevent an unusable setup.

Install matching kernel + headers/modules for your running kernel, then verify:

```bash
uname -r
# `hwmon_vid` is an equivalent alias if your distro exposes that spelling
modinfo -k "$(uname -r)" hwmon-vid || modinfo -k "$(uname -r)" hwmon_vid
```

If `modinfo` still fails, install/reinstall your distro's kernel modules package
for `$(uname -r)` and reboot into that kernel before running the installer again.

## The fan daemon is not running or applies an incorrect PWM value

Check the service status and logs:

```bash
systemctl status ugreen-fan-control.service
journalctl -u ugreen-fan-control.service -f
```

The daemon auto-detects the PWM channel at startup. If auto-detection fails, pin the
path explicitly in `/etc/ugreen/ugreen-fan-control.env`:

```
FAN_PWM_PATH=/sys/class/hwmon/hwmon3/pwm3
```

Then restart:

```bash
sudo systemctl restart ugreen-fan-control.service
```

## iDX6011 — `it87` reports "not activated, skipping" at ioreg 0x4e

On the UGREEN iDX6011 the IT8622E chip (OEM ID 0x5571) sits at ioreg 0x4e, and
the BIOS leaves the EC logical device deactivated.  The driver detects the chip
automatically via DMI and activates the logical device during probe.

If automatic DMI detection does not trigger (e.g. on a custom kernel or if the
system product name differs), add `force_activate=1` to the modprobe options:

```bash
sudo modprobe it87 ignore_resource_conflict=1 force_activate=1
```

To make this persistent, edit `/etc/modprobe.d/it87.conf` (or the equivalent
for your distro) and add:

```
options it87 ignore_resource_conflict=1 force_activate=1
```

After loading the module, verify with `dmesg | grep -i it87`.  You should see:

```
it87: Activating EC logical device for chip IT8622E ioreg 0x4e
it87: Found IT8622E chip at 0x..., revision N
```

Then restart the fan daemon so it re-detects the newly available PWM channel:

```bash
sudo systemctl restart ugreen-fan-control.service
```

## The DKMS module fails to build after a kernel update

```bash
# Check DKMS status
dkms status it87

# Rebuild for current kernel
cd it87
make clean
sudo make dkms
```

## TrueNAS SCALE — DKMS build process is killed (`Killed` in make.log)

On TrueNAS SCALE the DKMS build may be terminated by the kernel OOM killer during
the compilation of `it87.o`.  This is seen as:

```
make[3]: *** [.../it87.o] Killed
```

The most common cause is that the TrueNAS SCALE kernel (`production+truenas`) requires
BTF (BPF Type Format) metadata, whose generation is memory-intensive.  The automated
installer already copies `/sys/kernel/btf/vmlinux` into the kernel build directory to
satisfy this requirement, but the system may still run out of memory when running
multiple parallel compile jobs.

**Workaround — build with a single job:**

```bash
# Clone and enter the repo (with submodule)
git clone --recurse-submodules https://github.com/IT-Kuny/UGREEN-DXP-FAN-NAS-Driver.git
cd UGREEN-DXP-FAN-NAS-Driver/it87

# Copy BTF vmlinux if it is missing from the build tree
KBUILD=$(readlink -f /lib/modules/$(uname -r)/build)
[ ! -f "${KBUILD}/vmlinux" ] && cp /sys/kernel/btf/vmlinux "${KBUILD}/"

# Build and install with a single parallel job to reduce memory pressure
make -j1
sudo make install
```

After a successful build, continue with the rest of the
[Install Guide (Manual)](#install-guide-manual).

## TrueNAS SCALE — `it87: disagrees about version of symbol module_layout`

If `dmesg` shows:

```
it87: disagrees about version of symbol module_layout
```

and `modprobe it87` fails with `Exec format error`, this means a **pre-built**
`it87.ko` binary is being loaded that was not compiled for the running TrueNAS
SCALE kernel.  This almost always means the DKMS build described above was
**killed before it completed** (see the `Killed` entry in `make.log`).

The fix is to complete a successful DKMS build first using the single-job
workaround above.  Once the module is correctly compiled against the TrueNAS
kernel headers (`production+truenas`), the symbol version mismatch disappears.

> [!NOTE]
> This error is **not** related to the `ignore_resource_conflict=1` option or
> missing `hwmon-vid`; it is purely a build-vs-kernel mismatch.

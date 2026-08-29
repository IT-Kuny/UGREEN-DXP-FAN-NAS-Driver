# UGREEN DXP NAS Driver for the system fan

After multiple searches I found a bunch of posts about loud fans for the DXP2800 but not how to control the fans.
This applies to those who do not use UGOS PRO but __unRAID, Debian, Ubuntu, Fedora__ etc.

> [!NOTE]
> In cooperation with AI, we've upstreamed the driver for the it87 chipset for the latest linux kernel (April 2026), dropped old kernel support for kernel version 2.7.x since there will be no UGREEN NAS with such a low linux kernel available. I'm not good with C so any help, bug fixings and reviews are highly welcome :-)
>
> Official kernel documentation for the it87 driver: [docs.kernel.org/hwmon/it87.html](https://docs.kernel.org/hwmon/it87.html)

---

> [!IMPORTANT]  
> As it seems, does UGREEN utilize the it87 Chipset for each NAS slightly different. In that manner, I need your help, to extend the driver for all UGREEN NAS's. If you see your NAS not listed here, feel free to open an Issue with your NAS Model. Check out [DEVELOPER.md](DEVELOPER.md) for the diagnostics process — it tells you exactly what info I need to add support for your model.

What's currently being supported:

- DXP2800
- DXP8800
- DXP4800 ([Issue #11](https://github.com/IT-Kuny/UGREEN-DXP-FAN-NAS-Driver/issues/11) resolved — fan visibility and PWM control implemented; see the `pwmconfig` prompt selections in the Troubleshooting section for DXP4800 specifics)
- iDX6011 (IT8622E at ioreg 0x4e; OEM chip ID 0x5571; `force_activate=1` is handled automatically via DMI — only needed as a fallback if auto-detection fails, see Troubleshooting section)

What's currently being partially supported: 

- DXP6800Pro (See [Issue](https://github.com/IT-Kuny/UGREEN-DXP-FAN-NAS-Driver/issues/6) #6 for now)

What's currently under investigation / testing:

- DXP6011 Pro ([Issue #23](https://github.com/IT-Kuny/UGREEN-DXP-FAN-NAS-Driver/issues/23) closed, triaged in [PR #24](https://github.com/IT-Kuny/UGREEN-DXP-FAN-NAS-Driver/pull/24) — reported on unRAID with an unknown Super I/O ID `0x5571` at `0x4e`; plain `modprobe it87 ignore_resource_conflict=1` still fails with `No such device`, so support is pending register-dump analysis and `force_id` testing. UGREEN's published `kernel-6.12` GPL tree also contains a vendor `drivers/ugreen/` area that references `ug_idx6011pro-sio.o` and `leds-mcu.o`, and `ug_it55pro_functions.c` identifies the vendor product string as `iDX6011 Pro` and the chip as `ITE5571`, with OEM fan-control code paths that are useful reverse-engineering material even though the source drop appears incomplete.)

What's **not supported** by this driver (investigation completed — [Issue #18](https://github.com/IT-Kuny/UGREEN-DXP-FAN-NAS-Driver/issues/18)):

- DXP2800 GT / DXP4800 GT — these **GT** models use an **AMD Ryzen Embedded R2514** CPU (unlike the Intel N100 in the DXP2800) and a **different Super I/O chip** (a **National Semiconductor / Texas Instruments** chip with ID `0x2011` at I/O port `0x2e`).  The `it87` driver does **not** apply to this hardware. Diagnostic details and findings are documented in the closed [Issue #18](https://github.com/IT-Kuny/UGREEN-DXP-FAN-NAS-Driver/issues/18).

> [!NOTE]
> **AMD-based models (DXP2800 GT / DXP4800 GT):** On these, the LED MCU sits on a
> **Synopsys DesignWare** I2C controller (ACPI `AMDI0010`) rather than the Intel
> *SMBus I801 adapter*. The mainline `i2c-designware-platform` / `i2c-designware-core`
> drivers must be loaded for `/dev/i2c-*` to exist:
> ```
> modprobe i2c-designware-platform   # pulls in i2c-designware-core
> ```
> Most general-purpose distros (Debian, Proxmox VE, Arch, Fedora …) ship these as
> modules and the `modprobe` above is all you need. Where they are disabled, enable
> `CONFIG_I2C_DESIGNWARE_CORE=m` and `CONFIG_I2C_DESIGNWARE_PLATFORM=m` and build
> the modules for your kernel. See also
> [miskcoo/ugreen_leds_controller#100](https://github.com/miskcoo/ugreen_leds_controller/pull/100)
> for LED MCU framing details on these models.

---

Here is a step by step guide on how to do this:

## Package Requirements

- gcc
- make
- dkms
- dwarves
- kernel-headers
- lm_sensors
- git

## System requirements to set up fan control

- SSH Client
- Basic knowledge with Linux and terminal commands

## Install Guide (Automated)

The automated installer handles driver building via DKMS, systemd service setup,
and automatic fan control. Fan speed is managed fully automatically — no additional
configuration is required after running the installer.

1) SSH into your UGREEN NAS

2) Install the required packages

```bash
# Fedora/RHEL
sudo dnf install gcc make dkms dwarves kernel-headers lm_sensors git

# Debian/Ubuntu
sudo apt install gcc make dkms dwarves linux-headers-$(uname -r) lm-sensors git

# Arch
sudo pacman -S gcc make dkms linux-headers lm_sensors git
```

3) Clone the repository and run the installer

```bash
git clone --recurse-submodules https://github.com/IT-Kuny/UGREEN-DXP-FAN-NAS-Driver.git
cd UGREEN-DXP-FAN-NAS-Driver
sudo ./scripts/install.sh
```

That's it. The installer:
- Builds and installs the `it87` kernel driver via DKMS
- Enables and starts `ugreen-fan-control.service` — a Bash-native fan control daemon
  that auto-detects the PWM channel and adjusts fan speed based on CPU and disk temperatures
- Sets up proper service ordering so the driver is always loaded before the daemon

Fan control is running immediately and will survive reboots and kernel updates.

To verify:

```bash
systemctl status ugreen-fan-control.service
journalctl -u ugreen-fan-control.service -f
```

To adjust the fan curves or mode (`silent` / `normal` / `powerful`), edit
`/etc/ugreen/ugreen-fan-control.env` and restart the service:

```bash
sudo systemctl restart ugreen-fan-control.service
```

The installer automatically sets up systemd services that ensure:
- The `hwmon-vid` dependency module is loaded before `it87`
- The it87 driver is loaded **before** the fan daemon starts (prevents race conditions)
- The fan daemon auto-detects the PWM sysfs path at startup

`hwmon-vid` is used as the canonical name in this repo; `hwmon_vid` is an equivalent module alias on some distros/kernels.

## Install Guide (Manual)

<details>
<summary>Click to expand manual installation steps</summary>

1) SSH into your UGREEN NAS

2) Install the packages mentioned above like

```bash
sudo dnf install gcc make dkms dwarves kernel-headers lm_sensors
```

3) Building the dkms module and installing it

```bash
cd it87
make -j4
sudo make install
```

> [!NOTE]
> If you see this:
> __Skipping BTF generation [module name] due to unavailability of vmlinux.__
>
> You can simply run:
>
> ```bash
> cp /sys/kernel/btf/vmlinux /usr/lib/modules/`uname -r`/build/
> ```
>
> And clean up the previous, interrupted build and do a clean build from scratch
>
> ```bash
> make clean && make -j4 && sudo make install
> ```

4) Install the fan control daemon and service

```bash
sudo install -m 755 scripts/ugreen-fan-control.sh /usr/local/sbin/ugreen-fan-control.sh
sudo mkdir -p /etc/ugreen
sudo install -m 644 config/ugreen-fan-control.env /etc/ugreen/ugreen-fan-control.env
sudo cp config/ugreen-fan-control.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now ugreen-fan-control.service
```

</details>

## Uninstall

To remove the driver, services, and configuration files:

```bash
sudo ./scripts/uninstall.sh
```

This preserves your `/etc/ugreen/` configuration directory. Remove it manually if no longer needed.

## Troubleshooting

### Fan control stops working after reboot

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

### `it87` fails to load with `Unknown symbol vid_from_reg` / `vid_which_vrm`

This means the `hwmon-vid` dependency is not loaded yet.

```bash
sudo modprobe hwmon-vid
sudo modprobe it87 ignore_resource_conflict=1
```

If `modprobe hwmon-vid` fails, follow the **Installer aborts because `hwmon-vid` is unavailable** section next.

For persistence across reboots, use the same modules-load/modprobe steps shown in
**Fan control stops working after reboot** above.

### Installer aborts because `hwmon-vid` is unavailable

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

### Fan daemon is not running or applying incorrect PWM

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

### iDX6011 — `it87` reports "not activated, skipping" at ioreg 0x4e

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

### DKMS module fails to build after kernel update

```bash
# Check DKMS status
dkms status it87

# Rebuild for current kernel
cd it87
make clean
sudo make dkms
```

### TrueNAS SCALE — DKMS build process is killed (`Killed` in make.log)

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

### TrueNAS SCALE — `it87: disagrees about version of symbol module_layout`

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

### Why did I do that?

The idea for this project has been brought by this [Reddit post](https://www.reddit.com/r/unRAID/comments/1dzep0s/how_to_configure_fan_control_ugreen_nas/)

### Who wrote the dkms module?

That was written by 
 *  Copyright (C) 2001 Chris Gauthron
 *  Copyright (C) 2005-2010 Jean Delvare <jdelvare@suse.de>
and archived by [a1wong](https://github.com/a1wong/it87).

Official kernel documentation: [docs.kernel.org/hwmon/it87.html](https://docs.kernel.org/hwmon/it87.html)

## Results

Tested with

```txt
# sensors-detect version 3.6.0
# System: UGREEN DXP2800 [EM_DXP2800_V1.0.25]
# Board: Default string Default string
# OS: Fedora 42 Server Edition
# Kernel: 6.14.5-300.fc42.x86_64 x86_64
# Processor: Intel(R) N100 (6/190/0)
```

The automated installer ships `ugreen-fan-control.service`, which manages the fan curve on its own — no `fancontrol` setup is needed anymore. Verify it is running:

```bash
systemctl status ugreen-fan-control.service
```

Example `sensors` output with the driver loaded:
it8613-isa-0a30
Adapter: ISA adapter
in0:         660.00 mV (min =  +0.00 V, max =  +2.81 V)
in1:           1.12 V  (min =  +0.00 V, max =  +2.81 V)
in2:           2.07 V  (min =  +0.00 V, max =  +2.81 V)
in4:           2.06 V  (min =  +0.00 V, max =  +2.81 V)
in5:           2.08 V  (min =  +0.00 V, max =  +2.81 V)
3VSB:          3.30 V  (min =  +0.00 V, max =  +5.61 V)
Vbat:          3.15 V  
+3.3V:         3.37 V  
fan2:           0 RPM  (min =    0 RPM)
fan3:        1726 RPM  (min =    0 RPM)
temp1:        +40.0°C  (low  = -128.0°C, high = +127.0°C)  sensor = thermistor
temp2:        +23.0°C  (low  = -128.0°C, high = +127.0°C)  sensor = thermistor
temp3:        +42.0°C  (low  = -128.0°C, high = +127.0°C)
intrusion0:  ALARM

acpitz-acpi-0
Adapter: ACPI interface
temp1:        +27.8°C  

coretemp-isa-0000
Adapter: ISA adapter
Package id 0:  +49.0°C  (high = +105.0°C, crit = +105.0°C)
Core 0:        +49.0°C  (high = +105.0°C, crit = +105.0°C)
Core 1:        +49.0°C  (high = +105.0°C, crit = +105.0°C)
Core 2:        +49.0°C  (high = +105.0°C, crit = +105.0°C)
Core 3:        +49.0°C  (high = +105.0°C, crit = +105.0°C)
```

# Contributing & New Models

Want to add support for a new UGREEN NAS model? Start with [DEVELOPER.md](DEVELOPER.md) — it covers the full diagnostics process: chip identification, Super I/O register dumps, OEM custom IDs, and what to include in your issue.

No schematics, no datasheets — we figure it out the hard way.

---

# Bugs

Please report them [here](https://github.com/IT-Kuny/UGREEN-DXP-FAN-NAS-Driver/issues).

## Donations

It took me a few hours to prepare, testing and deliver this for you. :)
I'll appreciate any contribution to the coffee fund :3

BTC: ```3EdkooEbQJurjCHScwUjPHGCCszoFh1pmM```

ETH: ```0x0dB50ef6C03c354795e306133B71A69d8F2e9cc6```

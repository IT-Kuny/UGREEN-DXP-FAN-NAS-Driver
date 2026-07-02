# UGREEN DXP NAS Driver for the system fan

After multiple searches I found a bunch of posts about loud fans for the DXP2800 but not how to control the fans.
This applies to those who do not use UGOS PRO but __unRAID, Debian, Ubuntu, Fedora__ etc.

> [!NOTE]
> In cooperation with AI, we've upstreamed the driver for the it87 chipset for the latest linux kernel (April 2026), dropped old kernel support for kernel version 2.7.x since there will be no UGREEN NAS with such a low linux kernel available. Im not good with C so any help, bug fixings and reviews are highly welcome :-)

---

> [!IMPORTANT]  
> As it seems, does UGREEN utilize the it87 Chipset for each NAS slightly different. In that manner, I need your help, to extend the driver for all UGREEN NAS's. If you see your NAS not listed here, feel free to open an Issue with your NAS Model.

Whats currenttly being supported:

- DXP2800
- DXP8800

Whats currently being partially supported: 

- DXP6800Pro (See [Issue](https://github.com/IT-Kuny/UGREEN-DXP-FAN-NAS-Driver/issues/6) #6 for now)
- DXP4800 (See [Issue](https://github.com/IT-Kuny/UGREEN-DXP-FAN-NAS-Driver/issues/11) #11 for now — fan visibility works, active PWM control requires additional setup)

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
and configuration protection. It ensures the driver loads reliably after reboots
and kernel updates, and guards against fancontrol configuration loss.

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
git clone --recurse-submodules https://github.com/0n1cOn3/UGREEN-Fan-Control.git
cd UGREEN-Fan-Control
sudo ./scripts/install.sh
```

4) Detect sensors and configure fan control

```bash
sudo sensors-detect
```

You can answer all questions with Y.

> [!NOTE]
> If you have previously executed lm_sensors and the dkms module has not yet been installed, you may see the following message:
>
> ```txt
> Found `ITE IT8613E Super IO Sensors'                        Success!
> (address 0xa30, driver `to-be-written')
> ```
>
> That's normal behavior and will still appear even when the driver has been installed. The interface to the ventilation is now available.

5) Configure which fan uses which channel

```bash
sudo pwmconfig
```

This utility will create the fancontrol config file in `/etc/fancontrol`.

6) Enable and start the fancontrol service

```bash
sudo systemctl enable --now fancontrol
```

The installer automatically sets up systemd services that ensure:
- The `hwmon-vid` dependency module is loaded before `it87`
- The it87 driver is loaded **before** fancontrol starts (prevents race conditions)
- The fancontrol configuration is backed up and restored if corrupted
- Device paths are updated automatically if they change after reboot

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

4) Testing and configure the fans by configuring lm_sensors

```bash
sudo sensors-detect
```

You can answer all questions with Y.

5) Configure fan channels with pwmconfig

```bash
sudo pwmconfig
```

This small application will take over for creating the fancontrol config file in /etc

6) Activate the fancontrol service at boot time

```bash
systemctl enable --now fancontrol
```

</details>

## Uninstall

To remove the driver, services, and configuration files:

```bash
sudo ./scripts/uninstall.sh
```

This preserves your `/etc/fancontrol` configuration. Remove it manually if no longer needed.

## Troubleshooting

### Fan control stops working after reboot

The automated installer prevents this by setting up proper systemd service ordering.
If you installed manually, ensure the it87 module is loaded before fancontrol starts:

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

If `modprobe hwmon-vid` fails, follow **Installer aborts because `hwmon-vid` is unavailable** below.

For persistence across reboots, use the same modules-load/modprobe steps shown in
**Fan control stops working after reboot** above.

### Installer aborts because `hwmon-vid` is unavailable

The installer now checks whether `hwmon-vid` exists for your running kernel and
aborts if it is missing, to prevent an unusable setup.

Install a kernel/headers package that provides `hwmon-vid`, then run the
installer again.

### Configuration file is corrupted or missing

The automated installer includes a config guard that backs up and restores the configuration.
To manually restore from backup:

```bash
sudo /usr/local/sbin/fancontrol-config-guard.sh restore
```

To recreate the configuration from scratch:

```bash
sudo systemctl stop fancontrol
sudo pwmconfig
sudo systemctl start fancontrol
```

### DXP4800 — fan visibility works but pwmconfig finds no controllable channels

On the DXP4800 the IT8613E chip starts up with **pwm2 and pwm3 already in
hardware automatic mode**.

When `pwmconfig` asks:

```
Would you like to generate a detailed correlation table? (y/n)
```

select **n** (the detailed table is optional and can take longer).

When `pwmconfig` later offers to switch pwm2/pwm3 from automatic to manual
control, select **y** and let `pwmconfig` take them over. pwm4 and pwm5 are
not wired to the fans on this model; pwm2/pwm3 are the correct channels.

After `pwmconfig` finishes, verify that the fans respond by watching
`sensors` output while the service is running:

```bash
sudo systemctl start fancontrol
watch -n 2 sensors
```

If the fan RPM values change as expected, enable the service permanently:

```bash
sudo systemctl enable --now fancontrol
```

> [!NOTE]
> Unlike the DXP2800 (where fans idle at 0 RPM between `pwmconfig` tests),
> the DXP4800 fans continue spinning under hardware control during the
> correlation test.  The correct strategy is to **accept** the offer to
> switch pwm2/pwm3 to manual mode so that `fancontrol` can manage them.

### DKMS module fails to build after kernel update

```bash
# Check DKMS status
dkms status it87

# Rebuild for current kernel
cd it87
make clean
sudo make dkms
```

### Why did i that?

The idea for this project has been brought by this [Reddit post](https://www.reddit.com/r/unRAID/comments/1dzep0s/how_to_configure_fan_control_ugreen_nas/)

### Who wrote the dkms module?

That was written by 
 *  Copyright (C) 2001 Chris Gauthron
 *  Copyright (C) 2005-2010 Jean Delvare <jdelvare@suse.de>
and archived by [a1wong](https://github.com/a1wong/it87)

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

```bash
root@lainpool:/# fancontrol
Loading configuration from /etc/fancontrol ...

Common settings:
  INTERVAL=10

Settings for hwmon2/pwm3:
  Depends on hwmon1/temp3_input
  Controls hwmon2/fan3_input
  MINTEMP=22
  MAXTEMP=60
  MINSTART=105
  MINSTOP=26
  MINPWM=24
  MAXPWM=255
  AVERAGE=1
```

```bash
sensors
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

# Bugs

Please report them [here](https://github.com/IT-Kuny/UGREEN-DXP-FAN-NAS-Driver/issues).

## Donations

It took me a few hours to prepare, testing and deliver this for you. :)
I'll appreciate any contribution to the coffee fund :3

BTC: ```3EdkooEbQJurjCHScwUjPHGCCszoFh1pmM```

ETH: ```0x0dB50ef6C03c354795e306133B71A69d8F2e9cc6```

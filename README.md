# nvhoct.sh (Nvidia Headless Overclocking Tool)

nvhoct.sh is a lightweight Bash script designed to apply overclocking offsets and power-limit changes to Nvidia GPUs on headless Linux servers. It can generate a configuration file with sensible defaults, interactively collect user offsets, and apply or reset settings in batch—without ever opening a desktop session.

---

## Table of contents

1. [Prerequisites](#prerequisites)  
2. [Installation](#installation)  
3. [Usage](#usage)  
4. [Configuration](#configuration)  
5. [How it works](#how-it-works)  
6. [Why the need for a screen session](#Why-the-need-for-a-screen-session?)  
7. [Logging](#logging)  
8. [Options](#options)  
9. [Licence](#licence)  

---

## Prerequisites

- A Linux host with the proprietary Nvidia driver installed  
- `nvidia-smi` and `nvidia-settings` in your PATH  
- `screen` for spawning a temporary X server  
- Root or sudo privileges  

---

## Installation

1. Clone this repository  
   ```bash
   git clone https://github.com/vjsyong/nvhoct.git
   cd nvhoct
   ```  
2. Make the script executable  
   ```bash
   chmod +x nvhoct.sh
   ```  

---

## Usage

```bash
sudo ./nvhoct.sh [options]
```

**Examples**  
- Initialise a fresh config with each card’s default power-limit, then exit:  
  ```bash
  sudo ./nvhoct.sh --init
  ```  
- Apply settings from `oc_config.ini` to all GPUs:  
  ```bash
  sudo ./nvhoct.sh
  ```  
- Reset GPU 0 and 2 to zero offsets and no power limit:  
  ```bash
  sudo ./nvhoct.sh --reset-gpu 0,2
  ```  
- Dry-run without changing anything:  
  ```bash
  sudo ./nvhoct.sh --dry-run
  ```

---

## Configuration

The script reads `oc_config.ini` in the current directory. If it does not exist, nvhoct.sh will enter an interactive setup to create it. You can also regenerate it with defaults:

```bash
sudo ./nvhoct.sh --init
```

Each `gpuX` section includes:

- `core_offset` (MHz)  
- `mem_offset` (MHz)  
- `power_limit` (Watts)  

Recommended step sizes and safe bounds are documented in the header of the INI file.

---

## How it works

1. **Privilege check**  
   The script exits immediately if not run as root or via sudo.  
2. **Argument parsing**  
   Flags include `--init`, `--dry-run`, `--gpu`, `--reset-all`, `--reset-gpu`, `--verbose`.  
3. **Configuration generation**  
   With `--init`, nvhoct.sh queries each card’s default power limit via `nvidia-smi`, rounds it to an integer and writes `oc_config.ini`.  
4. **Interactive setup**  
   If no config file is found and `--init` is omitted, the script prompts for offsets and limits per GPU.  
5. **Target selection**  
   Determines which GPUs to touch based on `--gpu`, `--reset-gpu` or `--reset-all`.  
6. **Reset mode**  
   If requested, sends zero offsets and unsets any power limit.  
7. **Headless X server**  
   Launches a minimal X session inside a `screen` to allow `nvidia-settings` to operate without an attached display.  
8. **Apply settings**  
   Reads offsets and power limits from the INI file, validates against safe bounds, calls `nvidia-smi` and `nvidia-settings`.  
9. **Cleanup**  
   Quits the temporary screen session, killing the headless X server.

---

## Why the need for a screen session?

`nvidia-settings` requires an X server to apply clock and memory offsets. On a headless machine (no physical GPU-attached monitor), there is no native DISPLAY. By spawning a lightweight X server inside a detached `screen`, nvhoct.sh:

- Keeps the session isolated so it cannot interfere with any existing X instances  
- Runs completely in the background without blocking your shell  
- Automatically tears down as soon as overclock settings are applied  

---

## Logging

All actions and any warnings or errors are written both to stdout (with colour coding) and to a log file:

- By default: `/var/log/gpu_oc.log` (falls back to `~/gpu_oc.log` if the directory is not writable)  
- Contains timestamps, log level and descriptive messages for audit and debugging  

---

## Options

| Option               | Description                                                                 |
|----------------------|-----------------------------------------------------------------------------|
| `--init`             | Generate or regenerate `oc_config.ini` and exit                              |
| `--dry-run`          | Show commands without executing them                                         |
| `--gpu <list>`       | Apply only to specified GPUs (e.g. `0,2-4`)                                   |
| `--reset-all`        | Reset all GPUs to zero offsets and remove any power limit                    |
| `--reset-gpu <list>` | Reset only the specified GPUs                                                |
| `--verbose`          | Enable debug logging                                                         |
| `--help`             | Show usage instructions and exit                                             |

---

## Licence

This project is released under the MIT or the CC0 Licence at your choice. See the [LICENSE](LICENSE) file for details.

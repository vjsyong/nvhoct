#!/usr/bin/env bash

# nvhoct.sh is a headless Bash utility that applies and resets Nvidia GPU core and memory overclock offsets and power limits on Linux servers via a temporary X session.

# Exit if not run as root
if [[ "$EUID" -ne 0 ]]; then
  echo "This script must be run with sudo or as root. Exiting."
  exit 1
fi

CONFIG_FILE="oc_config.ini"

# Generic defaults
DEFAULT_CORE=0
DEFAULT_MEM=0
DEFAULT_POWER=0    # fallback if we can't detect the card's default

# Recommended step sizes
STEP_CORE=25    # MHz
STEP_MEM=200    # MHz

# Safe bounds
CORE_MIN=-500; CORE_MAX=500
MEM_MIN=0;     MEM_MAX=5000
POWER_MIN=1;   POWER_MAX=1000

# Logging setup
LOG_FILE="/var/log/gpu_oc.log"
if [[ ! -w "$(dirname "$LOG_FILE")" ]]; then
    LOG_FILE="$HOME/gpu_oc.log"
fi

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC}  $1";  echo "$(date '+%F %T') [INFO]  $1"  >> "$LOG_FILE"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; echo "$(date '+%F %T') [WARN]  $1"  >> "$LOG_FILE"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1";  echo "$(date '+%F %T') [ERROR] $1"  >> "$LOG_FILE"; }
log_debug() { [[ $VERBOSE ]] && echo -e "[DEBUG] $1"; [[ $VERBOSE ]] && echo "$(date '+%F %T') [DEBUG] $1" >> "$LOG_FILE"; }

show_help() {
  cat <<EOF
Usage: $0 [options]

Options:
  --init             Generate or regenerate $CONFIG_FILE and exit
  --dry-run          Show commands without running them
  --gpu <list>       Apply only to specified GPUs (e.g. "0,2-4")
  --reset-all        Reset all GPUs to zero offsets and no power limit
  --reset-gpu <list> Reset only the specified GPUs
  --verbose          Enable debug logging
  --help             Show this help text
EOF
}

# parse comma/range list into array
parse_list() {
  local list=$1; local -n out=$2
  IFS=',' read -ra parts <<< "$list"
  for part in "${parts[@]}"; do
    if [[ $part =~ ^([0-9]+)-([0-9]+)$ ]]; then
      for ((i=${BASH_REMATCH[1]}; i<=${BASH_REMATCH[2]}; i++)); do out+=("$i"); done
    else
      out+=("$part")
    fi
  done
}

# extract a key’s value from an INI section
get_config_value() {
    awk -F= -v section="[$1]" -v key="$2" '
    /^\[.*\]$/ {
        if ($0 == section) in_section=1; else in_section=0
        next
    }
    in_section==1 && $1 == key {
        gsub(/ /, "", $2)
        print $2
        exit
    }
    ' "$CONFIG_FILE"
}

# detect WSL
if grep -qi microsoft /proc/version 2>/dev/null; then
  log_error "WSL is not supported by this script."
  exit 1
fi

# parse arguments
INIT=; DRY_RUN=; VERBOSE=; RESET_ALL=; GPU_TARGETS=(); RESET_TARGETS=()
while [[ $# -gt 0 ]]; do
  case $1 in
    --init)       INIT=1; shift ;;
    --dry-run)    DRY_RUN=1; shift ;;
    --verbose)    VERBOSE=1; shift ;;
    --reset-all)  RESET_ALL=1; shift ;;
    --gpu)        parse_list "$2" GPU_TARGETS; shift 2 ;;
    --reset-gpu)  parse_list "$2" RESET_TARGETS; shift 2 ;;
    --help)       show_help; exit 0 ;;
    *) log_error "Unknown option $1"; show_help; exit 1 ;;
  esac
done

# gather GPU names
gpu_info=()
while IFS= read -r line; do gpu_info+=("$line"); done < <(
  nvidia-smi --query-gpu=name --format=csv,noheader
)
GPU_COUNT=${#gpu_info[@]}
log_debug "Found $GPU_COUNT GPUs."

# --init: generate config using each card’s default power limit, then exit
if [[ $INIT ]]; then
  [[ -f $CONFIG_FILE ]] && {
    bak="$CONFIG_FILE.bak-$(date +%Y%m%d-%H%M%S)"
    cp "$CONFIG_FILE" "$bak"
    log_info "Backed up old config to $bak"
  }
  > "$CONFIG_FILE"
  cat <<EOF >> "$CONFIG_FILE"
# NVIDIA OC configuration
# ------------------------
# Start with all offsets = 0.
# Increase core_offset in ${STEP_CORE} MHz steps.
# Increase mem_offset  in ${STEP_MEM} MHz steps.
# power_limit is initialized to each card's default.
EOF

  for i in "${!gpu_info[@]}"; do
    # Query the card's default power limit (might be a float like "270.00")
    raw_pl=$(nvidia-smi --id="$i" --query-gpu=power.default_limit --format=csv,noheader,nounits 2>/dev/null)
    # Round to nearest integer (printf %.0f does “round to nearest”)
    default_pl=$(printf "%.0f" "$raw_pl" 2>/dev/null || echo "$DEFAULT_POWER")
    # Fallback if still empty or not a number
    default_pl=${default_pl:-$DEFAULT_POWER}
    cat <<EOF >> "$CONFIG_FILE"

# GPU $i: ${gpu_info[$i]}
[gpu$i]
core_offset=$DEFAULT_CORE
mem_offset=$DEFAULT_MEM
power_limit=$default_pl
EOF
  done

  log_info "Written new $CONFIG_FILE with default power limits for $GPU_COUNT GPUs."
  exit 0
fi

# interactive setup if no config
if [[ ! -f $CONFIG_FILE ]]; then
  log_info "$CONFIG_FILE not found; entering interactive setup."
  > "$CONFIG_FILE"
  cat <<EOF >> "$CONFIG_FILE"
# NVIDIA OC configuration
# ------------------------
# Start with all offsets = 0.
# Increase core_offset in ${STEP_CORE} MHz steps.
# Increase mem_offset  in ${STEP_MEM} MHz steps.
# power_limit = 0 means no change; set as needed.
EOF

  for i in "${!gpu_info[@]}"; do
    echo; echo "GPU $i: ${gpu_info[$i]}"
    read -rp "  Core offset [${DEFAULT_CORE}]: " co
    read -rp "  Mem offset  [${DEFAULT_MEM}]: " mo
    read -rp "  Power limit  [${DEFAULT_POWER}]: " pl
    co=${co:-$DEFAULT_CORE}; mo=${mo:-$DEFAULT_MEM}; pl=${pl:-$DEFAULT_POWER}
    cat <<EOF >> "$CONFIG_FILE"

# GPU $i: ${gpu_info[$i]}
[gpu$i]
core_offset=$co
mem_offset=$mo
power_limit=$pl
EOF
  done

  log_info "Interactive config saved to $CONFIG_FILE."
fi

# decide which GPUs to touch
if [[ $RESET_ALL ]]; then
  TARGETS=($(seq 0 $((GPU_COUNT-1))))
elif (( ${#RESET_TARGETS[@]} )); then
  TARGETS=("${RESET_TARGETS[@]}")
elif (( ${#GPU_TARGETS[@]} )); then
  TARGETS=("${GPU_TARGETS[@]}")
else
  TARGETS=($(seq 0 $((GPU_COUNT-1))))
fi

# reset mode
if [[ $RESET_ALL || ${#RESET_TARGETS[@]} -gt 0 ]]; then
  for id in "${TARGETS[@]}"; do
    [[ $id -ge 0 && $id -lt $GPU_COUNT ]] || { log_warn "Skip invalid GPU $id"; continue; }
    log_info "Resetting GPU $id (${gpu_info[$id]})"
    for cmd in \
      "sudo nvidia-smi -i $id -pl 0" \
      "nvidia-settings -a [gpu:$id]/GPUGraphicsClockOffsetAllPerformanceLevels=0" \
      "nvidia-settings -a [gpu:$id]/GPUMemoryTransferRateOffsetAllPerformanceLevels=0"
    do
      if [[ $DRY_RUN ]]; then
        echo "DRY-RUN: $cmd"
      else
        eval $cmd
      fi
    done
  done
  exit 0
fi

# start X via screen
screen_name="temp_x_$$"
screen -dmS "$screen_name" bash -c "sudo X :1"
sleep 2
export DISPLAY=:1

# apply config
for id in "${TARGETS[@]}"; do
  if (( id<0 || id>=GPU_COUNT )); then
    log_warn "Skipping invalid GPU $id"; continue
  fi
  name="${gpu_info[$id]}"
  co=$(get_config_value "gpu$id" core_offset); mo=$(get_config_value "gpu$id" mem_offset); pl=$(get_config_value "gpu$id" power_limit)
  co=${co:-$DEFAULT_CORE}; mo=${mo:-$DEFAULT_MEM}; pl=${pl:-$DEFAULT_POWER}
  (( co<CORE_MIN || co>CORE_MAX )) && { log_warn "core_offset $co out of [$CORE_MIN,$CORE_MAX], resetting to $DEFAULT_CORE"; co=$DEFAULT_CORE; }
  (( mo<MEM_MIN   || mo>MEM_MAX  )) && { log_warn "mem_offset  $mo out of [$MEM_MIN,$MEM_MAX], resetting to $DEFAULT_MEM"; mo=$DEFAULT_MEM; }
  (( pl<POWER_MIN || pl>POWER_MAX)) && { log_warn "power_limit $pl out of [$POWER_MIN,$POWER_MAX], resetting to $DEFAULT_POWER"; pl=$DEFAULT_POWER; }
  log_info "GPU $id ($name): core=$co mem=$mo power=$pl"
  for cmd in \
    "sudo nvidia-smi -i $id -pl $pl" \
    "nvidia-settings -a [gpu:$id]/GPUGraphicsClockOffsetAllPerformanceLevels=$co" \
    "nvidia-settings -a [gpu:$id]/GPUMemoryTransferRateOffsetAllPerformanceLevels=$mo"
  do
    if [[ $DRY_RUN ]]; then
      echo "DRY-RUN: $cmd"
    else
      eval $cmd
    fi
  done
done

# teardown X
screen -S "$screen_name" -X quit

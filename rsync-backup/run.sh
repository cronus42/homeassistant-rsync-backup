#!/usr/bin/env sh
set -eu

OPTIONS_FILE="/data/options.json"
STATE_DIR="/data/state"
SSH_DIR="/data/ssh"

mkdir -p "${STATE_DIR}" "${SSH_DIR}"

LOG_LEVEL_NUM=20 # default INFO

log_level_to_num() {
  case "$1" in
    DEBUG) echo 10 ;;
    INFO) echo 20 ;;
    WARNING) echo 30 ;;
    ERROR) echo 40 ;;
    *) echo 20 ;;
  esac
}

log() {
  level="$1"; shift
  lvl_num=$(log_level_to_num "${level}")
  if [ "${lvl_num}" -lt "${LOG_LEVEL_NUM}" ]; then
    return
  fi
  echo "[${level}] $*"
}

if [ ! -f "${OPTIONS_FILE}" ]; then
  echo "[ERROR] Options file ${OPTIONS_FILE} not found; exiting." >&2
  exit 1
fi

REMOTE_HOST=$(jq -r '.remote_host // empty' "${OPTIONS_FILE}")
REMOTE_PORT=$(jq -r '.remote_port // 22' "${OPTIONS_FILE}")
REMOTE_USER=$(jq -r '.remote_user // empty' "${OPTIONS_FILE}")
REMOTE_PATH=$(jq -r '.remote_path // empty' "${OPTIONS_FILE}")
SYNC_INTERVAL_MINUTES=$(jq -r '.sync_interval_minutes // 60' "${OPTIONS_FILE}")
USE_GENERATED_KEY=$(jq -r '.use_generated_key // true' "${OPTIONS_FILE}")
UPLOADED_KEY=$(jq -r '.uploaded_private_key // ""' "${OPTIONS_FILE}")
KNOWN_HOSTS_OPT=$(jq -r '.known_hosts // ""' "${OPTIONS_FILE}")
LOG_LEVEL_OPT=$(jq -r '.log_level // "INFO"' "${OPTIONS_FILE}")

LOG_LEVEL_NUM=$(log_level_to_num "${LOG_LEVEL_OPT}")
log INFO "Effective log level: ${LOG_LEVEL_OPT} (${LOG_LEVEL_NUM})"

if [ -z "${REMOTE_HOST}" ] || [ -z "${REMOTE_USER}" ] || [ -z "${REMOTE_PATH}" ]; then
  log ERROR "remote_host, remote_user, and remote_path must be configured."
  exit 1
fi

KEY_PATH="${SSH_DIR}/id_ed25519"
PUB_KEY_PATH="${SSH_DIR}/id_ed25519.pub"
KNOWN_HOSTS_PATH="${SSH_DIR}/known_hosts"

# Handle SSH key material
if [ "${USE_GENERATED_KEY}" = "true" ]; then
  if [ ! -f "${KEY_PATH}" ]; then
    log INFO "Generating new SSH key at ${KEY_PATH}."
    ssh-keygen -t ed25519 -N "" -f "${KEY_PATH}" >/dev/null 2>&1
    if [ -f "${PUB_KEY_PATH}" ]; then
      log INFO "Generated SSH public key (add this to the remote authorized_keys):"
      log INFO "$(cat "${PUB_KEY_PATH}")"
    else
      log WARNING "SSH public key ${PUB_KEY_PATH} not found after key generation."
    fi
  else
    log INFO "Using existing generated key at ${KEY_PATH}."
  fi
else
  if [ -n "${UPLOADED_KEY}" ]; then
    log INFO "Writing uploaded private key to ${KEY_PATH}."
    # The uploaded key may contain literal \\n characters; convert them to newlines.
    printf '%s' "${UPLOADED_KEY}" | sed 's/\\\\n/\\n/g' >"${KEY_PATH}"
    chmod 600 "${KEY_PATH}"
  elif [ ! -f "${KEY_PATH}" ]; then
    log ERROR "use_generated_key is false and no uploaded_private_key or existing key found."
    exit 1
  fi
fi

# Handle known_hosts (optional)
if [ -n "${KNOWN_HOSTS_OPT}" ]; then
  log INFO "Writing known_hosts content."
  printf '%s
' "${KNOWN_HOSTS_OPT}" >"${KNOWN_HOSTS_PATH}"
  chmod 600 "${KNOWN_HOSTS_PATH}"
fi

# Base SSH options: identity and port; host-key policy depends on whether known_hosts is configured.
SSH_BASE_OPTS="-i ${KEY_PATH} -p ${REMOTE_PORT}"
if [ -f "${KNOWN_HOSTS_PATH}" ]; then
  # Strict checking against the provided known_hosts file.
  SSH_BASE_OPTS="${SSH_BASE_OPTS} -o StrictHostKeyChecking=yes -o UserKnownHostsFile=${KNOWN_HOSTS_PATH}"
else
  # Accept new host keys automatically and remember them for future connections.
  SSH_BASE_OPTS="${SSH_BASE_OPTS} -o StrictHostKeyChecking=accept-new"
fi

log INFO "Starting rsync loop to ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH} every ${SYNC_INTERVAL_MINUTES} minute(s)."

trap 'log INFO "Received termination signal, exiting."; exit 0' TERM INT

while true; do
  log INFO "Running rsync sync of /backup -> ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}"
  rsync -avz --delete -e "ssh ${SSH_BASE_OPTS}" /backup/ "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/"
  rc=$?
  if [ "${rc}" -ne 0 ]; then
    log ERROR "rsync failed with exit code ${rc}."
    # Avoid hammering the remote if credentials or connectivity are broken.
    sleep 60
  else
    log INFO "Sync cycle complete; sleeping ${SYNC_INTERVAL_MINUTES} minute(s)."
    sleep "$((SYNC_INTERVAL_MINUTES * 60))"
  fi
done

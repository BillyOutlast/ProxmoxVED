#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: BillyOutlast
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/mudler/LocalAI


source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y pciutils
msg_ok "Installed Dependencies"

# Enhanced binary download with better error handling
fetch_and_deploy_gh_release "localai" "mudler/LocalAI" "singlefile" "latest" "/opt/localai-bin" "local-ai-v*-linux-amd64"

localai_binary="$(find /opt/localai-bin -maxdepth 1 -type f -name 'local-ai-v*-linux-amd64' | sort | tail -n1)"
if [[ -z "$localai_binary" ]]; then
  msg_error "Unable to locate downloaded LocalAI linux-amd64 binary"
  exit 1
fi

# Install the binary with better error handling
install -m 755 "$localai_binary" /usr/local/bin/local-ai || {
  msg_error "Failed to install LocalAI binary"
  exit 1
}

if [[ -f ~/.localai ]]; then
  tr -d '\n' <~/.localai >/opt/localai_version.txt || {
    msg_warn "Failed to create version file"
  }
fi

# Enhanced GPU detection and ROCm installation
if grep -qE '(VGA|3D controller|Display controller).*\[1002:'; then
  msg_info "Installing ROCm"
  export DEBIAN_FRONTEND=noninteractive

  apt_get_retry_install() {
    local args="$*"
    local attempt
    for attempt in 1 2 3; do
      apt-get -qq -o Dpkg::Use-Pty=0 -o Acquire::Retries=5 -o Acquire::http::No-Cache=true -o Acquire::https::No-Cache=true update >/dev/null 2>&1 && \
        apt-get -qq -o Dpkg::Use-Pty=0 -o Acquire::Retries=5 install -y $args >/dev/null 2>&1 && return 0
      apt-get clean || true
      rm -rf /var/lib/apt/lists/* || true
      if [[ "$attempt" -lt 3 ]]; then
        sleep 5
      fi
    done
    return 1
  }

  # Add better error handling for repository setup
  mkdir -p /etc/apt/keyrings
  
  # Try multiple approaches to get the ROCm key
  if ! curl -fsSL https://repo.radeon.com/rocm/rocm.gpg.key | gpg --dearmor -o /etc/apt/keyrings/rocm.gpg; then
    msg_error "Failed to download ROCm GPG key"
    exit 1
  fi
  
  chmod 644 /etc/apt/keyrings/rocm.gpg

  cat <<EOF >/etc/apt/sources.list.d/rocm.list
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/7.2 noble main
deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/graphics/7.2/ubuntu noble main
EOF

  cat <<EOF >/etc/apt/preferences.d/rocm-pin-600
Package: *
Pin: release o=repo.radeon.com
Pin-Priority: 600
EOF

  # Update package lists and install ROCm with better error handling
  apt-get update -o Acquire::Retries=3 >/dev/null 2>&1 || {
    msg_error "Failed to update package lists for ROCm installation"
    exit 1
  }
  
  apt_get_retry_install --fix-missing --no-install-recommends rocm
  msg_ok "Installed ROCm"
fi

# Create directories with better error handling
mkdir -p /etc/localai /var/lib/localai/models || {
  msg_error "Failed to create LocalAI directories"
  exit 1
}


DOCKER_LATEST_VERSION=$(get_latest_github_release "moby/moby")
msg_info "Installing Docker $DOCKER_LATEST_VERSION (with Compose, Buildx)"
DOCKER_CONFIG_PATH='/etc/docker/daemon.json'
mkdir -p $(dirname $DOCKER_CONFIG_PATH)
echo -e '{\n  "log-driver": "journald"\n}' >/etc/docker/daemon.json
$STD sh <(curl -fsSL https://get.docker.com)
msg_ok "Installed Docker $DOCKER_LATEST_VERSION"

cat <<EOF >/etc/localai/localai.env
MODELS_PATH=/var/lib/localai/models
EOF
chmod 644 /etc/localai/localai.env

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/localai.service
[Unit]
Description=LocalAI Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/var/lib/localai
EnvironmentFile=/etc/localai/localai.env
ExecStart=/usr/local/bin/local-ai
Restart=on-failure
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload || {
  msg_error "Failed to reload systemd"
  exit 1
}
systemctl enable -q --now localai || {
  msg_error "Failed to enable/start LocalAI service"
  exit 1
}
msg_ok "Created Service"

if ! systemctl is-active -q localai; then
  msg_error "Failed to start LocalAI service"
  exit 1
fi
msg_ok "Started LocalAI"

motd_ssh
customize
cleanup_lxc

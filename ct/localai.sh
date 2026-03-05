#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)


# Copyright (c) 2021-2026 community-scripts ORG
# Author: BillyOutlast
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/mudler/LocalAI

APP="LocalAI"
var_tags="${var_tags:-ai;llm}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-64}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
var_nesting="${var_nesting:-1}"
var_keyctl="${var_keyctl:-1}"
var_gpu="${var_gpu:-yes}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if check_for_gh_release "localai" "mudler/LocalAI"; then
    msg_info "Stopping LocalAI Service"
    pct exec "$CTID" -- systemctl stop localai || true
    msg_ok "Stopped LocalAI Service"

    fetch_and_deploy_gh_release "localai" "mudler/LocalAI" "singlefile" "latest" "/opt/localai-bin" "local-ai-v*-linux-amd64"

    msg_info "Updating LocalAI Binary"
    pct exec "$CTID" -- bash -lc '
      set -e
      localai_binary="$(find /opt/localai-bin -maxdepth 1 -type f -name "local-ai-v*-linux-amd64" | sort | tail -n1)"
      if [[ -z "$localai_binary" ]]; then
        echo "Unable to locate downloaded LocalAI linux-amd64 binary" >&2
        exit 1
      fi
      install -m 755 "$localai_binary" /usr/local/bin/local-ai
      if [[ -f ~/.localai ]]; then
        tr -d "\n" <~/.localai >/opt/localai_version.txt
      fi
    '
    msg_ok "Updated LocalAI Binary"

    msg_info "Starting LocalAI Service"
    pct exec "$CTID" -- systemctl restart localai || {
      msg_error "Failed to start LocalAI service"
      exit 1
    }
    msg_ok "Started LocalAI Service"

    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description


msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
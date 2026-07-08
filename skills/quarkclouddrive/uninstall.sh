#!/usr/bin/env bash

set -euo pipefail


INSTALL_DIR="$HOME/.quarkclouddrive"


RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

info()  { printf "${GREEN}[info]${NC}  %s\n" "$*"; }
warn()  { printf "${YELLOW}[warn]${NC}  %s\n" "$*"; }
error() { printf "${RED}[error]${NC} %s\n" "$*" >&2; }


revoke_auth() {
  info "Step 1: 撤销本机授权并清除当前 agent 配置 (logout)..."

  local cli_bin="$INSTALL_DIR/quarkclouddrive"

  if [ -x "$cli_bin" ]; then
    if "$cli_bin" logout >/dev/null 2>&1; then
      info "已撤销本机授权并清除当前 agent 配置"
    else
      warn "撤销本机授权失败（可能未登录或网络异常），继续卸载"
    fi
  elif command -v quarkclouddrive &>/dev/null; then
    if quarkclouddrive logout >/dev/null 2>&1; then
      info "已撤销本机授权并清除当前 agent 配置"
    else
      warn "撤销本机授权失败（可能未登录或网络异常），继续卸载"
    fi
  else
    info "未找到 quarkclouddrive 可执行文件，跳过授权撤销"
  fi

  return 0
}


print_result() {
  local divider
  divider=$(printf '%0.s─' {1..50})

  printf '\n%s\n' "$divider"

  printf "${GREEN}${BOLD}✅ quarkclouddrive CLI 卸载完成${NC}\n\n"
  printf "  已清理以下内容:\n"
  printf "  • 当前 agent 的授权与配置目录（~/.quarkclouddrive/<agentId>）\n\n"
  printf "  为避免影响共享同一安装目录的其他 agent，已保留:\n"
  printf "  • 安装目录  ${BOLD}%s${NC}（含 CLI 二进制及其他 agent 配置）\n" "$INSTALL_DIR"
  printf "  • 全局命令  ${BOLD}quarkclouddrive${NC} 及 shell 配置中的 PATH 条目\n"

  printf '%s\n\n' "$divider"
}


main() {
  info "=== quarkclouddrive CLI 卸载脚本 ==="
  echo ""

  revoke_auth

  print_result
}

main "$@"

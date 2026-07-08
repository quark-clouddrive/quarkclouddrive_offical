#!/usr/bin/env bash

set -euo pipefail


SKILL_OPEN_API_HOST="https://open-api-drive.quark.cn"
if [ -z "$SKILL_OPEN_API_HOST" ] || [[ "$SKILL_OPEN_API_HOST" == __*__ ]]; then
  SKILL_OPEN_API_HOST="https://open-api-drive.quark.cn"
fi

SKILL_CONFIG_URL="${SKILL_OPEN_API_HOST}/agent/v1/skill_config"

ZIP_DOWNLOAD_URL=""
REMOTE_VERSION=""
REQUIRED_NODE_MAJOR=16
INSTALL_DIR="$HOME/.quarkclouddrive"
TMP_DIR="${TMPDIR:-/tmp}/quarkclouddrive-install-$$"

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

IS_UPDATE="false"
if [ -d "$INSTALL_DIR" ] && [ -f "$INSTALL_DIR/scripts/quark-drive.cjs" ]; then
  IS_UPDATE="true"
fi


info()  { printf "[info]  %s\n" "$*"; }
warn()  { printf "[warn]  %s\n" "$*"; }
error() { printf "[error] %s\n" "$*"; }


resolve_install_dir() {
  if [ -d "$INSTALL_DIR" ] && [ -f "$INSTALL_DIR/scripts/quark-drive.cjs" ]; then
    return 0
  fi

  local which_result real_path resolved_dir
  if which_result=$(which quarkclouddrive 2>/dev/null) && [ -n "$which_result" ]; then
    real_path=$(readlink -f "$which_result" 2>/dev/null || realpath "$which_result" 2>/dev/null || echo "")
    if [ -n "$real_path" ]; then
      resolved_dir=$(dirname "$real_path")
      if [ -f "$resolved_dir/scripts/quark-drive.cjs" ]; then
        INSTALL_DIR="$resolved_dir"
        return 0
      fi
    fi
  fi

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [ -f "$script_dir/scripts/quark-drive.cjs" ]; then
    INSTALL_DIR="$script_dir"
    return 0
  fi

  error "无法定位已有的安装目录"
  return 1
}


OS_TYPE=""
detect_os() {
  info "Step 1: 检测运行环境..."

  case "$(uname -s)" in
    Linux*)   OS_TYPE="linux" ;;
    Darwin*)  OS_TYPE="mac" ;;
    CYGWIN*|MINGW*|MSYS*) OS_TYPE="windows" ;;
    *)
      error "不支持的操作系统: $(uname -s)"
      return 1
      ;;
  esac

  info "检测到操作系统: ${OS_TYPE}"
}


ensure_node() {
  info "Step 2: 检测 Node.js 环境..."

  if command -v node &>/dev/null; then
    local node_version major_version
    node_version=$(node --version)
    major_version=$(echo "$node_version" | sed 's/v//' | cut -d. -f1)
    info "当前 Node.js 版本: $node_version"

    if [ "$major_version" -ge "$REQUIRED_NODE_MAJOR" ]; then
      info "Node.js 版本满足要求 (>= v${REQUIRED_NODE_MAJOR})"
      return 0
    fi

    warn "Node.js 版本 $node_version 低于 v${REQUIRED_NODE_MAJOR}，需要升级..."
  else
    warn "未检测到 Node.js，将自动安装..."
  fi

  install_node
}

install_node() {
  case "$OS_TYPE" in
    mac)
      install_node_mac
      ;;
    linux)
      install_node_linux
      ;;
    windows)
      install_node_windows
      ;;
  esac
}

install_node_mac() {
  if command -v brew &>/dev/null; then
    info "使用 Homebrew 安装 Node.js..."
    brew unlink node 2>/dev/null || true
    brew install node@${REQUIRED_NODE_MAJOR}
    brew link --overwrite --force node@${REQUIRED_NODE_MAJOR} 2>/dev/null || true
    if command -v node &>/dev/null; then
      return 0
    fi
  fi

  error "请手动安装 Node.js v${REQUIRED_NODE_MAJOR}+: https://nodejs.org/"
  return 1
}

install_node_linux() {
  if command -v apt-get &>/dev/null; then
    info "使用 apt 安装 Node.js ${REQUIRED_NODE_MAJOR}..."
    curl -fsSL "https://deb.nodesource.com/setup_${REQUIRED_NODE_MAJOR}.x" | sudo -E bash - 2>/dev/null
    sudo apt-get install -y nodejs 2>/dev/null
    if command -v node &>/dev/null; then
      return 0
    fi
  elif command -v yum &>/dev/null; then
    info "使用 yum 安装 Node.js ${REQUIRED_NODE_MAJOR}..."
    curl -fsSL "https://rpm.nodesource.com/setup_${REQUIRED_NODE_MAJOR}.x" | sudo bash - 2>/dev/null
    sudo yum install -y nodejs 2>/dev/null
    if command -v node &>/dev/null; then
      return 0
    fi
  fi

  error "请手动安装 Node.js v${REQUIRED_NODE_MAJOR}+: https://nodejs.org/"
  return 1
}

install_node_windows() {
  error "Windows 请手动安装 Node.js v${REQUIRED_NODE_MAJOR}+: https://nodejs.org/"
  return 1
}


get_local_version() {
  local skill_md="$SKILL_DIR/SKILL.md"
  if [ -f "$skill_md" ]; then
    local md_ver
    md_ver=$(grep -oE 'qk-skill-version:\s*[0-9]+\.[0-9]+\.[0-9]+' "$skill_md" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [ -n "$md_ver" ]; then
      printf '%s' "$md_ver"
      return 0
    fi
  fi

  local out=""
  if [ -x "$INSTALL_DIR/quarkclouddrive" ]; then
    out=$("$INSTALL_DIR/quarkclouddrive" --version 2>/dev/null || true)
  elif command -v quarkclouddrive &>/dev/null; then
    out=$(quarkclouddrive --version 2>/dev/null || true)
  fi
  printf '%s' "$out" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true
}

version_gt() {
  [ -n "$1" ] || return 1
  [ -n "$2" ] || return 0
  [ "$1" = "$2" ] && return 1
  local greater
  greater=$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)
  [ "$greater" = "$1" ]
}

fetch_skill_config() {
  info "请求 skill 配置接口获取最新版本与下载地址..."

  local req_id resp
  req_id="$(date +%s)${RANDOM}"

  if ! resp=$(curl -fsSL --connect-timeout 30 --max-time 60 "${SKILL_CONFIG_URL}?req_id=${req_id}" 2>/dev/null); then
    error "请求 skill_config 接口失败: ${SKILL_CONFIG_URL}"
    return 1
  fi

  local parsed
  if ! parsed=$(node -e '
    let j;
    try { j = JSON.parse(process.argv[1]); } catch (e) { process.exit(1); }
    // 兼容多层结构：{config} / {data:{config}} / {data:{...}} / 裸对象
    const cfg = (j && j.data && j.data.config) || (j && j.config) || (j && j.data) || j || {};
    const ver = cfg.qkPanVersion || "";
    const url = cfg.qkPan || "";
    if (!url) process.exit(2);
    process.stdout.write(ver + "\n" + url);
  ' "$resp" 2>/dev/null); then
    error "解析 skill_config 接口返回失败: $resp"
    return 1
  fi

  REMOTE_VERSION=$(printf '%s' "$parsed" | sed -n '1p')
  ZIP_DOWNLOAD_URL=$(printf '%s' "$parsed" | sed -n '2p')

  if [ -z "$ZIP_DOWNLOAD_URL" ]; then
    error "skill_config 接口未返回有效的 zip 下载地址"
    return 1
  fi

  info "接口版本: ${REMOTE_VERSION:-未知}"
  info "下载地址: $ZIP_DOWNLOAD_URL"
}


download_and_extract() {
  info "Step 3: 下载 skill zip 包..."

  mkdir -p "$TMP_DIR"
  local zip_path="$TMP_DIR/skill.zip"

  if ! curl -fsSL --connect-timeout 30 --max-time 120 -o "$zip_path" "$ZIP_DOWNLOAD_URL"; then
    warn "下载失败，重试中..."
    if ! curl -fsSL --connect-timeout 30 --max-time 120 -o "$zip_path" "$ZIP_DOWNLOAD_URL"; then
      error "下载 zip 包失败: $ZIP_DOWNLOAD_URL"
      return 1
    fi
  fi

  info "下载完成，正在解压..."
  unzip -qo "$zip_path" -d "$TMP_DIR"
  info "解压完成"
}


install_scripts() {
  info "Step 4: 安装脚本到 ${INSTALL_DIR}..."

  local scripts_src
  scripts_src=$(find "$TMP_DIR" -type d -name "scripts" | head -1)

  if [ -z "$scripts_src" ]; then
    error "zip 包中未找到 scripts 目录"
    return 1
  fi

  mkdir -p "$INSTALL_DIR"

  local scripts_dest="$INSTALL_DIR/scripts"
  local installed_count=0
  local skipped_count=0

  if [ "$IS_UPDATE" = "true" ]; then
    info "更新模式: 整个覆盖 scripts 目录，跳过 quarkclouddrive 入口文件"
    rm -rf "$scripts_dest"
    cp -rf "$scripts_src" "$scripts_dest"
    for file in "$scripts_dest"/*; do
      local filename
      filename=$(basename "$file")
      info "  [更新]  scripts/$filename → $scripts_dest/$filename"
      installed_count=$((installed_count + 1))
    done
    info "  [跳过]  quarkclouddrive (入口文件，更新模式下不覆盖)"
    skipped_count=1
  else
    cp -rf "$scripts_src" "$scripts_dest"
    for file in "$scripts_dest"/*; do
      local filename
      filename=$(basename "$file")
      info "  [安装]  scripts/$filename → $scripts_dest/$filename"
      installed_count=$((installed_count + 1))
    done

    if [ -f "$scripts_src/quarkclouddrive" ]; then
      cp -f "$scripts_src/quarkclouddrive" "$INSTALL_DIR/quarkclouddrive"
      chmod +x "$INSTALL_DIR/quarkclouddrive"
      info "  [安装]  quarkclouddrive → $INSTALL_DIR/quarkclouddrive"
      installed_count=$((installed_count + 1))
    fi
  fi

  echo ""
  info "安装目录: $INSTALL_DIR"
  info "文件统计: 已安装 ${installed_count} 个文件，跳过 ${skipped_count} 个文件"
}


install_skill_docs() {
  info "Step 4.5: 更新 SKILL.md 和 references 文档..."

  local skill_md_src
  skill_md_src=$(find "$TMP_DIR" -maxdepth 2 -name "SKILL.md" -type f | head -1)

  if [ -n "$skill_md_src" ]; then
    cp -f "$skill_md_src" "$SKILL_DIR/SKILL.md"
    info "  [更新]  SKILL.md → $SKILL_DIR/SKILL.md"
  else
    warn "  zip 包中未找到 SKILL.md，跳过"
  fi

  local refs_src
  refs_src=$(find "$TMP_DIR" -maxdepth 2 -type d -name "references" | head -1)

  if [ -n "$refs_src" ]; then
    rm -rf "$SKILL_DIR/references"
    cp -rf "$refs_src" "$SKILL_DIR/references"
    local ref_count
    ref_count=$(find "$SKILL_DIR/references" -type f | wc -l | tr -d ' ')
    info "  [更新]  references/ → $SKILL_DIR/references/ (${ref_count} 个文件)"
  else
    warn "  zip 包中未找到 references 目录，跳过"
  fi

  local install_script_src
  local uninstall_script_src
  install_script_src=$(find "$TMP_DIR" -maxdepth 2 -name "install.sh" -type f | head -1)
  uninstall_script_src=$(find "$TMP_DIR" -maxdepth 2 -name "uninstall.sh" -type f | head -1)

  if [ -n "$install_script_src" ]; then
    cp -f "$install_script_src" "$INSTALL_DIR/install.sh"
    chmod +x "$INSTALL_DIR/install.sh"
    info "  [更新]  install.sh → $INSTALL_DIR/install.sh"
    if [ "$SKILL_DIR" != "$INSTALL_DIR" ]; then
      rm -f "$SKILL_DIR/install.sh"
      cp -f "$install_script_src" "$SKILL_DIR/install.sh"
      chmod +x "$SKILL_DIR/install.sh"
      info "  [更新]  install.sh → $SKILL_DIR/install.sh"
    fi
  else
    warn "  zip 包中未找到 install.sh，跳过"
  fi

  if [ -n "$uninstall_script_src" ]; then
    cp -f "$uninstall_script_src" "$INSTALL_DIR/uninstall.sh"
    chmod +x "$INSTALL_DIR/uninstall.sh"
    info "  [更新]  uninstall.sh → $INSTALL_DIR/uninstall.sh"
    if [ "$SKILL_DIR" != "$INSTALL_DIR" ]; then
      cp -f "$uninstall_script_src" "$SKILL_DIR/uninstall.sh"
      chmod +x "$SKILL_DIR/uninstall.sh"
      info "  [更新]  uninstall.sh → $SKILL_DIR/uninstall.sh"
    fi
  else
    warn "  zip 包中未找到 uninstall.sh，跳过"
  fi

  local skill_scripts_src
  skill_scripts_src=$(find "$TMP_DIR" -type d -name "scripts" | head -1)
  if [ -n "$skill_scripts_src" ]; then
    rm -rf "$SKILL_DIR/scripts"
    cp -rf "$skill_scripts_src" "$SKILL_DIR/scripts"
    local skill_script_count
    skill_script_count=$(find "$SKILL_DIR/scripts" -type f | wc -l | tr -d ' ')
    info "  [更新]  scripts/ → $SKILL_DIR/scripts/ (${skill_script_count} 个文件)"
  else
    warn "  zip 包中未找到 scripts 目录，跳过 skill 目录同步"
  fi
}


register_command() {
  info "Step 5: 注册 quarkclouddrive 全局命令..."

  local quarkclouddrive_path="$INSTALL_DIR/quarkclouddrive"

  if [ ! -f "$quarkclouddrive_path" ]; then
    error "quarkclouddrive 文件不存在: $quarkclouddrive_path"
    return 1
  fi

  chmod +x "$quarkclouddrive_path"

  case "$OS_TYPE" in
    mac|linux)
      register_command_unix "$quarkclouddrive_path"
      ;;
    windows)
      register_command_windows "$quarkclouddrive_path"
      ;;
  esac
}

register_command_unix() {
  local quarkclouddrive_path="$1"
  local symlink_dir="/usr/local/bin"

  if [ -w "$symlink_dir" ]; then
    ln -sf "$quarkclouddrive_path" "$symlink_dir/quarkclouddrive"
    info "已创建符号链接: $symlink_dir/quarkclouddrive"
    return 0
  fi

  warn "/usr/local/bin 无写入权限，将安装目录添加到 shell 配置文件"
  add_to_path "$INSTALL_DIR"
}

register_command_windows() {
  local quarkclouddrive_path="$1"

  add_to_path "$INSTALL_DIR"

  local cmd_wrapper="$INSTALL_DIR/quarkclouddrive.cmd"
  cat > "$cmd_wrapper" << 'CMD_WRAPPER'
@echo off
set "SCRIPT_DIR=%~dp0"
node "%SCRIPT_DIR%scripts\quark-drive.cjs" %*
CMD_WRAPPER
  info "已创建 Windows CMD wrapper: $cmd_wrapper"

  local ps1_wrapper="$INSTALL_DIR/quarkclouddrive.ps1"
  cat > "$ps1_wrapper" << 'PS1_WRAPPER'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& node "$ScriptDir\scripts\quark-drive.cjs" $args
PS1_WRAPPER
  info "已创建 PowerShell wrapper: $ps1_wrapper"

  local win_install_dir
  win_install_dir=$(cygpath -w "$INSTALL_DIR" 2>/dev/null || echo "$INSTALL_DIR")

  if command -v powershell.exe &>/dev/null; then
    local current_path
    current_path=$(powershell.exe -NoProfile -Command "[Environment]::GetEnvironmentVariable('PATH', 'User')" 2>/dev/null | tr -d '\r')
    if echo "$current_path" | grep -qiF "$win_install_dir"; then
      info "Windows 用户 PATH 中已包含 $win_install_dir"
    else
      powershell.exe -NoProfile -Command "[Environment]::SetEnvironmentVariable('PATH', '$current_path;$win_install_dir', 'User')" 2>/dev/null
      info "已自动将 $win_install_dir 添加到 Windows 用户 PATH"
      warn "新打开的 CMD / PowerShell 窗口即可使用 quarkclouddrive 命令"
    fi
  else
    if command -v setx &>/dev/null; then
      local current_path_raw
      current_path_raw=$(cmd.exe //c "echo %PATH%" 2>/dev/null | tr -d '\r')
      local new_path="${current_path_raw};${win_install_dir}"
      local path_len=${#new_path}

      if [ "$path_len" -gt 1024 ]; then
        warn "当前 PATH 加上安装目录后共 ${path_len} 个字符，超过 setx 的 1024 字符限制"
        warn "无法通过 setx 自动添加，请按以下步骤手动操作："
        warn ""
        warn "  1. 按 Win + R，输入 sysdm.cpl 回车"
        warn "  2. 点击「高级」→「环境变量」"
        warn "  3. 在「用户变量」中找到 Path，点击「编辑」"
        warn "  4. 点击「新建」，添加：$win_install_dir"
        warn "  5. 点击「确定」保存，重新打开终端即可生效"
      else
        setx PATH "$new_path" >/dev/null 2>&1
        info "已通过 setx 将 $win_install_dir 添加到用户 PATH"
        warn "新打开的 CMD 窗口即可使用 quarkclouddrive 命令"
      fi
    else
      warn "未检测到 powershell.exe 或 setx，请按以下步骤手动操作："
      warn ""
      warn "  1. 按 Win + R，输入 sysdm.cpl 回车"
      warn "  2. 点击「高级」→「环境变量」"
      warn "  3. 在「用户变量」中找到 Path，点击「编辑」"
      warn "  4. 点击「新建」，添加：$win_install_dir"
      warn "  5. 点击「确定」保存，重新打开终端即可生效"
    fi
  fi
}

add_to_path() {
  local target_dir="$1"
  local shell_rc=""
  local current_shell
  current_shell=$(basename "${SHELL:-/bin/bash}")

  case "$current_shell" in
    zsh)  shell_rc="$HOME/.zshrc" ;;
    bash) shell_rc="$HOME/.bash_profile" ;;
    *)    shell_rc="$HOME/.profile" ;;
  esac

  local path_entry="export PATH=\"$target_dir:\$PATH\""

  if grep -qF "$target_dir" "$shell_rc" 2>/dev/null; then
    info "PATH 中已包含 $target_dir，无需重复添加"
  else
    printf '\n# quarkclouddrive CLI\n%s\n' "$path_entry" >> "$shell_rc"
    info "已将 $target_dir 添加到 $shell_rc"
  fi

  export PATH="$target_dir:$PATH"
}


verify_installation() {
  info "Step 6: 自检验证..."

  local quarkclouddrive_path="$INSTALL_DIR/quarkclouddrive"

  if [ ! -f "$quarkclouddrive_path" ]; then
    error "quarkclouddrive 不存在: $quarkclouddrive_path"
    return 1
  fi

  local version_output
  if version_output=$("$quarkclouddrive_path" --version 2>&1); then
    info "quarkclouddrive 安装成功，版本: $version_output"
    return 0
  fi

  error "quarkclouddrive --version 执行失败: $version_output"
  return 1
}


cleanup() {
  if [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
  fi
}


print_result() {
  local success="$1"
  local divider
  divider=$(printf '%0.s─' {1..50})

  printf '\n%s\n' "$divider"

  if [ "$success" = "true" ]; then
    if [ "$IS_UPDATE" = "true" ]; then
      printf "✅ quarkclouddrive CLI 更新完成\n\n"
    else
      printf "✅ quarkclouddrive CLI 安装完成\n\n"
    fi
    printf "  安装目录:  %s\n" "$INSTALL_DIR"
    printf "  全局命令:  quarkclouddrive\n"
    printf "  Node.js:   %s\n" "$(node --version 2>/dev/null || echo '未知')"
    printf "  入口脚本:  %s\n\n" "$INSTALL_DIR/quarkclouddrive"

    printf "  已安装的文件:\n"
    for file in "$INSTALL_DIR"/*; do
      if [ -f "$file" ]; then
        local fname fsize
        fname=$(basename "$file")
        fsize=$(wc -c < "$file" 2>/dev/null | tr -d ' ')
        if [ -x "$file" ]; then
          printf "    %-30s %6s bytes  [可执行]\n" "$fname" "$fsize"
        else
          printf "    %-30s %6s bytes\n" "$fname" "$fsize"
        fi
      fi
    done
    printf "\n"

    if [ "$IS_UPDATE" = "true" ]; then
      printf "  更新说明:\n"
      printf "    • 脚本文件已覆盖更新到最新版本\n"
      printf "    • SKILL.md 和 references 文档已同步更新\n"
    fi

    printf "  运行 quarkclouddrive --help 开始使用\n"
  else
    if [ "$IS_UPDATE" = "true" ]; then
      printf "❌ quarkclouddrive CLI 更新失败\n\n"
    else
      printf "❌ quarkclouddrive CLI 安装失败\n\n"
    fi
    printf "  请检查以上错误信息并重试\n"
    printf "  手动安装 Node.js v${REQUIRED_NODE_MAJOR}+: https://nodejs.org/\n"
  fi

  printf '%s\n\n' "$divider"
}


main() {
  if [ "$IS_UPDATE" = "true" ]; then
    info "=== quarkclouddrive CLI 更新脚本 ==="
  else
    info "=== quarkclouddrive CLI 安装脚本 ==="
  fi
  echo ""

  trap cleanup EXIT

  if ! detect_os; then
    print_result "false"
    exit 1
  fi

  if ! ensure_node; then
    error "Node.js 环境安装失败"
    print_result "false"
    exit 1
  fi

  if [ "$IS_UPDATE" = "true" ]; then
    info "反查安装目录..."
    if ! resolve_install_dir; then
      print_result "false"
      exit 1
    fi
    info "安装目录: $INSTALL_DIR"
  fi

  if ! fetch_skill_config; then
    print_result "false"
    exit 1
  fi

  if [ "$IS_UPDATE" = "true" ]; then
    local local_version
    local_version=$(get_local_version)
    info "本地版本: ${local_version:-未知}，远端版本: ${REMOTE_VERSION:-未知}"

    if ! version_gt "$REMOTE_VERSION" "$local_version"; then
      info "当前已是最新版本（本地 ${local_version:-未知} >= 远端 ${REMOTE_VERSION:-未知}），无需更新"
      print_result "true"
      exit 0
    fi
    info "检测到新版本，开始更新..."
  fi

  if ! download_and_extract; then
    print_result "false"
    exit 1
  fi

  if ! install_scripts; then
    print_result "false"
    exit 1
  fi

  if ! install_skill_docs; then
    warn "SKILL.md / references 更新失败，但不影响 CLI 使用"
  fi

  if [ "$IS_UPDATE" = "false" ]; then
    if ! register_command; then
      print_result "false"
      exit 1
    fi
  else
    info "Step 5: 跳过命令注册（更新模式）"
  fi

  if ! verify_installation; then
    print_result "false"
    exit 1
  fi

  print_result "true"
}

main "$@"

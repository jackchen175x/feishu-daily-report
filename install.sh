#!/bin/bash
# 飞书工作日报半自动化 · 一键安装脚本
# 用法：bash install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATES="$SCRIPT_DIR/templates"

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

say() { echo -e "${BLUE}▸${NC} $1"; }
ok()  { echo -e "${GREEN}✓${NC} $1"; }
warn(){ echo -e "${YELLOW}⚠${NC} $1"; }
err() { echo -e "${RED}✗${NC} $1" >&2; }

trap 'err "安装中断（第 $LINENO 行）。已完成的文件仍在原位，可重新跑 install.sh"; exit 1' ERR

echo
echo "╔══════════════════════════════════════════════╗"
echo "║  飞书工作日报半自动化 · 一键安装                ║"
echo "╚══════════════════════════════════════════════╝"
echo

# -------- Step 1：依赖检查 --------
say "Step 1/7  依赖检查"

need() {
    if ! command -v "$1" >/dev/null 2>&1; then
        err "缺少 $1 —— $2"
        exit 1
    fi
    ok "$1 已安装 ($(command -v $1))"
}

need claude   "请先安装 Claude Code：https://claude.com/claude-code"
need lark-cli "请运行：npm install -g @larksuiteoapi/lark-cli"
need jq       "请运行：brew install jq"
need perl     "macOS 自带，未找到？"

if ! command -v envsubst >/dev/null 2>&1; then
    warn "envsubst 未安装（需要 gettext）"
    read -rp "是否现在 brew install gettext？[Y/n] " yn
    if [[ "$yn" =~ ^[Nn] ]]; then
        err "envsubst 是必需的，退出"
        exit 1
    fi
    brew install gettext
    # macOS brew 把 gettext keg-only，envsubst 不会自动进 PATH
    BREW_PREFIX=$(brew --prefix)
    export PATH="$BREW_PREFIX/opt/gettext/bin:$PATH"
fi
ok "envsubst 已就位"

# 找 lark-cli / node 所在的 bin 目录（用于 plist PATH）
LARK_CLI_PATH=$(command -v lark-cli)
NODE_BIN_PATH=$(dirname "$LARK_CLI_PATH")
ok "Node bin 路径：$NODE_BIN_PATH（plist PATH 会写这个）"

# -------- Step 2：claude-mem plugin 检查 --------
echo
say "Step 2/7  claude-mem plugin 检查"
if claude mcp list 2>&1 | grep -q "claude-mem.*Connected"; then
    ok "claude-mem MCP 已连接"
else
    warn "claude-mem plugin 未装或未启用"
    read -rp "是否现在装（GitHub: thedotmack/claude-mem）？[Y/n] " yn
    if [[ ! "$yn" =~ ^[Nn] ]]; then
        claude plugin marketplace add thedotmack/claude-mem 2>&1 | tail -3 || true
        claude plugin install claude-mem@thedotmack 2>&1 | tail -3
        ok "claude-mem 已装，首次调用前可能需要重启 Claude Code"
    else
        warn "跳过 —— 没 claude-mem 主日报会缺数据源，但仍能发兜底版"
    fi
fi

# -------- Step 3：飞书登录 --------
echo
say "Step 3/7  飞书登录检查"
OPEN_ID=""
if lark-cli auth list 2>/dev/null | jq -e '.[0].userOpenId' >/dev/null 2>&1; then
    OPEN_ID=$(lark-cli auth list | jq -r '.[0].userOpenId')
    ok "已登录飞书，open_id = $OPEN_ID"
else
    warn "lark-cli 未登录飞书"
    echo "  即将运行：lark-cli auth login --domain all"
    echo "  扫码授权后回车继续..."
    read -r
    lark-cli auth login --domain all
    OPEN_ID=$(lark-cli auth list | jq -r '.[0].userOpenId')
    ok "登录成功，open_id = $OPEN_ID"
fi

# -------- Step 4：测试 bot 私聊 --------
echo
say "Step 4/7  测试 bot 能否发飞书私聊"
TEST_RESULT=$(lark-cli im +messages-send --user-id "$OPEN_ID" --text "🧪 日报自动化安装测试 · $(date '+%H:%M:%S')" 2>&1 | jq -r '.ok // "false"')
if [ "$TEST_RESULT" = "true" ]; then
    ok "测试消息已送达飞书，请到私聊确认收到"
else
    err "测试消息发送失败 —— 检查 lark-cli auth 是否正确"
    exit 1
fi

# -------- Step 5：交互配置 --------
echo
say "Step 5/7  配置推送时间 / 用户名 / 截止时间"

default_name=$(whoami)
read -rp "你的名字（会出现在 prompt 里，默认 $default_name）: " USER_NAME
USER_NAME="${USER_NAME:-$default_name}"

read -rp "每天几点推送日报？小时 [0-23，默认 18]: " PUSH_HOUR
PUSH_HOUR="${PUSH_HOUR:-18}"

read -rp "几分？[0-59，默认 20]: " PUSH_MINUTE
PUSH_MINUTE="${PUSH_MINUTE:-20}"

read -rp "公司日报截止提示语（默认：今晚提交即可，公司截止明早 9:00）: " DEADLINE_HINT
DEADLINE_HINT="${DEADLINE_HINT:-今晚提交即可，公司截止明早 9:00}"

echo
echo "  现在需要你填"公司项目清单"和"副业/个人项目清单"。"
echo "  每行一条（例如：长卿 AI 微信小程序、公司核心产品 XXX），输入完空行回车结束。"
echo "  这两个清单决定日报只写哪些事。"
echo

echo "▸ 公司项目清单（哪些是要写进日报的公司业务？）"
COMPANY_PROJECTS=""
while IFS= read -rp "  公司项目: " line; do
    [ -z "$line" ] && break
    COMPANY_PROJECTS+="- $line"$'\n'
done
COMPANY_PROJECTS="${COMPANY_PROJECTS:-- <请手动编辑 prompt 文件填写>}"

echo
echo "▸ 副业 / 个人项目清单（哪些不进日报？）"
PERSONAL_PROJECTS=""
while IFS= read -rp "  个人项目: " line; do
    [ -z "$line" ] && break
    PERSONAL_PROJECTS+="- $line"$'\n'
done
PERSONAL_PROJECTS="${PERSONAL_PROJECTS:-- <无>}"

# -------- Step 6：生成文件 --------
echo
say "Step 6/7  生成配置文件并部署"

export USER_NAME USER_OPEN_ID="$OPEN_ID" PUSH_HOUR PUSH_MINUTE DEADLINE_HINT
export COMPANY_PROJECTS PERSONAL_PROJECTS NODE_BIN_PATH WHOAMI=$(whoami)

mkdir -p ~/.local/bin ~/Library/LaunchAgents ~/.claude/commands ~/Library/Logs/work-report ~/.local/state/work-report

envsubst < "$TEMPLATES/work-report.template"              > ~/.local/bin/work-report
envsubst < "$TEMPLATES/work-report.prompt.template.md"    > ~/.local/bin/work-report.prompt.md
envsubst < "$TEMPLATES/work-report.config.template.env"   > ~/.local/bin/work-report.config.env
envsubst < "$TEMPLATES/com.workreport.template.plist"     > ~/Library/LaunchAgents/com.workreport.daily.plist
envsubst < "$TEMPLATES/report-fragment.template.md"       > ~/.claude/commands/report-fragment.md

chmod 755 ~/.local/bin/work-report
chmod 600 ~/.local/bin/work-report.config.env
chmod 644 ~/.local/bin/work-report.prompt.md ~/Library/LaunchAgents/com.workreport.daily.plist ~/.claude/commands/report-fragment.md

if plutil -lint ~/Library/LaunchAgents/com.workreport.daily.plist >/dev/null 2>&1; then
    ok "plist 合法"
else
    err "plist 非法，检查 templates/com.workreport.template.plist"
    exit 1
fi

# 注册 launchd
launchctl bootout gui/$(id -u)/com.workreport.daily 2>/dev/null || true
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.workreport.daily.plist
ok "launchd 已注册，每天 ${PUSH_HOUR}:${PUSH_MINUTE} 自动触发"

# -------- Step 7：首跑验证 --------
echo
say "Step 7/7  首跑验证（可选）"
read -rp "是否现在手动触发一次做验证？会真的发 4 条消息到你飞书 [Y/n] " yn
if [[ ! "$yn" =~ ^[Nn] ]]; then
    launchctl kickstart -k gui/$(id -u)/com.workreport.daily
    say "已触发，等 2-4 分钟..."
    say "过程日志：tail -f ~/Library/Logs/work-report/\$(date +%Y-%m-%d).log"
    say "状态文件：cat ~/.local/state/work-report/\$(date +%Y-%m-%d).json"
else
    say "跳过首跑。下次自动触发时间：每天 ${PUSH_HOUR}:${PUSH_MINUTE}"
fi

echo
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✓ 安装完成                                    ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo
echo "已部署："
echo "  ~/.local/bin/work-report              （wrapper）"
echo "  ~/.local/bin/work-report.prompt.md    （主日报 prompt，可编辑调整风格/项目清单）"
echo "  ~/.local/bin/work-report.config.env   （open_id 等敏感配置，chmod 600）"
echo "  ~/Library/LaunchAgents/com.workreport.daily.plist  （定时任务）"
echo "  ~/.claude/commands/report-fragment.md （slash command，在其他会话用 /report-fragment）"
echo
echo "日常使用："
echo "  • 每天 ${PUSH_HOUR}:${PUSH_MINUTE}：launchd 自动跑，飞书收到 4 条消息"
echo "  • 白天随时：在 Claude Code 会话里 /report-fragment，补片段到飞书"
echo "  • 手动触发：launchctl kickstart -k gui/\$(id -u)/com.workreport.daily"
echo "  • 停用：bash uninstall.sh"
echo

#!/bin/bash
# 飞书工作日报半自动化 · 一键安装脚本
# 用法：
#   交互：bash install.sh
#   非交互（Claude Code 调用或 CI）：
#     WR_AUTO=1 WR_USER_NAME="张三" WR_PUSH_HOUR=18 WR_PUSH_MINUTE=20 \
#     WR_DEADLINE_HINT="今晚提交即可" \
#     WR_COMPANY_PROJECTS=$'A 项目\nB 项目' \
#     WR_PERSONAL_PROJECTS=$'个人项目 X' \
#     WR_KICKSTART=1 \
#     bash install.sh

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

trap 'err "安装中断（第 $LINENO 行）"; exit 1' ERR

# 判断交互模式：有 TTY 且未设置 WR_AUTO=1
AUTO="${WR_AUTO:-0}"
if [ "$AUTO" = "1" ] || [ ! -t 0 ]; then
    INTERACTIVE=0
else
    INTERACTIVE=1
fi

ask() {
    # ask "prompt" "default_value" → echo answer
    # 非交互模式下直接回显 default
    local prompt="$1" default="${2:-}"
    if [ "$INTERACTIVE" = "0" ]; then
        echo "$default"
        return
    fi
    local ans
    read -rp "$prompt" ans
    echo "${ans:-$default}"
}

ask_yn() {
    # ask_yn "prompt" → 返回 0=yes 1=no；非交互默认 yes
    if [ "$INTERACTIVE" = "0" ]; then
        return 0
    fi
    local ans
    read -rp "$1 [Y/n] " ans
    [[ ! "$ans" =~ ^[Nn] ]]
}

echo
echo "╔══════════════════════════════════════════════╗"
echo "║  飞书工作日报半自动化 · 一键安装                ║"
echo "╚══════════════════════════════════════════════╝"
[ "$INTERACTIVE" = "0" ] && echo "（非交互模式）"
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
    if ask_yn "是否现在 brew install gettext？"; then
        brew install gettext
        BREW_PREFIX=$(brew --prefix)
        export PATH="$BREW_PREFIX/opt/gettext/bin:$PATH"
    else
        err "envsubst 是必需的，退出"
        exit 1
    fi
fi
ok "envsubst 已就位"

LARK_CLI_PATH=$(command -v lark-cli)
NODE_BIN_PATH=$(dirname "$LARK_CLI_PATH")
ok "Node bin 路径：$NODE_BIN_PATH"

# -------- Step 2：claude-mem plugin --------
echo
say "Step 2/7  claude-mem plugin 检查"
if claude mcp list 2>&1 | grep -q "claude-mem.*Connected"; then
    ok "claude-mem MCP 已连接"
else
    warn "claude-mem plugin 未装"
    if ask_yn "是否现在装（thedotmack/claude-mem）？"; then
        claude plugin marketplace add thedotmack/claude-mem 2>&1 | tail -3 || true
        claude plugin install claude-mem@thedotmack 2>&1 | tail -3
        ok "claude-mem 已装"
    else
        warn "跳过 —— 没 claude-mem 主日报会缺数据源"
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
    if [ "$INTERACTIVE" = "0" ]; then
        err "lark-cli 未登录飞书。请先手动运行：lark-cli auth login --domain all"
        err "登录后重新跑本脚本"
        exit 1
    fi
    warn "lark-cli 未登录，即将运行：lark-cli auth login --domain all"
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
    ok "测试消息已送达飞书"
else
    err "测试消息发送失败 —— 检查 lark-cli auth 是否正确"
    exit 1
fi

# -------- Step 5：收集配置 --------
echo
say "Step 5/7  收集配置"

default_name=$(whoami)
USER_NAME="${WR_USER_NAME:-$(ask "你的名字（出现在 prompt 里，默认 $default_name）: " "$default_name")}"
PUSH_HOUR="${WR_PUSH_HOUR:-$(ask "每天几点推送？小时 [0-23，默认 18]: " "18")}"
PUSH_MINUTE="${WR_PUSH_MINUTE:-$(ask "几分？[0-59，默认 20]: " "20")}"
DEADLINE_HINT="${WR_DEADLINE_HINT:-$(ask "截止提示语（默认：今晚提交即可，公司截止明早 9:00）: " "今晚提交即可，公司截止明早 9:00")}"

# 项目清单
if [ -n "${WR_COMPANY_PROJECTS:-}" ]; then
    COMPANY_PROJECTS=$(echo "$WR_COMPANY_PROJECTS" | sed 's/^/- /')
    ok "公司项目清单（来自 WR_COMPANY_PROJECTS）"
    echo "$COMPANY_PROJECTS" | sed 's/^/    /'
elif [ "$INTERACTIVE" = "1" ]; then
    echo
    echo "  公司项目清单（每行一条，空行结束）："
    COMPANY_PROJECTS=""
    while IFS= read -rp "  公司项目: " line; do
        [ -z "$line" ] && break
        COMPANY_PROJECTS+="- $line"$'\n'
    done
    [ -z "$COMPANY_PROJECTS" ] && COMPANY_PROJECTS="- <请编辑 ~/.local/bin/work-report.prompt.md 填写>"
else
    warn "未提供 WR_COMPANY_PROJECTS，清单为空（安装后请手动编辑 ~/.local/bin/work-report.prompt.md）"
    COMPANY_PROJECTS="- <请编辑本文件填写公司项目>"
fi

if [ -n "${WR_PERSONAL_PROJECTS:-}" ]; then
    PERSONAL_PROJECTS=$(echo "$WR_PERSONAL_PROJECTS" | sed 's/^/- /')
    ok "副业项目清单（来自 WR_PERSONAL_PROJECTS）"
    echo "$PERSONAL_PROJECTS" | sed 's/^/    /'
elif [ "$INTERACTIVE" = "1" ]; then
    echo
    echo "  副业 / 个人项目清单（每行一条，空行结束）："
    PERSONAL_PROJECTS=""
    while IFS= read -rp "  个人项目: " line; do
        [ -z "$line" ] && break
        PERSONAL_PROJECTS+="- $line"$'\n'
    done
    [ -z "$PERSONAL_PROJECTS" ] && PERSONAL_PROJECTS="- <无>"
else
    PERSONAL_PROJECTS="- <无>"
fi

# -------- Step 6：生成 + 部署 --------
echo
say "Step 6/7  生成配置文件并部署"

export USER_NAME USER_OPEN_ID="$OPEN_ID" PUSH_HOUR PUSH_MINUTE DEADLINE_HINT
export COMPANY_PROJECTS PERSONAL_PROJECTS NODE_BIN_PATH WHOAMI=$(whoami)

mkdir -p ~/.local/bin ~/Library/LaunchAgents ~/.claude/commands ~/Library/Logs/work-report ~/.local/state/work-report

envsubst < "$TEMPLATES/work-report.template"                  > ~/.local/bin/work-report
envsubst < "$TEMPLATES/work-report.prompt.template.md"        > ~/.local/bin/work-report.prompt.md
envsubst < "$TEMPLATES/work-report.config.template.env"       > ~/.local/bin/work-report.config.env
cp       "$TEMPLATES/work-report-collect-transcripts.template"  ~/.local/bin/work-report-collect-transcripts
envsubst < "$TEMPLATES/com.workreport.template.plist"         > ~/Library/LaunchAgents/com.workreport.daily.plist
envsubst < "$TEMPLATES/report-fragment.template.md"           > ~/.claude/commands/report-fragment.md

chmod 755 ~/.local/bin/work-report ~/.local/bin/work-report-collect-transcripts
chmod 600 ~/.local/bin/work-report.config.env
chmod 644 ~/.local/bin/work-report.prompt.md ~/Library/LaunchAgents/com.workreport.daily.plist ~/.claude/commands/report-fragment.md

if plutil -lint ~/Library/LaunchAgents/com.workreport.daily.plist >/dev/null 2>&1; then
    ok "plist 合法"
else
    err "plist 非法"
    exit 1
fi

launchctl bootout gui/$(id -u)/com.workreport.daily 2>/dev/null || true
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.workreport.daily.plist
ok "launchd 已注册，每天 ${PUSH_HOUR}:${PUSH_MINUTE} 自动触发"

# -------- Step 7：首跑 --------
echo
say "Step 7/7  首跑验证"
DO_KICKSTART="${WR_KICKSTART:-}"
if [ -z "$DO_KICKSTART" ]; then
    if ask_yn "是否现在手动触发一次？会真发 4 条消息到你飞书"; then
        DO_KICKSTART=1
    else
        DO_KICKSTART=0
    fi
fi

if [ "$DO_KICKSTART" = "1" ]; then
    launchctl kickstart -k gui/$(id -u)/com.workreport.daily
    say "已触发（通常 2-4 分钟）"
    say "日志：tail -f ~/Library/Logs/work-report/\$(date +%Y-%m-%d).log"
    say "状态：cat ~/.local/state/work-report/\$(date +%Y-%m-%d).json"
else
    say "跳过首跑。下次自动触发：每天 ${PUSH_HOUR}:${PUSH_MINUTE}"
fi

echo
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✓ 安装完成                                    ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo
echo "已部署："
echo "  ~/.local/bin/work-report"
echo "  ~/.local/bin/work-report.prompt.md      （可编辑调风格/清单）"
echo "  ~/.local/bin/work-report.config.env     （chmod 600）"
echo "  ~/Library/LaunchAgents/com.workreport.daily.plist"
echo "  ~/.claude/commands/report-fragment.md"
echo

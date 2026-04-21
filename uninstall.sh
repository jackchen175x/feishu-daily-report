#!/bin/bash
# 飞书工作日报半自动化 · 卸载
set -euo pipefail

echo "卸载飞书工作日报半自动化..."
launchctl bootout gui/$(id -u)/com.workreport.daily 2>/dev/null && echo "✓ launchd 已停用" || echo "(launchd 未运行)"

read -rp "是否删除所有文件（wrapper/prompt/config/plist/slash command）？[y/N] " yn
if [[ "$yn" =~ ^[Yy] ]]; then
    rm -f ~/.local/bin/work-report \
          ~/.local/bin/work-report.prompt.md \
          ~/.local/bin/work-report.config.env \
          ~/Library/LaunchAgents/com.workreport.daily.plist \
          ~/.claude/commands/report-fragment.md
    echo "✓ 文件已删除"
    echo "(日志和 state 仍在 ~/Library/Logs/work-report/ 和 ~/.local/state/work-report/，如需可手动删)"
else
    echo "只停用了 launchd，文件保留。下次想重新启用跑："
    echo "  launchctl bootstrap gui/\$(id -u) ~/Library/LaunchAgents/com.workreport.daily.plist"
fi

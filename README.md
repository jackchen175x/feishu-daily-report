# 飞书工作日报半自动化

每天到点自动把你在 Claude Code 里干的事整理成三段日报，推送到你自己飞书私聊，复制粘贴就能提交。

**适合**：公司用飞书"汇报·工作日报"的、经常忘写日报的、每天用 Claude Code 的。

## 它是怎么工作的

```
launchd (每天到点触发)
  → ~/.local/bin/work-report
      → claude headless
          ① 查 claude-mem 今日 observations
          ② 按"公司项目清单"过滤（副业/自用的全部丢掉）
          ③ 口语化合成"今日完成 / 成果 / 明日计划"三段
          ④ 通过 lark-cli bot 私聊推送 4 条到你飞书
      → 你在飞书看到消息，复制粘贴到公司日报表单，提交
```

**外加一个 `/report-fragment` slash command**：在其他 Claude Code 会话里随手打，把那个项目今天的进度补一条片段到飞书，跟主日报拼起来用。

## 前置条件

- macOS（launchd 依赖）
- [Claude Code](https://claude.com/claude-code) 已安装并登录
- Node.js（任意版本）
- 飞书账号（能收私聊就行）
- 公司日报是**飞书"汇报"产品**（不是审批）。飞书汇报没有官方提交 API，所以走"推送 → 人工复制粘贴"的半自动路径 —— 纯自动目前做不到，别折腾

## 安装

```bash
git clone <这个仓库> feishu-daily-report
cd feishu-daily-report
bash install.sh
```

安装脚本会引导你：

1. 检查依赖（claude / lark-cli / jq / envsubst / perl）缺啥提示怎么装
2. 装 claude-mem plugin（没装的话）
3. 引导 `lark-cli auth login` 扫码登录飞书
4. 自动拿你的 open_id
5. 发一条测试消息到飞书验证打通
6. 交互问你：推送时间、用户名、截止时间提示语、公司项目清单、副业项目清单
7. 生成配置、注册 launchd
8. 可选：立刻手动触发一次做首跑验证

**全程 3-5 分钟**。

## 卸载

```bash
bash uninstall.sh
```

## 使用

### 日常（自动）
- 每天到点（默认 18:20）launchd 自动触发，飞书收到 4 条消息：
  1. 【今日完成工作 · YYYY-MM-DD】
  2. 【今日工作成果 / 数据 · YYYY-MM-DD】
  3. 【明日计划工作 · YYYY-MM-DD】
  4. ✅ 操作指引（复制粘贴提交）

### 补片段（手动）
- 你在别的 Claude Code 会话里工作时（比如正在改公司 A 项目），打：
  ```
  /report-fragment
  ```
- 那个会话会回顾它今天的对话 + git log → 如果项目在"公司清单"里就自动推一条片段消息给飞书 → 晚上主日报到时把片段内容合并进去再提交

### 手动重触发主日报
```bash
launchctl kickstart -k gui/$(id -u)/com.workreport.daily
```

## 调整 / 定制

所有配置在 `~/.local/bin/` 下：

| 文件 | 改什么 |
|---|---|
| `work-report.prompt.md` | 主日报风格、公司项目清单、价值过滤规则 |
| `work-report.config.env` | open_id（换飞书账号时改） |
| `~/Library/LaunchAgents/com.workreport.daily.plist` | 定时时间（改完要 `launchctl bootout + bootstrap`） |
| `~/.claude/commands/report-fragment.md` | 片段 slash command 的规则 |

## 观测 / 排障

```bash
# 今日运行日志
tail -60 ~/Library/Logs/work-report/$(date +%Y-%m-%d).log

# 今日状态（ok:true 表示推送成功）
cat ~/.local/state/work-report/$(date +%Y-%m-%d).json

# Claude headless 原始 stdout（排障用）
cat ~/.local/state/work-report/$(date +%Y-%m-%d).raw

# launchd 状态
launchctl print gui/$(id -u)/com.workreport.daily | grep -E "state|runs|last exit"
```

## 已知坑（踩过的别再踩）

1. **macOS 没有 GNU `timeout`** —— wrapper 用 `perl -e 'alarm 600; exec @ARGV'` 替代
2. **launchd 里 `~` 和 `$HOME` 不展开** —— plist 全用绝对路径
3. **lark-cli 装在 nvm 下时 PATH 要补 nvm bin** —— install.sh 自动检测
4. **飞书汇报没有提交 API** —— 所以必须半自动，别试图改成全自动
5. **claude-mem 当日无数据是正常的** —— prompt 有兜底逻辑

## 风险与边界

- 日报内容是 Claude 生成的，**提交前务必扫一眼**（错字 / 不该写的 / 措辞不对）
- 公司清单和副业清单决定了什么进日报、什么丢掉 —— 配不准会漏报或错报
- 敏感信息（open_id）在 `work-report.config.env`，chmod 600，**不要提交到 git**

## 许可

MIT

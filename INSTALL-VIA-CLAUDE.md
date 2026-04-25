# 通过 Claude Code 一键安装

把下面整段**原文**复制，粘贴到你本机的 Claude Code 对话框，回车。Claude 会全程引导你装好。

---

```
请帮我在本机装这个工具：https://github.com/jackchen175x/feishu-daily-report

它的作用：每天到点自动把我在 Claude Code 里干过的事 + 当天飞书会议妙记，整理成日报，推到我自己飞书私聊，复制粘贴就能交。

**请按这个流程执行：**

## Step 1：先问我这些配置（一次性都问完，等我回答）

1. 你的名字（会出现在 prompt 里）
2. 每天几点推送日报（小时:分钟，例如 18:20）
3. 公司日报截止提示语（例如"今晚提交即可，公司截止明早 9:00"）
4. 公司项目清单（要进日报的业务项目，每行一条）
5. 副业 / 个人项目清单（不要进日报的，每行一条）

## Step 2：检查依赖

```bash
which claude lark-cli jq envsubst perl node npm
```

缺啥告诉我怎么装：
- claude 没装 → 终止，让我先装 Claude Code
- lark-cli → `npm install -g @larksuiteoapi/lark-cli`
- jq → `brew install jq`
- envsubst → `brew install gettext`
- node/npm → `brew install node`（妙记抓取要用）

## Step 3：检查飞书登录

```bash
lark-cli auth list 2>/dev/null | jq -r '.[0].userOpenId'
```
- 返回 `ou_xxx` → OK
- 报错或空 → **停下告诉我**：需要先扫码登录，运行 `lark-cli auth login --domain all`，扫完再继续

## Step 4：克隆仓库

```bash
git clone https://github.com/jackchen175x/feishu-daily-report.git ~/Projects/feishu-daily-report 2>/dev/null || (cd ~/Projects/feishu-daily-report && git pull)
```

## Step 5：非交互模式跑 install.sh

把 Step 1 的配置转成环境变量调用：

```bash
cd ~/Projects/feishu-daily-report
WR_AUTO=1 \
WR_USER_NAME="<我的名字>" \
WR_PUSH_HOUR=<小时> \
WR_PUSH_MINUTE=<分钟> \
WR_DEADLINE_HINT="<截止提示语>" \
WR_COMPANY_PROJECTS=$'<公司项目1>\n<公司项目2>\n<公司项目3>' \
WR_PERSONAL_PROJECTS=$'<副业项目1>\n<副业项目2>' \
WR_INSTALL_FETCHER=1 \
WR_KICKSTART=1 \
bash install.sh
```

注意：`$'\n'` 语法要 bash（不是 sh）。`WR_INSTALL_FETCHER=1` 让脚本自动装妙记抓取（~120MB playwright + chromium）。

## Step 6：扫码登录飞书妙记抓取（必须人工）

install.sh 装完会提示这一步。引导我做：

```bash
# 启动一次性登录窗口（playwright 自带 chromium 弹出）
cd ~/.local/share/feishu-minutes-fetcher && nohup node fetch.js login > /tmp/feishu-login.log 2>&1 & disown
```

**告诉我**：
> Chromium 已弹出，请用飞书 App 扫码登录飞书首页（看到飞书首页就行）。完成后告诉我"扫完了"。

我说扫完了之后：

```bash
pkill -f "fetch.js login"
sleep 2
# 验证登录态持久化
ls -lh ~/.local/share/feishu-minutes-fetcher/profile/Default/Cookies 2>/dev/null && echo "✓ 飞书登录态已保存"
```

## Step 7：等首跑完成 + 验证

WR_KICKSTART=1 让安装脚本自动触发了一次首跑。等 2-4 分钟：

```bash
tail -30 ~/Library/Logs/work-report/$(date +%Y-%m-%d).log
cat ~/.local/state/work-report/$(date +%Y-%m-%d).json
```

state 文件 `ok:true` 就是成功。告诉我飞书应该收到 2 条消息（日报正文 + 操作指引），让我去飞书确认。

## Step 8：告诉我日常用法

简要告诉我：
- 每天 <PUSH_HOUR:PUSH_MINUTE> 会自动跑，不用管
- **想让主日报自动总结某场飞书会议** → 把妙记 URL（`xxx.feishu.cn/minutes/<token>`）写到 `~/.local/state/work-report/minutes-watch-$(date +%Y-%m-%d).txt`
- 在其他 Claude Code 会话里打 `/report-fragment` 可以补片段
- 手动重触发：`launchctl kickstart -k gui/$(id -u)/com.workreport.daily`
- 编辑 prompt / 清单：`~/.local/bin/work-report.prompt.md`
- 卸载：`bash ~/Projects/feishu-daily-report/uninstall.sh`

**全程不要跳过任何 Step，不要擅自改 install.sh 的行为。如果某步失败，告诉我错误信息和排查方向，别假装成功。**
```

---

## 朋友的操作流程概览

1. 复制上面 ```...``` 包起来的整段 → 粘贴到自己 Claude Code → 回车
2. 回答 5 个问题（名字 / 时间 / 截止提示 / 公司项目 / 副业项目）
3. 中间可能要扫码登录飞书（lark-cli）
4. 装妙记抓取后**还要扫一次码**（playwright 持久化飞书登录态）
5. 装好后飞书收到测试消息
6. 之后每天到点自动推

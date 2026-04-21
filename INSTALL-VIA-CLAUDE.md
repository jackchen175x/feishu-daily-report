# 通过 Claude Code 一键安装

把下面整段**原文**复制，粘贴到你本机的 Claude Code 对话框，回车。Claude 会帮你装好。

---

```
请帮我在本机装这个工具：https://github.com/jackchen175x/feishu-daily-report

它的作用：每天到点自动把我在 Claude Code 里干过的事整理成飞书日报，推到我自己飞书私聊，复制粘贴就能交。

**请按这个流程执行（全程你主导，我回答问题即可）：**

## Step 1：先问我这些配置（一次性都问完，等我回答）

1. 你的名字（会出现在 prompt 里）
2. 每天几点推送日报（小时:分钟，例如 18:20）
3. 公司日报的截止提示语（例如"今晚提交即可，公司截止明早 9:00"）
4. 公司项目清单（要进日报的业务项目，每行一条）
5. 副业 / 个人项目清单（不要进日报的，每行一条）

## Step 2：检查依赖

跑一遍：
```bash
which claude lark-cli jq envsubst perl
```
缺啥告诉我怎么装（claude 没装就不继续；lark-cli 没装建议 `npm install -g @larksuiteoapi/lark-cli`；envsubst 没装 `brew install gettext`）。

## Step 3：检查飞书登录

```bash
lark-cli auth list 2>/dev/null | jq -r '.[0].userOpenId'
```
- 返回了 `ou_xxx`：OK，继续
- 返回空或报错：**停下来告诉我需要先跑 `lark-cli auth login --domain all` 扫码，扫完再继续**（这一步你代替不了，必须我本人扫）

## Step 4：克隆仓库

```bash
git clone https://github.com/jackchen175x/feishu-daily-report.git ~/Projects/feishu-daily-report 2>/dev/null || (cd ~/Projects/feishu-daily-report && git pull)
```

## Step 5：非交互模式跑 install.sh

把我在 Step 1 给你的配置转成环境变量调用：

```bash
cd ~/Projects/feishu-daily-report
WR_AUTO=1 \
WR_USER_NAME="<我的名字>" \
WR_PUSH_HOUR=<小时> \
WR_PUSH_MINUTE=<分钟> \
WR_DEADLINE_HINT="<截止提示语>" \
WR_COMPANY_PROJECTS=$'<公司项目1>\n<公司项目2>\n<公司项目3>' \
WR_PERSONAL_PROJECTS=$'<副业项目1>\n<副业项目2>' \
WR_KICKSTART=1 \
bash install.sh
```

注意：`$'\n'` 语法要用 bash（不是 sh）。项目清单里的换行用 `\n`。

## Step 6：等首跑完成 + 验证

跑完后等 2-4 分钟（launchd 在后台跑 claude headless），然后：

```bash
tail -30 ~/Library/Logs/work-report/$(date +%Y-%m-%d).log
cat ~/.local/state/work-report/$(date +%Y-%m-%d).json
```

state 文件 `ok:true` 就是成功。告诉我飞书应该收到 4 条消息（今日完成 / 成果 / 明日计划 / 操作指引），让我去飞书确认。

## Step 7：告诉我日常用法

简要告诉我：
- 每天 <PUSH_HOUR:PUSH_MINUTE> 会自动跑，不用管
- 在其他 Claude Code 会话里打 `/report-fragment` 可以补片段
- 手动重触发：`launchctl kickstart -k gui/$(id -u)/com.workreport.daily`
- 编辑 prompt / 清单：`~/.local/bin/work-report.prompt.md`
- 卸载：`bash ~/Projects/feishu-daily-report/uninstall.sh`

**全程不要跳过任何 Step，不要擅自改 install.sh 的行为。如果某步失败，告诉我错误信息和排查方向，别假装成功。**
```

---

## 使用说明

1. 粘贴上面 ```...``` 包起来的整段（包括 `请帮我在本机装...` 开头）到你 Claude Code 对话框
2. Claude 会先问你 5 个问题（名字 / 时间 / 截止提示 / 公司项目 / 副业项目）
3. 你回答
4. 中间如果需要扫码登录飞书，Claude 会暂停，你扫完告诉它继续
5. 装好后你会在飞书收到 4 条测试消息
6. 以后每天到点自动推

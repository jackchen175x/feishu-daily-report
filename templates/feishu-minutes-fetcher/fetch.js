#!/usr/bin/env node
// 飞书妙记内容抓取器
// 用法：
//   node fetch.js login                     # 第一次扫码登录飞书（手动）
//   node fetch.js <minute_url|minute_token> # 抓妙记内容（headless）
//
// 输出：stdout 输出 markdown：
//   # <妙记标题>
//   - 时长：...
//   - 创建：...
//   ## 智能纪要
//   <内容>

import { chromium } from 'playwright';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PROFILE_DIR = path.join(__dirname, 'profile');

const args = process.argv.slice(2);
if (args.length === 0) {
    console.error('用法：node fetch.js login | node fetch.js <minute_url|token>');
    process.exit(2);
}

const cmd = args[0];

// 解析 minute_token 或完整 URL
function resolveUrl(input) {
    if (input.startsWith('http')) return input;
    // 假定是 token，构造默认 URL（用户自己的 tenant 域名 icn2gj6bq8qn）
    return `https://icn2gj6bq8qn.feishu.cn/minutes/${input}`;
}

async function login() {
    const browser = await chromium.launchPersistentContext(PROFILE_DIR, {
        headless: false,
        viewport: { width: 1280, height: 800 },
        args: ['--no-first-run', '--no-default-browser-check'],
    });
    const page = await browser.newPage();
    await page.goto('https://www.feishu.cn/');
    console.error('▸ 在弹出的 Chromium 窗口里扫码登录飞书');
    console.error('▸ 登录成功（看到飞书首页）后，按 Ctrl+C 关掉本进程，登录态会持久化到 profile/');
    // 阻塞，等用户操作
    await new Promise(() => {});
}

async function fetchMinutes(url) {
    const browser = await chromium.launchPersistentContext(PROFILE_DIR, {
        headless: true,
        viewport: { width: 1280, height: 800 },
    });
    try {
        const page = await browser.newPage();
        await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
        // 等智能纪要区域出现
        await page.waitForSelector('[class*="summary"], [class*="ai-note"], [class*="abstract"]', { timeout: 20000 }).catch(() => {});
        await page.waitForTimeout(3000);  // 给 React 一些时间渲染

        const data = await page.evaluate(() => {
            // 标题（页面 title 即妙记标题）
            const title = document.title || '';

            // 顶部信息栏（时长、地点、时间）
            const infoBarText = document.body.innerText.split('\n').slice(0, 10).join(' ');

            // 智能纪要 — 找最大的 summary 区
            const candidates = Array.from(document.querySelectorAll('[class*="summary"], [class*="ai-note"], [class*="abstract"]'))
                .map(e => ({ len: e.innerText.length, text: e.innerText }))
                .filter(c => c.len > 100)
                .sort((a, b) => b.len - a.len);
            const summary = candidates[0]?.text || '';

            return { title, infoBarText, summary };
        });

        // 输出 markdown
        const out = [];
        out.push(`# 飞书妙记 · ${data.title}`);
        out.push('');
        out.push(`URL: ${url}`);
        out.push(`抓取时间: ${new Date().toISOString()}`);
        if (data.infoBarText) {
            out.push('');
            out.push('## 概要信息');
            out.push(data.infoBarText.slice(0, 300));
        }
        out.push('');
        out.push('## 智能纪要');
        out.push(data.summary || '(未抓到智能纪要内容 — 可能未登录或未渲染)');
        console.log(out.join('\n'));
    } finally {
        await browser.close();
    }
}

if (cmd === 'login') {
    login().catch(e => { console.error(e); process.exit(1); });
} else {
    const url = resolveUrl(cmd);
    fetchMinutes(url).catch(e => { console.error('抓取失败:', e.message); process.exit(1); });
}

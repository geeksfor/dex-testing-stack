import { defineConfig, devices } from "@playwright/test";

const isCI = !!process.env.CI;

export default defineConfig({
  testDir: "./tests",

  // CI 上建议更“保守”：更稳定、更好排查
  retries: isCI ? 1 : 0,                 // 失败自动重试一次（trace on-first-retry 才有意义）
  workers: isCI ? 2 : undefined,         // CI 控并发，避免资源争抢导致 flaky（可按你 CI 机器调）
  forbidOnly: isCI,                      // CI 禁止提交 test.only（有的话直接 fail）

  // 超时策略（可以按你项目实际调）
  timeout: 60_000,                       // 单条测试最大 60s
  expect: { timeout: 10_000 },           // expect 默认等待 10s

  // 报告：本地看 HTML，CI 用 JUnit 给平台展示（可选）
  reporter: [
    ["list"],                            // 终端输出，CI 日志友好
    ["html", { open: "never", outputFolder: "playwright-report" }],
    ["junit", { outputFile: "test-results/junit.xml" }]
  ],

  // 统一把运行产物放到 test-results 下（trace/video/screenshot 等）
  outputDir: "test-results",

  use: {
    // 失败证据三件套
    trace: "on-first-retry",             // 第一次重试时保存 trace（省资源，定位够用）
    screenshot: "only-on-failure",       // 失败才截图
    video: "retain-on-failure",          // 失败保留视频

    // 如果你跑的是本地前端，可以配 baseURL，测试里用 page.goto("/") 即可
    baseURL: process.env.BASE_URL || "http://127.0.0.1:3000",

    // CI 上更建议固定 viewport，减少渲染差异
    viewport: { width: 1280, height: 720 },

    // 某些项目需要忽略 https 自签证书（按需开启）
    // ignoreHTTPSErrors: true,
  },

  // 多项目/多浏览器（JD 常见问点：你能不能覆盖不同浏览器）
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] }
    }
    // 需要时再开：
    // { name: "firefox", use: { ...devices["Desktop Firefox"] } },
    // { name: "webkit",  use: { ...devices["Desktop Safari"] } },
  ]
});
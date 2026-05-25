# Dashboard Template Extraction Plan

## Context

`src/paperbot/dashboard.py` 当前内嵌了一个约 35KB 的 `_HTML` 字符串常量，包含完整的 HTML、CSS 和 JavaScript。这使得：
- 任何 UI 改动都需编辑 Python 文件
- 代码难以浏览和 diff
- IDE 无法为内嵌 HTML/JS/CSS 提供语法高亮

## Goal

将 `_HTML` 大字符串提取为独立的模板文件，`dashboard.py` 仅保留 HTTP 路由和处理逻辑。

## Approach

1. **Create template directory**: `src/paperbot/templates/`
2. **Extract HTML**: 将 `_HTML` 变量的内容写入 `src/paperbot/templates/dashboard.html`
   - 移除 Python 字符串引号和转义（如 `\n` → 真实换行，`\"` → `"`）
3. **Modify `dashboard.py`**:
   - 删除 `_HTML` 变量
   - 添加 `_load_template()` 函数，使用 `importlib.resources` 读取模板文件
   - 在 `do_GET` 的 `/` 路由中调用 `_load_template()` 返回 HTML
4. **Verify packaging**: hatchling 默认包含 package 目录下所有文件，模板文件会被自动打包

## Files to Modify

- **New**: `src/paperbot/templates/dashboard.html` — 提取出的完整 HTML 模板
- **Modify**: `src/paperbot/dashboard.py` — 移除 `_HTML`，改为运行时加载模板

## Verification

1. `python -c "from paperbot.dashboard import make_handler; print('OK')"` — 模块导入成功
2. `paperbot serve --daemon --port 8765` — 服务启动正常
3. 浏览器访问 `http://127.0.0.1:8765` — Dashboard 渲染正常
4. `pip install -e .` — 重新安装后模板文件仍然存在

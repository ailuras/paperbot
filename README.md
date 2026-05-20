# PaperBot

Daily paper recommendation for SMT / SAT / CP researchers.

## Project Structure

```
paperbot/
├── data/
│   └── config.json          # user-configurable tracks, scoring tiers, filters
├── src/paperbot/
│   ├── __init__.py
│   ├── cli.py               # typer CLI entry point
│   ├── config.py            # pydantic settings loader
│   ├── dashboard.py         # web dashboard (HTTP server + SPA)
│   ├── db.py                # SQLite layer (papers, recommendations, marks)
│   ├── fetch.py             # OpenAlex API fetcher
│   └── recommend.py         # recommendation engine
├── pyproject.toml
└── README.md
```

## Requirements

- Python >= 3.10
- [uv](https://docs.astral.sh/uv/)

## Install

```bash
uv pip install -e .
```

## Usage

### 推荐：`uv run`

不需要手动激活虚拟环境，直接用 `uv run`：

```bash
# 查看所有命令
uv run paperbot --help

# 查看某个命令的详细参数
uv run paperbot serve --help
uv run paperbot fetch --help
```

### 命令速查

| 命令        | 作用                   | 常用参数                          |
|-------------|------------------------|-----------------------------------|
| `fetch`     | 从 OpenAlex 抓取论文   | `--days 40` 抓取最近40天          |
| `recommend` | 生成今日推荐           | `--count 3` 推荐数量              |
| `mark`      | 标记论文状态           | `--status read`                   |
| `stats`     | 查看数据库统计         | —                                 |
| `history`   | 查看推荐历史           | `--days 7`                        |
| `serve`     | 启动 Web 看板          | `--port 8765 --daemon`            |
| `migrate`   | 从 JSON 导入论文       | `<path-to-json>`                  |

### 示例

```bash
# 抓取最近40天的论文
uv run paperbot fetch --days 40

# 生成3篇今日推荐
uv run paperbot recommend --count 3

# 启动看板（前台）
uv run paperbot serve --port 8765

# 后台启动看板
uv run paperbot serve --port 8765 --daemon

# 标记论文为已读
uv run paperbot mark "paper title" --status read

# 查看统计
uv run paperbot stats
```

### 或者：先激活虚拟环境

```bash
source .venv/bin/activate

# 现在可以直接用 paperbot 命令
paperbot --help
paperbot fetch --days 40
paperbot serve --port 8765 --daemon
# ...
```

## Configuration

Edit `data/config.json` to customize:

- **tracks** — SMT, SAT, CP queries and keywords
- **scoring.tiers** — venue tiers with point weights
- **scoring.citation_breakpoints** — citation → score mapping
- **filters** — title / source / venue blacklist
- **recommendation** — daily count, quality slots, thresholds

Default data directory: `~/.paperbot/`

"""PaperBot web dashboard — single-page HTTP server."""

from __future__ import annotations

import json
import sqlite3
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from typing import Any

from paperbot.config import default_config_path, load_config
from paperbot.db import get_recent_reads, get_stats, init_db, list_papers, set_paper_status, upsert_papers
from paperbot.fetch import fetch_papers

_HTML = """<!DOCTYPE html>
<html lang="en" data-theme="dark">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>PaperBot Dashboard</title>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@picocss/pico@2/css/pico.min.css">
  <style>
    :root {
      --pico-font-size: 90%;
    }
    .stats-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
      gap: 1rem;
      margin-bottom: 2rem;
    }
    .stat-card {
      background: var(--pico-card-background-color);
      border-radius: var(--pico-border-radius);
      padding: 1rem;
      text-align: center;
    }
    .stat-card .number {
      font-size: 2rem;
      font-weight: bold;
      color: var(--pico-primary);
    }
    .stat-card .label {
      font-size: 0.85rem;
      opacity: 0.8;
    }
    .paper-row {
      display: flex;
      justify-content: space-between;
      align-items: flex-start;
      gap: 1rem;
      padding: 0.75rem 0;
      border-bottom: 1px solid var(--pico-muted-border-color);
    }
    .paper-row:last-child { border-bottom: none; }
    .paper-title {
      font-weight: 600;
      margin-bottom: 0.25rem;
    }
    .paper-meta {
      font-size: 0.8rem;
      opacity: 0.7;
    }
    .paper-actions {
      display: flex;
      gap: 0.25rem;
      flex-shrink: 0;
    }
    .paper-actions button {
      padding: 0.25rem 0.5rem;
      font-size: 0.75rem;
    }
    .badge {
      display: inline-block;
      padding: 0.1rem 0.4rem;
      border-radius: var(--pico-border-radius);
      font-size: 0.75rem;
      background: var(--pico-primary-background);
      color: var(--pico-primary-inverse);
      margin-right: 0.3rem;
    }
    .badge.pending { background: #6c757d; }
    .badge.read { background: #198754; }
    .badge.starred { background: #ffc107; color: #000; }
    .badge.skip { background: #dc3545; }
    .badge.recommended { background: #0d6efd; }
    .recommendation-group {
      margin-bottom: 1rem;
    }
    .recommendation-date {
      font-weight: bold;
      margin-bottom: 0.5rem;
      padding: 0.5rem;
      background: var(--pico-primary-background);
      color: var(--pico-primary-inverse);
      border-radius: var(--pico-border-radius);
    }
    .recommendation-item {
      padding: 0.5rem 1rem;
      border-left: 3px solid var(--pico-primary);
      margin-bottom: 0.5rem;
    }
    .tabs {
      display: flex;
      gap: 0.5rem;
      margin-bottom: 1rem;
      border-bottom: 1px solid var(--pico-muted-border-color);
      padding-bottom: 0.5rem;
    }
    .tabs button {
      background: transparent;
      border: none;
      color: var(--pico-muted-color);
      cursor: pointer;
      padding: 0.5rem 1rem;
    }
    .tabs button.active {
      color: var(--pico-primary);
      border-bottom: 2px solid var(--pico-primary);
    }
    .filter-bar {
      display: flex;
      gap: 0.5rem;
      flex-wrap: nowrap;
      margin-bottom: 1rem;
      align-items: center;
    }
    .filter-bar input, .filter-bar select {
      margin-bottom: 0;
    }
    .filter-bar select {
      width: auto;
      min-width: 120px;
    }
    .hidden { display: none !important; }
    .empty-msg {
      text-align: center;
      padding: 2rem;
      opacity: 0.6;
    }
    nav { margin-bottom: 1rem; }
    .track-tag {
      font-size: 0.7rem;
      padding: 0.1rem 0.35rem;
      border-radius: 3px;
      font-weight: 600;
    }
    .track-tag.smt { background: #1e40af; color: #dbeafe; }
    .track-tag.sat { background: #14532d; color: #dcfce7; }
    .track-tag.cp  { background: #7c2d12; color: #ffedd5; }
    .track-tag.mix { background: #581c87; color: #f3e8ff; }
    .venue-tag {
      font-size: 0.7rem;
      padding: 0.1rem 0.35rem;
      border-radius: 3px;
      font-weight: 600;
    }
    .venue-tag.t1 { background: #b45309; color: #fef3c7; }
    .venue-tag.t2 { background: #1e3a8a; color: #dbeafe; }
    .venue-tag.t3 { background: #374151; color: #e5e7eb; }
    .venue-tag.t0 { background: var(--pico-secondary-background); color: var(--pico-color); }
    .page-btn {
      padding: 0.25rem 0.6rem;
      font-size: 0.85rem;
      min-width: 36px;
    }
    .page-btn.active {
      background: var(--pico-primary);
      color: var(--pico-primary-inverse);
      border-color: var(--pico-primary);
    }
    .toast {
      position: fixed;
      bottom: 1rem;
      right: 1rem;
      padding: 0.75rem 1.25rem;
      border-radius: var(--pico-border-radius);
      color: #fff;
      z-index: 1000;
      animation: fadein 0.3s ease;
    }
    .toast.success { background: #198754; }
    .toast.error { background: #dc3545; }
    @keyframes fadein { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }
  </style>
</head>
<body>
  <main class="container">
    <nav>
      <ul><li><strong>PaperBot Dashboard</strong></li></ul>
      <ul><li><small id="last-updated">Loading...</small></li></ul>
    </nav>

    <!-- Overview -->
    <section>
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:0.5rem;">
        <h2 style="margin:0;">Overview</h2>
        <button id="update-btn" onclick="updatePapers()">Update (40d)</button>
      </div>
      <div class="stats-grid" id="stats-grid">
        <div class="stat-card"><div class="number">-</div><div class="label">Total</div></div>
      </div>
    </section>

    <!-- Recent Reads -->
    <section>
      <h2>Recent Reads</h2>
      <div id="recent-reads">Loading...</div>
    </section>

    <!-- Papers with Filters -->
    <section>
      <h2>Papers</h2>
      <div class="tabs">
        <button class="active" data-tab="pending" onclick="switchTab('pending')">Pending</button>
        <button data-tab="read" onclick="switchTab('read')">Read</button>
        <button data-tab="starred" onclick="switchTab('starred')">Starred</button>
        <button data-tab="skip" onclick="switchTab('skip')">Skipped</button>
        <button data-tab="all" onclick="switchTab('all')">All</button>
      </div>
      <div class="filter-bar">
        <input type="search" id="keyword" placeholder="Search title/abstract..." style="flex:1;min-width:200px;">
        <select id="track-filter">
          <option value="">All Tracks</option>
          <option value="SMT">SMT</option>
          <option value="SAT">SAT</option>
          <option value="CP">CP</option>
        </select>
        <select id="sort-by">
          <option value="score">Score</option>
          <option value="publication_date">Date</option>
          <option value="cited_by_count">Citations</option>
          <option value="title">Title</option>
        </select>
        <select id="sort-order">
          <option value="desc">Desc</option>
          <option value="asc">Asc</option>
        </select>
        <span id="paper-count" style="font-size:0.85rem;opacity:0.7;padding:0.25rem 0;white-space:nowrap;"></span>
      </div>
      <div id="papers-list">Loading...</div>
      <div id="pagination" style="display:flex;gap:0.5rem;justify-content:center;margin-top:1rem;"></div>
    </section>
  </main>

  <script>
    const API = '';
    let currentTab = 'pending';
    let currentOffset = 0;
    let currentTotal = 0;
    const PAGE_SIZE = 50;

    async function api(path) {
      const r = await fetch(API + path);
      if (!r.ok) throw new Error(await r.text());
      return r.json();
    }

    async function postApi(path, body) {
      const r = await fetch(API + path, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      if (!r.ok) throw new Error(await r.text());
      return r.json();
    }

    function toast(msg, type='success') {
      const el = document.createElement('div');
      el.className = 'toast ' + type;
      el.textContent = msg;
      document.body.appendChild(el);
      setTimeout(() => el.remove(), 2500);
    }

    function switchTab(tab) {
      currentTab = tab;
      currentOffset = 0;
      document.querySelectorAll('.tabs button').forEach(b => {
        b.classList.toggle('active', b.dataset.tab === tab);
      });
      loadPapers();
    }

    async function updatePapers() {
      const btn = document.getElementById('update-btn');
      btn.disabled = true;
      btn.textContent = 'Updating...';
      try {
        const r = await fetch(API + '/api/update', { method: 'POST' });
        if (!r.ok) throw new Error(await r.text());
        const data = await r.json();
        toast(`Updated: ${data.inserted} inserted, ${data.updated} updated (${data.range})`);
        await loadStats();
        await loadPapers();
      } catch (e) {
        toast(e.message, 'error');
      } finally {
        btn.disabled = false;
        btn.textContent = 'Update (40d)';
      }
    }

    async function loadStats() {
      const s = await api('/api/stats');
      const grid = document.getElementById('stats-grid');
      const items = [
        { n: s.total_papers || 0, l: 'Total' },
        { n: s.pending || 0, l: 'Pending' },
        { n: s.read || 0, l: 'Read' },
        { n: s.starred || 0, l: 'Starred' },
        { n: s.skipped || 0, l: 'Skipped' },
      ];

      let tracksHtml = '';
      if (s.by_track) {
        const tracks = Object.entries(s.by_track)
          .filter(([t]) => !t.includes(','))  // skip combined tracks
          .sort((a, b) => b[1] - a[1]);
        tracksHtml = '<div style="margin-top:0.75rem;">' +
          tracks.map(([t, c]) => `
            <div style="display:flex;justify-content:space-between;align-items:center;padding:0.25rem 0;font-size:0.85rem;opacity:0.8;border-bottom:1px solid var(--pico-muted-border-color);max-width:300px;margin:0 auto;">
              <span><span class="track-tag">${t}</span></span>
              <span style="font-weight:600;">${c}</span>
            </div>`).join('') +
          '</div>';
      }

      grid.innerHTML = items.map(i =>
        `<div class="stat-card"><div class="number">${i.n}</div><div class="label">${i.l}</div></div>`
      ).join('') + tracksHtml;
    }

    async function loadRecentReads() {
      const rows = await api('/api/recent-reads?limit=3');
      const el = document.getElementById('recent-reads');
      if (!rows || !rows.length) { el.innerHTML = '<p class="empty-msg">No recent reads.</p>'; return; }

      el.innerHTML = rows.map((p, i) => {
        let authors = p.authors;
        if (typeof authors === 'string') { try { authors = JSON.parse(authors); } catch(e){} }
        const authorStr = (Array.isArray(authors) ? authors.slice(0,3).join(', ') : (authors||''));
        const extraAuthors = Array.isArray(authors) && authors.length > 3 ? ', et al.' : '';
        const dateStr = p.publication_date || p.publication_year || '?';
        const url = p.landing_page_url || p.doi || p.id || '#';
        const abstract = p.abstract || '';
        const absDisplay = abstract.length > 2000 ? abstract.slice(0, 2000) + '...' : abstract;

        return `<div class="paper-row" style="border-left:3px solid var(--pico-primary);padding-left:0.75rem;margin-bottom:1rem;">
          <div>
            <div class="paper-title"><strong>#${i+1}</strong> <a href="${url}" target="_blank">${p.title||'Untitled'}</a></div>
            <div class="paper-meta">${authorStr}${extraAuthors}</div>
            <div class="paper-meta">${venueTag(p.venue, p.tier)} ${trackTag(p.track)} ${dateStr} · ${p.venue||'Unknown'} · Cited ${p.cited_by_count||0} · Score ${(p.score||0).toFixed(1)}</div>
            ${absDisplay ? `<div style="margin-top:0.5rem;font-size:0.9rem;opacity:0.85;line-height:1.5;">${absDisplay}</div>` : ''}
          </div>
        </div>`;
      }).join('');
    }

    function statusBadge(st) {
      const display = st === 'recommended' ? 'read' : st;
      const map = { pending: '⏳ Pending', read: '✅ Read', starred: '⭐ Starred', skip: '❌ Skip' };
      return `<span class="badge ${display}">${map[display] || display}</span>`;
    }

    const VENUE_MAP = {
      'CAV': ['computer aided verification'],
      'ICSE': ['international conference on software engineering'],
      'FSE': ['foundations of software engineering', 'esec/fse'],
      'ASE': ['automated software engineering'],
      'ISSTA': ['software testing and analysis'],
      'PLDI': ['programming language design'],
      'POPL': ['principles of programming languages'],
      'OOPSLA': ['object-oriented programming'],
      'NeurIPS': ['neural information processing', 'neurips'],
      'ICML': ['international conference on machine learning'],
      'ICLR': ['learning representations'],
      'AAAI': ['advancement of artificial intelligence'],
      'IJCAI': ['joint conference on artificial intelligence'],
      'TACAS': ['tools and algorithms'],
      'CADE': ['automated deduction'],
      'IJCAR': ['joint conference on automated reasoning'],
      'LICS': ['logic in computer science'],
      'SAT': ['satisfiability testing', 'theory and applications of satisfiability'],
      'CP': ['constraint programming', 'principles and practice of constraint programming'],
      'FM': ['symposium on formal methods'],
      'JAIR': ['journal of artificial intelligence research'],
      'AIJ': ['artificial intelligence'],
      'TOSEM': ['acm transactions on software engineering'],
      'TSE': ['ieee transactions on software engineering'],
      'TOPLAS': ['programming languages and systems'],
      'USENIX': ['usenix security'],
      'CCS': ['computer and communications security'],
      'NDSS': ['network and distributed system security'],
      'S&P': ['security and privacy', 'ieee symposium on security'],
      'OSDI': ['operating systems design'],
      'SOSP': ['operating systems principles'],
      'EuroSys': ['eurosys'],
      'SIGCOMM': ['sigcomm'],
      'SIGMOD': ['management of data'],
      'VLDB': ['very large data bases', 'vldb'],
      'WWW': ['the web conference', 'world wide web'],
      'ACL': ['association for computational linguistics'],
      'EMNLP': ['empirical methods in natural language'],
      'CVPR': ['computer vision and pattern recognition'],
      'ICCV': ['international conference on computer vision'],
      'ECCV': ['european conference on computer vision'],
      'SAS': ['static analysis symposium'],
      'ICLP': ['logic programming'],
      'FMCAD': ['formal methods in computer-aided design'],
      'VMCAI': ['verification, model checking'],
      'CPAIOR': ['constraint programming, artificial intelligence'],
      'LPAR': ['logic for programming'],
      'JAR': ['journal of automated reasoning'],
      'FMSD': ['formal methods in system design'],
      'ICSME': ['software maintenance'],
      'ISSRE': ['software reliability engineering'],
      'SANER': ['software analysis, evolution'],
      'COMPSAC': ['computer software and applications'],
      'MSR': ['mining software repositories'],
      'KR': ['knowledge representation and reasoning'],
      'SEFM': ['software engineering and formal methods'],
      'ICFEM': ['formal engineering methods'],
      'ICECCS': ['engineering of complex computer systems'],
      'QRS': ['software quality, reliability'],
      'AST': ['automated software testing'],
      'ICTAI': ['tools with artificial intelligence'],
    };

    function venueAbbr(venue) {
      if (!venue) return '';
      const v = venue.toLowerCase();
      for (const [abbr, keywords] of Object.entries(VENUE_MAP)) {
        for (const kw of keywords) {
          if (v.includes(kw)) return abbr;
        }
      }
      const matches = venue.match(/\b[A-Z]{2,}\b/g);
      if (matches) return matches[0];
      return '';
    }

    function trackTag(track) {
      const t = (track || '?').toLowerCase();
      let cls = 'mix';
      if (t === 'smt') cls = 'smt';
      else if (t === 'sat') cls = 'sat';
      else if (t === 'cp') cls = 'cp';
      return `<span class="track-tag ${cls}">${track || '?'}</span>`;
    }

    function venueTag(venue, tier) {
      const abbr = venueAbbr(venue);
      if (!abbr) return '';
      const t = tier || '0';
      return `<span class="venue-tag t${t}">${abbr}</span>`;
    }

    async function markPaper(id, status) {
      try {
        await postApi('/api/mark', { id, status });
        toast(`Marked as ${status}`);
        loadPapers();
        loadStats();
      } catch (e) {
        toast(e.message, 'error');
      }
    }

    async function loadPapers() {
      const keyword = document.getElementById('keyword').value;
      const track = document.getElementById('track-filter').value;
      const sortBy = document.getElementById('sort-by').value;
      const sortOrder = document.getElementById('sort-order').value;
      let status = currentTab;
      if (status === 'all') status = '';

      let qs = `limit=${PAGE_SIZE}&offset=${currentOffset}`;
      if (track) qs += `&track=${encodeURIComponent(track)}`;
      if (status) qs += `&status=${encodeURIComponent(status)}`;
      if (keyword) qs += `&keyword=${encodeURIComponent(keyword)}`;
      qs += `&sort_by=${encodeURIComponent(sortBy)}`;
      qs += `&sort_order=${encodeURIComponent(sortOrder)}`;

      const data = await api(`/api/papers?${qs}`);
      currentTotal = data.total;
      const countEl = document.getElementById('paper-count');
      if (countEl) countEl.textContent = `${data.total} papers`;
      const el = document.getElementById('papers-list');

      if (!data.papers || !data.papers.length) {
        el.innerHTML = '<p class="empty-msg">No papers found.</p>';
        document.getElementById('pagination').innerHTML = '';
        return;
      }

      el.innerHTML = data.papers.map(p => {
        let authors = p.authors;
        if (typeof authors === 'string') { try { authors = JSON.parse(authors); } catch(e){} }
        const authorStr = (Array.isArray(authors) ? authors.slice(0,3).join(', ') : (authors||''));
        const extraAuthors = Array.isArray(authors) && authors.length > 3 ? ', et al.' : '';
        const dateStr = p.publication_date || p.publication_year || '?';
        const meta = [`${dateStr}`, `${p.venue||'Unknown'}`, `Cited ${p.cited_by_count||0}`, `Score ${(p.score||0).toFixed(1)}`].join(' · ');
        const url = p.landing_page_url || p.doi || p.id || '#';

        const st = p.status || 'pending';
        const actionBtns = [
          st === 'read'
            ? `<button onclick="markPaper('${p.id}','pending')" class="secondary">↩️ Unread</button>`
            : `<button onclick="markPaper('${p.id}','read')">✅ Read</button>`,
          st === 'starred'
            ? `<button onclick="markPaper('${p.id}','pending')" class="secondary">↩️ Unstar</button>`
            : `<button onclick="markPaper('${p.id}','starred')">⭐ Star</button>`,
          st === 'skip'
            ? `<button onclick="markPaper('${p.id}','pending')" class="secondary">↩️ Unskip</button>`
            : `<button onclick="markPaper('${p.id}','skip')" class="secondary">❌ Skip</button>`,
        ];

        return `<div class="paper-row">
          <div style="flex:1;min-width:0;">
            <div class="paper-title">${statusBadge(p.status||'pending')} <a href="${url}" target="_blank">${p.title||'Untitled'}</a></div>
            <div class="paper-meta">${authorStr}${extraAuthors}</div>
            <div class="paper-meta">${venueTag(p.venue, p.tier)} ${trackTag(p.track)} ${meta}</div>
          </div>
          <div class="paper-actions">${actionBtns.join('')}</div>
        </div>`;
      }).join('');

      // pagination
      const totalPages = Math.ceil(data.total / PAGE_SIZE);
      const currentPage = Math.floor(currentOffset / PAGE_SIZE) + 1;
      let pgHtml = '';

      if (currentPage > 1) {
        pgHtml += `<button class="page-btn" onclick="goPage(${currentOffset - PAGE_SIZE})">« Prev</button>`;
      }

      let start = 1, end = totalPages;
      if (totalPages > 5) {
        if (currentPage <= 3) { start = 1; end = 5; }
        else if (currentPage >= totalPages - 2) { start = totalPages - 4; end = totalPages; }
        else { start = currentPage - 2; end = currentPage + 2; }
      }
      for (let p = start; p <= end; p++) {
        const off = (p - 1) * PAGE_SIZE;
        const cls = p === currentPage ? 'page-btn active' : 'page-btn';
        pgHtml += `<button class="${cls}" onclick="goPage(${off})">${p}</button>`;
      }

      if (currentPage < totalPages) {
        pgHtml += `<button class="page-btn" onclick="goPage(${currentOffset + PAGE_SIZE})">Next »</button>`;
      }

      if (totalPages > 1) {
        pgHtml += `
          <input type="number" id="jump-page" min="1" max="${totalPages}" placeholder="#"
            style="width:60px;padding:0.25rem 0.5rem;font-size:0.85rem;margin-bottom:0;text-align:center;"
            onkeydown="if(event.key==='Enter')jumpToPage()">
          <button class="page-btn" onclick="jumpToPage()">Go</button>`;
      }

      document.getElementById('pagination').innerHTML = pgHtml;
    }

    function goPage(offset) {
      currentOffset = offset;
      loadPapers();
    }

    function jumpToPage() {
      const input = document.getElementById('jump-page');
      if (!input) return;
      const page = parseInt(input.value, 10);
      const totalPages = Math.ceil(currentTotal / PAGE_SIZE);
      if (!page || page < 1 || page > totalPages) {
        toast(`Enter a page between 1 and ${totalPages}`, 'error');
        return;
      }
      currentOffset = (page - 1) * PAGE_SIZE;
      loadPapers();
    }

    async function init() {
      document.getElementById('last-updated').textContent = new Date().toLocaleString();
      await loadStats();
      await loadRecentReads();
      await loadPapers();
    }

    // Auto-refresh when filter/sort changes
    let keywordTimer;
    document.getElementById('keyword').addEventListener('input', () => {
      clearTimeout(keywordTimer);
      keywordTimer = setTimeout(() => { currentOffset = 0; loadPapers(); }, 300);
    });
    document.getElementById('track-filter').addEventListener('change', () => { currentOffset = 0; loadPapers(); });
    document.getElementById('sort-by').addEventListener('change', () => { currentOffset = 0; loadPapers(); });
    document.getElementById('sort-order').addEventListener('change', () => { currentOffset = 0; loadPapers(); });

    init();
  </script>
</body>
</html>
""".strip()


def _json_response(handler: BaseHTTPRequestHandler, data: Any, status: int = 200) -> None:
    body = json.dumps(data, ensure_ascii=False).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Access-Control-Allow-Origin", "*")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def _html_response(handler: BaseHTTPRequestHandler, html: str, status: int = 200) -> None:
    body = html.encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "text/html; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def _parse_qs(path: str) -> dict[str, str]:
    parsed = urllib.parse.urlparse(path)
    return dict(urllib.parse.parse_qsl(parsed.query))


def _read_body(handler: BaseHTTPRequestHandler) -> dict[str, Any]:
    content_length = int(handler.headers.get("Content-Length", 0))
    if content_length == 0:
        return {}
    body = handler.rfile.read(content_length).decode("utf-8")
    return json.loads(body)


def make_handler(db_path: Path):
    class DashboardHandler(BaseHTTPRequestHandler):
        def log_message(self, fmt: str, *args: Any) -> None:
            # suppress default access logs
            pass

        def do_OPTIONS(self) -> None:
            self.send_response(204)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "Content-Type")
            self.end_headers()

        def do_GET(self) -> None:
            parsed = urllib.parse.urlparse(self.path)
            path = parsed.path
            qs = dict(urllib.parse.parse_qsl(parsed.query))

            try:
                if path == "/":
                    _html_response(self, _HTML)

                elif path == "/api/stats":
                    data = get_stats(db_path)
                    _json_response(self, data)

                elif path == "/api/papers":
                    limit = int(qs.get("limit", "50"))
                    offset = int(qs.get("offset", "0"))
                    track = qs.get("track") or None
                    status = qs.get("status") or None
                    keyword = qs.get("keyword") or None
                    sort_by = qs.get("sort_by") or "score"
                    sort_order = qs.get("sort_order") or "desc"
                    data = list_papers(
                        db_path,
                        track=track,
                        status=status,
                        keyword=keyword,
                        sort_by=sort_by,
                        sort_order=sort_order,
                        limit=min(limit, 200),
                        offset=max(offset, 0),
                    )
                    _json_response(self, data)

                elif path == "/api/recommendations":
                    days = int(qs.get("days", "7"))
                    rows = get_recommendation_history(db_path, days=min(days, 365))
                    _json_response(self, rows)

                elif path == "/api/recent-reads":
                    limit = int(qs.get("limit", "3"))
                    rows = get_recent_reads(db_path, limit=min(limit, 10))
                    _json_response(self, rows)

                else:
                    self.send_error(404, "Not Found")

            except Exception as e:
                _json_response(self, {"error": str(e)}, 500)

        def do_POST(self) -> None:
            parsed = urllib.parse.urlparse(self.path)
            path = parsed.path

            try:
                if path == "/api/mark":
                    body = _read_body(self)
                    paper_id = body.get("id")
                    status = body.get("status")
                    if not paper_id or not status:
                        _json_response(self, {"error": "Missing id or status"}, 400)
                        return
                    set_paper_status(db_path, paper_id, status)
                    _json_response(self, {"success": True, "id": paper_id, "status": status})

                elif path == "/api/update":
                    cfg = load_config(default_config_path())
                    papers, stats = fetch_papers(cfg, days=40)
                    if papers:
                        inserted, updated = upsert_papers(db_path, papers)
                    else:
                        inserted, updated = 0, 0
                    _json_response(self, {
                        "success": True,
                        "inserted": inserted,
                        "updated": updated,
                        "total": len(papers),
                        "range": stats.get("range", ""),
                    })

                else:
                    self.send_error(404, "Not Found")

            except Exception as e:
                _json_response(self, {"error": str(e)}, 500)

    return DashboardHandler


def run_server(db_path: Path, host: str = "127.0.0.1", port: int = 8000) -> None:
    """Start the dashboard HTTP server."""
    handler = make_handler(db_path)
    server = HTTPServer((host, port), handler)
    print(f"Dashboard running at http://{host}:{port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down.")
        server.shutdown()

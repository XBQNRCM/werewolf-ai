(function () {
  const SECTION_SRC = {
    "对局玩家信息": "src-engine",
    "本局规则": "src-engine",
    "当前可见时间线": "src-engine",
    "行动指令": "src-engine",
    "合法行动": "src-engine",
    "狼队夜聊协商": "src-engine",
    "输出约束": "src-engine",
    "输出格式": "src-engine",
    "最近一次身份推断摘要": "src-belief",
    "上一轮身份推断摘要": "src-belief",
    "推断经验": "src-belief",
    "基础打法": "src-static",
    "对局经验": "src-memory",
    "复盘对象与最终真相": "src-engine",
    "完整对局时间线": "src-engine",
    "已有对局经验": "src-memory",
  };

  function esc(s) {
    return String(s ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function sectionClass(title) {
    return SECTION_SRC[title] || "src-engine";
  }

  function prettyJson(text) {
    if (!text) return "";
    try {
      return JSON.stringify(JSON.parse(text), null, 2);
    } catch {
      return text;
    }
  }

  function renderSections(sections) {
    if (!sections || !sections.length) return "<p class='walkthrough-loading'>无 prompt 数据</p>";
    return sections
      .map(
        (s) => `<div class="prompt-section ${sectionClass(s.title)}">
          <h4>【${esc(s.title)}】</h4>
          <pre>${esc(s.content)}</pre>
        </div>`
      )
      .join("");
  }

  // collapsible prompt block (consistent style for prompt + response)
  function systemPromptBlock(text, open) {
    if (!text) return "";
    return `<details class="prompt-block${open ? " open-default" : ""}"${open ? " open" : ""}>
      <summary>System prompt</summary>
      <div class="prompt-sections">
        <div class="prompt-section src-system"><pre>${esc(text)}</pre></div>
      </div>
    </details>`;
  }

  function promptBlock(label, sections, open) {
    if (!sections) return "";
    return `<details class="prompt-block${open ? " open-default" : ""}"${open ? " open" : ""}>
      <summary>${esc(label)} · ${sections.length} sections</summary>
      <div class="prompt-sections">${renderSections(sections)}</div>
    </details>`;
  }

  function outputBlock(label, text, open) {
    if (!text) return "";
    return `<details class="prompt-block${open ? " open-default" : ""}"${open ? " open" : ""}>
      <summary>${esc(label)}</summary>
      <div class="prompt-sections"><pre class="output-pre">${esc(prettyJson(text))}</pre></div>
    </details>`;
  }

  function stopShell(num, title, desc, bodyHtml, open) {
    return `<details class="walkthrough-stop"${open ? " open" : ""}>
      <summary>
        <span class="stop-num">${num}</span>
        <div>
          <div class="stop-title">${esc(title)}</div>
          <p class="stop-desc">${esc(desc)}</p>
        </div>
      </summary>
      <div class="walkthrough-body">${bodyHtml}</div>
    </details>`;
  }

  // ---------- Stop 1: action request + visible-state clipping ----------
  function renderClipping(c, request) {
    const reqHtml = request
      ? `<h4 class="sub-h">Agent 收到的动作请求（action request）</h4>
         <p class="prose">Agent 不持有长对话历史。它轮询到一个 pending action 时，从游戏系统拿到的就是下面这个请求信封：阶段、合法动作、行动指令与强制输出格式，以及一份已按自己身份裁剪好的 <code>visible_state</code>。</p>
         <pre class="output-pre req-pre">${esc(JSON.stringify(request, null, 2))}</pre>
         <h4 class="sub-h">信封里的 visible_state 从何而来</h4>`
      : "";
    return reqHtml + renderClippingBody(c);
  }

  function renderClippingBody(c) {
    const eventLine = (e, showHidden) => {
      const hidden = !e.visible_to_self;
      const tag = hidden
        ? `<span class="evt-tag hidden">仅 god</span>`
        : "";
      return `<div class="evt-row${hidden && showHidden ? " evt-hidden" : ""}">
        <span class="evt-seq">#${e.sequence}</span>
        <span class="evt-text">${esc(e.text)}</span>
        ${showHidden ? tag : ""}
      </div>`;
    };

    const rawHtml = c.raw_events.map((e) => eventLine(e, true)).join("");
    const clippedHtml = c.clipped_events
      .map(
        (e) => `<div class="evt-row">
          <span class="evt-seq">#${e.sequence}</span>
          <span class="evt-text">${esc(e.text)}</span>
        </div>`
      )
      .join("");

    const invis = (c.investigations || []).length;

    return `<p class="prose">同一时刻，游戏后端持有完整的权威事件流（god）。它按该玩家身份做视角裁剪，只把允许看到的事件写入
      <code>ActionContext.visible_state</code>。Agent 轮询 pending action 时拿到的就是右侧这份裁剪后的列表——信息隔离发生在后端，Agent 既无需也无法自行维护隐藏事实。</p>
    <div class="clip-stats">
      <span><strong>${c.raw_count}</strong> 条权威事件</span>
      <span class="arrow">→</span>
      <span><strong>${c.visible_count}</strong> 条对该玩家可见</span>
      <span class="clip-drop">${c.hidden_count} 条私有事件被裁剪</span>
    </div>
    <div class="compare-grid">
      <div class="compare-panel god">
        <h4>裁剪前 · 权威事件流（god 视角）</h4>
        <div class="evt-list">${rawHtml}</div>
      </div>
      <div class="compare-panel player">
        <h4>裁剪后 · 该玩家的 visible_state.events</h4>
        <div class="evt-list">${clippedHtml}</div>
      </div>
    </div>
    <div class="callout teal">
      <p><strong>被裁剪掉的典型信息</strong>：预言家查验结果（如 <code>#10 预言家查验 erin → good</code>）、女巫用药（<code>#44 use_poison → alice</code>）、其他玩家的私有夜间行动，以及尚未结算的逐张投票（<code>#25–#31</code>）。</p>
      <p style="margin-top:8px">该玩家身份 <code>${esc(c.self_role)}</code>，作为狼人可见队友 <code>${esc((c.known_wolves || []).join("、"))}</code>，但其查验记录 <code>investigations</code> 为${invis ? `${invis} 条` : "空"}——看不到预言家的验人结果。</p>
    </div>`;
  }

  // ---------- Stop 2: belief ----------
  function renderBeliefTable(rows) {
    if (!rows || !rows.length) return "";
    const body = rows
      .map(
        (r) => `<tr>
          <td><code>${esc(r.target_user_name)}</code></td>
          <td>${esc(r.deduced_role)}</td>
          <td class="num">${esc(r.role_confidence)}</td>
          <td class="num">${esc(r.statement_reliability)}</td>
          <td>${esc(r.evidence)}</td>
        </tr>`
      )
      .join("");
    return `<div class="table-wrap"><table>
      <thead><tr><th>目标</th><th>推断身份</th><th>置信度</th><th>发言可信度</th><th>证据</th></tr></thead>
      <tbody>${body}</tbody>
    </table></div>`;
  }

  function renderBelief(b) {
    if (!b) return "";
    const llm = b.llm || {};
    return `<p class="prose">行动前先做一次身份推断。belief 只读裁剪后的可见状态，输出每个玩家的推断身份、置信度与可读证据，整轮快照落库供复盘与机制分析。</p>
    ${systemPromptBlock(llm.system_prompt, false)}
    ${promptBlock("Belief prompt · user", llm.sections, false)}
    ${outputBlock("Belief 模型输出", llm.response_text, false)}
    <h4 class="sub-h">结构化推断结果</h4>
    ${renderBeliefTable(b.players)}`;
  }

  // ---------- Stop 3: decision ----------
  function renderMemories(memories) {
    if (!memories || !memories.length) return "";
    return `<div class="memory-cards">${memories
      .map(
        (m) => `<div class="memory-card">
          <div class="mem-meta">
            <span class="mem-norm">归一化得分 ${esc(m.normalized_score)}</span>
            <span>原始 score ${esc(m.score)} / 寿命 ${esc(m.lifespan)} 局</span>
            <span>${esc(m.phase || "通用")}</span>
          </div>
          ${esc(m.content)}
        </div>`
      )
      .join("")}</div>`;
  }

  function renderDecision(d) {
    if (!d) return "";
    const llm = d.llm || {};
    const sub = d.submitted || {};
    return `<p class="prose">决策层在 belief 之上组装 prompt：注入推断摘要、按 <code>role/phase</code> 归一化得分召回的 top-5 记忆，并把动作约束在 <code>legal_actions</code> 内。下方默认展开完整 decision prompt。</p>
    <h4 class="sub-h">召回的策略记忆（按归一化得分排序）</h4>
    ${renderMemories(d.memories)}
    ${systemPromptBlock(llm.system_prompt, false)}
    ${promptBlock("Decision prompt · user（默认展开）", llm.sections, true)}
    ${outputBlock("Decision 模型输出", llm.response_text, false)}
    <div class="submitted-action"><strong>提交发言：</strong>${esc(sub.content)}</div>`;
  }

  // ---------- Stop 4: postgame review ----------
  function renderErrors(title, rows) {
    if (!rows || !rows.length) return `<p class="prose" style="color:var(--dim)">${esc(title)}：本局无。</p>`;
    const items = rows
      .map(
        (r) => `<li><strong>${esc(r.mistake || r.lesson || "")}</strong>${
          r.lesson ? `<br><span style="color:var(--muted)">复盘结论：${esc(r.lesson)}</span>` : ""
        }</li>`
      )
      .join("");
    return `<h4 class="sub-h">${esc(title)}</h4><ul class="review-list">${items}</ul>`;
  }

  function renderScoreUpdates(p) {
    const ups = p.score_updates || [];
    if (!ups.length) return "";
    const won = p.self_won || p.winner === "werewolf";
    const rows = ups
      .map(
        (u) => `<tr>
          <td>${esc(u.role || "通用")} · ${esc(u.phase || "通用")}<div class="su-content">${esc(u.content)}</div></td>
          <td class="num">${esc(u.old_score)}</td>
          <td class="num su-delta">+${esc(u.delta)}</td>
          <td class="num su-new">${esc(u.new_score)}</td>
          <td>${esc(u.reason)}</td>
        </tr>`
      )
      .join("");
    return `<h4 class="sub-h">策略记忆得分更新（确定性规则）</h4>
    <p class="prose">复盘只让模型判定「哪些记忆这局帮上了忙」（helpful），<strong>打分本身不交给模型</strong>，而是由系统按确定性规则更新，避免模型给自己刷分：
      命中 helpful <code>+8</code>；本阵营获胜且 helpful 再 <code>+2</code>；分数上限 <code>100</code>，第一版不做失败扣分。</p>
    <div class="su-formula">本局狼队<strong>${won ? "获胜" : "落败"}</strong> → ${p.helpful_count} 条命中 helpful 的记忆各 <code>+8 ${won ? "+2 = +10" : "= +8"}</code></div>
    <div class="table-wrap"><table class="su-table">
      <thead><tr><th>策略记忆（role · phase）</th><th>原分</th><th>本局</th><th>新分</th><th>判定理由</th></tr></thead>
      <tbody>${rows}</tbody>
    </table></div>`;
  }

  function renderPostgame(p) {
    if (!p) return "";
    const llm = p.llm || {};
    const created = (p.created_memories || [])
      .map(
        (m) => `<div class="memory-card new">
          <div class="mem-meta"><span class="mem-new">新增记忆</span><span>${esc(m.role || "通用")} · ${esc(m.phase || "通用")}</span></div>
          ${esc(m.content)}
        </div>`
      )
      .join("");
    return `<p class="prose">终局后用 god replay 把「模型当时知道什么」与「最终真相」放在同一条时间线上复盘，区分 belief 错误与 decision 错误，并把可复用经验写入 room-scoped 策略记忆，供同房后续对局召回。</p>
    ${systemPromptBlock(llm.system_prompt, false)}
    ${promptBlock("Postgame review prompt · user", llm.sections, false)}
    ${outputBlock("Postgame review 模型输出", llm.response_text, false)}
    <h4 class="sub-h">复盘摘要</h4>
    <div class="review-summary">${esc(p.summary)}</div>
    ${renderErrors("Belief 错误分析", p.belief_errors)}
    ${renderErrors("Decision 错误分析", p.decision_errors)}
    ${created ? `<h4 class="sub-h">写入的新策略记忆（供下一局召回）</h4><div class="memory-cards">${created}</div>` : ""}
    ${renderScoreUpdates(p)}`;
  }

  function render(data) {
    const root = document.getElementById("walkthrough-root");
    if (!root) return;
    const m = data.meta;

    root.innerHTML = `
      <div class="section-legend">
        <span class="legend-item legend-system">System</span>
        <span class="legend-item legend-engine">引擎裁剪</span>
        <span class="legend-item legend-belief">Belief</span>
        <span class="legend-item legend-static">Static pack</span>
        <span class="legend-item legend-memory">Room memory</span>
      </div>
      <div class="walkthrough-meta">
        <div class="meta-item"><strong>主角</strong><span>${esc(m.player)} · ${esc(m.self_role)}</span></div>
        <div class="meta-item"><strong>Profile</strong><span>${esc(m.profile_id)}</span></div>
        <div class="meta-item"><strong>跨局记忆</strong><span>本局前 ${m.prior_memory_count} 条 active</span></div>
        <div class="meta-item"><strong>当前阶段</strong><span>第 ${m.day} 天白天发言</span></div>
      </div>

      ${stopShell(1, "动作请求与信息裁剪 · 得到 visible state", "Agent 从游戏系统收到动作请求，其中的 visible_state 已按身份裁剪。", renderClipping(data.clipping, data.request), true)}
      ${stopShell(2, "Belief · 身份推断", "基于裁剪后的可见状态做带证据的身份推断。", renderBelief(data.belief), false)}
      ${stopShell(3, "Decision · 行动决策", "在推断与召回记忆之上组装 decision prompt，输出合法发言。", renderDecision(data.decision), false)}
      ${stopShell(4, "Postgame Review · 复盘与记忆沉淀", "终局后基于 god replay 复盘，写入跨局策略记忆。", renderPostgame(data.postgame), false)}
    `;
  }

  async function init() {
    const root = document.getElementById("walkthrough-root");
    if (!root) return;
    try {
      const res = await fetch("./assets/walkthrough/context-walkthrough.json");
      if (!res.ok) throw new Error(res.statusText);
      render(await res.json());
    } catch (err) {
      root.innerHTML = `<p class="walkthrough-loading">无法加载走查数据：${esc(err.message)}（请通过本地 HTTP 服务打开本页面）</p>`;
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();

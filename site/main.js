(() => {
  "use strict";
  const root = document.documentElement;

  // Day and night: an explicit choice is remembered, otherwise the system decides.
  const toggle = document.getElementById("theme-toggle");
  const systemDark = window.matchMedia("(prefers-color-scheme: dark)");
  const current = () => root.getAttribute("data-theme") || (systemDark.matches ? "dark" : "light");
  if (toggle) {
    toggle.addEventListener("click", () => {
      const next = current() === "dark" ? "light" : "dark";
      root.setAttribute("data-theme", next);
      try { localStorage.setItem("gaea-theme", next); } catch (e) { /* storage unavailable */ }
      const meta = document.querySelector('meta[name="theme-color"]');
      if (meta) meta.setAttribute("content", next === "dark" ? "#060d12" : "#eef2ef");
    });
  }

  // Code sample tabs
  const tabs = Array.from(document.querySelectorAll('[role="tab"]'));
  const select = (tab) => {
    tabs.forEach((t) => {
      const on = t === tab;
      t.setAttribute("aria-selected", String(on));
      t.tabIndex = on ? 0 : -1;
      const panel = document.getElementById(t.getAttribute("aria-controls"));
      if (panel) panel.hidden = !on;
    });
  };
  tabs.forEach((tab, i) => {
    tab.addEventListener("click", () => select(tab));
    tab.addEventListener("keydown", (e) => {
      if (e.key !== "ArrowRight" && e.key !== "ArrowLeft") return;
      const next = tabs[(i + (e.key === "ArrowRight" ? 1 : tabs.length - 1)) % tabs.length];
      select(next); next.focus();
    });
  });

  // Copy the visible sample
  const copy = document.getElementById("copy-code");
  if (copy) {
    copy.addEventListener("click", () => {
      const panel = document.querySelector('[role="tabpanel"]:not([hidden])');
      if (!panel) return;
      const text = panel.innerText;
      const done = (label) => { copy.textContent = label; setTimeout(() => (copy.textContent = "Copy"), 1600); };
      const fallback = () => {
        const range = document.createRange();
        range.selectNodeContents(panel);
        const sel = window.getSelection();
        sel.removeAllRanges(); sel.addRange(range);
        done("Selected");
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(() => done("Copied"), fallback);
      } else fallback();
    });
  }

  // Name the latest release when GitHub answers; the static text stands otherwise.
  const releaseText = document.getElementById("release-text");
  if (releaseText && window.fetch && location.protocol === "https:") {
    fetch("https://api.github.com/repos/xocialize-code/gaea/releases/latest", { headers: { Accept: "application/vnd.github+json" } })
      .then((r) => (r.ok ? r.json() : null))
      .then((rel) => {
        if (rel && rel.tag_name) releaseText.textContent = `Gaea ${rel.tag_name.replace(/^v/, "")} · open source · Apache-2.0`;
      })
      .catch(() => {});
  }
})();

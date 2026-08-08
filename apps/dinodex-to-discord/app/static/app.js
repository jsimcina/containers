const state = {
  items: [],
  maxCreatures: 10,
  selected: new Map(), // uuid -> name, insertion order preserved
};

const el = {
  search: document.getElementById("search"),
  list: document.getElementById("creatureList"),
  selectedCount: document.getElementById("selectedCount"),
  maxCount: document.getElementById("maxCount"),
  maxCountFooter: document.getElementById("maxCountFooter"),
  runBtn: document.getElementById("runBtn"),
  clearBtn: document.getElementById("clearBtn"),
  results: document.getElementById("results"),
  log: document.getElementById("log"),
  discordOutput: document.getElementById("discordOutput"),
  copyDiscordBtn: document.getElementById("copyDiscordBtn"),
};

async function init() {
  const [cfg, items] = await Promise.all([
    fetchJson("/api/config"),
    fetchJson("/api/creatures"),
  ]);

  state.maxCreatures = cfg.max_creatures;
  state.items = items;
  el.maxCount.textContent = state.maxCreatures;
  el.maxCountFooter.textContent = state.maxCreatures;

  render(state.items);
  updateFooter();
}

async function fetchJson(url, opts) {
  const res = await fetch(url, opts);
  const body = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(body.error || `${url} failed (${res.status})`);
  }
  return body;
}

function render(items) {
  el.list.innerHTML = "";
  const frag = document.createDocumentFragment();

  for (const item of items) {
    const row = document.createElement("label");
    row.className = "creature-row";

    const cb = document.createElement("input");
    cb.type = "checkbox";
    cb.value = item.uuid;
    cb.checked = state.selected.has(item.uuid);
    cb.addEventListener("change", () => onToggle(item, cb));

    const span = document.createElement("span");
    span.textContent = item.name;

    row.appendChild(cb);
    row.appendChild(span);
    frag.appendChild(row);
  }

  el.list.appendChild(frag);
}

function onToggle(item, checkbox) {
  if (checkbox.checked) {
    if (state.selected.size >= state.maxCreatures) {
      checkbox.checked = false;
      window.alert(`You can select up to ${state.maxCreatures} creatures.`);
      return;
    }
    state.selected.set(item.uuid, item.name);
  } else {
    state.selected.delete(item.uuid);
  }
  updateFooter();
}

function updateFooter() {
  el.selectedCount.textContent = state.selected.size;
  el.runBtn.disabled = state.selected.size === 0;
}

el.search.addEventListener("input", () => {
  const q = el.search.value.trim().toLowerCase();
  const filtered = q
    ? state.items.filter((i) => i.name.toLowerCase().includes(q))
    : state.items;
  render(filtered);
});

el.clearBtn.addEventListener("click", () => {
  state.selected.clear();
  render(state.items.filter((i) => {
    const q = el.search.value.trim().toLowerCase();
    return !q || i.name.toLowerCase().includes(q);
  }));
  updateFooter();
});

// Special-cased acquisition phrasing for specific exact location values,
// replacing the default "farmable in LOCATION" wording entirely (these
// aren't time-of-day farming spots, so TIME is ignored for them).
const LOCATION_PHRASES = {
  "Strike Towers": "acquired through Strike Towers",
  "Raid": "acquired via weekly raid",
};

// Parenthesized acquisition suffix, e.g. " (farmable in Zone 2, Day)":
//  - an exact match in LOCATION_PHRASES overrides the default wording
//  - otherwise " (farmable in LOCATION, TIME)" if both are set
//  - otherwise " (farmable in LOCATION)" if only location is set
//    (location "none" counts as not set)
//  - otherwise "" (no suffix)
function formatAcquisitionSuffix(location, time) {
  const hasLocation = !!location && location !== "none";
  const hasTime = !!time;
  const phrase = hasLocation ? LOCATION_PHRASES[location] : undefined;

  if (phrase) return ` (${phrase})`;
  if (hasLocation && hasTime) return ` (farmable in ${location}, ${time})`;
  if (hasLocation) return ` (farmable in ${location})`;
  return "";
}

// [Name](<url>) -- the angle brackets around the URL suppress Discord's
// link-preview embed.
function formatLink(name, url) {
  return `[${name}](<${url}>)`;
}

// [Name](<creature_url>) plus its acquisition suffix.
function formatIngredientLink(ingredient) {
  return formatLink(ingredient.name, ingredient.creature_url)
    + formatAcquisitionSuffix(ingredient.location, ingredient.time);
}

// Builds the Discord-ready markdown block for one creature:
//   ### [Name](<creature_url>)
//   - Fusable using [Ingredient1](<url>) (farmable in ...), ...     (if ingredients present)
//   - Not a hybrid (farmable in ...)                                (otherwise)
//   - Component for [Hybrid1](<url>) rarity, [Hybrid2](<url>) rarity (if hybrids present)
//   - Genetic deadend                                               (otherwise)
function formatCreatureForDiscord(creature) {
  const lines = [`### ${formatLink(creature.name, creature.creature_url)}`];

  if (Array.isArray(creature.ingredients) && creature.ingredients.length > 0) {
    const parts = creature.ingredients.map(formatIngredientLink);
    lines.push(`- Fusable using ${parts.join(", ")}`);
  } else {
    lines.push(`- Not a hybrid${formatAcquisitionSuffix(creature.location, creature.time)}`);
  }

  if (Array.isArray(creature.hybrids) && creature.hybrids.length > 0) {
    const parts = creature.hybrids.map((h) => `${formatLink(h.name, h.creature_url)} ${h.rarity}`);
    lines.push(`- Component for ${parts.join(", ")}`);
  } else {
    lines.push("- Genetic deadend");
  }

  return lines.join("\n");
}

function formatForDiscord(results) {
  if (!Array.isArray(results) || results.length === 0) return "";
  return results.map(formatCreatureForDiscord).join("\n\n");
}

el.copyDiscordBtn.addEventListener("click", async () => {
  const text = el.discordOutput.value;
  if (!text) return;

  try {
    await navigator.clipboard.writeText(text);
  } catch {
    // Clipboard API unavailable (e.g. non-secure context) -- fall back to
    // a manual select so the user can still Ctrl/Cmd+C it themselves.
    el.discordOutput.focus();
    el.discordOutput.select();
  }

  const original = el.copyDiscordBtn.textContent;
  el.copyDiscordBtn.textContent = "Copied!";
  setTimeout(() => {
    el.copyDiscordBtn.textContent = original;
  }, 1500);
});

el.runBtn.addEventListener("click", async () => {
  const uuids = Array.from(state.selected.keys());
  el.runBtn.disabled = true;
  el.runBtn.textContent = "Running...";
  el.results.textContent = "Running...";
  el.log.textContent = "";
  el.discordOutput.value = "";
  el.copyDiscordBtn.disabled = true;

  try {
    const res = await fetch("/api/run", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ uuids }),
    });
    const body = await res.json();

    el.log.textContent = body.log || "";

    if (!res.ok) {
      el.results.textContent = `Error: ${body.error || "unknown error"}`;
    } else {
      el.results.textContent = JSON.stringify(body.data, null, 2);
      el.discordOutput.value = formatForDiscord(body.data);
      el.copyDiscordBtn.disabled = !el.discordOutput.value;
    }
  } catch (err) {
    el.results.textContent = `Request failed: ${err.message}`;
  } finally {
    el.runBtn.disabled = state.selected.size === 0;
    el.runBtn.textContent = "Run";
  }
});

init().catch((err) => {
  el.results.textContent = `Failed to load: ${err.message}`;
});

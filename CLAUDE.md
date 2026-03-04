# Godot working guidelines for LLMs

This file tells an LLM coding agent how to work safely and effectively in a **Godot** repository.

## 0) Golden rule: delegate to the Godot skill first

Before you edit anything Godot-related, **load and follow the repo’s existing Godot skill**:

- `skills/godot` (primary reference the user provided)

That skill contains the “sharp edges” rules (especially **.tscn/.tres formatting** and safe editing patterns). Do **not** restate or re-invent those rules here—**use the skill as the source of truth**.
## 1) What this AGENT.md adds (beyond the skill)

This document covers **general, repo-agnostic** guidance for:
- how to approach changes as an LLM (scope control, verification, safety),
- Godot project organization conventions,
- scripting style expectations,
- scene/signal architecture hygiene,
- validation & run commands.

For detailed file-format correctness, templates, and pitfalls, **defer to the Godot skill**.

---

## 2) First steps on any task

1. **Identify Godot version**
   - Inspect `project.godot` (and any CI scripts) to learn the major version (3.x vs 4.x).
   - Assume **version-specific APIs** may differ; don’t “upgrade” patterns casually.

2. **Locate the modified surface area**
   - Prefer changes in **.gd** scripts over direct edits to **.tscn/.tres**, unless the task *requires* it.
   - If editing **.tscn/.tres**, follow the skill’s strict formatting rules

3. **Minimize blast radius**
   - Make the smallest change that achieves the goal.
   - Avoid mass renames / node path changes unless explicitly requested (these break references and connections).

---

## 3) Project structure & naming conventions

Follow Godot’s recommended organization conventions unless the repo already enforces a different standard:

- **snake_case** for folders and file names (except C# scripts), to avoid platform case-sensitivity issues.
- **PascalCase** for node names, matching built-in node casing.
- Keep third-party resources in a top-level `addons/` folder when practical.

If the repo already has a structure (e.g., “one folder per scene”), preserve it and extend it consistently.

---

## 4) GDScript style & readability

Default to the official **GDScript style guide**:
- readable, consistent formatting,
- clear naming,
- consistent ordering of members and functions,
- prefer clarity over cleverness.  [oai_citation:4‡Godot Engine documentation](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html)

Practical LLM rules:
- Add types if the codebase is typed (don’t mix styles randomly).
- Prefer explicit, searchable names over cryptic abbreviations.
- Don’t introduce large abstractions unless asked—Godot projects often value directness.

---

## 5) Scenes: composition, coupling, and refactor safety

Scene changes are high-risk because **node paths, signal wiring, and instancing** can break easily. Follow Godot’s scene organization guidance:
- split scenes when reuse is clear,
- avoid brittle hard references across scenes,
- prefer patterns that survive instancing and reuse.  [oai_citation:5‡Godot Engine documentation](https://docs.godotengine.org/en/stable/tutorials/best_practices/scene_organization.html)

LLM safety rules for scenes:
- Don’t reorder/rename nodes without a reason.
- When you must change a node path, update **all** references (code + exported NodePaths + scene connections).
- Prefer exporting Node references / NodePaths or using groups instead of deep `$A/B/C` chains where appropriate.

---

## 6) Signals: default to decoupling

Use signals to reduce coupling between systems and UI:
- signals let nodes react to changes without direct references,
- in Godot 4, signals are first-class (less stringly-typed).  [oai_citation:6‡Godot Engine documentation](https://docs.godotengine.org/en/4.4/getting_started/step_by_step/signals.html)

LLM rules for signals:
- Prefer connecting signals in `_ready()` (or via the editor) in a consistent style used by the repo.
- Don’t introduce a global “event bus” unless the repo already uses one (it’s a pattern choice, not a default).

---

## 7) Editing rules for Godot resource files (.tscn/.tres)

**Strictly defer to the Godot skill** for:
- `ExtResource` / `SubResource` rules,
- what syntax is illegal in `.tscn/.tres`,
- typed array syntax and serialization pitfalls,
- validation scripts or linters bundled with the repo.  [oai_citation:7‡FastMCP](https://fastmcp.me/Skills/Details/235/godot?utm_source=chatgpt.com)

Additional safety rules:
- Keep diffs small and deterministic (these files are serialized; reorder noise hurts reviews).
- Never “pretty format” a `.tscn/.tres` unless the repo explicitly standardizes formatting.

---

## 8) Verification: what to run before finishing

Prefer the repo’s own CI commands first. If not available, typical checks include:

- **Headless run / smoke test** (Godot 4 example):
  - `godot --headless --quit` (or run a minimal scene if the repo provides one)
- **Export/import checks** if the repo depends on importers or custom addons.
- Any **validation scripts** referenced by the Godot skill (especially for `.tres/.tscn`).  [oai_citation:8‡FastMCP](https://fastmcp.me/Skills/Details/235/godot?utm_source=chatgpt.com)

If you can’t run commands (environment limitations), still:
- ensure the edited files are syntactically valid,
- keep changes minimal,
- call out what should be run locally/CI.

---

## 9) Common LLM failure modes (avoid these)

- Editing `.tscn/.tres` like it’s code (it’s serialized data): **follow the skill**.  [oai_citation:9‡FastMCP](https://fastmcp.me/Skills/Details/235/godot?utm_source=chatgpt.com)
- Breaking node paths by renaming/reparenting nodes without updating references.
- Introducing patterns that fight Godot’s scene/component model (overengineering).
- Mixing typed and untyped styles randomly in GDScript.

---

## 10) When unsure

1. Check the existing Godot skill guidance first.  [oai_citation:10‡FastMCP](https://fastmcp.me/Skills/Details/235/godot?utm_source=chatgpt.com)  
2. Check Godot’s official docs for the relevant area (project org, scene org, style guide, signals).  [oai_citation:11‡Godot Engine documentation](https://docs.godotengine.org/en/stable/tutorials/best_practices/project_organization.html)  
3. Prefer a conservative change that matches existing repo patterns.

---

## 11) AGENT.md conventions (meta)

This file is intentionally:
- **actionable** (commands + rules, not essays),
- **scoped** (general guidelines, not a rehash of the Godot skill),
- **compatible** with common “agents.md / AGENTS.md” conventions.  [oai_citation:12‡agents.md](https://agents.md/)

# Copywriter Agent Team

A team of specialized copywriting/marketing subagents, each backed by skills in
`../skills/`. Invoke an agent with the Task tool (e.g. "use the copywriter agent
to write the homepage hero") or let Claude route automatically based on each
agent's `description`.

| Agent | Use it for | Skills it uses |
|-------|-----------|----------------|
| **copywriter** | Writing/rewriting copy from scratch (pages, headlines, CTAs) | copywriting, ogilvy-copywriting, stop-slop |
| **copy-editor** | Editing, polishing, proofreading existing copy | copy-editing, stop-slop, ogilvy-copywriting |
| **content-strategist** | Planning what to write — topic clusters, calendars | content-strategy, programmatic-seo, competitor-alternatives |
| **cro-specialist** | Improving page conversions and comparison pages | page-cro, competitor-alternatives, ogilvy-copywriting, adversarial-review |
| **seo-specialist** | SEO audits, schema markup, pages at scale | seo-audit, schema-markup, programmatic-seo |

## How agents and skills connect

Each agent's prompt tells it which skills to invoke (via the Skill tool). The
skills live in `../skills/` and carry the actual playbooks; the agents are thin
routers that apply the right skill with the right judgment and hand off to each
other.

## Source / attribution

Skills are vendored from https://github.com/boraoztunc/skills. Individual skills
retain their own licenses and attribution in their `SKILL.md` / metadata (e.g.
`stop-slop` by Hardik Pandya, `ogilvy-copywriting` MIT). See each skill folder.

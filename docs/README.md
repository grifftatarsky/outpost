<!-- COPY BEGIN 0f13ad5a [NEEDS HUMAN REVIEW] -->

# Outpost documentation

The source for [grifftatarsky.github.io/outpost](https://grifftatarsky.github.io/outpost/), a Jekyll
site using the [just-the-docs](https://just-the-docs.com) theme.

<!-- COPY END 0f13ad5a -->

<!-- COPY BEGIN e3049d68 [NEEDS HUMAN REVIEW] -->

## Running it locally

```bash
cd docs
bundle install
bundle exec jekyll serve
```

Then open <http://127.0.0.1:4000/outpost/>.

<!-- COPY END e3049d68 -->

<!-- COPY BEGIN bf259a78 [NEEDS HUMAN REVIEW] -->

## Publishing it

`.github/workflows/docs.yml` builds the site and deploys it to GitHub Pages. It runs only when started
by hand (Actions › Documentation › Run workflow), because publishing is a disclosure and should be a
person's decision. Before the first run, set the repository's Pages source to **GitHub Actions**
(Settings › Pages › Build and deployment). Run it with *Publish* unchecked to check a change builds
without deploying it.

<!-- COPY END bf259a78 -->

<!-- COPY BEGIN 60cf752b [NEEDS HUMAN REVIEW] -->

## The design set

`design/boards/` holds the design pass's boards, a closed record from 2026-08-18: the design tool is
retired and nothing will be re-exported, so the files are ordinary HTML and can be edited. They record
content, copy and accessibility intent; presentation questions are answered by Apple's guidance.

- `design/board-index.md` is the 84 boards as searchable text, generated.
- `design/boards.css` is the responsive layer each board links.
- `_plugins/design_boards.rb` copies the export's underscore-named assets through Jekyll.

Board links come from `design_board`, `design_decisions` and `design_blockers` in `_config.yml`, used
as `{{ site.baseurl }}{{ site.design_board }}`.

<!-- COPY END 60cf752b -->

<!-- COPY BEGIN e3cb8c67 [NEEDS HUMAN REVIEW] -->

## Adding to it

- **A decision that binds** goes in `decisions.md`, under its subject, with what it costs and what
  would change it, marked `RULED` only if Griff decided it, `PROPOSED` if Claude chose it, and `FACT`
  if nobody chose it. A replaced decision moves to *Superseded* as one line naming its replacement.
- **Something unbuilt or uncertain** goes in `open-questions.md`, written as a question.
- **Work** goes in an epic under `epics/` as a story with acceptance criteria, and its status goes on
  `roadmap.md`, the only place a status lives.
- **Something noticed and parked** goes in `inbox.md`. Delete it when it is done or does not matter.
- **Present tense means it is in the build.** Anything else gets a `{: .unbuilt }` or `{: .unproven }`
  callout.
- **The voice** is a good newspaper's: plain, specific, American spelling, no emoji. The copy guide in
  the marketing site's repository is the full version.

`CLAUDE.md` at the repository root is the orientation for anybody changing code: the module map, the
commands, the rules the lint enforces and the traps this codebase has fallen into.

<!-- COPY END e3cb8c67 -->

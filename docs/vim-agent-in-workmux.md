# Vim-Embedded Agent in Workmux Panes

## Status

**Blocked** on [workmux#82](https://github.com/raine/workmux/issues/82) -- waiting for
workmux to support writing the prompt file without requiring an agent pane.

## Problem

When workmux creates a new pane, it launches a standalone opencode agent in the
terminal. This works, but loses the ability to send file references, line
ranges, and selections to the agent -- capabilities that exist when running
opencode inside neovim via [tw-vim-lib](https://github.com/twhitney/tw-vim-lib)
(`<leader>co`).

The goal: workmux creates the worktree and pane as usual, but instead of a bare
agent, vim starts with an embedded agent that receives the workmux prompt.

## How Workmux Prompt Injection Works

Understanding the current flow is key to why this is non-trivial:

1. User runs `workmux add name -P prompt.md` (or `-p "inline prompt"`, or `-e`
   for editor).
2. `parse_prompt_document()` in `prompt.rs` processes frontmatter (`foreach:`
   matrices, template variables). For multi-agent prompts, this generates
   multiple worktrees.
3. Per worktree, `write_prompt_file()` in `setup.rs` writes the **resolved**
   prompt body (frontmatter stripped, templates substituted) to
   `.workmux/PROMPT-<branch>.md` inside the worktree.
4. `resolve_pane_command()` detects agent commands via `AgentProfile` matching
   (in `multiplexer/agent.rs`). For opencode, it appends
   `--prompt "$(cat .workmux/PROMPT-branch.md)"` to the command.
5. **Validation**: `validate_prompt_consumption()` **rejects** the prompt if no
   pane runs a recognized agent. This is the blocker.

Agent detection works by extracting the executable stem from the pane command
and matching against built-in profiles. It resolves symlinks, so
`/any/path/opencode` still matches. But `nvim` does not.

## Approaches Explored and Rejected

### Wrapper script named `opencode` (rejected: too hacky)

Create a shell script named `opencode` that intercepts the call, parses
`--prompt`, and launches nvim instead. Install via nix, shadow the real
opencode on PATH, alias `oc` to the real binary.

Problems:
- Requires PATH manipulation and careful ordering
- The real opencode reference must be hardcoded (nix store path via
  `${pkgs.opencode}/bin/opencode`)
- Vim's agent code (`claude.lua`) uses `command -v opencode` and would find
  the wrapper, requiring `$NVIM` env var checks to avoid recursion
- Fragile across nix rebuilds and multiple contexts

### Custom pane command without `<agent>` (rejected: validation blocks it)

Set the pane command to `nvim` and pass `-p` to workmux. Workmux writes the
prompt file, vim reads it on startup.

Problem: `validate_prompt_consumption()` errors because no pane runs a
recognized agent. The prompt file writing and agent injection are coupled.

### Dual-pane stopgap (viable but wasteful)

Keep an `<agent>` pane alongside a `nvim` pane. Workmux writes the prompt file
and injects it into the opencode pane. Vim reads `.workmux/PROMPT-*.md`
independently. Ignore/close the opencode pane.

This works but wastes a pane and adds clutter.

## Chosen Approach (pending workmux#82)

Once workmux supports writing the prompt file without requiring an agent pane:

### Workmux Config

```yaml
agent: opencode
panes:
  - command: nvim
    focus: true
  - split: horizontal
```

No `<agent>` placeholder. The `-p`/`-P`/`-e` flags write the resolved prompt
file to `.workmux/PROMPT-<branch>.md` but don't inject it into any pane
command.

### tw-vim-lib Changes

Add a startup mechanism that:

1. On `VimEnter`, checks for `.workmux/PROMPT-*.md` in the working directory.
2. If found, reads the prompt content.
3. Opens an opencode agent terminal (same as `<leader>co`).
4. Sends the prompt content to the agent.

This could be an autocmd in the agent module or a new `:WorkmuxPrompt` command
triggered by an `after/plugin` autocmd.

### Key Details

- The prompt file contains the **resolved** body only (no frontmatter, no
  template variables). It's safe to send directly to the agent.
- `tw-vim-lib` already has `confirmOpenAndDo()` with a 2500ms delay for agent
  startup before sending text. The same mechanism works here.
- Multi-worktree prompts (via `foreach:`) are already resolved per-worktree.
  Each vim instance gets its own prompt file.

### No Nix/Dotfiles Changes Required

The pane command is just `nvim` -- no wrappers, no PATH hacks, no custom
packages. The only changes are:
- `workmux/config.yaml`: change pane command from `<agent>` to `nvim`
- `tw-vim-lib`: add workmux prompt detection

## References

- Workmux agent profiles: `src/multiplexer/agent.rs` -- `AgentProfile` trait,
  `OpenCodeProfile.prompt_argument()`
- Workmux prompt parsing: `src/prompt.rs` -- frontmatter extraction, template
  resolution
- Workmux prompt validation: `src/workflow/setup.rs` --
  `validate_prompt_consumption()`, `write_prompt_file()`
- tw-vim-lib agent module: `lua/tw/agent/` -- `init.lua` (agent lifecycle),
  `claude.lua` (opencode integration), `commands.lua` (keybindings)

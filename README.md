# autosaver.nvim

A Neovim plugin that automatically commits and pushes markdown files to git when you enter normal mode.

## Features

- 🔄 Auto-commits markdown files when switching to normal mode
- ⚡ **Fully asynchronous** - Never blocks Neovim while saving
- 🎯 **Smart debouncing** - Waits 2s after last change (configurable)
- 📋 **Queue system** - Handles rapid mode changes without conflict
- ⏰ Uses timestamp as commit message (format: `YYYY-MM-DD HH:MM:S`)
- 🚀 Automatically pushes to remote repository
- 🔄 SSH/HTTPS fallback for git push
- ⚙️ Configurable and toggleable
- 🔕 Silent on success, notifies only on errors

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

**Simple (with defaults):**
```lua
{
  dir = "/home/servus/Documents/autosaver",  -- or wherever you clone this repo
  ft = "markdown",  -- Only load for markdown files
  opts = {},  -- Uses default configuration
}
```

**With custom configuration:**
```lua
{
  dir = "/home/servus/Documents/autosaver",  -- or wherever you clone this repo
  ft = "markdown",  -- Only load for markdown files
  opts = {
    enabled = true,        -- Enable on startup
    silent = false,        -- Show notifications
    file_pattern = "%.md$" -- Only .md files (lua pattern)
  }
}
```

**Alternative using config function:**
```lua
{
  dir = "/home/servus/Documents/autosaver",
  ft = "markdown",
  config = function()
    require("nvim-md-git-autosave").setup({
      enabled = true,
      silent = false,
    })
  end
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  '/home/servus/Documents/autosaver',
  config = function()
    require('nvim-md-git-autosave').setup()
  end
}
```

### Manual Installation

1. Clone or copy this repository to your Neovim config directory:
   ```bash
   mkdir -p ~/.config/nvim/pack/plugins/start/
   cp -r /home/servus/Documents/autosaver ~/.config/nvim/pack/plugins/start/autosaver
   ```

2. Restart Neovim

## Configuration

Default configuration:

```lua
require('nvim-md-git-autosave').setup({
  enabled = true,          -- Enable/disable the plugin
  file_pattern = "%.md$",  -- Lua pattern to match files (default: markdown)
  git_add = true,          -- Run git add
  git_commit = true,       -- Run git commit
  git_push = true,         -- Run git push
  silent = false,          -- Suppress notifications (only shows errors)
  debounce_ms = 2000,      -- Wait time after last change before saving (ms)
})
```

## Usage

The plugin works automatically once installed. Every time you enter normal mode (e.g., by pressing `Esc` or `Ctrl+[`), it will:

1. Check if the current file is a markdown file
2. Save the file immediately (fast, synchronous)
3. Queue git operations (fully asynchronous):
   - Run `git add <file>`
   - Run `git commit -m "<timestamp>"`
   - Run `git push` (with SSH/HTTPS fallback)

**Async Behavior:**
- Git operations run in the background - **Neovim never freezes**
- Smart debouncing: waits 2 seconds after your last mode change
- If you switch modes rapidly, only the latest change is saved
- Queue system prevents overlapping git operations
- Silent on success, only notifies on errors

### Commands

- `:AutoSaverEnable` - Enable the plugin
- `:AutoSaverDisable` - Disable the plugin
- `:AutoSaverToggle` - Toggle the plugin on/off
- `:AutoSaverStatus` - Show current status (enabled/disabled, queue size, running jobs)

### Example Workflow

1. Open a markdown file: `nvim notes.md`
2. Enter insert mode: `i`
3. Type your notes
4. Press `Esc` to return to normal mode
5. The file is automatically committed and pushed with a timestamp

## Requirements

- Neovim 0.7+ (for the ModeChanged autocommand)
- Git repository initialized in the working directory
- Git remote configured for pushing

## Customization

### Change File Pattern

To auto-commit different file types:

```lua
require('nvim-md-git-autosave').setup({
  file_pattern = "%.txt$"  -- Text files
})
```

Or multiple patterns (you'll need to modify the plugin slightly):

```lua
require('nvim-md-git-autosave').setup({
  file_pattern = "%.md$|%.txt$"  -- Markdown or text files
})
```

### Silent Mode

To suppress all notifications:

```lua
require('nvim-md-git-autosave').setup({
  silent = true
})
```

### Disable Auto-Push

To only commit locally without pushing:

```lua
require('nvim-md-git-autosave').setup({
  git_push = false
})
```

### Adjust Debounce Time

Change how long to wait after your last edit:

```lua
require('nvim-md-git-autosave').setup({
  debounce_ms = 5000  -- Wait 5 seconds (useful for slower connections)
})
```

Or make it instant (save immediately, no debounce):

```lua
require('nvim-md-git-autosave').setup({
  debounce_ms = 0  -- No debounce, save immediately
})
```

## Troubleshooting

**Plugin doesn't work:**
- Ensure you're in a git repository: `git rev-parse --is-inside-work-tree`
- Check if the file matches the pattern (default: `.md` extension)
- Verify git is properly configured with a remote

**Too many commits:**
- The plugin triggers on every mode change to normal mode
- Consider disabling it when you don't need it with `:AutoSaverDisable`
- Or set `enabled = false` in config and manually enable when needed

**Git push fails:**
- Ensure you have a remote configured: `git remote -v`
- Check you have push permissions
- Verify your git credentials are set up

## Notes

- This plugin will create a commit every time you enter normal mode, which may result in many commits
- Best used for personal notes or documentation where granular history is desired
- Consider using with a private repository or notes system
- The plugin silently handles "nothing to commit" scenarios

## License

MIT

## Contributing

Feel free to open issues or submit pull requests!

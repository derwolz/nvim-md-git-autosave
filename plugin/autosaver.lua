-- autosaver.nvim - Auto-commit and push markdown files when entering normal mode

local M = {}

-- Configuration
M.config = {
  enabled = true,
  file_pattern = "%.md$",  -- Pattern to match markdown files
  git_add = true,
  git_commit = true,
  git_push = true,
  silent = false,  -- Set to true to suppress notifications
}

-- Function to check if file is in a git repository
local function is_git_repo()
  local handle = io.popen("git rev-parse --is-inside-work-tree 2>/dev/null")
  if not handle then return false end
  local result = handle:read("*a")
  handle:close()
  return result:match("true") ~= nil
end

-- Function to get current timestamp
local function get_timestamp()
  return os.date("%Y-%m-%d %H:%M:%S")
end

-- Function to execute git commands
local function git_execute(cmd)
  local handle = io.popen(cmd .. " 2>&1")
  if not handle then return false, "Failed to execute command" end
  local result = handle:read("*a")
  local success = handle:close()
  return success, result
end

-- Main auto-save function
local function autosave_markdown()
  if not M.config.enabled then return end

  local filepath = vim.fn.expand("%:p")
  local filename = vim.fn.expand("%:t")

  -- Check if file matches pattern (default: .md files)
  if not filename:match(M.config.file_pattern) then
    return
  end

  -- Check if file exists and is in a git repo
  if vim.fn.filereadable(filepath) == 0 then
    return
  end

  if not is_git_repo() then
    if not M.config.silent then
      vim.notify("autosaver: Not in a git repository", vim.log.levels.WARN)
    end
    return
  end

  -- Save the file first
  vim.cmd("silent! write")

  local timestamp = get_timestamp()
  local commit_msg = timestamp

  -- Git add
  if M.config.git_add then
    local success, result = git_execute(string.format("git add %s", vim.fn.shellescape(filepath)))
    if not success then
      if not M.config.silent then
        vim.notify("autosaver: git add failed - " .. result, vim.log.levels.ERROR)
      end
      return
    end
  end

  -- Git commit
  if M.config.git_commit then
    local success, result = git_execute(string.format("git commit -m %s", vim.fn.shellescape(commit_msg)))
    if not success and not result:match("nothing to commit") then
      if not M.config.silent then
        vim.notify("autosaver: git commit failed - " .. result, vim.log.levels.ERROR)
      end
      return
    end
  end

  -- Git push
  if M.config.git_push then
    local success, result = git_execute("git push")
    if not success then
      if not M.config.silent then
        vim.notify("autosaver: git push failed - " .. result, vim.log.levels.ERROR)
      end
      return
    end
  end

  if not M.config.silent then
    vim.notify(string.format("autosaver: Committed and pushed '%s' at %s", filename, timestamp), vim.log.levels.INFO)
  end
end

-- Setup function for user configuration
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

-- Enable the plugin
function M.enable()
  M.config.enabled = true
end

-- Disable the plugin
function M.disable()
  M.config.enabled = false
end

-- Create autocommand to trigger on entering normal mode
vim.api.nvim_create_autocmd("ModeChanged", {
  pattern = "*:n",  -- Trigger when entering normal mode
  callback = function()
    autosave_markdown()
  end,
  group = vim.api.nvim_create_augroup("AutoSaverMd", { clear = true })
})

-- Create user commands
vim.api.nvim_create_user_command("AutoSaverEnable", function()
  M.enable()
  vim.notify("autosaver: Enabled", vim.log.levels.INFO)
end, {})

vim.api.nvim_create_user_command("AutoSaverDisable", function()
  M.disable()
  vim.notify("autosaver: Disabled", vim.log.levels.INFO)
end, {})

vim.api.nvim_create_user_command("AutoSaverToggle", function()
  if M.config.enabled then
    M.disable()
    vim.notify("autosaver: Disabled", vim.log.levels.INFO)
  else
    M.enable()
    vim.notify("autosaver: Enabled", vim.log.levels.INFO)
  end
end, {})

return M

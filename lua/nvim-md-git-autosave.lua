-- autosaver.nvim - Async auto-commit and push markdown files

local M = {}

-- Configuration
M.config = {
  enabled = true,
  file_pattern = "%.md$",  -- Pattern to match markdown files
  git_add = true,
  git_commit = true,
  git_push = true,
  silent = false,  -- Set to true to suppress notifications
  debounce_ms = 2000,  -- Wait 2s after last change before saving
}

-- State management
local save_queue = {}
local current_job = nil
local debounce_timer = nil

-- Function to check if file is in a git repository (sync, fast check)
local function is_git_repo(dir)
  local result = vim.fn.system("git -C " .. vim.fn.shellescape(dir) .. " rev-parse --is-inside-work-tree 2>/dev/null")
  return vim.v.shell_error == 0 and result:match("true") ~= nil
end

-- Function to get current timestamp
local function get_timestamp()
  return os.date("%Y-%m-%d %H:%M:%S")
end

-- Async function to execute git command in a specific directory
local function git_execute_async(cmd, cwd, callback)
  vim.system(cmd, { text = true, cwd = cwd }, function(obj)
    vim.schedule(function()
      callback(obj.code == 0, obj.stdout or obj.stderr or "", obj.code)
    end)
  end)
end

-- Function to convert HTTPS URL to SSH
local function https_to_ssh(url)
  local ssh_url = url:gsub("https://([^/]+)/(.+)", "git@%1:%2")
  return ssh_url
end

-- Process the next item in queue
local function process_queue()
  if current_job or #save_queue == 0 then
    return
  end

  -- Get the latest save request for each unique file
  local unique_saves = {}
  for _, save_data in ipairs(save_queue) do
    unique_saves[save_data.filepath] = save_data
  end

  -- Clear the queue
  save_queue = {}

  -- Process each unique file
  for _, save_data in pairs(unique_saves) do
    current_job = save_data
    perform_git_operations(save_data)
    break  -- Process one at a time
  end
end

-- Main git operations chain (fully async)
function perform_git_operations(save_data)
  local filepath = save_data.filepath
  local filename = save_data.filename
  local timestamp = save_data.timestamp
  local dir = save_data.dir

  -- Step 1: Git add
  if M.config.git_add then
    git_execute_async(
      { "git", "add", filepath },
      dir,
      function(success, output, code)
        if not success then
          vim.notify("autosaver: git add failed - " .. output, vim.log.levels.ERROR)
          current_job = nil
          process_queue()
          return
        end

        -- Step 2: Git commit
        if M.config.git_commit then
          git_execute_async(
            { "git", "commit", "-m", timestamp },
            dir,
            function(commit_success, commit_output, commit_code)
              -- Allow "nothing to commit" and "up to date" as non-errors
              if not commit_success then
                if commit_output:match("nothing to commit") or commit_output:match("up to date") or commit_output:match("up%-to%-date") then
                  current_job = nil
                  process_queue()
                  return
                end
                vim.notify("autosaver: git commit failed - " .. commit_output, vim.log.levels.ERROR)
                current_job = nil
                process_queue()
                return
              end

              -- Step 3: Git push
              if M.config.git_push then
                perform_git_push(filepath, filename, timestamp, dir)
              else
                current_job = nil
                process_queue()
              end
            end
          )
        else
          current_job = nil
          process_queue()
        end
      end
    )
  else
    current_job = nil
    process_queue()
  end
end

-- Git push with SSH/HTTPS fallback (fully async)
function perform_git_push(filepath, filename, timestamp, dir)
  -- Get remote URL first
  git_execute_async(
    { "git", "remote", "get-url", "origin" },
    dir,
    function(success, remote_url, code)
      if not success then
        vim.notify("autosaver: Failed to get remote URL - " .. remote_url, vim.log.levels.ERROR)
        current_job = nil
        process_queue()
        return
      end

      remote_url = remote_url:gsub("%s+$", "")  -- trim whitespace
      local original_url = remote_url

      -- Try initial push
      git_execute_async(
        { "git", "push" },
        dir,
        function(push_success, push_output, push_code)
          if push_success then
            -- Success! Only notify on error (silent on success)
            current_job = nil
            process_queue()
            return
          end

          -- "Everything up-to-date" is not an error
          if push_output:match("up to date") or push_output:match("up%-to%-date") then
            current_job = nil
            process_queue()
            return
          end

          -- Push failed, try fallback
          handle_push_fallback(remote_url, original_url, filepath, filename, timestamp, push_output, dir)
        end
      )
    end
  )
end

-- Handle push fallback from SSH to HTTPS or vice versa
function handle_push_fallback(remote_url, original_url, filepath, filename, timestamp, error_msg, dir)
  local fallback_url = nil

  -- If HTTPS, try SSH
  if remote_url:match("^https://") then
    fallback_url = https_to_ssh(remote_url)
  -- If SSH, try HTTPS
  elseif remote_url:match("^git@") then
    fallback_url = remote_url:gsub("git@([^:]+):(.+)", "https://%1/%2")
  else
    -- Unknown format, can't fallback
    vim.notify("autosaver: git push failed - " .. error_msg, vim.log.levels.ERROR)
    current_job = nil
    process_queue()
    return
  end

  -- Set new remote URL and try again
  git_execute_async(
    { "git", "remote", "set-url", "origin", fallback_url },
    dir,
    function(set_success, set_output, set_code)
      if not set_success then
        vim.notify("autosaver: Failed to change remote URL - " .. set_output, vim.log.levels.ERROR)
        current_job = nil
        process_queue()
        return
      end

      -- Try push with new URL
      git_execute_async(
        { "git", "push" },
        dir,
        function(retry_success, retry_output, retry_code)
          if retry_success or retry_output:match("up to date") or retry_output:match("up%-to%-date") then
            -- Success (or already up to date) with fallback
            current_job = nil
            process_queue()
          else
            -- Both failed, restore original and notify
            git_execute_async(
              { "git", "remote", "set-url", "origin", original_url },
              dir,
              function()
                vim.notify("autosaver: git push failed (tried both SSH and HTTPS) - " .. retry_output, vim.log.levels.ERROR)
                current_job = nil
                process_queue()
              end
            )
          end
        end
      )
    end
  )
end

-- Queue a save operation
local function queue_save(filepath, filename, dir)
  -- Cancel existing debounce timer
  if debounce_timer then
    debounce_timer:stop()
    debounce_timer = nil
  end

  -- Create debounce timer
  debounce_timer = vim.defer_fn(function()
    table.insert(save_queue, {
      filepath = filepath,
      filename = filename,
      dir = dir,
      timestamp = get_timestamp(),
    })

    -- Start processing if not already running
    if not current_job then
      process_queue()
    end

    debounce_timer = nil
  end, M.config.debounce_ms)
end

-- Main auto-save function (non-blocking)
local function autosave_markdown()
  if not M.config.enabled then return end

  local filepath = vim.fn.expand("%:p")
  local filename = vim.fn.expand("%:t")
  local dir = vim.fn.expand("%:p:h")

  -- Check if file matches pattern (default: .md files)
  if not filename:match(M.config.file_pattern) then
    return
  end

  -- Check if file exists and is in a git repo
  if vim.fn.filereadable(filepath) == 0 then
    return
  end

  if not is_git_repo(dir) then
    return  -- Silent fail if not in repo
  end

  -- Save the file first (sync, but fast)
  vim.cmd("silent! write")

  -- Queue the git operations (async)
  queue_save(filepath, filename, dir)
end

-- Enable the plugin
function M.enable()
  M.config.enabled = true
end

-- Disable the plugin
function M.disable()
  M.config.enabled = false
end

-- Setup function for user configuration
function M.setup(opts)
  -- Merge user configuration with defaults
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

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

  vim.api.nvim_create_user_command("AutoSaverStatus", function()
    local status = M.config.enabled and "enabled" or "disabled"
    local queue_size = #save_queue
    local is_running = current_job and "yes" or "no"
    vim.notify(string.format(
      "autosaver: %s | Queue: %d | Running: %s",
      status, queue_size, is_running
    ), vim.log.levels.INFO)
  end, {})
end

return M

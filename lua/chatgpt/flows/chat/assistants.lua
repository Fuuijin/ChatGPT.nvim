local pickers = require("telescope.pickers")
local previewers = require("telescope.previewers")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local conf = require("telescope.config").values
local job = require("plenary.job")

local Utils = require("chatgpt.utils")
local Config = require("chatgpt.config")
local Api = require("chatgpt.api")

local display_content_wrapped = Utils.defaulter(function(_)
  return previewers.new_buffer_previewer({
    define_preview = function(self, entry, status)
      local width = vim.api.nvim_win_get_width(self.state.winid)
      entry.preview_command(entry, self.state.bufnr, width)
    end,
  })
end, {})

local function preview_command(entry, bufnr, width)
  vim.api.nvim_buf_call(bufnr, function()
    local preview = Utils.wrapTextToTable(entry.information.instructions, width - 5)
    table.insert(preview, 1, "Instructions:")
    table.insert(preview, 1, "Name: " .. entry.information.name)
    table.insert(preview, 1, "Id: " .. entry.information.id)
    table.insert(preview, 1, "Model: " .. entry.information.model)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, preview)
  end)
end

local function entry_maker(entry)
  return {
    display = entry.name,
    value = entry.id,
    information = {
      id = entry.id,
      name = entry.name,
      instructions = entry.instructions,
      model = entry.model,
    },
    ordinal = entry.id,
    preview_command = preview_command,
  }
end

local finder = function(opts)
  local job_started = false
  local job_completed = false
  local results = {}
  local num_results = 0

  return setmetatable({
    close = function()
      -- TODO: check if we need to make some cleanup
    end,
  }, {
    __call = function(_, prompt, process_result, process_complete)
      if job_completed then
        local current_count = num_results
        for index = 1, current_count do
          if process_result(results[index]) then
            break
          end
        end
        process_complete()
      end

      if not job_started then
        job_started = true
        job
          :new({
            command = "curl",
            args = {
              Api.ASSISTANTS_URL,
              "-H",
              "Content-Type: application/json",
              "-H",
              Api.AUTHORIZATION_HEADER,
              "-H",
              "OpenAI-Beta: assistants=v1",
            },
            on_exit = vim.schedule_wrap(function(j, exit_code)
              if exit_code ~= 0 then
                vim.notify("An Error Occurred, cannot fetch list of prompts ...", vim.log.levels.ERROR)
                process_complete()
              end

              local parsed_response = vim.fn.json_decode(table.concat(j:result(), "\n"))

              local lines = {}

              for _, entry in ipairs(parsed_response.data) do
                if entry.name then -- Only include entries with a name
                  local v = entry_maker(entry)
                  num_results = num_results + 1
                  results[num_results] = v
                  process_result(v)
                  table.insert(lines, entry_maker(entry))
                end
              end

              process_complete()
              job_completed = true
            end),
          })
          :start()
      end
    end,
  })
end
--

local M = {}
function M.selectAssistant(opts)
  opts = opts or {}
  pickers
    .new(opts, {
      sorting_strategy = "ascending",
      layout_config = {
        height = 0.5,
      },
      results_title = "ChatGPT Assistants...",
      prompt_prefix = Config.options.popup_input.prompt,
      selection_caret = Config.options.chat.answer_sign .. " ",
      prompt_title = "Prompt",
      finder = finder(),
      sorter = conf.generic_sorter(opts),
      previewer = display_content_wrapped.new({}),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          opts.cb(selection.display, selection.value)
        end)
        return true
      end,
    })
    :find()
end

return M

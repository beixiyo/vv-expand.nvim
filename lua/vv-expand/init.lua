-- vv-expand: 智能增量选区
-- 扩张优先级: pair(本行 ([{<"'`*_- 等成对字符) → LSP selectionRange → treesitter 父节点 → 行
-- 初始化/扩张同键 (<CR>)，收缩另一键 (<BS>)，与 wildfire 用法一致

local R = require('vv-expand.range')
local layers = require('vv-expand.layers')

local M = {}

---@class ExpandConfig
---@field pairs { same: string[], nested: string[][] } 参与匹配的字符对；same 为同字符成对，nested 为开闭不同对
---@field layers ('pair'|'lsp'|'treesitter'|'line'|'word')[] 扩张层级顺序，先命中先用
---@field keymaps { init?: string, expand?: string, shrink?: string } 按键映射
---@field filetype_exclude string[] 不启用的 filetype 列表
---@field lsp_timeout integer LSP selectionRange 同步请求超时 (ms)
local defaults = {
  pairs = {
    same = { '"', "'", '`', '*', '_', '-' },
    nested = {
      { '(', ')' },
      { '[', ']' },
      { '{', '}' },
      { '<', '>' },
    },
  },
  layers = { 'word', 'pair', 'lsp', 'treesitter', 'line' },
  keymaps = {
    init = '<CR>',
    expand = '<CR>',
    shrink = '<BS>',
  },
  -- 'vv-explorer' 和 'vv-task-panel' 是作者的其他插件，未安装时会被安全忽略
  filetype_exclude = { 'qf', 'help', 'dashboard', 'vv-explorer', 'vv-task-panel' },
  lsp_timeout = 400,
}

M.config = defaults

-- 每 buffer 独立的选区历史栈
local stacks = {}

local function get_stack(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  stacks[buf] = stacks[buf] or {}
  return stacks[buf]
end

local function excluded_ft(ft)
  ft = ft or vim.bo.filetype
  for _, f in ipairs(M.config.filetype_exclude) do
    if f == ft then return true end
  end
  return false
end

function M.expand()
  if excluded_ft() then return end
  local cur = R.get_cur()
  local stack = get_stack()
  -- 与栈顶不一致（用户手动改了选区）→ 重置栈
  if #stack == 0 or not R.eq(stack[#stack], cur) then
    stack = {}
    stacks[vim.api.nvim_get_current_buf()] = stack
    stack[#stack + 1] = cur
  end

  local next_range
  for _, name in ipairs(M.config.layers) do
    local fn = layers[name]
    if fn then
      local r = fn(cur, M.config)
      if r and R.contains_strict(r, cur) then
        next_range = r
        break
      end
    end
  end
  if not next_range then return end
  stack[#stack + 1] = next_range
  R.set_visual(next_range)
end

function M.shrink()
  if excluded_ft() then return end
  local stack = get_stack()
  if #stack <= 1 then return end
  table.remove(stack)
  local prev = stack[#stack]
  if not prev then return end
  if prev[1] == prev[3] and prev[2] == prev[4] then
    if vim.fn.mode():match('[vV\22]') then vim.cmd('normal! \27') end
    vim.api.nvim_win_set_cursor(0, { prev[1], math.max(0, prev[2] - 1) })
  else
    R.set_visual(prev)
  end
end

function M.init()
  if excluded_ft() then return end
  stacks[vim.api.nvim_get_current_buf()] = {}
  M.expand()
end

local function install_keymaps(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local k = M.config.keymaps
  local function map(mode, lhs, fn, desc)
    if not lhs then return end
    vim.keymap.set(mode, lhs, fn, { buffer = buf, silent = true, desc = desc })
  end
  map('n', k.init, M.init, 'Expand: init selection')
  map('x', k.expand, M.expand, 'Expand: expand')
  map('x', k.shrink, M.shrink, 'Expand: shrink')
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', defaults, opts or {})

  local group = vim.api.nvim_create_augroup('VVExpand', { clear = true })
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    callback = function(ev)
      if excluded_ft(vim.bo[ev.buf].filetype) then return end
      install_keymaps(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = group,
    callback = function(ev) stacks[ev.buf] = nil end,
  })
  -- 懒加载时已打开的 buffer：补装 keymap
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local ft = vim.bo[buf].filetype
      if ft ~= '' and not excluded_ft(ft) then
        install_keymaps(buf)
      end
    end
  end
end

return M

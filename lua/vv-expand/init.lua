-- vv-expand: 智能增量选区
-- 扩张优先级: pair(本行 ([{<"'`*_- 等成对字符) → LSP selectionRange → treesitter 父节点 → 行
-- 初始化/扩张同键 (<CR>)，收缩另一键 (<BS>)，与 wildfire 用法一致

local R = require('vv-expand.range')
local layers = require('vv-expand.layers')

local M = {}

---@class VVExpandConfig
---@field pairs { same: string[], nested: string[][] } 参与匹配的字符对；same 为同字符成对，nested 为开闭不同对 @default { same = { '"', "'", '`', '*', '_', '-' }, nested = { ... } }
---@field layers ('pair'|'lsp'|'treesitter'|'line'|'word')[] 扩张层级顺序，先命中先用 @default { 'word', 'pair', 'lsp', 'treesitter', 'line' }
---@field keymaps { init?: string, expand?: string, shrink?: string } 按键映射 @default { init = '<CR>', expand = '<CR>', shrink = '<BS>' }
---@field filetype_exclude string[] 不启用的 filetype 列表 @default { 'qf', 'help', 'dashboard', 'vv-explorer', 'vv-task-panel', 'vv-task-panel-tasks' }
---@field subword_delimiters? string 逐段扩张的分隔符字符集；nil 则禁用逐段、直接 iw → iW @default '-=+/:;|,.?\\!@#$%^&*~'
---@field lsp_timeout integer LSP selectionRange 同步请求超时 (ms) @default 400
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
  subword_delimiters = '-=+/:;|,.?\\!@#$%^&*~',
  -- vv-* 是作者的其他插件，未安装时会被安全忽略
  filetype_exclude = {
    'qf', 'help', 'dashboard', 'vv-explorer',
    'vv-task-panel', 'vv-task-panel-tasks',
    'TelescopePrompt',
  },
  lsp_timeout = 400,
}

local config = defaults

-- 每 buffer 独立的选区历史栈
local stacks = {}
local owned_keymaps = {}

---@param buf integer
---@param mode string
---@param lhs string
---@return table?
local function get_buffer_keymap(buf, mode, lhs)
  local target = vim.fn.keytrans(vim.keycode(lhs))
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
    if vim.fn.keytrans(vim.keycode(mapping.lhs)) == target then return mapping end
  end
end

---@param buf integer
---@param mode string
---@param lhs string
---@param mapping table?
local function restore_buffer_keymap(buf, mode, lhs, mapping)
  if not mapping then
    pcall(vim.api.nvim_buf_del_keymap, buf, mode, lhs)
    return
  end

  local opts = {
    noremap = mapping.noremap == 1,
    silent = mapping.silent == 1,
    expr = mapping.expr == 1,
    nowait = mapping.nowait == 1,
    script = mapping.script == 1,
    desc = mapping.desc,
    replace_keycodes = mapping.replace_keycodes == 1,
  }
  if mapping.callback then opts.callback = mapping.callback end
  vim.api.nvim_buf_set_keymap(buf, mode, lhs, mapping.rhs or '', opts)
end

---@param buf integer
local function clear_keymaps(buf)
  local owned = owned_keymaps[buf]
  if not owned then return end

  for _, mapping in pairs(owned) do
    local current = get_buffer_keymap(buf, mapping.mode, mapping.lhs)
    if current
        and current.callback == mapping.callback
        and current.desc == mapping.desc
    then
      restore_buffer_keymap(buf, mapping.mode, mapping.lhs, mapping.previous)
    end
  end
  owned_keymaps[buf] = nil
end

local function get_stack(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  stacks[buf] = stacks[buf] or {}
  return stacks[buf]
end

local function excluded_ft(ft)
  ft = ft or vim.bo.filetype
  for _, f in ipairs(config.filetype_exclude) do
    if f == ft then return true end
  end
  return false
end

function M.expand()
  if excluded_ft() then return end
  -- blockwise visual (Ctrl-V) 没有良定义的「扩张」语义，且 set_visual 会把它静默转成 charwise
  -- 字符可视选区（块状选择丢失）。keymap 绑在 'x' 模式含块选，这里直接不处理、保留原选区
  if vim.fn.mode() == '\22' then return end
  local cur = R.get_cur()
  local stack = get_stack()
  -- 与栈顶不一致（用户手动改了选区）→ 重置栈
  if #stack == 0 or not R.eq(stack[#stack], cur) then
    stack = {}
    stacks[vim.api.nvim_get_current_buf()] = stack
    stack[#stack + 1] = cur
  end

  local next_range
  for _, name in ipairs(config.layers) do
    local fn = layers[name]
    if fn then
      local r = fn(cur, config)
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
  -- blockwise visual (Ctrl-V) 同 expand：不处理，避免把块选静默转成 charwise
  if vim.fn.mode() == '\22' then return end
  local stack = get_stack()
  if #stack <= 1 then return end
  -- 与栈顶不一致（用户手动改了选区）→ 这不是扩张历史的一部分，放手不处理
  if not R.eq(stack[#stack], R.get_cur()) then return end
  table.remove(stack)
  local prev = stack[#stack]
  if not prev then return end

  -- 中途编辑过 buffer 可能让栈里记录的绝对行号越界，越界则丢弃整栈，
  -- 让下一次 gv/expand 从实时选区重新播种，避免 nvim_win_set_cursor 抛 'Invalid cursor line'
  local n = vim.api.nvim_buf_line_count(0)
  if prev[1] > n or prev[3] > n then
    stacks[vim.api.nvim_get_current_buf()] = {}
    return
  end

  local ok = pcall(function()
    if prev[1] == prev[3] and prev[2] == prev[4] then
      if vim.fn.mode():match('[vV\22]') then vim.cmd('normal! \27') end
      vim.api.nvim_win_set_cursor(0, { prev[1], math.max(0, prev[2] - 1) })
    else
      R.set_visual(prev)
    end
  end)
  if not ok then
    stacks[vim.api.nvim_get_current_buf()] = {}
  end
end

function M.init()
  if excluded_ft() then return end
  stacks[vim.api.nvim_get_current_buf()] = {}
  M.expand()
end

local function install_keymaps(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local k = config.keymaps
  local function map(mode, lhs, fn, desc)
    if not lhs then return end

    local key = mode .. '\0' .. vim.fn.keytrans(vim.keycode(lhs))
    local callback = function() fn() end
    owned_keymaps[buf] = owned_keymaps[buf] or {}
    local claim = owned_keymaps[buf][key]

    -- expand/shrink 可以共用同一 visual lhs：第一次 claim 保存 setup 前映射，
    -- 后续安装只更新当前所有权，不能把插件自己的上一版误记为 original。
    if not claim then
      claim = {
        mode = mode,
        lhs = lhs,
        previous = get_buffer_keymap(buf, mode, lhs),
      }
      owned_keymaps[buf][key] = claim
    end

    vim.keymap.set(mode, lhs, callback, { buffer = buf, silent = true, desc = desc })
    claim.lhs = lhs
    claim.callback = callback
    claim.desc = desc
  end
  map('n', k.init, M.init, 'Expand: init selection')
  map('x', k.expand, M.expand, 'Expand: expand')
  map('x', k.shrink, M.shrink, 'Expand: shrink')
end

function M.setup(opts)
  for buf in pairs(owned_keymaps) do
    if vim.api.nvim_buf_is_valid(buf) then clear_keymaps(buf) end
  end

  config = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})

  local group = vim.api.nvim_create_augroup('VVExpand', { clear = true })
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    callback = function(ev)
      clear_keymaps(ev.buf)
      if excluded_ft(vim.bo[ev.buf].filetype) then return end
      install_keymaps(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = group,
    callback = function(ev)
      stacks[ev.buf] = nil
      owned_keymaps[ev.buf] = nil
    end,
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

  vim.api.nvim_create_user_command('VVExpandInit', function() M.init() end, {})
  vim.api.nvim_create_user_command('VVExpandExpand', function() M.expand() end, {})
  vim.api.nvim_create_user_command('VVExpandShrink', function() M.shrink() end, {})
end

---获取当前配置（只读副本）
---@return VVExpandConfig
function M.get_config()
  return vim.deepcopy(config)
end

return M

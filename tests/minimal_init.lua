local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fs.normalize(vim.fn.fnamemodify(source, ":p:h:h"))

vim.opt.runtimepath:prepend(root)
vim.opt.shadafile = "NONE"
vim.opt.swapfile = false
vim.opt.writebackup = false

package.path = table.concat({
  root .. "/?.lua",
  root .. "/?/init.lua",
  package.path,
}, ";")

if vim.env.PLENARY_PATH and vim.env.PLENARY_PATH ~= "" then
  vim.opt.runtimepath:append(vim.env.PLENARY_PATH)
end

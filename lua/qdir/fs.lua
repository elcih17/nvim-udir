local uv = vim.loop
local u = require("qdir.util")
local M = {}
local function assert_readable(path)
  assert((nil ~= path), string.format("Missing argument %s on %s:%s", "path", "lua/qdir/fs.fnl", 6))
  assert(uv.fs_access(path, "R"))
  return nil
end
local function assert_doesnt_exist(path)
  assert((nil ~= path), string.format("Missing argument %s on %s:%s", "path", "lua/qdir/fs.fnl", 10))
  assert(not uv.fs_access(path, "R"), string.format("%q already exists", path))
  return nil
end
local function delete_file(path)
  assert((nil ~= path), string.format("Missing argument %s on %s:%s", "path", "lua/qdir/fs.fnl", 14))
  assert(uv.fs_unlink(path))
  return u["delete-buffer"](path)
end
local function delete_dir(path)
  assert((nil ~= path), string.format("Missing argument %s on %s:%s", "path", "lua/qdir/fs.fnl", 18))
  local fs = assert(uv.fs_scandir(path))
  local done_3f = false
  while not done_3f do
    local name, type = uv.fs_scandir_next(fs)
    if not name then
      done_3f = true
    elseif "else" then
      if (type == "directory") then
        delete_dir(u["join-path"](path, name))
      elseif "else" then
        delete_file(u["join-path"](path, name))
      end
    end
  end
  return assert(uv.fs_rmdir(path))
end
M.canonicalize = function(path)
  assert((nil ~= path), string.format("Missing argument %s on %s:%s", "path", "lua/qdir/fs.fnl", 32))
  return assert(uv.fs_realpath(path))
end
M["is-dir?"] = function(path)
  assert((nil ~= path), string.format("Missing argument %s on %s:%s", "path", "lua/qdir/fs.fnl", 36))
  assert_readable(path)
  local file_info = uv.fs_stat(path)
  return (file_info.type == "directory")
end
M.list = function(path)
  assert((nil ~= path), string.format("Missing argument %s on %s:%s", "path", "lua/qdir/fs.fnl", 41))
  local fs = assert(uv.fs_scandir(path))
  local ret = {}
  local done_3f = false
  while not done_3f do
    local name, type, err_name = uv.fs_scandir_next(fs)
    if (name == nil) then
      done_3f = true
      assert(not type)
    else
      table.insert(ret, {name = name, type = type})
    end
  end
  return ret
end
M["get-parent-dir"] = function(dir)
  assert((nil ~= dir), string.format("Missing argument %s on %s:%s", "dir", "lua/qdir/fs.fnl", 58))
  local parent_dir = M.canonicalize((dir .. u.sep .. ".."))
  assert_readable(parent_dir)
  return parent_dir
end
M.basename = function(path)
  assert((nil ~= path), string.format("Missing argument %s on %s:%s", "path", "lua/qdir/fs.fnl", 64))
  local path_without_trailing_slash
  if vim.endswith(path, u.sep) then
    path_without_trailing_slash = path:sub(1, -2)
  else
    path_without_trailing_slash = path
  end
  local split = vim.split(path_without_trailing_slash, u.sep)
  return split[#split]
end
M.delete = function(path)
  assert((nil ~= path), string.format("Missing argument %s on %s:%s", "path", "lua/qdir/fs.fnl", 70))
  if M["is-dir?"](path) then
    delete_dir(path)
  elseif "else" then
    delete_file(path)
  end
  return nil
end
M["create-dir"] = function(path)
  assert((nil ~= path), string.format("Missing argument %s on %s:%s", "path", "lua/qdir/fs.fnl", 75))
  assert_doesnt_exist(path)
  local mode = tonumber("755", 8)
  assert(uv.fs_mkdir(path, mode))
  return nil
end
M["create-file"] = function(path)
  assert((nil ~= path), string.format("Missing argument %s on %s:%s", "path", "lua/qdir/fs.fnl", 82))
  assert_doesnt_exist(path)
  local mode = tonumber("644", 8)
  assert(uv.fs_open(path, "w", mode))
  return nil
end
M.rename = function(path, newpath)
  assert((nil ~= newpath), string.format("Missing argument %s on %s:%s", "newpath", "lua/qdir/fs.fnl", 89))
  assert((nil ~= path), string.format("Missing argument %s on %s:%s", "path", "lua/qdir/fs.fnl", 89))
  assert_doesnt_exist(newpath)
  assert(uv.fs_rename(path, newpath))
  return nil
end
return M

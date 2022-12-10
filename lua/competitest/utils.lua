local luv = vim.loop
local M = {}

---Show a CompetiTest notification with vim.notify()
---@param msg string: message to display
---@param log_level string | nil: a log level among the ones available in vim.log.levels. When nil it defaults to ERROR
function M.notify(msg, log_level)
	vim.notify("CompetiTest.nvim: " .. msg, vim.log.levels[log_level or "ERROR"], { title = "CompetiTest" })
end

-- CompetiTest strings modifiers
-- They can be strings or function accepting up to one argument, the absolute file path
M.modifiers = {
	-- $(): replace it with a dollar
	[""] = "$",

	-- $(HOME): home user directory
	["HOME"] = function()
		return luv.os_homedir()
	end,

	-- $(FNAME): file name
	["FNAME"] = function(filepath)
		return vim.fn.fnamemodify(filepath, ":t")
	end,

	-- $(FNOEXT): file name without extension
	["FNOEXT"] = function(filepath)
		return vim.fn.fnamemodify(filepath, ":t:r")
	end,

	-- $(FEXT): file extension
	["FEXT"] = function(filepath)
		return vim.fn.fnamemodify(filepath, ":e")
	end,

	-- $(FABSPATH): absolute path of current file
	["FABSPATH"] = function(filepath)
		return filepath
	end,

	-- $(ABSDIR): absolute path of folder that contains file
	["ABSDIR"] = function(filepath)
		return vim.fn.fnamemodify(filepath, ":p:h")
	end,

	-- $(TCNUM): testcase number; it will be set later
	["TCNUM"] = nil,
}

---Convert a string with CompetiTest modifiers into a formatted string
---@param filepath string: absolute file path, to evaluate string from
---@param str string: the string to evaluate
---@param tcnum integer | string | nil: testcase number or identifier
---@return string | nil: the converted string, or nil on failure
function M.eval_string(filepath, str, tcnum)
	M.modifiers["TCNUM"] = tostring(tcnum or "") -- testcase number

	local evaluated_str = {}
	local mod_start = 0 -- modifier starting position (0 means idle state)
	for i = 1, #str do
		local c = string.sub(str, i, i) -- current character
		if mod_start == -1 then -- if mod_start is -1 an opening parentheses is expected because a dollar was just encountered
			if c == "(" then
				mod_start = i
			else
				M.notify("eval_string: '$' isn't followed by '(' in the following string!\n" .. str)
				return nil
			end
		elseif mod_start == 0 then
			if c == "$" then
				mod_start = -1 -- wait for parentheses
			else
				table.insert(evaluated_str, c)
			end
		elseif mod_start ~= 0 and c == ")" then
			local mod = string.sub(str, mod_start + 1, i - 1)
			local replacement = M.modifiers[mod]
			if type(replacement) == "string" then
				table.insert(evaluated_str, replacement)
			elseif type(replacement) == "function" then
				table.insert(evaluated_str, replacement(filepath))
			else
				M.notify("eval_string: unrecognized modifier $(" .. mod .. ")")
				return nil
			end
			mod_start = 0
		end
	end

	return table.concat(evaluated_str)
end

---Convert a string with CompetiTest modifiers into a formatted string, but considering the given buffer
---@param bufnr integer: buffer number, representing the buffer to evaluate string from
---@param str string: the string to evaluate
---@param tcnum integer | string | nil: testcase number or identifier
---@return string | nil: the converted string, or nil on failure
function M.buf_eval_string(bufnr, str, tcnum)
	return M.eval_string(vim.api.nvim_buf_get_name(bufnr), str, tcnum)
end

---Return true if the given file exists, otherwise false
---@param filepath string
---@return boolean
function M.does_file_exist(filepath)
	return luv.fs_stat(filepath) ~= nil
end

---This function returns the content of the specified file as a string, or nil if the given path is invalid
---@param filepath string
---@return string | nil
function M.load_file_as_string(filepath)
	local fd = luv.fs_open(filepath, "r", 438)
	if fd == nil then
		return nil
	end
	local stat = assert(luv.fs_fstat(fd), "CompetiTest.nvim: load_file_as_string: cannot stat file '" .. filepath .. "'")
	local content = assert(luv.fs_read(fd, stat.size, 0), "CompetiTest.nvim: load_file_as_string: cannot read file '" .. filepath .. "'")
	assert(luv.fs_close(fd), "CompetiTest.nvim: load_file_as_string: unable to close '" .. filepath .. "'")
	return string.gsub(content, "\r\n", "\n") -- convert CRLF to LF
end

---Create the specified directory if it doesn't exist
---@param dirpath string: directory absolute path
function M.create_directory(dirpath)
	if not luv.fs_opendir(dirpath) then
		dirpath = string.gsub(dirpath, "[/\\]+$", "") -- trim trailing slashes
		local upper_dir = vim.fn.fnamemodify(dirpath, ":h")
		if upper_dir ~= dirpath then
			M.create_directory(upper_dir)
		end
		assert(luv.fs_mkdir(dirpath, 493), "CompetiTest.nvim: create_directory: cannot create directory '" .. dirpath .. "'")
	end
end

---Write the content of the given string on a file
---@param filepath string
---@param content string
function M.write_string_on_file(filepath, content)
	M.create_directory(vim.fn.fnamemodify(filepath, ":h"))
	local fd = assert(luv.fs_open(filepath, "w", 420), "CompetiTest.nvim: write_string_on_file: cannot open file '" .. filepath .. "'")
	assert(luv.fs_write(fd, content, 0), "CompetiTest.nvim: write_string_on_file: cannot write on file '" .. filepath .. "'")
	assert(luv.fs_close(fd), "CompetiTest.nvim: write_string_on_file: unable to close '" .. filepath .. "'")
end

---Delete the given file
---@param filepath string
function M.delete_file(filepath)
	assert(luv.fs_unlink(filepath), "CompetiTest.nvim: delete_file: cannot delete file '" .. filepath .. "'")
end

---Get Neovim UI width and height
---@return integer: width, number of columns
---@return integer: height, number of rows
function M.get_ui_size()
	local height = vim.o.lines - vim.o.cmdheight
	if vim.o.laststatus ~= 0 then
		height = height - 1
	end
	return vim.o.columns, height
end

return M

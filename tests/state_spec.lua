-- tests/state_spec.lua
local state = require("colorful-times.state")

describe("state.path", function()
	it("returns a string ending in state.json", function()
		assert.is_truthy(state.path():match("state%.json$"))
	end)
end)

describe("state.load", function()
	it("returns {} for non-existent file", function()
		local orig_path = state.path
		state.path = function()
			return "/tmp/ct_test_nonexistent_" .. os.time() .. ".json"
		end
		assert.are.same({}, state.load())
		state.path = orig_path
	end)

	it("returns {} on parse error", function()
		local tmp = os.tmpname()
		local f = io.open(tmp, "w")
		f:write("not json!!")
		f:close()
		local orig_path = state.path
		state.path = function()
			return tmp
		end
		assert.are.same({}, state.load())
		state.path = orig_path
		os.remove(tmp)
	end)

	it("parses valid JSON", function()
		local tmp = os.tmpname()
		local f = io.open(tmp, "w")
		f:write(vim.json.encode({ enabled = false, schedule = {} }))
		f:close()
		local orig_path = state.path
		state.path = function()
			return tmp
		end
		local result = state.load()
		state.path = orig_path
		os.remove(tmp)
		assert.is_false(result.enabled)
	end)
end)

describe("state.save and state.load roundtrip", function()
	it("saves and reloads data correctly", function()
		local tmp = os.tmpname()
		os.remove(tmp) -- ensure file doesn't exist yet
		local dir = tmp .. "_dir"
		vim.fn.mkdir(dir, "p")
		local file = dir .. "/state.json"

		local orig_path = state.path
		state.path = function()
			return file
		end

		local data = {
			enabled = true,
			schedule = {
				{ start = "06:00", stop = "18:00", colorscheme = "tokyonight-day", background = "light" },
			},
		}
		state.save(data)
		local loaded = state.load()
		state.path = orig_path

		vim.fn.delete(dir, "rf")

		assert.is_true(loaded.enabled)
		assert.are.equal(1, #loaded.schedule)
		assert.are.equal("tokyonight-day", loaded.schedule[1].colorscheme)
	end)
end)

describe("state.merge", function()
	local base = {
		enabled = true,
		schedule = { { start = "06:00", stop = "18:00", colorscheme = "base" } },
		default = { colorscheme = "default", background = "system" },
	}

	it("stored schedule wins over base", function()
		local result = state.merge(vim.deepcopy(base), {
			schedule = { { start = "09:00", stop = "17:00", colorscheme = "stored" } },
		})
		assert.are.equal("stored", result.schedule[1].colorscheme)
	end)

	it("stored enabled wins over base", function()
		local result = state.merge(vim.deepcopy(base), { enabled = false })
		assert.is_false(result.enabled)
	end)

	it("missing schedule key in stored leaves base intact", function()
		local result = state.merge(vim.deepcopy(base), { enabled = false })
		assert.are.equal("base", result.schedule[1].colorscheme)
	end)

	it("empty schedule array [] wins (clears base schedule)", function()
		local result = state.merge(vim.deepcopy(base), { schedule = {} })
		assert.are.same({}, result.schedule)
	end)

	it("missing enabled key in stored leaves base enabled", function()
		local result = state.merge(vim.deepcopy(base), {})
		assert.is_true(result.enabled)
	end)

	it("non-schedule keys from base are preserved", function()
		local result = state.merge(vim.deepcopy(base), { enabled = false })
		assert.are.equal("default", result.default.colorscheme)
	end)
end)

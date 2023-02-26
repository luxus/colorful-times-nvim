local Observer = {}

function Observer:new()
	local observers = {}

	function observers:register(callback)
		table.insert(self, callback)
	end

	function observers:unregister(callback)
		for i = #self, 1, -1 do
			if self[i] == callback then
				table.remove(self, i)
			end
		end
	end

	function observers:notify(...)
		for _, callback in ipairs(self) do
			callback(...)
		end
	end

	return observers
end

return Observer

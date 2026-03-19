local iterations = 1000000

local function bench(name, fn)
    local start = os.clock()
    for i = 1, iterations do
        fn()
    end
    local duration = os.clock() - start
    print(string.format("%-30s: %.4f seconds", name, duration))
    return duration
end

print("Benchmarking get_current_time implementations (" .. iterations .. " iterations):")

bench("os.date('*t')", function()
    local date_table = os.date("*t")
    return (date_table.hour * 60) + date_table.min
end)

bench("os.date('%H') and os.date('%M')", function()
    return tonumber(os.date("%H")) * 60 + tonumber(os.date("%M"))
end)

bench("os.date('%H:%M') with match", function()
    local h, m = os.date("%H:%M"):match("(%d+):(%d+)")
    return tonumber(h) * 60 + tonumber(m)
end)

bench("os.date('%H%M') with tonumber", function()
    local hm = tonumber(os.date("%H%M"))
    return math.floor(hm / 100) * 60 + (hm % 100)
end)

-- Shared offline loader: one host TOC, one namespace, exact client order.
local Fixture = {}
local testsDir = (debug and debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")) or "./"
function Fixture.Load(dir, name, namespace, check)
	local file = assert(io.open(dir .. name .. ".toc", "r"))
	for line in file:lines() do
		local rel = line:gsub("\r", ""):match("^%s*([^#%s].-)%s*$")
		if rel and rel:match("%.lua$") then
			local chunk, err = loadfile(dir .. rel:gsub("\\", "/"))
			if check then check(chunk ~= nil, name .. " compile: " .. tostring(err)) else assert(chunk, err) end
			chunk(name, namespace)
		end
	end
	file:close()
	return namespace.Analytics
end
return Fixture

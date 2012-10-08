local file1 = io.open(arg[1], "r")
local file2 = io.open(arg[2], "w")

print("file1="..arg[1])
print("file2="..arg[2])

file2:write(file1:read("*a"))

file1:close()
file2:close()
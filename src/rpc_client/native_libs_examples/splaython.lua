require"splay.base"
require"python"
events.run(function()
	python.execute("import string")
	pg = python.globals()
	print(pg.string)
	print(pg.string.lower("Hello from Python!"))
	py_os = python.import("os")
	print("os.getcwd()",py_os.getcwd())
	print("os.uname",py_os.uname())
end)
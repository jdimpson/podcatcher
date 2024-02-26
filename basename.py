#!/usr/bin/python
import re

def basename(f, ext=None):
	f = re.sub(r'^.*/', '', f)
	if ext is not None:
		if ext == f[f.find(ext):]:
			f = re.sub(r'{}$'.format(ext), '', f)
	return f

def me():
	import sys
	return basename(sys.argv[0], ext=".py")

if __name__ == "__main__":
	print(me())

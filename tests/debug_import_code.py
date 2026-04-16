import sys, pkgutil
print('sys.path[0]=', sys.path[0])
loader = pkgutil.find_loader('code')
print('find_loader code =', loader)
try:
    import code as stdcode
    print('imported stdlib code module:', stdcode)
except Exception as e:
    print('import code failed:', e)
print('sys.path =', sys.path[:5])
print('cwd=', __import__('os').getcwd())

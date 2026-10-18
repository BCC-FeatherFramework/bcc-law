"""Run offline Lua 5.4 checks using the installed shared library; no packages needed."""
import ctypes
import ctypes.util
import os
import argparse
import json
import uuid
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--character-fixture', type=Path, help='JSON file with three existing character UUIDs; tests remain offline')
args = parser.parse_args()
if args.character_fixture:
    identities = json.loads(args.character_fixture.read_text())['characters']
    if len(identities) != 3 or len(set(identities)) != 3:
        raise SystemExit('Three distinct character UUIDs required.')
    for key, value in zip(('ACTOR', 'SUBJECT', 'OTHER'), identities):
        os.environ['FEATHER_TEST_' + key + '_UUID'] = str(uuid.UUID(value))
    print('Character UUID fixture loaded; all database/provider calls in the suite remain mocked.', flush=True)
root = Path(__file__).resolve().parents[1]
os.chdir(root)
library = ctypes.util.find_library('lua5.4')
if not library:
    raise SystemExit('Lua 5.4 shared library is required.')
lua = ctypes.CDLL(library)
lua.luaL_newstate.restype = ctypes.c_void_p
lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
lua.luaL_loadfilex.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
lua.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_longlong, ctypes.c_void_p]
lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_size_t)]
lua.lua_tolstring.restype = ctypes.c_char_p
lua.lua_close.argtypes = [ctypes.c_void_p]
for path in sorted(root.rglob('*.lua')):
    state = lua.luaL_newstate()
    try:
        if lua.luaL_loadfilex(state, os.fsencode(path), None):
            raise SystemExit(lua.lua_tolstring(state, -1, None).decode())
    finally:
        lua.lua_close(state)
state = lua.luaL_newstate()
try:
    lua.luaL_openlibs(state)
    error = lua.luaL_loadfilex(state, b'tests/run.lua', None)
    if not error:
        error = lua.lua_pcallk(state, 0, 0, 0, 0, None)
    if error:
        raise SystemExit(lua.lua_tolstring(state, -1, None).decode())
finally:
    lua.lua_close(state)

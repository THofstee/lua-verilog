local function gen_accessors(module)
   local accessors = {}
   for _,port in ipairs(module.ports) do
      local str = [[    int   get_?name(void* ?module_name);]]
      str = str:gsub("?name", port.name)
      accessors[#accessors+1] = str

      if port.direction ~= "output" then
         str = [[    void  set_?name(void* ?module_name, int ?name);]]
         str = str:gsub("?name", port.name)
         accessors[#accessors+1] = str
      end
   end
   return table.concat(accessors, '\n')
end

local getter = [[
int get_?name(void* _?module_name) {
    ?class_name* ?module_name = static_cast<?class_name*>(_?module_name);
    return ?module_name->?name;
}
]]

local setter = [[
void set_?name(void* _?module_name, int ?name) {
    ?class_name* ?module_name = static_cast<?class_name*>(_?module_name);
    ?module_name->?name = ?name;
}
]]

local function gen_accessor_impls(module)
   local accessors = {}
   for _,port in ipairs(module.ports) do
      accessors[#accessors+1] = getter:gsub("?name", port.name)

      if port.direction ~= "output" then
         accessors[#accessors+1] = setter:gsub("?name", port.name)
      end
   end
   return table.concat(accessors, '\n')
end

local lua_getter = [[
   get_?name = function(self)
      return lib.get_?name(self[1])
   end,
]]

local lua_setter = [[
   set_?name = function(self, ?name)
      lib.set_?name(self[1], ?name)
   end,
]]

local function gen_lua_accessors(module)
   local accessors = {}
   for _,port in ipairs(module.ports) do
      accessors[#accessors+1] = lua_getter:gsub("?name", port.name)

      if port.direction ~= "output" then
         accessors[#accessors+1] = lua_setter:gsub("?name", port.name)
      end
   end
   return table.concat(accessors, '\n')
end

local header = [[
#ifdef __cplusplus
extern "C" {
#endif

    int   sim_finish();

    void* new_?module_name();
    void* eval(void* ?module_name);
    void  final(void* ?module_name);

?accessors

#ifdef __cplusplus
}
#endif
]]

local impl = [[
#include "gen_interface.h"
#include <verilated.h>
#include "?class_name.h"

int sim_finish() {
    return Verilated::gotFinish();
}

void* new_?module_name() {
    return static_cast<void*>(new ?class_name);
}

void* eval(void* _?module_name) {
    ?class_name* ?module_name = static_cast<?class_name*>(_?module_name);
    ?module_name->eval();
}

void final(void*  _?module_name) {
    ?class_name* ?module_name = static_cast<?class_name*>(_?module_name);
    ?module_name->final();
    delete ?module_name;
}

?accessor_impls
]]

local lua = [[
local ffi = require 'ffi'

function read_file(file)
   local f = assert(io.open(file, "r"), "Could not open " .. file .. " for reading")
   local content = f:read("*a")
   f:close()
   return content
end

ffi.cdef(read_file("ffi-interface.h"))

local lib = ffi.load('obj_dir/lib?class_name.so')

sim = {}
function sim.finish()
   return lib.sim_finish() == 1
end

local ?module_name_inst_mt = {
   eval = function(self)
      lib.eval(self[1])
   end,
   final = function(self)
      lib.final(self[1])
   end,
?lua_accessors
}

?module_name_inst_mt.__index = function(self, idx)
   if not ?module_name_inst_mt[idx] then idx = 'get_' .. idx end
   return ?module_name_inst_mt[idx]
end

?module_name_inst_mt.__newindex = function(self, idx, val)
   local str = 'set_' .. idx
   if self[str] then
      self[str](self, val)
   end
end

local ?module_name_mt = {}
function ?module_name_mt.new()
   return setmetatable({ lib.new_?module_name() }, ?module_name_inst_mt)
end
?module_name_mt.__index = ?module_name_mt
?module_name = setmetatable({}, ?module_name_mt)

dofile("sim_main.lua")
]]

local function gen_ffi(module)
   local class_name = string.format("V%s", module.name)

   local header = header
   header = header:gsub("?accessors", gen_accessors(module))
   header = header:gsub("?class_name", class_name)
   header = header:gsub("?module_name", module.name)

   local impl = impl
   impl = impl:gsub("?accessor_impls", gen_accessor_impls(module))
   impl = impl:gsub("?class_name", class_name)
   impl = impl:gsub("?module_name", module.name)

   local lua = lua
   lua = lua:gsub("?lua_accessors", gen_lua_accessors(module))
   lua = lua:gsub("?class_name", class_name)
   lua = lua:gsub("?module_name", module.name)

   return header, impl, lua
end

local function interactive()
   return arg[0] == debug.getinfo(1, 'S').source:sub(2,-1)
end

if interactive() then
   local argparse = require 'argparse'
   local inspect = require 'inspect'

   local usage = {
      "Generates luajit ffi bindings to Verilator given a module.",
   }

   local parser = argparse("gen_ffi", table.concat(usage, '\n'))
   parser:argument("input", "Input file.")
   parser:option("-o --output", "Output file prefix.", "sim_interface")

   local args = parser:parse()
   local ext = args.input:match("[^.]+$")

   local ast
   if ext == 'lua' then
      ast = dofile(args.input)
   else
      package.path = "../?.lua;" .. package.path
      local parse = require 'parse_module'

      local i = assert(io.open(args.input, 'r'),
                       string.format("Can't open '%s' for reading.", args.input))

      local str = i:read('*a')
      ast = parse(str)
   end

   local function write_file(file, data)
      local f = assert(io.open(file, "w"), "Could not open " .. file .. " for writing")
      f:write(data)
      f:close()
   end

   local header, impl, lua = gen_ffi(ast)
   write_file(args.output .. ".h", header)
   write_file(args.output .. ".cpp", impl)
   write_file(args.output .. ".lua", lua)
end

return gen_ffi

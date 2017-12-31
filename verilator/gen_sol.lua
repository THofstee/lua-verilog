local includes = [[
#include "sol.hpp"
#include <verilated.h>
#include "?class_name.h"
]]

local header = [[
int main(int argc, char** argv, char** env) {
    sol::state lua;

    sol::table sim = lua.create_named_table("sim");
    sim["finish"] = (bool(*)())&Verilated::gotFinish;

]]

local body = [[
    lua.new_usertype<?class_name>(
        "?module_name",
        sol::constructors<?class_name()>(),
        "eval", &?class_name::eval,
        "final", &?class_name::final,
        ?ports
    );
]]

local footer = [[

    lua.script_file("sim_main.lua");
}
]]

local function gen_sol(module)
   local function gen_ports(module)
      local ports = {}
      for _,port in ipairs(module.ports) do
         local str
         if port.direction == "output" then
            str = [["?name", sol::readonly(&?class_name::?name)]]
         else
            str = [["?name", &?class_name::?name]]
         end

         str = str:gsub("?name", port.name)
         ports[#ports+1] = str
      end
      return table.concat(ports, ',\n        ')
   end

   local class_name = string.format("V%s", module.name)

   local sim_main = includes .. header .. body .. footer
   sim_main = sim_main:gsub("?ports", gen_ports(module))
   sim_main = sim_main:gsub("?class_name", class_name)
   sim_main = sim_main:gsub("?module_name", module.name)

   return sim_main
end

local function interactive()
   return arg[0] == debug.getinfo(1, 'S').source:sub(2,-1)
end

if interactive() then
   local argparse = require 'argparse'
   local inspect = require 'inspect'

   local usage = {
      "Generates sol2 bindings to Verilator given a module.",
   }

   local parser = argparse("gen_sol", table.concat(usage, '\n'))
   parser:argument("input", "Input file.")
   parser:option("-o --output", "Output file.", "sim_main.cpp")

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

   local f = assert(io.open(args.output, 'w'),
                    string.format("Can't open '%s' for writing.", args.output))

   f:write(gen_sol(ast))
end

return gen_sol

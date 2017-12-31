local re = require 're'

local parser = re.compile[[
top <- {| module |}

module <- 'module' %s+ {ident} %s* params? %s* {|ports?|} %s* ';' {|(%s* port_def)*|}

params <- '#' %s* '(' %s* param* %s* ')'
param <- 'parameter' %s+ ident %s* ('=' %s* const)? ';'

port_def <- {| port_info %s+ {ident} %s* ';' |}

ports <- '(' %s* port* %s* ')'
port <- {| {:(port_info %s+)?:} {ident} |}
      / ',' %s* port

port_info <- {| {dir} {:(%s+ {type})?:} {:(%s* {size})?:} |}

size <- '[' %s* const (%s* ':' %s* const)? %s* ']'

type <- 'logic'
      / 'reg'
      / 'wire'

dir <-'input'
     / 'output'
     / 'inout'

const <- [0-9]
ident <- [a-zA-Z_] [a-zA-Z0-9_$]*
]]

local function parse(str)
   local t = parser:match(str)

   if not t then
      assert(false, "Couldn't parse input file.")
   end

   local ports = {}
   for _,t2 in ipairs(t[2]) do
      local port = {
         direction = t2[1][1],
         type = t2[1][2],
         size = t2[1][3],
         name = t2[2],
      }
      table.insert(ports,port)
   end

   for _,t3 in ipairs(t[3]) do
      for _,port in ipairs(ports) do
         if port.name == t3[2] then
            port.direction = t3[1][1]
            port.type = t3[1][2]
            port.size = t3[1][3]
         end
      end
   end

   return {
      name = t[1],
      ports = ports,
   }
end

local function interactive()
   return arg[0] == debug.getinfo(1, 'S').source:sub(2,-1)
end

if interactive() then
   local argparse = require 'argparse'
   local inspect = require 'inspect'

   local usage = {
      "Parses verilog module definitions into a Lua table.",
      "The table can be passed into other utilities in this library",
      "",
      "Limitations:",
      "The desired module needs to be at the top of the file.",
      "Parameters are parsed but not captured.",
      "Data type sizes are assumed to be constant integers.",
   }

   local parser = argparse("parse_module", table.concat(usage, '\n'))
   parser:argument("input", "Input file.")
   parser:option("-o --output", "Output file.")
   local args = parser:parse()

   local f = io.stdout
   if args.output then
      f = assert(io.open(args.output, 'w'),
                 string.format("Can't open '%s' for writing.", args.output))
   end

   local i = assert(io.open(args.input, 'r'),
                    string.format("Can't open '%s' for reading.", args.input))

   local str = i:read('*a')
   f:write('return ')
   f:write(inspect(parse(str)))
end

return parse

---@class Common
local Common = {}

---@type boolean, Narrow
local libLoaded, Lib = pcall(require, "Narrow")
assert(libLoaded, "ERROR")
assert(Lib.GetVersion() >= 0.94, "ERROR")
Common.Lib = Lib

Common.Log = Lib.Utils.Logger.new("Narrow's navbot")

return Common

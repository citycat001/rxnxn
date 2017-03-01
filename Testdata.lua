local inputfile = assert(io.open("testinput.csv", "w"))
local targetfile = assert(io.open("testtargetfile.csv", "w"))

for i=1, 400 do
        for j = 1, 6 do
                for k = 1, 30 do
                        str = string.format("%d,", j)
                        str = string.rep(str, 109)
                        strcolumn = string.format("%s%d\n", str, j)
                        inputfile:write(strcolumn)
                end
        targetfile:write(string.format("%d\n", j))
        end
end

inputfile.close()
targetfile.close()

local valinfile = assert(io.open("validinput.csv", "w"))
local valtfile = assert(io.open("validargetfile.csv", "w"))

for i=1, 160 do
        for j = 1, 6 do
                for k = 1, 30 do
                        str = string.format("%d,", j)
                        str = string.rep(str, 109)
                        strcolumn = string.format("%s%d\n", str, j)
                        valinfile:write(strcolumn)
                end
        valtfile:write(string.format("%d\n", j))
        end
end

valinfile.close()
valtfile.close()

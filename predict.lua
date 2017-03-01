require 'nn'
require 'nngraph'
require 'dpnn'
require 'rnn'

local obj = torch.load("./torchtestsave.t7")
local lm = obj.model

print (lm)

local test = torch.Tensor(1, 30, 95)
test:fill(9)

local output = lm:forward(test)

--output of LogSoftMax is log-probability, need to take an exponent in order to get the probability output
print (output:exp())

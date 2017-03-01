require 'nn'
require 'rnn'
require 'paths'
local csv2tensor = require 'csv2tensor'
local dl = require 'dataload'

--Init parameters for RNN
--LSTM stack, has 3 FastLSTM components, hidden node sizes for each are 300, 300, 95
local hiddensize = {600, 600, 95}

--Inputsize parameter for FastLSTM, which is the column number of a single time-step.
local inputsize = 95

--6 Catagories for the results.
local nClass = 6

--Parallel Computing setting, how many channels are used
local batchsize = 32

--sequence length or time-step numbers
local rho = 30

--the number of the samples used for training
local trainsize = 2400

--the number of the samples used for validation
local validsize = 960

--learning rate or grad decending rate
local startlr = 0.05
local minlr = 0.0001
local lr = 0.05

--Repeatly using the same training samples for training, change the learning rate to find out the one has the least total error. the repeat time is:
local repeattrain = 40

--Total error init to a large number
local minvalppl = 99999999

--After a training with a certain learning rate, if the next 10 times re-training with other learning rates cannot have less total error, stop the training.
local earlystop = 20

--Object to contain the parameters and the training module and the training result, used to serialize the training, later can be used to predict.
local xplog = {}
xplog.hiddensize = hiddensize
xplog.inputsize = inputsize
xplog.nClass = nClass
xplog.batchsize = batchsize
xplog.rho = rho
xplog.trainsize = trainsize
xplog.validsize = validsize
xplog.startlr = startlr
xplog.minlr = minlr
xplog.dataset = 'TestTrading'

----------------------------------------------------------------------------
--Data processing
----------------------------------------------------------------------------
--single sample is a 30X95 metrix. Row 30 indicates time-steps/sequeunce, which is rho defined above, in trading scenario, it's time steps for 30 candles. 
--Column 95 is composed of 22 key data from 5 different charts(H4, H1, M30, M15, M5), based on current trading system.
--Put samples together into a single Tensor, the first dimension is the number of samples, second is time-steps/sequence which is the row number of a single sample, the third is the data size in one single time step which is the column number of a single sample.
local input, column_input = csv2tensor.load("/home/felix/luascripts/testinput.csv")
--local input = torch.randn(torch.LongStorage{trainsize, rho, inputsize})

--single sample in the end comes to a single catagory, so only has one number for target as class.
local target, column_target = csv2tensor.load("/home/felix/luascripts/testtargetfile.csv")
--local target = torch.LongTensor(trainsize):random(nClass)

--Prepare training data structure
dataloader = dl.TensorLoader(input:resize(trainsize, rho, inputsize), target)

--Validation sample loading, have the same dimensions as the training data
--local vinput = torch.randn(torch.LongStorage{validsize, rho, inputsize})
--local vtarget = torch.LongTensor(validsize):random(nClass)
local vinput, column_vinput = csv2tensor.load("/home/felix/luascripts/validinput.csv")
local vtarget, column_vtarget = csv2tensor.load("/home/felix/luascripts/validargetfile.csv")
validloader = dl.TensorLoader(vinput:resize(validsize, rho, inputsize), vtarget)

----------------------------------------------------------------------------
--Define RNN
----------------------------------------------------------------------------

--Add modules in RNN network
--define module, sequential mode
lm = nn.Sequential()

--Input layer, no change for the matrix
lm:add(nn.Identity())

--RNN layer
local stepmodule = nn.Sequential()
--LSTM stack with 3 layers
local iz = inputsize
for i, hz in ipairs(hiddensize) do
	local rnn
	require 'nngraph'
	nn.FastLSTM.usenngraph = true
	nn.FastLSTM.bn = false
	rnn = nn.FastLSTM(iz, hz)
	
	stepmodule:add(rnn)
	
	iz = hz
end

--Pooling matrix size from 30X95 to 1X95, so that it can be processed by categorizing engine.
stepmodule:add(nn.TemporalMaxPooling(rho))

--Linear mapping 95 nodes to 6 nodes, which matches 6 categories
stepmodule:add(nn.Linear(iz, nClass))

--LogSoftMax for categorizing preparation.
stepmodule:add(nn.LogSoftMax())

--Add mode for parallel computing on sequencial data
lm:add(nn.Sequencer(stepmodule))

--Remember previous state between batches, to maintain the relationship between batch samples
lm:remember()

--Multi classes classification
local criterion = nn.ClassNLLCriterion()
local crit = nn.SequencerCriterion(criterion)

--Serialize the rnn module
local serial = nn.Serial(lm)
print (serial)
xplog.model = serial
xplog.model:mediumSerial()
xplog.crit = crit
xplog.trainppl = {}
xplog.valppl = {}
xplog.minvalppl = minvalppl
xplog.epoch = 0

----------------------------------------------------------------------------
--Training
----------------------------------------------------------------------------
local epoch = 1
local ntrial = 0

while epoch <= repeattrain do
	print("")
	print("Epoch #"..epoch.." :")
	print ("Learning rate: "..lr.."")

	--1. training
	lm:training()
	print ("Start training")
	
	local sumErr = 0
	for i, inputs, targets in dataloader:sampleiter(batchsize, trainsize) do
		--Forward calculation for the output results based on the RNN network and predefined weights for all the nodes
		local outputs = lm:forward(inputs)
		--print (outputs)

		--Calculate error based on the difference between outputs and the expected target result
		local err = crit:forward(outputs, targets)
		sumErr = sumErr + err

		--Backward calculation for the partial error on each node of the outputs
		local gradOutputs = crit:backward(outputs, targets)
	
		--Init grad metrix to 0
		lm:zeroGradParameters()

		--Backward calculation for the differential of error on each node in hidden layers
		local gradInputs = lm:backward(inputs, gradOutputs)
	
		--learning rate or grad decending rate
		lm:updateParameters(lr)

		xlua.progress(math.min(i + rho, trainsize), trainsize)

		if i % trainsize == 0 then
			collectgarbage()
		end
	end
	lr = lr + (minlr - startlr)/repeattrain
	lr = math.max(minlr, lr)
	
	--calculate the total error of training for current training epoch
	local ppl = torch.exp(sumErr/trainsize)
	print ("Training PPL : "..ppl)

	xplog.trainppl[epoch] = ppl

	-- 2. cross-validation
	lm:evaluate()
	print ("Start evaluating")
	local sumErr = 0

	--calculate the total error of validation for current training epoch
	for j, vinputs, vtargets in validloader:subiter(batchsize, validsize) do
		local voutputs = lm:forward(vinputs)
		local err = crit:forward(voutputs, vtargets)
		sumErr = sumErr + err
		xlua.progress(math.min(j + rho, validsize), validsize)
	end

	local ppl = torch.exp(sumErr/validsize)
	print ("Validation PPL : "..ppl)
	
	xplog.valppl[epoch] = ppl
	ntrial = ntrial + 1

	--early-stopping
	if ppl < xplog.minvalppl then
		xplog.minvalppl = ppl
		xplog.epoch = epoch
		local filename = paths.concat("./", "torchtestsave"..'.t7')
		print("Found new minima. Saving to "..filename)
		--print(xplog)
		--serialize all the training parameters and training modules
		torch.save(filename, xplog)
		ntrial = 0
	elseif ntrial >= earlystop then
		print("No new minima found after "..ntrial.." epochs.")
		print("Stopping experiment.")
		break
	end		
	epoch = epoch + 1
	
	collectgarbage()
end


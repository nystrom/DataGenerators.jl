#
# Nested Monte Carlo Search choice model
#
# constructor usage:
#
#		NCMSChoiceModel(choicemodel, fitnessfn, samplesize)
#
# where:
#	 choicemodel is an instance of another choice model (e.g. SamplerChoiceModel) used for simulating the outcome of choices
#  fitnessfn is a fitness function that takes a generated object as a parameter and returns a fitness where lower values are better
#  samplesize is the number of choices to sample when deciding on the value of each choice point
#
# example:
#		scm = SamplerChoiceModel(gn)
#		f = abs(size(x)-64)
#		ncm = NMCSChoiceModel(scm, f, 2)
#
# To implement higher level NMCS, use an NMCS instance as the policy choice model.  For example:
#		ncm2 = NMCSChoiceModel(NMCSChoiceModel(scm,f,2),f,2)
# specifies a 2-level NMCS
# While a little verbose, this can allow different sample sizes at different levels (and even different fitness functions).
#

type NMCSChoiceModel <: ChoiceModel
	policychoicemodel::ChoiceModel
	fitnessfunction::Function
	samplesize::Int 									# the number of samples to take
	bestfitness::Real 								# lower is better
	bestgodelsequence::Vector{Real} 	# the best godel sequence found so far
	function NMCSChoiceModel(policychoicemodel::ChoiceModel, fitnessfunction::Function, samplesize::Int=1)
		new(deepcopy(policychoicemodel), fitnessfunction, samplesize, +Inf, [])
	end
end


function godelnumber(cm::NMCSChoiceModel, cc::ChoiceContext)
	for i in 1:cm.samplesize
		policychoicemodel = deepcopy(cm.policychoicemodel)
		generator = deepcopy(cc.derivationstate.generator)
		presetgodelsequence = deepcopy(cc.derivationstate.godelsequence)
		simulationcm = NMCSSimulationChoiceModel(policychoicemodel, presetgodelsequence)
		result, state = nothing, nothing
		try
			result, state = generate(generator; choicemodel=simulationcm, maxchoices=cc.derivationstate.maxchoices)
		catch e
		  if isa(e,GenerationTerminatedException)
				continue # skip the remainder of this loop
			else
				throw(e)
			end
		end
		fitness = cm.fitnessfunction(result)
		if fitness <= cm.bestfitness
			cm.bestfitness = fitness
			cm.bestgodelsequence = deepcopy(state.godelsequence)
		end
	end
	if length(cm.bestgodelsequence) <= length(cc.derivationstate.godelsequence)
		throw(GenerationTerminatedException("for all simulations made at a choice point in NMCS, the number of the choices made exceeded $(s.maxchoices): specify a larger value of maxchoices as a parameter to generate, or increase NMCS sample size "))
	end
	cm.bestgodelsequence[length(cc.derivationstate.godelsequence)+1]
end

setparams(cm::NMCSChoiceModel, params) = setparams(cm.policychoicemodel, params)
getparams(cm::NMCSChoiceModel) = getparams(cm.policychoicemodel)
paramranges(cm::NMCSChoiceModel) = paramranges(cm.policychoicemodel)

type NMCSSimulationChoiceModel <: ChoiceModel
	policychoicemodel::ChoiceModel
	presetgodelsequence::Vector{Real}
end

function godelnumber(cm::NMCSSimulationChoiceModel, cc::ChoiceContext)
	if isempty(cm.presetgodelsequence)
		godelnumber(cm.policychoicemodel, cc)
	else
		shift!(cm.presetgodelsequence)
	end
end
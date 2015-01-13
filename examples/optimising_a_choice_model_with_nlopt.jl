require("../src/GodelTest.jl")
using GodelTest
using NLopt

# generator for simple arithmetic expressions
@generator SimpleExprGen begin
  start = expression
  expression = operand * " " * operator * " " * operand
  operand = (choose(Bool) ? "-" : "") * join(plus(digit))
  digit = string(choose(Int,0,9))
  operator = "+"
  operator = "-"
  operator = "/"
  operator = "*"
end

# create a generator instance
gn = SimpleExprGen()

# create a choice model using the sampler choice model
cm = SamplerChoiceModel(gn)

# Number of expressions sampled when comparing different choice models
NumSamples = 10000

# Generate examples from unoptimized model
unoptimized_examples = [gen(gn, choicemodel=cm) for i in 1:NumSamples]

# Number of generated data items per fitness calculation
NumDataPerFitnessCalc = 12

# define a fitness function (here as a closure)
# argument is a vector of model parameters
function fitnessfn(modelparams)
	# sets parameters of choice model
	setparams(cm, vec(modelparams))  
	# get a sample of data items from the generator using this choice model
	exprs = [gen(gn, choicemodel=cm) for i in 1:NumDataPerFitnessCalc]
	# calculate the fitness - here the mean distance of the length expression from 16
	mean(map(expr->abs(16-length(expr)), exprs))
end

# optimise the choice model params with different NLopt algorithms
NLoptAlgs = [:LN_COBYLA, :LN_BOBYQA, :LN_NEWUOA, :LN_PRAXIS, :LN_NELDERMEAD, :LN_SBPLX]

# paramranges returns a vector of tuples that specify the valid ranges of the model parameters
search_range = paramranges(cm)
numparams = length(search_range)

run_nlopt(alg) = begin
  opt = Opt(:LN_NELDERMEAD, length(search_range))
  lower_bounds!(opt, map(first, search_range))
  upper_bounds!(opt, map((t) -> t[2], search_range))
  xtol_abs!(opt, 1e-8 * ones(numparams))
  maxtime!(opt, 10.0)
  min_objective!(opt, (x::Vector, grad::Vector) -> fitnessfn(x))
  rand_from_range(t) = t[1] + (t[2] - t[1]) * rand()
  rand_starting_point = map(rand_from_range, search_range)
  println("Running NLopt with algorithm $alg")
  optimresult = optimize(opt, rand_starting_point)
  bestmodelparams = optimresult[2]
end

results = Dict{Any, Any}()
for alg in NLoptAlgs
  bestmodelparams = run_nlopt(alg)

  # apply the best parameters found
  setparams(cm, vec(bestmodelparams))

  # generate data using the optimised model
  optimized_examples = [gen(gn, choicemodel=cm) for i in 1:NumSamples]

  results[alg] = optimized_examples
end

# Print examples so they can be compared
report(examples, desc) = begin
  mean_length = round(mean(map(length, examples)), 3)
  println("\n", desc, " examples (avg. length = $mean_length):\n", 
    examples[1:min(10, length(examples))])
end

report(unoptimized_examples, "Unoptimized")
for alg in NLoptAlgs
  report(results[alg], "Optimized (with NLopt $alg)")
end

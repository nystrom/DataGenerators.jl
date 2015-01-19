# tests sampler choice model

using GodelTest

@generator SCMGen begin # prefix SCM (for Sampler Choice Model) to avoid type name clashes
	start() = reps(a,1+1,2+2) # non-literal arguments to allow us to pass range to godelnumber during testing
	a() = choose(Int,-2-2,1+1)
	a() = choose(Float64,-2.0-2.0,1.0+1.0)
	a() = choose(Bool)
end

@generator SCMRepsGen begin
	start() = reps(a,1+1,2+2) # non-literal arguments to allow us to pass range to godelnumber during testing
	a() = 'a'
end

@generator SCMChooseBoolGen begin
	start() = choose(Bool) # 
end

@generator SCMChooseIntGen begin
	start() = choose(Int,-2-2,1+1) # non-literal arguments to allow us to pass range to godelnumber during testing
end

@generator SCMChooseFloat64Gen begin
	start() = choose(Float64,-2.0-2.0,1.0+1.0) # non-literal arguments to allow us to pass range to godelnumber during testing
end

@generator SCMRuleGen begin
	start() = x()
	x() = 'a'
	x() = 'b'
	x() = 'c'
	x() = 'd'
end

# internally will use range of choice points, so convenient for testing choice model when more than one choice point
@generator SCMChooseStringGen begin
	start() = choose(ASCIIString,"a(b|c)d+ef?")
end


describe("sampler choice model constructor") do

	test("constructor - generator as a parameter") do
		gn = SCMGen()
		cm = SamplerChoiceModel(gn)
		@check typeof(cm) == SamplerChoiceModel
	end

end

# basic tests of parameter functionality; more specific tests using single choice point generators below
describe("sampler choice model - set/get parameters and ranges") do

	gn = SCMGen()
	cm = SamplerChoiceModel(gn)

	test("paramranges") do
		ranges = paramranges(cm)
		@check typeof(ranges) <: Vector
		@check length(ranges) == 5
		@check all([typeof(range) <: (Real,Real) for range in ranges])
	end

	test("getparams") do
		params = getparams(cm)
		@check typeof(params) <: Vector
		@check length(params) == 5
		@check all([typeof(param) <: Real for param in params])
	end

	test("setparams") do
		newparams = [(paramrange[1]+paramrange[2])/2 for paramrange in paramranges(cm)]
		setparams(cm, newparams)
		@check length(getparams(cm)) == 5 # can't check equality of params since some adjustment can be made by the cm
	end

end

describe("sampler choice model - rule choice point") do

	gn = SCMRuleGen()
	cm = SamplerChoiceModel(gn)
	cpi = choicepointinfo(gn)
	cpids = collect(keys(cpi))
	
	# type ChoiceContext
	# 	derivationstate::DerivationState
	# 	cptype::Symbol
	# 	cpid::Uint64
	# 	datatype::DataType
	# 	lowerbound::Real
	# 	upperbound::Real
	# end
	cc = GodelTest.ChoiceContext(GodelTest.DefaultDerivationState(gn, cm, 10000), GodelTest.RULE_CP, cpids[1], Int, 1, 4)

	@repeat test("valid Godel numbers returned") do
		gnum = GodelTest.godelnumber(cm, cc)
		@check convert(Int,gnum) != nothing  # raises exception if value can't be converted
		@mcheck_values_are gnum [1,2,3,4]
	end
	
	test("sampler uses a Categorical distribution") do
		@check length(cm.samplers) == 1
		sampler = first(values(cm.samplers))
		@check typeof(sampler.dist) <: Distributions.Categorical
	end

	test("get and set sampler parameters") do
		sampler = first(values(cm.samplers))
		@check sampler.dist.p ==[0.25,0.25,0.25,0.25,]
		@check getparams(cm) == [0.25,0.25,0.25,0.25,]
		@check paramranges(cm) == [(0.0,1.0),(0.0,1.0),(0.0,1.0),(0.0,1.0),]
		setparams(cm,[3,3,1,1])
		@check sampler.dist.p == [0.375,0.375,0.125,0.125,]
		@check getparams(cm) == [0.375,0.375,0.125,0.125,]
	end
		
end

describe("sampler choice model - sequence choice point") do

	gn = SCMRepsGen()
	cm = SamplerChoiceModel(gn)
	cpi = choicepointinfo(gn)
	cpids = collect(keys(cpi))
	
	describe("small finite range") do 
	
		cc = GodelTest.ChoiceContext(GodelTest.DefaultDerivationState(gn, cm, 10000), GodelTest.SEQUENCE_CP, cpids[1], Int, 0, 2)
		
		@repeat test("valid Godel numbers returned") do
			gnum = GodelTest.godelnumber(cm, cc)
			@check convert(Int,gnum) != nothing  # raises exception if value can't be converted
			@check 0 <= gnum <= 2
			@mcheck_values_are gnum [0,1,2]
		end

	end

	describe("large finite range") do
	
		cc = GodelTest.ChoiceContext(GodelTest.DefaultDerivationState(gn, cm, 10000), GodelTest.SEQUENCE_CP, cpids[1], Int, 11, 16)
		
		@repeat test("valid Godel numbers returned") do
			gnum = GodelTest.godelnumber(cm, cc)
			@check convert(Int,gnum) != nothing  # raises exception if value can't be converted
			@check 11 <= gnum <= 16
			@mcheck_values_include gnum [11,13,16]
		end
		
	end

	describe("semi-finite range") do

		cc = GodelTest.ChoiceContext(GodelTest.DefaultDerivationState(gn, cm, 10000), GodelTest.SEQUENCE_CP, cpids[1], Int, 1, typemax(Int))

		@repeat test("valid Godel numbers returned") do
			gnum = GodelTest.godelnumber(cm, cc)
			@check convert(Int,gnum) != nothing  # raises exception if value can't be converted
			@check 1 <= gnum <= typemax(Int)
			@mcheck_values_vary gnum
		end
		
	end
	
	test("sampler uses a Geometric distribution") do
		@check length(cm.samplers) == 1
		sampler = first(values(cm.samplers))
		@check typeof(sampler.dist) <: Distributions.Geometric
	end

	test("get and set sampler parameters") do
		sampler = first(values(cm.samplers))
		@check sampler.dist.p == 0.5
		@check getparams(cm) == [0.5,]
		@check paramranges(cm) == [(0.0,1.0),]
		setparams(cm,[0.6])
		@check sampler.dist.p == 0.6
		@check getparams(cm) == [0.6,]
	end
	
end


describe("sampler choice model - Bool value choice point") do

	gn = SCMChooseBoolGen()
	cm = SamplerChoiceModel(gn)
	cpi = choicepointinfo(gn)
	cpids = collect(keys(cpi))

	cc = GodelTest.ChoiceContext(GodelTest.DefaultDerivationState(gn, cm, 10000), GodelTest.VALUE_CP, cpids[1], Bool, false, true)
	
	@repeat test("valid Godel numbers returned") do
		gnum = GodelTest.godelnumber(cm, cc)
		@check convert(Bool,gnum) != nothing  # raises exception if value can't be converted
		@mcheck_values_are gnum [false,true]
	end

	test("sampler uses a Bernoulli distribution") do
		@check length(cm.samplers) == 1
		sampler = first(values(cm.samplers))
		@check typeof(sampler.dist) <: Distributions.Bernoulli
	end

	test("get and set sampler parameters") do
		sampler = first(values(cm.samplers))
		@check sampler.dist.p == 0.5
		@check getparams(cm) == [0.5,]
		@check paramranges(cm) == [(0.0,1.0),]
		setparams(cm,[0.6])
		@check sampler.dist.p == 0.6
		@check getparams(cm) == [0.6,]
	end
	
end


describe("sampler choice model - Int value choice point") do

	gn = SCMChooseIntGen()
	cm = SamplerChoiceModel(gn)
	cpi = choicepointinfo(gn)
	cpids = collect(keys(cpi))
	
	describe("small finite range") do

		cc = GodelTest.ChoiceContext(GodelTest.DefaultDerivationState(gn, cm, 10000), GodelTest.VALUE_CP, cpids[1], Int, -1, 2)

		@repeat test("valid Godel numbers returned") do
			gnum = GodelTest.godelnumber(cm, cc)
			@check convert(Int,gnum) != nothing  # raises exception if value can't be converted
			@check -1 <= gnum <= 2
			@mcheck_values_are gnum [-1,0,1,2]
		end
		
	end

	describe("large finite range") do
	
		cc = GodelTest.ChoiceContext(GodelTest.DefaultDerivationState(gn, cm, 10000), GodelTest.VALUE_CP, cpids[1], Int, 11, 16)
		
		@repeat test("valid Godel numbers returned") do
			gnum = GodelTest.godelnumber(cm, cc)
			@check convert(Int,gnum) != nothing  # raises exception if value can't be converted
			@check 11 <= gnum <= 16
			@mcheck_values_include gnum [11,13,16] # just a selection of possible values including end points
		end
		
	end

	describe("semi-finite range (upper)") do
	
		cc = GodelTest.ChoiceContext(GodelTest.DefaultDerivationState(gn, cm, 10000), GodelTest.VALUE_CP, cpids[1], Int, 128, typemax(Int))
		
		@repeat test("valid Godel numbers returned") do
			gnum = GodelTest.godelnumber(cm, cc)
			@check convert(Int,gnum) != nothing  # raises exception if value can't be converted
			@check 128 <= gnum <= typemax(Int)
			@mcheck_values_vary gnum
		end
		
	end

	describe("semi-finite range (lower)") do
	
		cc = GodelTest.ChoiceContext(GodelTest.DefaultDerivationState(gn, cm, 10000), GodelTest.VALUE_CP, cpids[1], Int, typemin(Int), 128)
		
		@repeat test("valid Godel numbers returned") do
			gnum = GodelTest.godelnumber(cm, cc)
			@check convert(Int,gnum) != nothing  # raises exception if value can't be converted
			@check typemin(Int) <= gnum <= 128
			@mcheck_values_vary gnum
		end
		
	end

	describe("infinite range") do
	
		cc = GodelTest.ChoiceContext(GodelTest.DefaultDerivationState(gn, cm, 10000), GodelTest.VALUE_CP, cpids[1], Int, typemin(Int), typemax(Int))
		
		@repeat test("valid Godel numbers returned") do
			gnum = GodelTest.godelnumber(cm, cc)
			@check convert(Int,gnum) != nothing  # raises exception if value can't be converted
			@check typemin(Int) <= gnum <= typemax(Int)
			@mcheck_values_vary gnum
		end
		
	end
	
	describe("sampler") do
		
		test("sampler uses a DiscreteUniform distribution") do
			@check length(cm.samplers) == 1
			sampler = first(values(cm.samplers))
			@check typeof(sampler.dist) <: Distributions.DiscreteUniform
		end

		test("get and set sampler parameters") do
			sampler = first(values(cm.samplers))
			@check getparams(cm) == []
			@check paramranges(cm) == []
		end

	end
	
end


describe("sampler choice model - Float64 value choice point") do

	gn = SCMChooseFloat64Gen()
	cm = SamplerChoiceModel(gn)
	cpi = choicepointinfo(gn)
	cpids = collect(keys(cpi))
	
	describe("finite range") do

		cc = GodelTest.ChoiceContext(GodelTest.DefaultDerivationState(gn, cm, 10000), GodelTest.VALUE_CP, cpids[1], Float64, -42.2, -8.7)

		@repeat test("valid Godel numbers returned") do
			gnum = GodelTest.godelnumber(cm, cc)
			@check convert(Float64,gnum) != nothing  # raises exception if value can't be converted
			@check -42.2 <= gnum <= -8.7
			@mcheck_that_sometimes int(gnum) != gnum
			@mcheck_values_vary gnum
		end
		
	end

	describe("semi-finite range (upper)") do
	
		cc = GodelTest.ChoiceContext(GodelTest.DefaultDerivationState(gn, cm, 10000), GodelTest.VALUE_CP, cpids[1], Float64, 450001.6, Inf)
		
		@repeat test("valid Godel numbers returned") do
			gnum = GodelTest.godelnumber(cm, cc)
			@check convert(Float64,gnum) != nothing  # raises exception if value can't be converted
			@check 450001.6 <= gnum
			@mcheck_that_sometimes int(gnum) != gnum
			@mcheck_values_vary gnum
		end
		
	end

	describe("semi-finite range (lower)") do
	
		cc = GodelTest.ChoiceContext(GodelTest.DefaultDerivationState(gn, cm, 10000), GodelTest.VALUE_CP, cpids[1], Float64, -Inf, 450001.6)
		
		@repeat test("valid Godel numbers returned") do
			gnum = GodelTest.godelnumber(cm, cc)
			@check convert(Float64,gnum) != nothing  # raises exception if value can't be converted
			@check gnum <= 450001.6
			@mcheck_that_sometimes int(gnum) != gnum
			@mcheck_values_vary gnum
		end
		
	end

	describe("infinite range") do
	
		cc = GodelTest.ChoiceContext(GodelTest.DefaultDerivationState(gn, cm, 10000), GodelTest.VALUE_CP, cpids[1], Float64, -Inf, Inf)
		
		@repeat test("valid Godel numbers returned") do
			gnum = GodelTest.godelnumber(cm, cc)
			@check convert(Float64,gnum) != nothing  # raises exception if value can't be converted
			@mcheck_that_sometimes int(gnum) != gnum
			@mcheck_values_vary gnum
		end
		
	end
	
	describe("sampler") do
	
		test("sampler uses a Uniform distribution") do
			@check length(cm.samplers) == 1
			sampler = first(values(cm.samplers))
			@check typeof(sampler.dist) <: Distributions.Uniform
		end

		test("get and set sampler parameters") do
			sampler = first(values(cm.samplers))
			@check getparams(cm) == []
			@check paramranges(cm) == []
		end
		
	end
	
end

describe("sampler choice model - generate for model with multiple choice points") do

	gn = SCMChooseStringGen()
	cm = DefaultChoiceModel(gn)
	
	@repeat test("full range of values generated using choice model") do
		td = gen(gn, choicemodel=cm)
		@check ismatch(r"^a(b|c)d+ef?$", td)
		@mcheck_values_include count(x->x=='d', td) [1,2,3]
		@mcheck_values_are td[2] ['b','c']
		@mcheck_values_are td[end] ['e','f']
	end

end
